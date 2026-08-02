import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../l10n/app_localizations.dart';
import '../../models/tag_group.dart';
import '../../services/llm/llm_client.dart';
import '../../services/tag_ai_group.dart';
import '../../theme/app_theme.dart';
import '../../widgets/panel_widgets.dart';

/// Reviews the model's filing proposals for the ungrouped bucket.
///
/// Every row is a separate decision. Nothing is applied until the user says
/// so — an "AI tidied your library" that ran unattended would be indisplaceable
/// once wrong, because the previous arrangement was "no arrangement at all"
/// and there is nothing to compare against.
Future<void> showAiGroupingDialog(
  BuildContext context, {
  required List<String> tags,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final appState = context.read<AppState>();
  if (appState.activeLlmProfile == null) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l10n.aiGroupNoBackend)));
    return;
  }
  if (tags.isEmpty) return;
  final applied = await showDialog<int>(
    context: context,
    builder: (context) => _AiGroupingDialog(tags: tags),
  );
  if (applied != null && applied > 0 && context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l10n.aiGroupApplied(applied))));
  }
}

class _AiGroupingDialog extends StatefulWidget {
  const _AiGroupingDialog({required this.tags});

  final List<String> tags;

  @override
  State<_AiGroupingDialog> createState() => _AiGroupingDialogState();
}

class _AiGroupingDialogState extends State<_AiGroupingDialog> {
  List<TagGroupSuggestion>? _suggestions;
  String? _error;
  int _done = 0;
  int _applied = 0;

  /// Batches whose answer could not be read, by kind. What separates "the
  /// model declined" from "the model's answer never arrived" — the second is
  /// a setup problem the user can fix, and saying nothing about it is what
  /// made this feature look inert.
  int _emptyBatches = 0;
  int _unreadableBatches = 0;
  int _totalBatches = 0;

  /// Guards the accept buttons while a group is being created and written.
  bool _applying = false;

  @override
  void initState() {
    super.initState();
    // The dialog opens straight into the request: the user already asked for
    // suggestions by opening it, so a second "Start" button would be a
    // confirmation of the confirmation.
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    final appState = context.read<AppState>();
    final profile = appState.activeLlmProfile;
    if (profile == null) return;
    setState(() {
      _suggestions = null;
      _error = null;
      _done = 0;
      _emptyBatches = 0;
      _unreadableBatches = 0;
      _totalBatches = 0;
    });
    try {
      final result = await suggestTagGroupsWithLlm(
        profile: profile,
        tags: widget.tags,
        existingGroups: [for (final g in appState.tagGroups) g.name],
        glosses: {
          for (final tag in widget.tags)
            tag: ?appState.tagTranslations.glossFor(tag),
        },
        languageCode: appState.tagTranslations.languageCode,
        onProgress: (done, _) {
          if (mounted) setState(() => _done = done);
        },
        onBatchProblem: (problem, _) {
          switch (problem) {
            // Both mean "the answer never arrived in full", and both are
            // fixed the same way — a bigger output budget.
            case TagGroupBatchProblem.emptyReply:
            case TagGroupBatchProblem.truncated:
              _emptyBatches++;
            case TagGroupBatchProblem.unparseable:
              _unreadableBatches++;
          }
        },
      );
      if (!mounted) return;
      setState(() {
        _suggestions = result;
        _totalBatches = (widget.tags.length / tagGroupBatchSize).ceil();
      });
    } on LlmException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      // Anything the transport did not wrap still has to reach the user:
      // an unhandled throw here leaves the dialog spinning forever, which is
      // indistinguishable from the feature doing nothing.
      if (mounted) setState(() => _error = '$e');
    }
  }

  int get _failedBatches => _emptyBatches + _unreadableBatches;

  /// The message for a run that produced no suggestions, naming the reason
  /// when there was one.
  String _emptyMessage(AppLocalizations l10n) {
    final failed = _failedBatches;
    if (failed == 0) return l10n.aiGroupEmpty;
    final total = _totalBatches < failed ? failed : _totalBatches;
    return _emptyBatches >= _unreadableBatches
        ? l10n.aiGroupNoReply(failed, total)
        : l10n.aiGroupUnreadable(failed, total);
  }

  /// The group [name] refers to, or null when it is a new one.
  ///
  /// Folded, not exact: a model that answers "服装 " or "Clothing" for a
  /// library that already has "服装"/"clothing" must land in the group the
  /// user has, not in a second one beside it.
  static TagGroup? _groupNamed(AppState appState, String name) {
    final groups = appState.tagGroups;
    final exact = groups.where((g) => g.name == name).firstOrNull;
    if (exact != null) return exact;
    final folded = name.trim().toLowerCase();
    return groups
        .where((g) => g.name.trim().toLowerCase() == folded)
        .firstOrNull;
  }

  /// Files one tag, creating the target group when the model named a new one.
  Future<void> _accept(TagGroupSuggestion suggestion) async {
    if (_applying) return;
    setState(() => _applying = true);
    final appState = context.read<AppState>();
    try {
      var group = _groupNamed(appState, suggestion.group);
      group ??= await appState.createTagGroup(
        suggestion.group,
        // Cycle the presets so a batch of new groups is visually separable
        // without asking the user to pick eight colors.
        kTagGroupPresetColors[appState.tagGroups.length %
            kTagGroupPresetColors.length],
      );
      await appState.moveTagsToGroup([suggestion.tag], group.id);
      if (!mounted) return;
      setState(() {
        _applied++;
        _suggestions = [
          for (final s in _suggestions ?? const <TagGroupSuggestion>[])
            if (s.tag != suggestion.tag) s,
        ];
      });
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  void _reject(TagGroupSuggestion suggestion) {
    setState(() {
      _suggestions = [
        for (final s in _suggestions ?? const <TagGroupSuggestion>[])
          if (s.tag != suggestion.tag) s,
      ];
    });
  }

  Future<void> _acceptAll() async {
    // Snapshot: [_accept] rewrites the list as it goes.
    for (final suggestion in [...?_suggestions]) {
      if (!mounted) return;
      await _accept(suggestion);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final semantic = context.semantic;
    final scheme = Theme.of(context).colorScheme;
    final appState = context.watch<AppState>();
    final suggestions = _suggestions;

    final Widget body;
    if (_error != null) {
      body = Text(
        l10n.aiGroupFailed(_error!),
        style: TextStyle(fontSize: AppText.secondary, color: scheme.error),
      );
    } else if (suggestions == null) {
      body = Row(
        children: [
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 10),
          Text(
            l10n.aiGroupRunning(_done, widget.tags.length),
            style: TextStyle(
              fontSize: AppText.secondary,
              color: semantic.muted,
            ),
          ),
        ],
      );
    } else if (suggestions.isEmpty) {
      body = Text(
        // After a run that filed everything the list is empty for a happy
        // reason; before one it means the model had nothing usable to say —
        // and [_emptyMessage] says which kind of nothing that was.
        _applied > 0 ? l10n.aiGroupApplied(_applied) : _emptyMessage(l10n),
        style: TextStyle(fontSize: AppText.secondary, color: semantic.muted),
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.aiGroupIntro(suggestions.length),
            style: TextStyle(
              fontSize: AppText.secondary,
              color: semantic.muted,
            ),
          ),
          const SizedBox(height: 10),
          for (final suggestion in suggestions)
            _SuggestionRow(
              suggestion: suggestion,
              gloss: appState.tagTranslations.glossFor(suggestion.tag),
              isNewGroup: _groupNamed(appState, suggestion.group) == null,
              newBadge: l10n.aiGroupNewGroupBadge,
              acceptTooltip: l10n.confirm,
              rejectTooltip: l10n.cancel,
              enabled: !_applying,
              onAccept: () => _accept(suggestion),
              onReject: () => _reject(suggestion),
            ),
        ],
      );
    }

    return GlassDialog(
      width: 520,
      header: Row(
        children: [
          Icon(Icons.auto_awesome, size: 15, color: scheme.primary),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              l10n.aiGroupTitle,
              style: const TextStyle(
                fontSize: AppText.base,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      body: body,
      actions: [
        if (suggestions != null && suggestions.isNotEmpty) ...[
          TextButton(
            onPressed: _applying
                ? null
                : () => setState(() => _suggestions = const []),
            child: Text(l10n.aiGroupIgnoreAll),
          ),
          const SizedBox(width: 6),
          FilledButton(
            onPressed: _applying ? null : _acceptAll,
            child: Text(l10n.aiGroupAcceptAll(suggestions.length)),
          ),
        ] else ...[
          TextButton(
            onPressed: () => Navigator.of(context).pop(_applied),
            child: Text(l10n.close),
          ),
          // A run that failed is worth one click to redo — the model is
          // non-deterministic and a truncated answer often is not the second
          // time. Offered only when there is something to redo.
          if (_error != null ||
              (suggestions != null && _applied == 0 && _failedBatches > 0)) ...[
            const SizedBox(width: 6),
            FilledButton(onPressed: _run, child: Text(l10n.aiGroupRetry)),
          ],
        ],
      ],
    );
  }
}

class _SuggestionRow extends StatelessWidget {
  const _SuggestionRow({
    required this.suggestion,
    required this.gloss,
    required this.isNewGroup,
    required this.newBadge,
    required this.acceptTooltip,
    required this.rejectTooltip,
    required this.enabled,
    required this.onAccept,
    required this.onReject,
  });

  final TagGroupSuggestion suggestion;
  final String? gloss;
  final bool isNewGroup;
  final String newBadge;
  final String acceptTooltip;
  final String rejectTooltip;
  final bool enabled;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
      decoration: BoxDecoration(
        color: semantic.raised,
        border: Border.all(color: semantic.line),
        borderRadius: BorderRadius.circular(AppRadii.control),
      ),
      child: Row(
        children: [
          Flexible(
            child: Text(
              suggestion.tag,
              overflow: TextOverflow.ellipsis,
              style: monoStyle(context, size: AppText.secondary),
            ),
          ),
          if (gloss != null) ...[
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                gloss!,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: AppText.small,
                  color: semantic.muted,
                ),
              ),
            ),
          ],
          const SizedBox(width: 8),
          Icon(Icons.arrow_forward, size: 13, color: semantic.muted),
          const SizedBox(width: 8),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: scheme.primary.withAlpha(30),
                border: Border.all(color: scheme.primary.withAlpha(90)),
                borderRadius: BorderRadius.circular(AppRadii.pill),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      suggestion.group,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: AppText.small,
                        color: scheme.primary,
                      ),
                    ),
                  ),
                  if (isNewGroup) ...[
                    const SizedBox(width: 5),
                    Text(
                      newBadge,
                      style: TextStyle(
                        fontSize: AppText.micro,
                        color: semantic.muted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const Spacer(),
          PanelIconButton(
            icon: Icons.check,
            tooltip: acceptTooltip,
            size: 15,
            hitSize: 26,
            color: semantic.ok,
            onPressed: enabled ? onAccept : null,
          ),
          PanelIconButton(
            icon: Icons.close,
            tooltip: rejectTooltip,
            size: 15,
            hitSize: 26,
            onPressed: enabled ? onReject : null,
          ),
        ],
      ),
    );
  }
}
