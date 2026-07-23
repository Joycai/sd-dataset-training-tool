/// App metadata shown on the settings "About" card.
///
/// [version] mirrors the `version:` field in pubspec.yaml (semver part,
/// without the build number). Do not edit the version by hand — run the
/// `sync-version` skill so both files stay in lockstep.
abstract final class AppInfo {
  /// Kept in sync with pubspec.yaml by the sync-version skill.
  static const String version = '1.0.0';

  static const String copyright = '© 2025-2026 Joycai';
  static const String license = 'GPL-3.0';
  static const String repositoryUrl =
      'https://github.com/Joycai/sd-dataset-training-tool';
}
