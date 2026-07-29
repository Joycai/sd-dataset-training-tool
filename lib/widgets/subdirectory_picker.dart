import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../state/dataset_state.dart';
import '../theme/app_theme.dart';

/// Human-readable name of a subdirectory scope: null is the whole dataset,
/// the empty path is the dataset root itself.
String subdirectoryLabel(AppLocalizations l10n, String? path) {
  if (path == null) return l10n.subdirAll;
  return path.isEmpty ? l10n.subdirRoot : path;
}

/// The navigator's scope switcher, shown only when the scan found images in
/// more than one directory.
///
/// It is deliberately the *first* control in the panel: picking a folder does
/// not just filter the gallery, it narrows the tag index and every batch
/// operation in the app, so it reads as the frame everything below sits in
/// rather than as one more filter next to the search box.
class SubdirectoryPicker extends StatelessWidget {
  const SubdirectoryPicker({super.key, required this.dataset});

  final DatasetState dataset;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final semantic = context.semantic;
    final scheme = Theme.of(context).colorScheme;
    final scoped = dataset.activeSubdirectory != null;

    return Tooltip(
      message: l10n.subdirPickerTooltip,
      waitDuration: const Duration(milliseconds: 600),
      child: Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: semantic.raised,
          border: Border.all(
            color: scoped ? scheme.primary.withAlpha(140) : semantic.line,
          ),
          borderRadius: BorderRadius.circular(AppRadii.input),
        ),
        child: Row(
          children: [
            Icon(
              scoped ? Icons.folder : Icons.folder_copy_outlined,
              size: 14,
              color: scoped ? scheme.primary : semantic.muted,
            ),
            const SizedBox(width: 7),
            Expanded(
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String?>(
                  value: dataset.activeSubdirectory,
                  isExpanded: true,
                  isDense: true,
                  icon: Icon(
                    Icons.expand_more,
                    size: 16,
                    color: semantic.muted,
                  ),
                  style: TextStyle(
                    fontSize: AppText.secondary,
                    color: scheme.onSurface,
                  ),
                  onChanged: dataset.setSubdirectory,
                  items: [
                    _item(
                      context,
                      value: null,
                      label: l10n.subdirAll,
                      count: dataset.allFiles.length,
                    ),
                    for (final dir in dataset.subdirectories)
                      _item(
                        context,
                        value: dir.path,
                        label: subdirectoryLabel(l10n, dir.path),
                        count: dir.count,
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

  DropdownMenuItem<String?> _item(
    BuildContext context, {
    required String? value,
    required String label,
    required int count,
  }) {
    final semantic = context.semantic;
    return DropdownMenuItem<String?>(
      value: value,
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: AppText.secondary),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$count',
            style: monoStyle(
              context,
              size: AppText.micro,
              color: semantic.muted,
            ),
          ),
        ],
      ),
    );
  }
}
