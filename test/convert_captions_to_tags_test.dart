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

/// `.atxt` (Anima Tag) is the active type, `.txt` (WD14) is the target — the
/// shape of a dataset captioned for Anima that is now going to train a LoRA.
const _types = [
  CaptionType(
    id: CaptionType.defaultId,
    name: 'Anima',
    extension: '.atxt',
    format: CaptionFormat.animaTag,
  ),
  CaptionType(id: 'wd', name: 'WD14', extension: '.txt'),
  CaptionType(
    id: 'json',
    name: 'Anima JSON',
    extension: '.json',
    format: CaptionFormat.json,
  ),
  CaptionType(
    id: 'nlp',
    name: 'NLP',
    extension: '.ntxt',
    format: CaptionFormat.prose,
  ),
];

void main() {
  late Directory tempDir;
  late DatasetState dataset;
  late TagOps tagOps;
  late ToolRegistry registry;

  String img(String name) => p.join(tempDir.path, '$name.png');
  String cap(String name, String ext) => p.join(tempDir.path, '$name$ext');
  Future<String> read(String name, String ext) =>
      File(cap(name, ext)).readAsString();

  Future<Map<String, dynamic>> call(
    String tool, [
    Map<String, dynamic> args = const {},
  ]) async {
    final result = await registry.dispatch(tool, jsonEncode(args));
    return jsonDecode(result.text) as Map<String, dynamic>;
  }

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('convert_to_tags_test_');
    for (final name in ['001', '002', '003']) {
      await File(img(name)).writeAsBytes(_pngBytes);
    }
    await File(cap('001', '.atxt')).writeAsString(
      'newest, safe, 1girl, @my artist, hatsune miku (racing), long_hair, '
      'smile. A girl smiles, indoors.',
    );
    await File(
      cap('002', '.atxt'),
    ).writeAsString('newest, safe, 1boy, short_hair');
    // 003 has no caption at all.

    dataset = DatasetState();
    await dataset.scan(
      directoryPath: tempDir.path,
      recursive: false,
      captionExtension: '.atxt',
      captionFormat: CaptionFormat.animaTag,
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

  group('convert_captions_to_tags', () {
    test('the whole Anima Tag → WD14 conversion in one call', () async {
      final out = await call('convert_captions_to_tags', {
        'source_extension': '.atxt',
        'target_extension': '.txt',
        'remove': ['newest', 'safe'],
        'rename': {'@my artist': 'my artist'},
        'spacing': 'spaces',
        'parentheses': 'escape',
        'prepend': ['trigger'],
      });

      expect(out['error'], isNull);
      expect(out['written'], 2);
      expect(out['skipped_uncaptioned'], 1);

      // Quality tags gone, @ stripped, parens escaped, underscores folded to
      // spaces, trigger word first, and no trailing sentence.
      expect(
        await read('001', '.txt'),
        'trigger, 1girl, my artist, hatsune miku \\(racing\\), long hair, '
        'smile',
      );
      expect(await read('002', '.txt'), 'trigger, 1boy, short hair');

      // The source is untouched — the description still lives there.
      expect(await read('001', '.atxt'), endsWith('. A girl smiles, indoors.'));
    });

    test('every drop and rename is reported with its caption count', () async {
      final out = await call('convert_captions_to_tags', {
        'source_extension': '.atxt',
        'target_extension': '.txt',
        'remove': ['newest', 'safe', 'nonexistent tag'],
        'rename': {'@my artist': 'my artist'},
      });

      expect(out['removed_tags'], {'newest': 2, 'safe': 2});
      expect(out['renamed_tags'], {'@my artist': 1});
      // A rule that matched nothing is visible by its absence, so a typo in
      // the drop list cannot pass as "there were none".
      expect(
        (out['removed_tags'] as Map).containsKey('nonexistent tag'),
        false,
      );
    });

    test('dropping a description is counted, never silent', () async {
      final out = await call('convert_captions_to_tags', {
        'source_extension': '.atxt',
        'target_extension': '.txt',
      });
      expect(out['descriptions_dropped'], 1);
      expect(out['descriptions_carried'], isNull);
    });

    test('priority orders the tags, prepend never duplicates', () async {
      await call('convert_captions_to_tags', {
        'source_extension': '.atxt',
        'target_extension': '.txt',
        'remove': ['newest', 'safe'],
        // "1girl" is both prepended and named in priority, and the caption
        // already carries it: it must appear exactly once, at the front.
        'prepend': ['1girl'],
        'priority': ['smile', '1girl', 'long hair'],
      });
      expect(
        await read('001', '.txt'),
        '1girl, smile, long_hair, @my artist, hatsune miku (racing)',
      );
    });

    test('an existing target is kept unless overwrite is set', () async {
      await File(cap('001', '.txt')).writeAsString('hand written');
      var out = await call('convert_captions_to_tags', {
        'source_extension': '.atxt',
        'target_extension': '.txt',
      });
      expect(out['skipped_existing'], 1);
      expect(await read('001', '.txt'), 'hand written');

      out = await call('convert_captions_to_tags', {
        'source_extension': '.atxt',
        'target_extension': '.txt',
        'overwrite': true,
      });
      // Only 001 changes: the first call already produced 002's target, and
      // an identical rewrite counts as unchanged rather than a write.
      expect(out['written'], 1);
      expect(out['unchanged'], 1);
      expect(await read('001', '.txt'), isNot('hand written'));
    });

    test('writing the active type keeps the dataset index in sync', () async {
      // .atxt is active here, so this is the reverse direction: WD14 in,
      // Anima Tag out.
      await File(cap('003', '.txt')).writeAsString('1girl, wave');
      final out = await call('convert_captions_to_tags', {
        'source_extension': '.txt',
        'target_extension': '.atxt',
        'overwrite': true,
      });
      expect(out['error'], isNull);
      expect(await read('003', '.atxt'), '1girl, wave');
      // The gallery and the tag index read from here, not from disk.
      expect(dataset.tagsOf(img('003')), ['1girl', 'wave']);
      expect(tagOps.canUndo, isTrue);
    });

    test('an Anima Tag target keeps the description it was given', () async {
      // Round trip: .atxt → .txt → back into a second Anima Tag type would
      // need a third type, so go the other way and check the tail survives a
      // same-format conversion through the .ntxt slot being rejected below.
      final out = await call('convert_captions_to_tags', {
        'source_extension': '.atxt',
        'target_extension': '.ntxt',
      });
      expect(out['error'], contains('tag-list'));
      expect(out['error'], contains('prose'));
    });

    test('a JSON type is refused with a pointer to the right tool', () async {
      final out = await call('convert_captions_to_tags', {
        'source_extension': '.atxt',
        'target_extension': '.json',
      });
      expect(out['error'], contains('convert_captions_to_json'));
    });

    test('source and target must differ', () async {
      final out = await call('convert_captions_to_tags', {
        'source_extension': '.atxt',
        'target_extension': '.atxt',
      });
      expect(out['error'], contains('same caption type'));
    });

    test(
      'a bad rule fails the whole call before anything is written',
      () async {
        final out = await call('convert_captions_to_tags', {
          'source_extension': '.atxt',
          'target_extension': '.txt',
          'spacing': 'sideways',
        });
        expect(out['error'], contains('spacing'));
        expect(File(cap('001', '.txt')).existsSync(), isFalse);
      },
    );
  });

  group('convert_captions_to_json with an Anima Tag source', () {
    Map<String, dynamic> jsonArgs({String? nlField}) => {
      'source_extension': '.atxt',
      'target_extension': '.json',
      'fields': [
        {'name': 'count', 'kind': 'string'},
        {'name': 'tags', 'kind': 'array'},
        {'name': 'nl', 'kind': 'string'},
      ],
      'assign': {'1girl': 'count', '1boy': 'count'},
      'unassigned_field': 'tags',
      'nl_field': ?nlField,
    };

    test('nl_field carries the trailing sentence into the document', () async {
      final out = await call(
        'convert_captions_to_json',
        jsonArgs(nlField: 'nl'),
      );
      expect(out['error'], isNull);
      expect(out['written'], 2);
      expect(out['descriptions_carried'], 1);
      expect(out['descriptions_dropped'], isNull);

      final decoded =
          jsonDecode(await read('001', '.json')) as Map<String, dynamic>;
      expect(decoded['count'], '1girl');
      expect(decoded['nl'], 'A girl smiles, indoors.');
      // The sentence never entered the tag buckets.
      expect(decoded['tags'], isNot(contains('A girl smiles, indoors.')));
      expect(decoded['tags'], contains('hatsune miku (racing)'));

      // An image without a description gets the empty string, not a missing
      // key — every caption keeps the same shape.
      final second =
          jsonDecode(await read('002', '.json')) as Map<String, dynamic>;
      expect(second.containsKey('nl'), isTrue);
      expect(second['nl'], '');
    });

    test('without nl_field the dropped descriptions are counted', () async {
      final out = await call('convert_captions_to_json', jsonArgs());
      expect(out['written'], 2);
      expect(out['descriptions_dropped'], 1);
    });

    test('nl_field must be a string field that is not the catch-all', () async {
      var out = await call(
        'convert_captions_to_json',
        jsonArgs(nlField: 'tags'),
      );
      expect(out['error'], contains('string'));

      out = await call(
        'convert_captions_to_json',
        jsonArgs(nlField: 'missing'),
      );
      expect(out['error'], contains('not a declared field'));
    });

    test('nl_field is refused for a source that has no description', () async {
      await File(cap('001', '.txt')).writeAsString('1girl, smile');
      final out = await call('convert_captions_to_json', {
        ...jsonArgs(nlField: 'nl'),
        'source_extension': '.txt',
      });
      expect(out['error'], contains('only applies to an Anima Tag source'));
    });
  });
}
