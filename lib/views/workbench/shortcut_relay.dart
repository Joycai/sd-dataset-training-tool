import 'package:flutter/foundation.dart';

/// Bridges workbench-level keyboard shortcuts to actions whose logic lives
/// inside a panel. The panel registers its handler on mount and clears it on
/// dispose; a null handler simply makes the shortcut a no-op.
class ShortcutRelay {
  /// Runs AI interrogation for the image open in the caption panel.
  VoidCallback? runAiForCurrentImage;
}
