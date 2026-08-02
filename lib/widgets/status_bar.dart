import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../state/ai_tagger_state.dart';
import '../state/dataset_state.dart';
import '../state/editor_session.dart';
import '../theme/app_theme.dart';
import '../utils/platform_shortcuts.dart';

/// Bottom status bar: how far the dataset is tagged, whether the tagger
/// service is reachable, and the always-on shortcut reminder.
///
/// File facts (name, resolution, size) live on the canvas overlay instead —
/// they belong to the image being looked at, not to the session.
class StatusBar extends StatelessWidget {
  const StatusBar({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final semantic = context.semantic;
    final dataset = context.watch<DatasetState>();
    final session = context.watch<EditorSession>();
    final ai = context.watch<AiTaggerState>();

    // The service exposes no explicit connection flag: a populated model
    // list is the proof that a request round-tripped.
    final connected = ai.models.isNotEmpty && ai.lastError == null;
    final address = Uri.tryParse(ai.serverUrl)?.authority ?? ai.serverUrl;
    final tagged = dataset.taggedCount == dataset.totalCount;

    return Container(
      height: AppMetrics.statusBar,
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
                if (dataset.totalCount > 0) ...[
                  _Dot(color: tagged ? semantic.ok : semantic.warn),
                  const SizedBox(width: 7),
                  Text(
                    l10n.taggedProgress(
                      dataset.taggedCount,
                      dataset.totalCount,
                    ),
                    style: monoStyle(
                      context,
                      size: AppText.small,
                      color: semantic.muted,
                    ),
                  ),
                  const SizedBox(width: 18),
                ],
                if (dataset.tagFilterActive) ...[
                  _Dot(color: semantic.warn),
                  const SizedBox(width: 7),
                  Text(
                    l10n.filterStatus(
                      dataset.visibleFiles.length,
                      dataset.totalCount,
                    ),
                    style: monoStyle(
                      context,
                      size: AppText.small,
                      color: semantic.warn,
                    ),
                  ),
                  const SizedBox(width: 18),
                ],
                _Dot(color: connected ? semantic.ok : semantic.muted),
                const SizedBox(width: 7),
                Flexible(
                  child: Text(
                    '${connected ? l10n.aiServiceConnected : l10n.aiServiceOffline}'
                    '  ·  $address',
                    overflow: TextOverflow.ellipsis,
                    style: monoStyle(
                      context,
                      size: AppText.small,
                      color: semantic.muted,
                    ),
                  ),
                ),
                if (session.anchorTag != null) ...[
                  const SizedBox(width: 18),
                  Flexible(
                    child: _AnchorPill(session: session, l10n: l10n),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 18),
          Text(
            l10n.shortcutHints(primaryModifierLabel),
            style: monoStyle(
              context,
              size: AppText.small,
              color: semantic.muted,
            ),
          ),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
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
        borderRadius: BorderRadius.circular(AppRadii.pill),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1.5),
          decoration: BoxDecoration(
            color: scheme.primary.withAlpha(31),
            border: Border.all(color: scheme.primary.withAlpha(115)),
            borderRadius: BorderRadius.circular(AppRadii.pill),
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
                  style: monoStyle(
                    context,
                    size: AppText.small,
                    color: scheme.primary,
                  ),
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
