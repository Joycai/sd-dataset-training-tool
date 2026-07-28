/// Splits comma-separated caption text into trimmed, de-duplicated tags.
/// The single tag grammar shared by the editor, the dataset index and the
/// batch rewrite operations — they must all agree on what a "tag" is.
List<String> parseTagText(String text) {
  final seen = <String>{};
  return text
      .split(',')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty && seen.add(s))
      .toList();
}

/// Folds a tag into the form the dictionary matches on: lower case, spaces
/// instead of underscores, parentheses unescaped, runs of blanks collapsed.
///
/// This is what makes the dictionary style-agnostic. Captions in the wild are
/// written `long hair`, `long_hair` or `smile \(expression\)`, while
/// danbooru's own spelling is `long_hair`. Folding both sides means a user
/// typing in their own style still reaches the canonical tag.
String tagLookupKey(String tag) => tag
    .replaceAll(r'\(', '(')
    .replaceAll(r'\)', ')')
    .replaceAll('_', ' ')
    .trim()
    .replaceAll(RegExp(r'\s+'), ' ')
    .toLowerCase();

/// Rewrites a tag into danbooru's own spelling: underscored and unescaped.
/// Used for wiki/post links and for looking a caption tag up in the
/// dictionary, both of which key on the canonical name.
String danbooruTagName(String tag) => tag
    .replaceAll(r'\(', '(')
    .replaceAll(r'\)', ')')
    .trim()
    .replaceAll(RegExp(r'\s+'), '_');
