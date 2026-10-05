import 'package:dataset_training_tool/l10n/app_localizations.dart';
import 'package:dataset_training_tool/models/image_operation.dart';
import 'package:dataset_training_tool/models/image_operation_plan.dart';
import 'package:dataset_training_tool/state/dataset_state.dart';
import 'package:dataset_training_tool/state/image_operation_state.dart';
import 'package:dataset_training_tool/state/tag_ops.dart';
import 'package:dataset_training_tool/views/panels/image_operation_review.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final language in ['en', 'zh']) {
    testWidgets('review displays targets and returns approval in $language', (
      tester,
    ) async {
      final dataset = DatasetState();
      final tags = TagOps(dataset: dataset);
      final state = ImageOperationState(
        dataset: dataset,
        tagOps: tags,
        serverUrl: () => '',
      );
      addTearDown(state.dispose);
      addTearDown(tags.dispose);
      addTearDown(dataset.dispose);
      final plan = ImageOperationPlan(
        id: '1-1',
        digest: 'digest',
        root: '/source',
        output: '/output',
        identity: 'scope',
        recipe: ImageRecipe.fromJson({}),
        replace: false,
        items: [
          ImagePlanItem(
            source: '/source/a.png',
            target: '/output/a.png',
            fingerprint: 'hash',
            sidecars: {'/source/a.txt': '/output/a.txt'},
            sidecarFingerprints: {},
          ),
        ],
        warnings: [],
      );
      bool? approved;
      await tester.pumpWidget(
        MaterialApp(
          locale: Locale(language),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  approved = await showImageOperationReview(
                    context,
                    state,
                    plan,
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('/output'), findsOneWidget);
      expect(find.textContaining('a.png → a.png'), findsOneWidget);
      await tester.tap(
        find.text(language == 'en' ? 'Approve this plan' : '批准此方案'),
      );
      await tester.pumpAndSettle();
      expect(approved, true);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('manual preprocessing dialog opens without an LLM profile', (
    tester,
  ) async {
    final dataset = DatasetState();
    final tags = TagOps(dataset: dataset);
    final state = ImageOperationState(
      dataset: dataset,
      tagOps: tags,
      serverUrl: () => '',
    );
    addTearDown(state.dispose);
    addTearDown(tags.dispose);
    addTearDown(dataset.dispose);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showImageProcessingDialog(context, state),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Image preprocessing'), findsOneWidget);
    expect(find.text('Prepare and review'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Image preprocessing'), findsNothing);
  });
}
