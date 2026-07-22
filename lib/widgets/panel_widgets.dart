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
          // inside it and the action icons sit flush right.
          Expanded(
            child: Row(
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
                if (count != null) ...[
                  const SizedBox(width: 8),
                  CountPill(text: '$count'),
                ],
              ],
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

/// Compact icon + label entry for [showPanelContextMenu].
PopupMenuItem<T> panelMenuItem<T>({
  required BuildContext context,
  required T value,
  required IconData icon,
  required String label,
  Color? color,
}) {
  final semantic = context.semantic;
  return PopupMenuItem<T>(
    value: value,
    height: 34,
    child: Row(
      children: [
        Icon(icon, size: 16, color: color ?? semantic.muted),
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
