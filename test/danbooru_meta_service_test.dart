import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:dataset_training_tool/models/tag_dictionary.dart';
import 'package:dataset_training_tool/services/danbooru_api.dart';
import 'package:dataset_training_tool/services/danbooru_meta_service.dart';

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('danbooru_meta_');
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  DanbooruMetaService service() =>
      DanbooruMetaService(storageDirectory: () async => temp);

  const found = DanbooruTagInfo(
    name: 'long_hair',
    category: TagCategory.general,
    postCount: 3000000,
    otherNames: ['ロングヘア', '長髪'],
    wikiExcerpt: 'Hair below the shoulder blades.',
    knownToDanbooru: true,
    hasWiki: true,
  );

  test('a record round-trips through the file', () async {
    final first = service();
    await first.init();
    await first.record(found);

    final second = service();
    await second.init();
    final read = second.lookup('long_hair');
    expect(read?.knownToDanbooru, isTrue);
    expect(read?.category, TagCategory.general);
    expect(read?.postCount, 3000000);
    expect(read?.otherNames, ['ロングヘア', '長髪']);
    expect(read?.wikiExcerpt, 'Hair below the shoulder blades.');
    expect(read?.hasWiki, isTrue);
  });

  test('lookup folds caption spelling', () async {
    final s = service();
    await s.init();
    await s.record(found);

    expect(s.lookup('Long Hair')?.name, 'long_hair');
    expect(s.has('long hair'), isTrue);
  });

  test('a "not on danbooru" mark persists and is not a hit', () async {
    final first = service();
    await first.init();
    await first.record(const DanbooruTagInfo(name: 'my_private_tag'));

    final second = service();
    await second.init();
    // Recorded — so a batch skips it — but recorded as absent.
    expect(second.has('my_private_tag'), isTrue);
    expect(second.isMissing('my_private_tag'), isTrue);
    expect(second.lookup('my_private_tag')?.knownToDanbooru, isFalse);
  });

  test('an alias query is recorded under both spellings', () async {
    final s = service();
    await s.init();
    // The dataset says `1girls`; danbooru canonicalizes to `1girl`. Without
    // the second key the alias would be re-fetched on every batch pass.
    await s.record(
      const DanbooruTagInfo(name: '1girl', knownToDanbooru: true),
      queriedAs: '1girls',
    );

    expect(s.has('1girl'), isTrue);
    expect(s.has('1girls'), isTrue);
    expect(s.lookup('1girls')?.name, '1girl');
  });

  test('clearMissing drops only the marks', () async {
    final s = service();
    await s.init();
    await s.record(found);
    await s.record(const DanbooruTagInfo(name: 'gone_tag'));

    expect(await s.clearMissing(), 1);
    expect(s.has('gone_tag'), isFalse);
    expect(s.has('long_hair'), isTrue);
  });

  test('a corrupt file reports but leaves the service writable', () async {
    await File('${temp.path}/danbooru_meta.json').writeAsString('{ not json');
    final s = service();
    await s.init();

    expect(s.lastError, isNotNull);
    // Everything here can be re-fetched, so locking the user out would be
    // the worse failure.
    await s.record(found);
    expect(s.has('long_hair'), isTrue);

    final reread = service();
    await reread.init();
    expect(reread.has('long_hair'), isTrue);
  });

  test('a newer schema freezes writes', () async {
    final file = File('${temp.path}/danbooru_meta.json');
    await file.writeAsString('{"schema": 99, "entries": {}}');
    final s = service();
    await s.init();

    expect(s.lastError, contains('schema 99'));
    await s.record(found);
    expect(s.has('long_hair'), isFalse);
    // The file a newer build wrote is left byte-for-byte alone.
    expect(await file.readAsString(), '{"schema": 99, "entries": {}}');
  });

  group('importEntries', () {
    test('merge keeps the local record, overwrite takes the file', () async {
      final s = service();
      await s.init();
      await s.record(found);

      final incoming = {
        'long_hair': const DanbooruTagInfo(
          name: 'long_hair',
          knownToDanbooru: true,
          wikiExcerpt: 'From the backup.',
        ).toJson(),
        'blue_eyes': const DanbooruTagInfo(
          name: 'blue_eyes',
          knownToDanbooru: true,
        ).toJson(),
      };

      expect(await s.importEntries(incoming), 1);
      expect(s.lookup('long_hair')?.wikiExcerpt, found.wikiExcerpt);
      expect(s.has('blue_eyes'), isTrue);

      expect(await s.importEntries(incoming, overwrite: true), 2);
      expect(s.lookup('long_hair')?.wikiExcerpt, 'From the backup.');
    });

    test('a backup fetchedAt stamp is carried, not re-minted', () async {
      final s = service();
      await s.init();
      await s.importEntries({
        'long_hair': {...found.toJson(), 'fetchedAt': '2026-01-01T00:00:00Z'},
      });

      final raw =
          jsonDecode(
                await File('${temp.path}/danbooru_meta.json').readAsString(),
              )
              as Map<String, dynamic>;
      expect(
        (raw['entries'] as Map)['long_hair']['fetchedAt'],
        '2026-01-01T00:00:00Z',
      );
    });
  });
}
