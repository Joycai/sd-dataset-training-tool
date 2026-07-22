import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dataset_training_tool/l10n/app_localizations.dart';
import 'package:dataset_training_tool/services/ai_tagger_service.dart';
import 'package:dataset_training_tool/services/settings_service.dart';
import 'package:dataset_training_tool/state/ai_tagger_state.dart';
import 'package:dataset_training_tool/theme/app_theme.dart';
import 'package:dataset_training_tool/views/panels/ai_params_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Map<String, dynamic> model(
    String name, {
    String category = 'tag',
    bool recommended = false,
    bool uncensored = false,
    bool legacy = false,
    double vram = 0,
    String description = '',
  }) =>
      {
        'ModelName': name,
        'SupportedVideo': false,
        'RepositoryLink': '',
        'Category': category,
        'Recommended': recommended,
        'Uncensored': uncensored,
        'Legacy': legacy,
        'VramGB': vram,
        'Description': description,
        'Advice': '',
      };

  final configResponse = {
    'Interrogators': [
      model('SmilingWolf/wd-eva02-large-tagger-v3',
          recommended: true, vram: 2, description: 'EVA02 tagger'),
      model('SmilingWolf/wd-vit-tagger-v3', vram: 1),
      model('SmilingWolf/wd-v1-4-vit-tagger', legacy: true, vram: 1),
      model('DeepDanbooru', legacy: true, vram: 1),
      model('fancyfeast/llama-joycaption-beta-one-hf-llava',
          category: 'caption', uncensored: true, vram: 18),
      model('BLIP', category: 'caption', legacy: true, vram: 2),
    ],
    'Editors': <Map<String, dynamic>>[],
    'Translators': <Map<String, dynamic>>[],
  };

  late AiTaggerState ai;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    final client = MockClient((request) async {
      if (request.url.path == '/getconfig') {
        return http.Response(jsonEncode(configResponse), 200,
            headers: {'content-type': 'application/json'});
      }
      return http.Response('not found', 404);
    });
    ai = AiTaggerState(
      SettingsService(),
      service: AiTaggerService(client: client),
    );
  });

  Widget harness() {
    return MaterialApp(
      theme: buildAppTheme(Brightness.dark),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showAiParamsDialog(context, ai),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> openDialogAndMenu(WidgetTester tester) async {
    await tester.runAsync(ai.refreshModels);
    await tester.pumpWidget(harness());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    // Open the model picker menu (the closed field shows the full name).
    await tester.tap(find.text('SmilingWolf/wd-eva02-large-tagger-v3'));
    await tester.pumpAndSettle();
  }

  testWidgets('menu groups models and collapses legacy ones', (tester) async {
    await openDialogAndMenu(tester);
    final l10n = AppLocalizations.of(
        tester.element(find.byType(AlertDialog)))!;

    // Section headers present.
    expect(find.text(l10n.aiModelGroupTag), findsOneWidget);
    expect(find.text(l10n.aiModelGroupCaption), findsOneWidget);

    // Current models visible (short names, org prefix stripped).
    expect(find.text('wd-eva02-large-tagger-v3'), findsOneWidget);
    expect(find.text('wd-vit-tagger-v3'), findsOneWidget);
    expect(find.text('llama-joycaption-beta-one-hf-llava'), findsOneWidget);

    // Legacy models hidden behind per-section collapse rows.
    expect(find.text('wd-v1-4-vit-tagger'), findsNothing);
    expect(find.text('BLIP'), findsNothing);
    expect(find.text(l10n.aiModelLegacyGroup(2)), findsOneWidget);
    expect(find.text(l10n.aiModelLegacyGroup(1)), findsOneWidget);

    // Badges.
    expect(find.text(l10n.aiBadgeRecommended), findsWidgets);
    expect(find.text(l10n.aiBadgeUncensored), findsOneWidget);

    // Expanding the tag-section legacy row reveals its models.
    await tester.tap(find.text(l10n.aiModelLegacyGroup(2)));
    await tester.pumpAndSettle();
    expect(find.text('wd-v1-4-vit-tagger'), findsOneWidget);
    expect(find.text('DeepDanbooru'), findsOneWidget);
    expect(find.text('BLIP'), findsNothing);
  });

  testWidgets('filter narrows the list and surfaces legacy matches',
      (tester) async {
    await openDialogAndMenu(tester);
    final l10n = AppLocalizations.of(
        tester.element(find.byType(AlertDialog)))!;

    await tester.enterText(
        find.widgetWithText(TextField, l10n.aiModelFilterHint), 'v1-4');
    await tester.pumpAndSettle();

    // Legacy match shows inline; non-matches and collapse rows are gone.
    expect(find.text('wd-v1-4-vit-tagger'), findsOneWidget);
    expect(find.text('wd-vit-tagger-v3'), findsNothing);
    expect(find.text(l10n.aiModelGroupCaption), findsNothing);

    await tester.enterText(
        find.widgetWithText(TextField, 'v1-4'), 'zzz-no-such');
    await tester.pumpAndSettle();
    expect(find.text(l10n.aiModelFilterNoMatch), findsOneWidget);
  });

  testWidgets('picking a model updates state and closes the menu',
      (tester) async {
    await openDialogAndMenu(tester);

    await tester.tap(find.text('wd-vit-tagger-v3'));
    await tester.pumpAndSettle();

    expect(ai.modelName, 'SmilingWolf/wd-vit-tagger-v3');
    // Menu closed: section headers are gone, field shows the new model.
    expect(find.text('SmilingWolf/wd-vit-tagger-v3'), findsOneWidget);
  });

  testWidgets('caption model disables the threshold controls', (tester) async {
    await openDialogAndMenu(tester);
    final l10n = AppLocalizations.of(
        tester.element(find.byType(AlertDialog)))!;

    await tester.tap(find.text('llama-joycaption-beta-one-hf-llava'));
    await tester.pumpAndSettle();

    expect(find.text(l10n.aiThresholdCaptionNote), findsOneWidget);
    final slider = tester.widget<Slider>(find.byType(Slider));
    expect(slider.onChanged, isNull);
  });
}
