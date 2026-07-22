import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dataset_training_tool/app_state.dart';
import 'package:dataset_training_tool/l10n/app_localizations.dart';
import 'package:dataset_training_tool/services/settings_service.dart';
import 'package:dataset_training_tool/state/dataset_state.dart';
import 'package:dataset_training_tool/state/editor_session.dart';
import 'package:dataset_training_tool/state/tag_ops.dart';
import 'package:dataset_training_tool/theme/app_theme.dart';
import 'package:dataset_training_tool/views/panels/tag_library_panel.dart';

void main() {
  late AppState appState;
  late DatasetState dataset;
  late EditorSession session;
  late TagOps ops;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    appState = AppState(SettingsService());
    await appState.loadSettings();
    await appState.addCommonTags(['alpha', 'beta', 'gamma']);
    dataset = DatasetState();
    session = EditorSession()..autoSaveEnabled = false;
    ops = TagOps(dataset: dataset);
  });

  tearDown(() {
    session.dispose();
  });

  Widget harness() {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: appState),
        ChangeNotifierProvider.value(value: dataset),
        ChangeNotifierProvider.value(value: session),
        ChangeNotifierProvider.value(value: ops),
      ],
      child: MaterialApp(
        theme: buildAppTheme(Brightness.dark),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(
          body: Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(width: 340, child: TagLibraryPanel()),
          ),
        ),
      ),
    );
  }

  testWidgets('groups render as sections with ungrouped last', (tester) async {
    final g = await appState.createTagGroup('outfit', 0xFF6A9BDD);
    await appState.moveTagsToGroup(['alpha'], g.id);

    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    expect(find.text('outfit'), findsOneWidget);
    expect(find.text('Ungrouped'), findsOneWidget);
    expect(find.text('alpha'), findsOneWidget);
    expect(find.text('beta'), findsOneWidget);
  });

  testWidgets('group edit mode: select two tags, send via context menu',
      (tester) async {
    await appState.createTagGroup('outfit', 0xFF6A9BDD);

    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.checklist));
    await tester.pumpAndSettle();
    expect(
      find.text('Click to select, right-click to send to a group'),
      findsOneWidget,
    );

    // Selection works without an image loaded — edit mode is library-only.
    await tester.tap(find.text('alpha'));
    await tester.tap(find.text('beta'));
    await tester.pumpAndSettle();
    expect(find.text('2 selected · right-click to send to a group'),
        findsOneWidget);

    await tester.tap(find.text('alpha'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send to outfit'));
    await tester.pumpAndSettle();

    expect(appState.tagGroups.single.tags, ['alpha', 'beta']);
    expect(appState.ungroupedTags, ['gamma']);
    // Moved tags leave the selection.
    expect(
      find.text('Click to select, right-click to send to a group'),
      findsOneWidget,
    );
  });

  testWidgets('right-click on an unselected tag sends only that tag',
      (tester) async {
    final g = await appState.createTagGroup('outfit', 0xFF6A9BDD);

    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.checklist));
    await tester.pumpAndSettle();
    await tester.tap(find.text('alpha'));
    await tester.pumpAndSettle();

    // 'gamma' is not selected: the menu targets it alone.
    await tester.tap(find.text('gamma'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send to outfit'));
    await tester.pumpAndSettle();

    expect(appState.tagGroups.single.tags, ['gamma']);
    expect(appState.groupOfTag('alpha'), isNull);
    expect(g.tags, isEmpty); // the original instance is immutable
  });

  testWidgets('remove from group via context menu', (tester) async {
    final g = await appState.createTagGroup('outfit', 0xFF6A9BDD);
    await appState.moveTagsToGroup(['alpha'], g.id);

    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.checklist));
    await tester.pumpAndSettle();
    await tester.tap(find.text('alpha'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove from group'));
    await tester.pumpAndSettle();

    expect(appState.groupOfTag('alpha'), isNull);
    expect(appState.ungroupedTags, ['alpha', 'beta', 'gamma']);
  });

  testWidgets('clear library via the more menu keeps groups', (tester) async {
    final g = await appState.createTagGroup('outfit', 0xFF6A9BDD);
    await appState.moveTagsToGroup(['alpha'], g.id);

    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear library'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();

    expect(appState.commonTags, isEmpty);
    expect(appState.tagGroups.single.name, 'outfit');
    expect(appState.tagGroups.single.tags, isEmpty);
    // The emptied group still renders as a section.
    expect(find.text('outfit'), findsOneWidget);
  });

  testWidgets('group header delete button removes the group', (tester) async {
    final g = await appState.createTagGroup('outfit', 0xFF6A9BDD);
    await appState.moveTagsToGroup(['alpha'], g.id);

    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    // Only real group headers carry a delete button; ungrouped has none.
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();

    expect(appState.tagGroups, isEmpty);
    expect(appState.ungroupedTags, ['alpha', 'beta', 'gamma']);
  });

  testWidgets('group header context menu deletes the group', (tester) async {
    final g = await appState.createTagGroup('outfit', 0xFF6A9BDD);
    await appState.moveTagsToGroup(['alpha'], g.id);

    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    await tester.tap(find.text('outfit'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete group'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();

    expect(appState.tagGroups, isEmpty);
    expect(appState.ungroupedTags, ['alpha', 'beta', 'gamma']);
  });
}
