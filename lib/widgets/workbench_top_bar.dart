import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../l10n/app_localizations.dart';
import '../state/ai_tagger_state.dart';
import '../state/batch_tag_state.dart';
import '../state/dataset_state.dart';
import '../state/tag_ops.dart';
import '../theme/app_theme.dart';
import '../views/panels/batch_tag_dialog.dart';

/// Top bar of the workbench: identity, the dataset path chip, and the
/// theme / settings actions.
class WorkbenchTopBar extends StatelessWidget {
  const WorkbenchTopBar({super.key, required this.onOpenFolder});

  final VoidCallback onOpenFolder;

  IconData _themeIcon(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return Icons.light_mode_outlined;
      case ThemeMode.dark:
        return Icons.dark_mode_outlined;
      case ThemeMode.system:
        return Icons.brightness_auto_outlined;
    }
  }

  void _cycleTheme(AppState appState) {
    const next = {
      ThemeMode.light: ThemeMode.dark,
      ThemeMode.dark: ThemeMode.system,
      ThemeMode.system: ThemeMode.light,
    };
    appState.updateThemeMode(next[appState.currentThemeMode]!);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final semantic = context.semantic;
    final scheme = Theme.of(context).colorScheme;
    final appState = context.watch<AppState>();
    final dataset = context.watch<DatasetState>();
    final tagOps = context.watch<TagOps>();
    final directory = appState.browsingDirectory;

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: semantic.panel,
        border: Border(bottom: BorderSide(color: semantic.line)),
      ),
      child: Row(
        children: [
          Image.asset(
            'assets/icon/icon.png',
            width: 22,
            height: 22,
            filterQuality: FilterQuality.medium,
          ),
          const SizedBox(width: 10),
          Text(
            l10n.appTitle,
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(width: 14),
          // The chip's flex slot absorbs ALL free width (aligned left inside),
          // so the trailing icons stay flush right. A Flexible chip next to a
          // Spacer would split the free space and leave the chip's unused
          // half dangling at the row's end.
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: InkWell(
                onTap: onOpenFolder,
                borderRadius: BorderRadius.circular(7),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    border: Border.all(color: semantic.line),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.folder_outlined,
                        size: 14,
                        color: semantic.muted,
                      ),
                      const SizedBox(width: 7),
                      Flexible(
                        child: Text(
                          directory ?? l10n.noDatasetOpen,
                          overflow: TextOverflow.ellipsis,
                          style: monoStyle(
                            context,
                            size: 11.5,
                            color: directory == null
                                ? semantic.muted
                                : scheme.onSurface,
                          ),
                        ),
                      ),
                      if (directory != null) ...[
                        const SizedBox(width: 8),
                        Text(
                          l10n.imageCountShort(dataset.totalCount),
                          style: monoStyle(
                            context,
                            size: 11.5,
                            color: semantic.muted,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
          _BatchTagButton(dataset: dataset),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Container(width: 1, height: 18, color: semantic.line),
          ),
          IconButton(
            icon: const Icon(Icons.undo, size: 18),
            tooltip: tagOps.undoLabel == null
                ? l10n.undo
                : l10n.undoTooltip(tagOps.undoLabel!),
            color: semantic.muted,
            visualDensity: VisualDensity.compact,
            onPressed: tagOps.canUndo ? tagOps.undo : null,
          ),
          IconButton(
            icon: const Icon(Icons.redo, size: 18),
            tooltip: tagOps.redoLabel == null
                ? l10n.redo
                : l10n.redoTooltip(tagOps.redoLabel!),
            color: semantic.muted,
            visualDensity: VisualDensity.compact,
            onPressed: tagOps.canRedo ? tagOps.redo : null,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Container(width: 1, height: 18, color: semantic.line),
          ),
          IconButton(
            icon: Icon(_themeIcon(appState.currentThemeMode), size: 18),
            tooltip: l10n.toggleTheme,
            color: semantic.muted,
            visualDensity: VisualDensity.compact,
            onPressed: () => _cycleTheme(appState),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined, size: 18),
            tooltip: l10n.settings,
            color: semantic.muted,
            visualDensity: VisualDensity.compact,
            onPressed: () => appState.updateView(MainView.settings),
          ),
        ],
      ),
    );
  }
}

/// Batch tagging entry point. While a run is active the icon becomes a small
/// progress ring and the button reopens the live progress dialog.
class _BatchTagButton extends StatelessWidget {
  const _BatchTagButton({required this.dataset});

  final DatasetState dataset;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final semantic = context.semantic;
    final batch = context.watch<BatchTagState>();
    final enabled = batch.running || dataset.allFiles.isNotEmpty;

    return IconButton(
      icon: batch.running
          ? SizedBox(
              width: 15,
              height: 15,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                value: batch.progress,
                color: Theme.of(context).colorScheme.primary,
              ),
            )
          : const Icon(Icons.auto_awesome_motion, size: 18),
      tooltip: batch.running
          ? l10n.batchTagRunning(batch.completed, batch.total)
          : l10n.batchTagButton,
      color: semantic.muted,
      visualDensity: VisualDensity.compact,
      onPressed: !enabled
          ? null
          : () => showBatchTagDialog(
                context,
                ai: context.read<AiTaggerState>(),
                batch: batch,
                dataset: dataset,
              ),
    );
  }
}
