import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/tag_dictionary_service.dart';
import '../theme/app_theme.dart';
import '../utils/external_links.dart';
import '../views/panels/tag_dictionary_dialog.dart';
import 'panel_widgets.dart';
import 'tag_gloss.dart';

/// Every action any tag's right-click menu can offer. A single call site only
/// ever sees the subset [TagMenuSections] enables for it.
enum TagMenuAction {
  filterInclude,
  filterExclude,
  removeFromImage,
  setAnchor,
  clearAnchor,
  applySuggestion,
  addToLibrary,
  removeFromLibrary,
  wiki,
  posts,
  openDictionary,
  replaceAppend,
  deleteGlobal,
}

/// Which optional groups [buildTagMenuItems] renders, in the one fixed order
/// every call site shares: info, filter, current-image, library & dictionary,
/// dataset-wide, danger. A tag's menu differs only in which of these groups
/// it turns on — never in the order they appear.
class TagMenuSections {
  const TagMenuSections({
    this.filter = false,
    this.currentImage = false,
    this.applySuggestion = false,
    this.addToLibrary = false,
    this.removeFromLibrary = false,
    this.datasetOps = false,
    this.danger = false,
  });

  /// "Only images with/without this tag" — feeds the gallery filter.
  final bool filter;

  /// "Remove from this image" + the insertion-anchor toggle. Only meaningful
  /// where the chip represents a tag actually on the current image.
  final bool currentImage;

  /// AI compare view's right column only: adopt the suggestion.
  final bool applySuggestion;

  /// Hidden automatically (see [buildTagMenuItems]'s `inLibrary`) once the tag
  /// is already in the library, so the item never reads as a no-op.
  final bool addToLibrary;

  final bool removeFromLibrary;

  /// Dataset-wide replace/insert — the dataset tab only.
  final bool datasetOps;

  /// Dataset-wide delete — the dataset tab only, always last.
  final bool danger;
}

/// Builds the shared tag right-click menu for every place a tag chip appears
/// (the tag library, the dataset tab, the caption editor, the AI compare
/// view). Sections that are switched off — or that have nothing to show, like
/// "add to library" once the tag is already there — simply disappear rather
/// than leaving a gap, and dividers only appear between groups that both
/// rendered something.
List<PopupMenuEntry<TagMenuAction>> buildTagMenuItems(
  BuildContext context, {
  required String tag,
  required TagMenuSections sections,
  TagDictionaryService? dictionary,
  bool anchorActive = false,
  bool inLibrary = false,
}) {
  final l10n = AppLocalizations.of(context)!;
  final semantic = context.semantic;
  final scheme = Theme.of(context).colorScheme;
  final entry = dictionary?.lookup(tag);
  // Three states, and the third is the useful one: a tag danbooru has never
  // heard of *and* that nothing else in the dataset uses is almost always a
  // typo, while the same tag on forty images is somebody's trigger word.
  final localUses = entry == null ? dictionary?.localUsage(tag) : null;
  final gloss = listTagGloss(context, tag);

  final info = <PopupMenuEntry<TagMenuAction>>[
    if (gloss != null)
      PopupMenuItem<TagMenuAction>(
        enabled: false,
        height: 26,
        child: Text(gloss, style: const TextStyle(fontSize: AppText.secondary)),
      ),
    if (dictionary != null && dictionary.isReady)
      PopupMenuItem<TagMenuAction>(
        enabled: false,
        height: 26,
        child: Text(
          entry != null
              ? l10n.tagPostCount(entry.postCount)
              : (localUses != null && localUses > 0
                    ? l10n.tagNotInDictionaryUsed(localUses)
                    : l10n.tagNotInDictionary),
          style: TextStyle(fontSize: AppText.small, color: semantic.muted),
        ),
      ),
  ];

  final filter = <PopupMenuEntry<TagMenuAction>>[
    if (sections.filter) ...[
      panelMenuItem(
        context: context,
        value: TagMenuAction.filterInclude,
        icon: Icons.filter_alt_outlined,
        label: l10n.menuFilterInclude,
      ),
      panelMenuItem(
        context: context,
        value: TagMenuAction.filterExclude,
        icon: Icons.visibility_off_outlined,
        label: l10n.menuFilterExclude,
      ),
    ],
  ];

  final currentImage = <PopupMenuEntry<TagMenuAction>>[
    if (sections.currentImage) ...[
      panelMenuItem(
        context: context,
        value: TagMenuAction.removeFromImage,
        icon: Icons.close,
        label: l10n.tagMenuRemoveFromImage,
      ),
      panelMenuItem(
        context: context,
        value: anchorActive
            ? TagMenuAction.clearAnchor
            : TagMenuAction.setAnchor,
        icon: Icons.push_pin_outlined,
        label: anchorActive ? l10n.tagMenuClearAnchor : l10n.tagMenuSetAnchor,
      ),
    ],
    if (sections.applySuggestion)
      panelMenuItem(
        context: context,
        value: TagMenuAction.applySuggestion,
        icon: Icons.add,
        label: l10n.tagMenuApplySuggestion,
      ),
  ];

  // The dictionary is reachable from the rail too, but this is where the
  // question actually comes up: the moment a tag's meaning is unclear is the
  // moment the user is looking at it. Wiki/posts/dictionary stay together
  // with library membership because all five answer the same question —
  // "what is this tag, and does it belong in my library?"
  final library = <PopupMenuEntry<TagMenuAction>>[
    panelMenuItem(
      context: context,
      value: TagMenuAction.wiki,
      icon: Icons.menu_book_outlined,
      label: l10n.tagWikiAction,
    ),
    panelMenuItem(
      context: context,
      value: TagMenuAction.posts,
      icon: Icons.image_search,
      label: l10n.tagPostsAction,
    ),
    panelMenuItem(
      context: context,
      value: TagMenuAction.openDictionary,
      icon: Icons.translate,
      label: l10n.tagMenuOpenDictionary,
    ),
    if (sections.addToLibrary && !inLibrary)
      panelMenuItem(
        context: context,
        value: TagMenuAction.addToLibrary,
        icon: Icons.playlist_add,
        label: l10n.tagMenuAddToLibrary,
      ),
    if (sections.removeFromLibrary)
      panelMenuItem(
        context: context,
        value: TagMenuAction.removeFromLibrary,
        icon: Icons.delete_outline,
        label: l10n.removeFromLibrary,
      ),
  ];

  final datasetOps = <PopupMenuEntry<TagMenuAction>>[
    if (sections.datasetOps)
      panelMenuItem(
        context: context,
        value: TagMenuAction.replaceAppend,
        icon: Icons.find_replace,
        label: l10n.menuReplaceAppend,
      ),
  ];

  final danger = <PopupMenuEntry<TagMenuAction>>[
    if (sections.danger)
      panelMenuItem(
        context: context,
        value: TagMenuAction.deleteGlobal,
        icon: Icons.delete_forever_outlined,
        label: l10n.menuDeleteGlobal,
        color: scheme.error,
      ),
  ];

  final items = <PopupMenuEntry<TagMenuAction>>[];
  for (final group in [info, filter, currentImage, library, datasetOps, danger]) {
    if (group.isEmpty) continue;
    if (items.isNotEmpty) items.add(const PopupMenuDivider(height: 9));
    items.addAll(group);
  }
  return items;
}

/// Handles the actions every call site shares (wiki/posts/dictionary). Call
/// sites handle the rest of their own [TagMenuAction]s after this returns
/// false, so each keeps only the switch cases it actually needs.
Future<bool> handleTagMenuAction(
  BuildContext context,
  TagMenuAction? action,
  String tag,
) async {
  switch (action) {
    case TagMenuAction.wiki:
      await openExternalUrl(danbooruWikiUrl(tag));
      return true;
    case TagMenuAction.posts:
      await openExternalUrl(danbooruPostsUrl(tag));
      return true;
    case TagMenuAction.openDictionary:
      await showTagDictionaryDialog(context, initialTag: tag);
      return true;
    default:
      return false;
  }
}
