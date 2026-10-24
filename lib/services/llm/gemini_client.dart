import 'dart:convert';

import '../../models/llm_models.dart';
import 'json_protocol_client.dart';
import 'llm_client.dart';

/// Native generateContent protocol, including signed thought parts.
class GeminiClient extends JsonProtocolClient {
  GeminiClient({super.clientFactory, super.connectTimeout, super.idleTimeout});
  String _base(LlmProviderProfile p) {
    final base = JsonProtocolClient.base(p);
    return RegExp(r'/v1(beta)?$').hasMatch(base) ? base : '$base/v1beta';
  }

  @override
  Uri endpoint(LlmProviderProfile profile, {bool stream = false}) {
    final model = profile.model.replaceFirst(RegExp(r'^models/'), '');
    return Uri.parse(
      '${_base(profile)}/models/${Uri.encodeComponent(model)}:${stream ? 'streamGenerateContent?alt=sse' : 'generateContent'}',
    );
  }

  @override
  Uri modelsEndpoint(LlmProviderProfile profile) =>
      Uri.parse('${_base(profile)}/models');
  @override
  Map<String, String> headers(LlmProviderProfile profile) => {
    'Content-Type': 'application/json',
    if (profile.apiKey.isNotEmpty) 'x-goog-api-key': profile.apiKey,
  };

  List<Map<String, dynamic>> _parts(ChatMessage m) => [
    for (final p in m.parts)
      if (p.text != null && p.text!.isNotEmpty)
        {'text': p.text}
      else if (p.isImage)
        {
          'inlineData': {
            'mimeType': p.imageMimeType,
            'data': base64Encode(p.imageBytes!),
          },
        },
  ];

  List<Map<String, dynamic>> _contents(
    LlmProviderProfile profile,
    List<ChatMessage> messages,
  ) {
    final out = <Map<String, dynamic>>[];
    final names = {
      for (final m in messages)
        for (final c in m.toolCalls) c.id: c.name,
    };
    void emit(String role, List<dynamic> parts) {
      if (parts.isEmpty) return;
      if (out.isNotEmpty && out.last['role'] == role) {
        (out.last['parts'] as List).addAll(parts);
      } else {
        out.add({'role': role, 'parts': List<dynamic>.of(parts)});
      }
    }

    for (final m in messages) {
      switch (m.role) {
        case ChatRole.system:
          break;
        case ChatRole.user:
          emit('user', _parts(m));
        case ChatRole.assistant:
          if ((m.replay?.matches(profile) ?? false) &&
              m.replay!.data['parts'] is List) {
            emit('model', m.replay!.data['parts'] as List);
          } else {
            emit('model', [
              ..._parts(m),
              for (final c in m.toolCalls)
                {
                  'functionCall': {
                    'id': c.id,
                    'name': c.name,
                    'args': jsonDecode(c.argumentsJson),
                  },
                },
            ]);
          }
        case ChatRole.tool:
          final name = names[m.toolCallId];
          if (name == null) {
            throw LlmException('Missing function call for ${m.toolCallId}.');
          }
          emit('user', [
            {
              'functionResponse': {
                'name': name,
                'id': m.toolCallId,
                'response': {'result': m.text},
                if (m.imageCount > 0)
                  'parts': _parts(
                    m,
                  ).where((p) => p.containsKey('inlineData')).toList(),
              },
            },
          ]);
      }
    }
    return out;
  }

  @override
  Map<String, dynamic> buildBody(
    LlmProviderProfile profile,
    List<ChatMessage> messages,
    List<AgentToolSpec> tools, {
    required bool stream,
  }) => {
    'contents': _contents(profile, messages),
    if (messages.any((m) => m.role == ChatRole.system))
      'systemInstruction': {
        'parts': [
          {
            'text': messages
                .where((m) => m.role == ChatRole.system)
                .map((m) => m.text)
                .join('\n\n'),
          },
        ],
      },
    'generationConfig': {
      'maxOutputTokens': profile.maxOutputTokens,
      'thinkingConfig': {
        'includeThoughts': true,
        if (profile.effort != LlmEffort.defaultValue)
          'thinkingLevel': switch (profile.effort) {
            LlmEffort.off || LlmEffort.low => 'LOW',
            LlmEffort.medium => 'MEDIUM',
            _ => 'HIGH',
          },
      },
    },
    if (tools.isNotEmpty)
      'tools': [
        {
          'functionDeclarations': [
            for (final t in tools)
              {
                'name': t.name,
                'description': t.description,
                'parametersJsonSchema': t.parametersSchema,
              },
          ],
        },
      ],
  };

  @override
  TokenUsage? readUsage(Map<String, dynamic> response) {
    final u = response['usageMetadata'];
    if (u is! Map<String, dynamic>) return null;
    int n(String key) => (u[key] as num?)?.toInt() ?? 0;
    return TokenUsage(
      prompt: n('promptTokenCount') + n('toolUsePromptTokenCount'),
      completion: n('candidatesTokenCount') + n('thoughtsTokenCount'),
      cacheRead: n('cachedContentTokenCount'),
    );
  }

  @override
  bool validResponse(Map<String, dynamic> response) =>
      response['candidates'] is List &&
      (response['candidates'] as List).isNotEmpty &&
      (response['promptFeedback'] as Map?)?['blockReason'] == null;

  @override
  Stream<LlmStreamEvent> decodeEvents(
    LlmProviderProfile profile,
    Stream<Map<String, dynamic>> events,
  ) async* {
    final parts = <Map<String, dynamic>>[];
    final calls = <ChatToolCall>[];
    TokenUsage? usage;
    String? finish;
    await for (final event in events) {
      final block = (event['promptFeedback'] as Map?)?['blockReason'];
      if (block != null) throw LlmException('Gemini prompt blocked: $block');
      usage = readUsage(event) ?? usage;
      final candidates = event['candidates'];
      if (candidates is! List || candidates.isEmpty) continue;
      final candidate = candidates.first as Map<String, dynamic>;
      finish = candidate['finishReason'] as String? ?? finish;
      if (finish != null && finish != 'STOP' && finish != 'MAX_TOKENS') {
        throw LlmException('Gemini response failed: $finish');
      }
      final content = candidate['content'] as Map?;
      for (final p
          in (content?['parts'] as List? ?? const [])
              .whereType<Map<String, dynamic>>()) {
        // A bare empty trailing text part cannot be replayed to Gemini.
        if (p.length == 1 && p['text'] == '') continue;
        parts.add(p);
        if (p['text'] is String) {
          if (p['thought'] == true) {
            yield ReasoningDelta(p['text'] as String);
          } else {
            yield TextDelta(p['text'] as String);
          }
        }
        final call = p['functionCall'];
        if (call is Map<String, dynamic>) {
          calls.add(
            ChatToolCall(
              id: call['id'] as String? ?? 'gemini_${calls.length}',
              name: call['name'] as String,
              argumentsJson: jsonEncode(call['args'] ?? {}),
            ),
          );
        }
      }
    }
    if (finish == null) {
      throw LlmException('Gemini stream ended without a finish reason.');
    }
    if (calls.isNotEmpty) yield ToolCallsReady(calls);
    yield StreamDone(
      finishReason: finish == 'MAX_TOKENS'
          ? 'length'
          : calls.isEmpty
          ? 'stop'
          : 'tool_calls',
      usage: usage,
      replay: LlmReplay(profile, {'parts': parts}),
    );
  }
}
