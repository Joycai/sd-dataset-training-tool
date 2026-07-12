import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../l10n/app_localizations.dart';
import '../state/dataset_state.dart';
import '../theme/app_theme.dart';

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
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [scheme.primary, const Color(0xFF7E6FD9)],
              ),
            ),
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
          Flexible(
            child: InkWell(
              onTap: onOpenFolder,
              borderRadius: BorderRadius.circular(7),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: scheme.surface,
                  border: Border.all(color: semantic.line),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.folder_outlined,
                        size: 14, color: semantic.muted),
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
                        style: monoStyle(context,
                            size: 11.5, color: semantic.muted),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          const Spacer(),
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
