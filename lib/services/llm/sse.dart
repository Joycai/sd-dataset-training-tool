/// Minimal Server-Sent-Events decoding shared by both LLM clients.
///
/// Pure Dart. Decodes a byte stream into the `data:` payload strings of each
/// event; `event:`/`id:`/comment lines are ignored (the JSON payloads of both
/// OpenAI-compatible and Anthropic streams are self-describing).
library;

import 'dart:convert';

/// Transforms a raw HTTP byte stream into one string per SSE event: the
/// concatenated `data:` payload. Multi-line `data:` fields are joined with
/// `\n` per the SSE spec. Empty events are skipped.
///
/// UTF-8 decoding happens before line splitting, so multi-byte characters
/// split across network chunks are handled correctly.
Stream<String> sseDataEvents(Stream<List<int>> bytes) async* {
  final lines = bytes
      .transform(const Utf8Decoder(allowMalformed: true))
      .transform(const LineSplitter());
  final data = <String>[];
  await for (final line in lines) {
    if (line.isEmpty) {
      // Blank line = event boundary.
      if (data.isNotEmpty) {
        yield data.join('\n');
        data.clear();
      }
      continue;
    }
    if (line.startsWith(':')) continue; // comment / keep-alive
    if (line.startsWith('data:')) {
      var payload = line.substring(5);
      if (payload.startsWith(' ')) payload = payload.substring(1);
      data.add(payload);
    }
    // event:/id:/retry: lines are intentionally ignored.
  }
  if (data.isNotEmpty) yield data.join('\n');
}
