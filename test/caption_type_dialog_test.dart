import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dataset_training_tool/app_state.dart';
import 'package:dataset_training_tool/l10n/app_localizations.dart';
import 'package:dataset_training_tool/models/caption_type.dart';
import 'package:dataset_training_tool/services/settings_service.dart';
import 'package:dataset_training_tool/theme/app_theme.dart';
import 'package:dataset_training_tool/views/panels/caption_type_dialog.dart';

void main() {
  late AppState appState;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    appState = AppState(SettingsService());
    await appState.loadSettings();
  });

  tearDown(() => appState.dispose());

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: appState,
        child: MaterialApp(
          theme: buildAppTheme(Brightness.dark),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showCaptionTypesDialog(context),
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

  /// The extension field of the row at [index] (the only mono, centered
  /// fields in the dialog).
  Finder extensionField(int index) => find
      .byWidgetPredicate(
        (w) => w is TextField && w.textAlign == TextAlign.center,
      )
      .at(index);

  Finder nameField(int index) => find
      .byWidgetPredicate(
        (w) => w is TextField && w.textAlign != TextAlign.center,
      )
      .at(index);

  testWidgets('shows the columns and marks the default row', (tester) async {
    await open(tester);

    expect(find.text('Caption Types'), findsOneWidget);
    expect(find.text('Format'), findsOneWidget);
    expect(find.text('Extension'), findsOneWidget);
    expect(find.text('Default'), findsOneWidget);
    expect(find.text('WD14 tags'), findsOneWidget);
    // The default type reads as on and cannot be turned off.
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
    expect(
      find.ancestor(
        of: find.byType(Switch),
        matching: find.byType(IgnorePointer),
      ),
      findsWidgets,
    );
  });

  testWidgets('add + done writes every row through in one update', (
    tester,
  ) async {
    await open(tester);

    await tester.tap(find.text('Add type'));
    await tester.pumpAndSettle();
    await tester.enterText(nameField(1), 'nlp');
    await tester.enterText(extensionField(1), 'ntxt');
    // Still buffered: nothing reaches the app state before Done.
    expect(appState.captionTypes.length, 1);

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(find.text('Caption Types'), findsNothing);
    expect(appState.captionTypes.length, 2);
    expect(appState.captionTypes[1].name, 'nlp');
    expect(appState.captionTypes[1].extension, '.ntxt');
  });

  testWidgets('cancel discards edits', (tester) async {
    await open(tester);

    await tester.enterText(extensionField(0), 'caption');
    await tester.tap(find.text('Add type'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(appState.captionTypes.single.extension, '.txt');
  });

  testWidgets('a rejected extension keeps the dialog open', (tester) async {
    await open(tester);

    await tester.tap(find.text('Add type'));
    await tester.pumpAndSettle();
    await tester.enterText(extensionField(1), '.png');
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(find.text('Not a usable caption extension'), findsOneWidget);
    expect(find.text('Caption Types'), findsOneWidget);
    expect(appState.captionTypes.length, 1);

    // A duplicate is reported the same way.
    await tester.enterText(extensionField(1), 'txt');
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(
      find.text('This extension is already used by another caption type'),
      findsOneWidget,
    );
    expect(appState.captionTypes.length, 1);
  });

  testWidgets('the format menu picks a format', (tester) async {
    await open(tester);

    await tester.tap(find.text('WD14 tags'));
    await tester.pumpAndSettle();
    // The menu shows every format with its summary.
    expect(
      find.text('Structured document · read-only tag view'),
      findsOneWidget,
    );

    await tester.tap(find.text('Anima JSON'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(appState.captionTypes.single.format, CaptionFormat.json);
  });
}
