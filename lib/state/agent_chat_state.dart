import 'dart:async';

import 'package:flutter/foundation.dart';

import '../app_state.dart';
import '../models/caption_type.dart';
import '../models/llm_models.dart';
import '../models/merge_rules.dart';
import '../services/agent/agent_session.dart';
import '../services/agent/agent_tools.dart';
import '../services/agent/caption_variant_tools.dart';
import '../services/agent/character_sheet.dart';
import '../services/agent/dataset_tools.dart';
import '../services/agent/json_caption_tools.dart';
import '../services/agent/media_tools.dart';
import '../services/agent/merge_rule_tools.dart';
import '../services/agent/tag_translation_tools.dart';
import '../services/llm/anthropic_client.dart';
import '../services/llm/llm_client.dart';
import '../services/llm/openai_compat_client.dart';
import 'ai_tagger_state.dart';
import 'dataset_state.dart';
import 'tag_ops.dart';

enum AgentEntryKind { user, assistant, tool, notice, rules }

/// What a notice row represents; the panel maps these to localized text.
enum AgentNoticeType { cancelled, error, reset, tokenCap, profileSwitched }

/// One row in the chat transcript. Mutable: assistant text streams in and
/// tool entries flip from running to finished.
class AgentChatEntry {
  AgentChatEntry.user(String message) : kind = AgentEntryKind.user {
    text = message;
  }

  AgentChatEntry.assistant() : kind = AgentEntryKind.assistant;

  AgentChatEntry.tool(ChatToolCall call) : kind = AgentEntryKind.tool {
    toolName = call.name;
    toolArgs = call.argumentsJson;
    running = true;
  }

  AgentChatEntry.notice(AgentNoticeType type, [String message = ''])
    : kind = AgentEntryKind.notice {
    noticeType = type;
    text = message;
    isError = type == AgentNoticeType.error;
  }

  AgentChatEntry.rules(CharacterMergeRules proposed)
    : kind = AgentEntryKind.rules {
    rules = proposed;
  }

  final AgentEntryKind kind;
  AgentNoticeType? noticeType;

  /// Set on [AgentEntryKind.rules] rows only.
  CharacterMergeRules? rules;

  String text = '';
  String toolName = '';
  String toolArgs = '';
  String toolResult = '';
  bool running = false;
  bool isError = false;
}

/// A write tool call waiting for the user's go-ahead; the panel renders it
/// as a confirmation bar and resolves the completer.
class PendingWriteConfirm {
  PendingWriteConfirm(this.toolName, this.argsJson);

  final String toolName;
  final String argsJson;
  final Completer<bool> completer = Completer();
}

/// A question the model asked via the ask_user tool; the panel renders the
/// options as buttons plus a free-form reply field. A null answer means the
/// question was dismissed/cancelled.
class PendingUserQuestion {
  PendingUserQuestion(this.question, this.options);

  final String question;
  final List<String> options;
  final Completer<String?> completer = Completer();
}

/// UI state of the assistant panel: the transcript, the running session, and
/// the LLM clients. Owned by the workbench alongside the other panel states.
class AgentChatState extends ChangeNotifier {
  AgentChatState({
    required this.app,
    required this.dataset,
    required this.tagOps,
    required this.aiTagger,
  });

  final AppState app;
  final DatasetState dataset;
  final TagOps tagOps;
  final AiTaggerState aiTagger;

  final Map<LlmApiKind, LlmClient> _clients = {
    LlmApiKind.openaiCompat: OpenAiCompatClient(),
    LlmApiKind.anthropic: AnthropicClient(),
  };

  final List<AgentChatEntry> entries = [];
  AgentSession? _session;
  bool _busy = false;
  bool _allowAllWrites = false;

  /// Non-null while a write tool waits for the user's decision.
  PendingWriteConfirm? pendingConfirm;

  /// Non-null while the ask_user tool waits for the user's answer.
  PendingUserQuestion? pendingQuestion;

  bool get busy => _busy;
  int get totalTokens => _session?.totalUsage.total ?? 0;

  /// The cap the running conversation was created with — changing the
  /// setting mid-conversation must not make the footer disagree with the
  /// session that is actually enforcing it. 0 = uncapped.
  int get tokenCap => _session?.sessionTokenCap ?? app.agentSessionTokenCap;

  /// Backend the current/next session uses, split for the header: the
  /// provider reads as a label, the model as a code chip.
  String? get providerName => app.activeLlmPair?.$1.name;
  String? get modelLabel => app.activeLlmPair?.$2.label;

  bool get hasProfile => app.activeLlmProfile != null;

  /// Switches the backend from the panel itself. A conversation is bound to
  /// the backend it started on — the history was built for that model's tool
  /// schema, context window and (non-)vision tool set — so the running
  /// session is dropped. [send] would drop it anyway; doing it here lets the
  /// transcript say so instead of the next reply silently forgetting
  /// everything above it.
  Future<void> switchProfile(String id) async {
    if (app.activeLlmProfile?.id == id) return;
    await app.setActiveLlmProfile(id);
    if (_session != null) {
      _session!.stop();
      _session = null;
      _allowAllWrites = false;
      entries.add(
        AgentChatEntry.notice(
          AgentNoticeType.profileSwitched,
          app.activeLlmProfile?.name ?? '',
        ),
      );
    }
    // The header reads the name off AppState, which this state object does
    // not listen to; notify either way so it repaints.
    _touch();
  }

  /// Bumped on every transcript change; the panel uses it to auto-scroll.
  int revision = 0;

  void _touch() {
    revision++;
    notifyListeners();
  }

  /// Runs the character-sheet skill: the form's answers become one task
  /// message, and the transcript shows [summary] in its place — the compiled
  /// task is several paragraphs of model-facing scaffolding that would bury
  /// the rest of the conversation.
  Future<void> startCharacterSheet(
    CharacterSheetInput input, {
    required String summary,
  }) => send(buildCharacterSheetTask(input), display: summary);

  Future<void> send(String input, {String? display}) async {
    final text = input.trim();
    if (text.isEmpty || _busy) return;
    final profile = app.activeLlmProfile;
    if (profile == null) return;

    // Model switch invalidates the conversation (history was built for the
    // previous backend); start fresh.
    if (_session != null && _session!.profile.id != profile.id) {
      _session = null;
    }
    _session ??= _createSession(profile);

    _busy = true;
    entries.add(AgentChatEntry.user(display ?? text));
    AgentChatEntry? assistant;
    _touch();
    try {
      await for (final event in _session!.run(text)) {
        switch (event) {
          case AgentTextDelta(:final text):
            if (assistant == null) {
              assistant = AgentChatEntry.assistant();
              entries.add(assistant);
            }
            assistant.text += text;
          case AgentToolStarted(:final call):
            assistant = null; // next text delta starts a new bubble
            entries.add(AgentChatEntry.tool(call));
          case AgentToolFinished(:final call, :final result):
            final entry = entries.lastWhere(
              (e) =>
                  e.kind == AgentEntryKind.tool &&
                  e.running &&
                  e.toolName == call.name,
              orElse: () => entries.last,
            );
            entry.running = false;
            entry.toolResult = result.text;
            entry.isError = result.isError;
          case AgentFinished(:final reason, :final message):
            _onFinished(reason, message);
        }
        _touch();
      }
    } finally {
      _busy = false;
      // Drop a tool entry left spinning by an abnormal end.
      for (final e in entries) {
        e.running = false;
      }
      _touch();
    }
  }

  void _onFinished(AgentStopReason reason, String? message) {
    switch (reason) {
      case AgentStopReason.completed:
        break;
      case AgentStopReason.cancelled:
        entries.add(AgentChatEntry.notice(AgentNoticeType.cancelled));
      case AgentStopReason.tokenCap:
        // Its own notice: "session token cap (1000000) reached" tells the
        // user nothing about what to do, and the way out (raise the cap, or
        // start a fresh conversation) is not obvious.
        entries.add(AgentChatEntry.notice(AgentNoticeType.tokenCap));
      case AgentStopReason.maxTurns:
      case AgentStopReason.error:
        entries.add(
          AgentChatEntry.notice(AgentNoticeType.error, message ?? reason.name),
        );
    }
  }

  /// Gate for write tools: transparent when confirmation is off or the user
  /// chose "allow all" for this conversation; otherwise blocks until the
  /// panel's confirmation bar resolves.
  Future<bool> _confirmWrite(AgentTool tool, ChatToolCall call) async {
    if (!app.agentConfirmWrites || _allowAllWrites) return true;
    final pending = PendingWriteConfirm(call.name, call.argumentsJson);
    pendingConfirm = pending;
    _touch();
    final allowed = await pending.completer.future;
    pendingConfirm = null;
    _touch();
    return allowed;
  }

  /// Called by the confirmation bar. [allowAll] upgrades this conversation
  /// to unattended writes.
  void resolveConfirm({required bool allow, bool allowAll = false}) {
    final pending = pendingConfirm;
    if (pending == null) return;
    if (allow && allowAll) _allowAllWrites = true;
    if (!pending.completer.isCompleted) pending.completer.complete(allow);
  }

  /// Called by the question card; null dismisses the question (the model is
  /// told the user declined to answer).
  void resolveQuestion(String? answer) {
    final pending = pendingQuestion;
    if (pending == null) return;
    if (!pending.completer.isCompleted) pending.completer.complete(answer);
  }

  /// The UI-bound ask_user tool: blocks the agent loop until the user picks
  /// an option (or types a custom reply) in the panel's question card.
  AgentTool _buildAskUserTool() => AgentTool(
    spec: const AgentToolSpec(
      name: 'ask_user',
      description:
          'Ask the user a question and wait for their answer. Use this '
          'whenever you need a decision or clarification before '
          'proceeding (e.g. choosing between cleanup strategies) '
          'instead of ending your reply with an open question. Provide '
          '2-5 short, concrete options when the answer space is known; '
          'the user can always type a custom reply.',
      parametersSchema: {
        'type': 'object',
        'properties': {
          'question': {'type': 'string'},
          'options': {
            'type': 'array',
            'items': {'type': 'string'},
            'description': 'short choice labels, max 5',
          },
        },
        'required': ['question'],
      },
    ),
    handler: (args) async {
      final question = requireString(args, 'question');
      final options = optStringList(args, 'options', maxLength: 5);
      final pending = PendingUserQuestion(question, options);
      pendingQuestion = pending;
      _touch();
      final answer = await pending.completer.future;
      pendingQuestion = null;
      _touch();
      if (answer == null) {
        return toolError(
          'the user dismissed the question without '
          'answering; proceed with your best judgment or finish',
        );
      }
      return toolOk({'answer': answer});
    },
  );

  /// Sink for `propose_merge_rules`: persists the proposal and drops a review
  /// card into the transcript. Unlike the write tools this is not gated by a
  /// confirmation — it touches no caption, and the card *is* the review.
  Future<CharacterMergeRules> _saveMergeRules(CharacterMergeRules rules) async {
    final stored = await app.saveMergeRules(rules);
    entries.add(AgentChatEntry.rules(stored));
    _touch();
    return stored;
  }

  AgentSession _createSession(LlmProviderProfile profile) {
    final deps = DatasetToolsDeps(
      dataset: dataset,
      rootDir: () => app.browsingDirectory,
      libraryTags: () => app.commonTags,
      tagGroups: () => app.tagGroups,
      captionTypes: () => app.enabledCaptionTypes,
    );
    // With a single tag-format type the variant tools are pure noise in the
    // prompt. A lone JSON or prose type is a different story: the tag tools
    // cannot rewrite those files at all, so the raw read/write tools are the
    // only ones that work. Types enabled mid-conversation arrive with the
    // next session.
    final multiType = app.enabledCaptionTypes.length > 1;
    final structuredTypes = app.enabledCaptionTypes.any(
      (t) => t.format != CaptionFormat.tags,
    );
    final jsonTypes = app.enabledCaptionTypes.any(
      (t) => t.format == CaptionFormat.json,
    );
    final registry = ToolRegistry([
      ...buildReadOnlyTools(deps),
      ...buildWriteTools(deps, tagOps),
      if (multiType || structuredTypes)
        ...buildCaptionVariantTools(deps, tagOps),
      if (jsonTypes) ...buildJsonCaptionTools(deps, tagOps),
      ...buildTaggerTools(deps, aiTagger),
      if (profile.supportsVision) ...buildVisionTools(deps),
      ...buildMergeRuleTools(_saveMergeRules),
      ...buildTagTranslationTools(
        TagTranslationToolsDeps(
          glossary: app.tagTranslations,
          dictionary: app.tagDictionary,
          dataset: dataset,
          libraryTags: () => app.commonTags,
        ),
      ),
      _buildAskUserTool(),
    ]);
    final root = app.browsingDirectory;
    final scope = dataset.activeSubdirectory;
    final summary = root == null
        ? 'no dataset directory is open yet'
        : '$root — ${dataset.totalCount} images '
              '(${dataset.taggedCount} captioned), '
              '${dataset.datasetTags.length} unique tags'
              // Only the counts above are scoped, so say so here rather than
              // letting them read as the whole dataset's.
              '${scope == null ? '' : '; scope: subdirectory '
                        '"${scope.isEmpty ? '.' : scope}" only'}';
    return AgentSession(
      client: _clients[profile.kind]!,
      registry: registry,
      profile: profile,
      sessionTokenCap: app.agentSessionTokenCap,
      systemPrompt: buildAgentSystemPrompt(
        localeName: app.currentLocale.languageCode == 'zh'
            ? 'Chinese (简体中文)'
            : 'English',
        datasetSummary: summary,
        captionExtension: app.captionExtension,
        captionTypesSummary: multiType || structuredTypes
            ? [
                for (final t in app.enabledCaptionTypes)
                  '${t.label} (${t.extension}'
                      '${switch (t.format) {
                        CaptionFormat.tags => '',
                        CaptionFormat.json => ', json format',
                        CaptionFormat.prose => ', natural-language prose',
                      }})'
                      '${t.extension == app.captionExtension ? ', active' : ''}',
              ].join('; ')
            : null,
        jsonToolsEnabled: jsonTypes,
        visionEnabled: profile.supportsVision,
      ),
      confirmWrite: _confirmWrite,
    );
  }

  void stopRun() {
    // Unblock pending interactions first, or the session cannot wind down.
    resolveConfirm(allow: false);
    resolveQuestion(null);
    _session?.stop();
  }

  /// Clears the conversation. With [datasetSwitched] a reset notice is shown
  /// as the first row (the dataset changed under a live conversation).
  void resetSession({bool datasetSwitched = false}) {
    resolveConfirm(allow: false);
    resolveQuestion(null);
    _session?.stop();
    _session = null;
    _allowAllWrites = false;
    entries.clear();
    if (datasetSwitched) {
      entries.add(AgentChatEntry.notice(AgentNoticeType.reset));
    }
    _touch();
  }

  @override
  void dispose() {
    resolveConfirm(allow: false);
    resolveQuestion(null);
    _session?.stop();
    for (final c in _clients.values) {
      c.dispose();
    }
    super.dispose();
  }
}
