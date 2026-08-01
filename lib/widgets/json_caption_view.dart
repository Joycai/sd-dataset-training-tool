import 'dart:convert';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';

/// Read-only, syntax-highlighted view of a JSON caption: pretty-printed with
/// two-space indents, keys and values tinted by role. The caption panel shows
/// this instead of the tag grid while a JSON-format type is active — the
/// text tab stays the place to actually edit the document.
///
/// Unparseable text is not hidden behind the error: the raw caption renders
/// below the parse message so the user can see what to fix.
class JsonCaptionView extends StatelessWidget {
  const JsonCaptionView({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final semantic = context.semantic;
    final scheme = Theme.of(context).colorScheme;

    if (text.trim().isEmpty) {
      return Center(
        child: Text(
          l10n.captionJsonEmpty,
          style: TextStyle(fontSize: 12.5, color: semantic.muted),
        ),
      );
    }

    final dynamic decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException catch (e) {
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.error_outline, size: 14, color: scheme.error),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    l10n.captionJsonInvalid(e.message),
                    style: TextStyle(fontSize: AppText.small, color: scheme.error),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SelectableText(
              text,
              style: monoStyle(context, size: 12.5, color: semantic.muted),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: SelectableText.rich(
        TextSpan(
          style: monoStyle(context, size: 12.5).copyWith(height: 1.55),
          children: jsonHighlightSpans(
            decoded,
            keyStyle: TextStyle(
              color: scheme.primary,
              fontWeight: FontWeight.w600,
            ),
            stringStyle: TextStyle(color: semantic.ok),
            literalStyle: TextStyle(color: semantic.warn),
            punctStyle: TextStyle(color: semantic.muted),
          ),
        ),
      ),
    );
  }
}

/// Pretty-prints a decoded JSON value into styled spans: objects one key per
/// line with two-space indents, arrays inline (matching how tag lists read),
/// keys / string values / other literals / punctuation each in their own
/// style. Exposed as a function so tests can assert on the emitted tokens.
List<InlineSpan> jsonHighlightSpans(
  dynamic value, {
  required TextStyle keyStyle,
  required TextStyle stringStyle,
  required TextStyle literalStyle,
  required TextStyle punctStyle,
}) {
  final out = <InlineSpan>[];
  void punct(String s) => out.add(TextSpan(text: s, style: punctStyle));

  void write(dynamic node, int depth) {
    final pad = '  ' * (depth + 1);
    if (node is Map) {
      if (node.isEmpty) {
        punct('{}');
        return;
      }
      punct('{\n');
      var first = true;
      for (final entry in node.entries) {
        if (!first) punct(',\n');
        first = false;
        punct(pad);
        out.add(TextSpan(text: jsonEncode('${entry.key}'), style: keyStyle));
        punct(': ');
        write(entry.value, depth + 1);
      }
      punct('\n${'  ' * depth}}');
    } else if (node is List) {
      if (node.isEmpty) {
        punct('[]');
        return;
      }
      punct('[');
      for (var i = 0; i < node.length; i++) {
        if (i > 0) punct(', ');
        write(node[i], depth + 1);
      }
      punct(']');
    } else if (node is String) {
      out.add(TextSpan(text: jsonEncode(node), style: stringStyle));
    } else {
      // Numbers, booleans, null.
      out.add(TextSpan(text: jsonEncode(node), style: literalStyle));
    }
  }

  write(value, 0);
  return out;
}
