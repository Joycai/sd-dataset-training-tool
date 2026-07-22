import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../state/ai_tagger_state.dart';
import '../../state/editor_session.dart';
import '../../theme/app_theme.dart';

/// The AI compare mode shown inside the caption editor's tags tab: current
/// tags on the left, AI predictions on the right, with the diff highlighted.
///
/// Three chip states:
/// - new suggestion (AI only, green): click to add to the image;
/// - missing (image only, amber): the model did not predict it — a possible
///   mis-tag, or a concept outside its vocabulary; delete individually;
/// - matched (both sides, dimmed).
class AiCompareView extends StatefulWidget {
  const AiCompareView({super.key, required this.onRunAi});

  /// Triggers (re-)interrogation of the current image; owned by CaptionPanel
  /// so the run flow (model bootstrap, error snackbars) lives in one place.
  final Future<void> Function() onRunAi;

  @override
  State<AiCompareView> createState() => _AiCompareViewState();
}

class _AiCompareViewState extends State<AiCompareView> {
  bool _showNewOnly = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final semantic = context.semantic;
    final session = context.watch<EditorSession>();
    final ai = context.watch<AiTaggerState>();

    final image = session.image;
    if (image == null) return const SizedBox.shrink();

    if (ai.running) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(height: 12),
            Text(
              l10n.aiInterrogating,
              style: TextStyle(fontSize: 12.5, color: semantic.muted),
            ),
            const SizedBox(height: 4),
            Text(
              l10n.aiFirstRunHint,
              style: TextStyle(fontSize: 11.5, color: semantic.muted),
            ),
          ],
        ),
      );
    }

    final predictions = ai.resultFor(image.path);
    if (predictions == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.aiNoResultYet,
              style: TextStyle(fontSize: 12.5, color: semantic.muted),
            ),
            const SizedBox(height: 10),
            TextButton.icon(
              onPressed: widget.onRunAi,
              icon: const Icon(Icons.auto_awesome, size: 14),
              label: Text(
                l10n.aiInterrogateButton,
                style: const TextStyle(fontSize: 12.5),
              ),
            ),
          ],
        ),
      );
    }

    final diff = AiTagDiff.compute(session.tags, predictions);
    final visiblePredictions = _showNewOnly ? diff.newSuggestions : predictions;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _buildCurrentColumn(session, diff, l10n, semantic),
              ),
              const VerticalDivider(width: 1),
              Expanded(
                child: _buildAiColumn(
                  session,
                  diff,
                  visiblePredictions,
                  l10n,
                  semantic,
                ),
              ),
            ],
          ),
        ),
        const Divider(),
        _buildFooter(session, diff, l10n, semantic),
      ],
    );
  }

  Widget _buildCurrentColumn(
    EditorSession session,
    AiTagDiff diff,
    AppLocalizations l10n,
    AppSemanticColors semantic,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(
                child: _ColumnLabel(
                  text:
                      '${l10n.aiCurrentTagsHeader} · '
                      '${session.tags.length}',
                ),
              ),
              if (diff.missing.isNotEmpty) ...[
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    l10n.aiMissingCount(diff.missing.length),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: semantic.warn),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 10),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final tag in session.tags)
                    diff.missing.contains(tag)
                        ? _CompareChip.missing(
                            label: tag,
                            semantic: semantic,
                            onDelete: () => session.removeTag(tag),
                          )
                        : _CompareChip.matched(label: tag, semantic: semantic),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAiColumn(
    EditorSession session,
    AiTagDiff diff,
    List<AiPrediction> visiblePredictions,
    AppLocalizations l10n,
    AppSemanticColors semantic,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // One flex slot for both labels so the filter pill stays
              // flush right.
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: _ColumnLabel(
                        text:
                            '${l10n.aiResultHeader} · '
                            '${diff.newSuggestions.length + diff.matched.length}',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        l10n.aiNewCount(diff.newSuggestions.length),
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: semantic.ok),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _MiniFilter(
                label: l10n.aiShowNewOnly,
                selected: _showNewOnly,
                onTap: () => setState(() => _showNewOnly = !_showNewOnly),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 10),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final p in visiblePredictions)
                    session.hasTag(p.tag)
                        ? _CompareChip.matched(
                            label: p.tag,
                            probability: p.probability,
                            semantic: semantic,
                          )
                        : _CompareChip.suggestion(
                            label: p.tag,
                            probability: p.probability,
                            semantic: semantic,
                            onTap: () => session.applyTag(p.tag),
                          ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(
    EditorSession session,
    AiTagDiff diff,
    AppLocalizations l10n,
    AppSemanticColors semantic,
  ) {
    final ai = context.read<AiTaggerState>();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: Row(
        children: [
          Expanded(
            child: Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                _LegendDot(color: semantic.ok, label: l10n.aiLegendNew),
                _LegendDot(color: semantic.warn, label: l10n.aiLegendMissing),
                _LegendDot(color: semantic.line, label: l10n.aiLegendMatched),
              ],
            ),
          ),
          TextButton(
            onPressed: diff.newSuggestions.isEmpty
                ? null
                : () {
                    for (final p in diff.newSuggestions) {
                      session.applyTag(p.tag);
                    }
                  },
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              textStyle: const TextStyle(fontSize: 12),
            ),
            child: Text(l10n.aiAddAllNew(diff.newSuggestions.length)),
          ),
          TextButton.icon(
            onPressed: widget.onRunAi,
            icon: const Icon(Icons.refresh, size: 13),
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              textStyle: const TextStyle(fontSize: 12),
              foregroundColor: semantic.muted,
            ),
            label: Text(l10n.aiRerun),
          ),
          FilledButton.tonal(
            onPressed: ai.exitCompareMode,
            style: FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
              textStyle: const TextStyle(fontSize: 12),
            ),
            child: Text(l10n.aiDoneCompare),
          ),
        ],
      ),
    );
  }
}

class _ColumnLabel extends StatelessWidget {
  const _ColumnLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.3,
        color: context.semantic.muted,
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(fontSize: 11.5, color: context.semantic.muted),
        ),
      ],
    );
  }
}

class _MiniFilter extends StatelessWidget {
  const _MiniFilter({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final semantic = context.semantic;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(99),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
        decoration: BoxDecoration(
          color: selected ? scheme.primary : Colors.transparent,
          border: Border.all(color: selected ? scheme.primary : semantic.line),
          borderRadius: BorderRadius.circular(99),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: selected ? scheme.onPrimary : semantic.muted,
          ),
        ),
      ),
    );
  }
}

/// One chip in either column. The named constructors encode the three states
/// so call sites stay declarative.
class _CompareChip extends StatelessWidget {
  const _CompareChip.suggestion({
    required this.label,
    required this.semantic,
    required double this.probability,
    required VoidCallback this.onTap,
  }) : _state = _ChipState.suggestion,
       onDelete = null;

  const _CompareChip.missing({
    required this.label,
    required this.semantic,
    required VoidCallback this.onDelete,
  }) : _state = _ChipState.missing,
       probability = null,
       onTap = null;

  const _CompareChip.matched({
    required this.label,
    required this.semantic,
    this.probability,
  }) : _state = _ChipState.matched,
       onTap = null,
       onDelete = null;

  final String label;
  final double? probability;
  final AppSemanticColors semantic;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;
  final _ChipState _state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final Color background;
    final Color border;
    final Widget leading;
    switch (_state) {
      case _ChipState.suggestion:
        background = Color.alphaBlend(
          semantic.ok.withAlpha(36),
          scheme.surface,
        );
        border = semantic.ok.withAlpha(140);
        leading = Icon(Icons.add, size: 11, color: semantic.ok);
      case _ChipState.missing:
        background = Color.alphaBlend(
          semantic.warn.withAlpha(33),
          scheme.surface,
        );
        border = semantic.warn.withAlpha(140);
        leading = Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: semantic.warn,
          ),
        );
      case _ChipState.matched:
        background = scheme.surface;
        border = semantic.line;
        leading = Icon(Icons.check, size: 11, color: semantic.muted);
    }

    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3.5),
      decoration: BoxDecoration(
        color: background,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          leading,
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: _state == _ChipState.matched
                    ? semantic.muted
                    : scheme.onSurface,
              ),
            ),
          ),
          if (probability != null) ...[
            const SizedBox(width: 5),
            Text(
              probability!.toStringAsFixed(2),
              style: monoStyle(context, size: 10.5, color: semantic.muted),
            ),
          ],
          if (onDelete != null) ...[
            const SizedBox(width: 5),
            InkWell(
              onTap: onDelete,
              borderRadius: BorderRadius.circular(99),
              child: Icon(Icons.close, size: 12, color: semantic.muted),
            ),
          ],
        ],
      ),
    );

    if (onTap == null) return chip;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(99),
      child: MouseRegion(cursor: SystemMouseCursors.click, child: chip),
    );
  }
}

enum _ChipState { suggestion, missing, matched }
