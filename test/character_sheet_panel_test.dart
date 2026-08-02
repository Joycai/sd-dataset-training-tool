import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dataset_training_tool/app_state.dart';
import 'package:dataset_training_tool/l10n/app_localizations.dart';
import 'package:dataset_training_tool/models/llm_models.dart';
import 'package:dataset_training_tool/models/merge_rules.dart';
import 'package:dataset_training_tool/services/settings_service.dart';
import 'package:dataset_training_tool/state/agent_chat_state.dart';
import 'package:dataset_training_tool/state/ai_tagger_state.dart';
import 'package:dataset_training_tool/state/dataset_state.dart';
import 'package:dataset_training_tool/state/tag_ops.dart';
import 'package:dataset_training_tool/theme/app_theme.dart';
import 'package:dataset_training_tool/views/panels/agent_chat_panel.dart';

void main() {
  late AppState appState;
  late DatasetState dataset;
  late AiTaggerState ai;
  late TagOps tagOps;
  late AgentChatState chat;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    appState = AppState(SettingsService());
    await appState.loadSettings();
    // The skill entry mirrors the input field's enabled state, which needs a
    // configured backend.
    await appState.updateLlmProviders([
      const LlmProvider(
        id: 'p1',
        name: 'Alpha',
        models: [LlmModelConfig(id: 'm1', modelId: 'alpha-mini')],
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
        body: SizedBox(width: 360, height: 620, child: AgentChatPanel()),
      ),
    ),
  );

  Future<void> openSkillDialog(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Prompt presets'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Character sheet tagging…'));
    await tester.pumpAndSettle();
  }

  testWidgets('the skill sits above the saved prompts', (tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Prompt presets'));
    await tester.pumpAndSettle();
    expect(find.text('Built-in skills'), findsOneWidget);
    expect(find.text('Character sheet tagging…'), findsOneWidget);
  });

  testWidgets('the skill opens its form', (tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();
    await openSkillDialog(tester);

    expect(find.text('Character sheet tagging'), findsOneWidget);
    expect(find.text('Outfit'), findsOneWidget);
    expect(find.text('Additional requirements (optional)'), findsOneWidget);
  });

  testWidgets('an empty sheet cannot be started', (tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();
    await openSkillDialog(tester);

    Finder startButton() => find.widgetWithText(FilledButton, 'Start');
    // Scoped to the dialog: the panel's own input box is a TextField too.
    Finder field(int i) => find
        .descendant(of: find.byType(Dialog), matching: find.byType(TextField))
        .at(i);
    expect(tester.widget<FilledButton>(startButton()).onPressed, isNull);

    // The name alone is a label, not an instruction — it must not enable the
    // run. The trigger word must.
    await tester.enterText(field(0), 'Aoi');
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(startButton()).onPressed, isNull);

    await tester.enterText(field(1), 'aoichr');
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(startButton()).onPressed, isNotNull);
  });

  testWidgets('proposed rules render as a review card', (tester) async {
    chat.entries.add(
      AgentChatEntry.rules(
        const CharacterMergeRules(
          id: 'r1',
          character: 'Aoi',
          triggerWord: 'aoichr',
          identityTags: ['blonde hair', 'twintails'],
          conflictTags: ['brown hair'],
          garments: [
            GarmentRule(
              tag: 'dress',
              evidence: ['dress', 'skirt'],
              note: 'lower-body crops only show a skirt',
            ),
            GarmentRule(tag: 'gloves'),
          ],
          passthrough: ['expression', 'background'],
          sampledImages: 12,
        ),
      ),
    );
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    expect(find.text('Merge rules · Aoi'), findsOneWidget);
    expect(find.text('from 12 sampled images'), findsOneWidget);
    expect(find.text('blonde hair, twintails'), findsOneWidget);
    expect(find.text('when the tagger says: dress, skirt'), findsOneWidget);
    expect(find.text('lower-body crops only show a skirt'), findsOneWidget);
    // The garment the sample never showed says so rather than looking like a
    // rule that fires.
    expect(
      find.text('no evidence in the sample — never written'),
      findsOneWidget,
    );
  });
}
