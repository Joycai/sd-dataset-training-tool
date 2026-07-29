/// The rule set that turns a character sheet plus a tagger run into one
/// image's caption. Produced once by the assistant (the "character sheet"
/// skill), reviewed by the user, then applied mechanically to every image.
///
/// The split exists because only [GarmentRule] needs a model's judgment, and
/// it needs it *per garment*, not per image: deciding that the tagger's
/// `high heels` is really this character's `high heel boots` is a decision
/// about the outfit, so it is made once and reused for the whole dataset.
library;

import 'dart:convert';

/// One tagger prediction with the confidence the tagger gave it.
///
/// The application pass needs the numbers, not just the words: an outfit item
/// the character sheet already vouches for deserves a lower bar than a tag
/// being asserted from scratch. See [applyMergeRules].
typedef ScoredTag = ({String tag, double probability});

/// Default bar for garment evidence — deliberately below a tagger's usual
/// threshold. See [applyMergeRules] for why the two differ.
const double kDefaultEvidenceThreshold = 0.2;

/// One garment/accessory from the character sheet, with the tagger vocabulary
/// that counts as evidence it is visible in a given image.
class GarmentRule {
  const GarmentRule({
    required this.tag,
    this.evidence = const [],
    this.note = '',
  });

  /// The canonical tag written when this garment fires — the user's wording,
  /// not the tagger's.
  final String tag;

  /// Tagger tags that mean "this garment is visible here". Any hit fires the
  /// rule; every hit is then removed in favour of [tag], which is how
  /// `skirt` on a lower-body crop becomes `dress`.
  ///
  /// Empty means the garment can never fire — the user listed it but the
  /// tagger has no word for it, so it is never written.
  final List<String> evidence;

  /// Why this mapping, in the user's language. Shown on the review card;
  /// never used by the application pass.
  final String note;

  Map<String, dynamic> toJson() => {
    'tag': tag,
    'evidence': evidence,
    if (note.isNotEmpty) 'note': note,
  };

  factory GarmentRule.fromJson(Map<String, dynamic> json) => GarmentRule(
    tag: (json['tag'] as String?)?.trim() ?? '',
    evidence: _stringList(json['evidence']),
    note: (json['note'] as String?)?.trim() ?? '',
  );
}

/// A named, persisted rule set for one character.
class CharacterMergeRules {
  const CharacterMergeRules({
    required this.id,
    this.character = '',
    this.triggerWord = '',
    this.identityTags = const [],
    this.conflictTags = const [],
    this.garments = const [],
    this.passthrough = const [],
    this.sampledImages = 0,
    this.notes = '',
  });

  final String id;

  /// Display name for the rule set; the picker and the review card use it.
  final String character;

  /// Written first on every image, ahead of [identityTags].
  final String triggerWord;

  /// Always written: the character's fixed traits (hair colour, hairstyle,
  /// breast size, eye colour…). Not conditional on the tagger seeing them.
  final List<String> identityTags;

  /// Always stripped from the tagger's output: the words that contradict
  /// [identityTags] (every other hair colour, every other breast size…).
  ///
  /// Garment evidence does *not* belong here — those are removed only when
  /// their garment actually fires.
  final List<String> conflictTags;

  final List<GarmentRule> garments;

  /// Tagger categories kept verbatim (expression, background, pose, action,
  /// framing). Free-form labels: documentation for the user, and the
  /// application pass keeps everything it was not told to touch anyway.
  final List<String> passthrough;

  /// How many images the assistant tagged before proposing this. 0 = unknown.
  final int sampledImages;

  final String notes;

  /// A rule set with no trigger word, no identity tags and no garments has
  /// nothing to apply.
  bool get isEmpty =>
      triggerWord.isEmpty && identityTags.isEmpty && garments.isEmpty;

  Map<String, dynamic> toJson() => {
    'id': id,
    'character': character,
    'trigger_word': triggerWord,
    'identity_tags': identityTags,
    'conflict_tags': conflictTags,
    'garments': [for (final g in garments) g.toJson()],
    'passthrough': passthrough,
    'sampled_images': sampledImages,
    if (notes.isNotEmpty) 'notes': notes,
  };

  factory CharacterMergeRules.fromJson(Map<String, dynamic> json) =>
      CharacterMergeRules(
        id: (json['id'] as String?) ?? '',
        character: (json['character'] as String?)?.trim() ?? '',
        triggerWord: (json['trigger_word'] as String?)?.trim() ?? '',
        identityTags: _stringList(json['identity_tags']),
        conflictTags: _stringList(json['conflict_tags']),
        garments: _garmentList(json['garments']),
        passthrough: _stringList(json['passthrough']),
        sampledImages: switch (json['sampled_images']) {
          final num n => n.toInt(),
          _ => 0,
        },
        notes: (json['notes'] as String?)?.trim() ?? '',
      );

  CharacterMergeRules withId(String id) => CharacterMergeRules(
    id: id,
    character: character,
    triggerWord: triggerWord,
    identityTags: identityTags,
    conflictTags: conflictTags,
    garments: garments,
    passthrough: passthrough,
    sampledImages: sampledImages,
    notes: notes,
  );
}

/// Builds one image's caption from [predicted] and [rules]. Returns null when
/// the result equals [current], mirroring the TagOps transform contract so
/// unchanged files are never rewritten.
///
/// The output order is the one a LoRA caption wants: trigger word, then the
/// fixed traits, then whichever outfit items the tagger vouched for, then
/// everything else the tagger said — expression, background, pose, framing —
/// in confidence order.
///
/// Two thresholds, because the two kinds of tag are not equally uncertain.
/// [threshold] gates tags the tagger asserts on its own. [evidenceThreshold]
/// — lower — gates garment evidence, where the character sheet has already
/// told us the item exists and the only question is whether this crop shows
/// it. A 0.2 `gloves` on a character known to wear gloves is far more likely
/// a real sighting than a hallucination. Passing an [evidenceThreshold] above
/// [threshold] is meaningless (evidence would leak into the passthrough
/// instead of being converted), so it is clamped down.
List<String>? applyMergeRules({
  required List<String> current,
  required List<ScoredTag> predicted,
  required CharacterMergeRules rules,
  required double threshold,
  required double evidenceThreshold,
}) {
  final evidenceCut = evidenceThreshold > threshold
      ? threshold
      : evidenceThreshold;

  // Which garment each tagger word belongs to. Explicit evidence first, then
  // each garment's own tag as implicit evidence for itself — if the tagger
  // says `high heel boots` outright, that is the strongest evidence there is
  // — without letting the implicit entry steal a word another garment
  // explicitly claimed.
  final owner = <String, String>{};
  for (final g in rules.garments) {
    for (final e in g.evidence) {
      owner.putIfAbsent(e.toLowerCase(), () => g.tag);
    }
  }
  for (final g in rules.garments) {
    owner.putIfAbsent(g.tag.toLowerCase(), () => g.tag);
  }

  final conflicts = {for (final t in rules.conflictTags) t.toLowerCase()};

  // A garment fires on any evidence above the lower bar; every word that
  // fired it is then spent, which is how `skirt` on a lower-body crop turns
  // into `dress` instead of joining it.
  final fired = <String>{};
  final spent = <String>{};
  for (final s in predicted) {
    if (s.probability < evidenceCut) continue;
    final key = s.tag.toLowerCase();
    final garment = owner[key];
    if (garment == null) continue;
    fired.add(garment);
    spent.add(key);
  }

  final out = <String>[];
  final seen = <String>{};
  void emit(String tag) {
    final trimmed = tag.trim();
    if (trimmed.isEmpty) return;
    if (seen.add(trimmed.toLowerCase())) out.add(trimmed);
  }

  emit(rules.triggerWord);
  for (final t in rules.identityTags) {
    emit(t);
  }
  for (final g in rules.garments) {
    if (fired.contains(g.tag)) emit(g.tag);
  }
  for (final s in predicted) {
    if (s.probability < threshold) continue;
    final key = s.tag.toLowerCase();
    if (conflicts.contains(key) || spent.contains(key)) continue;
    emit(s.tag);
  }

  return _sameTags(out, current) ? null : out;
}

bool _sameTags(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

List<String> _stringList(Object? raw) {
  if (raw is! List) return const [];
  return [
    for (final e in raw)
      if (e is String && e.trim().isNotEmpty) e.trim(),
  ];
}

/// A garment without a tag has nothing to write, so it is dropped rather
/// than kept as an empty row on the review card.
List<GarmentRule> _garmentList(Object? raw) {
  if (raw is! List) return const [];
  return [
    for (final map in raw.whereType<Map<String, dynamic>>())
      if (GarmentRule.fromJson(map) case final g when g.tag.isNotEmpty) g,
  ];
}

String encodeMergeRules(List<CharacterMergeRules> rules) =>
    jsonEncode([for (final r in rules) r.toJson()]);

/// Tolerant on purpose, like the prompt presets: a corrupt preference should
/// cost the user their saved rules, not the whole assistant panel.
List<CharacterMergeRules> decodeMergeRules(String json) {
  try {
    final decoded = jsonDecode(json);
    if (decoded is! List) return const [];
    return [
      for (final raw in decoded.whereType<Map<String, dynamic>>())
        if (raw['id'] is String) CharacterMergeRules.fromJson(raw),
    ];
  } catch (_) {
    return const [];
  }
}
