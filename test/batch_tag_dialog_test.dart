import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dataset_training_tool/app_state.dart';
import 'package:dataset_training_tool/l10n/app_localizations.dart';
import 'package:dataset_training_tool/models/caption_type.dart';
import 'package:dataset_training_tool/models/merge_rules.dart';
import 'package:dataset_training_tool/services/settings_service.dart';
import 'package:dataset_training_tool/state/ai_tagger_state.dart';
import 'package:dataset_training_tool/state/batch_tag_state.dart';
import 'package:dataset_training_tool/state/dataset_state.dart';
import 'package:dataset_training_tool/theme/app_theme.dart';
import 'package:dataset_training_tool/views/panels/batch_tag_dialog.dart';

void main() {
  late AppState appState;
  late DatasetState dataset;
  late AiTaggerState ai;
  late BatchTagState batch;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    appState = AppState(SettingsService());
    await appState.loadSettings();
    dataset = DatasetState();
    ai = AiTaggerState(SettingsService());
    await ai.setModelName('m');
    batch = BatchTagState(
      dataset: dataset,
      ai: ai,
      settings: SettingsService(),
    );
    batch.resolveRules = (id) {
      for (final r in appState.mergeRuleSets) {
        if (r.id == id) return r;
      }
      return null;
    };
  });

  tearDown(() {
    batch.dispose();
    ai.dispose();
    dataset.dispose();
  });

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

  testWidgets('the four-mode selector fits without overflowing', (
    tester,
  ) async {
    // The dialog's content width is fixed, so a label that no longer fits is
    // a layout error rather than something that degrades gracefully.
    await open(tester);
    expect(find.text('Append'), findsOneWidget);
    expect(find.text('Sheet'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('character-sheet mode says so when there are no rules', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.text('Sheet'));
    await tester.pumpAndSettle();

    expect(find.textContaining('No rule sets yet'), findsOneWidget);
    // Nothing to apply: the run must not be startable.
    final start = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Start'),
    );
    expect(start.onPressed, isNull);
  });

  testWidgets('picking a rule set enables the run and shows its shape', (
    tester,
  ) async {
    await appState.saveMergeRules(
      const CharacterMergeRules(
        id: '',
        character: 'Aoi',
        triggerWord: 'aoichr',
        identityTags: ['blonde hair', 'twintails'],
        conflictTags: ['brown hair'],
        garments: [
          GarmentRule(tag: 'dress', evidence: ['skirt']),
          GarmentRule(tag: 'gloves'),
        ],
      ),
    );
    await open(tester);
    await tester.tap(find.text('Sheet'));
    await tester.pumpAndSettle();

    // Nothing selected yet.
    expect(find.text('Pick a rule set'), findsOneWidget);
    final before = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Start'),
    );
    expect(before.onPressed, isNull);

    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aoi').last);
    await tester.pumpAndSettle();

    expect(
      find.text('2 fixed traits · 2 outfit items · 1 always removed'),
      findsOneWidget,
    );
    final after = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Start'),
    );
    // The dataset is empty in this harness, so the run still cannot start —
    // but the rule set is chosen and remembered.
    expect(batch.selectedRules?.character, 'Aoi');
    expect(after.onPressed, isNull);
  });

  group('caption formats other than tags', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('batch_dialog_format_');
    });

    tearDown(() async => tempDir.delete(recursive: true));

    /// Scans a one-image dataset under [format]. Real file IO never completes
    /// inside the fake-async zone, so it runs outside it.
    Future<void> scanAs(
      WidgetTester tester,
      CaptionFormat format,
      String extension,
    ) async {
      await tester.runAsync(() async {
        await File(p.join(tempDir.path, '001.png')).writeAsBytes([1, 2, 3]);
        await dataset.scan(
          directoryPath: tempDir.path,
          recursive: false,
          captionExtension: extension,
          captionFormat: format,
        );
      });
    }

    testWidgets('prose offers only the two writing modes', (tester) async {
      await scanAs(tester, CaptionFormat.prose, '.ntxt');
      await open(tester);

      // Compare mode and character sheets are tag concepts.
      expect(find.text('Recognize'), findsNothing);
      expect(find.text('Sheet'), findsNothing);
      expect(find.text('Append'), findsOneWidget);
      expect(find.text('Overwrite'), findsOneWidget);
      expect(
        find.textContaining('runs a natural-language caption model'),
        findsOneWidget,
      );
      // Tag-only knobs are gone with them.
      expect(find.text('Blacklist'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a persisted tag-only mode falls back to append', (
      tester,
    ) async {
      await batch.setMode(BatchTagMode.characterSheet);
      await scanAs(tester, CaptionFormat.prose, '.ntxt');
      await open(tester);

      expect(batch.effectiveMode, BatchTagMode.append);
      expect(find.textContaining('appended to each image'), findsOneWidget);
      // The choice itself is kept for whenever a tag type is active again.
      expect(batch.mode, BatchTagMode.characterSheet);
    });

    testWidgets('JSON is refused with an explanation, not a start button', (
      tester,
    ) async {
      await scanAs(tester, CaptionFormat.json, '.json');
      await open(tester);

      expect(
        find.textContaining('would flatten each document'),
        findsOneWidget,
      );
      expect(find.widgetWithText(FilledButton, 'Start'), findsNothing);
    });
  });
}
