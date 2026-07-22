import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../l10n/app_localizations.dart';
import '../../state/editor_session.dart';
import '../../theme/app_theme.dart';
import '../../widgets/panel_widgets.dart';
import 'dataset_tags_view.dart';

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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final semantic = context.semantic;
    final appState = context.watch<AppState>();
    final session = context.watch<EditorSession>();

    final commonTags = appState.commonTags;
    final commonSet = commonTags.toSet();
    final query = _filter.trim().toLowerCase();
    final visibleTags = query.isEmpty
        ? commonTags
        : commonTags.where((t) => t.toLowerCase().contains(query)).toList();
    final newTags = session.hasImage
        ? session.tags.where((t) => !commonSet.contains(t)).toList()
        : const <String>[];

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
              icon: Icons.swap_horiz,
              tooltip: l10n.importTagsTitle,
              onPressed: _showImportDialog,
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
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SectionLabel(text: l10n.clickToApplyHint),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 7,
                        runSpacing: 7,
                        children: [
                          for (final tag in visibleTags)
                            _LibraryTagChip(
                              label: tag,
                              applied: session.hasTag(tag),
                              enabled: session.hasImage,
                              onTap: () => session.toggleTag(tag),
                              onContextMenu: (position) =>
                                  _showTagMenu(context, position, tag),
                            ),
                        ],
                      ),
                      if (newTags.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: _SectionLabel(
                                text:
                                    '${l10n.newTagsSection} (${newTags.length})',
                              ),
                            ),
                            TextButton(
                              onPressed: () => appState.addCommonTags(newTags),
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
                                onTap: () => appState.addCommonTags([tag]),
                              ),
                          ],
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
  const _SectionLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.3,
        color: context.semantic.muted,
      ),
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
  });

  final String label;
  final bool applied;
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
          color: applied ? semantic.ok.withAlpha(140) : semantic.line,
        ),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (applied) ...[
            Icon(Icons.check, size: 11, color: semantic.ok),
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
