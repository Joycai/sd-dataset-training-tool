import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Vertical drag handle between panels. Draws the panel divider line and
/// widens/highlights it while hovered or dragged; double-tap restores the
/// panel's default width.
class ResizeHandle extends StatefulWidget {
  const ResizeHandle({
    super.key,
    required this.onDrag,
    this.onDragEnd,
    this.onReset,
  });

  /// Horizontal drag delta in logical pixels (positive = pointer moved right).
  final ValueChanged<double> onDrag;
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
        onHorizontalDragUpdate: (details) => widget.onDrag(details.delta.dx),
        onHorizontalDragStart: (_) => setState(() => _dragging = true),
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
