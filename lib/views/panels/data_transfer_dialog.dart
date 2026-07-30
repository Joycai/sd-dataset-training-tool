import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../l10n/app_localizations.dart';
import '../../models/data_bundle.dart';
import '../../services/data_transfer.dart';
import '../../theme/app_theme.dart';
import '../../widgets/panel_widgets.dart';

/// Export: pick the sections, then a destination, then write one JSON file.
///
/// The picker comes *before* the file dialog so the user is never asked where
/// to save something whose contents they have not chosen yet.
Future<void> showDataExportDialog(BuildContext context) async {
  final appState = context.read<AppState>();
  final l10n = AppLocalizations.of(context)!;
  final messenger = ScaffoldMessenger.of(context);

  final choice = await showDialog<_ExportChoice>(
    context: context,
    builder: (_) => _ExportDialog(appState: appState),
  );
  if (choice == null || choice.sections.isEmpty) return;

  final bundle = await DataTransfer(appState).collect(
    sections: choice.sections,
    includeApiKeys: choice.includeApiKeys,
  );
  final path = await FilePicker.saveFile(
    fileName: 'dataset_tool_settings.json',
    type: FileType.custom,
    allowedExtensions: ['json'],
  );
  if (path == null) return;
  try {
    await File(path).writeAsString(bundle.encode());
    messenger.showSnackBar(SnackBar(content: Text(l10n.exportedTo(path))));
  } on FileSystemException catch (e) {
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.exportFailedMsg(e.message))),
    );
  }
}

/// Import: pick the file first, because what it holds decides what the dialog
/// can even offer. A file that is not one of our exports is rejected here,
/// before the user has made any choices to lose.
Future<void> showDataImportDialog(BuildContext context) async {
  final l10n = AppLocalizations.of(context)!;
  final messenger = ScaffoldMessenger.of(context);

  final result = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['json'],
  );
  final path = result?.files.single.path;
  if (path == null) return;

  final String text;
  try {
    text = await File(path).readAsString();
  } on FileSystemException catch (e) {
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.importFailedMsg(e.message))),
    );
    return;
  }
  if (!context.mounted) return;
  await runDataImport(context, text);
}

/// Everything after the file has been read: parse, ask, apply, report.
///
/// Split from [showDataImportDialog] so the choice dialog and the merge
/// semantics can be driven in a test without an OS file picker in the way.
@visibleForTesting
Future<void> runDataImport(BuildContext context, String text) async {
  final appState = context.read<AppState>();
  final l10n = AppLocalizations.of(context)!;
  final messenger = ScaffoldMessenger.of(context);

  final DataBundle bundle;
  try {
    bundle = DataBundle.decode(text);
  } on FormatException catch (e) {
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.importFailedMsg(e.message))),
    );
    return;
  }
  if (bundle.isEmpty) {
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.importFailedMsg(l10n.dataSectionMissing))),
    );
    return;
  }
  if (!context.mounted) return;

  final choice = await showDialog<_ImportChoice>(
    context: context,
    builder: (_) => _ImportDialog(bundle: bundle),
  );
  if (choice == null || choice.sections.isEmpty) return;

  final report = await DataTransfer(appState).apply(
    bundle,
    sections: choice.sections,
    mode: choice.mode,
  );
  if (!context.mounted) return;
  await _showReport(context, bundle, choice, report);
}

Future<void> _showReport(
  BuildContext context,
  DataBundle bundle,
  _ImportChoice choice,
  DataImportReport report,
) {
  final l10n = AppLocalizations.of(context)!;
  final lines = <String>[
    if (report.isEmpty) l10n.dataImportNothingChanged,
    if (choice.sections.contains(DataSection.llm) &&
        bundle.has(DataSection.llm))
      l10n.dataImportReportLlm(
        report.providersAdded,
        report.providersUpdated,
        report.modelsAdded,
      ),
    if (choice.sections.contains(DataSection.tagLibrary) &&
        bundle.has(DataSection.tagLibrary))
      l10n.dataImportReportLibrary(
        report.tagsAdded,
        report.groupsCreated,
        report.customTagsAdded,
        report.translationsWritten,
      ),
    if (choice.sections.contains(DataSection.promptPresets) &&
        bundle.has(DataSection.promptPresets))
      l10n.dataImportReportPresets(report.presetsAdded, report.presetsUpdated),
  ];
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(l10n.dataImportDoneTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(line, style: const TextStyle(fontSize: 13)),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(l10n.close),
        ),
      ],
    ),
  );
}

class _ExportChoice {
  const _ExportChoice({required this.sections, required this.includeApiKeys});

  final Set<DataSection> sections;
  final bool includeApiKeys;
}

class _ImportChoice {
  const _ImportChoice({required this.sections, required this.mode});

  final Set<DataSection> sections;
  final DataImportMode mode;
}

class _ExportDialog extends StatefulWidget {
  const _ExportDialog({required this.appState});

  final AppState appState;

  @override
  State<_ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends State<_ExportDialog> {
  final Set<DataSection> _selected = {...DataSection.values};
  bool _includeApiKeys = true;

  /// Translation counts live behind an async directory walk, so the summary
  /// line starts without them and fills in. Everything else is already in
  /// memory and renders on the first frame.
  int? _translationCount;

  @override
  void initState() {
    super.initState();
    _countTranslations();
  }

  Future<void> _countTranslations() async {
    final service = widget.appState.tagTranslations;
    var total = 0;
    for (final code in await service.storedLanguages()) {
      try {
        total += (await service.entriesFor(code)).length;
      } catch (_) {
        // Unreadable glossaries are left out of the export too.
      }
    }
    if (mounted) setState(() => _translationCount = total);
  }

  void _toggle(DataSection section, bool? value) {
    setState(() {
      if (value ?? false) {
        _selected.add(section);
      } else {
        _selected.remove(section);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final semantic = context.semantic;
    final state = widget.appState;
    final groupedTags = state.tagGroups.fold(0, (n, g) => n + g.tags.length);

    return GlassDialog(
      width: 460,
      header: Text(
        l10n.dataExportDialogTitle,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.dataExportPick,
            style: TextStyle(fontSize: 12.5, color: semantic.muted),
          ),
          const SizedBox(height: 10),
          _SectionCheckbox(
            label: l10n.dataSectionLlm,
            summary: l10n.dataSectionLlmSummary(
              state.llmProviders.length,
              state.llmProfiles.length,
            ),
            value: _selected.contains(DataSection.llm),
            onChanged: (v) => _toggle(DataSection.llm, v),
          ),
          if (_selected.contains(DataSection.llm))
            Padding(
              padding: const EdgeInsets.only(left: 30, bottom: 4),
              child: _SectionCheckbox(
                label: l10n.dataExportApiKeys,
                summary: l10n.dataExportApiKeysHint,
                value: _includeApiKeys,
                onChanged: (v) =>
                    setState(() => _includeApiKeys = v ?? false),
              ),
            ),
          _SectionCheckbox(
            label: l10n.dataSectionTagLibrary,
            summary: l10n.dataSectionTagLibrarySummary(
              groupedTags + state.ungroupedTags.length,
              state.tagGroups.length,
              state.tagDictionary.customEntries.length,
              _translationCount ?? 0,
            ),
            value: _selected.contains(DataSection.tagLibrary),
            onChanged: (v) => _toggle(DataSection.tagLibrary, v),
          ),
          _SectionCheckbox(
            label: l10n.dataSectionPresets,
            summary: l10n.dataSectionPresetsSummary(state.promptPresets.length),
            value: _selected.contains(DataSection.promptPresets),
            onChanged: (v) => _toggle(DataSection.promptPresets, v),
          ),
          const SizedBox(height: 10),
          Text(
            l10n.dataExportExcludes,
            style: TextStyle(fontSize: 11.5, color: semantic.muted),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        const SizedBox(width: 6),
        FilledButton(
          onPressed: _selected.isEmpty
              ? null
              : () => Navigator.of(context).pop(
                  _ExportChoice(
                    sections: _selected,
                    includeApiKeys: _includeApiKeys,
                  ),
                ),
          child: Text(l10n.dataExportConfirm),
        ),
      ],
    );
  }
}

class _ImportDialog extends StatefulWidget {
  const _ImportDialog({required this.bundle});

  final DataBundle bundle;

  @override
  State<_ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends State<_ImportDialog> {
  late final Set<DataSection> _selected = {...widget.bundle.sections};
  DataImportMode _mode = DataImportMode.merge;

  void _toggle(DataSection section, bool? value) {
    setState(() {
      if (value ?? false) {
        _selected.add(section);
      } else {
        _selected.remove(section);
      }
    });
  }

  String _summaryFor(AppLocalizations l10n, DataSection section) {
    final bundle = widget.bundle;
    if (!bundle.has(section)) return l10n.dataSectionMissing;
    return switch (section) {
      DataSection.llm => l10n.dataSectionLlmSummary(
        bundle.providerCount,
        bundle.modelCount,
      ),
      DataSection.tagLibrary => l10n.dataSectionTagLibrarySummary(
        bundle.tagLibrary!.tagCount,
        bundle.tagLibrary!.groups.length,
        bundle.tagLibrary!.customTags.length,
        bundle.tagLibrary!.translationCount,
      ),
      DataSection.promptPresets => l10n.dataSectionPresetsSummary(
        bundle.presetCount,
      ),
    };
  }

  String _labelFor(AppLocalizations l10n, DataSection section) =>
      switch (section) {
        DataSection.llm => l10n.dataSectionLlm,
        DataSection.tagLibrary => l10n.dataSectionTagLibrary,
        DataSection.promptPresets => l10n.dataSectionPresets,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final semantic = context.semantic;
    final bundle = widget.bundle;
    final exportedAt = bundle.exportedAt;

    return GlassDialog(
      width: 460,
      header: Text(
        l10n.dataImportDialogTitle,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (bundle.appVersion.isNotEmpty && exportedAt != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                l10n.dataImportSource(
                  bundle.appVersion,
                  _formatDate(exportedAt),
                ),
                style: TextStyle(fontSize: 12.5, color: semantic.muted),
              ),
            ),
          for (final section in DataSection.values)
            _SectionCheckbox(
              label: _labelFor(l10n, section),
              summary: _summaryFor(l10n, section),
              value: _selected.contains(section),
              onChanged: bundle.has(section)
                  ? (v) => _toggle(section, v)
                  : null,
            ),
          if (bundle.has(DataSection.llm) && !bundle.hasApiKeys)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                l10n.dataImportNoKeys,
                style: TextStyle(fontSize: 11.5, color: semantic.muted),
              ),
            ),
          const SizedBox(height: 14),
          Text(
            l10n.dataImportMode,
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          SegmentedControl<DataImportMode>(
            value: _mode,
            fontSize: 12.5,
            verticalPadding: 5,
            segments: [
              SegmentedOption(
                value: DataImportMode.merge,
                label: l10n.dataImportModeMerge,
              ),
              SegmentedOption(
                value: DataImportMode.overwrite,
                label: l10n.dataImportModeOverwrite,
              ),
            ],
            onChanged: (value) => setState(() => _mode = value),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.dataImportModeHint,
            style: TextStyle(fontSize: 11.5, color: semantic.muted),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        const SizedBox(width: 6),
        FilledButton(
          onPressed: _selected.isEmpty
              ? null
              : () => Navigator.of(
                  context,
                ).pop(_ImportChoice(sections: _selected, mode: _mode)),
          child: Text(l10n.dataImportConfirm),
        ),
      ],
    );
  }
}

/// Deliberately not `intl`'s date formatting: this is a provenance line, not a
/// date the user does anything with, and an ISO-ish day reads the same in
/// every locale the app ships.
String _formatDate(DateTime value) {
  final local = value.toLocal();
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  return '${local.year}-$month-$day';
}

/// One selectable section: a checkbox, its name, and a line saying how much is
/// in it — the number is the whole reason the picker exists, since "tag
/// library" alone does not tell the user whether it is worth carrying.
class _SectionCheckbox extends StatelessWidget {
  const _SectionCheckbox({
    required this.label,
    required this.summary,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String summary;
  final bool value;

  /// Null disables the row — an import file that does not carry the section.
  final ValueChanged<bool?>? onChanged;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    final enabled = onChanged != null;
    return InkWell(
      onTap: enabled ? () => onChanged!(!value) : null,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 30,
              height: 30,
              child: Checkbox(
                value: enabled && value,
                onChanged: onChanged,
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: enabled ? null : semantic.muted,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      summary,
                      style: TextStyle(fontSize: 11.5, color: semantic.muted),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
