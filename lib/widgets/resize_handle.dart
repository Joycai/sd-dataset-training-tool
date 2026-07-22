import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Drag handle between panels. Draws the panel divider line and
/// widens/highlights it while hovered or dragged; double-tap restores the
/// panel's default size.
///
/// [axis] is the drag direction: horizontal (default) renders a vertical
/// divider between side-by-side panels; vertical renders a horizontal
/// divider between stacked panels.
///
/// Reports absolute pointer positions rather than per-event deltas: deltas
/// accumulated against a build-time snapshot lose events that arrive between
/// frames, which makes the drag lag behind the pointer.
class ResizeHandle extends StatefulWidget {
  const ResizeHandle({
    super.key,
    required this.onDragStart,
    required this.onDragUpdate,
    this.onDragEnd,
    this.onReset,
    this.axis = Axis.horizontal,
  });

  /// Global position (x for horizontal, y for vertical) where the drag
  /// started.
  final ValueChanged<double> onDragStart;

  /// Current global position of the pointer during the drag.
  final ValueChanged<double> onDragUpdate;

  final VoidCallback? onDragEnd;
  final VoidCallback? onReset;
  final Axis axis;

  @override
  State<ResizeHandle> createState() => _ResizeHandleState();
}

class _ResizeHandleState extends State<ResizeHandle> {
  bool _hovered = false;
  bool _dragging = false;

  void _start(double position) {
    setState(() => _dragging = true);
    widget.onDragStart(position);
  }

  void _end() {
    setState(() => _dragging = false);
    widget.onDragEnd?.call();
  }

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    final scheme = Theme.of(context).colorScheme;
    final active = _hovered || _dragging;
    final horizontal = widget.axis == Axis.horizontal;
    final lineColor = active ? scheme.primary : semantic.line;

    return MouseRegion(
      cursor: horizontal
          ? SystemMouseCursors.resizeColumn
          : SystemMouseCursors.resizeRow,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // Anchor the gesture at pointer-down so the initial touch slop is
        // included in the first update instead of showing up as a dead zone.
        dragStartBehavior: DragStartBehavior.down,
        onHorizontalDragStart:
            horizontal ? (d) => _start(d.globalPosition.dx) : null,
        onHorizontalDragUpdate: horizontal
            ? (d) => widget.onDragUpdate(d.globalPosition.dx)
            : null,
        onHorizontalDragEnd: horizontal ? (_) => _end() : null,
        onHorizontalDragCancel: horizontal ? _end : null,
        onVerticalDragStart:
            horizontal ? null : (d) => _start(d.globalPosition.dy),
        onVerticalDragUpdate: horizontal
            ? null
            : (d) => widget.onDragUpdate(d.globalPosition.dy),
        onVerticalDragEnd: horizontal ? null : (_) => _end(),
        onVerticalDragCancel: horizontal ? null : _end,
        onDoubleTap: widget.onReset,
        child: horizontal
            ? SizedBox(
                width: 7,
                child: Center(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    width: active ? 3 : 1,
                    color: lineColor,
                  ),
                ),
              )
            : SizedBox(
                height: 7,
                child: Center(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    height: active ? 3 : 1,
                    width: double.infinity,
                    color: lineColor,
                  ),
                ),
              ),
      ),
    );
  }
}
