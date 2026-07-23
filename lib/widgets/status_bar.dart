import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../l10n/app_localizations.dart';
import '../state/dataset_state.dart';
import '../state/editor_session.dart';
import '../theme/app_theme.dart';

/// Bottom status bar: current file facts, dataset tagging progress, and the
/// autosave state.
class StatusBar extends StatelessWidget {
  const StatusBar({super.key});

  String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024).round()} KB';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final semantic = context.semantic;
    // Only the autosave flag matters here; a full watch would rebuild the
    // bar on every AppState notification (e.g. tag-library edits).
    final autoSave = context.select<AppState, bool>((s) => s.autoSave);
    final dataset = context.watch<DatasetState>();
    final session = context.watch<EditorSession>();

    final file = dataset.selectedFile;
    final parts = <String>[];
    if (file != null) {
      parts.add(p.basename(file.path));
      if (session.imageWidth != null) {
        parts.add('${session.imageWidth} x ${session.imageHeight}');
      }
      if (session.imageBytes != null) {
        parts.add(_formatBytes(session.imageBytes!));
      }
    }

    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: semantic.panel,
        border: Border(top: BorderSide(color: semantic.line)),
      ),
      child: Row(
        children: [
          // One flex slot for the whole left group keeps the unused width
          // inside it, so the right-side hints stay flush right.
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    parts.join('  ·  '),
                    overflow: TextOverflow.ellipsis,
                    style: monoStyle(
                      context,
                      size: 11.5,
                      color: semantic.muted,
                    ),
                  ),
                ),
                if (dataset.totalCount > 0) ...[
                  const SizedBox(width: 18),
                  Text(
                    l10n.taggedProgress(
                      dataset.taggedCount,
                      dataset.totalCount,
                    ),
                    style: monoStyle(
                      context,
                      size: 11.5,
                      color: semantic.muted,
                    ),
                  ),
                ],
                if (session.anchorTag != null) ...[
                  const SizedBox(width: 18),
                  Flexible(child: _AnchorPill(session: session, l10n: l10n)),
                ],
              ],
            ),
          ),
          const SizedBox(width: 18),
          Text(
            autoSave ? l10n.autoSaveOnStatus : l10n.autoSaveOffStatus,
            style: monoStyle(
              context,
              size: 11.5,
              color: autoSave ? semantic.ok : semantic.muted,
            ),
          ),
          const SizedBox(width: 18),
          Text(
            l10n.saveShortcutHint,
            style: monoStyle(context, size: 11.5, color: semantic.muted),
          ),
        ],
      ),
    );
  }
}

/// Shows which tag new additions are anchored after, with a click-to-clear
/// affordance mirroring the holder toggle in the editor.
class _AnchorPill extends StatelessWidget {
  const _AnchorPill({required this.session, required this.l10n});

  final EditorSession session;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: l10n.anchorClearTooltip,
      waitDuration: const Duration(milliseconds: 600),
      child: InkWell(
        onTap: session.clearAnchor,
        borderRadius: BorderRadius.circular(99),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1.5),
          decoration: BoxDecoration(
            color: scheme.primary.withAlpha(31),
            border: Border.all(color: scheme.primary.withAlpha(115)),
            borderRadius: BorderRadius.circular(99),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.keyboard_tab, size: 11, color: scheme.primary),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  l10n.anchorStatusLabel(session.anchorTag!),
                  overflow: TextOverflow.ellipsis,
                  style: monoStyle(context, size: 11, color: scheme.primary),
                ),
              ),
              const SizedBox(width: 5),
              Icon(Icons.close, size: 11, color: scheme.primary),
            ],
          ),
        ),
      ),
    );
  }
}
