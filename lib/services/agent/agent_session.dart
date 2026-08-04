/// The agent loop: model turn → tool calls → tool results → repeat.
/// Pure Dart; the UI observes it through the [AgentUiEvent] stream.
library;

import 'dart:async';

import '../../models/llm_models.dart';
import '../llm/llm_client.dart';
import 'agent_tools.dart';
import 'context_budget.dart';
import 'tag_library_tools.dart'
    show maxAssignmentsPerCall, maxLibraryTagsPerCall;
import 'tag_translation_tools.dart' show maxTranslationEntries;

enum AgentStopReason { completed, cancelled, maxTurns, tokenCap, error }

sealed class AgentUiEvent {}

class AgentTextDelta extends AgentUiEvent {
  AgentTextDelta(this.text);

  final String text;
}

class AgentToolStarted extends AgentUiEvent {
  AgentToolStarted(this.call);

  final ChatToolCall call;
}

class AgentToolFinished extends AgentUiEvent {
  AgentToolFinished(this.call, this.result);

  final ChatToolCall call;
  final AgentToolResult result;
}

class AgentFinished extends AgentUiEvent {
  AgentFinished(this.reason, [this.message, this.retryable = false]);

  final AgentStopReason reason;
  final String? message;

  /// Whether sending the same request again could plausibly work — true for
  /// transport and API failures, which are the ones that happen to a run that
  /// was otherwise fine. A cap or a loop guard is not retryable: the request
  /// was received, and repeating it changes nothing.
  final bool retryable;
}

/// The user's answer when a run reaches its turn limit and asks whether to
/// keep going. [note] is optional extra guidance they typed; it enters the
/// history as a user message so the model acts on it.
class AgentContinueDecision {
  const AgentContinueDecision({this.note});

  final String? note;
}

/// One conversation with the model, including its full message history and
/// cumulative token usage. Create a new instance for a new conversation or
/// after the dataset directory changes.
class AgentSession {
  AgentSession({
    required this.client,
    required this.registry,
    required this.profile,
    required String systemPrompt,
    this.maxTurnsPerRun = 24,
    this.sessionTokenCap = 1000000,
    this.confirmWrite,
    this.confirmContinue,
  }) : budget = ContextBudget(
         contextWindow: profile.contextWindow,
         maxOutputTokens: profile.maxOutputTokens,
         toolSchemaTokens: registry.schemaTokens,
       ),
       history = [ChatMessage.system(systemPrompt)];

  final LlmClient client;
  final ToolRegistry registry;
  final LlmProviderProfile profile;
  final ContextBudget budget;

  /// Model turns per user request; guards against infinite tool loops.
  final int maxTurnsPerRun;

  /// Asked when a run has spent [maxTurnsPerRun] turns: a decision grants
  /// another [maxTurnsPerRun], null stops the run. Without it the limit is a
  /// hard stop, which kills a legitimate one-image-at-a-time sweep partway
  /// through; with it the loop is still gated on a human saying "keep going".
  final Future<AgentContinueDecision?> Function(int turnsUsed)? confirmContinue;

  /// Cumulative token cap for the whole conversation; 0 or less means no
  /// cap. Every turn re-sends the whole history, so this grows quadratically
  /// in turns — it is a spend guard, not a context measure.
  final int sessionTokenCap;

  /// When set, write tools require this callback to return true before they
  /// execute (Phase 2's confirmation UI hooks in here).
  final Future<bool> Function(AgentTool tool, ChatToolCall call)? confirmWrite;

  final List<ChatMessage> history;

  TokenUsage totalUsage = const TokenUsage();
  bool _busy = false;
  CancellationToken? _cancel;

  bool get busy => _busy;

  void stop() => _cancel?.cancel();

  /// Runs one user request to completion (or cancellation / cap). Events are
  /// for UI display only; [history] carries the authoritative state.
  Stream<AgentUiEvent> run(String userInput) async* {
    if (_busy) {
      yield AgentFinished(AgentStopReason.error, 'session is busy');
      return;
    }
    history.add(ChatMessage.user(userInput));
    yield* _loop();
  }

  /// Picks the run back up where a failed model call left it, with no new
  /// user message. A turn that throws never reaches [history] — the failure
  /// happens before the assistant message is appended — so the request that
  /// goes back on the wire is the one that failed, tool results and all.
  Stream<AgentUiEvent> resume() async* {
    if (_busy) {
      yield AgentFinished(AgentStopReason.error, 'session is busy');
      return;
    }
    // Nothing but the system prompt: there is no request to repeat.
    if (history.length < 2) {
      yield AgentFinished(AgentStopReason.completed);
      return;
    }
    yield* _loop();
  }

  Stream<AgentUiEvent> _loop() async* {
    _busy = true;
    final cancel = _cancel = CancellationToken();
    try {
      var consecutiveToolErrors = 0;

      var turnBudget = maxTurnsPerRun;

      for (var turn = 0; ; turn++) {
        if (cancel.isCancelled) {
          yield AgentFinished(AgentStopReason.cancelled);
          return;
        }
        if (turn >= turnBudget) {
          final decision = await confirmContinue?.call(turn);
          if (cancel.isCancelled) {
            yield AgentFinished(AgentStopReason.cancelled);
            return;
          }
          if (decision == null) {
            yield AgentFinished(
              AgentStopReason.maxTurns,
              'stopped after $turn model turns',
            );
            return;
          }
          turnBudget = turn + maxTurnsPerRun;
          final note = decision.note?.trim() ?? '';
          if (note.isNotEmpty) history.add(ChatMessage.user(note));
        }
        if (sessionTokenCap > 0 && totalUsage.total >= sessionTokenCap) {
          yield AgentFinished(
            AgentStopReason.tokenCap,
            'session token cap ($sessionTokenCap) reached',
          );
          return;
        }
        budget.compact(history);

        final textBuffer = StringBuffer();
        var calls = const <ChatToolCall>[];
        TokenUsage? usage;
        try {
          await for (final event in client.chat(
            profile: profile,
            messages: history,
            tools: registry.specs,
            cancel: cancel,
          )) {
            switch (event) {
              case TextDelta(:final text):
                textBuffer.write(text);
                yield AgentTextDelta(text);
              case ToolCallsReady(calls: final ready):
                calls = ready;
              case StreamDone(usage: final u):
                usage = u;
            }
          }
        } on LlmException catch (e) {
          final cancelled = cancel.isCancelled;
          yield AgentFinished(
            cancelled ? AgentStopReason.cancelled : AgentStopReason.error,
            e.message,
            !cancelled,
          );
          return;
        }

        totalUsage +=
            usage ??
            TokenUsage(
              prompt: budget.estimate(history),
              completion: ContextBudget.estimateText(textBuffer.toString()),
            );

        if (cancel.isCancelled && calls.isEmpty) {
          yield AgentFinished(AgentStopReason.cancelled);
          return;
        }

        history.add(
          ChatMessage.assistant(textBuffer.toString(), toolCalls: calls),
        );
        if (calls.isEmpty) {
          yield AgentFinished(AgentStopReason.completed);
          return;
        }

        // Execute serially: TagOps is single-flight and disk writes must not
        // interleave. Every call gets a result message — required to keep
        // the wire protocol history valid even on cancellation.
        for (final call in calls) {
          AgentToolResult result;
          // A rejection is the user exercising the confirmation gate, not a
          // failure — it must not push the run toward the 3-strikes abort
          // below, or asking for confirmation becomes something that
          // punishes saying no. It also does not reset the streak: a real
          // error right before it should still count toward the next one.
          var wasRejection = false;
          if (cancel.isCancelled) {
            result = toolError('cancelled by user');
          } else {
            yield AgentToolStarted(call);
            final tool = registry.find(call.name);
            if (tool != null &&
                tool.needsConfirmation(call.argumentsJson) &&
                confirmWrite != null &&
                !await confirmWrite!(tool, call)) {
              result = toolError('the user rejected this operation');
              wasRejection = true;
            } else {
              result = await registry.dispatch(call.name, call.argumentsJson);
            }
            yield AgentToolFinished(call, result);
          }
          history.add(
            ChatMessage.toolResult(
              toolCallId: call.id,
              text: result.text,
              extraParts: result.extraParts,
              pinned: result.pinned,
            ),
          );
          if (!wasRejection) {
            consecutiveToolErrors = result.isError
                ? consecutiveToolErrors + 1
                : 0;
          }
        }
        if (cancel.isCancelled) {
          yield AgentFinished(AgentStopReason.cancelled);
          return;
        }
        if (consecutiveToolErrors >= 3) {
          yield AgentFinished(
            AgentStopReason.error,
            'stopped after 3 consecutive tool errors',
          );
          return;
        }
      }
    } finally {
      _busy = false;
      _cancel = null;
    }
  }
}

/// The system prompt. English skeleton (models follow it most reliably) with
/// the user's locale injected so replies come back in their language.
///
/// Batch sizes quoted in the guidelines come from the tool definitions rather
/// than being retyped here: a prompt that promises a limit the tool rejects
/// costs the model a failed call to discover.
String buildAgentSystemPrompt({
  required String localeName,
  required String datasetSummary,
  required String captionExtension,
  String? captionTypesSummary,
  bool jsonToolsEnabled = false,
  bool visionEnabled = false,
  bool libraryToolsEnabled = true,
  bool translationToolsEnabled = true,
}) {
  final captionTypesGuideline = captionTypesSummary == null
      ? ''
      : '\n- This dataset manages several caption types side by side: '
            '$captionTypesSummary.\n  Every ordinary tool reads and writes '
            'only the active type; the user\n  switches it in the navigator. '
            'Use check_caption_variants to audit which\n  images have which '
            'types, read_caption_file for the raw text of another\n  type, '
            'and write_caption_file to generate one type from another '
            '(e.g.\n  compose a natural-language caption from an image\'s '
            'WD14 tags).\n  Writing a JSON-format type rejects text that '
            'does not parse as JSON. When a\n  conversion must keep the tag set '
            'intact (e.g. regrouping tags into JSON\n  fields), pass '
            'expect_tags_from with the source extension — the write is\n  '
            'then rejected unless its tags match the source caption\'s, '
            'with any\n  natural-language JSON fields excluded via '
            'ignore_keys.\n  To convert a whole dataset into a JSON-format '
            'caption type use\n  convert_captions_to_json: define the field '
            'layout and a tag→field\n  assignment once and the tool '
            'assembles every image\'s JSON itself —\n  never loop '
            'write_caption_file over a dataset. The way back is\n  '
            'convert_captions_to_tags with the JSON type as the source: give '
            '"fields"\n  to flatten each document into a tag line in that key '
            'order, and nl_field\n  for the prose key, or its sentence is '
            'comma-split into bogus tags. JSON\n  values carry plain '
            'parentheses; caption-style \\( escaping never belongs '
            'in\n  them (the converter strips it going in and can escape it '
            'coming back out).\n  Whether a type '
            'holds tags, JSON or\n  natural language is its configured '
            'format (shown in the overview), not\n  its file extension.';
  final jsonGuideline = jsonToolsEnabled
      ? '\n- Reshaping the JSON captions this dataset already has — renaming '
            'fields,\n  changing their order, moving tags between them — is '
            'what\n  inspect_json_captions and restructure_json_captions are '
            'for. Survey the\n  shape first, then declare the target shape '
            'once (the ordered fields, where\n  each one\'s tags come from, '
            'and a catch-all array field for the rest) and\n  the tool '
            'rebuilds every document itself: the field order is yours and the\n'
            '  tags are the file\'s own, never reworded, dropped or invented. '
            'Content that\n  is not tags — a natural-language description — '
            'goes in a "preserve" field,\n  which carries the old value over '
            'untouched. Never loop write_caption_file\n  to reshape a '
            'dataset; for a single image, write_caption_file with\n  '
            'expect_same_tags is the guarded way.\n'
            '- Adding, removing or renaming the TAGS inside JSON captions is '
            'a different\n  job from reshaping them, and it is what '
            'edit_json_captions does: give the\n  rules once (add tags to a '
            'named field, remove tags, rename tags) and it\n  edits every '
            'document in place, leaving the keys, their order and every '
            'value\n  no rule touches exactly as they were. edit_captions, '
            'sort_captions_everywhere\n  and reorder_caption cannot touch a '
            'JSON caption at all — they have no document\n  to write back.'
      : '';
  // The optional tool packs describe themselves only when they are actually
  // registered: telling the model about organize_tag_library when it has no
  // such tool buys nothing but a refusal it has to discover the hard way.
  final libraryGuideline = libraryToolsEnabled
      ? '\n- The tag library is the user\'s own curated tag set, shown as '
            'named colored\n  groups in the app\'s library panel — it is not '
            'the dataset. Read it with\n  get_tag_library and change it with '
            'organize_tag_library (file tags into\n  groups), '
            'add_library_tags, and manage_tag_groups (rename, recolor,\n'
            '  reorder or delete a group). When\n  asked to tidy '
            'or categorize the library, send the whole plan as ONE\n  '
            'organize_tag_library call carrying every group with its tags, up '
            'to\n  $maxAssignmentsPerCall groups and $maxLibraryTagsPerCall '
            'tags per group;\n  never one call per tag. Reuse the group names '
            'that already exist and keep\n  the number of new ones small. '
            'None of this touches a caption file, so a\n  library change '
            'never alters the dataset — and none of it is covered by\n  undo, '
            'which is why remove_library_tags and the delete action of\n  '
            'manage_tag_groups are confirmation-gated.'
      : '';
  final glossaryGuideline = translationToolsEnabled
      ? '\n- The tag glossary is display-only: translations are shown beside '
            'tags in\n  the app\'s UI and never written into a caption. There '
            'is one glossary per\n  app language and the tools report which '
            'is active, so translate into that\n  language. Find the work '
            'with list_tag_translations (dataset tags, busiest\n  first) and '
            'write it back in batches of up to $maxTranslationEntries with\n  '
            'write_tag_translations — never one call per tag. For characters,'
            '\n  copyrights and artists call fetch_danbooru_tag first and take '
            'the name\n  from other_names: those are proper names you must '
            'not invent. Ordinary\n  descriptive tags need no lookup.'
      : '';
  final visionGuideline = visionEnabled
      ? '\n- view_image lets you actually see images (max 4 per call, '
            'downscaled).\n  It is token-expensive: spot-check individual '
            'images with it, never sweep\n  the dataset — bulk visual tagging '
            'belongs to run_wd_tagger.'
      : '';
  return '''
You are an assistant embedded in DataSetTrainingTool, a desktop app for
curating image datasets used to train SDXL / anime LoRA models. Each image
has a caption file ($captionExtension) containing comma-separated
danbooru-style tags.

Current dataset: $datasetSummary

Guidelines:
- Start by understanding the dataset with get_dataset_overview and
  get_tag_stats before proposing changes; aggregate statistics are cheap,
  reading captions image-by-image is expensive.
- The first tag of a caption is often the LoRA trigger word. Preserve tag
  order unless asked otherwise, and never remove the first tag without
  explicit confirmation from the user.
- Sorting tags across many images is ONE call to sort_captions_everywhere
  with a priority list (build it from get_tag_stats / get_tag_library, use
  keep_first to protect trigger words). Never loop reorder_caption over a
  batch: it needs every tag of every image retyped exactly, so a hundred
  images means a hundred chances to mistype one and lose the run.
  reorder_caption is for a single image whose order a priority list cannot
  express; re-read it with read_captions immediately before, and copy the
  tags from that result rather than from memory.
- Changing which tags captions carry — deleting a tag everywhere, renaming
  one, giving every image a tag — is ONE call to edit_captions with add /
  remove / rename rules, narrowed by the same filters list_images takes. It
  is the counterpart of edit_json_captions and takes the same three rules.
  Matching folds case and underscore/space style. write_caption is for a
  single image whose new tag list no rule can express; pass expect_same_tags
  when the tags should not change at all.
- The user can narrow the app to one subdirectory of the dataset. While a
  scope is active every tool — listing, statistics, and the "everywhere"
  writes — sees only that folder, and paths outside it do not resolve at
  all. The scope can change mid-conversation: get_dataset_overview and each
  batch write report the scope they ran under, so read it back rather than
  claiming a dataset-wide sweep from memory.
- When the user asks for changes, describe your plan briefly before acting,
  and report exact numbers (images affected) afterwards.
- Every write to a caption file can be undone by the user (Ctrl+Z), and may
  require their confirmation first.
- run_wd_tagger produces booru-style tags for images via the local tagger
  server. Results are returned to you, not written to disk — filter them,
  then apply with the write tools.$libraryGuideline$glossaryGuideline$captionTypesGuideline$jsonGuideline$visionGuideline
- When you need the user to make a decision mid-task, call the ask_user
  tool with short concrete options instead of ending your reply with an
  open question — that keeps the task running once they answer.
- Reply in the user's language ($localeName). Keep answers concise; prefer
  short lists of concrete tags/numbers over prose.
''';
}
