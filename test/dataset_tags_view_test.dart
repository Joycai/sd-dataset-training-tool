import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dataset_training_tool/app_state.dart';
import 'package:dataset_training_tool/l10n/app_localizations.dart';
import 'package:dataset_training_tool/models/tag_filter.dart';
import 'package:dataset_training_tool/services/settings_service.dart';
import 'package:dataset_training_tool/state/dataset_state.dart';
import 'package:dataset_training_tool/state/editor_session.dart';
import 'package:dataset_training_tool/state/tag_ops.dart';
import 'package:dataset_training_tool/state/workbench_layout.dart';
import 'package:dataset_training_tool/theme/app_theme.dart';
import 'package:dataset_training_tool/views/panels/tag_library_panel.dart';

// 1x1 transparent PNG.
const _pngBytes = [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x62, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
];

void main() {
  late Directory tempDir;
  late DatasetState dataset;
  late EditorSession session;
  late TagOps ops;
  late AppState appState;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('dataset_tags_view_');
    for (final name in ['001', '002']) {
      await File(p.join(tempDir.path, '$name.png')).writeAsBytes(_pngBytes);
    }
    await File(p.join(tempDir.path, '001.txt')).writeAsString('alpha, beta');
    await File(p.join(tempDir.path, '002.txt')).writeAsString('beta');

    dataset = DatasetState();
    await dataset.scan(
      directoryPath: tempDir.path,
      recursive: false,
      captionExtension: '.txt',
    );
    session = EditorSession()..autoSaveEnabled = false;
    ops = TagOps(dataset: dataset);
    appState = AppState(SettingsService());
    await appState.loadSettings();
  });

  tearDown(() async {
    session.dispose();
    await tempDir.delete(recursive: true);
  });

  Widget harness() {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: appState),
        ChangeNotifierProvider.value(value: dataset),
        ChangeNotifierProvider.value(value: session),
        ChangeNotifierProvider.value(value: ops),
        ChangeNotifierProvider(create: (_) => WorkbenchLayout()),
      ],
      child: MaterialApp(
        theme: buildAppTheme(Brightness.dark),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(width: 340, child: TagLibraryPanel()),
          ),
        ),
      ),
    );
  }

  Future<void> openDatasetTab(WidgetTester tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();
    // The tab label carries its tag count ("Dataset  12") since the views
    // dropped their own title rows.
    await tester.tap(find.textContaining('Dataset').first);
    await tester.pumpAndSettle();
  }

  Future<void> rightClick(WidgetTester tester, Finder finder) async {
    await tester.tap(finder, buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
  }

  testWidgets('dataset tab lists tags with counts', (tester) async {
    await openDatasetTab(tester);

    expect(find.text('alpha'), findsOneWidget);
    expect(find.text('beta'), findsOneWidget);
    // beta appears in both captions, alpha in one.
    expect(find.text('2'), findsWidgets);
    expect(find.text('1'), findsWidgets);
  });

  testWidgets('context menu builds the gallery filter expression', (
    tester,
  ) async {
    await openDatasetTab(tester);

    await rightClick(tester, find.text('beta'));
    expect(find.text('Only images with this tag'), findsOneWidget);
    await tester.tap(find.text('Only images with this tag'));
    await tester.pumpAndSettle();

    var conditions = dataset.tagFilterExpression.children
        .whereType<TagFilterCondition>()
        .toList();
    expect(conditions.single.tag, 'beta');
    expect(conditions.single.exclude, isFalse);
    // The expression panel appears with the condition chip ('beta' also
    // shows in the tag list below, hence two).
    expect(find.text('Gallery filter'), findsOneWidget);
    expect(find.text('beta'), findsNWidgets(2));

    // A second tag chains with AND: has beta && !has alpha -> only 002.
    await rightClick(tester, find.text('alpha'));
    await tester.tap(find.text('Only images without this tag'));
    await tester.pumpAndSettle();
    conditions = dataset.tagFilterExpression.children
        .whereType<TagFilterCondition>()
        .toList();
    expect(conditions, hasLength(2));
    expect(conditions.last.tag, 'alpha');
    expect(conditions.last.exclude, isTrue);
    expect(find.text('AND'), findsOneWidget);
    expect(dataset.visibleFiles.map((f) => p.basename(f.path)), ['002.png']);

    // Re-filtering the same tag flips its role instead of duplicating.
    // ('alpha' now also renders as a panel chip; the list chip is last.)
    await rightClick(tester, find.text('alpha').last);
    await tester.tap(find.text('Only images with this tag'));
    await tester.pumpAndSettle();
    conditions = dataset.tagFilterExpression.children
        .whereType<TagFilterCondition>()
        .toList();
    expect(conditions, hasLength(2));
    expect(conditions.last.exclude, isFalse);
    expect(dataset.visibleFiles.map((f) => p.basename(f.path)), ['001.png']);

    // The header button clears the whole expression.
    await tester.tap(find.byIcon(Icons.filter_alt_off_outlined));
    await tester.pumpAndSettle();
    expect(dataset.tagFilterActive, isFalse);
    expect(find.text('Gallery filter'), findsNothing);
    expect(dataset.visibleFiles, hasLength(2));
  });

  testWidgets('expression panel edits: toggle op, toggle role, remove', (
    tester,
  ) async {
    await openDatasetTab(tester);

    // beta include + alpha include -> AND matches only 001.
    await rightClick(tester, find.text('beta'));
    await tester.tap(find.text('Only images with this tag'));
    await tester.pumpAndSettle();
    await rightClick(tester, find.text('alpha'));
    await tester.tap(find.text('Only images with this tag'));
    await tester.pumpAndSettle();
    expect(dataset.visibleFiles.map((f) => p.basename(f.path)), ['001.png']);

    // Toggle the group op: OR matches both.
    await tester.tap(find.text('AND'));
    await tester.pumpAndSettle();
    expect(find.text('OR'), findsOneWidget);
    expect(dataset.visibleFiles, hasLength(2));

    // Toggle alpha's role to exclude: !alpha || beta still matches both;
    // back to AND drops 001.
    final alphaChip = find.ancestor(
      of: find.text('alpha').first,
      matching: find.byType(Row),
    );
    await tester.tap(
      find
          .descendant(
            of: alphaChip,
            matching: find.byIcon(Icons.filter_alt_outlined),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('OR'));
    await tester.pumpAndSettle();
    expect(dataset.visibleFiles.map((f) => p.basename(f.path)), ['002.png']);

    // Remove the alpha condition: only the beta include remains.
    await tester.tap(
      find.descendant(of: alphaChip, matching: find.byIcon(Icons.close)).first,
    );
    await tester.pumpAndSettle();
    expect(
      dataset.tagFilterExpression.children
          .whereType<TagFilterCondition>()
          .single
          .tag,
      'beta',
    );
    expect(dataset.visibleFiles, hasLength(2));
  });

  testWidgets('add-tags dialog: position pills, index validation, scope', (
    tester,
  ) async {
    await openDatasetTab(tester);

    await tester.tap(find.byIcon(Icons.playlist_add));
    await tester.pumpAndSettle();
    expect(find.text('Add tags to all images'), findsOneWidget);
    // No gallery filter active: the scope checkbox is absent.
    expect(find.byType(Checkbox), findsNothing);
    expect(find.textContaining('added to 2 images'), findsOneWidget);

    // Empty input disables Apply.
    TextButton applyButton() =>
        tester.widget<TextButton>(find.widgetWithText(TextButton, 'Apply'));
    expect(applyButton().onPressed, isNull);

    await tester.enterText(find.byType(TextField).last, 'new tag');
    await tester.pumpAndSettle();
    expect(applyButton().onPressed, isNotNull);

    // "At position" needs a valid 1-based index before Apply enables.
    await tester.tap(find.text('At position'));
    await tester.pumpAndSettle();
    expect(applyButton().onPressed, isNull);
    await tester.enterText(find.byType(TextField).last, '2');
    await tester.pumpAndSettle();
    expect(applyButton().onPressed, isNotNull);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(ops.canUndo, isFalse);
  });

  testWidgets('add-tags dialog offers the filtered scope when filtering', (
    tester,
  ) async {
    await openDatasetTab(tester);

    // Filter down to the one image with alpha, then open the dialog.
    await rightClick(tester, find.text('alpha'));
    await tester.tap(find.text('Only images with this tag'));
    await tester.pumpAndSettle();
    expect(dataset.visibleFiles, hasLength(1));

    await tester.tap(find.byIcon(Icons.playlist_add));
    await tester.pumpAndSettle();
    expect(find.text('Only the 1 filtered images'), findsOneWidget);
    expect(find.textContaining('added to 2 images'), findsOneWidget);

    // Checking the scope box narrows the target count readout.
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    expect(find.textContaining('added to 1 images'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(ops.canUndo, isFalse);
  });

  // The disk effects of delete/replace/undo are covered by tag_ops_test.dart;
  // the widget tests stay UI-only because TagOps does real file IO, which can
  // never complete inside the widget test's fake-async zone.
  testWidgets('global delete shows a confirmation with the image count', (
    tester,
  ) async {
    await openDatasetTab(tester);

    await rightClick(tester, find.text('beta'));
    await tester.tap(find.text('Delete from all images'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Remove "beta" from 2 images'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    // Cancel touches nothing.
    expect(ops.canUndo, isFalse);
    expect(
      dataset.datasetTags.map((t) => '${t.tag}:${t.count}'),
      contains('beta:2'),
    );
  });

  testWidgets('replace dialog prefills the tag and validates input', (
    tester,
  ) async {
    await openDatasetTab(tester);

    await rightClick(tester, find.text('beta'));
    await tester.tap(find.text('Replace / append…'));
    await tester.pumpAndSettle();

    // Prefilled with the tag in replace mode.
    final field = find.byType(TextField).last;
    expect(tester.widget<TextField>(field).controller?.text, 'beta');

    // Emptying the input disables Apply.
    await tester.enterText(field, '');
    await tester.pumpAndSettle();
    final applyButton = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Apply'),
    );
    expect(applyButton.onPressed, isNull);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(ops.canUndo, isFalse);
  });

  testWidgets(
    'context menu carries the library/dictionary section, unified with '
    'the tag library panel',
    (tester) async {
      await openDatasetTab(tester);

      await rightClick(tester, find.text('beta'));
      expect(find.text('Danbooru wiki'), findsOneWidget);
      expect(find.text('Danbooru posts'), findsOneWidget);
      expect(find.text('Open in dictionary…'), findsOneWidget);
      // Neither tag is in the (empty) library yet.
      expect(find.text('Add to library'), findsOneWidget);
    },
  );

  testWidgets('add to library from the dataset tab adds the tag', (
    tester,
  ) async {
    await appState.addCommonTags(['alpha']);
    await openDatasetTab(tester);

    // 'alpha' is already in the library: no add-to-library entry.
    await rightClick(tester, find.text('alpha'));
    expect(find.text('Add to library'), findsNothing);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    // 'beta' is not: the entry adds it.
    await rightClick(tester, find.text('beta'));
    expect(find.text('Add to library'), findsOneWidget);
    await tester.tap(find.text('Add to library'));
    await tester.pumpAndSettle();
    expect(appState.commonTags, contains('beta'));
  });

  BoxDecoration decorationOf(WidgetTester tester, String tag) {
    final container = tester.widget<Container>(
      find.ancestor(of: find.text(tag), matching: find.byType(Container)).first,
    );
    return container.decoration! as BoxDecoration;
  }

  testWidgets(
    'applied dataset tags take their library group color instead of a '
    'flat green',
    (tester) async {
      await appState.addCommonTags(['alpha']);
      final group = await appState.createTagGroup('outfit', 0xFF6A9BDD);
      await appState.moveTagsToGroup(['alpha'], group.id);
      await tester.runAsync(
        () => session.load(File(p.join(tempDir.path, '001.png')), '.txt'),
      );

      await openDatasetTab(tester);

      // 'alpha' and 'beta' are both applied (session is on 001.png, whose
      // caption is "alpha, beta"); only 'alpha' is grouped.
      final grouped = decorationOf(tester, 'alpha');
      final ungrouped = decorationOf(tester, 'beta');
      expect(
        (grouped.border! as Border).top.color,
        const Color(0xFF6A9BDD).withAlpha(128),
      );
      expect(
        (ungrouped.border! as Border).top.color,
        isNot((grouped.border! as Border).top.color),
      );
    },
  );

  testWidgets(
    'a grouped tag not on the current image gets a colored outline, not a '
    'filled chip',
    (tester) async {
      await appState.addCommonTags(['alpha']);
      final group = await appState.createTagGroup('outfit', 0xFF6A9BDD);
      await appState.moveTagsToGroup(['alpha'], group.id);
      // 002.png's caption is "beta" only — 'alpha' is in the dataset (via
      // 001.txt) but not applied to this image.
      await tester.runAsync(
        () => session.load(File(p.join(tempDir.path, '002.png')), '.txt'),
      );

      await openDatasetTab(tester);

      final decoration = decorationOf(tester, 'alpha');
      // The "applied" branch tints at alpha 128; unapplied-but-grouped uses
      // a distinct 140 so the two states never collide on the same value.
      expect(
        (decoration.border! as Border).top.color,
        const Color(0xFF6A9BDD).withAlpha(140),
      );
    },
  );
}
