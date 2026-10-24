import 'dart:convert';
import 'dart:typed_data';

import 'package:dataset_training_tool/models/llm_models.dart';
import 'package:dataset_training_tool/services/llm/anthropic_client.dart';
import 'package:dataset_training_tool/services/llm/gemini_client.dart';
import 'package:dataset_training_tool/services/llm/llm_client.dart';
import 'package:dataset_training_tool/services/llm/openai_compat_client.dart';
import 'package:dataset_training_tool/services/llm/responses_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const profile = LlmProviderProfile(
  id: 'p',
  name: 'p',
  baseUrl: 'https://example.test/v1',
  model: 'gpt-6.1-sol',
  supportsVision: true,
);
const tool = AgentToolSpec(
  name: 'inspect',
  description: 'inspect',
  parametersSchema: {'type': 'object', 'properties': {}},
);
String sse(List<Map<String, dynamic>> objects) =>
    objects.map((o) => 'data: ${jsonEncode(o)}\n\n').join();
ChatContentPart picture() => ChatContentPart.image(
  Uint8List.fromList([1, 2, 3]),
  imageMimeType: 'image/png',
);

void main() {
  test(
    'Responses effort, signed output replay, tools, image and usage',
    () async {
      final bodies = <Map<String, dynamic>>[];
      final output = [
        {
          'type': 'reasoning',
          'id': 'rs_1',
          'encrypted_content': 'opaque',
          'summary': [],
        },
        {
          'type': 'function_call',
          'id': 'fc_1',
          'call_id': 'c1',
          'name': 'inspect',
          'arguments': '{}',
        },
      ];
      final p = profile.copyWith(
        kind: LlmApiKind.responses,
        effort: LlmEffort.high,
      );
      final client = ResponsesClient(
        clientFactory: () => MockClient((r) async {
          expect(r.url.path, '/v1/responses');
          bodies.add(jsonDecode(r.body) as Map<String, dynamic>);
          return http.Response(
            sse([
              {
                'type': 'response.reasoning_summary_text.delta',
                'delta': 'consider',
              },
              {
                'type': 'response.completed',
                'response': {
                  'status': 'completed',
                  'output': output,
                  'usage': {
                    'input_tokens': 50,
                    'output_tokens': 12,
                    'input_tokens_details': {'cached_tokens': 20},
                  },
                },
              },
            ]),
            200,
          );
        }),
      );
      final events = await client
          .chat(profile: p, messages: [ChatMessage.user('look')], tools: [tool])
          .toList();
      final done = events.whereType<StreamDone>().single;
      expect(done.usage!.prompt, 50);
      expect(done.usage!.cacheRead, 20);
      expect(bodies.single['reasoning'], {'effort': 'high'});
      expect(bodies.single['temperature'], isNull);
      expect(bodies.single['store'], false);
      expect((bodies.single['tools'] as List).single['strict'], false);
      final history = [
        ChatMessage.assistant(
          '',
          toolCalls: events.whereType<ToolCallsReady>().single.calls,
          replay: done.replay,
        ),
        ChatMessage.toolResult(
          toolCallId: 'c1',
          text: 'image',
          extraParts: [picture()],
        ),
      ];
      await client.chat(profile: p, messages: history, tools: [tool]).toList();
      final input = bodies.last['input'] as List;
      expect(input.take(2), output);
      expect(input[2]['call_id'], 'c1');
      expect(input[2]['output'][1]['image_url'], 'data:image/png;base64,AQID');
      final changed = client.buildBody(
        p.copyWith(model: 'another'),
        history,
        [],
        stream: true,
      );
      expect(jsonEncode(changed), isNot(contains('opaque')));
    },
  );

  test('Responses fails on failed event or missing terminal event', () async {
    for (final stream in [
      sse([
        {
          'type': 'response.failed',
          'response': {'error': 'bad'},
        },
      ]),
      sse([
        {'type': 'response.output_text.delta', 'delta': 'partial'},
      ]),
    ]) {
      final client = ResponsesClient(
        clientFactory: () =>
            MockClient((_) async => http.Response(stream, 200)),
      );
      await expectLater(
        client
            .chat(profile: profile, messages: [ChatMessage.user('x')])
            .toList(),
        throwsA(isA<LlmException>()),
      );
    }
  });

  for (final model in ['gemini-3.7-flash', 'gemini-3.8-flash']) {
    test('$model preserves signed calls and multimodal tool results', () async {
      final bodies = <Map<String, dynamic>>[];
      final p = profile.copyWith(
        kind: LlmApiKind.gemini,
        model: model,
        effort: LlmEffort.medium,
      );
      final signed = {
        'functionCall': {'id': 'gc_1', 'name': 'inspect', 'args': {}},
        'thoughtSignature': 'secret-signature',
      };
      final client = GeminiClient(
        clientFactory: () => MockClient((r) async {
          expect(r.url.path, '/v1/models/$model:streamGenerateContent');
          expect(r.url.queryParameters['alt'], 'sse');
          bodies.add(jsonDecode(r.body) as Map<String, dynamic>);
          return http.Response(
            sse([
              {
                'candidates': [
                  {
                    'content': {
                      'parts': [signed],
                    },
                    'finishReason': 'STOP',
                  },
                ],
                'usageMetadata': {
                  'promptTokenCount': 10,
                  'candidatesTokenCount': 2,
                  'thoughtsTokenCount': 4,
                },
              },
            ]),
            200,
          );
        }),
      );
      final events = await client
          .chat(
            profile: p,
            messages: [ChatMessage.user('inspect')],
            tools: [tool],
          )
          .toList();
      final done = events.whereType<StreamDone>().single;
      expect(done.usage!.completion, 6);
      expect(bodies.single['generationConfig']['thinkingConfig'], {
        'includeThoughts': true,
        'thinkingLevel': 'MEDIUM',
      });
      final history = [
        ChatMessage.assistant(
          '',
          toolCalls: events.whereType<ToolCallsReady>().single.calls,
          replay: done.replay,
        ),
        ChatMessage.toolResult(
          toolCallId: 'gc_1',
          text: 'ok',
          extraParts: [picture()],
        ),
      ];
      await client.chat(profile: p, messages: history, tools: [tool]).toList();
      final contents = bodies.last['contents'] as List;
      expect(contents.first['parts'], [signed]);
      final response = contents.last['parts'][0]['functionResponse'];
      expect(response['id'], 'gc_1');
      expect(response['name'], 'inspect');
      expect(response['parts'][0]['inlineData']['data'], 'AQID');
      expect(jsonEncode(bodies.last), isNot(contains('temperature')));
    });
  }

  test(
    'Gemini safety/signature failures are errors, not empty success',
    () async {
      final client = GeminiClient(
        clientFactory: () => MockClient(
          (_) async => http.Response(
            sse([
              {
                'candidates': [
                  {'finishReason': 'MISSING_THOUGHT_SIGNATURE'},
                ],
              },
            ]),
            200,
          ),
        ),
      );
      await expectLater(
        client
            .chat(profile: profile, messages: [ChatMessage.user('x')])
            .toList(),
        throwsA(isA<LlmException>()),
      );
    },
  );

  test(
    'Chat preserves original reasoning field and batches tool images after results',
    () async {
      final bodies = <Map<String, dynamic>>[];
      final p = profile.copyWith(
        model: 'deepseek-v4.1-flash',
        effort: LlmEffort.max,
      );
      final client = OpenAiCompatClient(
        clientFactory: () => MockClient((r) async {
          bodies.add(jsonDecode(r.body) as Map<String, dynamic>);
          return http.Response(
            sse([
              {
                'choices': [
                  {
                    'delta': {'reasoning_content': '', 'reasoning': 'why'},
                  },
                ],
              },
              {
                'choices': [
                  {
                    'delta': {'content': 'ok'},
                    'finish_reason': 'stop',
                  },
                ],
              },
            ]),
            200,
          );
        }),
      );
      final events = await client
          .chat(profile: p, messages: [ChatMessage.user('x')])
          .toList();
      expect(bodies.single['thinking'], {'type': 'enabled'});
      expect(bodies.single['reasoning_effort'], 'max');
      expect(events.whereType<ReasoningDelta>().single.text, 'why');
      const calls = [
        ChatToolCall(id: 'a', name: 'inspect', argumentsJson: '{}'),
        ChatToolCall(id: 'b', name: 'inspect', argumentsJson: '{}'),
      ];
      await client
          .chat(
            profile: p,
            messages: [
              ChatMessage.assistant(
                '',
                toolCalls: calls,
                replay: events.whereType<StreamDone>().single.replay,
              ),
              ChatMessage.toolResult(
                toolCallId: 'a',
                text: 'a',
                extraParts: [picture()],
              ),
              ChatMessage.toolResult(toolCallId: 'b', text: 'b'),
            ],
          )
          .toList();
      final messages = bodies.last['messages'] as List;
      expect(messages.map((m) => m['role']), [
        'assistant',
        'tool',
        'tool',
        'user',
      ]);
      expect(messages.first['reasoning'], 'why');
      expect(messages.first.containsKey('reasoning_content'), false);
    },
  );

  test(
    'Messages assembles thinking signature and redacted blocks for replay',
    () async {
      final bodies = <Map<String, dynamic>>[];
      final p = profile.copyWith(
        kind: LlmApiKind.anthropic,
        model: 'claude-opus-5-5',
        effort: LlmEffort.xhigh,
      );
      final client = AnthropicClient(
        clientFactory: () => MockClient((r) async {
          bodies.add(jsonDecode(r.body) as Map<String, dynamic>);
          return http.Response(
            sse([
              {
                'type': 'content_block_start',
                'index': 0,
                'content_block': {
                  'type': 'thinking',
                  'thinking': '',
                  'signature': '',
                },
              },
              {
                'type': 'content_block_delta',
                'index': 0,
                'delta': {'type': 'thinking_delta', 'thinking': 'hmm'},
              },
              {
                'type': 'content_block_delta',
                'index': 0,
                'delta': {'type': 'signature_delta', 'signature': 'sig'},
              },
              {
                'type': 'content_block_delta',
                'index': 0,
                'delta': {'type': 'signature_delta', 'signature': 'nature'},
              },
              {
                'type': 'content_block_start',
                'index': 1,
                'content_block': {
                  'type': 'redacted_thinking',
                  'data': 'opaque',
                },
              },
              {
                'type': 'content_block_delta',
                'index': 2,
                'delta': {'type': 'text_delta', 'text': 'ok'},
              },
              {
                'type': 'message_delta',
                'delta': {'stop_reason': 'end_turn'},
              },
              {'type': 'message_stop'},
            ]),
            200,
          );
        }),
      );
      final events = await client
          .chat(profile: p, messages: [ChatMessage.user('x')])
          .toList();
      expect(bodies.single['output_config'], {'effort': 'xhigh'});
      expect(bodies.single['temperature'], isNull);
      final history = [
        ChatMessage.assistant(
          'ok',
          replay: events.whereType<StreamDone>().single.replay,
        ),
        ChatMessage.user('next'),
      ];
      await client.chat(profile: p, messages: history).toList();
      expect(bodies.last['messages'][0]['content'][0], {
        'type': 'thinking',
        'thinking': 'hmm',
        'signature': 'signature',
      });
      expect(bodies.last['messages'][0]['content'][1], {
        'type': 'redacted_thinking',
        'data': 'opaque',
      });
    },
  );

  test('all protocols reject image input when vision is disabled', () async {
    for (final client in <LlmClient>[
      OpenAiCompatClient(),
      AnthropicClient(),
      ResponsesClient(),
      GeminiClient(),
    ]) {
      await expectLater(
        client
            .chat(
              profile: profile.copyWith(supportsVision: false),
              messages: [
                ChatMessage(role: ChatRole.user, parts: [picture()]),
              ],
            )
            .toList(),
        throwsA(isA<LlmException>()),
      );
    }
  });
}
