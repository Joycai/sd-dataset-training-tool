import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/check_layers.dart';

void main() {
  group('directiveUris', () {
    test('collects import, export and part; skips part of', () {
      const source = '''
library;

import 'dart:io';
import "../models/a.dart" as a show A;
export '../models/b.dart' hide B;
part 'c.part.dart';
part of '../x.dart';
/// import '../views/doc_comment.dart';
''';
      expect(directiveUris(source), [
        'dart:io',
        '../models/a.dart',
        '../models/b.dart',
        'c.part.dart',
      ]);
    });

    test('includes conditional-import alternatives, not conditions', () {
      const source = '''
import 'stub.dart'
    if (dart.library.io) 'io.dart'
    if (dart.library.js_interop == 'true') '../views/web.dart';
''';
      expect(directiveUris(source), [
        'stub.dart',
        'io.dart',
        '../views/web.dart',
      ]);
    });

    test('reads raw strings, inline comments and unspaced directives', () {
      // All valid Dart that `dart format` leaves alone (or only reflows), so
      // a line-based pattern would let them through.
      const source = '''
import r'../views/raw.dart';
import /* why */ '../views/commented.dart';
import'../views/unspaced.dart';
import 'a.dart'; import '../views/same_line.dart';
@Deprecated('x') import '../views/annotated.dart';
''';
      expect(directiveUris(source), [
        '../views/raw.dart',
        '../views/commented.dart',
        '../views/unspaced.dart',
        'a.dart',
        '../views/same_line.dart',
        '../views/annotated.dart',
      ]);
    });

    test('ignores block comments and stops at the first declaration', () {
      const source = """
/* An old import, commented out:
import '../views/old.dart';
   /* nested */ still a comment */
import 'kept.dart';

const prompt = '''
import '../views/in_a_string.dart';
''';
""";
      expect(directiveUris(source), ['kept.dart']);
    });

    test('decodes escapes and joins adjacent string literals', () {
      const source = r'''
import '\x2e\x2e/views/hex.dart';
import '../views/unicode.dart';
import '..\u{2F}views/braced.dart';
import '../vi' 'ews/adjacent.dart';
''';
      expect(directiveUris(source), [
        '../views/hex.dart',
        '../views/unicode.dart',
        '../views/braced.dart',
        '../views/adjacent.dart',
      ]);
    });

    test('annotations of any shape do not end the directive section', () {
      const source = r'''
@Ann<int>.named()
import 'generic.dart';
@Deprecated('x${"'"}')
import 'interpolated.dart';
@prefix.Ann(['a', ('b')])
import 'nested.dart';
''';
      expect(directiveUris(source), [
        'generic.dart',
        'interpolated.dart',
        'nested.dart',
      ]);
    });

    test('a bare carriage return ends a line comment', () {
      expect(directiveUris("// note\rimport 'a.dart';"), ['a.dart']);
    });
  });

  group('parseDirectives', () {
    test('part of takes a URI or a library name', () {
      expect(parseDirectives("part of '../x.dart';").single.uris, [
        '../x.dart',
      ]);
      final named = parseDirectives('part of foo.bar;').single;
      expect(named.kind, DirectiveKind.partOf);
      expect(named.uris, isEmpty);
    });
  });

  group('resolveTopLevel', () {
    test('relative URIs resolve against the importing file', () {
      expect(resolveTopLevel('widgets/a.dart', 'b.dart'), 'widgets');
      expect(resolveTopLevel('widgets/a.dart', '../views/v.dart'), 'views');
      expect(
        resolveTopLevel('services/llm/c.dart', '../../app_info.dart'),
        'app_info.dart',
      );
      expect(
        resolveTopLevel('widgets/a.dart', '../../test/t.dart'),
        outsideLib,
      );
    });

    test('own package URIs map into lib/, other schemes are ignored', () {
      expect(
        resolveTopLevel('widgets/a.dart', 'package:$packageName/views/v.dart'),
        'views',
      );
      expect(
        resolveTopLevel('widgets/a.dart', 'package:flutter/w.dart'),
        isNull,
      );
      expect(resolveTopLevel('widgets/a.dart', 'dart:io'), isNull);
      expect(
        resolveTopLevel('widgets/a.dart', 'file:///repo/lib/views/v.dart'),
        outsideLib,
      );
    });
  });

  group('checkLayers', () {
    late Directory lib;

    setUp(() => lib = Directory.systemTemp.createTempSync('check_layers_'));
    tearDown(() => lib.deleteSync(recursive: true));

    void write(String path, String source) => File('${lib.path}/$path')
      ..createSync(recursive: true)
      ..writeAsStringSync(source);

    List<String> found() => [
      for (final v in checkLayers(lib)) '${v.file} ${v.uri}',
    ];

    test('passes allowed imports and unrestricted entries', () {
      write('main.dart', "import 'views/v.dart';");
      write('views/v.dart', "import '../widgets/w.dart';");
      write('widgets/w.dart', "import '../state/s.dart';");
      write('state/s.dart', "import '../agent/a.dart';");
      write('agent/a.dart', "import '../state/s.dart';");
      write('l10n/app_localizations.dart', """
import 'package:flutter/widgets.dart';
import 'app_localizations_en.dart';
""");
      write('app_info.dart', '');
      expect(checkLayers(lib), isEmpty);
    });

    test('reports reverse dependencies in any directive form', () {
      write('widgets/w.dart', '''
import '../views/v.dart';
export '../views/v.dart';
import 'package:$packageName/views/v.dart';
import r'../views/v.dart';
''');
      write('models/m.dart', "import '../utils/u.dart';");
      expect(found(), [
        'models/m.dart ../utils/u.dart',
        'widgets/w.dart ../views/v.dart',
        'widgets/w.dart ../views/v.dart',
        'widgets/w.dart package:$packageName/views/v.dart',
        'widgets/w.dart ../views/v.dart',
      ]);
    });

    test('reports the forbidden cells that are easy to get wrong', () {
      write('widgets/w.dart', "import '../agent/a.dart';");
      write('agent/a.dart', "import '../theme/t.dart';");
      write('services/s.dart', '''
import '../state/s.dart';
import '../l10n/app_localizations.dart';
''');
      expect(checkLayers(lib).map((v) => v.message), [
        'agent/ may not depend on theme',
        'services/ may not depend on state',
        'services/ may not depend on l10n',
        'widgets/ may not depend on agent',
      ]);
    });

    test('l10n/ and app_info.dart are leaves', () {
      write('l10n/extra.dart', "import '../views/v.dart';");
      write('app_info.dart', "import 'models/m.dart';");
      expect(found(), [
        'app_info.dart models/m.dart',
        'l10n/extra.dart ../views/v.dart',
      ]);
    });

    test('conditional alternatives and URIs outside lib/ are checked', () {
      write('widgets/w.dart', '''
import 'stub.dart' if (dart.library.io) '../views/io.dart';
import '../../test/helpers.dart';
''');
      expect(checkLayers(lib).map((v) => v.message), [
        'widgets/ may not depend on views',
        'widgets/ may not depend on $outsideLib',
      ]);
    });

    test('a part must stay in its own top-level entry', () {
      // views/ may import anything, but a part in widgets/ would still run
      // inside the views library; both halves are reported.
      write('views/v.dart', "part '../widgets/p.dart';");
      write('widgets/p.dart', "part of '../views/v.dart';");
      write('state/s.dart', "part 'gen/s.g.dart';");
      write('state/gen/s.g.dart', "part of '../s.dart';");
      expect(found(), [
        'views/v.dart ../widgets/p.dart',
        'widgets/p.dart ../views/v.dart',
      ]);
    });

    test('reports entries missing from the layer table', () {
      write('core/c.dart', '');
      write('extra.dart', '');
      expect(checkLayers(lib).map((v) => v.file), [
        'core/c.dart',
        'extra.dart',
      ]);
    });
  });

  group('run', () {
    late Directory lib;

    setUp(() => lib = Directory.systemTemp.createTempSync('check_layers_'));
    tearDown(() => lib.deleteSync(recursive: true));

    test('exits 0 when clean, 1 on violations, 2 without lib/', () {
      final out = StringBuffer();
      final err = StringBuffer();
      expect(run([lib.path], out: out, err: err), 0);
      expect(out.toString(), contains('violations: 0'));

      File('${lib.path}/models/m.dart')
        ..createSync(recursive: true)
        ..writeAsStringSync("import '../views/v.dart';");
      out.clear();
      expect(run([lib.path], out: out, err: err), 1);
      expect(out.toString(), contains('VIOLATION lib/models/m.dart'));

      expect(run(['${lib.path}/missing'], out: out, err: err), 2);
      expect(err.toString(), contains('missing'));
    });
  });

  test('the rules match the table in docs/ARCHITECTURE.md', () {
    // Each table row: | `dir/`, `dir/` | holds | `allowed/`, ... |
    final rows = File('docs/ARCHITECTURE.md')
        .readAsLinesSync()
        .skipWhile((l) => !l.startsWith('| Directory |'))
        .skip(2)
        .takeWhile((l) => l.startsWith('|'));
    final ticked = RegExp('`([^`]+)`');
    List<String> entries(String cell) => [
      for (final m in ticked.allMatches(cell))
        m.group(1)!.replaceAll(RegExp(r'/$'), ''),
    ];

    final documented = <String>{};
    for (final row in rows) {
      final cells = row.split('|');
      final mayImport = cells[3];
      for (final entry in entries(cells[1])) {
        documented.add(entry);
        if (mayImport.contains('everything')) {
          expect(unrestricted, contains(entry), reason: row);
        } else {
          expect(allowedImports[entry], {
            entry,
            ...entries(mayImport),
          }, reason: row);
        }
      }
    }
    expect(documented, {...allowedImports.keys, ...unrestricted});
  });
}
