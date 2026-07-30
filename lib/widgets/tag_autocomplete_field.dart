import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';
import '../models/tag_dictionary.dart';
import '../services/ai_tagger_service.dart';
import '../services/tag_dictionary_service.dart';
import '../theme/app_theme.dart';
import '../utils/external_links.dart';
import 'tag_gloss.dart';

/// How a completion is spelled when it lands in the caption.
///
/// The dictionary stores danbooru's own spelling (`long_hair`); datasets are
/// written in whatever style their owner picked. These are the same two knobs
/// the AI tagger already exposes, so a hand-completed tag and an AI-suggested
/// one come out identical.
class TagInsertStyle {
  const TagInsertStyle({
    this.underscoreToSpaces = true,
    this.escapeParentheses = false,
  });

  final bool underscoreToSpaces;
  final bool escapeParentheses;

  String format(String canonical) => AiTaggerService.normalizeTag(
    canonical,
    underscoreStyle: underscoreToSpaces
        ? TagUnderscoreStyle.toSpaces
        : TagUnderscoreStyle.keep,
    escapeParentheses: escapeParentheses,
  );

  @override
  bool operator ==(Object other) =>
      other is TagInsertStyle &&
      other.underscoreToSpaces == underscoreToSpaces &&
      other.escapeParentheses == escapeParentheses;

  @override
  int get hashCode => Object.hash(underscoreToSpaces, escapeParentheses);
}

/// A text field that completes danbooru tags as you type.
///
/// Completion targets the *segment under the caret* — the run of text between
/// the surrounding commas — so it works the same in a one-tag input and in a
/// comma-separated list.
///
/// Keys, while the list is open:
///
///  * Down/Up move the highlight. Nothing is highlighted until they are
///    pressed, so Enter on freshly typed text always submits that text rather
///    than silently swapping in a suggestion.
///  * Tab completes (the highlight, or the first row when there is none).
///  * Enter accepts the highlight, or falls through to [onSubmitted].
///  * F1 opens the danbooru wiki for the highlighted (or first) row.
///  * Escape closes the list.
///
/// These are handled on a [Focus] wrapped around the field, which sits below
/// the workbench's root shortcut node in the focus tree and therefore sees the
/// keys first — arrow keys move the highlight instead of the image selection.
class TagAutocompleteField extends StatefulWidget {
  const TagAutocompleteField({
    super.key,
    required this.controller,
    required this.dictionary,
    this.focusNode,
    this.decoration,
    this.style,
    this.insertStyle = const TagInsertStyle(),
    this.onSubmitted,
    this.autofocus = false,
    this.maxSuggestions = 8,
    this.enabled = true,
  });

  final TextEditingController controller;
  final TagDictionaryService dictionary;
  final FocusNode? focusNode;
  final InputDecoration? decoration;
  final TextStyle? style;
  final TagInsertStyle insertStyle;

  /// Called on Enter when no suggestion is highlighted — i.e. the field's
  /// normal submit behaviour, unchanged.
  final ValueChanged<String>? onSubmitted;

  final bool autofocus;
  final int maxSuggestions;
  final bool enabled;

  @override
  State<TagAutocompleteField> createState() => _TagAutocompleteFieldState();
}

class _TagAutocompleteFieldState extends State<TagAutocompleteField> {
  final _portal = OverlayPortalController();
  final _link = LayerLink();
  final _fieldKey = GlobalKey();

  FocusNode? _ownedFocus;
  FocusNode get _focus => widget.focusNode ?? (_ownedFocus ??= FocusNode());

  List<TagSuggestion> _suggestions = const [];
  int _highlight = -1;

  /// Measured when the list opens: its width matches the field, and it flips
  /// above the field when there is more room up there (the caption editor's
  /// input sits at the very bottom of the window).
  double _listWidth = 260;
  bool _above = true;
  double _maxListHeight = 240;

  /// Set while a completion is being written back, so the controller listener
  /// does not immediately re-open the list on the text it just inserted.
  bool _applying = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
    _focus.addListener(_onFocusChanged);
    widget.dictionary.addListener(_onDictionaryChanged);
  }

  @override
  void didUpdateWidget(TagAutocompleteField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onTextChanged);
      widget.controller.addListener(_onTextChanged);
    }
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode?.removeListener(_onFocusChanged);
      _focus.addListener(_onFocusChanged);
    }
    if (oldWidget.dictionary != widget.dictionary) {
      oldWidget.dictionary.removeListener(_onDictionaryChanged);
      widget.dictionary.addListener(_onDictionaryChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    widget.focusNode?.removeListener(_onFocusChanged);
    widget.dictionary.removeListener(_onDictionaryChanged);
    _ownedFocus?.dispose();
    super.dispose();
  }

  // --- Query plumbing -------------------------------------------------

  /// The comma-delimited segment the caret is in, as `[start, caret)`.
  (int, String) _currentSegment() {
    final text = widget.controller.text;
    final selection = widget.controller.selection;
    // An unset/invalid selection (fresh controller, programmatic set) means
    // "end of text" as far as completion is concerned.
    final caret = selection.isValid
        ? selection.baseOffset.clamp(0, text.length)
        : text.length;
    // lastIndexOf rejects a negative start, which is exactly where an empty
    // field with the caret at 0 lands.
    final start = caret == 0 ? 0 : text.lastIndexOf(',', caret - 1) + 1;
    return (start, text.substring(start, caret));
  }

  void _onTextChanged() {
    if (_applying || !mounted) return;
    _refresh();
  }

  void _onDictionaryChanged() {
    // The dictionary finishes loading a moment after startup; whatever was
    // already typed should start matching without another keystroke.
    if (mounted && _focus.hasFocus) _refresh();
  }

  void _refresh() {
    final (_, query) = _currentSegment();
    final matches = widget.enabled && _focus.hasFocus
        ? widget.dictionary.search(query, limit: widget.maxSuggestions)
        : const <TagSuggestion>[];
    // Nothing is preselected: see the class docs on Enter.
    setState(() {
      _suggestions = matches;
      _highlight = -1;
    });
    if (matches.isEmpty) {
      _close();
    } else {
      _open();
    }
  }

  void _onFocusChanged() {
    if (!_focus.hasFocus) {
      _close();
    }
  }

  void _open() {
    _measure();
    if (!_portal.isShowing) _portal.show();
  }

  void _close() {
    if (_portal.isShowing) _portal.hide();
  }

  void _measure() {
    final box = _fieldKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final origin = box.localToGlobal(Offset.zero);
    final screen = MediaQuery.of(context).size;
    final roomAbove = origin.dy;
    final roomBelow = screen.height - (origin.dy + box.size.height);
    _listWidth = box.size.width.clamp(220.0, 460.0);
    _above = roomAbove >= roomBelow;
    _maxListHeight = ((_above ? roomAbove : roomBelow) - 16).clamp(80.0, 260.0);
  }

  // --- Accepting ------------------------------------------------------

  void _move(int delta) {
    if (_suggestions.isEmpty) return;
    setState(() {
      // From "nothing highlighted", Down lands on the first row and Up on the
      // last, so either key reaches a suggestion in one press.
      if (_highlight < 0) {
        _highlight = delta > 0 ? 0 : _suggestions.length - 1;
      } else {
        _highlight = (_highlight + delta) % _suggestions.length;
        if (_highlight < 0) _highlight += _suggestions.length;
      }
    });
  }

  /// How a suggestion is spelled once inserted.
  ///
  /// Dictionary tags are converted from danbooru's spelling into the user's.
  /// Local tags are inserted verbatim: they were *read out of* this dataset,
  /// so they are already in its style — running `my_trigger_word` through the
  /// underscore conversion would invent a tag that appears nowhere.
  String _spell(TagSuggestion suggestion) => suggestion.isLocal
      ? suggestion.name
      : widget.insertStyle.format(suggestion.name);

  void _accept(TagSuggestion suggestion) {
    final text = widget.controller.text;
    final (start, query) = _currentSegment();
    final caret = start + query.length;
    // Keep the caller's spacing after the comma: "a, lon" completes to
    // "a, long hair", not "a,long hair".
    final leading = query.length - query.trimLeft().length;
    final inserted = _spell(suggestion);
    final replacement = query.substring(0, leading) + inserted;

    _applying = true;
    widget.controller.value = TextEditingValue(
      text: text.replaceRange(start, caret, replacement),
      selection: TextSelection.collapsed(offset: start + replacement.length),
    );
    _applying = false;

    setState(() {
      _suggestions = const [];
      _highlight = -1;
    });
    _close();
  }

  Future<void> _openWiki(TagSuggestion suggestion) async {
    // A local or hand-added tag has no danbooru wiki page by definition.
    if (suggestion.isLocal || suggestion.isCustom) return;
    // Canonical name, not the user's spelling: the wiki is keyed by it.
    await openExternalUrl(danbooruWikiUrl(suggestion.name));
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;

    if (!_portal.isShowing) {
      // Down re-opens a list the user dismissed with Escape, without making
      // them retype anything.
      if (key == LogicalKeyboardKey.arrowDown && _suggestions.isNotEmpty) {
        _open();
        _move(1);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    if (key == LogicalKeyboardKey.arrowDown) {
      _move(1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _move(-1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      _close();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.tab) {
      _accept(_suggestions[_highlight < 0 ? 0 : _highlight]);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.f1) {
      _openWiki(_suggestions[_highlight < 0 ? 0 : _highlight]);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      // Only a deliberate highlight takes the Enter; otherwise the field
      // submits exactly what was typed.
      if (_highlight >= 0) {
        _accept(_suggestions[_highlight]);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    return KeyEventResult.ignored;
  }

  // --- Build ----------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return OverlayPortal(
      controller: _portal,
      overlayChildBuilder: _buildList,
      child: CompositedTransformTarget(
        link: _link,
        child: Focus(
          // Not focusable itself — it exists purely to see the keys before
          // the workbench's root shortcut node does.
          canRequestFocus: false,
          onKeyEvent: _onKeyEvent,
          child: TextField(
            key: _fieldKey,
            controller: widget.controller,
            focusNode: _focus,
            enabled: widget.enabled,
            autofocus: widget.autofocus,
            style: widget.style,
            decoration: widget.decoration,
            onSubmitted: widget.onSubmitted,
          ),
        ),
      ),
    );
  }

  Widget _buildList(BuildContext context) {
    final semantic = context.semantic;
    final queryLength = _currentSegment().$2.trim().length;
    return Positioned(
      left: 0,
      top: 0,
      child: CompositedTransformFollower(
        link: _link,
        targetAnchor: _above ? Alignment.topLeft : Alignment.bottomLeft,
        followerAnchor: _above ? Alignment.bottomLeft : Alignment.topLeft,
        offset: Offset(0, _above ? -4 : 4),
        child: Align(
          alignment: AlignmentDirectional.topStart,
          child: SizedBox(
            width: _listWidth,
            child: Material(
              color: semantic.raised,
              elevation: 8,
              borderRadius: BorderRadius.circular(AppRadii.control),
              clipBehavior: Clip.antiAlias,
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: semantic.line),
                  borderRadius: BorderRadius.circular(AppRadii.control),
                ),
                constraints: BoxConstraints(maxHeight: _maxListHeight),
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  shrinkWrap: true,
                  itemCount: _suggestions.length,
                  itemBuilder: (context, index) => _SuggestionRow(
                    suggestion: _suggestions[index],
                    display: _spell(_suggestions[index]),
                    queryLength: queryLength,
                    selected: index == _highlight,
                    onTap: () => _accept(_suggestions[index]),
                    onWiki: () => _openWiki(_suggestions[index]),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SuggestionRow extends StatelessWidget {
  const _SuggestionRow({
    required this.suggestion,
    required this.display,
    required this.queryLength,
    required this.selected,
    required this.onTap,
    required this.onWiki,
  });

  final TagSuggestion suggestion;
  final String display;

  /// How many leading characters the query matched, so the completed part of
  /// the row reads as the part the user has not typed yet.
  final int queryLength;

  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onWiki;

  /// The row's second line, or null when this hit has nothing to add: the
  /// translation, then where the hit came from.
  String? _secondary(BuildContext context, AppLocalizations l10n) {
    final parts = <String>[
      ?listTagGloss(context, suggestion.name),
      if (suggestion.isCustom)
        l10n.tagSuggestionCustom
      else if (suggestion.isLocal)
        suggestion.count > 0
            ? l10n.tagSuggestionLocalUsed(suggestion.count)
            : l10n.tagSuggestionLocalLibrary
      else if (suggestion.matchedAlias != null)
        l10n.tagSuggestionAlias(suggestion.matchedAlias!),
    ];
    return parts.isEmpty ? null : parts.join('  ·  ');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final semantic = context.semantic;
    final scheme = Theme.of(context).colorScheme;
    final matched = queryLength.clamp(0, display.length);

    return InkWell(
      onTap: onTap,
      // Never take focus: the list closes as soon as the field loses it, so a
      // focusable row would dismiss itself out from under the click.
      canRequestFocus: false,
      child: Container(
        color: selected ? scheme.primary.withAlpha(38) : null,
        padding: const EdgeInsets.fromLTRB(8, 5, 4, 5),
        child: Row(
          children: [
            Container(
              width: 7,
              height: 7,
              margin: const EdgeInsets.only(right: 8),
              // Local tags get a hollow dot: they carry no danbooru category,
              // and the outline reads as "yours" rather than as a sixth
              // category colour.
              decoration: BoxDecoration(
                color: suggestion.isLocal
                    ? null
                    : _categoryColor(suggestion.entry.category, semantic),
                border: suggestion.isLocal
                    ? Border.all(color: semantic.muted, width: 1.2)
                    : null,
                shape: BoxShape.circle,
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: display.substring(0, matched),
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: scheme.primary,
                          ),
                        ),
                        TextSpan(text: display.substring(matched)),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: AppText.secondary),
                  ),
                  // One second line, assembled from whatever this hit has to
                  // say. The translation leads it — finding a tag by its
                  // meaning is the whole point of having a glossary — and the
                  // provenance note follows: a local hit's count means "images
                  // in this dataset", not "posts on danbooru", and rendering
                  // the two the same way would misread badly.
                  if (_secondary(context, l10n) case final secondary?)
                    Text(
                      secondary,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: AppText.micro,
                        color: semantic.muted,
                      ),
                    ),
                ],
              ),
            ),
            // Danbooru's post count and its wiki only mean anything for a tag
            // danbooru actually has; a local or hand-added tag would just link
            // to a 404.
            if (!suggestion.isLocal && !suggestion.isCustom) ...[
              const SizedBox(width: 6),
              Text(
                _formatCount(suggestion.count),
                style: monoStyle(
                  context,
                  size: AppText.micro,
                  color: semantic.muted,
                ),
              ),
              InkWell(
                onTap: onWiki,
                canRequestFocus: false,
                borderRadius: BorderRadius.circular(AppRadii.pill),
                child: Tooltip(
                  message: l10n.tagWikiTooltip,
                  child: Padding(
                    padding: const EdgeInsets.all(5),
                    child: Icon(
                      Icons.help_outline,
                      size: 13,
                      color: semantic.muted,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Danbooru's own category colours, desaturated enough to sit on both themes.
/// General tags get no colour of their own — they are the overwhelming
/// majority, and tinting them would turn the whole list into noise.
Color _categoryColor(TagCategory category, AppSemanticColors semantic) =>
    switch (category) {
      TagCategory.general => semantic.muted,
      TagCategory.artist => const Color(0xFFE0525C),
      TagCategory.copyright => const Color(0xFFB05CD6),
      TagCategory.character => const Color(0xFF3FA65A),
      TagCategory.meta => const Color(0xFFE08B3E),
    };

/// Post counts run to eight digits; the row only has room for a magnitude.
String _formatCount(int count) {
  if (count >= 1000000) {
    final m = count / 1000000;
    return '${m.toStringAsFixed(m >= 10 ? 0 : 1)}M';
  }
  if (count >= 1000) {
    final k = count / 1000;
    return '${k.toStringAsFixed(k >= 10 ? 0 : 1)}k';
  }
  return '$count';
}
