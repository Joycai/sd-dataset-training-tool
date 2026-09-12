import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dataset_training_tool/theme/app_theme.dart';
import 'package:dataset_training_tool/widgets/panel_widgets.dart';

/// GlassSurface shares one backdrop snapshot with its siblings under a
/// BackdropGroup, and keeps its own filter everywhere else. The second half
/// is the structural fact worth pinning: a dialog is a route above the
/// Navigator, never a descendant of the workbench group, and it must not be,
/// because it blurs the grouped surfaces themselves.
void main() {
  List<BackdropKey?> keys(WidgetTester tester) => tester
      .renderObjectList<RenderBackdropFilter>(find.byType(BackdropFilter))
      .map((r) => r.backdropKey)
      .toList();

  Widget app(Widget home) => MaterialApp(
    theme: buildAppTheme(Brightness.dark),
    home: Scaffold(body: home),
  );

  testWidgets('surfaces under a BackdropGroup share one key', (tester) async {
    await tester.pumpWidget(
      app(
        BackdropGroup(
          child: const Column(
            children: [
              GlassSurface(child: SizedBox(width: 100, height: 40)),
              GlassSurface(child: SizedBox(width: 100, height: 40)),
            ],
          ),
        ),
      ),
    );

    final resolved = keys(tester);
    expect(resolved, hasLength(2));
    expect(resolved, everyElement(isNotNull));
    expect(resolved[0], same(resolved[1]));
  });

  testWidgets('a surface outside any group snapshots on its own', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(const GlassSurface(child: SizedBox(width: 100, height: 40))),
    );

    expect(keys(tester), [isNull]);
  });

  testWidgets('a dialog pushed over a grouped shell is not grouped', (
    tester,
  ) async {
    late BuildContext shell;
    await tester.pumpWidget(
      app(
        BackdropGroup(
          child: Builder(
            builder: (context) {
              shell = context;
              return const GlassSurface(
                child: SizedBox(width: 100, height: 40),
              );
            },
          ),
        ),
      ),
    );

    showDialog<void>(
      context: shell,
      builder: (_) => const GlassDialog(
        width: 300,
        header: Text('dialog'),
        body: SizedBox(height: 40),
      ),
    );
    await tester.pumpAndSettle();

    final resolved = keys(tester);
    expect(resolved, hasLength(2));
    // The shell surface stays grouped; the dialog's surface, built in the
    // Navigator's overlay, resolves no group and keeps its own filter.
    expect(resolved.where((k) => k != null), hasLength(1));
    expect(resolved.where((k) => k == null), hasLength(1));
  });
}
