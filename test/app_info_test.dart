import 'dart:io';

import 'package:dataset_training_tool/app_info.dart';
import 'package:flutter_test/flutter_test.dart';

/// The version is written in three places by hand (see the bump-version
/// skill): pubspec `version:`, [AppInfo.version] for the About card, and
/// `msix_config.msix_version` for the Windows installer. Nothing derives one
/// from another, so a bump that misses one only shows up in a shipped build.
/// This pins all three to each other on every CI run.
void main() {
  // `flutter test` runs with the package root as the working directory.
  final pubspec = File('pubspec.yaml').readAsLinesSync();

  String field(RegExp pattern) {
    for (final line in pubspec) {
      final match = pattern.firstMatch(line);
      if (match != null) return match.group(1)!;
    }
    fail('pubspec.yaml has no line matching $pattern');
  }

  test('AppInfo.version matches pubspec version (without build number)', () {
    final pubspecVersion = field(RegExp(r'^version:\s*(\S+)'));
    final semver = pubspecVersion.split('+').first;
    expect(
      AppInfo.version,
      semver,
      reason:
          'lib/app_info.dart has ${AppInfo.version} but pubspec.yaml has '
          '$pubspecVersion — run the bump-version skill',
    );
  });

  test('msix_version matches pubspec version with "+" replaced by "."', () {
    final pubspecVersion = field(RegExp(r'^version:\s*(\S+)'));
    final msixVersion = field(RegExp(r'^\s+msix_version:\s*(\S+)'));
    expect(
      msixVersion,
      pubspecVersion.replaceAll('+', '.'),
      reason:
          'msix_config.msix_version ($msixVersion) drifted from '
          'version: $pubspecVersion — run the bump-version skill',
    );
  });
}
