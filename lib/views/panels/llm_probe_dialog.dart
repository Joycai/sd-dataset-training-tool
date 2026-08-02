import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/llm_models.dart';
import '../../services/llm/endpoint_probe.dart';
import '../../services/llm/endpoint_probe_service.dart';
import '../../services/llm/llm_client.dart';
import '../../theme/app_theme.dart';
import '../../widgets/panel_widgets.dart';

/// Capability detection for one model, as a run-then-apply dialog.
///
/// Nothing is written on the way through: the run produces a report, the
/// report is shown with the server's own words next to each number, and only
/// the apply button touches the model. Detection that silently rewrote the
/// form would be indistinguishable from a relay having a bad minute.
///
/// Returns the updated [LlmModelConfig] when the user applied, else null.
Future<LlmModelConfig?> showLlmProbeDialog(
  BuildContext context, {
  required LlmProvider provider,
  required LlmModelConfig model,
  required LlmEndpointInspector inspector,
}) => showDialog<LlmModelConfig>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _LlmProbeDialog(
    provider: provider,
    model: model,
    inspector: inspector,
  ),
);

class _LlmProbeDialog extends StatefulWidget {
  const _LlmProbeDialog({
    required this.provider,
    required this.model,
    required this.inspector,
  });

  final LlmProvider provider;
  final LlmModelConfig model;
  final LlmEndpointInspector inspector;

  @override
  State<_LlmProbeDialog> createState() => _LlmProbeDialogState();
}

class _StepLine {
  _StepLine(this.step, this.status, this.detail);

  final ProbeStep step;
  ProbeStepStatus status;
  String? detail;
}

class _LlmProbeDialogState extends State<_LlmProbeDialog> {
  final _service = EndpointProbeService();

  bool _running = false;
  bool _cancelled = false;
  bool _includeTruncation = false;
  bool _finished = false;
  CapabilityReport? _report;
  final List<_StepLine> _lines = [];

  @override
  void dispose() {
    // The run holds no resources of its own, but a dialog closed mid-flight
    // must stop the remaining steps from being started.
    _cancelled = true;
    super.dispose();
  }

  int get _truncationCost => EndpointProbeService.estimateTruncationTestTokens(
    widget.model.contextWindow,
  );

  Future<void> _run() async {
    setState(() {
      _running = true;
      // A prior run may have left this set from a stop the user issued —
      // without resetting it, "stop, then run again" would exit immediately.
      _cancelled = false;
      _finished = false;
      _report = null;
      _lines.clear();
    });

    final report = await _service.run(
      provider: widget.provider,
      model: widget.model,
      inspector: widget.inspector,
      includeTruncationTest: _includeTruncation,
      isCancelled: () => _cancelled,
      onStep: (step, status, detail) {
        if (!mounted) return;
        setState(() {
          for (final line in _lines) {
            if (line.step != step) continue;
            line.status = status;
            line.detail = detail ?? line.detail;
            return;
          }
          _lines.add(_StepLine(step, status, detail));
        });
      },
    );

    if (!mounted) return;
    setState(() {
      _running = false;
      _finished = true;
      _report = report;
    });
  }

  void _stop() {
    // Not a pop: the run is mid-step and keeps going until it notices this
    // and returns whatever it already collected — closing the dialog here
    // would just orphan that in-flight future with no way back in to see
    // the result.
    setState(() => _cancelled = true);
  }

  void _apply() {
    final report = _report;
    if (report == null) return;
    final window = report.contextWindow;
    final output = report.maxOutput;
    final updated = widget.model.copyWith(
      // Only what was actually found moves; a run that learned nothing about
      // max output leaves the user's number alone. Same for the measurement
      // record itself — a rerun that only re-confirmed the context window
      // must not blank out a max-output figure an earlier run already
      // measured.
      contextWindow: window,
      maxOutputTokens: output,
      measuredContextWindow: window ?? widget.model.measuredContextWindow,
      measuredMaxOutput: output ?? widget.model.measuredMaxOutput,
      measuredAt: DateTime.now().toIso8601String(),
      silentTruncation: report.truncation == TruncationVerdict.detected,
    );
    Navigator.of(context).pop(updated);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final semantic = context.semantic;
    final report = _report;
    final hasResult = report != null && !report.isEmpty;

    return AlertDialog(
      title: Text(l10n.llmDetectTitle),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.llmDetectIntro,
                style: TextStyle(
                  fontSize: AppText.secondary,
                  color: semantic.muted,
                ),
              ),
              const SizedBox(height: 14),
              _TruncationOption(
                value: _includeTruncation,
                enabled: !_running,
                estimatedTokens: _truncationCost,
                onChanged: (value) =>
                    setState(() => _includeTruncation = value),
              ),
              if (_lines.isNotEmpty) ...[
                const SizedBox(height: 14),
                for (final line in _lines) _StepRow(line: line),
              ],
              if (_finished) ...[
                const SizedBox(height: 14),
                Container(width: double.infinity, height: 1, color: semantic.line),
                const SizedBox(height: 12),
                if (hasResult)
                  _Findings(report: report)
                else
                  Text(
                    l10n.llmDetectNothingFound,
                    style: TextStyle(
                      fontSize: AppText.secondary,
                      color: semantic.muted,
                    ),
                  ),
                if (report != null) _TruncationVerdictLine(report: report),
                if (report != null && report.notes.isNotEmpty)
                  _Notes(notes: report.notes),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _running ? _stop : () => Navigator.of(context).pop(),
          child: Text(_running ? l10n.llmDetectStop : l10n.cancel),
        ),
        TextButton(
          onPressed: _running ? null : _run,
          child: Text(
            _running
                ? l10n.llmDetectRunning
                : (_finished ? l10n.llmDetectRerun : l10n.llmDetectRun),
          ),
        ),
        FilledButton(
          onPressed: hasResult && !_running ? _apply : null,
          child: Text(l10n.llmDetectApply),
        ),
      ],
    );
  }
}

class _TruncationOption extends StatelessWidget {
  const _TruncationOption({
    required this.value,
    required this.enabled,
    required this.estimatedTokens,
    required this.onChanged,
  });

  final bool value;
  final bool enabled;
  final int estimatedTokens;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final semantic = context.semantic;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        border: Border.all(color: semantic.line),
        borderRadius: BorderRadius.circular(AppRadii.control),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.llmDetectTruncationOption,
                  style: const TextStyle(fontSize: AppText.base),
                ),
                const SizedBox(height: 3),
                Text(
                  l10n.llmDetectTruncationOptionDesc(estimatedTokens),
                  style: TextStyle(
                    fontSize: AppText.small,
                    color: semantic.muted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          AppSwitch(value: value, onChanged: enabled ? onChanged : null),
        ],
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.line});

  final _StepLine line;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final semantic = context.semantic;
    final scheme = Theme.of(context).colorScheme;

    final (IconData icon, Color color) = switch (line.status) {
      ProbeStepStatus.running => (Icons.more_horiz, semantic.muted),
      ProbeStepStatus.done => (Icons.check, semantic.ok),
      ProbeStepStatus.skipped => (Icons.remove, semantic.muted),
      ProbeStepStatus.failed => (Icons.close, scheme.error),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 14, color: color),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_stepLabel(l10n, line.step)} · '
                  '${_statusLabel(l10n, line.status)}',
                  style: const TextStyle(fontSize: AppText.secondary),
                ),
                if (line.detail != null && line.detail!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      line.detail!,
                      style: monoStyle(
                        context,
                        size: AppText.micro,
                        color: semantic.muted,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Findings extends StatelessWidget {
  const _Findings({required this.report});

  final CapabilityReport report;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final semantic = context.semantic;
    final contextWindow = report.contextWindow;
    final maxOutput = report.maxOutput;

    /// The source of the number that won, so the user can see whether it came
    /// from a catalogue or from the server refusing a request.
    String? evidenceFor(int? value, int? Function(CapabilityFinding) read) {
      if (value == null) return null;
      CapabilitySource? source;
      for (final finding in report.findings) {
        if (read(finding) != value) continue;
        // Same resolution order the value itself won by, so the label always
        // names the source the number actually came from.
        if (source == null ||
            CapabilitySource.values.indexOf(finding.source) >=
                CapabilitySource.values.indexOf(source)) {
          source = finding.source;
        }
      }
      return source == null ? null : _sourceLabel(l10n, source);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (contextWindow != null)
          _ResultLine(
            text: l10n.llmDetectFoundContext(contextWindow),
            evidence: evidenceFor(contextWindow, (f) => f.contextWindow),
          ),
        if (maxOutput != null)
          _ResultLine(
            text: l10n.llmDetectFoundOutput(maxOutput),
            evidence: evidenceFor(maxOutput, (f) => f.maxOutput),
          ),
        if (contextWindow == null && maxOutput == null)
          Text(
            l10n.llmDetectNothingFound,
            style: TextStyle(
              fontSize: AppText.secondary,
              color: semantic.muted,
            ),
          ),
      ],
    );
  }
}

class _ResultLine extends StatelessWidget {
  const _ResultLine({required this.text, this.evidence});

  final String text;
  final String? evidence;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            text,
            style: const TextStyle(
              fontSize: AppText.base,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (evidence != null)
            Text(
              evidence!,
              style: TextStyle(
                fontSize: AppText.small,
                color: semantic.muted,
              ),
            ),
        ],
      ),
    );
  }
}

class _TruncationVerdictLine extends StatelessWidget {
  const _TruncationVerdictLine({required this.report});

  final CapabilityReport report;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final semantic = context.semantic;
    final scheme = Theme.of(context).colorScheme;

    return switch (report.truncation) {
      TruncationVerdict.detected => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          l10n.llmDetectTruncationDetected(report.effectiveContextWindow ?? 0),
          style: TextStyle(fontSize: AppText.secondary, color: scheme.error),
        ),
      ),
      TruncationVerdict.notDetected => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          l10n.llmDetectTruncationNotDetected,
          style: TextStyle(
            fontSize: AppText.small,
            color: semantic.muted,
          ),
        ),
      ),
      TruncationVerdict.inconclusive => const SizedBox.shrink(),
    };
  }
}

class _Notes extends StatelessWidget {
  const _Notes({required this.notes});

  final List<String> notes;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final semantic = context.semantic;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.llmDetectNotes,
            style: TextStyle(
              fontSize: AppText.micro,
              fontWeight: FontWeight.w600,
              letterSpacing: 1,
              color: semantic.muted,
            ),
          ),
          const SizedBox(height: 4),
          for (final note in notes)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(
                note,
                style: monoStyle(
                  context,
                  size: AppText.micro,
                  color: semantic.muted,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

String _stepLabel(AppLocalizations l10n, ProbeStep step) => switch (step) {
  ProbeStep.listing => l10n.llmDetectStepListing,
  ProbeStep.backendApi => l10n.llmDetectStepBackendApi,
  ProbeStep.errorProbe => l10n.llmDetectStepErrorProbe,
  ProbeStep.calibration => l10n.llmDetectStepCalibration,
  ProbeStep.truncationTest => l10n.llmDetectStepTruncation,
};

String _statusLabel(AppLocalizations l10n, ProbeStepStatus status) =>
    switch (status) {
      ProbeStepStatus.running => l10n.llmDetectStatusRunning,
      ProbeStepStatus.done => l10n.llmDetectStatusDone,
      ProbeStepStatus.skipped => l10n.llmDetectStatusSkipped,
      ProbeStepStatus.failed => l10n.llmDetectStatusFailed,
    };

String _sourceLabel(AppLocalizations l10n, CapabilitySource source) =>
    switch (source) {
      CapabilitySource.listing => l10n.llmDetectEvidenceListing,
      CapabilitySource.backendApi => l10n.llmDetectEvidenceBackend,
      CapabilitySource.errorMessage => l10n.llmDetectEvidenceError,
      CapabilitySource.measured => l10n.llmDetectEvidenceMeasured,
    };
