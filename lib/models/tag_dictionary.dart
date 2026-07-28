/// Danbooru's own tag category numbers. Every dictionary source encodes them
/// directly — the API, the WD tagger's label file and the tagcomplete CSV all
/// agree on these values, which is why they are stored raw rather than
/// remapped per source.
enum TagCategory {
  general(0),
  artist(1),
  copyright(3),
  character(4),
  meta(5);

  const TagCategory(this.id);

  final int id;

  /// Null for ids this app does not model — notably 9, the WD label file's
  /// "rating" pseudo-category (general/sensitive/questionable/explicit). Those
  /// are model outputs, not danbooru tags, and must not reach the dictionary.
  static TagCategory? fromId(int id) => switch (id) {
    0 => TagCategory.general,
    1 => TagCategory.artist,
    3 => TagCategory.copyright,
    4 => TagCategory.character,
    5 => TagCategory.meta,
    _ => null,
  };
}

/// One dictionary entry: a canonical danbooru tag plus the metadata the
/// suggestion list ranks and renders with.
class TagDictionaryEntry {
  const TagDictionaryEntry({
    required this.name,
    required this.category,
    required this.postCount,
    this.aliases = const [],
  });

  /// The canonical name in danbooru's own spelling — underscored, unescaped
  /// (`hatsune_miku`, `smile_(expression)`). Converting to the user's caption
  /// style is the caller's job, so one dictionary serves every style.
  final String name;

  final TagCategory category;

  /// Danbooru post count; the primary ranking signal between equally good
  /// textual matches.
  final int postCount;

  /// Deprecated or alternate spellings that resolve to [name]. Only the full
  /// dictionary carries these — the WD label file has no alias column.
  final List<String> aliases;
}

/// How well a dictionary entry matched the query. Ordered best-first; the
/// suggestion list sorts on this before falling back to post count.
enum TagMatchKind {
  /// The query is the whole canonical name.
  exactName,

  /// The query is a whole alias of the canonical name.
  exactAlias,

  /// The canonical name starts with the query.
  namePrefix,

  /// Some word inside the canonical name starts with the query, so typing
  /// "hair" reaches `long_hair` and `hair_ornament`.
  nameWordPrefix,

  /// An alias starts with the query.
  aliasPrefix,
}

/// Where a suggestion came from.
enum TagSuggestionOrigin {
  /// The danbooru dictionary — bundled or downloaded.
  dictionary,

  /// The user's own vocabulary: tags in this dataset or in the tag library
  /// that danbooru has never heard of. Trigger words, private character
  /// names, project conventions.
  local,
}

/// A ranked hit produced by [TagDictionaryService.search].
class TagSuggestion {
  const TagSuggestion({
    required this.entry,
    required this.kind,
    this.origin = TagSuggestionOrigin.dictionary,
    this.matchedAlias,
  });

  final TagDictionaryEntry entry;
  final TagMatchKind kind;
  final TagSuggestionOrigin origin;

  /// The alias that produced the hit, when the query did not match the
  /// canonical name. The list shows it so an alias hit does not look like a
  /// mismatch.
  final String? matchedAlias;

  String get name => entry.name;

  bool get isLocal => origin == TagSuggestionOrigin.local;

  /// For a dictionary hit, danbooru's post count. For a local hit, how many
  /// images in the dataset carry the tag (0 when it only exists in the tag
  /// library) — a different unit, so the list must not render them alike.
  int get count => entry.postCount;
}
