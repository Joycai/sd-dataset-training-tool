import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dataset_training_tool/app_state.dart';
import 'package:dataset_training_tool/models/data_bundle.dart';
import 'package:dataset_training_tool/models/llm_models.dart';
import 'package:dataset_training_tool/models/tag_dictionary.dart';
import 'package:dataset_training_tool/models/tag_translation.dart';
import 'package:dataset_training_tool/services/data_transfer.dart';
import 'package:dataset_training_tool/services/settings_service.dart';
import 'package:dataset_training_tool/services/tag_dictionary_service.dart';
import 'package:dataset_training_tool/services/tag_translation_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    temp = await Directory.systemTemp.createTemp('data_transfer_test');
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  /// A state whose two tag services write into this test's temp directory
  /// rather than the real application support folder.
  ///
  /// Every call also resets the preference store, so the "source" and
  /// "target" of an import are genuinely separate installs rather than two
  /// views of one — the singleton would otherwise hand the target everything
  /// the source just saved and every import would look like a no-op.
  Future<AppState> freshState({String locale = 'zh'}) async {
    SharedPreferences.setMockInitialValues({});
    final dictionaryDir = Directory('${temp.path}/${_nextScope()}')
      ..createSync(recursive: true);
    final translationsDir = Directory('${dictionaryDir.path}/translations')
      ..createSync(recursive: true);
    final state = AppState(
      SettingsService(),
      tagDictionary: TagDictionaryService(
        storageDirectory: () async => dictionaryDir,
      ),
      tagTranslations: TagTranslationService(
        storageDirectory: () async => translationsDir,
      ),
    );
    await state.loadSettings();
    await state.tagTranslations.load(locale);
    return state;
  }

  const provider = LlmProvider(
    id: 'p1',
    name: 'OpenAI',
    baseUrl: 'https://api.openai.com/v1',
    apiKey: 'sk-secret',
    models: [
      LlmModelConfig(id: 'm1', modelId: 'gpt-5', contextWindow: 200000),
    ],
  );

  /// Fills [state] with one of everything the bundle carries.
  Future<void> seed(AppState state) async {
    await state.updateLlmProviders([provider]);
    await state.addCommonTags(['long_hair', 'blue_eyes', 'trigger_word']);
    final group = await state.createTagGroup('Hair', 0xFF6A9BDD);
    await state.moveTagsToGroup(['long_hair'], group.id);
    await state.tagDictionary.setCustomEntries([
      const TagDictionaryEntry(
        name: 'trigger_word',
        category: TagCategory.character,
      ),
    ]);
    await state.tagTranslations.upsert(
      const TagTranslation(tag: 'long_hair', text: '长发'),
    );
    await state.tagTranslations.upsertAllFor('ja', [
      const TagTranslation(tag: 'blue_eyes', text: '青い目'),
    ]);
    await state.createPromptPreset(title: 'cleanup', content: 'tidy the tags');
  }

  group('DataBundle file format', () {
    test('round trips every section', () async {
      final state = await freshState();
      await seed(state);
      final bundle = await DataTransfer(state).collect(
        sections: {...DataSection.values},
      );

      final decoded = DataBundle.decode(bundle.encode());
      expect(decoded.sections, {...DataSection.values});
      expect(decoded.providerCount, 1);
      expect(decoded.modelCount, 1);
      expect(decoded.providers!.single.apiKey, 'sk-secret');
      expect(decoded.providers!.single.models.single.contextWindow, 200000);
      expect(decoded.tagLibrary!.tagCount, 3);
      expect(decoded.tagLibrary!.groups.single.name, 'Hair');
      expect(decoded.tagLibrary!.groups.single.tags, ['long_hair']);
      expect(decoded.tagLibrary!.ungrouped, ['blue_eyes', 'trigger_word']);
      expect(decoded.tagLibrary!.customTags.single.name, 'trigger_word');
      // Every language on disk, not just the one the app is showing.
      expect(decoded.tagLibrary!.translations.keys, containsAll(['zh', 'ja']));
      expect(decoded.tagLibrary!.translationCount, 2);
      expect(decoded.presets!.single.title, 'cleanup');
    });

    test('a section left out of the export is absent, not empty', () async {
      final state = await freshState();
      await seed(state);
      final bundle = await DataTransfer(
        state,
      ).collect(sections: {DataSection.promptPresets});

      final decoded = DataBundle.decode(bundle.encode());
      expect(decoded.sections, {DataSection.promptPresets});
      expect(decoded.has(DataSection.llm), isFalse);
      expect(decoded.providers, isNull);
      expect(decoded.tagLibrary, isNull);
    });

    test('api keys can be stripped, the rest of the backend survives',
        () async {
      final state = await freshState();
      await seed(state);
      final bundle = await DataTransfer(state).collect(
        sections: {DataSection.llm},
        includeApiKeys: false,
      );

      final decoded = DataBundle.decode(bundle.encode());
      expect(decoded.hasApiKeys, isFalse);
      expect(decoded.providers!.single.apiKey, isEmpty);
      expect(decoded.providers!.single.baseUrl, 'https://api.openai.com/v1');
      expect(decoded.providers!.single.models.single.modelId, 'gpt-5');
    });

    test('rejects files that are not this app\'s export', () {
      expect(() => DataBundle.decode('not json'), throwsFormatException);
      expect(() => DataBundle.decode('[]'), throwsFormatException);
      expect(() => DataBundle.decode('{"a":1}'), throwsFormatException);
      // A tag-library export is JSON, and importing it as a settings bundle
      // would silently restore nothing.
      expect(
        () => DataBundle.decode('{"version":1,"groups":[]}'),
        throwsFormatException,
      );
    });

    test('refuses a schema newer than this build', () {
      expect(
        () => DataBundle.decode(
          '{"app":"dataset_training_tool","schema":99,"llm":{"providers":[]}}',
        ),
        throwsFormatException,
      );
    });
  });

  group('import into an empty app', () {
    test('restores all three sections', () async {
      final source = await freshState();
      await seed(source);
      final bundle = DataBundle.decode(
        (await DataTransfer(source).collect(sections: {...DataSection.values}))
            .encode(),
      );

      final target = await freshState();
      final report = await DataTransfer(
        target,
      ).apply(bundle, sections: {...DataSection.values});

      expect(report.providersAdded, 1);
      expect(report.modelsAdded, 1);
      expect(target.llmProviders.single.name, 'OpenAI');
      expect(target.llmProviders.single.apiKey, 'sk-secret');
      // A restore onto an unconfigured app may pick the backend; one that
      // already had backends must not be repointed.
      expect(target.activeLlmProfile, isNotNull);

      expect(report.groupsCreated, 1);
      expect(report.tagsAdded, 3);
      expect(target.commonTags, hasLength(3));
      expect(target.tagGroups.single.name, 'Hair');
      expect(target.tagGroups.single.tags, ['long_hair']);
      expect(target.ungroupedTags, ['blue_eyes', 'trigger_word']);

      expect(report.customTagsAdded, 1);
      expect(target.tagDictionary.customEntries.single.name, 'trigger_word');

      expect(report.translationsWritten, 2);
      expect(target.tagTranslations.glossFor('long_hair'), '长发');
      // The inactive language landed in its own file, not the active one.
      expect(target.tagTranslations.glossFor('blue_eyes'), isNull);
      expect(
        (await target.tagTranslations.entriesFor('ja')).single.text,
        '青い目',
      );

      expect(report.presetsAdded, 1);
      expect(target.promptPresets.single.content, 'tidy the tags');
    });

    test('only the selected sections are applied', () async {
      final source = await freshState();
      await seed(source);
      final bundle = DataBundle.decode(
        (await DataTransfer(source).collect(sections: {...DataSection.values}))
            .encode(),
      );

      final target = await freshState();
      await DataTransfer(
        target,
      ).apply(bundle, sections: {DataSection.promptPresets});

      expect(target.promptPresets, hasLength(1));
      expect(target.llmProviders, isEmpty);
      expect(target.commonTags, isEmpty);
    });

    test('importing the same file twice changes nothing the second time',
        () async {
      final source = await freshState();
      await seed(source);
      final bundle = DataBundle.decode(
        (await DataTransfer(source).collect(sections: {...DataSection.values}))
            .encode(),
      );

      final target = await freshState();
      await DataTransfer(
        target,
      ).apply(bundle, sections: {...DataSection.values});
      final second = await DataTransfer(
        target,
      ).apply(bundle, sections: {...DataSection.values});

      expect(second.isEmpty, isTrue);
      expect(target.llmProviders, hasLength(1));
      expect(target.llmProviders.single.models, hasLength(1));
      expect(target.tagGroups, hasLength(1));
      expect(target.commonTags, hasLength(3));
      expect(target.promptPresets, hasLength(1));
      expect(target.tagDictionary.customEntries, hasLength(1));
    });
  });

  group('conflicts', () {
    /// A bundle whose every field disagrees with what [seed] writes.
    Future<DataBundle> conflictingBundle() async {
      final source = await freshState();
      await source.updateLlmProviders([
        const LlmProvider(
          id: 'other',
          name: 'OpenAI',
          baseUrl: 'https://relay.example/v1',
          apiKey: 'sk-from-file',
          models: [
            LlmModelConfig(id: 'x', modelId: 'gpt-5', contextWindow: 400000),
            LlmModelConfig(id: 'y', modelId: 'gpt-5-mini'),
          ],
        ),
      ]);
      await source.addCommonTags(['long_hair']);
      final group = await source.createTagGroup('Hair', 0xFFD983A6);
      await source.moveTagsToGroup(['long_hair'], group.id);
      await source.tagTranslations.upsert(
        const TagTranslation(tag: 'long_hair', text: '长长的头发'),
      );
      await source.createPromptPreset(title: 'cleanup', content: 'from file');
      return DataBundle.decode(
        (await DataTransfer(source).collect(sections: {...DataSection.values}))
            .encode(),
      );
    }

    test('merge keeps what is already here', () async {
      final bundle = await conflictingBundle();
      final target = await freshState();
      await seed(target);

      final report = await DataTransfer(target).apply(
        bundle,
        sections: {...DataSection.values},
        mode: DataImportMode.merge,
      );

      // Matched by name, so no second "OpenAI" backend.
      expect(target.llmProviders, hasLength(1));
      expect(target.llmProviders.single.baseUrl, 'https://api.openai.com/v1');
      expect(target.llmProviders.single.apiKey, 'sk-secret');
      final models = target.llmProviders.single.models;
      expect(models.firstWhere((m) => m.modelId == 'gpt-5').contextWindow,
          200000);
      // A model the local side does not have is still added — merge means
      // "keep what is here", not "ignore the file".
      expect(report.modelsAdded, 1);
      expect(models.map((m) => m.modelId), containsAll(['gpt-5', 'gpt-5-mini']));

      expect(target.tagGroups.single.color, 0xFF6A9BDD);
      expect(target.tagTranslations.glossFor('long_hair'), '长发');
      expect(target.promptPresets.single.content, 'tidy the tags');
      expect(report.presetsAdded, 0);
    });

    test('overwrite lets the file win', () async {
      final bundle = await conflictingBundle();
      final target = await freshState();
      await seed(target);

      final report = await DataTransfer(target).apply(
        bundle,
        sections: {...DataSection.values},
        mode: DataImportMode.overwrite,
      );

      expect(target.llmProviders.single.baseUrl, 'https://relay.example/v1');
      expect(target.llmProviders.single.apiKey, 'sk-from-file');
      expect(
        target.llmProviders.single.models
            .firstWhere((m) => m.modelId == 'gpt-5')
            .contextWindow,
        400000,
      );
      expect(target.tagGroups.single.color, 0xFFD983A6);
      expect(target.tagTranslations.glossFor('long_hair'), '长长的头发');
      expect(target.promptPresets.single.content, 'from file');
      expect(report.presetsUpdated, 1);
    });

    test('a key-stripped export never blanks a key that is already here',
        () async {
      final source = await freshState();
      await source.updateLlmProviders([provider]);
      final bundle = DataBundle.decode(
        (await DataTransfer(source).collect(
          sections: {DataSection.llm},
          includeApiKeys: false,
        )).encode(),
      );

      final target = await freshState();
      await target.updateLlmProviders([provider]);
      await DataTransfer(target).apply(
        bundle,
        sections: {DataSection.llm},
        mode: DataImportMode.overwrite,
      );

      expect(target.llmProviders.single.apiKey, 'sk-secret');
    });

    test('neither mode deletes anything the file does not mention', () async {
      final bundle = await conflictingBundle();
      final target = await freshState();
      await seed(target);
      await target.addCommonTags(['local_only']);
      await target.createPromptPreset(title: 'local', content: 'mine');

      await DataTransfer(target).apply(
        bundle,
        sections: {...DataSection.values},
        mode: DataImportMode.overwrite,
      );

      expect(target.commonTags, contains('local_only'));
      expect(target.promptPresets.map((p) => p.title), contains('local'));
      expect(target.tagDictionary.customEntries, hasLength(1));
      expect(
        (await target.tagTranslations.entriesFor('ja')).single.text,
        '青い目',
      );
    });

    test('a backend the file does not name keeps the active pointer', () async {
      final bundle = await conflictingBundle();
      final target = await freshState();
      await target.updateLlmProviders([
        const LlmProvider(
          id: 'local',
          name: 'Ollama',
          baseUrl: 'http://127.0.0.1:11434/v1',
          models: [LlmModelConfig(id: 'l', modelId: 'qwen3')],
        ),
      ]);
      await target.setActiveLlmProfile('local/l');

      await DataTransfer(
        target,
      ).apply(bundle, sections: {DataSection.llm});

      expect(target.llmProviders, hasLength(2));
      expect(target.activeLlmProfile?.model, 'qwen3');
    });
  });
}

/// Unique subdirectory per state, so two states in one test do not share a
/// dictionary or a glossary folder.
int _scope = 0;
String _nextScope() => 'scope${_scope++}';
