import 'dart:typed_data';

import 'package:dataset_training_tool/models/image_operation.dart';
import 'package:dataset_training_tool/services/image_transform_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  final service = ImageTransformService();
  Uint8List fixture({int channels = 3}) => Uint8List.fromList(
    img.encodePng(img.Image(width: 80, height: 40, numChannels: channels)),
  );

  test('fit preserves aspect ratio and refuses implicit upscaling', () async {
    final small = await service.transform(
      fixture(),
      ImageRecipe.fromJson({'width': 20, 'height': 20}),
    );
    expect((small.width, small.height), (20, 10));
    final large = await service.transform(
      fixture(),
      ImageRecipe.fromJson({'width': 1024, 'height': 1024}),
    );
    expect((large.width, large.height), (80, 40));
  });
  test(
    'crop uses source coordinates and rejects out-of-bounds rectangles',
    () async {
      final cropped = await service.transform(
        fixture(),
        ImageRecipe.fromJson({
          'crop': [10, 5, 20, 10],
        }),
      );
      expect((cropped.width, cropped.height), (20, 10));
      await expectLater(
        service.transform(
          fixture(),
          ImageRecipe.fromJson({
            'crop': [70, 0, 20, 10],
          }),
        ),
        throwsFormatException,
      );
    },
  );
  test(
    'pad produces exact requested dimensions without enlarging subject',
    () async {
      final result = await service.transform(
        fixture(),
        ImageRecipe.fromJson({
          'width': 100,
          'height': 100,
          'resize_mode': 'pad',
          'background': [255, 255, 255],
        }),
      );
      final decoded = img.decodePng(result.bytes)!;
      expect((decoded.width, decoded.height), (100, 100));
      expect(decoded.getPixel(0, 0).r, 255);
      expect(decoded.getPixel(50, 50).r, 0);
    },
  );
  test('JPEG alpha needs an explicit flatten color', () async {
    await expectLater(
      service.transform(
        fixture(channels: 4),
        ImageRecipe.fromJson({'format': 'jpeg'}),
      ),
      throwsFormatException,
    );
    final result = await service.transform(
      fixture(channels: 4),
      ImageRecipe.fromJson({
        'format': 'jpeg',
        'background': [255, 255, 255],
      }),
    );
    expect(img.decodeJpg(result.bytes)!.getPixel(0, 0).r, greaterThan(245));
  });
  test(
    'foreground crop uses mask bounds with margin in source pixels',
    () async {
      final mask = img.Image(width: 80, height: 40, numChannels: 4);
      img.fillRect(
        mask,
        x1: 20,
        y1: 10,
        x2: 39,
        y2: 29,
        color: img.ColorRgba8(255, 0, 0, 255),
      );
      final result = await service.transform(
        fixture(),
        ImageRecipe.fromJson({
          'crop_foreground': true,
          'model': 'fake',
          'margin': 2,
        }),
        foreground: Uint8List.fromList(img.encodePng(mask)),
      );
      expect((result.width, result.height), (24, 24));
    },
  );
  test('rejects empty mask and mismatched AI coordinate frame', () async {
    final recipe = ImageRecipe.fromJson({
      'crop_foreground': true,
      'model': 'fake',
    });
    await expectLater(
      service.transform(fixture(), recipe, foreground: fixture(channels: 4)),
      throwsStateError,
    );
    final wrong = Uint8List.fromList(
      img.encodePng(img.Image(width: 10, height: 10, numChannels: 4)),
    );
    await expectLater(
      service.transform(fixture(), recipe, foreground: wrong),
      throwsStateError,
    );
  });
  test(
    'rejects a crop resize whose intermediate allocation is too large',
    () async {
      final panorama = Uint8List.fromList(
        img.encodePng(img.Image(width: 40000, height: 1)),
      );
      await expectLater(
        service.transform(
          panorama,
          ImageRecipe.fromJson({
            'width': 1024,
            'height': 1024,
            'resize_mode': 'crop',
            'upscale': true,
          }),
        ),
        throwsFormatException,
      );
    },
  );
  test('strict recipe validation rejects fractional coordinates and typos', () {
    expect(
      () => ImageRecipe.fromJson({'width': 20.1, 'height': 20}),
      throwsFormatException,
    );
    expect(
      () => ImageRecipe.fromJson({
        'crop': [0, 0, 10.5, 10],
      }),
      throwsFormatException,
    );
    expect(
      () => ImageRecipe.fromJson({'formant': 'png'}),
      throwsFormatException,
    );
    expect(
      () => ImageRecipe.fromJson({'prefix': '../escape'}),
      throwsFormatException,
    );
  });
}
