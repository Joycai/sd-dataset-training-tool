import '../../models/llm_models.dart';
import 'anthropic_client.dart';
import 'gemini_client.dart';
import 'llm_client.dart';
import 'openai_compat_client.dart';
import 'responses_client.dart';

LlmClient createLlmClient(
  LlmApiKind kind, {
  Duration idleTimeout = const Duration(seconds: 120),
}) => switch (kind) {
  LlmApiKind.openaiCompat => OpenAiCompatClient(idleTimeout: idleTimeout),
  LlmApiKind.responses => ResponsesClient(idleTimeout: idleTimeout),
  LlmApiKind.anthropic => AnthropicClient(idleTimeout: idleTimeout),
  LlmApiKind.gemini => GeminiClient(idleTimeout: idleTimeout),
};
