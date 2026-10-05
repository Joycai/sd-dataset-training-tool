import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../models/image_operation.dart';

class ImageTransformResult {
  const ImageTransformResult(this.bytes, this.width, this.height);
  final Uint8List bytes;
  final int width, height;
}

/// CPU work and image decoding run outside the UI isolate. All dataset I/O
/// remains in DatasetStore. AI masks use the same oriented source frame.
class ImageTransformService {
  Future<ImageTransformResult> transform(
    Uint8List bytes,
    ImageRecipe recipe, {
    Uint8List? foreground,
  }) => Isolate.run(() {
    var source = _decode(bytes);
    final sourceProfile = source.iccProfile?.clone();
    final originalWidth = source.width;
    final originalHeight = source.height;
    if (recipe.format == 'keep') {
      return ImageTransformResult(bytes, source.width, source.height);
    }
    List<int>? box = recipe.crop;
    if (recipe.needsAi) {
      if (foreground == null) throw StateError('Missing foreground analysis');
      final cutout = _decode(foreground);
      if (cutout.width != source.width ||
          cutout.height != source.height ||
          !cutout.hasAlpha) {
        throw StateError('AI output must be RGBA in the oriented source frame');
      }
      if (recipe.cropForeground) {
        var left = source.width, top = source.height, right = -1, bottom = -1;
        var covered = 0;
        for (final pixel in cutout) {
          if (pixel.aNormalized >= 0.5) {
            covered++;
            left = math.min(left, pixel.x);
            top = math.min(top, pixel.y);
            right = math.max(right, pixel.x);
            bottom = math.max(bottom, pixel.y);
          }
        }
        if (covered < 16 || covered / (source.width * source.height) < 0.001) {
          throw StateError('No reliable foreground; review or skip this image');
        }
        left = math.max(0, left - recipe.margin);
        top = math.max(0, top - recipe.margin);
        right = math.min(source.width - 1, right + recipe.margin);
        bottom = math.min(source.height - 1, bottom + recipe.margin);
        box = [left, top, right - left + 1, bottom - top + 1];
      }
      if (recipe.removeBackground) source = cutout;
    }
    if (box != null) {
      if (box[0] + box[2] > originalWidth || box[1] + box[3] > originalHeight) {
        throw const FormatException(
          'Crop is outside the oriented source image',
        );
      }
      source = img.copyCrop(
        source,
        x: box[0],
        y: box[1],
        width: box[2],
        height: box[3],
      );
    }
    if (recipe.width case final int width) {
      final height = recipe.height!;
      var scale = recipe.resizeMode == 'crop'
          ? math.max(width / source.width, height / source.height)
          : math.min(width / source.width, height / source.height);
      if (!recipe.upscale && scale > 1) {
        if (recipe.resizeMode == 'crop') {
          throw const FormatException(
            'Target crop requires upscaling; enable it or use fit/pad',
          );
        }
        scale = 1;
      }
      final resizedWidth = (source.width * scale).round();
      final resizedHeight = (source.height * scale).round();
      if (resizedWidth * resizedHeight > 40000000) {
        throw const FormatException(
          'Intermediate resize exceeds 40 megapixels; crop first',
        );
      }
      source = img.copyResize(
        source,
        width: math.max(1, (source.width * scale).round()),
        height: math.max(1, (source.height * scale).round()),
        interpolation: img.Interpolation.cubic,
      );
      if (recipe.resizeMode == 'crop') {
        source = img.copyCrop(
          source,
          x: (source.width - width) ~/ 2,
          y: (source.height - height) ~/ 2,
          width: width,
          height: height,
        );
      } else if (recipe.resizeMode == 'pad') {
        final canvas = img.Image(width: width, height: height, numChannels: 4);
        if (recipe.background case final List<int> bg) {
          img.fill(canvas, color: img.ColorRgba8(bg[0], bg[1], bg[2], 255));
        }
        img.compositeImage(
          canvas,
          source,
          dstX: (width - source.width) ~/ 2,
          dstY: (height - source.height) ~/ 2,
        );
        source = canvas;
      }
    }
    if (recipe.format == 'jpeg' && source.hasAlpha) {
      final bg = recipe.background;
      if (bg == null && source.any((p) => p.aNormalized < 1)) {
        throw const FormatException(
          'JPEG needs an explicit background RGB color for transparency',
        );
      }
      final canvas = img.Image(width: source.width, height: source.height);
      img.fill(
        canvas,
        color: img.ColorRgb8(bg?[0] ?? 255, bg?[1] ?? 255, bg?[2] ?? 255),
      );
      img.compositeImage(canvas, source);
      source = canvas;
    }
    // Orientation is baked into pixels. Remove EXIF so readers do not rotate
    // a second time; avoid carrying camera/GPS metadata into derived datasets.
    source.exif.clear();
    source.iccProfile = sourceProfile;
    final encoded = recipe.format == 'jpeg'
        ? img.encodeJpg(source, quality: recipe.quality)
        : img.encodePng(source);
    return ImageTransformResult(
      Uint8List.fromList(encoded),
      source.width,
      source.height,
    );
  });

  Future<ImageTransformResult> inspect(Uint8List bytes) => Isolate.run(() {
    final image = _decode(bytes);
    return ImageTransformResult(Uint8List(0), image.width, image.height);
  });

  Future<Uint8List> thumbnail(Uint8List bytes) => Isolate.run(() {
    var image = _decode(bytes);
    if (math.max(image.width, image.height) > 512) {
      image = img.copyResize(
        image,
        width: image.width >= image.height ? 512 : null,
        height: image.height > image.width ? 512 : null,
      );
    }
    return Uint8List.fromList(img.encodePng(image));
  });

  static img.Image _decode(Uint8List bytes) {
    if (bytes.length > 100 * 1024 * 1024) {
      throw const FormatException('Image exceeds 100 MiB');
    }
    final decoder = img.findDecoderForData(bytes);
    final info = decoder?.startDecode(bytes);
    if (info == null ||
        info.width <= 0 ||
        info.height <= 0 ||
        info.width * info.height > 40000000 ||
        info.numFrames != 1) {
      throw const FormatException(
        'Use a single-frame image up to 40 megapixels',
      );
    }
    final image = decoder!.decodeFrame(0);
    if (image == null) throw const FormatException('Cannot decode image');
    return img.bakeOrientation(image);
  }
}
