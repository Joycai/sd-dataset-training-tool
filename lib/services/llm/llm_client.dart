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

  /// Registers [listener] and returns its unregistration handle. Callers
  /// with a shorter life than the token (each turn's HTTP client, on a token
  /// spanning a whole run) must call it, or the token accumulates a dead
  /// listener per turn.
  void Function() onCancel(void Function() listener) {
    if (_cancelled) {
      listener();
      return () {};
    }
    _listeners.add(listener);
    return () => _listeners.remove(listener);
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

/// One probe request's outcome, kept structured.
///
/// [LlmClient.probe] flattens everything into a message, which is right for a
/// connection test and useless for capability detection: telling a context
/// limit apart from a rate limit needs the status code and the provider's own
/// error code, not a sentence.
class ProbeResponse {
  const ProbeResponse({
    required this.statusCode,
    this.errorCode = '',
    this.message = '',
    this.usage,
  });

  /// HTTP status, or 0 when the request never got a reply (in which case
  /// [message] carries the transport error).
  final int statusCode;

  /// The provider's machine-readable code (`context_length_exceeded`…), empty
  /// when the response carried none.
  final String errorCode;

  /// Error text on failure, truncated. Empty on success.
  final String message;

  /// Token accounting the server reported, when it reported any.
  final TokenUsage? usage;

  /// A usable response, which is not the same as a 2xx: relays are known to
  /// answer 200 with an error object in the body, and treating that as a
  /// success would read "the server accepted it" out of a refusal.
  bool get ok => statusCode >= 200 && statusCode < 300 && message.isEmpty;
}

/// The non-chat surface capability detection needs. Kept separate from
/// [LlmClient] so implementing a chat client — in a test double, say — does
/// not oblige anyone to implement endpoint inspection.
abstract class LlmEndpointInspector {
  /// Sends one deliberately small, non-streaming request and reports what
  /// came back, including failures. Never throws for an HTTP or transport
  /// error — those are the result.
  Future<ProbeResponse> sendProbe(
    LlmProviderProfile profile, {
    required List<ChatMessage> messages,
    required int maxTokens,
    Duration? timeout,
  });

  /// `GET /models` as whole objects rather than just ids, because the
  /// per-model metadata (`context_length`, `max_model_len`, …) is exactly
  /// what gets thrown away by an id-only listing.
  Future<List<Map<String, dynamic>>> listModelsDetailed(
    LlmProviderProfile profile,
  );
}
