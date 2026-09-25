import 'dart:io';

import 'package:dataset_training_tool/services/dataset_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

const _invalidUtf8 = [0xFF, 0xFE, 0x00];

void main() {
  const store = DatasetStore();
  late Directory tempDir;

  String path(String name) => p.join(tempDir.path, name);
  Future<void> write(String name, [String text = '']) async {
    final file = File(path(name));
    await file.parent.create(recursive: true);
    await file.writeAsString(text);
  }

  Future<Map<String, String>> scan({
    String? root,
    bool recursive = false,
  }) async => {
    await for (final (:image, :caption) in store.scan(
      root ?? tempDir.path,
      recursive: recursive,
      captionExtension: '.txt',
    ))
      p.relative(image.path, from: tempDir.path): caption,
  };

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('dataset_store_test_');
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  group('scan', () {
    test('finds supported images only, case-insensitively', () async {
      await write('a.png');
      await write('b.JPG');
      await write('c.webp');
      await write('notes.txt', 'not an image');
      await write('d.psd');
      expect(
        (await scan()).keys,
        unorderedEquals(['a.png', 'b.JPG', 'c.webp']),
      );
    });

    test('pairs each image with its caption text', () async {
      await write('a.png');
      await write('a.txt', '1girl, solo');
      await write('b.png');
      expect(await scan(), {'a.png': '1girl, solo', 'b.png': ''});
    });

    test('an unreadable caption counts as empty', () async {
      await write('a.png');
      await File(path('a.txt')).writeAsBytes(_invalidUtf8);
      expect(await scan(), {'a.png': ''});
    });

    test('recursive decides whether subdirectories are listed', () async {
      await write('a.png');
      await write(p.join('sub', 'b.png'), '');
      await write(p.join('sub', 'b.txt'), 'tag');
      expect((await scan()).keys, ['a.png']);
      expect(await scan(recursive: true), {
        'a.png': '',
        p.join('sub', 'b.png'): 'tag',
      });
    });

    test('does not follow symlinks', () async {
      final outside = await Directory.systemTemp.createTemp('dataset_store_');
      addTearDown(() => outside.delete(recursive: true));
      await File(p.join(outside.path, 'x.png')).writeAsString('');
      await Link(path('linked')).create(outside.path);
      await write('a.png');
      expect((await scan(recursive: true)).keys, ['a.png']);
    });

    test('a listing failure is a stream error', () async {
      await expectLater(
        store.scan(path('missing'), recursive: false, captionExtension: '.txt'),
        emitsError(isA<FileSystemException>()),
      );
    });
  });

  group('captions', () {
    test('readCaption returns null when there is no caption file', () async {
      expect(await store.readCaption(path('a.txt')), isNull);
      // A directory in its place is not a caption file either.
      await Directory(path('b.txt')).create();
      expect(await store.readCaption(path('b.txt')), isNull);
    });

    test('readCaption throws when the file cannot be decoded', () async {
      await File(path('a.txt')).writeAsBytes(_invalidUtf8);
      await expectLater(
        store.readCaption(path('a.txt')),
        throwsA(isA<FileSystemException>()),
      );
    });

    test('writeCaption throws when the path is taken by a directory', () async {
      await Directory(path('a.txt')).create();
      await expectLater(
        store.writeCaption(path('a.txt'), 'x'),
        throwsA(isA<FileSystemException>()),
      );
    });

    test('writeCaption creates and overwrites', () async {
      await store.writeCaption(path('a.txt'), 'one');
      expect(await store.readCaption(path('a.txt')), 'one');
      await store.writeCaption(path('a.txt'), 'two');
      expect(await File(path('a.txt')).readAsString(), 'two');
    });

    test('isNonEmptyFile', () async {
      await write('empty.txt');
      await write('full.txt', 'x');
      expect(await store.isNonEmptyFile(path('empty.txt')), isFalse);
      expect(await store.isNonEmptyFile(path('full.txt')), isTrue);
      expect(await store.isNonEmptyFile(path('missing.txt')), isFalse);
    });
  });

  group('images and directories', () {
    test('imageLength and readImageBytes', () async {
      await File(path('a.png')).writeAsBytes([1, 2, 3]);
      expect(await store.imageLength(path('a.png')), 3);
      expect(await store.readImageBytes(path('a.png')), [1, 2, 3]);
      await expectLater(
        store.imageLength(path('missing.png')),
        throwsA(isA<FileSystemException>()),
      );
      await expectLater(
        store.readImageBytes(path('missing.png')),
        throwsA(isA<FileSystemException>()),
      );
    });

    test('directoryExists', () async {
      await write('a.png');
      expect(await store.directoryExists(tempDir.path), isTrue);
      expect(await store.directoryExists(path('a.png')), isFalse);
      expect(await store.directoryExists(path('missing')), isFalse);
    });
  });
}
