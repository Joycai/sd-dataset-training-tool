import 'dart:convert';
import 'dart:io';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'app_state.dart';
import 'l10n/app_localizations.dart';
import 'services/settings_service.dart';
import 'theme/app_theme.dart';
import 'views/image_preview_window.dart';
import 'views/settings_view.dart';
import 'views/workbench_view.dart';

bool get _isDesktop =>
    !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  final settingsService = SettingsService();
  final appState = AppState(settingsService);
  await appState.loadSettings();

  if (_isDesktop) {
    final windowController = await WindowController.fromCurrentEngine();
    // Sub-windows are created with a JSON payload as arguments; the main
    // window has none.
    if (windowController.arguments.isNotEmpty) {
      final arguments =
          jsonDecode(windowController.arguments) as Map<String, dynamic>;
      runApp(
        ChangeNotifierProvider.value(
          value: appState,
          child: ImagePreviewWindow(
            windowController: windowController,
            args: arguments,
          ),
        ),
      );
      return;
    }
  }

  runApp(
    ChangeNotifierProvider.value(
      value: appState,
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();

    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context)!.appTitle,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: appState.currentLocale,
      theme: buildAppTheme(Brightness.light),
      darkTheme: buildAppTheme(Brightness.dark),
      themeMode: appState.currentThemeMode,
      home: const MyHomePage(),
    );
  }
}

class MyHomePage extends StatelessWidget {
  const MyHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();

    return Scaffold(
      body: IndexedStack(
        index: appState.currentView.index,
        children: const [
          WorkbenchView(),
          SettingsView(),
        ],
      ),
    );
  }
}
