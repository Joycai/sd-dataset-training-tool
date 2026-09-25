/// Enforces the `lib/` layer rules from docs/ARCHITECTURE.md (the matrix in
/// docs/plans/CODE_STRUCTURE_REFACTOR_LLD.md §3). Run from the repo root:
///
///     dart run tool/check_layers.dart [libDir]
///
/// Every `import`, `export` and `part` URI (conditional-import alternatives
/// included) in a restricted layer is resolved to the top-level `lib/` entry it
/// points at — relative paths and `package:dataset_training_tool/...` alike —
/// and must be in that layer's allowed set. Other packages and `dart:` are not
/// restricted. Prints each violation and exits 1 if there are any.
library;

// This is a CLI check — print is the intended output channel.
// ignore_for_file: avoid_print

import 'dart:io';

const String packageName = 'dataset_training_tool';

/// Layer → the top-level `lib/` entries it may import. Keep in sync with the
/// ARCHITECTURE.md table.
const Map<String, Set<String>> allowedImports = {
  'widgets': {
    'widgets',
    'state',
    'services',
    'models',
    'theme',
    'utils',
    'l10n',
    'app_info.dart',
  },
  'state': {
    'state',
    'agent',
    'services',
    'models',
    'theme',
    'utils',
    'l10n',
    'app_info.dart',
  },
  'agent': {
    'agent',
    'state',
    'services',
    'models',
    'utils',
    'l10n',
    'app_info.dart',
  },
  'services': {'services', 'models', 'theme', 'utils', 'app_info.dart'},
  'models': {'models'},
  'theme': {'theme', 'models'},
  'utils': {'utils', 'models'},
};

/// Top-level directories that may import anything. `l10n/` holds generated
/// code. Files directly under `lib/` (`main.dart`, `app_info.dart`) are
/// unrestricted as well.
const Set<String> unrestrictedDirs = {'views', 'l10n'};

/// Returned by [resolveTopLevel] for a URI that climbs out of `lib/`.
const String outsideLib = '<outside lib/>';

class Violation {
  const Violation(this.file, this.uri, this.message);

  /// Path relative to `lib/`, `/`-separated.
  final String file;
  final String? uri;
  final String message;

  @override
  String toString() =>
      uri == null ? 'lib/$file: $message' : "lib/$file -> '$uri': $message";
}

final RegExp _directive = RegExp(
  r'''^[ \t]*(?:import|export|part)\s+(['"][^;]*);''',
  multiLine: true,
);
final RegExp _condition = RegExp(r'\([^)]*\)');
final RegExp _stringLiteral = RegExp(r'''(['"])(.*?)\1''');

/// The URIs of every `import`/`export`/`part` directive in [source],
/// including the alternatives of conditional imports. `part of` is skipped.
List<String> directiveUris(String source) => [
  for (final m in _directive.allMatches(source))
    for (final s in _stringLiteral.allMatches(
      // Drop `if (dart.library.io)` conditions so only URIs remain.
      m.group(1)!.replaceAll(_condition, ''),
    ))
      s.group(2)!,
];

/// The top-level `lib/` entry (`widgets`, `app_info.dart`, …) that [uri],
/// written in the file at [file] (relative to `lib/`), refers to. Null for
/// `dart:` and other packages; [outsideLib] if it resolves outside `lib/`.
String? resolveTopLevel(String file, String uri) {
  final List<String> segments;
  if (uri.startsWith('package:')) {
    final prefix = 'package:$packageName/';
    if (!uri.startsWith(prefix)) return null;
    segments = Uri.parse(
      'file:///lib/${uri.substring(prefix.length)}',
    ).pathSegments;
  } else if (Uri.parse(uri).hasScheme) {
    return null; // dart:, and anything else with a scheme.
  } else {
    segments = Uri.parse('file:///lib/$file').resolve(uri).pathSegments;
  }
  if (segments.length < 2 || segments.first != 'lib') return outsideLib;
  return segments[1];
}

/// Checks every `.dart` file under [lib] against [allowedImports].
List<Violation> checkLayers(Directory lib) {
  final violations = <Violation>[];
  final root = lib.absolute.uri;
  final files = {
    for (final f in lib.listSync(recursive: true).whereType<File>())
      if (f.path.endsWith('.dart'))
        Uri.decodeComponent(f.absolute.uri.path.substring(root.path.length)): f,
  };
  for (final file in files.keys.toList()..sort()) {
    final parts = file.split('/');
    if (parts.length == 1) continue; // main.dart, app_info.dart
    final layer = parts.first;
    if (unrestrictedDirs.contains(layer)) continue;
    final allowed = allowedImports[layer];
    if (allowed == null) {
      violations.add(
        Violation(
          file,
          null,
          "'$layer/' is not a known layer; add it to the ARCHITECTURE.md "
          'table and to tool/check_layers.dart',
        ),
      );
      continue;
    }
    final source = files[file]!.readAsStringSync();
    for (final uri in directiveUris(source)) {
      final target = resolveTopLevel(file, uri);
      if (target == null || allowed.contains(target)) continue;
      violations.add(Violation(file, uri, '$layer/ may not depend on $target'));
    }
  }
  return violations;
}

void main(List<String> args) {
  final lib = Directory(args.isNotEmpty ? args.first : 'lib');
  if (!lib.existsSync()) {
    stderr.writeln(
      'No ${lib.path}/ here; run from the repo root or pass the lib path.',
    );
    exit(2);
  }
  final violations = checkLayers(lib);
  for (final v in violations) {
    print('VIOLATION $v');
  }
  print('violations: ${violations.length}');
  if (violations.isNotEmpty) exit(1);
}
