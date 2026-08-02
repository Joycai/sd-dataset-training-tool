/// Runs capability detection against a live endpoint.
///
/// The order is deliberate and is the whole design: free metadata first,
/// then one cheap request that makes the server volunteer its own numbers,
/// and only then — and only when asked — a paid request large enough to catch
/// silent truncation. No searching, no escalation: every step has a fixed
/// cost that can be shown to the user before anything is sent.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../models/llm_models.dart';
import 'endpoint_probe.dart';
import 'llm_client.dart';

enum ProbeStep { listing, backendApi, errorProbe, calibration, truncationTest }

enum ProbeStepStatus { running, done, skipped, failed }

/// Progress callback. [detail] is raw server evidence and stays untranslated.
typedef ProbeStepReporter =
    void Function(ProbeStep step, ProbeStepStatus status, String? detail);

class EndpointProbeService {
  EndpointProbeService({
    this.metadataTimeout = const Duration(seconds: 20),
    this.probeTimeout = const Duration(seconds: 60),

    /// Generous: a local backend handed a near-full window may have to load
    /// or re-shard the model before it answers at all.
    this.largePromptTimeout = const Duration(seconds: 180),
  });

  final Duration metadataTimeout;
  final Duration probeTimeout;
  final Duration largePromptTimeout;

  /// Small and large calibration samples, in filler words.
  static const int _calibrationSmallWords = 150;
  static const int _calibrationLargeWords = 1200;

  /// The absurd `max_tokens` used to make the server state its own ceiling.
  /// Large enough that no real model could honour it, so a success means the
  /// server does not validate the parameter rather than that it agreed.
  static const int absurdMaxTokens = 100000000;

  /// Fraction of the claimed window the truncation check fills. Not 100%:
  /// the envelope and the reply need room, and a request that fails purely
  /// for being one token over teaches nothing.
  static const double truncationFillRatio = 0.9;

  /// Input tokens the optional truncation check will spend on a window of
  /// [claimedContextWindow]. Shown before the user opts in.
  static int estimateTruncationTestTokens(int claimedContextWindow) =>
      (claimedContextWindow * truncationFillRatio).round() +
      (_calibrationSmallWords + _calibrationLargeWords) * 2;

  /// A one-word answer keeps the reply cheap even where the absurd
  /// `max_tokens` is accepted rather than refused.
  static final _tinyPrompt = [
    ChatMessage.user('Reply with the single word: ok'),
  ];

  Future<CapabilityReport> run({
    required LlmProvider provider,
    required LlmModelConfig model,
    required LlmEndpointInspector inspector,
    bool includeTruncationTest = false,
    ProbeStepReporter? onStep,
    bool Function()? isCancelled,
  }) async {
    final report = CapabilityReport();
    final profile = provider.resolve(model);
    bool cancelled() => isCancelled?.call() ?? false;

    void step(ProbeStep s, ProbeStepStatus status, [String? detail]) =>
        onStep?.call(s, status, detail);

    // --- 1. Free: the model listing -----------------------------------
    step(ProbeStep.listing, ProbeStepStatus.running);
    try {
      final entries = await inspector.listModelsDetailed(profile);
      final entry = findModelEntry(entries, model.modelId);
      if (entry == null) {
        step(
          ProbeStep.listing,
          ProbeStepStatus.skipped,
          'no entry for "${model.modelId}" among ${entries.length} models',
        );
      } else {
        final limits = limitsFromModelEntry(entry);
        if (limits.isEmpty) {
          step(
            ProbeStep.listing,
            ProbeStepStatus.skipped,
            'entry carries no limit fields',
          );
        } else {
          report.findings.add(
            CapabilityFinding(
              source: CapabilitySource.listing,
              detail: _compactJson(entry),
              contextWindow: limits.contextWindow,
              maxOutput: limits.maxOutput,
            ),
          );
          step(ProbeStep.listing, ProbeStepStatus.done, limits.toString());
        }
      }
    } on LlmException catch (e) {
      step(ProbeStep.listing, ProbeStepStatus.failed, e.message);
    }
    if (cancelled()) return report;

    // --- 2. Free: backend-specific endpoints ---------------------------
    //
    // Only when the listing came up empty, and only for OpenAI-compatible
    // endpoints — these paths exist on Ollama and llama.cpp, which both
    // speak that protocol. Failures are expected on any other host and are
    // reported as "skipped", not as an error.
    if (report.contextWindow == null &&
        provider.kind == LlmApiKind.openaiCompat) {
      step(ProbeStep.backendApi, ProbeStepStatus.running);
      final found = await _probeBackendApis(provider, model, report);
      step(
        ProbeStep.backendApi,
        found == null ? ProbeStepStatus.skipped : ProbeStepStatus.done,
        found ?? 'no Ollama or llama.cpp endpoint answered',
      );
    } else {
      step(ProbeStep.backendApi, ProbeStepStatus.skipped, 'not needed');
    }
    if (cancelled()) return report;

    // --- 3. One cheap request: make the server state its limits ---------
    step(ProbeStep.errorProbe, ProbeStepStatus.running);
    final probe = await inspector.sendProbe(
      profile,
      messages: _tinyPrompt,
      maxTokens: absurdMaxTokens,
      timeout: probeTimeout,
    );
    if (probe.ok) {
      step(
        ProbeStep.errorProbe,
        ProbeStepStatus.done,
        'accepted max_tokens=$absurdMaxTokens — the server does not '
        'validate it, so no ceiling can be read from it',
      );
      report.notes.add(
        'max_tokens=$absurdMaxTokens was accepted; this endpoint does not '
        'report an output ceiling.',
      );
    } else {
      final failure = classifyFailure(
        statusCode: probe.statusCode,
        errorCode: probe.errorCode,
        message: probe.message,
      );
      if (failure.isLimitEvidence) {
        final limits = parseLimitsFromMessage(
          probe.message,
          requested: absurdMaxTokens,
        );
        if (limits.isEmpty) {
          step(
            ProbeStep.errorProbe,
            ProbeStepStatus.skipped,
            'refused, but the message carries no number: ${probe.message}',
          );
          report.notes.add(probe.message);
        } else {
          report.findings.add(
            CapabilityFinding(
              source: CapabilitySource.errorMessage,
              detail: probe.message,
              contextWindow: limits.contextWindow,
              maxOutput: limits.maxOutput,
            ),
          );
          step(ProbeStep.errorProbe, ProbeStepStatus.done, limits.toString());
        }
      } else {
        // Anything else — a rate limit, a dead upstream, a bad key — says
        // nothing about the window and must not be allowed to lower it.
        step(
          ProbeStep.errorProbe,
          ProbeStepStatus.failed,
          '${failure.name}: ${probe.message}',
        );
        report.notes.add('${failure.name}: ${probe.message}');
      }
    }
    if (cancelled() || !includeTruncationTest) {
      if (!includeTruncationTest) {
        step(ProbeStep.calibration, ProbeStepStatus.skipped, 'not requested');
        step(
          ProbeStep.truncationTest,
          ProbeStepStatus.skipped,
          'not requested',
        );
      }
      return report;
    }

    // --- 4. Paid, opt-in: calibrate, then check for silent truncation ---
    //
    // The cost the user agreed to (shown before the run started) was
    // estimated from the *configured* window. If the steps above just found
    // a much bigger one — a listing reporting 1M against an 8K config is not
    // a hypothetical — spending at the newly-claimed size would send a
    // request the user never actually approved the price of.
    final claimedWindow = report.contextWindow ?? model.contextWindow;
    final approvedTokens = estimateTruncationTestTokens(model.contextWindow);
    final actualTokens = estimateTruncationTestTokens(claimedWindow);
    if (actualTokens > approvedTokens * 2) {
      final detail =
          'detected window is $claimedWindow tokens vs the configured '
          '${model.contextWindow} — testing it would cost about '
          '$actualTokens tokens, not the ~$approvedTokens shown before you '
          'started this run';
      step(ProbeStep.calibration, ProbeStepStatus.skipped, detail);
      step(ProbeStep.truncationTest, ProbeStepStatus.skipped, detail);
      report.notes.add(
        'Truncation test skipped: $detail. Raise the configured context '
        'window and rerun to test at the real size, or confirm manually.',
      );
      return report;
    }

    await _runTruncationCheck(
      inspector: inspector,
      profile: profile,
      claimedWindow: claimedWindow,
      report: report,
      step: step,
      cancelled: cancelled,
    );
    return report;
  }

  // --- Backend-specific metadata ---------------------------------------

  /// Tries Ollama's `/api/show` and llama.cpp's `/props` against the host
  /// root. Returns a human-readable summary, or null when neither answered.
  Future<String?> _probeBackendApis(
    LlmProvider provider,
    LlmModelConfig model,
    CapabilityReport report,
  ) async {
    final base = Uri.tryParse(provider.baseUrl.trim());
    if (base == null || !base.hasScheme || base.host.isEmpty) return null;
    final root = Uri(scheme: base.scheme, host: base.host, port: base.hasPort ? base.port : null);

    final client = http.Client();
    try {
      // Ollama. `model` is the current field name and `name` the older one;
      // sending both keeps one request working across versions.
      try {
        final resp = await client
            .post(
              root.replace(path: '/api/show'),
              headers: const {'Content-Type': 'application/json'},
              body: jsonEncode({'model': model.modelId, 'name': model.modelId}),
            )
            .timeout(metadataTimeout);
        if (resp.statusCode >= 200 && resp.statusCode < 300) {
          final decoded = jsonDecode(utf8.decode(resp.bodyBytes));
          if (decoded is Map<String, dynamic>) {
            final info = parseOllamaShow(decoded);
            if (!info.isEmpty) {
              if (info.modelContextLength != null) {
                // Recorded as a note, never as the answer: the weights
                // supporting 128K says nothing about num_ctx allocating it,
                // and proposing the larger number is exactly the mistake
                // this check exists to prevent.
                report.notes.add(
                  'Ollama: weights support ${info.modelContextLength} tokens; '
                  'the running configuration is what governs a request.',
                );
              }
              if (info.numCtx != null) {
                report.findings.add(
                  CapabilityFinding(
                    source: CapabilitySource.backendApi,
                    detail: 'Ollama /api/show: num_ctx=${info.numCtx}',
                    contextWindow: info.numCtx,
                  ),
                );
                return 'Ollama num_ctx=${info.numCtx}';
              }
              return 'Ollama reported no num_ctx; '
                  'the default applies and is usually far below the weights';
            }
          }
        }
      } catch (_) {
        // Not an Ollama host. Expected.
      }

      // llama.cpp.
      try {
        final resp = await client
            .get(root.replace(path: '/props'))
            .timeout(metadataTimeout);
        if (resp.statusCode >= 200 && resp.statusCode < 300) {
          final nCtx = parseLlamaCppContext(
            jsonDecode(utf8.decode(resp.bodyBytes)),
          );
          if (nCtx != null) {
            report.findings.add(
              CapabilityFinding(
                source: CapabilitySource.backendApi,
                detail: 'llama.cpp /props: n_ctx=$nCtx',
                contextWindow: nCtx,
              ),
            );
            return 'llama.cpp n_ctx=$nCtx';
          }
        }
      } catch (_) {
        // Not a llama.cpp host. Expected.
      }
      return null;
    } finally {
      client.close();
    }
  }

  // --- Truncation check --------------------------------------------------

  Future<void> _runTruncationCheck({
    required LlmEndpointInspector inspector,
    required LlmProviderProfile profile,
    required int claimedWindow,
    required CapabilityReport report,
    required void Function(ProbeStep, ProbeStepStatus, [String?]) step,
    required bool Function() cancelled,
  }) async {
    step(ProbeStep.calibration, ProbeStepStatus.running);

    Future<int?> promptTokensFor(int words, Duration timeout) async {
      final response = await inspector.sendProbe(
        profile,
        messages: [ChatMessage.user(buildFiller(words))],
        maxTokens: 1,
        timeout: timeout,
      );
      if (!response.ok) {
        final failure = classifyFailure(
          statusCode: response.statusCode,
          errorCode: response.errorCode,
          message: response.message,
        );
        throw _ProbeAborted(failure, response.message);
      }
      final prompt = response.usage?.prompt ?? 0;
      return prompt > 0 ? prompt : null;
    }

    TokenCalibration calibration;
    try {
      final small = await promptTokensFor(
        _calibrationSmallWords,
        probeTimeout,
      );
      if (cancelled()) return;
      final large = await promptTokensFor(
        _calibrationLargeWords,
        probeTimeout,
      );
      if (small == null || large == null) {
        step(
          ProbeStep.calibration,
          ProbeStepStatus.skipped,
          'the server reported no prompt token usage',
        );
        report.notes.add(
          'No usage reported, so silent truncation cannot be checked here.',
        );
        step(
          ProbeStep.truncationTest,
          ProbeStepStatus.skipped,
          'needs calibration',
        );
        return;
      }
      final derived = calibrate(
        smallWords: _calibrationSmallWords,
        smallTokens: small,
        largeWords: _calibrationLargeWords,
        largeTokens: large,
      );
      if (derived == null) {
        step(
          ProbeStep.calibration,
          ProbeStepStatus.skipped,
          'inconsistent counts: $small then $large tokens',
        );
        step(
          ProbeStep.truncationTest,
          ProbeStepStatus.skipped,
          'needs calibration',
        );
        return;
      }
      calibration = derived;
      step(
        ProbeStep.calibration,
        ProbeStepStatus.done,
        '${calibration.tokensPerWord.toStringAsFixed(2)} tokens/word, '
        'envelope ${calibration.overheadTokens.round()} tokens',
      );
    } on _ProbeAborted catch (e) {
      step(ProbeStep.calibration, ProbeStepStatus.failed, e.describe());
      report.notes.add(e.describe());
      step(ProbeStep.truncationTest, ProbeStepStatus.skipped, 'calibration failed');
      return;
    }
    if (cancelled()) return;

    // --- the one large request ---
    step(ProbeStep.truncationTest, ProbeStepStatus.running);
    final targetTokens = (claimedWindow * truncationFillRatio).round();
    final words = calibration.wordsForTokens(targetTokens);
    if (words <= _calibrationLargeWords) {
      step(
        ProbeStep.truncationTest,
        ProbeStepStatus.skipped,
        'the claimed window is too small to test meaningfully',
      );
      return;
    }
    final expected = calibration.expectedTokens(words);

    final ProbeResponse response;
    try {
      response = await inspector.sendProbe(
        profile,
        messages: [ChatMessage.user(buildFiller(words))],
        maxTokens: 1,
        timeout: largePromptTimeout,
      );
    } catch (e) {
      step(ProbeStep.truncationTest, ProbeStepStatus.failed, '$e');
      return;
    }

    if (!response.ok) {
      final failure = classifyFailure(
        statusCode: response.statusCode,
        errorCode: response.errorCode,
        message: response.message,
      );
      if (failure.isLimitEvidence) {
        // Refusing is the honest behaviour: the content was not silently
        // dropped. Whatever number the message carries is better evidence
        // than the claim being tested.
        final limits = parseLimitsFromMessage(response.message);
        if (!limits.isEmpty) {
          report.findings.add(
            CapabilityFinding(
              source: CapabilitySource.errorMessage,
              detail: response.message,
              contextWindow: limits.contextWindow,
              maxOutput: limits.maxOutput,
            ),
          );
        }
        report.truncation = TruncationVerdict.notDetected;
        step(
          ProbeStep.truncationTest,
          ProbeStepStatus.done,
          'refused rather than truncated: ${response.message}',
        );
      } else {
        step(
          ProbeStep.truncationTest,
          ProbeStepStatus.failed,
          '${failure.name}: ${response.message}',
        );
        report.notes.add('${failure.name}: ${response.message}');
      }
      return;
    }

    final reported = response.usage?.prompt ?? 0;
    report.truncation = judgeTruncation(
      expectedTokens: expected,
      reportedTokens: reported,
    );
    switch (report.truncation) {
      case TruncationVerdict.detected:
        report.effectiveContextWindow = reported;
        report.findings.add(
          CapabilityFinding(
            source: CapabilitySource.measured,
            detail:
                'sent ~$expected tokens, the server counted $reported — '
                'the rest was dropped without an error',
            contextWindow: reported,
          ),
        );
        step(
          ProbeStep.truncationTest,
          ProbeStepStatus.done,
          'truncation: expected ~$expected, counted $reported',
        );
      case TruncationVerdict.notDetected:
        step(
          ProbeStep.truncationTest,
          ProbeStepStatus.done,
          'expected ~$expected, counted $reported',
        );
      case TruncationVerdict.inconclusive:
        step(
          ProbeStep.truncationTest,
          ProbeStepStatus.skipped,
          'the server reported no prompt token usage',
        );
    }
  }

  static String _compactJson(Map<String, dynamic> entry) {
    try {
      final text = jsonEncode(entry);
      return text.length <= 400 ? text : '${text.substring(0, 400)}…';
    } catch (_) {
      return entry.toString();
    }
  }
}

/// Internal control flow for a probe that could not continue.
class _ProbeAborted implements Exception {
  _ProbeAborted(this.failure, this.message);

  final ProbeFailure failure;
  final String message;

  String describe() => '${failure.name}: $message';
}
