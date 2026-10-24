import 'package:dataset_training_tool/models/llm_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('per-model protocol and effort survive storage and resolution', () {
    for (final kind in LlmApiKind.values) {
      final p = LlmProvider(
        id: 'p',
        name: 'p',
        models: [
          LlmModelConfig(
            id: 'm',
            modelId: 'custom',
            protocol: kind,
            effort: LlmEffort.high,
            reasoningDialect: LlmReasoningDialect.standard,
          ),
        ],
      );
      final restored = decodeLlmProviders(encodeLlmProviders([p])).single;
      final resolved = restored.resolve(restored.models.single);
      expect(resolved.kind, kind);
      expect(resolved.effort, LlmEffort.high);
      expect(resolved.reasoningDialect, LlmReasoningDialect.standard);
      expect(
        restored.models.single.copyWith(displayName: 'renamed').protocol,
        kind,
      );
    }
  });
  test('legacy configs inherit protocol and omit effort', () {
    final p = LlmProvider.fromLegacyJson({
      'id': 'p',
      'kind': 'anthropic',
      'model': 'claude-opus-4-6',
      'temperature': .8,
    });
    expect(p.models.single.protocol, isNull);
    expect(p.resolve(p.models.single).kind, LlmApiKind.anthropic);
    expect(p.models.single.effort, LlmEffort.defaultValue);
  });
  test('DeepSeek off and Qwen effort have distinct wire shapes', () {
    Map<String, dynamic> body(String model, LlmEffort effort) =>
        reasoningParameters(
          effort: effort,
          dialect: LlmReasoningDialect.automatic,
          model: model,
          anthropic: false,
        );
    expect(body('deepseek-v4-flash', LlmEffort.off), {
      'thinking': {'type': 'disabled'},
    });
    expect(body('qwen3.8-max', LlmEffort.xhigh), {
      'enable_thinking': true,
      'reasoning_effort': 'xhigh',
    });
    expect(body('qwen3.8-27b', LlmEffort.off), {'enable_thinking': false});
    expect(body('gpt-5.6-sol', LlmEffort.defaultValue), isEmpty);
    expect(() => body('qwen3.8-flash', LlmEffort.high), throwsArgumentError);
    expect(() => body('gpt-6.1-sol', LlmEffort.off), throwsArgumentError);
  });
  test('Claude effort menus account for 4.6 versus newer versions', () {
    for (final model in ['claude-opus-4-6', 'claude-sonnet-4-6']) {
      expect(
        availableEfforts(LlmReasoningDialect.adaptive, model),
        isNot(contains(LlmEffort.xhigh)),
      );
    }
    for (final model in [
      'claude-opus-4-7',
      'claude-opus-4-8',
      'claude-opus-5',
      'claude-opus-5-5',
      'claude-sonnet-5',
      'claude-sonnet-5-5',
      'claude-fable-5',
      'claude-fable-5-1',
    ]) {
      expect(
        availableEfforts(LlmReasoningDialect.adaptive, model),
        contains(LlmEffort.xhigh),
      );
    }
  });
}
