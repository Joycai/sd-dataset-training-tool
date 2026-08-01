import 'dart:convert';

import '../models/caption_type.dart';

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

/// Where prose caption text breaks into segments: a run of `,`/`.` followed
/// by whitespace or the end of the text (so `1.5` and `no.7` stay whole),
/// or a run of full-width `，`/`。` anywhere (Chinese prose has no spaces).
final RegExp _sentenceBreak = RegExp(r'[,.]+(?=\s|$)|[，。]+');

/// The prose counterpart of [parseTagText]: splits natural-language caption
/// text into sentence segments for the tag view. Each segment keeps its
/// trailing punctuation, which is what lets [joinCaptionText] reassemble the
/// caption without inventing or dropping delimiters. Exact duplicate
/// segments collapse, mirroring the tag grammar.
List<String> parseSentenceText(String text) {
  final seen = <String>{};
  final out = <String>[];
  void add(String raw) {
    final segment = raw.trim();
    if (segment.isNotEmpty && seen.add(segment)) out.add(segment);
  }

  var start = 0;
  for (final match in _sentenceBreak.allMatches(text)) {
    add(text.substring(start, match.end));
    start = match.end;
  }
  add(text.substring(start));
  return out;
}

/// Parses caption text in the grammar of the active caption type's format:
/// the tag grammar, sentence segments for prose, or the string leaves of a
/// JSON document.
List<String> parseCaptionText(
  String text, {
  CaptionFormat format = CaptionFormat.tags,
}) => switch (format) {
  CaptionFormat.tags => parseTagText(text),
  CaptionFormat.prose => parseSentenceText(text),
  CaptionFormat.json => parseJsonCaptionTags(text),
};

/// The tags carried by a JSON caption, for display, statistics and the
/// assistant's reads: every string leaf in document order, each split by the
/// tag grammar, de-duplicated. Unparseable JSON yields no tags — the image
/// still counts as captioned, it just contributes nothing to the tag index.
List<String> parseJsonCaptionTags(String text) {
  if (text.trim().isEmpty) return const [];
  dynamic decoded;
  try {
    decoded = jsonDecode(text);
  } on FormatException {
    return const [];
  }
  final seen = <String>{};
  final out = <String>[];
  void walk(dynamic node) {
    if (node is String) {
      for (final tag in parseTagText(node)) {
        if (seen.add(tag)) out.add(tag);
      }
    } else if (node is List) {
      node.forEach(walk);
    } else if (node is Map) {
      node.values.forEach(walk);
    }
  }

  walk(decoded);
  return out;
}

/// Joins parsed caption parts back into file text. Tags join with `", "`;
/// prose segments carry their own punctuation, so they join with a plain
/// space — omitted after full-width punctuation, which no space follows.
/// JSON captions cannot be reassembled from a flat tag list, so every
/// tag-level rewrite path refuses to run on them before ever joining.
String joinCaptionText(
  List<String> parts, {
  CaptionFormat format = CaptionFormat.tags,
}) {
  if (format != CaptionFormat.prose) return parts.join(', ');
  final buffer = StringBuffer();
  for (var i = 0; i < parts.length; i++) {
    if (i > 0 && !parts[i - 1].endsWith('，') && !parts[i - 1].endsWith('。')) {
      buffer.write(' ');
    }
    buffer.write(parts[i]);
  }
  return buffer.toString();
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

/// Removes caption-style backslash escaping from a tag
/// (`smile \(expression\)` → `smile (expression)`). The escaping exists for
/// prompt attention syntax in plain-text captions; structured formats like
/// JSON captions carry the plain spelling.
String unescapeTagParens(String tag) =>
    tag.replaceAll(r'\(', '(').replaceAll(r'\)', ')');

/// Rewrites a tag into danbooru's own spelling: underscored and unescaped.
/// Used for wiki/post links and for looking a caption tag up in the
/// dictionary, both of which key on the canonical name.
String danbooruTagName(String tag) => tag
    .replaceAll(r'\(', '(')
    .replaceAll(r'\)', ')')
    .trim()
    .replaceAll(RegExp(r'\s+'), '_');
