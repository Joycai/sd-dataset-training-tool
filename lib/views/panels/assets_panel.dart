import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../l10n/app_localizations.dart';
import '../../state/dataset_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/panel_widgets.dart';

/// Left panel: search, caption-status filters, and the thumbnail grid.
class AssetsPanel extends StatelessWidget {
  const AssetsPanel({
    super.key,
    required this.onOpenFolder,
    required this.onRefresh,
    required this.onOpenExternalPreview,
  });

  final VoidCallback onOpenFolder;
  final VoidCallback onRefresh;
  final ValueChanged<File> onOpenExternalPreview;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final semantic = context.semantic;
    final dataset = context.watch<DatasetState>();
    // select (not watch): the grid should not rebuild on unrelated AppState
    // notifications such as tag-library edits.
    final hasDirectory =
        context.select<AppState, bool>((s) => s.browsingDirectory != null);
    final columns = context
        .select<AppState, int>((s) => s.crossAxisCount)
        .clamp(2, 6);

    // The divider to the center column is drawn by the resize handle.
    return Container(
      color: semantic.panel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PanelHeader(
            title: l10n.assetsPanelTitle,
            count: dataset.totalCount,
            actions: [
              PanelIconButton(
                icon: Icons.refresh,
                tooltip: l10n.refresh,
                onPressed: hasDirectory ? onRefresh : null,
              ),
              PanelIconButton(
                icon: Icons.folder_open_outlined,
                tooltip: l10n.openFolder,
                onPressed: onOpenFolder,
              ),
            ],
          ),
          PanelSearchField(
            hint: l10n.searchFilenameHint,
            onChanged: dataset.setQuery,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                FilterChipPill(
                  label: '${l10n.filterAll} ${dataset.totalCount}',
                  selected: dataset.filter == CaptionFilter.all,
                  onTap: () => dataset.setFilter(CaptionFilter.all),
                ),
                FilterChipPill(
                  label: '${l10n.filterUntagged} ${dataset.untaggedCount}',
                  selected: dataset.filter == CaptionFilter.untagged,
                  onTap: () => dataset.setFilter(CaptionFilter.untagged),
                ),
                FilterChipPill(
                  label: '${l10n.filterTagged} ${dataset.taggedCount}',
                  selected: dataset.filter == CaptionFilter.tagged,
                  onTap: () => dataset.setFilter(CaptionFilter.tagged),
                ),
              ],
            ),
          ),
          Expanded(child: _buildBody(context, l10n, dataset, columns)),
          const Divider(),
          _ColumnsFooter(columns: columns, l10n: l10n),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context, AppLocalizations l10n,
      DatasetState dataset, int columns) {
    final semantic = context.semantic;

    if (dataset.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (dataset.error != null) {
      return _EmptyState(
        icon: Icons.error_outline,
        message: l10n.scanError(dataset.error!),
      );
    }
    if (dataset.totalCount == 0) {
      return _EmptyState(
        icon: Icons.photo_library_outlined,
        message: l10n.noImagesFound,
        action: FilledButton.icon(
          onPressed: onOpenFolder,
          icon: const Icon(Icons.folder_open_outlined, size: 16),
          label: Text(l10n.openFolder),
        ),
      );
    }

    final visible = dataset.visibleFiles;
    if (visible.isEmpty) {
      return _EmptyState(
        icon: Icons.filter_alt_outlined,
        message: l10n.noMatches,
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 12),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: visible.length,
      itemBuilder: (context, index) {
        final file = visible[index];
        final selected = file.path == dataset.selectedFile?.path;
        final captioned = dataset.hasCaption(file.path);
        return _Thumbnail(
          file: file,
          selected: selected,
          captioned: captioned,
          okColor: semantic.ok,
          warnColor: semantic.warn,
          onTap: () => dataset.select(file.path),
          onDoubleTap: () {
            dataset.select(file.path);
            onOpenExternalPreview(file);
          },
        );
      },
    );
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({
    required this.file,
    required this.selected,
    required this.captioned,
    required this.okColor,
    required this.warnColor,
    required this.onTap,
    required this.onDoubleTap,
  });

  final File file;
  final bool selected;
  final bool captioned;
  final Color okColor;
  final Color warnColor;
  final VoidCallback onTap;
  final VoidCallback onDoubleTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: p.basename(file.path),
      child: GestureDetector(
        onTap: onTap,
        onDoubleTap: onDoubleTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(7),
            border: Border.all(
              color: selected ? scheme.primary : Colors.transparent,
              width: 2,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: scheme.primary.withAlpha(77),
                      blurRadius: 0,
                      spreadRadius: 2,
                    ),
                  ]
                : null,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.file(
                  file,
                  fit: BoxFit.cover,
                  // Thumbnails decode at a small size; full resolution would
                  // eat hundreds of MB across a large grid.
                  cacheWidth: 256,
                  errorBuilder: (context, error, stackTrace) => ColoredBox(
                    color: scheme.surfaceContainerHigh,
                    child: const Center(
                        child: Icon(Icons.broken_image_outlined, size: 18)),
                  ),
                ),
                Positioned(
                  top: 4,
                  right: 4,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: captioned ? okColor : warnColor,
                      border: Border.all(color: Colors.black45, width: 1.5),
                    ),
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

class _ColumnsFooter extends StatelessWidget {
  const _ColumnsFooter({required this.columns, required this.l10n});

  final int columns;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: Row(
        children: [
          Icon(Icons.grid_view_outlined, size: 14, color: semantic.muted),
          Expanded(
            child: Slider(
              value: columns.toDouble(),
              min: 2,
              max: 6,
              divisions: 4,
              onChanged: (value) => context
                  .read<AppState>()
                  .updateCrossAxisCount(value.round()),
            ),
          ),
          Text(
            l10n.columnsCount(columns),
            style: monoStyle(context, size: 11, color: semantic.muted),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.message, this.action});

  final IconData icon;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 30, color: semantic.muted),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: semantic.muted),
            ),
            if (action != null) ...[
              const SizedBox(height: 14),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
