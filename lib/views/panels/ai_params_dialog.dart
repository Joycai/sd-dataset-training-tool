import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/ai_tagger_models.dart';
import '../../state/ai_tagger_state.dart';
import '../../theme/app_theme.dart';

/// Opens the AI interrogation parameters dialog. [ai] is passed explicitly
/// because dialogs live above the workbench's provider subtree.
Future<void> showAiParamsDialog(BuildContext context, AiTaggerState ai) {
  return showDialog<void>(
    context: context,
    builder: (context) => ChangeNotifierProvider.value(
      value: ai,
      child: const _AiParamsDialog(),
    ),
  );
}

class _AiParamsDialog extends StatefulWidget {
  const _AiParamsDialog();

  @override
  State<_AiParamsDialog> createState() => _AiParamsDialogState();
}

class _AiParamsDialogState extends State<_AiParamsDialog> {
  late final AiTaggerState _ai;
  late final TextEditingController _urlController;
  late final TextEditingController _ignoreController;
  double _sliderValue = 0.35;

  static const double _defaultCustomThreshold = 0.35;

  @override
  void initState() {
    super.initState();
    _ai = context.read<AiTaggerState>();
    _urlController = TextEditingController(text: _ai.serverUrl);
    _ignoreController =
        TextEditingController(text: _ai.ignoreTags.join(', '));
    _sliderValue = _ai.threshold ?? _defaultCustomThreshold;
    // First open: fetch the model list so the dropdown has content.
    if (_ai.models.isEmpty && !_ai.loadingModels) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _ai.refreshModels();
      });
    }
  }

  @override
  void dispose() {
    // Persist free-text fields on close; setters are no-ops when unchanged.
    _ai.setServerUrl(_urlController.text);
    _ai.setIgnoreTagsFromInput(_ignoreController.text);
    _urlController.dispose();
    _ignoreController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final semantic = context.semantic;
    final scheme = Theme.of(context).colorScheme;
    final ai = context.watch<AiTaggerState>();
    final useDefaultThreshold = ai.threshold == null;
    // The confidence threshold only exists for booru-style taggers; caption
    // models ignore it, so the whole threshold block goes inert for them.
    // Unknown category (old server) keeps the block enabled.
    AiModelInfo? selectedInfo;
    for (final m in ai.models) {
      if (m.modelName == ai.modelName) {
        selectedInfo = m;
        break;
      }
    }
    final thresholdApplies = selectedInfo?.category != 'caption';

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.tune, size: 18, color: semantic.muted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(l10n.aiParamsTitle,
                style: const TextStyle(fontSize: 15)),
          ),
          _ConnectionBadge(ai: ai, l10n: l10n),
        ],
      ),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _FieldLabel(text: l10n.aiServerUrl),
              TextField(
                controller: _urlController,
                style: const TextStyle(fontSize: 13),
                onSubmitted: (value) async {
                  await ai.setServerUrl(value);
                  await ai.refreshModels();
                },
              ),
              const SizedBox(height: 14),
              _FieldLabel(text: l10n.aiModelLabel),
              Row(
                children: [
                  Expanded(
                    child: _ModelPickerField(ai: ai, l10n: l10n),
                  ),
                  const SizedBox(width: 6),
                  IconButton(
                    icon: ai.loadingModels
                        ? SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                                strokeWidth: 1.5, color: semantic.muted),
                          )
                        : const Icon(Icons.refresh, size: 18),
                    tooltip: l10n.aiRefreshModels,
                    color: semantic.muted,
                    onPressed: ai.loadingModels
                        ? null
                        : () async {
                            await ai.setServerUrl(_urlController.text);
                            await ai.refreshModels();
                          },
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(child: _FieldLabel(text: l10n.aiThresholdLabel)),
                  Text(
                    useDefaultThreshold
                        ? l10n.aiUseModelDefault
                        : _sliderValue.toStringAsFixed(2),
                    style: monoStyle(context,
                        size: 11.5,
                        color: useDefaultThreshold || !thresholdApplies
                            ? semantic.muted
                            : scheme.onSurface),
                  ),
                  const SizedBox(width: 6),
                  _CompactSwitch(
                    value: !useDefaultThreshold && thresholdApplies,
                    onChanged: thresholdApplies
                        ? (custom) =>
                            ai.setThreshold(custom ? _sliderValue : null)
                        : null,
                  ),
                ],
              ),
              Slider(
                value: _sliderValue,
                min: 0.05,
                max: 0.95,
                divisions: 18,
                onChanged: useDefaultThreshold || !thresholdApplies
                    ? null
                    : (value) => setState(() => _sliderValue = value),
                onChangeEnd: useDefaultThreshold || !thresholdApplies
                    ? null
                    : (value) => ai.setThreshold(value),
              ),
              Text(
                thresholdApplies
                    ? l10n.aiThresholdDesc
                    : l10n.aiThresholdCaptionNote,
                style: TextStyle(fontSize: 11.5, color: semantic.muted),
              ),
              const SizedBox(height: 14),
              _FieldLabel(text: l10n.aiIgnoreTagsLabel),
              TextField(
                controller: _ignoreController,
                style: const TextStyle(fontSize: 13),
                maxLines: 2,
                onSubmitted: (value) => ai.setIgnoreTagsFromInput(value),
              ),
              const SizedBox(height: 4),
              Text(
                l10n.aiIgnoreTagsDesc,
                style: TextStyle(fontSize: 11.5, color: semantic.muted),
              ),
              const SizedBox(height: 10),
              const Divider(),
              _SwitchRow(
                label: l10n.aiUnderscoreToSpaces,
                value: ai.underscoreToSpaces,
                onChanged: ai.setUnderscoreToSpaces,
              ),
              _SwitchRow(
                label: l10n.aiEscapeParentheses,
                value: ai.escapeParentheses,
                onChanged: ai.setEscapeParentheses,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.confirm),
        ),
      ],
    );
  }
}

class _ConnectionBadge extends StatelessWidget {
  const _ConnectionBadge({required this.ai, required this.l10n});

  final AiTaggerState ai;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    final scheme = Theme.of(context).colorScheme;

    final Color color;
    final String text;
    if (ai.loadingModels) {
      color = semantic.muted;
      text = l10n.aiConnecting;
    } else if (ai.models.isNotEmpty) {
      color = semantic.ok;
      text = l10n.aiConnectionOk;
    } else if (ai.lastError != null) {
      color = scheme.error;
      text = l10n.aiConnectionFail;
    } else {
      color = semantic.muted;
      text = l10n.aiConnectionUnknown;
    }

    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
        const SizedBox(width: 5),
        Text(text, style: TextStyle(fontSize: 11.5, color: color)),
      ],
    );

    final error = ai.lastError;
    return error == null ? row : Tooltip(message: error, child: row);
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Text(
        text,
        style: TextStyle(fontSize: 12, color: context.semantic.muted),
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: const TextStyle(fontSize: 13)),
          ),
          _CompactSwitch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

/// A Switch scaled down to fit dense dialog rows: the stock Material 3
/// switch is 32 px tall plus tap padding and collides with its neighbors.
class _CompactSwitch extends StatelessWidget {
  const _CompactSwitch({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 38,
      height: 22,
      child: FittedBox(
        fit: BoxFit.contain,
        child: Switch(
          value: value,
          onChanged: onChanged,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    );
  }
}

/// Grouped model picker. A plain DropdownButtonFormField cannot express
/// section headers, a collapsed legacy group, a filter box, or per-item
/// tooltips, so this uses MenuAnchor (standard M3, themed via MenuStyle)
/// with a custom item list.
class _ModelPickerField extends StatefulWidget {
  const _ModelPickerField({required this.ai, required this.l10n});

  final AiTaggerState ai;
  final AppLocalizations l10n;

  @override
  State<_ModelPickerField> createState() => _ModelPickerFieldState();
}

class _ModelPickerFieldState extends State<_ModelPickerField> {
  final MenuController _menu = MenuController();

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    final scheme = Theme.of(context).colorScheme;
    final ai = widget.ai;
    final l10n = widget.l10n;

    AiModelInfo? selected;
    for (final m in ai.models) {
      if (m.modelName == ai.modelName) {
        selected = m;
        break;
      }
    }

    return MenuAnchor(
      controller: _menu,
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(semantic.raised),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(7),
            side: BorderSide(color: semantic.line),
          ),
        ),
        padding: const WidgetStatePropertyAll(EdgeInsets.zero),
      ),
      menuChildren: [
        _ModelMenu(
          ai: ai,
          l10n: l10n,
          onPicked: (name) {
            ai.setModelName(name);
            _menu.close();
          },
        ),
      ],
      builder: (context, controller, child) {
        return InkWell(
          borderRadius: BorderRadius.circular(7),
          onTap: ai.models.isEmpty
              ? null
              : () => controller.isOpen ? controller.close() : controller.open(),
          child: InputDecorator(
            decoration: const InputDecoration(),
            isEmpty: false,
            child: Row(
              children: [
                Expanded(
                  child: selected == null
                      ? Text(
                          l10n.aiNoModels,
                          overflow: TextOverflow.ellipsis,
                          style:
                              TextStyle(fontSize: 12.5, color: semantic.muted),
                        )
                      : Text(
                          selected.modelName,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 12.5, color: scheme.onSurface),
                        ),
                ),
                if (selected != null && selected.recommended) ...[
                  const SizedBox(width: 6),
                  _ModelBadge(
                      text: l10n.aiBadgeRecommended, color: semantic.ok),
                ],
                const SizedBox(width: 4),
                Icon(Icons.arrow_drop_down, size: 18, color: semantic.muted),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The dropdown panel: filter box, grouped rows, collapsible legacy rows,
/// VRAM footnote. Owns its own filter/expansion state so setState rebuilds
/// stay inside the overlay.
class _ModelMenu extends StatefulWidget {
  const _ModelMenu({
    required this.ai,
    required this.l10n,
    required this.onPicked,
  });

  final AiTaggerState ai;
  final AppLocalizations l10n;
  final ValueChanged<String> onPicked;

  @override
  State<_ModelMenu> createState() => _ModelMenuState();
}

class _ModelMenuState extends State<_ModelMenu> {
  final TextEditingController _filter = TextEditingController();
  // The menu panel already owns the PrimaryScrollController; the inner list
  // needs its own so the two scrollables don't fight over one position.
  final ScrollController _scroll = ScrollController();
  final Set<String> _expandedLegacy = {};

  @override
  void dispose() {
    _filter.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    final l10n = widget.l10n;
    final models = widget.ai.models;
    final query = _filter.text.trim().toLowerCase();
    final hasCategories = models.any((m) => m.category.isNotEmpty);

    bool matches(AiModelInfo m) =>
        query.isEmpty || m.modelName.toLowerCase().contains(query);

    final rows = <Widget>[];
    if (!hasCategories) {
      // Old server without metadata: flat, ungrouped list.
      rows.addAll([for (final m in models.where(matches)) _row(m)]);
    } else {
      final sections = [
        (l10n.aiModelGroupTag, Icons.sell_outlined,
            models.where((m) => m.category == 'tag').toList()),
        (l10n.aiModelGroupCaption, Icons.notes,
            models.where((m) => m.category != 'tag').toList()),
      ];
      for (final (title, icon, sectionModels) in sections) {
        final current =
            sectionModels.where((m) => !m.legacy && matches(m)).toList();
        final legacy =
            sectionModels.where((m) => m.legacy && matches(m)).toList();
        if (current.isEmpty && legacy.isEmpty) continue;
        rows.add(_sectionHeader(title, icon));
        rows.addAll(current.map(_row));
        if (legacy.isNotEmpty) {
          // While filtering, show matching legacy rows inline instead of
          // hiding them behind the collapse.
          if (query.isNotEmpty) {
            rows.addAll(legacy.map(_row));
          } else {
            final expanded = _expandedLegacy.contains(title);
            rows.add(_legacyToggle(title, legacy.length, expanded));
            if (expanded) rows.addAll(legacy.map(_row));
          }
        }
      }
    }
    if (rows.isEmpty) {
      rows.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: Text(l10n.aiModelFilterNoMatch,
              style: TextStyle(fontSize: 12, color: semantic.muted)),
        ),
      ));
    }

    return SizedBox(
      width: 372,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
            child: TextField(
              controller: _filter,
              autofocus: true,
              style: const TextStyle(fontSize: 12.5),
              decoration: InputDecoration(
                hintText: l10n.aiModelFilterHint,
                prefixIcon:
                    Icon(Icons.search, size: 15, color: semantic.muted),
                prefixIconConstraints:
                    const BoxConstraints(minWidth: 30, minHeight: 28),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: SingleChildScrollView(
                controller: _scroll,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: rows,
                ),
              ),
            ),
          ),
          if (hasCategories) ...[
            Divider(height: 1, color: semantic.line),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 7),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 12, color: semantic.muted),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(l10n.aiVramFootnote,
                        style:
                            TextStyle(fontSize: 11, color: semantic.muted)),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _sectionHeader(String title, IconData icon) {
    final semantic = context.semantic;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 3),
      child: Row(
        children: [
          Icon(icon, size: 13, color: semantic.muted),
          const SizedBox(width: 6),
          Text(title,
              style: TextStyle(fontSize: 11, color: semantic.muted)),
        ],
      ),
    );
  }

  Widget _legacyToggle(String section, int count, bool expanded) {
    final semantic = context.semantic;
    return InkWell(
      onTap: () => setState(() {
        expanded ? _expandedLegacy.remove(section) : _expandedLegacy.add(section);
      }),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 5, 10, 5),
        child: Row(
          children: [
            Icon(expanded ? Icons.expand_more : Icons.chevron_right,
                size: 14, color: semantic.muted),
            const SizedBox(width: 4),
            Text(widget.l10n.aiModelLegacyGroup(count),
                style: TextStyle(fontSize: 11.5, color: semantic.muted)),
          ],
        ),
      ),
    );
  }

  Widget _row(AiModelInfo m) {
    final semantic = context.semantic;
    final scheme = Theme.of(context).colorScheme;
    final l10n = widget.l10n;
    final isSelected = m.modelName == widget.ai.modelName;
    // Show the repo name without the org prefix; the full name lives in the
    // info tooltip and the closed field.
    final slash = m.modelName.indexOf('/');
    final shortName =
        slash > 0 ? m.modelName.substring(slash + 1) : m.modelName;
    final highVram = m.vramGb >= 12;
    final nameColor = m.legacy
        ? semantic.muted
        : (isSelected ? scheme.primary : scheme.onSurface);

    return InkWell(
      onTap: () => widget.onPicked(m.modelName),
      child: Container(
        color: isSelected
            ? scheme.primary.withValues(alpha: 0.10)
            : Colors.transparent,
        padding: const EdgeInsets.fromLTRB(24, 5, 10, 5),
        child: Row(
          children: [
            Expanded(
              child: Text(
                shortName,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12.5, color: nameColor),
              ),
            ),
            if (m.recommended) ...[
              const SizedBox(width: 6),
              _ModelBadge(text: l10n.aiBadgeRecommended, color: semantic.ok),
            ],
            if (m.uncensored) ...[
              const SizedBox(width: 6),
              _ModelBadge(text: l10n.aiBadgeUncensored, color: scheme.error),
            ],
            if (m.vramGb > 0) ...[
              const SizedBox(width: 6),
              Text(
                _vramLabel(m.vramGb),
                style: monoStyle(context,
                    size: 10.5,
                    color: highVram ? semantic.warn : semantic.muted),
              ),
            ],
            if (m.description.isNotEmpty || m.advice.isNotEmpty) ...[
              const SizedBox(width: 6),
              Tooltip(
                margin: const EdgeInsets.symmetric(horizontal: 60),
                richMessage: TextSpan(
                  children: [
                    TextSpan(
                      text: '${m.modelName}\n\n',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    TextSpan(text: m.description),
                    if (m.advice.isNotEmpty)
                      TextSpan(text: '\n\n${m.advice}'),
                  ],
                ),
                child:
                    Icon(Icons.info_outline, size: 14, color: semantic.muted),
              ),
            ],
            if (isSelected) ...[
              const SizedBox(width: 6),
              Icon(Icons.check, size: 14, color: scheme.primary),
            ],
          ],
        ),
      ),
    );
  }

  static String _vramLabel(double gb) {
    final n = gb == gb.roundToDouble() ? gb.toInt().toString() : gb.toString();
    return gb >= 12 ? '${n}G+' : '~${n}G';
  }
}

/// A small tinted pill, e.g. "recommended" / "uncensored".
class _ModelBadge extends StatelessWidget {
  const _ModelBadge({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(text, style: TextStyle(fontSize: 10.5, color: color)),
    );
  }
}
