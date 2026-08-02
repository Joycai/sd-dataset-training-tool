import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../l10n/app_localizations.dart';
import '../../models/tag_filter.dart';
import '../../state/dataset_state.dart';
import '../../state/editor_session.dart';
import '../../state/tag_ops.dart';
import '../../theme/app_theme.dart';
import '../../widgets/panel_widgets.dart';
import '../../widgets/subdirectory_picker.dart';
import '../../widgets/tag_context_menu.dart';
import '../../widgets/tag_gloss.dart';
import 'tag_dictionary_dialog.dart';

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
    final dataset = context.read<DatasetState>();
    final appState = context.read<AppState>();
    final action = await showPanelContextMenu<TagMenuAction>(
      context: context,
      position: position,
      items: buildTagMenuItems(
        context,
        tag: entry.tag,
        dictionary: appState.tagDictionary,
        inLibrary: appState.commonTags.contains(entry.tag),
        sections: const TagMenuSections(
          filter: true,
          addToLibrary: true,
          datasetOps: true,
          danger: true,
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (await handleTagMenuAction(context, action, entry.tag)) return;
    switch (action) {
      case TagMenuAction.filterInclude:
        dataset.setTagFilter(entry.tag, exclude: false);
      case TagMenuAction.filterExclude:
        dataset.setTagFilter(entry.tag, exclude: true);
      case TagMenuAction.addToLibrary:
        await appState.addCommonTags([entry.tag]);
      case TagMenuAction.replaceAppend:
        await _showReplaceDialog(entry);
      case TagMenuAction.deleteGlobal:
        await _confirmDelete(entry);
      default:
        break;
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

    final result = await ops.deleteEverywhere(
      entry.tag,
      label: l10n.opDeleteLabel(entry.tag),
    );
    // Conditions on a tag that no longer exists are stale (an include would
    // blank the gallery); drop them from the expression.
    dataset.removeTagFromFilter(entry.tag);
    _showResult(result);
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
    final outcome = switch (mode) {
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
    _showResult(outcome);
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
    final outcome = await ops.addEverywhere(
      input,
      index: index,
      files: onlyFiltered ? List.of(dataset.visibleFiles) : null,
      label: l10n.opAddGlobalLabel(input.trim()),
    );
    _showResult(outcome);
  }

  /// A sweep skips caption files it cannot write, so the snack bar has to
  /// name them — otherwise a failed write is indistinguishable from a file
  /// that simply needed no change.
  void _showResult(BatchRewriteResult result) {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;
    final message = switch ((result.changed, result.failed)) {
      (0, 0) => l10n.noFilesChanged,
      (0, final failed) => l10n.filesFailed(failed),
      (final changed, 0) => l10n.filesUpdated(changed),
      (final changed, final failed) =>
        '${l10n.filesUpdated(changed)} · ${l10n.filesFailed(failed)}',
    };
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final semantic = context.semantic;
    final dataset = context.watch<DatasetState>();
    final session = context.watch<EditorSession>();
    final ops = context.watch<TagOps>();
    final dictionary = context.read<AppState>().tagDictionary;

    final allTags = dataset.datasetTags;
    final query = _filter.trim().toLowerCase();
    final visibleTags = query.isEmpty
        ? allTags
        : allTags.where((t) => t.tag.toLowerCase().contains(query)).toList();
    final refs = filterReferencedTags(dataset.tagFilterExpression);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Filter field and actions share one band; the tab above names this
        // view and carries its tag count.
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
          child: Row(
            children: [
              Expanded(
                child: PanelSearchField(
                  hint: l10n.filterTagsHint,
                  onChanged: (value) => setState(() => _filter = value),
                  padding: EdgeInsets.zero,
                ),
              ),
              const SizedBox(width: 4),
              PanelIconButton(
                icon: Icons.playlist_add,
                tooltip: l10n.addTagsGlobalTooltip,
                size: 16,
                hitSize: 28,
                onPressed: dataset.totalCount > 0 && !ops.busy
                    ? _showAddTagsDialog
                    : null,
              ),
              PanelIconButton(
                icon: Icons.translate,
                tooltip: l10n.dictOpenTooltip,
                size: 16,
                hitSize: 28,
                onPressed: () => showTagDictionaryDialog(
                  context,
                  initialQuery: _filter.trim().isEmpty ? null : _filter,
                ),
              ),
              PanelIconButton(
                icon: Icons.filter_alt_off_outlined,
                tooltip: l10n.clearTagFilter,
                size: 16,
                hitSize: 28,
                onPressed: dataset.tagFilterActive
                    ? dataset.clearTagFilter
                    : null,
              ),
            ],
          ),
        ),
        // Every action in this panel is a sweep, and the scope decides how
        // far it reaches — it has to be visible from here, not only from the
        // navigator on the far side of the window.
        if (dataset.activeSubdirectory != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: _ScopeBanner(
              label: subdirectoryLabel(l10n, dataset.activeSubdirectory),
              onClear: () => dataset.setSubdirectory(null),
            ),
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
                      // The dictionary notifies on its own (a download ticks
                      // every 256 KB) and AppState never forwards that, so the
                      // "not in the dictionary" marking subscribes to it
                      // directly — and only the chip wrap rebuilds.
                      ListenableBuilder(
                        listenable: dictionary,
                        builder: (context, _) => Wrap(
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
                                // Amber outline for a tag danbooru has never
                                // heard of and the user has not added: it can
                                // never be translated or completed, and on a
                                // fresh dataset that is usually a typo.
                                unknown:
                                    dictionary.isReady &&
                                    dictionary.lookup(entry.tag) == null,
                                enabled: session.hasImage && !ops.busy,
                                onTap: () => session.toggleTag(entry.tag),
                                onContextMenu: (position) =>
                                    _showTagMenu(position, entry),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}

/// Names the subdirectory every operation in this panel is confined to, with
/// a way back out to the whole dataset.
class _ScopeBanner extends StatelessWidget {
  const _ScopeBanner({required this.label, required this.onClear});

  final String label;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(9, 5, 5, 5),
      decoration: BoxDecoration(
        color: scheme.primary.withAlpha(23),
        border: Border.all(color: scheme.primary.withAlpha(115)),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        children: [
          Icon(Icons.folder, size: 13, color: scheme.primary),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              l10n.subdirScopeNotice(label),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11.5, color: scheme.primary),
            ),
          ),
          Tooltip(
            message: l10n.subdirScopeClearTooltip,
            child: InkWell(
              onTap: onClear,
              borderRadius: BorderRadius.circular(99),
              child: Padding(
                padding: const EdgeInsets.all(3),
                child: Icon(Icons.close, size: 13, color: scheme.primary),
              ),
            ),
          ),
        ],
      ),
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
      builder: (context) => _ConditionPickerDialog(tags: dataset.datasetTags),
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
            onTap: () =>
                _edit(filterToggleOp(dataset.tagFilterExpression, group.id)),
          ),
        switch (child) {
          TagFilterCondition c => _ConditionChip(
            condition: c,
            toggleTooltip: l10n.filterToggleRoleTooltip,
            removeTooltip: l10n.filterRemoveConditionTooltip,
            onToggleRole: () =>
                _edit(filterToggleRole(dataset.tagFilterExpression, c.id)),
            onRemove: () =>
                _edit(filterRemove(dataset.tagFilterExpression, c.id)),
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
            onTap: () =>
                _edit(filterDissolve(dataset.tagFilterExpression, group.id)),
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
        : widget.tags.where((t) => t.tag.toLowerCase().contains(q)).toList();

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
    required this.unknown,
    required this.enabled,
    required this.onTap,
    required this.onContextMenu,
  });

  final DatasetTag entry;
  final bool applied;
  final bool filtered;
  final bool filterExclude;

  /// Known to neither the dictionary nor the user's own additions.
  final bool unknown;

  final bool enabled;
  final VoidCallback onTap;
  final ValueChanged<Offset> onContextMenu;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    final scheme = Theme.of(context).colorScheme;

    // Five states, five colours: excluded from the gallery reads as the
    // destructive one, included is the accent, on-this-image stays green,
    // a tag no dictionary knows is amber, and everything else is inventory in
    // muted ink. The gallery states outrank "unknown" — they answer what the
    // user is doing right now, while unknown is a standing property.
    final Color accentOfState;
    if (filtered) {
      accentOfState = filterExclude ? scheme.error : scheme.primary;
    } else if (applied) {
      accentOfState = semantic.ok;
    } else if (unknown) {
      accentOfState = semantic.warn;
    } else {
      accentOfState = semantic.muted;
    }
    final tinted = filtered || applied;

    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2.5),
      decoration: BoxDecoration(
        color: tinted
            ? Color.alphaBlend(accentOfState.withAlpha(38), semantic.panel)
            : semantic.raised,
        border: Border.all(
          color: tinted
              ? accentOfState.withAlpha(128)
              : unknown
              // An outline only: the tag is still ordinary inventory, and a
              // filled amber chip on every fresh dataset would read as an
              // error state.
              ? semantic.warn.withAlpha(105)
              : semantic.line,
        ),
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (filtered) ...[
            Icon(
              filterExclude ? Icons.block_outlined : Icons.filter_alt_outlined,
              size: 10,
              color: accentOfState,
            ),
            const SizedBox(width: 4),
          ] else if (applied) ...[
            Icon(Icons.check, size: 10, color: semantic.ok),
            const SizedBox(width: 4),
          ],
          Text(
            entry.tag,
            style: TextStyle(
              fontSize: AppText.small,
              color: tinted ? scheme.onSurface : semantic.muted,
            ),
          ),
          TagGlossLabel(entry.tag),
          const SizedBox(width: 5),
          Text(
            '${entry.count}',
            style: monoStyle(
              context,
              size: AppText.micro,
              color: semantic.muted,
            ),
          ),
        ],
      ),
    );

    final hovering = MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: chip,
    );
    // The amber outline says *that* something is off; the tooltip says what.
    // It rides along with the gloss rather than replacing it — a translated
    // tag can still be one the dictionary does not know.
    final gloss = tagGlossTooltip(context, entry.tag);
    final unknownHint = AppLocalizations.of(context)!.dictUnknownTagHint;
    final message = !unknown
        ? gloss
        : gloss == null
        ? unknownHint
        : '$gloss — $unknownHint';

    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        onSecondaryTapDown: (details) => onContextMenu(details.globalPosition),
        onLongPressStart: (details) => onContextMenu(details.globalPosition),
        child: message == null
            ? hovering
            : Tooltip(message: message, child: hovering),
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
    final targetCount = _onlyFiltered
        ? widget.filteredCount
        : widget.totalCount;

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
