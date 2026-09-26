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

  /// Names in [dir] (relative to the temp root), sorted.
  Future<List<String>> entries([String dir = '']) async =>
      [await for (final e in Directory(path(dir)).list()) p.basename(e.path)]
        ..sort();

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

    test(
      'a listing failure mid-scan still delivers what came before it',
      () async {
        // The locked directory is created first so that file systems that
        // list newest entries first (tmpfs) put the images ahead of it.
        final locked = await Directory(path('locked')).create();
        await write(p.join('locked', 'hidden.png'));
        for (var i = 0; i < 20; i++) {
          await write('img_$i.png');
        }
        await Process.run('chmod', ['000', locked.path]);
        addTearDown(() => Process.run('chmod', ['755', locked.path]));

        // What the platform lists before the failure is up to the file
        // system's entry order, so the expectation is taken from a plain
        // listing of the same tree.
        final listedFirst = <String>[];
        Object? listingError;
        try {
          await for (final e in tempDir.list(recursive: true)) {
            if (e.path.endsWith('.png')) listedFirst.add(e.path);
          }
        } catch (e) {
          listingError = e;
        }
        if (listingError == null) {
          markTestSkipped('chmod 000 did not block listing (running as root?)');
          return;
        }
        if (listedFirst.isEmpty) {
          // Nothing precedes the failure here, so the test would prove
          // nothing about partial delivery.
          markTestSkipped('this file system lists the locked directory first');
          return;
        }

        final delivered = <String>[];
        Object? scanError;
        try {
          await for (final (:image, caption: _) in store.scan(
            tempDir.path,
            recursive: true,
            captionExtension: '.txt',
          )) {
            delivered.add(image.path);
          }
        } catch (e) {
          scanError = e;
        }
        expect(scanError, isA<FileSystemException>());
        expect(delivered, listedFirst);
      },
      skip: Platform.isWindows ? 'relies on chmod' : false,
    );

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
      // The temporary file must not outlive the failed rename.
      expect(await entries(), ['a.txt']);
    });

    test('writeCaption creates and overwrites', () async {
      await store.writeCaption(path('a.txt'), 'one');
      expect(await store.readCaption(path('a.txt')), 'one');
      await store.writeCaption(path('a.txt'), 'two');
      expect(await File(path('a.txt')).readAsString(), 'two');
      expect(await entries(), ['a.txt']);
    });

    test('writeCaption replaces a longer caption without a tail', () async {
      await write('a.txt', 'a much longer caption than the next one');
      await store.writeCaption(path('a.txt'), 'short');
      expect(await File(path('a.txt')).readAsString(), 'short');
    });

    test(
      'writeCaption keeps the old caption when the directory is read-only',
      () async {
        await write('sub/a.txt', 'old');
        final dir = Directory(path('sub'));
        await Process.run('chmod', ['555', dir.path]);
        addTearDown(() => Process.run('chmod', ['755', dir.path]));

        Object? error;
        try {
          await store.writeCaption(path('sub/a.txt'), 'new');
        } catch (e) {
          error = e;
        }
        if (error == null) {
          markTestSkipped('chmod 555 did not block writing (running as root?)');
          return;
        }
        expect(error, isA<FileSystemException>());
        expect(await File(path('sub/a.txt')).readAsString(), 'old');
        expect(await entries('sub'), ['a.txt']);
      },
      skip: Platform.isWindows ? 'relies on chmod' : false,
    );

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
