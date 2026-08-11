import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:dataset_training_tool/services/agent/agent_tools.dart';
import 'package:dataset_training_tool/services/agent/caption_edit_tools.dart';
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
      ...buildCaptionEditTools(deps, tagOps),
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
    test('edit_captions removes a tag across the dataset, undoably', () async {
      final out = await call('edit_captions', {
        'remove': ['watermark'],
      });
      expect(out['written'], 2);
      expect(out['removed_tags'], {'watermark': 2});
      expect(await readCap('001'), 'trigger, 1girl, smile');
      expect(tagOps.undoLabel, startsWith('AI:'));

      await tagOps.undo();
      expect(await readCap('001'), 'trigger, 1girl, smile, watermark');
      expect(dataset.tagsOf(img('001')), contains('watermark'));
    });

    test(
      'edit_captions holds TagOps.busy for the whole sweep, not just on '
      'entry',
      () async {
        // edit_captions writes files itself instead of going through
        // TagOps.rewriteOne/_rewriteAll, so nothing else marks TagOps busy
        // for it. Without the fix, TagOps.busy stayed false for the whole
        // call, so canUndo/canRedo (what gates the UI's undo/redo buttons)
        // stayed true and a concurrent undo could race a mid-sweep write.
        // Seed undo history first — an empty stack would make canUndo false
        // regardless of busy, which would not exercise the fix.
        await tagOps.rewriteOne(img('003'), 'seed', label: 'seed');
        expect(tagOps.canUndo, isTrue);

        final future = registry.dispatch(
          'edit_captions',
          jsonEncode({
            'remove': ['watermark'],
          }),
        );
        expect(tagOps.busy, isTrue);
        expect(tagOps.canUndo, isFalse);
        await future;
        expect(tagOps.busy, isFalse);
        expect(tagOps.canUndo, isTrue);
      },
    );

    test('edit_captions renames in place, folding case', () async {
      final out = await call('edit_captions', {
        'rename': {'1GIRL': '1woman'},
      });
      expect(out['written'], 2);
      // Keyed by the spelling on disk, not the one the rule was written with.
      expect(out['renamed_tags'], {'1girl': 2});
      expect(await readCap('002'), 'trigger, 1woman, watermark');
    });

    test('edit_captions rename onto an existing tag merges', () async {
      await call('edit_captions', {
        'rename': {'smile': 'watermark'},
      });
      // 001 had both; the renamed one merges into the tag already there
      // rather than being written twice.
      expect(await readCap('001'), 'trigger, 1girl, watermark');
    });

    test('edit_captions respects filters and creates missing captions',
        () async {
      final out = await call('edit_captions', {
        'add': ['masterpiece'],
        'untagged_only': true,
      });
      expect(out['written'], 1);
      expect(out['added_tags'], {'masterpiece': 1});
      expect(await readCap('003'), 'masterpiece');
      expect(await readCap('001'), 'trigger, 1girl, smile, watermark');
    });

    test('edit_captions places added tags by index or anchor', () async {
      await call('edit_captions', {
        'add': ['masterpiece'],
        'add_index': 0,
        'name_query': '001',
      });
      expect(
        await readCap('001'),
        'masterpiece, trigger, 1girl, smile, watermark',
      );

      await call('edit_captions', {
        'add': ['best quality'],
        'add_anchor': 'trigger',
        'add_after': false,
      });
      expect(await readCap('002'), 'best quality, trigger, 1girl, watermark');
      // 003 has no caption and so no anchor: nothing was added to it.
      expect(File(cap('003')).existsSync(), isFalse);
    });

    test('edit_captions applies all three rules in one undoable pass',
        () async {
      final out = await call('edit_captions', {
        'remove': ['watermark'],
        'rename': {'1girl': '1woman'},
        'add': ['masterpiece'],
      });
      expect(out['written'], 3);
      expect(await readCap('001'), 'trigger, 1woman, smile, masterpiece');
      expect(await readCap('003'), 'masterpiece');

      await tagOps.undo();
      expect(await readCap('001'), 'trigger, 1girl, smile, watermark');
      expect(await readCap('003'), '');
    });

    test('edit_captions rejects contradictory rules before writing', () async {
      final both = await call('edit_captions', {
        'remove': ['1girl'],
        'rename': {'1girl': '1woman'},
      });
      expect(both['error'], contains('pick one'));

      final fighting = await call('edit_captions', {
        'add': ['smile'],
        'remove': ['smile'],
      });
      expect(fighting['error'], contains('fight over it'));

      final nothing = await call('edit_captions');
      expect(nothing['error'], contains('nothing to do'));

      final placed = await call('edit_captions', {
        'add': ['x'],
        'add_index': 0,
        'add_anchor': 'trigger',
      });
      expect(placed['error'], contains('not both'));

      expect(await readCap('001'), 'trigger, 1girl, smile, watermark');
      expect(tagOps.canUndo, isFalse);
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

    test('edit_captions reports the files it could not write', () async {
      await blockCaption('003');
      final out = await call('edit_captions', {
        'add': ['masterpiece'],
      });
      expect(out['written'], 2);
      // The skipped file is named rather than silently dropped.
      expect(out['failed_images'], 1);
      expect((out['failures'] as List).single['path'], '003.png');
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
        'edit_captions',
        jsonEncode({
          'add': ['masterpiece'],
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

    test('sort_captions_everywhere sorts a batch in one operation', () async {
      final out = await call('sort_captions_everywhere', {
        'priority': ['smile', '1girl'],
        'keep_first': 1,
      });
      // 001 reordered; 002 has no "smile" so it was already in this order.
      expect(out['written'], 1);
      expect(out['scanned_files'], 3);
      expect(await readCap('001'), 'trigger, smile, 1girl, watermark');
      expect(await readCap('002'), 'trigger, 1girl, watermark');
      // 003 has no caption and must not gain one.
      expect(File(cap('003')).existsSync(), isFalse);

      // One undo puts the whole batch back.
      await tagOps.undo();
      expect(await readCap('001'), 'trigger, 1girl, smile, watermark');
    });

    test('every batch write reports the same shape', () async {
      await blockCaption('003');
      // Two tools, two code paths (TagOps' batch rewrite and the standalone
      // sweep), one vocabulary. The retired keys were changed_files /
      // failed_files / caption_file — a second name for each of these facts,
      // which a model has to learn twice and can read as a different outcome.
      final sorted = await call('sort_captions_everywhere', {
        'priority': ['smile', '1girl'],
        'keep_first': 1,
      });
      expect(sorted.keys, containsAll(['written', 'scope']));
      expect(sorted.keys, isNot(contains('changed_files')));

      final edited = await call('edit_captions', {
        'add': ['masterpiece'],
      });
      expect(edited.keys, containsAll(['written', 'scope', 'failed_images']));
      expect(edited.keys, isNot(contains('failed_files')));
      // A failure names a path, never a bare "caption_file" basename.
      final failure = (edited['failures'] as List).single as Map;
      expect(failure.keys, containsAll(['path', 'error']));
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

    test(
      'sort_captions_everywhere folds spelling but keeps the file\'s',
      () async {
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
      },
    );

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
      expect(out['written'], 150);
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
      await call('edit_captions', {
        'remove': ['watermark'],
      });
      final out = await call('undo_last_operation');
      expect(out['undone'], startsWith('AI:'));
      expect(await readCap('001'), 'trigger, 1girl, watermark');
    });
  });
}
