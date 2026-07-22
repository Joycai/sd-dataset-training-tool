import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dataset_training_tool/app_state.dart';
import 'package:dataset_training_tool/l10n/app_localizations.dart';
import 'package:dataset_training_tool/services/settings_service.dart';
import 'package:dataset_training_tool/state/dataset_state.dart';
import 'package:dataset_training_tool/state/editor_session.dart';
import 'package:dataset_training_tool/state/tag_ops.dart';
import 'package:dataset_training_tool/theme/app_theme.dart';
import 'package:dataset_training_tool/views/panels/tag_library_panel.dart';

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
  late DatasetState dataset;
  late EditorSession session;
  late TagOps ops;
  late AppState appState;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('dataset_tags_view_');
    for (final name in ['001', '002']) {
      await File(p.join(tempDir.path, '$name.png')).writeAsBytes(_pngBytes);
    }
    await File(p.join(tempDir.path, '001.txt')).writeAsString('alpha, beta');
    await File(p.join(tempDir.path, '002.txt')).writeAsString('beta');

    dataset = DatasetState();
    await dataset.scan(
      directoryPath: tempDir.path,
      recursive: false,
      captionExtension: '.txt',
    );
    session = EditorSession()..autoSaveEnabled = false;
    ops = TagOps(dataset: dataset);
    appState = AppState(SettingsService());
    await appState.loadSettings();
  });

  tearDown(() async {
    session.dispose();
    await tempDir.delete(recursive: true);
  });

  Widget harness() {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: appState),
        ChangeNotifierProvider.value(value: dataset),
        ChangeNotifierProvider.value(value: session),
        ChangeNotifierProvider.value(value: ops),
      ],
      child: MaterialApp(
        theme: buildAppTheme(Brightness.dark),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(width: 340, child: TagLibraryPanel()),
          ),
        ),
      ),
    );
  }

  Future<void> openDatasetTab(WidgetTester tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dataset'));
    await tester.pumpAndSettle();
  }

  Future<void> rightClick(WidgetTester tester, Finder finder) async {
    await tester.tap(finder, buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
  }

  testWidgets('dataset tab lists tags with counts', (tester) async {
    await openDatasetTab(tester);

    expect(find.text('alpha'), findsOneWidget);
    expect(find.text('beta'), findsOneWidget);
    // beta appears in both captions, alpha in one.
    expect(find.text('2'), findsWidgets);
    expect(find.text('1'), findsWidgets);
  });

  testWidgets('context menu sets and clears the gallery tag filter', (
    tester,
  ) async {
    await openDatasetTab(tester);

    await rightClick(tester, find.text('beta'));
    expect(find.text('Only images with this tag'), findsOneWidget);
    await tester.tap(find.text('Only images with this tag'));
    await tester.pumpAndSettle();

    expect(dataset.tagFilter, 'beta');
    expect(dataset.tagFilterExclude, isFalse);
    expect(find.text('Only with: beta'), findsOneWidget);

    // Exclude flips the filter; only 001 has alpha.
    await rightClick(tester, find.text('alpha'));
    await tester.tap(find.text('Only images without this tag'));
    await tester.pumpAndSettle();
    expect(dataset.tagFilter, 'alpha');
    expect(dataset.tagFilterExclude, isTrue);
    expect(dataset.visibleFiles.map((f) => p.basename(f.path)), ['002.png']);

    // The header button clears the filter.
    await tester.tap(find.byIcon(Icons.filter_alt_off_outlined));
    await tester.pumpAndSettle();
    expect(dataset.tagFilter, isNull);
    expect(dataset.visibleFiles, hasLength(2));
  });

  // The disk effects of delete/replace/undo are covered by tag_ops_test.dart;
  // the widget tests stay UI-only because TagOps does real file IO, which can
  // never complete inside the widget test's fake-async zone.
  testWidgets('global delete shows a confirmation with the image count', (
    tester,
  ) async {
    await openDatasetTab(tester);

    await rightClick(tester, find.text('beta'));
    await tester.tap(find.text('Delete from all images'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Remove "beta" from 2 images'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    // Cancel touches nothing.
    expect(ops.canUndo, isFalse);
    expect(
      dataset.datasetTags.map((t) => '${t.tag}:${t.count}'),
      contains('beta:2'),
    );
  });

  testWidgets('replace dialog prefills the tag and validates input', (
    tester,
  ) async {
    await openDatasetTab(tester);

    await rightClick(tester, find.text('beta'));
    await tester.tap(find.text('Replace / append…'));
    await tester.pumpAndSettle();

    // Prefilled with the tag in replace mode.
    final field = find.byType(TextField).last;
    expect(tester.widget<TextField>(field).controller?.text, 'beta');

    // Emptying the input disables Apply.
    await tester.enterText(field, '');
    await tester.pumpAndSettle();
    final applyButton = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Apply'),
    );
    expect(applyButton.onPressed, isNull);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(ops.canUndo, isFalse);
  });
}
