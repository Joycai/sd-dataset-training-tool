import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dataset_training_tool/widgets/row_limited_wrap.dart';

/// Fixed-size boxes: the packing is what is under test, not text metrics.
Widget _harness({
  required int count,
  int? maxRuns,
  double width = 300,
  double itemWidth = 100,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: width,
          child: RowLimitedWrap(
            spacing: 0,
            runSpacing: 0,
            maxRuns: maxRuns,
            overflowBuilder: (context, hidden) => Text('+$hidden more'),
            children: [
              for (var i = 0; i < count; i++)
                SizedBox(
                  width: itemWidth,
                  height: 20,
                  child: Text('t$i', key: ValueKey('t$i')),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('everything fits: no overflow affordance', (tester) async {
    await tester.pumpWidget(_harness(count: 6, maxRuns: 2));
    await tester.pumpAndSettle();

    expect(find.textContaining('more'), findsNothing);
    expect(find.text('t5'), findsOneWidget);
  });

  testWidgets('past the row cap the rest is cut and counted', (tester) async {
    await tester.pumpWidget(_harness(count: 10, maxRuns: 2));
    await tester.pumpAndSettle();

    // Two rows of three fit; the other four are hidden.
    expect(find.text('+4 more'), findsOneWidget);
  });

  testWidgets('a cut child is not hit-testable', (tester) async {
    var tapped = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 300,
              child: RowLimitedWrap(
                maxRuns: 1,
                overflowBuilder: (context, hidden) => Text('+$hidden more'),
                children: [
                  for (var i = 0; i < 6; i++)
                    GestureDetector(
                      onTap: () => tapped.add('t$i'),
                      child: SizedBox(
                        width: 100,
                        height: 20,
                        child: Text('t$i'),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('+3 more'), findsOneWidget);

    await tester.tap(find.text('t0'));
    await tester.pumpAndSettle();
    expect(tapped, ['t0']);

    // t4 is laid out (the framework requires it) but never positioned or
    // painted, so no tap anywhere can reach it.
    await tester.tap(find.text('t4'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(tapped, isNot(contains('t4')));
  });

  testWidgets('no cap shows everything', (tester) async {
    await tester.pumpWidget(_harness(count: 10));
    await tester.pumpAndSettle();

    expect(find.textContaining('more'), findsNothing);
    // Four rows of three plus one: the wrap grew instead of cutting.
    final size = tester.getSize(find.byType(RowLimitedWrap));
    expect(size.height, 80);
  });

  testWidgets('the cut count follows a width change', (tester) async {
    await tester.pumpWidget(_harness(count: 9, maxRuns: 2, width: 300));
    await tester.pumpAndSettle();
    expect(find.text('+3 more'), findsOneWidget);

    // Narrower: two per row instead of three, so two more fall off.
    await tester.pumpWidget(_harness(count: 9, maxRuns: 2, width: 200));
    await tester.pumpAndSettle();
    expect(find.text('+5 more'), findsOneWidget);
  });

  testWidgets('a child wider than the row still gets one', (tester) async {
    await tester.pumpWidget(
      _harness(count: 3, maxRuns: 2, width: 80, itemWidth: 100),
    );
    await tester.pumpAndSettle();

    // One per row, two rows, one left over — no infinite loop, no zero rows.
    expect(find.text('+1 more'), findsOneWidget);
  });

  testWidgets('an empty wrap reports nothing hidden', (tester) async {
    await tester.pumpWidget(_harness(count: 0, maxRuns: 2));
    await tester.pumpAndSettle();

    expect(find.textContaining('more'), findsNothing);
  });
}
