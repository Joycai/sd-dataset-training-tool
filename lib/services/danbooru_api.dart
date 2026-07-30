import 'dart:convert';

import 'package:http/http.dart' as http;

import '../app_info.dart';
import '../models/tag_dictionary.dart';
import '../utils/tag_text.dart';

/// What danbooru knows about one tag, as fetched from its public API.
///
/// Two requests behind it, because danbooru splits the answer: `/tags.json`
/// has the category and post count, `/wiki_pages` has the prose and — the
/// reason this exists — [otherNames], danbooru's own list of what the tag is
/// called in other languages. Those are *given* translations, not guesses, and
/// for a Japanese glossary they are the answer outright.
class DanbooruTagInfo {
  const DanbooruTagInfo({
    required this.name,
    this.category,
    this.postCount = 0,
    this.otherNames = const [],
    this.wikiExcerpt,
    this.knownToDanbooru = false,
    this.hasWiki = false,
  });

  /// Canonical danbooru spelling — the name as danbooru returned it when it
  /// knows the tag, otherwise the normalized query.
  final String name;

  /// Null when danbooru has no tag record, or its category is one this app
  /// does not model.
  final TagCategory? category;

  final int postCount;

  /// Danbooru's `other_names`: alternate and foreign-language names for the
  /// tag. Usually Japanese for characters and copyrights.
  final List<String> otherNames;

  /// The opening of the wiki page as plain text, with DText markup stripped.
  /// Null when the tag has no wiki page or its body is empty.
  final String? wikiExcerpt;

  /// Whether `/tags.json` returned a record. False means danbooru has never
  /// heard of this tag — usually a typo, occasionally a brand-new tag.
  final bool knownToDanbooru;

  final bool hasWiki;

  bool get isEmpty =>
      !knownToDanbooru && !hasWiki && otherNames.isEmpty && wikiExcerpt == null;
}

/// A failed lookup, with a message fit to show the user.
class DanbooruApiException implements Exception {
  DanbooruApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Read-only client for danbooru's public JSON API.
///
/// Anonymous access only: every endpoint used here is public, and asking the
/// user for an API key to read a wiki page would be a poor trade. That also
/// bounds the blast radius — this client cannot write anything.
class DanbooruApi {
  DanbooruApi({http.Client Function()? clientFactory})
    : _clientFactory = clientFactory ?? http.Client.new;

  static const host = 'danbooru.donmai.us';

  /// Danbooru asks API clients to identify themselves and throttles or blocks
  /// generic agents.
  static final userAgent = 'sd-dataset-training-tool/${AppInfo.version} '
      '(+${AppInfo.repositoryUrl})';

  /// Per-request ceiling. A wiki body runs to a few KB; anything wildly past
  /// that is not the response we asked for.
  static const _timeout = Duration(seconds: 20);

  final http.Client Function() _clientFactory;

  /// Extracts a danbooru tag name from whatever the user pasted.
  ///
  /// Accepts a bare tag in any caption style, or a danbooru URL — a wiki page,
  /// a post search, a tag listing. Returns null when there is no tag in it.
  ///
  /// Deliberately tolerant: the whole point of accepting a URL is that the
  /// user got here by browsing, and the address bar is what they have.
  static String? parseQuery(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;

    final uri = Uri.tryParse(trimmed);
    final looksLikeUrl =
        uri != null && (uri.hasScheme || trimmed.startsWith('danbooru.'));
    if (!looksLikeUrl) {
      // A bare tag. Underscored and unescaped is what every endpoint keys on.
      final name = danbooruTagName(trimmed);
      return name.isEmpty ? null : name;
    }

    // `?tags=long_hair`, `?search[name_matches]=long_hair`, `?search[title]=…`
    for (final key in const [
      'tags',
      'search[name]',
      'search[name_matches]',
      'search[title]',
      'search[title_normalize]',
    ]) {
      final value = uri.queryParameters[key];
      if (value == null || value.trim().isEmpty) continue;
      // A post search can carry several tags and metatags; the first plain tag
      // is the one the user is looking at.
      for (final part in value.split(RegExp(r'[\s+]+'))) {
        if (part.isEmpty || part.contains(':') || part.startsWith('-')) continue;
        return danbooruTagName(part);
      }
    }

    // `/wiki_pages/long_hair`, `/posts/123` (no tag), `/tags/456` (no name).
    final segments = uri.pathSegments
        .where((s) => s.isNotEmpty)
        .toList(growable: false);
    if (segments.length >= 2 && segments.first == 'wiki_pages') {
      final last = Uri.decodeComponent(segments[1]);
      // A numeric wiki id is a page reference, not a tag name; there is
      // nothing to look the tag up by.
      if (RegExp(r'^\d+$').hasMatch(last)) return null;
      final name = danbooruTagName(last.replaceAll('.json', ''));
      return name.isEmpty ? null : name;
    }
    return null;
  }

  /// Looks [input] up on danbooru. [input] may be a tag name or a URL; see
  /// [parseQuery].
  ///
  /// Throws [DanbooruApiException] on a bad query, a transport failure or an
  /// error status. A tag danbooru does not have is *not* an error — it comes
  /// back with `knownToDanbooru == false`, which is itself the answer.
  Future<DanbooruTagInfo> fetch(String input) async {
    final name = parseQuery(input);
    if (name == null) {
      throw DanbooruApiException('not a danbooru tag or tag URL: "$input"');
    }

    final client = _clientFactory();
    try {
      // Sequential, not concurrent: two parallel requests double this client's
      // instantaneous rate against a service that asks callers to go easy, and
      // the second one is only a few hundred milliseconds either way.
      final tag = await _getJson(client, _tagUrl(name));
      final record = tag is List && tag.isNotEmpty ? tag.first : null;

      // Danbooru's own spelling wins — the query may have been an alias or a
      // near miss, and everything downstream keys on the canonical name.
      final canonical = record is Map
          ? ((record['name'] as Object?)?.toString().trim() ?? name)
          : name;

      Object? wiki;
      try {
        wiki = await _getJson(client, _wikiUrl(canonical));
      } on DanbooruApiException {
        // No wiki page is the common case for the long tail of tags, and the
        // tag record on its own is still worth returning.
        wiki = null;
      }
      final page = wiki is Map ? wiki : null;

      final rawCategory = record is Map ? record['category'] : null;
      return DanbooruTagInfo(
        name: canonical,
        category: rawCategory is num
            ? TagCategory.fromId(rawCategory.toInt())
            : null,
        postCount: record is Map && record['post_count'] is num
            ? (record['post_count'] as num).toInt()
            : 0,
        otherNames: page == null
            ? const []
            : [
                for (final other in (page['other_names'] as List? ?? const []))
                  if ('$other'.trim().isNotEmpty) '$other'.trim(),
              ],
        wikiExcerpt: page == null
            ? null
            : stripDText('${page['body'] ?? ''}'),
        knownToDanbooru: record is Map,
        hasWiki: page != null,
      );
    } finally {
      client.close();
    }
  }

  Uri _tagUrl(String name) => Uri.https(host, '/tags.json', {
    'search[name]': name,
    'limit': '1',
  });

  /// Built from path segments: a tag name may contain a slash
  /// (`fate/grand_order`), which has to reach the server escaped.
  Uri _wikiUrl(String name) => Uri(
    scheme: 'https',
    host: host,
    pathSegments: ['wiki_pages', '$name.json'],
  );

  Future<Object?> _getJson(http.Client client, Uri url) async {
    final http.Response response;
    try {
      response = await client
          .get(url, headers: {'User-Agent': userAgent, 'Accept': '*/*'})
          .timeout(_timeout);
    } catch (e) {
      throw DanbooruApiException('could not reach danbooru: $e');
    }
    if (response.statusCode == 404) {
      throw DanbooruApiException('not found on danbooru');
    }
    if (response.statusCode == 403 || response.statusCode == 429) {
      // Worth distinguishing: the caller should back off rather than retry.
      throw DanbooruApiException(
        'danbooru is rate-limiting this client '
        '(HTTP ${response.statusCode}); try again in a moment',
      );
    }
    if (response.statusCode != 200) {
      throw DanbooruApiException('danbooru returned HTTP ${response.statusCode}');
    }
    try {
      // bodyBytes, not body: danbooru serves UTF-8 and `other_names` is mostly
      // Japanese, which http's latin-1 default would mangle.
      return jsonDecode(utf8.decode(response.bodyBytes, allowMalformed: true));
    } on FormatException catch (e) {
      throw DanbooruApiException('danbooru returned unreadable JSON: ${e.message}');
    }
  }
}

/// Wiki bodies are written in DText, danbooru's own markup. Reduces it to the
/// plain first paragraph — enough to seed a note, without dragging link syntax
/// into the glossary.
///
/// Deliberately lossy and deliberately not a parser: the output is a hint for
/// a human to edit, so a mangled edge case costs a word, not correctness.
String? stripDText(String body, {int maxLength = 320}) {
  var text = body.replaceAll('\r\n', '\n');

  // `[[tag|label]]` / `[[tag]]` — wiki links. The label is the readable half.
  text = text.replaceAllMapped(
    RegExp(r'\[\[([^\]|]+)(?:\|([^\]]*))?\]\]'),
    (m) => (m.group(2)?.trim().isNotEmpty ?? false) ? m.group(2)! : m.group(1)!,
  );
  // `"label":[url]` and `"label":url` — external links.
  text = text.replaceAllMapped(
    RegExp(r'"([^"]*)":\[[^\]]*\]'),
    (m) => m.group(1)!,
  );
  text = text.replaceAllMapped(
    RegExp(r'"([^"]*)":https?://\S+'),
    (m) => m.group(1)!,
  );
  // Inline tags: [b], [i], [quote], [expand=…] and their closers.
  text = text.replaceAll(RegExp(r'\[/?[a-zA-Z]+[^\]]*\]'), '');
  // Block markup: `h4. Heading`, list bullets. Horizontal whitespace only —
  // `\s*` here would swallow the blank line before a heading, collapsing the
  // paragraph break that the excerpt is cut on.
  text = text.replaceAll(RegExp(r'^[ \t]*h[1-6]\.[ \t]*', multiLine: true), '');
  text = text.replaceAll(RegExp(r'^[ \t]*[*#]+[ \t]*', multiLine: true), '');

  // First paragraph only — the rest of a wiki page is usually related-tag
  // lists, which say nothing about what the tag means.
  final paragraph = text
      .split(RegExp(r'\n\s*\n'))
      .map((p) => p.replaceAll(RegExp(r'\s+'), ' ').trim())
      .firstWhere((p) => p.isNotEmpty, orElse: () => '');
  if (paragraph.isEmpty) return null;
  if (paragraph.length <= maxLength) return paragraph;
  // Cut on a word boundary when there is one nearby, so the hint does not end
  // mid-word.
  final cut = paragraph.lastIndexOf(' ', maxLength);
  return '${paragraph.substring(0, cut > maxLength - 40 ? cut : maxLength)}…';
}
