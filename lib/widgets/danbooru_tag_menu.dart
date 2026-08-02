import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/tag_dictionary_service.dart';
import '../theme/app_theme.dart';
import '../utils/external_links.dart';
import '../views/panels/tag_dictionary_dialog.dart';
import 'panel_widgets.dart';
import 'tag_gloss.dart';

/// Menu values reserved by [danbooruTagMenuItems]. Hosts route them through
/// [handleDanbooruTagMenuAction] and keep their own values distinct.
const danbooruWikiMenuValue = 'danbooru.wiki';
const danbooruPostsMenuValue = 'danbooru.posts';
const danbooruTranslateMenuValue = 'danbooru.translate';
const danbooruFetchMenuValue = 'danbooru.fetch';

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
  // The translation gets its own header line above the count, in body ink:
  // it is the answer to "what is this tag", which is what the menu is for,
  // while the count is provenance.
  final gloss = listTagGloss(context, tag);
  return [
    if (gloss != null)
      PopupMenuItem<String>(
        enabled: false,
        height: 26,
        child: Text(gloss, style: const TextStyle(fontSize: AppText.secondary)),
      ),
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
    const PopupMenuDivider(height: 9),
    // The dictionary is reachable from the rail too, but this is where the
    // question actually comes up: the moment a tag's meaning is unclear is the
    // moment the user is looking at it.
    panelMenuItem(
      context: context,
      value: danbooruTranslateMenuValue,
      icon: Icons.translate,
      label: gloss == null ? l10n.tagTranslateAction : l10n.tagEditTranslation,
    ),
    // The same destination, one step further along: for a tag nobody has
    // glossed yet, danbooru's own `other_names` are usually the answer, and
    // making the user open the dictionary and press fetch is a step that
    // carries no decision.
    panelMenuItem(
      context: context,
      value: danbooruFetchMenuValue,
      icon: Icons.cloud_download_outlined,
      label: l10n.dictFetchAction,
    ),
  ];
}

/// Handles [action] when it is one of this menu's own values. Returns whether
/// the action belonged to it, so hosts can fall through to their own.
Future<bool> handleDanbooruTagMenuAction(
  BuildContext context,
  String? action,
  String tag,
) async {
  switch (action) {
    case danbooruWikiMenuValue:
      await openExternalUrl(danbooruWikiUrl(tag));
      return true;
    case danbooruPostsMenuValue:
      await openExternalUrl(danbooruPostsUrl(tag));
      return true;
    case danbooruTranslateMenuValue:
      await showTagDictionaryDialog(context, initialTag: tag);
      return true;
    case danbooruFetchMenuValue:
      await showTagDictionaryDialog(
        context,
        initialTag: tag,
        fetchOnOpen: true,
      );
      return true;
  }
  return false;
}
