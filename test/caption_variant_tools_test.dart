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
  CaptionType(
    id: 'nlp',
    name: 'NLP',
    extension: '.ntxt',
    format: CaptionFormat.prose,
  ),
  CaptionType(
    id: 'anima',
    name: 'anima',
    extension: '.json',
    format: CaptionFormat.json,
  ),
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
      expect(types, hasLength(3));
      expect(types[0]['extension'], '.txt');
      expect(types[0]['active'], isTrue);
      expect(types[1]['extension'], '.ntxt');
      expect(types[1]['active'], isFalse);
      expect(types[2]['extension'], '.json');
      expect(types[2]['active'], isFalse);
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
      expect(images[0]['captions'], {
        '.txt': true,
        '.ntxt': true,
        '.json': false,
      });
      expect(images[1]['captions'], {
        '.txt': false,
        '.ntxt': false,
        '.json': false,
      });
      expect(images[2]['error'], contains('not found'));
    });

    test('rejects an unconfigured extension', () async {
      final result = await registry.dispatch(
        'check_caption_variants',
        jsonEncode({'missing_extension': '.foo'}),
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
        jsonEncode({'path': '001.png', 'extension': '.foo', 'text': 'x'}),
      );
      expect(result.isError, isTrue);
      expect(File(cap('001', '.foo')).existsSync(), isFalse);
    });
  });

  group('write_caption_file JSON validation', () {
    test('rejects text that does not parse as JSON', () async {
      final result = await registry.dispatch(
        'write_caption_file',
        jsonEncode({
          'path': '001.png',
          'extension': '.json',
          'text': '{"tags": [,]}',
        }),
      );
      expect(result.isError, isTrue);
      expect(result.text, contains('not valid JSON'));
      expect(File(cap('001', '.json')).existsSync(), isFalse);
    });

    test('valid JSON is stored verbatim', () async {
      const text = '{"tags": ["smile"]}';
      final out = await call('write_caption_file', {
        'path': '001.png',
        'extension': '.json',
        'text': text,
      });
      expect(out['written'], isTrue);
      expect(await File(cap('001', '.json')).readAsString(), text);
    });
  });

  group('write_caption_file expect_tags_from', () {
    // 001.txt is 'trigger, 1girl, smile'.
    const animaJson =
        '{"quality": [""], "count": "1girl", "character": "trigger", '
        '"series": [], "artist": "", "appearance": [], "tags": ["smile"], '
        '"environment": [], "nl": "a girl smiling"}';

    test('a lossless JSON conversion passes and reports the tag count',
        () async {
      final out = await call('write_caption_file', {
        'path': '001.png',
        'extension': '.json',
        'text': animaJson,
        'expect_tags_from': '.txt',
        'ignore_keys': ['nl'],
      });
      expect(out['written'], isTrue);
      expect(out['tags_verified'], 3);
      expect(await File(cap('001', '.json')).readAsString(), animaJson);
    });

    test('matching folds case and underscore style', () async {
      final out = await call('write_caption_file', {
        'path': '001.png',
        'extension': '.json',
        'text': '{"count": "1GIRL", "tags": ["trigger", "smile"]}',
        'expect_tags_from': '.txt',
      });
      expect(out['written'], isTrue);
      expect(out['tags_verified'], 3);
    });

    test('a lost tag rejects the write', () async {
      final result = await registry.dispatch(
        'write_caption_file',
        jsonEncode({
          'path': '001.png',
          'extension': '.json',
          'text': '{"count": "1girl", "tags": ["trigger"]}',
          'expect_tags_from': '.txt',
        }),
      );
      expect(result.isError, isTrue);
      expect(result.text, contains('lost: smile'));
      expect(result.text, contains('trigger, 1girl, smile'));
      expect(File(cap('001', '.json')).existsSync(), isFalse);
    });

    test('an invented or duplicated tag rejects the write', () async {
      final result = await registry.dispatch(
        'write_caption_file',
        jsonEncode({
          'path': '001.png',
          'extension': '.json',
          'text':
              '{"count": "1girl", "appearance": ["smile"], '
              '"tags": ["trigger", "smile"]}',
          'expect_tags_from': '.txt',
        }),
      );
      expect(result.isError, isTrue);
      expect(result.text, contains('invented or duplicated: smile'));
      expect(File(cap('001', '.json')).existsSync(), isFalse);
    });

    test('nl text only escapes the comparison via ignore_keys', () async {
      final result = await registry.dispatch(
        'write_caption_file',
        jsonEncode({
          'path': '001.png',
          'extension': '.json',
          'text':
              '{"tags": ["trigger", "1girl", "smile"], '
              '"nl": "a girl smiling"}',
          'expect_tags_from': '.txt',
        }),
      );
      expect(result.isError, isTrue);
      expect(result.text, contains('invented or duplicated'));
    });

    test('guards a tag-style non-JSON target too', () async {
      final out = await call('write_caption_file', {
        'path': '001.png',
        'extension': '.txt',
        'text': 'smile, trigger, 1girl',
        'expect_tags_from': '.txt',
      });
      expect(out['written'], isTrue);
      expect(out['tags_verified'], 3);
      expect(dataset.tagsOf(img('001')), ['smile', 'trigger', '1girl']);
    });

    test('rejects a prose source type', () async {
      final result = await registry.dispatch(
        'write_caption_file',
        jsonEncode({
          'path': '001.png',
          'extension': '.json',
          'text': '{}',
          'expect_tags_from': '.ntxt',
        }),
      );
      expect(result.isError, isTrue);
      expect(result.text, contains('prose'));
    });

    test('rejects a prose target', () async {
      final result = await registry.dispatch(
        'write_caption_file',
        jsonEncode({
          'path': '001.png',
          'extension': '.ntxt',
          'text': 'A girl.',
          'expect_tags_from': '.txt',
        }),
      );
      expect(result.isError, isTrue);
      expect(result.text, contains('prose target'));
    });

    test('rejects an unconfigured source extension', () async {
      final result = await registry.dispatch(
        'write_caption_file',
        jsonEncode({
          'path': '001.png',
          'extension': '.json',
          'text': '{}',
          'expect_tags_from': '.foo',
        }),
      );
      expect(result.isError, isTrue);
      expect(result.text, contains('not a configured caption type'));
    });

    test('an uncaptioned source rejects any tags in the new text', () async {
      final result = await registry.dispatch(
        'write_caption_file',
        jsonEncode({
          'path': '003.png',
          'extension': '.json',
          'text': '{"tags": ["solo"]}',
          'expect_tags_from': '.txt',
        }),
      );
      expect(result.isError, isTrue);
      expect(result.text, contains('invented or duplicated: solo'));
    });
  });

  group('convert_captions_to_json', () {
    // The anima-style shape used throughout: 001.txt is
    // 'trigger, 1girl, smile', 002.txt is 'trigger, 1boy'.
    const animaArgs = {
      'source_extension': '.txt',
      'target_extension': '.json',
      'fields': [
        {'name': 'quality', 'kind': 'array'},
        {'name': 'count', 'kind': 'string'},
        {'name': 'character', 'kind': 'string'},
        {'name': 'artist', 'kind': 'string'},
        {'name': 'appearance', 'kind': 'array'},
        {'name': 'tags', 'kind': 'array'},
        {'name': 'nl', 'kind': 'string'},
      ],
      'constants': {
        'quality': [''],
        'artist': '',
        'nl': '',
      },
      'assign': {
        '1girl': 'count',
        '1boy': 'count',
        'trigger': 'character',
        'smile': 'appearance',
      },
      'unassigned_field': 'tags',
    };

    test('assembles ordered JSON for every captioned image as one undoable '
        'operation', () async {
      final out = await call('convert_captions_to_json', animaArgs);
      expect(out['written'], 2);
      expect(out['skipped_uncaptioned'], 1);
      expect(out['unassigned_tags_seen'], isEmpty);

      final text = await File(cap('001', '.json')).readAsString();
      final decoded = jsonDecode(text) as Map<String, dynamic>;
      expect(decoded.keys.toList(), [
        'quality',
        'count',
        'character',
        'artist',
        'appearance',
        'tags',
        'nl',
      ]);
      expect(decoded['quality'], ['']);
      expect(decoded['count'], '1girl');
      expect(decoded['character'], 'trigger');
      expect(decoded['appearance'], ['smile']);
      expect(decoded['tags'], isEmpty);
      expect(decoded['nl'], '');
      final two = jsonDecode(await File(cap('002', '.json')).readAsString());
      expect(two['count'], '1boy');
      expect(two['appearance'], isEmpty);

      expect(tagOps.undoLabel, 'AI: convert 2 captions to .json');
      await tagOps.undo();
      expect(await File(cap('001', '.json')).readAsString(), isEmpty);
      expect(dataset.tagsOf(img('001')), ['trigger', '1girl', 'smile']);
    });

    test('strips caption-style escaping and reports unassigned tags',
        () async {
      await File(img('004')).writeAsBytes(_pngBytes);
      await File(
        cap('004', '.txt'),
      ).writeAsString(r'trigger, smile \(happy\)');
      await dataset.scan(
        directoryPath: tempDir.path,
        recursive: false,
        captionExtension: '.txt',
      );

      final out = await call('convert_captions_to_json', {
        ...animaArgs,
        'name_query': '004',
      });
      expect(out['written'], 1);
      final decoded = jsonDecode(await File(cap('004', '.json')).readAsString());
      expect(decoded['tags'], ['smile (happy)']);
      expect(out['unassigned_tags_seen'], [r'smile \(happy\)']);
    });

    test('existing target files are skipped unless overwrite', () async {
      await call('convert_captions_to_json', animaArgs);
      final again = await call('convert_captions_to_json', animaArgs);
      expect(again['written'], 0);
      expect(again['skipped_existing'], 2);

      final rebuilt = await call('convert_captions_to_json', {
        ...animaArgs,
        'overwrite': true,
      });
      expect(rebuilt['written'], 0);
      expect(rebuilt['unchanged'], 2);
    });

    test('two tags landing in one string field fails that image only',
        () async {
      final out = await call('convert_captions_to_json', {
        ...animaArgs,
        'assign': {
          '1girl': 'count',
          '1boy': 'count',
          'smile': 'count',
          'trigger': 'character',
        },
      });
      // 001 puts both 1girl and smile into "count"; 002 is fine.
      expect(out['written'], 1);
      expect(out['failed_images'], 1);
      final failure = (out['failures'] as List).single as Map;
      expect(failure['path'], '001.png');
      expect(failure['error'], contains('"count"'));
      expect(File(cap('001', '.json')).existsSync(), isFalse);
      expect(File(cap('002', '.json')).existsSync(), isTrue);
    });

    test('source and target are validated by configured format', () async {
      final source = await registry.dispatch(
        'convert_captions_to_json',
        jsonEncode({...animaArgs, 'source_extension': '.json'}),
      );
      expect(source.isError, isTrue);
      expect(source.text, contains('tag-list'));

      final target = await registry.dispatch(
        'convert_captions_to_json',
        jsonEncode({...animaArgs, 'target_extension': '.ntxt'}),
      );
      expect(target.isError, isTrue);
      expect(target.text, contains('prose, not'));
    });

    test('rejects a bad shape before touching any file', () async {
      final undeclared = await registry.dispatch(
        'convert_captions_to_json',
        jsonEncode({
          ...animaArgs,
          'assign': {'1girl': 'nope'},
        }),
      );
      expect(undeclared.isError, isTrue);
      expect(undeclared.text, contains('not a declared field'));

      final notArray = await registry.dispatch(
        'convert_captions_to_json',
        jsonEncode({...animaArgs, 'unassigned_field': 'count'}),
      );
      expect(notArray.isError, isTrue);
      expect(notArray.text, contains('unassigned_field'));
      expect(notArray.text, contains('array'));

      final constantTarget = await registry.dispatch(
        'convert_captions_to_json',
        jsonEncode({
          ...animaArgs,
          'assign': {'1girl': 'artist'},
        }),
      );
      expect(constantTarget.isError, isTrue);
      expect(constantTarget.text, contains('constant'));
      expect(File(cap('001', '.json')).existsSync(), isFalse);
    });

    test('an undeclared constant is dropped and reported, not fatal', () async {
      final out = await call('convert_captions_to_json', {
        ...animaArgs,
        'constants': {
          'quality': [''],
          'artist': '',
          'nl': '',
          'reason': 'because',
        },
      });
      expect(out['written'], 2);
      expect(out['ignored_constants'], ['reason']);
      final decoded =
          jsonDecode(await File(cap('001', '.json')).readAsString()) as Map;
      expect(decoded.containsKey('reason'), isFalse);
      expect(decoded['quality'], ['']);
    });
  });
}
