import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:dataset_training_tool/state/dataset_state.dart';
import 'package:dataset_training_tool/state/editor_session.dart';

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

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('dataset_test_');
    for (var i = 1; i <= 3; i++) {
      await File(p.join(tempDir.path, '00$i.png')).writeAsBytes(_pngBytes);
    }
    // 001 tagged, 002 empty caption file (counts as untagged), 003 no file.
    await File(p.join(tempDir.path, '001.txt')).writeAsString('1girl, solo');
    await File(p.join(tempDir.path, '002.txt')).writeAsString('');
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  test('scan finds images and caption status', () async {
    final dataset = DatasetState();
    await dataset.scan(
      directoryPath: tempDir.path,
      recursive: false,
      captionExtension: '.txt',
    );

    expect(dataset.totalCount, 3);
    expect(dataset.taggedCount, 1);
    expect(dataset.untaggedCount, 2);
    expect(dataset.hasCaption(p.join(tempDir.path, '001.png')), isTrue);
    expect(dataset.hasCaption(p.join(tempDir.path, '002.png')), isFalse);

    dataset.setFilter(CaptionFilter.tagged);
    expect(dataset.visibleFiles.map((f) => p.basename(f.path)), ['001.png']);

    dataset.setFilter(CaptionFilter.all);
    dataset.setQuery('002');
    expect(dataset.visibleFiles.map((f) => p.basename(f.path)), ['002.png']);
  });

  test('selection navigates the visible list with arrows', () async {
    final dataset = DatasetState();
    await dataset.scan(
      directoryPath: tempDir.path,
      recursive: false,
      captionExtension: '.txt',
    );

    expect(dataset.selectByOffset(1), isNotNull);
    expect(dataset.selectedVisibleIndex, 0);
    dataset.selectByOffset(1);
    expect(dataset.selectedVisibleIndex, 1);
    dataset.selectByOffset(-1);
    expect(dataset.selectedVisibleIndex, 0);
    // Clamped at the ends.
    expect(dataset.selectByOffset(-1), isNull);
    expect(dataset.selectedVisibleIndex, 0);
  });

  test(
    'session loads caption, applies tags, saves and reports status',
    () async {
      final session = EditorSession()..autoSaveEnabled = false;
      final saved = <(String, String)>[];
      session.onSaved = (path, text) => saved.add((path, text));

      final image = File(p.join(tempDir.path, '001.png'));
      await session.load(image, '.txt');
      expect(session.tags, ['1girl', 'solo']);
      expect(session.saveState, SaveState.clean);

      session.applyTag('long hair');
      expect(session.tags, ['1girl', 'solo', 'long hair']);
      expect(session.captionController.text, '1girl, solo, long hair');
      expect(session.saveState, SaveState.dirty);

      session.toggleTag('solo');
      expect(session.tags, ['1girl', 'long hair']);

      session.reorderTag(1, 0);
      expect(session.captionController.text, 'long hair, 1girl');

      await session.save();
      expect(session.saveState, SaveState.saved);
      expect(
        await File(p.join(tempDir.path, '001.txt')).readAsString(),
        'long hair, 1girl',
      );
      expect(saved.single, (image.path, 'long hair, 1girl'));

      session.dispose();
    },
  );

  test('insertion anchor: adds land after it and it rides along', () async {
    final session = EditorSession()..autoSaveEnabled = false;
    await session.load(File(p.join(tempDir.path, '001.png')), '.txt');
    expect(session.tags, ['1girl', 'solo']);
    expect(session.anchorTag, isNull);

    // Anchor on "1girl": adds insert right after it in click order, the
    // anchor riding along onto each newest insert like a text caret.
    session.setAnchorTag('1girl');
    session.applyTag('long hair');
    expect(session.tags, ['1girl', 'long hair', 'solo']);
    expect(session.anchorTag, 'long hair');
    session.addTagsFromInput('smile, blush');
    expect(session.tags, ['1girl', 'long hair', 'smile', 'blush', 'solo']);
    expect(session.anchorTag, 'blush');

    // The anchor is a name: it follows reorders for free.
    session.reorderTag(3, 0); // 'blush' to the front
    expect(session.tags, ['blush', '1girl', 'long hair', 'smile', 'solo']);
    expect(session.anchorTag, 'blush');
    session.applyTag('dress');
    expect(session.tags,
        ['blush', 'dress', '1girl', 'long hair', 'smile', 'solo']);
    expect(session.anchorTag, 'dress');

    // Renaming the anchored tag keeps the anchor on the successor.
    session.replaceTagAt(1, 'frilled dress');
    expect(session.anchorTag, 'frilled dress');

    // Removing the anchored tag deactivates it (adds append again), but the
    // memory survives for images that still have the tag.
    session.removeTag('frilled dress');
    expect(session.anchorTag, isNull);
    session.applyTag('ribbon');
    expect(session.tags.last, 'ribbon');

    session.dispose();
  });

  test('insertion anchor is remembered by name across image switches',
      () async {
    // A and C have "shared"; B does not.
    await File(p.join(tempDir.path, '001.txt'))
        .writeAsString('shared, alpha');
    await File(p.join(tempDir.path, '002.txt')).writeAsString('beta');
    await File(p.join(tempDir.path, '003.txt'))
        .writeAsString('gamma, shared');

    final session = EditorSession()..autoSaveEnabled = false;
    await session.load(File(p.join(tempDir.path, '001.png')), '.txt');
    session.setAnchorTag('shared');
    expect(session.anchorTag, 'shared');

    // B lacks the tag: anchor lies dormant, adds append at the end.
    await session.load(File(p.join(tempDir.path, '002.png')), '.txt');
    expect(session.anchorTag, isNull);
    session.applyTag('delta');
    expect(session.tags, ['beta', 'delta']);

    // C has it again: the anchor re-activates and inserts after it.
    await session.load(File(p.join(tempDir.path, '003.png')), '.txt');
    expect(session.anchorTag, 'shared');
    session.applyTag('epsilon');
    expect(session.tags, ['gamma', 'shared', 'epsilon']);

    // Unload clears the memory.
    await session.unload();
    await session.load(File(p.join(tempDir.path, '001.png')), '.txt');
    expect(session.anchorTag, isNull);

    session.dispose();
  });

  test('moveAnchor cycles through the tags and the append state', () async {
    final session = EditorSession()..autoSaveEnabled = false;
    await session.load(File(p.join(tempDir.path, '001.png')), '.txt');
    expect(session.tags, ['1girl', 'solo']);

    // Forward: end -> first -> ... -> last -> end.
    session.moveAnchor(1);
    expect(session.anchorTag, '1girl');
    session.moveAnchor(1);
    expect(session.anchorTag, 'solo');
    session.moveAnchor(1);
    expect(session.anchorTag, isNull);

    // Backward: end -> last -> ... -> first -> end.
    session.moveAnchor(-1);
    expect(session.anchorTag, 'solo');
    session.moveAnchor(-1);
    expect(session.anchorTag, '1girl');
    session.moveAnchor(-1);
    expect(session.anchorTag, isNull);

    session.dispose();
  });

  test('saving an emptied caption marks the image untagged', () async {
    final session = EditorSession()..autoSaveEnabled = false;
    final saved = <(String, String)>[];
    session.onSaved = (path, text) => saved.add((path, text));

    final image = File(p.join(tempDir.path, '001.png'));
    await session.load(image, '.txt');
    session.captionController.text = '';
    await session.save();
    expect(saved.single.$2, isEmpty);

    session.dispose();
  });

  test('flush before switching images persists pending edits', () async {
    final session = EditorSession()..autoSaveEnabled = false;

    await session.load(File(p.join(tempDir.path, '001.png')), '.txt');
    session.addTagsFromInput('new tag, another');
    expect(session.saveState, SaveState.dirty);

    // Loading the next image flushes the previous caption to disk.
    await session.load(File(p.join(tempDir.path, '003.png')), '.txt');
    expect(
      await File(p.join(tempDir.path, '001.txt')).readAsString(),
      '1girl, solo, new tag, another',
    );
    expect(session.tags, isEmpty);

    session.dispose();
  });
}
