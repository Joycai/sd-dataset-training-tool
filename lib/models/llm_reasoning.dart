/// Parameter shapes are explicit per endpoint/model, including relay overrides.
enum LlmReasoningDialect {
  automatic,
  standard,
  deepseek,
  qwen,
  adaptive,
  disabled,
}

enum LlmEffort { defaultValue, off, low, medium, high, xhigh, max }

T enumByName<T extends Enum>(List<T> values, Object? name, T fallback) =>
    values.where((v) => v.name == name).firstOrNull ?? fallback;

/// Known IDs only supply defaults. An explicit declaration always wins.
LlmReasoningDialect resolveReasoningDialect(
  LlmReasoningDialect declared,
  String model, {
  required bool anthropic,
}) {
  if (declared != LlmReasoningDialect.automatic) return declared;
  if (anthropic) return LlmReasoningDialect.adaptive;
  final id = model.toLowerCase();
  if (id.startsWith('deepseek-')) return LlmReasoningDialect.deepseek;
  if (id.startsWith('qwen3.8-')) return LlmReasoningDialect.qwen;
  return LlmReasoningDialect.standard;
}

List<LlmEffort> availableEfforts(LlmReasoningDialect dialect, String model) {
  const base = [
    LlmEffort.defaultValue,
    LlmEffort.low,
    LlmEffort.medium,
    LlmEffort.high,
    LlmEffort.xhigh,
    LlmEffort.max,
  ];
  if (dialect == LlmReasoningDialect.disabled) return [LlmEffort.defaultValue];
  if (dialect == LlmReasoningDialect.deepseek) {
    return [
      LlmEffort.defaultValue,
      LlmEffort.off,
      LlmEffort.low,
      LlmEffort.high,
      LlmEffort.max,
    ];
  }
  if (dialect == LlmReasoningDialect.qwen) {
    return [
      LlmEffort.defaultValue,
      LlmEffort.off,
      LlmEffort.low,
      LlmEffort.medium,
      LlmEffort.xhigh,
    ];
  }
  if (dialect == LlmReasoningDialect.adaptive) {
    final id = model.replaceAll('.', '-');
    return [
      for (final e in base)
        if (e != LlmEffort.xhigh || !id.contains('4-6')) e,
    ];
  }
  if (model.contains('gpt-6-astra') || model.contains('gpt-6.1')) return base;
  return [LlmEffort.defaultValue, LlmEffort.off, ...base.skip(1)];
}

Map<String, dynamic> reasoningParameters({
  required LlmEffort effort,
  required LlmReasoningDialect dialect,
  required String model,
  required bool anthropic,
  bool responses = false,
}) {
  final resolved = resolveReasoningDialect(
    dialect,
    model,
    anthropic: anthropic,
  );
  if (!availableEfforts(resolved, model).contains(effort)) {
    throw ArgumentError(
      'Unsupported effort ${effort.name} for $model / ${resolved.name}',
    );
  }
  if (resolved == LlmReasoningDialect.disabled) return {};
  if (anthropic) {
    if (resolved != LlmReasoningDialect.adaptive) {
      throw ArgumentError('Use adaptive reasoning with the Messages protocol.');
    }
    return {
      'thinking': {'type': 'adaptive', 'display': 'summarized'},
      if (effort != LlmEffort.defaultValue)
        'output_config': {'effort': effort.name},
    };
  }
  if (effort == LlmEffort.defaultValue) return {};
  if (responses) {
    return {
      'reasoning': {'effort': effort == LlmEffort.off ? 'none' : effort.name},
    };
  }
  if (resolved == LlmReasoningDialect.deepseek) {
    return {
      'thinking': {'type': effort == LlmEffort.off ? 'disabled' : 'enabled'},
      if (effort != LlmEffort.off) 'reasoning_effort': effort.name,
    };
  }
  if (resolved == LlmReasoningDialect.qwen) {
    return {
      'enable_thinking': effort != LlmEffort.off,
      if (effort != LlmEffort.off) 'reasoning_effort': effort.name,
    };
  }
  return {'reasoning_effort': effort == LlmEffort.off ? 'none' : effort.name};
}
