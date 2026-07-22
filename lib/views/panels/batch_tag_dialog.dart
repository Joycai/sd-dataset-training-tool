import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../state/ai_tagger_state.dart';
import '../../state/batch_tag_state.dart';
import '../../state/dataset_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/model_picker.dart';
import 'ai_params_dialog.dart';

/// Opens the batch tagging dialog. The states are passed explicitly because
/// dialogs live above the workbench's provider subtree. Reopening while a run
/// is active shows the live progress of that run.
Future<void> showBatchTagDialog(
  BuildContext context, {
  required AiTaggerState ai,
  required BatchTagState batch,
  required DatasetState dataset,
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
      ],
      child: const _BatchTagDialog(),
    ),
  );
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
    _preservedController =
        TextEditingController(text: _batch.preservedTags.join(', '));
    _keepFirstNController =
        TextEditingController(text: _batch.keepFirstN.toString());
    _blacklistController =
        TextEditingController(text: _batch.blacklist.join(', '));
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

  List<String> _targetPaths(DatasetState dataset) {
    final files = _onlyFiltered ? dataset.visibleFiles : dataset.allFiles;
    return [for (final f in files) f.path];
  }

  void _start() {
    final l10n = AppLocalizations.of(context)!;
    final dataset = context.read<DatasetState>();
    _persistFields();
    final files =
        List.of(_onlyFiltered ? dataset.visibleFiles : dataset.allFiles);
    setState(() => _started = true);
    // Not awaited: the dialog follows the run through the state's notifies.
    _batch.run(files: files, operationLabel: l10n.batchTagOperationLabel);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final batch = context.watch<BatchTagState>();
    if (batch.running) return _progressView(context, l10n, batch);
    if (_started) return _summaryView(context, l10n, batch);
    return _configView(context, l10n);
  }

  // --- Configuration --------------------------------------------------

  Widget _configView(BuildContext context, AppLocalizations l10n) {
    final semantic = context.semantic;
    final ai = context.watch<AiTaggerState>();
    final batch = context.watch<BatchTagState>();
    final dataset = context.watch<DatasetState>();
    final filtered = dataset.visibleFiles.length != dataset.allFiles.length;
    final targetCount = _targetPaths(dataset).length;
    final canStart = ai.modelName != null && targetCount > 0;
    final overwrite = batch.mode == BatchTagMode.overwrite;

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.auto_awesome_motion, size: 18, color: semantic.muted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(l10n.batchTagTitle,
                style: const TextStyle(fontSize: 15)),
          ),
        ],
      ),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _FieldLabel(text: l10n.aiModelLabel),
              Row(
                children: [
                  Expanded(child: ModelPickerField(ai: ai, l10n: l10n)),
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
                    onPressed: ai.loadingModels ? null : ai.refreshModels,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.batchTagParamsHint,
                      style: TextStyle(fontSize: 11.5, color: semantic.muted),
                    ),
                  ),
                  TextButton(
                    onPressed: () => showAiParamsDialog(
                        context, context.read<AiTaggerState>()),
                    child: Text(l10n.batchTagOpenParams,
                        style: const TextStyle(fontSize: 12)),
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
                      label: Text(l10n.batchTagModeAppend,
                          style: const TextStyle(fontSize: 12.5)),
                    ),
                    ButtonSegment(
                      value: BatchTagMode.overwrite,
                      icon: const Icon(Icons.published_with_changes, size: 15),
                      label: Text(l10n.batchTagModeOverwrite,
                          style: const TextStyle(fontSize: 12.5)),
                    ),
                  ],
                  selected: {batch.mode},
                  onSelectionChanged: (set) => batch.setMode(set.first),
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                overwrite
                    ? l10n.batchTagModeOverwriteDesc
                    : l10n.batchTagModeAppendDesc,
                style: TextStyle(fontSize: 11.5, color: semantic.muted),
              ),
              const SizedBox(height: 14),
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
                      child: Text(l10n.batchTagKeepFirstN,
                          style: const TextStyle(fontSize: 13)),
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
              const SizedBox(height: 10),
              const Divider(),
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
                        l10n.batchTagScopeFiltered(
                            dataset.visibleFiles.length),
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
      BuildContext context, AppLocalizations l10n, BatchTagState batch) {
    final semantic = context.semantic;
    final scheme = Theme.of(context).colorScheme;
    final current = batch.currentPath;

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.auto_awesome_motion, size: 18, color: semantic.muted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(l10n.batchTagTitle,
                style: const TextStyle(fontSize: 15)),
          ),
        ],
      ),
      content: SizedBox(
        width: 400,
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
                    style: monoStyle(context, size: 11.5,
                        color: semantic.muted),
                  ),
                ),
                Text(
                  '${batch.completed} / ${batch.total}',
                  style: monoStyle(context, size: 11.5,
                      color: scheme.onSurface),
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
          child: Text(batch.cancelRequested
              ? l10n.batchTagCancelling
              : l10n.batchTagCancel),
        ),
      ],
    );
  }

  // --- Summary ---------------------------------------------------------

  Widget _summaryView(
      BuildContext context, AppLocalizations l10n, BatchTagState batch) {
    final semantic = context.semantic;
    final scheme = Theme.of(context).colorScheme;
    final hasFailures = batch.failed > 0;

    return AlertDialog(
      title: Row(
        children: [
          Icon(
            hasFailures ? Icons.error_outline : Icons.check_circle_outline,
            size: 18,
            color: hasFailures ? semantic.warn : semantic.ok,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(l10n.batchTagDoneTitle,
                style: const TextStyle(fontSize: 15)),
          ),
        ],
      ),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.batchTagDoneSummary(
                  batch.completed, batch.changed, batch.failed),
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
                l10n.batchTagUndoHint,
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
