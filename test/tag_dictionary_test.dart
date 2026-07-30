import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:dataset_training_tool/models/tag_dictionary.dart';
import 'package:dataset_training_tool/services/tag_dictionary_service.dart';
import 'package:dataset_training_tool/utils/external_links.dart';
import 'package:dataset_training_tool/utils/tag_text.dart';

/// WD label layout: `tag_id,name,category,count`, with a header row and the
/// four rating pseudo-tags the model emits alongside real tags.
const _wdCsv = '''
tag_id,name,category,count
9999999,general,9,1589178
9999996,explicit,9,706509
470575,1girl,0,5113288
16867,long_hair,0,3000000
13200,hair_ornament,0,900000
1234,hatsune_miku,4,200000
5678,fate/grand_order,3,150000
''';

/// tagcomplete layout: `name,category,count,"aliases"`, no header.
const _fullCsv = '''
1girl,0,5113288,"1girls,sole_female"
long_hair,0,3000000,
blue_eyes,0,2000000,"blue_eye,blue_eyed"
hair_ornament,0,900000,
''';

void main() {
  group('parsing', () {
    test('WD labels drop the header and the rating pseudo-tags', () async {
      final dictionary = TagDictionaryService();
      await dictionary.loadCsv(_wdCsv);

      expect(dictionary.source, TagDictionarySource.bundled);
      expect(dictionary.entryCount, 5);
      // "general" and "explicit" are ratings (category 9), not danbooru tags.
      expect(dictionary.lookup('general'), isNull);
      expect(dictionary.lookup('explicit'), isNull);
      expect(dictionary.lookup('1girl')?.postCount, 5113288);
      expect(
        dictionary.lookup('hatsune_miku')?.category,
        TagCategory.character,
      );
      expect(
        dictionary.lookup('fate/grand_order')?.category,
        TagCategory.copyright,
      );
    });

    test('the quoted alias column is split on its inner commas', () async {
      final dictionary = TagDictionaryService();
      await dictionary.loadCsv(_fullCsv, full: true);

      expect(dictionary.source, TagDictionarySource.full);
      expect(dictionary.lookup('1girl')?.aliases, ['1girls', 'sole_female']);
      expect(dictionary.lookup('long_hair')?.aliases, isEmpty);
    });

    test('the bundled asset parses into a usable dictionary', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final dictionary = TagDictionaryService();
      await dictionary.loadBundled();

      expect(dictionary.lastError, isNull);
      expect(dictionary.entryCount, greaterThan(10000));
      expect(dictionary.lookup('1girl'), isNotNull);
      expect(
        dictionary.lookup('hatsune_miku')?.category,
        TagCategory.character,
      );
      // The rating rows must not leak in — "general" as a *tag* does not exist
      // and would otherwise top every completion of "gen".
      expect(dictionary.lookup('general'), isNull);
    });
  });

  group('search', () {
    late TagDictionaryService dictionary;

    setUp(() async {
      dictionary = TagDictionaryService();
      await dictionary.loadCsv(_fullCsv, full: true);
    });

    test('exact name outranks a prefix, prefix outranks an interior word', () {
      final hits = dictionary.search('hair');
      expect(hits.map((h) => h.name), ['hair_ornament', 'long_hair']);
      expect(hits.first.kind, TagMatchKind.namePrefix);
      expect(hits.last.kind, TagMatchKind.nameWordPrefix);
    });

    test('equally good matches are ordered by post count', () async {
      await dictionary.loadCsv(_wdCsv);
      final hits = dictionary.search('h');
      expect(hits.map((h) => h.name), [
        'hair_ornament', // 900k, name prefix
        'hatsune_miku', // 200k, name prefix
        'long_hair', // interior word, so last whatever its count
      ]);
    });

    test('the query may be written in any caption style', () {
      for (final query in ['long h', 'long_h', 'LONG H']) {
        expect(dictionary.search(query).map((h) => h.name), [
          'long_hair',
        ], reason: query);
      }
    });

    test('an alias hit resolves to the canonical tag and says so', () {
      // "blue_eye" is both an exact alias and a prefix of the canonical name.
      // One entry must never occupy two rows, and the exact alias is the more
      // informative label: it tells the user they typed a deprecated spelling.
      final hits = dictionary.search('blue_eye');
      expect(hits, hasLength(1));
      expect(hits.single.name, 'blue_eyes');
      expect(hits.single.kind, TagMatchKind.exactAlias);

      final aliasOnly = dictionary.search('sole');
      expect(aliasOnly.single.name, '1girl');
      expect(aliasOnly.single.kind, TagMatchKind.aliasPrefix);
      expect(aliasOnly.single.matchedAlias, 'sole female');
    });

    test('an empty or unmatched query yields nothing', () {
      expect(dictionary.search(''), isEmpty);
      expect(dictionary.search('   '), isEmpty);
      expect(dictionary.search('zzzzz'), isEmpty);
    });

    test('the limit caps the row count', () {
      expect(dictionary.search('', limit: 0), isEmpty);
      expect(dictionary.search('h', limit: 1), hasLength(1));
    });

    test('lookup accepts a tag written in the caption\'s own style', () {
      expect(dictionary.lookup('long hair')?.name, 'long_hair');
      expect(dictionary.lookup('LONG_HAIR')?.name, 'long_hair');
      expect(dictionary.lookup('not_a_tag'), isNull);
    });
  });

  group('local vocabulary', () {
    late TagDictionaryService dictionary;

    setUp(() async {
      dictionary = TagDictionaryService();
      await dictionary.loadCsv(_fullCsv, full: true);
    });

    test('only tags the dictionary lacks become local suggestions', () {
      dictionary.setLocalTags(
        datasetUsage: {
          'long_hair': 40, // danbooru knows this one
          'long hair': 40, // ...and this is the same tag in caption style
          'myoc_trigger': 12,
        },
      );

      final hits = dictionary.search('long');
      expect(hits.where((h) => h.isLocal).map((h) => h.name), isEmpty);
      // The dictionary entry appears exactly once, not once per spelling.
      expect(hits.where((h) => h.name == 'long_hair'), hasLength(1));

      final local = dictionary.search('myoc');
      expect(local.single.name, 'myoc_trigger');
      expect(local.single.origin, TagSuggestionOrigin.local);
      expect(local.single.count, 12);
    });

    test(
      'local hits keep a slice of the list when the dictionary fills it',
      () async {
        // Eight dictionary tags all starting with "long" would otherwise use up
        // every row of the default limit.
        await dictionary.loadCsv(
          [
            for (var i = 0; i < 8; i++) 'long_${i}_tag,0,${1000 - i},',
          ].join('\n'),
          full: true,
        );
        dictionary.setLocalTags(
          datasetUsage: {'long_trigger': 9, 'long_other': 6},
        );

        final hits = dictionary.search('long');
        expect(hits, hasLength(8));
        final local = hits.where((h) => h.isLocal).toList();
        expect(local.map((h) => h.name), ['long_trigger', 'long_other']);
        // Dictionary hits still come first.
        expect(hits.take(6).every((h) => !h.isLocal), isTrue);
      },
    );

    test('local hits are ordered by how much the dataset uses them', () {
      dictionary.setLocalTags(
        datasetUsage: {'zzz_rare': 6, 'zzz_common': 90, 'zzz_mid': 20},
      );
      expect(dictionary.search('zzz').map((h) => h.name), [
        'zzz_common',
        'zzz_mid',
        'zzz_rare',
      ]);
    });

    test('a dataset tag has to earn its place before it is suggested', () {
      dictionary.setLocalTags(
        datasetUsage: {
          'zzz_probable_typo': TagDictionaryService.minDatasetUsage - 1,
          'zzz_deliberate': TagDictionaryService.minDatasetUsage,
        },
      );
      expect(dictionary.search('zzz').map((h) => h.name), ['zzz_deliberate']);
    });

    test('library tags are suggested however little the dataset uses them', () {
      dictionary.setLocalTags(
        datasetUsage: {'zzz_curated': 2, 'zzz_stray': 2},
        libraryTags: ['zzz_curated', 'zzz_unused'],
      );
      // Putting a tag in the library is the deliberate act the usage
      // threshold is only estimating, so it overrides the threshold.
      final hits = dictionary.search('zzz');
      expect(hits.map((h) => h.name), ['zzz_curated', 'zzz_unused']);
      // The library entry still reports its real dataset usage, and a tag on
      // no image at all weighs zero.
      expect(hits.first.count, 2);
      expect(hits.last.count, 0);
    });

    test('localUsage reports raw usage, including below the threshold', () {
      dictionary.setLocalTags(
        datasetUsage: {'myoc_trigger': 12, 'probable_typo': 2},
      );
      expect(dictionary.localUsage('myoc_trigger'), 12);
      expect(dictionary.localUsage('MYOC TRIGGER'), 12); // style-insensitive
      expect(dictionary.localUsage('never_seen'), isNull);
      // The tag lookup menu exists to tell a typo from a trigger word, so it
      // must still see the tags the suggestion list filtered out.
      expect(dictionary.localUsage('probable_typo'), 2);
      expect(dictionary.search('probable'), isEmpty);
    });

    test('loading a dictionary re-filters the local tags', () async {
      final fresh = TagDictionaryService();
      // Local tags can arrive before the dictionary has finished parsing.
      fresh.setLocalTags(datasetUsage: {'long_hair': 40, 'myoc_trigger': 12});
      expect(fresh.search('long').single.isLocal, isTrue);

      await fresh.loadCsv(_fullCsv, full: true);
      expect(fresh.search('long').every((h) => !h.isLocal), isTrue);
      expect(fresh.search('myoc').single.isLocal, isTrue);
    });
  });

  group('user-added entries', () {
    // The only group here that touches the disk: setCustomEntries persists, and
    // "survive a reload" is the whole point of it.
    late Directory temp;
    late TagDictionaryService dictionary;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('tag_dictionary_custom_');
      dictionary = TagDictionaryService(storageDirectory: () async => temp);
    });

    tearDown(() async {
      if (await temp.exists()) await temp.delete(recursive: true);
    });

    test('a custom tag is searchable and carries its category', () async {
      await dictionary.loadCsv(_fullCsv, full: true);
      await dictionary.setCustomEntries(const [
        TagDictionaryEntry(
          name: 'my_character_(oc)',
          category: TagCategory.character,
        ),
      ]);

      expect(
        dictionary.lookup('my_character_(oc)')?.category,
        TagCategory.character,
      );
      final hits = dictionary.search('my_char');
      expect(hits, isNotEmpty);
      expect(hits.first.name, 'my_character_(oc)');
      expect(hits.first.isCustom, isTrue);
    });

    test('custom hits lead the list without taking all of it', () async {
      await dictionary.loadCsv(_fullCsv, full: true);
      await dictionary.setCustomEntries(const [
        TagDictionaryEntry(name: 'long_braid', category: TagCategory.general),
        TagDictionaryEntry(name: 'long_cape', category: TagCategory.general),
        TagDictionaryEntry(name: 'long_scarf', category: TagCategory.general),
        TagDictionaryEntry(name: 'long_coat', category: TagCategory.general),
      ]);

      final hits = dictionary.search('long', limit: 4);
      // Half the list at most: a handful of hand-added tags must not hide
      // danbooru behind a shared prefix.
      expect(hits.take(2).every((h) => h.isCustom), isTrue);
      expect(hits.any((h) => h.name == 'long_hair'), isTrue);
    });

    test('a name the dictionary already has is dropped', () async {
      await dictionary.loadCsv(_fullCsv, full: true);
      await dictionary.setCustomEntries(const [
        // Written in a different style on purpose — the check folds both sides.
        TagDictionaryEntry(name: 'long hair', category: TagCategory.meta),
        TagDictionaryEntry(name: 'my_oc', category: TagCategory.character),
      ]);

      expect(dictionary.customEntries.map((e) => e.name), ['my_oc']);
      // The real dictionary entry is untouched, so it still ranks and links.
      expect(dictionary.lookup('long_hair')?.category, TagCategory.general);
    });

    test('a custom tag stops being a local tag', () async {
      await dictionary.loadCsv(_fullCsv, full: true);
      dictionary.setLocalTags(datasetUsage: {'my_trigger_word': 40});

      expect(dictionary.search('my_trig').single.origin, TagSuggestionOrigin.local);

      await dictionary.setCustomEntries(const [
        TagDictionaryEntry(
          name: 'my_trigger_word',
          category: TagCategory.character,
        ),
      ]);

      // One row, not two: "local" means covered by neither the dictionary nor
      // the user's own additions.
      expect(
        dictionary.search('my_trig').single.origin,
        TagSuggestionOrigin.custom,
      );
    });

    test('custom entries survive a reload', () async {
      await dictionary.setCustomEntries(const [
        TagDictionaryEntry(name: 'my_oc', category: TagCategory.character),
      ]);

      final reloaded = TagDictionaryService(
        storageDirectory: () async => temp,
      );
      await reloaded.init();
      expect(reloaded.customEntries.single.name, 'my_oc');
      expect(reloaded.lookup('my_oc')?.category, TagCategory.character);
    });
  });

  group('links', () {
    test('a caption-style tag becomes a canonical wiki URL', () {
      expect(
        danbooruWikiUrl('long hair').toString(),
        'https://danbooru.donmai.us/wiki_pages/long_hair',
      );
      // Escaped parens are a caption convention, not part of the tag.
      expect(
        danbooruWikiUrl(r'smile \(expression\)').toString(),
        'https://danbooru.donmai.us/wiki_pages/smile_(expression)',
      );
    });

    test('a slash in a tag is escaped, not read as a path separator', () {
      expect(
        danbooruWikiUrl('fate/grand order').toString(),
        'https://danbooru.donmai.us/wiki_pages/fate%2Fgrand_order',
      );
    });

    test('the post search carries the tag as a query parameter', () {
      expect(
        danbooruPostsUrl('long hair').toString(),
        'https://danbooru.donmai.us/posts?tags=long_hair',
      );
    });
  });

  group('tag text folding', () {
    test('lookup keys collapse style differences', () {
      expect(tagLookupKey('Long_Hair'), 'long hair');
      expect(tagLookupKey(r'smile \(expression\)'), 'smile (expression)');
      expect(tagLookupKey('  spaced   out  '), 'spaced out');
    });

    test('canonical names are underscored and unescaped', () {
      expect(danbooruTagName('long hair'), 'long_hair');
      expect(danbooruTagName(r'smile \(expression\)'), 'smile_(expression)');
    });
  });
}
