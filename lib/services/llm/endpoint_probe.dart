/// Pure logic for working out what a backend *actually* accepts: error
/// classification, limit extraction from error text and `/models` metadata,
/// deterministic filler, and token calibration. No Flutter, no I/O — the
/// orchestration that makes requests lives in `endpoint_probe_service.dart`.
///
/// The guiding rule throughout: only evidence that unambiguously describes a
/// limit may lower a number. A rate-limit or a dead upstream must never be
/// read as "the window is small" — that is how this kind of detection ends up
/// reporting an 8K window for a 200K model.
library;

// --- Failure classification -------------------------------------------

/// Why a probe request did not succeed.
///
/// Only [contextLimit] and [outputLimit] are admissible as evidence about the
/// model's limits. Everything else means "we learned nothing", not "the limit
/// is here".
enum ProbeFailure {
  /// The server said the prompt (or prompt + completion) exceeds its window.
  contextLimit,

  /// The server said the requested output length is too large.
  outputLimit,

  /// A parameter was rejected on its own terms (wrong name, unsupported).
  parameterRejected,

  /// HTTP 413 — a gateway body-size cap, measured in bytes, *not* tokens.
  payloadTooLarge,

  rateLimited,
  auth,
  serverError,
  timeout,
  network,
  unknown,
}

extension ProbeFailureX on ProbeFailure {
  /// Whether the failure says anything trustworthy about the limits.
  bool get isLimitEvidence =>
      this == ProbeFailure.contextLimit || this == ProbeFailure.outputLimit;

  /// Whether retrying the identical request could plausibly succeed.
  bool get isTransient =>
      this == ProbeFailure.rateLimited ||
      this == ProbeFailure.serverError ||
      this == ProbeFailure.timeout ||
      this == ProbeFailure.network;
}

/// Ordered so the first match wins: the context/output patterns are checked
/// before the generic parameter patterns, because a single OpenAI message
/// mentions `max_tokens` *and* the context window and the window is the real
/// information in it.
final _contextPhrases = RegExp(
  r'maximum context length'
  r'|context length of'
  r'|context window'
  r'|context_length_exceeded'
  r'|reduce the length of the messages'
  r'|exceeds the available context'
  r'|prompt is too long'
  r'|too many tokens',
  caseSensitive: false,
);

final _outputPhrases = RegExp(
  r'maximum allowed number of output tokens'
  r'|maximum number of output tokens'
  r'|max_tokens.{0,60}?(?:too large|exceeds|must be)'
  r'|max_completion_tokens.{0,60}?(?:too large|exceeds|must be)',
  caseSensitive: false,
);

final _parameterPhrases = RegExp(
  r'unsupported parameter'
  r'|unrecognized request argument'
  r'|unknown (?:field|parameter)'
  r'|invalid_request_error'
  r'|is not supported',
  caseSensitive: false,
);

/// Maps one failed response onto a [ProbeFailure].
///
/// [statusCode] 0 means the request never got a reply; [message] then carries
/// the transport error so timeouts can be told apart from refused connections.
ProbeFailure classifyFailure({
  required int statusCode,
  String errorCode = '',
  String message = '',
}) {
  final code = errorCode.toLowerCase();
  final text = message.toLowerCase();

  if (statusCode == 0) {
    return text.contains('timed out') || text.contains('timeout')
        ? ProbeFailure.timeout
        : ProbeFailure.network;
  }
  if (statusCode == 401 || statusCode == 403) return ProbeFailure.auth;
  if (statusCode == 413) return ProbeFailure.payloadTooLarge;
  if (statusCode == 429) return ProbeFailure.rateLimited;
  if (statusCode >= 500) return ProbeFailure.serverError;

  if (code == 'context_length_exceeded' || code == 'string_above_max_length') {
    return ProbeFailure.contextLimit;
  }
  if (_contextPhrases.hasMatch(text)) return ProbeFailure.contextLimit;
  if (_outputPhrases.hasMatch(text)) return ProbeFailure.outputLimit;
  if (_parameterPhrases.hasMatch(text)) return ProbeFailure.parameterRejected;
  return ProbeFailure.unknown;
}

// --- Limit extraction from error text ---------------------------------

/// A context window and/or max output length read out of one piece of
/// evidence. Either may be null — most sources only know one of them.
class ProbedLimits {
  const ProbedLimits({this.contextWindow, this.maxOutput});

  final int? contextWindow;
  final int? maxOutput;

  bool get isEmpty => contextWindow == null && maxOutput == null;

  ProbedLimits merge(ProbedLimits other) => ProbedLimits(
    contextWindow: contextWindow ?? other.contextWindow,
    maxOutput: maxOutput ?? other.maxOutput,
  );

  @override
  String toString() => 'ProbedLimits(ctx: $contextWindow, out: $maxOutput)';
}

/// Plausibility bounds. A parsed number outside these is a mis-parse (a
/// timestamp, an error code, a byte count), not a limit.
const int _minContext = 512;
const int _maxContext = 20000000;
const int _minOutput = 16;
const int _maxOutput = 2000000;

/// Patterns that name a *context window*. Each must capture the number in
/// group 1; digit grouping commas are stripped before parsing.
final _contextNumberPatterns = <RegExp>[
  // OpenAI / vLLM / most relays:
  // "This model's maximum context length is 8192 tokens"
  RegExp(
    r'maximum context length is ([\d,]+)',
    caseSensitive: false,
  ),
  RegExp(r'maximum context length \(([\d,]+)\)', caseSensitive: false),
  RegExp(r'context length of ([\d,]+)', caseSensitive: false),
  RegExp(r'context window of ([\d,]+)', caseSensitive: false),
  // vLLM: "the maximum number of tokens for this model (4096)"
  RegExp(
    r'maximum (?:number of )?tokens for this model \(?([\d,]+)\)?',
    caseSensitive: false,
  ),
  RegExp(r'max_model_len \(?([\d,]+)\)?', caseSensitive: false),
  RegExp(r'\bn_ctx\b\D{0,20}([\d,]+)', caseSensitive: false),
];

/// Patterns that name a *max output length*.
final _outputNumberPatterns = <RegExp>[
  // Anthropic: "max_tokens: 999999 > 64000, which is the maximum allowed
  // number of output tokens for claude-…"
  RegExp(
    r'>\s*([\d,]+)[,\s]*which is the maximum allowed number of output tokens',
    caseSensitive: false,
  ),
  RegExp(
    r'maximum (?:allowed )?(?:number of )?(?:output|completion) tokens'
    r'\D{0,30}?([\d,]+)',
    caseSensitive: false,
  ),
  RegExp(
    r'max(?:_completion)?_tokens\D{0,60}?'
    r'(?:less than or equal to|at most|<=|maximum of|maximum is)\s*([\d,]+)',
    caseSensitive: false,
  ),
];

int? _parseGrouped(String raw) => int.tryParse(raw.replaceAll(',', ''));

/// Reads limits out of a server error message.
///
/// [requested] is the value this probe *sent* (the deliberately absurd
/// `max_tokens`, say). Servers echo it back in the message — "you requested
/// 10000000 tokens" — and picking that up would report the number we made up
/// as if the server had told us. Any match equal to it is discarded.
ProbedLimits parseLimitsFromMessage(String message, {int? requested}) {
  if (message.isEmpty) return const ProbedLimits();

  int? pick(List<RegExp> patterns, int min, int max) {
    for (final pattern in patterns) {
      for (final match in pattern.allMatches(message)) {
        final value = _parseGrouped(match.group(1) ?? '');
        if (value == null) continue;
        if (value == requested) continue;
        if (value < min || value > max) continue;
        return value;
      }
    }
    return null;
  }

  return ProbedLimits(
    contextWindow: pick(_contextNumberPatterns, _minContext, _maxContext),
    maxOutput: pick(_outputNumberPatterns, _minOutput, _maxOutput),
  );
}

// --- Limits from `/models` metadata -----------------------------------

/// Keys seen carrying a context window, most specific first. vLLM uses
/// `max_model_len`, OpenRouter `context_length`, LM Studio
/// `max_context_length`; some relays copy one of those, most copy none.
const _contextKeys = [
  'max_model_len',
  'context_length',
  'max_context_length',
  'context_window',
  'contextLength',
  'context_size',
  'n_ctx',
];

const _outputKeys = [
  'max_completion_tokens',
  'max_output_tokens',
  'max_output',
  'maxOutputTokens',
];

/// Nested objects worth looking inside (OpenRouter puts the operative numbers
/// under `top_provider`).
const _nestedKeys = ['top_provider', 'limits', 'capabilities', 'architecture'];

/// Extracts limits from one `/models` entry.
///
/// Deliberately does *not* read a bare `max_tokens` key: on several relays
/// that field means the default request size rather than the model's ceiling,
/// and a wrong small number here is worse than no number at all.
ProbedLimits limitsFromModelEntry(Map<String, dynamic> entry) {
  int? lookup(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      final parsed = value is num
          ? value.toInt()
          : (value is String ? int.tryParse(value.trim()) : null);
      if (parsed != null && parsed > 0) return parsed;
    }
    return null;
  }

  var context = lookup(entry, _contextKeys);
  var output = lookup(entry, _outputKeys);
  for (final key in _nestedKeys) {
    final nested = entry[key];
    if (nested is! Map<String, dynamic>) continue;
    context ??= lookup(nested, _contextKeys);
    output ??= lookup(nested, _outputKeys);
  }

  return ProbedLimits(
    contextWindow: (context != null &&
            context >= _minContext &&
            context <= _maxContext)
        ? context
        : null,
    maxOutput: (output != null && output >= _minOutput && output <= _maxOutput)
        ? output
        : null,
  );
}

/// Finds the entry describing [modelId] in a `/models` payload.
Map<String, dynamic>? findModelEntry(
  List<Map<String, dynamic>> entries,
  String modelId,
) {
  final wanted = modelId.trim().toLowerCase();
  if (wanted.isEmpty) return null;
  for (final entry in entries) {
    if ((entry['id'] ?? '').toString().toLowerCase() == wanted) return entry;
  }
  return null;
}

// --- Backend-specific responses ---------------------------------------

/// What Ollama's `POST /api/show` tells us.
///
/// [modelContextLength] is what the *weights* support; [numCtx] is what the
/// running configuration actually allocates. They routinely differ by more
/// than an order of magnitude, and only [numCtx] governs a request — anything
/// past it is dropped without an error. That asymmetry is the single most
/// valuable thing this whole feature detects.
class OllamaShowInfo {
  const OllamaShowInfo({this.modelContextLength, this.numCtx});

  final int? modelContextLength;
  final int? numCtx;

  bool get isEmpty => modelContextLength == null && numCtx == null;
}

/// Parses `POST /api/show`. Architecture-agnostic: the key is
/// `<arch>.context_length` (`llama.context_length`, `qwen2.context_length`…).
OllamaShowInfo parseOllamaShow(Map<String, dynamic> json) {
  int? modelContext;
  final info = json['model_info'];
  if (info is Map<String, dynamic>) {
    for (final entry in info.entries) {
      if (!entry.key.endsWith('.context_length')) continue;
      final value = entry.value;
      if (value is num && value > 0) {
        modelContext = value.toInt();
        break;
      }
    }
  }

  // `parameters` is the Modelfile text, one "key value" per line.
  int? numCtx;
  final parameters = json['parameters'];
  if (parameters is String) {
    for (final line in parameters.split('\n')) {
      final parts = line.trim().split(RegExp(r'\s+'));
      if (parts.length >= 2 && parts.first == 'num_ctx') {
        numCtx = int.tryParse(parts[1]);
        break;
      }
    }
  }

  return OllamaShowInfo(modelContextLength: modelContext, numCtx: numCtx);
}

/// Pulls `n_ctx` out of llama.cpp's `GET /props`.
///
/// Searched recursively rather than at a fixed path: the field has moved
/// between `default_generation_settings.n_ctx` and
/// `default_generation_settings.params.n_ctx` across releases, and a
/// version-pinned path would silently return nothing on the other one.
int? parseLlamaCppContext(Object? json) {
  if (json is Map) {
    final direct = json['n_ctx'];
    if (direct is num && direct > 0) return direct.toInt();
    for (final value in json.values) {
      final found = parseLlamaCppContext(value);
      if (found != null) return found;
    }
  } else if (json is List) {
    for (final value in json) {
      final found = parseLlamaCppContext(value);
      if (found != null) return found;
    }
  }
  return null;
}

// --- Deterministic filler ---------------------------------------------

/// Ordinary words, so the text tokenizes at a normal rate and does not look
/// like an attack payload to a content filter.
const _fillerWords = [
  'river', 'copper', 'lantern', 'garden', 'method', 'silent', 'harbor',
  'window', 'travel', 'orange', 'pencil', 'bridge', 'forest', 'moment',
  'candle', 'marble', 'signal', 'pocket', 'ribbon', 'summer', 'ticket',
  'valley', 'wander', 'yellow', 'anchor', 'basket', 'cotton', 'dinner',
  'engine', 'fabric', 'gentle', 'hollow', 'island', 'jacket', 'kettle',
  'ladder', 'meadow', 'napkin', 'orchid', 'parcel', 'quarry', 'rocket',
  'saddle', 'temple', 'urgent', 'velvet', 'walnut', 'zenith',
];

/// Builds [words] words of deterministic filler.
///
/// Seeded and non-repeating on purpose. A block of identical text would be
/// collapsed by prefix caches and by some tokenizers, so the token count it
/// produces would not resemble the count real content produces — the
/// calibration derived from it would be wrong in the user's favour and the
/// truncation check would miss.
String buildFiller(int words, {int seed = 20260802}) {
  if (words <= 0) return '';
  final buffer = StringBuffer();
  var state = seed & 0x7fffffff;
  for (var i = 0; i < words; i++) {
    // Park–Miller LCG: reproducible across platforms, unlike Random().
    state = (state * 48271) % 2147483647;
    if (i > 0) buffer.write(i % 12 == 0 ? '.\n' : ' ');
    buffer.write(_fillerWords[state % _fillerWords.length]);
  }
  return buffer.toString();
}

// --- Token calibration -------------------------------------------------

/// The server's own tokens-per-word rate for this model, plus the fixed cost
/// of the request envelope (chat template, role markers, system prompt).
class TokenCalibration {
  const TokenCalibration({
    required this.tokensPerWord,
    required this.overheadTokens,
  });

  final double tokensPerWord;
  final double overheadTokens;

  int expectedTokens(int words) =>
      (overheadTokens + tokensPerWord * words).round();

  /// How many filler words it takes to fill [tokens].
  int wordsForTokens(int tokens) {
    final usable = tokens - overheadTokens;
    if (usable <= 0 || tokensPerWord <= 0) return 0;
    return (usable / tokensPerWord).floor();
  }
}

/// Derives the rate from two measurements of different lengths.
///
/// Taking the *difference* rather than a single ratio is what removes the
/// envelope overhead: a one-point estimate folds the template's fixed tokens
/// into the per-word rate and then over-predicts every larger prompt.
///
/// Returns null when the two points cannot yield a sane line (equal sizes, a
/// server that reports no usage, or counts that move the wrong way).
TokenCalibration? calibrate({
  required int smallWords,
  required int smallTokens,
  required int largeWords,
  required int largeTokens,
}) {
  if (largeWords <= smallWords) return null;
  if (smallTokens <= 0 || largeTokens <= smallTokens) return null;
  final rate = (largeTokens - smallTokens) / (largeWords - smallWords);
  if (rate <= 0) return null;
  final overhead = smallTokens - rate * smallWords;
  return TokenCalibration(
    tokensPerWord: rate,
    overheadTokens: overhead < 0 ? 0 : overhead,
  );
}

/// How far below prediction a reported prompt size must fall before we call
/// it truncation. Generous on purpose: tokenizer drift between the calibration
/// sample and the big prompt is normal, silently dropping 90% of the prompt is
/// not. A false "your backend is broken" is more damaging than a missed one,
/// and the negative result is already reported as inconclusive.
const double truncationRatio = 0.8;

/// Verdict of the one large-prompt check.
enum TruncationVerdict {
  /// Reported prompt size matched prediction — *not* proof of correctness:
  /// some servers report the pre-truncation count and some invent usage
  /// numbers entirely. Only the positive result is conclusive.
  notDetected,

  /// Reported prompt size came in far under prediction: content was dropped.
  detected,

  /// No usable usage came back, so nothing can be said either way.
  inconclusive,
}

TruncationVerdict judgeTruncation({
  required int expectedTokens,
  required int reportedTokens,
}) {
  if (reportedTokens <= 0 || expectedTokens <= 0) {
    return TruncationVerdict.inconclusive;
  }
  return reportedTokens < expectedTokens * truncationRatio
      ? TruncationVerdict.detected
      : TruncationVerdict.notDetected;
}

// --- Report ------------------------------------------------------------

/// Where one finding came from, ordered weakest to strongest. The order is
/// the resolution order in [CapabilityReport]: a number the server produced
/// while refusing a request beats one copied out of a model catalogue.
enum CapabilitySource { listing, backendApi, errorMessage, measured }

class CapabilityFinding {
  const CapabilityFinding({
    required this.source,
    required this.detail,
    this.contextWindow,
    this.maxOutput,
  });

  final CapabilitySource source;

  /// Raw evidence, in the server's own words. Never localized — a truncated
  /// error string is the thing a user forwards when asking for help.
  final String detail;

  final int? contextWindow;
  final int? maxOutput;
}

/// Everything one detection run learned.
class CapabilityReport {
  CapabilityReport({
    List<CapabilityFinding>? findings,
    List<String>? notes,
    this.truncation = TruncationVerdict.inconclusive,
    this.effectiveContextWindow,
  }) : findings = findings ?? [],
       notes = notes ?? [];

  final List<CapabilityFinding> findings;

  /// Diagnostics that are not limits: which step was skipped, what a backend
  /// claims the weights support, why a probe was inconclusive.
  final List<String> notes;

  TruncationVerdict truncation;

  /// Tokens the server actually accepted when truncation was detected.
  int? effectiveContextWindow;

  bool get isEmpty => findings.isEmpty;

  int _rank(CapabilitySource s) => CapabilitySource.values.indexOf(s);

  T? _best<T>(T? Function(CapabilityFinding) read) {
    T? best;
    var bestRank = -1;
    for (final finding in findings) {
      final value = read(finding);
      if (value == null) continue;
      final rank = _rank(finding.source);
      if (rank >= bestRank) {
        best = value;
        bestRank = rank;
      }
    }
    return best;
  }

  /// Best available context window, strongest source wins.
  int? get contextWindow => _best((f) => f.contextWindow);

  int? get maxOutput => _best((f) => f.maxOutput);
}
