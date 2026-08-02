import 'dart:io';

import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dataset_training_tool/app_state.dart';
import 'package:dataset_training_tool/l10n/app_localizations.dart';
import 'package:dataset_training_tool/models/ai_tagger_models.dart';
import 'package:dataset_training_tool/services/settings_service.dart';
import 'package:dataset_training_tool/state/ai_tagger_state.dart';
import 'package:dataset_training_tool/state/editor_session.dart';
import 'package:dataset_training_tool/theme/app_theme.dart';
import 'package:dataset_training_tool/views/panels/ai_compare_view.dart';

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
  late File image;
  late EditorSession session;
  late AiTaggerState ai;
  late AppState appState;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    appState = AppState(SettingsService());
    await appState.loadSettings();
    tempDir = await Directory.systemTemp.createTemp('compare_view_');
    image = File(p.join(tempDir.path, 'shot.png'));
    await image.writeAsBytes(_pngBytes);
    // "solo" is on the image but not predicted; "jewelry" is predicted but
    // not on the image; "1girl" is on both — one chip of each state.
    await File(p.join(tempDir.path, 'shot.txt')).writeAsString('1girl, solo');
    session = EditorSession();
    // Autosave would leave a debounce timer pending past teardown, and the
    // temp dir is gone by the time it fires.
    session.autoSaveEnabled = false;
    await session.load(image, '.txt');

    ai = AiTaggerState(SettingsService());
    ai.storeResult(
      image.path,
      const AiInterrogateResponse(
        success: true,
        results: [
          AiModelResult(
            modelName: 'test',
            tags: [
              AiTag(tag: '1girl', probability: 0.99),
              AiTag(tag: 'jewelry', probability: 0.95),
            ],
          ),
        ],
      ),
    );
    ai.enterCompareMode();
  });

  tearDown(() async {
    session.dispose();
    ai.dispose();
    await tempDir.delete(recursive: true);
  });

  Widget harness({double width = 620, bool includeAppState = true}) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: session),
        ChangeNotifierProvider.value(value: ai),
        // Optional: the context menu's library actions degrade gracefully
        // without one, which one test below exercises directly.
        if (includeAppState) ChangeNotifierProvider.value(value: appState),
      ],
      child: MaterialApp(
        theme: buildAppTheme(Brightness.dark),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              height: 240,
              child: AiCompareView(onRunAi: () async {}),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('both columns render the three diff states', (tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    // Left column: the matched tag and the one the model did not see.
    expect(find.text('1girl'), findsWidgets);
    expect(find.text('solo'), findsOneWidget);
    // Right column: the unaccepted suggestion, with its confidence.
    expect(find.text('jewelry'), findsOneWidget);
    expect(find.text('0.95'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a narrow editor column does not overflow', (tester) async {
    // The center column can get this tight when both side panels are wide.
    await tester.pumpWidget(harness(width: 320));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('clicking a suggestion moves it onto the image', (tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    await tester.tap(find.text('jewelry'));
    await tester.pumpAndSettle();

    expect(session.tags, contains('jewelry'));
    // It is now matched on both sides, so it is no longer a suggestion.
    expect(ai.pendingFor(image.path, session.tags), isEmpty);
  });

  testWidgets(
    'left column: right-click on a matched tag offers remove/anchor, not '
    'apply-suggestion',
    (tester) async {
      await tester.pumpWidget(harness());
      await tester.pumpAndSettle();

      // '1girl' is matched (on both sides); the left column renders first.
      await tester.tap(find.text('1girl').first, buttons: kSecondaryButton);
      await tester.pumpAndSettle();

      expect(find.text('Remove from this image'), findsOneWidget);
      expect(find.text('Set as insertion anchor'), findsOneWidget);
      expect(find.text('Add to library'), findsOneWidget);
      expect(find.text('Apply suggestion'), findsNothing);

      await tester.tap(find.text('Remove from this image'));
      await tester.pumpAndSettle();
      expect(session.tags, isNot(contains('1girl')));
    },
  );

  testWidgets(
    'right column: right-click on a suggestion offers apply, not '
    'remove-from-image',
    (tester) async {
      await tester.pumpWidget(harness());
      await tester.pumpAndSettle();

      await tester.tap(find.text('jewelry'), buttons: kSecondaryButton);
      await tester.pumpAndSettle();

      expect(find.text('Apply suggestion'), findsOneWidget);
      expect(find.text('Remove from this image'), findsNothing);
      expect(find.text('Set as insertion anchor'), findsNothing);
      expect(find.text('Add to library'), findsOneWidget);

      await tester.tap(find.text('Apply suggestion'));
      await tester.pumpAndSettle();
      expect(session.tags, contains('jewelry'));
    },
  );

  testWidgets(
    'right column: right-click on an already-matched suggestion offers no '
    'action beyond info/library',
    (tester) async {
      await tester.pumpWidget(harness());
      await tester.pumpAndSettle();

      // '1girl' also renders on the right (matched); that chip is last.
      await tester.tap(find.text('1girl').last, buttons: kSecondaryButton);
      await tester.pumpAndSettle();

      expect(find.text('Apply suggestion'), findsNothing);
      expect(find.text('Remove from this image'), findsNothing);
      expect(find.text('Add to library'), findsOneWidget);
    },
  );

  testWidgets('add to library from either column adds the tag', (
    tester,
  ) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    expect(appState.commonTags, isNot(contains('solo')));
    await tester.tap(find.text('solo'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add to library'));
    await tester.pumpAndSettle();
    expect(appState.commonTags, contains('solo'));
  });

  testWidgets(
    'without an AppState the menu still opens and add-to-library is a safe '
    'no-op',
    (tester) async {
      await tester.pumpWidget(harness(includeAppState: false));
      await tester.pumpAndSettle();

      await tester.tap(find.text('solo'), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      expect(find.text('Add to library'), findsOneWidget);

      await tester.tap(find.text('Add to library'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
