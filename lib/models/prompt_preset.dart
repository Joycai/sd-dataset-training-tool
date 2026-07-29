import 'dart:convert';

/// A saved prompt the user can drop into the assistant's input box.
///
/// Pure data — persistence is a JSON list handled by [encodePromptPresets] /
/// [decodePromptPresets], mirroring how tag groups are stored.
class PromptPreset {
  const PromptPreset({
    required this.id,
    this.title = '',
    this.content = '',
  });

  final String id;

  /// What the picker shows. May be empty while the user is still typing one;
  /// the UI falls back to a placeholder label then.
  final String title;

  /// The text inserted into the input box.
  final String content;

  PromptPreset copyWith({String? title, String? content}) => PromptPreset(
    id: id,
    title: title ?? this.title,
    content: content ?? this.content,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'content': content,
  };

  factory PromptPreset.fromJson(Map<String, dynamic> json) => PromptPreset(
    id: json['id'] as String,
    title: (json['title'] as String?) ?? '',
    content: (json['content'] as String?) ?? '',
  );
}

String encodePromptPresets(List<PromptPreset> presets) =>
    jsonEncode([for (final p in presets) p.toJson()]);

/// Tolerant on purpose: a corrupt preference should cost the user their
/// presets, not the whole assistant panel.
List<PromptPreset> decodePromptPresets(String json) {
  try {
    final decoded = jsonDecode(json);
    if (decoded is! List) return const [];
    return [
      for (final raw in decoded.whereType<Map<String, dynamic>>())
        if (raw['id'] is String) PromptPreset.fromJson(raw),
    ];
  } catch (_) {
    return const [];
  }
}
