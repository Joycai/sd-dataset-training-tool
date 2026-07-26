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
  }) =>
      LlmProviderProfile(
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

String encodeLlmProfiles(List<LlmProviderProfile> profiles) =>
    jsonEncode([for (final p in profiles) p.toJson()]);

List<LlmProviderProfile> decodeLlmProfiles(String json) {
  try {
    final decoded = jsonDecode(json);
    if (decoded is! List) return const [];
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(LlmProviderProfile.fromJson)
        .where((p) => p.id.isNotEmpty)
        .toList();
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

  const ChatContentPart.image(Uint8List this.imageBytes,
      {this.imageMimeType = 'image/jpeg'})
      : text = null;

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
  }) : parts = parts ?? [];

  factory ChatMessage.system(String text) =>
      ChatMessage(role: ChatRole.system, parts: [ChatContentPart.text(text)]);

  factory ChatMessage.user(String text) =>
      ChatMessage(role: ChatRole.user, parts: [ChatContentPart.text(text)]);

  factory ChatMessage.assistant(String text,
          {List<ChatToolCall> toolCalls = const []}) =>
      ChatMessage(
        role: ChatRole.assistant,
        parts: [if (text.isNotEmpty) ChatContentPart.text(text)],
        toolCalls: toolCalls,
      );

  factory ChatMessage.toolResult({
    required String toolCallId,
    required String text,
    List<ChatContentPart> extraParts = const [],
  }) =>
      ChatMessage(
        role: ChatRole.tool,
        parts: [ChatContentPart.text(text), ...extraParts],
        toolCallId: toolCallId,
      );

  final ChatRole role;

  /// Mutable on purpose: [ContextBudget.compact] replaces elided content.
  List<ChatContentPart> parts;

  final List<ChatToolCall> toolCalls;
  final String? toolCallId;

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
