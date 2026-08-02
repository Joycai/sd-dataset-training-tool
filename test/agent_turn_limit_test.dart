import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dataset_training_tool/app_state.dart';
import 'package:dataset_training_tool/l10n/app_localizations.dart';
import 'package:dataset_training_tool/services/agent/agent_session.dart';
import 'package:dataset_training_tool/services/settings_service.dart';
import 'package:dataset_training_tool/state/agent_chat_state.dart';
import 'package:dataset_training_tool/state/ai_tagger_state.dart';
import 'package:dataset_training_tool/state/dataset_state.dart';
import 'package:dataset_training_tool/state/tag_ops.dart';
import 'package:dataset_training_tool/theme/app_theme.dart';
import 'package:dataset_training_tool/views/panels/agent_chat_panel.dart';

void main() {
  group('turn limit continue card', () {
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

    /// Parks a run at the limit the way the session does; the returned
    /// completer carries whatever the card answers.
    Future<PendingContinue> park(WidgetTester tester) async {
      final pending = PendingContinue(24);
      chat.pendingContinue = pending;
      await tester.pumpWidget(harness());
      await tester.pumpAndSettle();
      return pending;
    }

    testWidgets('names the turns spent and offers both ways out', (
      tester,
    ) async {
      await park(tester);
      expect(find.textContaining('24 turns'), findsOneWidget);
      expect(find.text('Continue'), findsOneWidget);
      expect(find.text('Stop here'), findsOneWidget);
    });

    testWidgets('Continue resolves with a decision, no note', (tester) async {
      final pending = await park(tester);
      await tester.tap(find.text('Continue'));
      expect((await pending.completer.future)?.note, isNull);
    });

    testWidgets('Stop here resolves null', (tester) async {
      final pending = await park(tester);
      await tester.tap(find.text('Stop here'));
      expect(await pending.completer.future, isNull);
    });

    testWidgets('a typed reply continues and carries the note', (tester) async {
      final pending = await park(tester);
      await tester.enterText(
        find.byType(TextField).first,
        'skip the done ones',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      expect((await pending.completer.future)?.note, 'skip the done ones');
    });

    testWidgets('stopping at the limit is not reported as an error', (
      tester,
    ) async {
      chat.entries.add(AgentChatEntry.notice(AgentNoticeType.turnLimitStopped));
      await tester.pumpWidget(harness());
      await tester.pumpAndSettle();

      expect(find.textContaining('Stopped at the turn limit'), findsOneWidget);
      expect(find.textContaining('Error:'), findsNothing);
    });
  });
}
