import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/tag_dictionary_service.dart';
import '../theme/app_theme.dart';
import '../utils/external_links.dart';
import 'panel_widgets.dart';

/// Menu values reserved by [danbooruTagMenuItems]. Hosts route them through
/// [handleDanbooruTagMenuAction] and keep their own values distinct.
const danbooruWikiMenuValue = 'danbooru.wiki';
const danbooruPostsMenuValue = 'danbooru.posts';

/// "What is this tag?" entries for any tag context menu.
///
/// Wherever a tag is shown, the two questions worth one click are what it
/// means (the wiki, which is also where implications and aliases live) and
/// what it looks like (the post search). [dictionary], when given, adds a
/// header line with the tag's post count — or a note that danbooru has never
/// heard of it, which is how a typo announces itself.
List<PopupMenuEntry<String>> danbooruTagMenuItems(
  BuildContext context, {
  required String tag,
  TagDictionaryService? dictionary,
}) {
  final l10n = AppLocalizations.of(context)!;
  final semantic = context.semantic;
  final entry = dictionary?.lookup(tag);
  // Three states, and the third is the useful one: a tag danbooru has never
  // heard of *and* that nothing else in the dataset uses is almost always a
  // typo, while the same tag on forty images is somebody's trigger word.
  final localUses = entry == null ? dictionary?.localUsage(tag) : null;
  return [
    if (dictionary != null && dictionary.isReady)
      PopupMenuItem<String>(
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
    panelMenuItem(
      context: context,
      value: danbooruWikiMenuValue,
      icon: Icons.menu_book_outlined,
      label: l10n.tagWikiAction,
    ),
    panelMenuItem(
      context: context,
      value: danbooruPostsMenuValue,
      icon: Icons.image_search,
      label: l10n.tagPostsAction,
    ),
  ];
}

/// Opens the browser when [action] is one of this menu's own values. Returns
/// whether the action belonged to it, so hosts can fall through to their own.
Future<bool> handleDanbooruTagMenuAction(String? action, String tag) async {
  switch (action) {
    case danbooruWikiMenuValue:
      await openExternalUrl(danbooruWikiUrl(tag));
      return true;
    case danbooruPostsMenuValue:
      await openExternalUrl(danbooruPostsUrl(tag));
      return true;
  }
  return false;
}
