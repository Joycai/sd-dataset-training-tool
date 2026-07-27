import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:dataset_training_tool/models/tag_group.dart';
import 'package:dataset_training_tool/services/agent/agent_tools.dart';
import 'package:dataset_training_tool/services/agent/dataset_tools.dart';
import 'package:dataset_training_tool/state/dataset_state.dart';

// 1x1 transparent PNG.
const _pngBytes = [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x62, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
];

void main() {
  late Directory tempDir;
  late DatasetState dataset;
  late ToolRegistry registry;

  Future<Map<String, dynamic>> call(
    String tool, [
    Map<String, dynamic> args = const {},
  ]) async {
    final result = await registry.dispatch(tool, jsonEncode(args));
    return jsonDecode(result.text) as Map<String, dynamic>;
  }

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('dataset_tools_test_');
    for (final name in ['001', '002', '003']) {
      await File(p.join(tempDir.path, '$name.png')).writeAsBytes(_pngBytes);
    }
    await File(
      p.join(tempDir.path, '001.txt'),
    ).writeAsString('1girl, solo, long hair');
    await File(p.join(tempDir.path, '002.txt')).writeAsString('1girl, smile');
    // 003 stays uncaptioned.

    dataset = DatasetState();
    await dataset.scan(
      directoryPath: tempDir.path,
      recursive: false,
      captionExtension: '.txt',
    );
    registry = ToolRegistry(
      buildReadOnlyTools(
        DatasetToolsDeps(
          dataset: dataset,
          rootDir: () => tempDir.path,
          libraryTags: () => ['1girl', 'solo', 'standing'],
          tagGroups: () => [
            const TagGroup(
              id: 'g1',
              name: 'subject',
              color: 0,
              tags: ['1girl', 'solo'],
            ),
          ],
        ),
      ),
    );
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  group('dispatch robustness', () {
    test('unknown tool returns error result, not an exception', () async {
      final result = await registry.dispatch('nope', '{}');
      expect(result.isError, isTrue);
      expect(result.text, contains('unknown tool'));
    });

    test('malformed JSON arguments return error result', () async {
      final result = await registry.dispatch('get_tag_stats', '{not json');
      expect(result.isError, isTrue);
      expect(result.text, contains('invalid JSON'));
    });

    test('argument validation errors are reported to the model', () async {
      final result = await registry.dispatch('search_tags', '{}');
      expect(result.isError, isTrue);
      expect(result.text, contains('query'));
    });
  });

  group('read-only tools', () {
    test('get_dataset_overview reports counts', () async {
      final out = await call('get_dataset_overview');
      expect(out['total_images'], 3);
      expect(out['captioned'], 2);
      expect(out['uncaptioned'], 1);
      expect(out['caption_extension'], '.txt');
    });

    test('get_tag_stats returns [tag, count] pairs sorted by count', () async {
      final out = await call('get_tag_stats');
      expect(out['total_unique'], 4);
      expect((out['tags'] as List).first, ['1girl', 2]);
      expect(out['truncated'], isFalse);
    });

    test('get_tag_stats paginates and flags truncation', () async {
      final out = await call('get_tag_stats', {'limit': 2, 'offset': 0});
      expect((out['tags'] as List).length, 2);
      expect(out['truncated'], isTrue);
    });

    test('search_tags matches case-insensitively', () async {
      final out = await call('search_tags', {'query': 'HAIR'});
      expect((out['tags'] as List).single, ['long hair', 1]);
    });

    test('list_images filters by include/exclude/untagged', () async {
      final withSolo = await call('list_images', {
        'include_tags': ['1girl', 'solo'],
      });
      expect(withSolo['total_matches'], 1);

      final withoutSmile = await call('list_images', {
        'include_tags': ['1girl'],
        'exclude_tags': ['smile'],
      });
      expect(withoutSmile['total_matches'], 1);

      final untagged = await call('list_images', {'untagged_only': true});
      expect(untagged['total_matches'], 1);
      expect(((untagged['images'] as List).single as Map)['path'], '003.png');
    });

    test('read_captions resolves relative paths and flags misses', () async {
      final out = await call('read_captions', {
        'paths': ['001.png', 'missing.png'],
      });
      final captions = out['captions'] as List;
      expect((captions[0] as Map)['tags'], ['1girl', 'solo', 'long hair']);
      expect((captions[1] as Map)['error'], isNotNull);
    });

    test('get_tag_library returns groups and ungrouped remainder', () async {
      final out = await call('get_tag_library');
      expect(((out['groups'] as List).single as Map)['tags'], [
        '1girl',
        'solo',
      ]);
      expect(out['ungrouped'], ['standing']);
    });
  });

  group('resolveDatasetPath', () {
    test('rejects traversal outside the root', () {
      expect(resolveDatasetPath(tempDir.path, '../etc/passwd'), isNull);
      expect(
        resolveDatasetPath(tempDir.path, p.join('..', 'other', 'x.png')),
        isNull,
      );
    });

    test('accepts plain relative and in-root absolute paths', () {
      expect(resolveDatasetPath(tempDir.path, '001.png'), isNotNull);
      expect(
        resolveDatasetPath(tempDir.path, p.join(tempDir.path, '001.png')),
        isNotNull,
      );
    });
  });
}
