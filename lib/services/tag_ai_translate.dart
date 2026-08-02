/// One-shot tag translation through the configured LLM backend.
///
/// Deliberately not the assistant: the dictionary's "translate this one" button
/// is a lookup, not a conversation. It carries no tools, no history and no
/// dataset context, so it cannot touch a caption file, and the worst it can do
/// is put a wrong word in a field the user has not saved yet.
///
/// Bulk translation stays with the assistant — `write_tag_translations` exists
/// precisely because a few hundred tags must not become a few hundred requests.
library;

import 'dart:convert';

import '../models/llm_models.dart';
import 'llm/anthropic_client.dart';
import 'llm/llm_client.dart';
import 'llm/openai_compat_client.dart';

/// A translation long enough to be prose is not a gloss — it is the model
/// explaining itself, and it would render as a paragraph beside a tag chip.
const _maxGlossLength = 60;

/// Asks [profile]'s model for a short gloss of [tag] in [languageCode].
///
/// [note] is whatever context the dictionary already has — a danbooru wiki
/// excerpt, usually — which is what turns a guess at an opaque tag into an
/// answer. [client] is injectable for tests.
///
/// Returns the gloss with no surrounding punctuation. Throws [LlmException] on
/// transport failure, and when the model answers with nothing usable.
Future<String> translateTagWithLlm({
  required LlmProviderProfile profile,
  required String tag,
  required String languageCode,
  String? note,
  LlmClient? client,
}) async {
  final llm =
      client ??
      (profile.kind == LlmApiKind.anthropic
          ? AnthropicClient()
          : OpenAiCompatClient());
  final buffer = StringBuffer();
  try {
    final stream = llm.chat(
      profile: profile,
      messages: [
        ChatMessage.system(
          'You translate danbooru image tags into short display labels. '
          'Answer with the label only: no quotes, no explanation, no '
          'punctuation, no romanisation in parentheses. Keep it under '
          '$_maxGlossLength characters. If you do not know the tag, answer '
          'with the single word UNKNOWN.',
        ),
        ChatMessage.user(
          'Target language (IETF code): $languageCode\n'
          'Tag: $tag'
          '${note == null || note.trim().isEmpty ? '' : '\nContext: ${note.trim()}'}',
        ),
      ],
    );
    await for (final event in stream) {
      if (event is TextDelta) buffer.write(event.text);
    }
  } finally {
    // Only a client this call created: an injected one belongs to its owner.
    if (client == null) llm.dispose();
  }

  final gloss = _tidy(buffer.toString());
  if (gloss.isEmpty || gloss.toUpperCase() == 'UNKNOWN') {
    throw LlmException('the model returned no usable translation for "$tag"');
  }
  return gloss;
}

/// Reduces a model answer to the one line it should have been.
///
/// Models pad a one-word answer in predictable ways — a leading "Translation:",
/// surrounding quotes, a trailing period, an explanatory second line. Stripping
/// them here is worth more than a stricter prompt, because the failure is
/// invisible otherwise: the padding lands in the glossary and renders beside
/// every chip carrying the tag.
String _tidy(String raw) {
  var text = raw.trim();
  // First non-empty line only.
  for (final line in const LineSplitter().convert(text)) {
    if (line.trim().isNotEmpty) {
      text = line.trim();
      break;
    }
  }
  text = text.replaceFirst(RegExp(r'^[A-Za-z ]{0,20}[:：]\s*'), '');
  text = text.replaceAll(RegExp(r'''^["'“”「『]+|["'“”」』]+$'''), '');
  text = text.replaceAll(RegExp(r'[.。;；]+$'), '');
  text = text.trim();
  return text.length <= _maxGlossLength
      ? text
      : text.substring(0, _maxGlossLength).trim();
}
