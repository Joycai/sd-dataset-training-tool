import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../l10n/app_localizations.dart';
import '../../models/tag_group.dart';
import '../../state/dataset_state.dart';
import '../../state/editor_session.dart';
import '../../state/tag_ops.dart';
import '../../state/workbench_layout.dart';
import '../../theme/app_theme.dart';
import '../../utils/tag_search.dart';
import '../../widgets/panel_widgets.dart';
import '../../widgets/row_limited_wrap.dart';
import '../../widgets/tag_context_menu.dart';
import '../../widgets/tag_gloss.dart';
import 'dataset_tags_view.dart';
import 'tag_ai_group_dialog.dart';
import 'tag_dictionary_dialog.dart';
import 'tag_group_dialog.dart';
import 'tag_merge_dialog.dart';

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
    if (widget.filterFocusNode?.hasFocus == true) {
      context.read<WorkbenchLayout>().showInspectorTab(InspectorTab.library);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final semantic = context.semantic;
    // The tab lives in the shared layout state: the icon rail selects it
    // too, so it cannot be owned by this panel.
    final layout = context.watch<WorkbenchLayout>();
    final tab = layout.inspectorTab;
    // Counts ride on the tab labels, which is why the views below no longer
    // need a title row of their own. select (not watch): the tab strip must
    // not rebuild on every unrelated library edit.
    final libraryCount = context.select<AppState, int>(
      (s) => s.commonTags.length,
    );
    final datasetCount = context.select<DatasetState, int>(
      (s) => s.datasetTags.length,
    );

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
                    label: '${l10n.rightTabLibrary}  $libraryCount',
                    selected: tab == InspectorTab.library,
                    onTap: () => layout.showInspectorTab(InspectorTab.library),
                  ),
                ),
                Flexible(
                  child: PanelTab(
                    label: '${l10n.rightTabDataset}  $datasetCount',
                    selected: tab == InspectorTab.dataset,
                    onTap: () => layout.showInspectorTab(InspectorTab.dataset),
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
              index: tab.index,
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

/// The browse-state filter over the library, on the axis of the *current
/// image*: what is already on it, what is not, and what the image carries
/// that the library has never heard of.
enum _LibraryStatus { all, used, unused, fresh }

/// How many rows a collapsed group shows before it cuts to "+N more".
const int _groupRowCap = 2;

/// A tag selection in flight between a chip and a group header.
class _TagDrag {
  const _TagDrag(this.tags);

  final List<String> tags;
}

/// The reusable tag library. Click applies a tag to the current image, click
/// again removes it; tags found in the image but missing from the library
/// surface in the "new tags" group.
///
/// Everything above the tag rows exists for one reason: a library that has
/// grown past a screenful. Groups fold (and stay folded across restarts), each
/// group shows two rows at a time, the status filter narrows to what the
/// current image does or does not carry, and the dataset switch hides library
/// tags this dataset never uses.
class _LibraryView extends StatefulWidget {
  const _LibraryView({this.filterFocusNode});

  final FocusNode? filterFocusNode;

  @override
  State<_LibraryView> createState() => _LibraryViewState();
}

class _LibraryViewState extends State<_LibraryView> {
  String _filter = '';
  _LibraryStatus _status = _LibraryStatus.all;

  /// Hides library tags no image in the current scope carries — the other
  /// axis of "too many tags": a library shared across datasets holds tags
  /// that are simply not this dataset's business.
  bool _datasetOnly = false;

  /// Organize mode: clicks select instead of applying, and the bottom bar
  /// moves / merges / deletes the selection. Pure library editing — the
  /// current image is not touched.
  bool _organizeMode = false;
  final Set<String> _selected = {};

  /// Last tag clicked without Shift; the other end of a Shift range.
  String? _anchor;

  /// Sections the user opened past the two-row cap. Per session, unlike the
  /// collapsed state: "show me the rest of this group" is a momentary need,
  /// while a folded group is a filing decision.
  final Set<String> _expanded = {};

  /// Bumped on every arrow reorder so [AnimatedReorderColumn] slides the
  /// sections; other layout shifts stay instant.
  int _reorderTick = 0;

  /// The flat order tags render in, rebuilt every frame — what a Shift range
  /// runs along.
  List<String> _visibleOrder = const [];

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
    final appState = context.read<AppState>();
    final dataset = context.read<DatasetState>();
    final action = await showPanelContextMenu<TagMenuAction>(
      context: context,
      position: position,
      items: buildTagMenuItems(
        context,
        tag: tag,
        dictionary: appState.tagDictionary,
        sections: const TagMenuSections(filter: true, removeFromLibrary: true),
      ),
    );
    if (!context.mounted) return;
    if (await handleTagMenuAction(context, action, tag)) return;
    switch (action) {
      case TagMenuAction.filterInclude:
        dataset.setTagFilter(tag, exclude: false);
      case TagMenuAction.filterExclude:
        dataset.setTagFilter(tag, exclude: true);
      case TagMenuAction.removeFromLibrary:
        await appState.removeCommonTags([tag]);
      default:
        break;
    }
  }

  /// Organize-mode context menu: the same three-section shape as the normal
  /// tag menu (info is meaningless here, so it starts at "selection") — a
  /// selection section for the clicked tag, the send-to-group actions, and a
  /// danger section last. [clickedTag] drives the selection toggle and "select
  /// all in group"; [targets] is the whole selection when the clicked tag is
  /// part of it, otherwise just the clicked tag, and is what the send/remove
  /// actions act on.
  Future<void> _showSendMenu(
    Offset position,
    String clickedTag,
    List<String> targets,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final appState = context.read<AppState>();
    final scheme = Theme.of(context).colorScheme;
    final clickedSelected = _selected.contains(clickedTag);
    final siblings =
        appState.groupOfTag(clickedTag)?.tags ?? appState.ungroupedTags;

    final action = await showPanelContextMenu<String>(
      context: context,
      position: position,
      items: [
        panelMenuItem(
          context: context,
          value: clickedSelected ? 'deselect' : 'select',
          icon: clickedSelected
              ? Icons.check_box_outlined
              : Icons.check_box_outline_blank,
          label: clickedSelected
              ? l10n.groupEditDeselectAction
              : l10n.groupEditSelectAction,
        ),
        if (siblings.length > 1)
          panelMenuItem(
            context: context,
            value: 'selectGroup',
            icon: Icons.select_all,
            label: l10n.groupEditSelectAllInGroupAction,
          ),
        const PopupMenuDivider(height: 9),
        ..._moveMenuItems(appState),
        const PopupMenuDivider(height: 9),
        panelMenuItem(
          context: context,
          value: 'removeFromLibrary',
          icon: Icons.delete_outline,
          label: l10n.removeFromLibrary,
          color: scheme.error,
        ),
      ],
    );
    if (action == null || !mounted) return;

    switch (action) {
      case 'select':
        setState(() => _selected.add(clickedTag));
        return;
      case 'deselect':
        setState(() => _selected.remove(clickedTag));
        return;
      case 'selectGroup':
        setState(() => _selected.addAll(siblings));
        return;
      case 'removeFromLibrary':
        await appState.removeCommonTags(targets);
        setState(() => _selected.removeAll(targets));
        return;
    }
    await _applyMoveAction(action, targets);
  }

  /// The "where to" half of both the chip menu and the bottom bar's move
  /// button: one entry per group, plus a new group and the way out.
  List<PopupMenuEntry<String>> _moveMenuItems(AppState appState) {
    final l10n = AppLocalizations.of(context)!;
    return [
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
      panelMenuItem(
        context: context,
        value: 'ungroup',
        icon: Icons.folder_off_outlined,
        label: l10n.removeFromGroup,
      ),
    ];
  }

  Future<void> _applyMoveAction(String action, List<String> targets) async {
    final appState = context.read<AppState>();
    String? groupId;
    if (action == 'ungroup') {
      groupId = null;
    } else if (action == 'new') {
      final input = await showTagGroupDialog(context);
      if (input == null) return;
      groupId = (await appState.createTagGroup(input.name, input.color)).id;
    } else if (action.startsWith('send:')) {
      groupId = action.substring('send:'.length);
    } else {
      return;
    }
    await appState.moveTagsToGroup(targets, groupId);
    if (mounted) setState(() => _selected.removeAll(targets));
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
      await _confirmDeleteGroup(group);
    }
  }

  /// Quick color change from the organize-mode dot: preset swatches in a
  /// popup, with the full edit dialog behind a "custom" entry.
  Future<void> _showColorSwatches(Offset position, TagGroup group) async {
    final l10n = AppLocalizations.of(context)!;
    final appState = context.read<AppState>();
    final scheme = Theme.of(context).colorScheme;
    const custom = -1;
    final picked = await showPanelContextMenu<int>(
      context: context,
      position: position,
      items: [
        PopupMenuItem<int>(
          enabled: false,
          height: 36,
          child: SizedBox(
            width: 168,
            child: Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                for (final preset in kTagGroupPresetColors)
                  InkWell(
                    // Pops the menu route with the swatch as its result.
                    onTap: () => Navigator.of(context).pop(preset),
                    borderRadius: BorderRadius.circular(99),
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(preset),
                        border: Border.all(
                          color: group.color == preset
                              ? scheme.primary
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      child: group.color == preset
                          ? const Icon(Icons.check, size: 13)
                          : null,
                    ),
                  ),
              ],
            ),
          ),
        ),
        const PopupMenuDivider(height: 10),
        panelMenuItem(
          context: context,
          value: custom,
          icon: Icons.palette_outlined,
          label: l10n.customColorLabel,
        ),
      ],
    );
    if (picked == null || !mounted) return;

    if (picked == custom) {
      final input = await showTagGroupDialog(context, existing: group);
      if (input == null) return;
      await appState.updateTagGroup(
        group.id,
        name: input.name,
        color: input.color,
      );
    } else {
      await appState.updateTagGroup(group.id, color: picked);
    }
  }

  /// Confirm-and-delete for a group; its tags return to ungrouped.
  Future<void> _confirmDeleteGroup(TagGroup group) async {
    final l10n = AppLocalizations.of(context)!;
    final appState = context.read<AppState>();
    final confirmed = await _confirm(
      title: l10n.deleteGroupMenu,
      message: l10n.deleteGroupConfirmContent(group.name),
    );
    if (confirmed) await appState.deleteTagGroup(group.id);
  }

  Future<bool> _confirm({
    required String title,
    required String message,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
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
    return confirmed == true;
  }

  void _snack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  /// Overflow menu on the panel header: paste import/replace, file
  /// import/export, and clearing the library.
  Future<void> _showMoreMenu(BuildContext buttonContext) async {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final box = buttonContext.findRenderObject()! as RenderBox;
    final action = await showPanelContextMenu<String>(
      context: context,
      position: box.localToGlobal(Offset(0, box.size.height)),
      items: [
        panelMenuItem(
          context: context,
          value: 'paste',
          icon: Icons.swap_horiz,
          label: l10n.importTagsTitle,
        ),
        panelMenuItem(
          context: context,
          value: 'importFile',
          icon: Icons.file_open_outlined,
          label: l10n.importFromFile,
        ),
        panelMenuItem(
          context: context,
          value: 'exportAll',
          icon: Icons.save_alt,
          label: l10n.exportLibraryMenu,
        ),
        panelMenuItem(
          context: context,
          value: 'exportGroups',
          icon: Icons.save_alt,
          label: l10n.exportGroupsMenu,
        ),
        const PopupMenuDivider(height: 10),
        panelMenuItem(
          context: context,
          value: 'clear',
          icon: Icons.delete_sweep_outlined,
          label: l10n.clearLibrary,
          color: scheme.error,
        ),
      ],
    );
    if (action == null || !mounted) return;
    switch (action) {
      case 'paste':
        await _showImportDialog();
      case 'importFile':
        await _importFromFile();
      case 'exportAll':
        await _exportLibrary(groupsOnly: false);
      case 'exportGroups':
        await _exportLibrary(groupsOnly: true);
      case 'clear':
        await _confirmClearLibrary();
    }
  }

  Future<void> _importFromFile() async {
    final l10n = AppLocalizations.of(context)!;
    final appState = context.read<AppState>();
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    final path = result?.files.single.path;
    if (path == null) return;
    try {
      final imported = await appState.importLibraryJson(
        await File(path).readAsString(),
      );
      if (!mounted) return;
      _snack(l10n.importSummary(imported.tagsAdded, imported.groupsCreated));
    } on FormatException catch (e) {
      if (mounted) _snack(l10n.importFailedMsg(e.message));
    } on FileSystemException catch (e) {
      if (mounted) _snack(l10n.importFailedMsg(e.message));
    }
  }

  Future<void> _exportLibrary({required bool groupsOnly}) async {
    final l10n = AppLocalizations.of(context)!;
    final appState = context.read<AppState>();
    final path = await FilePicker.saveFile(
      fileName: groupsOnly ? 'tag_groups.json' : 'tag_library.json',
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (path == null) return;
    try {
      await File(
        path,
      ).writeAsString(appState.exportLibraryJson(groupsOnly: groupsOnly));
      if (!mounted) return;
      _snack(l10n.exportedTo(path));
    } on FileSystemException catch (e) {
      if (mounted) _snack(l10n.exportFailedMsg(e.message));
    }
  }

  Future<void> _confirmClearLibrary() async {
    final l10n = AppLocalizations.of(context)!;
    final appState = context.read<AppState>();
    final count = appState.commonTags.length;
    if (count == 0) return;
    if (await _confirm(
      title: l10n.clearLibrary,
      message: l10n.clearLibraryConfirmContent(count),
    )) {
      await appState.clearCommonTags();
      setState(_selected.clear);
    }
  }

  /// Arrow reorder: arms the slide animation for exactly this order change.
  void _reorderGroup(TagGroup group, int delta) {
    setState(() => _reorderTick++);
    context.read<AppState>().reorderTagGroup(group.id, delta);
  }

  Future<void> _createGroup() async {
    final appState = context.read<AppState>();
    final input = await showTagGroupDialog(context);
    if (input != null) {
      await appState.createTagGroup(input.name, input.color);
    }
  }

  // --- Organize mode ------------------------------------------------------

  /// The selection in library order, so a batch operation is stable regardless
  /// of the order the user clicked in.
  List<String> _selectionInOrder(AppState appState) =>
      appState.commonTags.where(_selected.contains).toList();

  void _onChipTap(EditorSession session, String tag) {
    if (!_organizeMode) {
      session.toggleTag(tag);
      return;
    }
    final shift = HardwareKeyboard.instance.isShiftPressed;
    setState(() {
      if (shift && _anchor != null && _anchor != tag) {
        final from = _visibleOrder.indexOf(_anchor!);
        final to = _visibleOrder.indexOf(tag);
        if (from >= 0 && to >= 0) {
          final lo = from < to ? from : to;
          final hi = from < to ? to : from;
          // A range extends the selection rather than replacing it: picking
          // two runs out of two groups is the common case.
          _selected.addAll(_visibleOrder.sublist(lo, hi + 1));
          return;
        }
      }
      if (!_selected.remove(tag)) _selected.add(tag);
      _anchor = tag;
    });
  }

  void _onChipContextMenu(Offset position, String tag) {
    if (_organizeMode) {
      final targets = _selected.contains(tag)
          ? _selectionInOrder(context.read<AppState>())
          : [tag];
      _showSendMenu(position, tag, targets);
    } else {
      _showTagMenu(context, position, tag);
    }
  }

  /// What a chip drags: the whole selection when the dragged tag is part of
  /// it, otherwise just that tag — the same rule the context menu follows.
  _TagDrag _dragPayload(String tag) {
    if (!_selected.contains(tag)) return _TagDrag([tag]);
    return _TagDrag(_selectionInOrder(context.read<AppState>()));
  }

  Future<void> _onDropOnGroup(String? groupId, _TagDrag drag) async {
    await context.read<AppState>().moveTagsToGroup(drag.tags, groupId);
    if (mounted) setState(() => _selected.removeAll(drag.tags));
  }

  Future<void> _showMoveMenu(BuildContext buttonContext) async {
    final appState = context.read<AppState>();
    final targets = _selectionInOrder(appState);
    if (targets.isEmpty) return;
    final box = buttonContext.findRenderObject()! as RenderBox;
    final action = await showPanelContextMenu<String>(
      context: context,
      // Anchored above the button: the bar sits at the bottom of the panel
      // and a menu dropping down would open off-screen.
      position: box.localToGlobal(Offset.zero),
      items: _moveMenuItems(appState),
    );
    if (action == null || !mounted) return;
    await _applyMoveAction(action, targets);
  }

  Future<void> _mergeSelection() async {
    final l10n = AppLocalizations.of(context)!;
    final appState = context.read<AppState>();
    final ops = context.read<TagOps>();
    final dataset = context.read<DatasetState>();
    final targets = _selectionInOrder(appState);
    if (targets.length < 2) return;

    final input = await showMergeTagsDialog(
      context,
      tags: targets,
      canRewriteCaptions: dataset.scopedFiles.isNotEmpty,
    );
    if (input == null || !mounted) return;

    await appState.mergeCommonTags(targets, input.target);
    setState(() => _selected.removeAll(targets));
    if (!input.rewriteCaptions) return;

    final result = await ops.mergeEverywhere(
      targets,
      input.target,
      label: l10n.opMergeLabel(input.target),
    );
    if (!mounted) return;
    if (result.failures.isNotEmpty) {
      _snack(l10n.importFailedMsg(result.failures.first.error));
    } else {
      _snack(l10n.mergeTagsSummary(input.target, result.changed));
    }
  }

  Future<void> _deleteSelection() async {
    final l10n = AppLocalizations.of(context)!;
    final appState = context.read<AppState>();
    final targets = _selectionInOrder(appState);
    if (targets.isEmpty) return;
    if (!await _confirm(
      title: l10n.organizeDelete,
      message: l10n.organizeDeleteConfirm(targets.length),
    )) {
      return;
    }
    await appState.removeCommonTags(targets);
    if (mounted) setState(() => _selected.removeAll(targets));
  }

  void _setOrganizeMode(bool value) {
    setState(() {
      _organizeMode = value;
      if (!value) {
        _selected.clear();
        _anchor = null;
      }
    });
  }

  // --- Build --------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final semantic = context.semantic;
    final scheme = Theme.of(context).colorScheme;
    final appState = context.watch<AppState>();
    final session = context.watch<EditorSession>();
    // The cached list identity only moves when captions change, so this does
    // not rebuild the library on every gallery selection.
    final datasetTags = context.select<DatasetState, List<DatasetTag>>(
      (s) => s.datasetTags,
    );
    // Registers a dependency on the glossary scope so a translation edit
    // re-runs the filter below. The values themselves come off AppState,
    // which is the same service and answers in every display mode — a user
    // who turned glosses *off* still expects to find a tag by its Chinese
    // name. (Null outside the app shell, e.g. in widget tests.)
    TagGlossScope.maybeOf(context);
    final glosses = appState.tagTranslations;

    final commonTags = appState.commonTags;
    final commonSet = commonTags.toSet();
    final inDataset = {for (final entry in datasetTags) entry.tag};
    final matcher = TagSearchMatcher(_filter);

    bool statusAllows(String tag) => switch (_status) {
      _LibraryStatus.all => true,
      _LibraryStatus.used => session.hasTag(tag),
      _LibraryStatus.unused => !session.hasTag(tag),
      // Library tags are by definition not new; the "new" filter shows the
      // image's unknown tags and nothing else.
      _LibraryStatus.fresh => false,
    };
    bool visible(String tag) =>
        statusAllows(tag) &&
        (!_datasetOnly || inDataset.contains(tag)) &&
        matcher.matches(tag, glosses.glossFor(tag));

    final allNewTags = session.hasImage
        ? session.tags.where((t) => !commonSet.contains(t)).toList()
        : const <String>[];
    // The search narrows this section too: a filter that left an unrelated
    // block of chips standing would read as "no match, except these". The
    // pill above still counts the whole set, like the other three.
    final newTags = allNewTags
        .where((t) => matcher.matches(t, glosses.glossFor(t)))
        .toList();
    final showNewSection =
        newTags.isNotEmpty &&
        (_status == _LibraryStatus.all || _status == _LibraryStatus.fresh);

    // (group, visible tags) sections; ungrouped last. Under any narrowing,
    // empty sections disappear; with none, empty groups stay visible so they
    // can be managed (and take a drop), but an empty ungrouped section is
    // just noise.
    final narrowed =
        !matcher.isEmpty || _status != _LibraryStatus.all || _datasetOnly;
    final sections =
        <(TagGroup?, List<String>)>[
          for (final group in appState.tagGroups)
            (group, group.tags.where(visible).toList()),
          (null, appState.ungroupedTags.where(visible).toList()),
        ].where((s) {
          if (narrowed) return s.$2.isNotEmpty;
          return s.$1 != null || s.$2.isNotEmpty;
        }).toList();

    _visibleOrder = [for (final (_, tags) in sections) ...tags];

    final sectionIds = [
      for (final (group, _) in sections) group?.id ?? kUngroupedSectionId,
    ];
    final allCollapsed =
        sectionIds.isNotEmpty && sectionIds.every(appState.isTagGroupCollapsed);
    final hiddenByDataset = _datasetOnly
        ? commonTags.where((t) => !inDataset.contains(t)).length
        : 0;
    final ungrouped = appState.ungroupedTags;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Filter and actions share one band: the tab above already names
        // this view and carries its count, so a separate title row would be
        // a second header saying the same thing.
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 6, 6),
          child: Row(
            children: [
              Expanded(
                child: PanelSearchField(
                  hint: l10n.filterTagsHint,
                  focusNode: widget.filterFocusNode,
                  onChanged: (value) => setState(() => _filter = value),
                  padding: EdgeInsets.zero,
                ),
              ),
              const SizedBox(width: 4),
              PanelIconButton(
                icon: Icons.add,
                tooltip: l10n.addTagsTitle,
                size: 16,
                hitSize: 28,
                onPressed: _showAddDialog,
              ),
              PanelIconButton(
                icon: Icons.create_new_folder_outlined,
                tooltip: l10n.newGroupTitle,
                size: 16,
                hitSize: 28,
                onPressed: _createGroup,
              ),
              PanelIconButton(
                icon: allCollapsed ? Icons.unfold_more : Icons.unfold_less,
                tooltip: allCollapsed
                    ? l10n.libraryExpandAllTooltip
                    : l10n.libraryCollapseAllTooltip,
                size: 16,
                hitSize: 28,
                onPressed: sectionIds.isEmpty
                    ? null
                    : () => appState.setAllTagGroupsCollapsed(
                        sectionIds,
                        collapsed: !allCollapsed,
                      ),
              ),
              // The dictionary is one click from wherever tags are on screen,
              // carrying whatever the user has typed into the filter: the
              // moment a tag's meaning is unclear is the moment they are
              // looking at it.
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
                icon: Icons.checklist,
                tooltip: l10n.groupEditModeTooltip,
                size: 16,
                hitSize: 28,
                color: _organizeMode ? scheme.primary : null,
                onPressed: () => _setOrganizeMode(!_organizeMode),
              ),
              // Import/export/clear live in an overflow menu; the Builder
              // provides the button's own context to anchor the popup.
              Builder(
                builder: (buttonContext) => PanelIconButton(
                  icon: Icons.more_horiz,
                  tooltip: l10n.moreActionsTooltip,
                  size: 16,
                  hitSize: 28,
                  onPressed: () => _showMoreMenu(buttonContext),
                ),
              ),
            ],
          ),
        ),
        // The browse controls stay up while organizing: a filter narrows what
        // the batch actions can reach, and one that is active but invisible is
        // how a selection ends up smaller — or larger — than it looked.
        _BrowseControls(
          status: _status,
          onStatusChanged: (value) => setState(() => _status = value),
          usedCount: commonTags.where(session.hasTag).length,
          unusedCount:
              commonTags.length - commonTags.where(session.hasTag).length,
          newCount: allNewTags.length,
          allCount: commonTags.length,
          datasetOnly: _datasetOnly,
          onDatasetOnlyChanged: (value) => setState(() => _datasetOnly = value),
          hiddenByDataset: hiddenByDataset,
          datasetLoaded: datasetTags.isNotEmpty,
        ),
        if (_organizeMode)
          _OrganizeHeader(
            selected: _selected.length,
            onDone: () => _setOrganizeMode(false),
          ),
        Expanded(
          child: Container(
            // A faint wash while organizing — a reminder that a click here
            // selects instead of applying to the current image, since the
            // chips themselves keep the same pill shape either way.
            decoration: _organizeMode
                ? BoxDecoration(
                    color: scheme.primary.withAlpha(10),
                    border: Border(
                      top: BorderSide(color: scheme.primary.withAlpha(60)),
                    ),
                  )
                : null,
            child: sections.isEmpty && !showNewSection
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        narrowed && commonTags.isNotEmpty
                            ? l10n.libraryNoMatches
                            : l10n.libraryEmpty,
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
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _SectionLabel(
                                text: _organizeMode
                                    ? l10n.organizeHint
                                    : l10n.libraryBrowseHint,
                                color: _organizeMode ? scheme.primary : null,
                              ),
                              // Sections are single keyed children so a
                              // reorder slides them to their new position.
                              AnimatedReorderColumn(
                                reorderToken: _reorderTick,
                                children: [
                                  for (final (group, tags) in sections)
                                    _GroupSection(
                                      key: ValueKey(
                                        group?.id ?? kUngroupedSectionId,
                                      ),
                                      group: group,
                                      tags: tags,
                                      session: session,
                                      appState: appState,
                                      organizeMode: _organizeMode,
                                      selected: _selected,
                                      expanded: _expanded.contains(
                                        group?.id ?? kUngroupedSectionId,
                                      ),
                                      onToggleExpanded: () => setState(() {
                                        final id =
                                            group?.id ?? kUngroupedSectionId;
                                        if (!_expanded.remove(id)) {
                                          _expanded.add(id);
                                        }
                                      }),
                                      isFirstGroup:
                                          group != null &&
                                          group.id ==
                                              appState.tagGroups.first.id,
                                      isLastGroup:
                                          group != null &&
                                          group.id ==
                                              appState.tagGroups.last.id,
                                      ungroupedCount: ungrouped.length,
                                      onChipTap: (tag) =>
                                          _onChipTap(session, tag),
                                      onChipContextMenu: _onChipContextMenu,
                                      dragPayload: _dragPayload,
                                      onDrop: _onDropOnGroup,
                                      onGroupMenu: _showGroupMenu,
                                      onDeleteGroup: _confirmDeleteGroup,
                                      onColorTap: _showColorSwatches,
                                      onReorder: _reorderGroup,
                                      onAiGroup: () => showAiGroupingDialog(
                                        context,
                                        tags: ungrouped,
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        if (showNewSection) ...[
                          const SizedBox(height: 12),
                          // A hairline, not a card: this is a section of the
                          // same list, not a separate surface.
                          Container(height: 1, color: semantic.line),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        l10n.newTagsSection,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: AppText.secondary,
                                          fontWeight: FontWeight.w600,
                                          color: scheme.onSurface,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      '${newTags.length}',
                                      style: monoStyle(
                                        context,
                                        size: AppText.small,
                                        color: semantic.muted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              _LinkButton(
                                label: l10n.addAllToLibrary,
                                onTap: () => appState.addCommonTags(newTags),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              for (final tag in newTags)
                                _NewTagChip(
                                  label: tag,
                                  onTap: () => appState.addCommonTags([tag]),
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
          ),
        ),
        const Divider(),
        if (_organizeMode)
          _OrganizeActionBar(
            selected: _selected.length,
            canMerge: _selected.length > 1,
            onMove: _showMoveMenu,
            onMerge: _mergeSelection,
            onDelete: _deleteSelection,
          )
        else
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                _LegendItem(color: semantic.ok, label: l10n.legendApplied),
                _LegendItem(
                  color: semantic.muted,
                  label: l10n.legendNotApplied,
                ),
                _LegendItem(color: semantic.warn, label: l10n.legendNew),
              ],
            ),
          ),
      ],
    );
  }
}

/// The browse-state band: status filter over the current image, plus the
/// dataset-scope switch.
class _BrowseControls extends StatelessWidget {
  const _BrowseControls({
    required this.status,
    required this.onStatusChanged,
    required this.allCount,
    required this.usedCount,
    required this.unusedCount,
    required this.newCount,
    required this.datasetOnly,
    required this.onDatasetOnlyChanged,
    required this.hiddenByDataset,
    required this.datasetLoaded,
  });

  final _LibraryStatus status;
  final ValueChanged<_LibraryStatus> onStatusChanged;
  final int allCount;
  final int usedCount;
  final int unusedCount;
  final int newCount;
  final bool datasetOnly;
  final ValueChanged<bool> onDatasetOnlyChanged;
  final int hiddenByDataset;
  final bool datasetLoaded;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final semantic = context.semantic;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 5,
            runSpacing: 5,
            children: [
              _StatusPill(
                label: '${l10n.libraryStatusAll} $allCount',
                selected: status == _LibraryStatus.all,
                onTap: () => onStatusChanged(_LibraryStatus.all),
              ),
              _StatusPill(
                label: '${l10n.libraryStatusUsed} $usedCount',
                selected: status == _LibraryStatus.used,
                accent: semantic.ok,
                onTap: () => onStatusChanged(_LibraryStatus.used),
              ),
              _StatusPill(
                label: '${l10n.libraryStatusUnused} $unusedCount',
                selected: status == _LibraryStatus.unused,
                onTap: () => onStatusChanged(_LibraryStatus.unused),
              ),
              _StatusPill(
                label: '${l10n.libraryStatusNew} $newCount',
                selected: status == _LibraryStatus.fresh,
                // The same amber the new-tag chips use: "new" means the same
                // thing in both places.
                accent: semantic.warn,
                onTap: () => onStatusChanged(_LibraryStatus.fresh),
              ),
            ],
          ),
          if (datasetLoaded) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                AppSwitch(value: datasetOnly, onChanged: onDatasetOnlyChanged),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    l10n.libraryDatasetOnly,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: AppText.small,
                      color: semantic.muted,
                    ),
                  ),
                ),
                if (datasetOnly && hiddenByDataset > 0) ...[
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      l10n.libraryDatasetOnlyHidden(hiddenByDataset),
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: AppText.small,
                        color: semantic.muted.withAlpha(170),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// One filter pill. [accent] tints the selected fill for the two states that
/// already have a color elsewhere in the panel.
class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.label,
    required this.selected,
    required this.onTap,
    this.accent,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final semantic = context.semantic;
    final tint = accent ?? scheme.primary;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
          decoration: BoxDecoration(
            color: selected
                ? Color.alphaBlend(tint.withAlpha(45), semantic.panel)
                : Colors.transparent,
            border: Border.all(
              color: selected ? tint.withAlpha(150) : semantic.line,
            ),
            borderRadius: BorderRadius.circular(AppRadii.pill),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: AppText.small,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: selected ? (accent ?? scheme.onSurface) : semantic.muted,
            ),
          ),
        ),
      ),
    );
  }
}

/// The strip that replaces the browse controls while organizing.
class _OrganizeHeader extends StatelessWidget {
  const _OrganizeHeader({required this.selected, required this.onDone});

  final int selected;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final semantic = context.semantic;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 8, 6),
      child: Row(
        children: [
          Icon(Icons.checklist, size: 14, color: scheme.primary),
          const SizedBox(width: 6),
          // Both texts ellipsize: at the 200px minimum panel width the mode
          // name and the selection count together outrun the row, and "Done"
          // is the one thing that must never be pushed off the edge.
          Flexible(
            child: Text(
              l10n.organizeModeTitle,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: AppText.secondary,
                fontWeight: FontWeight.w600,
                color: scheme.primary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              l10n.organizeSelectedCount(selected),
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: AppText.small, color: semantic.muted),
            ),
          ),
          const Spacer(),
          _LinkButton(label: l10n.organizeModeDone, onTap: onDone),
        ],
      ),
    );
  }
}

/// Move / merge / delete, disabled until something is selected.
class _OrganizeActionBar extends StatelessWidget {
  const _OrganizeActionBar({
    required this.selected,
    required this.canMerge,
    required this.onMove,
    required this.onMerge,
    required this.onDelete,
  });

  final int selected;
  final bool canMerge;
  final ValueChanged<BuildContext> onMove;
  final VoidCallback onMerge;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final enabled = selected > 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 7, 10, 8),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Builder(
              builder: (buttonContext) => FilledButton(
                onPressed: enabled ? () => onMove(buttonContext) : null,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  visualDensity: VisualDensity.compact,
                ),
                child: Text(
                  l10n.organizeMoveToGroup,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: AppText.small),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            flex: 3,
            child: OutlinedButton(
              // Merging one tag into itself is a no-op, so the button waits
              // for a second selection rather than opening a dialog that can
              // only be cancelled.
              onPressed: canMerge ? onMerge : null,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                visualDensity: VisualDensity.compact,
              ),
              child: Text(
                l10n.organizeMergeInto,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: AppText.small),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            flex: 2,
            child: OutlinedButton(
              onPressed: enabled ? onDelete : null,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                visualDensity: VisualDensity.compact,
                foregroundColor: scheme.error,
                side: BorderSide(color: scheme.error.withAlpha(120)),
              ),
              child: Text(
                l10n.organizeDelete,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: AppText.small),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One collapsible group: header, then two rows of chips and a way to see
/// the rest.
class _GroupSection extends StatelessWidget {
  const _GroupSection({
    super.key,
    required this.group,
    required this.tags,
    required this.session,
    required this.appState,
    required this.organizeMode,
    required this.selected,
    required this.expanded,
    required this.onToggleExpanded,
    required this.isFirstGroup,
    required this.isLastGroup,
    required this.ungroupedCount,
    required this.onChipTap,
    required this.onChipContextMenu,
    required this.dragPayload,
    required this.onDrop,
    required this.onGroupMenu,
    required this.onDeleteGroup,
    required this.onColorTap,
    required this.onReorder,
    required this.onAiGroup,
  });

  final TagGroup? group;
  final List<String> tags;
  final EditorSession session;
  final AppState appState;
  final bool organizeMode;
  final Set<String> selected;
  final bool expanded;
  final VoidCallback onToggleExpanded;
  final bool isFirstGroup;
  final bool isLastGroup;
  final int ungroupedCount;
  final ValueChanged<String> onChipTap;
  final void Function(Offset position, String tag) onChipContextMenu;
  final _TagDrag Function(String tag) dragPayload;
  final Future<void> Function(String? groupId, _TagDrag drag) onDrop;
  final void Function(Offset position, TagGroup group) onGroupMenu;
  final Future<void> Function(TagGroup group) onDeleteGroup;
  final void Function(Offset position, TagGroup group) onColorTap;
  final void Function(TagGroup group, int delta) onReorder;
  final VoidCallback onAiGroup;

  String get _id => group?.id ?? kUngroupedSectionId;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final semantic = context.semantic;
    final collapsed = appState.isTagGroupCollapsed(_id);
    // Usage counts the whole group, not the filtered slice: "6/9 used" is a
    // fact about the group, and a filter must not make it lie.
    final members = group?.tags ?? appState.ungroupedTags;
    final used = members.where(session.hasTag).length;

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _GroupHeader(
            group: group,
            total: members.length,
            used: used,
            collapsed: collapsed,
            organizeMode: organizeMode,
            pendingUngrouped: group == null && ungroupedCount > 0,
            onToggleCollapsed: () =>
                appState.setTagGroupCollapsed(_id, !collapsed),
            onDropTags: (drag) => onDrop(group?.id, drag),
            onContextMenu: group == null
                ? null
                : (position) => onGroupMenu(position, group!),
            onDelete: group == null ? null : () => onDeleteGroup(group!),
            onColorTap: !organizeMode || group == null
                ? null
                : (position) => onColorTap(position, group!),
            // Arrows reorder within the full group list (a filter may hide
            // sections but the order is global) and disable at the ends.
            onMoveUp: !organizeMode || group == null || isFirstGroup
                ? null
                : () => onReorder(group!, -1),
            onMoveDown: !organizeMode || group == null || isLastGroup
                ? null
                : () => onReorder(group!, 1),
            onAiGroup: group == null && ungroupedCount > 0 ? onAiGroup : null,
          ),
          if (!collapsed) ...[
            const SizedBox(height: 7),
            if (tags.isEmpty && organizeMode)
              _DropPlaceholder(
                label: l10n.organizeDropHere,
                onDropTags: (drag) => onDrop(group?.id, drag),
              )
            else
              RowLimitedWrap(
                spacing: 7,
                runSpacing: 7,
                maxRuns: expanded ? null : _groupRowCap,
                overflowBuilder: (context, hidden) => _MoreChip(
                  label: l10n.libraryMoreTags(hidden),
                  onTap: onToggleExpanded,
                ),
                children: [
                  for (final tag in tags)
                    _DraggableChip(
                      tag: tag,
                      enabled: organizeMode,
                      payload: dragPayload,
                      child: _LibraryTagChip(
                        label: tag,
                        applied: session.hasTag(tag),
                        enabled: organizeMode || session.hasImage,
                        dotColor: group == null ? null : Color(group!.color),
                        selectionMode: organizeMode,
                        selected: selected.contains(tag),
                        onTap: () => onChipTap(tag),
                        onContextMenu: (position) =>
                            onChipContextMenu(position, tag),
                      ),
                    ),
                ],
              ),
            if (expanded && tags.isNotEmpty) ...[
              const SizedBox(height: 7),
              _LinkButton(label: l10n.libraryShowLess, onTap: onToggleExpanded),
            ],
          ],
          if (collapsed) const SizedBox(height: 2),
          if (collapsed)
            Container(
              height: 1,
              color: semantic.line.withAlpha(120),
              margin: const EdgeInsets.only(top: 4),
            ),
        ],
      ),
    );
  }
}

/// Wraps a chip in a [Draggable] while organizing. Outside organize mode the
/// chip is returned untouched — a drag gesture there would fight the click
/// that applies a tag.
class _DraggableChip extends StatelessWidget {
  const _DraggableChip({
    required this.tag,
    required this.enabled,
    required this.payload,
    required this.child,
  });

  final String tag;
  final bool enabled;
  final _TagDrag Function(String tag) payload;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    return Draggable<_TagDrag>(
      data: payload(tag),
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: _DragFeedback(count: payload(tag).tags.length, label: tag),
      childWhenDragging: Opacity(opacity: 0.35, child: child),
      child: child,
    );
  }
}

class _DragFeedback extends StatelessWidget {
  const _DragFeedback({required this.count, required this.label});

  final int count;
  final String label;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return Transform.translate(
      // Just below and right of the pointer, so the drop target stays visible.
      offset: const Offset(8, 8),
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: scheme.primary,
            borderRadius: BorderRadius.circular(AppRadii.pill),
          ),
          child: Text(
            count > 1 ? l10n.organizeSelectedCount(count) : label,
            style: TextStyle(fontSize: AppText.small, color: scheme.onPrimary),
          ),
        ),
      ),
    );
  }
}

/// The empty-group drop zone shown while organizing.
class _DropPlaceholder extends StatefulWidget {
  const _DropPlaceholder({required this.label, required this.onDropTags});

  final String label;
  final ValueChanged<_TagDrag> onDropTags;

  @override
  State<_DropPlaceholder> createState() => _DropPlaceholderState();
}

class _DropPlaceholderState extends State<_DropPlaceholder> {
  bool _over = false;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    final scheme = Theme.of(context).colorScheme;
    return DragTarget<_TagDrag>(
      onWillAcceptWithDetails: (_) {
        setState(() => _over = true);
        return true;
      },
      onLeave: (_) => setState(() => _over = false),
      onAcceptWithDetails: (details) {
        setState(() => _over = false);
        widget.onDropTags(details.data);
      },
      builder: (context, _, _) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
        decoration: BoxDecoration(
          color: _over ? scheme.primary.withAlpha(30) : Colors.transparent,
          border: Border.all(
            color: _over ? scheme.primary : semantic.warn.withAlpha(120),
          ),
          borderRadius: BorderRadius.circular(AppRadii.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add, size: 11, color: semantic.warn),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                widget.label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: AppText.small, color: semantic.warn),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The "+N more" chip that opens a capped group.
class _MoreChip extends StatelessWidget {
  const _MoreChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2.5),
          decoration: BoxDecoration(
            border: Border.all(color: scheme.primary.withAlpha(110)),
            borderRadius: BorderRadius.circular(AppRadii.pill),
          ),
          child: Text(
            label,
            style: TextStyle(fontSize: AppText.small, color: scheme.primary),
          ),
        ),
      ),
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

/// Section header inside the library card: fold chevron, color dot, group
/// name, count and usage. Real groups take a right-click menu (edit/delete);
/// ungrouped does not, but it does carry the AI filing action. In organize
/// mode real groups additionally expose quick controls: the color dot opens a
/// swatch picker and arrows move the section up/down. Every header is a drop
/// target — dragging a selection onto one is the fastest way to file it.
class _GroupHeader extends StatefulWidget {
  const _GroupHeader({
    required this.group,
    required this.total,
    required this.used,
    required this.collapsed,
    required this.organizeMode,
    required this.pendingUngrouped,
    required this.onToggleCollapsed,
    required this.onDropTags,
    this.onContextMenu,
    this.onDelete,
    this.onColorTap,
    this.onMoveUp,
    this.onMoveDown,
    this.onAiGroup,
  });

  final TagGroup? group;
  final int total;
  final int used;
  final bool collapsed;
  final bool organizeMode;

  /// Marks the ungrouped section as a backlog rather than a section like any
  /// other — it is the one bucket that is supposed to be empty.
  final bool pendingUngrouped;

  final VoidCallback onToggleCollapsed;
  final ValueChanged<_TagDrag> onDropTags;
  final ValueChanged<Offset>? onContextMenu;

  /// Deletes the group (tags return to ungrouped); null for ungrouped,
  /// which cannot be deleted.
  final VoidCallback? onDelete;

  /// Organize mode only. [onColorTap] gets the tap position to anchor the
  /// swatch popup; the move callbacks are null at the ends of the list
  /// (arrow renders disabled).
  final ValueChanged<Offset>? onColorTap;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;

  final VoidCallback? onAiGroup;

  @override
  State<_GroupHeader> createState() => _GroupHeaderState();
}

class _GroupHeaderState extends State<_GroupHeader> {
  bool _dragOver = false;

  Widget _headerAction({
    required IconData icon,
    required String tooltip,
    VoidCallback? onTap,
    Color? color,
  }) {
    final semantic = context.semantic;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(99),
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Icon(
            icon,
            size: 13,
            color: onTap == null
                ? semantic.muted.withAlpha(90)
                : (color ?? semantic.muted),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final semantic = context.semantic;
    final scheme = Theme.of(context).colorScheme;
    final group = widget.group;
    final editMode = widget.onColorTap != null;

    final dot = Container(
      width: editMode ? 11 : 9,
      height: editMode ? 11 : 9,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: group == null ? semantic.muted : Color(group.color),
        // A hairline ring hints that the dot became a control.
        border: editMode ? Border.all(color: semantic.line) : null,
      ),
    );

    final row = Row(
      children: [
        Icon(
          widget.collapsed ? Icons.chevron_right : Icons.expand_more,
          size: 15,
          color: semantic.muted,
        ),
        const SizedBox(width: 2),
        if (widget.onColorTap == null)
          dot
        else
          Tooltip(
            message: l10n.changeGroupColorTooltip,
            child: GestureDetector(
              onTapDown: (details) =>
                  widget.onColorTap!(details.globalPosition),
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                // Padded hit zone; the visual dot stays small.
                child: Padding(padding: const EdgeInsets.all(2), child: dot),
              ),
            ),
          ),
        const SizedBox(width: 6),
        // Name, size and the group controls sit left; the Expanded is what
        // pushes the status cluster to the right edge without a Spacer
        // competing with the two texts for the same free space.
        Expanded(
          child: Row(
            children: [
              Flexible(
                child: Text(
                  group?.name ?? l10n.ungroupedSection,
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
                '${widget.total}',
                style: monoStyle(context, size: 11, color: semantic.muted),
              ),
              if (editMode) ...[
                const SizedBox(width: 4),
                _headerAction(
                  icon: Icons.arrow_upward,
                  tooltip: l10n.moveGroupUpTooltip,
                  onTap: widget.onMoveUp,
                ),
                _headerAction(
                  icon: Icons.arrow_downward,
                  tooltip: l10n.moveGroupDownTooltip,
                  onTap: widget.onMoveDown,
                ),
              ],
              if (widget.onDelete != null) ...[
                const SizedBox(width: 2),
                _headerAction(
                  icon: Icons.delete_outline,
                  tooltip: l10n.deleteGroupMenu,
                  onTap: widget.onDelete,
                ),
              ],
            ],
          ),
        ),
        if (widget.onAiGroup != null)
          _headerAction(
            icon: Icons.auto_awesome,
            tooltip: l10n.aiGroupButton,
            color: scheme.primary,
            onTap: widget.onAiGroup,
          ),
        if (widget.pendingUngrouped)
          Flexible(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(width: 4),
                Icon(
                  Icons.warning_amber_rounded,
                  size: 12,
                  color: semantic.warn.withAlpha(190),
                ),
                const SizedBox(width: 3),
                Flexible(
                  child: Text(
                    l10n.libraryUngroupedPending,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: AppText.small,
                      color: semantic.warn,
                    ),
                  ),
                ),
              ],
            ),
          )
        // Organize mode trades the usage note for the reorder and delete
        // controls: at the 200px minimum width both do not fit, and while
        // filing groups the current image is not what you are looking at.
        else if (widget.total > 0 && !editMode)
          Flexible(
            child: Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Text(
                l10n.libraryGroupUsage(widget.used, widget.total),
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: AppText.small,
                  color: widget.used > 0 ? semantic.ok : semantic.muted,
                ),
              ),
            ),
          ),
      ],
    );

    // The whole header row folds the section; the controls inside it swallow
    // their own taps, so the chevron is a hint rather than the only hit area.
    Widget content = MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onToggleCollapsed,
        onSecondaryTapDown: widget.onContextMenu == null
            ? null
            : (details) => widget.onContextMenu!(details.globalPosition),
        onLongPressStart: widget.onContextMenu == null
            ? null
            : (details) => widget.onContextMenu!(details.globalPosition),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
          decoration: BoxDecoration(
            color: _dragOver ? scheme.primary.withAlpha(40) : null,
            border: Border.all(
              color: _dragOver ? scheme.primary : Colors.transparent,
            ),
            borderRadius: BorderRadius.circular(AppRadii.input),
          ),
          child: row,
        ),
      ),
    );

    return DragTarget<_TagDrag>(
      onWillAcceptWithDetails: (_) {
        setState(() => _dragOver = true);
        return true;
      },
      onLeave: (_) => setState(() => _dragOver = false),
      onAcceptWithDetails: (details) {
        setState(() => _dragOver = false);
        widget.onDropTags(details.data);
      },
      builder: (context, _, _) => content,
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

  /// Organize mode: [selected] drives the accent highlight and the applied
  /// state is not shown (selection is about the library, not the image).
  final bool selectionMode;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    final scheme = Theme.of(context).colorScheme;

    final Color borderColor;
    final Color bgColor;
    final Color textColor;
    if (selectionMode && selected) {
      borderColor = scheme.primary;
      bgColor = Color.alphaBlend(scheme.primary.withAlpha(38), semantic.panel);
      textColor = scheme.onSurface;
    } else if (!selectionMode && applied) {
      borderColor = semantic.ok.withAlpha(115);
      bgColor = Color.alphaBlend(semantic.ok.withAlpha(38), semantic.panel);
      textColor = scheme.onSurface;
    } else {
      borderColor = semantic.line;
      bgColor = semantic.raised;
      // Unapplied tags are inventory, not state: muted ink keeps the applied
      // ones readable as the foreground.
      textColor = semantic.muted;
    }

    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2.5),
      decoration: BoxDecoration(
        color: bgColor,
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (selectionMode) ...[
            // A checkbox, not a checkmark: unlike "applied", "selected" has
            // no colored fill of its own to lean on, so the unselected state
            // needs its own glyph rather than just omitting one.
            Icon(
              selected ? Icons.check_box : Icons.check_box_outline_blank,
              size: 12,
              color: selected ? scheme.primary : semantic.muted,
            ),
            const SizedBox(width: 4),
          ] else if (applied) ...[
            Icon(Icons.check, size: 10, color: semantic.ok),
            const SizedBox(width: 4),
          ],
          if (dotColor != null) ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: dotColor,
              ),
            ),
            const SizedBox(width: 5),
          ],
          // Flexible, not bare: a tag long enough to outrun the panel would
          // otherwise paint overflow stripes across a column the user cannot
          // widen past 480px. The gloss beside it is capped for the same
          // reason.
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: AppText.small, color: textColor),
            ),
          ),
          TagGlossLabel(label),
        ],
      ),
    );

    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        onSecondaryTapDown: (details) => onContextMenu(details.globalPosition),
        onLongPressStart: (details) => onContextMenu(details.globalPosition),
        child: withTagGlossTooltip(
          context: context,
          tag: label,
          child: MouseRegion(
            cursor: enabled
                ? SystemMouseCursors.click
                : SystemMouseCursors.basic,
            child: chip,
          ),
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
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: CustomPaint(
          painter: _DashedPillBorder(color: semantic.warn.withAlpha(140)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2.5),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.add, size: 10, color: semantic.warn),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: AppText.small,
                    color: semantic.warn,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Dashed pill outline for the "not in the library yet" chips — a proposal
/// reads as provisional, which a solid border does not convey.
class _DashedPillBorder extends CustomPainter {
  const _DashedPillBorder({required this.color});

  final Color color;

  static const double _dash = 3.5;
  static const double _gap = 3;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(size.height / 2),
    );
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final metric in (Path()..addRRect(rrect)).computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(metric.extractPath(distance, distance + _dash), paint);
        distance += _dash + _gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedPillBorder oldDelegate) =>
      oldDelegate.color != color;
}

/// Accent text action — the "全部入库" style link in section headers.
class _LinkButton extends StatelessWidget {
  const _LinkButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Text(
          label,
          style: TextStyle(
            fontSize: AppText.small,
            color: Theme.of(context).colorScheme.primary,
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
