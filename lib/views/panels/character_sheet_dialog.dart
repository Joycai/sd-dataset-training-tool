import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../services/agent/character_sheet.dart';
import '../../theme/app_theme.dart';
import '../../widgets/panel_widgets.dart';

/// Collects the character sheet for the tagging skill, in one pass.
///
/// One dialog rather than a round of questions from the model: the outfit
/// field is a long comma-separated string that belongs in a real text area,
/// and every question/answer round would sit in the context window for the
/// rest of the run.
///
/// Returns null when the user cancels.
Future<CharacterSheetInput?> showCharacterSheetDialog(BuildContext context) =>
    showDialog<CharacterSheetInput>(
      context: context,
      builder: (_) => const _CharacterSheetDialog(),
    );

/// The transcript bubble shown in place of the compiled task. Markdown, to
/// match the other chat bubbles.
String characterSheetSummary(AppLocalizations l10n, CharacterSheetInput input) {
  final lines = <String>['**${l10n.characterSheetSummaryTitle}**'];
  void add(String label, String value) {
    final text = value.trim();
    if (text.isNotEmpty) lines.add('$label: $text');
  }

  add(l10n.characterSheetTrigger, input.triggerWord);
  add(
    l10n.characterSheetIdentity,
    parseSheetTags(input.identityTags).join(', '),
  );
  add(
    l10n.characterSheetGarments,
    parseSheetTags(input.garmentTags).join(', '),
  );
  add(l10n.characterSheetExtra, input.extraNotes);
  lines.add(l10n.characterSheetSummarySample(input.sampleSize));
  return lines.join('\n\n');
}

class _CharacterSheetDialog extends StatefulWidget {
  const _CharacterSheetDialog();

  @override
  State<_CharacterSheetDialog> createState() => _CharacterSheetDialogState();
}

class _CharacterSheetDialogState extends State<_CharacterSheetDialog> {
  final _name = TextEditingController();
  final _trigger = TextEditingController();
  final _identity = TextEditingController();
  final _garments = TextEditingController();
  final _extra = TextEditingController();
  int _sampleSize = CharacterSheetInput.kDefaultSampleSize;

  @override
  void dispose() {
    _name.dispose();
    _trigger.dispose();
    _identity.dispose();
    _garments.dispose();
    _extra.dispose();
    super.dispose();
  }

  CharacterSheetInput get _input => CharacterSheetInput(
    character: _name.text,
    triggerWord: _trigger.text,
    identityTags: _identity.text,
    garmentTags: _garments.text,
    extraNotes: _extra.text,
    sampleSize: _sampleSize,
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final semantic = context.semantic;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580, maxHeight: 640),
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
                        l10n.characterSheetTitle,
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
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        l10n.characterSheetIntro,
                        style: TextStyle(
                          fontSize: AppText.secondary,
                          height: 1.5,
                          color: semantic.muted,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _Field(
                              label: l10n.characterSheetName,
                              hint: l10n.characterSheetNameHint,
                              controller: _name,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: _Field(
                              label: l10n.characterSheetTrigger,
                              hint: l10n.characterSheetTriggerHint,
                              controller: _trigger,
                              onChanged: () => setState(() {}),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _Field(
                        label: l10n.characterSheetIdentity,
                        hint: l10n.characterSheetIdentityHint,
                        help: l10n.characterSheetTagsHelp,
                        controller: _identity,
                        lines: 3,
                        onChanged: () => setState(() {}),
                      ),
                      const SizedBox(height: 14),
                      _Field(
                        label: l10n.characterSheetGarments,
                        hint: l10n.characterSheetGarmentsHint,
                        help: l10n.characterSheetTagsHelp,
                        controller: _garments,
                        lines: 4,
                        onChanged: () => setState(() {}),
                      ),
                      const SizedBox(height: 14),
                      _Field(
                        label: l10n.characterSheetExtra,
                        hint: l10n.characterSheetExtraHint,
                        controller: _extra,
                        lines: 2,
                        onChanged: () => setState(() {}),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Text(
                            l10n.characterSheetSampleSize,
                            style: TextStyle(
                              fontSize: AppText.secondary,
                              color: semantic.muted,
                            ),
                          ),
                          Expanded(
                            child: Slider(
                              value: _sampleSize.toDouble(),
                              min: CharacterSheetInput.kMinSampleSize
                                  .toDouble(),
                              max: CharacterSheetInput.kMaxSampleSize
                                  .toDouble(),
                              divisions:
                                  CharacterSheetInput.kMaxSampleSize -
                                  CharacterSheetInput.kMinSampleSize,
                              onChanged: (v) =>
                                  setState(() => _sampleSize = v.round()),
                            ),
                          ),
                          Text(
                            '$_sampleSize ${l10n.characterSheetSampleSizeSuffix}',
                            style: const TextStyle(fontSize: AppText.secondary),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 14),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(l10n.cancel),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      // An empty sheet would ask the model to derive rules
                      // from nothing; the tagger alone needs no rules.
                      onPressed: _input.isEmpty
                          ? null
                          : () => Navigator.of(context).pop(_input),
                      child: Text(l10n.characterSheetStart),
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

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.hint,
    required this.controller,
    this.help,
    this.lines = 1,
    this.onChanged,
  });

  final String label;
  final String hint;
  final String? help;
  final TextEditingController controller;
  final int lines;

  /// Only the fields that decide whether the start button is enabled pass
  /// this; the name field cannot enable it on its own.
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: AppText.secondary,
                color: semantic.muted,
              ),
            ),
            if (help != null) ...[
              const Spacer(),
              Text(
                help!,
                style: TextStyle(
                  fontSize: AppText.micro,
                  color: semantic.muted,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 5),
        TextField(
          controller: controller,
          minLines: lines,
          maxLines: lines,
          keyboardType: lines > 1 ? TextInputType.multiline : null,
          style: const TextStyle(fontSize: AppText.base, height: 1.5),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
              fontSize: AppText.secondary,
              color: semantic.muted,
            ),
            border: const OutlineInputBorder(),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 10,
            ),
          ),
          onChanged: onChanged == null ? null : (_) => onChanged!(),
        ),
      ],
    );
  }
}
