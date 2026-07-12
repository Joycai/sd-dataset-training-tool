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
    final appState = context.watch<AppState>();
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
          Flexible(
            child: Text(
              parts.join('  ·  '),
              overflow: TextOverflow.ellipsis,
              style: monoStyle(context, size: 11.5, color: semantic.muted),
            ),
          ),
          if (dataset.totalCount > 0) ...[
            const SizedBox(width: 18),
            Text(
              l10n.taggedProgress(dataset.taggedCount, dataset.totalCount),
              style: monoStyle(context, size: 11.5, color: semantic.muted),
            ),
          ],
          const Spacer(),
          Text(
            appState.autoSave ? l10n.autoSaveOnStatus : l10n.autoSaveOffStatus,
            style: monoStyle(
              context,
              size: 11.5,
              color: appState.autoSave ? semantic.ok : semantic.muted,
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
