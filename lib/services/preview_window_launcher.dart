import 'dart:convert';

import 'package:desktop_multi_window/desktop_multi_window.dart';

/// Opens (or refreshes) the external preview window. The inline preview is
/// the primary surface; this window is the opt-in second-screen companion.
class PreviewWindowLauncher {
  WindowController? _window;

  Future<void> show(List<String> imagePaths, int currentIndex) async {
    final args = jsonEncode({
      'imagePaths': imagePaths,
      'currentIndex': currentIndex,
    });

    final existing = _window;
    if (existing != null) {
      try {
        await existing.invokeMethod('update_image', args);
        await existing.show();
        return;
      } on WindowChannelException {
        // The preview window was closed; create a new one below.
        _window = null;
      }
    }

    final window = await WindowController.create(
      WindowConfiguration(arguments: args),
    );
    _window = window;
    await window.show();
  }
}
