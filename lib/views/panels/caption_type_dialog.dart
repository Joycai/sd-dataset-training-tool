import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../l10n/app_localizations.dart';
import '../../models/caption_type.dart';
import '../../theme/app_theme.dart';
import '../../widgets/panel_widgets.dart';

/// Column widths shared by the header labels and every type row, so the
/// labels sit exactly over the controls they name.
const double _switchWidth = AppMetrics.switchWidth;
const double _formatWidth = 156;
const double _extensionWidth = 96;
const double _actionWidth = 28;

/// Horizontal padding inside a type card; the header labels use the same
/// inset plus the card's 1px border.
const double _cardInset = 10;

/// Management dialog for the dataset's caption types: one card per type with
/// its enabled switch, display name, content format and file extension.
///
/// Edits are buffered — names, extensions, formats and deletions live in
/// local drafts and only reach [AppState] when the user confirms, so
/// dismissing the dialog (or pressing cancel) leaves the dataset untouched.
/// That also means the workbench rescans once, on confirm, instead of after
/// every keystroke. The default type cannot be disabled or deleted; only its
/// name, format and extension are editable.
Future<void> showCaptionTypesDialog(BuildContext context) {
  final appState = context.read<AppState>();
  return showDialog(
    context: context,
    builder: (_) => _CaptionTypesDialog(appState: appState),
  );
}

/// One row's editable state. The controllers live here — in the dialog, not
/// in the row widget — so a row rebuild (toggling, reordering after a
/// delete) never resets what the user has typed.
class _TypeDraft {
  _TypeDraft(CaptionType type)
    : id = type.id,
      name = TextEditingController(text: type.name),
      extension = TextEditingController(text: type.extension),
      enabled = type.enabled,
      format = type.format;

  final String id;
  final TextEditingController name;
  final TextEditingController extension;
  bool enabled;
  CaptionFormat format;

  bool get isDefault => id == CaptionType.defaultId;

  void dispose() {
    name.dispose();
    extension.dispose();
  }
}

class _CaptionTypesDialog extends StatefulWidget {
  const _CaptionTypesDialog({required this.appState});

  final AppState appState;

  @override
  State<_CaptionTypesDialog> createState() => _CaptionTypesDialogState();
}

class _CaptionTypesDialogState extends State<_CaptionTypesDialog> {
  // Same reason as the tag-group counter: two types created within one clock
  // tick would otherwise share an id.
  static int _idCounter = 0;

  late final List<_TypeDraft> _drafts = [
    for (final type in widget.appState.captionTypes) _TypeDraft(type),
  ];

  /// Set by [_submit] when a row fails validation: the message shown in the
  /// footer and the row that caused it.
  String? _error;
  String? _errorId;

  @override
  void dispose() {
    for (final draft in _drafts) {
      draft.dispose();
    }
    super.dispose();
  }

  void _add() {
    setState(() {
      _clearError();
      _drafts.add(
        _TypeDraft(
          CaptionType(
            id: '${DateTime.now().microsecondsSinceEpoch}-${_idCounter++}',
            extension: _freeExtension(),
          ),
        ),
      );
    });
  }

  /// A placeholder extension not yet in use, so a freshly added row is valid
  /// before the user has typed anything.
  String _freeExtension() {
    final used = {
      for (final draft in _drafts)
        normalizeCaptionExtension(draft.extension.text),
    };
    for (var i = 1; ; i++) {
      final candidate = i == 1 ? '.caption' : '.caption$i';
      if (!used.contains(candidate)) return candidate;
    }
  }

  void _delete(_TypeDraft draft) {
    setState(() {
      _clearError();
      _drafts.remove(draft);
    });
    draft.dispose();
  }

  void _clearError() {
    _error = null;
    _errorId = null;
  }

  /// Validates every row and writes the result through in one update. A bad
  /// extension keeps the dialog open with the offending card marked, rather
  /// than silently dropping the type the way [sanitizeCaptionTypes] would.
  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context)!;
    final navigator = Navigator.of(context);
    final seen = <String>{};
    final types = <CaptionType>[];
    for (final draft in _drafts) {
      final extension = normalizeCaptionExtension(draft.extension.text);
      if (extension == null || !seen.add(extension)) {
        setState(() {
          _error = extension == null
              ? l10n.captionTypeInvalid
              : l10n.captionTypeDuplicate;
          _errorId = draft.id;
        });
        return;
      }
      draft.extension.text = extension;
      types.add(
        CaptionType(
          id: draft.id,
          name: draft.name.text.trim(),
          extension: extension,
          enabled: draft.isDefault || draft.enabled,
          format: draft.format,
        ),
      );
    }
    await widget.appState.updateCaptionTypes(types);
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final semantic = context.semantic;
    final scheme = Theme.of(context).colorScheme;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580, maxHeight: 560),
        child: GlassSurface(
          borderRadius: BorderRadius.circular(14),
          blurSigma: 14,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              _header(l10n, semantic, scheme),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _columnLabels(l10n, semantic),
                      for (final draft in _drafts)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _CaptionTypeRow(
                            key: ValueKey(draft.id),
                            draft: draft,
                            hasError: draft.id == _errorId,
                            onChanged: () => setState(_clearError),
                            onDelete: draft.isDefault
                                ? null
                                : () => _delete(draft),
                          ),
                        ),
                      _AddTypeButton(label: l10n.captionTypeAdd, onTap: _add),
                    ],
                  ),
                ),
              ),
              _footer(l10n, semantic, scheme),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(
    AppLocalizations l10n,
    AppSemanticColors semantic,
    ColorScheme scheme,
  ) => Container(
    padding: const EdgeInsets.fromLTRB(16, 14, 10, 12),
    decoration: BoxDecoration(
      border: Border(bottom: BorderSide(color: semantic.line)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(Icons.list_alt, size: 17, color: scheme.primary),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.captionTypesTitle,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                l10n.captionTypesDesc,
                style: TextStyle(
                  fontSize: AppText.small,
                  color: semantic.muted,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        PanelIconButton(
          icon: Icons.close,
          tooltip: l10n.cancel,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    ),
  );

  Widget _columnLabels(AppLocalizations l10n, AppSemanticColors semantic) {
    final style = TextStyle(fontSize: AppText.small, color: semantic.muted);
    return Padding(
      padding: const EdgeInsets.fromLTRB(_cardInset + 1, 0, _cardInset + 1, 8),
      child: Row(
        children: [
          SizedBox(
            width: _switchWidth,
            child: Text(l10n.captionTypeEnabled, style: style),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(l10n.captionTypeName, style: style)),
          const SizedBox(width: 10),
          SizedBox(
            width: _formatWidth,
            child: Text(l10n.captionTypeFormat, style: style),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: _extensionWidth,
            child: Text(l10n.captionTypeExtension, style: style),
          ),
          const SizedBox(width: 4),
          const SizedBox(width: _actionWidth),
        ],
      ),
    );
  }

  Widget _footer(
    AppLocalizations l10n,
    AppSemanticColors semantic,
    ColorScheme scheme,
  ) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 14, 12),
    child: Row(
      children: [
        Expanded(
          child: Text(
            _error ?? l10n.captionTypeRules,
            style: TextStyle(
              fontSize: AppText.small,
              color: _error == null ? semantic.muted : scheme.error,
            ),
          ),
        ),
        const SizedBox(width: 10),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        const SizedBox(width: 6),
        FilledButton(onPressed: _submit, child: Text(l10n.done)),
      ],
    ),
  );
}

String _formatLabel(AppLocalizations l10n, CaptionFormat format) =>
    switch (format) {
      CaptionFormat.tags => l10n.captionTypeFormatTags,
      CaptionFormat.json => l10n.captionTypeFormatJson,
      CaptionFormat.prose => l10n.captionTypeFormatNl,
    };

String _formatSummary(AppLocalizations l10n, CaptionFormat format) =>
    switch (format) {
      CaptionFormat.tags => l10n.captionTypeFormatTagsDesc,
      CaptionFormat.json => l10n.captionTypeFormatJsonDesc,
      CaptionFormat.prose => l10n.captionTypeFormatNlDesc,
    };

/// One type card. Owns only presentation state (focus, hover); the values
/// themselves live in the dialog's [_TypeDraft].
class _CaptionTypeRow extends StatefulWidget {
  const _CaptionTypeRow({
    super.key,
    required this.draft,
    required this.hasError,
    required this.onChanged,
    required this.onDelete,
  });

  final _TypeDraft draft;

  /// Marks the card that failed validation on confirm.
  final bool hasError;

  /// Notifies the dialog that something changed (rebuild + clear the error).
  final VoidCallback onChanged;

  /// Null for the default type, which cannot be deleted.
  final VoidCallback? onDelete;

  @override
  State<_CaptionTypeRow> createState() => _CaptionTypeRowState();
}

class _CaptionTypeRowState extends State<_CaptionTypeRow> {
  final FocusNode _extensionFocus = FocusNode();
  bool _focused = false;
  bool _hovered = false;

  @override
  void initState() {
    super.initState();
    // Normalize on blur so the field shows what will actually be saved
    // (lowercased, exactly one leading dot). Anything unusable is left as
    // typed and reported when the dialog is confirmed.
    _extensionFocus.addListener(() {
      if (_extensionFocus.hasFocus) return;
      final normalized = normalizeCaptionExtension(widget.draft.extension.text);
      if (normalized != null) widget.draft.extension.text = normalized;
    });
  }

  @override
  void dispose() {
    _extensionFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final semantic = context.semantic;
    final scheme = Theme.of(context).colorScheme;
    final draft = widget.draft;

    final borderColor = widget.hasError
        ? scheme.error
        : _focused
        ? scheme.primary
        : (_hovered ? scheme.primary.withValues(alpha: 0.35) : semantic.line);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onFocusChange: (value) => setState(() => _focused = value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(
            horizontal: _cardInset,
            vertical: 7,
          ),
          decoration: BoxDecoration(
            color: semantic.raised,
            borderRadius: BorderRadius.circular(AppRadii.card),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            children: [
              Tooltip(
                message: draft.isDefault
                    ? l10n.captionTypeDefaultHint
                    : l10n.captionTypeEnabled,
                // The default type's switch reads as on but does nothing —
                // a disabled Switch renders in the *off* palette, which is
                // exactly the wrong thing to say about a type that is
                // always enabled.
                child: draft.isDefault
                    ? Opacity(
                        opacity: 0.7,
                        child: IgnorePointer(
                          child: AppSwitch(value: true, onChanged: (_) {}),
                        ),
                      )
                    : AppSwitch(
                        value: draft.enabled,
                        onChanged: (value) {
                          draft.enabled = value;
                          widget.onChanged();
                        },
                      ),
              ),
              const SizedBox(width: 12),
              // Disabled types keep their definition but stop appearing in
              // the navigator, so the whole card reads as inactive.
              Expanded(
                child: Opacity(
                  opacity: draft.isDefault || draft.enabled ? 1 : 0.5,
                  child: _nameField(l10n, semantic, scheme),
                ),
              ),
              const SizedBox(width: 10),
              Opacity(
                opacity: draft.isDefault || draft.enabled ? 1 : 0.5,
                child: Row(
                  children: [
                    SizedBox(
                      width: _formatWidth,
                      child: _FormatField(
                        format: draft.format,
                        onChanged: (format) {
                          draft.format = format;
                          widget.onChanged();
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: _extensionWidth,
                      child: TextField(
                        controller: draft.extension,
                        focusNode: _extensionFocus,
                        textAlign: TextAlign.center,
                        style: monoStyle(context, size: 12.5),
                        decoration: const InputDecoration(isDense: true),
                        onChanged: (_) {
                          if (widget.hasError) widget.onChanged();
                        },
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              SizedBox(
                width: _actionWidth,
                child: PanelIconButton(
                  icon: Icons.delete_outline,
                  tooltip: l10n.delete,
                  size: 15,
                  onPressed: widget.onDelete,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _nameField(
    AppLocalizations l10n,
    AppSemanticColors semantic,
    ColorScheme scheme,
  ) => Row(
    children: [
      Flexible(
        child: TextField(
          controller: widget.draft.name,
          style: monoStyle(context, size: 13),
          decoration: InputDecoration(
            isDense: true,
            // The name is a label, not a card: no box around it, so the row
            // reads as one field group.
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            filled: false,
            contentPadding: const EdgeInsets.symmetric(vertical: 6),
            hintText: l10n.captionTypeNameHint,
            hintStyle: TextStyle(
              fontSize: AppText.secondary,
              color: semantic.muted,
            ),
          ),
          onChanged: (_) {
            if (widget.hasError) widget.onChanged();
          },
        ),
      ),
      if (widget.draft.isDefault) ...[
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.input),
            border: Border.all(color: scheme.primary.withValues(alpha: 0.55)),
          ),
          child: Text(
            l10n.captionTypeDefaultBadge,
            style: TextStyle(fontSize: AppText.micro, color: scheme.primary),
          ),
        ),
      ],
    ],
  );
}

/// The format picker: a bordered field that opens a menu anchored under it,
/// each option carrying the one-line summary of how that format is edited.
///
/// MenuAnchor rather than DropdownButton — the stock dropdown centers its
/// menu over the button and cannot carry two-line items.
class _FormatField extends StatefulWidget {
  const _FormatField({required this.format, required this.onChanged});

  final CaptionFormat format;
  final ValueChanged<CaptionFormat> onChanged;

  @override
  State<_FormatField> createState() => _FormatFieldState();
}

class _FormatFieldState extends State<_FormatField> {
  static const double _menuWidth = 244;

  final MenuController _menu = MenuController();
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final semantic = context.semantic;
    final scheme = Theme.of(context).colorScheme;

    return MenuAnchor(
      controller: _menu,
      // Right-aligned with the field: the menu is wider than its anchor, and
      // the extension column sits immediately to its right.
      alignmentOffset: const Offset(_formatWidth - _menuWidth, 4),
      onOpen: () => setState(() => _open = true),
      onClose: () => setState(() => _open = false),
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(semantic.raised),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.control),
            side: BorderSide(color: semantic.line),
          ),
        ),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(vertical: 4),
        ),
      ),
      menuChildren: [
        for (final format in CaptionFormat.values)
          _MenuRow(
            width: _menuWidth,
            label: _formatLabel(l10n, format),
            summary: _formatSummary(l10n, format),
            selected: format == widget.format,
            onTap: () {
              _menu.close();
              if (format != widget.format) widget.onChanged(format);
            },
          ),
      ],
      builder: (context, controller, child) => Tooltip(
        message: l10n.captionTypeFormatTooltip,
        waitDuration: const Duration(milliseconds: 600),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadii.control),
          onTap: () =>
              controller.isOpen ? controller.close() : controller.open(),
          // Same fill, radius and border weights as the extension field
          // beside it — the two read as one control group.
          child: Container(
            padding: const EdgeInsets.fromLTRB(10, 7, 6, 7),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(AppRadii.control),
              border: Border.all(
                color: _open ? scheme.primary : semantic.line,
                width: _open ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _formatLabel(l10n, widget.format),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: AppText.secondary,
                      color: scheme.onSurface,
                    ),
                  ),
                ),
                Icon(
                  _open ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                  size: 18,
                  color: semantic.muted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.width,
    required this.label,
    required this.summary,
    required this.selected,
    required this.onTap,
  });

  final double width;
  final String label;
  final String summary;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    final scheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onTap,
      child: Container(
        width: width,
        color: selected
            ? scheme.primary.withValues(alpha: 0.10)
            : Colors.transparent,
        padding: const EdgeInsets.fromLTRB(12, 7, 10, 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: AppText.base,
                      color: selected ? scheme.primary : scheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    summary,
                    style: TextStyle(
                      fontSize: AppText.small,
                      color: semantic.muted,
                    ),
                  ),
                ],
              ),
            ),
            if (selected) ...[
              const SizedBox(width: 8),
              Icon(Icons.check, size: 15, color: scheme.primary),
            ],
          ],
        ),
      ),
    );
  }
}

/// Full-width dashed "add type" affordance from the spec. Flutter has no
/// dashed border, hence the painter.
class _AddTypeButton extends StatelessWidget {
  const _AddTypeButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    final scheme = Theme.of(context).colorScheme;

    return CustomPaint(
      painter: _DashedBorderPainter(
        color: semantic.line,
        radius: AppRadii.card,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.card),
        onTap: onTap,
        child: SizedBox(
          height: 42,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add, size: 15, color: scheme.primary),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: AppText.secondary,
                  color: scheme.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = color;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          Radius.circular(radius),
        ).deflate(0.5),
      );
    const dash = 5.0;
    const gap = 4.0;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = math.min(distance + dash, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance = next + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.radius != radius;
}
