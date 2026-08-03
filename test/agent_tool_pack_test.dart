import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dataset_training_tool/app_state.dart';
import 'package:dataset_training_tool/models/agent_tool_pack.dart';
import 'package:dataset_training_tool/models/llm_models.dart';
import 'package:dataset_training_tool/services/agent/agent_session.dart';
import 'package:dataset_training_tool/services/agent/agent_tools.dart';
import 'package:dataset_training_tool/services/settings_service.dart';
import 'package:dataset_training_tool/state/agent_chat_state.dart';
import 'package:dataset_training_tool/state/ai_tagger_state.dart';
import 'package:dataset_training_tool/state/dataset_state.dart';
import 'package:dataset_training_tool/state/tag_ops.dart';

const _profile = LlmProviderProfile(id: 'p', name: 'fake', model: 'm');

void main() {
  group('AgentToolPack.decode', () {
    test('a missing key is a first run, not "everything off"', () {
      expect(AgentToolPack.decode(null), AgentToolPack.defaults);
      expect(AgentToolPack.decode(null), {AgentToolPack.tagLibrary});
    });

    test('an empty list is a user who switched everything off', () {
      expect(AgentToolPack.decode(const []), isEmpty);
    });

    test('an id from a future build is dropped, not fatal', () {
      expect(AgentToolPack.decode(const ['mergeRules', 'fromTheFuture']), {
        AgentToolPack.mergeRules,
      });
    });
  });

  group('AppState', () {
    late AppState state;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      state = AppState(SettingsService());
      await state.loadSettings();
    });

    test('defaults: library on, translation and merge rules off', () {
      expect(state.isAgentToolPackEnabled(AgentToolPack.tagLibrary), isTrue);
      expect(
        state.isAgentToolPackEnabled(AgentToolPack.tagTranslation),
        isFalse,
      );
      expect(state.isAgentToolPackEnabled(AgentToolPack.mergeRules), isFalse);
    });

    test('switching a pack persists and survives a reload', () async {
      await state.updateAgentToolPack(AgentToolPack.tagLibrary, false);
      await state.updateAgentToolPack(AgentToolPack.tagTranslation, true);

      final reloaded = AppState(SettingsService());
      await reloaded.loadSettings();
      expect(reloaded.isAgentToolPackEnabled(AgentToolPack.tagLibrary), isFalse);
      expect(
        reloaded.isAgentToolPackEnabled(AgentToolPack.tagTranslation),
        isTrue,
      );
    });

    test('switching everything off survives a reload as off', () async {
      // The one case a null-means-defaults fallback would silently undo.
      await state.updateAgentToolPack(AgentToolPack.tagLibrary, false);
      final reloaded = AppState(SettingsService());
      await reloaded.loadSettings();
      expect(reloaded.agentToolPacks, isEmpty);
    });
  });

  group('registry gating', () {
    late AppState appState;
    late DatasetState dataset;
    late AiTaggerState ai;
    late TagOps tagOps;
    late AgentChatState chat;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      appState = AppState(SettingsService());
      await appState.loadSettings();
      dataset = DatasetState();
      ai = AiTaggerState(SettingsService());
      tagOps = TagOps(dataset: dataset);
      chat = AgentChatState(
        app: appState,
        dataset: dataset,
        tagOps: tagOps,
        aiTagger: ai,
      );
    });

    tearDown(() {
      chat.dispose();
      tagOps.dispose();
      ai.dispose();
      dataset.dispose();
    });

    List<String> names() => [
      for (final spec in chat.buildRegistry(_profile).specs) spec.name,
    ];

    test('the default registry carries the library pack and nothing else', () {
      final tools = names();
      expect(tools, contains('organize_tag_library'));
      expect(tools, isNot(contains('list_tag_translations')));
      expect(tools, isNot(contains('propose_merge_rules')));
      // The unconditional core is untouched by any of this.
      expect(tools, containsAll(['get_tag_stats', 'write_caption']));
    });

    test('switching a pack on registers its whole group', () async {
      await appState.updateAgentToolPack(AgentToolPack.tagTranslation, true);
      expect(
        names(),
        containsAll([
          'list_tag_translations',
          'fetch_danbooru_tag',
          'write_tag_translations',
        ]),
      );
    });

    /// Rough size of everything the registry puts on the wire each turn.
    /// Not the token estimate — just enough to show the gate removes weight,
    /// not only entries.
    int weight(ToolRegistry registry) => registry.specs.fold(
      0,
      (sum, spec) =>
          sum +
          spec.name.length +
          spec.description.length +
          jsonEncode(spec.parametersSchema).length,
    );

    test('switching the library pack off drops six tools and their bulk', () {
      final before = chat.buildRegistry(_profile);
      final withLibrary = weight(before);

      appState.updateAgentToolPack(AgentToolPack.tagLibrary, false);
      final after = chat.buildRegistry(_profile);
      expect(before.specs.length - after.specs.length, 6);
      // The whole point of the gate: less re-sent on every single turn.
      expect(withLibrary - weight(after), greaterThan(2000));
      expect(names(), isNot(contains('organize_tag_library')));
    });
  });

  group('system prompt', () {
    String prompt({bool library = true, bool translation = true}) =>
        buildAgentSystemPrompt(
          localeName: 'English',
          datasetSummary: 'none',
          captionExtension: '.txt',
          libraryToolsEnabled: library,
          translationToolsEnabled: translation,
        );

    test('a pack that is off is not described either', () {
      expect(prompt(), contains('organize_tag_library'));
      expect(prompt(), contains('list_tag_translations'));
      // Describing a tool the model was not given buys nothing but a refusal
      // it has to discover the hard way.
      expect(
        prompt(library: false, translation: false),
        isNot(contains('organize_tag_library')),
      );
      expect(
        prompt(library: false, translation: false),
        isNot(contains('list_tag_translations')),
      );
    });

    test('the core guidelines survive either way', () {
      final bare = prompt(library: false, translation: false);
      expect(bare, contains('get_dataset_overview'));
      expect(bare, contains('sort_captions_everywhere'));
    });
  });
}
