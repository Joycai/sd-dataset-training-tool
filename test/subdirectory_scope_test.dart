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

/// Layout used by every test here:
///
///   root/root1.png        "shared, rooty"
///   root/10_a/a1.png      "shared, alpha"
///   root/10_a/a2.png      "shared, alpha"
///   root/20_b/b1.png      "shared, beta"
void main() {
  late Directory tempDir;
  late DatasetState dataset;

  String img(String relative) => p.join(tempDir.path, relative);
  String cap(String relative) =>
      p.join(tempDir.path, '${p.withoutExtension(relative)}.txt');
  Future<String> readCap(String relative) => File(cap(relative)).readAsString();

  Future<void> write(String relative, String caption) async {
    final file = File(img(relative));
    await file.parent.create(recursive: true);
    await file.writeAsBytes(_pngBytes);
    await File(cap(relative)).writeAsString(caption);
  }

  Future<void> rescan() => dataset.scan(
    directoryPath: tempDir.path,
    recursive: true,
    captionExtension: '.txt',
  );

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('subdir_scope_test_');
    await write('root1.png', 'shared, rooty');
    await write(p.join('10_a', 'a1.png'), 'shared, alpha');
    await write(p.join('10_a', 'a2.png'), 'shared, alpha');
    await write(p.join('20_b', 'b1.png'), 'shared, beta');

    dataset = DatasetState();
    await rescan();
  });

  tearDown(() async {
    dataset.dispose();
    await tempDir.delete(recursive: true);
  });

  group('DatasetState scope', () {
    test('scan lists directories holding images, root first', () {
      expect(dataset.hasSubdirectories, isTrue);
      expect(dataset.subdirectories.map((d) => '${d.path}:${d.count}'), [
        ':1',
        '10_a:2',
        '20_b:1',
      ]);
      expect(dataset.subdirectories.first.isRoot, isTrue);
    });

    test('a flat dataset offers nothing to switch between', () async {
      await dataset.scan(
        directoryPath: p.join(tempDir.path, '10_a'),
        recursive: true,
        captionExtension: '.txt',
      );
      expect(dataset.hasSubdirectories, isFalse);
      expect(dataset.subdirectories.single.path, '');
    });

    test('picking a subdirectory narrows counts, files and the tag index', () {
      dataset.setSubdirectory('10_a');

      expect(dataset.activeSubdirectory, '10_a');
      expect(dataset.totalCount, 2);
      expect(dataset.allFiles.length, 4);
      expect(dataset.scopedFiles.map((f) => p.basename(f.path)), [
        'a1.png',
        'a2.png',
      ]);
      expect(dataset.visibleFiles.map((f) => p.basename(f.path)), [
        'a1.png',
        'a2.png',
      ]);
      expect(dataset.datasetTags.map((t) => '${t.tag}:${t.count}'), [
        'alpha:2',
        'shared:2',
      ]);
    });

    test('the root scope is the root directory only, not everything', () {
      dataset.setSubdirectory('');
      expect(dataset.totalCount, 1);
      expect(dataset.visibleFiles.single.path, img('root1.png'));
    });

    test('null and unknown directories both mean the whole dataset', () {
      dataset.setSubdirectory('10_a');
      dataset.setSubdirectory('30_nope');
      expect(dataset.activeSubdirectory, isNull);
      expect(dataset.totalCount, 4);
    });

    test('a selection outside the new scope is dropped', () {
      dataset.select(img('root1.png'));
      dataset.setSubdirectory('10_a');
      expect(dataset.selectedFile, isNull);

      dataset.select(img(p.join('10_a', 'a1.png')));
      dataset.setSubdirectory('20_b');
      expect(dataset.selectedFile, isNull);
    });

    test('a selection inside the new scope survives', () {
      dataset.select(img(p.join('10_a', 'a1.png')));
      dataset.setSubdirectory('10_a');
      expect(dataset.selectedFile?.path, img(p.join('10_a', 'a1.png')));
    });

    test('a refresh keeps a scope that still exists', () async {
      dataset.setSubdirectory('10_a');
      await rescan();
      expect(dataset.activeSubdirectory, '10_a');
      expect(dataset.totalCount, 2);
    });

    test('a refresh drops a scope whose directory is gone', () async {
      dataset.setSubdirectory('20_b');
      await Directory(p.join(tempDir.path, '20_b')).delete(recursive: true);
      await rescan();
      expect(dataset.activeSubdirectory, isNull);
      expect(dataset.totalCount, 3);
    });
  });

  group('TagOps sweeps', () {
    late TagOps tagOps;

    setUp(() => tagOps = TagOps(dataset: dataset));
    tearDown(() => tagOps.dispose());

    test('delete only reaches the active subdirectory', () async {
      dataset.setSubdirectory('10_a');
      final result = await tagOps.deleteEverywhere('shared', label: 'del');

      expect(result.changed, 2);
      expect(await readCap(p.join('10_a', 'a1.png')), 'alpha');
      expect(await readCap(p.join('20_b', 'b1.png')), 'shared, beta');
      expect(await readCap('root1.png'), 'shared, rooty');
    });

    test('add only reaches the active subdirectory', () async {
      dataset.setSubdirectory('20_b');
      final result = await tagOps.addEverywhere('extra', label: 'add');

      expect(result.changed, 1);
      expect(await readCap(p.join('20_b', 'b1.png')), 'shared, beta, extra');
      expect(await readCap(p.join('10_a', 'a1.png')), 'shared, alpha');
    });

    test(
      'undo of a scoped sweep still works after leaving the scope',
      () async {
        dataset.setSubdirectory('10_a');
        await tagOps.deleteEverywhere('shared', label: 'del');
        dataset.setSubdirectory(null);
        await tagOps.undo();

        expect(await readCap(p.join('10_a', 'a1.png')), 'shared, alpha');
      },
    );

    test('no scope sweeps everything, as before', () async {
      final result = await tagOps.deleteEverywhere('shared', label: 'del');
      expect(result.changed, 4);
    });
  });

  group('agent tools', () {
    late TagOps tagOps;
    late ToolRegistry registry;

    Future<AgentToolResult> raw(
      String tool, [
      Map<String, dynamic> args = const {},
    ]) => registry.dispatch(tool, jsonEncode(args));

    Future<Map<String, dynamic>> call(
      String tool, [
      Map<String, dynamic> args = const {},
    ]) async =>
        jsonDecode((await raw(tool, args)).text) as Map<String, dynamic>;

    setUp(() {
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

    tearDown(() => tagOps.dispose());

    test(
      'the overview names the scope and the available directories',
      () async {
        expect(
          await call('get_dataset_overview'),
          containsPair('scope', 'whole dataset'),
        );

        dataset.setSubdirectory('10_a');
        final scoped = await call('get_dataset_overview');
        expect(scoped['scope'], 'subdirectory "10_a" only');
        expect(scoped['total_images'], 2);
        expect(scoped['subdirectories'], hasLength(3));
      },
    );

    test('list_images and get_tag_stats stay inside the scope', () async {
      dataset.setSubdirectory('10_a');

      final listed = await call('list_images');
      expect(listed['total_matches'], 2);
      expect(listed['scope'], 'subdirectory "10_a" only');

      final stats = await call('get_tag_stats');
      expect(stats['total_unique'], 2);
    });

    test('an out-of-scope path does not resolve, and says why', () async {
      dataset.setSubdirectory('10_a');
      final read = await call('read_captions', {
        'paths': ['20_b/b1.png'],
      });
      final entry = (read['captions'] as List).single as Map<String, dynamic>;
      expect(entry['error'], contains('active scope'));
      expect(entry['error'], contains('10_a'));

      final write = await raw('write_caption', {
        'path': '20_b/b1.png',
        'caption': 'wrecked',
      });
      expect(write.isError, isTrue);
      expect(await readCap(p.join('20_b', 'b1.png')), 'shared, beta');
    });

    test('a batch write sweeps the scope and reports it', () async {
      dataset.setSubdirectory('10_a');
      final result = await call('edit_captions', {
        'remove': ['shared'],
      });

      expect(result['written'], 2);
      expect(result['scope'], 'subdirectory "10_a" only');
      expect(await readCap(p.join('20_b', 'b1.png')), 'shared, beta');
    });
  });
}
