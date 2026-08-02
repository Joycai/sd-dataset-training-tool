import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:dataset_training_tool/models/caption_type.dart';
import 'package:dataset_training_tool/state/dataset_state.dart';
import 'package:dataset_training_tool/state/editor_session.dart';
import 'package:dataset_training_tool/state/tag_ops.dart';
import 'package:dataset_training_tool/utils/tag_text.dart';

// 1x1 transparent PNG.
const _pngBytes = [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x62, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
];

/// A caption in the shape the standard prescribes.
const _sample =
    'newest, safe, 1girl, @my artist, long hair, smile, indoors. '
    'A graceful girl smiles warmly, seated in a serene room.';

void main() {
  group('parseAnimaTagText', () {
    test('splits tags from the trailing sentence', () {
      expect(parseAnimaTagText(_sample), [
        'newest',
        'safe',
        '1girl',
        '@my artist',
        'long hair',
        'smile',
        'indoors',
        '. A graceful girl smiles warmly, seated in a serene room.',
      ]);
    });

    test('the sentence keeps its own commas and periods', () {
      final parts = parseAnimaTagText('1girl. She smiles. She waves, twice.');
      expect(parts, ['1girl', '. She smiles. She waves, twice.']);
    });

    test('a caption without a sentence is a plain tag list', () {
      expect(parseAnimaTagText('1girl, smile'), ['1girl', 'smile']);
    });

    test('a trailing period alone adds no sentence', () {
      expect(parseAnimaTagText('1girl, smile.'), ['1girl', 'smile']);
    });

    test('decimals and dotted tags stay inside the tag list', () {
      expect(parseAnimaTagText('1girl, no.7, v1.5, smile'), [
        '1girl',
        'no.7',
        'v1.5',
        'smile',
      ]);
    });

    test('a sentence-only caption parses as the tail', () {
      expect(parseAnimaTagText('. Just a description.'), [
        '. Just a description.',
      ]);
    });
  });

  group('joinCaptionText for Anima Tag', () {
    String join(List<String> parts) =>
        joinCaptionText(parts, format: CaptionFormat.animaTag);

    test('round-trips a parsed caption', () {
      expect(join(parseAnimaTagText(_sample)), _sample);
    });

    test('the sentence is re-appended last wherever it sat', () {
      expect(
        join(['1girl', '. She smiles.', 'indoors']),
        '1girl, indoors. She smiles.',
      );
    });

    test('a tag list with no sentence joins like WD14', () {
      expect(join(['1girl', 'smile']), '1girl, smile');
    });
  });

  test('splitAnimaParts separates the tail from the tags', () {
    final split = splitAnimaParts(parseAnimaTagText(_sample));
    expect(split.tags, isNot(contains(anyElement(startsWith('. ')))));
    expect(split.tags.last, 'indoors');
    expect(split.nl, 'A graceful girl smiles warmly, seated in a serene room.');
  });

  test('the animaTag format survives the caption type round trip', () {
    final decoded = decodeCaptionTypes(
      encodeCaptionTypes([
        const CaptionType(
          id: 'anima',
          extension: '.atxt',
          format: CaptionFormat.animaTag,
        ),
      ]),
    );
    expect(decoded.single.format, CaptionFormat.animaTag);
    expect(sanitizeCaptionTypes(decoded).last.format, CaptionFormat.animaTag);
    expect(CaptionFormat.animaTag.isTagList, isTrue);
    expect(CaptionFormat.prose.isTagList, isFalse);
  });

  group('Anima Tag mode end to end', () {
    late Directory tempDir;
    late DatasetState dataset;

    String img(String name) => p.join(tempDir.path, '$name.png');
    String cap(String name) => p.join(tempDir.path, '$name.atxt');
    Future<String> readCap(String name) => File(cap(name)).readAsString();

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('caption_anima_test_');
      for (final name in ['001', '002']) {
        await File(img(name)).writeAsBytes(_pngBytes);
      }
      await File(cap('001')).writeAsString(_sample);
      await File(cap('002')).writeAsString('1girl, smile, indoors');

      dataset = DatasetState();
      addTearDown(dataset.dispose);
      await dataset.scan(
        directoryPath: tempDir.path,
        recursive: false,
        captionExtension: '.atxt',
        captionFormat: CaptionFormat.animaTag,
      );
    });

    tearDown(() => tempDir.delete(recursive: true));

    test('the dataset index holds the tags plus the tail', () {
      expect(dataset.captionFormat, CaptionFormat.animaTag);
      expect(dataset.tagsOf(img('001')).take(3), ['newest', 'safe', '1girl']);
      expect(dataset.tagsOf(img('001')).last, startsWith('. A graceful girl'));
    });

    test('a batch sort never moves the sentence out of last place', () async {
      final ops = TagOps(dataset: dataset);
      addTearDown(ops.dispose);
      // "unlisted: start" is the setting that would drag the tail to the
      // front if it were bucketed as an ordinary tag.
      final result = await ops.reorderEverywhere(
        ['1girl', 'newest'],
        unlistedFirst: true,
        label: 'test sort',
      );
      expect(result.failed, 0);
      expect(
        await readCap('001'),
        endsWith('. A graceful girl smiles warmly, seated in a serene room.'),
      );
      expect(await readCap('001'), startsWith('safe, @my artist'));
    });

    test('adding tags at the end lands before the sentence', () async {
      final ops = TagOps(dataset: dataset);
      addTearDown(ops.dispose);
      final result = await ops.addEverywhere('outdoors', label: 'test add');
      expect(result.failed, 0);
      expect(
        await readCap('001'),
        'newest, safe, 1girl, @my artist, long hair, smile, indoors, '
        'outdoors. A graceful girl smiles warmly, seated in a serene room.',
      );
      // A caption with no sentence is untouched by the tail handling.
      expect(await readCap('002'), '1girl, smile, indoors, outdoors');
    });

    test('replacing a tag cannot reach into the sentence', () async {
      final ops = TagOps(dataset: dataset);
      addTearDown(ops.dispose);
      await ops.replaceEverywhere('smile', 'grin', label: 'test replace');
      final text = await readCap('001');
      expect(text, contains('grin, indoors.'));
      expect(text, endsWith('smiles warmly, seated in a serene room.'));
    });

    test('the editor appends new tags before the sentence', () async {
      final session = EditorSession();
      addTearDown(session.dispose);
      session.autoSaveEnabled = false;
      await session.load(
        File(img('001')),
        '.atxt',
        format: CaptionFormat.animaTag,
      );
      expect(session.tagsEditable, isTrue);

      session.applyTag('outdoors');
      expect(
        session.captionController.text,
        endsWith(
          'indoors, outdoors. '
          'A graceful girl smiles warmly, seated in a serene room.',
        ),
      );
      expect(session.tags.last, startsWith('. A graceful girl'));
    });

    test('editing the sentence chip keeps it a sentence', () async {
      final session = EditorSession();
      addTearDown(session.dispose);
      session.autoSaveEnabled = false;
      await session.load(
        File(img('001')),
        '.atxt',
        format: CaptionFormat.animaTag,
      );
      final index = session.tags.length - 1;
      // Typed without the marker and with a comma in it: the old text would
      // have come back as two tags.
      session.replaceTagAt(index, 'A girl sits, smiling.');
      expect(session.tags.last, '. A girl sits, smiling.');
      expect(
        session.captionController.text,
        'newest, safe, 1girl, @my artist, long hair, smile, indoors. '
        'A girl sits, smiling.',
      );
    });
  });
}
