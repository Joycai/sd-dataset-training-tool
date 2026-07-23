import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Shared header for the side panels: bold title, count pill, trailing
/// icon actions.
class PanelHeader extends StatelessWidget {
  const PanelHeader({
    super.key,
    required this.title,
    this.count,
    this.actions = const [],
  });

  final String title;
  final int? count;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 8),
      child: Row(
        children: [
          // Title and pill share one flex slot so the unused width stays
          // inside it and the action icons sit flush right. The title
          // ellipsizes, but the pill cannot shrink — hide it when the
          // actions squeeze this slot too far (narrow panels).
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final showCount = count != null && constraints.maxWidth >= 90;
                return Row(
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (showCount) ...[
                      const SizedBox(width: 8),
                      CountPill(text: '$count'),
                    ],
                  ],
                );
              },
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}

class CountPill extends StatelessWidget {
  const CountPill({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: semantic.line),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        text,
        style: monoStyle(context, size: 11, color: semantic.muted),
      ),
    );
  }
}

/// Compact icon button used in panel headers and overlay pills.
class PanelIconButton extends StatelessWidget {
  const PanelIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.color,
    this.size = 17,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: size),
      tooltip: tooltip,
      onPressed: onPressed,
      color: color ?? context.semantic.muted,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
      padding: EdgeInsets.zero,
    );
  }
}

/// Dense search/filter input used at the top of both side panels.
class PanelSearchField extends StatelessWidget {
  const PanelSearchField({
    super.key,
    required this.hint,
    this.onChanged,
    this.controller,
    this.focusNode,
  });

  final String hint;
  final ValueChanged<String>? onChanged;
  final TextEditingController? controller;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        onChanged: onChanged,
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: Icon(Icons.search, size: 16, color: semantic.muted),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 32,
            minHeight: 32,
          ),
        ),
      ),
    );
  }
}

/// Underline tab used by the caption editor and the right panel: selection
/// is a 2px primary underline, matching the workbench's flat look.
class PanelTab extends StatelessWidget {
  const PanelTab({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final semantic = context.semantic;
    return InkWell(
      onTap: onTap,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(7)),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected ? scheme.primary : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Text(
          label,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? scheme.onSurface : semantic.muted,
          ),
        ),
      ),
    );
  }
}

/// [showMenu] wrapper that applies the panel palette — the default popup
/// surface ignores the app theme's raised color and hairlines.
Future<T?> showPanelContextMenu<T>({
  required BuildContext context,
  required Offset position,
  required List<PopupMenuEntry<T>> items,
}) {
  final semantic = context.semantic;
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  return showMenu<T>(
    context: context,
    position: RelativeRect.fromRect(
      position & const Size(1, 1),
      Offset.zero & overlay.size,
    ),
    color: semantic.raised,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(8),
      side: BorderSide(color: semantic.line),
    ),
    constraints: const BoxConstraints(minWidth: 180),
    items: items,
  );
}

/// Compact icon + label entry for [showPanelContextMenu]. [iconColor] tints
/// only the icon (e.g. a group's color dot), leaving the label default.
PopupMenuItem<T> panelMenuItem<T>({
  required BuildContext context,
  required T value,
  required IconData icon,
  required String label,
  Color? color,
  Color? iconColor,
}) {
  final semantic = context.semantic;
  return PopupMenuItem<T>(
    value: value,
    height: 34,
    child: Row(
      children: [
        Icon(icon, size: 16, color: iconColor ?? color ?? semantic.muted),
        const SizedBox(width: 9),
        Flexible(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12.5, color: color),
          ),
        ),
      ],
    ),
  );
}

/// Wraps a tag chip with the insertion-anchor affordance:
///
/// - a slim "holder" strip after the chip — invisible at rest, revealed as a
///   grip while the tag is hovered, and always clickable either way;
/// - when this tag is the anchor, a primary-tinted halo behind the whole tag
///   plus a caret bar in the holder slot marking where new tags insert;
/// - clicking the holder toggles the anchor on/off.
class AnchorableTag extends StatefulWidget {
  const AnchorableTag({
    super.key,
    required this.active,
    required this.tooltip,
    required this.onToggle,
    required this.child,
    this.expandChild = false,
  });

  final bool active;
  final String tooltip;
  final VoidCallback onToggle;
  final Widget child;

  /// True in fixed-width hosts (grid cells) where the chip should fill the
  /// remaining width; false in intrinsic-width hosts (wraps).
  final bool expandChild;

  @override
  State<AnchorableTag> createState() => _AnchorableTagState();
}

class _AnchorableTagState extends State<AnchorableTag> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final semantic = context.semantic;

    final holder = Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 600),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onToggle,
          child: SizedBox(
            width: 13,
            // Wrap hosts give the row no height to stretch into; a fixed
            // hit zone keeps the invisible holder comfortably clickable.
            height: widget.expandChild ? null : 24,
            child: Center(
              child: widget.active
                  // The caret: where the next tag will land.
                  ? Container(
                      width: 2.5,
                      height: 15,
                      decoration: BoxDecoration(
                        color: scheme.primary,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    )
                  // Hover preview of the same caret, dimmed; hidden at rest
                  // but the hit zone above stays clickable regardless.
                  : AnimatedOpacity(
                      duration: const Duration(milliseconds: 120),
                      opacity: _hovered ? 1 : 0,
                      child: Container(
                        width: 2,
                        height: 13,
                        decoration: BoxDecoration(
                          color: semantic.muted,
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                    ),
            ),
          ),
        ),
      ),
    );

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(
          // The halo marks the anchored tag without recoloring the chip
          // itself; padding is constant so toggling never shifts layout.
          color: widget.active
              ? scheme.primary.withAlpha(38)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
        ),
        padding: const EdgeInsets.all(2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          // Grid cells are height-bounded: stretch so the chip fills them.
          // Wraps are not: center on the chip's intrinsic height.
          crossAxisAlignment: widget.expandChild
              ? CrossAxisAlignment.stretch
              : CrossAxisAlignment.center,
          children: [
            if (widget.expandChild)
              Expanded(child: widget.child)
            else
              widget.child,
            holder,
          ],
        ),
      ),
    );
  }
}

/// Column whose keyed children slide to their new position when the order
/// changes (FLIP: measure old offset, rebuild, animate the delta back to
/// zero). Bump [reorderToken] alongside the order change to arm the
/// animation — offset shifts from unrelated rebuilds (filtering, content
/// growth) stay instant.
class AnimatedReorderColumn extends StatefulWidget {
  const AnimatedReorderColumn({
    super.key,
    required this.children,
    required this.reorderToken,
    this.duration = const Duration(milliseconds: 240),
    this.curve = Curves.easeOutCubic,
    this.crossAxisAlignment = CrossAxisAlignment.start,
  });

  /// Every child needs a unique, stable key.
  final List<Widget> children;

  final int reorderToken;
  final Duration duration;
  final Curve curve;
  final CrossAxisAlignment crossAxisAlignment;

  @override
  State<AnimatedReorderColumn> createState() => _AnimatedReorderColumnState();
}

class _AnimatedReorderColumnState extends State<AnimatedReorderColumn> {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: widget.crossAxisAlignment,
      children: [
        for (final child in widget.children)
          _ReorderItem(
            key: child.key,
            token: widget.reorderToken,
            duration: widget.duration,
            curve: widget.curve,
            child: child,
          ),
      ],
    );
  }
}

class _ReorderItem extends StatefulWidget {
  const _ReorderItem({
    super.key,
    required this.token,
    required this.duration,
    required this.curve,
    required this.child,
  });

  final int token;
  final Duration duration;
  final Curve curve;
  final Widget child;

  @override
  State<_ReorderItem> createState() => _ReorderItemState();
}

class _ReorderItemState extends State<_ReorderItem>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
    value: 1, // start settled: no animation on first layout
  );

  double? _lastDy;
  int? _lastToken;
  double _fromDelta = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _measure(Duration _) {
    if (!mounted) return;
    final box = context.findRenderObject();
    final colState = context.findAncestorStateOfType<_AnimatedReorderColumnState>();
    final colBox = colState?.context.findRenderObject();
    if (box is! RenderBox || !box.hasSize || colBox is! RenderBox) return;
    // Offset relative to the column, so scrolling never reads as movement.
    final dy = box.localToGlobal(Offset.zero, ancestor: colBox).dy;
    final armed = _lastToken != null && _lastToken != widget.token;
    if (armed && _lastDy != null && (dy - _lastDy!).abs() > 0.5) {
      if (MediaQuery.disableAnimationsOf(context)) {
        _controller.value = 1;
      } else {
        _fromDelta = _lastDy! - dy;
        _controller.forward(from: 0);
      }
    }
    _lastToken = widget.token;
    _lastDy = dy;
  }

  @override
  Widget build(BuildContext context) {
    // Offsets can shift on any parent rebuild; re-measure after every frame
    // this item takes part in.
    WidgetsBinding.instance.addPostFrameCallback(_measure);
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final remaining = 1 - widget.curve.transform(_controller.value);
        if (remaining == 0) return child!;
        return Transform.translate(
          offset: Offset(0, _fromDelta * remaining),
          child: child,
        );
      },
    );
  }
}

/// Small selectable pill used for the caption-status filters.
class FilterChipPill extends StatelessWidget {
  const FilterChipPill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final semantic = context.semantic;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(99),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          color: selected ? scheme.primary : Colors.transparent,
          border: Border.all(color: selected ? scheme.primary : semantic.line),
          borderRadius: BorderRadius.circular(99),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? scheme.onPrimary : semantic.muted,
          ),
        ),
      ),
    );
  }
}
