import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:reorderable_grid_view/reorderable_grid_view.dart';

import '../../l10n/app_localizations.dart';
import '../../state/editor_session.dart';
import '../../theme/app_theme.dart';

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
            child: Row(
              children: [
                _EditorTab(
                  label: l10n.textTab,
                  selected: _tab == _tabText,
                  onTap: () => setState(() => _tab = _tabText),
                ),
                _EditorTab(
                  label: l10n.tagsTab,
                  selected: _tab == _tabTags,
                  onTap: () => setState(() => _tab = _tabTags),
                ),
                const Spacer(),
                Flexible(
                  child: _SaveStateIndicator(session: session, l10n: l10n),
                ),
              ],
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
                      _buildTagsView(session, l10n, semantic),
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
      EditorSession session, AppLocalizations l10n, AppSemanticColors semantic) {
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
                  gridDelegate:
                      const SliverGridDelegateWithMaxCrossAxisExtent(
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
              prefixIconConstraints:
                  const BoxConstraints(minWidth: 30, minHeight: 30),
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

class _EditorTab extends StatelessWidget {
  const _EditorTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final semantic = context.semantic;
    return InkWell(
      onTap: onTap,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(7)),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected ? scheme.primary : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? scheme.onSurface : semantic.muted,
          ),
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
        if (session.lastSavedAt == null) {
          return Text(
            l10n.tagCount(session.tags.length),
            overflow: TextOverflow.ellipsis,
            style: monoStyle(context, size: 11.5, color: semantic.muted),
          );
        }
        icon = Icons.check_circle_outline;
        final t = session.lastSavedAt!;
        final hhmm = '${t.hour.toString().padLeft(2, '0')}:'
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
