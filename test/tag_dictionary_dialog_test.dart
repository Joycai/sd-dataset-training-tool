import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart' show kSecondaryButton;
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
import 'package:dataset_training_tool/services/danbooru_meta_service.dart';
import 'package:dataset_training_tool/services/settings_service.dart';
import 'package:dataset_training_tool/services/tag_dictionary_service.dart';
import 'package:dataset_training_tool/services/tag_translation_service.dart';
import 'package:dataset_training_tool/theme/app_theme.dart';
import 'package:dataset_training_tool/views/panels/tag_dictionary_dialog.dart';
import 'package:dataset_training_tool/widgets/panel_widgets.dart';
import 'package:dataset_training_tool/widgets/tag_gloss.dart';

const _csv = '''
1girl,0,5113288,"1girls,sole_female"
long_hair,0,3000000,
blue_eyes,0,2000000,
''';

/// A danbooru that knows every tag it is asked about — except the ones in
/// [unknown] — echoing the name back.
///
/// Echoing matters: the dialog re-selects whatever the lookup resolved to, so a
/// fake that always answered with the same tag would silently move the
/// selection and make the "already in the dictionary" cases untestable.
DanbooruApi _fakeApi({Set<String> unknown = const {}}) => DanbooruApi(
  clientFactory: () => MockClient((request) async {
    if (request.url.path == '/tags.json') {
      final name = request.url.queryParameters['search[name]'];
      return http.Response(
        jsonEncode([
          if (!unknown.contains(name))
            {'name': name, 'category': 4, 'post_count': 200000},
        ]),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }
    final page = request.url.pathSegments.last.replaceAll('.json', '');
    if (unknown.contains(page)) return http.Response('', 404);
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

  /// The workbench snapshot handed to the dialog; set by [open].
  TagDictionaryScope scope = const TagDictionaryScope();

  /// Tags the fake danbooru claims not to have; set before [open].
  Set<String> unknownTags = const {};

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    temp = await Directory.systemTemp.createTemp('dict_dialog_');
    openWith = null;
    unknownTags = const {};
    appState = AppState(
      SettingsService(),
      tagDictionary: TagDictionaryService(storageDirectory: () async => temp),
      tagTranslations: TagTranslationService(
        storageDirectory: () async => temp,
      ),
      danbooruMeta: DanbooruMetaService(storageDirectory: () async => temp),
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
    if (custom.isNotEmpty) {
      await appState.tagDictionary.setCustomEntries(custom);
    }
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
                    api: _fakeApi(unknown: unknownTags),
                    scope: scope,
                    batchDelay: Duration.zero,
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

  Future<void> open(
    WidgetTester tester, {
    String? initialTag,
    TagDictionaryScope workbench = const TagDictionaryScope(),
  }) async {
    openWith = initialTag;
    scope = workbench;
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
      // The header actions are bare tap targets, not buttons: they sit beside
      // the tag name, where a Material button's padding would dominate.
      await tester.tap(find.text('Update from danbooru'));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 80));
    });
    await tester.pumpAndSettle();
  }

  /// Taps a toolbar control by label, reaching into the overflow menu when the
  /// strip was too narrow to keep it. The test font is wide enough that the
  /// default surface size already pushes controls in there.
  Future<void> tapToolbar(WidgetTester tester, String label) async {
    if (find.text(label).evaluate().isEmpty) {
      await tester.tap(find.byIcon(Icons.more_horiz));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text(label));
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

  group('the toolbar band', () {
    /// The band is one row by construction — the search field's vertical
    /// centre used to move when the controls wrapped to a second line — so
    /// every width it can get has to fit, with the surplus in the menu.
    for (final width in const [1400.0, 1000.0, 820.0, 680.0, 560.0, 460.0]) {
      testWidgets('holds one line at ${width.toInt()}px', (tester) async {
        addTearDown(tester.view.reset);
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 760);

        await tester.runAsync(() => prepare());
        // The widest the strip ever gets: four filters plus both actions.
        await open(
          tester,
          workbench: const TagDictionaryScope(
            datasetTags: ['long_hair'],
            datasetUsage: {'long hair': 1},
            imageCount: 1,
          ),
        );

        // An overflow would already have thrown; this pins the row down.
        // Whatever survived on the strip has to share the search field's
        // midline — the wrap this replaced pushed it up half a line.
        final search = tester.getRect(find.byType(PanelSearchField));
        final probes = <Finder>[
          for (final label in const ['All', 'Untranslated'])
            if (find.text(label).evaluate().isNotEmpty) find.text(label),
          if (find.byIcon(Icons.more_horiz).evaluate().isNotEmpty)
            find.byIcon(Icons.more_horiz),
        ];
        expect(probes, isNotEmpty);
        for (final probe in probes) {
          expect(
            tester.getRect(probe).center.dy,
            closeTo(search.center.dy, 1),
            reason: 'a control left the search field\'s midline',
          );
        }
      });
    }

    testWidgets('what does not fit is reachable from the menu', (tester) async {
      addTearDown(tester.view.reset);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(560, 760);

      await tester.runAsync(() => prepare());
      await open(tester);

      // The two actions are dropped first: each is reachable another way,
      // while the filters steer the list.
      expect(find.text('New tag'), findsNothing);
      await tester.tap(find.byIcon(Icons.more_horiz));
      await tester.pumpAndSettle();
      await tester.tap(find.text('New tag'));
      await tester.pumpAndSettle();

      expect(find.text('New custom tag'), findsOneWidget);
    });
  });

  testWidgets('the trailing actions keep the right edge', (tester) async {
    await tester.runAsync(() => prepare());
    await open(tester, initialTag: 'long_hair');

    final surface = tester.getRect(find.byType(GlassSurface));
    // The footer's own 12px of padding and nothing else. These used to be one
    // flex child among two, which handed them half the band and left them
    // aligned right *within that half* — the middle of the footer.
    expect(
      surface.right -
          tester.getRect(find.widgetWithText(TextButton, 'Export')).right,
      closeTo(12, 1),
    );
    // And the same shape one row up.
    expect(
      surface.right -
          tester.getRect(find.widgetWithText(FilledButton, 'Save')).right,
      closeTo(18, 1),
    );
  });

  testWidgets('the save row does not move as the line beside it changes', (
    tester,
  ) async {
    await tester.runAsync(
      () => prepare(
        glossary: const [
          // An entry the user did not write, so typing over it flips the
          // provenance and raises the note this test is about.
          TagTranslation(
            tag: 'long_hair',
            text: '长发',
            source: TagTranslationSource.llm,
          ),
        ],
      ),
    );
    await open(tester, initialTag: 'long_hair');

    final before = tester.getRect(find.widgetWithText(FilledButton, 'Save'));
    // Typing raises a "saving makes it X" note next to the source badge. The
    // buttons used to be one flex child among three and slid left when it did.
    await tester.enterText(
      find.widgetWithText(TextField, 'Shown beside the tag in the UI'),
      '长长的头发',
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('saving makes it'), findsOneWidget);
    expect(tester.getRect(find.widgetWithText(FilledButton, 'Save')), before);
  });

  group('deleting', () {
    Future<void> openTranslated(WidgetTester tester) async {
      await tester.runAsync(
        () => prepare(
          glossary: const [TagTranslation(tag: 'long_hair', text: '长发')],
        ),
      );
      await open(tester, initialTag: 'long_hair');
    }

    testWidgets('emptying the field is not a delete', (tester) async {
      await openTranslated(tester);

      await tester.enterText(
        find.widgetWithText(TextField, 'Shown beside the tag in the UI'),
        '',
      );
      await tester.pump();

      // Deleting by clearing meant a select-all-and-retype that ended up empty
      // silently dropped a translation. Saving is simply not offered instead.
      final save = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Save'),
      );
      expect(save.onPressed, isNull);
      expect(appState.tagTranslations.has('long_hair'), isTrue);
    });

    testWidgets('the explicit delete asks before it acts', (tester) async {
      await openTranslated(tester);

      await tapInForm(
        tester,
        find.widgetWithText(OutlinedButton, 'Delete translation'),
      );
      // Nothing is gone until the question is answered.
      expect(appState.tagTranslations.has('long_hair'), isTrue);

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(appState.tagTranslations.has('long_hair'), isTrue);

      await tapInForm(
        tester,
        find.widgetWithText(OutlinedButton, 'Delete translation'),
      );
      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(appState.tagTranslations.has('long_hair'), isFalse);
    });

    testWidgets('a row offers its deletions on right-click', (tester) async {
      await openTranslated(tester);

      // Reached without selecting the row first, which is what makes clearing
      // out a batch of stray entries bearable.
      await tester.tapAt(
        tester.getCenter(
          // The gloss shows in the list row and in the editor field alike.
          find.descendant(of: find.byType(ListView), matching: find.text('长发')),
        ),
        buttons: kSecondaryButton,
      );
      await tester.pumpAndSettle();
      // The editor behind the menu offers the same action under the same name.
      await tester.tap(
        find.descendant(
          of: find.byType(PopupMenuItem<String>),
          matching: find.text('Delete translation'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(appState.tagTranslations.has('long_hair'), isFalse);
    });
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
    expect(
      find.textContaining('Glossary file could not be read'),
      findsOneWidget,
    );
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

    testWidgets('a hand-added tag offers the update but not the wiki link', (
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

      // A collected dataset tag is usually a real danbooru tag, so the update
      // stays offered; the wiki link waits until danbooru confirms the page
      // can exist.
      expect(find.text('Update from danbooru'), findsOneWidget);
      expect(find.text('Danbooru wiki'), findsNothing);
    });
  });

  group('danbooru update', () {
    testWidgets('writes other_names into a custom entry\'s aliases', (
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
      await fetch(tester);

      // Persisted into the entry itself, with danbooru's own count — not
      // merely displayed for the session.
      final entry = appState.tagDictionary.customEntries.single;
      expect(entry.aliases, ['初音ミク']);
      expect(entry.postCount, 200000);
      // Confirmed on danbooru, so the wiki link is now offered too.
      expect(find.text('Danbooru wiki'), findsOneWidget);
    });

    testWidgets('fills an empty note with the wiki excerpt', (tester) async {
      await tester.runAsync(
        () => prepare(
          glossary: const [TagTranslation(tag: 'long_hair', text: '长发')],
        ),
      );
      await open(tester, initialTag: 'long_hair');
      await fetch(tester);

      final entry = appState.tagTranslations.lookup('long_hair');
      expect(entry?.note, 'The most famous vocaloid.');
      // The note came from danbooru but the translation did not: a later
      // "clear fetched translations" must not sweep this entry away.
      expect(entry?.source, TagTranslationSource.manual);
    });

    testWidgets('never overwrites a note the user wrote', (tester) async {
      await tester.runAsync(
        () => prepare(
          glossary: const [
            TagTranslation(tag: 'long_hair', text: '长发', note: '手写注释'),
          ],
        ),
      );
      await open(tester, initialTag: 'long_hair');
      await fetch(tester);

      expect(appState.tagTranslations.lookup('long_hair')?.note, '手写注释');
    });

    testWidgets('a tag danbooru lacks is marked as missing', (tester) async {
      unknownTags = {'my_oc'};
      await tester.runAsync(
        () => prepare(
          custom: const [
            TagDictionaryEntry(name: 'my_oc', category: TagCategory.character),
          ],
        ),
      );
      await open(tester, initialTag: 'my_oc');
      await fetch(tester);

      // The mark is the answer: recorded, so a batch run never asks again.
      expect(appState.danbooruMeta.isMissing('my_oc'), isTrue);
      expect(appState.tagDictionary.customEntries.single.aliases, isEmpty);
    });

    testWidgets('a recorded lookup renders next time without fetching', (
      tester,
    ) async {
      await tester.runAsync(() async {
        await prepare();
        await appState.danbooruMeta.record(
          const DanbooruTagInfo(
            name: 'long_hair',
            category: TagCategory.general,
            postCount: 3000000,
            otherNames: ['ロングヘア'],
            wikiExcerpt: 'Hair below the shoulder blades.',
            knownToDanbooru: true,
            hasWiki: true,
          ),
        );
      });
      await open(tester, initialTag: 'long_hair');

      // Straight from the store — no tap on the update action.
      expect(find.text('ロングヘア'), findsOneWidget);
      expect(find.text('Hair below the shoulder blades.'), findsOneWidget);
    });
  });

  group('batch update', () {
    testWidgets('fetches only unrecorded tags and marks the unknown ones', (
      tester,
    ) async {
      unknownTags = {'prettysammy'};
      await tester.runAsync(() async {
        await prepare(
          glossary: const [TagTranslation(tag: 'long_hair', text: '长发')],
        );
        // Already recorded: the batch must not ask danbooru about it again.
        await appState.danbooruMeta.record(
          const DanbooruTagInfo(name: '1girl', knownToDanbooru: true),
        );
      });
      await open(
        tester,
        workbench: const TagDictionaryScope(
          datasetTags: ['1girl', 'long_hair', 'prettysammy'],
          datasetUsage: {'1girl': 40, 'long hair': 30, 'prettysammy': 12},
          imageCount: 40,
        ),
      );

      await tester.tap(find.text('Danbooru batch update'));
      await tester.pumpAndSettle();
      expect(find.text('2 tags to fetch'), findsOneWidget);

      // The pane is a scrolling form and the button sits below the fold on
      // the test surface.
      await tester.ensureVisible(find.widgetWithText(FilledButton, 'Start'));
      await tester.pumpAndSettle();

      // The whole run has to finish inside runAsync — its progress bar, like
      // the single lookup's spinner, never lets pumpAndSettle settle.
      await tester.runAsync(() async {
        await tester.tap(find.widgetWithText(FilledButton, 'Start'));
        for (
          var i = 0;
          i < 200 && !appState.danbooruMeta.has('prettysammy');
          i++
        ) {
          await tester.pump();
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        await Future<void>.delayed(const Duration(milliseconds: 60));
      });
      await tester.pumpAndSettle();

      expect(
        find.text('Done: 1 updated, 1 not on danbooru, 0 failed'),
        findsOneWidget,
      );
      // The real tag got the full treatment — note included — and the
      // unknown one got its mark.
      expect(
        appState.tagTranslations.lookup('long_hair')?.note,
        'The most famous vocaloid.',
      );
      expect(appState.danbooruMeta.isMissing('prettysammy'), isTrue);
      expect(appState.danbooruMeta.lookup('1girl')?.otherNames, isEmpty);
    });
  });

  group('the open dataset', () {
    /// A workbench with three dataset tags, one of which danbooru — and this
    /// dictionary — has never heard of.
    TagDictionaryScope workbench() => const TagDictionaryScope(
      datasetTags: ['1girl', 'long_hair', 'prettysammy'],
      datasetUsage: {'1girl': 40, 'long hair': 30, 'prettysammy': 12},
      imageCount: 40,
    );

    testWidgets('tags missing from the dictionary are offered for adding', (
      tester,
    ) async {
      await tester.runAsync(() => prepare());
      await open(tester, workbench: workbench());

      // Only the one the dictionary cannot resolve: the other two are real
      // danbooru tags and adding them would shadow the real entries.
      expect(find.text('1 tags are not in the dictionary'), findsOneWidget);
      expect(find.text('prettysammy'), findsWidgets);

      await tester.tap(find.text('Add all as custom'));
      await tester.pumpAndSettle();

      expect(appState.tagDictionary.customEntries.map((e) => e.name), [
        'prettysammy',
      ]);
      // The prompt is gone once there is nothing left to prompt about.
      expect(find.text('1 tags are not in the dictionary'), findsNothing);
    });

    testWidgets('the banner can be dismissed without adding anything', (
      tester,
    ) async {
      await tester.runAsync(() => prepare());
      await open(tester, workbench: workbench());

      await tester.tap(find.text('Ignore'));
      await tester.pumpAndSettle();

      expect(find.text('1 tags are not in the dictionary'), findsNothing);
      expect(appState.tagDictionary.customEntries, isEmpty);
    });

    testWidgets('the list is narrowed to the dataset by default', (
      tester,
    ) async {
      await tester.runAsync(() => prepare());
      await open(tester, workbench: workbench());

      // The vocabulary in front of the user, busiest first — not the hundred
      // thousand tags danbooru knows.
      expect(find.text('3 results'), findsOneWidget);
      expect(find.text('By usage'), findsOneWidget);

      await tapToolbar(tester, 'This dataset only');

      // Widened: with nothing translated and nothing added, the whole-
      // dictionary view has nothing to list until something is searched for.
      expect(find.text('0 results'), findsOneWidget);
      expect(find.text('1girl'), findsNothing);
    });

    testWidgets('a tag the dataset lacks opens with the narrowing off', (
      tester,
    ) async {
      await tester.runAsync(() => prepare());
      // The path from the tag library, whose tags need not be in the dataset:
      // an editor whose tag the list beside it cannot show reads as a glitch.
      await open(tester, initialTag: 'blue_eyes', workbench: workbench());

      expect(find.text('blue_eyes'), findsWidgets);
      expect(find.text('1 results'), findsOneWidget);
    });

    testWidgets('the editor shows how much of the dataset uses the tag', (
      tester,
    ) async {
      await tester.runAsync(() => prepare());
      await open(tester, initialTag: 'long_hair', workbench: workbench());

      // 30 of 40 images: the number that decides whether a translation is
      // worth writing at all.
      expect(find.text('30 images · 75%'), findsOneWidget);
    });
  });

  group('new custom tag', () {
    Future<void> openForm(WidgetTester tester) async {
      await tester.tap(find.text('New tag'));
      await tester.pumpAndSettle();
    }

    testWidgets('adds the tag, its translation and its aliases at once', (
      tester,
    ) async {
      await tester.runAsync(() => prepare());
      await open(tester);
      await openForm(tester);

      await tester.enterText(
        find.widgetWithText(
          TextField,
          'danbooru spelling, e.g. my_character_(oc)',
        ),
        'pretty sammy (oc)',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Shown beside the tag in the UI'),
        '美少女战士萨米',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'prettysammy, sammy'),
        'prettysammy, sammy',
      );
      await tester.pump();
      await tapInForm(tester, find.widgetWithText(FilledButton, 'Add'));

      // Stored in danbooru's spelling whatever the user typed, so one entry
      // serves every caption style.
      final entry = appState.tagDictionary.customEntries.single;
      expect(entry.name, 'pretty_sammy_(oc)');
      expect(entry.aliases, ['prettysammy', 'sammy']);
      expect(entry.autocomplete, isTrue);
      expect(appState.tagTranslations.glossFor('pretty_sammy_(oc)'), '美少女战士萨米');
    });

    testWidgets('the autocomplete switch is carried into the entry', (
      tester,
    ) async {
      await tester.runAsync(() => prepare());
      await open(tester);
      await openForm(tester);

      await tester.enterText(
        find.widgetWithText(
          TextField,
          'danbooru spelling, e.g. my_character_(oc)',
        ),
        'quiet_tag',
      );
      await tapInForm(tester, find.byType(Switch));
      await tapInForm(tester, find.widgetWithText(FilledButton, 'Add'));

      expect(appState.tagDictionary.customEntries.single.autocomplete, isFalse);
      // Still in the dictionary, just not in the type-ahead.
      expect(appState.tagDictionary.lookup('quiet_tag'), isNotNull);
      expect(appState.tagDictionary.search('quiet'), isEmpty);
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

    await tapInForm(
      tester,
      find.widgetWithText(OutlinedButton, 'Remove from dictionary'),
    );
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(appState.tagDictionary.customEntries, isEmpty);
  });
}
