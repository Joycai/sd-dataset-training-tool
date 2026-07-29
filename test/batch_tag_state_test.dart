import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dataset_training_tool/models/merge_rules.dart';
import 'package:dataset_training_tool/services/ai_tagger_service.dart';
import 'package:dataset_training_tool/services/settings_service.dart';
import 'package:dataset_training_tool/state/ai_tagger_state.dart';
import 'package:dataset_training_tool/state/batch_tag_state.dart';
import 'package:dataset_training_tool/state/dataset_state.dart';
import 'package:dataset_training_tool/state/tag_ops.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('mergeBatchTags · overwrite', () {
    const config = BatchTagConfig(mode: BatchTagMode.overwrite);

    test('predictions replace existing tags', () {
      expect(
        mergeBatchTags(
          current: ['old one', 'old two'],
          predicted: ['1girl', 'smile'],
          config: config,
        ),
        ['1girl', 'smile'],
      );
    });

    test('preserved tags survive case-insensitively, in original order', () {
      expect(
        mergeBatchTags(
          current: ['Narumi Nagisa', 'old', 'masterpiece'],
          predicted: ['1girl'],
          config: const BatchTagConfig(
            mode: BatchTagMode.overwrite,
            preservedTags: ['narumi nagisa', 'masterpiece'],
          ),
        ),
        ['Narumi Nagisa', 'masterpiece', '1girl'],
      );
    });

    test('keepFirstN keeps the leading tags', () {
      expect(
        mergeBatchTags(
          current: ['trigger word', 'style tag', 'old'],
          predicted: ['1girl'],
          config: const BatchTagConfig(
            mode: BatchTagMode.overwrite,
            keepFirstN: 2,
          ),
        ),
        ['trigger word', 'style tag', '1girl'],
      );
    });

    test('kept tags de-duplicate predictions case-insensitively', () {
      expect(
        mergeBatchTags(
          current: ['1Girl', 'old'],
          predicted: ['1girl', 'smile'],
          config: const BatchTagConfig(
            mode: BatchTagMode.overwrite,
            preservedTags: ['1girl'],
          ),
        ),
        ['1Girl', 'smile'],
      );
    });

    test('no semantic change returns null', () {
      expect(
        mergeBatchTags(
          current: ['1girl', 'smile'],
          predicted: ['1girl', 'smile'],
          config: config,
        ),
        isNull,
      );
    });
  });

  group('mergeBatchTags · append', () {
    const config = BatchTagConfig(mode: BatchTagMode.append);

    test('appends only new predictions, existing order untouched', () {
      expect(
        mergeBatchTags(
          current: ['solo', 'red hair'],
          predicted: ['1girl', 'Red Hair', 'smile'],
          config: config,
        ),
        ['solo', 'red hair', '1girl', 'smile'],
      );
    });

    test('blacklist drops predictions case-insensitively', () {
      expect(
        mergeBatchTags(
          current: ['solo'],
          predicted: ['1girl', 'realistic', 'smile'],
          config: const BatchTagConfig(
            mode: BatchTagMode.append,
            blacklist: ['Realistic', 'smile'],
          ),
        ),
        ['solo', '1girl'],
      );
    });

    test('nothing new returns null', () {
      expect(
        mergeBatchTags(
          current: ['1girl'],
          predicted: ['1girl'],
          config: config,
        ),
        isNull,
      );
      expect(
        mergeBatchTags(
          current: ['1girl'],
          predicted: ['realistic'],
          config: const BatchTagConfig(
            mode: BatchTagMode.append,
            blacklist: ['realistic'],
          ),
        ),
        isNull,
      );
    });
  });

  group('BatchTagState.run', () {
    late Directory tempDir;
    late DatasetState dataset;
    late AiTaggerState ai;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      tempDir = await Directory.systemTemp.createTemp('batch_tag_test');
      dataset = DatasetState();
      ai = AiTaggerState(SettingsService());
      await ai.setModelName('m');
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    Future<File> addImage(String name, {String? caption}) async {
      final image = File('${tempDir.path}/$name.png');
      await image.writeAsBytes([1, 2, 3]);
      if (caption != null) {
        await File('${tempDir.path}/$name.txt').writeAsString(caption);
      }
      return image;
    }

    Future<void> scan() => dataset.scan(
      directoryPath: tempDir.path,
      recursive: false,
      captionExtension: '.txt',
    );

    /// Server answering per image file name; a null entry answers a failure.
    BatchTagState buildState(
      Map<String, List<Map<String, dynamic>>?> tagsByFileName, {
      void Function(TagOperation op)? onOperation,
      void Function(Set<String> paths)? onCaptionsChanged,
    }) {
      final client = MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final tags = tagsByFileName[body['FileName']];
        final response = tags == null
            ? {'Success': false, 'ErrorMessage': 'boom', 'Result': <dynamic>[]}
            : {
                'Success': true,
                'ErrorMessage': '',
                'Result': [
                  {'ModelName': 'm', 'Tags': tags},
                ],
              };
        return http.Response(
          jsonEncode(response),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      return BatchTagState(
        dataset: dataset,
        ai: ai,
        settings: SettingsService(),
        service: AiTaggerService(client: client),
        onOperation: onOperation,
        onCaptionsChanged: onCaptionsChanged,
      );
    }

    test(
      'append run rewrites captions, updates the index, reports one op',
      () async {
        final img1 = await addImage('a', caption: 'solo, red hair');
        final img2 = await addImage('b');
        await scan();

        final ops = <TagOperation>[];
        final touched = <String>{};
        final state = buildState(
          {
            'a.png': [
              {'Tag': 'red_hair', 'Probability': 0.9},
              {'Tag': 'smile', 'Probability': 0.8},
            ],
            'b.png': [
              {'Tag': '1girl', 'Probability': 0.95},
            ],
          },
          onOperation: ops.add,
          onCaptionsChanged: touched.addAll,
        );

        final ok = await state.run(
          files: [img1, img2],
          operationLabel: 'batch',
        );
        expect(ok, isTrue);
        expect(state.completed, 2);
        expect(state.changed, 2);
        expect(state.failed, 0);

        // red_hair normalizes to the already-present "red hair".
        expect(
          await File('${tempDir.path}/a.txt').readAsString(),
          'solo, red hair, smile',
        );
        // The missing caption file is created.
        expect(await File('${tempDir.path}/b.txt').readAsString(), '1girl');
        // In-memory index follows without a rescan.
        expect(dataset.tagsOf(img1.path), ['solo', 'red hair', 'smile']);
        expect(dataset.tagsOf(img2.path), ['1girl']);

        expect(ops, hasLength(1));
        expect(ops.single.label, 'batch');
        expect(ops.single.edits, hasLength(2));
        expect(touched, {img1.path, img2.path});
        state.dispose();
      },
    );

    test('overwrite run honors preserved tags and the ignore list', () async {
      final img = await addImage('a', caption: 'narumi nagisa, old tag');
      await scan();
      await ai.setIgnoreTagsFromInput('realistic');
      final state = buildState({
        'a.png': [
          {'Tag': '1girl', 'Probability': 0.95},
          {'Tag': 'realistic', 'Probability': 0.9},
          {'Tag': 'smile', 'Probability': 0.8},
        ],
      });
      await state.setMode(BatchTagMode.overwrite);
      await state.setPreservedTagsFromInput('narumi nagisa');

      await state.run(files: [img], operationLabel: 'batch');
      expect(state.changed, 1);
      // Preserved tag first, "old tag" dropped, ignored prediction dropped,
      // remaining predictions in probability order.
      expect(
        await File('${tempDir.path}/a.txt').readAsString(),
        'narumi nagisa, 1girl, smile',
      );
      state.dispose();
    });

    test('a failed image is counted and skipped, the rest proceeds', () async {
      final img1 = await addImage('a', caption: 'solo');
      final img2 = await addImage('b');
      await scan();

      final ops = <TagOperation>[];
      final state = buildState({
        'a.png': null, // server failure
        'b.png': [
          {'Tag': '1girl', 'Probability': 0.95},
        ],
      }, onOperation: ops.add);

      await state.run(files: [img1, img2], operationLabel: 'batch');
      expect(state.completed, 2);
      expect(state.changed, 1);
      expect(state.failed, 1);
      expect(state.lastError, 'boom');
      // The failed image's caption is untouched.
      expect(await File('${tempDir.path}/a.txt').readAsString(), 'solo');
      expect(ops.single.edits, hasLength(1));
      state.dispose();
    });

    test('unchanged captions do not enter the operation', () async {
      final img = await addImage('a', caption: '1girl');
      await scan();

      final ops = <TagOperation>[];
      final state = buildState({
        'a.png': [
          {'Tag': '1girl', 'Probability': 0.95},
        ],
      }, onOperation: ops.add);

      await state.run(files: [img], operationLabel: 'batch');
      expect(state.changed, 0);
      expect(ops, isEmpty);
      state.dispose();
    });

    test('recognize-only run caches results and enters compare mode '
        'without touching captions', () async {
      final img1 = await addImage('a', caption: 'solo');
      final img2 = await addImage('b');
      await scan();

      final ops = <TagOperation>[];
      final state = buildState({
        'a.png': [
          {'Tag': '1girl', 'Probability': 0.95},
          {'Tag': 'smile', 'Probability': 0.8},
        ],
        'b.png': null, // server failure
      }, onOperation: ops.add);
      await state.setMode(BatchTagMode.recognizeOnly);

      await state.run(files: [img1, img2], operationLabel: 'batch');
      expect(state.completed, 2);
      expect(state.changed, 1); // recognized count
      expect(state.failed, 1);

      // Captions untouched, no undo operation.
      expect(await File('${tempDir.path}/a.txt').readAsString(), 'solo');
      expect(File('${tempDir.path}/b.txt').existsSync(), isFalse);
      expect(ops, isEmpty);

      // Results feed the single-image cache; compare mode is on.
      expect(ai.compareMode, isTrue);
      expect(ai.hasResultFor(img1.path), isTrue);
      expect(ai.hasResultFor(img2.path), isFalse);
      expect(ai.resultFor(img1.path)!.map((p) => p.tag), ['1girl', 'smile']);
      state.dispose();
    });

    test('run without a model or with an active run returns false', () async {
      final img = await addImage('a');
      await scan();
      final state = buildState({});
      await ai.setModelName(null);
      expect(await state.run(files: [img], operationLabel: 'batch'), isFalse);
      state.dispose();
    });

    group('character sheet', () {
      const rules = CharacterMergeRules(
        id: 'r1',
        character: 'Aoi',
        triggerWord: 'aoichr',
        identityTags: ['blonde hair', 'twintails'],
        conflictTags: ['brown hair'],
        garments: [
          GarmentRule(tag: 'dress', evidence: ['dress', 'skirt']),
          GarmentRule(tag: 'gloves', evidence: ['gloves']),
        ],
      );

      /// Every threshold the run asked the server for, in call order.
      late List<double?> requested;

      BatchTagState buildSheetState(
        Map<String, List<Map<String, dynamic>>?> tagsByFileName, {
        void Function(TagOperation op)? onOperation,
        CharacterMergeRules? available = rules,
      }) {
        requested = [];
        final client = MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final models = (body['Models'] as List?) ?? const [];
          for (final m in models.whereType<Map<String, dynamic>>()) {
            final params =
                (m['AdditionalParameters'] as List?) ?? const <dynamic>[];
            requested.add(
              params
                  .whereType<Map<String, dynamic>>()
                  .where((p) => p['Key'] == 'threshold')
                  .map((p) => double.tryParse('${p['Value']}'))
                  .firstOrNull,
            );
          }
          final tags = tagsByFileName[body['FileName']];
          final response = tags == null
              ? {
                  'Success': false,
                  'ErrorMessage': 'boom',
                  'Result': <dynamic>[],
                }
              : {
                  'Success': true,
                  'ErrorMessage': '',
                  'Result': [
                    {'ModelName': 'm', 'Tags': tags},
                  ],
                };
          return http.Response(
            jsonEncode(response),
            200,
            headers: {'content-type': 'application/json'},
          );
        });
        final state = BatchTagState(
          dataset: dataset,
          ai: ai,
          settings: SettingsService(),
          service: AiTaggerService(client: client),
          onOperation: onOperation,
        );
        state.resolveRules = (id) =>
            available != null && available.id == id ? available : null;
        return state;
      }

      test('rebuilds the caption from the rules, replacing what was '
          'there', () async {
        final img = await addImage('a', caption: 'old, stale, brown hair');
        await scan();
        await ai.setThreshold(0.35);
        final state = buildSheetState({
          'a.png': [
            {'Tag': 'skirt', 'Probability': 0.9},
            {'Tag': 'brown_hair', 'Probability': 0.85},
            {'Tag': 'smile', 'Probability': 0.8},
            {'Tag': 'outdoors', 'Probability': 0.7},
          ],
        });
        await state.setMode(BatchTagMode.characterSheet);
        await state.setRulesId('r1');

        expect(await state.run(files: [img], operationLabel: 'batch'), isTrue);
        expect(state.changed, 1);
        expect(
          await File('${tempDir.path}/a.txt').readAsString(),
          // trigger, traits, the skirt promoted to dress, then the tagger's
          // own words. The gloves never appeared, so they are not written.
          'aoichr, blonde hair, twintails, dress, smile, outdoors',
        );
        state.dispose();
      });

      test('asks the server below the threshold so faint outfit evidence '
          'survives', () async {
        final img = await addImage('a');
        await scan();
        await ai.setThreshold(0.35);
        final state = buildSheetState({
          'a.png': [
            {'Tag': 'gloves', 'Probability': 0.24},
            {'Tag': 'castle', 'Probability': 0.24},
            {'Tag': 'smile', 'Probability': 0.9},
          ],
        });
        await state.setMode(BatchTagMode.characterSheet);
        await state.setRulesId('r1');
        await state.setEvidenceThreshold(0.2);

        await state.run(files: [img], operationLabel: 'batch');
        // The request had to go below the tagger's own threshold, or the
        // faint gloves would never have reached us at all.
        expect(requested, [0.2]);
        // ...and the low-confidence non-garment tag is still dropped.
        expect(
          await File('${tempDir.path}/a.txt').readAsString(),
          'aoichr, blonde hair, twintails, gloves, smile',
        );
        state.dispose();
      });

      test('the whole run is one undoable operation', () async {
        final img1 = await addImage('a');
        final img2 = await addImage('b');
        await scan();
        await ai.setThreshold(0.35);
        final ops = <TagOperation>[];
        final state = buildSheetState({
          'a.png': [
            {'Tag': 'smile', 'Probability': 0.9},
          ],
          'b.png': [
            {'Tag': 'skirt', 'Probability': 0.9},
          ],
        }, onOperation: ops.add);
        await state.setMode(BatchTagMode.characterSheet);
        await state.setRulesId('r1');

        await state.run(files: [img1, img2], operationLabel: 'sheet run');
        expect(ops, hasLength(1));
        expect(ops.single.edits, hasLength(2));
        state.dispose();
      });

      test('a run with no rule set chosen is refused', () async {
        final img = await addImage('a', caption: 'keep me');
        await scan();
        final state = buildSheetState({
          'a.png': [
            {'Tag': 'smile', 'Probability': 0.9},
          ],
        });
        await state.setMode(BatchTagMode.characterSheet);

        expect(await state.run(files: [img], operationLabel: 'batch'), isFalse);
        // Nothing was interrogated and nothing was written — the guard has to
        // fire before the loop, or every caption becomes the empty string.
        expect(requested, isEmpty);
        expect(await File('${tempDir.path}/a.txt').readAsString(), 'keep me');
        state.dispose();
      });

      test('a rule set deleted since the last run stops resolving', () async {
        final img = await addImage('a', caption: 'keep me');
        await scan();
        final state = buildSheetState({
          'a.png': [
            {'Tag': 'smile', 'Probability': 0.9},
          ],
        }, available: null);
        await state.setMode(BatchTagMode.characterSheet);
        await state.setRulesId('r1');

        expect(state.selectedRules, isNull);
        expect(await state.run(files: [img], operationLabel: 'batch'), isFalse);
        expect(await File('${tempDir.path}/a.txt').readAsString(), 'keep me');
        state.dispose();
      });

      test('with no user threshold it falls back rather than refusing to '
          'run', () async {
        final img = await addImage('a');
        await scan();
        await ai.setThreshold(null);
        final state = buildSheetState({
          'a.png': [
            {'Tag': 'smile', 'Probability': 0.9},
          ],
        });
        await state.setMode(BatchTagMode.characterSheet);
        await state.setRulesId('r1');
        await state.setEvidenceThreshold(0.2);

        await state.run(files: [img], operationLabel: 'batch');
        // The params probe fails against this mock, so the run uses the
        // documented WD default and still asks below it.
        expect(requested.last, 0.2);
        expect(state.changed, 1);
        state.dispose();
      });
    });
  });
}
