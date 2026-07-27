import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import 'package:dataset_training_tool/services/agent/agent_tools.dart';
import 'package:dataset_training_tool/services/agent/dataset_tools.dart';
import 'package:dataset_training_tool/services/agent/media_tools.dart';
import 'package:dataset_training_tool/services/settings_service.dart';
import 'package:dataset_training_tool/state/ai_tagger_state.dart';
import 'package:dataset_training_tool/state/dataset_state.dart';

void main() {
  late Directory tempDir;
  late DatasetState dataset;
  late DatasetToolsDeps deps;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('media_tools_test_');
    // A real 64x32 PNG so the vision pipeline has something to decode.
    final image = img.Image(width: 64, height: 32);
    img.fill(image, color: img.ColorRgb8(200, 120, 40));
    await File(
      p.join(tempDir.path, '001.png'),
    ).writeAsBytes(img.encodePng(image));

    dataset = DatasetState();
    await dataset.scan(
      directoryPath: tempDir.path,
      recursive: false,
      captionExtension: '.txt',
    );
    deps = DatasetToolsDeps(
      dataset: dataset,
      rootDir: () => tempDir.path,
      libraryTags: () => const [],
      tagGroups: () => const [],
    );
  });

  tearDown(() async {
    dataset.dispose();
    await tempDir.delete(recursive: true);
  });

  group('compressForVision', () {
    test('re-encodes as JPEG and keeps small images unscaled', () async {
      final bytes = await File(p.join(tempDir.path, '001.png')).readAsBytes();
      final jpeg = await compressForVision(bytes);
      expect(jpeg, isNotNull);
      final decoded = img.decodeImage(jpeg!);
      expect(decoded!.width, 64);
      expect(decoded.height, 32);
    });

    test('downscales the longest side to the cap', () async {
      final wide = img.Image(width: 2000, height: 500);
      final jpeg = await compressForVision(
        Uint8List.fromList(img.encodePng(wide)),
      );
      final decoded = img.decodeImage(jpeg!);
      expect(decoded!.width, kVisionMaxDimension);
      expect(decoded.height, (500 * 768 / 2000).round());
    });

    test('returns null for undecodable bytes', () async {
      expect(await compressForVision(Uint8List.fromList([1, 2, 3])), isNull);
    });
  });

  group('view_image tool', () {
    late ToolRegistry registry;

    setUp(() {
      registry = ToolRegistry(buildVisionTools(deps));
    });

    test('attaches an image part and reports the path order', () async {
      final result = await registry.dispatch(
        'view_image',
        jsonEncode({
          'paths': ['001.png'],
        }),
      );
      expect(result.isError, isFalse);
      expect(result.extraParts.length, 1);
      expect(result.extraParts.single.isImage, isTrue);
      final out = jsonDecode(result.text) as Map<String, dynamic>;
      expect(out['attached'], 1);
      expect(out['paths'], ['001.png']);
    });

    test('rejects more than 4 paths', () async {
      final result = await registry.dispatch(
        'view_image',
        jsonEncode({
          'paths': ['a', 'b', 'c', 'd', 'e'],
        }),
      );
      expect(result.isError, isTrue);
      expect(result.text, contains('at most 4'));
    });

    test('missing images produce an error result with no parts', () async {
      final result = await registry.dispatch(
        'view_image',
        jsonEncode({
          'paths': ['nope.png'],
        }),
      );
      expect(result.isError, isTrue);
      expect(result.extraParts, isEmpty);
    });
  });

  group('run_wd_tagger tool', () {
    test('errors cleanly when no model is selected', () async {
      final ai = AiTaggerState(SettingsService());
      final registry = ToolRegistry(buildTaggerTools(deps, ai));
      final result = await registry.dispatch(
        'run_wd_tagger',
        jsonEncode({
          'paths': ['001.png'],
        }),
      );
      expect(result.isError, isTrue);
      expect(result.text, contains('no tagger model selected'));
      ai.dispose();
    });
  });
}
