import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dataset_training_tool/app_state.dart';
import 'package:dataset_training_tool/models/llm_models.dart';
import 'package:dataset_training_tool/services/agent/agent_session.dart';
import 'package:dataset_training_tool/services/settings_service.dart';
import 'package:dataset_training_tool/state/agent_chat_state.dart';
import 'package:dataset_training_tool/state/ai_tagger_state.dart';
import 'package:dataset_training_tool/state/dataset_state.dart';
import 'package:dataset_training_tool/state/tag_ops.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  test('a burst of text deltas coalesces to a handful of notifications', () async {
    var notifications = 0;
    chat.addListener(() => notifications++);

    await chat.consumeEventsForTest(
      Stream.fromIterable([
        for (var i = 0; i < 200; i++) AgentTextDelta('word$i '),
        AgentFinished(AgentStopReason.completed),
      ]),
    );

    // The whole burst lands within one coalescing window, so it costs at
    // most one deferred notification; the finish and the cleanup in the
    // finally block notify immediately. Without coalescing this is 201+.
    expect(notifications, lessThan(10));
    // No delta may be lost to the batching.
    expect(chat.entries.last.text, contains('word0'));
    expect(chat.entries.last.text, contains('word199'));
    // Every event still bumps the revision, deferred or not.
    expect(chat.revision, greaterThanOrEqualTo(201));
  });

  test('a pending delta notification still fires without a structural event',
      () async {
    var notifications = 0;
    chat.addListener(() => notifications++);

    final controller = StreamController<AgentUiEvent>();
    final consumed = chat.consumeEventsForTest(controller.stream);
    controller.add(AgentTextDelta('hello'));
    await Future<void>.delayed(Duration.zero);
    // The delta's notification is deferred, not dropped: it arrives once the
    // coalescing window elapses even though nothing else happens.
    expect(notifications, 0);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(notifications, 1);
    expect(chat.entries.last.text, 'hello');

    await controller.close();
    await consumed;
  });

  test('structural events notify immediately, not on the delta timer',
      () async {
    var notifications = 0;
    chat.addListener(() => notifications++);

    final controller = StreamController<AgentUiEvent>();
    final consumed = chat.consumeEventsForTest(controller.stream);
    controller.add(AgentTextDelta('thinking...'));
    controller.add(
      AgentToolStarted(
        const ChatToolCall(id: 'c1', name: 'echo', argumentsJson: '{}'),
      ),
    );
    await Future<void>.delayed(Duration.zero);
    // The tool card must appear the moment the call starts — it flushes the
    // pending delta along with it instead of waiting out the timer.
    expect(notifications, greaterThanOrEqualTo(1));
    expect(chat.entries.last.toolName, 'echo');

    await controller.close();
    await consumed;
  });
}
