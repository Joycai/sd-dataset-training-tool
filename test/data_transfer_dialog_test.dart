import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dataset_training_tool/app_state.dart';
import 'package:dataset_training_tool/l10n/app_localizations.dart';
import 'package:dataset_training_tool/models/data_bundle.dart';
import 'package:dataset_training_tool/models/llm_models.dart';
import 'package:dataset_training_tool/services/data_transfer.dart';
import 'package:dataset_training_tool/services/settings_service.dart';
import 'package:dataset_training_tool/services/tag_dictionary_service.dart';
import 'package:dataset_training_tool/services/tag_translation_service.dart';
import 'package:dataset_training_tool/theme/app_theme.dart';
import 'package:dataset_training_tool/views/panels/data_transfer_dialog.dart';
import 'package:dataset_training_tool/views/settings_view.dart';

void main() {
  late Directory temp;
  late AppState appState;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    temp = await Directory.systemTemp.createTemp('data_transfer_dialog_');
    appState = AppState(
      SettingsService(),
      tagDictionary: TagDictionaryService(storageDirectory: () async => temp),
      tagTranslations: TagTranslationService(
        storageDirectory: () async => temp,
      ),
    );
    await appState.loadSettings();
    await appState.tagTranslations.load('en');
  });

  tearDown(() async {
    appState.dispose();
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  Widget harness(Widget Function(BuildContext context) body) =>
      ChangeNotifierProvider.value(
        value: appState,
        child: MaterialApp(
          theme: buildAppTheme(Brightness.dark),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(body: Builder(builder: body)),
        ),
      );

  testWidgets('settings has a data section with export and import', (
    tester,
  ) async {
    await tester.pumpWidget(harness((_) => const SettingsView()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Data'));
    await tester.pumpAndSettle();

    expect(find.text('Export data'), findsOneWidget);
    expect(find.text('Import data'), findsOneWidget);
    expect(find.text('Export…'), findsOneWidget);
    expect(find.text('Import…'), findsOneWidget);
  });

  testWidgets('the export picker counts what each section holds', (
    tester,
  ) async {
    await appState.updateLlmProviders([
      const LlmProvider(
        id: 'p',
        name: 'OpenAI',
        models: [
          LlmModelConfig(id: 'a', modelId: 'gpt-5'),
          LlmModelConfig(id: 'b', modelId: 'gpt-5-mini'),
        ],
      ),
    ]);
    await appState.addCommonTags(['long_hair', 'blue_eyes']);
    await appState.createPromptPreset(title: 'cleanup');

    await tester.pumpWidget(
      harness(
        (context) => TextButton(
          onPressed: () => showDataExportDialog(context),
          child: const Text('open'),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('1 backends · 2 models'), findsOneWidget);
    expect(
      find.text(
        '2 tags · 0 groups · 0 custom tags · 0 translations '
        '· 0 danbooru records',
      ),
      findsOneWidget,
    );
    expect(find.text('1 presets'), findsOneWidget);
    // The key sub-option only exists while its section is selected, and the
    // plain-text warning must be on screen before the file is written.
    expect(find.text('Include API keys'), findsOneWidget);

    await tester.tap(find.text('AI backends'));
    await tester.pumpAndSettle();
    expect(find.text('Include API keys'), findsNothing);

    // With nothing selected there is nothing to write, so no file dialog.
    await tester.tap(find.text('Tag library'));
    await tester.tap(find.text('Prompt presets'));
    await tester.pumpAndSettle();
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Export'),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('import reports what it changed and leaves the rest alone', (
    tester,
  ) async {
    // A bundle written by a different install.
    final source = AppState(
      SettingsService(),
      tagDictionary: TagDictionaryService(storageDirectory: () async => temp),
      tagTranslations: TagTranslationService(
        storageDirectory: () async => temp,
      ),
    );
    SharedPreferences.setMockInitialValues({});
    await source.loadSettings();
    await source.createPromptPreset(title: 'from file', content: 'body');
    final text = (await DataTransfer(
      source,
    ).collect(sections: {DataSection.promptPresets})).encode();
    source.dispose();

    await tester.pumpWidget(
      harness(
        (context) => TextButton(
          onPressed: () => runDataImport(context, text),
          child: const Text('open'),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Sections the file does not carry are shown but cannot be selected.
    expect(find.text('Not in this file'), findsNWidgets(2));
    expect(find.text('1 presets'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Import'));
    await tester.pumpAndSettle();

    expect(find.text('Prompt presets: 1 added, 0 updated'), findsOneWidget);
    expect(appState.promptPresets.single.title, 'from file');
    expect(appState.llmProviders, isEmpty);
  });

  testWidgets('a file that is not an export is refused', (tester) async {
    await tester.pumpWidget(
      harness(
        (context) => TextButton(
          onPressed: () => runDataImport(context, '{"version":1,"groups":[]}'),
          child: const Text('open'),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Import failed'), findsOneWidget);
    // No picker dialog behind the snackbar.
    expect(find.text('Import'), findsNothing);
  });
}
