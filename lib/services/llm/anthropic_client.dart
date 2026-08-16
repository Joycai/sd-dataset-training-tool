/// Native Anthropic Messages API client (streaming + tools + vision).
/// Pure Dart.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../models/llm_models.dart';
import 'llm_client.dart';
import 'sse.dart';

class AnthropicClient implements LlmClient, LlmEndpointInspector {
  AnthropicClient({
    this.connectTimeout = const Duration(seconds: 30),
    this.idleTimeout = const Duration(seconds: 120),
    this.apiVersion = '2023-06-01',
    http.Client Function()? clientFactory,
  }) : _clientFactory = clientFactory ?? http.Client.new;

  final Duration connectTimeout;
  final Duration idleTimeout;
  final String apiVersion;

  /// Injection point for tests (`MockClient`); production uses the default.
  final http.Client Function() _clientFactory;

  Uri _url(LlmProviderProfile profile, String path) {
    var base = profile.baseUrl.trim();
    if (base.isEmpty) base = 'https://api.anthropic.com';
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    return Uri.parse(base.endsWith('/v1') ? '$base$path' : '$base/v1$path');
  }

  Uri _endpoint(LlmProviderProfile profile) => _url(profile, '/messages');

  Map<String, String> _headers(LlmProviderProfile profile) => {
    'Content-Type': 'application/json',
    'x-api-key': profile.apiKey,
    'anthropic-version': apiVersion,
  };

  // --- Request building -------------------------------------------------

  Map<String, dynamic> _buildBody(
    LlmProviderProfile profile,
    List<ChatMessage> messages,
    List<AgentToolSpec> tools, {
    required bool stream,
    int? maxTokensOverride,
  }) {
    final system = messages
        .where((m) => m.role == ChatRole.system)
        .map((m) => m.text)
        .join('\n\n');
    // Prompt-cache breakpoints on the static prefix: the last tool schema
    // and the system block. An agent run re-sends the same system prompt and
    // ~30 tool schemas every turn (up to 24 turns), which is exactly the
    // payload shape caching pays for. Below the model's minimum cacheable
    // length the marker is accepted and simply does nothing. The moving
    // breakpoint that would also cache the growing history is deliberately
    // not attempted here.
    const cacheControl = {'type': 'ephemeral'};
    return {
      'model': profile.model,
      'max_tokens': maxTokensOverride ?? profile.maxOutputTokens,
      'temperature': profile.temperature.clamp(0.0, 1.0),
      'stream': stream,
      if (system.isNotEmpty)
        'system': [
          {'type': 'text', 'text': system, 'cache_control': cacheControl},
        ],
      'messages': _convertMessages(messages),
      if (tools.isNotEmpty)
        'tools': [
          for (final (i, t) in tools.indexed)
            {
              'name': t.name,
              'description': t.description,
              'input_schema': t.parametersSchema,
              if (i == tools.length - 1) 'cache_control': cacheControl,
            },
        ],
    };
  }

  /// Converts to Anthropic's alternating user/assistant shape: tool results
  /// become `tool_result` blocks in a user message, and consecutive
  /// same-role messages are merged (the API rejects non-alternating roles).
  List<Map<String, dynamic>> _convertMessages(List<ChatMessage> messages) {
    final out = <Map<String, dynamic>>[];

    void emit(String role, List<Map<String, dynamic>> blocks) {
      if (blocks.isEmpty) return;
      if (out.isNotEmpty && out.last['role'] == role) {
        (out.last['content'] as List).addAll(blocks);
      } else {
        out.add({'role': role, 'content': blocks});
      }
    }

    for (final m in messages) {
      switch (m.role) {
        case ChatRole.system:
          break; // top-level field
        case ChatRole.user:
          emit('user', _contentBlocks(m));
        case ChatRole.assistant:
          emit('assistant', [
            ..._contentBlocks(m),
            for (final c in m.toolCalls)
              {
                'type': 'tool_use',
                'id': c.id,
                'name': c.name,
                'input': _parseArgs(c.argumentsJson),
              },
          ]);
        case ChatRole.tool:
          emit('user', [
            {
              'type': 'tool_result',
              'tool_use_id': m.toolCallId ?? '',
              'content': _contentBlocks(m),
            },
          ]);
      }
    }
    return out;
  }

  List<Map<String, dynamic>> _contentBlocks(ChatMessage m) => [
    for (final p in m.parts)
      if (p.text != null && p.text!.isNotEmpty)
        {'type': 'text', 'text': p.text}
      else if (p.isImage)
        {
          'type': 'image',
          'source': {
            'type': 'base64',
            'media_type': p.imageMimeType ?? 'image/jpeg',
            'data': base64Encode(p.imageBytes!),
          },
        },
  ];

  Map<String, dynamic> _parseArgs(String json) {
    try {
      final decoded = jsonDecode(json);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {}
    return const {};
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
    final client = _clientFactory();
    // The token outlives this turn's client by the whole run; without the
    // unregistration a 24-turn run leaves 24 dead listeners on it.
    final unregister = cancel?.onCancel(client.close);
    try {
      final body = _buildBody(profile, messages, tools, stream: true);
      final resp = await _send(client, profile, body);
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw LlmException(
          'Server returned HTTP ${resp.statusCode}: '
          '${_truncate(await _readBody(resp))}',
        );
      }

      // index → partially assembled tool_use block
      final blocks = <int, ({String id, String name, StringBuffer json})>{};
      var stopReason = '';
      var inputTokens = 0;
      var outputTokens = 0;
      var cacheReadTokens = 0;
      var cacheWriteTokens = 0;

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
          final Map<String, dynamic> obj;
          try {
            final decoded = jsonDecode(data);
            if (decoded is! Map<String, dynamic>) continue;
            obj = decoded;
          } on FormatException {
            continue;
          }
          switch (obj['type']) {
            case 'message_start':
              final usage = (obj['message'] as Map<String, dynamic>?)?['usage'];
              if (usage is Map<String, dynamic>) {
                // Anthropic's input_tokens EXCLUDES the cache counters;
                // TokenUsage.prompt means the full context, so they are
                // summed back in when the stream ends.
                inputTokens = (usage['input_tokens'] as num?)?.toInt() ?? 0;
                cacheReadTokens =
                    (usage['cache_read_input_tokens'] as num?)?.toInt() ?? 0;
                cacheWriteTokens =
                    (usage['cache_creation_input_tokens'] as num?)?.toInt() ??
                    0;
              }
            case 'content_block_start':
              final index = (obj['index'] as num?)?.toInt() ?? 0;
              final block = obj['content_block'];
              if (block is Map<String, dynamic> &&
                  block['type'] == 'tool_use') {
                blocks[index] = (
                  id: (block['id'] as String?) ?? '',
                  name: (block['name'] as String?) ?? '',
                  json: StringBuffer(),
                );
              }
            case 'content_block_delta':
              final index = (obj['index'] as num?)?.toInt() ?? 0;
              final delta = obj['delta'];
              if (delta is! Map<String, dynamic>) continue;
              if (delta['type'] == 'text_delta') {
                final text = delta['text'];
                if (text is String && text.isNotEmpty) yield TextDelta(text);
              } else if (delta['type'] == 'thinking_delta') {
                // Extended thinking is never requested by this client, but a
                // relay may switch it on server-side; showing the stream
                // beats displaying a stalled connection while it thinks.
                final text = delta['thinking'];
                if (text is String && text.isNotEmpty) {
                  yield ReasoningDelta(text);
                }
              } else if (delta['type'] == 'input_json_delta') {
                blocks[index]?.json.write(delta['partial_json'] ?? '');
              }
            case 'message_delta':
              final delta = obj['delta'];
              if (delta is Map<String, dynamic>) {
                stopReason = (delta['stop_reason'] as String?) ?? stopReason;
              }
              final usage = obj['usage'];
              if (usage is Map<String, dynamic>) {
                outputTokens =
                    (usage['output_tokens'] as num?)?.toInt() ?? outputTokens;
              }
            case 'error':
              final err = obj['error'];
              throw LlmException(
                err is Map<String, dynamic>
                    ? 'API error: ${err['message']}'
                    : 'API error.',
              );
            case 'message_stop':
              break;
          }
        }
      } on http.ClientException {
        if (cancel?.isCancelled ?? false) return;
        rethrow;
      }

      final calls = [
        for (final entry
            in (blocks.entries.toList()..sort((a, b) => a.key - b.key)))
          if (entry.value.name.isNotEmpty)
            ChatToolCall(
              id: entry.value.id,
              name: entry.value.name,
              argumentsJson: entry.value.json.isEmpty
                  ? '{}'
                  : entry.value.json.toString(),
            ),
      ];
      if (calls.isNotEmpty) yield ToolCallsReady(calls);
      yield StreamDone(
        finishReason: stopReason == 'tool_use' ? 'tool_calls' : stopReason,
        usage: TokenUsage(
          prompt: inputTokens + cacheReadTokens + cacheWriteTokens,
          completion: outputTokens,
          cacheRead: cacheReadTokens,
          cacheWrite: cacheWriteTokens,
        ),
      );
    } on LlmException {
      if (cancel?.isCancelled ?? false) return;
      rethrow;
    } on SocketException catch (e) {
      if (cancel?.isCancelled ?? false) return;
      throw LlmException('Network error: ${e.message}');
    } finally {
      unregister?.call();
      client.close();
    }
  }

  // --- Probe ------------------------------------------------------------

  @override
  Future<String?> probe(LlmProviderProfile profile) async {
    final client = _clientFactory();
    try {
      final body = _buildBody(
        profile,
        [ChatMessage.user('Hi')],
        const [],
        stream: false,
        maxTokensOverride: 1,
      );
      final resp = await _send(client, profile, body);
      final text = await _readBody(resp);
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        return 'Server returned HTTP ${resp.statusCode}: ${_truncate(text)}';
      }
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic> && decoded['content'] is List) {
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

  /// `GET /v1/models` — returns the `data[].id` values sorted alphabetically.
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
    final client = _clientFactory();
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
      return (decoded['data'] as List)
          .whereType<Map<String, dynamic>>()
          .toList();
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
    final client = _clientFactory();
    try {
      final body = _buildBody(
        profile,
        messages,
        const [],
        stream: false,
        maxTokensOverride: maxTokens,
      );
      final resp = await _send(client, profile, body, timeout: timeout);
      final text = await _readBody(resp);

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
        errorCode = (error['type'] ?? '').toString();
        message = (error['message'] ?? '').toString();
      }
      if (message.isEmpty && resp.statusCode >= 400) {
        message = _truncate(text);
      }

      TokenUsage? usage;
      final rawUsage = map?['usage'];
      if (rawUsage is Map<String, dynamic>) {
        usage = TokenUsage(
          prompt: (rawUsage['input_tokens'] as num?)?.toInt() ?? 0,
          completion: (rawUsage['output_tokens'] as num?)?.toInt() ?? 0,
        );
      }

      return ProbeResponse(
        statusCode: resp.statusCode,
        errorCode: errorCode,
        message: message,
        usage: usage,
      );
    } on LlmException catch (e) {
      return ProbeResponse(statusCode: 0, message: e.message);
    } finally {
      client.close();
    }
  }

  @override
  void dispose() {}
}
