import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dataset_training_tool/app_state.dart';
import 'package:dataset_training_tool/l10n/app_localizations.dart';
import 'package:dataset_training_tool/services/settings_service.dart';
import 'package:dataset_training_tool/state/agent_chat_state.dart';
import 'package:dataset_training_tool/state/ai_tagger_state.dart';
import 'package:dataset_training_tool/state/dataset_state.dart';
import 'package:dataset_training_tool/state/tag_ops.dart';
import 'package:dataset_training_tool/theme/app_theme.dart';
import 'package:dataset_training_tool/views/panels/agent_chat_panel.dart';

void main() {
  group('AppState session token cap', () {
    late AppState state;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      state = AppState(SettingsService());
      await state.loadSettings();
    });

    test('defaults to one million', () {
      expect(state.agentSessionTokenCap, 1000000);
    });

    test('update persists and survives a reload', () async {
      await state.updateAgentSessionTokenCap(5000000);
      expect(state.agentSessionTokenCap, 5000000);

      final reloaded = AppState(SettingsService());
      await reloaded.loadSettings();
      expect(reloaded.agentSessionTokenCap, 5000000);
    });

    test('0 is uncapped and negatives clamp to it', () async {
      await state.updateAgentSessionTokenCap(0);
      expect(state.agentSessionTokenCap, 0);
      await state.updateAgentSessionTokenCap(-1);
      expect(state.agentSessionTokenCap, 0);
    });
  });

  group('chat panel usage footer', () {
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

    test('the cap falls back to the setting with no session running', () async {
      expect(chat.tokenCap, 1000000);
      await appState.updateAgentSessionTokenCap(0);
      expect(chat.tokenCap, 0);
    });

    testWidgets('the cap notice says what to do about it', (tester) async {
      chat.entries.add(AgentChatEntry.notice(AgentNoticeType.tokenCap));
      await tester.pumpWidget(harness());
      await tester.pumpAndSettle();

      expect(
        find.textContaining('reached its token budget'),
        findsOneWidget,
      );
      // Not the raw "session token cap (1000000) reached" of the stop reason.
      expect(find.textContaining('session token cap'), findsNothing);
    });
  });
}
