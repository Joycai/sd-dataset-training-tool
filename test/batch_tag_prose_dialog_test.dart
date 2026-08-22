import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dataset_training_tool/app_state.dart';
import 'package:dataset_training_tool/l10n/app_localizations.dart';
import 'package:dataset_training_tool/models/caption_type.dart';
import 'package:dataset_training_tool/services/ai_tagger_service.dart';
import 'package:dataset_training_tool/services/settings_service.dart';
import 'package:dataset_training_tool/state/ai_tagger_state.dart';
import 'package:dataset_training_tool/state/batch_tag_state.dart';
import 'package:dataset_training_tool/state/dataset_state.dart';
import 'package:dataset_training_tool/theme/app_theme.dart';
import 'package:dataset_training_tool/views/panels/batch_tag_dialog.dart';

/// What the batch dialog says about a run it just finished under a prose
/// caption type. Its own fixture rather than [batch_tag_dialog_test]'s,
/// because this one needs a fake server to actually complete a run and that
/// changes the dialog's layout enough to disturb the layout assertions there.
void main() {
  late Directory tempDir;
  late AppState appState;
  late DatasetState dataset;
  late AiTaggerState ai;
  late BatchTagState batch;

  MockClient fakeServer() => MockClient((request) async {
    final body = request.url.path == '/getconfig'
        ? {
            'Interrogators': [
              {'ModelName': 'joycaption', 'Category': 'caption'},
            ],
          }
        : {
            'Success': true,
            'ErrorMessage': '',
            'Result': [
              {
                'ModelName': 'joycaption',
                'Tags': [
                  {'Tag': 'A girl smiles.', 'Probability': 1.0},
                ],
              },
            ],
          };
    return http.Response(
      jsonEncode(body),
      200,
      headers: {'content-type': 'application/json'},
    );
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    appState = AppState(SettingsService());
    await appState.loadSettings();
    dataset = DatasetState();
    ai = AiTaggerState(
      SettingsService(),
      service: AiTaggerService(client: fakeServer()),
    );
    await ai.setModelName('joycaption');
    batch = BatchTagState(
      dataset: dataset,
      ai: ai,
      settings: SettingsService(),
      service: AiTaggerService(client: fakeServer()),
    );
  });

  tearDown(() async {
    batch.dispose();
    ai.dispose();
    dataset.dispose();
    // A test that failed mid-run can still hold the image open on Windows;
    // losing a temp directory is not worth failing the teardown over.
    try {
      await tempDir.delete(recursive: true);
    } on FileSystemException {
      // ignored
    }
  });

  /// Scans a one-image prose dataset. Real file IO never completes inside the
  /// fake-async zone, so it runs outside it.
  Future<void> scanProse(WidgetTester tester) async {
    await tester.runAsync(() async {
      tempDir = await Directory.systemTemp.createTemp('batch_prose_dialog_');
      await File('${tempDir.path}/001.png').writeAsBytes([1, 2, 3]);
      await dataset.scan(
        directoryPath: tempDir.path,
        recursive: false,
        captionExtension: '.ntxt',
        captionFormat: CaptionFormat.prose,
      );
    });
  }

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.dark),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showBatchTagDialog(
                  context,
                  ai: ai,
                  batch: batch,
                  dataset: dataset,
                  appState: appState,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  /// Presses Start and lets the (unawaited) run finish.
  ///
  /// The run is started from inside the fake-async zone, so its continuations
  /// only advance when the test pumps — but each interrogation and each
  /// caption write is real IO that only advances on the real event loop. One
  /// wait plus one pump therefore deadlocks halfway through; the two have to
  /// alternate until the run reports itself done.
  Future<void> runToCompletion(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(FilledButton, 'Start'));
    await tester.pump();
    for (var i = 0; i < 40 && batch.running; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(batch.running, isFalse, reason: 'the run never finished');
    // The notification that ended the run may have landed during a real-time
    // slice; settle so the dialog is showing the summary, not a stale frame.
    await tester.pumpAndSettle();
  }

  testWidgets('a finished description run is reported as one', (tester) async {
    // The tag-only mode the state coerces away: the run appends descriptions,
    // so the summary must not claim it only recognized and cached them.
    await batch.setMode(BatchTagMode.recognizeOnly);
    await scanProse(tester);
    await open(tester);
    await runToCompletion(tester);

    expect(batch.changed, 1);
    expect(batch.failed, 0);

    expect(find.text('Batch AI description finished'), findsOneWidget);
    expect(find.textContaining('recognized'), findsNothing);
    expect(find.textContaining('Compare mode is on'), findsNothing);
    // A run that rewrote captions has to say it can be undone.
    expect(find.textContaining('Use undo in the top bar'), findsOneWidget);
  });

  testWidgets('the caption is written and the compare view stays shut', (
    tester,
  ) async {
    await batch.setMode(BatchTagMode.recognizeOnly);
    await scanProse(tester);
    await open(tester);
    await runToCompletion(tester);

    expect(ai.compareMode, isFalse);
    await tester.runAsync(() async {
      expect(
        await File('${tempDir.path}/001.ntxt').readAsString(),
        'A girl smiles.',
      );
    });
  });
}
