import 'dart:io';

import 'tag_text.dart';

const _danbooruHost = 'danbooru.donmai.us';

/// The danbooru wiki page for [tag], written in any caption style.
///
/// Wiki pages are keyed by the canonical underscored name, so `long hair`,
/// `long_hair` and `smile \(expression\)` all have to be folded first.
///
/// Built from path segments, not an interpolated path: tag names may contain
/// a slash (`fate/grand_order`), which has to reach the server escaped rather
/// than as a path separator.
Uri danbooruWikiUrl(String tag) => Uri(
  scheme: 'https',
  host: _danbooruHost,
  pathSegments: ['wiki_pages', danbooruTagName(tag)],
);

/// A post search for [tag] — the fallback when a tag has no wiki page, and
/// the faster answer when the question is "what does this tag look like".
Uri danbooruPostsUrl(String tag) =>
    Uri.https(_danbooruHost, '/posts', {'tags': danbooruTagName(tag)});

/// Opens [url] in the user's default browser.
///
/// Shells out per platform rather than pulling in url_launcher: this app is
/// desktop-only and needs exactly this one call. Returns false when the
/// browser could not be started — callers decide whether that is worth
/// surfacing.
Future<bool> openExternalUrl(Uri url) async {
  try {
    if (Platform.isWindows) {
      // rundll32 rather than `start`: no shell, so nothing in the URL can be
      // read as a command.
      await Process.start('rundll32', [
        'url.dll,FileProtocolHandler',
        url.toString(),
      ]);
    } else if (Platform.isMacOS) {
      await Process.start('open', [url.toString()]);
    } else {
      await Process.start('xdg-open', [url.toString()]);
    }
    return true;
  } catch (_) {
    return false;
  }
}
