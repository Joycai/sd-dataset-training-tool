import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../models/caption_type.dart';
import '../models/image_formats.dart';

/// One image found by [DatasetStore.scan], with the raw text of its caption
/// file: '' when the caption is missing or cannot be read.
typedef ScannedImage = ({File image, String caption});

/// The dataset on disk: image files and the caption files beside them.
///
/// Every caption read and write, and every image read by state classes and
/// agent tools, goes through here, so those hold no file I/O of their own,
/// and a test can swap in a fake with `implements DatasetStore`. Two image
/// readers bypass it by design: `AiTaggerService.interrogateImageFile`
/// uploads the bytes itself, and the UI decodes images with `Image.file`.
/// Stateless: one const instance can be shared freely.
class DatasetStore {
  const DatasetStore();

  /// Supported images under [root] (symlinks are not followed), unordered,
  /// each with its caption text. A caption that exists but cannot be read
  /// counts as '' — an unreadable caption must not abort a scan. A listing
  /// failure surfaces as a stream error after the images found so far.
  Stream<ScannedImage> scan(
    String root, {
    required bool recursive,
    required String captionExtension,
  }) async* {
    final entries = Directory(
      root,
    ).list(recursive: recursive, followLinks: false);
    await for (final entity in entries) {
      if (entity is! File) continue;
      if (!supportedImageExtensions.contains(
        p.extension(entity.path).toLowerCase(),
      )) {
        continue;
      }
      var caption = '';
      try {
        caption =
            await readCaption(captionPathOf(entity.path, captionExtension)) ??
            '';
      } catch (_) {
        // Unreadable caption file: treat as untagged.
      }
      yield (image: entity, caption: caption);
    }
  }

  /// The caption file's text, or null when the file does not exist.
  /// Throws [FileSystemException] when it exists but cannot be read
  /// (including invalid UTF-8).
  Future<String?> readCaption(String captionPath) async {
    final file = File(captionPath);
    if (!await file.exists()) return null;
    return file.readAsString();
  }

  /// Creates or overwrites the caption file. The text is written to a
  /// temporary file in the same directory and renamed over [captionPath], so
  /// a crash mid-write leaves the previous caption intact rather than a
  /// truncated one. Throws [FileSystemException]; the temporary file is
  /// removed on failure.
  ///
  /// Accepted trade-offs of the rename: the new file gets default
  /// permissions rather than the old file's, and a [captionPath] that is a
  /// symlink is replaced by a regular file instead of written through.
  Future<void> writeCaption(String captionPath, String text) async {
    // Hidden and with an extension no scan looks for, so a leftover never
    // shows up as an image or a caption. The pid and counter keep concurrent
    // writers, in this process or another, off each other's file.
    final temp = File(
      p.join(
        p.dirname(captionPath),
        '.${p.basename(captionPath)}.$pid-${_nextTempId++}.tmp',
      ),
    );
    try {
      await temp.writeAsString(text, flush: true);
      await temp.rename(captionPath);
    } catch (_) {
      try {
        await temp.delete();
      } on FileSystemException {
        // Never created, or gone already: nothing to clean up.
      }
      rethrow;
    }
  }

  static int _nextTempId = 0;

  /// Whether [path] exists and is larger than zero bytes.
  Future<bool> isNonEmptyFile(String path) async {
    final file = File(path);
    return await file.exists() && await file.length() > 0;
  }

  /// Size of the image in bytes. Throws [FileSystemException].
  Future<int> imageLength(String imagePath) => File(imagePath).length();

  /// The image's raw bytes. Throws [FileSystemException].
  Future<Uint8List> readImageBytes(String imagePath) =>
      File(imagePath).readAsBytes();

  /// Whether [path] is an existing directory.
  Future<bool> directoryExists(String path) => Directory(path).exists();
}
