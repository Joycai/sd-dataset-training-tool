import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../views/settings_view.dart';
import '../app_state.dart';
import '../l10n/app_localizations.dart';
import '../state/ai_tagger_state.dart';
import '../state/batch_tag_state.dart';
import '../state/dataset_state.dart';
import '../state/workbench_layout.dart';
import '../theme/app_theme.dart';
import '../views/panels/batch_tag_dialog.dart';

/// The vertical icon rail: one entry per workbench area, settings pinned to
/// the bottom.
///
/// The rail navigates the existing surfaces rather than replacing them —
/// browse toggles the navigator, tags/dataset reveal the matching inspector
/// tab, batch opens its dialog. Nothing here owns content of its own.
class IconNavRail extends StatelessWidget {
  const IconNavRail({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final semantic = context.semantic;
    final layout = context.watch<WorkbenchLayout>();

    return Container(
      width: AppMetrics.navRail,
      decoration: BoxDecoration(
        color: semantic.panel,
        border: Border(right: BorderSide(color: semantic.line)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 10),
          _RailButton(
            icon: Icons.grid_view_outlined,
            tooltip: l10n.navBrowse,
            active: layout.navigatorVisible,
            onPressed: layout.toggleNavigator,
          ),
          _RailButton(
            icon: Icons.sell_outlined,
            tooltip: l10n.rightTabLibrary,
            active:
                layout.inspectorVisible &&
                layout.inspectorTab == InspectorTab.library,
            onPressed: () => layout.showInspectorTab(InspectorTab.library),
          ),
          _RailButton(
            icon: Icons.dataset_outlined,
            tooltip: l10n.rightTabDataset,
            active:
                layout.inspectorVisible &&
                layout.inspectorTab == InspectorTab.dataset,
            onPressed: () => layout.showInspectorTab(InspectorTab.dataset),
          ),
          const _BatchRailButton(),
          const Spacer(),
          _RailButton(
            icon: Icons.settings_outlined,
            tooltip: l10n.settings,
            active: false,
            onPressed: () => showSettingsDialog(context),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}

/// Batch tagging: an ordinary rail entry that turns into a progress ring
/// while a run is going, mirroring the button it replaces in the title bar.
class _BatchRailButton extends StatelessWidget {
  const _BatchRailButton();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final batch = context.watch<BatchTagState>();
    final dataset = context.watch<DatasetState>();
    final enabled = batch.running || dataset.allFiles.isNotEmpty;

    return _RailButton(
      icon: Icons.auto_awesome_motion,
      progress: batch.running ? batch.progress : null,
      tooltip: batch.running
          ? l10n.batchTagRunning(batch.completed, batch.total)
          : l10n.batchTagButton,
      active: batch.running,
      onPressed: !enabled
          ? null
          : () => showBatchTagDialog(
              context,
              ai: context.read<AiTaggerState>(),
              batch: batch,
              dataset: dataset,
              appState: context.read<AppState>(),
            ),
    );
  }
}

class _RailButton extends StatefulWidget {
  const _RailButton({
    required this.icon,
    required this.tooltip,
    required this.active,
    required this.onPressed,
    this.progress,
  });

  final IconData icon;
  final String tooltip;
  final bool active;
  final VoidCallback? onPressed;

  /// When set, the icon is replaced by a determinate ring.
  final double? progress;

  @override
  State<_RailButton> createState() => _RailButtonState();
}

class _RailButtonState extends State<_RailButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final semantic = context.semantic;
    final enabled = widget.onPressed != null;
    final color = !enabled
        ? semantic.muted.withValues(alpha: 0.4)
        : widget.active
        ? scheme.primary
        : semantic.muted;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Tooltip(
        message: widget.tooltip,
        child: MouseRegion(
          cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onPressed,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOut,
              width: AppMetrics.railItem,
              height: AppMetrics.railItem,
              decoration: BoxDecoration(
                color: widget.active
                    ? scheme.primary.withValues(alpha: 0.22)
                    : _hovered && enabled
                    ? semantic.raised
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(AppRadii.control),
              ),
              child: Center(
                child: widget.progress != null
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          value: widget.progress,
                          color: scheme.primary,
                        ),
                      )
                    : Icon(widget.icon, size: 18, color: color),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
