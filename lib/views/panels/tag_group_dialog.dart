import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../../models/tag_group.dart';
import '../../theme/app_theme.dart';

/// Name + color for a tag group, as returned by [showTagGroupDialog].
typedef TagGroupInput = ({String name, int color});

/// Create/edit dialog for a tag group: name field, the eight preset swatches,
/// and a custom RGB picker (sliders + hex). Returns null when cancelled.
Future<TagGroupInput?> showTagGroupDialog(
  BuildContext context, {
  TagGroup? existing,
}) {
  return showDialog<TagGroupInput>(
    context: context,
    builder: (context) => _TagGroupDialog(existing: existing),
  );
}

class _TagGroupDialog extends StatefulWidget {
  const _TagGroupDialog({this.existing});

  final TagGroup? existing;

  @override
  State<_TagGroupDialog> createState() => _TagGroupDialogState();
}

class _TagGroupDialogState extends State<_TagGroupDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _hexController;
  late int _color;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.existing?.name ?? '');
    _color = widget.existing?.color ?? kTagGroupPresetColors.first;
    _hexController = TextEditingController(text: _toHex(_color));
  }

  @override
  void dispose() {
    _nameController.dispose();
    _hexController.dispose();
    super.dispose();
  }

  static String _toHex(int color) =>
      (color & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase();

  void _setColor(int color, {bool updateHex = true}) {
    setState(() => _color = color);
    if (updateHex) _hexController.text = _toHex(color);
  }

  void _onHexChanged(String text) {
    final cleaned = text.replaceFirst('#', '');
    if (cleaned.length != 6) return;
    final value = int.tryParse(cleaned, radix: 16);
    if (value == null) return;
    _setColor(0xFF000000 | value, updateHex: false);
  }

  Widget _channelSlider({
    required String label,
    required int value,
    required ValueChanged<int> onChanged,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 16,
          child: Text(label, style: monoStyle(context, size: 11.5)),
        ),
        Expanded(
          child: Slider(
            value: value.toDouble(),
            min: 0,
            max: 255,
            onChanged: (v) => onChanged(v.round()),
          ),
        ),
        SizedBox(
          width: 30,
          child: Text(
            '$value',
            textAlign: TextAlign.right,
            style: monoStyle(context, size: 11.5),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final semantic = context.semantic;
    final scheme = Theme.of(context).colorScheme;
    final color = Color(_color);
    final r = (_color >> 16) & 0xFF, g = (_color >> 8) & 0xFF;
    final b = _color & 0xFF;

    return AlertDialog(
      title: Text(
        widget.existing == null ? l10n.newGroupTitle : l10n.editGroupTitle,
      ),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameController,
              autofocus: true,
              decoration: InputDecoration(hintText: l10n.groupNameHint),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            Text(
              l10n.groupColorLabel,
              style: TextStyle(fontSize: 12, color: semantic.muted),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final preset in kTagGroupPresetColors)
                  InkWell(
                    onTap: () => _setColor(preset),
                    borderRadius: BorderRadius.circular(99),
                    child: Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(preset),
                        border: Border.all(
                          color: _color == preset
                              ? scheme.primary
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      child: _color == preset
                          ? const Icon(Icons.check, size: 14)
                          : null,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Text(
                  l10n.customColorLabel,
                  style: TextStyle(fontSize: 12, color: semantic.muted),
                ),
                const SizedBox(width: 10),
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color,
                    border: Border.all(color: semantic.line),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 92,
                  child: TextField(
                    controller: _hexController,
                    style: monoStyle(context, size: 12),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                        RegExp(r'[#0-9a-fA-F]'),
                      ),
                      LengthLimitingTextInputFormatter(7),
                    ],
                    decoration: const InputDecoration(hintText: 'RRGGBB'),
                    onChanged: _onHexChanged,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            _channelSlider(
              label: 'R',
              value: r,
              onChanged: (v) => _setColor(0xFF000000 | (v << 16) | (g << 8) | b),
            ),
            _channelSlider(
              label: 'G',
              value: g,
              onChanged: (v) => _setColor(0xFF000000 | (r << 16) | (v << 8) | b),
            ),
            _channelSlider(
              label: 'B',
              value: b,
              onChanged: (v) => _setColor(0xFF000000 | (r << 16) | (g << 8) | v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        TextButton(
          onPressed: _nameController.text.trim().isEmpty
              ? null
              : () => Navigator.of(context).pop(
                    (name: _nameController.text.trim(), color: _color),
                  ),
          child: Text(l10n.confirm),
        ),
      ],
    );
  }
}
