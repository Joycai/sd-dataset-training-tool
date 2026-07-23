import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/tag_filter.dart';
import '../../state/dataset_state.dart';
import '../../state/editor_session.dart';
import '../../state/tag_ops.dart';
import '../../theme/app_theme.dart';
import '../../widgets/panel_widgets.dart';

enum _TagMenuAction {
  filterInclude,
  filterExclude,
  replaceAppend,
  deleteGlobal,
}

enum _EditMode { replace, insertBefore, insertAfter }

enum _AddPosition { head, tail, at }

/// Right panel, "Dataset" tab: every tag in the dataset with its image count.
/// Green marks tags present on the current image; click toggles the tag on
/// it; right-click offers gallery filtering and dataset-wide edits.
class DatasetTagsView extends StatefulWidget {
  const DatasetTagsView({super.key});

  @override
  State<DatasetTagsView> createState() => _DatasetTagsViewState();
}

class _DatasetTagsViewState extends State<DatasetTagsView> {
  String _filter = '';

  Future<void> _showTagMenu(Offset position, DatasetTag entry) async {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final dataset = context.read<DatasetState>();
    final action = await showPanelContextMenu<_TagMenuAction>(
      context: context,
      position: position,
      items: [
        panelMenuItem(
          context: context,
          value: _TagMenuAction.filterInclude,
          icon: Icons.filter_alt_outlined,
          label: l10n.menuFilterInclude,
        ),
        panelMenuItem(
          context: context,
          value: _TagMenuAction.filterExclude,
          icon: Icons.visibility_off_outlined,
          label: l10n.menuFilterExclude,
        ),
        const PopupMenuDivider(height: 8),
        panelMenuItem(
          context: context,
          value: _TagMenuAction.replaceAppend,
          icon: Icons.find_replace,
          label: l10n.menuReplaceAppend,
        ),
        panelMenuItem(
          context: context,
          value: _TagMenuAction.deleteGlobal,
          icon: Icons.delete_forever_outlined,
          label: l10n.menuDeleteGlobal,
          color: scheme.error,
        ),
      ],
    );
    if (!mounted || action == null) return;
    switch (action) {
      case _TagMenuAction.filterInclude:
        dataset.setTagFilter(entry.tag, exclude: false);
      case _TagMenuAction.filterExclude:
        dataset.setTagFilter(entry.tag, exclude: true);
      case _TagMenuAction.replaceAppend:
        await _showReplaceDialog(entry);
      case _TagMenuAction.deleteGlobal:
        await _confirmDelete(entry);
    }
  }

  Future<void> _confirmDelete(DatasetTag entry) async {
    final l10n = AppLocalizations.of(context)!;
    final dataset = context.read<DatasetState>();
    final ops = context.read<TagOps>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.deleteTagConfirmTitle),
        content: SizedBox(
          width: 380,
          child: Text(
            l10n.deleteTagConfirmContent(entry.count, entry.tag),
            style: const TextStyle(fontSize: 13, height: 1.5),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final count = await ops.deleteEverywhere(
      entry.tag,
      label: l10n.opDeleteLabel(entry.tag),
    );
    // Conditions on a tag that no longer exists are stale (an include would
    // blank the gallery); drop them from the expression.
    dataset.removeTagFromFilter(entry.tag);
    _showResult(count);
  }

  Future<void> _showReplaceDialog(DatasetTag entry) async {
    final l10n = AppLocalizations.of(context)!;
    final ops = context.read<TagOps>();
    final result = await showDialog<(_EditMode, String)>(
      context: context,
      builder: (context) => _ReplaceDialog(tag: entry.tag),
    );
    if (result == null || !mounted) return;

    final (mode, input) = result;
    final count = switch (mode) {
      _EditMode.replace => await ops.replaceEverywhere(
        entry.tag,
        input,
        label: l10n.opReplaceLabel(entry.tag),
      ),
      _EditMode.insertBefore => await ops.insertBeside(
        entry.tag,
        input,
        after: false,
        label: l10n.opInsertLabel(entry.tag),
      ),
      _EditMode.insertAfter => await ops.insertBeside(
        entry.tag,
        input,
        after: true,
        label: l10n.opInsertLabel(entry.tag),
      ),
    };
    _showResult(count);
  }

  Future<void> _showAddTagsDialog() async {
    final l10n = AppLocalizations.of(context)!;
    final dataset = context.read<DatasetState>();
    final ops = context.read<TagOps>();
    final result = await showDialog<(String, int?, bool)>(
      context: context,
      builder: (context) => _AddTagsDialog(
        totalCount: dataset.totalCount,
        filteredCount: dataset.visibleFiles.length,
      ),
    );
    if (result == null || !mounted) return;

    final (input, index, onlyFiltered) = result;
    final count = await ops.addEverywhere(
      input,
      index: index,
      files: onlyFiltered ? List.of(dataset.visibleFiles) : null,
      label: l10n.opAddGlobalLabel(input.trim()),
    );
    _showResult(count);
  }

  void _showResult(int count) {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          count == 0 ? l10n.noFilesChanged : l10n.filesUpdated(count),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final semantic = context.semantic;
    final dataset = context.watch<DatasetState>();
    final session = context.watch<EditorSession>();
    final ops = context.watch<TagOps>();

    final allTags = dataset.datasetTags;
    final query = _filter.trim().toLowerCase();
    final visibleTags = query.isEmpty
        ? allTags
        : allTags.where((t) => t.tag.toLowerCase().contains(query)).toList();
    final refs = filterReferencedTags(dataset.tagFilterExpression);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PanelHeader(
          title: l10n.datasetTagsTitle,
          count: allTags.length,
          actions: [
            PanelIconButton(
              icon: Icons.playlist_add,
              tooltip: l10n.addTagsGlobalTooltip,
              onPressed: dataset.totalCount > 0 && !ops.busy
                  ? _showAddTagsDialog
                  : null,
            ),
            PanelIconButton(
              icon: Icons.filter_alt_off_outlined,
              tooltip: l10n.clearTagFilter,
              onPressed: dataset.tagFilterActive
                  ? dataset.clearTagFilter
                  : null,
            ),
          ],
        ),
        PanelSearchField(
          hint: l10n.filterTagsHint,
          onChanged: (value) => setState(() => _filter = value),
        ),
        if (dataset.tagFilterActive)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: _FilterExpressionPanel(dataset: dataset),
          ),
        Expanded(
          child: allTags.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      l10n.datasetTagsEmpty,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12.5, color: semantic.muted),
                    ),
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.datasetTagsHint,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.3,
                          color: semantic.muted,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 7,
                        runSpacing: 7,
                        children: [
                          for (final entry in visibleTags)
                            _DatasetTagChip(
                              entry: entry,
                              applied: session.hasTag(entry.tag),
                              filtered:
                                  refs.included.contains(entry.tag) ||
                                  refs.excluded.contains(entry.tag),
                              // Excluded-only tags show the eye-off glyph; a
                              // tag used both ways keeps the include glyph.
                              filterExclude:
                                  !refs.included.contains(entry.tag) &&
                                  refs.excluded.contains(entry.tag),
                              enabled: session.hasImage && !ops.busy,
                              onTap: () => session.toggleTag(entry.tag),
                              onContextMenu: (position) =>
                                  _showTagMenu(position, entry),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}

/// The gallery's boolean filter, rendered as nested chip groups. Every edit
/// rebuilds the immutable tree via the tag_filter helpers and pushes it back
/// through [DatasetState.setTagFilterExpression].
class _FilterExpressionPanel extends StatelessWidget {
  const _FilterExpressionPanel({required this.dataset});

  final DatasetState dataset;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final semantic = context.semantic;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 7, 10, 9),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: semantic.line),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.filterPanelTitle,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                    color: semantic.muted,
                  ),
                ),
              ),
              Text(
                l10n.filterMatches(
                  dataset.visibleFiles.length,
                  dataset.totalCount,
                ),
                style: monoStyle(context, size: 11, color: semantic.muted),
              ),
            ],
          ),
          const SizedBox(height: 7),
          // Deep expressions grow downward; cap the height so the tag list
          // below stays usable.
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 180),
            child: SingleChildScrollView(
              child: _FilterGroupView(
                dataset: dataset,
                group: dataset.tagFilterExpression,
                depth: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One group of the expression: its children joined by op pills, wrapped in
/// literal parentheses tinted by nesting depth (teal, purple, pink) so
/// membership of a sub-group reads at a glance. The root has neither border
/// nor parens — it is the whole expression.
class _FilterGroupView extends StatelessWidget {
  const _FilterGroupView({
    required this.dataset,
    required this.group,
    required this.depth,
  });

  final DatasetState dataset;
  final TagFilterGroup group;
  final int depth;

  /// Hue cycle for sub-group depth: accent, then purple/pink from the group
  /// preset palette (distinct from the semantic colors).
  Color _depthColor(BuildContext context) {
    return switch ((depth - 1) % 3) {
      0 => Theme.of(context).colorScheme.primary,
      1 => const Color(0xFF9B84E0),
      _ => const Color(0xFFD983A6),
    };
  }

  void _edit(TagFilterGroup next) => dataset.setTagFilterExpression(next);

  Future<void> _showAddMenu(BuildContext context, Offset position) async {
    final l10n = AppLocalizations.of(context)!;
    final action = await showPanelContextMenu<String>(
      context: context,
      position: position,
      items: [
        panelMenuItem(
          context: context,
          value: 'condition',
          icon: Icons.filter_alt_outlined,
          label: l10n.filterAddCondition,
        ),
        panelMenuItem(
          context: context,
          value: 'group',
          icon: Icons.account_tree_outlined,
          label: l10n.filterAddSubgroup,
        ),
      ],
    );
    if (action == null || !context.mounted) return;

    if (action == 'group') {
      // A fresh sub-group starts on the opposite operator — that is why one
      // reaches for parentheses in the first place.
      _edit(
        filterAddTo(
          dataset.tagFilterExpression,
          group.id,
          TagFilterGroup.create(
            group.op == TagFilterOp.and ? TagFilterOp.or : TagFilterOp.and,
          ),
        ),
      );
      return;
    }

    final picked = await showDialog<(String, bool)>(
      context: context,
      builder: (context) =>
          _ConditionPickerDialog(tags: dataset.datasetTags),
    );
    if (picked == null) return;
    _edit(
      filterAddTo(
        dataset.tagFilterExpression,
        group.id,
        TagFilterCondition.create(picked.$1, exclude: picked.$2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final semantic = context.semantic;
    final isRoot = depth == 0;
    final color = isRoot ? semantic.line : _depthColor(context);

    final children = <Widget>[
      if (!isRoot) _Paren(text: '(', color: color),
      for (final (i, child) in group.children.indexed) ...[
        if (i > 0)
          _OpPill(
            op: group.op,
            label: group.op == TagFilterOp.and
                ? l10n.filterOpAnd
                : l10n.filterOpOr,
            tooltip: l10n.filterToggleOpTooltip,
            onTap: () => _edit(
              filterToggleOp(dataset.tagFilterExpression, group.id),
            ),
          ),
        switch (child) {
          TagFilterCondition c => _ConditionChip(
              condition: c,
              toggleTooltip: l10n.filterToggleRoleTooltip,
              removeTooltip: l10n.filterRemoveConditionTooltip,
              onToggleRole: () => _edit(
                filterToggleRole(dataset.tagFilterExpression, c.id),
              ),
              onRemove: () => _edit(
                filterRemove(dataset.tagFilterExpression, c.id),
              ),
            ),
          TagFilterGroup g => _FilterGroupView(
              dataset: dataset,
              group: g,
              depth: depth + 1,
            ),
        },
      ],
      if (!isRoot) _Paren(text: ')', color: color),
      Builder(
        builder: (buttonContext) => Tooltip(
          message: l10n.filterAddTooltip,
          child: InkWell(
            borderRadius: BorderRadius.circular(99),
            onTap: () {
              final box = buttonContext.findRenderObject()! as RenderBox;
              _showAddMenu(
                buttonContext,
                box.localToGlobal(Offset(0, box.size.height)),
              );
            },
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: semantic.line),
              ),
              child: Icon(Icons.add, size: 13, color: semantic.muted),
            ),
          ),
        ),
      ),
      if (!isRoot)
        Tooltip(
          message: l10n.filterDissolveGroupTooltip,
          child: InkWell(
            borderRadius: BorderRadius.circular(99),
            onTap: () => _edit(
              filterDissolve(dataset.tagFilterExpression, group.id),
            ),
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: Icon(Icons.close, size: 12, color: semantic.muted),
            ),
          ),
        ),
    ];

    final wrap = Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: children,
    );

    if (isRoot) return wrap;
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
      decoration: BoxDecoration(
        color: color.withAlpha(23),
        border: Border.all(color: color.withAlpha(140), width: 1.5),
        borderRadius: BorderRadius.circular(9),
      ),
      child: wrap,
    );
  }
}

class _Paren extends StatelessWidget {
  const _Paren({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w300,
        height: 1,
        color: color,
      ),
    );
  }
}

/// The 且/或 joint between two siblings; clicking flips the whole group.
class _OpPill extends StatelessWidget {
  const _OpPill({
    required this.op,
    required this.label,
    required this.tooltip,
    required this.onTap,
  });

  final TagFilterOp op;
  final String label;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    final color = op == TagFilterOp.or ? semantic.warn : semantic.muted;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(99),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
          decoration: BoxDecoration(
            border: Border.all(
              color: op == TagFilterOp.or
                  ? semantic.warn.withAlpha(140)
                  : semantic.line,
            ),
            borderRadius: BorderRadius.circular(99),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 1,
              color: color,
            ),
          ),
        ),
      ),
    );
  }
}

class _ConditionChip extends StatelessWidget {
  const _ConditionChip({
    required this.condition,
    required this.toggleTooltip,
    required this.removeTooltip,
    required this.onToggleRole,
    required this.onRemove,
  });

  final TagFilterCondition condition;
  final String toggleTooltip;
  final String removeTooltip;
  final VoidCallback onToggleRole;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    final scheme = Theme.of(context).colorScheme;
    final roleColor = condition.exclude ? semantic.warn : scheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: semantic.raised,
        border: Border.all(
          color: condition.exclude
              ? semantic.warn.withAlpha(115)
              : semantic.line,
        ),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Tooltip(
            message: toggleTooltip,
            child: InkWell(
              onTap: onToggleRole,
              borderRadius: BorderRadius.circular(99),
              child: Icon(
                condition.exclude
                    ? Icons.visibility_off_outlined
                    : Icons.filter_alt_outlined,
                size: 12,
                color: roleColor,
              ),
            ),
          ),
          const SizedBox(width: 5),
          Text(condition.tag, style: const TextStyle(fontSize: 12)),
          const SizedBox(width: 5),
          Tooltip(
            message: removeTooltip,
            child: InkWell(
              onTap: onRemove,
              borderRadius: BorderRadius.circular(99),
              child: Icon(Icons.close, size: 12, color: semantic.muted),
            ),
          ),
        ],
      ),
    );
  }
}

/// Searchable tag picker for "add condition": role toggle on top, dataset
/// tags with counts below; tapping a tag pops `(tag, exclude)`.
class _ConditionPickerDialog extends StatefulWidget {
  const _ConditionPickerDialog({required this.tags});

  final List<DatasetTag> tags;

  @override
  State<_ConditionPickerDialog> createState() => _ConditionPickerDialogState();
}

class _ConditionPickerDialogState extends State<_ConditionPickerDialog> {
  String _query = '';
  bool _exclude = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final semantic = context.semantic;
    final scheme = Theme.of(context).colorScheme;
    final q = _query.trim().toLowerCase();
    final visible = q.isEmpty
        ? widget.tags
        : widget.tags
              .where((t) => t.tag.toLowerCase().contains(q))
              .toList();

    return AlertDialog(
      title: Text(l10n.filterPickerTitle),
      content: SizedBox(
        width: 340,
        height: 400,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              autofocus: true,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                hintText: l10n.filterTagsHint,
                prefixIcon: Icon(Icons.search, size: 16, color: semantic.muted),
                prefixIconConstraints: const BoxConstraints(
                  minWidth: 32,
                  minHeight: 32,
                ),
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              children: [
                FilterChipPill(
                  label: l10n.filterRoleInclude,
                  selected: !_exclude,
                  onTap: () => setState(() => _exclude = false),
                ),
                FilterChipPill(
                  label: l10n.filterRoleExclude,
                  selected: _exclude,
                  onTap: () => setState(() => _exclude = true),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Expanded(
              child: ListView.builder(
                itemCount: visible.length,
                itemBuilder: (context, index) {
                  final entry = visible[index];
                  return InkWell(
                    onTap: () =>
                        Navigator.of(context).pop((entry.tag, _exclude)),
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _exclude
                                ? Icons.visibility_off_outlined
                                : Icons.filter_alt_outlined,
                            size: 13,
                            color: _exclude ? semantic.warn : scheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              entry.tag,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12.5),
                            ),
                          ),
                          Text(
                            '${entry.count}',
                            style: monoStyle(
                              context,
                              size: 11,
                              color: semantic.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
      ],
    );
  }
}

class _DatasetTagChip extends StatelessWidget {
  const _DatasetTagChip({
    required this.entry,
    required this.applied,
    required this.filtered,
    required this.filterExclude,
    required this.enabled,
    required this.onTap,
    required this.onContextMenu,
  });

  final DatasetTag entry;
  final bool applied;
  final bool filtered;
  final bool filterExclude;
  final bool enabled;
  final VoidCallback onTap;
  final ValueChanged<Offset> onContextMenu;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    final scheme = Theme.of(context).colorScheme;

    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 3.5),
      decoration: BoxDecoration(
        color: applied
            ? Color.alphaBlend(semantic.ok.withAlpha(36), scheme.surface)
            : scheme.surface,
        border: Border.all(
          color: filtered
              ? scheme.primary
              : applied
              ? semantic.ok.withAlpha(140)
              : semantic.line,
          width: filtered ? 1.5 : 1,
        ),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (filtered) ...[
            Icon(
              filterExclude
                  ? Icons.visibility_off_outlined
                  : Icons.filter_alt_outlined,
              size: 11,
              color: scheme.primary,
            ),
            const SizedBox(width: 5),
          ] else if (applied) ...[
            Icon(Icons.check, size: 11, color: semantic.ok),
            const SizedBox(width: 5),
          ],
          Text(entry.tag, style: const TextStyle(fontSize: 12)),
          const SizedBox(width: 5),
          Text(
            '${entry.count}',
            style: monoStyle(context, size: 10.5, color: semantic.muted),
          ),
        ],
      ),
    );

    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        onSecondaryTapDown: (details) => onContextMenu(details.globalPosition),
        onLongPressStart: (details) => onContextMenu(details.globalPosition),
        child: MouseRegion(
          cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
          child: chip,
        ),
      ),
    );
  }
}

/// Mode picker + tag input for the dataset-wide replace / insert operation.
/// Pops `(mode, input)` on apply, null on cancel.
class _ReplaceDialog extends StatefulWidget {
  const _ReplaceDialog({required this.tag});

  final String tag;

  @override
  State<_ReplaceDialog> createState() => _ReplaceDialogState();
}

class _ReplaceDialogState extends State<_ReplaceDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.tag,
  );
  _EditMode _mode = _EditMode.replace;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _setMode(_EditMode mode) {
    if (_mode == mode) return;
    setState(() {
      // The prefilled tag only makes sense as a replacement seed; swap it
      // out when moving to insert modes and back.
      if (_mode == _EditMode.replace && _controller.text == widget.tag) {
        _controller.clear();
      } else if (mode == _EditMode.replace && _controller.text.isEmpty) {
        _controller.text = widget.tag;
      }
      _mode = mode;
    });
  }

  void _submit() {
    if (_controller.text.trim().isEmpty) return;
    Navigator.of(context).pop((_mode, _controller.text));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final semantic = context.semantic;
    final canApply = _controller.text.trim().isNotEmpty;

    return AlertDialog(
      title: Text(l10n.replaceDialogTitle),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: semantic.raised,
                border: Border.all(color: semantic.line),
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(widget.tag, style: monoStyle(context, size: 12)),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                FilterChipPill(
                  label: l10n.replaceModeReplace,
                  selected: _mode == _EditMode.replace,
                  onTap: () => _setMode(_EditMode.replace),
                ),
                FilterChipPill(
                  label: l10n.replaceModeBefore,
                  selected: _mode == _EditMode.insertBefore,
                  onTap: () => _setMode(_EditMode.insertBefore),
                ),
                FilterChipPill(
                  label: l10n.replaceModeAfter,
                  selected: _mode == _EditMode.insertAfter,
                  onTap: () => _setMode(_EditMode.insertAfter),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              autofocus: true,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(hintText: l10n.replaceInputHint),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        TextButton(
          onPressed: canApply ? _submit : null,
          child: Text(l10n.apply),
        ),
      ],
    );
  }
}

/// Tag input + insert position + scope for the "add tags to all images"
/// operation. Pops `(input, index, onlyFiltered)` on apply — index null
/// means append at the end — or null on cancel.
class _AddTagsDialog extends StatefulWidget {
  const _AddTagsDialog({required this.totalCount, required this.filteredCount});

  final int totalCount;
  final int filteredCount;

  @override
  State<_AddTagsDialog> createState() => _AddTagsDialogState();
}

class _AddTagsDialogState extends State<_AddTagsDialog> {
  final TextEditingController _tagsController = TextEditingController();
  final TextEditingController _indexController = TextEditingController();
  _AddPosition _position = _AddPosition.tail;
  bool _onlyFiltered = false;

  @override
  void dispose() {
    _tagsController.dispose();
    _indexController.dispose();
    super.dispose();
  }

  /// User-facing position is 1-based; null = append at the end.
  int? get _index => switch (_position) {
    _AddPosition.head => 0,
    _AddPosition.tail => null,
    _AddPosition.at => switch (int.tryParse(_indexController.text.trim())) {
      final n? when n >= 1 => n - 1,
      _ => null,
    },
  };

  bool get _canApply {
    if (_tagsController.text.trim().isEmpty) return false;
    if (_position == _AddPosition.at && _index == null) return false;
    return true;
  }

  void _submit() {
    if (!_canApply) return;
    Navigator.of(context).pop((_tagsController.text, _index, _onlyFiltered));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final semantic = context.semantic;
    final filtered = widget.filteredCount != widget.totalCount;
    final targetCount = _onlyFiltered ? widget.filteredCount : widget.totalCount;

    return AlertDialog(
      title: Text(l10n.addTagsGlobalTitle),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _tagsController,
              autofocus: true,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(hintText: l10n.replaceInputHint),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 14),
            Text(
              l10n.addTagsPositionLabel,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
                color: semantic.muted,
              ),
            ),
            const SizedBox(height: 7),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilterChipPill(
                  label: l10n.addTagsPosHead,
                  selected: _position == _AddPosition.head,
                  onTap: () => setState(() => _position = _AddPosition.head),
                ),
                FilterChipPill(
                  label: l10n.addTagsPosTail,
                  selected: _position == _AddPosition.tail,
                  onTap: () => setState(() => _position = _AddPosition.tail),
                ),
                FilterChipPill(
                  label: l10n.addTagsPosIndex,
                  selected: _position == _AddPosition.at,
                  onTap: () => setState(() => _position = _AddPosition.at),
                ),
                if (_position == _AddPosition.at)
                  SizedBox(
                    width: 90,
                    child: TextField(
                      controller: _indexController,
                      autofocus: true,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(fontSize: 13),
                      decoration: InputDecoration(
                        hintText: l10n.addTagsIndexHint,
                        hintStyle: const TextStyle(fontSize: 11.5),
                        isDense: true,
                      ),
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) => _submit(),
                    ),
                  ),
              ],
            ),
            if (filtered) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  SizedBox(
                    width: 30,
                    height: 26,
                    child: Checkbox(
                      value: _onlyFiltered,
                      visualDensity: VisualDensity.compact,
                      onChanged: (v) =>
                          setState(() => _onlyFiltered = v ?? false),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      l10n.batchTagScopeFiltered(widget.filteredCount),
                      style: const TextStyle(fontSize: 12.5),
                    ),
                  ),
                ],
              ),
            ],
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                l10n.addTagsGlobalTargetCount(targetCount),
                style: TextStyle(fontSize: 11.5, color: semantic.muted),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        TextButton(
          onPressed: _canApply ? _submit : null,
          child: Text(l10n.apply),
        ),
      ],
    );
  }
}
