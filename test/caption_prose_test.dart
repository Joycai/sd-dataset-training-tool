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
    test('segments by , and . keeping the punctuation', () {
      expect(
        parseSentenceText('A girl smiling. She has long hair, and a hat.'),
        ['A girl smiling.', 'She has long hair,', 'and a hat.'],
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

    test('splits full-width punctuation without needing spaces', () {
      expect(parseSentenceText('她是女孩，戴着帽子。在雨中。'), ['她是女孩，', '戴着帽子。', '在雨中。']);
    });

    test('exact duplicate segments collapse', () {
      expect(parseSentenceText('A cat. A cat. A dog.'), ['A cat.', 'A dog.']);
    });
  });

  group('joinCaptionText', () {
    test('prose join round-trips a parsed caption', () {
      const text = 'A girl smiling. She has long hair, and a hat.';
      expect(joinCaptionText(parseSentenceText(text), prose: true), text);
    });

    test('no space is inserted after full-width punctuation', () {
      const text = '她是女孩，戴着帽子。在雨中。';
      expect(joinCaptionText(parseSentenceText(text), prose: true), text);
    });

    test('tag mode keeps the comma join', () {
      expect(joinCaptionText(['a', 'b']), 'a, b');
    });
  });

  test('CaptionType.prose survives the JSON round trip and sanitize', () {
    final decoded = decodeCaptionTypes(
      encodeCaptionTypes([
        const CaptionType(id: 'nlp', extension: '.ntxt', prose: true),
      ]),
    );
    expect(decoded.single.prose, isTrue);
    final sanitized = sanitizeCaptionTypes(decoded);
    expect(sanitized.last.prose, isTrue);
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
        captionProse: true,
      );
      expect(dataset.captionProse, isTrue);
      expect(dataset.tagsOf(p.join(tempDir.path, '001.png')), [
        'A girl smiling.',
        'She wears a red hat,',
        'outdoors.',
      ]);
    });

    test('editor chips are sentences and edits keep the punctuation', () async {
      final session = EditorSession();
      addTearDown(session.dispose);
      session.autoSaveEnabled = false;
      await session.load(
        File(p.join(tempDir.path, '001.png')),
        '.ntxt',
        prose: true,
      );
      expect(session.tags, [
        'A girl smiling.',
        'She wears a red hat,',
        'outdoors.',
      ]);

      session.removeTag('She wears a red hat,');
      expect(session.captionController.text, 'A girl smiling. outdoors.');

      await session.save();
      expect(
        await File(p.join(tempDir.path, '001.ntxt')).readAsString(),
        'A girl smiling. outdoors.',
      );
    });
  });
}
