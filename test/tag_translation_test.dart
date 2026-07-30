import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:dataset_training_tool/models/tag_translation.dart';
import 'package:dataset_training_tool/services/tag_translation_service.dart';

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

    test('a file from a newer schema is reported and left untouched', () async {
      final onDisk = jsonEncode({
        'schema': TagTranslationService.schemaVersion + 1,
        'entries': {
          'long_hair': {'text': '长发', 'tone': 'formal'},
        },
      });
      await glossaryFile('zh').writeAsString(onDisk);

      final glossary = service();
      await glossary.load('zh');

      expect(glossary.count, 0);
      expect(glossary.lastError, contains('schema'));

      // Unlike a corrupt file, this one still holds the user's translations —
      // in a shape with fields this build would drop. Writing is refused so a
      // downgrade cannot quietly rewrite it to the older layout.
      final (written, skipped) = await glossary.upsertAll(const [
        TagTranslation(tag: '1girl', text: '单人女性'),
      ]);
      expect((written, skipped), (0, 1));
      expect(await glossaryFile('zh').readAsString(), onDisk);

      // And the freeze lifts as soon as a readable file loads.
      await glossaryFile('zh').writeAsString(jsonEncode({'long_hair': '长发'}));
      await glossary.load('zh');
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

}
