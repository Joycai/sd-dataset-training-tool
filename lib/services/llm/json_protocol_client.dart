import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../models/llm_models.dart';
import 'llm_client.dart';
import 'sse.dart';

/// Shared transport only; subclasses own their protocol's body and events.
abstract class JsonProtocolClient implements LlmClient, LlmEndpointInspector {
  JsonProtocolClient({
    http.Client Function()? clientFactory,
    this.connectTimeout = const Duration(seconds: 30),
    this.idleTimeout = const Duration(seconds: 120),
  }) : clientFactory = clientFactory ?? http.Client.new;

  final http.Client Function() clientFactory;
  final Duration connectTimeout;
  final Duration idleTimeout;
  Uri endpoint(LlmProviderProfile profile, {bool stream = false});
  Uri modelsEndpoint(LlmProviderProfile profile);
  Map<String, String> headers(LlmProviderProfile profile);
  Map<String, dynamic> buildBody(
    LlmProviderProfile profile,
    List<ChatMessage> messages,
    List<AgentToolSpec> tools, {
    required bool stream,
  });
  Stream<LlmStreamEvent> decodeEvents(
    LlmProviderProfile profile,
    Stream<Map<String, dynamic>> events,
  );
  TokenUsage? readUsage(Map<String, dynamic> response);
  bool validResponse(Map<String, dynamic> response);

  static String base(LlmProviderProfile p) =>
      p.baseUrl.trim().replaceAll(RegExp(r'/+$'), '');

  Future<http.StreamedResponse> send(
    http.Client client,
    LlmProviderProfile profile,
    Map<String, dynamic> body, {
    bool stream = false,
    Duration? timeout,
  }) => client
      .send(
        http.Request('POST', endpoint(profile, stream: stream))
          ..headers.addAll(headers(profile))
          ..body = jsonEncode(body),
      )
      .timeout(timeout ?? connectTimeout);

  Stream<Map<String, dynamic>> objects(http.StreamedResponse response) async* {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final text = await response.stream.bytesToString().timeout(idleTimeout);
      throw LlmException(
        'HTTP ${response.statusCode}: ${text.substring(0, text.length.clamp(0, 600))}',
      );
    }
    await for (final data in sseDataEvents(
      response.stream,
    ).timeout(idleTimeout)) {
      if (data == '[DONE]') break;
      final decoded = jsonDecode(data);
      if (decoded is! Map<String, dynamic>) continue;
      if (decoded['error'] != null) {
        throw LlmException('API error: ${decoded['error']}');
      }
      yield decoded;
    }
  }

  @override
  Stream<LlmStreamEvent> chat({
    required LlmProviderProfile profile,
    required List<ChatMessage> messages,
    List<AgentToolSpec> tools = const [],
    CancellationToken? cancel,
  }) async* {
    if (cancel?.isCancelled ?? false) return;
    final client = clientFactory();
    final unregister = cancel?.onCancel(client.close);
    try {
      validateLlmImages(profile, messages);
      final response = await send(
        client,
        profile,
        buildBody(profile, messages, tools, stream: true),
        stream: true,
      );
      yield* decodeEvents(profile, objects(response));
    } catch (e) {
      if (cancel?.isCancelled ?? false) return;
      if (e is LlmException) rethrow;
      if (e is TimeoutException ||
          e is SocketException ||
          e is http.ClientException ||
          e is FormatException ||
          e is ArgumentError) {
        throw LlmException('LLM request failed: $e');
      }
      rethrow;
    } finally {
      unregister?.call();
      client.close();
    }
  }

  @override
  Future<ProbeResponse> sendProbe(
    LlmProviderProfile profile, {
    required List<ChatMessage> messages,
    required int maxTokens,
    Duration? timeout,
  }) async {
    final client = clientFactory();
    try {
      validateLlmImages(profile, messages);
      final response = await send(
        client,
        profile,
        buildBody(
          profile.copyWith(maxOutputTokens: maxTokens),
          messages,
          const [],
          stream: false,
        ),
        timeout: timeout,
      );
      final decoded = jsonDecode(
        await response.stream.bytesToString().timeout(timeout ?? idleTimeout),
      );
      final map = decoded is Map<String, dynamic>
          ? decoded
          : <String, dynamic>{};
      final error = map['error'];
      return ProbeResponse(
        statusCode: response.statusCode,
        message: error != null
            ? error.toString()
            : validResponse(map)
            ? ''
            : 'Unexpected response shape or failed response.',
        usage: readUsage(map),
      );
    } catch (e) {
      return ProbeResponse(statusCode: 0, message: e.toString());
    } finally {
      client.close();
    }
  }

  @override
  Future<String?> probe(LlmProviderProfile profile) async {
    final result = await sendProbe(
      profile,
      messages: [ChatMessage.user('Hi')],
      maxTokens: 64,
    );
    return result.ok ? null : 'HTTP ${result.statusCode}: ${result.message}';
  }

  @override
  Future<List<Map<String, dynamic>>> listModelsDetailed(
    LlmProviderProfile profile,
  ) async {
    final client = clientFactory();
    try {
      final response = await client
          .get(modelsEndpoint(profile), headers: headers(profile))
          .timeout(connectTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw LlmException('Model listing HTTP ${response.statusCode}');
      }
      final decoded =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final rows = decoded['data'] ?? decoded['models'];
      if (rows is! List) throw LlmException('Unexpected model listing.');
      return [
        for (final row in rows.whereType<Map<String, dynamic>>())
          {
            ...row,
            'id':
                row['id'] ??
                (row['name'] as String? ?? '').replaceFirst('models/', ''),
          },
      ];
    } catch (e) {
      if (e is LlmException) rethrow;
      throw LlmException('Model listing failed: $e');
    } finally {
      client.close();
    }
  }

  @override
  Future<List<String>> listModels(LlmProviderProfile profile) async =>
      (await listModelsDetailed(profile))
          .map((m) => m['id'] as String)
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList()
        ..sort();
  @override
  void dispose() {}
}
