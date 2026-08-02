import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:markdown_widget/markdown_widget.dart';
import 'package:provider/provider.dart';

import '../settings_view.dart';
import '../../app_state.dart';
import '../../l10n/app_localizations.dart';
import '../../models/llm_models.dart';
import '../../models/merge_rules.dart';
import '../../models/prompt_preset.dart';
import '../../state/agent_chat_state.dart';
import '../../theme/app_theme.dart';
import 'character_sheet_dialog.dart';
import 'llm_profile_dialog.dart';
import 'prompt_preset_dialog.dart';

/// Markdown rendering shared by the user and assistant bubbles: the preset
/// for the current brightness with the chat's compact font size.
Widget chatMarkdown(BuildContext context, String text) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final base = isDark
      ? MarkdownConfig.darkConfig
      : MarkdownConfig.defaultConfig;
  return MarkdownBlock(
    data: text,
    selectable: true,
    config: base.copy(
      configs: [
        PConfig(textStyle: const TextStyle(fontSize: 12.5, height: 1.45)),
      ],
    ),
  );
}

/// The AI assistant's body: transcript, run state, and input row.
///
/// The header and the surface around it belong to whatever hosts this — the
/// floating dock draws its own glass frame and title bar so the panel can be
/// dragged and collapsed without this widget knowing about either.
class AgentChatPanel extends StatefulWidget {
  const AgentChatPanel({super.key});

  @override
  State<AgentChatPanel> createState() => _AgentChatPanelState();
}

class _AgentChatPanelState extends State<AgentChatPanel> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final FocusNode _inputFocus = FocusNode();
  int _lastRevision = -1;

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  void _send(AgentChatState chat) {
    final text = _input.text.trim();
    if (text.isEmpty || chat.busy || !chat.hasProfile) return;
    _input.clear();
    chat.send(text);
    _inputFocus.requestFocus();
  }

  /// Large modal editor for longer prompts; shares the input controller so
  /// text survives opening/closing either way.
  Future<void> _openComposer() async {
    final chat = context.read<AgentChatState>();
    final l10n = AppLocalizations.of(context)!;
    final send = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.agentComposerTitle),
        content: SizedBox(
          width: 560,
          height: 340,
          child: TextField(
            controller: _input,
            autofocus: true,
            maxLines: null,
            expands: true,
            textAlignVertical: TextAlignVertical.top,
            keyboardType: TextInputType.multiline,
            style: const TextStyle(fontSize: 13, height: 1.5),
            decoration: InputDecoration(
              hintText: l10n.agentInputHint,
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(
            child: Text(l10n.cancel),
            onPressed: () => Navigator.of(dialogContext).pop(false),
          ),
          FilledButton(
            child: Text(l10n.agentSend),
            onPressed: () => Navigator.of(dialogContext).pop(true),
          ),
        ],
      ),
    );
    if (send == true && mounted) _send(chat);
  }

  /// Drops a preset's text into the input rather than sending it: presets are
  /// starting points, and the user usually has a detail to add before the
  /// assistant runs off and edits captions.
  void _insertPreset(PromptPreset preset) {
    final text = preset.content.trim();
    if (text.isEmpty) return;
    final current = _input.text.trimRight();
    final next = current.isEmpty ? text : '$current\n$text';
    _input.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
    _inputFocus.requestFocus();
  }

  /// The character-sheet skill: collect the sheet, then hand the compiled
  /// task straight to the session. Unlike a preset this does not stop in the
  /// input box — the dialog's start button is the confirmation.
  Future<void> _startCharacterSheet() async {
    final chat = context.read<AgentChatState>();
    final l10n = AppLocalizations.of(context)!;
    final input = await showCharacterSheetDialog(context);
    if (input == null || !mounted) return;
    if (chat.busy || !chat.hasProfile) return;
    chat.startCharacterSheet(
      input,
      summary: characterSheetSummary(l10n, input),
    );
  }

  void _autoScroll(AgentChatState chat) {
    if (chat.revision == _lastRevision) return;
    _lastRevision = chat.revision;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final semantic = context.semantic;
    final scheme = Theme.of(context).colorScheme;
    final chat = context.watch<AgentChatState>();
    _autoScroll(chat);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: chat.hasProfile || chat.entries.isNotEmpty
              ? ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(10, 10, 10, 4),
                  itemCount: chat.entries.length,
                  itemBuilder: (context, index) =>
                      _EntryRow(entry: chat.entries[index]),
                )
              : _NoProfileHint(),
        ),
        if (chat.busy)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: [
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.6,
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  l10n.agentRunning,
                  style: TextStyle(fontSize: 11.5, color: semantic.muted),
                ),
                const Spacer(),
                TextButton.icon(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    foregroundColor: scheme.error,
                    textStyle: const TextStyle(fontSize: 11.5),
                  ),
                  onPressed: chat.stopRun,
                  icon: const Icon(Icons.stop_circle_outlined, size: 14),
                  label: Text(l10n.agentStop),
                ),
              ],
            ),
          ),
        if (chat.pendingQuestion != null) _QuestionCard(chat: chat),
        if (chat.pendingConfirm != null) _ConfirmBar(chat: chat),
        _InputRow(
          controller: _input,
          focusNode: _inputFocus,
          enabled: chat.hasProfile && !chat.busy,
          onSend: () => _send(chat),
          onExpand: _openComposer,
          onPickPreset: _insertPreset,
          onStartSkill: _startCharacterSheet,
        ),
        _InputFooter(chat: chat),
      ],
    );
  }
}

/// Title bar of the floating assistant: identity on the left, window
/// controls on the right, and the whole strip doubles as the drag handle.
class AgentPanelHeader extends StatelessWidget {
  const AgentPanelHeader({
    super.key,
    required this.chat,
    required this.onClose,
    required this.minimized,
    required this.onToggleMinimized,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  /// Fixed bar height. The dock reads it to size its collapsed state, which
  /// is this bar and nothing else.
  static const double height = 58;

  final AgentChatState chat;
  final VoidCallback onClose;
  final bool minimized;
  final VoidCallback onToggleMinimized;
  final ValueChanged<Offset> onDragUpdate;
  final VoidCallback onDragEnd;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final semantic = context.semantic;
    final scheme = Theme.of(context).colorScheme;
    return MouseRegion(
      cursor: SystemMouseCursors.move,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate: (details) => onDragUpdate(details.delta),
        onPanEnd: (_) => onDragEnd(),
        // Deliberately no double-tap-to-collapse: a double-tap recognizer
        // here keeps the gesture arena open for its timeout, so every single
        // click on the three buttons in this bar would be delayed by ~300ms.
        // The minimize button is the discoverable path anyway.
        child: Container(
          height: height,
          padding: const EdgeInsets.fromLTRB(12, 0, 10, 0),
          decoration: BoxDecoration(
            border: minimized
                ? null
                : Border(bottom: BorderSide(color: semantic.line)),
          ),
          child: Row(
            children: [
              // The assistant's mark: a tinted tile rather than a bare icon,
              // so the panel reads as its own surface and not as one more
              // toolbar of the workbench behind it.
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: scheme.primary.withAlpha(30),
                  border: Border.all(color: scheme.primary.withAlpha(70)),
                  borderRadius: BorderRadius.circular(AppRadii.control + 2),
                ),
                child: Icon(
                  Icons.auto_awesome,
                  size: 16,
                  color: scheme.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.agentPanelTitle,
                      // Two stacked rows in a fixed bar leave the title no
                      // room to wrap when the panel is dragged narrow.
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: AppText.base,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    _ProfileMenuButton(chat: chat),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              _ChromeButton(
                icon: Icons.add_comment_outlined,
                tooltip: l10n.agentNewSession,
                onPressed: chat.busy ? null : () => chat.resetSession(),
              ),
              const SizedBox(width: 4),
              _ChromeButton(
                icon: minimized ? Icons.expand_less : Icons.remove,
                tooltip: minimized ? l10n.agentExpand : l10n.agentMinimize,
                onPressed: onToggleMinimized,
              ),
              const SizedBox(width: 4),
              _ChromeButton(
                icon: Icons.close,
                tooltip: l10n.cancel,
                onPressed: onClose,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// How a [_ChromeSlot] is painted: a hairline slot for secondary actions, a
/// tinted one for the accented affordances, a solid one for send.
enum _ChromeFill { outlined, tinted, solid }

/// The square slot the panel's chrome is built from — title-bar buttons, the
/// preset picker, the input actions. Visual only: the interactive wrappers
/// ([_ChromeButton], the preset [PopupMenuButton]) supply the gesture, so a
/// menu button and a plain button can look identical.
class _ChromeSlot extends StatelessWidget {
  const _ChromeSlot({
    required this.icon,
    this.fill = _ChromeFill.outlined,
    this.enabled = true,
  });

  /// One size everywhere: the title bar and the input row are the same
  /// grid, and a slot that shrinks in one of them breaks the alignment.
  static const double size = 30;

  final IconData icon;
  final _ChromeFill fill;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    final scheme = Theme.of(context).colorScheme;

    final (Color? background, Color? border, Color icons) = switch (fill) {
      _ChromeFill.outlined => (null, semantic.line, semantic.muted),
      _ChromeFill.tinted => (
        scheme.primary.withAlpha(enabled ? 30 : 14),
        scheme.primary.withAlpha(enabled ? 70 : 34),
        scheme.primary,
      ),
      _ChromeFill.solid => (
        enabled ? scheme.primary : scheme.primary.withAlpha(60),
        null,
        scheme.onPrimary,
      ),
    };

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: background,
        border: border == null ? null : Border.all(color: border),
        borderRadius: BorderRadius.circular(AppRadii.control + 1),
      ),
      child: Icon(
        icon,
        size: 15,
        // Disabled slots dim their glyph rather than their frame: the frame
        // is what keeps the row's rhythm readable.
        color: enabled ? icons : icons.withAlpha(90),
      ),
    );
  }
}

class _ChromeButton extends StatelessWidget {
  const _ChromeButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.fill = _ChromeFill.outlined,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final _ChromeFill fill;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(AppRadii.control + 1),
          child: _ChromeSlot(icon: icon, fill: fill, enabled: enabled),
        ),
      ),
    );
  }
}

/// The backend name under the panel title, doubling as the switcher.
///
/// It used to be plain text: the only way to move the assistant to another
/// model was the Settings dialog, three clicks away from the conversation
/// the switch is about.
class _ProfileMenuButton extends StatelessWidget {
  const _ProfileMenuButton({required this.chat});

  final AgentChatState chat;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final semantic = context.semantic;
    final app = context.watch<AppState>();
    final providers = app.llmProviders;
    final activeId = app.activeLlmProfile?.id;
    // With a single provider its name is already in the closed label, so the
    // header would just repeat it above one short list.
    final groupByProvider = providers.length > 1;

    return PopupMenuButton<String>(
      tooltip: l10n.agentSwitchProfile,
      position: PopupMenuPosition.under,
      constraints: const BoxConstraints(minWidth: 200, maxWidth: 340),
      padding: EdgeInsets.zero,
      // A run is bound to the backend it started on; switching underneath it
      // would leave the header disagreeing with what is actually answering.
      enabled: !chat.busy,
      onSelected: chat.switchProfile,
      itemBuilder: (_) => [
        if (providers.isEmpty)
          PopupMenuItem<String>(
            enabled: false,
            height: 34,
            child: Text(
              l10n.llmNoProfiles,
              style: TextStyle(fontSize: 11.5, color: semantic.muted),
            ),
          ),
        for (final provider in providers) ...[
          if (groupByProvider)
            PopupMenuItem<String>(
              enabled: false,
              height: 26,
              child: Text(
                provider.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 10.5, color: semantic.muted),
              ),
            ),
          for (final model in provider.models)
            _profileItem(
              context,
              provider: provider,
              model: model,
              grouped: groupByProvider,
              activeId: activeId,
            ),
        ],
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          height: 34,
          // The menu is gone by the time this runs, so the dialog opens from
          // the panel's context rather than the popup route's.
          onTap: () => showLlmProfilesDialog(context),
          child: Row(
            children: [
              Icon(Icons.tune, size: 13, color: semantic.muted),
              const SizedBox(width: 7),
              Text(
                l10n.llmManageProfiles,
                style: TextStyle(fontSize: 11.5, color: semantic.muted),
              ),
            ],
          ),
        ),
      ],
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // The provider stays plain text and the model gets the chip: the
          // model is what the user actually switches between, and a code
          // name deserves the code face.
          if (chat.providerName != null)
            Flexible(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Text(
                  '${chat.providerName} ·',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: AppText.micro,
                    color: semantic.muted,
                  ),
                ),
              ),
            ),
          Flexible(
            flex: 3,
            child: Container(
              padding: const EdgeInsets.fromLTRB(6, 1, 2, 1),
              decoration: BoxDecoration(
                color: semantic.raised,
                border: Border.all(color: semantic.line),
                borderRadius: BorderRadius.circular(AppRadii.input),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      chat.modelLabel ?? l10n.llmNoProfiles,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: monoStyle(
                        context,
                        size: AppText.micro,
                        color: semantic.muted,
                      ),
                    ),
                  ),
                  Icon(Icons.arrow_drop_down, size: 13, color: semantic.muted),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  PopupMenuItem<String> _profileItem(
    BuildContext context, {
    required LlmProvider provider,
    required LlmModelConfig model,
    required bool grouped,
    required String? activeId,
  }) {
    final l10n = AppLocalizations.of(context)!;
    final semantic = context.semantic;
    final scheme = Theme.of(context).colorScheme;
    final profile = provider.resolve(model);
    final active = profile.id == activeId;
    // The provider name is already above the row (or in the closed label);
    // a single model under a single provider is the only case with nothing
    // else to say, and there `profile.name` is just the provider name.
    final label = grouped || provider.models.length > 1
        ? model.label
        : profile.name;
    return PopupMenuItem<String>(
      value: profile.id,
      height: 32,
      child: Padding(
        padding: EdgeInsets.only(left: grouped ? 10 : 0),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: active ? scheme.primary : null,
                ),
              ),
            ),
            if (profile.supportsVision) ...[
              const SizedBox(width: 6),
              Tooltip(
                message: l10n.llmVisionBadge,
                child: Icon(
                  Icons.image_outlined,
                  size: 13,
                  color: semantic.muted,
                ),
              ),
            ],
            if (active) ...[
              const SizedBox(width: 6),
              Icon(Icons.check, size: 13, color: scheme.primary),
            ],
          ],
        ),
      ),
    );
  }
}

class _NoProfileHint extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final semantic = context.semantic;
    // Scrollable: as a floating panel this can be shorter than the hint,
    // and a clipped call-to-action is worse than a scrolled one.
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.smart_toy_outlined, size: 28, color: semantic.muted),
            const SizedBox(height: 10),
            Text(
              l10n.agentNoProfileHint,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: semantic.muted),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                textStyle: const TextStyle(fontSize: 12),
              ),
              onPressed: () => showSettingsDialog(context),
              child: Text(l10n.agentOpenSettings),
            ),
          ],
        ),
      ),
    );
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({required this.entry});

  final AgentChatEntry entry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final semantic = context.semantic;
    final scheme = Theme.of(context).colorScheme;

    switch (entry.kind) {
      case AgentEntryKind.user:
        return Align(
          alignment: Alignment.centerRight,
          // IntrinsicWidth keeps short messages shrink-wrapped: the
          // markdown column would otherwise stretch the bubble full-width.
          child: IntrinsicWidth(
            child: Container(
              margin: const EdgeInsets.only(bottom: 8, left: 30),
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
              decoration: BoxDecoration(
                color: scheme.primary.withAlpha(26),
                border: Border.all(color: scheme.primary.withAlpha(70)),
                borderRadius: BorderRadius.circular(AppRadii.card - 2),
              ),
              child: chatMarkdown(context, entry.text),
            ),
          ),
        );
      case AgentEntryKind.assistant:
        return Padding(
          padding: const EdgeInsets.only(bottom: 8, right: 12),
          child: chatMarkdown(context, entry.text),
        );
      case AgentEntryKind.tool:
        return _ToolCard(entry: entry);
      case AgentEntryKind.rules:
        return _RulesCard(rules: entry.rules!);
      case AgentEntryKind.notice:
        final text = switch (entry.noticeType) {
          AgentNoticeType.cancelled => l10n.agentStoppedNotice,
          AgentNoticeType.reset => l10n.agentSessionResetNotice,
          AgentNoticeType.tokenCap => l10n.agentTokenCapNotice,
          AgentNoticeType.profileSwitched => l10n.agentProfileSwitchedNotice(
            entry.text,
          ),
          AgentNoticeType.error || null => l10n.agentErrorNotice(entry.text),
        };
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              fontStyle: FontStyle.italic,
              color: entry.isError ? scheme.error : semantic.muted,
            ),
          ),
        );
    }
  }
}

/// A collapsed one-line tool call; expands to show arguments and result.
class _ToolCard extends StatefulWidget {
  const _ToolCard({required this.entry});

  final AgentChatEntry entry;

  @override
  State<_ToolCard> createState() => _ToolCardState();
}

class _ToolCardState extends State<_ToolCard> {
  bool _expanded = false;

  static String _clip(String s) =>
      s.length <= 1500 ? s : '${s.substring(0, 1500)}…';

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    final scheme = Theme.of(context).colorScheme;
    final entry = widget.entry;

    return Container(
      margin: const EdgeInsets.only(bottom: 8, right: 12),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border.all(color: semantic.line),
        borderRadius: BorderRadius.circular(AppRadii.control + 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(AppRadii.control + 2),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  if (entry.running)
                    SizedBox(
                      width: 13,
                      height: 13,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: scheme.primary,
                      ),
                    )
                  else
                    Icon(
                      entry.isError
                          ? Icons.error_outline
                          : Icons.check_circle_outline,
                      size: 14,
                      // A finished call is a small good-news event: the ok
                      // green says so at a glance while scrolling a long run.
                      color: entry.isError ? scheme.error : semantic.ok,
                    ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      entry.toolName,
                      overflow: TextOverflow.ellipsis,
                      style: monoStyle(context, size: 11.5),
                    ),
                  ),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 14,
                    color: semantic.muted,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Container(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (entry.toolArgs.isNotEmpty && entry.toolArgs != '{}')
                    SelectableText(
                      _clip(entry.toolArgs),
                      style: monoStyle(
                        context,
                        size: 10.5,
                        color: semantic.muted,
                      ),
                    ),
                  if (entry.toolResult.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    SelectableText(
                      _clip(entry.toolResult),
                      style: monoStyle(
                        context,
                        size: 10.5,
                        color: entry.isError ? scheme.error : null,
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// The merge rules the assistant proposed, laid out for review.
///
/// This is the deliverable of the planning phase, so it renders expanded
/// rather than as another collapsed tool row: the user is meant to read every
/// garment mapping and catch the wrong ones before anything is applied.
class _RulesCard extends StatelessWidget {
  const _RulesCard({required this.rules});

  final CharacterMergeRules rules;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final semantic = context.semantic;
    final scheme = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 8, right: 12),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      decoration: BoxDecoration(
        color: scheme.primary.withAlpha(14),
        border: Border.all(color: scheme.primary.withAlpha(90)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.rule, size: 14, color: scheme.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  rules.character.isEmpty
                      ? l10n.mergeRulesTitle
                      : '${l10n.mergeRulesTitle} · ${rules.character}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (rules.sampledImages > 0)
                Text(
                  l10n.mergeRulesSampled(rules.sampledImages),
                  style: TextStyle(fontSize: 10.5, color: semantic.muted),
                ),
            ],
          ),
          if (rules.triggerWord.isNotEmpty)
            _section(context, l10n.mergeRulesTrigger, [rules.triggerWord]),
          if (rules.identityTags.isNotEmpty)
            _section(context, l10n.mergeRulesIdentity, rules.identityTags),
          if (rules.conflictTags.isNotEmpty)
            _section(
              context,
              l10n.mergeRulesConflict,
              rules.conflictTags,
              muted: true,
            ),
          if (rules.garments.isNotEmpty) ...[
            _label(context, l10n.mergeRulesGarments),
            for (final g in rules.garments) _garment(context, l10n, g),
          ],
          if (rules.passthrough.isNotEmpty)
            _section(
              context,
              l10n.mergeRulesPassthrough,
              rules.passthrough,
              muted: true,
            ),
          if (rules.notes.isNotEmpty) ...[
            _label(context, l10n.mergeRulesNotes),
            Text(
              rules.notes,
              style: TextStyle(
                fontSize: 11,
                height: 1.45,
                color: semantic.muted,
              ),
            ),
          ],
          // The rules are saved but inert until a batch run applies them, and
          // that lives outside this panel.
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              l10n.mergeRulesApplyHint,
              style: TextStyle(
                fontSize: 10.5,
                height: 1.4,
                color: scheme.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 3),
    child: Text(
      text,
      style: TextStyle(fontSize: 10.5, color: context.semantic.muted),
    ),
  );

  Widget _section(
    BuildContext context,
    String label,
    List<String> tags, {
    bool muted = false,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _label(context, label),
      Text(
        tags.join(', '),
        style: monoStyle(
          context,
          size: 11,
          color: muted ? context.semantic.muted : null,
        ),
      ),
    ],
  );

  /// One garment: the tag that gets written, and what makes it fire. A
  /// garment with no evidence is the interesting failure — the user listed
  /// it, the sample never showed it — so it says so instead of looking like
  /// a rule that works.
  Widget _garment(BuildContext context, AppLocalizations l10n, GarmentRule g) {
    final semantic = context.semantic;
    final scheme = Theme.of(context).colorScheme;
    final fires = g.evidence.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                fires ? Icons.check : Icons.remove,
                size: 12,
                color: fires ? scheme.primary : semantic.muted,
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  g.tag,
                  style: monoStyle(
                    context,
                    size: 11,
                    color: fires ? null : semantic.muted,
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 17),
            child: Text(
              fires
                  ? l10n.mergeRulesEvidence(g.evidence.join(', '))
                  : l10n.mergeRulesNeverWritten,
              style: TextStyle(
                fontSize: 10.5,
                height: 1.4,
                color: semantic.muted,
              ),
            ),
          ),
          if (g.note.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 17, top: 1),
              child: Text(
                g.note,
                style: TextStyle(
                  fontSize: 10.5,
                  height: 1.4,
                  fontStyle: FontStyle.italic,
                  color: semantic.muted,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Confirmation bar for a pending write tool: shows what the assistant wants
/// to run and lets the user allow it once, allow everything this
/// conversation, or reject it.
class _ConfirmBar extends StatelessWidget {
  const _ConfirmBar({required this.chat});

  final AgentChatState chat;

  static String _clip(String s) =>
      s.length <= 300 ? s : '${s.substring(0, 300)}…';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final semantic = context.semantic;
    final scheme = Theme.of(context).colorScheme;
    final pending = chat.pendingConfirm!;

    return Container(
      margin: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: scheme.primary.withAlpha(18),
        border: Border.all(color: scheme.primary.withAlpha(120)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.shield_outlined, size: 14, color: scheme.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  l10n.agentConfirmTitle,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(pending.toolName, style: monoStyle(context, size: 11.5)),
          if (pending.argsJson.isNotEmpty && pending.argsJson != '{}')
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                _clip(pending.argsJson),
                style: monoStyle(context, size: 10.5, color: semantic.muted),
              ),
            ),
          const SizedBox(height: 6),
          Row(
            children: [
              FilledButton(
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  textStyle: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onPressed: () => chat.resolveConfirm(allow: true),
                child: Text(l10n.agentConfirmAllow),
              ),
              const SizedBox(width: 6),
              TextButton(
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  textStyle: const TextStyle(fontSize: 11.5),
                ),
                onPressed: () =>
                    chat.resolveConfirm(allow: true, allowAll: true),
                child: Text(l10n.agentConfirmAllowAll),
              ),
              const Spacer(),
              TextButton(
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  foregroundColor: scheme.error,
                  textStyle: const TextStyle(fontSize: 11.5),
                ),
                onPressed: () => chat.resolveConfirm(allow: false),
                child: Text(l10n.agentConfirmReject),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Multi-line input: grows up to 5 lines, Enter sends, Shift+Enter inserts a
/// newline, and the expand button opens the large composer dialog.
///
/// The field and its three actions sit inside one rounded slot so the whole
/// composer reads as a single control, the way the transcript above it reads
/// as a stack of cards.
class _InputRow extends StatelessWidget {
  const _InputRow({
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.onSend,
    required this.onExpand,
    required this.onPickPreset,
    required this.onStartSkill,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final VoidCallback onSend;
  final VoidCallback onExpand;
  final ValueChanged<PromptPreset> onPickPreset;
  final VoidCallback onStartSkill;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final semantic = context.semantic;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: semantic.line)),
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border.all(color: semantic.line),
          borderRadius: BorderRadius.circular(AppRadii.card),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              // Plain Enter sends; Shift+Enter falls through to the text
              // field's default newline insertion.
              child: CallbackShortcuts(
                bindings: {
                  const SingleActivator(LogicalKeyboardKey.enter): onSend,
                  const SingleActivator(LogicalKeyboardKey.numpadEnter): onSend,
                },
                child: Padding(
                  // Bottom-aligned against 30px action slots, the field's own
                  // baseline would otherwise sit a few pixels too low.
                  padding: const EdgeInsets.only(bottom: 6),
                  child: TextField(
                    controller: controller,
                    focusNode: focusNode,
                    enabled: enabled,
                    style: const TextStyle(fontSize: 12.5, height: 1.4),
                    decoration: InputDecoration(
                      hintText: l10n.agentInputHint,
                      hintStyle: TextStyle(fontSize: 12, color: semantic.muted),
                      // Unbounded, the placeholder wraps to four lines in a
                      // narrow panel and the empty composer opens that tall.
                      hintMaxLines: 1,
                      isDense: true,
                      filled: false,
                      contentPadding: EdgeInsets.zero,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                    ),
                    minLines: 1,
                    maxLines: 5,
                    keyboardType: TextInputType.multiline,
                    textInputAction: TextInputAction.newline,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            _PresetMenuButton(
              enabled: enabled,
              onPick: onPickPreset,
              onStartSkill: onStartSkill,
            ),
            const SizedBox(width: 6),
            _ChromeButton(
              icon: Icons.open_in_full,
              tooltip: l10n.agentExpandInput,
              onPressed: enabled ? onExpand : null,
            ),
            const SizedBox(width: 6),
            _ChromeButton(
              icon: Icons.send,
              tooltip: l10n.agentSend,
              fill: _ChromeFill.solid,
              onPressed: enabled ? onSend : null,
            ),
          ],
        ),
      ),
    );
  }
}

/// Footer under the composer: cumulative usage on the left, the send/newline
/// reminder on the right.
///
/// With a cap set the counter reads "used / cap" and turns amber near the
/// end, next to a bar of the same ratio: hitting the cap ends the run, and a
/// counter that only ever climbs gives no warning that it is coming.
class _InputFooter extends StatelessWidget {
  const _InputFooter({required this.chat});

  final AgentChatState chat;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final semantic = context.semantic;
    final scheme = Theme.of(context).colorScheme;
    final cap = chat.tokenCap;
    final used = chat.totalTokens;
    final nearCap = cap > 0 && used >= cap * 0.8;

    final hint = Text(
      l10n.agentKeyHint,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: AppText.micro, color: semantic.muted),
    );

    // The dock parks its resize grip in this corner, so the row stops short
    // of the panel's right edge.
    const padding = EdgeInsets.fromLTRB(12, 0, 20, 7);

    // Nothing counted yet: the whole footer is the keyboard hint, which is
    // exactly when a first-time user is looking for it.
    if (used == 0) {
      return Padding(
        padding: padding,
        child: Align(alignment: Alignment.centerRight, child: hint),
      );
    }

    return Padding(
      padding: padding,
      child: LayoutBuilder(
        builder: (context, constraints) => Row(
          children: [
            Flexible(
              child: Text(
                cap > 0
                    ? l10n.agentTokensUsedOfCap(used, cap)
                    : l10n.agentTokensUsed(used),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: monoStyle(
                  context,
                  size: 10.5,
                  color: nearCap ? semantic.warn : semantic.muted,
                ),
              ),
            ),
            if (cap > 0) ...[
              const SizedBox(width: 8),
              SizedBox(
                width: 72,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadii.pill),
                  child: LinearProgressIndicator(
                    value: (used / cap).clamp(0.0, 1.0),
                    minHeight: 4,
                    backgroundColor: semantic.line,
                    color: nearCap ? semantic.warn : scheme.primary,
                  ),
                ),
              ),
            ],
            // Beside a live counter the hint is the first thing to go: at
            // the panel's usual width there is only room for one of them,
            // and half a keyboard hint teaches nothing.
            if (constraints.maxWidth >= 460) ...[
              const SizedBox(width: 12),
              Flexible(child: hint),
            ],
          ],
        ),
      ),
    );
  }
}

/// The prompts shipped with the app: ready-made starting points for the
/// Anima JSON caption workflow. Built from l10n on each open so they follow
/// the UI language; the ids are stable but never persisted — picking one
/// only fills the input, exactly like a saved preset.
List<PromptPreset> builtinPromptPresets(AppLocalizations l10n) => [
  PromptPreset(
    id: 'builtin-anima-json-generate',
    title: l10n.animaJsonGeneratePresetTitle,
    content: l10n.animaJsonGeneratePresetBody,
  ),
  PromptPreset(
    id: 'builtin-anima-json-reorder',
    title: l10n.animaJsonReorderPresetTitle,
    content: l10n.animaJsonReorderPresetBody,
  ),
];

/// Picker next to the input: the built-in skills, the built-in prompts, the
/// saved prompts, and a way to manage the latter. A preset only fills the
/// input; a skill opens its own dialog and starts from there.
class _PresetMenuButton extends StatelessWidget {
  const _PresetMenuButton({
    required this.enabled,
    required this.onPick,
    required this.onStartSkill,
  });

  /// Mirrors the input field: presets cannot be inserted into a disabled
  /// field, but the manage entry stays reachable either way.
  final bool enabled;

  final ValueChanged<PromptPreset> onPick;
  final VoidCallback onStartSkill;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final semantic = context.semantic;
    final scheme = Theme.of(context).colorScheme;
    final presets = context.watch<AppState>().promptPresets;

    return PopupMenuButton<PromptPreset>(
      tooltip: l10n.promptPresetsTitle,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 220, maxWidth: 320),
      position: PopupMenuPosition.over,
      onSelected: onPick,
      // Matches the input row's other two slots; the tint marks it as the
      // one that brings its own content rather than acting on the field.
      child: _ChromeSlot(
        icon: Icons.auto_awesome,
        fill: _ChromeFill.tinted,
        enabled: enabled,
      ),
      itemBuilder: (_) => [
        PopupMenuItem<PromptPreset>(
          enabled: false,
          height: 28,
          child: Text(
            l10n.agentSkillsSection,
            style: TextStyle(fontSize: 10.5, color: semantic.muted),
          ),
        ),
        PopupMenuItem<PromptPreset>(
          enabled: enabled,
          height: 38,
          // Like the manage entry: the menu closes before this runs, so the
          // dialog opens from the panel's context, not the popup route's.
          onTap: onStartSkill,
          child: Row(
            children: [
              Icon(Icons.auto_awesome, size: 13, color: scheme.primary),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  l10n.characterSheetSkill,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11.5),
                ),
              ),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<PromptPreset>(
          enabled: false,
          height: 28,
          child: Text(
            l10n.builtinPresetsSection,
            style: TextStyle(fontSize: 10.5, color: semantic.muted),
          ),
        ),
        for (final preset in builtinPromptPresets(l10n))
          PopupMenuItem<PromptPreset>(
            value: preset,
            enabled: enabled,
            height: 42,
            child: _PresetMenuEntry(preset: preset),
          ),
        const PopupMenuDivider(),
        if (presets.isEmpty)
          PopupMenuItem<PromptPreset>(
            enabled: false,
            height: 34,
            child: Text(
              l10n.promptPresetsEmpty,
              style: TextStyle(fontSize: 11.5, color: semantic.muted),
            ),
          ),
        for (final preset in presets)
          PopupMenuItem<PromptPreset>(
            value: preset,
            enabled: enabled,
            height: 42,
            child: _PresetMenuEntry(preset: preset),
          ),
        const PopupMenuDivider(),
        PopupMenuItem<PromptPreset>(
          height: 34,
          // The menu closes before this runs, so it opens the dialog from
          // the panel's context rather than the popup route's.
          onTap: () => showPromptPresetsDialog(context),
          child: Row(
            children: [
              Icon(Icons.tune, size: 13, color: semantic.muted),
              const SizedBox(width: 7),
              Text(
                l10n.promptPresetsManage,
                style: TextStyle(fontSize: 11.5, color: semantic.muted),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PresetMenuEntry extends StatelessWidget {
  const _PresetMenuEntry({required this.preset});

  final PromptPreset preset;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final semantic = context.semantic;
    final body = preset.content.trim();
    final title = preset.title.trim().isNotEmpty
        ? preset.title.trim()
        : (body.isEmpty ? l10n.promptPresetUntitled : body.split('\n').first);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
        ),
        if (body.isNotEmpty)
          Text(
            body,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 10, color: semantic.muted),
          ),
      ],
    );
  }
}

/// Question card for the ask_user tool: the model's question, one button per
/// option, and a free-form reply field.
class _QuestionCard extends StatefulWidget {
  const _QuestionCard({required this.chat});

  final AgentChatState chat;

  @override
  State<_QuestionCard> createState() => _QuestionCardState();
}

class _QuestionCardState extends State<_QuestionCard> {
  final TextEditingController _reply = TextEditingController();

  @override
  void dispose() {
    _reply.dispose();
    super.dispose();
  }

  void _sendCustom() {
    final text = _reply.text.trim();
    if (text.isEmpty) return;
    _reply.clear();
    widget.chat.resolveQuestion(text);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final semantic = context.semantic;
    final scheme = Theme.of(context).colorScheme;
    final pending = widget.chat.pendingQuestion!;

    return Container(
      margin: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: scheme.primary.withAlpha(18),
        border: Border.all(color: scheme.primary.withAlpha(120)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.help_outline, size: 14, color: scheme.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  l10n.agentQuestionTitle,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 14),
                tooltip: l10n.agentQuestionDismiss,
                color: semantic.muted,
                visualDensity: VisualDensity.compact,
                onPressed: () => widget.chat.resolveQuestion(null),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SelectableText(
            pending.question,
            style: const TextStyle(fontSize: 12.5, height: 1.4),
          ),
          if (pending.options.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final option in pending.options)
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      textStyle: const TextStyle(fontSize: 11.5),
                    ),
                    onPressed: () => widget.chat.resolveQuestion(option),
                    child: Text(option),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _reply,
                  style: const TextStyle(fontSize: 12),
                  decoration: InputDecoration(
                    hintText: l10n.agentQuestionCustomHint,
                    hintStyle: TextStyle(fontSize: 11.5, color: semantic.muted),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 7,
                    ),
                    border: const OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _sendCustom(),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.send, size: 15),
                tooltip: l10n.agentSend,
                color: scheme.primary,
                visualDensity: VisualDensity.compact,
                onPressed: _sendCustom,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
