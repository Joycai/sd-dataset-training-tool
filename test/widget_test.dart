import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dataset_training_tool/app_state.dart';
import 'package:dataset_training_tool/main.dart';
import 'package:dataset_training_tool/services/settings_service.dart';
import 'package:dataset_training_tool/state/dataset_state.dart';
import 'package:dataset_training_tool/views/panels/assets_panel.dart';
import 'package:dataset_training_tool/views/panels/tag_library_panel.dart';
import 'package:dataset_training_tool/widgets/resize_handle.dart';

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
  testWidgets('App builds and shows the workbench by default',
      (WidgetTester tester) async {
    final appState = await _createAppState();

    await tester.pumpWidget(_wrapApp(appState));
    await tester.pumpAndSettle();

    // Assets panel empty state prompts to open a folder; the preview and
    // caption editor both hint at selecting an image.
    expect(find.text('Open Folder'), findsOneWidget);
    expect(find.text('Select an image from the assets panel.'), findsWidgets);
    expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
  });

  testWidgets('Settings button switches to the settings view',
      (WidgetTester tester) async {
    final appState = await _createAppState();

    await tester.pumpWidget(_wrapApp(appState));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();

    expect(appState.currentView, MainView.settings);
    // Language dropdown is only present on the settings page.
    expect(find.byType(DropdownButton<Locale>), findsOneWidget);

    // Back arrow returns to the workbench.
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(appState.currentView, MainView.editor);
  });

  test('Settings load defaults from empty preferences', () async {
    final appState = await _createAppState();

    expect(appState.captionExtension, '.txt');
    expect(appState.crossAxisCount, 4);
    expect(appState.includeSubdirectories, false);
    expect(appState.browsingDirectory, isNull);
    expect(appState.commonTags, isEmpty);
    expect(appState.autoSave, isTrue);
    expect(appState.leftPanelWidth, SettingsService.defaultLeftPanelWidth);
    expect(appState.rightPanelWidth, SettingsService.defaultRightPanelWidth);
    expect(appState.currentLocale, const Locale('en'));
    expect(appState.currentThemeMode, ThemeMode.system);
  });

  testWidgets('Panel resize handles adjust widths and persist them',
      (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final appState = await _createAppState();
    await tester.pumpWidget(_wrapApp(appState));
    await tester.pumpAndSettle();

    expect(tester.getSize(find.byType(AssetsPanel)).width,
        SettingsService.defaultLeftPanelWidth);

    // Drag the left handle 60px to the right: the assets panel grows by
    // exactly the pointer travel (anchor-based drag, no slop dead zone).
    await tester.drag(find.byType(ResizeHandle).first, const Offset(60, 0));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(AssetsPanel)).width,
        SettingsService.defaultLeftPanelWidth + 60);
    expect(
        appState.leftPanelWidth, SettingsService.defaultLeftPanelWidth + 60);

    // Drag the right handle 80px to the right: the library shrinks.
    await tester.drag(find.byType(ResizeHandle).last, const Offset(80, 0));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(TagLibraryPanel)).width,
        SettingsService.defaultRightPanelWidth - 80);
    expect(appState.rightPanelWidth,
        SettingsService.defaultRightPanelWidth - 80);

    // Widths never shrink below the panel minimum.
    await tester.drag(find.byType(ResizeHandle).last, const Offset(500, 0));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(TagLibraryPanel)).width, 200);
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

  testWidgets('Workbench shortcuts yield to focused text fields',
      (WidgetTester tester) async {
    final appState = await _createAppState();
    await tester.pumpWidget(_wrapApp(appState));
    await tester.pumpAndSettle();

    // With no dataset open, navigation / AI / undo shortcuts are no-ops
    // rather than crashes.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    // Focus the assets-panel search field and type; the caret ends at 3.
    final field = find.byType(TextField).first;
    await tester.enterText(field, 'abc');
    await tester.pump();
    final editable = tester.widget<EditableText>(
      find.descendant(of: field, matching: find.byType(EditableText)),
    );
    expect(editable.controller.selection.baseOffset, 3);

    // ArrowLeft must reach the text field (caret moves) instead of being
    // swallowed by the workbench image-navigation shortcut.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(editable.controller.selection.baseOffset, 2);
  });

  test('Dataset filters and selection navigate the visible list', () {
    final dataset = DatasetState();
    expect(dataset.visibleFiles, isEmpty);
    expect(dataset.selectByOffset(1), isNull);
    expect(dataset.selectedVisibleIndex, -1);

    dataset.setQuery('foo');
    expect(dataset.query, 'foo');
    dataset.setFilter(CaptionFilter.untagged);
    expect(dataset.filter, CaptionFilter.untagged);
  });
}
