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

  int get inputBudget =>
      (contextWindow - maxOutputTokens - safetyMargin).clamp(1024, 1 << 31).toInt();

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
    return (ascii / 4).ceil() + (other / 1.7).ceil();
  }

  /// Shrinks [history] in place until it fits [inputBudget].
  ///
  /// Priority: (1) fold old tool results, (2) fold old user/assistant text.
  /// The system prompt (index 0), the last [protectedTail] messages, and
  /// message *structure* (roles, tool_call ids) are always preserved so the
  /// wire protocols stay valid.
  void compact(List<ChatMessage> history) {
    if (estimate(history) <= inputBudget) return;

    bool isProtected(int i) =>
        i == 0 || i >= history.length - protectedTail;

    // Pass 1: elide tool result bodies, oldest first.
    for (var i = 0; i < history.length; i++) {
      if (isProtected(i)) continue;
      final m = history[i];
      if (m.role != ChatRole.tool || _isElided(m)) continue;
      _elide(m, 'tool result');
      if (estimate(history) <= inputBudget) return;
    }

    // Pass 2: fold old user/assistant turns, oldest first.
    for (var i = 0; i < history.length; i++) {
      if (isProtected(i)) continue;
      final m = history[i];
      if (m.role == ChatRole.tool || m.role == ChatRole.system) continue;
      if (_isElided(m)) continue;
      _elide(m, m.role == ChatRole.user ? 'user message' : 'assistant message');
      if (estimate(history) <= inputBudget) return;
    }
  }

  static const _elidedPrefix = '[elided ';

  bool _isElided(ChatMessage m) =>
      m.parts.length == 1 &&
      (m.parts.first.text?.startsWith(_elidedPrefix) ?? false);

  void _elide(ChatMessage m, String what) {
    final chars = m.parts.fold<int>(
        0, (sum, p) => sum + (p.text?.length ?? 0) + (p.isImage ? 1 : 0));
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
