import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:reorderable_grid_view/reorderable_grid_view.dart';

import '../../l10n/app_localizations.dart';
import '../../state/ai_tagger_state.dart';
import '../../state/editor_session.dart';
import '../../theme/app_theme.dart';
import '../../widgets/panel_widgets.dart';
import 'ai_compare_view.dart';
import 'ai_params_dialog.dart';

/// Center-bottom: the caption editor. Two views of the same caption — raw
/// text and a reorderable tag grid — plus a live save-state indicator.
class CaptionPanel extends StatefulWidget {
  const CaptionPanel({super.key});

  @override
  State<CaptionPanel> createState() => _CaptionPanelState();
}

class _CaptionPanelState extends State<CaptionPanel> {
  static const _tabText = 0;
  static const _tabTags = 1;

  int _tab = _tabTags;
  final TextEditingController _addTagController = TextEditingController();
  final FocusNode _addTagFocus = FocusNode();

  @override
  void dispose() {
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

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: semantic.panel,
        border: Border.all(color: semantic.line),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 12, 0),
            child: LayoutBuilder(
              builder: (context, constraints) {
                // On narrow center columns the AI button collapses to an icon
                // so the toolbar never overflows.
                final compact = constraints.maxWidth < 420;
                return Row(
                  children: [
                    PanelTab(
                      label: l10n.textTab,
                      selected: _tab == _tabText,
                      onTap: () => setState(() => _tab = _tabText),
                    ),
                    PanelTab(
                      label: l10n.tagsTab,
                      selected: _tab == _tabTags,
                      onTap: () => setState(() => _tab = _tabTags),
                    ),
                    // Single flex slot, right-aligned: keeps the AI buttons
                    // flush right instead of splitting free width with a
                    // Spacer.
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: _SaveStateIndicator(
                          session: session,
                          l10n: l10n,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    _AiRunButton(
                      ai: ai,
                      enabled: session.hasImage && !ai.running,
                      compact: compact,
                      onPressed: _runAi,
                      l10n: l10n,
                    ),
                    IconButton(
                      icon: const Icon(Icons.tune, size: 16),
                      tooltip: l10n.aiParamsTitle,
                      color: semantic.muted,
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints(
                        minWidth: 30,
                        minHeight: 30,
                      ),
                      padding: EdgeInsets.zero,
                      onPressed: () => showAiParamsDialog(context, ai),
                    ),
                  ],
                );
              },
            ),
          ),
          const Divider(),
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
                      ai.compareMode
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
              : ReorderableGridView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                  itemCount: session.tags.length,
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 170,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: 3.4,
                  ),
                  onReorder: session.reorderTag,
                  itemBuilder: (context, index) {
                    final tag = session.tags[index];
                    // Tags are de-duplicated on parse, so the tag itself is a
                    // stable key across reorders.
                    return _TagChip(
                      key: ValueKey(tag),
                      label: tag,
                      onTap: () => _editTag(session, index),
                      onDelete: () => session.removeTag(tag),
                    );
                  },
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
          child: TextField(
            controller: _addTagController,
            focusNode: _addTagFocus,
            style: const TextStyle(fontSize: 12.5),
            decoration: InputDecoration(
              hintText: l10n.addTagHint,
              prefixIcon: Icon(Icons.add, size: 15, color: semantic.muted),
              prefixIconConstraints: const BoxConstraints(
                minWidth: 30,
                minHeight: 30,
              ),
            ),
            onSubmitted: (value) {
              session.addTagsFromInput(value);
              _addTagController.clear();
              _addTagFocus.requestFocus();
            },
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
              color: semantic.muted,
            ),
          )
        : const Icon(Icons.auto_awesome, size: 14);

    if (compact) {
      return IconButton(
        icon: icon,
        tooltip: label,
        onPressed: enabled ? onPressed : null,
        color: Theme.of(context).colorScheme.primary,
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
        padding: EdgeInsets.zero,
      );
    }

    return TextButton.icon(
      onPressed: enabled ? onPressed : null,
      icon: icon,
      label: Text(label, style: const TextStyle(fontSize: 12)),
      style: TextButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        minimumSize: const Size(0, 28),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
        if (session.lastSavedAt == null) {
          return Text(
            l10n.tagCount(session.tags.length),
            overflow: TextOverflow.ellipsis,
            style: monoStyle(context, size: 11.5, color: semantic.muted),
          );
        }
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
        Text(
          l10n.tagCount(session.tags.length),
          style: monoStyle(context, size: 11.5, color: semantic.muted),
        ),
        const SizedBox(width: 12),
        ?leading,
        if (icon != null) Icon(icon, size: 13, color: color),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            text,
            overflow: TextOverflow.ellipsis,
            style: monoStyle(context, size: 11.5, color: color),
          ),
        ),
      ],
    );

    return tooltip == null ? row : Tooltip(message: tooltip, child: row);
  }
}

class _TagChip extends StatelessWidget {
  const _TagChip({
    super.key,
    required this.label,
    required this.onTap,
    required this.onDelete,
  });

  final String label;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(7),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9),
        decoration: BoxDecoration(
          color: semantic.raised,
          border: Border.all(color: semantic.line),
          borderRadius: BorderRadius.circular(7),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12),
              ),
            ),
            const SizedBox(width: 4),
            InkWell(
              onTap: onDelete,
              borderRadius: BorderRadius.circular(99),
              child: Icon(Icons.close, size: 12, color: semantic.muted),
            ),
          ],
        ),
      ),
    );
  }
}
