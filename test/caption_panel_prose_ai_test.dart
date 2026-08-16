import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dataset_training_tool/app_state.dart';
import 'package:dataset_training_tool/l10n/app_localizations.dart';
import 'package:dataset_training_tool/models/caption_type.dart';
import 'package:dataset_training_tool/services/ai_tagger_service.dart';
import 'package:dataset_training_tool/services/settings_service.dart';
import 'package:dataset_training_tool/state/ai_tagger_state.dart';
import 'package:dataset_training_tool/state/editor_session.dart';
import 'package:dataset_training_tool/state/shortcut_relay.dart';
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

/// A prose caption is what a natural-language caption model is for, so the AI
/// button has to work there — it just produces sentences instead of tags, and
/// the compare view stays out of it.
void main() {
  late Directory tempDir;
  late AppState appState;
  late File image;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    appState = AppState(SettingsService());
    await appState.loadSettings();
    tempDir = await Directory.systemTemp.createTemp('caption_panel_prose_ai_');
    image = File(p.join(tempDir.path, '001.png'));
    await image.writeAsBytes(_pngBytes);
  });

  tearDown(() async => tempDir.delete(recursive: true));

  /// A server holding one tagger and one caption model, answering every
  /// interrogation with [description].
  AiTaggerState buildAi({required String description}) {
    final client = MockClient((request) async {
      Map<String, dynamic> body;
      switch (request.url.path) {
        case '/getconfig':
          body = {
            'Interrogators': [
              {'ModelName': 'wd-tagger', 'Category': 'tag'},
              {'ModelName': 'joycaption', 'Category': 'caption'},
            ],
          };
        case '/interrogateimage':
          body = {
            'Success': true,
            'ErrorMessage': '',
            'Result': [
              {
                'ModelName': 'joycaption',
                'Tags': [
                  {'Tag': description, 'Probability': 1.0},
                ],
              },
            ],
          };
        default:
          return http.Response('not found', 404);
      }
      return http.Response(
        jsonEncode(body),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    return AiTaggerState(
      SettingsService(),
      service: AiTaggerService(client: client),
    );
  }

  Future<EditorSession> open(
    WidgetTester tester, {
    required AiTaggerState ai,
    required ShortcutRelay relay,
    required CaptionFormat format,
    String extension = '.ntxt',
    String captionText = '',
  }) async {
    final session = EditorSession()..autoSaveEnabled = false;
    addTearDown(session.dispose);
    // Real file IO never completes inside the fake-async zone.
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
          home: Scaffold(
            body: SizedBox(
              width: 900,
              height: 460,
              child: CaptionPanel(shortcutRelay: relay),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return session;
  }

  /// Fires the panel's AI action the way the toolbar button and Ctrl+E do.
  /// It reads the image off disk, so it has to run outside the fake-async
  /// zone; the pump afterwards renders whatever it changed.
  Future<void> runAi(WidgetTester tester, ShortcutRelay relay) async {
    await tester.runAsync(() async {
      relay.runAiForCurrentImage!();
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
  }

  testWidgets('a caption model describes the image into the sentence list', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final ai = buildAi(
      description: 'A girl smiles. She wears a red hat, outdoors.',
    );
    addTearDown(ai.dispose);
    await ai.refreshModels();
    await ai.setModelName('joycaption');
    final relay = ShortcutRelay();

    final session = await open(
      tester,
      ai: ai,
      relay: relay,
      format: CaptionFormat.prose,
    );

    // The button is live here, and it says what it produces.
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'AI describe'),
    );
    expect(button.onPressed, isNotNull);

    await runAi(tester, relay);

    // The description lands as sentences, split like a typed one would be.
    expect(
      session.captionController.text,
      'A girl smiles. She wears a red hat, outdoors.',
    );
    expect(find.text('A girl smiles.'), findsOneWidget);
    expect(find.text('She wears a red hat, outdoors.'), findsOneWidget);
    // Tag machinery stays out of it.
    expect(ai.compareMode, isFalse);
    expect(ai.hasResultFor(image.path), isFalse);
  });

  testWidgets('a tagger model is refused instead of writing tags as sentences', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final ai = buildAi(description: '1girl, smile, outdoors');
    addTearDown(ai.dispose);
    await ai.refreshModels();
    await ai.setModelName('wd-tagger');
    final relay = ShortcutRelay();

    final session = await open(
      tester,
      ai: ai,
      relay: relay,
      format: CaptionFormat.prose,
      captionText: 'A girl smiles.',
    );

    await runAi(tester, relay);

    expect(session.captionController.text, 'A girl smiles.');
    expect(
      find.textContaining('outputs tags, not sentences'),
      findsOneWidget,
    );
  });

  testWidgets('JSON captions keep the AI button disabled', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final ai = buildAi(description: 'unused');
    addTearDown(ai.dispose);
    final relay = ShortcutRelay();

    await open(
      tester,
      ai: ai,
      relay: relay,
      format: CaptionFormat.json,
      extension: '.json',
      captionText: '{"tags": ["1girl"]}',
    );

    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'AI tag'),
    );
    expect(button.onPressed, isNull);
  });
}
