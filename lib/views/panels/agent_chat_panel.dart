import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:markdown_widget/markdown_widget.dart';
import 'package:provider/provider.dart';

import '../settings_view.dart';
import '../../app_state.dart';
import '../../l10n/app_localizations.dart';
import '../../models/llm_models.dart';
import '../../models/prompt_preset.dart';
import '../../state/agent_chat_state.dart';
import '../../theme/app_theme.dart';
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
        ),
        if (chat.totalTokens > 0) _UsageFooter(chat: chat),
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
          height: 40,
          padding: const EdgeInsets.only(left: 12, right: 4),
          decoration: BoxDecoration(
            border: minimized
                ? null
                : Border(bottom: BorderSide(color: semantic.line)),
          ),
          child: Row(
            children: [
              Icon(
                Icons.smart_toy_outlined,
                size: 15,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.agentPanelTitle,
                      // Two stacked rows in a 40px bar leave the title no
                      // room to wrap when the panel is dragged narrow.
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    _ProfileMenuButton(chat: chat),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add_comment_outlined, size: 16),
                tooltip: l10n.agentNewSession,
                color: semantic.muted,
                visualDensity: VisualDensity.compact,
                onPressed: chat.busy ? null : () => chat.resetSession(),
              ),
              IconButton(
                icon: Icon(
                  minimized ? Icons.expand_less : Icons.remove,
                  size: 16,
                ),
                tooltip: minimized ? l10n.agentExpand : l10n.agentMinimize,
                color: semantic.muted,
                visualDensity: VisualDensity.compact,
                onPressed: onToggleMinimized,
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 16),
                tooltip: l10n.cancel,
                color: semantic.muted,
                visualDensity: VisualDensity.compact,
                onPressed: onClose,
              ),
            ],
          ),
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
          Flexible(
            child: Text(
              chat.profileName ?? l10n.llmNoProfiles,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10, color: semantic.muted),
            ),
          ),
          Icon(Icons.arrow_drop_down, size: 13, color: semantic.muted),
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
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: scheme.primary.withAlpha(28),
                borderRadius: BorderRadius.circular(9),
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
        borderRadius: BorderRadius.circular(7),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(7),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                children: [
                  if (entry.running)
                    SizedBox(
                      width: 11,
                      height: 11,
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
                      size: 13,
                      color: entry.isError ? scheme.error : semantic.muted,
                    ),
                  const SizedBox(width: 7),
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
class _InputRow extends StatelessWidget {
  const _InputRow({
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.onSend,
    required this.onExpand,
    required this.onPickPreset,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final VoidCallback onSend;
  final VoidCallback onExpand;
  final ValueChanged<PromptPreset> onPickPreset;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final semantic = context.semantic;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: semantic.line)),
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
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                enabled: enabled,
                style: const TextStyle(fontSize: 12.5, height: 1.4),
                decoration: InputDecoration(
                  hintText: l10n.agentInputHint,
                  hintStyle: TextStyle(fontSize: 12, color: semantic.muted),
                  isDense: true,
                  border: InputBorder.none,
                ),
                minLines: 1,
                maxLines: 5,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
              ),
            ),
          ),
          _PresetMenuButton(enabled: enabled, onPick: onPickPreset),
          IconButton(
            icon: const Icon(Icons.open_in_full, size: 15),
            tooltip: l10n.agentExpandInput,
            color: semantic.muted,
            visualDensity: VisualDensity.compact,
            onPressed: enabled ? onExpand : null,
          ),
          IconButton(
            icon: const Icon(Icons.send, size: 16),
            tooltip: l10n.agentSend,
            color: Theme.of(context).colorScheme.primary,
            visualDensity: VisualDensity.compact,
            onPressed: enabled ? onSend : null,
          ),
        ],
      ),
    );
  }
}

/// Cumulative usage of the conversation. With a cap set it reads "used /
/// cap" and turns amber near the end: hitting the cap ends the run, and a
/// counter that only ever climbs gives no warning that it is coming.
class _UsageFooter extends StatelessWidget {
  const _UsageFooter({required this.chat});

  final AgentChatState chat;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final semantic = context.semantic;
    final cap = chat.tokenCap;
    final nearCap = cap > 0 && chat.totalTokens >= cap * 0.8;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Text(
        cap > 0
            ? l10n.agentTokensUsedOfCap(chat.totalTokens, cap)
            : l10n.agentTokensUsed(chat.totalTokens),
        style: monoStyle(
          context,
          size: 10.5,
          color: nearCap ? semantic.warn : semantic.muted,
        ),
      ),
    );
  }
}

/// Prompt-preset picker next to the input: the saved prompts, plus a way to
/// manage them. Picking one fills the input; it never sends on its own.
class _PresetMenuButton extends StatelessWidget {
  const _PresetMenuButton({required this.enabled, required this.onPick});

  /// Mirrors the input field: presets cannot be inserted into a disabled
  /// field, but the manage entry stays reachable either way.
  final bool enabled;

  final ValueChanged<PromptPreset> onPick;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final semantic = context.semantic;
    final presets = context.watch<AppState>().promptPresets;

    return PopupMenuButton<PromptPreset>(
      tooltip: l10n.promptPresetsTitle,
      icon: const Icon(Icons.bookmark_border, size: 15),
      iconColor: semantic.muted,
      iconSize: 15,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 220, maxWidth: 320),
      position: PopupMenuPosition.over,
      onSelected: onPick,
      itemBuilder: (_) => [
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
