import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../l10n/app_localizations.dart';
import '../../state/ai_tagger_state.dart';
import '../../state/dataset_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/panel_widgets.dart';
import '../../widgets/subdirectory_picker.dart';

/// Left panel — the file navigator: search, caption-status segments, and the
/// file list.
///
/// One control switches presentation: at one column the files render as
/// scannable rows (thumbnail + name + tag count + status), at two or more as
/// the thumbnail grid. Rows are the default because the navigator is narrow
/// and filenames are what you navigate by.
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
    final hasDirectory = context.select<AppState, bool>(
      (s) => s.browsingDirectory != null,
    );
    final columns = context
        .select<AppState, int>((s) => s.crossAxisCount)
        .clamp(1, 6);
    final fill = context.select<AppState, bool>((s) => s.thumbnailFill);

    // The divider to the center column is drawn by the resize handle.
    return Container(
      color: semantic.panel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (dataset.hasSubdirectories) ...[
                  SubdirectoryPicker(dataset: dataset),
                  const SizedBox(height: 8),
                ],
                PanelSearchField(
                  hint: l10n.searchFilenameHint,
                  onChanged: dataset.setQuery,
                  padding: EdgeInsets.zero,
                ),
                const SizedBox(height: 8),
                SegmentedControl<CaptionFilter>(
                  value: dataset.filter,
                  onChanged: dataset.setFilter,
                  segments: [
                    SegmentedOption(
                      value: CaptionFilter.all,
                      label: '${l10n.filterAll} ${dataset.totalCount}',
                    ),
                    SegmentedOption(
                      value: CaptionFilter.untagged,
                      label: '${l10n.filterUntagged} ${dataset.untaggedCount}',
                    ),
                    SegmentedOption(
                      value: CaptionFilter.tagged,
                      label: '${l10n.filterTagged} ${dataset.taggedCount}',
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(child: _buildBody(context, l10n, dataset, columns, fill)),
          Container(height: 1, color: semantic.line),
          _NavigatorFooter(
            columns: columns,
            fill: fill,
            l10n: l10n,
            onRefresh: hasDirectory ? onRefresh : null,
            onOpenFolder: onOpenFolder,
          ),
        ],
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    AppLocalizations l10n,
    DatasetState dataset,
    int columns,
    bool fill,
  ) {
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
        // A tag filter can empty the navigator from another panel entirely;
        // without a way out from here you have to go find where it was set.
        action: dataset.tagFilterActive
            ? TextButton.icon(
                onPressed: dataset.clearTagFilter,
                icon: const Icon(Icons.filter_alt_off_outlined, size: 15),
                label: Text(
                  l10n.clearTagFilter,
                  style: const TextStyle(fontSize: AppText.secondary),
                ),
              )
            : null,
      );
    }

    void open(File file) {
      dataset.select(file.path);
      onOpenExternalPreview(file);
    }

    // In compare mode the rows report review progress instead of the tag
    // count. Only built rows are diffed, so the cost stays bounded by what
    // is on screen rather than by the size of the dataset.
    final ai = context.watch<AiTaggerState>();

    if (columns == 1) {
      return ListView.builder(
        padding: const EdgeInsets.fromLTRB(6, 2, 6, 8),
        // Rows are a fixed height, so the list can skip measuring them.
        itemExtent: _FileRow.height,
        itemCount: visible.length,
        itemBuilder: (context, index) {
          final file = visible[index];
          // Diff once per row: pending count and review state are two reads
          // of the same answer.
          final pending = ai.compareMode
              ? ai.pendingFor(file.path, dataset.tagsOf(file.path)).length
              : 0;
          return _FileRow(
            file: file,
            selected: file.path == dataset.selectedFile?.path,
            captioned: dataset.hasCaption(file.path),
            tagCount: dataset.tagsOf(file.path).length,
            pendingReview: !ai.compareMode || !ai.hasResultFor(file.path)
                ? null
                : pending,
            fill: fill,
            onTap: () => dataset.select(file.path),
            onDoubleTap: () => open(file),
          );
        },
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(10, 2, 10, 10),
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
          fill: fill,
          okColor: semantic.ok,
          warnColor: semantic.warn,
          onTap: () => dataset.select(file.path),
          onDoubleTap: () => open(file),
        );
      },
    );
  }
}

/// One file as a scannable row: thumbnail, filename, tag count, status dot.
class _FileRow extends StatefulWidget {
  const _FileRow({
    required this.file,
    required this.selected,
    required this.captioned,
    required this.tagCount,
    required this.fill,
    required this.onTap,
    required this.onDoubleTap,
    this.pendingReview,
  });

  static const double thumb = 30;
  static const double height = 38;

  final File file;
  final bool selected;
  final bool captioned;
  final int tagCount;

  /// Compare mode only: how many AI suggestions this image has not taken.
  /// Null outside compare mode and for images with no result at all, which
  /// keeps the ordinary tag count showing for them.
  final int? pendingReview;

  final bool fill;
  final VoidCallback onTap;
  final VoidCallback onDoubleTap;

  @override
  State<_FileRow> createState() => _FileRowState();
}

class _FileRowState extends State<_FileRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final semantic = context.semantic;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        onDoubleTap: widget.onDoubleTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: widget.selected
                ? scheme.primary.withValues(alpha: 0.20)
                : _hovered
                ? semantic.raised
                : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadii.input),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(5),
                child: SizedBox(
                  width: _FileRow.thumb,
                  height: _FileRow.thumb,
                  child: Image.file(
                    widget.file,
                    fit: widget.fill ? BoxFit.cover : BoxFit.contain,
                    cacheWidth: 96,
                    errorBuilder: (context, error, stackTrace) => ColoredBox(
                      color: scheme.surfaceContainerHigh,
                      child: Icon(
                        Icons.broken_image_outlined,
                        size: 14,
                        color: semantic.muted,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Tooltip(
                  message: p.basename(widget.file.path),
                  waitDuration: const Duration(milliseconds: 700),
                  child: Text(
                    p.basename(widget.file.path),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: monoStyle(
                      context,
                      size: AppText.secondary,
                      color: widget.selected
                          ? scheme.onSurface
                          : semantic.muted,
                    ),
                  ),
                ),
              ),
              if (widget.pendingReview != null) ...[
                const SizedBox(width: 8),
                Text(
                  widget.pendingReview! > 0
                      ? AppLocalizations.of(
                          context,
                        )!.compareBadgePending(widget.pendingReview!)
                      : AppLocalizations.of(context)!.compareBadgeReviewed,
                  style: TextStyle(
                    fontSize: AppText.micro,
                    color: widget.pendingReview! > 0
                        ? semantic.warn
                        : semantic.ok,
                  ),
                ),
              ] else if (widget.tagCount > 0) ...[
                const SizedBox(width: 8),
                Text(
                  AppLocalizations.of(context)!.tagCountShort(widget.tagCount),
                  style: TextStyle(
                    fontSize: AppText.micro,
                    color: semantic.muted,
                  ),
                ),
              ],
              const SizedBox(width: 8),
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.captioned ? semantic.ok : semantic.warn,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({
    required this.file,
    required this.selected,
    required this.captioned,
    required this.fill,
    required this.okColor,
    required this.warnColor,
    required this.onTap,
    required this.onDoubleTap,
  });

  final File file;
  final bool selected;
  final bool captioned;
  final bool fill;
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
                // Fit mode letterboxes; a backdrop makes the empty bands
                // read as deliberate instead of broken.
                if (!fill) ColoredBox(color: scheme.surfaceContainerHigh),
                Image.file(
                  file,
                  fit: fill ? BoxFit.cover : BoxFit.contain,
                  // Thumbnails decode at a small size; full resolution would
                  // eat hundreds of MB across a large grid.
                  cacheWidth: 256,
                  errorBuilder: (context, error, stackTrace) => ColoredBox(
                    color: scheme.surfaceContainerHigh,
                    child: const Center(
                      child: Icon(Icons.broken_image_outlined, size: 18),
                    ),
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

/// Bottom strip of the navigator: the columns slider (1 = list mode) plus
/// the actions that no longer have a panel header to live in.
class _NavigatorFooter extends StatelessWidget {
  const _NavigatorFooter({
    required this.columns,
    required this.fill,
    required this.l10n,
    required this.onRefresh,
    required this.onOpenFolder,
  });

  final int columns;
  final bool fill;
  final AppLocalizations l10n;
  final VoidCallback? onRefresh;
  final VoidCallback onOpenFolder;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 4, 6, 4),
      child: Row(
        children: [
          Tooltip(
            message: l10n.columnsCount(columns),
            child: Icon(
              columns == 1
                  ? Icons.view_list_outlined
                  : Icons.grid_view_outlined,
              size: 14,
              color: semantic.muted,
            ),
          ),
          Expanded(
            child: Slider(
              value: columns.toDouble(),
              min: 1,
              max: 6,
              divisions: 5,
              onChanged: (value) =>
                  context.read<AppState>().updateCrossAxisCount(value.round()),
            ),
          ),
          // The icon previews the mode clicking switches to.
          PanelIconButton(
            icon: fill ? Icons.fit_screen_outlined : Icons.zoom_out_map,
            tooltip: fill ? l10n.thumbFitTooltip : l10n.thumbFillTooltip,
            size: 14,
            onPressed: () =>
                context.read<AppState>().updateThumbnailFill(!fill),
          ),
          PanelIconButton(
            icon: Icons.refresh,
            tooltip: l10n.refresh,
            size: 15,
            onPressed: onRefresh,
          ),
          PanelIconButton(
            icon: Icons.folder_open_outlined,
            tooltip: l10n.openFolder,
            size: 15,
            onPressed: onOpenFolder,
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
            if (action != null) ...[const SizedBox(height: 14), action!],
          ],
        ),
      ),
    );
  }
}
