import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dataset_training_tool/app_state.dart';
import 'package:dataset_training_tool/l10n/app_localizations.dart';
import 'package:dataset_training_tool/models/tag_dictionary.dart';
import 'package:dataset_training_tool/models/tag_translation.dart';
import 'package:dataset_training_tool/services/settings_service.dart';
import 'package:dataset_training_tool/services/tag_dictionary_service.dart';
import 'package:dataset_training_tool/services/tag_translation_service.dart';
import 'package:dataset_training_tool/theme/app_theme.dart';
import 'package:dataset_training_tool/views/panels/tag_dictionary_dialog.dart';
import 'package:dataset_training_tool/widgets/tag_gloss.dart';

const _csv = '''
1girl,0,5113288,"1girls,sole_female"
long_hair,0,3000000,
blue_eyes,0,2000000,
''';

void main() {
  late Directory temp;
  late AppState appState;

  /// Which tag the dialog is opened onto; set by [open] before pumping.
  String? openWith;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    temp = await Directory.systemTemp.createTemp('dict_dialog_');
    openWith = null;
    appState = AppState(
      SettingsService(),
      tagDictionary: TagDictionaryService(storageDirectory: () async => temp),
      tagTranslations: TagTranslationService(
        storageDirectory: () async => temp,
      ),
    );
    await appState.loadSettings();
  });

  tearDown(() async {
    appState.dispose();
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  /// The dialog reads both services off AppState, so the test drives the real
  /// ones — pointed at a temp directory rather than the app support folder.
  Future<void> prepare({
    Iterable<TagTranslation> glossary = const [],
    List<TagDictionaryEntry> custom = const [],
  }) async {
    await appState.tagDictionary.loadCsv(_csv, full: true);
    if (custom.isNotEmpty) await appState.tagDictionary.setCustomEntries(custom);
    await appState.tagTranslations.load('zh');
    if (glossary.isNotEmpty) await appState.tagTranslations.upsertAll(glossary);
  }

  Widget harness() => ChangeNotifierProvider.value(
    value: appState,
    child: ListenableBuilder(
      listenable: appState.tagTranslations,
      builder: (context, _) => TagGlossScope(
        glosses: appState.tagTranslations,
        display: TagGlossDisplay.inline,
        child: MaterialApp(
          theme: buildAppTheme(Brightness.dark),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () =>
                      showTagDictionaryDialog(context, initialTag: openWith),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Future<void> open(WidgetTester tester, {String? initialTag}) async {
    openWith = initialTag;
    await tester.pumpWidget(harness());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('opens onto the tag it was given, in any spelling', (
    tester,
  ) async {
    await tester.runAsync(() => prepare());
    // A caption hands over its own spelling; the editor keys on danbooru's.
    await open(tester, initialTag: 'long hair');

    expect(find.text('Translation'), findsOneWidget);
    expect(find.text('long_hair'), findsWidgets);
  });

  testWidgets('writing a translation persists it and shows it in the list', (
    tester,
  ) async {
    await tester.runAsync(() => prepare());
    await open(tester, initialTag: 'long_hair');

    await tester.enterText(
      find.widgetWithText(TextField, 'Shown beside the tag in the UI'),
      '长发',
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(appState.tagTranslations.glossFor('long_hair'), '长发');
    expect(find.text('长发'), findsWidgets);
  });

  testWidgets('emptying the field deletes the translation', (tester) async {
    await tester.runAsync(
      () => prepare(
        glossary: const [TagTranslation(tag: 'long_hair', text: '长发')],
      ),
    );
    await open(tester, initialTag: 'long_hair');

    await tester.enterText(
      find.widgetWithText(TextField, 'Shown beside the tag in the UI'),
      '',
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    // One action, one meaning: there is no separate delete button, so an empty
    // field must not persist as a blank gloss on every chip.
    expect(appState.tagTranslations.has('long_hair'), isFalse);
  });

  testWidgets('the list searches by translation, not only by tag', (
    tester,
  ) async {
    await tester.runAsync(
      () => prepare(
        glossary: const [TagTranslation(tag: 'blue_eyes', text: '蓝眼')],
      ),
    );
    await open(tester);

    await tester.enterText(
      find.widgetWithText(TextField, 'Search a tag or a translation'),
      '蓝眼',
    );
    await tester.pumpAndSettle();

    // The direction the dictionary itself cannot answer.
    expect(find.text('blue_eyes'), findsOneWidget);
  });

  testWidgets('the empty search lists custom tags and translated ones', (
    tester,
  ) async {
    await tester.runAsync(
      () => prepare(
        glossary: const [TagTranslation(tag: 'long_hair', text: '长发')],
        custom: const [
          TagDictionaryEntry(name: 'my_oc', category: TagCategory.character),
        ],
      ),
    );
    await open(tester);

    expect(find.text('my_oc'), findsOneWidget);
    expect(find.text('added'), findsOneWidget);
    expect(find.text('long_hair'), findsOneWidget);
    // Untranslated dictionary tags are not inventory to scroll through.
    expect(find.text('1girl'), findsNothing);
  });

  testWidgets('a custom tag can be removed from the dictionary', (
    tester,
  ) async {
    await tester.runAsync(
      () => prepare(
        custom: const [
          TagDictionaryEntry(name: 'my_oc', category: TagCategory.character),
        ],
      ),
    );
    await open(tester, initialTag: 'my_oc');

    await tester.tap(
      find.widgetWithText(OutlinedButton, 'Remove from dictionary'),
    );
    await tester.pumpAndSettle();

    expect(appState.tagDictionary.customEntries, isEmpty);
  });
}
