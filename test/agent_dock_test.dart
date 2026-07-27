import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dataset_training_tool/app_state.dart';
import 'package:dataset_training_tool/l10n/app_localizations.dart';
import 'package:dataset_training_tool/services/settings_service.dart';
import 'package:dataset_training_tool/state/agent_chat_state.dart';
import 'package:dataset_training_tool/state/ai_tagger_state.dart';
import 'package:dataset_training_tool/state/dataset_state.dart';
import 'package:dataset_training_tool/state/tag_ops.dart';
import 'package:dataset_training_tool/theme/app_theme.dart';
import 'package:dataset_training_tool/views/panels/agent_chat_panel.dart';
import 'package:dataset_training_tool/views/panels/agent_dock.dart';

void main() {
  late AppState appState;
  late DatasetState dataset;
  late AiTaggerState ai;
  late TagOps tagOps;
  late AgentChatState chat;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    appState = AppState(SettingsService());
    await appState.loadSettings();
    dataset = DatasetState();
    ai = AiTaggerState(SettingsService());
    tagOps = TagOps(dataset: dataset);
    chat = AgentChatState(
      app: appState,
      dataset: dataset,
      tagOps: tagOps,
      aiTagger: ai,
    );
  });

  tearDown(() {
    chat.dispose();
    tagOps.dispose();
    ai.dispose();
    dataset.dispose();
  });

  const stackKey = ValueKey('dock-area');

  /// The dock is positioned against its stack, so the stack has to be the
  /// whole test surface for screen coordinates to mean anything.
  Widget harness(Size area) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: appState),
        ChangeNotifierProvider.value(value: chat),
      ],
      child: MaterialApp(
        theme: buildAppTheme(Brightness.dark),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Stack(
            key: stackKey,
            children: [
              const Positioned.fill(child: ColoredBox(color: Colors.black)),
              AgentDock(area: area, onClose: () {}),
            ],
          ),
        ),
      ),
    );
  }

  /// Sizes the test surface so `area` really is the space the dock has.
  void useSurface(WidgetTester tester, Size area) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = area;
    addTearDown(tester.view.reset);
  }

  Rect dockRect(WidgetTester tester) =>
      tester.getRect(find.byType(AgentDock).first);
  Rect areaRect(WidgetTester tester) => tester.getRect(find.byKey(stackKey));

  testWidgets('parks in the bottom-right corner of its area', (tester) async {
    const area = Size(1000, 700);
    useSurface(tester, area);
    await tester.pumpWidget(harness(area));
    await tester.pumpAndSettle();

    final stack = areaRect(tester);
    final dock = dockRect(tester);
    expect(stack.right - dock.right, closeTo(16, 0.01));
    expect(stack.bottom - dock.bottom, closeTo(16, 0.01));
  });

  testWidgets('dragging the header moves it and keeps it inside', (
    tester,
  ) async {
    const area = Size(1000, 700);
    useSurface(tester, area);
    await tester.pumpWidget(harness(area));
    await tester.pumpAndSettle();

    final before = dockRect(tester);
    // Grab the title bar and drag up-left.
    // touchSlop 0: the drag recognizer would otherwise eat the first 20px
    // and the assertion below would be measuring the slop, not the move.
    await tester.drag(
      find.byType(AgentPanelHeader),
      const Offset(-120, -80),
      touchSlopX: 0,
      touchSlopY: 0,
    );
    await tester.pumpAndSettle();

    final after = dockRect(tester);
    expect(after.left, closeTo(before.left - 120, 0.01));
    expect(after.top, closeTo(before.top - 80, 0.01));

    // Dragging far past the edge stops at it instead of leaving the area.
    await tester.drag(
      find.byType(AgentPanelHeader),
      const Offset(-5000, -5000),
      touchSlopX: 0,
      touchSlopY: 0,
    );
    await tester.pumpAndSettle();

    final stack = areaRect(tester);
    final parked = dockRect(tester);
    expect(parked.left, greaterThanOrEqualTo(stack.left - 0.01));
    expect(parked.top, greaterThanOrEqualTo(stack.top - 0.01));
  });

  testWidgets('minimizing leaves only the title bar', (tester) async {
    const area = Size(1000, 700);
    useSurface(tester, area);
    await tester.pumpWidget(harness(area));
    await tester.pumpAndSettle();

    expect(dockRect(tester).height, greaterThan(200));

    await tester.tap(find.byTooltip('Collapse panel'));
    await tester.pumpAndSettle();

    // 40px title bar + the glass surface's 1px border on each side.
    expect(dockRect(tester).height, closeTo(42, 0.01));
    // And it is still pinned to the same corner.
    final stack = areaRect(tester);
    expect(stack.bottom - dockRect(tester).bottom, closeTo(16, 0.01));

    await tester.tap(find.byTooltip('Expand panel'));
    await tester.pumpAndSettle();
    expect(dockRect(tester).height, greaterThan(200));
  });

  testWidgets('a window smaller than the panel minimum still lays out', (
    tester,
  ) async {
    // clamp(min, max) throws when min > max, which is exactly what a window
    // narrower than the panel's minimum would produce without a guard.
    // Below both declared minimums (280x220), which is what exercises the
    // guard on the clamp ranges.
    const tiny = Size(260, 200);
    useSurface(tester, tiny);
    await tester.pumpWidget(harness(tiny));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
