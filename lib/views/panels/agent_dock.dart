import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/settings_service.dart';
import '../../state/agent_chat_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/panel_widgets.dart';
import 'agent_chat_panel.dart';

/// The AI assistant as a floating panel over the workbench.
///
/// It used to be a fourth resizable column, which cost the centre canvas its
/// width whenever the assistant was open — even while idle. Floating keeps it
/// one gesture away without permanently reshaping the workbench.
///
/// Must be a direct child of a [Stack]: it returns a [Positioned]. [area] is
/// that stack's size, used to keep the panel inside the window.
class AgentDock extends StatefulWidget {
  const AgentDock({super.key, required this.area, required this.onClose});

  final Size area;
  final VoidCallback onClose;

  @override
  State<AgentDock> createState() => _AgentDockState();
}

class _AgentDockState extends State<AgentDock> {
  /// GlassSurface draws a 1px border on every side, so the collapsed panel
  /// has to be that much taller than its title bar or the bar overflows the
  /// content box by exactly those two pixels.
  static const double _collapsedHeight = AgentPanelHeader.height + 2;
  static const double _minWidth = 280;
  static const double _minHeight = 220;

  final SettingsService _settings = SettingsService();

  double _width = SettingsService.defaultAgentPanelWidth;
  double _height = SettingsService.defaultAgentPanelHeight;
  double _right = SettingsService.defaultAgentPanelInset;
  double _bottom = SettingsService.defaultAgentPanelInset;
  bool _minimized = false;

  @override
  void initState() {
    super.initState();
    _settings.loadAgentPanelWidth().then((v) {
      if (mounted) setState(() => _width = v);
    });
    _settings.loadAgentPanelHeight().then((v) {
      if (mounted) setState(() => _height = v);
    });
    _settings.loadAgentPanelOffset().then((offset) {
      if (mounted) {
        setState(() {
          _right = offset.$1;
          _bottom = offset.$2;
        });
      }
    });
    _settings.loadAgentPanelMinimized().then((v) {
      if (mounted) setState(() => _minimized = v);
    });
  }

  /// Panel size after clamping to the window — a saved size from a larger
  /// window must not push the panel off screen.
  ///
  /// The minimums yield to the window: in an area smaller than the panel's
  /// own minimum, the panel shrinks to the area rather than hanging off the
  /// edge (and rather than handing `clamp` a range whose lower bound exceeds
  /// its upper, which throws).
  Size get _size {
    final minWidth = math.min(_minWidth, widget.area.width);
    final minHeight = math.min(_minHeight, widget.area.height);
    final width = _width
        .clamp(minWidth, math.max(minWidth, widget.area.width))
        .toDouble();
    final height = _minimized
        ? math.min(_collapsedHeight, widget.area.height)
        : _height
              .clamp(minHeight, math.max(minHeight, widget.area.height))
              .toDouble();
    return Size(width, height);
  }

  /// Keeps both edges inside [area]; the offsets are from the bottom-right,
  /// so the panel stays in its corner as the window resizes.
  (double, double) _clampOffset(double right, double bottom, Size size) {
    final maxRight = (widget.area.width - size.width).clamp(
      0.0,
      double.infinity,
    );
    final maxBottom = (widget.area.height - size.height).clamp(
      0.0,
      double.infinity,
    );
    return (
      right.clamp(0.0, maxRight).toDouble(),
      bottom.clamp(0.0, maxBottom).toDouble(),
    );
  }

  void _onDrag(Offset delta) {
    final size = _size;
    setState(() {
      // Dragging right moves the panel right, which *shrinks* the offset
      // from the right edge — hence the subtraction.
      final (right, bottom) = _clampOffset(
        _right - delta.dx,
        _bottom - delta.dy,
        size,
      );
      _right = right;
      _bottom = bottom;
    });
  }

  void _persistOffset() => _settings.saveAgentPanelOffset(_right, _bottom);

  void _toggleMinimized() {
    setState(() => _minimized = !_minimized);
    _settings.saveAgentPanelMinimized(_minimized);
  }

  /// Drag of the bottom-right grip. The panel's own offsets pin *that*
  /// corner, so growing it means moving both of them by exactly what the
  /// panel gains — the top-left corner is what stays put, which is what the
  /// grip's direction promises.
  ///
  /// Reads the on-screen geometry rather than the raw fields: a saved size
  /// from a larger window is clamped for display, and resizing from the
  /// unclamped value would jump on the first pixel of the drag.
  void _onResize(Offset delta) {
    final size = _size;
    final (right, bottom) = _clampOffset(_right, _bottom, size);
    final left = widget.area.width - right - size.width;
    final top = widget.area.height - bottom - size.height;

    setState(() {
      _width = (size.width + delta.dx)
          .clamp(_minWidth, math.max(_minWidth, widget.area.width - left))
          .toDouble();
      _height = (size.height + delta.dy)
          .clamp(_minHeight, math.max(_minHeight, widget.area.height - top))
          .toDouble();
      // Never negative: in a window too small for the minimums the panel
      // already overflows, and a negative offset would only push it further
      // off the opposite edge.
      _right = math.max(0, widget.area.width - left - _width);
      _bottom = math.max(0, widget.area.height - top - _height);
    });
  }

  void _persistSize() {
    _settings.saveAgentPanelWidth(_width);
    _settings.saveAgentPanelHeight(_height);
    // Resizing moves the pinned corner, so the offsets changed too.
    _persistOffset();
  }

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    final chat = context.watch<AgentChatState>();
    final size = _size;
    final (right, bottom) = _clampOffset(_right, _bottom, size);

    return Positioned(
      right: right,
      bottom: bottom,
      width: size.width,
      height: size.height,
      child: GlassSurface(
        borderRadius: BorderRadius.circular(AppRadii.card),
        blurSigma: 14,
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AgentPanelHeader(
                  chat: chat,
                  onClose: widget.onClose,
                  minimized: _minimized,
                  onToggleMinimized: _toggleMinimized,
                  onDragUpdate: _onDrag,
                  onDragEnd: _persistOffset,
                ),
                if (!_minimized) const Expanded(child: AgentChatPanel()),
              ],
            ),
            if (!_minimized)
              Positioned(
                right: 2,
                bottom: 2,
                child: _ResizeCorner(
                  color: semantic.muted,
                  onDrag: _onResize,
                  onDragEnd: _persistSize,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Bottom-right grip, where a window's resize handle belongs. The panel
/// keeps its top-left corner while this drags, so the grip pulls the frame
/// out in the direction it points.
class _ResizeCorner extends StatelessWidget {
  const _ResizeCorner({
    required this.color,
    required this.onDrag,
    required this.onDragEnd,
  });

  final Color color;
  final ValueChanged<Offset> onDrag;
  final VoidCallback onDragEnd;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeDownRight,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate: (details) => onDrag(details.delta),
        onPanEnd: (_) => onDragEnd(),
        child: SizedBox(
          width: 18,
          height: 18,
          // A diagonal arrow reads as "resize"; a rotated chevron just reads
          // as a stray angle bracket in the corner. It points the way the
          // drag grows the panel.
          child: Center(child: Icon(Icons.south_east, size: 12, color: color)),
        ),
      ),
    );
  }
}
