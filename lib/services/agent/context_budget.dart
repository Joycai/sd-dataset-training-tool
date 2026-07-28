/// Local context-window accounting and history compaction for the agent.
/// Pure Dart.
library;

import '../../models/llm_models.dart';

class ContextBudget {
  ContextBudget({
    required this.contextWindow,
    required this.maxOutputTokens,
    this.safetyMargin = 1024,
    this.protectedTail = 8,
  });

  final int contextWindow;
  final int maxOutputTokens;

  /// Extra headroom subtracted from the window: local estimation error,
  /// protocol overhead, tool schemas.
  final int safetyMargin;

  /// The most recent N messages are never folded (≈ the last 4 rounds).
  final int protectedTail;

  int get inputBudget => (contextWindow - maxOutputTokens - safetyMargin)
      .clamp(1024, 1 << 31)
      .toInt();

  /// Estimated tokens for one image content part (768px JPEG, base64).
  static const imageTokens = 1600;

  /// Deliberately over-estimates by ~10%: running out of window mid-stream
  /// is an error, trimming early merely loses a little history.
  int estimate(List<ChatMessage> history) {
    var tokens = 0;
    for (final m in history) {
      tokens += 4; // per-message protocol overhead
      for (final p in m.parts) {
        if (p.isImage) {
          tokens += imageTokens;
        } else if (p.text != null) {
          tokens += estimateText(p.text!);
        }
      }
      for (final c in m.toolCalls) {
        tokens += estimateText(c.name) + estimateText(c.argumentsJson) + 8;
      }
    }
    return (tokens * 1.1).ceil();
  }

  /// ASCII ≈ 4 chars/token; CJK and other non-ASCII ≈ 1.7 chars/token.
  ///
  /// Pure integer arithmetic (ceil(n/4) and ceil(n·10/17)): floating-point
  /// division would make exact multiples land on either side of the
  /// boundary depending on rounding (17 / 1.7 is 10.000000000000002).
  static int estimateText(String text) {
    var ascii = 0;
    var other = 0;
    for (final unit in text.codeUnits) {
      if (unit < 128) {
        ascii++;
      } else {
        other++;
      }
    }
    return (ascii + 3) ~/ 4 + (other * 10 + 16) ~/ 17;
  }

  /// Shrinks [history] in place until it fits [inputBudget].
  ///
  /// Priority: (1) fold old *unpinned* tool results, (2) fold old
  /// user/assistant text, (3) fold pinned tool results as a last resort.
  /// The system prompt (index 0), the last [protectedTail] messages, and
  /// message *structure* (roles, tool_call ids) are always preserved so the
  /// wire protocols stay valid.
  ///
  /// The pinned pass exists because folding a `read_captions` body out from
  /// under a long per-image rewrite leaves the model retyping captions from
  /// memory — it invents tags and drops real ones. Deferring those bodies
  /// keeps the source of truth in context for as long as the window allows;
  /// pass 3 still guarantees the history shrinks when it must.
  void compact(List<ChatMessage> history) {
    if (estimate(history) <= inputBudget) return;

    bool isProtected(int i) => i == 0 || i >= history.length - protectedTail;

    /// Folds tool results oldest first, returning true once history fits.
    bool foldToolResults({required bool pinned}) {
      for (var i = 0; i < history.length; i++) {
        if (isProtected(i)) continue;
        final m = history[i];
        if (m.role != ChatRole.tool || m.pinned != pinned || _isElided(m)) {
          continue;
        }
        _elide(m, 'tool result');
        if (estimate(history) <= inputBudget) return true;
      }
      return false;
    }

    // Pass 1: elide unpinned tool result bodies, oldest first.
    if (foldToolResults(pinned: false)) return;

    // Pass 2: fold old user/assistant turns, oldest first.
    for (var i = 0; i < history.length; i++) {
      if (isProtected(i)) continue;
      final m = history[i];
      if (m.role == ChatRole.tool || m.role == ChatRole.system) continue;
      if (_isElided(m)) continue;
      _elide(m, m.role == ChatRole.user ? 'user message' : 'assistant message');
      if (estimate(history) <= inputBudget) return;
    }

    // Pass 3: nothing cheap is left — the pinned bodies go too.
    foldToolResults(pinned: true);
  }

  static const _elidedPrefix = '[elided ';

  bool _isElided(ChatMessage m) =>
      m.parts.length == 1 &&
      (m.parts.first.text?.startsWith(_elidedPrefix) ?? false);

  void _elide(ChatMessage m, String what) {
    final chars = m.parts.fold<int>(
      0,
      (sum, p) => sum + (p.text?.length ?? 0) + (p.isImage ? 1 : 0),
    );
    final head = _firstLine(m.text);
    m.parts = [
      ChatContentPart.text(
        '$_elidedPrefix$what, $chars chars'
        '${head.isEmpty ? '' : ': $head'}]',
      ),
    ];
  }

  static String _firstLine(String text) {
    final line = text.split('\n').first.trim();
    return line.length <= 80 ? line : '${line.substring(0, 80)}…';
  }
}
