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
import 'package:dataset_training_tool/state/editor_session.dart';
import 'package:dataset_training_tool/theme/app_theme.dart';
import 'package:dataset_training_tool/views/panels/caption_panel.dart';

// 1x1 transparent PNG.
const _pngBytes = [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x62, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
];

/// The editor toolbar lays itself out from hand-tuned width budgets, and the
/// numbers went stale once the save indicator started appearing next to the
/// labelled buttons: between the collapse threshold and the width the labels
/// actually need, every frame threw "A RenderFlex overflowed".
///
/// The budgets are only as good as this sweep, so it walks every width the
/// panel can plausibly get, in both locales and in every save state, and
/// fails on the first overflow.
void main() {
  late Directory tempDir;
  late AppState appState;
  late File image;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    appState = AppState(SettingsService());
    await appState.loadSettings();
    tempDir = await Directory.systemTemp.createTemp('toolbar_overflow_');
    image = File(p.join(tempDir.path, '001.png'));
    await image.writeAsBytes(_pngBytes);
    await File(p.join(tempDir.path, '001.txt')).writeAsString('alpha, beta');
  });

  tearDown(() async => tempDir.delete(recursive: true));

  Widget harness({
    required double width,
    required Locale locale,
    required EditorSession session,
    required AiTaggerState ai,
    required Key key,
  }) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: appState),
        ChangeNotifierProvider.value(value: session),
        ChangeNotifierProvider.value(value: ai),
      ],
      child: MaterialApp(
        theme: buildAppTheme(Brightness.dark),
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              height: 400,
              child: CaptionPanel(key: key),
            ),
          ),
        ),
      ),
    );
  }

  // The narrowest the centre column reaches with both side panels at their
  // 200 minimum is around a 720px window; 200 leaves room to spare below it.
  const minWidth = 200;
  const maxWidth = 900;

  testWidgets('editor toolbar never overflows at any panel width', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(2000, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    for (final locale in [const Locale('en'), const Locale('zh')]) {
      // Each save state renders a different indicator width, and "nothing
      // saved yet" renders none at all — the widest and the narrowest cases
      // sit at opposite ends of that set.
      for (final state in ['pristine', 'dirty', 'saved']) {
        for (final compare in [false, true]) {
          final session = EditorSession()..autoSaveEnabled = false;
          final ai = AiTaggerState(SettingsService());
          addTearDown(session.dispose);

          await tester.runAsync(() async {
            await session.load(image, '.txt');
            if (state == 'dirty') {
              session.captionController.text = 'alpha, beta, gamma';
            } else if (state == 'saved') {
              session.captionController.text = 'alpha, beta, gamma';
              await session.save();
            }
          });
          if (compare) ai.enterCompareMode();

          final label = '${locale.languageCode}/$state/compare=$compare';
          for (var w = minWidth; w <= maxWidth; w += 4) {
            // A fresh key every pump: RenderFlex reports an overflow only
            // once per render object, so reusing the subtree would swallow
            // every hit after the first and quietly pass.
            await tester.pumpWidget(
              harness(
                width: w.toDouble(),
                locale: locale,
                session: session,
                ai: ai,
                key: ValueKey('$label-$w'),
              ),
            );
            await tester.pump();
            expect(
              tester.takeException(),
              isNull,
              reason: 'toolbar overflowed at ${w}px ($label)',
            );
          }
        }
      }
    }
  });
}
