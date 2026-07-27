import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dataset_training_tool/app_state.dart';
import 'package:dataset_training_tool/models/llm_models.dart';
import 'package:dataset_training_tool/services/settings_service.dart';

/// Exactly what a pre-tree build wrote: a flat list of backends, each with
/// its own URL, key and single model.
const _legacyJson = '''
[
  {
    "id": "old-openai",
    "name": "OpenAI",
    "kind": "openai",
    "baseUrl": "https://api.openai.com/v1",
    "apiKey": "sk-legacy",
    "model": "gpt-4o",
    "supportsVision": true,
    "contextWindow": 128000,
    "maxOutputTokens": 8192,
    "temperature": 0.4
  },
  {
    "id": "old-ollama",
    "name": "Ollama",
    "kind": "openai",
    "baseUrl": "http://127.0.0.1:11434/v1",
    "apiKey": "",
    "model": "qwen2.5",
    "supportsVision": false,
    "contextWindow": 32768,
    "maxOutputTokens": 4096,
    "temperature": 0.7
  }
]
''';

void main() {
  group('migration from the flat backend list', () {
    test('each old backend becomes a provider holding its one model', () {
      final providers = decodeLlmProviders(_legacyJson);

      expect(providers, hasLength(2));
      final openai = providers.first;
      expect(openai.id, 'old-openai');
      expect(openai.name, 'OpenAI');
      expect(openai.baseUrl, 'https://api.openai.com/v1');
      expect(openai.apiKey, 'sk-legacy');
      expect(openai.models, hasLength(1));

      // Everything per-model moved down a level, unchanged.
      final model = openai.models.single;
      expect(model.modelId, 'gpt-4o');
      expect(model.supportsVision, isTrue);
      expect(model.contextWindow, 128000);
      expect(model.maxOutputTokens, 8192);
      expect(model.temperature, 0.4);
    });

    test('re-encoding writes the tree shape and stays stable', () {
      final once = decodeLlmProviders(_legacyJson);
      final encoded = encodeLlmProviders(once);

      // The stored shape is now a tree: models live in an array.
      final raw = jsonDecode(encoded) as List<dynamic>;
      expect((raw.first as Map<String, dynamic>).containsKey('models'), isTrue);
      expect((raw.first as Map<String, dynamic>).containsKey('model'), isFalse);

      final twice = decodeLlmProviders(encoded);
      expect(twice.map((p) => p.id), once.map((p) => p.id));
      expect(
        twice.first.models.single.modelId,
        once.first.models.single.modelId,
      );
    });

    test('a malformed blob yields nothing rather than throwing', () {
      expect(decodeLlmProviders('not json'), isEmpty);
      expect(decodeLlmProviders('{"not": "a list"}'), isEmpty);
    });
  });

  group('resolving a provider/model pair', () {
    test('the model inherits the endpoint and credentials', () {
      final provider = decodeLlmProviders(_legacyJson).first;
      final resolved = provider.resolve(provider.models.single);

      expect(resolved.baseUrl, 'https://api.openai.com/v1');
      expect(resolved.apiKey, 'sk-legacy');
      expect(resolved.model, 'gpt-4o');
      expect(resolved.contextWindow, 128000);
      // A lone model does not clutter the label with its own name.
      expect(resolved.name, 'OpenAI');
    });

    test('a second model under one provider reuses its URL and key', () {
      final base = decodeLlmProviders(_legacyJson).first;
      final provider = base.copyWith(
        models: [
          ...base.models,
          const LlmModelConfig(
            id: 'mini',
            modelId: 'gpt-4o-mini',
            displayName: 'Mini',
          ),
        ],
      );

      final second = provider.resolve(provider.models.last);
      expect(second.baseUrl, 'https://api.openai.com/v1');
      expect(second.apiKey, 'sk-legacy');
      expect(second.model, 'gpt-4o-mini');
      // With siblings, the label says which model it is.
      expect(second.name, 'OpenAI · Mini');
    });
  });

  group('AppState', () {
    test('flattens the tree and honours a legacy active id', () async {
      SharedPreferences.setMockInitialValues({
        'flutter.llmProviderProfiles': _legacyJson,
        // Written before the tree: a backend id, not a provider/model pair.
        'flutter.llmActiveProfileId': 'old-ollama',
      });
      final appState = AppState(SettingsService());
      await appState.loadSettings();

      expect(appState.llmProviders, hasLength(2));
      expect(appState.llmProfiles, hasLength(2));
      // The stale id names a provider; its first model stands in.
      expect(appState.activeLlmProfile?.model, 'qwen2.5');
      expect(appState.activeLlmProfile?.id, 'old-ollama/default');
    });

    test(
      'deleting the active pair moves the selection to a live one',
      () async {
        SharedPreferences.setMockInitialValues({
          'flutter.llmProviderProfiles': _legacyJson,
          'flutter.llmActiveProfileId': 'old-openai/default',
        });
        final appState = AppState(SettingsService());
        await appState.loadSettings();
        expect(appState.activeLlmProfile?.model, 'gpt-4o');

        await appState.updateLlmProviders(
          appState.llmProviders.where((p) => p.id != 'old-openai').toList(),
        );

        expect(appState.llmProfiles, hasLength(1));
        expect(appState.activeLlmProfile?.model, 'qwen2.5');
      },
    );

    test('no configured backend resolves to null, not a crash', () async {
      SharedPreferences.setMockInitialValues({});
      final appState = AppState(SettingsService());
      await appState.loadSettings();

      expect(appState.llmProviders, isEmpty);
      expect(appState.activeLlmProfile, isNull);
    });
  });
}
