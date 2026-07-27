/// The agent loop: model turn → tool calls → tool results → repeat.
/// Pure Dart; the UI observes it through the [AgentUiEvent] stream.
library;

import 'dart:async';

import '../../models/llm_models.dart';
import '../llm/llm_client.dart';
import 'agent_tools.dart';
import 'context_budget.dart';

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
  AgentFinished(this.reason, [this.message]);

  final AgentStopReason reason;
  final String? message;
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
  }) : budget = ContextBudget(
         contextWindow: profile.contextWindow,
         maxOutputTokens: profile.maxOutputTokens,
       ),
       history = [ChatMessage.system(systemPrompt)];

  final LlmClient client;
  final ToolRegistry registry;
  final LlmProviderProfile profile;
  final ContextBudget budget;

  /// Model turns per user request; guards against infinite tool loops.
  final int maxTurnsPerRun;

  /// Cumulative token cap for the whole conversation.
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
    _busy = true;
    final cancel = _cancel = CancellationToken();
    try {
      history.add(ChatMessage.user(userInput));
      var consecutiveToolErrors = 0;

      for (var turn = 0; turn < maxTurnsPerRun; turn++) {
        if (cancel.isCancelled) {
          yield AgentFinished(AgentStopReason.cancelled);
          return;
        }
        if (totalUsage.total >= sessionTokenCap) {
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
          yield AgentFinished(
            cancel.isCancelled
                ? AgentStopReason.cancelled
                : AgentStopReason.error,
            e.message,
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
          if (cancel.isCancelled) {
            result = toolError('cancelled by user');
          } else {
            yield AgentToolStarted(call);
            final tool = registry.find(call.name);
            if (tool != null &&
                tool.isWrite &&
                confirmWrite != null &&
                !await confirmWrite!(tool, call)) {
              result = toolError('the user rejected this operation');
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
            ),
          );
          consecutiveToolErrors = result.isError
              ? consecutiveToolErrors + 1
              : 0;
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
      yield AgentFinished(
        AgentStopReason.maxTurns,
        'stopped after $maxTurnsPerRun model turns',
      );
    } finally {
      _busy = false;
      _cancel = null;
    }
  }
}

/// The system prompt. English skeleton (models follow it most reliably) with
/// the user's locale injected so replies come back in their language.
String buildAgentSystemPrompt({
  required String localeName,
  required String datasetSummary,
  required String captionExtension,
  bool visionEnabled = false,
}) {
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
- When the user asks for changes, describe your plan briefly before acting,
  and report exact numbers (images affected) afterwards.
- Every write operation you perform can be undone by the user (Ctrl+Z), and
  may require their confirmation first.
- run_wd_tagger produces booru-style tags for images via the local tagger
  server. Results are returned to you, not written to disk — filter them,
  then apply with the write tools.$visionGuideline
- When you need the user to make a decision mid-task, call the ask_user
  tool with short concrete options instead of ending your reply with an
  open question — that keeps the task running once they answer.
- Reply in the user's language ($localeName). Keep answers concise; prefer
  short lists of concrete tags/numbers over prose.
''';
}
