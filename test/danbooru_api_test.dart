import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:dataset_training_tool/models/tag_dictionary.dart';
import 'package:dataset_training_tool/services/danbooru_api.dart';

/// Serves the two endpoints `fetch` calls. [tag] null means danbooru has no
/// tag record; [wiki] null means no wiki page (404).
MockClient _client({
  Map<String, dynamic>? tag,
  Map<String, dynamic>? wiki,
  List<Uri>? recordTo,
  int? status,
}) => MockClient((request) async {
  recordTo?.add(request.url);
  if (status != null) return http.Response('nope', status);
  if (request.url.path == '/tags.json') {
    return http.Response(
      jsonEncode(tag == null ? [] : [tag]),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  }
  if (request.url.path.startsWith('/wiki_pages/')) {
    if (wiki == null) return http.Response('not found', 404);
    // Bytes, not the string constructor: MockClient's String response encodes
    // as UTF-8, which is what danbooru actually serves.
    return http.Response.bytes(
      utf8.encode(jsonEncode(wiki)),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  }
  return http.Response('unexpected ${request.url}', 500);
});

void main() {
  group('parseQuery', () {
    test('a bare tag is normalized to danbooru spelling', () {
      expect(DanbooruApi.parseQuery('long hair'), 'long_hair');
      expect(DanbooruApi.parseQuery('  Long_Hair '), 'Long_Hair');
      expect(DanbooruApi.parseQuery(r'smile \(expression\)'), 'smile_(expression)');
      expect(DanbooruApi.parseQuery('   '), isNull);
    });

    test('a wiki page URL yields its title', () {
      expect(
        DanbooruApi.parseQuery('https://danbooru.donmai.us/wiki_pages/long_hair'),
        'long_hair',
      );
      // Tag names can contain a slash, which arrives percent-encoded.
      expect(
        DanbooruApi.parseQuery(
          'https://danbooru.donmai.us/wiki_pages/fate%2Fgrand_order',
        ),
        'fate/grand_order',
      );
      // A numeric wiki id names no tag, so there is nothing to look up.
      expect(
        DanbooruApi.parseQuery('https://danbooru.donmai.us/wiki_pages/12345'),
        isNull,
      );
    });

    test('a post search URL yields its first plain tag', () {
      expect(
        DanbooruApi.parseQuery(
          'https://danbooru.donmai.us/posts?tags=long_hair+blue_eyes',
        ),
        'long_hair',
      );
      // Metatags and exclusions are not tags to look up; skip to the real one.
      expect(
        DanbooruApi.parseQuery(
          'https://danbooru.donmai.us/posts?tags=rating:general+-comic+long_hair',
        ),
        'long_hair',
      );
    });

    test('a tag listing URL yields its search term', () {
      expect(
        DanbooruApi.parseQuery(
          'https://danbooru.donmai.us/tags?search%5Bname_matches%5D=long_hair',
        ),
        'long_hair',
      );
    });

    test('an unrelated URL yields nothing', () {
      expect(DanbooruApi.parseQuery('https://example.com/hello'), isNull);
      expect(
        DanbooruApi.parseQuery('https://danbooru.donmai.us/posts/12345'),
        isNull,
      );
    });
  });

  group('fetch', () {
    test('combines the tag record and the wiki page', () async {
      final api = DanbooruApi(
        clientFactory: () => _client(
          tag: {'name': 'hatsune_miku', 'category': 4, 'post_count': 200000},
          wiki: {
            'title': 'hatsune_miku',
            'other_names': ['初音ミク', 'Hatsune Miku', ''],
            'body': 'The most famous [[vocaloid]].\n\nSee also: stuff.',
          },
        ),
      );

      final info = await api.fetch('hatsune miku');

      expect(info.name, 'hatsune_miku');
      expect(info.category, TagCategory.character);
      expect(info.postCount, 200000);
      expect(info.knownToDanbooru, isTrue);
      expect(info.hasWiki, isTrue);
      // Blank entries dropped; the Japanese name survives the UTF-8 round trip,
      // which is the whole reason this endpoint is worth calling.
      expect(info.otherNames, ['初音ミク', 'Hatsune Miku']);
      expect(info.wikiExcerpt, 'The most famous vocaloid.');
    });

    test("danbooru's own spelling wins over the query", () async {
      final urls = <Uri>[];
      final api = DanbooruApi(
        clientFactory: () => _client(
          tag: {'name': 'long_hair', 'category': 0, 'post_count': 3000000},
          wiki: {'other_names': const [], 'body': ''},
          recordTo: urls,
        ),
      );

      final info = await api.fetch('LONG HAIR');

      // The wiki request has to use the canonical name, not the query.
      expect(info.name, 'long_hair');
      expect(urls.last.path, '/wiki_pages/long_hair.json');
    });

    test('a tag with no wiki page still returns its record', () async {
      final api = DanbooruApi(
        clientFactory: () => _client(
          tag: {'name': 'obscure_tag', 'category': 0, 'post_count': 3},
        ),
      );

      final info = await api.fetch('obscure_tag');

      expect(info.knownToDanbooru, isTrue);
      expect(info.hasWiki, isFalse);
      expect(info.wikiExcerpt, isNull);
      expect(info.otherNames, isEmpty);
    });

    test('an unknown tag is an answer, not an error', () async {
      final api = DanbooruApi(clientFactory: () => _client());

      final info = await api.fetch('lnog_hair');

      // "danbooru doesn't have this either" is exactly what confirms a typo,
      // so it must not surface as a failure.
      expect(info.knownToDanbooru, isFalse);
      expect(info.name, 'lnog_hair');
    });

    test('an unusable query throws before any request', () async {
      final urls = <Uri>[];
      final api = DanbooruApi(clientFactory: () => _client(recordTo: urls));

      await expectLater(
        () => api.fetch('https://example.com/nothing'),
        throwsA(isA<DanbooruApiException>()),
      );
      expect(urls, isEmpty);
    });

    test('rate limiting says so rather than looking like a missing tag', () async {
      final api = DanbooruApi(clientFactory: () => _client(status: 429));

      await expectLater(
        () => api.fetch('long_hair'),
        throwsA(
          isA<DanbooruApiException>().having(
            (e) => e.message,
            'message',
            contains('429'),
          ),
        ),
      );
    });
  });

  group('stripDText', () {
    test('wiki links reduce to their readable half', () {
      expect(stripDText('a [[long hair|long-haired]] girl'), 'a long-haired girl');
      expect(stripDText('a [[long_hair]] girl'), 'a long_hair girl');
    });

    test('external links keep only their label', () {
      expect(
        stripDText('see "the docs":[https://example.com/x] for more'),
        'see the docs for more',
      );
      expect(
        stripDText('see "the docs":https://example.com/x for more'),
        'see the docs for more',
      );
    });

    test('inline and block markup is dropped', () {
      expect(stripDText('[b]Bold[/b] text'), 'Bold text');
      expect(stripDText('h4. Heading\nbody text'), 'Heading body text');
      expect(stripDText('* one\n* two'), 'one two');
    });

    test('only the first paragraph survives', () {
      // The rest of a danbooru wiki page is usually related-tag lists, which
      // say nothing about what the tag means.
      expect(
        stripDText('What it means.\n\nh4. Related tags\n* other_tag'),
        'What it means.',
      );
    });

    test('an empty or markup-only body yields null', () {
      expect(stripDText(''), isNull);
      expect(stripDText('   \n\n  '), isNull);
    });

    test('a long body is cut on a word boundary', () {
      final body = List.filled(80, 'word').join(' ');
      final excerpt = stripDText(body, maxLength: 40)!;

      expect(excerpt.length, lessThanOrEqualTo(41));
      expect(excerpt, endsWith('…'));
      expect(excerpt, startsWith('word word'));
    });
  });
}
