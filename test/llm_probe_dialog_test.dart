import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dataset_training_tool/l10n/app_localizations.dart';
import 'package:dataset_training_tool/models/llm_models.dart';
import 'package:dataset_training_tool/services/llm/llm_client.dart';
import 'package:dataset_training_tool/theme/app_theme.dart';
import 'package:dataset_training_tool/views/panels/llm_probe_dialog.dart';

/// An inspector whose `sendProbe` hangs until [finish] is called — the
/// "still running" window the Stop button has to work inside. A fresh
/// completer is armed on every call, so the same instance can hang a second
/// run after the first was finished.
class _HangingInspector implements LlmEndpointInspector {
  var _current = Completer<ProbeResponse>();

  @override
  Future<List<Map<String, dynamic>>> listModelsDetailed(
    LlmProviderProfile profile,
  ) async => const [];

  @override
  Future<ProbeResponse> sendProbe(
    LlmProviderProfile profile, {
    required List<ChatMessage> messages,
    required int maxTokens,
    Duration? timeout,
  }) {
    if (_current.isCompleted) _current = Completer<ProbeResponse>();
    return _current.future;
  }

  void finish() {
    if (!_current.isCompleted) {
      _current.complete(
        const ProbeResponse(statusCode: 429, message: 'rate limited'),
      );
    }
  }
}

const _provider = LlmProvider(
  id: 'p',
  name: 'Test',
  kind: LlmApiKind.anthropic,
  baseUrl: 'https://api.anthropic.com',
);
const _model = LlmModelConfig(id: 'm', modelId: 'claude-x', contextWindow: 8192);

Widget _harness(LlmEndpointInspector inspector) => MaterialApp(
  theme: buildAppTheme(Brightness.dark),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: Builder(
      builder: (context) => ElevatedButton(
        onPressed: () => showLlmProbeDialog(
          context,
          provider: _provider,
          model: _model,
          inspector: inspector,
        ),
        child: const Text('open'),
      ),
    ),
  ),
);

void main() {
  testWidgets(
    'the stop button is enabled mid-run and ends the dialog in a finished '
    'state instead of leaving it spinning',
    (tester) async {
      final inspector = _HangingInspector();
      await tester.pumpWidget(_harness(inspector));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final l10n = AppLocalizations.of(
        tester.element(find.text('open')),
      )!;

      // Kick off the run: the listing step resolves immediately, the
      // error-probe step then hangs on the inspector's completer.
      await tester.tap(find.text(l10n.llmDetectRun));
      await tester.pump();
      await tester.pump();

      // Regression: the Cancel button used to stay disabled for the whole
      // run, with no other way to stop it — a dialog that could not be
      // closed until a request finished on its own, sometimes minutes later.
      final stopButton = find.widgetWithText(TextButton, l10n.llmDetectStop);
      expect(stopButton, findsOneWidget);
      final button = tester.widget<TextButton>(stopButton);
      expect(button.onPressed, isNotNull);

      await tester.tap(stopButton);
      await tester.pump();

      // Letting the in-flight request resolve now lets the run notice the
      // cancellation and return — the dialog must not still be stuck on
      // "running" once that happens.
      inspector.finish();
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextButton, l10n.llmDetectStop), findsNothing);
      expect(find.widgetWithText(TextButton, l10n.cancel), findsOneWidget);
      final cancelButton = tester.widget<TextButton>(
        find.widgetWithText(TextButton, l10n.cancel),
      );
      expect(cancelButton.onPressed, isNotNull);
    },
  );

  testWidgets('stopping then running again does not exit immediately', (
    tester,
  ) async {
    // `_cancelled` must be reset at the start of each run, or "stop, then
    // run again" would return before the first step even starts.
    final first = _HangingInspector();
    await tester.pumpWidget(_harness(first));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final l10n = AppLocalizations.of(tester.element(find.text('open')))!;

    await tester.tap(find.text(l10n.llmDetectRun));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.widgetWithText(TextButton, l10n.llmDetectStop));
    await tester.pump();
    first.finish();
    await tester.pumpAndSettle();

    await tester.tap(find.text(l10n.llmDetectRerun));
    await tester.pump();
    await tester.pump();

    // Still mid-run: the error-probe step is hanging on a fresh completer,
    // so the stop control must be back, not skipped straight to done —
    // which is what a `_cancelled` left set from the previous run would do.
    expect(find.widgetWithText(TextButton, l10n.llmDetectStop), findsOneWidget);
    first.finish();
    await tester.pumpAndSettle();
  });
}
