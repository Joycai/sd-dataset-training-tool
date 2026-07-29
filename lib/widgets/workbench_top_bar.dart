import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../l10n/app_localizations.dart';
import '../state/ai_tagger_state.dart';
import '../state/dataset_state.dart';
import '../state/tag_ops.dart';
import '../state/workbench_layout.dart';
import '../theme/app_theme.dart';

/// Title bar: sidebar toggles on the left, the centered activity capsule,
/// and the document-level actions on the right.
///
/// No traffic lights — the window keeps its native Windows frame, so the
/// capsule is the only thing this bar borrows from the macOS reference.
class WorkbenchTopBar extends StatelessWidget {
  const WorkbenchTopBar({
    super.key,
    required this.onOpenFolder,
    required this.agentOpen,
    required this.onToggleAgent,
    required this.onUndo,
    required this.onRedo,
  });

  final VoidCallback onOpenFolder;
  final bool agentOpen;
  final VoidCallback onToggleAgent;

  /// Routed through the workbench rather than calling [TagOps] directly: a
  /// replay can fail on some files, and reporting that needs a Scaffold.
  final VoidCallback onUndo;
  final VoidCallback onRedo;

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
    final tagOps = context.watch<TagOps>();
    final layout = context.watch<WorkbenchLayout>();

    return Container(
      height: AppMetrics.titleBar,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: semantic.panel,
        border: Border(bottom: BorderSide(color: semantic.line)),
      ),
      child: Row(
        children: [
          _BarIconButton(
            icon: Icons.vertical_split_outlined,
            tooltip: l10n.toggleNavigator,
            active: layout.navigatorVisible,
            onPressed: layout.toggleNavigator,
          ),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 460, maxWidth: 640),
                child: _ActivityCapsule(onOpenFolder: onOpenFolder),
              ),
            ),
          ),
          _BarIconButton(
            icon: Icons.undo,
            tooltip:
                '${tagOps.undoLabel == null ? l10n.undo : l10n.undoTooltip(tagOps.undoLabel!)} (Ctrl+Z)',
            onPressed: tagOps.canUndo ? onUndo : null,
          ),
          _BarIconButton(
            icon: Icons.redo,
            tooltip:
                '${tagOps.redoLabel == null ? l10n.redo : l10n.redoTooltip(tagOps.redoLabel!)} (Ctrl+Y)',
            onPressed: tagOps.canRedo ? onRedo : null,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Container(width: 1, height: 18, color: semantic.line),
          ),
          _BarIconButton(
            icon: Icons.auto_awesome,
            tooltip: l10n.agentPanelTitle,
            active: agentOpen,
            // The assistant is the one always-accented action in this group.
            color: agentOpen ? scheme.primary : null,
            onPressed: onToggleAgent,
          ),
          _BarIconButton(
            icon: _themeIcon(appState.currentThemeMode),
            tooltip: l10n.toggleTheme,
            onPressed: () => _cycleTheme(appState),
          ),
          _BarIconButton(
            icon: Icons.view_sidebar_outlined,
            tooltip: l10n.toggleInspector,
            active: layout.inspectorVisible,
            onPressed: layout.toggleInspector,
          ),
        ],
      ),
    );
  }
}

/// The centered status capsule: what dataset is open, how far along it is,
/// and where the selection sits inside it. Clicking it opens a folder.
class _ActivityCapsule extends StatelessWidget {
  const _ActivityCapsule({required this.onOpenFolder});

  final VoidCallback onOpenFolder;

  /// `parent / leaf` — enough context to tell two `dataset` folders apart
  /// without spending the capsule's width on a full path.
  String _shortLocation(String directory) {
    final leaf = p.basename(directory);
    final parent = p.basename(p.dirname(directory));
    return parent.isEmpty || parent == leaf ? leaf : '$parent / $leaf';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final semantic = context.semantic;
    final scheme = Theme.of(context).colorScheme;
    final dataset = context.watch<DatasetState>();
    final directory = context.select<AppState, String?>(
      (s) => s.browsingDirectory,
    );
    final autoSave = context.select<AppState, bool>((s) => s.autoSave);

    final ai = context.watch<AiTaggerState>();
    final open = directory != null;
    final total = dataset.totalCount;
    // The dot reports the dataset's tagging state, matching the ok/warn
    // semantics used everywhere else for captioned/uncaptioned.
    final dotColor = !open || total == 0
        ? semantic.muted
        : dataset.untaggedCount > 0
        ? semantic.warn
        : semantic.ok;

    final visibleCount = dataset.visibleFiles.length;
    final index = dataset.selectedVisibleIndex;

    // Compare mode takes the capsule over: it is a mode the whole workbench
    // is in, and the one place to leave it belongs where the mode is named.
    if (ai.compareMode) {
      return _CompareCapsule(
        resultCount: ai.resultCount,
        onExit: ai.exitCompareMode,
      );
    }

    return Tooltip(
      message: l10n.openFolder,
      waitDuration: const Duration(milliseconds: 600),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onOpenFolder,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
            decoration: BoxDecoration(
              color: scheme.surface,
              border: Border.all(color: semantic.line),
              borderRadius: BorderRadius.circular(AppRadii.control),
            ),
            child: Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: dotColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 9),
                // One flex slot for the label group: a Spacer alongside the
                // Flexible texts would take a share of the free width even
                // when it has nothing to push, squeezing the dataset name.
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          open ? _shortLocation(directory) : l10n.noDatasetOpen,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: AppText.secondary,
                            color: open ? scheme.onSurface : semantic.muted,
                          ),
                        ),
                      ),
                      if (open && total > 0) ...[
                        const SizedBox(width: 12),
                        Flexible(
                          child: Text(
                            '${l10n.taggedProgress(dataset.taggedCount, total)}'
                            '  ·  '
                            '${autoSave ? l10n.autoSaveOnStatus : l10n.autoSaveOffStatus}',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: AppText.secondary,
                              color: semantic.muted,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (index >= 0) ...[
                  const SizedBox(width: 12),
                  Text(
                    '${index + 1} / $visibleCount',
                    style: monoStyle(
                      context,
                      size: AppText.secondary,
                      color: semantic.muted,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The capsule while AI compare mode is on: accent outline, what the mode is
/// for, and the global way out.
class _CompareCapsule extends StatelessWidget {
  const _CompareCapsule({required this.resultCount, required this.onExit});

  final int resultCount;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final semantic = context.semantic;
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border.all(color: scheme.primary.withAlpha(128)),
        borderRadius: BorderRadius.circular(AppRadii.control),
      ),
      child: Row(
        children: [
          Icon(Icons.compare_arrows, size: 15, color: scheme.primary),
          const SizedBox(width: 9),
          Flexible(
            child: Text(
              l10n.compareModeCapsule(resultCount),
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: AppText.secondary,
                color: scheme.onSurface,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              l10n.compareModeHint,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: AppText.secondary,
                color: semantic.muted,
              ),
            ),
          ),
          const SizedBox(width: 12),
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onExit,
              child: Text(
                l10n.compareModeExitGlobal,
                style: TextStyle(
                  fontSize: AppText.secondary,
                  fontWeight: FontWeight.w600,
                  color: scheme.primary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Title-bar action: muted at rest, accented while its surface is showing.
class _BarIconButton extends StatelessWidget {
  const _BarIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.active = false,
    this.color,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool active;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IconButton(
      icon: Icon(icon, size: 18),
      tooltip: tooltip,
      color: color ?? (active ? scheme.onSurface : context.semantic.muted),
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      padding: EdgeInsets.zero,
      onPressed: onPressed,
    );
  }
}
