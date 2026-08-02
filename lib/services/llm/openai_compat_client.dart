/// OpenAI-compatible Chat Completions client (streaming + tools + vision).
///
/// Covers OpenAI itself, newapi/one-api style relays, Ollama's `/v1`
/// compatibility layer, and Gemini's OpenAI-compatible endpoint. Pure Dart.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../models/llm_models.dart';
import 'llm_client.dart';
import 'sse.dart';

class OpenAiCompatClient implements LlmClient, LlmEndpointInspector {
  OpenAiCompatClient({
    this.connectTimeout = const Duration(seconds: 30),
    this.idleTimeout = const Duration(seconds: 120),
  });

  /// Timeout for connecting + response headers (first byte).
  final Duration connectTimeout;

  /// Max silence between stream events. Generous: relays queue requests and
  /// Ollama may load a model on first use.
  final Duration idleTimeout;

  Uri _url(LlmProviderProfile profile, String path) {
    var base = profile.baseUrl.trim();
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    return Uri.parse('$base$path');
  }

  Uri _endpoint(LlmProviderProfile profile) =>
      _url(profile, '/chat/completions');

  Map<String, String> _headers(LlmProviderProfile profile) => {
    'Content-Type': 'application/json',
    if (profile.apiKey.isNotEmpty) 'Authorization': 'Bearer ${profile.apiKey}',
  };

  // --- Request building -------------------------------------------------

  Map<String, dynamic> _buildBody(
    LlmProviderProfile profile,
    List<ChatMessage> messages,
    List<AgentToolSpec> tools, {
    required bool stream,
    int? maxTokensOverride,
  }) => {
    'model': profile.model,
    'messages': _convertMessages(messages),
    'stream': stream,
    if (stream) 'stream_options': {'include_usage': true},
    'max_tokens': maxTokensOverride ?? profile.maxOutputTokens,
    'temperature': profile.temperature,
    if (tools.isNotEmpty)
      'tools': [
        for (final t in tools)
          {
            'type': 'function',
            'function': {
              'name': t.name,
              'description': t.description,
              'parameters': t.parametersSchema,
            },
          },
      ],
  };

  List<Map<String, dynamic>> _convertMessages(List<ChatMessage> messages) {
    final out = <Map<String, dynamic>>[];
    for (final m in messages) {
      switch (m.role) {
        case ChatRole.system:
          out.add({'role': 'system', 'content': m.text});
        case ChatRole.user:
          out.add({'role': 'user', 'content': _content(m)});
        case ChatRole.assistant:
          out.add({
            'role': 'assistant',
            // Tool-call turns may carry no text (null is the protocol's
            // shape); a plain empty reply becomes '' for relays that
            // reject null content.
            'content': m.text.isNotEmpty
                ? m.text
                : (m.toolCalls.isEmpty ? '' : null),
            if (m.toolCalls.isNotEmpty)
              'tool_calls': [
                for (final c in m.toolCalls)
                  {
                    'id': c.id,
                    'type': 'function',
                    'function': {'name': c.name, 'arguments': c.argumentsJson},
                  },
              ],
          });
        case ChatRole.tool:
          // The tool role only carries text in this protocol; images from a
          // tool result ride along as a follow-up user message.
          out.add({
            'role': 'tool',
            'tool_call_id': m.toolCallId ?? '',
            'content': m.text,
          });
          if (m.imageCount > 0) {
            out.add({
              'role': 'user',
              'content': [
                {
                  'type': 'text',
                  'text': '[images returned by the previous tool call]',
                },
                ..._imageParts(m),
              ],
            });
          }
      }
    }
    return out;
  }

  Object _content(ChatMessage m) {
    if (m.imageCount == 0) return m.text;
    return [
      for (final p in m.parts)
        if (p.text != null)
          {'type': 'text', 'text': p.text}
        else if (p.isImage)
          _imagePart(p),
    ];
  }

  List<Map<String, dynamic>> _imageParts(ChatMessage m) => [
    for (final p in m.parts.where((p) => p.isImage)) _imagePart(p),
  ];

  Map<String, dynamic> _imagePart(ChatContentPart p) => {
    'type': 'image_url',
    'image_url': {
      'url':
          'data:${p.imageMimeType ?? 'image/jpeg'};base64,'
          '${base64Encode(p.imageBytes!)}',
    },
  };

  /// One-shot compatibility repair for a 4xx response: strips or renames the
  /// parameters the server complained about. Returns null when nothing in
  /// the body matches, meaning a retry would be pointless.
  Map<String, dynamic>? _adjustBody(Map<String, dynamic> body, String error) {
    final e = error.toLowerCase();
    var changed = false;
    final next = Map<String, dynamic>.from(body);
    if (e.contains('max_completion_tokens') && next.containsKey('max_tokens')) {
      next['max_completion_tokens'] = next.remove('max_tokens');
      changed = true;
    }
    if (e.contains('stream_options') && next.containsKey('stream_options')) {
      next.remove('stream_options');
      changed = true;
    }
    if (e.contains('temperature') && next.containsKey('temperature')) {
      next.remove('temperature');
      changed = true;
    }
    return changed ? next : null;
  }

  // --- Transport --------------------------------------------------------

  Future<http.StreamedResponse> _send(
    http.Client client,
    LlmProviderProfile profile,
    Map<String, dynamic> body, {
    Duration? timeout,
  }) async {
    final limit = timeout ?? connectTimeout;
    final request = http.Request('POST', _endpoint(profile))
      ..headers.addAll(_headers(profile))
      ..body = jsonEncode(body);
    try {
      return await client.send(request).timeout(limit);
    } on TimeoutException {
      throw LlmException('Connection timed out after ${limit.inSeconds}s.');
    } on SocketException catch (e) {
      throw LlmException(
        'Cannot reach ${_endpoint(profile).host}: ${e.message}',
      );
    } on http.ClientException catch (e) {
      throw LlmException('HTTP error: ${e.message}');
    }
  }

  Future<String> _readBody(http.StreamedResponse resp) async {
    try {
      return utf8.decode(await resp.stream.toBytes(), allowMalformed: true);
    } catch (_) {
      return '';
    }
  }

  /// Sends [body], transparently retrying once with adjusted parameters when
  /// the server rejects a request shape (see [_adjustBody]).
  Future<http.StreamedResponse> _sendWithRepair(
    http.Client client,
    LlmProviderProfile profile,
    Map<String, dynamic> body,
  ) async {
    var resp = await _send(client, profile, body);
    if (resp.statusCode >= 200 && resp.statusCode < 300) return resp;
    final error = await _readBody(resp);
    if (resp.statusCode >= 400 && resp.statusCode < 500) {
      final adjusted = _adjustBody(body, error);
      if (adjusted != null) {
        resp = await _send(client, profile, adjusted);
        if (resp.statusCode >= 200 && resp.statusCode < 300) return resp;
        throw LlmException(
          'Server returned HTTP ${resp.statusCode}: '
          '${_truncate(await _readBody(resp))}',
        );
      }
    }
    throw LlmException(
      'Server returned HTTP ${resp.statusCode}: ${_truncate(error)}',
    );
  }

  static String _truncate(String s) =>
      s.length <= 600 ? s : '${s.substring(0, 600)}…';

  // --- Streaming chat ---------------------------------------------------

  @override
  Stream<LlmStreamEvent> chat({
    required LlmProviderProfile profile,
    required List<ChatMessage> messages,
    List<AgentToolSpec> tools = const [],
    CancellationToken? cancel,
  }) async* {
    final client = http.Client();
    cancel?.onCancel(client.close);
    try {
      final body = _buildBody(profile, messages, tools, stream: true);
      final resp = await _sendWithRepair(client, profile, body);

      final acc = _ToolCallAccumulator();
      var finishReason = '';
      TokenUsage? usage;

      final events = sseDataEvents(resp.stream).timeout(
        idleTimeout,
        onTimeout: (sink) {
          sink.addError(
            LlmException(
              'Stream stalled: no data for ${idleTimeout.inSeconds}s.',
            ),
          );
          sink.close();
        },
      );

      try {
        await for (final data in events) {
          if (data == '[DONE]') break;
          final Map<String, dynamic> obj;
          try {
            final decoded = jsonDecode(data);
            if (decoded is! Map<String, dynamic>) continue;
            obj = decoded;
          } on FormatException {
            continue;
          }
          final u = obj['usage'];
          if (u is Map<String, dynamic>) {
            usage = TokenUsage(
              prompt: (u['prompt_tokens'] as num?)?.toInt() ?? 0,
              completion: (u['completion_tokens'] as num?)?.toInt() ?? 0,
            );
          }
          final choices = obj['choices'];
          if (choices is! List || choices.isEmpty) continue;
          final choice = choices.first;
          if (choice is! Map<String, dynamic>) continue;
          final reason = choice['finish_reason'];
          if (reason is String && reason.isNotEmpty) finishReason = reason;
          final delta = choice['delta'];
          if (delta is! Map<String, dynamic>) continue;
          final content = delta['content'];
          if (content is String && content.isNotEmpty) {
            yield TextDelta(content);
          }
          final toolCalls = delta['tool_calls'];
          if (toolCalls is List) {
            for (final tc in toolCalls.whereType<Map<String, dynamic>>()) {
              acc.add(tc);
            }
          }
        }
      } on http.ClientException {
        // Closing the client mid-stream (cancel) surfaces here.
        if (cancel?.isCancelled ?? false) return;
        rethrow;
      }

      final calls = acc.build();
      if (calls.isNotEmpty) yield ToolCallsReady(calls);
      yield StreamDone(
        finishReason: finishReason.isEmpty && calls.isNotEmpty
            ? 'tool_calls'
            : finishReason,
        usage: usage,
      );
    } on LlmException {
      if (cancel?.isCancelled ?? false) return;
      rethrow;
    } on SocketException catch (e) {
      if (cancel?.isCancelled ?? false) return;
      throw LlmException('Network error: ${e.message}');
    } finally {
      client.close();
    }
  }

  // --- Probe ------------------------------------------------------------

  @override
  Future<String?> probe(LlmProviderProfile profile) async {
    final client = http.Client();
    try {
      final body = _buildBody(
        profile,
        [ChatMessage.user('Hi')],
        const [],
        stream: false,
        maxTokensOverride: 1,
      )..remove('stream_options');
      final resp = await _sendWithRepair(client, profile, body);
      final text = await _readBody(resp);
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic> && decoded['choices'] is List) {
        return null;
      }
      return 'Unexpected response shape from server.';
    } on LlmException catch (e) {
      return e.message;
    } on FormatException {
      return 'Server did not return JSON.';
    } finally {
      client.close();
    }
  }

  // --- Model discovery --------------------------------------------------

  /// `GET /models` — the standard OpenAI model listing, also served by
  /// newapi/one-api relays, Ollama's compat layer and Gemini's compat
  /// endpoint. Returns the `data[].id` values sorted alphabetically.
  @override
  Future<List<String>> listModels(LlmProviderProfile profile) async {
    final ids =
        (await listModelsDetailed(profile))
            .map((m) => (m['id'] ?? '').toString())
            .where((id) => id.isNotEmpty)
            .toSet()
            .toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return ids;
  }

  @override
  Future<List<Map<String, dynamic>>> listModelsDetailed(
    LlmProviderProfile profile,
  ) async {
    final client = http.Client();
    try {
      final resp = await client
          .get(_url(profile, '/models'), headers: _headers(profile))
          .timeout(connectTimeout);
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw LlmException(
          'Server returned HTTP ${resp.statusCode}: ${_truncate(resp.body)}',
        );
      }
      final decoded = jsonDecode(utf8.decode(resp.bodyBytes));
      if (decoded is! Map<String, dynamic> || decoded['data'] is! List) {
        throw LlmException('Unexpected /models response shape.');
      }
      return (decoded['data'] as List).whereType<Map<String, dynamic>>().toList();
    } on TimeoutException {
      throw LlmException(
        'Connection timed out after ${connectTimeout.inSeconds}s.',
      );
    } on SocketException catch (e) {
      throw LlmException(
        'Cannot reach ${_url(profile, '/models').host}: ${e.message}',
      );
    } on http.ClientException catch (e) {
      throw LlmException('HTTP error: ${e.message}');
    } on FormatException {
      throw LlmException('Server did not return JSON.');
    } finally {
      client.close();
    }
  }

  // --- Capability probe -------------------------------------------------

  @override
  Future<ProbeResponse> sendProbe(
    LlmProviderProfile profile, {
    required List<ChatMessage> messages,
    required int maxTokens,
    Duration? timeout,
  }) async {
    final client = http.Client();
    try {
      var body =
          _buildBody(
            profile,
            messages,
            const [],
            stream: false,
            maxTokensOverride: maxTokens,
          )..remove('stream_options');
      var resp = await _send(client, profile, body, timeout: timeout);
      var text = await _readBody(resp);

      // One repair pass, same as the chat path: a server that only knows
      // `max_completion_tokens` would otherwise be reported as "rejected the
      // request size" when it merely dislikes the parameter's name.
      if (resp.statusCode >= 400 && resp.statusCode < 500) {
        final adjusted = _adjustBody(body, text);
        if (adjusted != null) {
          body = adjusted;
          resp = await _send(client, profile, body, timeout: timeout);
          text = await _readBody(resp);
        }
      }
      return _toProbeResponse(resp.statusCode, text);
    } on LlmException catch (e) {
      return ProbeResponse(statusCode: 0, message: e.message);
    } finally {
      client.close();
    }
  }

  /// Reads status, provider error code and usage out of a raw response body.
  static ProbeResponse _toProbeResponse(int statusCode, String text) {
    Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      decoded = null;
    }
    final map = decoded is Map<String, dynamic> ? decoded : null;

    var errorCode = '';
    var message = '';
    final error = map?['error'];
    if (error is Map<String, dynamic>) {
      errorCode = (error['code'] ?? error['type'] ?? '').toString();
      message = (error['message'] ?? '').toString();
    }
    if (message.isEmpty && statusCode >= 400) {
      // Relays return bare strings and HTML often enough that the raw body is
      // the only evidence there is; the patterns match against it too.
      message = _truncate(text);
    }

    TokenUsage? usage;
    final rawUsage = map?['usage'];
    if (rawUsage is Map<String, dynamic>) {
      usage = TokenUsage(
        prompt: (rawUsage['prompt_tokens'] as num?)?.toInt() ?? 0,
        completion: (rawUsage['completion_tokens'] as num?)?.toInt() ?? 0,
      );
    }

    return ProbeResponse(
      statusCode: statusCode,
      errorCode: errorCode,
      message: message,
      usage: usage,
    );
  }

  @override
  void dispose() {}
}

/// Accumulates streamed `tool_calls` deltas (arguments arrive in fragments,
/// keyed by index; some relays send whole calls in a single chunk without an
/// index).
class _ToolCallAccumulator {
  final List<({String id, String name, StringBuffer args})> _calls = [];
  final Map<int, int> _indexToSlot = {};

  void add(Map<String, dynamic> delta) {
    final index = (delta['index'] as num?)?.toInt();
    final id = delta['id'] as String?;
    final function = delta['function'];
    final name = function is Map<String, dynamic>
        ? function['name'] as String?
        : null;
    final args = function is Map<String, dynamic>
        ? function['arguments'] as String?
        : null;

    int slot;
    if (index != null) {
      slot = _indexToSlot.putIfAbsent(index, () {
        _calls.add((id: id ?? '', name: name ?? '', args: StringBuffer()));
        return _calls.length - 1;
      });
    } else if (id != null && id.isNotEmpty || _calls.isEmpty) {
      _calls.add((id: id ?? '', name: name ?? '', args: StringBuffer()));
      slot = _calls.length - 1;
    } else {
      slot = _calls.length - 1;
    }

    final current = _calls[slot];
    _calls[slot] = (
      id: current.id.isEmpty ? (id ?? '') : current.id,
      name: current.name.isEmpty ? (name ?? '') : current.name,
      args: current.args..write(args ?? ''),
    );
  }

  List<ChatToolCall> build() => [
    for (var i = 0; i < _calls.length; i++)
      if (_calls[i].name.isNotEmpty)
        ChatToolCall(
          id: _calls[i].id.isEmpty ? 'call_$i' : _calls[i].id,
          name: _calls[i].name,
          argumentsJson: _calls[i].args.isEmpty
              ? '{}'
              : _calls[i].args.toString(),
        ),
  ];
}
