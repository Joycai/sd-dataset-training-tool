import 'package:flutter/material.dart';

import '../models/tag_translation.dart';
import '../services/tag_translation_service.dart';
import '../theme/app_theme.dart';

/// Makes the active tag glossary reachable from any tag-rendering widget.
///
/// An inherited widget rather than a provider read because tags are rendered
/// in four unrelated places, several of them deep inside `Wrap`s of hundreds
/// of chips: `dependOnInheritedWidgetOfExactType` rebuilds exactly the chips
/// that asked for a gloss, and only when the glossary or the display mode
/// actually changed. Installed above `MaterialApp`, so dialog routes — the
/// dictionary manager included — inherit it too.
class TagGlossScope extends InheritedWidget {
  const TagGlossScope({
    super.key,
    required this.glosses,
    required this.display,
    required super.child,
  });

  final TagTranslationService glosses;
  final TagGlossDisplay display;

  static TagGlossScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<TagGlossScope>();

  @override
  bool updateShouldNotify(TagGlossScope oldWidget) =>
      display != oldWidget.display ||
      !identical(glosses, oldWidget.glosses) ||
      // The service mutates in place, so identity is not enough: a re-notified
      // scope carries the same instance with different contents. Its own
      // revision counter is the only reliable signal — editing one entry's
      // text moves neither the identity nor the count.
      glosses.revision != oldWidget.glosses.revision;
}

/// The translation to render *beside* [tag], or null when there is none or the
/// active mode keeps it out of the layout.
String? inlineTagGloss(BuildContext context, String tag) {
  final scope = TagGlossScope.maybeOf(context);
  if (scope == null || scope.display != TagGlossDisplay.inline) return null;
  return scope.glosses.glossFor(tag);
}

/// The translation for [tag] wherever a second line already exists — the
/// completion list and the tag context menu.
///
/// Answers in every mode but [TagGlossDisplay.off]: those two surfaces have
/// room for it by construction, and the choice between inline and tooltip is
/// about the width-starved chip rows, not about them. Finding a tag by its
/// translation is the main reason to have a glossary at all.
String? listTagGloss(BuildContext context, String tag) {
  final scope = TagGlossScope.maybeOf(context);
  if (scope == null || scope.display == TagGlossDisplay.off) return null;
  return scope.glosses.glossFor(tag);
}

/// The line to put in a tag's tooltip: the translation, plus the longer note
/// when there is one. Null when the glossary has nothing for [tag] or glosses
/// are switched off entirely.
///
/// Unlike [inlineTagGloss] this answers in *both* visible modes — inline mode
/// still wants the note somewhere, and the note never fits on a chip.
String? tagGlossTooltip(BuildContext context, String tag) {
  final scope = TagGlossScope.maybeOf(context);
  if (scope == null || scope.display == TagGlossDisplay.off) return null;
  final entry = scope.glosses.lookup(tag);
  if (entry == null) return null;
  final note = entry.note;
  // Inline mode already shows the text, so a tooltip that only repeats it is
  // noise — there it appears only to carry the note.
  if (scope.display == TagGlossDisplay.inline) {
    return note == null ? null : '${entry.text} — $note';
  }
  return note == null ? entry.text : '${entry.text} — $note';
}

/// The muted translation that follows a tag on a chip, including its leading
/// gap. Renders nothing at all when [inlineTagGloss] has nothing to show, so
/// hosts can drop it into a `Row` unconditionally.
class TagGlossLabel extends StatelessWidget {
  const TagGlossLabel(
    this.tag, {
    super.key,
    this.fontSize = AppText.micro,
    this.maxWidth = 132,
  });

  final String tag;
  final double fontSize;

  /// Chips size themselves to their content inside an unbounded `Wrap`, where
  /// `TextOverflow.ellipsis` never fires on its own. Capping the gloss keeps
  /// one long translation from stretching a chip across the panel.
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final gloss = inlineTagGloss(context, tag);
    if (gloss == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(left: 5),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Text(
          gloss,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: fontSize, color: context.semantic.muted),
        ),
      ),
    );
  }
}

/// Wraps [child] in the tag's gloss tooltip when there is one to show.
Widget withTagGlossTooltip({
  required BuildContext context,
  required String tag,
  required Widget child,
}) {
  final message = tagGlossTooltip(context, tag);
  return message == null ? child : Tooltip(message: message, child: child);
}
