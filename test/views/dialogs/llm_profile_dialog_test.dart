import 'package:dataset_training_tool/l10n/app_localizations.dart';
import 'package:dataset_training_tool/models/llm_models.dart';
import 'package:dataset_training_tool/services/settings_service.dart';
import 'package:dataset_training_tool/state/app_state.dart';
import 'package:dataset_training_tool/theme/app_theme.dart';
import 'package:dataset_training_tool/views/dialogs/llm_profile_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  for (final locale in ['en', 'zh']) {
    testWidgets(
      '$locale model protocol and effort are editable and persisted',
      (tester) async {
        tester.view.physicalSize = const Size(1400, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        SharedPreferences.setMockInitialValues({});
        final app = AppState(SettingsService());
        await app.loadSettings();
        await app.updateLlmProviders([
          const LlmProvider(
            id: 'p',
            name: 'Provider',
            models: [
              LlmModelConfig(
                id: 'm',
                modelId: 'gemini-3.8-flash',
                displayName: 'Test Model',
              ),
            ],
          ),
        ]);
        await tester.pumpWidget(
          ChangeNotifierProvider.value(
            value: app,
            child: MaterialApp(
              locale: Locale(locale),
              theme: buildAppTheme(Brightness.dark),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Scaffold(
                body: Builder(
                  builder: (context) => TextButton(
                    onPressed: () => showLlmProfilesDialog(context),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Test Model'));
        await tester.pumpAndSettle();
        final protocol = find.byType(DropdownButtonFormField<LlmApiKind>);
        await tester.ensureVisible(protocol);
        await tester.tap(protocol);
        await tester.pumpAndSettle();
        expect(find.text('Chat Completions'), findsWidgets);
        expect(find.text('Responses'), findsOneWidget);
        expect(find.text('Messages (Anthropic)'), findsOneWidget);
        await tester.tap(find.text('Gemini').last);
        await tester.pumpAndSettle();
        expect(
          app.llmProviders.single.models.single.protocol,
          LlmApiKind.gemini,
        );
        final effort = find.byType(DropdownButtonFormField<LlmEffort>);
        await tester.ensureVisible(effort);
        await tester.tap(effort);
        await tester.pumpAndSettle();
        expect(find.text('xhigh'), findsNothing);
        await tester.tap(find.text('high').last);
        await tester.pumpAndSettle();
        expect(app.activeLlmProfile!.effort, LlmEffort.high);
        expect(app.activeLlmProfile!.kind, LlmApiKind.gemini);
        final loaded = AppState(SettingsService());
        await loaded.loadSettings();
        expect(loaded.llmProviders.single.models.single.effort, LlmEffort.high);
        expect(
          loaded.llmProviders.single.models.single.protocol,
          LlmApiKind.gemini,
        );
        await tester.pumpWidget(const SizedBox());
        app.dispose();
        loaded.dispose();
      },
    );
  }
}
