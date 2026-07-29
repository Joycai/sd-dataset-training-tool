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

  // A directory sitting where [name]'s caption file belongs: File.exists is
  // false for it and every write to it throws, which is how these tests
  // simulate an unwritable caption without fiddling with permissions.
  Future<void> blockCaption(String name) => Directory(cap(name)).create();

  group('TagOps.rewriteOne', () {
    test('writes, indexes and undoes byte-for-byte', () async {
      final result = await tagOps.rewriteOne(
        img('001'),
        'trigger, smile, 1girl',
        label: 'AI: rewrite 001.png',
      );
      expect(result.written, isTrue);
      expect(result.failed, isFalse);
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
      final result = await tagOps.rewriteOne(
        img('001'),
        'trigger, 1girl, smile, watermark',
        label: 'AI: rewrite',
      );
      expect(result.unchanged, isTrue);
      expect(result.written, isFalse);
      expect(result.failed, isFalse);
      expect(tagOps.canUndo, isFalse);
    });

    test('a failed write is not reported as unchanged', () async {
      await blockCaption('003');
      final result = await tagOps.rewriteOne(
        img('003'),
        'masterpiece',
        label: 'AI: rewrite 003.png',
      );
      expect(result.failed, isTrue);
      expect(result.written, isFalse);
      // The distinction that matters: "no change needed" would let a caller
      // move on from a write that never landed.
      expect(result.unchanged, isFalse);
      expect(result.error, contains('cannot write'));
      expect(tagOps.canUndo, isFalse);
      expect(dataset.hasCaption(img('003')), isFalse);
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

    test('write_caption errors when the caption file is unwritable', () async {
      await blockCaption('003');
      final result = await registry.dispatch(
        'write_caption',
        jsonEncode({'path': '003.png', 'caption': 'masterpiece'}),
      );
      // Not {'written': false, 'unchanged': true} — that reads as "this
      // image needed no change" and the model walks away from a lost write.
      expect(result.isError, isTrue);
      expect(result.text, contains('nothing was written'));
      expect(result.text, contains('003'));
      expect(tagOps.canUndo, isFalse);
    });

    test(
      'reorder_caption errors when the caption file is unwritable',
      () async {
        // 001 is captioned and indexed; replacing the file with a directory
        // leaves the reorder valid but the write impossible.
        await File(cap('001')).delete();
        await Directory(cap('001')).create();
        final result = await registry.dispatch(
          'reorder_caption',
          jsonEncode({
            'path': '001.png',
            'order': ['trigger', 'smile', 'watermark', '1girl'],
          }),
        );
        expect(result.isError, isTrue);
        expect(result.text, contains('nothing was written'));
        expect(tagOps.canUndo, isFalse);
      },
    );

    test('add_tags_everywhere reports the files it could not write', () async {
      await blockCaption('003');
      final out = await call('add_tags_everywhere', {
        'tags': ['masterpiece'],
      });
      expect(out['changed_files'], 2);
      // The skipped file is named rather than silently dropped.
      expect(out['failed_files'], 1);
      expect((out['failures'] as List).single['caption_file'], '003.txt');
      expect(await readCap('001'), endsWith('masterpiece'));
    });

    test('a sweep that writes nothing and fails is an error', () async {
      await File(cap('001')).delete();
      await Directory(cap('001')).create();
      await File(cap('002')).delete();
      await Directory(cap('002')).create();
      await blockCaption('003');
      await dataset.scan(
        directoryPath: tempDir.path,
        recursive: false,
        captionExtension: '.txt',
      );
      final result = await registry.dispatch(
        'add_tags_everywhere',
        jsonEncode({
          'tags': ['masterpiece'],
        }),
      );
      expect(result.isError, isTrue);
      expect(result.text, contains('nothing was written'));
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
