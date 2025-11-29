import 'dart:convert';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'app_state.dart';
import 'l10n/app_localizations.dart';
import 'services/settings_service.dart';
import 'views/editor_view.dart';
import 'views/image_preview_window.dart';
import 'views/settings_view.dart';
import 'widgets/main_app_bar.dart';

void main(List<String> args) async {
  if (args.firstOrNull == 'multi_window') {
    final windowId = int.parse(args[1]);
    // FIX: Explicitly type the empty map to avoid type mismatch.
    final arguments = args[2].isEmpty
        ? const <String, dynamic>{}
        : jsonDecode(args[2]) as Map<String, dynamic>;

    final settingsService = SettingsService();
    final appState = AppState(settingsService);
    await appState.loadSettings();
    
    runApp(
      ChangeNotifierProvider.value(
        value: appState,
        child: ImagePreviewWindow(
          windowController: WindowController.fromWindowId(windowId),
          args: arguments,
        ),
      ),
    );

  } else {
    // This is the main window
    WidgetsFlutterBinding.ensureInitialized();

    final settingsService = SettingsService();
    final appState = AppState(settingsService);

    await appState.loadSettings();

    runApp(
      ChangeNotifierProvider.value(
        value: appState,
        child: const MyApp(),
      ),
    );
  }
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
