import 'dart:convert';

import 'package:dataset_training_tool/models/llm_models.dart';
import 'package:dataset_training_tool/services/llm/endpoint_probe.dart';
import 'package:dataset_training_tool/services/llm/endpoint_probe_service.dart';
import 'package:dataset_training_tool/services/llm/llm_client.dart';
import 'package:flutter_test/flutter_test.dart';

/// [listingContextLength] seeds `/models` with a `context_length` entry for
/// the probed model, standing in for a relay whose catalogue disagrees with
/// the configured window. Every `sendProbe` call is counted so a test can
/// tell "the guard skipped before calibration" from "it proceeded".
class _FakeInspector implements LlmEndpointInspector {
  _FakeInspector({this.listingContextLength});

  final int? listingContextLength;
  int sendProbeCalls = 0;

  @override
  Future<List<Map<String, dynamic>>> listModelsDetailed(
    LlmProviderProfile profile,
  ) async {
    final window = listingContextLength;
    if (window == null) return const [];
    return [
      {'id': profile.model, 'context_length': window},
    ];
  }

  @override
  Future<ProbeResponse> sendProbe(
    LlmProviderProfile profile, {
    required List<ChatMessage> messages,
    required int maxTokens,
    Duration? timeout,
  }) async {
    sendProbeCalls++;
    // The absurd max_tokens identifies the error-probe step; answer it with
    // something that carries no limit evidence so it does not itself set
    // report.contextWindow. Calibration calls (maxTokens: 1) get an ok reply
    // with no usage, which is enough to prove they were reached without
    // needing the whole calibration/truncation flow to succeed.
    if (maxTokens != 1) {
      return const ProbeResponse(statusCode: 429, message: 'rate limited');
    }
    return const ProbeResponse(statusCode: 200);
  }
}

void main() {
  group('classifyFailure', () {
    test('reads OpenAI-style context overflow as limit evidence', () {
      final failure = classifyFailure(
        statusCode: 400,
        errorCode: 'context_length_exceeded',
        message: "This model's maximum context length is 8192 tokens.",
      );
      expect(failure, ProbeFailure.contextLimit);
      expect(failure.isLimitEvidence, isTrue);
    });

    test('reads an Anthropic output ceiling as output evidence', () {
      expect(
        classifyFailure(
          statusCode: 400,
          errorCode: 'invalid_request_error',
          message:
              'max_tokens: 100000000 > 64000, which is the maximum allowed '
              'number of output tokens for claude-opus-4',
        ),
        ProbeFailure.outputLimit,
      );
    });

    // The whole point of the classifier: none of these may be read as "the
    // window is small". Misreading one is how detection reports 8K for a
    // 200K model.
    test('never treats a rate limit as limit evidence', () {
      final failure = classifyFailure(
        statusCode: 429,
        message: 'Rate limit reached for tokens per minute',
      );
      expect(failure, ProbeFailure.rateLimited);
      expect(failure.isLimitEvidence, isFalse);
      expect(failure.isTransient, isTrue);
    });

    test('separates a byte-size gateway cap from a token limit', () {
      final failure = classifyFailure(
        statusCode: 413,
        message: 'Payload Too Large',
      );
      expect(failure, ProbeFailure.payloadTooLarge);
      expect(failure.isLimitEvidence, isFalse);
    });

    test('an upstream failure is transient, not a limit', () {
      final failure = classifyFailure(
        statusCode: 502,
        message: 'upstream error',
      );
      expect(failure, ProbeFailure.serverError);
      expect(failure.isLimitEvidence, isFalse);
    });

    test('a bad key is auth, not a limit', () {
      expect(
        classifyFailure(statusCode: 401, message: 'invalid api key'),
        ProbeFailure.auth,
      );
    });

    test('status 0 splits timeout from network by message', () {
      expect(
        classifyFailure(statusCode: 0, message: 'Connection timed out after 30s.'),
        ProbeFailure.timeout,
      );
      expect(
        classifyFailure(statusCode: 0, message: 'Cannot reach host: refused'),
        ProbeFailure.network,
      );
    });

    test('a rejected parameter is not a limit', () {
      expect(
        classifyFailure(
          statusCode: 400,
          message:
              "Unsupported parameter: 'max_tokens' is not supported with this "
              'model. Use max_completion_tokens instead.',
        ),
        ProbeFailure.parameterRejected,
      );
    });

    test('a message naming both prefers the context window', () {
      // OpenAI answers an absurd max_tokens with a sentence that mentions
      // max_tokens *and* states the context window; the window is the real
      // information and must win.
      expect(
        classifyFailure(
          statusCode: 400,
          errorCode: '',
          message:
              "This model's maximum context length is 128000 tokens, however "
              'you requested 100000200 tokens (200 in your prompt; 100000000 '
              'for the completion).',
        ),
        ProbeFailure.contextLimit,
      );
    });
  });

  group('parseLimitsFromMessage', () {
    test('reads the OpenAI context sentence', () {
      final limits = parseLimitsFromMessage(
        "This model's maximum context length is 8192 tokens, however you "
        'requested 9000 tokens.',
      );
      expect(limits.contextWindow, 8192);
    });

    test('discards the value the probe itself sent', () {
      // Servers echo the requested number back. Picking it up would report
      // our own made-up constant as if the server had stated it.
      final limits = parseLimitsFromMessage(
        "This model's maximum context length is 128000 tokens, however you "
        'requested 100000200 tokens (200 in your prompt; 100000000 for the '
        'completion).',
        requested: 100000000,
      );
      expect(limits.contextWindow, 128000);
    });

    test('reads the Anthropic output ceiling', () {
      final limits = parseLimitsFromMessage(
        'max_tokens: 100000000 > 64000, which is the maximum allowed number '
        'of output tokens for claude-opus-4',
        requested: 100000000,
      );
      expect(limits.maxOutput, 64000);
      expect(limits.contextWindow, isNull);
    });

    test('handles digit grouping', () {
      expect(
        parseLimitsFromMessage(
          "This model's maximum context length is 1,048,576 tokens",
        ).contextWindow,
        1048576,
      );
    });

    test('rejects implausible numbers', () {
      // An id or a timestamp in the message must not become a window.
      expect(
        parseLimitsFromMessage(
          'context length of 12 tokens (request 1722600000)',
        ).contextWindow,
        isNull,
      );
    });

    test('returns nothing for a message with no number', () {
      expect(
        parseLimitsFromMessage(
          'the request exceeds the available context size',
        ).isEmpty,
        isTrue,
      );
    });
  });

  group('limitsFromModelEntry', () {
    test('reads vLLM max_model_len', () {
      final limits = limitsFromModelEntry({
        'id': 'qwen',
        'max_model_len': 32768,
      });
      expect(limits.contextWindow, 32768);
    });

    test('reads OpenRouter nested top_provider', () {
      final limits = limitsFromModelEntry({
        'id': 'anthropic/claude',
        'context_length': 200000,
        'top_provider': {'max_completion_tokens': 8192},
      });
      expect(limits.contextWindow, 200000);
      expect(limits.maxOutput, 8192);
    });

    test('ignores a bare max_tokens field', () {
      // On several relays that key is the default request size, not the
      // model ceiling; a wrong small number is worse than none.
      final limits = limitsFromModelEntry({'id': 'x', 'max_tokens': 512});
      expect(limits.isEmpty, isTrue);
    });

    test('accepts a numeric string', () {
      expect(
        limitsFromModelEntry({'id': 'x', 'context_length': '65536'})
            .contextWindow,
        65536,
      );
    });

    test('finds the entry by id case-insensitively', () {
      final entries = [
        {'id': 'Other', 'context_length': 1},
        {'id': 'GPT-4o', 'context_length': 128000},
      ];
      expect(findModelEntry(entries, 'gpt-4o')?['context_length'], 128000);
      expect(findModelEntry(entries, 'missing'), isNull);
    });
  });

  group('backend responses', () {
    test('Ollama: weights capacity and running num_ctx are kept apart', () {
      final info = parseOllamaShow(
        jsonDecode('''
        {
          "model_info": {"qwen2.context_length": 131072, "general.name": "q"},
          "parameters": "stop \\"<|im_end|>\\"\\nnum_ctx 4096"
        }
        ''') as Map<String, dynamic>,
      );
      expect(info.modelContextLength, 131072);
      expect(info.numCtx, 4096);
    });

    test('Ollama: architecture prefix is not hardcoded', () {
      final info = parseOllamaShow({
        'model_info': {'llama.context_length': 8192},
      });
      expect(info.modelContextLength, 8192);
      expect(info.numCtx, isNull);
    });

    test('llama.cpp: n_ctx is found at either nesting depth', () {
      expect(
        parseLlamaCppContext({
          'default_generation_settings': {'n_ctx': 4096},
        }),
        4096,
      );
      expect(
        parseLlamaCppContext({
          'default_generation_settings': {
            'params': {'n_ctx': 16384},
          },
        }),
        16384,
      );
      expect(parseLlamaCppContext({'unrelated': true}), isNull);
    });
  });

  group('filler', () {
    test('is deterministic for a seed', () {
      expect(buildFiller(50), buildFiller(50));
      expect(buildFiller(50, seed: 1), isNot(buildFiller(50, seed: 2)));
    });

    test('does not repeat a single token block', () {
      // A run of identical text is collapsed by prefix caches and by some
      // tokenizers, which would make the calibration flatter than reality.
      final words = buildFiller(200).split(RegExp(r'[\s.\n]+'));
      expect(words.toSet().length, greaterThan(10));
    });

    test('scales with the word count', () {
      expect(buildFiller(0), isEmpty);
      expect(buildFiller(400).length, greaterThan(buildFiller(100).length * 3));
    });
  });

  group('calibration', () {
    test('two points remove the envelope overhead', () {
      // 1.4 tokens/word plus a fixed 20-token envelope.
      final calibration = calibrate(
        smallWords: 100,
        smallTokens: 160,
        largeWords: 1100,
        largeTokens: 1560,
      )!;
      expect(calibration.tokensPerWord, closeTo(1.4, 0.001));
      expect(calibration.overheadTokens, closeTo(20, 0.001));
      expect(calibration.expectedTokens(500), 720);
    });

    test('a one-point estimate would over-predict — this does not', () {
      final calibration = calibrate(
        smallWords: 100,
        smallTokens: 160,
        largeWords: 1100,
        largeTokens: 1560,
      )!;
      // Naive rate 160/100 = 1.6 would predict 16000 tokens for 10k words.
      expect(calibration.expectedTokens(10000), lessThan(15000));
    });

    test('rejects degenerate measurements', () {
      expect(
        calibrate(
          smallWords: 100,
          smallTokens: 160,
          largeWords: 100,
          largeTokens: 160,
        ),
        isNull,
      );
      expect(
        calibrate(
          smallWords: 100,
          smallTokens: 0,
          largeWords: 1100,
          largeTokens: 1560,
        ),
        isNull,
      );
      expect(
        calibrate(
          smallWords: 100,
          smallTokens: 200,
          largeWords: 1100,
          largeTokens: 150,
        ),
        isNull,
      );
    });

    test('wordsForTokens inverts expectedTokens', () {
      final calibration = calibrate(
        smallWords: 100,
        smallTokens: 160,
        largeWords: 1100,
        largeTokens: 1560,
      )!;
      final words = calibration.wordsForTokens(10000);
      expect(calibration.expectedTokens(words), lessThanOrEqualTo(10000));
      expect(calibration.expectedTokens(words + 2), greaterThan(10000));
    });
  });

  group('judgeTruncation', () {
    test('a count far below prediction is truncation', () {
      expect(
        judgeTruncation(expectedTokens: 100000, reportedTokens: 4096),
        TruncationVerdict.detected,
      );
    });

    test('ordinary tokenizer drift is not truncation', () {
      expect(
        judgeTruncation(expectedTokens: 100000, reportedTokens: 92000),
        TruncationVerdict.notDetected,
      );
    });

    test('missing usage is inconclusive, not clean', () {
      expect(
        judgeTruncation(expectedTokens: 100000, reportedTokens: 0),
        TruncationVerdict.inconclusive,
      );
    });
  });

  group('CapabilityReport', () {
    CapabilityFinding finding(CapabilitySource source, int window) =>
        CapabilityFinding(
          source: source,
          detail: source.name,
          contextWindow: window,
        );

    test('a server-stated number beats a catalogue number', () {
      final report = CapabilityReport(
        findings: [
          finding(CapabilitySource.listing, 200000),
          finding(CapabilitySource.errorMessage, 32768),
        ],
      );
      expect(report.contextWindow, 32768);
    });

    test('a direct measurement beats everything', () {
      final report = CapabilityReport(
        findings: [
          finding(CapabilitySource.errorMessage, 131072),
          finding(CapabilitySource.measured, 4096),
        ],
      );
      expect(report.contextWindow, 4096);
    });

    test('the backend API beats the listing', () {
      final report = CapabilityReport(
        findings: [
          finding(CapabilitySource.listing, 131072),
          finding(CapabilitySource.backendApi, 4096),
        ],
      );
      expect(report.contextWindow, 4096);
    });

    test('reads each limit independently', () {
      final report = CapabilityReport(
        findings: [
          const CapabilityFinding(
            source: CapabilitySource.listing,
            detail: '',
            contextWindow: 200000,
          ),
          const CapabilityFinding(
            source: CapabilitySource.errorMessage,
            detail: '',
            maxOutput: 8192,
          ),
        ],
      );
      expect(report.contextWindow, 200000);
      expect(report.maxOutput, 8192);
    });

    test('an empty report proposes nothing', () {
      final report = CapabilityReport();
      expect(report.isEmpty, isTrue);
      expect(report.contextWindow, isNull);
      expect(report.maxOutput, isNull);
    });
  });

  group('ProbeResponse', () {
    test('a clean 2xx is usable', () {
      const response = ProbeResponse(statusCode: 200);
      expect(response.ok, isTrue);
    });

    test('a 200 carrying an error body is not usable', () {
      // Relays answer 200 with an error object often enough that trusting the
      // status alone would read a refusal as "the server accepted it".
      const response = ProbeResponse(
        statusCode: 200,
        errorCode: 'context_length_exceeded',
        message: "This model's maximum context length is 8192 tokens.",
      );
      expect(response.ok, isFalse);
      expect(
        classifyFailure(
          statusCode: response.statusCode,
          errorCode: response.errorCode,
          message: response.message,
        ),
        ProbeFailure.contextLimit,
      );
    });
  });

  group('LlmModelConfig measurement fields', () {
    test('round-trip through JSON', () {
      const model = LlmModelConfig(
        id: 'm',
        modelId: 'gpt-4o',
        measuredContextWindow: 128000,
        measuredMaxOutput: 16384,
        measuredAt: '2026-08-02T10:00:00.000',
        silentTruncation: true,
      );
      final decoded = LlmModelConfig.fromJson(model.toJson());
      expect(decoded.measuredContextWindow, 128000);
      expect(decoded.measuredMaxOutput, 16384);
      expect(decoded.measuredAt, '2026-08-02T10:00:00.000');
      expect(decoded.silentTruncation, isTrue);
      expect(decoded.hasMeasurement, isTrue);
    });

    test('an unmeasured model writes no detection keys', () {
      const model = LlmModelConfig(id: 'm', modelId: 'x');
      final json = model.toJson();
      expect(json.containsKey('measuredContextWindow'), isFalse);
      expect(json.containsKey('measuredAt'), isFalse);
      expect(json.containsKey('silentTruncation'), isFalse);
      expect(model.hasMeasurement, isFalse);
    });

    test('a config saved before detection existed still reads', () {
      final decoded = LlmModelConfig.fromJson({
        'id': 'm',
        'modelId': 'x',
        'contextWindow': 65536,
      });
      expect(decoded.contextWindow, 65536);
      expect(decoded.hasMeasurement, isFalse);
      expect(decoded.silentTruncation, isFalse);
    });
  });

  group('EndpointProbeService.run truncation cost guard', () {
    const provider = LlmProvider(
      id: 'p',
      name: 'Test',
      kind: LlmApiKind.anthropic,
      baseUrl: 'https://api.anthropic.com',
    );

    test(
      'skips the truncation test when the detected window dwarfs the '
      'configured one',
      () async {
        // The listing reports a window the user never saw an estimate for —
        // spending at that size would bill for far more than the number
        // they approved before starting the run.
        const model = LlmModelConfig(id: 'm', modelId: 'x', contextWindow: 8192);
        final inspector = _FakeInspector(listingContextLength: 1000000);
        final report = await EndpointProbeService().run(
          provider: provider,
          model: model,
          inspector: inspector,
          includeTruncationTest: true,
        );
        expect(
          report.notes.any((n) => n.contains('Truncation test skipped')),
          isTrue,
        );
        // Only the error-probe step's request went out — calibration, which
        // would spend real tokens at the claimed size, must never start.
        expect(inspector.sendProbeCalls, 1);
      },
    );

    test(
      'runs the truncation test normally when the windows agree',
      () async {
        const model = LlmModelConfig(id: 'm', modelId: 'x', contextWindow: 100);
        final inspector = _FakeInspector();
        final report = await EndpointProbeService().run(
          provider: provider,
          model: model,
          inspector: inspector,
          includeTruncationTest: true,
        );
        expect(
          report.notes.any((n) => n.contains('Truncation test skipped')),
          isFalse,
        );
        // Calibration was attempted, not short-circuited by the guard.
        expect(inspector.sendProbeCalls, greaterThan(1));
      },
    );
  });
}
