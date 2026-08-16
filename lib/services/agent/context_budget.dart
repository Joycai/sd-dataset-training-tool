/// Local context-window accounting and history compaction for the agent.
/// Pure Dart.
library;

import '../../models/llm_models.dart';

/// What one [ContextBudget.compact] pass did, so the session can tell the
/// user about it. Folding history is invisible on the wire — the request
/// still returns 200 — so the only place it can become visible is here.
typedef CompactResult = ({
  /// Messages whose bodies were replaced with an elision placeholder.
  int folded,

  /// Image parts replaced with a text placeholder by the unconditional cap.
  int imagesDropped,

  /// True when even after folding everything foldable the history still
  /// exceeds the input budget. The request that follows is over-long; on an
  /// endpoint known to truncate silently it must not be sent at all.
  bool stillOverBudget,
});

class ContextBudget {
  ContextBudget({
    required this.contextWindow,
    required this.maxOutputTokens,
    this.toolSchemaTokens = 0,
    this.safetyMargin = 1024,
    this.protectedTail = 8,
  });

  final int contextWindow;
  final int maxOutputTokens;

  /// What the tool schemas cost in every request (`ToolRegistry.schemaTokens`).
  ///
  /// They are not part of the history, so [estimate] can never see them —
  /// they come off the top of the window instead. Leaving this at 0 is what
  /// made a full registry (a few thousand tokens, a quarter of a 32K window)
  /// invisible to the budget, so compaction fired long after the request had
  /// already outgrown the window.
  final int toolSchemaTokens;

  /// Extra headroom subtracted from the window: local estimation error and
  /// protocol overhead.
  final int safetyMargin;

  /// The most recent N messages are never folded (≈ the last 4 rounds).
  final int protectedTail;

  /// The floor [inputBudget] clamps to: below this there is no conversation
  /// left to fit, only a window that cannot seat one.
  static const _minInputBudget = 1024;

  int get _rawInputBudget =>
      contextWindow - maxOutputTokens - toolSchemaTokens - safetyMargin;

  /// Room left for the history once the reply reservation, the tool schemas
  /// and the safety margin come off the window.
  ///
  /// Clamped so compaction always has a target to aim at. When the clamp is
  /// what produced the number that target is a fiction — see
  /// [windowExhausted].
  int get inputBudget =>
      _rawInputBudget.clamp(_minInputBudget, 1 << 31).toInt();

  /// True when the window has no room for history at all: the reply
  /// reservation, the tool schemas and the safety margin already claim all of
  /// it.
  ///
  /// Reachable on a small local model once several tool packs are switched
  /// on — the schemas alone can be a quarter of a 32K window. The clamp above
  /// would otherwise hand compaction a 1024-token target that a short history
  /// clears, reporting a request that cannot fit as fitting, which is exactly
  /// what [CompactResult.stillOverBudget] exists to prevent. Folding cannot
  /// help either, so [compact] reports it instead of shredding the history
  /// against a target it can never reach.
  bool get windowExhausted => _rawInputBudget <= 0;

  /// Estimated tokens for one image content part (768px JPEG, base64).
  static const imageTokens = 1600;

  /// Hard cap on images kept in the history, newest first.
  ///
  /// Unconditional — it runs even when the token budget shows plenty of
  /// room. [estimate] prices an image at [imageTokens] flat, which tracks the
  /// provider's billing, but on the wire each one is a 768px base64 JPEG
  /// measured in hundreds of KB and it persists across turns. Counting only
  /// tokens, a session that keeps calling view_image grows a request body no
  /// endpoint accepts while the estimate still reads as fine. Tool-attached
  /// and user-attached images count the same: both are base64 on the wire,
  /// and capping only one kind lets the other walk around the cap.
  static const maxImages = 4;

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

  /// Shrinks [history] in place until it fits [inputBudget], and reports
  /// what it did.
  ///
  /// Pass 0 caps images at [maxImages] unconditionally (see there). Then,
  /// only when over budget: (1) fold old *unpinned* tool results, (2) fold
  /// old user/assistant text, (3) fold pinned tool results as a last resort.
  /// The system prompt (index 0), the last [protectedTail] messages, and
  /// message *structure* (roles, tool_call ids) are always preserved so the
  /// wire protocols stay valid.
  ///
  /// The pinned pass exists because folding a `read_captions` body out from
  /// under a long per-image rewrite leaves the model retyping captions from
  /// memory — it invents tags and drops real ones. Deferring those bodies
  /// keeps the source of truth in context for as long as the window allows;
  /// pass 3 still guarantees the history shrinks when it must.
  CompactResult compact(List<ChatMessage> history) {
    final imagesDropped = _capImages(history);
    var folded = 0;

    CompactResult result() => (
      folded: folded,
      imagesDropped: imagesDropped,
      stillOverBudget: windowExhausted || estimate(history) > inputBudget,
    );

    // The image cap above still applies — it bounds request bytes and is
    // worth doing whatever the token maths says. Folding is not: no history
    // is small enough to rescue a window this size, and the passes below
    // would elide every foldable message to prove it.
    if (windowExhausted) return result();

    if (estimate(history) <= inputBudget) return result();

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
        folded++;
        if (estimate(history) <= inputBudget) return true;
      }
      return false;
    }

    // Pass 1: elide unpinned tool result bodies, oldest first.
    if (foldToolResults(pinned: false)) return result();

    // Pass 2: fold old user/assistant turns, oldest first.
    for (var i = 0; i < history.length; i++) {
      if (isProtected(i)) continue;
      final m = history[i];
      if (m.role == ChatRole.tool || m.role == ChatRole.system) continue;
      if (_isElided(m)) continue;
      _elide(m, m.role == ChatRole.user ? 'user message' : 'assistant message');
      folded++;
      if (estimate(history) <= inputBudget) return result();
    }

    // Pass 3: nothing cheap is left — the pinned bodies go too.
    foldToolResults(pinned: true);
    return result();
  }

  /// Replaces all but the newest [maxImages] image parts with a text
  /// placeholder, oldest first. Text parts of the same message survive.
  /// Runs regardless of the token budget — see [maxImages] for why. Even the
  /// protected tail is not exempt: the cap bounds request *bytes*, and a
  /// recent message's image weighs the same as an old one's.
  int _capImages(List<ChatMessage> history) {
    var total = 0;
    for (final m in history) {
      total += m.imageCount;
    }
    var toDrop = total - maxImages;
    if (toDrop <= 0) return 0;
    final dropped = toDrop;
    for (final m in history) {
      if (toDrop == 0) break;
      if (m.imageCount == 0) continue;
      final parts = <ChatContentPart>[];
      for (final p in m.parts) {
        if (p.isImage && toDrop > 0) {
          toDrop--;
          parts.add(
            const ChatContentPart.text('[image dropped to bound request size]'),
          );
        } else {
          parts.add(p);
        }
      }
      m.parts = parts;
    }
    return dropped;
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
