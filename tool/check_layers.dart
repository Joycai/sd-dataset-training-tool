/// Enforces the `lib/` layer rules from docs/ARCHITECTURE.md (the matrix in
/// docs/plans/CODE_STRUCTURE_REFACTOR_LLD.md §3). Run from the repo root:
///
///     dart run tool/check_layers.dart [libDir]
///
/// Every `import` and `export` URI (conditional-import alternatives included)
/// in a restricted layer is resolved to the top-level `lib/` entry it points
/// at — relative paths and `package:dataset_training_tool/...` alike — and
/// must be in that layer's allowed set. A `part` / `part of` must stay inside
/// its own top-level entry, so a part file cannot smuggle code into another
/// layer's library. Other packages and `dart:` are not restricted. Prints each
/// violation and exits 1 if there are any.
///
/// Directives are read with a small scanner rather than a regex: Dart only
/// allows them before the first declaration, so scanning stops there, and
/// comments, raw strings and annotations are lexed instead of pattern-matched.
library;

import 'dart:io';

const String packageName = 'dataset_training_tool';

/// Layer → the top-level `lib/` entries it may import. Keep in sync with the
/// ARCHITECTURE.md table (test/tool/check_layers_test.dart compares them).
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
  'l10n': {'l10n'},
  'app_info.dart': {'app_info.dart'},
};

/// Top-level entries that may import anything: the UI layer and the entry
/// point that wires everything together.
const Set<String> unrestricted = {'views', 'main.dart'};

/// Returned by [resolveTopLevel] for a URI that climbs out of `lib/`.
const String outsideLib = '<outside lib/>';

enum DirectiveKind { import, export, part, partOf }

class Directive {
  const Directive(this.kind, this.uris);

  final DirectiveKind kind;

  /// The URI strings, in source order. Conditional imports list every
  /// alternative; a `part of` naming a library (not a URI) has none.
  final List<String> uris;

  @override
  String toString() => '${kind.name} $uris';
}

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

/// Every `import`/`export`/`part`/`part of` directive in [source].
List<Directive> parseDirectives(String source) =>
    _DirectiveScanner(source).scan();

/// The URIs of every `import`/`export`/`part` directive in [source],
/// including the alternatives of conditional imports. `part of` is skipped.
List<String> directiveUris(String source) => [
  for (final d in parseDirectives(source))
    if (d.kind != DirectiveKind.partOf) ...d.uris,
];

/// Reads the directive section at the top of a Dart file.
class _DirectiveScanner {
  _DirectiveScanner(this._s);

  final String _s;
  int _i = 0;

  bool get _atEnd => _i >= _s.length;
  String _at(int offset) => _i + offset < _s.length ? _s[_i + offset] : '';

  List<Directive> scan() {
    final out = <Directive>[];
    if (_s.startsWith('\uFEFF')) _i = 1;
    if (_s.startsWith('#!', _i)) _skipLine();
    while (true) {
      _skipTrivia();
      if (_atEnd) break;
      if (_at(0) == '@') {
        _skipAnnotation();
        continue;
      }
      switch (_identifier()) {
        case 'library':
          _clause();
        case 'import':
          out.add(Directive(DirectiveKind.import, _clause()));
        case 'export':
          out.add(Directive(DirectiveKind.export, _clause()));
        case 'part':
          final save = _i;
          _skipTrivia();
          if (_identifier() == 'of') {
            out.add(Directive(DirectiveKind.partOf, _clause()));
          } else {
            _i = save;
            out.add(Directive(DirectiveKind.part, _clause()));
          }
        default:
          // The first declaration: no directive can follow it.
          return out;
      }
    }
    return out;
  }

  /// Consumes up to and including the next top-level `;`, returning the
  /// string literals outside parentheses — the URIs, not the `if (…)`
  /// conditions of a conditional import. Adjacent literals are one string.
  List<String> _clause() {
    final uris = <String>[];
    var afterString = false;
    while (true) {
      _skipTrivia();
      if (_atEnd) return uris;
      final c = _at(0);
      if (_atString) {
        final part = _string();
        if (afterString) {
          uris.last += part;
        } else {
          uris.add(part);
        }
        afterString = true;
        continue;
      }
      afterString = false;
      if (c == ';') {
        _i++;
        return uris;
      } else if (c == '(') {
        _skipBalanced('(', ')');
      } else if (_identifier() == null) {
        _i++; // `,`, `.`, `==` and the like.
      }
    }
  }

  /// Skips `@name`, `@prefix.Name<T>.named(...)` and the like.
  void _skipAnnotation() {
    _i++; // @
    while (true) {
      _skipTrivia();
      if (_identifier() == null) break;
      _skipTrivia();
      if (_at(0) == '<') {
        _skipBalanced('<', '>');
        _skipTrivia();
      }
      if (_at(0) != '.') break;
      _i++;
    }
    _skipTrivia();
    if (_at(0) == '(') _skipBalanced('(', ')');
  }

  void _skipBalanced(String open, String close) {
    var depth = 0;
    while (!_atEnd) {
      _skipTrivia();
      if (_atEnd) return;
      final c = _at(0);
      if (_atString) {
        _string();
        continue;
      }
      _i++;
      if (c == open) {
        depth++;
      } else if (c == close && --depth == 0) {
        return;
      }
    }
  }

  void _skipTrivia() {
    while (!_atEnd) {
      final c = _at(0);
      if (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
        _i++;
      } else if (c == '/' && _at(1) == '/') {
        _skipLine();
      } else if (c == '/' && _at(1) == '*') {
        _i += 2;
        var depth = 1; // Dart block comments nest.
        while (!_atEnd && depth > 0) {
          if (_at(0) == '/' && _at(1) == '*') {
            depth++;
            _i += 2;
          } else if (_at(0) == '*' && _at(1) == '/') {
            depth--;
            _i += 2;
          } else {
            _i++;
          }
        }
      } else {
        return;
      }
    }
  }

  void _skipLine() {
    while (!_atEnd && _at(0) != '\n' && _at(0) != '\r') {
      _i++;
    }
  }

  static final RegExp _identStart = RegExp(r'[A-Za-z_$]');
  static final RegExp _identPart = RegExp(r'[A-Za-z0-9_$]');

  String? _identifier() {
    if (_atEnd || !_identStart.hasMatch(_at(0)) || _atString) return null;
    final start = _i;
    while (!_atEnd && _identPart.hasMatch(_at(0))) {
      _i++;
    }
    return _s.substring(start, _i);
  }

  bool get _atString {
    final c = _at(0);
    if (c == "'" || c == '"') return true;
    final q = _at(1);
    return c == 'r' && (q == "'" || q == '"');
  }

  /// Reads a single, raw or triple-quoted string literal and returns its
  /// value with escapes decoded, so `'\x2e\x2e/views/a.dart'` is seen as
  /// `../views/a.dart`. `${…}` interpolations (legal in annotation arguments,
  /// never in a URI) are skipped, nested strings and all.
  String _string() {
    final raw = _at(0) == 'r';
    if (raw) _i++;
    final q = _at(0);
    final triple = _s.startsWith('$q$q$q', _i);
    final quote = triple ? '$q$q$q' : q;
    _i += quote.length;
    if (triple) _skipBlankFirstLine();
    final buf = StringBuffer();
    while (!_atEnd && !_s.startsWith(quote, _i)) {
      final c = _at(0);
      if (!triple && (c == '\n' || c == '\r')) {
        return buf.toString(); // Unterminated: stop at the line end.
      } else if (!raw && c == r'\') {
        _i++;
        buf.write(_escape());
      } else if (!raw && c == r'$' && _at(1) == '{') {
        _i++;
        _skipBalanced('{', '}');
      } else {
        buf.write(c);
        _i++;
      }
    }
    _i += quote.length;
    return buf.toString();
  }

  /// Dart ignores the first line of a triple-quoted string, terminator
  /// included, when it holds nothing but whitespace.
  void _skipBlankFirstLine() {
    var j = _i;
    while (j < _s.length && (_s[j] == ' ' || _s[j] == '\t')) {
      j++;
    }
    if (_s.startsWith('\r\n', j)) {
      _i = j + 2;
    } else if (j < _s.length && (_s[j] == '\n' || _s[j] == '\r')) {
      _i = j + 1;
    }
  }

  /// Decodes the escape sequence after a backslash.
  String _escape() {
    if (_atEnd) return '';
    final c = _at(0);
    _i++;
    switch (c) {
      case 'n':
        return '\n';
      case 'r':
        return '\r';
      case 't':
        return '\t';
      case 'b':
        return '\b';
      case 'f':
        return '\f';
      case 'v':
        return '\v';
      case 'x':
        return _hex(2) ?? 'x';
      case 'u':
        if (_at(0) == '{') {
          final end = _s.indexOf('}', _i);
          if (end < 0) return 'u';
          final code = _codePoint(_s.substring(_i + 1, end));
          if (code == null) return 'u';
          _i = end + 1;
          return code;
        }
        return _hex(4) ?? 'u';
      default:
        return c;
    }
  }

  String? _hex(int digits) {
    if (_i + digits > _s.length) return null;
    final code = _codePoint(_s.substring(_i, _i + digits));
    if (code == null) return null;
    _i += digits;
    return code;
  }

  static final RegExp _hexDigits = RegExp(r'^[0-9a-fA-F]{1,6}$');

  /// The character for a hex code point, or null if [hex] is not a valid one
  /// (`int.parse` alone would accept `-1` and `+1`).
  static String? _codePoint(String hex) {
    if (!_hexDigits.hasMatch(hex)) return null;
    final code = int.parse(hex, radix: 16);
    return code <= 0x10FFFF ? String.fromCharCode(code) : null;
  }
}

/// The top-level `lib/` entry (`widgets`, `app_info.dart`, …) that [uri],
/// written in the file at [file] (relative to `lib/`), refers to. Null for
/// `dart:` and other packages; [outsideLib] if it resolves outside `lib/`.
String? resolveTopLevel(String file, String uri) {
  final parsed = Uri.parse(uri); // Lowercases the scheme, as Dart does.
  final List<String> segments;
  if (parsed.scheme == 'package') {
    final prefix = '$packageName/';
    if (!parsed.path.startsWith(prefix)) return null;
    segments = Uri.parse(
      'file:///lib/${parsed.path.substring(prefix.length)}',
    ).pathSegments;
  } else if (parsed.hasScheme) {
    // dart: and other schemes are not ours; an absolute file: URI is never
    // a portable way into lib/.
    return parsed.scheme == 'file' ? outsideLib : null;
  } else {
    segments = Uri.parse('file:///lib/$file').resolve(uri).pathSegments;
  }
  if (segments.length < 2 || segments.first != 'lib') return outsideLib;
  return segments[1];
}

/// Files directly under `lib/` form one group; each directory is its own.
String _group(String entry) => entry.endsWith('.dart') ? '' : entry;

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
    final entry = file.split('/').first;
    final allowed = allowedImports[entry];
    final isFile = entry == file;
    if (allowed == null && !unrestricted.contains(entry)) {
      violations.add(
        Violation(
          file,
          null,
          "'${isFile ? entry : '$entry/'}' is not a known layer; add it to the "
          'ARCHITECTURE.md table and to tool/check_layers.dart',
        ),
      );
      continue;
    }
    final name = isFile ? entry : '$entry/';
    final List<Directive> directives;
    try {
      directives = parseDirectives(files[file]!.readAsStringSync());
    } on Object catch (e) {
      violations.add(Violation(file, null, 'could not read directives: $e'));
      continue;
    }
    for (final d in directives) {
      for (final uri in d.uris) {
        final String? target;
        try {
          target = resolveTopLevel(file, uri);
        } on FormatException catch (e) {
          violations.add(Violation(file, uri, 'not a valid URI: ${e.message}'));
          continue;
        }
        if (target == null) continue;
        if (d.kind == DirectiveKind.part || d.kind == DirectiveKind.partOf) {
          if (_group(target) != _group(entry)) {
            violations.add(
              Violation(
                file,
                uri,
                'a part and its library must both be in '
                '${isFile ? 'lib/' : name}',
              ),
            );
          }
        } else if (allowed != null && !allowed.contains(target)) {
          violations.add(
            Violation(file, uri, '$name may not depend on $target'),
          );
        }
      }
    }
  }
  return violations;
}

/// Runs the check on `args.first` (default `lib`) and returns the exit code:
/// 0 clean, 1 violations, 2 no such directory.
int run(List<String> args, {StringSink? out, StringSink? err}) {
  out ??= stdout;
  err ??= stderr;
  final lib = Directory(args.isNotEmpty ? args.first : 'lib');
  if (!lib.existsSync()) {
    err.writeln(
      'No ${lib.path}/ here; run from the repo root or pass the lib path.',
    );
    return 2;
  }
  final violations = checkLayers(lib);
  for (final v in violations) {
    out.writeln('VIOLATION $v');
  }
  out.writeln('violations: ${violations.length}');
  return violations.isEmpty ? 0 : 1;
}

void main(List<String> args) => exitCode = run(args);
