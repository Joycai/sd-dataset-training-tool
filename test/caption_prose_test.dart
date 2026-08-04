import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:dataset_training_tool/models/caption_type.dart';
import 'package:dataset_training_tool/state/dataset_state.dart';
import 'package:dataset_training_tool/state/editor_session.dart';
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

void main() {
  group('parseSentenceText', () {
    test('segments by sentence, keeping the punctuation', () {
      expect(
        parseSentenceText('A girl smiling. She has long hair, and a hat.'),
        ['A girl smiling.', 'She has long hair, and a hat.'],
      );
    });

    test('commas inside a sentence are not breaks', () {
      // What a captioning model actually writes. Breaking here would cut it
      // into clauses — the tag grammar wearing a different name.
      expect(
        parseSentenceText('A girl with long hair, smiling, stands indoors.'),
        ['A girl with long hair, smiling, stands indoors.'],
      );
    });

    test('does not split decimals or dotted abbreviations', () {
      expect(parseSentenceText('She is 1.5 meters tall. Photo no.7 shows it'), [
        'She is 1.5 meters tall.',
        'Photo no.7 shows it',
      ]);
    });

    test('a punctuation run stays one break', () {
      expect(parseSentenceText('Wait... she smiles.'), [
        'Wait...',
        'she smiles.',
      ]);
    });

    test('splits full-width 。 without needing spaces, but not ，', () {
      expect(parseSentenceText('她是女孩，戴着帽子。在雨中。'), ['她是女孩，戴着帽子。', '在雨中。']);
    });

    test('a repeated sentence is kept, not collapsed', () {
      // Two identical tags on one image are one tag; two identical sentences
      // in a paragraph are two sentences. Collapsing them made the segment
      // view a lossy round trip.
      expect(parseSentenceText('A cat. A cat. A dog.'), [
        'A cat.',
        'A cat.',
        'A dog.',
      ]);
      expect(
        joinCaptionText(
          parseSentenceText('A cat. A cat. A dog.'),
          format: CaptionFormat.prose,
        ),
        'A cat. A cat. A dog.',
      );
    });
  });

  group('joinCaptionText', () {
    test('prose join round-trips a parsed caption', () {
      const text = 'A girl smiling. She has long hair, and a hat.';
      expect(
        joinCaptionText(parseSentenceText(text), format: CaptionFormat.prose),
        text,
      );
    });

    test('no space is inserted after full-width punctuation', () {
      const text = '她是女孩，戴着帽子。在雨中。';
      expect(
        joinCaptionText(parseSentenceText(text), format: CaptionFormat.prose),
        text,
      );
    });

    test('tag mode keeps the comma join', () {
      expect(joinCaptionText(['a', 'b']), 'a, b');
    });
  });

  test('CaptionType.format survives the JSON round trip and sanitize', () {
    final decoded = decodeCaptionTypes(
      encodeCaptionTypes([
        const CaptionType(
          id: 'nlp',
          extension: '.ntxt',
          format: CaptionFormat.prose,
        ),
      ]),
    );
    expect(decoded.single.format, CaptionFormat.prose);
    final sanitized = sanitizeCaptionTypes(decoded);
    expect(sanitized.last.format, CaptionFormat.prose);
  });

  test('legacy prose flag decodes into the format enum', () {
    final decoded = decodeCaptionTypes(
      '[{"id": "nlp", "extension": ".ntxt", "prose": true}, '
      '{"id": "wd", "extension": ".txt", "prose": false}]',
    );
    expect(decoded.first.format, CaptionFormat.prose);
    expect(decoded.last.format, CaptionFormat.tags);
  });

  group('prose mode end to end', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('caption_prose_test_');
      await File(p.join(tempDir.path, '001.png')).writeAsBytes(_pngBytes);
      await File(
        p.join(tempDir.path, '001.ntxt'),
      ).writeAsString('A girl smiling. She wears a red hat, outdoors.');
    });

    tearDown(() => tempDir.delete(recursive: true));

    test('the dataset index holds sentence segments', () async {
      final dataset = DatasetState();
      addTearDown(dataset.dispose);
      await dataset.scan(
        directoryPath: tempDir.path,
        recursive: false,
        captionExtension: '.ntxt',
        captionFormat: CaptionFormat.prose,
      );
      expect(dataset.captionFormat, CaptionFormat.prose);
      expect(dataset.tagsOf(p.join(tempDir.path, '001.png')), [
        'A girl smiling.',
        'She wears a red hat, outdoors.',
      ]);
    });

    test('editor chips are sentences and edits keep the punctuation', () async {
      final session = EditorSession();
      addTearDown(session.dispose);
      session.autoSaveEnabled = false;
      await session.load(
        File(p.join(tempDir.path, '001.png')),
        '.ntxt',
        format: CaptionFormat.prose,
      );
      expect(session.tags, [
        'A girl smiling.',
        'She wears a red hat, outdoors.',
      ]);

      session.removeTag('She wears a red hat, outdoors.');
      expect(session.captionController.text, 'A girl smiling.');

      await session.save();
      expect(
        await File(p.join(tempDir.path, '001.ntxt')).readAsString(),
        'A girl smiling.',
      );
    });
  });
}
