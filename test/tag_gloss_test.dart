import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dataset_training_tool/app_state.dart';
import 'package:dataset_training_tool/l10n/app_localizations.dart';
import 'package:dataset_training_tool/models/tag_translation.dart';
import 'package:dataset_training_tool/services/ai_tagger_service.dart';
import 'package:dataset_training_tool/services/settings_service.dart';
import 'package:dataset_training_tool/services/tag_translation_service.dart';
import 'package:dataset_training_tool/state/ai_tagger_state.dart';
import 'package:dataset_training_tool/state/editor_session.dart';
import 'package:dataset_training_tool/theme/app_theme.dart';
import 'package:dataset_training_tool/views/panels/caption_panel.dart';
import 'package:dataset_training_tool/widgets/tag_gloss.dart';

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
  late TagTranslationService glossary;
  late File image;
  late File caption;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    appState = AppState(SettingsService());
    await appState.loadSettings();
    tempDir = await Directory.systemTemp.createTemp('tag_gloss_');
    image = File(p.join(tempDir.path, '001.png'));
    caption = File(p.join(tempDir.path, '001.txt'));
    await image.writeAsBytes(_pngBytes);
    await caption.writeAsString('long_hair, blue_eyes');

    session = EditorSession()..autoSaveEnabled = false;
    ai = AiTaggerState(SettingsService(), service: AiTaggerService());

    glossary = TagTranslationService(storageDirectory: () async => tempDir);
    await glossary.load('zh');
    await glossary.upsertAll(const [
      TagTranslation(tag: 'long_hair', text: '长发', note: '头发长过肩'),
      TagTranslation(tag: 'blue_eyes', text: '蓝眼'),
    ]);
  });

  tearDown(() async {
    session.dispose();
    glossary.dispose();
    await tempDir.delete(recursive: true);
  });

  Widget harness(TagGlossDisplay display) => MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: appState),
      ChangeNotifierProvider.value(value: session),
      ChangeNotifierProvider.value(value: ai),
    ],
    // Mirrors main.dart: the ListenableBuilder is what turns the service's own
    // notifications into a scope update, so the tests exercise that wiring
    // rather than a static snapshot of it.
    child: ListenableBuilder(
      listenable: glossary,
      builder: (context, _) => TagGlossScope(
        glosses: glossary,
        display: display,
        child: MaterialApp(
          theme: buildAppTheme(Brightness.dark),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: CaptionPanel()),
        ),
      ),
    ),
  );

  Future<void> open(WidgetTester tester, TagGlossDisplay display) async {
    await tester.runAsync(() => session.load(image, '.txt'));
    await tester.pumpWidget(harness(display));
    await tester.pumpAndSettle();
  }

  testWidgets('inline mode renders the gloss beside the tag', (tester) async {
    await open(tester, TagGlossDisplay.inline);

    expect(find.text('long_hair'), findsOneWidget);
    expect(find.text('长发'), findsOneWidget);
    expect(find.text('蓝眼'), findsOneWidget);
  });

  testWidgets('a gloss never reaches the caption file', (tester) async {
    await open(tester, TagGlossDisplay.inline);
    expect(find.text('长发'), findsOneWidget);

    // The whole point of the layer: it is display metadata. Editing tags with
    // glosses on screen has to write tags only. Mutation, save and read-back
    // all happen outside the fake-async zone — real file IO inside it hangs.
    String? written;
    await tester.runAsync(() async {
      session.removeTag('blue_eyes');
      await session.save();
      written = await caption.readAsString();
    });

    expect(session.tags, ['long_hair']);
    expect(written, 'long_hair');
  });

  testWidgets('editing a translation repaints the chips', (tester) async {
    await open(tester, TagGlossDisplay.inline);
    expect(find.text('长发'), findsOneWidget);

    await tester.runAsync(
      () => glossary.upsert(
        const TagTranslation(tag: 'long_hair', text: '长头发'),
      ),
    );
    await tester.pumpAndSettle();

    // Editing one entry's text moves neither the glossary's identity nor its
    // entry count, so this only works if the scope watches a real revision.
    expect(find.text('长发'), findsNothing);
    expect(find.text('长头发'), findsOneWidget);
  });

  testWidgets('tooltip mode keeps the gloss out of the layout', (tester) async {
    await open(tester, TagGlossDisplay.tooltip);

    expect(find.text('long_hair'), findsOneWidget);
    // Chip widths are budgeted to the pixel elsewhere; this mode exists so
    // they do not move at all.
    expect(find.text('长发'), findsNothing);
    expect(
      find.ancestor(
        of: find.text('long_hair'),
        matching: find.byType(Tooltip),
      ),
      findsOneWidget,
    );
  });

  testWidgets('off mode renders neither the gloss nor a tooltip', (
    tester,
  ) async {
    await open(tester, TagGlossDisplay.off);

    expect(find.text('long_hair'), findsOneWidget);
    expect(find.text('长发'), findsNothing);
    expect(
      find.ancestor(
        of: find.text('long_hair'),
        matching: find.byType(Tooltip),
      ),
      findsNothing,
    );
  });

  testWidgets('with no scope installed nothing changes', (tester) async {
    // Panels rendered outside the app's scope — sub-windows, tests — must
    // degrade to plain tags rather than throw.
    await tester.runAsync(() => session.load(image, '.txt'));
    await tester.pumpWidget(
      MultiProvider(
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
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('long_hair'), findsOneWidget);
    expect(find.text('长发'), findsNothing);
  });
}
