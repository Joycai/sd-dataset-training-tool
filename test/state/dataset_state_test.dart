import 'dart:io';

import 'package:dataset_training_tool/state/dataset_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

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
}
