import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:dataset_training_tool/models/caption_type.dart';
import 'package:dataset_training_tool/services/agent/agent_tools.dart';
import 'package:dataset_training_tool/services/agent/caption_variant_tools.dart';
import 'package:dataset_training_tool/services/agent/dataset_tools.dart';
import 'package:dataset_training_tool/services/agent/json_caption_tools.dart';
import 'package:dataset_training_tool/state/dataset_state.dart';
import 'package:dataset_training_tool/state/tag_ops.dart';

// 1x1 transparent PNG.
const _pngBytes = [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x62, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
];

/// The JSON type is the *active* one here: a dataset whose only caption
/// flavor is structured is exactly the case the restructure has to serve,
/// and it is the one where a wrong write also corrupts the app's own state.
const _types = [
  CaptionType(
    id: CaptionType.defaultId,
    name: 'anima',
    extension: '.json',
    format: CaptionFormat.json,
  ),
  CaptionType(id: 'wd', name: 'WD14', extension: '.txt'),
];

void main() {
  late Directory tempDir;
  late DatasetState dataset;
  late TagOps tagOps;
  late ToolRegistry registry;

  String img(String name) => p.join(tempDir.path, '$name.png');
  String cap(String name, [String ext = '.json']) =>
      p.join(tempDir.path, '$name$ext');
  Future<String> readCap(String name, [String ext = '.json']) =>
      File(cap(name, ext)).readAsString();

  Future<Map<String, dynamic>> call(
    String tool, [
    Map<String, dynamic> args = const {},
  ]) async {
    final result = await registry.dispatch(tool, jsonEncode(args));
    return jsonDecode(result.text) as Map<String, dynamic>;
  }

  Future<void> writeJson(String name, Object document) => File(
    cap(name),
  ).writeAsString(const JsonEncoder.withIndent('  ').convert(document));

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('json_caption_test_');
    for (final name in ['001', '002', '003']) {
      await File(img(name)).writeAsBytes(_pngBytes);
    }
    await writeJson('001', {
      'chara': ['hatsune miku'],
      'quality': ['masterpiece', 'best quality'],
      'tags': ['1girl', 'smile', 'long hair'],
      'nl': 'A girl smiling at the camera.',
    });
    await writeJson('002', {
      'chara': ['kagamine rin'],
      'quality': ['best quality'],
      'tags': ['1girl', 'blonde hair'],
      'nl': 'A blonde girl.',
    });
    // 003 has no caption at all.

    dataset = DatasetState();
    await dataset.scan(
      directoryPath: tempDir.path,
      recursive: false,
      captionExtension: '.json',
      captionFormat: CaptionFormat.json,
    );
    tagOps = TagOps(dataset: dataset);
    final deps = DatasetToolsDeps(
      dataset: dataset,
      rootDir: () => tempDir.path,
      libraryTags: () => const [],
      tagGroups: () => const [],
      captionTypes: () => _types,
    );
    registry = ToolRegistry([
      ...buildReadOnlyTools(deps),
      ...buildWriteTools(deps, tagOps),
      ...buildCaptionVariantTools(deps, tagOps),
      ...buildJsonCaptionTools(deps, tagOps),
    ]);
  });

  tearDown(() async {
    tagOps.dispose();
    dataset.dispose();
    await tempDir.delete(recursive: true);
  });

  group('inspect_json_captions', () {
    test('reports keys, kinds, tag counts and key orders', () async {
      final out = await call('inspect_json_captions', {'extension': '.json'});
      expect(out['with_caption'], 2);
      expect(out['without_caption'], 1);
      expect(out['unparseable'], 0);
      expect(out['root_kinds'], {'object': 2});

      final orders = (out['key_orders'] as List).cast<Map>();
      expect(orders, hasLength(1));
      expect(orders.single['keys'], ['chara', 'quality', 'tags', 'nl']);
      expect(orders.single['images'], 2);

      final keys = {
        for (final k in (out['keys'] as List).cast<Map>()) k['path']: k,
      };
      expect(keys.keys, containsAll(['chara', 'quality', 'tags', 'nl']));
      expect(keys['tags']!['kinds'], ['array<string>']);
      expect(keys['tags']!['images'], 2);
      expect(keys['tags']!['tags'], 5);
      expect(keys['nl']!['kinds'], ['string']);
      // The prose field's sentence is split by the tag grammar like any
      // other string leaf — which is exactly the signal that it is not a
      // tag field and belongs in a "preserve" field.
      expect(keys['nl']!['distinct_tags'], greaterThan(0));
    });

    test(
      'names the files that do not parse instead of skipping them',
      () async {
        await File(cap('003')).writeAsString('{not json');
        final out = await call('inspect_json_captions', {'extension': '.json'});
        expect(out['unparseable'], 1);
        final examples = (out['unparseable_examples'] as List).cast<Map>();
        expect(examples.single['path'], '003.png');
        expect(examples.single['error'], contains('not valid JSON'));
      },
    );

    test('refuses a caption type that is not JSON-format', () async {
      final out = await call('inspect_json_captions', {'extension': '.txt'});
      expect(out['error'], contains('configured as tags'));
    });
  });

  group('restructure_json_captions', () {
    test('renames and reorders fields without touching the tags', () async {
      final out = await call('restructure_json_captions', {
        'extension': '.json',
        'fields': [
          {'name': 'quality', 'kind': 'array'},
          {'name': 'character', 'kind': 'string'},
          {'name': 'general', 'kind': 'array'},
          {'name': 'description', 'kind': 'preserve'},
        ],
        'from': {
          'character': ['chara'],
          'general': ['tags'],
          'description': ['nl'],
        },
        'unassigned_field': 'general',
      });
      expect(out['written'], 2);
      expect(out['failed_images'], isNull);

      final doc = jsonDecode(await readCap('001')) as Map<String, dynamic>;
      // Field order is the declared one, not the old document's.
      expect(doc.keys.toList(), [
        'quality',
        'character',
        'general',
        'description',
      ]);
      expect(doc['quality'], ['masterpiece', 'best quality']);
      expect(doc['character'], 'hatsune miku');
      expect(doc['general'], ['1girl', 'smile', 'long hair']);
      // A preserved field is copied over verbatim, not re-split into tags.
      expect(doc['description'], 'A girl smiling at the camera.');
    });

    test('moves individual tags between fields via assign', () async {
      await call('restructure_json_captions', {
        'extension': '.json',
        'fields': [
          {'name': 'chara', 'kind': 'array'},
          {'name': 'quality', 'kind': 'array'},
          {'name': 'tags', 'kind': 'array'},
          {'name': 'nl', 'kind': 'preserve'},
        ],
        'assign': {'long_hair': 'chara', 'best quality': 'tags'},
        'unassigned_field': 'tags',
      });
      final doc = jsonDecode(await readCap('001')) as Map<String, dynamic>;
      // Matching folds underscore/space style, and the tag keeps the
      // spelling the file had.
      expect(doc['chara'], ['hatsune miku', 'long hair']);
      expect(doc['quality'], ['masterpiece']);
      expect(doc['tags'], ['best quality', '1girl', 'smile']);
    });

    test(
      'sends tags of unrouted keys to the catch-all and reports them',
      () async {
        final out = await call('restructure_json_captions', {
          'extension': '.json',
          'fields': [
            {'name': 'quality', 'kind': 'array'},
            {'name': 'everything_else', 'kind': 'array'},
            {'name': 'nl', 'kind': 'preserve'},
          ],
          'unassigned_field': 'everything_else',
        });
        expect(out['written'], 2);
        expect(out['unrouted_keys_seen'], containsAll(['chara', 'tags']));
        final doc = jsonDecode(await readCap('001')) as Map<String, dynamic>;
        expect(doc['everything_else'], [
          'hatsune miku',
          '1girl',
          'smile',
          'long hair',
        ]);
        expect(doc['quality'], ['masterpiece', 'best quality']);
      },
    );

    test('orders tags inside array fields by tag_priority', () async {
      await call('restructure_json_captions', {
        'extension': '.json',
        'fields': [
          {'name': 'chara', 'kind': 'array'},
          {'name': 'quality', 'kind': 'array'},
          {'name': 'tags', 'kind': 'array'},
          {'name': 'nl', 'kind': 'preserve'},
        ],
        'unassigned_field': 'tags',
        'tag_priority': ['long_hair', '1girl'],
      });
      final doc = jsonDecode(await readCap('001')) as Map<String, dynamic>;
      expect(doc['tags'], ['long hair', '1girl', 'smile']);
    });

    test(
      'writes constants verbatim and keeps them out of the tag check',
      () async {
        await call('restructure_json_captions', {
          'extension': '.json',
          'fields': [
            {'name': 'artist', 'kind': 'string'},
            {'name': 'chara', 'kind': 'array'},
            {'name': 'quality', 'kind': 'array'},
            {'name': 'tags', 'kind': 'array'},
            {'name': 'nl', 'kind': 'preserve'},
          ],
          'constants': {'artist': 'unknown artist'},
          'unassigned_field': 'tags',
        });
        final doc = jsonDecode(await readCap('001')) as Map<String, dynamic>;
        expect(doc.keys.first, 'artist');
        expect(doc['artist'], 'unknown artist');
        // The constant's words did not leak into the tag comparison, and no
        // tag went missing to make room for it.
        expect(doc['chara'], ['hatsune miku']);
        expect(doc['tags'], ['1girl', 'smile', 'long hair']);
      },
    );

    test('drop_empty omits fields that came out empty', () async {
      final fields = [
        {'name': 'chara', 'kind': 'array'},
        {'name': 'quality', 'kind': 'array'},
        {'name': 'tags', 'kind': 'array'},
        {'name': 'artist', 'kind': 'array'},
        {'name': 'nl', 'kind': 'preserve'},
      ];
      await call('restructure_json_captions', {
        'extension': '.json',
        'fields': fields,
        'unassigned_field': 'tags',
      });
      expect(
        (jsonDecode(await readCap('001')) as Map).containsKey('artist'),
        isTrue,
      );

      await call('restructure_json_captions', {
        'extension': '.json',
        'fields': fields,
        'unassigned_field': 'tags',
        'drop_empty': true,
      });
      expect(
        (jsonDecode(await readCap('001')) as Map).containsKey('artist'),
        isFalse,
      );
    });

    test(
      'skips an image whose string field would collect several tags',
      () async {
        final out = await call('restructure_json_captions', {
          'extension': '.json',
          'fields': [
            {'name': 'chara', 'kind': 'array'},
            {'name': 'quality', 'kind': 'string'},
            {'name': 'tags', 'kind': 'array'},
            {'name': 'nl', 'kind': 'preserve'},
          ],
          'unassigned_field': 'tags',
        });
        // 001 has two quality tags and fails; 002 has one and is written.
        expect(out['written'], 1);
        expect(out['failed_images'], 1);
        final failure = (out['failures'] as List).cast<Map>().single;
        expect(failure['path'], '001.png');
        expect(failure['error'], contains('would get 2 tags'));
        // The failed image is untouched, not half-rewritten.
        final doc = jsonDecode(await readCap('001')) as Map<String, dynamic>;
        expect(doc.keys.toList(), ['chara', 'quality', 'tags', 'nl']);
      },
    );

    test('keeps the dataset tag index and undo in step', () async {
      final before = dataset.tagsOf(img('001'));
      await call('restructure_json_captions', {
        'extension': '.json',
        'fields': [
          {'name': 'tags', 'kind': 'array'},
          {'name': 'nl', 'kind': 'preserve'},
        ],
        'unassigned_field': 'tags',
      });
      // The active type was rewritten in place: the index must follow the
      // new document rather than keep serving the old one.
      expect(dataset.tagsOf(img('001')), before);
      expect(jsonDecode(await readCap('001')), {
        'tags': [
          'hatsune miku',
          'masterpiece',
          'best quality',
          '1girl',
          'smile',
          'long hair',
        ],
        'nl': 'A girl smiling at the camera.',
      });

      expect(tagOps.undoLabel, startsWith('AI: restructure'));
      final undo = await tagOps.undo();
      expect(undo.failed, 0);
      final restored = jsonDecode(await readCap('001')) as Map<String, dynamic>;
      expect(restored.keys.toList(), ['chara', 'quality', 'tags', 'nl']);
      expect(dataset.tagsOf(img('001')), before);
    });

    test('rejects a shape whose old key feeds two fields', () async {
      final out = await call('restructure_json_captions', {
        'extension': '.json',
        'fields': [
          {'name': 'a', 'kind': 'array'},
          {'name': 'b', 'kind': 'array'},
        ],
        'from': {
          'a': ['tags'],
          'b': ['tags'],
        },
        'unassigned_field': 'a',
      });
      expect(out['error'], contains('routed to both'));
      // Nothing was written: the shape failed before the sweep started.
      final doc = jsonDecode(await readCap('001')) as Map<String, dynamic>;
      expect(doc.keys.toList(), ['chara', 'quality', 'tags', 'nl']);
    });

    test('rejects a catch-all that is not an array field', () async {
      final out = await call('restructure_json_captions', {
        'extension': '.json',
        'fields': [
          {'name': 'tags', 'kind': 'string'},
        ],
        'unassigned_field': 'tags',
      });
      expect(out['error'], contains('must be an "array" field'));
    });

    test('reports an unparseable document instead of overwriting it', () async {
      await File(cap('003')).writeAsString('{broken');
      final out = await call('restructure_json_captions', {
        'extension': '.json',
        'fields': [
          {'name': 'tags', 'kind': 'array'},
          {'name': 'nl', 'kind': 'preserve'},
        ],
        'unassigned_field': 'tags',
      });
      expect(out['written'], 2);
      expect(out['failed_images'], 1);
      expect(await readCap('003'), '{broken');
    });
  });

  group('edit_json_captions', () {
    test('adds, removes and renames tags while the shape stays put', () async {
      final out = await call('edit_json_captions', {
        'extension': '.json',
        'remove': ['masterpiece'],
        'rename': {'1girl': '1boy'},
        'add': {
          'tags': ['solo'],
        },
      });
      expect(out['written'], 2);
      expect(out['skipped_without_caption'], 1);
      // Counted per caption: "masterpiece" is only in 001.
      expect(out['removed_tags'], {'masterpiece': 1});
      expect(out['renamed_tags'], {'1girl': 2});
      expect(out['added_tags'], {'tags: solo': 2});

      final one = jsonDecode(await readCap('001')) as Map<String, dynamic>;
      expect(one.keys.toList(), ['chara', 'quality', 'tags', 'nl']);
      expect(one['quality'], ['best quality']);
      expect(one['tags'], ['1boy', 'smile', 'long hair', 'solo']);
      // No rule matched the prose leaf, so it comes out byte-identical
      // rather than re-joined through the tag grammar.
      expect(one['nl'], 'A girl smiling at the camera.');
      expect(jsonDecode(await readCap('002'))['tags'], [
        '1boy',
        'blonde hair',
        'solo',
      ]);

      // The active type was rewritten in place: the index has to follow.
      expect(dataset.tagsOf(img('001')), contains('1boy'));
      expect(dataset.tagsOf(img('001')), isNot(contains('1girl')));
      expect(dataset.tagsOf(img('001')), isNot(contains('masterpiece')));

      expect(tagOps.undoLabel, startsWith('AI: edit'));
      final undo = await tagOps.undo();
      expect(undo.failed, 0);
      expect(jsonDecode(await readCap('001'))['tags'], [
        '1girl',
        'smile',
        'long hair',
      ]);
      expect(dataset.tagsOf(img('001')), contains('1girl'));
    });

    test('a rename onto a tag the field already has merges into it', () async {
      final out = await call('edit_json_captions', {
        'extension': '.json',
        'rename': {'long hair': 'smile'},
      });
      expect(out['written'], 1);
      expect(jsonDecode(await readCap('001'))['tags'], ['1girl', 'smile']);
    });

    test('a missing add target is created, a non-array one is reported',
        () async {
      final created = await call('edit_json_captions', {
        'extension': '.json',
        'add': {
          'environment': ['outdoors'],
        },
      });
      expect(created['written'], 2);
      expect(created['fields_created'], 2);
      final one = jsonDecode(await readCap('001')) as Map<String, dynamic>;
      expect(one.keys.toList(), ['chara', 'quality', 'tags', 'nl', 'environment']);
      expect(one['environment'], ['outdoors']);

      final scalar = await call('edit_json_captions', {
        'extension': '.json',
        'add': {
          'nl': ['outdoors'],
        },
      });
      expect(scalar['error'], contains('not an array'));
      expect(jsonDecode(await readCap('001'))['nl'], isA<String>());
    });

    test('skip_fields keeps a prose field out of the tag grammar', () async {
      final hit = await call('edit_json_captions', {
        'extension': '.json',
        'remove': ['A blonde girl.'],
      });
      expect(hit['written'], 1);
      expect(jsonDecode(await readCap('002'))['nl'], '');
      await tagOps.undo();

      final skipped = await call('edit_json_captions', {
        'extension': '.json',
        'remove': ['A blonde girl.'],
        'skip_fields': ['nl'],
      });
      expect(skipped['written'], 0);
      expect(jsonDecode(await readCap('002'))['nl'], 'A blonde girl.');
    });

    test('contradictory rules fail the call before anything is written',
        () async {
      final both = await call('edit_json_captions', {
        'extension': '.json',
        'remove': ['1girl'],
        'rename': {'1girl': '1boy'},
      });
      expect(both['error'], contains('pick one'));

      final fighting = await call('edit_json_captions', {
        'extension': '.json',
        'remove': ['solo'],
        'add': {
          'tags': ['solo'],
        },
      });
      expect(fighting['error'], contains('fight over it'));

      final nothing = await call('edit_json_captions', {'extension': '.json'});
      expect(nothing['error'], contains('nothing to do'));

      final tagList = await call('edit_json_captions', {
        'extension': '.txt',
        'remove': ['1girl'],
      });
      expect(tagList['error'], contains('remove_tag_everywhere'));

      expect(jsonDecode(await readCap('001'))['tags'], [
        '1girl',
        'smile',
        'long hair',
      ]);
    });
  });

  group('JSON guards on the tag tools', () {
    test('the tag sweeps name the tool that can do the job', () async {
      final removed = await call('remove_tag_everywhere', {'tag': '1girl'});
      expect(removed['error'], contains('edit_json_captions'));
      final replaced = await call('replace_tag_everywhere', {
        'tag': '1girl',
        'replacement': '1boy',
      });
      expect(replaced['error'], contains('edit_json_captions'));
      final added = await call('add_tags_everywhere', {
        'tags': ['solo'],
      });
      expect(added['error'], contains('edit_json_captions'));
      final sorted = await call('sort_captions_everywhere', {
        'priority': ['1girl'],
      });
      expect(sorted['error'], contains('restructure_json_captions'));
      // Every one of them refused before writing: the documents are intact.
      expect(jsonDecode(await readCap('001'))['tags'], [
        '1girl',
        'smile',
        'long hair',
      ]);
    });

    test('reorder_caption refuses a JSON active type', () async {
      final out = await call('reorder_caption', {
        'path': '001.png',
        'order': ['1girl', 'smile'],
      });
      expect(out['error'], contains('restructure_json_captions'));
      // The document is intact — this is the write that used to flatten it.
      expect(jsonDecode(await readCap('001')), isA<Map>());
    });

    test('write_caption refuses text that is not a JSON document', () async {
      final out = await call('write_caption', {
        'path': '001.png',
        'caption': '1girl, smile',
      });
      expect(out['error'], contains('does not parse'));
      expect(jsonDecode(await readCap('001')), isA<Map>());
    });

    test('write_caption compares tags with the JSON grammar', () async {
      final out = await call('write_caption', {
        'path': '001.png',
        'caption': jsonEncode({
          'tags': ['1girl', 'smile'],
        }),
        'expect_same_tags': true,
      });
      expect(out['error'], contains('would change the tag set'));
      expect(out['error'], contains('hatsune miku'));
    });
  });

  group('write_caption_file expect_same_tags', () {
    test('accepts a pure reshape of the same document', () async {
      final out = await call('write_caption_file', {
        'path': '001.png',
        'extension': '.json',
        'text': jsonEncode({
          'nl': 'A girl smiling at the camera.',
          'all': [
            'long hair',
            'smile',
            '1girl',
            'best quality',
            'masterpiece',
            'hatsune miku',
          ],
        }),
        'expect_same_tags': true,
      });
      expect(out['written'], isTrue);
      final doc = jsonDecode(await readCap('001')) as Map<String, dynamic>;
      expect(doc.keys.toList(), ['nl', 'all']);
    });

    test('rejects a reshape that drops a tag', () async {
      final out = await call('write_caption_file', {
        'path': '001.png',
        'extension': '.json',
        'text': jsonEncode({
          'all': ['1girl', 'smile'],
        }),
        'expect_same_tags': true,
      });
      expect(out['error'], contains('lost:'));
      expect(out['error'], contains('hatsune miku'));
      // Nothing hit the disk.
      final doc = jsonDecode(await readCap('001')) as Map<String, dynamic>;
      expect(doc.keys.toList(), ['chara', 'quality', 'tags', 'nl']);
    });

    test('refuses to be combined with expect_tags_from', () async {
      final out = await call('write_caption_file', {
        'path': '001.png',
        'extension': '.json',
        'text': '{}',
        'expect_same_tags': true,
        'expect_tags_from': '.txt',
      });
      expect(out['error'], contains('set only one'));
    });
  });
}
