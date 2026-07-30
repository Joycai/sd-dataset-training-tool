import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;

import 'package:dataset_training_tool/models/tag_translation.dart';
import 'package:dataset_training_tool/services/agent/agent_tools.dart';
import 'package:dataset_training_tool/services/agent/tag_translation_tools.dart';
import 'package:dataset_training_tool/services/danbooru_api.dart';
import 'package:dataset_training_tool/services/tag_dictionary_service.dart';
import 'package:dataset_training_tool/services/tag_translation_service.dart';
import 'package:dataset_training_tool/state/dataset_state.dart';

// 1x1 transparent PNG.
const _pngBytes = [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x62, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
];

const _csv = '''
1girl,0,5113288,
long_hair,0,3000000,
smile,0,2500000,
hatsune_miku,4,200000,
''';

void main() {
  late Directory temp;
  late DatasetState dataset;
  late TagTranslationService glossary;
  late TagDictionaryService dictionary;
  late ToolRegistry registry;
  late int danbooruRequests;

  Future<Map<String, dynamic>> call(
    String tool, [
    Map<String, dynamic> args = const {},
  ]) async {
    final result = await registry.dispatch(tool, jsonEncode(args));
    return jsonDecode(result.text) as Map<String, dynamic>;
  }

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('translate_tools_');
    for (final name in ['001', '002', '003']) {
      await File(p.join(temp.path, '$name.png')).writeAsBytes(_pngBytes);
    }
    // long_hair on three images, 1girl on two, smile on one — so "busiest
    // first" has something to order.
    await File(
      p.join(temp.path, '001.txt'),
    ).writeAsString('1girl, long hair, smile');
    await File(p.join(temp.path, '002.txt')).writeAsString('1girl, long hair');
    await File(p.join(temp.path, '003.txt')).writeAsString('long hair');

    dataset = DatasetState();
    await dataset.scan(
      directoryPath: temp.path,
      recursive: false,
      captionExtension: '.txt',
    );

    dictionary = TagDictionaryService(storageDirectory: () async => temp);
    await dictionary.loadCsv(_csv, full: true);
    glossary = TagTranslationService(storageDirectory: () async => temp);
    await glossary.load('zh');

    danbooruRequests = 0;
    registry = ToolRegistry(
      buildTagTranslationTools(
        TagTranslationToolsDeps(
          glossary: glossary,
          dictionary: dictionary,
          dataset: dataset,
          libraryTags: () => ['1girl', 'my_trigger_word'],
          api: DanbooruApi(
            clientFactory: () => MockClient((request) async {
              danbooruRequests++;
              if (request.url.path == '/tags.json') {
                return http.Response(
                  jsonEncode([
                    {
                      'name': request.url.queryParameters['search[name]'],
                      'category': 4,
                      'post_count': 200000,
                    },
                  ]),
                  200,
                );
              }
              return http.Response.bytes(
                utf8.encode(
                  jsonEncode({
                    'other_names': ['初音ミク'],
                    'body': 'A [[vocaloid]].',
                  }),
                ),
                200,
              );
            }),
          ),
        ),
      ),
    );
  });

  tearDown(() async {
    dataset.dispose();
    glossary.dispose();
    dictionary.dispose();
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  group('list_tag_translations', () {
    test('defaults to untranslated dataset tags, busiest first', () async {
      final result = await call('list_tag_translations');

      expect(result['locale'], 'zh');
      expect(result['scope'], 'dataset');
      final tags = (result['tags'] as List).cast<Map<String, dynamic>>();
      expect(tags.map((t) => t['tag']), ['long hair', '1girl', 'smile']);
      // The count the user actually sees, which is what makes a tag worth
      // translating first.
      expect(tags.first['images'], 3);
      // Dictionary metadata rides along so the model can tell a character tag
      // from a descriptive one without a second call.
      expect(tags.first['category'], 'general');
      expect(tags.first['post_count'], 3000000);
    });

    test('translated tags drop out of the default list', () async {
      await glossary.upsert(const TagTranslation(tag: 'long_hair', text: '长发'));

      final result = await call('list_tag_translations');

      final tags = (result['tags'] as List).cast<Map<String, dynamic>>();
      // Matched through tagLookupKey: the dataset spells it "long hair", the
      // glossary "long_hair".
      expect(tags.map((t) => t['tag']), ['1girl', 'smile']);
      expect(result['translated_total'], 1);
    });

    test('only_missing:false reports the existing translation and source', () async {
      await glossary.upsertAll(const [
        TagTranslation(
          tag: 'long_hair',
          text: '长发',
          note: '过肩',
          source: TagTranslationSource.llm,
        ),
      ]);

      final result = await call('list_tag_translations', {
        'only_missing': false,
      });

      final row = (result['tags'] as List)
          .cast<Map<String, dynamic>>()
          .firstWhere((t) => t['tag'] == 'long hair');
      expect(row['translation'], '长发');
      expect(row['note'], '过肩');
      expect(row['source'], 'llm');
    });

    test('the library scope lists library tags, not dataset ones', () async {
      final result = await call('list_tag_translations', {'scope': 'library'});

      final tags = (result['tags'] as List).cast<Map<String, dynamic>>();
      expect(tags.map((t) => t['tag']), ['1girl', 'my_trigger_word']);
    });

    test('the dictionary scope walks the vocabulary popularity-first', () async {
      final result = await call('list_tag_translations', {
        'scope': 'dictionary',
        'limit': 2,
      });

      final tags = (result['tags'] as List).cast<Map<String, dynamic>>();
      expect(tags.map((t) => t['tag']), ['1girl', 'long_hair']);
    });

    test('explicit tags come back whether translated or not', () async {
      final result = await call('list_tag_translations', {
        'tags': ['long_hair', 'nonexistent_tag'],
      });

      final tags = (result['tags'] as List).cast<Map<String, dynamic>>();
      expect(tags.map((t) => t['tag']), ['long_hair', 'nonexistent_tag']);
      // A tag no dictionary knows still gets a row — that is how the model
      // learns it is the user's own vocabulary rather than a typo it should
      // silently skip.
      expect(tags.last.containsKey('category'), isFalse);
    });
  });

  group('write_tag_translations', () {
    test('a batch is written and recorded as the assistant\'s', () async {
      final result = await call('write_tag_translations', {
        'entries': [
          {'tag': 'long hair', 'translation': '长发', 'note': '过肩'},
          {'tag': 'smile', 'translation': '微笑'},
        ],
      });

      expect(result['written'], 2);
      expect(result['locale'], 'zh');
      // Normalized to danbooru spelling on the way in, so one entry serves
      // every caption style.
      expect(glossary.lookup('long_hair')?.text, '长发');
      expect(glossary.lookup('long_hair')?.note, '过肩');
      // Always llm, so the user's one-action cleanup can find the whole run.
      expect(glossary.lookup('smile')?.source, TagTranslationSource.llm);
    });

    test('hand-written translations survive a bulk pass by default', () async {
      await glossary.upsert(const TagTranslation(tag: 'long_hair', text: '长发'));

      final result = await call('write_tag_translations', {
        'entries': [
          {'tag': 'long_hair', 'translation': '长长的头发'},
          {'tag': 'smile', 'translation': '微笑'},
        ],
      });

      expect(result['written'], 1);
      expect(result['skipped_existing'], 1);
      expect(glossary.lookup('long_hair')?.text, '长发');
      expect(glossary.lookup('long_hair')?.source, TagTranslationSource.manual);
    });

    test('overwrite:true replaces, when the user asked for it', () async {
      await glossary.upsert(const TagTranslation(tag: 'long_hair', text: '长发'));

      await call('write_tag_translations', {
        'entries': [
          {'tag': 'long_hair', 'translation': '长长的头发'},
        ],
        'overwrite': true,
      });

      expect(glossary.lookup('long_hair')?.text, '长长的头发');
    });

    test('entries it cannot use are reported, not silently dropped', () async {
      final result = await call('write_tag_translations', {
        'entries': [
          {'tag': 'smile', 'translation': '微笑'},
          {'tag': '', 'translation': 'x'},
          {'tag': 'blank', 'translation': '   '},
        ],
      });

      expect(result['written'], 1);
      expect((result['rejected'] as List).length, 2);
    });

    test('an oversized batch is refused with the limit stated', () async {
      final result = await call('write_tag_translations', {
        'entries': [
          for (var i = 0; i < maxTranslationEntries + 1; i++)
            {'tag': 'tag_$i', 'translation': 't$i'},
        ],
      });

      expect(result['error'], contains('$maxTranslationEntries'));
      expect(glossary.count, 0);
    });

    test('an empty batch is an argument error, not a no-op success', () async {
      final result = await call('write_tag_translations', {'entries': []});

      expect(result['error'], isNotNull);
    });
  });

  group('fetch_danbooru_tag', () {
    test('returns other_names and the wiki summary', () async {
      final result = await call('fetch_danbooru_tag', {
        'tags': ['hatsune_miku'],
      });

      final row = (result['results'] as List).cast<Map<String, dynamic>>().single;
      expect(row['tag'], 'hatsune_miku');
      expect(row['known_to_danbooru'], isTrue);
      expect(row['other_names'], ['初音ミク']);
      expect(row['wiki'], 'A vocaloid.');
      expect(result['lookups_remaining'], maxDanbooruLookupsPerSession - 1);
    });

    test('more than five tags per call is refused', () async {
      final result = await call('fetch_danbooru_tag', {
        'tags': ['a', 'b', 'c', 'd', 'e', 'f'],
      });

      expect(result['error'], contains('5'));
      expect(danbooruRequests, 0);
    });

    test('the session budget stops a scrape and says what to do instead', () async {
      // Six tags a call would exceed the arg cap, so spend the budget five at
      // a time — the shape a model looping over a big glossary would produce.
      for (var i = 0; i < maxDanbooruLookupsPerSession / 5; i++) {
        await call('fetch_danbooru_tag', {
          'tags': [for (var j = 0; j < 5; j++) 'tag_${i}_$j'],
        });
      }
      // Two requests per tag (tag record + wiki page).
      expect(danbooruRequests, maxDanbooruLookupsPerSession * 2);

      final result = await call('fetch_danbooru_tag', {
        'tags': ['one_more'],
      });

      expect(result['error'], contains('budget'));
      // And no request went out past the cap.
      expect(danbooruRequests, maxDanbooruLookupsPerSession * 2);
    });
  });
}
