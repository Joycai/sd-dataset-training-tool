import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dataset_training_tool/app_state.dart';
import 'package:dataset_training_tool/l10n/app_localizations.dart';
import 'package:dataset_training_tool/services/settings_service.dart';
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

void main() {
  late Directory tempDir;
  late AppState appState;
  late DatasetState dataset;
  late AiTaggerState ai;

  // All file IO stays in setUp: testWidgets bodies run under a fake clock
  // where real async IO never completes.
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('subdir_picker_');
    for (final rel in [
      'root.png',
      '10_a/a1.png',
      '10_a/a2.png',
      '20_b/b.png',
    ]) {
      final file = File(p.join(tempDir.path, p.joinAll(p.posix.split(rel))));
      await file.parent.create(recursive: true);
      await file.writeAsBytes(_pngBytes);
    }
    appState = AppState(SettingsService());
    await appState.loadSettings();
    ai = AiTaggerState(SettingsService());
    dataset = DatasetState();
    await dataset.scan(
      directoryPath: tempDir.path,
      recursive: true,
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

  testWidgets('picking a folder narrows the navigator', (tester) async {
    await tester.pumpWidget(harness());
    await tester.pump();

    expect(find.byType(DropdownButton<String?>), findsOneWidget);
    // Unscoped: the caption-status segment counts all four images.
    expect(find.text('All 4'), findsOneWidget);

    await tester.tap(find.byType(DropdownButton<String?>));
    await tester.pumpAndSettle();
    // The button shows the current value, so the menu entry is the second
    // "10_a" in the tree.
    await tester.tap(find.text('10_a').last);
    await tester.pumpAndSettle();

    expect(dataset.activeSubdirectory, '10_a');
    expect(find.text('All 2'), findsOneWidget);
    expect(find.text('a1.png'), findsOneWidget);
    expect(find.text('root.png'), findsNothing);
  });

  testWidgets('a single-folder dataset shows no picker', (tester) async {
    // runAsync: a rescan is real file IO, which never completes under the
    // fake clock a testWidgets body runs on.
    await tester.runAsync(
      () => dataset.scan(
        directoryPath: p.join(tempDir.path, '10_a'),
        recursive: true,
        captionExtension: '.txt',
      ),
    );
    await tester.pumpWidget(harness());
    await tester.pump();

    expect(dataset.totalCount, 2);
    expect(find.byType(DropdownButton<String?>), findsNothing);
  });
}
