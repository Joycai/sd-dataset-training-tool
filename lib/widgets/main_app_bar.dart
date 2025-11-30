import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import '../l10n/app_localizations.dart';

class MainAppBar extends StatelessWidget implements PreferredSizeWidget {
  const MainAppBar({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final appState = context.watch<AppState>();
    final currentView = appState.currentView;
    final currentMode = appState.currentThemeMode;

    IconData getThemeIcon() {
      switch (currentMode) {
        case ThemeMode.light:
          return Icons.light_mode;
        case ThemeMode.dark:
          return Icons.dark_mode;
        case ThemeMode.system:
          return Icons.settings_brightness;
      }
    }

    void cycleTheme() {
      final appState = context.read<AppState>();
      final nextMode = {
        ThemeMode.light: ThemeMode.dark,
        ThemeMode.dark: ThemeMode.system,
        ThemeMode.system: ThemeMode.light,
      }[currentMode];
      appState.updateThemeMode(nextMode!);
    }

    void toggleLanguage() {
      final appState = context.read<AppState>();
      final nextLocale =
          appState.currentLocale.languageCode == 'en'
              ? const Locale('zh')
              : const Locale('en');
      appState.updateLocale(nextLocale);
    }

    return AppBar(
      backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      title: Row(
        children: [
          Text(l10n.appTitle),
          const SizedBox(width: 24),
          TextButton.icon(
            icon: const Icon(Icons.edit_document),
            label: Text(l10n.editor),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
            ).copyWith(
              // FIX: Use WidgetStateProperty and withAlpha
              backgroundColor: WidgetStateProperty.resolveWith<Color?>(
                (Set<WidgetState> states) {
                  if (currentView == MainView.editor) {
                    // FIX: Use withAlpha instead of withOpacity
                    return Theme.of(context).colorScheme.primary.withAlpha(51); // 0.2 opacity
                  }
                  return null;
                },
              ),
            ),
            onPressed: () {
              context.read<AppState>().updateView(MainView.editor);
            },
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.settings),
          tooltip: l10n.settings,
          isSelected: currentView == MainView.settings,
          onPressed: () {
            context.read<AppState>().updateView(MainView.settings);
          },
        ),
        IconButton(
          icon: Icon(getThemeIcon()),
          tooltip: l10n.toggleTheme,
          onPressed: cycleTheme,
        ),
      ],
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}
