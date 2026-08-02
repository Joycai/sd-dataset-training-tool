/// One-shot "sort these tags into groups" through the configured LLM backend.
///
/// A lookup, not a conversation: no history and no dataset context, so it
/// cannot touch a caption file — the worst it can do is propose a bad home for
/// a tag, which the user accepts or rejects one row at a time.
///
/// It exists because the ungrouped bucket is where a tag library goes to die:
/// tagging a few dozen images adds a hundred tags nobody will ever file by
/// hand, and an unfiled library is one long alphabetical wall.
///
/// **The answer comes back as a tool call, not as text.** Asking for "a JSON
/// array and nothing else" fails on exactly the backends this app is pointed
/// at: a reasoning model behind an OpenAI-compatible relay puts its reasoning
/// in `reasoning_content` and can spend the whole output budget there, so the
/// `content` this code reads arrives empty or truncated and the batch is lost.
/// Tool-call arguments ride a different field, are schema-shaped rather than
/// hand-parsed, and are the path the assistant already uses successfully
/// against those same relays. Text is still accepted as a fallback for
/// backends that answer in prose anyway.
library;

import 'dart:convert';
import 'dart:math' as math;

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

/// Why a batch produced nothing, so the caller can say so.
///
/// "The model had no suggestion" and "the model's answer was unreadable" look
/// identical from the outside — both leave an empty list — and telling the
/// user the first when the second happened is how this feature came to look
/// like it silently did nothing.
enum TagGroupBatchProblem {
  /// Neither a tool call nor any text came back. Almost always the output
  /// budget: a reasoning model spends `max_tokens` on thinking and never
  /// reaches the answer.
  emptyReply,

  /// The model ran out of output tokens mid-answer (`finish_reason: length`).
  /// Distinct from [emptyReply] because the remedy is the same but the user
  /// can see it happened rather than guessing.
  truncated,

  /// Something came back but no assignments could be recovered from it.
  unparseable,
}

/// The tool the model is asked to call with its answer.
///
/// One call carrying every placement, rather than one call per tag: a model
/// that has to emit forty separate tool calls will stop early, and the
/// arguments of a single call are one JSON document to validate.
const AgentToolSpec _fileTagsTool = AgentToolSpec(
  name: 'file_tags',
  description:
      'Report where each tag belongs. Call this exactly once, listing every '
      'tag you can confidently place. Omit tags you are unsure about rather '
      'than guessing.',
  parametersSchema: {
    'type': 'object',
    'properties': {
      'assignments': {
        'type': 'array',
        'description': 'One entry per tag you can place.',
        'items': {
          'type': 'object',
          'properties': {
            'tag': {
              'type': 'string',
              'description': 'The tag, copied verbatim from the list given.',
            },
            'group': {'type': 'string', 'description': 'Target category name.'},
          },
          'required': ['tag', 'group'],
        },
      },
    },
    'required': ['assignments'],
  },
);

/// A model asked to file two hundred tags in one answer runs out of output
/// tokens halfway through and the whole reply is lost. Batching costs a few
/// more requests and makes a partial failure cost one batch.
const int tagGroupBatchSize = 40;

/// Output-token floor for this call.
///
/// The profile's own budget is tuned for chat turns and defaults to 4096,
/// which a reasoning model can spend entirely on thinking — leaving an empty
/// answer that used to be reported as "no suggestions". One batch's answer
/// needs about a thousand tokens, so the floor is headroom for the thinking,
/// not for the answer.
const int _minOutputTokens = 8192;

/// How long this call tolerates silence on the stream.
///
/// The clients default to two minutes, which is tuned for a chat turn that
/// starts emitting text almost immediately. A reasoning model given a whole
/// batch to think about can be silent for longer than that before its first
/// token — and a relay that does not forward reasoning deltas makes the whole
/// thinking phase look like a dead connection. Timing out there reads as
/// "it just failed after a while" with nothing to act on.
const Duration _idleTimeout = Duration(minutes: 5);

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
/// bad answer does not discard the rest — but it is reported through
/// [onBatchProblem] so an empty result can say why it is empty.
Future<List<TagGroupSuggestion>> suggestTagGroupsWithLlm({
  required LlmProviderProfile profile,
  required List<String> tags,
  required List<String> existingGroups,
  Map<String, String> glosses = const {},
  String languageCode = 'en',
  int batchSize = tagGroupBatchSize,
  LlmClient? client,
  void Function(int done, int total)? onProgress,
  void Function(TagGroupBatchProblem problem, String reply)? onBatchProblem,
}) async {
  if (tags.isEmpty) return const [];
  // Annotated, not inferred: both concrete clients implement two interfaces,
  // so their least upper bound is no longer LlmClient.
  final LlmClient llm =
      client ??
      (profile.kind == LlmApiKind.anthropic
          ? AnthropicClient(idleTimeout: _idleTimeout)
          : OpenAiCompatClient(idleTimeout: _idleTimeout));
  final budgeted = profile.copyWith(
    maxOutputTokens: math.max(profile.maxOutputTokens, _minOutputTokens),
  );
  final out = <TagGroupSuggestion>[];
  try {
    for (var start = 0; start < tags.length; start += batchSize) {
      final batch = tags.sublist(
        start,
        (start + batchSize).clamp(0, tags.length),
      );
      final answer = await _ask(
        llm: llm,
        profile: budgeted,
        batch: batch,
        existingGroups: existingGroups,
        glosses: glosses,
        languageCode: languageCode,
      );
      final decoded = _decodeItems(answer);
      if (decoded == null) {
        onBatchProblem?.call(answer.problem, answer.forDisplay);
      } else {
        out.addAll(_parse(decoded, batch));
      }
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

/// One batch's raw answer: whichever of the two channels the model used, plus
/// why it produced nothing when it produced nothing.
class _Answer {
  const _Answer({
    required this.toolArguments,
    required this.text,
    required this.finishReason,
  });

  /// Arguments of the `file_tags` call, or empty when the model answered in
  /// text (or not at all).
  final String toolArguments;

  /// Assistant text. The fallback channel, and what a model that ignored the
  /// tool answers with.
  final String text;

  /// `finish_reason` from the stream: `length` means the budget ran out.
  final String finishReason;

  bool get isEmpty => toolArguments.trim().isEmpty && text.trim().isEmpty;

  TagGroupBatchProblem get problem {
    if (finishReason == 'length') return TagGroupBatchProblem.truncated;
    return isEmpty
        ? TagGroupBatchProblem.emptyReply
        : TagGroupBatchProblem.unparseable;
  }

  /// What to show a human debugging a bad batch.
  String get forDisplay => toolArguments.trim().isEmpty ? text : toolArguments;
}

Future<_Answer> _ask({
  required LlmClient llm,
  required LlmProviderProfile profile,
  required List<String> batch,
  required List<String> existingGroups,
  required Map<String, String> glosses,
  required String languageCode,
}) async {
  final buffer = StringBuffer();
  final arguments = StringBuffer();
  var finishReason = '';
  final stream = llm.chat(
    profile: profile,
    tools: const [_fileTagsTool],
    messages: [
      ChatMessage.system(
        'You file danbooru image tags into categories for a tagging '
        'workbench.\n'
        'Report your answer by calling the ${_fileTagsTool.name} tool exactly '
        'once. Do not write the assignments as prose or as a JSON code block '
        '— only the tool call is read.\n'
        'Rules:\n'
        '- Reuse a category from the existing list whenever the tag plausibly '
        'belongs there. Only invent a category when several tags in this '
        'batch need it, and name it in the same language as the existing '
        'ones (or in the target language below when the list is empty).\n'
        '- Copy tags exactly as given, including underscores and escapes.\n'
        '- Omit a tag entirely rather than guessing wildly.\n'
        '- Keep the number of distinct categories small.\n'
        '- Keep any thinking brief: the tool call is the deliverable and it '
        'must fit in the output budget.',
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
    switch (event) {
      case TextDelta(:final text):
        buffer.write(text);
      case ToolCallsReady(:final calls):
        for (final call in calls) {
          // Name-agnostic: a relay that renames or prefixes the call still
          // carries the arguments, and this request offers exactly one tool.
          arguments.write(call.argumentsJson);
        }
      case StreamDone(finishReason: final reason):
        if (reason.isNotEmpty) finishReason = reason;
    }
  }
  return _Answer(
    toolArguments: arguments.toString(),
    text: buffer.toString(),
    finishReason: finishReason,
  );
}

/// Reads decoded items back into suggestions, restricted to [batch].
///
/// Strict on the content: a tag that was not asked about is dropped rather
/// than added to the library through the back door.
List<TagGroupSuggestion> _parse(List<dynamic> decoded, List<String> batch) {
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

/// Recovers the answer's list of `{tag, group}` objects, or null when nothing
/// JSON-shaped is in there at all.
///
/// Lenient on the envelope, because the envelope is where this fails in the
/// wild. `indexOf('[') … lastIndexOf(']')` — the obvious version — breaks on
/// both of the two things models actually do: a prose lead-in that happens to
/// contain a bracket ("here are the categories [see below]:") swallows the
/// real array into an unparseable slice, and an answer cut off by the output
/// limit has no closing bracket to find. Neither is rare, and both used to
/// come back as a silent "the model had no suggestions".
///
/// So: try every balanced array in the text, and if none of them decodes,
/// fall back to harvesting the individual objects — which is what is left of
/// a truncated array, and is still most of the answer.
///
/// The tool-call channel is tried first and gets the same leniency. Its
/// arguments *should* be clean JSON, but a relay that streams them in pieces
/// or wraps them can produce the same envelope damage as prose, and there is
/// no reason to be strict on one channel and forgiving on the other.
List<dynamic>? _decodeItems(_Answer answer) {
  for (final channel in [answer.toolArguments, answer.text]) {
    if (channel.trim().isEmpty) continue;
    final items = _decodeChannel(channel);
    if (items != null) return items;
  }
  return null;
}

List<dynamic>? _decodeChannel(String answer) {
  for (final slice in _balancedSlices(answer, '[', ']')) {
    try {
      final decoded = jsonDecode(slice);
      if (decoded is List) return decoded;
    } on FormatException {
      continue;
    }
  }
  final salvaged = <dynamic>[];
  for (final slice in _balancedSlices(answer, '{', '}')) {
    try {
      final decoded = jsonDecode(slice);
      // Only the leaf objects: the outer `{"suggestions": [...]}` wrapper
      // decodes too, and would double-count everything inside it.
      if (decoded is Map && decoded['tag'] != null) salvaged.add(decoded);
    } on FormatException {
      continue;
    }
  }
  return salvaged.isEmpty ? null : salvaged;
}

/// Every `[open … close]` run in [text] whose brackets balance, outermost
/// first, ignoring brackets inside JSON strings.
///
/// A run that never closes (the truncated case) is yielded to the end of the
/// text: it will not decode, but the object-level salvage runs over the same
/// text and does not need it to.
Iterable<String> _balancedSlices(String text, String open, String close) sync* {
  for (var i = 0; i < text.length; i++) {
    if (text[i] != open) continue;
    var depth = 0;
    var inString = false;
    var escaped = false;
    for (var j = i; j < text.length; j++) {
      final c = text[j];
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (c == r'\') {
          escaped = true;
        } else if (c == '"') {
          inString = false;
        }
        continue;
      }
      if (c == '"') {
        inString = true;
      } else if (c == open) {
        depth++;
      } else if (c == close) {
        depth--;
        if (depth == 0) {
          yield text.substring(i, j + 1);
          break;
        }
      }
    }
  }
}
