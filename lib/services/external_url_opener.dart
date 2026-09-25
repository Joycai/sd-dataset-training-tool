import 'dart:io';

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
