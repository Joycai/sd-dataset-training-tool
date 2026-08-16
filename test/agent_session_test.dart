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
  test('the session budget subtracts the registry it was built with', () {
    // A big schema stands in for the real registry (a few thousand tokens).
    final fat = AgentTool(
      spec: AgentToolSpec(
        name: 'fat',
        description: 'x' * 4000,
        parametersSchema: const {'type': 'object', 'properties': {}},
      ),
      handler: (args) async => toolOk(const {}),
    );
    final lean = ToolRegistry([_echoTool()]);
    final heavy = ToolRegistry([_echoTool(), fat]);
    expect(heavy.schemaTokens - lean.schemaTokens, greaterThan(900));

    AgentSession session(ToolRegistry registry) => AgentSession(
      client: FakeLlmClient(const []),
      registry: registry,
      profile: _profile,
      systemPrompt: 'sys',
    );
    // Schemas are re-sent every turn but never appear in the history, so the
    // only place they can be accounted for is the budget's ceiling.
    expect(
      session(lean).budget.inputBudget - session(heavy).budget.inputBudget,
      heavy.schemaTokens - lean.schemaTokens,
    );
  });

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
    // 4 working turns + the tool-less wind-down summary.
    expect(client.calls, 5);
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
      // 4 working turns + the tool-less wind-down summary.
      expect(client.calls, 5);
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
    // 6 working turns + the tool-less wind-down summary.
    expect(client.calls, 7);
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

  test('a prose turn cut off by the output limit is flagged', () async {
    final client = FakeLlmClient([
      [TextDelta('half an ans'), StreamDone(finishReason: 'length')],
    ]);
    final session = AgentSession(
      client: client,
      registry: ToolRegistry([_echoTool()]),
      profile: _profile,
      systemPrompt: 'sys',
    );

    final events = await session.run('go').toList();
    expect(events.whereType<AgentOutputTruncated>(), hasLength(1));
    // Still an answer, just a marked one.
    expect((events.last as AgentFinished).reason, AgentStopReason.completed);
  });

  test('anthropic max_tokens counts as truncation too', () async {
    final client = FakeLlmClient([
      [TextDelta('half'), StreamDone(finishReason: 'max_tokens')],
    ]);
    final session = AgentSession(
      client: client,
      registry: ToolRegistry([_echoTool()]),
      profile: _profile,
      systemPrompt: 'sys',
    );

    final events = await session.run('go').toList();
    expect(events.whereType<AgentOutputTruncated>(), hasLength(1));
  });

  test('a truncated tool call names the budget, not bad JSON', () async {
    final client = FakeLlmClient([
      [
        // Arguments cut mid-string by the output limit.
        ToolCallsReady(const [
          ChatToolCall(id: 'c1', name: 'echo', argumentsJson: '{"v": "trun'),
        ]),
        StreamDone(finishReason: 'length'),
      ],
      [TextDelta('recovered'), StreamDone(finishReason: 'stop')],
    ]);
    final session = AgentSession(
      client: client,
      registry: ToolRegistry([_echoTool()]),
      profile: _profile,
      systemPrompt: 'sys',
    );

    final events = await session.run('go').toList();
    final finished = events.whereType<AgentToolFinished>().single;
    expect(finished.result.isError, isTrue);
    expect(finished.result.text, contains('output token limit'));
    expect(finished.result.text, isNot(contains('invalid JSON')));
    // The result message still pairs with the call.
    final toolMsg = session.history.firstWhere(
      (m) => m.role == ChatRole.tool,
    );
    expect(toolMsg.toolCallId, 'c1');
  });

  test('truncated calls do not feed the 3-strikes abort', () async {
    final client = FakeLlmClient([
      for (var i = 0; i < 4; i++)
        [
          ToolCallsReady([
            ChatToolCall(id: 'c$i', name: 'echo', argumentsJson: '{"v": "cut'),
          ]),
          StreamDone(finishReason: 'length'),
        ],
      [TextDelta('done'), StreamDone(finishReason: 'stop')],
    ]);
    final session = AgentSession(
      client: client,
      registry: ToolRegistry([_echoTool()]),
      profile: _profile,
      systemPrompt: 'sys',
    );

    final events = await session.run('go').toList();
    // Four truncated calls in a row and the run still reaches the answer.
    expect((events.last as AgentFinished).reason, AgentStopReason.completed);
    expect(client.calls, 5);
  });

  test(
    'a silently-truncating endpoint stops instead of sending over-long',
    () async {
      final client = FakeLlmClient([
        [TextDelta('never'), StreamDone(finishReason: 'stop')],
      ]);
      final session = AgentSession(
        client: client,
        registry: ToolRegistry([_echoTool()]),
        // Window so small even the seed does not fit once folded.
        profile: _profile.copyWith(
          contextWindow: 1,
          maxOutputTokens: 1,
          silentTruncation: true,
        ),
        systemPrompt: 'sys ${'x' * 40000}',
      );

      final events = await session.run('u ${'y' * 40000}').toList();
      final done = events.last as AgentFinished;
      expect(done.reason, AgentStopReason.error);
      expect(done.message, contains('truncate'));
      expect(client.calls, 0); // the doomed request never went out
      expect(
        events.whereType<AgentContextCompacted>().single.stillOverBudget,
        isTrue,
      );
    },
  );

  test('stopping at the limit still yields a wind-down summary', () async {
    final client = FakeLlmClient([
      [
        ToolCallsReady([
          const ChatToolCall(id: 'c', name: 'echo', argumentsJson: '{"v":1}'),
        ]),
        StreamDone(finishReason: 'tool_calls'),
      ],
      [TextDelta('tagged 3 of 9; the rest remain'), StreamDone()],
    ]);
    final session = AgentSession(
      client: client,
      registry: ToolRegistry([_echoTool()]),
      profile: _profile,
      systemPrompt: 'sys',
      maxTurnsPerRun: 1,
      confirmContinue: (_) async => null, // "stop here"
    );

    final events = await session.run('sweep').toList();
    expect((events.last as AgentFinished).reason, AgentStopReason.maxTurns);
    // The summary streamed to the transcript and entered history…
    expect(
      events.whereType<AgentTextDelta>().map((e) => e.text).join(),
      contains('the rest remain'),
    );
    expect(session.history.last.text, contains('the rest remain'));
    // …but its one-shot instruction was withdrawn: nothing in history tells
    // the model "do not call tools" forever after.
    expect(
      session.history.any((m) => m.text.contains('Do not call tools')),
      isFalse,
    );
  });

  test('an empty turn ends retryable with clean history', () async {
    final client = FakeLlmClient([
      [StreamDone(finishReason: 'length')], // all budget spent thinking
      [TextDelta('recovered'), StreamDone(finishReason: 'stop')],
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
    expect(done.message, contains('output budget'));
    expect(done.retryable, isTrue);
    // The empty turn never reached history…
    expect(session.history.last.role, ChatRole.user);
    // …so resume re-sends the same request and can succeed.
    final retried = await session.resume().toList();
    expect((retried.last as AgentFinished).reason, AgentStopReason.completed);
  });

  test('reasoning deltas pass through without touching history', () async {
    final client = FakeLlmClient([
      [
        ReasoningDelta('hmm, tags first'),
        TextDelta('answer'),
        StreamDone(finishReason: 'stop'),
      ],
    ]);
    final session = AgentSession(
      client: client,
      registry: ToolRegistry([_echoTool()]),
      profile: _profile,
      systemPrompt: 'sys',
    );

    final events = await session.run('go').toList();
    expect(
      events.whereType<AgentReasoningDelta>().map((e) => e.text).join(),
      'hmm, tags first',
    );
    // Thinking is display-only: the history carries only the answer.
    expect(session.history.last.text, 'answer');
  });

  test('the measured window caps a silently-truncating endpoint', () {
    AgentSession session(LlmProviderProfile profile) => AgentSession(
      client: FakeLlmClient(const []),
      registry: ToolRegistry(const []),
      profile: profile,
      systemPrompt: 'sys',
    );
    final declared = session(_profile.copyWith(contextWindow: 32768));
    // Measured-but-clean endpoints keep the user's value: detection
    // proposes, only the user applies.
    final clean = session(
      _profile.copyWith(contextWindow: 32768, measuredContextWindow: 8000),
    );
    expect(clean.budget.inputBudget, declared.budget.inputBudget);
    // A silently-truncating endpoint budgets against the measurement.
    final lying = session(
      _profile.copyWith(
        contextWindow: 32768,
        measuredContextWindow: 8000,
        silentTruncation: true,
      ),
    );
    expect(
      declared.budget.inputBudget - lying.budget.inputBudget,
      32768 - 8000,
    );
    // A measurement larger than the declared window never widens it.
    final wider = session(
      _profile.copyWith(
        contextWindow: 32768,
        measuredContextWindow: 64000,
        silentTruncation: true,
      ),
    );
    expect(wider.budget.inputBudget, declared.budget.inputBudget);
  });
}
