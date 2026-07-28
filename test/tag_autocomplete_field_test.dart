import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dataset_training_tool/l10n/app_localizations.dart';
import 'package:dataset_training_tool/services/tag_dictionary_service.dart';
import 'package:dataset_training_tool/theme/app_theme.dart';
import 'package:dataset_training_tool/widgets/tag_autocomplete_field.dart';

const _csv = '''
1girl,0,5113288,"1girls,sole_female"
long_hair,0,3000000,
long_sleeves,0,1500000,
hair_ornament,0,900000,
''';

void main() {
  late TagDictionaryService dictionary;
  late TextEditingController controller;
  late List<String> submitted;

  setUp(() {
    dictionary = TagDictionaryService();
    controller = TextEditingController();
    submitted = [];
  });

  tearDown(() => controller.dispose());

  Widget harness({TagInsertStyle style = const TagInsertStyle()}) {
    return MaterialApp(
      theme: buildAppTheme(Brightness.dark),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 300,
            child: TagAutocompleteField(
              controller: controller,
              dictionary: dictionary,
              insertStyle: style,
              onSubmitted: submitted.add,
            ),
          ),
        ),
      ),
    );
  }

  /// The dictionary parses on a real isolate, so it has to be built outside
  /// the fake-async zone.
  Future<void> load(WidgetTester tester) =>
      tester.runAsync(() => dictionary.loadCsv(_csv, full: true));

  testWidgets('typing opens a ranked list of matches', (tester) async {
    await load(tester);
    await tester.pumpWidget(harness());

    await tester.enterText(find.byType(TextField), 'long');
    await tester.pumpAndSettle();

    // Underscores become spaces by default, matching the AI tagger's default.
    expect(find.textContaining('long hair'), findsOneWidget);
    expect(find.textContaining('long sleeves'), findsOneWidget);
    expect(find.textContaining('hair ornament'), findsNothing);
  });

  testWidgets('Down then Enter completes; Enter alone does not', (
    tester,
  ) async {
    await load(tester);
    await tester.pumpWidget(harness());

    await tester.enterText(find.byType(TextField), 'long');
    await tester.pumpAndSettle();

    // Nothing is highlighted yet, so Enter must leave the typed text alone —
    // otherwise a deliberate new tag would be silently replaced.
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(controller.text, 'long');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(controller.text, 'long hair');
    expect(controller.selection.baseOffset, 'long hair'.length);
    // The completion consumed the Enter; it must not also submit.
    expect(submitted, isEmpty);
    expect(find.textContaining('long sleeves'), findsNothing);
  });

  testWidgets('Tab completes the first row without highlighting it', (
    tester,
  ) async {
    await load(tester);
    await tester.pumpWidget(harness());

    await tester.enterText(find.byType(TextField), 'long');
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();

    expect(controller.text, 'long hair');
  });

  testWidgets('only the segment under the caret is replaced', (tester) async {
    await load(tester);
    await tester.pumpWidget(harness());

    await tester.enterText(find.byType(TextField), 'smile, long');
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();

    // The space after the comma is the caller's spacing, not part of the tag.
    expect(controller.text, 'smile, long hair');
  });

  testWidgets('the insert style decides how the completion is spelled', (
    tester,
  ) async {
    await load(tester);
    await tester.pumpWidget(
      harness(style: const TagInsertStyle(underscoreToSpaces: false)),
    );

    await tester.enterText(find.byType(TextField), 'long');
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();

    expect(controller.text, 'long_hair');
  });

  testWidgets('clicking a row completes without the list closing first', (
    tester,
  ) async {
    await load(tester);
    await tester.pumpWidget(harness());

    await tester.enterText(find.byType(TextField), 'long');
    await tester.pumpAndSettle();

    // A focusable row would steal focus on tap-down, close the list on the
    // field's focus loss, and swallow its own tap.
    await tester.tap(find.textContaining('long sleeves'));
    await tester.pumpAndSettle();

    expect(controller.text, 'long sleeves');
  });

  testWidgets('an alias match shows the tag it resolves to', (tester) async {
    await load(tester);
    await tester.pumpWidget(harness());

    await tester.enterText(find.byType(TextField), 'sole');
    await tester.pumpAndSettle();

    expect(find.textContaining('1girl'), findsOneWidget);
    expect(find.textContaining('sole female'), findsOneWidget);
  });

  testWidgets('a local tag is inserted verbatim, not restyled', (tester) async {
    await load(tester);
    // Read out of the dataset, so already in the dataset's own spelling. The
    // default insert style turns underscores into spaces, which would invent
    // a tag that appears on no image.
    dictionary.setLocalTags(datasetUsage: {'myoc_trigger_word': 12});
    await tester.pumpWidget(harness());

    await tester.enterText(find.byType(TextField), 'myoc');
    await tester.pumpAndSettle();
    expect(find.textContaining('myoc_trigger_word'), findsOneWidget);
    // Local counts mean images in this dataset, so the row says which.
    expect(find.textContaining('12'), findsOneWidget);
    // Nothing to link to: a local tag has no danbooru wiki page.
    expect(find.byIcon(Icons.help_outline), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(controller.text, 'myoc_trigger_word');
  });

  testWidgets('Escape closes the list and Down reopens it', (tester) async {
    await load(tester);
    await tester.pumpWidget(harness());

    await tester.enterText(find.byType(TextField), 'long');
    await tester.pumpAndSettle();
    expect(find.textContaining('long hair'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.textContaining('long hair'), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(find.textContaining('long hair'), findsOneWidget);
  });

  testWidgets('a dictionary that loads late still matches what was typed', (
    tester,
  ) async {
    await tester.pumpWidget(harness());
    await tester.enterText(find.byType(TextField), 'long');
    await tester.pumpAndSettle();
    expect(find.textContaining('long hair'), findsNothing);

    await load(tester);
    await tester.pumpAndSettle();

    expect(find.textContaining('long hair'), findsOneWidget);
  });
}
