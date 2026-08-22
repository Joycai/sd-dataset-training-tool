import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dataset_training_tool/app_state.dart';
import 'package:dataset_training_tool/l10n/app_localizations.dart';
import 'package:dataset_training_tool/models/tag_group.dart';
import 'package:dataset_training_tool/models/tag_translation.dart';
import 'package:dataset_training_tool/services/settings_service.dart';
import 'package:dataset_training_tool/state/dataset_state.dart';
import 'package:dataset_training_tool/state/editor_session.dart';
import 'package:dataset_training_tool/state/tag_ops.dart';
import 'package:dataset_training_tool/state/workbench_layout.dart';
import 'package:dataset_training_tool/theme/app_theme.dart';
import 'package:dataset_training_tool/utils/tag_search.dart';
import 'package:dataset_training_tool/views/panels/tag_library_panel.dart';
import 'package:dataset_training_tool/widgets/panel_widgets.dart';

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
  late AppState appState;
  late DatasetState dataset;
  late EditorSession session;
  late TagOps ops;
  late Directory tempDir;

  // Real file IO stays in setUp: inside testWidgets' fake-async zone a disk
  // round-trip never completes and the test hangs until the suite times out.
  setUp(() async {
    resetTagSearchCache();
    SharedPreferences.setMockInitialValues({});
    appState = AppState(SettingsService());
    await appState.loadSettings();

    tempDir = await Directory.systemTemp.createTemp('tag_library_browse_');
    for (final name in ['001', '002']) {
      await File(p.join(tempDir.path, '$name.png')).writeAsBytes(_pngBytes);
    }
    await File(
      p.join(tempDir.path, '001.txt'),
    ).writeAsString('applied, stranger');
    await File(p.join(tempDir.path, '002.txt')).writeAsString('used_here');

    dataset = DatasetState();
    await dataset.scan(
      directoryPath: tempDir.path,
      recursive: false,
      captionExtension: '.txt',
    );
    session = EditorSession()..autoSaveEnabled = false;
    await session.load(File(p.join(tempDir.path, '001.png')), '.txt');
    ops = TagOps(dataset: dataset);
  });

  tearDown(() async {
    session.dispose();
    await tempDir.delete(recursive: true);
  });

  Widget harness({double width = 340, DatasetState? datasetOverride}) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: appState),
        ChangeNotifierProvider<DatasetState>.value(
          value: datasetOverride ?? dataset,
        ),
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
            child: SizedBox(width: width, child: const TagLibraryPanel()),
          ),
        ),
      ),
    );
  }

  group('collapsing', () {
    testWidgets('a group header folds and unfolds its tags', (tester) async {
      final g = await appState.createTagGroup('outfit', 0xFF6A9BDD);
      await appState.addCommonTags(['dress', 'skirt']);
      await appState.moveTagsToGroup(['dress'], g.id);

      await tester.pumpWidget(harness());
      await tester.pumpAndSettle();
      expect(find.text('dress'), findsOneWidget);

      await tester.tap(find.text('outfit'));
      await tester.pumpAndSettle();
      expect(find.text('dress'), findsNothing);
      // The other section is untouched.
      expect(find.text('skirt'), findsOneWidget);
      expect(appState.isTagGroupCollapsed(g.id), isTrue);

      await tester.tap(find.text('outfit'));
      await tester.pumpAndSettle();
      expect(find.text('dress'), findsOneWidget);
    });

    testWidgets('the toolbar folds and unfolds every section', (tester) async {
      final g = await appState.createTagGroup('outfit', 0xFF6A9BDD);
      await appState.addCommonTags(['dress', 'skirt']);
      await appState.moveTagsToGroup(['dress'], g.id);

      await tester.pumpWidget(harness());
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.unfold_less));
      await tester.pumpAndSettle();
      expect(find.text('dress'), findsNothing);
      expect(find.text('skirt'), findsNothing);
      expect(appState.isTagGroupCollapsed(kUngroupedSectionId), isTrue);

      // The button flips once everything is folded.
      await tester.tap(find.byIcon(Icons.unfold_more));
      await tester.pumpAndSettle();
      expect(find.text('dress'), findsOneWidget);
      expect(find.text('skirt'), findsOneWidget);
    });

    testWidgets('a folded group survives a rebuild from storage', (
      tester,
    ) async {
      final g = await appState.createTagGroup('outfit', 0xFF6A9BDD);
      await appState.addCommonTags(['dress']);
      await appState.moveTagsToGroup(['dress'], g.id);
      await appState.setTagGroupCollapsed(g.id, true);

      // A fresh AppState reading the same preferences is what a restart is.
      final reloaded = AppState(SettingsService());
      await reloaded.loadSettings();
      appState = reloaded;

      await tester.pumpWidget(harness());
      await tester.pumpAndSettle();
      expect(find.text('outfit'), findsOneWidget);
      expect(find.text('dress'), findsNothing);
    });
  });

  group('row cap', () {
    testWidgets('a long group cuts to two rows and opens on demand', (
      tester,
    ) async {
      await appState.addCommonTags([
        for (var i = 0; i < 12; i++) 'tag_number_$i',
      ]);

      await tester.pumpWidget(harness());
      await tester.pumpAndSettle();

      // Two rows of a 340px panel hold nowhere near 12 chips. Cut chips stay
      // in the tree unpainted, so "gone" means "not reachable by a tap".
      expect(find.textContaining('more'), findsOneWidget);
      expect(find.text('tag_number_11').hitTestable(), findsNothing);

      await tester.tap(find.textContaining('more'));
      await tester.pumpAndSettle();
      expect(find.text('tag_number_11').hitTestable(), findsOneWidget);
      expect(find.textContaining('more'), findsNothing);
      expect(find.text('Show less'), findsOneWidget);

      // The expanded group pushes the link past the panel's viewport.
      await tester.ensureVisible(find.text('Show less'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Show less'));
      await tester.pumpAndSettle();
      expect(find.text('tag_number_11').hitTestable(), findsNothing);
    });

    testWidgets('a short group shows no overflow affordance', (tester) async {
      await appState.addCommonTags(['a', 'b']);

      await tester.pumpWidget(harness());
      await tester.pumpAndSettle();
      expect(find.textContaining('more'), findsNothing);
    });
  });

  group('status filter', () {
    testWidgets('used / unused split the library by the current image', (
      tester,
    ) async {
      await appState.addCommonTags(['applied', 'absent']);

      await tester.pumpWidget(harness());
      await tester.pumpAndSettle();
      expect(find.text('Used 1'), findsOneWidget);
      expect(find.text('Unused 1'), findsOneWidget);

      await tester.tap(find.text('Used 1'));
      await tester.pumpAndSettle();
      expect(find.text('applied'), findsOneWidget);
      expect(find.text('absent'), findsNothing);

      await tester.tap(find.text('Unused 1'));
      await tester.pumpAndSettle();
      expect(find.text('applied'), findsNothing);
      expect(find.text('absent'), findsOneWidget);
    });

    testWidgets('the new filter shows only what the image brought', (
      tester,
    ) async {
      await appState.addCommonTags(['applied']);

      await tester.pumpWidget(harness());
      await tester.pumpAndSettle();

      await tester.tap(find.text('New 1'));
      await tester.pumpAndSettle();
      expect(find.text('stranger'), findsOneWidget);
      expect(find.text('applied'), findsNothing);
    });

    testWidgets('a filter with nothing left says so', (tester) async {
      await appState.addCommonTags(['alpha']);

      await tester.pumpWidget(harness());
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'zzz');
      await tester.pumpAndSettle();

      expect(find.text('No tag matches the filter.'), findsOneWidget);
    });
  });

  group('dataset scope', () {
    testWidgets('the switch hides library tags the dataset never uses', (
      tester,
    ) async {
      await appState.addCommonTags(['used_here', 'elsewhere']);

      await tester.pumpWidget(harness());
      await tester.pumpAndSettle();
      expect(find.text('elsewhere'), findsOneWidget);

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      expect(find.text('used_here'), findsOneWidget);
      expect(find.text('elsewhere'), findsNothing);
      expect(find.text('1 library tags hidden'), findsOneWidget);
    });

    testWidgets('with no dataset open the switch is not offered', (
      tester,
    ) async {
      await appState.addCommonTags(['alpha']);

      // A DatasetState that never scanned: no tag index, nothing to scope to.
      await tester.pumpWidget(harness(datasetOverride: DatasetState()));
      await tester.pumpAndSettle();
      expect(find.byType(Switch), findsNothing);
    });
  });

  group('translation search', () {
    testWidgets('a tag is reachable by its gloss and by pinyin', (
      tester,
    ) async {
      await appState.addCommonTags(['long_hair', 'skirt']);
      // The glossary persists to disk; inside the fake-async zone that write
      // would never complete.
      await tester.runAsync(
        () => appState.tagTranslations.upsert(
          const TagTranslation(tag: 'long_hair', text: '长发'),
        ),
      );

      await tester.pumpWidget(harness());
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, '长发');
      await tester.pumpAndSettle();
      expect(find.text('long_hair'), findsOneWidget);
      expect(find.text('skirt'), findsNothing);

      await tester.enterText(find.byType(TextField).first, 'cf');
      await tester.pumpAndSettle();
      expect(find.text('long_hair'), findsOneWidget);
      expect(find.text('skirt'), findsNothing);
    });
  });

  group('organize mode', () {
    Future<void> enterOrganize(WidgetTester tester) async {
      await tester.tap(find.byIcon(Icons.checklist));
      await tester.pumpAndSettle();
    }

    testWidgets('shift-click selects a range', (tester) async {
      await appState.addCommonTags(['a', 'b', 'c', 'd']);

      await tester.pumpWidget(harness());
      await tester.pumpAndSettle();
      await enterOrganize(tester);

      await tester.tap(find.text('a'));
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.tap(find.text('c'));
      await tester.pumpAndSettle();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);

      expect(find.text('3 tags selected'), findsOneWidget);
    });

    testWidgets('the bottom bar moves the selection into a group', (
      tester,
    ) async {
      await appState.createTagGroup('outfit', 0xFF6A9BDD);
      await appState.addCommonTags(['dress', 'skirt', 'shoes']);

      await tester.pumpWidget(harness());
      await tester.pumpAndSettle();
      await enterOrganize(tester);

      await tester.tap(find.text('dress'));
      await tester.tap(find.text('skirt'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Move to group'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Send to outfit'));
      await tester.pumpAndSettle();

      expect(appState.tagGroups.single.tags, ['dress', 'skirt']);
      expect(appState.ungroupedTags, ['shoes']);
      expect(find.text('Nothing selected'), findsOneWidget);
    });

    testWidgets('the bottom bar deletes the selection after confirming', (
      tester,
    ) async {
      await appState.addCommonTags(['a', 'b', 'c']);

      await tester.pumpWidget(harness());
      await tester.pumpAndSettle();
      await enterOrganize(tester);

      await tester.tap(find.text('a'));
      await tester.tap(find.text('b'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(find.text('Remove 2 tags from the library?'), findsOneWidget);
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();

      expect(appState.commonTags, ['c']);
    });

    testWidgets('merge needs two tags and collapses them into one', (
      tester,
    ) async {
      await appState.addCommonTags(['blue dress', 'blue_dress', 'skirt']);

      await tester.pumpWidget(harness());
      await tester.pumpAndSettle();
      await enterOrganize(tester);

      // One selected: merging would be a rename of a tag into itself.
      await tester.tap(find.text('blue dress'));
      await tester.pumpAndSettle();
      final mergeButton = tester.widget<OutlinedButton>(
        find.ancestor(
          of: find.text('Merge into…'),
          matching: find.byType(OutlinedButton),
        ),
      );
      expect(mergeButton.onPressed, isNull);

      await tester.tap(find.text('blue_dress'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Merge into…'));
      await tester.pumpAndSettle();

      // Prefilled with the first selected tag; confirm as-is.
      expect(find.text('Merging 2 tags'), findsOneWidget);
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();

      expect(appState.commonTags, ['blue dress', 'skirt']);
    });

    testWidgets('dragging a selection onto a header files it', (tester) async {
      await appState.createTagGroup('outfit', 0xFF6A9BDD);
      await appState.addCommonTags(['dress', 'skirt']);

      await tester.pumpWidget(harness());
      await tester.pumpAndSettle();
      await enterOrganize(tester);

      await tester.tap(find.text('dress'));
      await tester.pumpAndSettle();

      // Measured before the drag starts: childWhenDragging reflows the rows
      // the moment the pointer is claimed.
      final start = tester.getCenter(find.text('dress'));
      final target = tester.getCenter(find.text('outfit'));
      final gesture = await tester.startGesture(start);
      await tester.pump(const Duration(milliseconds: 100));
      // One move past the touch slop so the drag wins against the chip's tap.
      await gesture.moveBy(const Offset(0, 24));
      await tester.pump();
      await gesture.moveTo(target);
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(appState.tagGroups.single.tags, ['dress']);
    });

    testWidgets('leaving organize mode drops the selection', (tester) async {
      await appState.addCommonTags(['a', 'b']);

      await tester.pumpWidget(harness());
      await tester.pumpAndSettle();
      await enterOrganize(tester);
      await tester.tap(find.text('a'));
      await tester.pumpAndSettle();
      expect(find.text('1 tag selected'), findsOneWidget);

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.text('Organize mode'), findsNothing);

      await enterOrganize(tester);
      expect(find.text('Nothing selected'), findsOneWidget);
    });
  });

  group('inactive tab', () {
    testWidgets('the hidden tab builds no chips', (tester) async {
      await appState.addCommonTags(['dress']);

      await tester.pumpWidget(harness());
      await tester.pumpAndSettle();

      // Library tab in front: its chips exist, the dataset tab's do not —
      // 'used_here' lives only in 002.txt's caption, and with the old
      // keep-both-alive IndexedStack it was mounted (and laid out) here.
      expect(find.text('dress'), findsOneWidget);
      expect(find.text('used_here'), findsNothing);

      await tester.tap(find.byType(PanelTab).at(1));
      await tester.pumpAndSettle();
      expect(find.text('used_here'), findsOneWidget);
      expect(find.text('dress'), findsNothing);
    });

    testWidgets('the library filter text survives a tab round-trip', (
      tester,
    ) async {
      await appState.addCommonTags(['dress', 'skirt']);

      await tester.pumpWidget(harness());
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'dre');
      await tester.pumpAndSettle();
      expect(find.text('dress'), findsOneWidget);
      expect(find.text('skirt'), findsNothing);

      await tester.tap(find.byType(PanelTab).at(1));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(PanelTab).at(0));
      await tester.pumpAndSettle();

      // The State object survived the shrink; the filter still narrows and
      // the field still shows what was typed.
      expect(find.text('dress'), findsOneWidget);
      expect(find.text('skirt'), findsNothing);
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller?.text,
        'dre',
      );
    });
  });
}
