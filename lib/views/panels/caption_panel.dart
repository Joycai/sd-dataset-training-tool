import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:reorderable_grid_view/reorderable_grid_view.dart';

import '../../app_state.dart';
import '../../l10n/app_localizations.dart';
import '../../state/ai_tagger_state.dart';
import '../../state/editor_session.dart';
import '../../state/shortcut_relay.dart';
import '../../theme/app_theme.dart';
import '../../widgets/panel_widgets.dart';
import 'ai_compare_view.dart';
import 'ai_params_dialog.dart';

/// Center-bottom: the caption editor. Two views of the same caption — raw
/// text and a reorderable tag grid — plus a live save-state indicator.
class CaptionPanel extends StatefulWidget {
  const CaptionPanel({super.key, this.shortcutRelay});

  /// Lets workbench-level shortcuts trigger the AI run implemented here.
  final ShortcutRelay? shortcutRelay;

  @override
  State<CaptionPanel> createState() => _CaptionPanelState();
}

class _CaptionPanelState extends State<CaptionPanel> {
  static const _tabText = 0;
  static const _tabTags = 1;

  int _tab = _tabTags;

  /// Tags-tab interaction mode: false = edit (click to edit, long-press to
  /// drag), true = sort (drag immediately, no editing). Lives on the panel
  /// state so it survives image switches.
  bool _sortMode = false;

  final TextEditingController _addTagController = TextEditingController();
  final FocusNode _addTagFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    widget.shortcutRelay?.runAiForCurrentImage = _runAi;
  }

  @override
  void dispose() {
    widget.shortcutRelay?.runAiForCurrentImage = null;
    _addTagController.dispose();
    _addTagFocus.dispose();
    super.dispose();
  }

  /// Runs AI interrogation for the current image. Bootstraps the model list
  /// on first use; opens the params dialog when no model can be resolved.
  Future<void> _runAi() async {
    final ai = context.read<AiTaggerState>();
    final session = context.read<EditorSession>();
    final image = session.image;
    if (image == null || ai.running) return;

    if (ai.modelName == null) {
      await ai.refreshModels();
      if (!mounted) return;
      if (ai.modelName == null) {
        final l10n = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              ai.lastError == null
                  ? l10n.aiNoModelSelected
                  : l10n.aiFailed(ai.lastError!),
            ),
          ),
        );
        await showAiParamsDialog(context, ai);
        return;
      }
    }

    // Compare mode lives in the tags tab; make it visible right away so the
    // running indicator shows where the result will land.
    setState(() => _tab = _tabTags);
    final hadResult = ai.hasResultFor(image.path);
    ai.enterCompareMode();
    final ok = await ai.interrogate(image);
    if (!ok) {
      // Don't strand the user on an empty compare view.
      if (!hadResult) ai.exitCompareMode();
      if (mounted && ai.lastError != null) {
        final l10n = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.aiFailed(ai.lastError!))));
      }
    }
  }

  Future<void> _editTag(EditorSession session, int index) async {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController(text: session.tags[index]);
    final newValue = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.editTagTitle),
        content: TextField(
          controller: controller,
          autofocus: true,
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: Text(l10n.confirm),
          ),
        ],
      ),
    );
    if (newValue != null) {
      session.replaceTagAt(index, newValue);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final semantic = context.semantic;
    final session = context.watch<EditorSession>();
    final ai = context.watch<AiTaggerState>();

    // The editor is a panel under the canvas, not a floating card: one
    // hairline separates them and the fill runs to the window edges.
    return Container(
      decoration: BoxDecoration(
        color: semantic.panel,
        border: Border(top: BorderSide(color: semantic.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 7, 10, 7),
            child: LayoutBuilder(
              builder: (context, constraints) {
                // On narrow center columns the labelled buttons collapse to
                // icons so the toolbar never overflows. Compare mode adds a
                // second labelled button, so it needs the wider budget —
                // one flat threshold would either overflow there or hide the
                // AI label at widths that comfortably fit it.
                final compact =
                    constraints.maxWidth < (ai.compareMode ? 520 : 380);
                return Row(
                  children: [
                    SizedBox(
                      width: 128,
                      child: SegmentedControl<int>(
                        value: _tab,
                        onChanged: (value) => setState(() => _tab = value),
                        fontSize: AppText.secondary,
                        segments: [
                          SegmentedOption(value: _tabTags, label: l10n.tagsTab),
                          SegmentedOption(value: _tabText, label: l10n.textTab),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    // The count owns the only flex slot. Pairing it with a
                    // second flex child would hand half the slack to the save
                    // indicator even when that renders nothing, and the count
                    // would ellipsize with room to spare.
                    Expanded(
                      child: Text(
                        l10n.tagCount(session.tags.length),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: monoStyle(
                          context,
                          size: AppText.small,
                          color: semantic.muted,
                        ),
                      ),
                    ),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 130),
                      child: _SaveStateIndicator(session: session, l10n: l10n),
                    ),
                    const SizedBox(width: 10),
                    // Compare mode is a global flag; its exit control sits up
                    // here (not inside the compare view) so it doesn't read
                    // as a per-image action.
                    if (ai.compareMode) ...[
                      compact
                          ? IconButton(
                              icon: const Icon(Icons.compare_arrows, size: 16),
                              tooltip: l10n.aiExitCompareTooltip,
                              color: Theme.of(context).colorScheme.primary,
                              visualDensity: VisualDensity.compact,
                              constraints: const BoxConstraints(
                                minWidth: 30,
                                minHeight: 30,
                              ),
                              padding: EdgeInsets.zero,
                              onPressed: ai.exitCompareMode,
                            )
                          : Tooltip(
                              message: l10n.aiExitCompareTooltip,
                              child: FilledButton.tonalIcon(
                                onPressed: ai.exitCompareMode,
                                icon: const Icon(
                                  Icons.compare_arrows,
                                  size: 14,
                                ),
                                label: Text(
                                  l10n.aiExitCompare,
                                  style: const TextStyle(fontSize: 12),
                                ),
                                style: FilledButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                  ),
                                  minimumSize: const Size(0, 28),
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                              ),
                            ),
                      const SizedBox(width: 4),
                    ],
                    _AiRunButton(
                      ai: ai,
                      enabled: session.hasImage && !ai.running,
                      compact: compact,
                      onPressed: _runAi,
                      l10n: l10n,
                    ),
                    const SizedBox(width: 6),
                    _OutlinedIconButton(
                      icon: Icons.tune,
                      tooltip: l10n.aiParamsTitle,
                      onPressed: () => showAiParamsDialog(context, ai),
                    ),
                  ],
                );
              },
            ),
          ),
          Container(height: 1, color: semantic.line),
          Expanded(
            child: !session.hasImage
                ? Center(
                    child: Text(
                      l10n.selectImageHint,
                      style: TextStyle(fontSize: 12.5, color: semantic.muted),
                    ),
                  )
                : IndexedStack(
                    index: _tab,
                    sizing: StackFit.expand,
                    children: [
                      _buildTextView(session, l10n),
                      // Compare mode is a global flag, but it only makes sense
                      // for images that actually have (or are getting) a
                      // result — other images keep the normal tags view.
                      ai.compareMode &&
                              (ai.running ||
                                  ai.hasResultFor(session.image!.path))
                          ? AiCompareView(onRunAi: _runAi)
                          : _buildTagsView(session, l10n, semantic),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextView(EditorSession session, AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: TextField(
        controller: session.captionController,
        maxLines: null,
        expands: true,
        textAlignVertical: TextAlignVertical.top,
        style: const TextStyle(fontSize: 13, height: 1.6),
        decoration: InputDecoration(
          hintText: l10n.captionHint,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          filled: false,
          contentPadding: EdgeInsets.zero,
        ),
      ),
    );
  }

  Widget _buildTagsView(
    EditorSession session,
    AppLocalizations l10n,
    AppSemanticColors semantic,
  ) {
    return Column(
      children: [
        Expanded(
          child: session.tags.isEmpty
              ? Center(
                  child: Text(
                    l10n.noTagsYet,
                    style: TextStyle(fontSize: 12.5, color: semantic.muted),
                  ),
                )
              // A flowing wrap, not a grid: chips size to their tag, so long
              // tags stop being truncated to a fixed cell width. Reordering
              // hit-tests the real chip boxes (same pattern as the compare
              // view's left column).
              : ReorderableWrapperWidget(
                  onReorder: session.reorderTag,
                  // Sort mode: drag starts immediately instead of after a
                  // long press. Null keeps the package's long-press default.
                  dragStartDelay: _sortMode ? Duration.zero : null,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final (index, tag) in session.tags.indexed)
                          // Tags are de-duplicated on parse, so the tag itself
                          // is a stable key across reorders.
                          ReorderableItemView(
                            key: ValueKey(tag),
                            index: index,
                            // The trailing holder anchors insertion after this
                            // tag; new tags from any source land there. In
                            // sort mode the immediate drag recognizer swallows
                            // its taps, so it is display-only there.
                            child: AnchorableTag(
                              active: session.anchorTag == tag,
                              tooltip: l10n.tagAnchorHolderTooltip,
                              onToggle: () => session.setAnchorTag(
                                session.anchorTag == tag ? null : tag,
                              ),
                              child: _TagChip(
                                label: tag,
                                sortMode: _sortMode,
                                groupColor: context
                                    .watch<AppState>()
                                    .groupOfTag(tag)
                                    ?.color,
                                onTap: () => _editTag(session, index),
                                onDelete: () => session.removeTag(tag),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
        ),
        Container(height: 1, color: semantic.line),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 4, 6, 4),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _addTagController,
                  focusNode: _addTagFocus,
                  style: const TextStyle(fontSize: AppText.secondary),
                  // Borderless: the hairline above already separates this
                  // row, and a boxed field inside a panel footer reads as a
                  // second frame.
                  decoration: InputDecoration(
                    hintText: l10n.addTagHint,
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    prefixIcon: Icon(
                      Icons.add,
                      size: 15,
                      color: semantic.muted,
                    ),
                    prefixIconConstraints: const BoxConstraints(
                      minWidth: 26,
                      minHeight: 26,
                    ),
                  ),
                  onSubmitted: (value) {
                    session.addTagsFromInput(value);
                    _addTagController.clear();
                    _addTagFocus.requestFocus();
                  },
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.drag_indicator, size: 16),
                tooltip: l10n.tagSortModeTooltip,
                isSelected: _sortMode,
                color: semantic.muted,
                selectedIcon: Icon(
                  Icons.drag_indicator,
                  size: 16,
                  color: Theme.of(context).colorScheme.primary,
                ),
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                padding: EdgeInsets.zero,
                onPressed: () => setState(() => _sortMode = !_sortMode),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AiRunButton extends StatelessWidget {
  const _AiRunButton({
    required this.ai,
    required this.enabled,
    required this.compact,
    required this.onPressed,
    required this.l10n,
  });

  final AiTaggerState ai;
  final bool enabled;
  final bool compact;
  final VoidCallback onPressed;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    final label = ai.running ? l10n.aiInterrogating : l10n.aiInterrogateButton;
    final icon = ai.running
        ? SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              color: compact
                  ? semantic.muted
                  : Theme.of(context).colorScheme.onPrimary,
            ),
          )
        : const Icon(Icons.auto_awesome, size: 14);

    if (compact) {
      return IconButton(
        icon: icon,
        tooltip: '$label (Ctrl+E)',
        onPressed: enabled ? onPressed : null,
        color: Theme.of(context).colorScheme.primary,
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
        padding: EdgeInsets.zero,
      );
    }

    // The one filled, accented control in the editor: AI tagging is the
    // primary action of this toolbar.
    return Tooltip(
      message: '$label (Ctrl+E)',
      child: FilledButton.icon(
        onPressed: enabled ? onPressed : null,
        icon: icon,
        label: Text(
          label,
          style: const TextStyle(
            fontSize: AppText.secondary,
            fontWeight: FontWeight.w600,
          ),
        ),
        style: FilledButton.styleFrom(
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          minimumSize: const Size(0, 28),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.input),
          ),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    );
  }
}

class _SaveStateIndicator extends StatelessWidget {
  const _SaveStateIndicator({required this.session, required this.l10n});

  final EditorSession session;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    final scheme = Theme.of(context).colorScheme;

    IconData? icon;
    Widget? leading;
    String text;
    Color color;
    String? tooltip;

    switch (session.saveState) {
      case SaveState.dirty:
        icon = Icons.edit_outlined;
        text = l10n.unsavedChanges;
        color = semantic.warn;
      case SaveState.saving:
        leading = SizedBox(
          width: 11,
          height: 11,
          child: CircularProgressIndicator(
            strokeWidth: 1.5,
            color: semantic.muted,
          ),
        );
        text = l10n.savingNow;
        color = semantic.muted;
      case SaveState.error:
        icon = Icons.error_outline;
        text = l10n.saveFailed;
        color = scheme.error;
        tooltip = session.lastError;
      case SaveState.saved:
      case SaveState.clean:
        // Nothing saved yet in this session: the toolbar's tag count already
        // says everything there is to say.
        if (session.lastSavedAt == null) return const SizedBox.shrink();
        icon = Icons.check_circle_outline;
        final t = session.lastSavedAt!;
        final hhmm =
            '${t.hour.toString().padLeft(2, '0')}:'
            '${t.minute.toString().padLeft(2, '0')}';
        text = l10n.savedAt(hhmm);
        color = semantic.ok;
    }

    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ?leading,
        if (icon != null) Icon(icon, size: 13, color: color),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            text,
            overflow: TextOverflow.ellipsis,
            style: monoStyle(context, size: AppText.small, color: color),
          ),
        ),
      ],
    );

    return tooltip == null ? row : Tooltip(message: tooltip, child: row);
  }
}

class _TagChip extends StatelessWidget {
  const _TagChip({
    required this.label,
    required this.onTap,
    required this.onDelete,
    this.sortMode = false,
    this.groupColor,
  });

  final String label;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  /// Sort mode: the chip is drag-only — no tap-to-edit, and the delete
  /// button is replaced by a drag handle (immediate drag would swallow the
  /// taps anyway).
  final bool sortMode;

  /// ARGB tint from the tag's library group; null keeps the default look.
  final int? groupColor;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    final tint = groupColor == null ? null : Color(groupColor!);
    // Intrinsic width: the chip is as wide as its tag, which is what makes
    // the wrap readable at a glance.
    final body = Container(
      padding: const EdgeInsets.fromLTRB(10, 3, 7, 3),
      decoration: BoxDecoration(
        color: tint == null
            ? semantic.raised
            : Color.alphaBlend(tint.withAlpha(33), semantic.raised),
        border: Border.all(color: tint?.withAlpha(153) ?? semantic.line),
        borderRadius: BorderRadius.circular(AppRadii.control),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(fontSize: AppText.secondary)),
          const SizedBox(width: 6),
          if (sortMode)
            Icon(Icons.drag_indicator, size: 12, color: semantic.muted)
          else
            InkWell(
              onTap: onDelete,
              borderRadius: BorderRadius.circular(AppRadii.pill),
              child: Icon(Icons.close, size: 12, color: semantic.muted),
            ),
        ],
      ),
    );

    if (sortMode) {
      return MouseRegion(cursor: SystemMouseCursors.grab, child: body);
    }
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.control),
      child: body,
    );
  }
}

/// Outlined square icon button — the secondary partner to the filled AI
/// action in the editor toolbar.
class _OutlinedIconButton extends StatelessWidget {
  const _OutlinedIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    return Tooltip(
      message: tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onPressed,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
            decoration: BoxDecoration(
              border: Border.all(color: semantic.line),
              borderRadius: BorderRadius.circular(AppRadii.input),
            ),
            child: Icon(icon, size: 15, color: semantic.muted),
          ),
        ),
      ),
    );
  }
}
