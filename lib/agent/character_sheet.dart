/// The "character sheet" skill: phase A of tagging a character dataset.
///
/// The user fills in a form (their standard sample: trigger word, fixed
/// traits, outfit) and the skill compiles it into one task message. The
/// assistant then samples the dataset with the tagger, learns which words
/// *this* tagger actually produces for this outfit, and submits a rule set
/// via `propose_merge_rules`. It writes no captions — applying the rules to
/// every image is phase B.
///
/// The task text is English on purpose, like the system prompt: it is
/// model-facing, and the model is separately told to reply in the user's
/// language. Only the form around it is localized.
library;

/// What the form collects. Everything except [garmentTags] may be empty —
/// an empty sheet means "keep whatever the tagger says", which is a valid
/// (if unambitious) way to run this.
class CharacterSheetInput {
  const CharacterSheetInput({
    this.character = '',
    this.triggerWord = '',
    this.identityTags = '',
    this.garmentTags = '',
    this.extraNotes = '',
    this.sampleSize = kDefaultSampleSize,
  });

  /// Free-form name for the rule set. Falls back to the trigger word.
  final String character;

  final String triggerWord;

  /// Comma-separated fixed traits: hair colour, hairstyle, breast size, eyes.
  final String identityTags;

  /// Comma-separated outfit tags: dress, gloves, boots, accessories.
  final String garmentTags;

  /// Anything the form has no field for. Passed through verbatim.
  final String extraNotes;

  /// How many images to run through the tagger before proposing rules.
  final int sampleSize;

  static const int kDefaultSampleSize = 12;
  static const int kMinSampleSize = 4;
  static const int kMaxSampleSize = 30;

  /// The label the rule set gets when the model does not name it itself.
  String get label {
    final name = character.trim();
    if (name.isNotEmpty) return name;
    return triggerWord.trim();
  }

  /// Nothing to reason about: no traits, no outfit, no instructions. The
  /// dialog uses this to keep the start button disabled.
  bool get isEmpty =>
      triggerWord.trim().isEmpty &&
      identityTags.trim().isEmpty &&
      garmentTags.trim().isEmpty &&
      extraNotes.trim().isEmpty;
}

/// Splits a user-typed tag field on commas *and* newlines, so pasting a
/// caption line and typing one garment per line both work.
List<String> parseSheetTags(String raw) => [
  for (final part in raw.split(RegExp(r'[,\n]')))
    if (part.trim().isNotEmpty) part.trim(),
];

String _bullets(List<String> items) =>
    [for (final i in items) '  - $i'].join('\n');

/// Compiles [input] into the task message sent to the assistant.
String buildCharacterSheetTask(CharacterSheetInput input) {
  final identity = parseSheetTags(input.identityTags);
  final garments = parseSheetTags(input.garmentTags);
  final trigger = input.triggerWord.trim();
  final notes = input.extraNotes.trim();

  final sheet = StringBuffer();
  if (trigger.isNotEmpty) {
    sheet.writeln(
      '- Trigger word (must be the first tag of every caption): '
      '$trigger',
    );
  }
  if (identity.isNotEmpty) {
    sheet.writeln(
      '- Fixed traits, written on every image whether or not the '
      'tagger sees them:',
    );
    sheet.writeln(_bullets(identity));
  }
  if (garments.isNotEmpty) {
    sheet.writeln(
      '- Outfit, written ONLY on images where the tagger saw '
      'evidence of the item:',
    );
    sheet.writeln(_bullets(garments));
  }
  if (notes.isNotEmpty) {
    sheet.writeln('- Additional instructions from the user:');
    sheet.writeln('  $notes');
  }
  if (sheet.isEmpty) {
    sheet.writeln(
      '- (empty — the user gave no fixed tags; derive everything '
      'from the tagger sample)',
    );
  }

  return '''
Task: build the merge rules for tagging this character dataset. This is the
planning phase — do NOT write any caption, and do not call any write tool.

The user's character sheet:
${sheet.toString().trimRight()}

Steps:
1. list_images to see what is in scope, then pick ${input.sampleSize} images
   spread across the dataset (not the first N in a row — step through the
   list so different crops and framings are represented).
2. run_wd_tagger on them (max 10 per call) to learn the vocabulary this
   tagger actually produces for this character and outfit.
3. Work out, for each outfit item above, which tagger tags are evidence that
   the item is visible. This is the only judgment that matters here: the
   tagger is limited by framing and crop, so it says `high heels` for
   `high heel boots`, or `skirt` for the lower half of a `dress`. When the
   tagger emits any evidence tag, the user's wording wins and the evidence
   tags are dropped. When it emits none, the item is NOT written — a
   close-up that never shows the gloves must not get `gloves`.
4. Work out which tagger tags contradict the fixed traits (every other hair
   colour, hairstyle, breast size the sample contains). Those are stripped
   unconditionally.
5. Everything else the tagger produces — expression, background, setting,
   pose, action, framing (portrait / upper body / close-up / cowboy shot) —
   is kept verbatim. Do not list those as rules.
6. Call propose_merge_rules with the result.

Then summarize the rules for the user in one short reply, and flag anything
the sample contradicted (an outfit item no sampled image showed, a trait the
tagger consistently disagrees with). Record those in the rules' notes rather
than asking follow-up questions — the user reviews the card and edits the
sheet if something is wrong.
''';
}
