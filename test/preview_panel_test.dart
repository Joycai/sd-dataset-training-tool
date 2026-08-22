import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dataset_training_tool/l10n/app_localizations.dart';
import 'package:dataset_training_tool/state/dataset_state.dart';
import 'package:dataset_training_tool/state/editor_session.dart';
import 'package:dataset_training_tool/theme/app_theme.dart';
import 'package:dataset_training_tool/views/panels/preview_panel.dart';

// 1x1 transparent PNG.
const _pngBytes = [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x62, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
];

/// "100%" — the scale at which the picture fits the canvas.
const _fittedScale = 1.0;

void main() {
  late Directory tempDir;
  late DatasetState dataset;
  late EditorSession session;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    // All file IO happens here: testWidgets bodies run under a fake clock
    // where real async IO never completes.
    tempDir = await Directory.systemTemp.createTemp('preview_panel_');
    for (final name in ['001', '002']) {
      await File(p.join(tempDir.path, '$name.png')).writeAsBytes(_pngBytes);
    }
    dataset = DatasetState();
    await dataset.scan(
      directoryPath: tempDir.path,
      recursive: false,
      captionExtension: '.txt',
    );
    dataset.select(p.join(tempDir.path, '001.png'));
    session = EditorSession();
  });

  tearDown(() async {
    dataset.dispose();
    session.dispose();
    await tempDir.delete(recursive: true);
  });

  Widget harness() {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: dataset),
        ChangeNotifierProvider.value(value: session),
      ],
      child: MaterialApp(
        theme: buildAppTheme(Brightness.dark),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 600,
              height: 400,
              child: PreviewPanel(onOpenExternalPreview: () {}),
            ),
          ),
        ),
      ),
    );
  }

  double scaleOf(WidgetTester tester) => tester
      .widget<InteractiveViewer>(find.byType(InteractiveViewer))
      .transformationController!
      .value
      .getMaxScaleOnAxis();

  testWidgets('zoom buttons step the scale and fit restores it', (
    tester,
  ) async {
    await tester.pumpWidget(harness());
    await tester.pump();

    // Fitted view reads as 100%.
    expect(find.text('100%'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();
    expect(scaleOf(tester), closeTo(1.25, 1e-9));
    expect(find.text('125%'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();
    expect(find.text('156%'), findsOneWidget);

    // Zooming back out is the exact inverse, not an approximation.
    await tester.tap(find.byIcon(Icons.remove));
    await tester.tap(find.byIcon(Icons.remove));
    await tester.pump();
    expect(scaleOf(tester), closeTo(1.0, 1e-9));

    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();
    await tester.tap(find.text('Fit to window'));
    await tester.pump();
    expect(scaleOf(tester), closeTo(1.0, 1e-9));
  });

  testWidgets('zoom is anchored on the viewport centre', (tester) async {
    await tester.pumpWidget(harness());
    await tester.pump();

    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();

    // T(c)·S(k)·T(-c) with c = (300, 200), k = 1.25 puts the origin at
    // c * (1 - k) — the centre pixel stays where it was.
    final matrix = tester
        .widget<InteractiveViewer>(find.byType(InteractiveViewer))
        .transformationController!
        .value;
    expect(matrix.getTranslation().x, closeTo(300 * (1 - 1.25), 1e-9));
    expect(matrix.getTranslation().y, closeTo(200 * (1 - 1.25), 1e-9));
  });

  testWidgets('zoom stops at both bounds and disables the button there', (
    tester,
  ) async {
    await tester.pumpWidget(harness());
    await tester.pump();

    // The fitted view is the floor, so zoom-out starts disabled.
    expect(
      tester.widget<Icon>(find.byIcon(Icons.remove)).color?.a,
      lessThan(1.0),
    );

    for (var i = 0; i < 20; i++) {
      await tester.tap(find.byIcon(Icons.add));
      await tester.pump();
    }
    expect(scaleOf(tester), closeTo(8, 1e-9));
    // At the ceiling, zoom-in dims in turn.
    expect(tester.widget<Icon>(find.byIcon(Icons.add)).color?.a, lessThan(1.0));

    for (var i = 0; i < 40; i++) {
      await tester.tap(find.byIcon(Icons.remove));
      await tester.pump();
    }
    // Not 0.1: InteractiveViewer's zero boundary margin keeps the child
    // covering the viewport, so the fitted view is as far out as it goes.
    expect(scaleOf(tester), closeTo(_fittedScale, 1e-9));
  });

  testWidgets('browsing decodes bounded, zooming past 2x goes full-res', (
    tester,
  ) async {
    await tester.pumpWidget(harness());
    await tester.pump();

    ImageProvider provider() =>
        tester.widget<Image>(find.byType(Image)).image;

    // The fitted view shows a viewport-bounded decode, never the raw file.
    expect(provider(), isA<ResizeImage>());

    // 100% → 125% → 156% → 195% stays bounded; 244% crosses the threshold.
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byIcon(Icons.add));
      await tester.pump();
    }
    expect(provider(), isA<ResizeImage>());

    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();
    expect(provider(), isA<FileImage>());

    // Zooming back out keeps the full decode — no re-decode churn…
    await tester.tap(find.text('Fit to window'));
    await tester.pump();
    expect(provider(), isA<FileImage>());

    // …but the next image starts bounded again.
    dataset.select(p.join(tempDir.path, '002.png'));
    await tester.pump();
    expect(provider(), isA<ResizeImage>());
  });
}
