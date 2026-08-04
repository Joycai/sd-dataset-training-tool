import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dataset_training_tool/app_state.dart';
import 'package:dataset_training_tool/l10n/app_localizations.dart';
import 'package:dataset_training_tool/models/caption_type.dart';
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

/// The editor's second tab has to fit the caption's format: an Anima Tag
/// caption's trailing sentence must not appear among the tag chips (it is not
/// a tag), and a prose caption needs a sentence view rather than a tag grid it
/// has no use for.
void main() {
  late Directory tempDir;
  late AppState appState;
  late File image;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    appState = AppState(SettingsService());
    await appState.loadSettings();
    tempDir = await Directory.systemTemp.createTemp('caption_panel_formats_');
    image = File(p.join(tempDir.path, '001.png'));
    await image.writeAsBytes(_pngBytes);
  });

  tearDown(() async => tempDir.delete(recursive: true));

  Future<EditorSession> open(
    WidgetTester tester,
    String extension,
    String captionText,
    CaptionFormat format,
  ) async {
    final session = EditorSession()..autoSaveEnabled = false;
    addTearDown(session.dispose);
    final ai = AiTaggerState(SettingsService());
    // Both the write and the load have to run outside the fake-async zone:
    // real file IO never completes inside it.
    await tester.runAsync(() async {
      await File(
        p.join(tempDir.path, '001$extension'),
      ).writeAsString(captionText);
      await session.load(image, extension, format: format);
    });
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: appState),
          ChangeNotifierProvider.value(value: session),
          ChangeNotifierProvider.value(value: ai),
        ],
        child: MaterialApp(
          theme: buildAppTheme(Brightness.dark),
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            body: SizedBox(width: 900, height: 460, child: CaptionPanel()),
          ),
        ),
      ),
    );
    await tester.pump();
    return session;
  }

  testWidgets('the Anima Tag sentence is not a chip and not in the count', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await open(
      tester,
      '.atxt',
      '1girl, smile, indoors. A girl smiles, indoors.',
      CaptionFormat.animaTag,
    );

    // Three tags, and the count says so — the sentence is not one of them.
    expect(find.text('3 tags'), findsOneWidget);
    expect(find.text('1girl'), findsOneWidget);
    expect(find.text('. A girl smiles, indoors.'), findsNothing);

    // It lives in its own labelled field instead.
    expect(find.text('Description'), findsOneWidget);
    expect(
      find.widgetWithText(TextField, 'A girl smiles, indoors.'),
      findsOneWidget,
    );
  });

  testWidgets('editing the description rewrites only the caption tail', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final session = await open(
      tester,
      '.atxt',
      '1girl, smile. An old sentence.',
      CaptionFormat.animaTag,
    );

    await tester.enterText(
      find.widgetWithText(TextField, 'An old sentence.'),
      'A new one, with a comma.',
    );
    await tester.pump();

    expect(
      session.captionController.text,
      '1girl, smile. A new one, with a comma.',
    );
    expect(session.captionTags, ['1girl', 'smile']);
  });

  testWidgets('clearing the description drops the period too', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final session = await open(
      tester,
      '.atxt',
      '1girl, smile. Gone soon.',
      CaptionFormat.animaTag,
    );

    await tester.enterText(find.widgetWithText(TextField, 'Gone soon.'), '   ');
    await tester.pump();

    expect(session.captionController.text, '1girl, smile');
  });

  testWidgets('a prose caption gets a sentence view, not a tag grid', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final session = await open(
      tester,
      '.ntxt',
      'A girl smiles. She wears a red hat, outdoors.',
      CaptionFormat.prose,
    );

    // The tab and the counter both speak prose.
    expect(find.text('Sentences'), findsOneWidget);
    expect(find.text('2 sentences'), findsOneWidget);
    expect(find.text('Type a sentence and press Enter'), findsOneWidget);

    // Each sentence is its own row, with its punctuation intact — and the
    // comma inside one does not start a second row.
    expect(find.text('A girl smiles.'), findsOneWidget);
    expect(find.text('She wears a red hat, outdoors.'), findsOneWidget);

    // And the rows drive the same session the text tab writes to.
    session.removeTag('She wears a red hat, outdoors.');
    await tester.pump();
    expect(session.captionController.text, 'A girl smiles.');
    expect(find.text('She wears a red hat, outdoors.'), findsNothing);
  });
}
