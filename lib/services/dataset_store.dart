import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../models/caption_type.dart';
import '../models/image_formats.dart';
import '../models/operation_context.dart';

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
      if (p
          .split(p.relative(entity.path, from: root))
          .contains('.dataset-toolkit')) {
        continue;
      }
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
  /// Accepted trade-offs of the rename: the directory must be writable even
  /// when the file itself is; the new file gets default permissions rather
  /// than the old file's; other hard links to the old file keep the old
  /// text; and a [captionPath] that is a symlink is replaced by a regular
  /// file instead of written through.
  Future<void> writeCaption(String captionPath, String text) async {
    OperationContext.check();
    final target = File(captionPath);
    // A rename ignores the target's own permissions, so check them the way a
    // plain write would: a read-only caption stays a refused write.
    if (await target.exists()) {
      final probe = await target.open(mode: FileMode.append);
      await probe.close();
    }
    // Hidden and with an extension no scan looks for, so a leftover never
    // shows up as an image or a caption. The pid and counter keep concurrent
    // writers, in this process or another, off each other's file. The target
    // name is left out so that a long caption name cannot push this one past
    // the file system's limit.
    final temp = File(
      p.join(p.dirname(captionPath), '.caption-$pid-${_nextTempId++}.tmp'),
    );
    try {
      await temp.writeAsString(text, flush: true);
      OperationContext.check();
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

  /// Refuse symlinks in every existing path component, including the root.
  /// Lexical containment alone is not sufficient at a filesystem boundary.
  Future<void> validateAssetPath(String root, String path) async {
    final base = p.normalize(p.absolute(root));
    final target = p.normalize(p.absolute(path));
    if (base.isEmpty || !(p.equals(base, target) || p.isWithin(base, target))) {
      throw FileSystemException(
        'Path is outside the dataset/output root',
        path,
      );
    }
    var component = target;
    while (true) {
      if (await FileSystemEntity.type(component, followLinks: false) ==
          FileSystemEntityType.link) {
        throw FileSystemException('Symlink paths are not supported', component);
      }
      if (p.equals(component, base)) break;
      final parent = p.dirname(component);
      if (parent == component) break;
      component = parent;
    }
  }

  Future<bool> assetExists(String path) async =>
      await FileSystemEntity.type(path, followLinks: false) !=
      FileSystemEntityType.notFound;

  Future<String> fingerprint(String path) async =>
      (await sha256.bind(File(path).openRead()).first).toString();

  Future<Uint8List> readAsset(String root, String path) async {
    await validateAssetPath(root, path);
    if (await File(path).length() > 100 * 1024 * 1024) {
      throw FileSystemException('Asset exceeds 100 MiB', path);
    }
    return File(path).readAsBytes();
  }

  Future<void> writeAsset(
    String root,
    String path,
    List<int> bytes, {
    bool overwrite = false,
  }) async {
    await validateAssetPath(root, path);
    if (!overwrite && await assetExists(path)) {
      throw FileSystemException('Destination already exists', path);
    }
    await Directory(p.dirname(path)).create(recursive: true);
    final temp = File('$path.dataset-tmp-$pid-${_nextTempId++}');
    try {
      await temp.writeAsBytes(bytes, flush: true);
      await validateAssetPath(root, path);
      if (!overwrite && await assetExists(path)) {
        throw FileSystemException('Destination appeared during commit', path);
      }
      await temp.rename(path);
    } finally {
      if (await temp.exists()) await temp.delete();
    }
  }

  Future<void> deleteAsset(String root, String path) async {
    await validateAssetPath(root, path);
    if (await File(path).exists()) await File(path).delete();
  }

  /// Every same-stem companion, not only the active/enabled caption type.
  /// Ambiguous stems are rejected instead of sharing one caption implicitly.
  Future<List<String>> sidecars(String root, String imagePath) async {
    await validateAssetPath(root, imagePath);
    final stem = p.basenameWithoutExtension(imagePath).toLowerCase();
    final result = <String>[];
    await for (final entry in Directory(
      p.dirname(imagePath),
    ).list(followLinks: false)) {
      if (p.equals(entry.path, imagePath)) continue;
      if (p.basenameWithoutExtension(entry.path).toLowerCase() != stem) {
        continue;
      }
      if (supportedImageExtensions.contains(
        p.extension(entry.path).toLowerCase(),
      )) {
        throw FileSystemException(
          'Ambiguous image stem; rename duplicate stems first',
          imagePath,
        );
      }
      if (entry is! File) {
        throw FileSystemException('Unsupported sidecar', entry.path);
      }
      await validateAssetPath(root, entry.path);
      result.add(entry.path);
    }
    result.sort();
    return result;
  }

  Future<void> checkPortableCollision(String path, {String? sameSource}) async {
    final directory = Directory(p.dirname(path));
    if (!await directory.exists()) return;
    await for (final entry in directory.list(followLinks: false)) {
      if (p.basename(entry.path).toLowerCase() ==
              p.basename(path).toLowerCase() &&
          !(sameSource != null &&
              p.equals(entry.path, sameSource) &&
              p.equals(path, sameSource))) {
        throw FileSystemException(
          'Destination collision (including case-only names)',
          path,
        );
      }
    }
  }
}
