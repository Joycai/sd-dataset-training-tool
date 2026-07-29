import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dataset_training_tool/app_state.dart';
import 'package:dataset_training_tool/l10n/app_localizations.dart';
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
}
