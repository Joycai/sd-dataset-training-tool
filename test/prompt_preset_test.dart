import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dataset_training_tool/app_state.dart';
import 'package:dataset_training_tool/l10n/app_localizations.dart';
import 'package:dataset_training_tool/models/llm_models.dart';
import 'package:dataset_training_tool/models/prompt_preset.dart';
import 'package:dataset_training_tool/services/settings_service.dart';
import 'package:dataset_training_tool/state/agent_chat_state.dart';
import 'package:dataset_training_tool/state/ai_tagger_state.dart';
import 'package:dataset_training_tool/state/dataset_state.dart';
import 'package:dataset_training_tool/state/tag_ops.dart';
import 'package:dataset_training_tool/theme/app_theme.dart';
import 'package:dataset_training_tool/views/panels/agent_chat_panel.dart';
import 'package:dataset_training_tool/views/panels/prompt_preset_dialog.dart';

void main() {
  group('PromptPreset JSON', () {
    test('encode/decode round trip', () {
      const presets = [
        PromptPreset(id: '1', title: 'cleanup', content: 'tidy the tags'),
        PromptPreset(id: '2'),
      ];
      final decoded = decodePromptPresets(encodePromptPresets(presets));
      expect(decoded, hasLength(2));
      expect(decoded[0].title, 'cleanup');
      expect(decoded[0].content, 'tidy the tags');
      expect(decoded[1].id, '2');
      expect(decoded[1].title, isEmpty);
      expect(decoded[1].content, isEmpty);
    });

    test('corrupt json decodes to empty, partial entries are dropped', () {
      expect(decodePromptPresets('not json'), isEmpty);
      expect(decodePromptPresets('{"a":1}'), isEmpty);
      expect(decodePromptPresets(''), isEmpty);
      // Missing id: no stable handle for edits, so it is not worth keeping.
      expect(decodePromptPresets('[{"title":"x"}]'), isEmpty);
    });
  });

  group('AppState prompt presets', () {
    late AppState state;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      state = AppState(SettingsService());
      await state.loadSettings();
    });

    test('starts empty', () {
      expect(state.promptPresets, isEmpty);
    });

    test('create, edit and delete', () async {
      final first = await state.createPromptPreset(title: 'a');
      await state.createPromptPreset(title: 'b', content: 'body');
      expect(state.promptPresets, hasLength(2));
      expect(state.promptPresets[1].content, 'body');

      await state.updatePromptPreset(first.id, content: 'edited');
      expect(state.promptPresets.first.title, 'a');
      expect(state.promptPresets.first.content, 'edited');

      await state.deletePromptPreset(first.id);
      expect(state.promptPresets.map((p) => p.title), ['b']);
    });

    test('ids are unique within a tick', () async {
      final a = await state.createPromptPreset(title: 'a');
      final b = await state.createPromptPreset(title: 'b');
      expect(a.id, isNot(b.id));
    });

    test('reorder moves and clamps at the ends', () async {
      final a = await state.createPromptPreset(title: 'a');
      await state.createPromptPreset(title: 'b');
      final c = await state.createPromptPreset(title: 'c');

      await state.reorderPromptPreset(c.id, -1);
      expect(state.promptPresets.map((p) => p.title), ['a', 'c', 'b']);

      // Already first: nothing to move past.
      await state.reorderPromptPreset(a.id, -1);
      expect(state.promptPresets.map((p) => p.title), ['a', 'c', 'b']);
    });

    test('survives a reload', () async {
      await state.createPromptPreset(title: 'a', content: 'body');
      final reloaded = AppState(SettingsService());
      await reloaded.loadSettings();
      expect(reloaded.promptPresets, hasLength(1));
      expect(reloaded.promptPresets.first.content, 'body');
    });
  });

  group('preset picker', () {
    late AppState appState;
    late DatasetState dataset;
    late AiTaggerState ai;
    late TagOps tagOps;
    late AgentChatState chat;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      appState = AppState(SettingsService());
      await appState.loadSettings();
      // The input row is disabled without a backend, and so are the presets.
      await appState.updateLlmProviders([
        const LlmProvider(
          id: 'p1',
          name: 'test',
          baseUrl: 'http://localhost/v1',
          models: [LlmModelConfig(id: 'm1', modelId: 'test-model')],
        ),
      ]);
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

    Widget harness() => MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: appState),
        ChangeNotifierProvider.value(value: chat),
      ],
      child: MaterialApp(
        theme: buildAppTheme(Brightness.dark),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(
          body: SizedBox(width: 340, height: 460, child: AgentChatPanel()),
        ),
      ),
    );

    testWidgets('picking a preset fills the input instead of sending', (
      tester,
    ) async {
      await appState.createPromptPreset(
        title: 'cleanup',
        content: 'remove duplicate tags',
      );
      await tester.pumpWidget(harness());
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Prompt presets'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('cleanup'));
      await tester.pumpAndSettle();

      final field = tester.widget<TextField>(
        find.widgetWithText(TextField, 'remove duplicate tags'),
      );
      expect(field.controller!.text, 'remove duplicate tags');
      // Nothing was sent: the transcript is still empty.
      expect(chat.entries, isEmpty);
    });

    testWidgets('a second pick appends on its own line', (tester) async {
      await appState.createPromptPreset(title: 'one', content: 'first');
      await appState.createPromptPreset(title: 'two', content: 'second');
      await tester.pumpWidget(harness());
      await tester.pumpAndSettle();

      for (final label in ['one', 'two']) {
        await tester.tap(find.byTooltip('Prompt presets'));
        await tester.pumpAndSettle();
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
      }

      expect(find.text('first\nsecond'), findsOneWidget);
    });

    testWidgets('built-in Anima presets fill the input without sending', (
      tester,
    ) async {
      await tester.pumpWidget(harness());
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Prompt presets'));
      await tester.pumpAndSettle();
      expect(find.text('Built-in prompts'), findsOneWidget);
      expect(find.text('Reorder Anima JSON fields'), findsOneWidget);

      await tester.tap(find.text('WD14 tags to Anima JSON'));
      await tester.pumpAndSettle();

      final field = tester.widget<TextField>(
        find.byWidgetPredicate(
          (w) =>
              w is TextField &&
              (w.controller?.text.contains('convert_captions_to_json') ??
                  false),
        ),
      );
      expect(field.controller!.text, contains('unassigned_field'));
      // Filled the input only: nothing went to the session.
      expect(chat.entries, isEmpty);
    });

    testWidgets('with no presets the menu says so', (tester) async {
      await tester.pumpWidget(harness());
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Prompt presets'));
      await tester.pumpAndSettle();
      expect(find.text('No prompt presets yet'), findsOneWidget);
      expect(find.text('Manage presets…'), findsOneWidget);
    });
  });

  group('preset dialog', () {
    late AppState appState;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      appState = AppState(SettingsService());
      await appState.loadSettings();
    });

    Widget harness() => ChangeNotifierProvider.value(
      value: appState,
      child: MaterialApp(
        theme: buildAppTheme(Brightness.dark),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showPromptPresetsDialog(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    testWidgets('adding and editing a preset writes through', (tester) async {
      await tester.pumpWidget(harness());
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('No prompt presets yet'), findsOneWidget);
      await tester.tap(find.text('Add prompt'));
      await tester.pumpAndSettle();
      expect(appState.promptPresets, hasLength(1));

      // The new preset is selected, so its form is on screen.
      await tester.enterText(
        find.widgetWithText(TextField, 'New prompt'),
        'cleanup',
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField).last,
        'remove duplicate tags',
      );
      await tester.pumpAndSettle();

      expect(appState.promptPresets.single.title, 'cleanup');
      expect(appState.promptPresets.single.content, 'remove duplicate tags');
    });

    testWidgets('deleting asks first', (tester) async {
      await appState.createPromptPreset(title: 'cleanup', content: 'body');
      await tester.pumpWidget(harness());
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('cleanup'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(find.text('Delete prompt'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(appState.promptPresets, hasLength(1));

      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Delete').last);
      await tester.pumpAndSettle();
      expect(appState.promptPresets, isEmpty);
    });
  });
}
