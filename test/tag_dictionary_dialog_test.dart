import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dataset_training_tool/app_state.dart';
import 'package:dataset_training_tool/l10n/app_localizations.dart';
import 'package:dataset_training_tool/models/tag_dictionary.dart';
import 'package:dataset_training_tool/models/tag_translation.dart';
import 'package:dataset_training_tool/services/danbooru_api.dart';
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

/// A danbooru that knows every tag it is asked about, echoing the name back.
///
/// Echoing matters: the dialog re-selects whatever the lookup resolved to, so a
/// fake that always answered with the same tag would silently move the
/// selection and make the "already in the dictionary" cases untestable.
DanbooruApi _fakeApi() => DanbooruApi(
  clientFactory: () => MockClient((request) async {
    if (request.url.path == '/tags.json') {
      return http.Response(
        jsonEncode([
          {
            'name': request.url.queryParameters['search[name]'],
            'category': 4,
            'post_count': 200000,
          },
        ]),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }
    return http.Response.bytes(
      utf8.encode(
        jsonEncode({
          'other_names': ['初音ミク'],
          'body': 'The most famous [[vocaloid]].',
        }),
      ),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  }),
);

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
                  onPressed: () => showTagDictionaryDialog(
                    context,
                    initialTag: openWith,
                    api: _fakeApi(),
                  ),
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

  /// Taps the fetch button and lets the request finish.
  ///
  /// The whole round trip has to complete inside [WidgetTester.runAsync]: the
  /// lookup renders a progress indicator while in flight, and `pumpAndSettle`
  /// can never settle against a spinning one — it would sit there until its own
  /// ten-minute timeout.
  Future<void> fetch(WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.tap(
        find.widgetWithText(OutlinedButton, 'Fetch from danbooru'),
      );
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 80));
    });
    await tester.pumpAndSettle();
  }

  /// The fetched-info panel sits at the bottom of a scrolling form, so on the
  /// 580px-tall dialog it starts below the fold.
  Future<void> tapInForm(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
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

  testWidgets('an unreadable glossary file says so instead of looking empty', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await File('${temp.path}/zh.json').writeAsString('{ not json');
      await prepare();
    });
    await open(tester);

    // Zero translations and a broken file look identical otherwise, which
    // invites the user to translate the whole dataset a second time.
    expect(find.textContaining('Glossary file could not be read'), findsOneWidget);
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

  group('danbooru lookup', () {
    testWidgets('a fetch offers other_names and the wiki as candidates', (
      tester,
    ) async {
      await tester.runAsync(() => prepare());
      await open(tester, initialTag: 'hatsune_miku');

      await fetch(tester);

      // Facts danbooru returned, none of them written on the user's behalf.
      expect(find.text('danbooru: Character · 200000 posts'), findsOneWidget);
      expect(find.text('初音ミク'), findsOneWidget);
      expect(find.text('The most famous vocaloid.'), findsOneWidget);
      expect(appState.tagTranslations.has('hatsune_miku'), isFalse);
    });

    testWidgets('an other_name becomes the translation in one tap', (
      tester,
    ) async {
      await tester.runAsync(() => prepare());
      await open(tester, initialTag: 'hatsune_miku');
      await fetch(tester);

      await tapInForm(tester, find.text('初音ミク'));
      await tapInForm(tester, find.widgetWithText(FilledButton, 'Save'));

      final entry = appState.tagTranslations.lookup('hatsune_miku');
      expect(entry?.text, '初音ミク');
      // Provenance is recorded, so a later bulk cleanup can tell danbooru's
      // wording apart from the user's own.
      expect(entry?.source, TagTranslationSource.danbooru);
    });

    testWidgets('typing over a fetched name makes it the user\'s own', (
      tester,
    ) async {
      await tester.runAsync(() => prepare());
      await open(tester, initialTag: 'hatsune_miku');
      await fetch(tester);

      await tapInForm(tester, find.text('初音ミク'));
      await tester.enterText(
        find.widgetWithText(TextField, 'Shown beside the tag in the UI'),
        '初音未来',
      );
      await tester.pump();
      await tapInForm(tester, find.widgetWithText(FilledButton, 'Save'));

      final entry = appState.tagTranslations.lookup('hatsune_miku');
      expect(entry?.text, '初音未来');
      expect(entry?.source, TagTranslationSource.manual);
    });

    testWidgets('a fetched tag can be added to the dictionary', (tester) async {
      await tester.runAsync(() => prepare());
      await open(tester, initialTag: 'hatsune_miku');
      await fetch(tester);

      await tapInForm(
        tester,
        find.widgetWithText(OutlinedButton, 'Add to the dictionary'),
      );

      // With danbooru's own category and count, so it ranks and colours like
      // the real tag it is.
      final added = appState.tagDictionary.lookup('hatsune_miku');
      expect(added?.category, TagCategory.character);
      expect(added?.postCount, 200000);
    });

    testWidgets('a tag the dictionary already has offers no add action', (
      tester,
    ) async {
      await tester.runAsync(() => prepare());
      await open(tester, initialTag: 'long_hair');
      await fetch(tester);

      expect(
        find.widgetWithText(OutlinedButton, 'Add to the dictionary'),
        findsNothing,
      );
    });

    testWidgets('a hand-added tag offers no lookup at all', (tester) async {
      await tester.runAsync(
        () => prepare(
          custom: const [
            TagDictionaryEntry(name: 'my_oc', category: TagCategory.character),
          ],
        ),
      );
      await open(tester, initialTag: 'my_oc');

      // danbooru has neither a record nor a wiki page for the user's own
      // invention, so both the lookup and the wiki link would come back empty.
      expect(
        find.widgetWithText(OutlinedButton, 'Fetch from danbooru'),
        findsNothing,
      );
      expect(find.widgetWithText(OutlinedButton, 'Danbooru wiki'), findsNothing);
    });
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
