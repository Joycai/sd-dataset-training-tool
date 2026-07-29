import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dataset_training_tool/app_state.dart';
import 'package:dataset_training_tool/models/caption_type.dart';
import 'package:dataset_training_tool/services/settings_service.dart';

void main() {
  group('normalizeCaptionExtension', () {
    test('adds the dot, trims and lowercases', () {
      expect(normalizeCaptionExtension('ntxt'), '.ntxt');
      expect(normalizeCaptionExtension(' .NTXT '), '.ntxt');
      expect(normalizeCaptionExtension('..caption'), '.caption');
    });

    test('rejects empty, separators, inner dots and image extensions', () {
      expect(normalizeCaptionExtension(''), isNull);
      expect(normalizeCaptionExtension('.'), isNull);
      expect(normalizeCaptionExtension('a/b'), isNull);
      expect(normalizeCaptionExtension('a b'), isNull);
      expect(normalizeCaptionExtension('tag.txt'), isNull);
      expect(normalizeCaptionExtension('.png'), isNull);
      expect(normalizeCaptionExtension('JPG'), isNull);
    });
  });

  group('sanitizeCaptionTypes', () {
    test('recreates a missing default and keeps it first and enabled', () {
      final out = sanitizeCaptionTypes([
        const CaptionType(id: 'a', name: 'NLP', extension: '.ntxt'),
      ]);
      expect(out.first.id, CaptionType.defaultId);
      expect(out.first.extension, '.txt');
      expect(out.first.enabled, isTrue);
      expect(out.map((t) => t.extension), ['.txt', '.ntxt']);
    });

    test('forces the default enabled and drops duplicate extensions', () {
      final out = sanitizeCaptionTypes([
        const CaptionType(
          id: CaptionType.defaultId,
          extension: '.txt',
          enabled: false,
        ),
        const CaptionType(id: 'a', extension: 'TXT'),
        const CaptionType(id: 'b', extension: 'ntxt'),
        const CaptionType(id: 'c', extension: '.png'),
      ]);
      expect(out.map((t) => t.id), [CaptionType.defaultId, 'b']);
      expect(out.first.enabled, isTrue);
      expect(out[1].extension, '.ntxt');
    });
  });

  test('decode tolerates garbage', () {
    expect(decodeCaptionTypes('not json'), isEmpty);
    expect(decodeCaptionTypes('{"a":1}'), isEmpty);
    final roundTrip = decodeCaptionTypes(
      encodeCaptionTypes([
        const CaptionType(id: 'x', name: 'NLP', extension: '.ntxt'),
      ]),
    );
    expect(roundTrip.single.name, 'NLP');
    expect(roundTrip.single.extension, '.ntxt');
  });

  group('AppState caption types', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    Future<AppState> load() async {
      final state = AppState(SettingsService());
      await state.loadSettings();
      return state;
    }

    test(
      'migrates the legacy single extension into the default type',
      () async {
        SharedPreferences.setMockInitialValues({
          'captionExtension': '.caption',
        });
        final state = await load();
        expect(state.captionTypes.single.extension, '.caption');
        expect(state.captionExtension, '.caption');
      },
    );

    test('active type falls back to default when disabled', () async {
      final state = await load();
      await state.updateCaptionTypes([
        ...state.captionTypes,
        const CaptionType(id: 'nlp', name: 'NLP', extension: '.ntxt'),
      ]);
      await state.setActiveCaptionType('nlp');
      expect(state.captionExtension, '.ntxt');

      final types = state.captionTypes;
      await state.updateCaptionTypes([
        types.first,
        types[1].copyWith(enabled: false),
      ]);
      expect(state.captionExtension, types.first.extension);
      expect(state.enabledCaptionTypes.length, 1);
    });

    test('persists types and the active selection', () async {
      final state = await load();
      await state.updateCaptionTypes([
        ...state.captionTypes,
        const CaptionType(id: 'nlp', name: 'NLP', extension: '.ntxt'),
      ]);
      await state.setActiveCaptionType('nlp');

      final reloaded = await load();
      expect(reloaded.captionTypes.length, 2);
      expect(reloaded.activeCaptionType.id, 'nlp');
      expect(reloaded.captionExtension, '.ntxt');
    });

    test('setActiveCaptionType ignores unknown or disabled ids', () async {
      final state = await load();
      await state.setActiveCaptionType('nope');
      expect(state.activeCaptionType.id, CaptionType.defaultId);
    });
  });
}
