/// The UI-only translation layer over the danbooru tag dictionary.
///
/// Translations are display metadata and nothing else — they are never written
/// into a caption file, never sent to the tagger, and never take part in tag
/// matching. The dictionary stays the single source of truth for what a tag
/// *is*; this layer only answers what it means in the user's language.
library;

/// Who produced a translation.
///
/// Recorded per entry because it is the only practical escape hatch from a bad
/// bulk run: a thousand machine translations can be filtered out or cleared in
/// one action, while the ones typed by hand survive untouched.
enum TagTranslationSource {
  /// Typed or edited by the user in the dictionary manager.
  manual('manual'),

  /// Produced by the AI assistant.
  llm('llm'),

  /// Taken from danbooru's own wiki metadata (`other_names`).
  danbooru('danbooru');

  const TagTranslationSource(this.id);

  /// Stable string written to the translation file — never renumber these.
  final String id;

  static TagTranslationSource fromId(String? id) => switch (id) {
    'llm' => TagTranslationSource.llm,
    'danbooru' => TagTranslationSource.danbooru,
    _ => TagTranslationSource.manual,
  };
}

/// One tag's translation in one language.
class TagTranslation {
  const TagTranslation({
    required this.tag,
    required this.text,
    this.note,
    this.source = TagTranslationSource.manual,
  });

  /// The tag this translates, in danbooru's own spelling (`long_hair`). Stored
  /// canonically so one translation file serves every caption style; lookup
  /// folds both sides through `tagLookupKey`.
  final String tag;

  /// The translation shown beside the tag. Short by construction — it has to
  /// fit on a chip next to the tag itself.
  final String text;

  /// An optional longer gloss: what the tag actually denotes, when the
  /// translation alone is ambiguous. Shown in tooltips and the manager, never
  /// on a chip.
  final String? note;

  final TagTranslationSource source;

  /// Only the two fields the service normalizes on the way in. Anything else is
  /// decided when the entry is constructed — the form picks the source, the
  /// note comes from the same edit as the text — so there is nothing to copy.
  TagTranslation copyWith({String? tag, String? text}) => TagTranslation(
    tag: tag ?? this.tag,
    text: text ?? this.text,
    note: note,
    source: source,
  );

  Map<String, dynamic> toJson() => {
    'text': text,
    if (note != null && note!.isNotEmpty) 'note': note,
    'source': source.id,
  };

  /// Reads one entry. Returns null for anything without usable text, so a
  /// hand-edited file with a stray key cannot poison the index.
  static TagTranslation? fromJson(String tag, Object? value) {
    final name = tag.trim();
    if (name.isEmpty) return null;
    // A bare string is accepted so the file can be hand-written the short way:
    //   "long_hair": "长发"
    if (value is String) {
      final text = value.trim();
      return text.isEmpty
          ? null
          : TagTranslation(tag: name, text: text, source: _defaultSource);
    }
    if (value is! Map) return null;
    final text = (value['text'] as Object?)?.toString().trim() ?? '';
    if (text.isEmpty) return null;
    final note = (value['note'] as Object?)?.toString().trim();
    return TagTranslation(
      tag: name,
      text: text,
      note: note == null || note.isEmpty ? null : note,
      source: TagTranslationSource.fromId(value['source'] as String?),
    );
  }

  static const _defaultSource = TagTranslationSource.manual;
}

/// How much of a translation the tag chips show.
///
/// A setting rather than a fixed choice because the two reasonable answers
/// pull in opposite directions: the caption panel's chip row is width-starved,
/// while a user working in their own language wants the gloss in front of them
/// at all times.
enum TagGlossDisplay {
  /// Translations are stored and editable but never rendered beside a tag.
  off('off'),

  /// The gloss sits next to the tag in muted type — `long_hair 长发`.
  inline('inline'),

  /// Chips stay exactly as wide as they are today; the gloss is in the
  /// tooltip only.
  tooltip('tooltip');

  const TagGlossDisplay(this.id);

  final String id;

  static TagGlossDisplay fromId(String? id) => switch (id) {
    'off' => TagGlossDisplay.off,
    'tooltip' => TagGlossDisplay.tooltip,
    _ => TagGlossDisplay.inline,
  };
}
