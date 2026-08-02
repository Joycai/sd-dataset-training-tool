import 'dart:convert';

import 'package:dataset_training_tool/models/llm_models.dart';
import 'package:dataset_training_tool/services/agent/agent_session.dart';
import 'package:dataset_training_tool/services/agent/agent_tools.dart';
import 'package:dataset_training_tool/services/llm/llm_client.dart';
import 'package:flutter_test/flutter_test.dart';

/// Scripted client: replays one canned event list per chat() call.
class FakeLlmClient implements LlmClient {
  FakeLlmClient(this.turns);

  final List<List<LlmStreamEvent>> turns;
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
    return Stream.fromIterable(turn);
  }

  @override
  Future<String?> probe(LlmProviderProfile profile) async => null;

  @override
  Future<List<String>> listModels(LlmProviderProfile profile) async => const [];

  @override
  void dispose() {}
}

const _profile = LlmProviderProfile(
  id: 'p1',
  name: 'fake',
  model: 'fake-model',
);

AgentTool _echoTool() => AgentTool(
  spec: const AgentToolSpec(
    name: 'echo',
    description: 'echoes',
    parametersSchema: {'type': 'object', 'properties': {}},
  ),
  handler: (args) async => toolOk({'echo': args['v']}),
);

AgentTool _writeTool() => AgentTool(
  spec: const AgentToolSpec(
    name: 'write',
    description: 'writes something',
    parametersSchema: {'type': 'object', 'properties': {}},
  ),
  isWrite: true,
  handler: (args) async => toolOk({'wrote': true}),
);

void main() {
  test('text-only turn completes and records history', () async {
    final client = FakeLlmClient([
      [TextDelta('hi '), TextDelta('there'), StreamDone(finishReason: 'stop')],
    ]);
    final session = AgentSession(
      client: client,
      registry: ToolRegistry([_echoTool()]),
      profile: _profile,
      systemPrompt: 'sys',
    );

    final events = await session.run('hello').toList();
    expect(events.whereType<AgentTextDelta>().length, 2);
    final done = events.last as AgentFinished;
    expect(done.reason, AgentStopReason.completed);
    // system + user + assistant
    expect(session.history.length, 3);
    expect(session.history.last.text, 'hi there');
  });

  test(
    'tool call round-trip: result lands in history, loop continues',
    () async {
      final client = FakeLlmClient([
        [
          ToolCallsReady([
            const ChatToolCall(
              id: 'c1',
              name: 'echo',
              argumentsJson: '{"v": 42}',
            ),
          ]),
          StreamDone(finishReason: 'tool_calls'),
        ],
        [TextDelta('done'), StreamDone(finishReason: 'stop')],
      ]);
      final session = AgentSession(
        client: client,
        registry: ToolRegistry([_echoTool()]),
        profile: _profile,
        systemPrompt: 'sys',
      );

      final events = await session.run('run the tool').toList();
      expect(events.whereType<AgentToolStarted>().length, 1);
      final finished = events.whereType<AgentToolFinished>().single;
      expect(jsonDecode(finished.result.text), {'echo': 42});

      // system, user, assistant(toolCalls), tool result, assistant text
      expect(session.history.length, 5);
      expect(session.history[3].role, ChatRole.tool);
      expect(session.history[3].toolCallId, 'c1');
      // The second model call saw the tool result.
      expect(
        client.seenMessages[1].any((m) => m.role == ChatRole.tool),
        isTrue,
      );
    },
  );

  test('three consecutive tool errors abort the run', () async {
    List<LlmStreamEvent> badCall(String id) => [
      ToolCallsReady([ChatToolCall(id: id, name: 'nope', argumentsJson: '{}')]),
      StreamDone(finishReason: 'tool_calls'),
    ];
    final client = FakeLlmClient([
      badCall('1'),
      badCall('2'),
      badCall('3'),
      [TextDelta('never'), StreamDone(finishReason: 'stop')],
    ]);
    final session = AgentSession(
      client: client,
      registry: ToolRegistry([_echoTool()]),
      profile: _profile,
      systemPrompt: 'sys',
    );

    final events = await session.run('go').toList();
    final done = events.last as AgentFinished;
    expect(done.reason, AgentStopReason.error);
    expect(client.calls, 3);
  });

  test(
    'three consecutive write rejections do not abort the run as an error',
    () async {
      // The user exercising the confirmation gate is not the same thing as
      // the model failing three times in a row — rejecting a write must not
      // read back as "stopped after 3 consecutive tool errors".
      List<LlmStreamEvent> writeCall(String id) => [
        ToolCallsReady([
          ChatToolCall(id: id, name: 'write', argumentsJson: '{}'),
        ]),
        StreamDone(finishReason: 'tool_calls'),
      ];
      final client = FakeLlmClient([
        writeCall('1'),
        writeCall('2'),
        writeCall('3'),
        [TextDelta('ok, I will stop asking'), StreamDone(finishReason: 'stop')],
      ]);
      final session = AgentSession(
        client: client,
        registry: ToolRegistry([_writeTool()]),
        profile: _profile,
        systemPrompt: 'sys',
        confirmWrite: (_, _) async => false,
      );

      final events = await session.run('go').toList();
      final finishedResults = events
          .whereType<AgentToolFinished>()
          .map((e) => e.result)
          .toList();
      expect(finishedResults, hasLength(3));
      expect(finishedResults.every((r) => r.isError), isTrue);
      final done = events.last as AgentFinished;
      expect(done.reason, AgentStopReason.completed);
      expect(client.calls, 4);
    },
  );

  test('maxTurns caps a model that never stops calling tools', () async {
    final client = FakeLlmClient([
      [
        ToolCallsReady([
          const ChatToolCall(id: 'c', name: 'echo', argumentsJson: '{"v":1}'),
        ]),
        StreamDone(finishReason: 'tool_calls'),
      ],
    ]);
    final session = AgentSession(
      client: client,
      registry: ToolRegistry([_echoTool()]),
      profile: _profile,
      systemPrompt: 'sys',
      maxTurnsPerRun: 4,
    );

    final events = await session.run('loop').toList();
    final done = events.last as AgentFinished;
    expect(done.reason, AgentStopReason.maxTurns);
    expect(client.calls, 4);
  });

  test(
    'the turn limit asks before stopping, and stops when declined',
    () async {
      final client = FakeLlmClient([
        [
          ToolCallsReady([
            const ChatToolCall(id: 'c', name: 'echo', argumentsJson: '{"v":1}'),
          ]),
          StreamDone(finishReason: 'tool_calls'),
        ],
      ]);
      final asked = <int>[];
      final session = AgentSession(
        client: client,
        registry: ToolRegistry([_echoTool()]),
        profile: _profile,
        systemPrompt: 'sys',
        maxTurnsPerRun: 4,
        confirmContinue: (turns) async {
          asked.add(turns);
          return null; // "stop here"
        },
      );

      final events = await session.run('loop').toList();
      expect(asked, [4]);
      expect((events.last as AgentFinished).reason, AgentStopReason.maxTurns);
      expect(client.calls, 4);
    },
  );

  test('continuing grants another budget of turns', () async {
    final client = FakeLlmClient([
      [
        ToolCallsReady([
          const ChatToolCall(id: 'c', name: 'echo', argumentsJson: '{"v":1}'),
        ]),
        StreamDone(finishReason: 'tool_calls'),
      ],
    ]);
    final asked = <int>[];
    final session = AgentSession(
      client: client,
      registry: ToolRegistry([_echoTool()]),
      profile: _profile,
      systemPrompt: 'sys',
      maxTurnsPerRun: 3,
      // Continue once, then stop — an unbounded "yes" would never end.
      confirmContinue: (turns) async {
        asked.add(turns);
        return asked.length == 1 ? const AgentContinueDecision() : null;
      },
    );

    final events = await session.run('loop').toList();
    expect(asked, [3, 6]);
    expect((events.last as AgentFinished).reason, AgentStopReason.maxTurns);
    expect(client.calls, 6);
  });

  test('a note typed on the continue card reaches the model', () async {
    final client = FakeLlmClient([
      [
        ToolCallsReady([
          const ChatToolCall(id: 'c', name: 'echo', argumentsJson: '{"v":1}'),
        ]),
        StreamDone(finishReason: 'tool_calls'),
      ],
    ]);
    var first = true;
    final session = AgentSession(
      client: client,
      registry: ToolRegistry([_echoTool()]),
      profile: _profile,
      systemPrompt: 'sys',
      maxTurnsPerRun: 2,
      confirmContinue: (_) async {
        if (!first) return null;
        first = false;
        return const AgentContinueDecision(note: 'skip the ones already done');
      },
    );

    await session.run('loop').toList();
    // The note is a user message in the history, and the model call made
    // right after the limit saw it.
    expect(
      session.history.any(
        (m) =>
            m.role == ChatRole.user && m.text == 'skip the ones already done',
      ),
      isTrue,
    );
    expect(client.seenMessages[2].last.text, 'skip the ones already done');
  });

  test('session token cap stops before the next model call', () async {
    final client = FakeLlmClient([
      [
        TextDelta('big'),
        StreamDone(
          finishReason: 'stop',
          usage: const TokenUsage(prompt: 900, completion: 200),
        ),
      ],
    ]);
    final session = AgentSession(
      client: client,
      registry: ToolRegistry([_echoTool()]),
      profile: _profile,
      systemPrompt: 'sys',
      sessionTokenCap: 1000,
    );

    await session.run('one').toList();
    expect(session.totalUsage.total, 1100);
    final events = await session.run('two').toList();
    final done = events.last as AgentFinished;
    expect(done.reason, AgentStopReason.tokenCap);
    expect(client.calls, 1); // second run never reached the model
  });

  test('a cap of 0 never stops the conversation', () async {
    final client = FakeLlmClient([
      for (var i = 0; i < 2; i++)
        [
          TextDelta('big'),
          StreamDone(
            finishReason: 'stop',
            usage: const TokenUsage(prompt: 900, completion: 200),
          ),
        ],
    ]);
    final session = AgentSession(
      client: client,
      registry: ToolRegistry([_echoTool()]),
      profile: _profile,
      systemPrompt: 'sys',
      sessionTokenCap: 0,
    );

    await session.run('one').toList();
    final events = await session.run('two').toList();
    expect((events.last as AgentFinished).reason, AgentStopReason.completed);
    expect(client.calls, 2);
  });
}
