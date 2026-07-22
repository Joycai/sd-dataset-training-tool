import 'dart:convert';

/// Preset swatches for group colors (ARGB). Deliberately distinct from the
/// theme's semantic colors (teal accent, green ok, amber warn, red danger) so
/// group tints never read as a state.
const List<int> kTagGroupPresetColors = [
  0xFF6A9BDD, // blue
  0xFF9B84E0, // purple
  0xFFD983A6, // pink
  0xFFD9925B, // orange
  0xFF5FBF8F, // mint
  0xFFC7B45A, // gold
  0xFF8A9BB0, // slate
  0xFFB08A6A, // brown
];

/// A named, colored group of library tags. Pure data — persistence is a JSON
/// list handled by [encodeTagGroups] / [decodeTagGroups].
///
/// Membership is exclusive: a tag lives in at most one group; everything else
/// is implicitly "ungrouped". Enforced by AppState.moveTagsToGroup, not here.
class TagGroup {
  const TagGroup({
    required this.id,
    required this.name,
    required this.color,
    required this.tags,
  });

  final String id;
  final String name;

  /// ARGB value; usually one of [kTagGroupPresetColors] but any custom color
  /// from the picker is allowed.
  final int color;

  final List<String> tags;

  TagGroup copyWith({String? name, int? color, List<String>? tags}) {
    return TagGroup(
      id: id,
      name: name ?? this.name,
      color: color ?? this.color,
      tags: tags ?? this.tags,
    );
  }

  factory TagGroup.fromJson(Map<String, dynamic> json) {
    return TagGroup(
      id: json['id'] as String,
      name: json['name'] as String,
      color: json['color'] as int,
      tags: (json['tags'] as List<dynamic>).cast<String>(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'color': color,
        'tags': tags,
      };
}

String encodeTagGroups(List<TagGroup> groups) =>
    jsonEncode([for (final g in groups) g.toJson()]);

List<TagGroup> decodeTagGroups(String json) {
  try {
    final list = jsonDecode(json) as List<dynamic>;
    return [
      for (final item in list) TagGroup.fromJson(item as Map<String, dynamic>),
    ];
  } on FormatException {
    // A corrupt preference should not brick the library — start over.
    return const [];
  } on TypeError {
    return const [];
  }
}
