import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dataset_training_tool/app_state.dart';
import 'package:dataset_training_tool/l10n/app_localizations.dart';
import 'package:dataset_training_tool/services/settings_service.dart';
import 'package:dataset_training_tool/state/dataset_state.dart';
import 'package:dataset_training_tool/theme/app_theme.dart';
import 'package:dataset_training_tool/views/panels/assets_panel.dart';

// 1x1 transparent PNG.
const _pngBytes = [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x62, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
];

void main() {
  late Directory tempDir;
  late AppState appState;
  late DatasetState dataset;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('assets_panel_');
    for (final name in ['001', '002']) {
      await File(p.join(tempDir.path, '$name.png')).writeAsBytes(_pngBytes);
    }
    appState = AppState(SettingsService());
    await appState.loadSettings();
    dataset = DatasetState();
    await dataset.scan(
      directoryPath: tempDir.path,
      recursive: false,
      captionExtension: '.txt',
    );
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  Widget harness() {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: appState),
        ChangeNotifierProvider.value(value: dataset),
      ],
      child: MaterialApp(
        theme: buildAppTheme(Brightness.dark),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: 300,
              child: AssetsPanel(
                onOpenFolder: () {},
                onRefresh: () {},
                onOpenExternalPreview: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<BoxFit?> gridImageFits(WidgetTester tester) => [
        for (final image in tester.widgetList<Image>(
          find.descendant(
            of: find.byType(GridView),
            matching: find.byType(Image),
          ),
        ))
          image.fit,
      ];

  testWidgets('thumbnail fill/fit toggle switches BoxFit and persists', (
    tester,
  ) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    // Default: fill (cover), and the header button offers switching to fit.
    expect(gridImageFits(tester), everyElement(BoxFit.cover));
    expect(find.byIcon(Icons.fit_screen_outlined), findsOneWidget);

    await tester.tap(find.byIcon(Icons.fit_screen_outlined));
    await tester.pumpAndSettle();
    expect(appState.thumbnailFill, isFalse);
    expect(gridImageFits(tester), everyElement(BoxFit.contain));
    // The button now offers switching back to fill.
    expect(find.byIcon(Icons.zoom_out_map), findsOneWidget);

    await tester.tap(find.byIcon(Icons.zoom_out_map));
    await tester.pumpAndSettle();
    expect(appState.thumbnailFill, isTrue);
    expect(gridImageFits(tester), everyElement(BoxFit.cover));
  });

  test('thumbnailFill persists across reload', () async {
    await appState.updateThumbnailFill(false);

    final reloaded = AppState(SettingsService());
    await reloaded.loadSettings();
    expect(reloaded.thumbnailFill, isFalse);
  });
}
