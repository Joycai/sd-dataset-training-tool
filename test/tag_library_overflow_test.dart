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
import 'package:dataset_training_tool/state/workbench_layout.dart';
import 'package:dataset_training_tool/theme/app_theme.dart';
import 'package:dataset_training_tool/views/panels/tag_library_panel.dart';

/// The panel gained three bands of chrome — status pills, the dataset switch,
/// the organize action bar — on top of a toolbar that was already tight. All
/// of them have to survive the narrowest column the workbench allows (200px,
/// `_panelMinWidth`) in both locales, and none of it is obvious by reading the
/// widget tree.
void main() {
  const widths = [200.0, 240.0, 280.0, 340.0, 480.0];
  const locales = [Locale('en'), Locale('zh')];

  late AppState appState;
  late DatasetState dataset;
  late EditorSession session;
  late TagOps ops;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    appState = AppState(SettingsService());
    await appState.loadSettings();
    dataset = DatasetState();
    session = EditorSession()..autoSaveEnabled = false;
    ops = TagOps(dataset: dataset);
  });

  tearDown(() => session.dispose());

  Widget harness(double width, Locale locale) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: appState),
        ChangeNotifierProvider.value(value: dataset),
        ChangeNotifierProvider.value(value: session),
        ChangeNotifierProvider.value(value: ops),
        ChangeNotifierProvider(create: (_) => WorkbenchLayout()),
      ],
      child: MaterialApp(
        locale: locale,
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

  for (final locale in locales) {
    for (final width in widths) {
      testWidgets('${locale.languageCode} @ ${width.toInt()}px: no overflow', (
        tester,
      ) async {
        // A long group name and a long tag: the two things a user supplies
        // that the layout cannot bound.
        final group = await appState.createTagGroup(
          'a rather long group name',
          0xFF6A9BDD,
        );
        await appState.addCommonTags([
          'a_very_long_tag_name_that_will_not_fit',
          'short',
          'other',
        ]);
        await appState.moveTagsToGroup([
          'a_very_long_tag_name_that_will_not_fit',
        ], group.id);

        await tester.pumpWidget(harness(width, locale));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        // Organize mode adds the header strip and the three-button bar.
        await tester.tap(find.byIcon(Icons.checklist));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        // With a selection the bar's buttons are enabled and at full width.
        await tester.tap(find.text('short'));
        await tester.tap(find.text('other'));
        await tester.pumpAndSettle();
      });
    }
  }
}
