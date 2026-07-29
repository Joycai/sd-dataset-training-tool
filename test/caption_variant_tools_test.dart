import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:dataset_training_tool/models/caption_type.dart';
import 'package:dataset_training_tool/services/agent/agent_tools.dart';
import 'package:dataset_training_tool/services/agent/caption_variant_tools.dart';
import 'package:dataset_training_tool/services/agent/dataset_tools.dart';
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

const _types = [
  CaptionType(id: CaptionType.defaultId, name: 'WD14', extension: '.txt'),
  CaptionType(id: 'nlp', name: 'NLP', extension: '.ntxt'),
];

void main() {
  late Directory tempDir;
  late DatasetState dataset;
  late TagOps tagOps;
  late ToolRegistry registry;

  String img(String name) => p.join(tempDir.path, '$name.png');
  String cap(String name, String ext) => p.join(tempDir.path, '$name$ext');

  Future<Map<String, dynamic>> call(
    String tool, [
    Map<String, dynamic> args = const {},
  ]) async {
    final result = await registry.dispatch(tool, jsonEncode(args));
    return jsonDecode(result.text) as Map<String, dynamic>;
  }

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('caption_variant_test_');
    for (final name in ['001', '002', '003']) {
      await File(img(name)).writeAsBytes(_pngBytes);
    }
    await File(cap('001', '.txt')).writeAsString('trigger, 1girl, smile');
    await File(cap('002', '.txt')).writeAsString('trigger, 1boy');
    await File(cap('001', '.ntxt')).writeAsString('A girl smiling.');
    // 002/003 have no .ntxt; 003 has no caption at all.

    dataset = DatasetState();
    await dataset.scan(
      directoryPath: tempDir.path,
      recursive: false,
      captionExtension: '.txt',
    );
    tagOps = TagOps(dataset: dataset);
    final deps = DatasetToolsDeps(
      dataset: dataset,
      rootDir: () => tempDir.path,
      libraryTags: () => const [],
      tagGroups: () => const [],
      captionTypes: () => _types,
    );
    registry = ToolRegistry([
      ...buildReadOnlyTools(deps),
      ...buildCaptionVariantTools(deps, tagOps),
    ]);
  });

  tearDown(() async {
    tagOps.dispose();
    dataset.dispose();
    await tempDir.delete(recursive: true);
  });

  group('get_dataset_overview', () {
    test('lists the configured caption types', () async {
      final out = await call('get_dataset_overview');
      final types = (out['caption_types'] as List).cast<Map>();
      expect(types, hasLength(2));
      expect(types[0]['extension'], '.txt');
      expect(types[0]['active'], isTrue);
      expect(types[1]['extension'], '.ntxt');
      expect(types[1]['active'], isFalse);
    });
  });

  group('check_caption_variants', () {
    test('summarizes per-type coverage', () async {
      final out = await call('check_caption_variants');
      final types = (out['types'] as List).cast<Map>();
      expect(out['total_images'], 3);
      expect(types[0]['extension'], '.txt');
      expect(types[0]['images_with_caption'], 2);
      expect(types[0]['images_missing'], 1);
      expect(types[1]['extension'], '.ntxt');
      expect(types[1]['images_with_caption'], 1);
      expect(types[1]['images_missing'], 2);
    });

    test('lists images missing a given type', () async {
      final out = await call('check_caption_variants', {
        'missing_extension': 'ntxt',
      });
      expect(out['missing_extension'], '.ntxt');
      expect(out['missing_images'], ['002.png', '003.png']);
      expect(out['truncated'], isFalse);
    });

    test('per-image breakdown via paths', () async {
      final out = await call('check_caption_variants', {
        'paths': ['001.png', '003.png', 'nope.png'],
      });
      final images = (out['images'] as List).cast<Map>();
      expect(images[0]['captions'], {'.txt': true, '.ntxt': true});
      expect(images[1]['captions'], {'.txt': false, '.ntxt': false});
      expect(images[2]['error'], contains('not found'));
    });

    test('rejects an unconfigured extension', () async {
      final result = await registry.dispatch(
        'check_caption_variants',
        jsonEncode({'missing_extension': '.json'}),
      );
      expect(result.isError, isTrue);
      expect(result.text, contains('.ntxt'));
    });
  });

  group('read_caption_file', () {
    test('returns raw unparsed text', () async {
      final out = await call('read_caption_file', {
        'paths': ['001.png', '002.png'],
        'extension': '.ntxt',
      });
      final captions = (out['captions'] as List).cast<Map>();
      expect(captions[0]['text'], 'A girl smiling.');
      expect(captions[0]['exists'], isTrue);
      expect(captions[1]['exists'], isFalse);
    });

    test('escaping the dataset root does not resolve', () async {
      final out = await call('read_caption_file', {
        'paths': ['../outside.png'],
        'extension': '.txt',
      });
      final captions = (out['captions'] as List).cast<Map>();
      expect(captions[0]['error'], contains('not found'));
    });
  });

  group('write_caption_file', () {
    test('writes a variant file and records undo without touching the '
        'active caption state', () async {
      final out = await call('write_caption_file', {
        'path': '002.png',
        'extension': '.ntxt',
        'text': 'A boy standing.',
      });
      expect(out['written'], isTrue);
      expect(await File(cap('002', '.ntxt')).readAsString(), 'A boy standing.');
      // The active (.txt) index must be untouched by the variant write…
      expect(dataset.tagsOf(img('002')), ['trigger', '1boy']);

      // …and by its undo.
      expect(tagOps.undoLabel, 'AI: write 002.ntxt');
      await tagOps.undo();
      expect(File(cap('002', '.ntxt')).existsSync(), isTrue);
      expect(await File(cap('002', '.ntxt')).readAsString(), isEmpty);
      expect(dataset.tagsOf(img('002')), ['trigger', '1boy']);
      expect(await File(cap('002', '.txt')).readAsString(), 'trigger, 1boy');
    });

    test('identical content reports unchanged without history', () async {
      final out = await call('write_caption_file', {
        'path': '001.png',
        'extension': '.ntxt',
        'text': 'A girl smiling.',
      });
      expect(out['written'], isFalse);
      expect(out['unchanged'], isTrue);
      expect(tagOps.canUndo, isFalse);
    });

    test('writing the active type goes through the dataset state', () async {
      final out = await call('write_caption_file', {
        'path': '003.png',
        'extension': '.txt',
        'text': 'trigger, solo',
      });
      expect(out['written'], isTrue);
      expect(dataset.tagsOf(img('003')), ['trigger', 'solo']);
      expect(dataset.hasCaption(img('003')), isTrue);
    });

    test('rejects an unconfigured extension', () async {
      final result = await registry.dispatch(
        'write_caption_file',
        jsonEncode({'path': '001.png', 'extension': '.json', 'text': '{}'}),
      );
      expect(result.isError, isTrue);
      expect(File(cap('001', '.json')).existsSync(), isFalse);
    });
  });
}
