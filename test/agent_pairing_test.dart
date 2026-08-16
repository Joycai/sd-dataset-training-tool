/// The tool-call pairing invariant: every tool_call in history gets exactly
/// one paired result, whatever happens — a history with an unpaired call is
/// rejected by every provider on every later turn, permanently.
library;

import 'dart:async';

import 'package:dataset_training_tool/models/llm_models.dart';
import 'package:dataset_training_tool/services/agent/agent_session.dart';
import 'package:dataset_training_tool/services/agent/agent_tools.dart';
import 'package:dataset_training_tool/services/llm/llm_client.dart';
import 'package:flutter_test/flutter_test.dart';

/// Asserts every assistant tool_call in [history] has a following tool
/// result with its id.
void expectPaired(List<ChatMessage> history) {
  for (var i = 0; i < history.length; i++) {
    final m = history[i];
    if (m.role != ChatRole.assistant || m.toolCalls.isEmpty) continue;
    final answered = <String?>{};
    var j = i + 1;
    while (j < history.length && history[j].role == ChatRole.tool) {
      answered.add(history[j].toolCallId);
      j++;
    }
    for (final call in m.toolCalls) {
      expect(
        answered,
        contains(call.id),
        reason: 'tool_call ${call.id} at history[$i] has no paired result',
      );
    }
  }
}

ChatMessage _assistantCalls(List<String> ids) => ChatMessage.assistant(
  '',
  toolCalls: [
    for (final id in ids)
      ChatToolCall(id: id, name: 't', argumentsJson: '{}'),
  ],
);

void main() {
  group('repairToolCallPairing', () {
    test('a fully paired history is left untouched', () {
      final history = [
        ChatMessage.system('sys'),
        ChatMessage.user('go'),
        _assistantCalls(['a', 'b']),
        ChatMessage.toolResult(toolCallId: 'a', text: 'ok'),
        ChatMessage.toolResult(toolCallId: 'b', text: 'ok'),
        ChatMessage.assistant('done'),
      ];
      final before = history.length;
      expect(repairToolCallPairing(history), 0);
      expect(history.length, before);
    });

    test('missing results get stubs in call order, in place', () {
      final history = [
        ChatMessage.system('sys'),
        ChatMessage.user('go'),
        _assistantCalls(['a', 'b', 'c']),
        // Only b answered; a and c dropped by some unforeseen path.
        ChatMessage.toolResult(toolCallId: 'b', text: 'ok'),
        ChatMessage.user('and then?'),
        _assistantCalls(['d']),
        // d never answered at the very end of history.
      ];
      expect(repairToolCallPairing(history), 3);
      expectPaired(history);
      // Stubs sit with their round, before the next user message.
      expect(history[4].role, ChatRole.tool);
      expect(history[5].role, ChatRole.tool);
      expect(history[6].role, ChatRole.user);
      expect(history.last.role, ChatRole.tool);
      expect(history.last.text, contains('not run'));
    });
  });

  group('cancellation keeps pairing', () {
    test('cancel between two tool calls still pairs both', () async {
      // A client whose single turn requests two tool calls; the first tool's
      // handler cancels the run, so the second call must be stubbed.
      final client = _OneTurnClient([
        ToolCallsReady(const [
          ChatToolCall(id: 'c1', name: 'stopper', argumentsJson: '{}'),
          ChatToolCall(id: 'c2', name: 'stopper', argumentsJson: '{}'),
        ]),
        StreamDone(finishReason: 'tool_calls'),
      ]);
      late AgentSession session;
      final registry = ToolRegistry([
        AgentTool(
          spec: const AgentToolSpec(
            name: 'stopper',
            description: 'cancels the session mid-round',
            parametersSchema: {'type': 'object', 'properties': {}},
          ),
          handler: (args) async {
            session.stop();
            return toolOk(const {'ok': true});
          },
        ),
      ]);
      session = AgentSession(
        client: client,
        registry: registry,
        profile: const LlmProviderProfile(id: 'p', name: 'f', model: 'm'),
        systemPrompt: 'sys',
      );

      final events = await session.run('go').toList();
      expect((events.last as AgentFinished).reason, AgentStopReason.cancelled);
      expectPaired(session.history);
      // The second call was stubbed, not executed.
      final results = session.history
          .where((m) => m.role == ChatRole.tool)
          .toList();
      expect(results, hasLength(2));
      expect(results.last.toolCallId, 'c2');
      expect(results.last.text, contains('cancelled'));
    });
  });
}

class _OneTurnClient implements LlmClient {
  _OneTurnClient(this.events);

  final List<LlmStreamEvent> events;

  @override
  Stream<LlmStreamEvent> chat({
    required LlmProviderProfile profile,
    required List<ChatMessage> messages,
    List<AgentToolSpec> tools = const [],
    CancellationToken? cancel,
  }) => Stream.fromIterable(events);

  @override
  Future<String?> probe(LlmProviderProfile profile) async => null;

  @override
  Future<List<String>> listModels(LlmProviderProfile profile) async =>
      const [];

  @override
  void dispose() {}
}
