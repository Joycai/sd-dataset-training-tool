/// Phase-2 cost fixes: remembered 4xx repairs, cache-token accounting on
/// both clients, Anthropic prompt-cache breakpoints, and pricing math.
library;

import 'dart:convert';

import 'package:dataset_training_tool/models/llm_models.dart';
import 'package:dataset_training_tool/services/llm/anthropic_client.dart';
import 'package:dataset_training_tool/services/llm/openai_compat_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _profile = LlmProviderProfile(
  id: 'p1',
  name: 'fake',
  baseUrl: 'https://relay.example/v1',
  apiKey: 'k',
  model: 'm',
);

String _openAiSse({Map<String, dynamic>? usage}) =>
    [
      'data: {"choices":[{"delta":{"content":"hi"},"finish_reason":"stop"}]}',
      if (usage != null) 'data: ${jsonEncode({'usage': usage, 'choices': []})}',
      'data: [DONE]',
    ].map((l) => '$l\n\n').join();

void main() {
  group('remembered 4xx repairs', () {
    test('a repair that worked is applied on the next request', () async {
      final bodies = <Map<String, dynamic>>[];
      final client = OpenAiCompatClient(
        clientFactory: () => MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          bodies.add(body);
          if (body.containsKey('temperature')) {
            return http.Response(
              '{"error": {"message": "temperature is not supported"}}',
              400,
            );
          }
          return http.Response(_openAiSse(), 200);
        }),
      );

      await client.chat(profile: _profile, messages: [
        ChatMessage.user('one'),
      ]).toList();
      // Round one paid the discovery round-trip: reject, then repaired.
      expect(bodies, hasLength(2));
      expect(bodies[0].containsKey('temperature'), isTrue);
      expect(bodies[1].containsKey('temperature'), isFalse);

      await client.chat(profile: _profile, messages: [
        ChatMessage.user('two'),
      ]).toList();
      // Round two sends the accepted shape on the first try.
      expect(bodies, hasLength(3));
      expect(bodies[2].containsKey('temperature'), isFalse);
    });

    test('repairs are per profile, not global', () async {
      final bodies = <Map<String, dynamic>>[];
      final client = OpenAiCompatClient(
        clientFactory: () => MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          bodies.add(body);
          if (body.containsKey('temperature')) {
            return http.Response('temperature rejected', 400);
          }
          return http.Response(_openAiSse(), 200);
        }),
      );

      await client.chat(profile: _profile, messages: [
        ChatMessage.user('one'),
      ]).toList();
      bodies.clear();
      // A different profile has not earned the repair.
      await client.chat(
        profile: _profile.copyWith(name: 'other') /* same id! */,
        messages: [ChatMessage.user('x')],
      ).toList();
      expect(bodies.first.containsKey('temperature'), isFalse);

      bodies.clear();
      const fresh = LlmProviderProfile(
        id: 'p2',
        name: 'fresh',
        baseUrl: 'https://relay.example/v1',
        model: 'm',
      );
      await client.chat(profile: fresh, messages: [
        ChatMessage.user('x'),
      ]).toList();
      // New profile pays its own discovery round-trip.
      expect(bodies, hasLength(2));
      expect(bodies.first.containsKey('temperature'), isTrue);
    });
  });

  group('cache token accounting', () {
    test('openai cached_tokens land in cacheRead', () async {
      final client = OpenAiCompatClient(
        clientFactory: () => MockClient(
          (request) async => http.Response(
            _openAiSse(
              usage: {
                'prompt_tokens': 100,
                'completion_tokens': 10,
                'prompt_tokens_details': {'cached_tokens': 80},
              },
            ),
            200,
          ),
        ),
      );
      final events = await client.chat(
        profile: _profile,
        messages: [ChatMessage.user('hi')],
      ).toList();
      final usage = events.whereType<StreamDone>().single.usage!;
      // prompt_tokens already includes the cached subset.
      expect(usage.prompt, 100);
      expect(usage.cacheRead, 80);
      expect(usage.cacheWrite, 0);
      expect(usage.completion, 10);
    });

    test('anthropic cache counters are folded back into prompt', () async {
      final sse = [
        'data: {"type":"message_start","message":{"usage":{"input_tokens":10,'
            '"cache_read_input_tokens":80,"cache_creation_input_tokens":20}}}',
        'data: {"type":"content_block_delta","index":0,'
            '"delta":{"type":"text_delta","text":"hi"}}',
        'data: {"type":"message_delta","delta":{"stop_reason":"end_turn"},'
            '"usage":{"output_tokens":5}}',
        'data: {"type":"message_stop"}',
      ].map((l) => '$l\n\n').join();
      final client = AnthropicClient(
        clientFactory: () =>
            MockClient((request) async => http.Response(sse, 200)),
      );
      final events = await client.chat(
        profile: _profile,
        messages: [ChatMessage.user('hi')],
      ).toList();
      final usage = events.whereType<StreamDone>().single.usage!;
      // input_tokens excludes the cache counters; TokenUsage.prompt is the
      // full context, so the client sums them back in.
      expect(usage.prompt, 110);
      expect(usage.cacheRead, 80);
      expect(usage.cacheWrite, 20);
      expect(usage.completion, 5);
    });
  });

  group('anthropic prompt-cache breakpoints', () {
    test('system block and last tool carry cache_control', () async {
      Map<String, dynamic>? seen;
      final client = AnthropicClient(
        clientFactory: () => MockClient((request) async {
          seen = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            'data: {"type":"message_stop"}\n\n',
            200,
          );
        }),
      );
      const tools = [
        AgentToolSpec(
          name: 'a',
          description: 'first',
          parametersSchema: {'type': 'object', 'properties': {}},
        ),
        AgentToolSpec(
          name: 'b',
          description: 'last',
          parametersSchema: {'type': 'object', 'properties': {}},
        ),
      ];
      await client.chat(
        profile: _profile,
        messages: [ChatMessage.system('sys'), ChatMessage.user('hi')],
        tools: tools,
      ).toList();

      final system = seen!['system'] as List;
      expect((system.single as Map)['cache_control'], {'type': 'ephemeral'});
      final wireTools = seen!['tools'] as List;
      expect((wireTools[0] as Map).containsKey('cache_control'), isFalse);
      expect((wireTools[1] as Map)['cache_control'], {'type': 'ephemeral'});
    });
  });

  group('pricing math', () {
    test('cached input is billed at the cache rates', () {
      const pricing = LlmPricing(
        input: 3,
        output: 15,
        cacheRead: 0.3,
        cacheWrite: 3.75,
      );
      const usage = TokenUsage(
        prompt: 1000000, // 700k fresh + 200k read + 100k write
        completion: 100000,
        cacheRead: 200000,
        cacheWrite: 100000,
      );
      expect(
        pricing.costOf(usage),
        closeTo(0.7 * 3 + 0.2 * 0.3 + 0.1 * 3.75 + 0.1 * 15, 1e-9),
      );
    });

    test('usage sums preserve the cache counters', () {
      const a = TokenUsage(prompt: 10, completion: 1, cacheRead: 5);
      const b = TokenUsage(prompt: 20, completion: 2, cacheWrite: 7);
      final sum = a + b;
      expect(sum.prompt, 30);
      expect(sum.cacheRead, 5);
      expect(sum.cacheWrite, 7);
      expect(sum.total, 33);
    });
  });
}
