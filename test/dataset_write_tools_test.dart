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

    test('write_caption reorders one image via relative path', () async {
      final out = await call('write_caption', {
        'path': '001.png',
        'caption': 'trigger, smile, 1girl, watermark',
      });
      expect(out['written'], isTrue);
      expect(await readCap('001'), 'trigger, smile, 1girl, watermark');
    });

    test('write_caption rejects paths outside the dataset', () async {
      final result = await registry.dispatch(
        'write_caption',
        jsonEncode({'path': '../evil.png', 'caption': 'x'}),
      );
      expect(result.isError, isTrue);
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
