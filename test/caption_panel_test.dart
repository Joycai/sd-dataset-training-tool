import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart' show kLongPressTimeout;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dataset_training_tool/app_state.dart';
import 'package:dataset_training_tool/l10n/app_localizations.dart';
import 'package:dataset_training_tool/services/ai_tagger_service.dart';
import 'package:dataset_training_tool/services/settings_service.dart';
import 'package:dataset_training_tool/state/ai_tagger_state.dart';
import 'package:dataset_training_tool/state/editor_session.dart';
import 'package:dataset_training_tool/theme/app_theme.dart';
import 'package:dataset_training_tool/views/panels/ai_compare_view.dart';
import 'package:dataset_training_tool/views/panels/caption_panel.dart';
import 'package:reorderable_grid_view/reorderable_grid_view.dart';

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
  late EditorSession session;
  late AiTaggerState ai;
  late AppState appState;
  late File imageA;
  late File imageB;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    appState = AppState(SettingsService());
    await appState.loadSettings();
    tempDir = await Directory.systemTemp.createTemp('caption_panel_');
    imageA = File(p.join(tempDir.path, '001.png'));
    imageB = File(p.join(tempDir.path, '002.png'));
    await imageA.writeAsBytes(_pngBytes);
    await imageB.writeAsBytes(_pngBytes);
    await File(p.join(tempDir.path, '001.txt')).writeAsString('alpha, beta');
    await File(p.join(tempDir.path, '002.txt')).writeAsString('gamma');

    session = EditorSession()..autoSaveEnabled = false;

    final client = MockClient((request) async {
      if (request.url.path == '/interrogateimage') {
        return http.Response(
          jsonEncode({
            'Success': true,
            'ErrorMessage': '',
            'Result': [
              {
                'ModelName': 'm',
                'Tags': [
                  {'Tag': 'smile', 'Probability': 0.9},
                ],
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('not found', 404);
    });
    ai = AiTaggerState(
      SettingsService(),
      service: AiTaggerService(client: client),
    );
    await ai.setModelName('m');
  });

  tearDown(() async {
    session.dispose();
    await tempDir.delete(recursive: true);
  });

  Widget harness() {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: appState),
        ChangeNotifierProvider.value(value: session),
        ChangeNotifierProvider.value(value: ai),
      ],
      child: MaterialApp(
        theme: buildAppTheme(Brightness.dark),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: CaptionPanel()),
      ),
    );
  }

  testWidgets('compare mode shows for the interrogated image', (tester) async {
    // Interrogation and file IO happen outside the fake-async zone.
    await tester.runAsync(() async {
      await session.load(imageA, '.txt');
      expect(await ai.interrogate(imageA), isTrue);
    });

    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    expect(ai.compareMode, isTrue);
    expect(find.byType(AiCompareView), findsOneWidget);
    expect(find.text('smile'), findsOneWidget);
  });

  testWidgets('current tags reorder by long-press drag in compare mode',
      (tester) async {
    await tester.runAsync(() async {
      await session.load(imageA, '.txt'); // tags: alpha, beta
      expect(await ai.interrogate(imageA), isTrue);
    });

    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();
    expect(find.byType(AiCompareView), findsOneWidget);

    // Long-press starts the drag (delete taps must keep working), then drop
    // "alpha" onto "beta" to swap them.
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('alpha')),
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await gesture.moveTo(tester.getCenter(find.text('beta')));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(session.tags, ['beta', 'alpha']);
  });

  testWidgets(
      'switching to an uninterrogated image falls back to the tags view',
      (tester) async {
    await tester.runAsync(() async {
      await session.load(imageA, '.txt');
      expect(await ai.interrogate(imageA), isTrue);
      // Regression: compare mode is a global flag; image B has no result, so
      // the tags tab used to render the empty "no result yet" compare view
      // instead of B's tags.
      await session.load(imageB, '.txt');
    });

    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    expect(ai.compareMode, isTrue);
    expect(find.byType(AiCompareView), findsNothing);
    expect(find.text('gamma'), findsOneWidget);
  });

  testWidgets('sort mode toggle switches drag behavior and chip actions',
      (tester) async {
    await tester.runAsync(() async {
      await session.load(imageA, '.txt');
    });

    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    // Edit mode: chips carry a delete button, drag needs a long press.
    expect(find.byIcon(Icons.close), findsNWidgets(2));
    ReorderableGridView grid() =>
        tester.widget<ReorderableGridView>(find.byType(ReorderableGridView));
    expect(grid().dragStartDelay, isNull);

    await tester.tap(find.byTooltip('Sort mode: drag tags to reorder'));
    await tester.pumpAndSettle();

    // Sort mode: no delete buttons, immediate drag.
    expect(find.byIcon(Icons.close), findsNothing);
    expect(grid().dragStartDelay, Duration.zero);

    // Switching images does not reset the mode.
    await tester.runAsync(() => session.load(imageB, '.txt'));
    await tester.pumpAndSettle();
    expect(find.text('gamma'), findsOneWidget);
    expect(find.byIcon(Icons.close), findsNothing);
    expect(grid().dragStartDelay, Duration.zero);
  });

  testWidgets('tag chips are tinted with their library group color',
      (tester) async {
    const groupColor = 0xFF9B84E0;
    await tester.runAsync(() async {
      await appState.addCommonTags(['alpha']);
      final g = await appState.createTagGroup('traits', groupColor);
      await appState.moveTagsToGroup(['alpha'], g.id);
      await session.load(imageA, '.txt'); // tags: alpha, beta
    });

    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    BoxDecoration decorationOf(String tag) {
      final container = tester.widget<Container>(
        find
            .ancestor(of: find.text(tag), matching: find.byType(Container))
            .first,
      );
      return container.decoration! as BoxDecoration;
    }

    // Grouped tag carries the group tint on its border; ungrouped stays
    // on the default hairline.
    final grouped = decorationOf('alpha');
    final plain = decorationOf('beta');
    expect(
      (grouped.border! as Border).top.color,
      const Color(groupColor).withAlpha(153),
    );
    expect(
      (plain.border! as Border).top.color,
      isNot((grouped.border! as Border).top.color),
    );
  });
}
