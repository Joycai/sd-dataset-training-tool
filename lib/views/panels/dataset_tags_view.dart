import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
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
    // An include-filter on a tag that no longer exists would blank the
    // gallery; drop it.
    if (dataset.tagFilter == entry.tag && !dataset.tagFilterExclude) {
      dataset.clearTagFilter();
    }
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PanelHeader(
          title: l10n.datasetTagsTitle,
          count: allTags.length,
          actions: [
            PanelIconButton(
              icon: Icons.filter_alt_off_outlined,
              tooltip: l10n.clearTagFilter,
              onPressed: dataset.tagFilter == null
                  ? null
                  : dataset.clearTagFilter,
            ),
          ],
        ),
        PanelSearchField(
          hint: l10n.filterTagsHint,
          onChanged: (value) => setState(() => _filter = value),
        ),
        if (dataset.tagFilter != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: _ActiveFilterBanner(
              tag: dataset.tagFilter!,
              exclude: dataset.tagFilterExclude,
              onClear: dataset.clearTagFilter,
            ),
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
                              filtered: dataset.tagFilter == entry.tag,
                              filterExclude: dataset.tagFilterExclude,
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

/// Shows which tag filter is active on the gallery; the close glyph clears it.
class _ActiveFilterBanner extends StatelessWidget {
  const _ActiveFilterBanner({
    required this.tag,
    required this.exclude,
    required this.onClear,
  });

  final String tag;
  final bool exclude;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final semantic = context.semantic;
    final scheme = Theme.of(context).colorScheme;
    final label = exclude
        ? l10n.filterActiveExclude(tag)
        : l10n.filterActiveInclude(tag);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Color.alphaBlend(scheme.primary.withAlpha(26), semantic.raised),
        border: Border.all(color: scheme.primary.withAlpha(120)),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        children: [
          Icon(
            exclude ? Icons.visibility_off_outlined : Icons.filter_alt_outlined,
            size: 14,
            color: scheme.primary,
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: scheme.onSurface),
            ),
          ),
          InkWell(
            onTap: onClear,
            borderRadius: BorderRadius.circular(99),
            child: Icon(Icons.close, size: 14, color: semantic.muted),
          ),
        ],
      ),
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
