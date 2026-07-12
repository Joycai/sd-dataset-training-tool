import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Vertical drag handle between panels. Draws the panel divider line and
/// widens/highlights it while hovered or dragged; double-tap restores the
/// panel's default width.
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
  });

  /// Global x position where the drag started.
  final ValueChanged<double> onDragStart;

  /// Current global x position of the pointer during the drag.
  final ValueChanged<double> onDragUpdate;

  final VoidCallback? onDragEnd;
  final VoidCallback? onReset;

  @override
  State<ResizeHandle> createState() => _ResizeHandleState();
}

class _ResizeHandleState extends State<ResizeHandle> {
  bool _hovered = false;
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    final scheme = Theme.of(context).colorScheme;
    final active = _hovered || _dragging;

    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // Anchor the gesture at pointer-down so the initial touch slop is
        // included in the first update instead of showing up as a dead zone.
        dragStartBehavior: DragStartBehavior.down,
        onHorizontalDragStart: (details) {
          setState(() => _dragging = true);
          widget.onDragStart(details.globalPosition.dx);
        },
        onHorizontalDragUpdate: (details) =>
            widget.onDragUpdate(details.globalPosition.dx),
        onHorizontalDragEnd: (_) {
          setState(() => _dragging = false);
          widget.onDragEnd?.call();
        },
        onHorizontalDragCancel: () {
          setState(() => _dragging = false);
          widget.onDragEnd?.call();
        },
        onDoubleTap: widget.onReset,
        child: SizedBox(
          width: 7,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: active ? 3 : 1,
              color: active ? scheme.primary : semantic.line,
            ),
          ),
        ),
      ),
    );
  }
}
