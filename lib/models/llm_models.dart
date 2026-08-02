/// Data models for the LLM agent assistant: provider profiles, the
/// protocol-neutral chat message shapes, tool specs, and stream events.
///
/// Nothing here imports Flutter — it is pure data, mirroring the style of
/// `ai_tagger_models.dart`.
library;

import 'dart:convert';
import 'dart:typed_data';

/// Which wire protocol a provider speaks.
///
/// [openaiCompat] covers OpenAI, newapi/one-api style relays, Ollama's
/// `/v1` compatibility layer, and Gemini's OpenAI-compatible endpoint.
/// [anthropic] is the native Anthropic Messages API.
enum LlmApiKind {
  openaiCompat('openai'),
  anthropic('anthropic');

  const LlmApiKind(this.id);

  final String id;

  static LlmApiKind fromId(String? id) => LlmApiKind.values.firstWhere(
    (e) => e.id == id,
    orElse: () => LlmApiKind.openaiCompat,
  );
}

/// One saved LLM backend configuration. Users can keep several (e.g. an
/// OpenAI profile, a local Ollama profile) and switch the active one.
class LlmProviderProfile {
  const LlmProviderProfile({
    required this.id,
    required this.name,
    this.kind = LlmApiKind.openaiCompat,
    this.baseUrl = '',
    this.apiKey = '',
    this.model = '',
    this.supportsVision = false,
    this.contextWindow = 32768,
    this.maxOutputTokens = 4096,
    this.temperature = 0.7,
  });

  final String id;
  final String name;
  final LlmApiKind kind;

  /// For [LlmApiKind.openaiCompat] this is the URL up to and including the
  /// version segment (e.g. `https://api.openai.com/v1`); the client appends
  /// `/chat/completions`. For [LlmApiKind.anthropic] the host root
  /// (`https://api.anthropic.com`).
  final String baseUrl;

  /// May be empty for local backends (Ollama).
  final String apiKey;

  final String model;

  /// Whether the model accepts image content; gates the image tools.
  final bool supportsVision;

  /// Model context window in tokens, set by the user per model.
  final int contextWindow;

  final int maxOutputTokens;
  final double temperature;

  LlmProviderProfile copyWith({
    String? name,
    LlmApiKind? kind,
    String? baseUrl,
    String? apiKey,
    String? model,
    bool? supportsVision,
    int? contextWindow,
    int? maxOutputTokens,
    double? temperature,
  }) => LlmProviderProfile(
    id: id,
    name: name ?? this.name,
    kind: kind ?? this.kind,
    baseUrl: baseUrl ?? this.baseUrl,
    apiKey: apiKey ?? this.apiKey,
    model: model ?? this.model,
    supportsVision: supportsVision ?? this.supportsVision,
    contextWindow: contextWindow ?? this.contextWindow,
    maxOutputTokens: maxOutputTokens ?? this.maxOutputTokens,
    temperature: temperature ?? this.temperature,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'kind': kind.id,
    'baseUrl': baseUrl,
    'apiKey': apiKey,
    'model': model,
    'supportsVision': supportsVision,
    'contextWindow': contextWindow,
    'maxOutputTokens': maxOutputTokens,
    'temperature': temperature,
  };

  factory LlmProviderProfile.fromJson(Map<String, dynamic> json) =>
      LlmProviderProfile(
        id: (json['id'] as String?) ?? '',
        name: (json['name'] as String?) ?? '',
        kind: LlmApiKind.fromId(json['kind'] as String?),
        baseUrl: (json['baseUrl'] as String?) ?? '',
        apiKey: (json['apiKey'] as String?) ?? '',
        model: (json['model'] as String?) ?? '',
        supportsVision: (json['supportsVision'] as bool?) ?? false,
        contextWindow: (json['contextWindow'] as num?)?.toInt() ?? 32768,
        maxOutputTokens: (json['maxOutputTokens'] as num?)?.toInt() ?? 4096,
        temperature: (json['temperature'] as num?)?.toDouble() ?? 0.7,
      );

  /// Base URL presets offered by the settings UI, keyed by display label.
  static const Map<String, (LlmApiKind, String)> presets = {
    'OpenAI': (LlmApiKind.openaiCompat, 'https://api.openai.com/v1'),
    'Gemini (OpenAI compat)': (
      LlmApiKind.openaiCompat,
      'https://generativelanguage.googleapis.com/v1beta/openai',
    ),
    'Ollama': (LlmApiKind.openaiCompat, 'http://127.0.0.1:11434/v1'),
    'Anthropic': (LlmApiKind.anthropic, 'https://api.anthropic.com'),
  };
}

// --- Provider -> model tree -----------------------------------------
//
// Endpoint and credentials belong to the provider and are entered once;
// each model under it carries only what varies per model.
// [LlmProviderProfile] stays as the *resolved* pair handed to the clients,
// so nothing downstream had to learn about the tree.

/// Per-Mtoken prices, for usage accounting. Optional: an all-zero record
/// means "not tracked" and is dropped on save.
class LlmPricing {
  const LlmPricing({
    this.input = 0,
    this.output = 0,
    this.cacheRead = 0,
    this.cacheWrite = 0,
  });

  final double input;
  final double output;

  /// Reading from a prompt cache — usually far cheaper than fresh input.
  final double cacheRead;

  /// Writing a prompt cache entry (Anthropic bills this separately).
  final double cacheWrite;

  bool get isEmpty =>
      input == 0 && output == 0 && cacheRead == 0 && cacheWrite == 0;

  LlmPricing copyWith({
    double? input,
    double? output,
    double? cacheRead,
    double? cacheWrite,
  }) => LlmPricing(
    input: input ?? this.input,
    output: output ?? this.output,
    cacheRead: cacheRead ?? this.cacheRead,
    cacheWrite: cacheWrite ?? this.cacheWrite,
  );

  Map<String, dynamic> toJson() => {
    'input': input,
    'output': output,
    'cacheRead': cacheRead,
    'cacheWrite': cacheWrite,
  };

  factory LlmPricing.fromJson(Map<String, dynamic> json) => LlmPricing(
    input: (json['input'] as num?)?.toDouble() ?? 0,
    output: (json['output'] as num?)?.toDouble() ?? 0,
    cacheRead: (json['cacheRead'] as num?)?.toDouble() ?? 0,
    cacheWrite: (json['cacheWrite'] as num?)?.toDouble() ?? 0,
  );
}

/// One model under a provider.
class LlmModelConfig {
  const LlmModelConfig({
    required this.id,
    required this.modelId,
    this.displayName = '',
    this.contextWindow = 32768,
    this.maxOutputTokens = 4096,
    this.temperature = 0.7,
    this.supportsVision = false,
    this.pricing,
    this.measuredContextWindow = 0,
    this.measuredMaxOutput = 0,
    this.measuredAt = '',
    this.silentTruncation = false,
  });

  /// Stable local id; the wire name is [modelId] and may change.
  final String id;

  /// What goes in the request body.
  final String modelId;

  final String displayName;
  final int contextWindow;
  final int maxOutputTokens;
  final double temperature;
  final bool supportsVision;
  final LlmPricing? pricing;

  // --- Detection results ------------------------------------------------
  //
  // Kept apart from the four fields above, which the user owns. Detection
  // proposes; only the user applies. Overwriting a hand-set value with a
  // measurement would make a relay's bad day look like a settings change.

  /// Context window detection found, 0 when never detected.
  final int measuredContextWindow;

  /// Max output length detection found, 0 when never detected.
  final int measuredMaxOutput;

  /// ISO-8601 timestamp of the last detection run, empty when never run.
  /// A measurement against a relay is a sample of one moment — the same model
  /// name can route elsewhere tomorrow — so the reading is only meaningful
  /// alongside when it was taken.
  final String measuredAt;

  /// The endpoint accepted an over-long prompt and quietly dropped part of
  /// it. Only ever set from a positive detection: not being set means
  /// "nothing found", never "verified clean".
  final bool silentTruncation;

  String get label => displayName.trim().isEmpty ? modelId : displayName;

  bool get hasMeasurement => measuredAt.isNotEmpty;

  LlmModelConfig copyWith({
    String? modelId,
    String? displayName,
    int? contextWindow,
    int? maxOutputTokens,
    double? temperature,
    bool? supportsVision,
    LlmPricing? pricing,
    bool clearPricing = false,
    int? measuredContextWindow,
    int? measuredMaxOutput,
    String? measuredAt,
    bool? silentTruncation,
  }) => LlmModelConfig(
    id: id,
    modelId: modelId ?? this.modelId,
    displayName: displayName ?? this.displayName,
    contextWindow: contextWindow ?? this.contextWindow,
    maxOutputTokens: maxOutputTokens ?? this.maxOutputTokens,
    temperature: temperature ?? this.temperature,
    supportsVision: supportsVision ?? this.supportsVision,
    pricing: clearPricing ? null : (pricing ?? this.pricing),
    measuredContextWindow: measuredContextWindow ?? this.measuredContextWindow,
    measuredMaxOutput: measuredMaxOutput ?? this.measuredMaxOutput,
    measuredAt: measuredAt ?? this.measuredAt,
    silentTruncation: silentTruncation ?? this.silentTruncation,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'modelId': modelId,
    'displayName': displayName,
    'contextWindow': contextWindow,
    'maxOutputTokens': maxOutputTokens,
    'temperature': temperature,
    'supportsVision': supportsVision,
    if (pricing != null && !pricing!.isEmpty) 'pricing': pricing!.toJson(),
    if (measuredContextWindow > 0) 'measuredContextWindow':
        measuredContextWindow,
    if (measuredMaxOutput > 0) 'measuredMaxOutput': measuredMaxOutput,
    if (measuredAt.isNotEmpty) 'measuredAt': measuredAt,
    if (silentTruncation) 'silentTruncation': true,
  };

  factory LlmModelConfig.fromJson(Map<String, dynamic> json) => LlmModelConfig(
    id: (json['id'] as String?) ?? '',
    modelId: (json['modelId'] as String?) ?? '',
    displayName: (json['displayName'] as String?) ?? '',
    contextWindow: (json['contextWindow'] as num?)?.toInt() ?? 32768,
    maxOutputTokens: (json['maxOutputTokens'] as num?)?.toInt() ?? 4096,
    temperature: (json['temperature'] as num?)?.toDouble() ?? 0.7,
    supportsVision: (json['supportsVision'] as bool?) ?? false,
    pricing: json['pricing'] is Map<String, dynamic>
        ? LlmPricing.fromJson(json['pricing'] as Map<String, dynamic>)
        : null,
    measuredContextWindow:
        (json['measuredContextWindow'] as num?)?.toInt() ?? 0,
    measuredMaxOutput: (json['measuredMaxOutput'] as num?)?.toInt() ?? 0,
    measuredAt: (json['measuredAt'] as String?) ?? '',
    silentTruncation: (json['silentTruncation'] as bool?) ?? false,
  );
}

/// An endpoint plus its credentials, holding one or more models.
class LlmProvider {
  const LlmProvider({
    required this.id,
    required this.name,
    this.kind = LlmApiKind.openaiCompat,
    this.baseUrl = '',
    this.apiKey = '',
    this.models = const [],
  });

  /// Model id assigned when a pre-tree flat backend is read in.
  static const String legacyModelId = 'default';

  final String id;
  final String name;
  final LlmApiKind kind;
  final String baseUrl;
  final String apiKey;
  final List<LlmModelConfig> models;

  LlmProvider copyWith({
    String? name,
    LlmApiKind? kind,
    String? baseUrl,
    String? apiKey,
    List<LlmModelConfig>? models,
  }) => LlmProvider(
    id: id,
    name: name ?? this.name,
    kind: kind ?? this.kind,
    baseUrl: baseUrl ?? this.baseUrl,
    apiKey: apiKey ?? this.apiKey,
    models: models ?? this.models,
  );

  /// The flat shape the chat session and the HTTP clients consume.
  LlmProviderProfile resolve(LlmModelConfig model) => LlmProviderProfile(
    id: '$id/${model.id}',
    name: models.length <= 1 ? name : '$name · ${model.label}',
    kind: kind,
    baseUrl: baseUrl,
    apiKey: apiKey,
    model: model.modelId,
    supportsVision: model.supportsVision,
    contextWindow: model.contextWindow,
    maxOutputTokens: model.maxOutputTokens,
    temperature: model.temperature,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'kind': kind.id,
    'baseUrl': baseUrl,
    'apiKey': apiKey,
    'models': [for (final m in models) m.toJson()],
  };

  factory LlmProvider.fromJson(Map<String, dynamic> json) => LlmProvider(
    id: (json['id'] as String?) ?? '',
    name: (json['name'] as String?) ?? '',
    kind: LlmApiKind.fromId(json['kind'] as String?),
    baseUrl: (json['baseUrl'] as String?) ?? '',
    apiKey: (json['apiKey'] as String?) ?? '',
    models: [
      for (final raw in (json['models'] as List<dynamic>? ?? const []))
        if (raw is Map<String, dynamic>) LlmModelConfig.fromJson(raw),
    ],
  );

  /// Reads a pre-tree entry — one flat backend — as a provider holding the
  /// single model it named. Same storage key, so upgrading costs the user
  /// nothing and the tree writes itself back on the next save.
  factory LlmProvider.fromLegacyJson(Map<String, dynamic> json) {
    final profile = LlmProviderProfile.fromJson(json);
    return LlmProvider(
      id: profile.id,
      name: profile.name,
      kind: profile.kind,
      baseUrl: profile.baseUrl,
      apiKey: profile.apiKey,
      models: [
        LlmModelConfig(
          id: legacyModelId,
          modelId: profile.model,
          contextWindow: profile.contextWindow,
          maxOutputTokens: profile.maxOutputTokens,
          temperature: profile.temperature,
          supportsVision: profile.supportsVision,
        ),
      ],
    );
  }
}

String encodeLlmProviders(List<LlmProvider> providers) =>
    jsonEncode([for (final p in providers) p.toJson()]);

/// Accepts both the tree shape and the flat pre-tree shape, so the stored
/// value migrates itself the first time it is read.
List<LlmProvider> decodeLlmProviders(String json) {
  try {
    final decoded = jsonDecode(json);
    if (decoded is! List) return const [];
    return [
      for (final raw in decoded.whereType<Map<String, dynamic>>())
        raw.containsKey('models')
            ? LlmProvider.fromJson(raw)
            : LlmProvider.fromLegacyJson(raw),
    ].where((p) => p.id.isNotEmpty).toList();
  } catch (_) {
    return const [];
  }
}

// --- Chat messages (protocol neutral) --------------------------------

enum ChatRole { system, user, assistant, tool }

/// One piece of message content: text or an (already downscaled) image.
class ChatContentPart {
  const ChatContentPart.text(String this.text)
    : imageBytes = null,
      imageMimeType = null;

  const ChatContentPart.image(
    Uint8List this.imageBytes, {
    this.imageMimeType = 'image/jpeg',
  }) : text = null;

  final String? text;
  final Uint8List? imageBytes;
  final String? imageMimeType;

  bool get isImage => imageBytes != null;
}

/// A tool invocation requested by the model. [argumentsJson] is kept as the
/// raw string so malformed JSON can be reported back to the model verbatim.
class ChatToolCall {
  const ChatToolCall({
    required this.id,
    required this.name,
    required this.argumentsJson,
  });

  final String id;
  final String name;
  final String argumentsJson;
}

class ChatMessage {
  ChatMessage({
    required this.role,
    List<ChatContentPart>? parts,
    this.toolCalls = const [],
    this.toolCallId,
    this.pinned = false,
  }) : parts = parts ?? [];

  factory ChatMessage.system(String text) =>
      ChatMessage(role: ChatRole.system, parts: [ChatContentPart.text(text)]);

  factory ChatMessage.user(String text) =>
      ChatMessage(role: ChatRole.user, parts: [ChatContentPart.text(text)]);

  factory ChatMessage.assistant(
    String text, {
    List<ChatToolCall> toolCalls = const [],
  }) => ChatMessage(
    role: ChatRole.assistant,
    parts: [if (text.isNotEmpty) ChatContentPart.text(text)],
    toolCalls: toolCalls,
  );

  factory ChatMessage.toolResult({
    required String toolCallId,
    required String text,
    List<ChatContentPart> extraParts = const [],
    bool pinned = false,
  }) => ChatMessage(
    role: ChatRole.tool,
    parts: [ChatContentPart.text(text), ...extraParts],
    toolCallId: toolCallId,
    pinned: pinned,
  );

  final ChatRole role;

  /// Mutable on purpose: [ContextBudget.compact] replaces elided content.
  List<ChatContentPart> parts;

  final List<ChatToolCall> toolCalls;
  final String? toolCallId;

  /// Content the model is still expected to be working from verbatim (the
  /// captions it is reordering, say). Compaction folds pinned messages only
  /// as a last resort — see [ContextBudget.compact].
  final bool pinned;

  String get text =>
      parts.where((p) => p.text != null).map((p) => p.text).join();

  int get imageCount => parts.where((p) => p.isImage).length;
}

/// The JSON-schema description of one tool, as sent to the model.
class AgentToolSpec {
  const AgentToolSpec({
    required this.name,
    required this.description,
    required this.parametersSchema,
  });

  final String name;
  final String description;

  /// A JSON Schema object (`{"type": "object", "properties": ...}`).
  final Map<String, dynamic> parametersSchema;
}

// --- Stream events ----------------------------------------------------

class TokenUsage {
  const TokenUsage({this.prompt = 0, this.completion = 0});

  final int prompt;
  final int completion;

  int get total => prompt + completion;

  TokenUsage operator +(TokenUsage other) => TokenUsage(
    prompt: prompt + other.prompt,
    completion: completion + other.completion,
  );
}

sealed class LlmStreamEvent {}

class TextDelta extends LlmStreamEvent {
  TextDelta(this.text);

  final String text;
}

/// Emitted once per response, before [StreamDone], when the model requested
/// tool calls. Arguments are fully accumulated at this point.
class ToolCallsReady extends LlmStreamEvent {
  ToolCallsReady(this.calls);

  final List<ChatToolCall> calls;
}

class StreamDone extends LlmStreamEvent {
  StreamDone({this.finishReason = '', this.usage});

  final String finishReason;
  final TokenUsage? usage;
}
