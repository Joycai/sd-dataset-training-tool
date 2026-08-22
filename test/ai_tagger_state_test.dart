import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dataset_training_tool/services/ai_tagger_service.dart';
import 'package:dataset_training_tool/services/settings_service.dart';
import 'package:dataset_training_tool/state/ai_tagger_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AiTagDiff.compute', () {
    const predictions = [
      AiPrediction(tag: '1girl', probability: 0.99),
      AiPrediction(tag: 'long hair', probability: 0.9),
      AiPrediction(tag: 'smile', probability: 0.8),
    ];

    test('splits into new / missing / matched', () {
      final diff = AiTagDiff.compute(['narumi nagisa', 'smile'], predictions);
      expect(diff.newSuggestions.map((p) => p.tag), ['1girl', 'long hair']);
      expect(diff.missing, {'narumi nagisa'});
      expect(diff.matched, {'smile'});
    });

    test('empty current tags: everything is new', () {
      final diff = AiTagDiff.compute([], predictions);
      expect(diff.newSuggestions, hasLength(3));
      expect(diff.missing, isEmpty);
      expect(diff.matched, isEmpty);
    });

    test('empty predictions: everything is missing', () {
      final diff = AiTagDiff.compute(['solo'], const []);
      expect(diff.newSuggestions, isEmpty);
      expect(diff.missing, {'solo'});
    });
  });

  group('AiTaggerState.interrogate', () {
    late Directory tempDir;
    late File image;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      tempDir = await Directory.systemTemp.createTemp('ai_tagger_test');
      image = File('${tempDir.path}/img.png');
      await image.writeAsBytes([1, 2, 3]);
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    AiTaggerState buildState(Map<String, dynamic> interrogateResponse) {
      final client = MockClient((request) async {
        if (request.url.path == '/interrogateimage') {
          return http.Response(
            jsonEncode(interrogateResponse),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('not found', 404);
      });
      return AiTaggerState(
        SettingsService(),
        service: AiTaggerService(client: client),
      );
    }

    Map<String, dynamic> response(List<Map<String, dynamic>> tags) => {
      'Success': true,
      'ErrorMessage': '',
      'Result': [
        {'ModelName': 'm', 'Tags': tags},
      ],
    };

    test('normalizes, de-duplicates and sorts predictions', () async {
      final state = buildState(
        response([
          {'Tag': 'long_hair', 'Probability': 0.7},
          {'Tag': 'smile', 'Probability': 0.95},
          {'Tag': 'long hair', 'Probability': 0.9},
        ]),
      );
      await state.setModelName('m');

      final ok = await state.interrogate(image);
      expect(ok, isTrue);
      expect(state.compareMode, isTrue);

      final result = state.resultFor(image.path)!;
      // long_hair normalizes to "long hair"; the higher probability wins.
      expect(result.map((p) => p.tag), ['smile', 'long hair']);
      expect(result[1].probability, 0.9);
    });

    test('resultFor applies the ignore list case-insensitively', () async {
      final state = buildState(
        response([
          {'Tag': 'smile', 'Probability': 0.9},
          {'Tag': 'realistic', 'Probability': 0.8},
        ]),
      );
      await state.setModelName('m');
      await state.interrogate(image);

      await state.setIgnoreTagsFromInput('Realistic');
      expect(state.resultFor(image.path)!.map((p) => p.tag), ['smile']);

      // Clearing the ignore list restores the cached result without a re-run.
      await state.setIgnoreTagsFromInput('');
      expect(state.resultFor(image.path), hasLength(2));
    });

    test('failure stores the error and keeps compare mode off', () async {
      final state = buildState({
        'Success': false,
        'ErrorMessage': 'boom',
        'Result': <dynamic>[],
      });
      await state.setModelName('m');

      final ok = await state.interrogate(image);
      expect(ok, isFalse);
      expect(state.lastError, 'boom');
      expect(state.compareMode, isFalse);
      expect(state.hasResultFor(image.path), isFalse);
    });

    test('interrogate without a model is a no-op', () async {
      final state = buildState(response([]));
      expect(await state.interrogate(image), isFalse);
    });
  });

  group('AiTaggerState.describe', () {
    late Directory tempDir;
    late File image;
    late List<Map<String, dynamic>> sentRequests;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      tempDir = await Directory.systemTemp.createTemp('ai_describe_test');
      image = File('${tempDir.path}/img.png');
      await image.writeAsBytes([1, 2, 3]);
      sentRequests = [];
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    AiTaggerState buildState(Map<String, dynamic> interrogateResponse) {
      final client = MockClient((request) async {
        if (request.url.path == '/interrogateimage') {
          sentRequests.add(
            jsonDecode(request.body) as Map<String, dynamic>,
          );
          return http.Response(
            jsonEncode(interrogateResponse),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('not found', 404);
      });
      return AiTaggerState(
        SettingsService(),
        service: AiTaggerService(client: client),
      );
    }

    Map<String, dynamic> response(List<String> texts) => {
      'Success': true,
      'ErrorMessage': '',
      'Result': [
        {
          'ModelName': 'joycaption',
          'Tags': [
            for (final t in texts) {'Tag': t, 'Probability': 1.0},
          ],
        },
      ],
    };

    test('returns the description verbatim, with no tag normalization', () async {
      final state = buildState(
        response([r'A girl with long_hair smiles (softly), outdoors.']),
      );
      await state.setModelName('joycaption');
      await state.setUnderscoreToSpaces(true);
      await state.setEscapeParentheses(true);

      // The tag path would have rewritten the underscore and escaped the
      // parentheses; this is prose, so both stay as the model wrote them.
      expect(
        await state.describe(image),
        r'A girl with long_hair smiles (softly), outdoors.',
      );
    });

    test('sends no threshold and leaves the compare cache alone', () async {
      final state = buildState(response(['A girl smiles.']));
      await state.setModelName('joycaption');
      await state.setThreshold(0.42);

      await state.describe(image);

      final models = sentRequests.single['Models'] as List;
      expect((models.single as Map)['AdditionalParameters'], isEmpty);
      // The compare view diffs tag sets; a paragraph has no business in it.
      expect(state.hasResultFor(image.path), isFalse);
      expect(state.compareMode, isFalse);
    });

    test('failure returns null and stores the error', () async {
      final state = buildState({
        'Success': false,
        'ErrorMessage': 'boom',
        'Result': <dynamic>[],
      });
      await state.setModelName('joycaption');

      expect(await state.describe(image), isNull);
      expect(state.lastError, 'boom');
    });

    test('a model that answers with nothing yields an empty string', () async {
      final state = buildState(response(['   ']));
      await state.setModelName('joycaption');

      expect(await state.describe(image), isEmpty);
      expect(state.lastError, isNull);
    });

    test('describe without a model is a no-op', () async {
      final state = buildState(response(['ignored']));
      expect(await state.describe(image), isNull);
      expect(sentRequests, isEmpty);
    });
  });

  group('AiTaggerState.setIgnoreTagsFromInput', () {
    test('parses, trims and de-duplicates', () async {
      SharedPreferences.setMockInitialValues({});
      final state = AiTaggerState(SettingsService());
      await state.setIgnoreTagsFromInput(
        ' virtual youtuber ,, realistic, Realistic ',
      );
      expect(state.ignoreTags, ['virtual youtuber', 'realistic']);
      state.dispose();
    });
  });

  group('AiTaggerState.modelMismatches', () {
    /// A server that names a category for every model except `mystery`, which
    /// stands in for an older AiApiServer that predates the field.
    Future<AiTaggerState> stateWith(String modelName) async {
      SharedPreferences.setMockInitialValues({});
      final client = MockClient((request) async {
        if (request.url.path == '/getconfig') {
          return http.Response(
            jsonEncode({
              'Interrogators': [
                {'ModelName': 'wd-tagger', 'Category': 'tag'},
                {'ModelName': 'joycaption', 'Category': 'caption'},
                {'ModelName': 'mystery', 'Category': ''},
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('not found', 404);
      });
      final state = AiTaggerState(
        SettingsService(),
        service: AiTaggerService(client: client),
      );
      await state.refreshModels();
      await state.setModelName(modelName);
      return state;
    }

    test('a tagger mismatches a caption run and fits a tag run', () async {
      final state = await stateWith('wd-tagger');
      expect(state.modelMismatches(wantCaption: true), isTrue);
      expect(state.modelMismatches(wantCaption: false), isFalse);
      state.dispose();
    });

    test('a caption model fits only a caption run', () async {
      final state = await stateWith('joycaption');
      expect(state.modelMismatches(wantCaption: false), isTrue);
      expect(state.modelMismatches(wantCaption: true), isFalse);
      state.dispose();
    });

    test('an empty category is not a claim in either direction', () async {
      final state = await stateWith('mystery');
      expect(state.modelMismatches(wantCaption: true), isFalse);
      expect(state.modelMismatches(wantCaption: false), isFalse);
      state.dispose();
    });

    test('a model list that was never fetched never mismatches', () async {
      SharedPreferences.setMockInitialValues({});
      final state = AiTaggerState(SettingsService());
      await state.setModelName('wd-tagger');
      expect(state.selectedModel, isNull);
      expect(state.modelMismatches(wantCaption: true), isFalse);
      expect(state.modelMismatches(wantCaption: false), isFalse);
      state.dispose();
    });
  });

  group('AiTaggerState.setShowNewOnly', () {
    test('persists and is restored by loadSettings', () async {
      SharedPreferences.setMockInitialValues({});
      final state = AiTaggerState(SettingsService());
      expect(state.showNewOnly, isFalse);
      await state.setShowNewOnly(true);
      expect(state.showNewOnly, isTrue);
      state.dispose();

      // A fresh state (new app session) reads the persisted value back.
      final reloaded = AiTaggerState(SettingsService());
      await reloaded.loadSettings();
      expect(reloaded.showNewOnly, isTrue);
      reloaded.dispose();
    });
  });
}
