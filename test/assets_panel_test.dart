import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dataset_training_tool/app_state.dart';
import 'package:dataset_training_tool/l10n/app_localizations.dart';
import 'package:dataset_training_tool/services/settings_service.dart';
import 'package:dataset_training_tool/models/ai_tagger_models.dart';
import 'package:dataset_training_tool/state/ai_tagger_state.dart';
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

/// Long enough to force the row's filename to ellipsize at panel widths.
const _longName = 'a_very_long_generated_frame_name_0001';

void main() {
  late Directory tempDir;
  late AppState appState;
  late DatasetState dataset;
  late AiTaggerState ai;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('assets_panel_');
    // File IO has to happen here: testWidgets bodies run under a fake clock
    // where real async IO never completes.
    for (final name in ['001', '002', _longName]) {
      await File(p.join(tempDir.path, '$name.png')).writeAsBytes(_pngBytes);
    }
    await File(
      p.join(tempDir.path, '$_longName.txt'),
    ).writeAsString('1girl, solo, magical girl, purple hair, twintails');
    appState = AppState(SettingsService());
    await appState.loadSettings();
    ai = AiTaggerState(SettingsService());
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

  Widget harness({double width = 300}) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: appState),
        ChangeNotifierProvider.value(value: dataset),
        ChangeNotifierProvider.value(value: ai),
      ],
      child: MaterialApp(
        theme: buildAppTheme(Brightness.dark),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: width,
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
      find.descendant(of: find.byType(GridView), matching: find.byType(Image)),
    ))
      image.fit,
  ];

  testWidgets('one column renders rows, more than one renders the grid', (
    tester,
  ) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    // Default is the row list: filenames and per-file tag counts are on
    // screen, and there is no grid.
    expect(appState.crossAxisCount, 1);
    expect(find.byType(GridView), findsNothing);
    expect(find.text('001.png'), findsOneWidget);
    expect(find.text('002.png'), findsOneWidget);

    await appState.updateCrossAxisCount(3);
    await tester.pumpAndSettle();

    expect(find.byType(GridView), findsOneWidget);
    // The grid shows thumbnails only — no filename labels.
    expect(find.text('001.png'), findsNothing);
  });

  testWidgets('rows survive the navigator minimum width with long names', (
    tester,
  ) async {
    // A long filename plus a tag count plus the status dot is the row's
    // worst case; a RenderFlex overflow here fails the test.
    await tester.pumpWidget(harness(width: 200));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // The tag count renders for the captioned file only.
    expect(find.text('5 tags'), findsOneWidget);
  });

  testWidgets('thumbnail fill/fit toggle switches BoxFit and persists', (
    tester,
  ) async {
    // The toggle is observable through the grid's images, so this case runs
    // in grid mode; the row list applies the same BoxFit.
    await appState.updateCrossAxisCount(3);
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    expect(gridImageFits(tester), isNotEmpty);

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

  testWidgets('compare mode swaps the tag count for review progress', (
    tester,
  ) async {
    // The captioned file already has "1girl" and "solo"; the model also
    // proposes "jewelry", which nothing has accepted yet.
    ai.storeResult(
      p.join(tempDir.path, '$_longName.png'),
      const AiInterrogateResponse(
        success: true,
        results: [
          AiModelResult(
            modelName: 'test',
            tags: [
              AiTag(tag: '1girl', probability: 0.99),
              AiTag(tag: 'solo', probability: 0.98),
              AiTag(tag: 'jewelry', probability: 0.95),
            ],
          ),
        ],
      ),
    );
    ai.enterCompareMode();

    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    expect(find.text('1 to review'), findsOneWidget);
    // Images without a result keep their ordinary tag count.
    expect(find.text('5 tags'), findsNothing);

    // Accepting the last suggestion flips the badge.
    ai.storeResult(
      p.join(tempDir.path, '$_longName.png'),
      const AiInterrogateResponse(
        success: true,
        results: [
          AiModelResult(
            modelName: 'test',
            tags: [AiTag(tag: '1girl', probability: 0.99)],
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Reviewed'), findsOneWidget);
  });

  testWidgets('an empty gallery filter offers its own way out', (tester) async {
    // No image carries this tag, so the navigator ends up empty — and the
    // filter was set from a different panel entirely.
    dataset.setTagFilter('nothing-matches-this', exclude: false);

    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    expect(find.text('No images match the current filter.'), findsOneWidget);
    await tester.tap(find.text('Clear tag filter'));
    await tester.pumpAndSettle();

    expect(dataset.tagFilterActive, isFalse);
    expect(find.text('001.png'), findsOneWidget);
  });

  test('thumbnailFill persists across reload', () async {
    await appState.updateThumbnailFill(false);

    final reloaded = AppState(SettingsService());
    await reloaded.loadSettings();
    expect(reloaded.thumbnailFill, isFalse);
  });
}
