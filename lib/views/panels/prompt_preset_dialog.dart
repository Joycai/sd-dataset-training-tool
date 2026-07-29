import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../l10n/app_localizations.dart';
import '../../models/prompt_preset.dart';
import '../../theme/app_theme.dart';
import '../../widgets/panel_widgets.dart';

/// Management dialog for the assistant's prompt presets: a list on the left,
/// the selected preset's name and text on the right.
///
/// Edits are written straight through to [AppState] as the user types — the
/// same live-save the LLM backend dialog uses, so there is no unsaved state
/// to lose when the dialog is dismissed.
Future<void> showPromptPresetsDialog(BuildContext context) => showDialog(
  context: context,
  builder: (_) => ChangeNotifierProvider.value(
    value: context.read<AppState>(),
    child: const _PromptPresetsDialog(),
  ),
);

class _PromptPresetsDialog extends StatefulWidget {
  const _PromptPresetsDialog();

  @override
  State<_PromptPresetsDialog> createState() => _PromptPresetsDialogState();
}

class _PromptPresetsDialogState extends State<_PromptPresetsDialog> {
  String? _selectedId;

  List<PromptPreset> get _presets => context.read<AppState>().promptPresets;

  PromptPreset? get _selected {
    for (final p in _presets) {
      if (p.id == _selectedId) return p;
    }
    return null;
  }

  Future<void> _add() async {
    final l10n = AppLocalizations.of(context)!;
    final preset = await context.read<AppState>().createPromptPreset(
      title: l10n.promptPresetNewName,
    );
    if (!mounted) return;
    setState(() => _selectedId = preset.id);
  }

  Future<void> _delete(PromptPreset preset) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.promptPresetDeleteConfirmTitle),
        content: Text(
          l10n.promptPresetDeleteConfirmContent(
            _labelOf(l10n, preset),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await context.read<AppState>().deletePromptPreset(preset.id);
    if (!mounted) return;
    setState(() => _selectedId = null);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final semantic = context.semantic;
    // watch, not read: saving rebuilds the list and the form underneath.
    context.watch<AppState>();
    final presets = _presets;
    final selected = _selected;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 540),
        child: GlassSurface(
          borderRadius: BorderRadius.circular(14),
          blurSigma: 14,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
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
                        l10n.promptPresetsTitle,
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
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: 236,
                      child: _PresetList(
                        presets: presets,
                        selectedId: _selectedId,
                        onSelect: (id) => setState(() => _selectedId = id),
                        onAdd: _add,
                      ),
                    ),
                    Container(width: 1, color: semantic.line),
                    Expanded(
                      child: selected == null
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text(
                                  l10n.promptPresetSelectHint,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: AppText.secondary,
                                    color: semantic.muted,
                                  ),
                                ),
                              ),
                            )
                          : _PresetForm(
                              // Rebuild the controllers when the selection
                              // moves to another preset.
                              key: ValueKey(selected.id),
                              preset: selected,
                              isFirst: presets.first.id == selected.id,
                              isLast: presets.last.id == selected.id,
                              onChanged: (title, content) => context
                                  .read<AppState>()
                                  .updatePromptPreset(
                                    selected.id,
                                    title: title,
                                    content: content,
                                  ),
                              onMove: (delta) => context
                                  .read<AppState>()
                                  .reorderPromptPreset(selected.id, delta),
                              onDelete: () => _delete(selected),
                            ),
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

/// The label a preset shows before its name is filled in: the first line of
/// its text, or a placeholder when that is empty too.
String _labelOf(AppLocalizations l10n, PromptPreset preset) {
  final title = preset.title.trim();
  if (title.isNotEmpty) return title;
  final firstLine = preset.content.trim().split('\n').first.trim();
  return firstLine.isEmpty ? l10n.promptPresetUntitled : firstLine;
}

class _PresetList extends StatelessWidget {
  const _PresetList({
    required this.presets,
    required this.selectedId,
    required this.onSelect,
    required this.onAdd,
  });

  final List<PromptPreset> presets;
  final String? selectedId;
  final ValueChanged<String> onSelect;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final semantic = context.semantic;
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: presets.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      l10n.promptPresetsEmpty,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: AppText.secondary,
                        color: semantic.muted,
                      ),
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(8, 10, 8, 8),
                  children: [
                    for (final preset in presets)
                      _PresetRow(
                        label: _labelOf(l10n, preset),
                        preview: preset.content.trim(),
                        selected: preset.id == selectedId,
                        onTap: () => onSelect(preset.id),
                      ),
                  ],
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onAdd,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 7),
                decoration: BoxDecoration(
                  border: Border.all(color: semantic.line),
                  borderRadius: BorderRadius.circular(AppRadii.input),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add, size: 14, color: scheme.primary),
                    const SizedBox(width: 6),
                    Text(
                      l10n.promptPresetAdd,
                      style: TextStyle(
                        fontSize: AppText.secondary,
                        color: scheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PresetRow extends StatelessWidget {
  const _PresetRow({
    required this.label,
    required this.preview,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String preview;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final semantic = context.semantic;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: selected
                  ? scheme.primary.withValues(alpha: 0.20)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(AppRadii.input),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: AppText.secondary,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: selected ? scheme.onSurface : semantic.muted,
                  ),
                ),
                if (preview.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      preview,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: AppText.micro,
                        color: semantic.muted,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PresetForm extends StatefulWidget {
  const _PresetForm({
    super.key,
    required this.preset,
    required this.isFirst,
    required this.isLast,
    required this.onChanged,
    required this.onMove,
    required this.onDelete,
  });

  final PromptPreset preset;
  final bool isFirst;
  final bool isLast;

  /// Called with the whole pair on every keystroke; nulls are not used, so
  /// the caller can pass both straight to `updatePromptPreset`.
  final void Function(String title, String content) onChanged;

  final ValueChanged<int> onMove;
  final VoidCallback onDelete;

  @override
  State<_PresetForm> createState() => _PresetFormState();
}

class _PresetFormState extends State<_PresetForm> {
  late final TextEditingController _title = TextEditingController(
    text: widget.preset.title,
  );
  late final TextEditingController _content = TextEditingController(
    text: widget.preset.content,
  );

  @override
  void dispose() {
    _title.dispose();
    _content.dispose();
    super.dispose();
  }

  void _commit() => widget.onChanged(_title.text, _content.text);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final semantic = context.semantic;
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.promptPresetName,
            style: TextStyle(
              fontSize: AppText.secondary,
              color: semantic.muted,
            ),
          ),
          const SizedBox(height: 5),
          TextField(
            controller: _title,
            style: const TextStyle(fontSize: AppText.base),
            onChanged: (_) => _commit(),
          ),
          const SizedBox(height: 14),
          Text(
            l10n.promptPresetContent,
            style: TextStyle(
              fontSize: AppText.secondary,
              color: semantic.muted,
            ),
          ),
          const SizedBox(height: 5),
          Expanded(
            child: TextField(
              controller: _content,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              keyboardType: TextInputType.multiline,
              style: const TextStyle(fontSize: AppText.base, height: 1.5),
              decoration: InputDecoration(
                hintText: l10n.promptPresetContentHint,
                hintStyle: TextStyle(
                  fontSize: AppText.secondary,
                  color: semantic.muted,
                ),
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => _commit(),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              PanelIconButton(
                icon: Icons.arrow_upward,
                tooltip: l10n.promptPresetMoveUp,
                size: 15,
                onPressed: widget.isFirst ? null : () => widget.onMove(-1),
              ),
              PanelIconButton(
                icon: Icons.arrow_downward,
                tooltip: l10n.promptPresetMoveDown,
                size: 15,
                onPressed: widget.isLast ? null : () => widget.onMove(1),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: widget.onDelete,
                icon: const Icon(Icons.delete_outline, size: 15),
                style: TextButton.styleFrom(
                  foregroundColor: scheme.error,
                  visualDensity: VisualDensity.compact,
                  textStyle: const TextStyle(fontSize: AppText.secondary),
                ),
                label: Text(l10n.delete),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
