import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../l10n/app_localizations.dart';
import '../../models/tag_group.dart';
import '../../state/editor_session.dart';
import '../../theme/app_theme.dart';
import '../../widgets/panel_widgets.dart';
import 'dataset_tags_view.dart';
import 'tag_group_dialog.dart';

/// Right panel: two tabs sharing the column — the reusable tag library and
/// the dataset-wide tag list.
class TagLibraryPanel extends StatefulWidget {
  const TagLibraryPanel({super.key, this.filterFocusNode});

  /// Focused by the workbench-level Ctrl+F shortcut.
  final FocusNode? filterFocusNode;

  @override
  State<TagLibraryPanel> createState() => _TagLibraryPanelState();
}

class _TagLibraryPanelState extends State<TagLibraryPanel> {
  static const _tabLibrary = 0;
  static const _tabDataset = 1;

  int _tab = _tabLibrary;

  @override
  void initState() {
    super.initState();
    // Ctrl+F targets the library's filter field; if the dataset tab is
    // showing, typing would land in an invisible field — switch first.
    widget.filterFocusNode?.addListener(_onFilterFocus);
  }

  @override
  void dispose() {
    widget.filterFocusNode?.removeListener(_onFilterFocus);
    super.dispose();
  }

  void _onFilterFocus() {
    if (widget.filterFocusNode?.hasFocus == true && _tab != _tabLibrary) {
      setState(() => _tab = _tabLibrary);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final semantic = context.semantic;

    // The divider to the center column is drawn by the resize handle.
    return Container(
      color: semantic.panel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
            child: Row(
              children: [
                // Loose-fit Flexible on both tabs (no Spacer in this row):
                // long localized labels ellipsize instead of overflowing the
                // panel's minimum width.
                Flexible(
                  child: PanelTab(
                    label: l10n.rightTabLibrary,
                    selected: _tab == _tabLibrary,
                    onTap: () => setState(() => _tab = _tabLibrary),
                  ),
                ),
                Flexible(
                  child: PanelTab(
                    label: l10n.rightTabDataset,
                    selected: _tab == _tabDataset,
                    onTap: () => setState(() => _tab = _tabDataset),
                  ),
                ),
              ],
            ),
          ),
          const Divider(),
          Expanded(
            // IndexedStack keeps both tabs alive so scroll positions and
            // filter text survive switching.
            child: IndexedStack(
              index: _tab,
              sizing: StackFit.expand,
              children: [
                _LibraryView(filterFocusNode: widget.filterFocusNode),
                const DatasetTagsView(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The reusable tag library. Click applies a tag to the current image, click
/// again removes it; tags found in the image but missing from the library
/// surface in the "new tags" group.
class _LibraryView extends StatefulWidget {
  const _LibraryView({this.filterFocusNode});

  final FocusNode? filterFocusNode;

  @override
  State<_LibraryView> createState() => _LibraryViewState();
}

class _LibraryViewState extends State<_LibraryView> {
  String _filter = '';

  /// Group-edit mode: clicks select instead of applying, right-click sends
  /// the selection to a group. Pure library editing — the current image is
  /// not touched.
  bool _groupEditMode = false;
  final Set<String> _selected = {};

  Future<void> _showAddDialog() async {
    final l10n = AppLocalizations.of(context)!;
    final appState = context.read<AppState>();
    final tags = await _promptForTags(
      title: l10n.addTagsTitle,
      hint: l10n.addTagsContent,
    );
    if (tags != null && tags.isNotEmpty) {
      await appState.addCommonTags(tags);
    }
  }

  Future<void> _showImportDialog() async {
    final l10n = AppLocalizations.of(context)!;
    final appState = context.read<AppState>();
    final tags = await _promptForTags(
      title: l10n.importTagsTitle,
      hint: l10n.importTagsContent,
    );
    if (tags != null) {
      await appState.updateCommonTags(tags);
    }
  }

  Future<List<String>?> _promptForTags({
    required String title,
    required String hint,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 380,
          child: TextField(
            controller: controller,
            decoration: InputDecoration(hintText: hint),
            maxLines: 4,
            autofocus: true,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.confirm),
          ),
        ],
      ),
    );
    if (confirmed != true) return null;
    return controller.text
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  void _showTagMenu(BuildContext context, Offset position, String tag) async {
    final l10n = AppLocalizations.of(context)!;
    final appState = context.read<AppState>();
    final action = await showPanelContextMenu<String>(
      context: context,
      position: position,
      items: [
        panelMenuItem(
          context: context,
          value: 'remove',
          icon: Icons.delete_outline,
          label: l10n.removeFromLibrary,
        ),
      ],
    );
    if (action == 'remove') {
      await appState.removeCommonTags([tag]);
    }
  }

  /// Group-edit mode context menu. [targets] is the whole selection when the
  /// clicked tag is part of it, otherwise just the clicked tag.
  Future<void> _showSendMenu(Offset position, List<String> targets) async {
    final l10n = AppLocalizations.of(context)!;
    final appState = context.read<AppState>();
    final action = await showPanelContextMenu<String>(
      context: context,
      position: position,
      items: [
        for (final group in appState.tagGroups)
          panelMenuItem(
            context: context,
            value: 'send:${group.id}',
            icon: Icons.circle,
            iconColor: Color(group.color),
            label: l10n.sendToGroup(group.name),
          ),
        panelMenuItem(
          context: context,
          value: 'new',
          icon: Icons.create_new_folder_outlined,
          label: l10n.sendToNewGroup,
        ),
        const PopupMenuDivider(height: 10),
        panelMenuItem(
          context: context,
          value: 'ungroup',
          icon: Icons.folder_off_outlined,
          label: l10n.removeFromGroup,
        ),
      ],
    );
    if (action == null || !mounted) return;

    String? groupId;
    if (action == 'ungroup') {
      groupId = null;
    } else if (action == 'new') {
      final input = await showTagGroupDialog(context);
      if (input == null) return;
      groupId = (await appState.createTagGroup(input.name, input.color)).id;
    } else {
      groupId = action.substring('send:'.length);
    }
    await appState.moveTagsToGroup(targets, groupId);
    setState(() => _selected.removeAll(targets));
  }

  /// Section-header context menu: edit (name/color) or delete the group.
  Future<void> _showGroupMenu(Offset position, TagGroup group) async {
    final l10n = AppLocalizations.of(context)!;
    final appState = context.read<AppState>();
    final scheme = Theme.of(context).colorScheme;
    final action = await showPanelContextMenu<String>(
      context: context,
      position: position,
      items: [
        panelMenuItem(
          context: context,
          value: 'edit',
          icon: Icons.edit_outlined,
          label: l10n.editGroupMenu,
        ),
        panelMenuItem(
          context: context,
          value: 'delete',
          icon: Icons.delete_outline,
          label: l10n.deleteGroupMenu,
          color: scheme.error,
        ),
      ],
    );
    if (action == null || !mounted) return;

    if (action == 'edit') {
      final input = await showTagGroupDialog(context, existing: group);
      if (input == null) return;
      await appState.updateTagGroup(
        group.id,
        name: input.name,
        color: input.color,
      );
    } else if (action == 'delete') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l10n.deleteGroupMenu),
          content: Text(l10n.deleteGroupConfirmContent(group.name)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l10n.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l10n.confirm),
            ),
          ],
        ),
      );
      if (confirmed == true) {
        await appState.deleteTagGroup(group.id);
      }
    }
  }

  Future<void> _createGroup() async {
    final appState = context.read<AppState>();
    final input = await showTagGroupDialog(context);
    if (input != null) {
      await appState.createTagGroup(input.name, input.color);
    }
  }

  void _onChipTap(EditorSession session, String tag) {
    if (_groupEditMode) {
      setState(() {
        if (!_selected.remove(tag)) _selected.add(tag);
      });
    } else {
      session.toggleTag(tag);
    }
  }

  void _onChipContextMenu(Offset position, String tag) {
    if (_groupEditMode) {
      final targets = _selected.contains(tag)
          // Selection in library order, so a batch send keeps a stable order.
          ? context
              .read<AppState>()
              .commonTags
              .where(_selected.contains)
              .toList()
          : [tag];
      _showSendMenu(position, targets);
    } else {
      _showTagMenu(context, position, tag);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final semantic = context.semantic;
    final scheme = Theme.of(context).colorScheme;
    final appState = context.watch<AppState>();
    final session = context.watch<EditorSession>();

    final commonTags = appState.commonTags;
    final commonSet = commonTags.toSet();
    final query = _filter.trim().toLowerCase();
    bool matches(String t) => query.isEmpty || t.toLowerCase().contains(query);
    final newTags = session.hasImage
        ? session.tags.where((t) => !commonSet.contains(t)).toList()
        : const <String>[];

    // (group, visible tags) sections; ungrouped last. Under a filter, empty
    // sections disappear; without one, empty groups stay visible so they can
    // be managed, but an empty ungrouped section is just noise.
    final sections = <(TagGroup?, List<String>)>[
      for (final group in appState.tagGroups)
        (group, group.tags.where(matches).toList()),
      (null, appState.ungroupedTags.where(matches).toList()),
    ].where((s) {
      if (query.isNotEmpty) return s.$2.isNotEmpty;
      return s.$1 != null || s.$2.isNotEmpty;
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PanelHeader(
          title: l10n.tagLibraryTitle,
          count: commonTags.length,
          actions: [
            PanelIconButton(
              icon: Icons.add,
              tooltip: l10n.addTagsTitle,
              onPressed: _showAddDialog,
            ),
            PanelIconButton(
              icon: Icons.create_new_folder_outlined,
              tooltip: l10n.newGroupTitle,
              onPressed: _createGroup,
            ),
            PanelIconButton(
              icon: Icons.swap_horiz,
              tooltip: l10n.importTagsTitle,
              onPressed: _showImportDialog,
            ),
            PanelIconButton(
              icon: Icons.checklist,
              tooltip: l10n.groupEditModeTooltip,
              color: _groupEditMode ? scheme.primary : null,
              onPressed: () => setState(() {
                _groupEditMode = !_groupEditMode;
                if (!_groupEditMode) _selected.clear();
              }),
            ),
          ],
        ),
        PanelSearchField(
          hint: l10n.filterTagsHint,
          focusNode: widget.filterFocusNode,
          onChanged: (value) => setState(() => _filter = value),
        ),
        Expanded(
          child: commonTags.isEmpty && newTags.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      l10n.libraryEmpty,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12.5, color: semantic.muted),
                    ),
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _PanelCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _SectionLabel(
                              text: _groupEditMode
                                  ? (_selected.isEmpty
                                      ? l10n.groupEditHint
                                      : l10n.groupEditSelectedHint(
                                          _selected.length,
                                        ))
                                  : l10n.clickToApplyHint,
                              color: _groupEditMode ? scheme.primary : null,
                            ),
                            for (final (group, tags) in sections) ...[
                              const SizedBox(height: 10),
                              _GroupHeader(
                                group: group,
                                count: tags.length,
                                ungroupedLabel: l10n.ungroupedSection,
                                onContextMenu: group == null
                                    ? null
                                    : (position) =>
                                        _showGroupMenu(position, group),
                              ),
                              const SizedBox(height: 7),
                              Wrap(
                                spacing: 7,
                                runSpacing: 7,
                                children: [
                                  for (final tag in tags)
                                    _LibraryTagChip(
                                      label: tag,
                                      applied: session.hasTag(tag),
                                      enabled:
                                          _groupEditMode || session.hasImage,
                                      dotColor: group == null
                                          ? null
                                          : Color(group.color),
                                      selectionMode: _groupEditMode,
                                      selected: _selected.contains(tag),
                                      onTap: () => _onChipTap(session, tag),
                                      onContextMenu: (position) =>
                                          _onChipContextMenu(position, tag),
                                    ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (newTags.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        _PanelCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: _SectionLabel(
                                      text:
                                          '${l10n.newTagsSection} (${newTags.length})',
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: () =>
                                        appState.addCommonTags(newTags),
                                    style: TextButton.styleFrom(
                                      visualDensity: VisualDensity.compact,
                                      textStyle: const TextStyle(fontSize: 12),
                                    ),
                                    child: Text(l10n.addAllToLibrary),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Wrap(
                                spacing: 7,
                                runSpacing: 7,
                                children: [
                                  for (final tag in newTags)
                                    _NewTagChip(
                                      label: tag,
                                      onTap: () =>
                                          appState.addCommonTags([tag]),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
        ),
        const Divider(),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              _LegendItem(color: semantic.ok, label: l10n.legendApplied),
              _LegendItem(color: semantic.line, label: l10n.legendNotApplied),
              _LegendItem(color: semantic.warn, label: l10n.legendNew),
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.text, this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.3,
        color: color ?? context.semantic.muted,
      ),
    );
  }
}

/// Bordered card giving the library and new-tags areas a visual boundary.
class _PanelCard extends StatelessWidget {
  const _PanelCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: semantic.line),
        borderRadius: BorderRadius.circular(10),
      ),
      child: child,
    );
  }
}

/// Section header inside the library card: color dot, group name, count.
/// Real groups take a right-click menu (edit/delete); ungrouped does not.
class _GroupHeader extends StatelessWidget {
  const _GroupHeader({
    required this.group,
    required this.count,
    required this.ungroupedLabel,
    this.onContextMenu,
  });

  final TagGroup? group;
  final int count;
  final String ungroupedLabel;
  final ValueChanged<Offset>? onContextMenu;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: group == null ? semantic.muted : Color(group!.color),
          ),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            group?.name ?? ungroupedLabel,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
              color: semantic.muted,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '$count',
          style: monoStyle(context, size: 11, color: semantic.muted),
        ),
      ],
    );

    if (onContextMenu == null) return row;
    return GestureDetector(
      onSecondaryTapDown: (details) => onContextMenu!(details.globalPosition),
      onLongPressStart: (details) => onContextMenu!(details.globalPosition),
      child: MouseRegion(cursor: SystemMouseCursors.click, child: row),
    );
  }
}

class _LibraryTagChip extends StatelessWidget {
  const _LibraryTagChip({
    required this.label,
    required this.applied,
    required this.enabled,
    required this.onTap,
    required this.onContextMenu,
    this.dotColor,
    this.selectionMode = false,
    this.selected = false,
  });

  final String label;
  final bool applied;
  final bool enabled;
  final VoidCallback onTap;
  final ValueChanged<Offset> onContextMenu;

  /// Group color dot shown before the label; null for ungrouped tags.
  final Color? dotColor;

  /// Group-edit mode: [selected] drives the accent highlight and the applied
  /// state is not shown (selection is about the library, not the image).
  final bool selectionMode;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    final scheme = Theme.of(context).colorScheme;

    final Color borderColor;
    final Color bgColor;
    if (selectionMode && selected) {
      borderColor = scheme.primary;
      bgColor = Color.alphaBlend(scheme.primary.withAlpha(36), scheme.surface);
    } else if (!selectionMode && applied) {
      borderColor = semantic.ok.withAlpha(140);
      bgColor = Color.alphaBlend(semantic.ok.withAlpha(36), scheme.surface);
    } else {
      borderColor = semantic.line;
      bgColor = scheme.surface;
    }

    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 3.5),
      decoration: BoxDecoration(
        color: bgColor,
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (selectionMode && selected) ...[
            Icon(Icons.check, size: 11, color: scheme.primary),
            const SizedBox(width: 5),
          ] else if (!selectionMode && applied) ...[
            Icon(Icons.check, size: 11, color: semantic.ok),
            const SizedBox(width: 5),
          ],
          if (dotColor != null) ...[
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: dotColor,
              ),
            ),
            const SizedBox(width: 5),
          ],
          Text(label, style: const TextStyle(fontSize: 12)),
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

class _NewTagChip extends StatelessWidget {
  const _NewTagChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 3.5),
          decoration: BoxDecoration(
            color: Color.alphaBlend(
              semantic.warn.withAlpha(33),
              scheme.surface,
            ),
            border: Border.all(color: semantic.warn.withAlpha(140)),
            borderRadius: BorderRadius.circular(99),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add, size: 11, color: semantic.warn),
              const SizedBox(width: 5),
              Text(label, style: const TextStyle(fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(fontSize: 11.5, color: context.semantic.muted),
        ),
      ],
    );
  }
}
