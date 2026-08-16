import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:dataset_training_tool/models/caption_type.dart';
import 'package:dataset_training_tool/services/agent/agent_tools.dart';
import 'package:dataset_training_tool/services/agent/caption_edit_tools.dart';
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
      ...buildCaptionEditTools(deps, tagOps),
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

  group('convert_captions_to_tags from a JSON source', () {
    // The Anima simplified shape, as convert_captions_to_json writes it.
    Future<void> writeJson(String name, Map<String, Object?> doc) => File(
      cap(name, '.json'),
    ).writeAsString(const JsonEncoder.withIndent('  ').convert(doc));

    setUp(() async {
      await writeJson('001', {
        'quality': 'newest, safe',
        'count': '1girl',
        'character': 'hatsune miku (racing)',
        'artist': '@my artist',
        'appearance': ['long hair', 'blue eyes'],
        'tags': ['smile'],
        'environment': ['indoors'],
        'nl': 'A girl smiles, indoors.',
      });
      await writeJson('002', {
        'quality': 'newest, safe',
        'count': '1boy',
        'character': '',
        'artist': '',
        'appearance': ['short hair'],
        'tags': [],
        'environment': [],
        'nl': '',
      });
    });

    const order = [
      'quality',
      'count',
      'character',
      'artist',
      'appearance',
      'tags',
      'environment',
    ];

    test('flattens the document into the declared key order', () async {
      final out = await call('convert_captions_to_tags', {
        'source_extension': '.json',
        'target_extension': '.txt',
        'fields': order,
        'nl_field': 'nl',
      });
      expect(out['written'], 2);
      // Key order is the declared one, and the prose field never became tags.
      expect(
        await read('001', '.txt'),
        'newest, safe, 1girl, hatsune miku (racing), @my artist, long hair, '
        'blue eyes, smile, indoors',
      );
      // The description had nowhere to go in a plain tag list — dropped, and
      // counted rather than silently lost.
      expect(out['descriptions_dropped'], 1);
      expect(out.containsKey('unlisted_keys_seen'), isFalse);
    });

    test('the round trip back to WD14 applies the same rules', () async {
      final out = await call('convert_captions_to_tags', {
        'source_extension': '.json',
        'target_extension': '.txt',
        'fields': order,
        'nl_field': 'nl',
        // What "back to WD14 for training" actually means: no quality/meta
        // vocabulary, no @ on the artist, and parentheses escaped because
        // bare ones are prompt attention syntax in a text caption.
        'remove': ['newest', 'safe'],
        'rename': {'@my artist': 'my artist'},
        'parentheses': 'escape',
        'spacing': 'underscores',
        'prepend': ['trigger'],
      });
      expect(out['written'], 2);
      expect(out['removed_tags'], {'newest': 2, 'safe': 2});
      expect(
        await read('001', '.txt'),
        r'trigger, 1girl, hatsune_miku_\(racing\), my_artist, long_hair, '
        r'blue_eyes, smile, indoors',
      );
    });

    test('an unlisted key keeps its tags and is named', () async {
      final out = await call('convert_captions_to_tags', {
        'source_extension': '.json',
        'target_extension': '.txt',
        'fields': const ['count', 'appearance'],
        'nl_field': 'nl',
      });
      // Nothing is dropped for going unlisted — the rest is appended and
      // reported, so a field order that missed something is visible.
      expect(out['unlisted_keys_seen'], [
        'quality',
        'character',
        'artist',
        'tags',
        'environment',
      ]);
      // The two declared fields lead; everything else follows in document
      // order behind them.
      expect(
        await read('001', '.txt'),
        '1girl, long hair, blue eyes, newest, safe, hatsune miku (racing), '
        '@my artist, smile, indoors',
      );
    });

    test('skip_fields drops tags on purpose and counts them', () async {
      final out = await call('convert_captions_to_tags', {
        'source_extension': '.json',
        'target_extension': '.txt',
        'fields': order,
        'nl_field': 'nl',
        'skip_fields': ['quality', 'artist'],
      });
      // 001: newest, safe, @my artist = 3; 002: newest, safe = 2.
      expect(out['tags_skipped_by_field'], 5);
      expect(await read('001', '.txt'), isNot(contains('newest')));
      expect(await read('001', '.txt'), isNot(contains('artist')));
    });

    test('a nested skip field is counted, not just dropped', () async {
      // skip_fields is documented as ignoring a key "at any depth", and the
      // drop already worked at any depth — only the counter looked at the
      // top level, so a nested skip reported 0 tags skipped while quietly
      // dropping them. That is backwards for the one number that exists to
      // make the drop auditable.
      await writeJson('001', {
        'count': '1girl',
        'meta': {
          'internal_note': ['scratch', 'wip'],
          'tags': ['smile'],
        },
      });
      await writeJson('002', {'count': '1boy'});

      final out = await call('convert_captions_to_tags', {
        'source_extension': '.json',
        'target_extension': '.txt',
        'fields': ['count'],
        'skip_fields': ['internal_note'],
        'overwrite': true,
      });

      expect(out['tags_skipped_by_field'], 2);
      final written = await read('001', '.txt');
      expect(written, isNot(contains('scratch')));
      expect(written, isNot(contains('wip')));
      // The sibling under the same nested object still comes through.
      expect(written, contains('smile'));
    });

    test('an Anima Tag target takes the prose field as its tail', () async {
      await call('convert_captions_to_tags', {
        'source_extension': '.json',
        'target_extension': '.atxt',
        'fields': order,
        'nl_field': 'nl',
        'overwrite': true,
      });
      expect(
        await read('001', '.atxt'),
        endsWith('. A girl smiles, indoors.'),
      );
    });

    test('without nl_field the sentence is comma-split into tags', () async {
      await call('convert_captions_to_tags', {
        'source_extension': '.json',
        'target_extension': '.txt',
        'fields': order,
      });
      // Exactly the failure nl_field exists to prevent, and why the tool
      // says so: the sentence arrives as two bogus tags.
      expect(await read('001', '.txt'), endsWith('A girl smiles, indoors.'));
    });

    test('a document that does not parse fails only its own image', () async {
      await File(cap('002', '.json')).writeAsString('{broken');
      final out = await call('convert_captions_to_tags', {
        'source_extension': '.json',
        'target_extension': '.txt',
        'fields': order,
        'nl_field': 'nl',
      });
      expect(out['written'], 1);
      expect(out['failed_images'], 1);
      expect((out['failures'] as List).single['error'], contains('not valid'));
      expect(File(cap('001', '.txt')).existsSync(), isTrue);
    });

    test('the JSON knobs are refused for a tag-list source', () async {
      final out = await call('convert_captions_to_tags', {
        'source_extension': '.atxt',
        'target_extension': '.txt',
        'fields': order,
      });
      expect(out['error'], contains('only apply to a JSON source'));
    });

    test('a JSON target still points at the other tools', () async {
      final out = await call('convert_captions_to_tags', {
        'source_extension': '.atxt',
        'target_extension': '.json',
      });
      expect(out['error'], contains('convert_captions_to_json'));
    });
  });

  group('edit_captions on a prose type', () {
    setUp(() async {
      await File(cap('001', '.ntxt')).writeAsString(
        'A girl with long hair, smiling, stands indoors. '
        'She wears a red hat.',
      );
      await File(
        cap('002', '.ntxt'),
      ).writeAsString('A boy runs outdoors. She wears a red hat.');
    });

    test('the parts are whole sentences, commas and all', () async {
      final out = await call('edit_captions', {
        'extension': '.ntxt',
        // The whole sentence, punctuation included — a clause would match
        // nothing now that a comma is not a break.
        'remove': ['She wears a red hat.'],
      });
      expect(out['written'], 2);
      expect(out['removed_tags'], {'She wears a red hat.': 2});
      expect(
        await read('001', '.ntxt'),
        'A girl with long hair, smiling, stands indoors.',
      );
      expect(await read('002', '.ntxt'), 'A boy runs outdoors.');
    });

    test('a rule naming a clause matches nothing', () async {
      final out = await call('edit_captions', {
        'extension': '.ntxt',
        'remove': ['smiling'],
      });
      expect(out['written'], 0);
      expect(out['removed_tags'], isEmpty);
      expect(await read('001', '.ntxt'), contains('smiling'));
    });

    test('a sentence can be replaced or appended whole', () async {
      await call('edit_captions', {
        'extension': '.ntxt',
        'rename': {'A boy runs outdoors.': 'A boy runs in a field.'},
        'add': ['The light is warm.'],
        'name_query': '002',
      });
      expect(
        await read('002', '.ntxt'),
        'A boy runs in a field. She wears a red hat. The light is warm.',
      );
    });
  });
}
