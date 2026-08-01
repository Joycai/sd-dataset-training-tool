import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../l10n/app_localizations.dart';
import '../../models/caption_type.dart';
import '../../theme/app_theme.dart';
import '../../widgets/panel_widgets.dart';

/// Management dialog for the dataset's caption types: one row per type with
/// its enabled switch, display name and file extension.
///
/// Edits are written straight through to [AppState] as they are committed —
/// the same live-save the prompt-preset dialog uses, so there is no unsaved
/// state to lose when the dialog is dismissed. The default type cannot be
/// disabled or deleted; only its extension and name are editable.
Future<void> showCaptionTypesDialog(BuildContext context) => showDialog(
  context: context,
  builder: (_) => ChangeNotifierProvider.value(
    value: context.read<AppState>(),
    child: const _CaptionTypesDialog(),
  ),
);

class _CaptionTypesDialog extends StatefulWidget {
  const _CaptionTypesDialog();

  @override
  State<_CaptionTypesDialog> createState() => _CaptionTypesDialogState();
}

class _CaptionTypesDialogState extends State<_CaptionTypesDialog> {
  // Same reason as the tag-group counter: two types created within one clock
  // tick would otherwise share an id.
  static int _idCounter = 0;

  Future<void> _update(List<CaptionType> types) =>
      context.read<AppState>().updateCaptionTypes(types);

  Future<void> _add() {
    final types = context.read<AppState>().captionTypes;
    return _update([
      ...types,
      CaptionType(
        id: '${DateTime.now().microsecondsSinceEpoch}-${_idCounter++}',
        extension: _freeExtension(types),
      ),
    ]);
  }

  /// A placeholder extension not yet in use, so a freshly added row is valid
  /// before the user has typed anything.
  static String _freeExtension(List<CaptionType> types) {
    final used = {for (final t in types) t.extension};
    for (var i = 1; ; i++) {
      final candidate = i == 1 ? '.caption' : '.caption$i';
      if (!used.contains(candidate)) return candidate;
    }
  }

  Future<void> _change(CaptionType next) => _update([
    for (final t in context.read<AppState>().captionTypes)
      t.id == next.id ? next : t,
  ]);

  Future<void> _delete(String id) => _update([
    for (final t in context.read<AppState>().captionTypes)
      if (t.id != id) t,
  ]);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final semantic = context.semantic;
    final scheme = Theme.of(context).colorScheme;
    // watch, not read: saving rebuilds the rows underneath.
    final types = context.watch<AppState>().captionTypes;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 480),
        child: GlassSurface(
          borderRadius: BorderRadius.circular(14),
          blurSigma: 14,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(18, 12, 10, 12),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: semantic.line)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.captionTypesTitle,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    PanelIconButton(
                      icon: Icons.close,
                      tooltip: l10n.cancel,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
                  children: [
                    for (final type in types)
                      _CaptionTypeRow(
                        // Rebuild the controllers when the type itself is
                        // replaced (extension normalized elsewhere).
                        key: ValueKey('${type.id}:${type.extension}'),
                        type: type,
                        onChanged: _change,
                        onDelete: type.isDefault
                            ? null
                            : () => _delete(type.id),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.captionTypeDefaultHint,
                        style: TextStyle(
                          fontSize: AppText.micro,
                          color: semantic.muted,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _add,
                      icon: Icon(Icons.add, size: 14, color: scheme.primary),
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        textStyle: const TextStyle(fontSize: AppText.secondary),
                      ),
                      label: Text(l10n.captionTypeAdd),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _formatLabel(AppLocalizations l10n, CaptionFormat format) =>
    switch (format) {
      CaptionFormat.tags => l10n.captionTypeFormatTags,
      CaptionFormat.json => l10n.captionTypeFormatJson,
      CaptionFormat.prose => l10n.captionTypeFormatNl,
    };

class _CaptionTypeRow extends StatefulWidget {
  const _CaptionTypeRow({
    super.key,
    required this.type,
    required this.onChanged,
    required this.onDelete,
  });

  final CaptionType type;
  final ValueChanged<CaptionType> onChanged;

  /// Null for the default type, which cannot be deleted.
  final VoidCallback? onDelete;

  @override
  State<_CaptionTypeRow> createState() => _CaptionTypeRowState();
}

class _CaptionTypeRowState extends State<_CaptionTypeRow> {
  late final TextEditingController _name = TextEditingController(
    text: widget.type.name,
  );
  late final TextEditingController _extension = TextEditingController(
    text: widget.type.extension,
  );
  final FocusNode _extensionFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _extensionFocus.addListener(() {
      if (!_extensionFocus.hasFocus) _commitExtension();
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _extension.dispose();
    _extensionFocus.dispose();
    super.dispose();
  }

  /// Extensions commit on focus loss / submit, names on every keystroke —
  /// a half-typed extension must never reach the app state, where it would
  /// immediately become what the whole app scans for.
  void _commitExtension() {
    final l10n = AppLocalizations.of(context)!;
    final normalized = normalizeCaptionExtension(_extension.text);
    final taken = context.read<AppState>().captionTypes.any(
      (t) => t.id != widget.type.id && t.extension == normalized,
    );
    if (normalized == null || taken) {
      _extension.text = widget.type.extension;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(
            taken ? l10n.captionTypeDuplicate : l10n.captionTypeInvalid,
          ),
        ),
      );
      return;
    }
    _extension.text = normalized;
    if (normalized != widget.type.extension) {
      widget.onChanged(widget.type.copyWith(extension: normalized));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final semantic = context.semantic;
    final type = widget.type;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Tooltip(
            message: type.isDefault
                ? l10n.captionTypeDefaultHint
                : l10n.captionTypeEnabled,
            child: AppSwitch(
              value: type.enabled,
              onChanged: type.isDefault
                  ? null
                  : (value) => widget.onChanged(type.copyWith(enabled: value)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _name,
              style: const TextStyle(fontSize: AppText.base),
              decoration: InputDecoration(
                isDense: true,
                hintText: l10n.captionTypeName,
                hintStyle: TextStyle(
                  fontSize: AppText.secondary,
                  color: semantic.muted,
                ),
              ),
              onChanged: (value) =>
                  widget.onChanged(type.copyWith(name: value)),
            ),
          ),
          const SizedBox(width: 4),
          // The format decides how the entire app — editor, statistics,
          // batch edits, assistant — parses this type's caption files.
          Tooltip(
            message: l10n.captionTypeFormatTooltip,
            waitDuration: const Duration(milliseconds: 600),
            child: SizedBox(
              width: 96,
              child: DropdownButtonHideUnderline(
                child: DropdownButton<CaptionFormat>(
                  value: type.format,
                  isExpanded: true,
                  isDense: true,
                  icon: Icon(
                    Icons.expand_more,
                    size: 14,
                    color: semantic.muted,
                  ),
                  style: TextStyle(
                    fontSize: AppText.secondary,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  items: [
                    for (final format in CaptionFormat.values)
                      DropdownMenuItem(
                        value: format,
                        child: Text(_formatLabel(l10n, format)),
                      ),
                  ],
                  onChanged: (format) {
                    if (format != null) {
                      widget.onChanged(type.copyWith(format: format));
                    }
                  },
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 90,
            child: TextField(
              controller: _extension,
              focusNode: _extensionFocus,
              textAlign: TextAlign.center,
              style: monoStyle(context, size: 12.5),
              decoration: const InputDecoration(isDense: true),
              onSubmitted: (_) => _commitExtension(),
            ),
          ),
          const SizedBox(width: 4),
          PanelIconButton(
            icon: Icons.delete_outline,
            tooltip: l10n.delete,
            size: 15,
            onPressed: widget.onDelete,
          ),
        ],
      ),
    );
  }
}
