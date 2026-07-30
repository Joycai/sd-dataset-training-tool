import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:dataset_training_tool/models/tag_dictionary.dart';
import 'package:dataset_training_tool/models/tag_translation.dart';
import 'package:dataset_training_tool/services/tag_dictionary_service.dart';
import 'package:dataset_training_tool/services/tag_translation_service.dart';

const _csv = '''
1girl,0,5113288,"1girls,sole_female"
long_hair,0,3000000,
blue_eyes,0,2000000,
''';

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('tag_translations_test');
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  TagTranslationService service() =>
      TagTranslationService(storageDirectory: () async => temp);

  TagDictionaryService dictionary() =>
      TagDictionaryService(storageDirectory: () async => temp);

  File glossaryFile(String locale) => File('${temp.path}/$locale.json');

  group('glossary storage', () {
    test('an upsert survives a reload and folds every caption style', () async {
      final glossary = service();
      await glossary.load('zh');
      await glossary.upsert(
        const TagTranslation(tag: 'long_hair', text: '长发', note: '过肩'),
      );

      final reloaded = service();
      await reloaded.load('zh');
      expect(reloaded.count, 1);
      // Stored under danbooru's spelling, found under any of them: this is
      // what lets one glossary serve every caption style.
      expect(reloaded.glossFor('long_hair'), '长发');
      expect(reloaded.glossFor('long hair'), '长发');
      expect(reloaded.glossFor('Long_Hair'), '长发');
      expect(reloaded.lookup('long hair')?.note, '过肩');
    });

    test('each language keeps its own file', () async {
      final glossary = service();
      await glossary.load('zh');
      await glossary.upsert(
        const TagTranslation(tag: 'long_hair', text: '长发'),
      );

      // Switching languages switches the whole glossary — no fallback to the
      // one that happened to be loaded before.
      await glossary.load('ja');
      expect(glossary.count, 0);
      expect(glossary.glossFor('long_hair'), isNull);

      await glossary.load('zh');
      expect(glossary.glossFor('long_hair'), '长发');
      expect(await glossaryFile('ja').exists(), isFalse);
    });

    test('a spelling variant replaces the entry instead of doubling it', () async {
      final glossary = service();
      await glossary.load('zh');
      await glossary.upsert(const TagTranslation(tag: 'long hair', text: '长发'));
      await glossary.upsert(
        const TagTranslation(tag: 'long_hair', text: '长头发'),
      );

      // Two spellings fold to one lookup key, so keeping both would leave the
      // loser sitting in the file forever, fighting over the same tag.
      expect(glossary.count, 1);
      expect(glossary.glossFor('long_hair'), '长头发');
    });

    test('a corrupt file leaves the service usable and reports why', () async {
      await glossaryFile('zh').writeAsString('{ this is not json');
      final glossary = service();
      await glossary.load('zh');

      expect(glossary.count, 0);
      expect(glossary.lastError, isNotNull);
      // Still writable: losing glosses must not lock the user out of fixing
      // them.
      await glossary.upsert(const TagTranslation(tag: '1girl', text: '单人女性'));
      expect(glossary.glossFor('1girl'), '单人女性');
    });
  });

  group('bulk writes', () {
    test('upsertAll leaves untouched entries alone', () async {
      final glossary = service();
      await glossary.load('zh');
      await glossary.upsertAll(const [
        TagTranslation(tag: 'long_hair', text: '长发'),
        TagTranslation(tag: '1girl', text: '单人女性'),
      ]);

      final (written, skipped) = await glossary.upsertAll(const [
        TagTranslation(tag: 'blue_eyes', text: '蓝眼'),
      ]);

      expect((written, skipped), (1, 0));
      // The one guarantee a bulk producer must not be able to break: it can
      // only add and replace, never drop what it did not know about.
      expect(glossary.count, 3);
      expect(glossary.glossFor('long_hair'), '长发');
    });

    test('overwrite:false protects hand-written text', () async {
      final glossary = service();
      await glossary.load('zh');
      await glossary.upsert(
        const TagTranslation(tag: 'long_hair', text: '长发'),
      );

      final (written, skipped) = await glossary.upsertAll(
        const [
          TagTranslation(
            tag: 'long_hair',
            text: '长长的头发',
            source: TagTranslationSource.llm,
          ),
          TagTranslation(
            tag: '1girl',
            text: '单人女性',
            source: TagTranslationSource.llm,
          ),
        ],
        overwrite: false,
      );

      expect((written, skipped), (1, 1));
      expect(glossary.glossFor('long_hair'), '长发');
      expect(glossary.glossFor('1girl'), '单人女性');
    });

    test('clearing one source keeps the others', () async {
      final glossary = service();
      await glossary.load('zh');
      await glossary.upsertAll(const [
        TagTranslation(tag: 'long_hair', text: '长发'),
        TagTranslation(
          tag: '1girl',
          text: '单人女性',
          source: TagTranslationSource.llm,
        ),
        TagTranslation(
          tag: 'blue_eyes',
          text: '蓝眼',
          source: TagTranslationSource.llm,
        ),
      ]);

      expect(glossary.countBySource(TagTranslationSource.llm), 2);
      final removed = await glossary.clearBySource(TagTranslationSource.llm);

      expect(removed, 2);
      expect(glossary.count, 1);
      expect(glossary.glossFor('long_hair'), '长发');
    });

    test('empty text is refused rather than stored as a blank gloss', () async {
      final glossary = service();
      await glossary.load('zh');
      final (written, skipped) = await glossary.upsertAll(const [
        TagTranslation(tag: 'long_hair', text: '   '),
      ]);

      expect((written, skipped), (0, 1));
      expect(glossary.count, 0);
    });
  });

  group('import / export', () {
    test('an export round-trips', () async {
      final glossary = service();
      await glossary.load('zh');
      await glossary.upsertAll(const [
        TagTranslation(tag: 'long_hair', text: '长发', note: '过肩'),
        TagTranslation(
          tag: '1girl',
          text: '单人女性',
          source: TagTranslationSource.llm,
        ),
      ]);
      final exported = glossary.exportJson();

      final other = service();
      await other.load('ja');
      final (written, _) = await other.importJson(exported);

      expect(written, 2);
      expect(other.lookup('long_hair')?.note, '过肩');
      expect(other.lookup('1girl')?.source, TagTranslationSource.llm);
    });

    test('a hand-written bare map is accepted', () async {
      final glossary = service();
      await glossary.load('zh');
      final (written, _) = await glossary.importJson(
        jsonEncode({'long_hair': '长发', 'blue_eyes': ''}),
      );

      expect(written, 1);
      expect(glossary.glossFor('long_hair'), '长发');
      // An entry with no text is not a translation.
      expect(glossary.has('blue_eyes'), isFalse);
    });

    test('a non-object file is a FormatException, not a silent no-op', () async {
      final glossary = service();
      await glossary.load('zh');
      expect(
        () => glossary.importJson('[1, 2, 3]'),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('user-added dictionary entries', () {
    test('a custom tag is searchable and carries its category', () async {
      final dict = dictionary();
      await dict.loadCsv(_csv, full: true);
      await dict.setCustomEntries(const [
        TagDictionaryEntry(
          name: 'my_character_(oc)',
          category: TagCategory.character,
        ),
      ]);

      expect(dict.lookup('my_character_(oc)')?.category, TagCategory.character);
      final hits = dict.search('my_char');
      expect(hits, isNotEmpty);
      expect(hits.first.name, 'my_character_(oc)');
      expect(hits.first.isCustom, isTrue);
    });

    test('custom hits lead the list without taking all of it', () async {
      final dict = dictionary();
      await dict.loadCsv(_csv, full: true);
      await dict.setCustomEntries(const [
        TagDictionaryEntry(name: 'long_braid', category: TagCategory.general),
        TagDictionaryEntry(name: 'long_cape', category: TagCategory.general),
        TagDictionaryEntry(name: 'long_scarf', category: TagCategory.general),
        TagDictionaryEntry(name: 'long_coat', category: TagCategory.general),
      ]);

      final hits = dict.search('long', limit: 4);
      // Half the list at most: a handful of hand-added tags must not hide
      // danbooru behind a shared prefix.
      expect(hits.take(2).every((h) => h.isCustom), isTrue);
      expect(hits.any((h) => h.name == 'long_hair'), isTrue);
    });

    test('a name the dictionary already has is dropped', () async {
      final dict = dictionary();
      await dict.loadCsv(_csv, full: true);
      await dict.setCustomEntries(const [
        // Written in a different style on purpose — the check folds both sides.
        TagDictionaryEntry(name: 'long hair', category: TagCategory.meta),
        TagDictionaryEntry(name: 'my_oc', category: TagCategory.character),
      ]);

      expect(dict.customEntries.map((e) => e.name), ['my_oc']);
      // The real dictionary entry is untouched, so it still ranks and links.
      expect(dict.lookup('long_hair')?.category, TagCategory.general);
    });

    test('a custom tag stops being a local tag', () async {
      final dict = dictionary();
      await dict.loadCsv(_csv, full: true);
      dict.setLocalTags(datasetUsage: {'my_trigger_word': 40});

      expect(
        dict.search('my_trig').single.origin,
        TagSuggestionOrigin.local,
      );

      await dict.setCustomEntries(const [
        TagDictionaryEntry(
          name: 'my_trigger_word',
          category: TagCategory.character,
        ),
      ]);

      // One row, not two: "local" means covered by neither the dictionary nor
      // the user's own additions.
      final hits = dict.search('my_trig');
      expect(hits.single.origin, TagSuggestionOrigin.custom);
    });

    test('custom entries survive a reload', () async {
      final dict = dictionary();
      await dict.setCustomEntries(const [
        TagDictionaryEntry(name: 'my_oc', category: TagCategory.character),
      ]);

      final reloaded = dictionary();
      await reloaded.init();
      expect(reloaded.customEntries.single.name, 'my_oc');
      expect(reloaded.lookup('my_oc')?.category, TagCategory.character);
    });
  });
}
