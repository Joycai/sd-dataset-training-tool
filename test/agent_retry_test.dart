import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dataset_training_tool/app_state.dart';
import 'package:dataset_training_tool/l10n/app_localizations.dart';
import 'package:dataset_training_tool/models/llm_models.dart';
import 'package:dataset_training_tool/services/agent/agent_session.dart';
import 'package:dataset_training_tool/services/agent/agent_tools.dart';
import 'package:dataset_training_tool/services/llm/llm_client.dart';
import 'package:dataset_training_tool/services/settings_service.dart';
import 'package:dataset_training_tool/state/agent_chat_state.dart';
import 'package:dataset_training_tool/state/ai_tagger_state.dart';
import 'package:dataset_training_tool/state/dataset_state.dart';
import 'package:dataset_training_tool/state/tag_ops.dart';
import 'package:dataset_training_tool/theme/app_theme.dart';
import 'package:dataset_training_tool/views/panels/agent_chat_panel.dart';

/// Scripted client with failures in the script: one entry per chat() call,
/// where a null entry dies the way a dead connection does. The last entry
/// repeats if the loop asks for more.
class ScriptedLlmClient implements LlmClient {
  ScriptedLlmClient(this.turns, {this.cancelBeforeFailing = false});

  final List<List<LlmStreamEvent>?> turns;

  /// Cancels the token before failing, which is what pressing stop does: the
  /// socket closes and the client reports the broken read.
  final bool cancelBeforeFailing;

  final List<List<ChatMessage>> seenMessages = [];
  int calls = 0;

  @override
  Stream<LlmStreamEvent> chat({
    required LlmProviderProfile profile,
    required List<ChatMessage> messages,
    List<AgentToolSpec> tools = const [],
    CancellationToken? cancel,
  }) {
    seenMessages.add(List.of(messages));
    final turn = turns[calls < turns.length ? calls : turns.length - 1];
    calls++;
    if (turn == null) {
      if (cancelBeforeFailing) cancel?.cancel();
      return Stream.error(LlmException('Connection timed out after 30s.'));
    }
    return Stream.fromIterable(turn);
  }

  @override
  Future<String?> probe(LlmProviderProfile profile) async => null;

  @override
  Future<List<String>> listModels(LlmProviderProfile profile) async => const [];

  @override
  void dispose() {}
}

const _profile = LlmProviderProfile(id: 'p1', name: 'fake', model: 'fake');

AgentTool _echoTool() => AgentTool(
  spec: const AgentToolSpec(
    name: 'echo',
    description: 'echoes',
    parametersSchema: {'type': 'object', 'properties': {}},
  ),
  handler: (args) async => toolOk({'echo': args['v']}),
);

AgentSession _session(ScriptedLlmClient client) => AgentSession(
  client: client,
  registry: ToolRegistry([_echoTool()]),
  profile: _profile,
  systemPrompt: 'sys',
);

List<LlmStreamEvent> _toolTurn() => [
  ToolCallsReady([
    const ChatToolCall(id: 'c1', name: 'echo', argumentsJson: '{}'),
  ]),
  StreamDone(finishReason: 'tool_calls'),
];

void main() {
  group('AgentSession.resume', () {
    test('an API failure ends the run as retryable', () async {
      final client = ScriptedLlmClient([null]);
      final session = _session(client);

      final done = (await session.run('hello').toList()).last as AgentFinished;
      expect(done.reason, AgentStopReason.error);
      expect(done.message, contains('timed out'));
      expect(done.retryable, isTrue);
    });

    test('resume repeats the failed request, it does not add one', () async {
      final client = ScriptedLlmClient([
        null,
        [TextDelta('recovered'), StreamDone(finishReason: 'stop')],
      ]);
      final session = _session(client);

      await session.run('hello').toList();
      final events = await session.resume().toList();

      expect((events.last as AgentFinished).reason, AgentStopReason.completed);
      expect(client.calls, 2);
      // Byte for byte the request that failed — one user message, not two.
      expect(client.seenMessages[1].map((m) => m.text).toList(), [
        'sys',
        'hello',
      ]);
      expect(
        session.history.where((m) => m.role == ChatRole.user),
        hasLength(1),
      );
      expect(session.history.last.text, 'recovered');
    });

    test('resume keeps the work the failed run already did', () async {
      // Tool call, then the turn that reads its result dies.
      final client = ScriptedLlmClient([
        _toolTurn(),
        null,
        [TextDelta('done'), StreamDone(finishReason: 'stop')],
      ]);
      final session = _session(client);

      final done = (await session.run('go').toList()).last as AgentFinished;
      expect(done.reason, AgentStopReason.error);

      await session.resume().toList();
      expect(client.calls, 3);
      // The retry picks up after the tool call rather than running it again.
      expect(
        client.seenMessages[2].map((m) => m.role).toList(),
        client.seenMessages[1].map((m) => m.role).toList(),
      );
      expect(client.seenMessages[2].last.role, ChatRole.tool);
      expect(
        session.history.where((m) => m.role == ChatRole.tool),
        hasLength(1),
      );
    });

    test('a cancelled run is not retryable', () async {
      final client = ScriptedLlmClient([null], cancelBeforeFailing: true);
      final session = _session(client);

      final done = (await session.run('hello').toList()).last as AgentFinished;
      expect(done.reason, AgentStopReason.cancelled);
      expect(done.retryable, isFalse);
    });

    test('resume with nothing to repeat never reaches the model', () async {
      final client = ScriptedLlmClient([
        [TextDelta('unreachable'), StreamDone(finishReason: 'stop')],
      ]);
      final session = _session(client);

      await session.resume().toList();
      expect(client.calls, 0);
    });
  });

  group('error card', () {
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

    testWidgets('shows the failure and a way to send it again', (tester) async {
      chat.entries.add(
        AgentChatEntry.notice(
          AgentNoticeType.error,
          'Connection timed out after 30s.',
          true,
        ),
      );
      await tester.pumpWidget(harness());
      await tester.pumpAndSettle();

      expect(find.text('The request failed'), findsOneWidget);
      expect(find.textContaining('Connection timed out'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('a failure repeating cannot fix offers no button', (
      tester,
    ) async {
      chat.entries.add(
        AgentChatEntry.notice(
          AgentNoticeType.error,
          'stopped after 3 consecutive tool errors',
        ),
      );
      await tester.pumpWidget(harness());
      await tester.pumpAndSettle();

      expect(find.text('The request failed'), findsOneWidget);
      expect(find.text('Try again'), findsNothing);
    });

    testWidgets('only the last failure keeps its button', (tester) async {
      chat.entries.addAll([
        AgentChatEntry.notice(AgentNoticeType.error, 'first failure', true),
        AgentChatEntry.user('never mind, do this instead'),
        AgentChatEntry.notice(AgentNoticeType.error, 'second failure', true),
      ]);
      await tester.pumpWidget(harness());
      await tester.pumpAndSettle();

      expect(find.text('The request failed'), findsNWidgets(2));
      expect(find.text('Try again'), findsOneWidget);
    });

    test('retry without a session leaves the offer standing', () async {
      chat.entries.add(
        AgentChatEntry.notice(AgentNoticeType.error, 'boom', true),
      );
      expect(chat.canRetry, isTrue);
      await chat.retry();
      // Nothing to resume, so nothing is spent: the button must not be
      // consumed by a no-op.
      expect(chat.canRetry, isTrue);
    });
  });
}
