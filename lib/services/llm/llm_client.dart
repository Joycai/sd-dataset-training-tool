/// The protocol-neutral LLM client interface. Pure Dart.
library;

import '../../models/llm_models.dart';

/// Raised on transport failure or a non-2xx API response. [message] is safe
/// to show to the user — implementations must never include the API key.
class LlmException implements Exception {
  LlmException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Cooperative cancellation for a streaming chat call. [cancel] closes the
/// underlying connection; the stream then ends with an [LlmException].
class CancellationToken {
  bool _cancelled = false;
  final List<void Function()> _listeners = [];

  bool get isCancelled => _cancelled;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final l in List.of(_listeners)) {
      l();
    }
  }

  void onCancel(void Function() listener) {
    if (_cancelled) {
      listener();
    } else {
      _listeners.add(listener);
    }
  }
}

abstract class LlmClient {
  /// Sends one model turn and streams back deltas.
  ///
  /// Event order: zero or more [TextDelta], then an optional
  /// [ToolCallsReady] (with fully accumulated arguments), then exactly one
  /// [StreamDone]. Transport/API errors surface as [LlmException]; a
  /// cancelled call may end without [StreamDone].
  Stream<LlmStreamEvent> chat({
    required LlmProviderProfile profile,
    required List<ChatMessage> messages,
    List<AgentToolSpec> tools = const [],
    CancellationToken? cancel,
  });

  /// Connection test: sends a minimal request. Returns null on success or a
  /// human-readable error description.
  Future<String?> probe(LlmProviderProfile profile);

  /// Model ids the server advertises (`GET /models`), sorted alphabetically.
  /// Throws [LlmException] on failure.
  Future<List<String>> listModels(LlmProviderProfile profile);

  /// Releases underlying HTTP resources.
  void dispose();
}
