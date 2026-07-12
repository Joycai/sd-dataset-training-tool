import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dataset_training_tool/app_state.dart';
import 'package:dataset_training_tool/main.dart';
import 'package:dataset_training_tool/services/settings_service.dart';

Future<AppState> _createAppState({Map<String, Object> prefs = const {}}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final appState = AppState(SettingsService());
  await appState.loadSettings();
  return appState;
}

Widget _wrapApp(AppState appState) {
  return ChangeNotifierProvider.value(
    value: appState,
    child: const MyApp(),
  );
}

void main() {
  testWidgets('App builds and shows the editor view by default',
      (WidgetTester tester) async {
    final appState = await _createAppState();

    await tester.pumpWidget(_wrapApp(appState));
    await tester.pumpAndSettle();

    // Editor view: image browser (left) prompts to open a directory,
    // workspace (right) prompts to select an image.
    expect(find.text('Open'), findsOneWidget);
    expect(find.text('Select an image to start editing.'), findsOneWidget);
    expect(find.byIcon(Icons.settings), findsOneWidget);
  });

  testWidgets('Settings button switches to the settings view',
      (WidgetTester tester) async {
    final appState = await _createAppState();

    await tester.pumpWidget(_wrapApp(appState));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.settings));
    await tester.pumpAndSettle();

    expect(appState.currentView, MainView.settings);
    // Language dropdown is only present on the settings page.
    expect(find.byType(DropdownButton<Locale>), findsOneWidget);
  });

  test('Settings load defaults from empty preferences', () async {
    final appState = await _createAppState();

    expect(appState.captionExtension, '.txt');
    expect(appState.crossAxisCount, 4);
    expect(appState.includeSubdirectories, false);
    expect(appState.browsingDirectory, isNull);
    expect(appState.commonTags, isEmpty);
    expect(appState.currentLocale, const Locale('en'));
    expect(appState.currentThemeMode, ThemeMode.system);
  });

  test('Common tags add/remove persist and de-duplicate', () async {
    final appState = await _createAppState();

    await appState.addCommonTags(['1girl', 'solo', '1girl']);
    expect(appState.commonTags, ['1girl', 'solo']);

    await appState.addCommonTags(['solo', 'highres']);
    expect(appState.commonTags, ['1girl', 'solo', 'highres']);

    await appState.removeCommonTags(['solo']);
    expect(appState.commonTags, ['1girl', 'highres']);
  });
}
