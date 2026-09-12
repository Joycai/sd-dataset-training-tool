import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dataset_training_tool/theme/app_theme.dart';

/// The disabled-chip dim used to be an `Opacity(0.55)` around each chip; it
/// is now mixed into the colours with [dimDisabled]. This renders the same
/// chip both ways over the panel backdrop and diffs the pixels, so the
/// saveLayer removal is proven to be a visual no-op rather than assumed.
void main() {
  const panel = Color(0xFF1C1C20);
  const fill = Color(0xFF2A2A2F);
  const text = Color(0xFFD0D0D6);
  const icon = Color(0xFF40C080);

  Widget chip({
    required Color fill,
    required Color border,
    required Color text,
    required Color icon,
  }) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2.5),
    decoration: BoxDecoration(
      color: fill,
      border: Border.all(color: border),
      borderRadius: BorderRadius.circular(AppRadii.pill),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.check, size: 10, color: icon),
        const SizedBox(width: 4),
        Text(
          '1girl',
          style: TextStyle(fontSize: AppText.small, color: text),
        ),
      ],
    ),
  );

  final key = GlobalKey();

  Widget scene(Widget child) => MaterialApp(
    theme: buildAppTheme(Brightness.dark),
    home: Scaffold(
      body: Center(
        child: RepaintBoundary(
          key: key,
          child: ColoredBox(
            color: panel,
            child: Padding(padding: const EdgeInsets.all(8), child: child),
          ),
        ),
      ),
    ),
  );

  Future<ByteData> capture(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(scene(child));
    late ByteData bytes;
    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage();
      bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    });
    return bytes;
  }

  /// Renders the chip under Opacity(0.55) and with the dim pre-mixed, and
  /// returns (max channel delta, share of channels differing by more than 4).
  Future<(int, double)> diff(WidgetTester tester, Color border) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final reference = await capture(
      tester,
      Opacity(
        opacity: 0.55,
        child: chip(fill: fill, border: border, text: text, icon: icon),
      ),
    );

    Color ink(Color c) => dimDisabled(c, backdrop: panel, over: fill);
    final candidate = await capture(
      tester,
      chip(
        fill: dimDisabled(fill, backdrop: panel),
        border: ink(border),
        text: ink(text),
        icon: ink(icon),
      ),
    );

    expect(candidate.lengthInBytes, reference.lengthInBytes);
    var maxDelta = 0;
    var over = 0;
    for (var i = 0; i < reference.lengthInBytes; i++) {
      final d = (reference.getUint8(i) - candidate.getUint8(i)).abs();
      if (d > maxDelta) maxDelta = d;
      if (d > 4) over++;
    }
    return (maxDelta, over / reference.lengthInBytes);
  }

  // Fill, border body and panel match to the bit. What does not is a one-
  // pixel fringe on glyph and icon edges: Skia tunes glyph coverage by the
  // text colour's luminance, and the pre-dimmed ink is a different luminance
  // from the bright ink the Opacity path rasterised. That fringe is invisible
  // (a few percent of the chip's pixels, under 24/255), so the assertion pins
  // it as small and rare rather than pretending it is zero.
  testWidgets('with the hairline border the dim is visually a no-op', (
    tester,
  ) async {
    // The stock chip border: a 10% white wash, as in the dark palette.
    final (maxDelta, share) = await diff(tester, const Color(0x1AFFFFFF));
    expect(maxDelta, lessThanOrEqualTo(24));
    expect(share, lessThan(0.03));
  });

  testWidgets('with a strong translucent border only edges move', (
    tester,
  ) async {
    // Applied / filtered chips ring themselves in an accent at 50%. The
    // stroke body sits on the fill and matches exactly; its anti-aliased
    // outer edge joins the glyph fringe above, since the old group composited
    // the border over nothing and the new colour was resolved over the fill.
    final (maxDelta, share) = await diff(tester, const Color(0x80E08040));
    expect(maxDelta, lessThanOrEqualTo(24));
    expect(share, lessThan(0.03));
  });
}
