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
    if (dart.library.js_interop) '../views/web.dart';
''';
      expect(directiveUris(source), [
        'stub.dart',
        'io.dart',
        '../views/web.dart',
      ]);
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
    });
  });

  group('checkLayers', () {
    late Directory lib;

    setUp(() => lib = Directory.systemTemp.createTempSync('check_layers_'));
    tearDown(() => lib.deleteSync(recursive: true));

    void write(String path, String source) => File('${lib.path}/$path')
      ..createSync(recursive: true)
      ..writeAsStringSync(source);

    test('passes allowed imports and unrestricted directories', () {
      write('main.dart', "import 'views/v.dart';");
      write('views/v.dart', "import '../widgets/w.dart';");
      write('widgets/w.dart', "import '../state/s.dart';");
      write('state/s.dart', "import '../agent/a.dart';");
      write('agent/a.dart', "import '../state/s.dart';");
      expect(checkLayers(lib), isEmpty);
    });

    test('reports reverse dependencies in any directive form', () {
      write('widgets/w.dart', '''
import '../views/v.dart';
export '../views/v.dart';
import 'package:$packageName/views/v.dart';
''');
      write('models/m.dart', "import '../utils/u.dart';");
      final violations = checkLayers(lib);
      expect(violations.map((v) => '${v.file} ${v.uri}'), [
        'models/m.dart ../utils/u.dart',
        'widgets/w.dart ../views/v.dart',
        'widgets/w.dart ../views/v.dart',
        'widgets/w.dart package:$packageName/views/v.dart',
      ]);
    });

    test('reports files in a directory missing from the layer table', () {
      write('core/c.dart', '');
      expect(checkLayers(lib).single.file, 'core/c.dart');
    });
  });
}
