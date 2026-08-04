import 'dart:typed_data';

import 'package:dataset_training_tool/models/llm_models.dart';
import 'package:dataset_training_tool/services/agent/context_budget.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('estimateText', () {
    test('ascii is ~4 chars per token', () {
      expect(ContextBudget.estimateText('a' * 400), 100);
    });

    test('cjk is ~1.7 chars per token', () {
      expect(ContextBudget.estimateText('汉' * 17), 10);
    });

    test('mixed text sums both scales', () {
      final tokens = ContextBudget.estimateText('abcd汉汉');
      expect(tokens, 1 + 2); // 4 ascii → 1, 2 cjk → ceil(2/1.7)=2
    });
  });

  group('estimate', () {
    test('counts images at the flat rate', () {
      final budget = ContextBudget(contextWindow: 32768, maxOutputTokens: 4096);
      final history = [
        ChatMessage(
          role: ChatRole.user,
          parts: [ChatContentPart.image(Uint8List(10))],
        ),
      ];
      // 4 overhead + 1600 image, ×1.1
      expect(budget.estimate(history), ((4 + 1600) * 1.1).ceil());
    });
  });

  group('inputBudget', () {
    test('tool schemas come off the top of the window', () {
      const window = 32768;
      const output = 4096;
      final without = ContextBudget(
        contextWindow: window,
        maxOutputTokens: output,
      );
      final with_ = ContextBudget(
        contextWindow: window,
        maxOutputTokens: output,
        toolSchemaTokens: 9000,
      );
      expect(without.inputBudget - with_.inputBudget, 9000);
      // The whole point: a registry this size is a quarter of the window, and
      // the old budget could not see a token of it.
      expect(with_.inputBudget, window - output - 9000 - 1024);
    });

    test('a registry bigger than the window still leaves a floor', () {
      final budget = ContextBudget(
        contextWindow: 8192,
        maxOutputTokens: 4096,
        toolSchemaTokens: 9000,
      );
      expect(budget.inputBudget, 1024);
    });
  });

  group('compact', () {
    ChatMessage tool(String text, String id) =>
        ChatMessage.toolResult(toolCallId: id, text: text);

    test('does nothing when under budget', () {
      final budget = ContextBudget(
        contextWindow: 200000,
        maxOutputTokens: 4096,
      );
      final history = [ChatMessage.system('sys'), ChatMessage.user('hello')];
      budget.compact(history);
      expect(history[1].text, 'hello');
    });

    test('folds old tool results first, keeps structure', () {
      // Tiny window forces folding. safetyMargin floor keeps inputBudget
      // at the 1024 clamp.
      final budget = ContextBudget(
        contextWindow: 2048,
        maxOutputTokens: 512,
        protectedTail: 2,
      );
      final bigTool = 'x' * 8000;
      final history = [
        ChatMessage.system('sys'),
        ChatMessage.user('question'),
        ChatMessage.assistant(
          '',
          toolCalls: const [
            ChatToolCall(id: '1', name: 't', argumentsJson: '{}'),
          ],
        ),
        tool(bigTool, '1'),
        ChatMessage.assistant('answer part'),
        ChatMessage.user('follow-up'),
        ChatMessage.assistant('final'),
      ];
      budget.compact(history);
      // Tool result folded to a small placeholder.
      expect(history[3].text, startsWith('[elided tool result'));
      // Structure preserved: role and toolCallId untouched.
      expect(history[3].role, ChatRole.tool);
      expect(history[3].toolCallId, '1');
      // System and the protected tail stay intact.
      expect(history[0].text, 'sys');
      expect(history[5].text, 'follow-up');
      expect(history[6].text, 'final');
    });

    test('pinned tool results outlive unpinned ones', () {
      final budget = ContextBudget(
        contextWindow: 2048,
        maxOutputTokens: 512,
        protectedTail: 2,
      );
      final history = [
        ChatMessage.system('sys'),
        ChatMessage.user('question'),
        // The captions the model is rewriting from, read first and needed
        // longest.
        ChatMessage.toolResult(toolCallId: '1', text: 'c' * 3000, pinned: true),
        tool('x' * 8000, '2'),
        ChatMessage.assistant('progress'),
        ChatMessage.assistant('final'),
      ];
      budget.compact(history);
      expect(history[3].text, startsWith('[elided tool result'));
      expect(history[2].text, 'c' * 3000);
    });

    test('pinned tool results still fold as a last resort', () {
      final budget = ContextBudget(
        contextWindow: 1,
        maxOutputTokens: 1,
        protectedTail: 1,
      );
      final history = [
        ChatMessage.system('sys'),
        ChatMessage.toolResult(
          toolCallId: '1',
          text: 'c' * 50000,
          pinned: true,
        ),
        ChatMessage.assistant('tail'),
      ];
      budget.compact(history);
      expect(history[1].text, startsWith('[elided tool result'));
      expect(history[1].toolCallId, '1');
    });

    test('terminates even when everything is folded', () {
      final budget = ContextBudget(
        contextWindow: 1,
        maxOutputTokens: 1,
        protectedTail: 1,
      );
      final history = [
        ChatMessage.system('s' * 50000),
        ChatMessage.user('u' * 50000),
        ChatMessage.assistant('a' * 50000),
        ChatMessage.user('tail'),
      ];
      budget.compact(history); // must not loop forever
      expect(history[1].text, startsWith('[elided'));
      expect(history[2].text, startsWith('[elided'));
      expect(history[3].text, 'tail');
    });
  });
}
