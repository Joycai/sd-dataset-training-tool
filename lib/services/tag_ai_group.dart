/// One-shot "sort these tags into groups" through the configured LLM backend.
///
/// Same shape as [translateTagWithLlm] and for the same reason: this is a
/// lookup, not a conversation. It carries no tools and no dataset context, so
/// it cannot touch a caption file — the worst it can do is propose a bad home
/// for a tag, which the user accepts or rejects one row at a time.
///
/// It exists because the ungrouped bucket is where a tag library goes to die:
/// tagging a few dozen images adds a hundred tags nobody will ever file by
/// hand, and an unfiled library is one long alphabetical wall.
library;

import 'dart:convert';

import '../models/llm_models.dart';
import '../utils/tag_text.dart';
import 'llm/anthropic_client.dart';
import 'llm/llm_client.dart';
import 'llm/openai_compat_client.dart';

/// A proposed home for one tag.
class TagGroupSuggestion {
  const TagGroupSuggestion({required this.tag, required this.group});

  /// The tag, in the library's own spelling.
  final String tag;

  /// Target group name. Matched against existing groups by name; anything
  /// else is a group the model invented and the caller has to create.
  final String group;
}

/// A model asked to file two hundred tags in one answer runs out of output
/// tokens halfway through and the whole reply is lost. Batching costs a few
/// more requests and makes a partial failure cost one batch.
const int _defaultBatchSize = 60;

/// Asks [profile]'s model where each of [tags] belongs.
///
/// [existingGroups] are offered as the preferred targets — a suggestion that
/// invents "Clothing" beside the user's "服装" is worse than useless.
/// [glosses] carries whatever translations the library already has, which is
/// what lets a model reason about tags it does not recognise.
///
/// Returns one suggestion per tag it could place, in request order; tags the
/// model skipped or answered with an empty group simply do not appear.
/// [onProgress] reports completed batches. Throws [LlmException] on transport
/// failure; a batch that comes back unparseable is skipped, not fatal, so one
/// bad answer does not discard the rest.
Future<List<TagGroupSuggestion>> suggestTagGroupsWithLlm({
  required LlmProviderProfile profile,
  required List<String> tags,
  required List<String> existingGroups,
  Map<String, String> glosses = const {},
  String languageCode = 'en',
  int batchSize = _defaultBatchSize,
  LlmClient? client,
  void Function(int done, int total)? onProgress,
}) async {
  if (tags.isEmpty) return const [];
  final llm =
      client ??
      (profile.kind == LlmApiKind.anthropic
          ? AnthropicClient()
          : OpenAiCompatClient());
  final out = <TagGroupSuggestion>[];
  try {
    for (var start = 0; start < tags.length; start += batchSize) {
      final batch = tags.sublist(
        start,
        (start + batchSize).clamp(0, tags.length),
      );
      final answer = await _ask(
        llm: llm,
        profile: profile,
        batch: batch,
        existingGroups: existingGroups,
        glosses: glosses,
        languageCode: languageCode,
      );
      out.addAll(_parse(answer, batch));
      onProgress?.call(
        (start + batch.length).clamp(0, tags.length),
        tags.length,
      );
    }
  } finally {
    // Only a client this call created: an injected one belongs to its owner.
    if (client == null) llm.dispose();
  }
  return out;
}

Future<String> _ask({
  required LlmClient llm,
  required LlmProviderProfile profile,
  required List<String> batch,
  required List<String> existingGroups,
  required Map<String, String> glosses,
  required String languageCode,
}) async {
  final buffer = StringBuffer();
  final stream = llm.chat(
    profile: profile,
    messages: [
      ChatMessage.system(
        'You file danbooru image tags into categories for a tagging '
        'workbench. Answer with a JSON array and nothing else — no prose, no '
        'markdown fence. Each element is {"tag": "<the tag, copied '
        'verbatim>", "group": "<category name>"}.\n'
        'Rules:\n'
        '- Reuse a category from the existing list whenever the tag plausibly '
        'belongs there. Only invent a category when several tags in this '
        'batch need it, and name it in the same language as the existing '
        'ones (or in the target language below when the list is empty).\n'
        '- Copy tags exactly as given, including underscores and escapes.\n'
        '- Omit a tag entirely rather than guessing wildly.\n'
        '- Keep the number of distinct categories small.',
      ),
      ChatMessage.user(
        'Target language for new category names (IETF code): $languageCode\n'
        'Existing categories: '
        '${existingGroups.isEmpty ? '(none yet)' : existingGroups.join(', ')}\n'
        'Tags:\n'
        '${[for (final tag in batch) glosses[tag] == null ? '- $tag' : '- $tag  (${glosses[tag]})'].join('\n')}',
      ),
    ],
  );
  await for (final event in stream) {
    if (event is TextDelta) buffer.write(event.text);
  }
  return buffer.toString();
}

/// Reads the model's answer back into suggestions, restricted to [batch].
///
/// Lenient on the envelope (a fenced block, a leading sentence, an object
/// wrapping the array) and strict on the content: a tag that was not asked
/// about is dropped rather than added to the library through the back door.
List<TagGroupSuggestion> _parse(String answer, List<String> batch) {
  final decoded = _decodeArray(answer);
  if (decoded == null) return const [];
  // Folded lookup: models routinely answer `long hair` for `long_hair`.
  final byKey = {for (final tag in batch) tagLookupKey(tag): tag};
  final seen = <String>{};
  final out = <TagGroupSuggestion>[];
  for (final item in decoded) {
    if (item is! Map) continue;
    final rawTag = (item['tag'] as Object?)?.toString().trim() ?? '';
    final group = (item['group'] as Object?)?.toString().trim() ?? '';
    if (rawTag.isEmpty || group.isEmpty) continue;
    final tag = byKey[tagLookupKey(rawTag)];
    if (tag == null || !seen.add(tag)) continue;
    out.add(TagGroupSuggestion(tag: tag, group: group));
  }
  // Request order, not answer order: the review list should read like the
  // ungrouped section it came from.
  final rank = {for (var i = 0; i < batch.length; i++) batch[i]: i};
  out.sort((a, b) => rank[a.tag]!.compareTo(rank[b.tag]!));
  return out;
}

List<dynamic>? _decodeArray(String answer) {
  final start = answer.indexOf('[');
  final end = answer.lastIndexOf(']');
  if (start < 0 || end <= start) return null;
  try {
    final decoded = jsonDecode(answer.substring(start, end + 1));
    return decoded is List ? decoded : null;
  } on FormatException {
    return null;
  }
}
