import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../l10n/app_localizations.dart';
import '../../models/merge_rules.dart';
import '../../state/ai_tagger_state.dart';
import '../../state/batch_tag_state.dart';
import '../../state/dataset_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/model_picker.dart';
import '../../widgets/subdirectory_picker.dart';
import 'ai_params_dialog.dart';

/// Opens the batch tagging dialog. The states are passed explicitly because
/// dialogs live above the workbench's provider subtree. Reopening while a run
/// is active shows the live progress of that run.
Future<void> showBatchTagDialog(
  BuildContext context, {
  required AiTaggerState ai,
  required BatchTagState batch,
  required DatasetState dataset,
  required AppState appState,
}) {
  return showDialog<void>(
    context: context,
    // Closing is an explicit choice between "run in background" and cancel.
    barrierDismissible: false,
    builder: (context) => MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: ai),
        ChangeNotifierProvider.value(value: batch),
        ChangeNotifierProvider.value(value: dataset),
        ChangeNotifierProvider.value(value: appState),
      ],
      child: const _BatchTagDialog(),
    ),
  );
}

/// Content width of every view in this dialog. Wide enough that the mode
/// selector fits four segments without clipping their labels.
const double _dialogWidth = 440;

/// The title row every view of this dialog shares. Factored because there are
/// four of them and they have drifted once already: the config view was
/// retitled for description runs while the progress and summary views went on
/// calling the same run "tagging".
Widget _dialogTitle(
  BuildContext context,
  String text, {
  IconData icon = Icons.auto_awesome_motion,
  Color? color,
}) => Row(
  children: [
    Icon(icon, size: 18, color: color ?? context.semantic.muted),
    const SizedBox(width: 8),
    Expanded(child: Text(text, style: const TextStyle(fontSize: 15))),
  ],
);

/// The label a rule set shows in the picker: its character name, else the
/// trigger word it writes, else a placeholder.
String mergeRulesLabel(AppLocalizations l10n, CharacterMergeRules rules) {
  if (rules.character.trim().isNotEmpty) return rules.character.trim();
  if (rules.triggerWord.trim().isNotEmpty) return rules.triggerWord.trim();
  return l10n.batchTagRulesUnnamed;
}

class _BatchTagDialog extends StatefulWidget {
  const _BatchTagDialog();

  @override
  State<_BatchTagDialog> createState() => _BatchTagDialogState();
}

class _BatchTagDialogState extends State<_BatchTagDialog> {
  late final BatchTagState _batch;
  late final TextEditingController _preservedController;
  late final TextEditingController _keepFirstNController;
  late final TextEditingController _blacklistController;

  /// Whether this dialog instance is showing the progress/summary of a run —
  /// true after pressing start, or when opened onto an already-running batch.
  bool _started = false;
  bool _onlyFiltered = false;

  @override
  void initState() {
    super.initState();
    _batch = context.read<BatchTagState>();
    _started = _batch.running;
    _preservedController = TextEditingController(
      text: _batch.preservedTags.join(', '),
    );
    _keepFirstNController = TextEditingController(
      text: _batch.keepFirstN.toString(),
    );
    _blacklistController = TextEditingController(
      text: _batch.blacklist.join(', '),
    );
    final ai = context.read<AiTaggerState>();
    // First open: fetch the model list so the picker has content.
    if (ai.models.isEmpty && !ai.loadingModels) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ai.refreshModels();
      });
    }
  }

  @override
  void dispose() {
    // Persist free-text fields on close; setters are no-ops when unchanged.
    _persistFields();
    _preservedController.dispose();
    _keepFirstNController.dispose();
    _blacklistController.dispose();
    super.dispose();
  }

  void _persistFields() {
    _batch.setPreservedTagsFromInput(_preservedController.text);
    _batch.setKeepFirstN(int.tryParse(_keepFirstNController.text) ?? 0);
    _batch.setBlacklistFromInput(_blacklistController.text);
  }

  /// The run targets the active subdirectory scope, not the whole dataset —
  /// same rule as every other batch operation.
  List<File> _targetFiles(DatasetState dataset) =>
      _onlyFiltered ? dataset.visibleFiles : dataset.scopedFiles;

  void _start() {
    final l10n = AppLocalizations.of(context)!;
    final dataset = context.read<DatasetState>();
    _persistFields();
    final files = List.of(_targetFiles(dataset));
    final describing = _batch.describing;
    setState(() => _started = true);
    // Not awaited: the dialog follows the run through the state's notifies.
    // The state has no l10n of its own, so every string a run can surface is
    // handed to it here — the same way the undo label always has been.
    _batch.run(
      files: files,
      operationLabel: describing
          ? l10n.batchTagProseOperationLabel
          : l10n.batchTagOperationLabel,
      emptyDescriptionMessage: l10n.aiDescribeEmpty,
      unsupportedFormatMessage: l10n.batchTagJsonUnsupported,
      wrongModelMessage: describing
          ? l10n.aiCaptionModelRequired
          : l10n.aiTagModelRequired,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final batch = context.watch<BatchTagState>();
    if (batch.running) return _progressView(context, l10n, batch);
    if (_started) return _summaryView(context, l10n, batch);
    return _configView(context, l10n, batch);
  }

  // --- Configuration --------------------------------------------------

  Widget _configView(
    BuildContext context,
    AppLocalizations l10n,
    BatchTagState batch,
  ) {
    // JSON captions have no batch path at all: a flat result cannot be
    // serialized back into a document, and merging one in would rewrite every
    // caption as a comma line. Saying so beats a start button that destroys
    // the dataset. The state owns the rule; this renders it — first, so the
    // whole configuration below (including a watch on AppState's rule sets)
    // is never assembled just to be thrown away.
    if (!batch.batchSupported) {
      return AlertDialog(
        title: _dialogTitle(context, l10n.batchTagTitle),
        content: SizedBox(
          width: _dialogWidth,
          child: Text(
            l10n.batchTagJsonUnsupported,
            style: const TextStyle(fontSize: 12.5),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.close),
          ),
        ],
      );
    }

    final semantic = context.semantic;
    final ai = context.watch<AiTaggerState>();
    final dataset = context.watch<DatasetState>();
    final filtered = dataset.visibleFiles.length != dataset.scopedFiles.length;
    final targetCount = _targetFiles(dataset).length;
    // Prose is described, not tagged: the two tag-only modes are hidden and
    // the state coerces them, so the segments must follow effectiveMode
    // rather than the persisted choice.
    final describing = batch.describing;
    final mode = batch.effectiveMode;
    final overwrite = mode == BatchTagMode.overwrite;
    final recognizeOnly = mode == BatchTagMode.recognizeOnly;
    final characterSheet = mode == BatchTagMode.characterSheet;
    // The model has to match the caption type in both directions — a tagger
    // into prose, or a caption model into tags, is the corruption this whole
    // path exists to avoid. An unknown category (older server) is trusted,
    // same as the single-image run.
    final wrongModel = ai.modelMismatches(wantCaption: describing);
    final ruleSets = context.watch<AppState>().mergeRuleSets;
    final canStart =
        ai.modelName != null &&
        targetCount > 0 &&
        !wrongModel &&
        (!characterSheet || batch.selectedRules != null);

    return AlertDialog(
      title: _dialogTitle(
        context,
        describing ? l10n.batchTagProseTitle : l10n.batchTagTitle,
      ),
      content: SizedBox(
        width: _dialogWidth,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (describing) ...[
                Text(
                  l10n.batchTagProseNote,
                  style: TextStyle(fontSize: 12, color: semantic.muted),
                ),
                const SizedBox(height: 10),
              ],
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
                              strokeWidth: 1.5,
                              color: semantic.muted,
                            ),
                          )
                        : const Icon(Icons.refresh, size: 18),
                    tooltip: l10n.aiRefreshModels,
                    color: semantic.muted,
                    onPressed: ai.loadingModels ? null : ai.refreshModels,
                  ),
                ],
              ),
              if (wrongModel)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    describing
                        ? l10n.aiCaptionModelRequired
                        : l10n.aiTagModelRequired,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              const SizedBox(height: 4),
              Row(
                children: [
                  // Threshold, ignore list and tag normalization are tag
                  // settings; none of them touches a description. The hint
                  // goes, the flex slot stays so the button keeps its place.
                  if (describing)
                    const Spacer()
                  else
                    Expanded(
                      child: Text(
                        l10n.batchTagParamsHint,
                        style: TextStyle(fontSize: 11.5, color: semantic.muted),
                      ),
                    ),
                  TextButton(
                    onPressed: () => showAiParamsDialog(
                      context,
                      context.read<AiTaggerState>(),
                    ),
                    child: Text(
                      l10n.batchTagOpenParams,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _FieldLabel(text: l10n.batchTagModeLabel),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<BatchTagMode>(
                  segments: [
                    ButtonSegment(
                      value: BatchTagMode.append,
                      icon: const Icon(Icons.playlist_add, size: 15),
                      label: Text(
                        l10n.batchTagModeAppend,
                        style: const TextStyle(fontSize: 12.5),
                      ),
                    ),
                    ButtonSegment(
                      value: BatchTagMode.overwrite,
                      icon: const Icon(Icons.published_with_changes, size: 15),
                      label: Text(
                        l10n.batchTagModeOverwrite,
                        style: const TextStyle(fontSize: 12.5),
                      ),
                    ),
                    // Neither survives a prose caption: compare mode diffs tag
                    // sets, and a character sheet is a rule set over tags.
                    if (!describing) ...[
                      ButtonSegment(
                        value: BatchTagMode.recognizeOnly,
                        icon: const Icon(Icons.compare_arrows, size: 15),
                        label: Text(
                          l10n.batchTagModeRecognize,
                          style: const TextStyle(fontSize: 12.5),
                        ),
                      ),
                      ButtonSegment(
                        value: BatchTagMode.characterSheet,
                        icon: const Icon(Icons.rule, size: 15),
                        label: Text(
                          l10n.batchTagModeSheet,
                          style: const TextStyle(fontSize: 12.5),
                        ),
                      ),
                    ],
                  ],
                  selected: {mode},
                  onSelectionChanged: (set) => batch.setMode(set.first),
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                describing
                    ? (overwrite
                          ? l10n.batchTagModeOverwriteProseDesc
                          : l10n.batchTagModeAppendProseDesc)
                    : characterSheet
                    ? l10n.batchTagModeSheetDesc
                    : recognizeOnly
                    ? l10n.batchTagModeRecognizeDesc
                    : overwrite
                    ? l10n.batchTagModeOverwriteDesc
                    : l10n.batchTagModeAppendDesc,
                style: TextStyle(fontSize: 11.5, color: semantic.muted),
              ),
              const SizedBox(height: 14),
              // The preserved / keep-first-N / blacklist fields are all tag
              // lists: a description has nothing to match them against, and
              // recognize-only writes no caption at all. Both render nothing
              // here rather than an empty placeholder widget.
              if (characterSheet)
                _SheetSection(batch: batch, ruleSets: ruleSets)
              else if (!describing && !recognizeOnly) ...[
                if (overwrite) ...[
                  _FieldLabel(text: l10n.batchTagPreservedLabel),
                  TextField(
                    controller: _preservedController,
                    style: const TextStyle(fontSize: 13),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n.batchTagPreservedDesc,
                    style: TextStyle(fontSize: 11.5, color: semantic.muted),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          l10n.batchTagKeepFirstN,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      SizedBox(
                        width: 64,
                        child: TextField(
                          controller: _keepFirstNController,
                          style: const TextStyle(fontSize: 13),
                          textAlign: TextAlign.center,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                        ),
                      ),
                    ],
                  ),
                ] else ...[
                  _FieldLabel(text: l10n.batchTagBlacklistLabel),
                  TextField(
                    controller: _blacklistController,
                    style: const TextStyle(fontSize: 13),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n.batchTagBlacklistDesc,
                    style: TextStyle(fontSize: 11.5, color: semantic.muted),
                  ),
                ],
              ],
              const SizedBox(height: 10),
              const Divider(),
              // The target count alone would not say *why* it is smaller
              // than the dataset.
              if (dataset.activeSubdirectory != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 2),
                  child: Text(
                    l10n.subdirScopeNotice(
                      subdirectoryLabel(l10n, dataset.activeSubdirectory),
                    ),
                    style: TextStyle(
                      fontSize: 11.5,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              if (filtered)
                Row(
                  children: [
                    SizedBox(
                      width: 30,
                      height: 26,
                      child: Checkbox(
                        value: _onlyFiltered,
                        visualDensity: VisualDensity.compact,
                        onChanged: (v) =>
                            setState(() => _onlyFiltered = v ?? false),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        l10n.batchTagScopeFiltered(dataset.visibleFiles.length),
                        style: const TextStyle(fontSize: 12.5),
                      ),
                    ),
                  ],
                ),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  l10n.batchTagTargetCount(targetCount),
                  style: TextStyle(fontSize: 11.5, color: semantic.muted),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: canStart ? _start : null,
          child: Text(l10n.batchTagStart),
        ),
      ],
    );
  }

  // --- Progress --------------------------------------------------------

  Widget _progressView(
    BuildContext context,
    AppLocalizations l10n,
    BatchTagState batch,
  ) {
    final semantic = context.semantic;
    final scheme = Theme.of(context).colorScheme;
    final current = batch.currentPath;

    return AlertDialog(
      title: _dialogTitle(
        context,
        batch.describing ? l10n.batchTagProseTitle : l10n.batchTagTitle,
      ),
      content: SizedBox(
        width: _dialogWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LinearProgressIndicator(value: batch.progress),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    current == null ? '' : p.basename(current),
                    overflow: TextOverflow.ellipsis,
                    style: monoStyle(
                      context,
                      size: 11.5,
                      color: semantic.muted,
                    ),
                  ),
                ),
                Text(
                  '${batch.completed} / ${batch.total}',
                  style: monoStyle(
                    context,
                    size: 11.5,
                    color: scheme.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              l10n.batchTagProgressCounts(batch.changed, batch.failed),
              style: TextStyle(fontSize: 11.5, color: semantic.muted),
            ),
            if (batch.lastError != null) ...[
              const SizedBox(height: 6),
              Text(
                batch.lastError!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, color: scheme.error),
              ),
            ],
            const SizedBox(height: 6),
            Text(
              l10n.aiFirstRunHint,
              style: TextStyle(fontSize: 11.5, color: semantic.muted),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.batchTagHide),
        ),
        TextButton(
          onPressed: batch.cancelRequested ? null : batch.requestCancel,
          child: Text(
            batch.cancelRequested
                ? l10n.batchTagCancelling
                : l10n.batchTagCancel,
          ),
        ),
      ],
    );
  }

  // --- Summary ---------------------------------------------------------

  Widget _summaryView(
    BuildContext context,
    AppLocalizations l10n,
    BatchTagState batch,
  ) {
    final semantic = context.semantic;
    final scheme = Theme.of(context).colorScheme;
    final hasFailures = batch.failed > 0;
    final describing = batch.describing;
    // The run followed [effectiveMode], so the summary has to as well: a
    // persisted recognize-only choice under a prose type still described and
    // rewrote every caption, and reporting it as a recognize run would claim
    // nothing was written and point at a compare mode that never opened.
    final recognizeOnly = batch.effectiveMode == BatchTagMode.recognizeOnly;

    return AlertDialog(
      title: _dialogTitle(
        context,
        describing ? l10n.batchTagProseDoneTitle : l10n.batchTagDoneTitle,
        icon: hasFailures ? Icons.error_outline : Icons.check_circle_outline,
        color: hasFailures ? semantic.warn : semantic.ok,
      ),
      content: SizedBox(
        width: _dialogWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              recognizeOnly
                  ? l10n.batchTagRecognizeDoneSummary(
                      batch.completed,
                      batch.changed,
                      batch.failed,
                    )
                  : l10n.batchTagDoneSummary(
                      batch.completed,
                      batch.changed,
                      batch.failed,
                    ),
              style: const TextStyle(fontSize: 13),
            ),
            if (hasFailures && batch.lastError != null) ...[
              const SizedBox(height: 6),
              Text(
                batch.lastError!,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, color: scheme.error),
              ),
            ],
            if (batch.changed > 0) ...[
              const SizedBox(height: 6),
              Text(
                recognizeOnly
                    ? l10n.batchTagRecognizeDoneHint
                    : l10n.batchTagUndoHint,
                style: TextStyle(fontSize: 11.5, color: semantic.muted),
              ),
            ],
          ],
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

/// Character-sheet mode's own controls: which rule set to apply and how much
/// benefit of the doubt its outfit items get.
class _SheetSection extends StatelessWidget {
  const _SheetSection({required this.batch, required this.ruleSets});

  final BatchTagState batch;
  final List<CharacterMergeRules> ruleSets;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final semantic = context.semantic;
    final scheme = Theme.of(context).colorScheme;

    if (ruleSets.isEmpty) {
      return Text(
        l10n.batchTagRulesEmpty,
        style: TextStyle(fontSize: 11.5, color: scheme.error),
      );
    }

    // A rule set deleted since the last run leaves the stored id dangling;
    // showing no selection is better than showing someone else's rules.
    final selected = batch.selectedRules;
    final percent = (batch.evidenceThreshold * 100).round();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldLabel(text: l10n.batchTagRulesLabel),
        SizedBox(
          width: double.infinity,
          child: DropdownButton<String>(
            value: selected?.id,
            isExpanded: true,
            hint: Text(
              l10n.batchTagRulesHint,
              style: TextStyle(fontSize: 13, color: semantic.muted),
            ),
            style: TextStyle(fontSize: 13, color: scheme.onSurface),
            onChanged: (id) => batch.setRulesId(id),
            items: [
              for (final r in ruleSets)
                DropdownMenuItem(
                  value: r.id,
                  child: Text(
                    mergeRulesLabel(l10n, r),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
        ),
        if (selected != null) ...[
          const SizedBox(height: 4),
          Text(
            l10n.batchTagRulesSummary(
              selected.identityTags.length,
              selected.garments.length,
              selected.conflictTags.length,
            ),
            style: TextStyle(fontSize: 11.5, color: semantic.muted),
          ),
        ],
        const SizedBox(height: 12),
        _FieldLabel(text: l10n.batchTagEvidenceThreshold),
        Row(
          children: [
            Expanded(
              child: Slider(
                value: batch.evidenceThreshold,
                max: 0.6,
                divisions: 12,
                onChanged: batch.setEvidenceThreshold,
              ),
            ),
            SizedBox(
              width: 40,
              child: Text(
                '$percent%',
                textAlign: TextAlign.right,
                style: monoStyle(context, size: 11.5),
              ),
            ),
          ],
        ),
        Text(
          l10n.batchTagEvidenceThresholdDesc,
          style: TextStyle(fontSize: 11.5, color: semantic.muted),
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.warning_amber, size: 14, color: semantic.warn),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                l10n.batchTagSheetOverwriteWarning,
                style: TextStyle(fontSize: 11.5, color: semantic.warn),
              ),
            ),
          ],
        ),
      ],
    );
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
