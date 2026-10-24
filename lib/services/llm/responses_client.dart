import 'dart:convert';

import '../../models/llm_models.dart';
import 'json_protocol_client.dart';
import 'llm_client.dart';

class ResponsesClient extends JsonProtocolClient {
  ResponsesClient({
    super.clientFactory,
    super.connectTimeout,
    super.idleTimeout,
  });
  @override
  Uri endpoint(LlmProviderProfile profile, {bool stream = false}) =>
      Uri.parse('${JsonProtocolClient.base(profile)}/responses');
  @override
  Uri modelsEndpoint(LlmProviderProfile profile) =>
      Uri.parse('${JsonProtocolClient.base(profile)}/models');
  @override
  Map<String, String> headers(LlmProviderProfile profile) => {
    'Content-Type': 'application/json',
    if (profile.apiKey.isNotEmpty) 'Authorization': 'Bearer ${profile.apiKey}',
  };

  List<Map<String, dynamic>> parts(ChatMessage m) => [
    for (final p in m.parts)
      if (p.text != null)
        {'type': 'input_text', 'text': p.text}
      else if (p.isImage)
        {
          'type': 'input_image',
          'image_url':
              'data:${p.imageMimeType};base64,${base64Encode(p.imageBytes!)}',
        },
  ];

  @override
  Map<String, dynamic> buildBody(
    LlmProviderProfile profile,
    List<ChatMessage> messages,
    List<AgentToolSpec> tools, {
    required bool stream,
  }) => {
    'model': profile.model,
    'stream': stream,
    'store': false,
    'instructions': messages
        .where((m) => m.role == ChatRole.system)
        .map((m) => m.text)
        .join('\n\n'),
    'max_output_tokens': profile.maxOutputTokens,
    'include': ['reasoning.encrypted_content'],
    ...validatedReasoningParameters(
      effort: profile.effort,
      dialect: profile.reasoningDialect,
      model: profile.model,
      anthropic: false,
      responses: true,
    ),
    'input': [
      for (final m in messages)
        if (m.role == ChatRole.user)
          {'role': 'user', 'content': parts(m)}
        else if (m.role == ChatRole.tool)
          {
            'type': 'function_call_output',
            'call_id': m.toolCallId,
            'output': m.imageCount > 0 ? parts(m) : m.text,
          }
        else if (m.role == ChatRole.assistant)
          if ((m.replay?.matches(profile) ?? false) &&
              m.replay!.data['output'] is List)
            ...m.replay!.data['output'] as List
          else ...[
            if (m.text.isNotEmpty) {'role': 'assistant', 'content': m.text},
            for (final c in m.toolCalls)
              {
                'type': 'function_call',
                'call_id': c.id,
                'name': c.name,
                'arguments': c.argumentsJson,
              },
          ],
    ],
    if (tools.isNotEmpty)
      'tools': [
        for (final t in tools)
          {
            'type': 'function',
            'name': t.name,
            'description': t.description,
            'parameters': t.parametersSchema,
            'strict': false,
          },
      ],
  };

  @override
  TokenUsage? readUsage(Map<String, dynamic> response) {
    final u = response['usage'];
    if (u is! Map<String, dynamic>) return null;
    final details = u['input_tokens_details'];
    return TokenUsage(
      prompt: (u['input_tokens'] as num?)?.toInt() ?? 0,
      completion: (u['output_tokens'] as num?)?.toInt() ?? 0,
      cacheRead: details is Map
          ? (details['cached_tokens'] as num?)?.toInt() ?? 0
          : 0,
      cacheWrite: details is Map
          ? (details['cache_write_tokens'] as num?)?.toInt() ?? 0
          : 0,
    );
  }

  @override
  bool validResponse(Map<String, dynamic> response) =>
      response['output'] is List &&
      (response['status'] == 'completed' || response['status'] == 'incomplete');

  @override
  Stream<LlmStreamEvent> decodeEvents(
    LlmProviderProfile profile,
    Stream<Map<String, dynamic>> events,
  ) async* {
    final output = <int, Map<String, dynamic>>{};
    Map<String, dynamic>? completed;
    await for (final event in events) {
      switch (event['type']) {
        case 'response.output_text.delta':
          yield TextDelta(event['delta'] as String? ?? '');
        case 'response.reasoning_summary_text.delta':
        case 'response.reasoning_text.delta':
          yield ReasoningDelta(event['delta'] as String? ?? '');
        case 'response.output_item.done':
          if (event['item'] is Map<String, dynamic>) {
            output[(event['output_index'] as num).toInt()] =
                event['item'] as Map<String, dynamic>;
          }
        case 'response.completed':
        case 'response.incomplete':
          completed = event['response'] as Map<String, dynamic>?;
        case 'response.failed':
        case 'error':
          throw LlmException(
            'Responses API failed: ${event['response'] ?? event}',
          );
      }
    }
    if (completed == null) {
      throw LlmException('Responses stream ended without a terminal event.');
    }
    final items = completed['output'] is List
        ? completed['output'] as List
        : [for (final i in output.keys.toList()..sort()) output[i]!];
    final calls = [
      for (final item in items.whereType<Map<String, dynamic>>())
        if (item['type'] == 'function_call')
          ChatToolCall(
            id: item['call_id'] as String,
            name: item['name'] as String,
            argumentsJson: item['arguments'] as String? ?? '{}',
          ),
    ];
    if (calls.isNotEmpty) yield ToolCallsReady(calls);
    final incomplete = completed['status'] == 'incomplete';
    if (incomplete &&
        (completed['incomplete_details'] as Map?)?['reason'] !=
            'max_output_tokens') {
      throw LlmException(
        'Incomplete response: ${completed['incomplete_details']}',
      );
    }
    yield StreamDone(
      finishReason: incomplete
          ? 'length'
          : calls.isEmpty
          ? 'stop'
          : 'tool_calls',
      usage: readUsage(completed),
      replay: LlmReplay(profile, {'output': items}),
    );
  }
}
