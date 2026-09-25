import 'package:dataset_training_tool/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The refresh spec quotes the neutral ramp as concrete hex values. The
/// palette derives them from the accent hue instead, so it can only match
/// the spec's *lightness*; this pins that, and the saturation budget that
/// keeps the accent readable on the chrome.
void main() {
  String hex(Color c) =>
      '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

  for (final entry in {
    Brightness.dark: {
      'bg0': ('#1e1e20', 0.122),
      'bg1': ('#26262a', 0.157),
      'bg2': ('#313136', 0.202),
      'ink': ('#f2f2f4', 0.953),
      'muted': ('#98989f', 0.610),
    },
    Brightness.light: {
      'bg0': ('#ececf0', 0.933),
      'bg1': ('#f7f7f9', 0.973),
      'ink': ('#1d1d1f', 0.118),
      'muted': ('#7a7a80', 0.490),
    },
  }.entries) {
    test('${entry.key.name} ramp tracks the spec lightness', () {
      for (final accent in AppAccentChoice.values) {
        final p = AppPalette.derive(accent.accentFor(entry.key), entry.key);
        final tones = {
          'bg0': p.bg0,
          'bg1': p.bg1,
          'bg2': p.bg2,
          'ink': p.ink,
          'muted': p.muted,
        };
        for (final want in entry.value.entries) {
          final hsl = HSLColor.fromColor(tones[want.key]!);
          expect(
            hsl.lightness,
            closeTo(want.value.$2, 0.005),
            reason:
                '${accent.id} ${want.key} = ${hex(tones[want.key]!)}, '
                'spec ${want.value.$1}',
          );
          // Tinted, but nowhere near a color wash.
          expect(
            hsl.saturation,
            lessThanOrEqualTo(0.17),
            reason: '${accent.id} ${want.key} too saturated',
          );
        }
      }
    });
  }

  test('hairlines and glass are translucent so they layer on any bg', () {
    for (final b in Brightness.values) {
      final p = AppPalette.derive(AppAccentChoice.teal.accentFor(b), b);
      expect(p.line.a, lessThan(0.2));
      expect(p.glass.a, inInclusiveRange(0.7, 0.9));
      expect(p.shadow.a, greaterThan(0));
    }
  });
}
