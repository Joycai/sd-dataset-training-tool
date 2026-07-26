import 'dart:convert';

import 'package:dataset_training_tool/services/llm/sse.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<List<String>> decode(List<List<int>> chunks) =>
      sseDataEvents(Stream.fromIterable(chunks)).toList();

  test('splits events on blank lines and strips the data prefix', () async {
    final events = await decode([
      utf8.encode('data: {"a":1}\n\ndata: {"b":2}\n\n'),
    ]);
    expect(events, ['{"a":1}', '{"b":2}']);
  });

  test('handles payload split across network chunks', () async {
    final events = await decode([
      utf8.encode('data: {"a"'),
      utf8.encode(':1}\n\n'),
    ]);
    expect(events, ['{"a":1}']);
  });

  test('handles multi-byte utf8 split across chunks', () async {
    final bytes = utf8.encode('data: {"t":"汉字"}\n\n');
    // Split inside the first CJK character's 3-byte sequence.
    final cut = bytes.indexOf(0xE6) + 1;
    final events = await decode([
      bytes.sublist(0, cut),
      bytes.sublist(cut),
    ]);
    expect(events, ['{"t":"汉字"}']);
  });

  test('joins multi-line data fields with newline', () async {
    final events = await decode([
      utf8.encode('data: line1\ndata: line2\n\n'),
    ]);
    expect(events, ['line1\nline2']);
  });

  test('ignores comments and event/id lines, passes [DONE] through',
      () async {
    final events = await decode([
      utf8.encode(': keep-alive\n\n'
          'event: message_start\ndata: {"x":1}\n\n'
          'data: [DONE]\n\n'),
    ]);
    expect(events, ['{"x":1}', '[DONE]']);
  });

  test('flushes a trailing event without final blank line', () async {
    final events = await decode([utf8.encode('data: tail')]);
    expect(events, ['tail']);
  });
}
