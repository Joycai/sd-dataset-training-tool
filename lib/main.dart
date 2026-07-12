import 'dart:convert';
import 'dart:io';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'app_state.dart';
import 'l10n/app_localizations.dart';
import 'services/settings_service.dart';
import 'views/editor_view.dart';
import 'views/image_preview_window.dart';
import 'views/settings_view.dart';
import 'widgets/main_app_bar.dart';

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
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.deepPurple, brightness: Brightness.dark),
        brightness: Brightness.dark,
      ),
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

    const Widget editorView = EditorView();
    const Widget settingsView = SettingsView();

    return Scaffold(
      appBar: const MainAppBar(),
      body: IndexedStack(
        index: appState.currentView.index,
        children: [
          editorView,
          settingsView,
        ],
      ),
    );
  }
}
