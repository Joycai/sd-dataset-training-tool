import 'dart:convert';

import '../state/dataset_state.dart';

/// How a caption type's file content is structured. The format — not the
/// file extension — is what decides how the app parses, displays and
/// rewrites a caption: `.json` is only a convention, and nothing stops a
/// user from keeping JSON captions in `.anima` files.
enum CaptionFormat {
  /// Comma-separated danbooru-style tags (WD14).
  tags,

  /// One JSON document per caption. The tag views give way to a read-only
  /// highlighted JSON view, and tag-level rewrites are refused — structured
  /// captions are edited as text or through the assistant's JSON tools.
  json,

  /// Natural-language prose: the tag views segment the text by `,` and `.`
  /// (plus their full-width forms) instead of treating it as tags.
  prose;

  static CaptionFormat fromName(String? name) => switch (name) {
    'json' => CaptionFormat.json,
    'prose' => CaptionFormat.prose,
    _ => CaptionFormat.tags,
  };
}

/// One flavor of caption file a dataset can carry — e.g. `.txt` holding
/// WD14-style tags next to `.ntxt` holding a natural-language description.
///
/// The whole app operates on exactly one type at a time (the active one);
/// the others exist so the navigator can switch between them and the
/// assistant can audit / convert one into another.
///
/// Pure data — persistence is a JSON list handled by [encodeCaptionTypes] /
/// [decodeCaptionTypes], mirroring how prompt presets are stored.
class CaptionType {
  const CaptionType({
    required this.id,
    this.name = '',
    required this.extension,
    this.enabled = true,
    this.format = CaptionFormat.tags,
  });

  /// The id of the built-in type. It always exists, is always enabled, and
  /// carries the legacy single-extension setting forward.
  static const String defaultId = 'default';

  final String id;

  /// Display label ("WD14", "NLP"…). May be empty; the UI falls back to the
  /// extension then.
  final String name;

  /// Caption file suffix including the dot, e.g. `.txt`.
  final String extension;

  /// Disabled types keep their definition but disappear from the navigator
  /// switcher and the assistant's variant tools.
  final bool enabled;

  /// The content structure of this type's caption files. See
  /// [CaptionFormat] — everything that parses or rewrites a caption keys on
  /// this, never on the extension.
  final CaptionFormat format;

  bool get isDefault => id == defaultId;

  /// What pickers and tool results call this type.
  String get label => name.trim().isEmpty ? extension : name.trim();

  CaptionType copyWith({
    String? name,
    String? extension,
    bool? enabled,
    CaptionFormat? format,
  }) => CaptionType(
    id: id,
    name: name ?? this.name,
    extension: extension ?? this.extension,
    enabled: enabled ?? this.enabled,
    format: format ?? this.format,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'extension': extension,
    'enabled': enabled,
    'format': format.name,
  };

  factory CaptionType.fromJson(Map<String, dynamic> json) => CaptionType(
    id: json['id'] as String,
    name: (json['name'] as String?) ?? '',
    extension: (json['extension'] as String?) ?? '',
    enabled: (json['enabled'] as bool?) ?? true,
    // Prefs written before formats existed carry `prose: true/false`.
    format: json['format'] is String
        ? CaptionFormat.fromName(json['format'] as String)
        : (json['prose'] == true ? CaptionFormat.prose : CaptionFormat.tags),
  );
}

String encodeCaptionTypes(List<CaptionType> types) =>
    jsonEncode([for (final t in types) t.toJson()]);

/// Tolerant on purpose: a corrupt preference should cost the user their
/// extra caption types, not the whole app.
List<CaptionType> decodeCaptionTypes(String json) {
  try {
    final decoded = jsonDecode(json);
    if (decoded is! List) return const [];
    return [
      for (final raw in decoded.whereType<Map<String, dynamic>>())
        if (raw['id'] is String) CaptionType.fromJson(raw),
    ];
  } catch (_) {
    return const [];
  }
}

/// Normalizes a user-typed caption extension: trimmed, lowercased, exactly
/// one leading dot. Returns null when nothing usable remains or the result
/// could not name a caption file (path separators, an image extension —
/// writing captions over `.png` files must be impossible to configure).
String? normalizeCaptionExtension(String input) {
  var value = input.trim().toLowerCase();
  while (value.startsWith('.')) {
    value = value.substring(1);
  }
  if (value.isEmpty ||
      value.contains(RegExp(r'[\\/\s.]')) ||
      DatasetState.supportedExtensions.contains('.$value')) {
    return null;
  }
  return '.$value';
}

/// Brings a caption-type list back to its invariants: the default type
/// exists, sits first and is enabled; every extension is normalized; a
/// duplicated extension keeps its first occurrence. Invalid entries are
/// dropped (the default falls back to `.txt` instead).
List<CaptionType> sanitizeCaptionTypes(List<CaptionType> types) {
  final seen = <String>{};
  CaptionType? defaultType;
  final rest = <CaptionType>[];
  for (final type in types) {
    final extension = normalizeCaptionExtension(type.extension);
    if (type.isDefault) {
      defaultType ??= type.copyWith(
        extension: extension ?? '.txt',
        enabled: true,
      );
      continue;
    }
    if (extension == null) continue;
    rest.add(type.copyWith(extension: extension));
  }
  defaultType ??= const CaptionType(
    id: CaptionType.defaultId,
    extension: '.txt',
  );
  seen.add(defaultType.extension);
  return [
    defaultType,
    for (final type in rest)
      if (seen.add(type.extension)) type,
  ];
}
