import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/ai_tagger_models.dart';
import '../../state/ai_tagger_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/model_picker.dart';

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
                    child: ModelPickerField(ai: ai, l10n: l10n),
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
