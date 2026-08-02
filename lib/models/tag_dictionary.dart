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
    // Defaulted for hand-added entries, which have no danbooru presence to
    // count. Every dictionary source supplies it explicitly.
    this.postCount = 0,
    this.aliases = const [],
    this.autocomplete = true,
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

  /// Whether the caption editor may offer this entry as a completion.
  ///
  /// Only a user-added entry can turn this off, and the reason is narrow but
  /// real: a private tag worth *translating* is not always a tag worth
  /// *suggesting*. Retired spellings and one-off dataset words belong in the
  /// glossary so their gloss renders, and nowhere near the type-ahead. Always
  /// true for entries parsed out of a dictionary CSV, which is the whole point
  /// of downloading one.
  final bool autocomplete;

  Map<String, dynamic> toJson() => {
    'name': name,
    'category': category.id,
    if (postCount != 0) 'count': postCount,
    if (aliases.isNotEmpty) 'aliases': aliases,
    // Written only when off: the file stays as it was for every entry that
    // predates this flag, and those all mean "yes".
    if (!autocomplete) 'autocomplete': false,
  };

  /// Reads a user-added entry. Returns null for anything unusable so a
  /// hand-edited `custom_tags.json` cannot break the dictionary.
  static TagDictionaryEntry? fromJson(Object? value) {
    if (value is! Map) return null;
    final name = (value['name'] as Object?)?.toString().trim() ?? '';
    if (name.isEmpty) return null;
    final raw = value['category'];
    final category =
        TagCategory.fromId(
          raw is num ? raw.toInt() : int.tryParse('$raw') ?? -1,
        ) ??
        TagCategory.general;
    final count = value['count'];
    final aliases = value['aliases'];
    return TagDictionaryEntry(
      name: name,
      category: category,
      postCount: count is num ? count.toInt() : 0,
      aliases: aliases is List
          ? [
              for (final a in aliases)
                if ('$a'.trim().isNotEmpty) '$a'.trim(),
            ]
          : const [],
      // Absent means yes: every entry written before the flag existed was a
      // completion candidate, and reading them as anything else would silently
      // empty the user's type-ahead.
      autocomplete: value['autocomplete'] != false,
    );
  }
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

  /// A tag the user added to the dictionary by hand, with a category of its
  /// own. Deliberate additions, so they outrank both other sources.
  custom,

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

  bool get isCustom => origin == TagSuggestionOrigin.custom;

  /// For a dictionary hit, danbooru's post count. For a local hit, how many
  /// images in the dataset carry the tag (0 when it only exists in the tag
  /// library) — a different unit, so the list must not render them alike. A
  /// custom entry's count is whatever the user typed, usually 0.
  int get count => entry.postCount;
}
