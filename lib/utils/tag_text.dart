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

/// Marks the natural-language tail of an Anima Tag caption inside a parsed
/// part list. The `". "` is kept on the segment — exactly like prose segments
/// keep their punctuation — so a flat list of parts still reassembles into the
/// caption it came from, and so every consumer can tell the tail apart from a
/// tag without a second channel.
const String animaNlPrefix = '. ';

/// Where an Anima Tag caption's tag list ends and its natural-language
/// description begins: the first `.` followed by whitespace or the end of the
/// text. The lookahead is what keeps `1.5` and `no.7` inside a tag; a tag
/// spelled with a sentence-style `. ` in it (`dr. pepper`) would end the tag
/// list early, which is the documented cost of the standard's own separator.
final RegExp _animaNlBreak = RegExp(r'\.(?=\s|$)');

/// True when [part] is the natural-language tail rather than a tag.
bool isAnimaNlPart(String part) => part.startsWith(animaNlPrefix);

/// The tail's text without its [animaNlPrefix] marker.
String animaNlText(String part) =>
    isAnimaNlPart(part) ? part.substring(animaNlPrefix.length).trim() : part;

/// Splits an Anima Tag caption into its tags plus — when the caption has one
/// — a single trailing natural-language segment carrying [animaNlPrefix].
///
/// The tag half follows the ordinary tag grammar; the tail is taken verbatim,
/// so the commas and periods inside a sentence never turn into tags.
List<String> parseAnimaTagText(String text) {
  final match = _animaNlBreak.firstMatch(text);
  if (match == null) return parseTagText(text);
  final tail = text.substring(match.end).trim();
  final tags = parseTagText(text.substring(0, match.start));
  return tail.isEmpty ? tags : [...tags, '$animaNlPrefix$tail'];
}

/// Separates an Anima Tag part list into its tags and its natural-language
/// tail (null when it has none). The single place that answers "which of
/// these parts are actually tags" for the rewrite paths.
({List<String> tags, String? nl}) splitAnimaParts(List<String> parts) {
  final tags = <String>[];
  final tail = <String>[];
  for (final part in parts) {
    (isAnimaNlPart(part) ? tail : tags).add(part);
  }
  return (
    tags: tags,
    // More than one tail can only come from hand-editing a part into the
    // marker; joining them keeps the text rather than dropping it.
    nl: tail.isEmpty ? null : tail.map(animaNlText).join(' '),
  );
}

/// Parses caption text in the grammar of the active caption type's format:
/// the tag grammar, tags plus a natural-language tail for Anima Tag, sentence
/// segments for prose, or the string leaves of a JSON document.
List<String> parseCaptionText(
  String text, {
  CaptionFormat format = CaptionFormat.tags,
}) => switch (format) {
  CaptionFormat.tags => parseTagText(text),
  CaptionFormat.animaTag => parseAnimaTagText(text),
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
  return [
    for (final tag in jsonCaptionTags(decoded))
      if (seen.add(tag)) tag,
  ];
}

/// The tags of an already-decoded JSON caption, in document order and
/// **with duplicates kept** — the multiset a lossless restructure has to
/// preserve. String leaves are split by the tag grammar (so `["a", "b"]`
/// and `"a, b"` count their tags alike), subtrees under [ignoreKeys] are
/// skipped, and non-string leaves carry none.
///
/// This is the single definition of "the tags of a JSON caption". The tag
/// index and the caption views dedupe it ([parseJsonCaptionTags]) because
/// the same tag listed under two fields is still one tag on the image; the
/// assistant's lossless guards compare it as-is, because a restructure that
/// merged two occurrences into one *did* change the document.
List<String> jsonCaptionTags(
  dynamic decoded, {
  Set<String> ignoreKeys = const {},
}) {
  final out = <String>[];
  void walk(dynamic node) {
    if (node is String) {
      out.addAll(parseTagText(node));
    } else if (node is List) {
      node.forEach(walk);
    } else if (node is Map) {
      node.forEach((key, value) {
        if (!ignoreKeys.contains(key)) walk(value);
      });
    }
  }

  walk(decoded);
  return out;
}

/// Flattens a decoded JSON caption into an ordered tag line — the way back
/// from a JSON caption type to a plain tag list.
///
/// [fields] names the top-level keys whose tags come first, in that order.
/// A key it does not name still contributes its tags, appended after the
/// ordered ones and reported in `unlisted`: dropping a tag for going
/// unlisted is exactly the silent loss the JSON tools exist to prevent, so
/// the only way to lose one here is to ask, via [skipFields].
///
/// [nlField] is pulled out whole rather than split: a prose sentence read
/// with the tag grammar becomes a handful of comma-shaped fragments, which
/// is what a caption converted "back" most often gets wrong. It is returned
/// separately so the caller can decide whether the target format has
/// anywhere to put it.
({List<String> tags, String? nl, Set<String> unlisted, int skipped})
flattenJsonCaption(
  dynamic decoded, {
  List<String> fields = const [],
  String? nlField,
  Set<String> skipFields = const {},
}) {
  if (decoded is! Map) {
    // No keys to order by; everything the document carries comes out as it
    // was walked.
    return (
      tags: jsonCaptionTags(decoded, ignoreKeys: skipFields),
      nl: null,
      unlisted: const {},
      skipped: 0,
    );
  }

  var skipped = 0;
  for (final entry in decoded.entries) {
    if (skipFields.contains('${entry.key}')) {
      skipped += jsonCaptionTags(entry.value).length;
    }
  }

  String? nl;
  if (nlField != null) {
    final value = decoded[nlField];
    if (value is String && value.trim().isNotEmpty) nl = value.trim();
  }

  final taken = <String>{?nlField, ...skipFields};
  final tags = <String>[];
  for (final field in fields) {
    if (!taken.add(field)) continue;
    if (!decoded.containsKey(field)) continue;
    tags.addAll(jsonCaptionTags(decoded[field], ignoreKeys: skipFields));
  }
  final unlisted = <String>{};
  decoded.forEach((key, value) {
    final name = '$key';
    if (!taken.add(name)) return;
    unlisted.add(name);
    tags.addAll(jsonCaptionTags(value, ignoreKeys: skipFields));
  });
  return (tags: tags, nl: nl, unlisted: unlisted, skipped: skipped);
}

/// Joins parsed caption parts back into file text. Tags join with `", "`;
/// prose segments carry their own punctuation, so they join with a plain
/// space — omitted after full-width punctuation, which no space follows.
/// An Anima Tag caption's natural-language tail is re-appended last whatever
/// position it holds in [parts], because "last" is what the format means by
/// it. JSON captions cannot be reassembled from a flat tag list, so every
/// tag-level rewrite path refuses to run on them before ever joining.
String joinCaptionText(
  List<String> parts, {
  CaptionFormat format = CaptionFormat.tags,
}) {
  if (format == CaptionFormat.animaTag) {
    final split = splitAnimaParts(parts);
    final tags = split.tags.join(', ');
    return split.nl == null ? tags : '$tags$animaNlPrefix${split.nl}';
  }
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
