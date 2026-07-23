import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

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

  String img(String name) => p.join(tempDir.path, '$name.png');
  String cap(String name) => p.join(tempDir.path, '$name.txt');
  Future<String> readCap(String name) => File(cap(name)).readAsString();

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('tag_ops_test_');
    for (final name in ['001', '002', '003']) {
      await File(img(name)).writeAsBytes(_pngBytes);
    }
    await File(cap('001')).writeAsString('a, b, c');
    // Odd spacing on purpose: undo must restore it byte-for-byte.
    await File(cap('002')).writeAsString('b,  c ,d');
    // 003 has no caption file.

    dataset = DatasetState();
    await dataset.scan(
      directoryPath: tempDir.path,
      recursive: false,
      captionExtension: '.txt',
    );
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  group('DatasetState tag index', () {
    test('datasetTags counts and sorts (count desc, then alpha)', () {
      final tags = dataset.datasetTags;
      expect(tags.map((t) => '${t.tag}:${t.count}'), [
        'b:2',
        'c:2',
        'a:1',
        'd:1',
      ]);
    });

    test('tag filter narrows visibleFiles in both directions', () {
      dataset.setTagFilter('a', exclude: false);
      expect(dataset.visibleFiles.map((f) => p.basename(f.path)), ['001.png']);

      // Exclude mode: uncaptioned images count as "without the tag".
      dataset.setTagFilter('a', exclude: true);
      expect(dataset.visibleFiles.map((f) => p.basename(f.path)), [
        '002.png',
        '003.png',
      ]);

      dataset.clearTagFilter();
      expect(dataset.visibleFiles, hasLength(3));
    });

    test('updateCaptionText keeps the index in sync', () {
      dataset.updateCaptionText(img('003'), 'a, e');
      expect(dataset.hasCaption(img('003')), isTrue);
      expect(dataset.tagsOf(img('003')), ['a', 'e']);
      expect(
        dataset.datasetTags.map((t) => '${t.tag}:${t.count}'),
        contains('a:2'),
      );
    });
  });

  group('TagOps', () {
    late TagOps ops;
    late List<Set<String>> changeReports;
    var flushCalls = 0;

    setUp(() {
      changeReports = [];
      flushCalls = 0;
      ops = TagOps(
        dataset: dataset,
        beforeMutate: () async => flushCalls++,
        onCaptionsChanged: changeReports.add,
      );
    });

    test('deleteEverywhere rewrites every file with the tag', () async {
      final count = await ops.deleteEverywhere('b', label: 'delete b');
      expect(count, 2);
      expect(await readCap('001'), 'a, c');
      expect(await readCap('002'), 'c, d');
      expect(flushCalls, 1);
      expect(changeReports.single, {img('001'), img('002')});
      expect(dataset.datasetTags.map((t) => t.tag), isNot(contains('b')));
      expect(ops.canUndo, isTrue);
      expect(ops.undoLabel, 'delete b');
    });

    test('undo restores the exact on-disk text, redo re-applies', () async {
      await ops.deleteEverywhere('b', label: 'delete b');

      await ops.undo();
      expect(await readCap('001'), 'a, b, c');
      expect(await readCap('002'), 'b,  c ,d'); // odd spacing preserved
      expect(dataset.tagsOf(img('002')), ['b', 'c', 'd']);
      expect(ops.canUndo, isFalse);
      expect(ops.canRedo, isTrue);

      await ops.redo();
      expect(await readCap('001'), 'a, c');
      expect(await readCap('002'), 'c, d');
      expect(ops.canUndo, isTrue);
      expect(ops.canRedo, isFalse);
    });

    test('replaceEverywhere replaces in place and de-duplicates', () async {
      // 001 [a, b, c]: c -> [x, b]; b already present, so only x lands.
      final count = await ops.replaceEverywhere(
        'c',
        'x, b',
        label: 'replace c',
      );
      expect(count, 2);
      expect(await readCap('001'), 'a, b, x');
      expect(await readCap('002'), 'b, x, d');
    });

    test('insertBeside inserts before/after and skips existing tags', () async {
      await ops.insertBeside('c', 'q', after: true, label: 'append');
      expect(await readCap('001'), 'a, b, c, q');
      expect(await readCap('002'), 'b, c, q, d');

      await ops.insertBeside('b', 'p, a', after: false, label: 'prepend');
      // 001 already has a: only p lands, directly before b.
      expect(await readCap('001'), 'a, p, b, c, q');
      expect(await readCap('002'), 'p, a, b, c, q, d');
    });

    test('addEverywhere appends by default and creates missing captions',
        () async {
      final count = await ops.addEverywhere('x', label: 'add x');
      expect(count, 3);
      expect(await readCap('001'), 'a, b, c, x');
      expect(await readCap('002'), 'b, c, d, x');
      // 003 had no caption file: it gets created.
      expect(await readCap('003'), 'x');
      expect(dataset.hasCaption(img('003')), isTrue);

      // Undo restores 003 to an empty caption, not a tagged one.
      await ops.undo();
      expect(await readCap('003'), '');
      expect(dataset.hasCaption(img('003')), isFalse);
      expect(await readCap('002'), 'b,  c ,d'); // odd spacing preserved
    });

    test('addEverywhere inserts at the index, clamped, skipping duplicates',
        () async {
      // 001 [a, b, c]: a already present, only x lands at the head.
      final count = await ops.addEverywhere('x, a', index: 0, label: 'add');
      expect(count, 3);
      expect(await readCap('001'), 'x, a, b, c');
      expect(await readCap('002'), 'x, a, b, c, d');
      expect(await readCap('003'), 'x, a');

      // An index beyond the end clamps to append.
      await ops.addEverywhere('z', index: 99, label: 'add z');
      expect(await readCap('001'), 'x, a, b, c, z');
    });

    test('addEverywhere with a file list only touches those files', () async {
      final target = dataset.allFiles
          .where((f) => p.basename(f.path) == '002.png')
          .toList();
      final count = await ops.addEverywhere(
        'x',
        files: target,
        label: 'add x',
      );
      expect(count, 1);
      expect(await readCap('001'), 'a, b, c');
      expect(await readCap('002'), 'b, c, d, x');
      expect(File(cap('003')).existsSync(), isFalse);
    });

    test('addEverywhere with empty or all-duplicate input is a no-op',
        () async {
      expect(await ops.addEverywhere('  ', label: 'noop'), 0);
      // Every file already has its tags — b for 001/002 — but 003 gains it.
      expect(await ops.addEverywhere('b', label: 'add b'), 1);
      expect(await readCap('001'), 'a, b, c');
      expect(await readCap('003'), 'b');
    });

    test('a new operation clears the redo stack', () async {
      await ops.deleteEverywhere('d', label: 'delete d');
      await ops.undo();
      expect(ops.canRedo, isTrue);

      await ops.deleteEverywhere('a', label: 'delete a');
      expect(ops.canRedo, isFalse);
      expect(ops.undoLabel, 'delete a');
    });

    test('semantic no-op touches nothing and records no history', () async {
      // Replacing a tag with itself changes no tag list; 002's odd spacing
      // alone must not count as a change.
      final count = await ops.replaceEverywhere('b', 'b', label: 'noop');
      expect(count, 0);
      expect(await readCap('002'), 'b,  c ,d');
      expect(ops.canUndo, isFalse);
      expect(changeReports, isEmpty);
    });

    test('clearHistory drops both stacks', () async {
      await ops.deleteEverywhere('a', label: 'delete a');
      await ops.undo();
      ops.clearHistory();
      expect(ops.canUndo, isFalse);
      expect(ops.canRedo, isFalse);
    });
  });
}
