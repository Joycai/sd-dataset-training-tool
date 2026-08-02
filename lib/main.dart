import 'dart:async';
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
import 'views/workbench_view.dart';
import 'widgets/tag_gloss.dart';

bool get _isDesktop =>
    !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  final settingsService = SettingsService();
  final appState = AppState(settingsService);
  await appState.loadSettings();

  if (_isDesktop) {
    // 在 runApp 之前注册上次选择的字体，避免首帧闪一下系统字体。
    // 字体加载失败（如目录被清掉）不应阻止启动。
    try {
      await appState.fontService.init();
      await appState.fontService.loadIfDownloaded(appState.fontChoice);
    } catch (_) {}
  }

  if (_isDesktop) {
    final windowController = await WindowController.fromCurrentEngine();
    // Sub-windows are created with a JSON payload as arguments; the main
    // window has none.
    if (windowController.arguments.isNotEmpty) {
      final arguments =
          jsonDecode(windowController.arguments) as Map<String, dynamic>;
      runApp(
        _withoutSemantics(
          ChangeNotifierProvider.value(
            value: appState,
            child: ImagePreviewWindow(
              windowController: windowController,
              args: arguments,
            ),
          ),
        ),
      );
      return;
    }
  }

  // Not awaited: parsing the tag dictionary spawns an isolate, and the
  // caption editor is perfectly usable in the fraction of a second before
  // autocomplete comes online — the field listens and picks it up.
  unawaited(appState.tagDictionary.init());
  // Same bargain for the glossary: tags render untranslated for a moment and
  // the gloss scope repaints them once it lands.
  unawaited(appState.tagTranslations.load(appState.currentLocale.languageCode));
  // And for the danbooru records, which only the dictionary manager renders.
  unawaited(appState.danbooruMeta.init());

  runApp(
    _withoutSemantics(
      ChangeNotifierProvider.value(value: appState, child: const MyApp()),
    ),
  );
}

/// Opts the whole app out of the platform accessibility tree.
///
/// Semantics stays off until some accessibility client attaches — which on a
/// stock Windows desktop can happen with nothing installed and nobody asking.
/// As soon as it does, Flutter's Windows accessibility bridge mis-orders this
/// app's first semantics update and gives up on its AXTree:
///
///     Failed to update ui::AXTree, error: 0 will not be in the tree and is
///     not the new root
///
/// Every later update then fails too, and the next window resize — maximizing
/// by double-clicking the title bar is the easy way to hit it — dereferences a
/// node the bridge never created and takes the process down with an access
/// violation, losing whatever caption was being edited. That is
/// flutter/flutter#182444, still open upstream; it is a bug in the bridge's
/// diffing, not in any one widget here — bisecting showed that excluding *any*
/// single panel from semantics is enough to reshuffle the update and hide it,
/// so there is nothing local to fix.
///
/// With no semantics nodes below the root the bridge has nothing to diff, so
/// the crash cannot happen. The cost is screen-reader support, which this app
/// has never actually provided. Remove this once the upstream fix lands.
Widget _withoutSemantics(Widget child) => ExcludeSemantics(child: child);

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();

    // Above MaterialApp, so dialog routes — the dictionary manager included —
    // inherit the glossary along with the workbench. The ListenableBuilder is
    // what turns the service's own notifications into a scope update; only the
    // widgets that actually asked for a gloss rebuild from there.
    return ListenableBuilder(
      listenable: appState.tagTranslations,
      builder: (context, _) => TagGlossScope(
        glosses: appState.tagTranslations,
        display: appState.tagGlossDisplay,
        child: MaterialApp(
          onGenerateTitle: (context) => AppLocalizations.of(context)!.appTitle,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: appState.currentLocale,
          theme: buildAppTheme(
            Brightness.light,
            fontFamily: appState.uiFontFamily,
            accent: appState.accentChoice,
          ),
          darkTheme: buildAppTheme(
            Brightness.dark,
            fontFamily: appState.uiFontFamily,
            accent: appState.accentChoice,
          ),
          themeMode: appState.currentThemeMode,
          home: const MyHomePage(),
        ),
      ),
    );
  }
}

class MyHomePage extends StatelessWidget {
  const MyHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    // Settings are a modal now, so the workbench is the only top-level view
    // and there is nothing left to switch between.
    return const Scaffold(body: WorkbenchView());
  }
}
