import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:dataset_training_tool/models/caption_type.dart';
import 'package:dataset_training_tool/state/dataset_state.dart';
import 'package:dataset_training_tool/state/editor_session.dart';
import 'package:dataset_training_tool/state/tag_ops.dart';
import 'package:dataset_training_tool/utils/tag_text.dart';
import 'package:dataset_training_tool/widgets/json_caption_view.dart';

// 1x1 transparent PNG.
const _pngBytes = [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x62, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
];

const _animaJson =
    '{"count": "1girl", "character": "trigger", '
    '"appearance": ["blue eyes", "long hair"], "tags": [], "nl": ""}';

void main() {
  group('parseJsonCaptionTags', () {
    test('collects string leaves in document order, de-duplicated', () {
      expect(parseJsonCaptionTags(_animaJson), [
        '1girl',
        'trigger',
        'blue eyes',
        'long hair',
      ]);
    });

    test('comma-separated strings split by the tag grammar', () {
      expect(parseJsonCaptionTags('{"tags": "a, b", "more": ["b", "c"]}'), [
        'a',
        'b',
        'c',
      ]);
    });

    test('unparseable or empty text yields no tags', () {
      expect(parseJsonCaptionTags('{"tags": [,]}'), isEmpty);
      expect(parseJsonCaptionTags('   '), isEmpty);
    });

    test('parseCaptionText routes the json format here', () {
      expect(
        parseCaptionText('{"a": "x"}', format: CaptionFormat.json),
        ['x'],
      );
    });
  });

  group('jsonHighlightSpans', () {
    const keyStyle = TextStyle(color: Color(0xFF0000FF));
    const stringStyle = TextStyle(color: Color(0xFF00FF00));
    const literalStyle = TextStyle(color: Color(0xFFFF0000));
    const punctStyle = TextStyle(color: Color(0xFF888888));

    List<InlineSpan> spans(dynamic value) => jsonHighlightSpans(
      value,
      keyStyle: keyStyle,
      stringStyle: stringStyle,
      literalStyle: literalStyle,
      punctStyle: punctStyle,
    );

    String textOf(List<InlineSpan> spans) =>
        spans.map((s) => (s as TextSpan).text).join();

    test('pretty-prints objects one key per line, arrays inline', () {
      expect(
        textOf(
          spans({
            'a': ['x', 'y'],
            'n': 1,
            'empty': <String>[],
          }),
        ),
        '{\n'
        '  "a": ["x", "y"],\n'
        '  "n": 1,\n'
        '  "empty": []\n'
        '}',
      );
    });

    test('nested objects indent one level deeper', () {
      expect(
        textOf(
          spans({
            'outer': {'inner': true},
          }),
        ),
        '{\n'
        '  "outer": {\n'
        '    "inner": true\n'
        '  }\n'
        '}',
      );
    });

    test('keys, strings and literals carry their own styles', () {
      final result = spans({'k': 'v', 'n': null}).cast<TextSpan>();
      TextSpan byText(String text) =>
          result.firstWhere((s) => s.text == text);
      expect(byText('"k"').style, keyStyle);
      expect(byText('"v"').style, stringStyle);
      expect(byText('null').style, literalStyle);
      expect(byText(': ').style, punctStyle);
    });

    test('string tokens re-escape special characters', () {
      expect(textOf(spans('a "quote"')), r'"a \"quote\""');
    });
  });

  group('json format end to end', () {
    late Directory tempDir;

    String img(String name) => p.join(tempDir.path, '$name.png');

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('caption_json_test_');
      await File(img('001')).writeAsBytes(_pngBytes);
      await File(p.join(tempDir.path, '001.json')).writeAsString(_animaJson);
    });

    tearDown(() => tempDir.delete(recursive: true));

    Future<DatasetState> scan() async {
      final dataset = DatasetState();
      addTearDown(dataset.dispose);
      await dataset.scan(
        directoryPath: tempDir.path,
        recursive: false,
        captionExtension: '.json',
        captionFormat: CaptionFormat.json,
      );
      return dataset;
    }

    test('the dataset index holds the extracted strings', () async {
      final dataset = await scan();
      expect(dataset.captionFormat, CaptionFormat.json);
      expect(dataset.hasCaption(img('001')), isTrue);
      expect(dataset.tagsOf(img('001')), [
        '1girl',
        'trigger',
        'blue eyes',
        'long hair',
      ]);
    });

    test('tag-level batch rewrites refuse to run and leave the file alone',
        () async {
      final dataset = await scan();
      final tagOps = TagOps(dataset: dataset);
      addTearDown(tagOps.dispose);
      final result = await tagOps.deleteEverywhere('1girl', label: 'del');
      expect(result.changed, 0);
      expect(result.failed, 1);
      expect(result.failures.single.error, contains('JSON'));
      expect(
        await File(p.join(tempDir.path, '001.json')).readAsString(),
        _animaJson,
      );
      expect(tagOps.canUndo, isFalse);
    });

    test('editor session disables tag edits but still saves text edits',
        () async {
      final session = EditorSession();
      addTearDown(session.dispose);
      session.autoSaveEnabled = false;
      await session.load(
        File(img('001')),
        '.json',
        format: CaptionFormat.json,
      );
      expect(session.tagsEditable, isFalse);
      expect(session.tags, contains('blue eyes'));

      // Tag mutators bail: the document cannot be rebuilt from a tag list.
      session.removeTag('blue eyes');
      session.addTagsFromInput('new tag');
      session.applyTag('another');
      expect(session.captionController.text, _animaJson);
      expect(session.tags, contains('blue eyes'));

      // Raw text edits are the JSON editing path and still save.
      const edited = '{"count": "1girl", "tags": ["smile"]}';
      session.captionController.text = edited;
      await session.save();
      expect(
        await File(p.join(tempDir.path, '001.json')).readAsString(),
        edited,
      );
      expect(session.tags, ['1girl', 'smile']);
    });
  });
}
