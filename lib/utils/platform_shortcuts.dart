import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Whether the app is running on macOS, where the primary shortcut modifier
/// is Cmd (⌘) rather than Ctrl.
bool get isMacPlatform => !kIsWeb && Platform.isMacOS;

/// Display label for the platform's primary shortcut modifier, for tooltips
/// and the shortcuts help list.
String get primaryModifierLabel => isMacPlatform ? '⌘' : 'Ctrl';

/// A [SingleActivator] bound to the platform's primary modifier — Cmd on
/// macOS, Ctrl elsewhere — instead of a literal Ctrl that macOS users don't
/// expect.
SingleActivator primaryShortcut(LogicalKeyboardKey key, {bool shift = false}) =>
    SingleActivator(
      key,
      control: !isMacPlatform,
      meta: isMacPlatform,
      shift: shift,
    );
