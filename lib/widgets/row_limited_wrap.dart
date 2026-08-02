import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// A [Wrap] that stops after [maxRuns] rows and reports how many children it
/// left out, so the caller can offer them behind a "+N more" affordance.
///
/// This is what makes a group of thirty tags browsable: the group still says
/// how big it is, but it costs two rows of the panel instead of eight.
///
/// The overflow indicator is built *below* the rows, never inside them —
/// deliberately. An indicator sharing the last row would have to reserve space
/// whose width depends on the number it prints, which depends on how many
/// children fit, which depends on the reserved width: a layout that can
/// oscillate. Below the rows the two are independent.
class RowLimitedWrap extends StatefulWidget {
  const RowLimitedWrap({
    super.key,
    required this.children,
    required this.overflowBuilder,
    this.maxRuns,
    this.spacing = 0,
    this.runSpacing = 0,
  });

  final List<Widget> children;

  /// Builds the "+N more" affordance, shown only when something was cut.
  final Widget Function(BuildContext context, int hidden) overflowBuilder;

  /// Rows to keep; null shows everything.
  final int? maxRuns;

  final double spacing;
  final double runSpacing;

  @override
  State<RowLimitedWrap> createState() => _RowLimitedWrapState();
}

class _RowLimitedWrapState extends State<RowLimitedWrap> {
  /// Written during layout (via a post-frame callback) and read by the
  /// indicator alone, so a changed count rebuilds one small widget rather
  /// than the whole section.
  final ValueNotifier<int> _hidden = ValueNotifier(0);

  @override
  void dispose() {
    _hidden.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _RawRowLimitedWrap(
          maxRuns: widget.maxRuns,
          spacing: widget.spacing,
          runSpacing: widget.runSpacing,
          hidden: _hidden,
          children: widget.children,
        ),
        ValueListenableBuilder<int>(
          valueListenable: _hidden,
          builder: (context, hidden, _) => hidden == 0
              ? const SizedBox.shrink()
              : Padding(
                  padding: EdgeInsets.only(top: widget.runSpacing),
                  child: widget.overflowBuilder(context, hidden),
                ),
        ),
      ],
    );
  }
}

class _RawRowLimitedWrap extends MultiChildRenderObjectWidget {
  const _RawRowLimitedWrap({
    required super.children,
    required this.hidden,
    required this.maxRuns,
    required this.spacing,
    required this.runSpacing,
  });

  final ValueNotifier<int> hidden;
  final int? maxRuns;
  final double spacing;
  final double runSpacing;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderRowLimitedWrap(
      hidden: hidden,
      maxRuns: maxRuns,
      spacing: spacing,
      runSpacing: runSpacing,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderRowLimitedWrap renderObject,
  ) {
    renderObject
      ..hidden = hidden
      ..maxRuns = maxRuns
      ..spacing = spacing
      ..runSpacing = runSpacing;
  }
}

class _WrapParentData extends ContainerBoxParentData<RenderBox> {
  /// False for children the row limit cut: laid out (the framework requires
  /// it) but neither painted nor hit-tested.
  bool visible = true;
}

/// How the children packed into rows.
class _Packing {
  const _Packing(this.runCounts, this.runHeights, this.runWidths);

  final List<int> runCounts;
  final List<double> runHeights;
  final List<double> runWidths;

  int get placed => runCounts.fold(0, (a, b) => a + b);
}

class _RenderRowLimitedWrap extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _WrapParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _WrapParentData> {
  _RenderRowLimitedWrap({
    required ValueNotifier<int> hidden,
    required int? maxRuns,
    required double spacing,
    required double runSpacing,
  }) : _hidden = hidden,
       _maxRuns = maxRuns,
       _spacing = spacing,
       _runSpacing = runSpacing;

  ValueNotifier<int> _hidden;
  set hidden(ValueNotifier<int> value) {
    if (identical(_hidden, value)) return;
    _hidden = value;
    markNeedsLayout();
  }

  int? _maxRuns;
  set maxRuns(int? value) {
    if (_maxRuns == value) return;
    _maxRuns = value;
    markNeedsLayout();
  }

  double _spacing;
  set spacing(double value) {
    if (_spacing == value) return;
    _spacing = value;
    markNeedsLayout();
  }

  double _runSpacing;
  set runSpacing(double value) {
    if (_runSpacing == value) return;
    _runSpacing = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _WrapParentData) {
      child.parentData = _WrapParentData();
    }
  }

  /// Packs [sizes] into rows no wider than [maxWidth], stopping after
  /// [_maxRuns] rows. A child wider than the row on its own still gets a row —
  /// it was already laid out against [maxWidth], so it cannot grow past it.
  _Packing _pack(List<Size> sizes, double maxWidth) {
    final runCounts = <int>[];
    final runHeights = <double>[];
    final runWidths = <double>[];
    var count = 0;
    var width = 0.0;
    var height = 0.0;

    for (var i = 0; i < sizes.length; i++) {
      final size = sizes[i];
      final needed = count == 0 ? size.width : width + _spacing + size.width;
      if (count == 0 || needed <= maxWidth) {
        width = needed;
        height = math.max(height, size.height);
        count++;
        continue;
      }
      runCounts.add(count);
      runHeights.add(height);
      runWidths.add(width);
      if (_maxRuns != null && runCounts.length >= _maxRuns!) {
        return _Packing(runCounts, runHeights, runWidths);
      }
      count = 1;
      width = size.width;
      height = size.height;
    }
    if (count > 0) {
      runCounts.add(count);
      runHeights.add(height);
      runWidths.add(width);
    }
    return _Packing(runCounts, runHeights, runWidths);
  }

  Size _sizeOf(_Packing packing) {
    if (packing.runCounts.isEmpty) return Size.zero;
    return Size(
      packing.runWidths.reduce(math.max),
      packing.runHeights.reduce((a, b) => a + b) +
          _runSpacing * (packing.runCounts.length - 1),
    );
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final sizes = <Size>[];
    for (var child = firstChild; child != null; child = childAfter(child)) {
      sizes.add(
        child.getDryLayout(BoxConstraints(maxWidth: constraints.maxWidth)),
      );
    }
    return constraints.constrain(_sizeOf(_pack(sizes, constraints.maxWidth)));
  }

  @override
  void performLayout() {
    final maxWidth = constraints.maxWidth;
    final childConstraints = BoxConstraints(maxWidth: maxWidth);

    // Every child is laid out, cut or not: the framework will not leave a
    // dirty child behind, and a hidden tag is one line of text either way.
    final children = <RenderBox>[];
    final sizes = <Size>[];
    for (var child = firstChild; child != null; child = childAfter(child)) {
      child.layout(childConstraints, parentUsesSize: true);
      children.add(child);
      sizes.add(child.size);
    }
    if (children.isEmpty) {
      size = constraints.smallest;
      _report(0);
      return;
    }

    final packing = _pack(sizes, maxWidth);
    var index = 0;
    var y = 0.0;
    for (var run = 0; run < packing.runCounts.length; run++) {
      var x = 0.0;
      for (var i = 0; i < packing.runCounts[run]; i++, index++) {
        final data = children[index].parentData! as _WrapParentData;
        data
          ..visible = true
          // Vertically centered within the run, matching Wrap's default.
          ..offset = Offset(
            x,
            y + (packing.runHeights[run] - sizes[index].height) / 2,
          );
        x += sizes[index].width + _spacing;
      }
      y += packing.runHeights[run] + _runSpacing;
    }
    for (var i = index; i < children.length; i++) {
      (children[i].parentData! as _WrapParentData).visible = false;
    }

    size = constraints.constrain(_sizeOf(packing));
    _report(children.length - packing.placed);
  }

  /// Pushes the cut count out to the indicator after the frame — writing a
  /// [ValueNotifier] during layout would rebuild a widget mid-layout.
  void _report(int hidden) {
    if (_hidden.value == hidden) return;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (attached) _hidden.value = hidden;
    });
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    for (var child = firstChild; child != null; child = childAfter(child)) {
      final data = child.parentData! as _WrapParentData;
      if (!data.visible) continue;
      context.paintChild(child, data.offset + offset);
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    for (var child = lastChild; child != null; child = childBefore(child)) {
      final data = child.parentData! as _WrapParentData;
      if (!data.visible) continue;
      final hit = result.addWithPaintOffset(
        offset: data.offset,
        position: position,
        hitTest: (result, transformed) =>
            child!.hitTest(result, position: transformed),
      );
      if (hit) return true;
    }
    return false;
  }
}
