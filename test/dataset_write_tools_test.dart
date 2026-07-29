import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:dataset_training_tool/services/agent/agent_tools.dart';
import 'package:dataset_training_tool/services/agent/dataset_tools.dart';
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

void main() {
  late Directory tempDir;
  late DatasetState dataset;
  late TagOps tagOps;
  late ToolRegistry registry;

  String img(String name) => p.join(tempDir.path, '$name.png');
  String cap(String name) => p.join(tempDir.path, '$name.txt');
  Future<String> readCap(String name) => File(cap(name)).readAsString();

  Future<Map<String, dynamic>> call(
    String tool, [
    Map<String, dynamic> args = const {},
  ]) async {
    final result = await registry.dispatch(tool, jsonEncode(args));
    return jsonDecode(result.text) as Map<String, dynamic>;
  }

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('write_tools_test_');
    for (final name in ['001', '002', '003']) {
      await File(img(name)).writeAsBytes(_pngBytes);
    }
    await File(cap('001')).writeAsString('trigger, 1girl, smile, watermark');
    await File(cap('002')).writeAsString('trigger, 1girl, watermark');
    // 003 stays uncaptioned.

    dataset = DatasetState();
    await dataset.scan(
      directoryPath: tempDir.path,
      recursive: false,
      captionExtension: '.txt',
    );
    tagOps = TagOps(dataset: dataset);
    final deps = DatasetToolsDeps(
      dataset: dataset,
      rootDir: () => tempDir.path,
      libraryTags: () => const [],
      tagGroups: () => const [],
    );
    registry = ToolRegistry([
      ...buildReadOnlyTools(deps),
      ...buildWriteTools(deps, tagOps),
    ]);
  });

  tearDown(() async {
    tagOps.dispose();
    dataset.dispose();
    await tempDir.delete(recursive: true);
  });

  group('TagOps.rewriteOne', () {
    test('writes, indexes and undoes byte-for-byte', () async {
      final ok = await tagOps.rewriteOne(
        img('001'),
        'trigger, smile, 1girl',
        label: 'AI: rewrite 001.png',
      );
      expect(ok, isTrue);
      expect(await readCap('001'), 'trigger, smile, 1girl');
      // The in-memory index followed the write.
      expect(dataset.tagsOf(img('001')), ['trigger', 'smile', '1girl']);

      await tagOps.undo();
      expect(await readCap('001'), 'trigger, 1girl, smile, watermark');
      expect(dataset.tagsOf(img('001')), [
        'trigger',
        '1girl',
        'smile',
        'watermark',
      ]);
    });

    test('identical content is a no-op without history', () async {
      final ok = await tagOps.rewriteOne(
        img('001'),
        'trigger, 1girl, smile, watermark',
        label: 'AI: rewrite',
      );
      expect(ok, isFalse);
      expect(tagOps.canUndo, isFalse);
    });
  });

  group('write tools', () {
    test('remove_tag_everywhere sweeps the dataset and is undoable', () async {
      final out = await call('remove_tag_everywhere', {'tag': 'watermark'});
      expect(out['changed_files'], 2);
      expect(await readCap('001'), 'trigger, 1girl, smile');
      expect(tagOps.undoLabel, startsWith('AI:'));
    });

    test('replace_tag_everywhere de-duplicates in place', () async {
      final out = await call('replace_tag_everywhere', {
        'tag': '1girl',
        'replacement': '1woman',
      });
      expect(out['changed_files'], 2);
      expect(await readCap('002'), 'trigger, 1woman, watermark');
    });

    test('add_tags_everywhere respects filters and creates captions', () async {
      final out = await call('add_tags_everywhere', {
        'tags': ['masterpiece'],
        'untagged_only': true,
      });
      expect(out['changed_files'], 1);
      expect(await readCap('003'), 'masterpiece');
      expect(await readCap('001'), 'trigger, 1girl, smile, watermark');
    });

    test('write_caption rewrites one image via relative path', () async {
      final out = await call('write_caption', {
        'path': '001.png',
        'caption': 'trigger, smile, 1girl, watermark',
      });
      expect(out['written'], isTrue);
      expect(out['added'], isEmpty);
      expect(out['removed'], isEmpty);
      expect(await readCap('001'), 'trigger, smile, 1girl, watermark');
    });

    test('write_caption reports the tags it added and removed', () async {
      final out = await call('write_caption', {
        'path': '001.png',
        'caption': 'trigger, 1girl, smile, masterpiece',
      });
      expect(out['added'], ['masterpiece']);
      expect(out['removed'], ['watermark']);
    });

    test('write_caption honours expect_same_tags', () async {
      final result = await registry.dispatch(
        'write_caption',
        jsonEncode({
          'path': '001.png',
          // "smile" silently dropped, "masterpiece" invented — exactly the
          // corruption a from-memory rewrite produces.
          'caption': 'trigger, 1girl, masterpiece, watermark',
          'expect_same_tags': true,
        }),
      );
      expect(result.isError, isTrue);
      expect(result.text, contains('masterpiece'));
      expect(result.text, contains('smile'));
      // The file is untouched.
      expect(await readCap('001'), 'trigger, 1girl, smile, watermark');
      expect(tagOps.canUndo, isFalse);
    });

    test('write_caption rejects paths outside the dataset', () async {
      final result = await registry.dispatch(
        'write_caption',
        jsonEncode({'path': '../evil.png', 'caption': 'x'}),
      );
      expect(result.isError, isTrue);
    });

    test('reorder_caption permutes and is undoable', () async {
      final out = await call('reorder_caption', {
        'path': '001.png',
        'order': ['trigger', 'smile', 'watermark', '1girl'],
      });
      expect(out['written'], isTrue);
      expect(await readCap('001'), 'trigger, smile, watermark, 1girl');

      await tagOps.undo();
      expect(await readCap('001'), 'trigger, 1girl, smile, watermark');
    });

    test('reorder_caption refuses an order that drops a tag', () async {
      final result = await registry.dispatch(
        'reorder_caption',
        jsonEncode({
          'path': '001.png',
          'order': ['trigger', 'smile', '1girl'],
        }),
      );
      expect(result.isError, isTrue);
      expect(result.text, contains('left out'));
      expect(result.text, contains('watermark'));
      expect(await readCap('001'), 'trigger, 1girl, smile, watermark');
      expect(tagOps.canUndo, isFalse);
    });

    test('reorder_caption refuses an order that invents a tag', () async {
      final result = await registry.dispatch(
        'reorder_caption',
        jsonEncode({
          'path': '001.png',
          'order': ['trigger', '1girl', 'smile', 'watermark', 'masterpiece'],
        }),
      );
      expect(result.isError, isTrue);
      expect(result.text, contains('not on this image'));
      expect(result.text, contains('masterpiece'));
      expect(await readCap('001'), 'trigger, 1girl, smile, watermark');
    });

    test('reorder_caption error echoes the image\'s current tags', () async {
      final result = await registry.dispatch(
        'reorder_caption',
        jsonEncode({
          'path': '002.png',
          'order': ['1girl'],
        }),
      );
      // The model needs the ground truth to retry from, not just a refusal.
      expect(result.text, contains('trigger, 1girl, watermark'));
    });

    test('reorder_caption keeps the file\'s own tag spelling', () async {
      await File(cap('001')).writeAsString('trigger, long_hair, smile');
      await dataset.scan(
        directoryPath: tempDir.path,
        recursive: false,
        captionExtension: '.txt',
      );
      // The model types the spaced style; the file keeps the underscore.
      final out = await call('reorder_caption', {
        'path': '001.png',
        'order': ['Trigger', 'smile', 'long hair'],
      });
      expect(out['written'], isTrue);
      expect(await readCap('001'), 'trigger, smile, long_hair');
    });

    test('reorder_caption rejects an uncaptioned image', () async {
      final result = await registry.dispatch(
        'reorder_caption',
        jsonEncode({
          'path': '003.png',
          'order': ['whatever'],
        }),
      );
      expect(result.isError, isTrue);
      expect(File(cap('003')).existsSync(), isFalse);
    });

    test('sort_captions_everywhere sorts a batch in one operation', () async {
      final out = await call('sort_captions_everywhere', {
        'priority': ['smile', '1girl'],
        'keep_first': 1,
      });
      // 001 reordered; 002 has no "smile" so it was already in this order.
      expect(out['changed_files'], 1);
      expect(out['scanned_files'], 3);
      expect(await readCap('001'), 'trigger, smile, 1girl, watermark');
      expect(await readCap('002'), 'trigger, 1girl, watermark');
      // 003 has no caption and must not gain one.
      expect(File(cap('003')).existsSync(), isFalse);

      // One undo puts the whole batch back.
      await tagOps.undo();
      expect(await readCap('001'), 'trigger, 1girl, smile, watermark');
    });

    test('sort_captions_everywhere never changes the tag set', () async {
      // Two spellings of one tag: both rank the same, and both survive.
      await File(cap('001')).writeAsString('b, long hair, c, long_hair');
      await dataset.scan(
        directoryPath: tempDir.path,
        recursive: false,
        captionExtension: '.txt',
      );
      final before = dataset.tagsOf(img('001')).toSet();
      await call('sort_captions_everywhere', {
        'priority': ['long_hair', 'zzz'],
      });
      expect(await readCap('001'), 'long hair, long_hair, b, c');
      expect(dataset.tagsOf(img('001')).toSet(), before);
    });

    test('sort_captions_everywhere keeps unlisted tags in order', () async {
      await File(cap('001')).writeAsString('z, y, smile, x, 1girl');
      await dataset.scan(
        directoryPath: tempDir.path,
        recursive: false,
        captionExtension: '.txt',
      );
      await call('sort_captions_everywhere', {
        'priority': ['1girl', 'smile'],
      });
      expect(await readCap('001'), '1girl, smile, z, y, x');
    });

    test('sort_captions_everywhere can front the unlisted tags', () async {
      await File(cap('001')).writeAsString('1girl, z, smile, y');
      await dataset.scan(
        directoryPath: tempDir.path,
        recursive: false,
        captionExtension: '.txt',
      );
      await call('sort_captions_everywhere', {
        'priority': ['smile', '1girl'],
        'unlisted': 'start',
      });
      expect(await readCap('001'), 'z, y, smile, 1girl');
    });

    test('sort_captions_everywhere folds spelling but keeps the file\'s', () async {
      await File(cap('001')).writeAsString('trigger, watermark, long_hair');
      await dataset.scan(
        directoryPath: tempDir.path,
        recursive: false,
        captionExtension: '.txt',
      );
      await call('sort_captions_everywhere', {
        'priority': ['Long Hair'],
        'keep_first': 1,
      });
      expect(await readCap('001'), 'trigger, long_hair, watermark');
    });

    test('sort_captions_everywhere honours the list_images filters', () async {
      await call('sort_captions_everywhere', {
        'priority': ['watermark'],
        'include_tags': ['smile'],
        'keep_first': 1,
      });
      // Only 001 carries "smile"; 002 is left alone.
      expect(await readCap('001'), 'trigger, watermark, 1girl, smile');
      expect(await readCap('002'), 'trigger, 1girl, watermark');
    });

    test('sort_captions_everywhere handles a batch-sized dataset', () async {
      // The case this tool exists for: a couple of hundred images sorted by
      // one call, landing on the undo stack as a single operation.
      for (var i = 0; i < 150; i++) {
        final name = 'batch_$i';
        await File(img(name)).writeAsBytes(_pngBytes);
        await File(cap(name)).writeAsString('trigger, watermark, 1girl');
      }
      await dataset.scan(
        directoryPath: tempDir.path,
        recursive: false,
        captionExtension: '.txt',
      );
      final out = await call('sort_captions_everywhere', {
        'priority': ['1girl', 'watermark'],
        'keep_first': 1,
        'name_query': 'batch_',
      });
      expect(out['changed_files'], 150);
      expect(await readCap('batch_0'), 'trigger, 1girl, watermark');
      expect(await readCap('batch_149'), 'trigger, 1girl, watermark');

      await tagOps.undo();
      expect(await readCap('batch_0'), 'trigger, watermark, 1girl');
      expect(await readCap('batch_149'), 'trigger, watermark, 1girl');
    });

    test('sort_captions_everywhere rejects a bad unlisted value', () async {
      final result = await registry.dispatch(
        'sort_captions_everywhere',
        jsonEncode({
          'priority': ['1girl'],
          'unlisted': 'middle',
        }),
      );
      expect(result.isError, isTrue);
      expect(await readCap('001'), 'trigger, 1girl, smile, watermark');
    });

    test('undo_last_operation only reverts AI operations', () async {
      // A user operation on top of the stack must be protected.
      await tagOps.deleteEverywhere('smile', label: 'delete "smile"');
      final refused = await registry.dispatch('undo_last_operation', '{}');
      expect(refused.isError, isTrue);
      expect(await readCap('001'), 'trigger, 1girl, watermark');

      // An AI operation undoes fine.
      await call('remove_tag_everywhere', {'tag': 'watermark'});
      final out = await call('undo_last_operation');
      expect(out['undone'], startsWith('AI:'));
      expect(await readCap('001'), 'trigger, 1girl, watermark');
    });
  });
}
