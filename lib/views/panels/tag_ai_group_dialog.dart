import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../l10n/app_localizations.dart';
import '../../models/tag_group.dart';
import '../../models/llm_models.dart';
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

/// One line of the run log. The level only picks a colour — the text is
/// already a full sentence, because a log nobody can read without a legend is
/// not a log.
enum _LogLevel { info, ok, warn, error }

class _LogLine {
  const _LogLine(this.text, this.level);

  final String text;
  final _LogLevel level;
}

class _AiGroupingDialogState extends State<_AiGroupingDialog> {
  /// Which model to ask. Defaults to the assistant's active backend, but this
  /// run is a one-off — filing tags is a different job from the conversation,
  /// and may well deserve a cheaper (or simply a different) model.
  String? _profileId;

  /// Null until the user starts the run: the model choice has to be made
  /// before any tokens are spent, so this dialog no longer fires on open.
  bool _started = false;

  final List<_LogLine> _log = [];

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
    _profileId = context.read<AppState>().activeLlmProfile?.id;
  }

  /// The profile the run will use, falling back to the active one when the
  /// remembered id no longer resolves (the user edited backends meanwhile).
  LlmProviderProfile? _selectedProfile(AppState appState) {
    final profiles = appState.llmProfiles;
    if (profiles.isEmpty) return null;
    return profiles.where((p) => p.id == _profileId).firstOrNull ??
        appState.activeLlmProfile ??
        profiles.first;
  }

  void _appendLog(String text, _LogLevel level) {
    if (!mounted) return;
    setState(() => _log.add(_LogLine(text, level)));
  }

  Future<void> _run() async {
    final l10n = AppLocalizations.of(context)!;
    final appState = context.read<AppState>();
    final profile = _selectedProfile(appState);
    if (profile == null) return;
    setState(() {
      _started = true;
      _suggestions = null;
      _error = null;
      _done = 0;
      _emptyBatches = 0;
      _unreadableBatches = 0;
      _totalBatches = 0;
      _log.clear();
      _log.add(_LogLine(l10n.aiGroupLogModel(profile.name), _LogLevel.info));
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
        onBatchStart: (index, batches, size) => _appendLog(
          l10n.aiGroupLogBatchStart(index, batches, size),
          _LogLevel.info,
        ),
        onBatchDone: (index, batches, placed) => _appendLog(
          l10n.aiGroupLogBatchDone(index, batches, placed),
          _LogLevel.ok,
        ),
        onBatchProblem: (problem, _) {
          switch (problem) {
            // The first two both mean "the answer never arrived in full", and
            // both are fixed the same way — a bigger output budget — but the
            // log names which one happened.
            case TagGroupBatchProblem.emptyReply:
              _emptyBatches++;
              _appendLog(l10n.aiGroupLogBatchEmpty, _LogLevel.warn);
            case TagGroupBatchProblem.truncated:
              _emptyBatches++;
              _appendLog(l10n.aiGroupLogBatchTruncated, _LogLevel.warn);
            case TagGroupBatchProblem.unparseable:
              _unreadableBatches++;
              _appendLog(l10n.aiGroupLogBatchUnreadable, _LogLevel.warn);
          }
        },
      );
      if (!mounted) return;
      setState(() {
        _suggestions = result;
        _totalBatches = (widget.tags.length / tagGroupBatchSize).ceil();
        _log.add(_LogLine(l10n.aiGroupLogDone(result.length), _LogLevel.ok));
      });
    } on LlmException catch (e) {
      _fail(e.message);
    } catch (e) {
      // Anything the transport did not wrap still has to reach the user:
      // an unhandled throw here leaves the dialog spinning forever, which is
      // indistinguishable from the feature doing nothing.
      _fail('$e');
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;
    setState(() {
      _error = message;
      _log.add(_LogLine(l10n.aiGroupFailed(message), _LogLevel.error));
    });
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
    if (!_started) {
      // Setup: pick the model, see what is about to be sent, then start.
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.aiGroupSetupHint(widget.tags.length),
            style: TextStyle(
              fontSize: AppText.secondary,
              color: semantic.muted,
            ),
          ),
          const SizedBox(height: 12),
          _ProfilePicker(
            label: l10n.aiGroupModelLabel,
            selected: _selectedProfile(appState),
            providers: appState.llmProviders,
            emptyLabel: l10n.llmNoProfiles,
            onSelected: (id) => setState(() => _profileId = id),
          ),
        ],
      );
    } else if (_error != null) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.aiGroupFailed(_error!),
            style: TextStyle(fontSize: AppText.secondary, color: scheme.error),
          ),
          const SizedBox(height: 10),
          _LogView(lines: _log, title: l10n.aiGroupLogTitle),
        ],
      );
    } else if (suggestions == null) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
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
          ),
          const SizedBox(height: 10),
          _LogView(lines: _log, title: l10n.aiGroupLogTitle),
        ],
      );
    } else if (suggestions.isEmpty) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            // After a run that filed everything the list is empty for a happy
            // reason; before one it means the model had nothing usable to say
            // — and [_emptyMessage] says which kind of nothing that was.
            _applied > 0 ? l10n.aiGroupApplied(_applied) : _emptyMessage(l10n),
            style: TextStyle(
              fontSize: AppText.secondary,
              color: semantic.muted,
            ),
          ),
          const SizedBox(height: 10),
          _LogView(lines: _log, title: l10n.aiGroupLogTitle),
        ],
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
            AiGroupSuggestionRow(
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
          const SizedBox(height: 8),
          _LogView(lines: _log, title: l10n.aiGroupLogTitle, collapsed: true),
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
        if (!_started) ...[
          TextButton(
            onPressed: () => Navigator.of(context).pop(_applied),
            child: Text(l10n.cancel),
          ),
          const SizedBox(width: 6),
          FilledButton(
            onPressed: _selectedProfile(appState) == null ? null : _run,
            child: Text(l10n.aiGroupStart),
          ),
        ] else if (suggestions != null && suggestions.isNotEmpty) ...[
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

/// One proposal row. Public only so the layout regression test can pump it
/// directly — the accept/reject pair drifting with tag length is a bug you
/// cannot see from the widget tree, only from geometry.
@visibleForTesting
class AiGroupSuggestionRow extends StatelessWidget {
  const AiGroupSuggestionRow({
    super.key,
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
      // The accept/reject pair is pinned to the right edge by giving the
      // content one Expanded slot of its own. The obvious version — content
      // chips, then a Spacer, then the buttons — does not do that: Spacer is
      // `Expanded(flex: 1)`, so it splits the free space evenly with the three
      // `Flexible` children beside it and only claims a quarter of it. The
      // buttons then sit at "content width + a quarter of the slack", which
      // moves with every tag's length and reads as ragged.
      child: Row(
        children: [
          Expanded(
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
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
              ],
            ),
          ),
          const SizedBox(width: 8),
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

/// Backend chooser for this run.
///
/// Deliberately not tied to the assistant's active backend: filing tags is a
/// short structured job, and the model that is right for a conversation is
/// often not the one you want to spend on a hundred one-line placements.
/// Picking here does not move the assistant.
class _ProfilePicker extends StatelessWidget {
  const _ProfilePicker({
    required this.label,
    required this.selected,
    required this.providers,
    required this.emptyLabel,
    required this.onSelected,
  });

  final String label;
  final LlmProviderProfile? selected;
  final List<LlmProvider> providers;
  final String emptyLabel;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    // With one provider its name is already in the closed label, so a header
    // above one short list would just repeat it.
    final grouped = providers.length > 1;
    return Row(
      children: [
        Text(
          label,
          style: TextStyle(fontSize: AppText.secondary, color: semantic.muted),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: PopupMenuButton<String>(
            position: PopupMenuPosition.under,
            constraints: const BoxConstraints(minWidth: 220, maxWidth: 380),
            padding: EdgeInsets.zero,
            enabled: providers.isNotEmpty,
            onSelected: onSelected,
            itemBuilder: (_) => [
              for (final provider in providers) ...[
                if (grouped)
                  PopupMenuItem<String>(
                    enabled: false,
                    height: 26,
                    child: Text(
                      provider.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: AppText.micro,
                        color: semantic.muted,
                      ),
                    ),
                  ),
                for (final model in provider.models)
                  PopupMenuItem<String>(
                    value: provider.resolve(model).id,
                    height: 34,
                    child: Padding(
                      padding: EdgeInsets.only(left: grouped ? 8 : 0),
                      child: Text(
                        model.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: AppText.secondary),
                      ),
                    ),
                  ),
              ],
            ],
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: semantic.raised,
                border: Border.all(color: semantic.line),
                borderRadius: BorderRadius.circular(AppRadii.control),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      selected?.name ?? emptyLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: AppText.secondary,
                        color: selected == null ? semantic.muted : null,
                      ),
                    ),
                  ),
                  Icon(Icons.arrow_drop_down, size: 18, color: semantic.muted),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The run log.
///
/// This feature's failures are all invisible from the outside — a request in
/// flight, a model that answered with nothing, a batch whose reply could not
/// be read — and a spinner reading `0/24` describes every one of them
/// identically. The log is what makes the difference legible without asking
/// the user to reproduce anything.
class _LogView extends StatefulWidget {
  const _LogView({
    required this.lines,
    required this.title,
    this.collapsed = false,
  });

  final List<_LogLine> lines;
  final String title;

  /// Starts folded. Once suggestions are on screen they are the thing to
  /// read; the log stays one click away rather than pushing them down.
  final bool collapsed;

  @override
  State<_LogView> createState() => _LogViewState();
}

class _LogViewState extends State<_LogView> {
  late bool _open = !widget.collapsed;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    final scheme = Theme.of(context).colorScheme;
    if (widget.lines.isEmpty) return const SizedBox.shrink();

    Color colorOf(_LogLevel level) => switch (level) {
      _LogLevel.info => semantic.muted,
      _LogLevel.ok => semantic.ok,
      _LogLevel.warn => semantic.warn,
      _LogLevel.error => scheme.error,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => setState(() => _open = !_open),
          borderRadius: BorderRadius.circular(AppRadii.control),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Icon(
                  _open ? Icons.expand_more : Icons.chevron_right,
                  size: 15,
                  color: semantic.muted,
                ),
                const SizedBox(width: 4),
                Text(
                  '${widget.title} (${widget.lines.length})',
                  style: TextStyle(
                    fontSize: AppText.small,
                    color: semantic.muted,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_open)
          Container(
            constraints: const BoxConstraints(maxHeight: 150),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: semantic.panel,
              border: Border.all(color: semantic.line),
              borderRadius: BorderRadius.circular(AppRadii.control),
            ),
            child: SingleChildScrollView(
              // Newest last, like every other log: the interesting line is at
              // the bottom while a run is in flight.
              reverse: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final line in widget.lines)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 1.5),
                      child: Text(
                        line.text,
                        style: monoStyle(
                          context,
                          size: AppText.micro,
                        ).copyWith(color: colorOf(line.level)),
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
