import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:dataset_training_tool/models/tag_group.dart';
import 'package:dataset_training_tool/services/agent/agent_tools.dart';
import 'package:dataset_training_tool/services/agent/tag_library_tools.dart';

/// An in-memory stand-in for AppState's library, with the same two rules that
/// matter here: the library is an ordered list, and group membership is
/// exclusive.
class _FakeLibrary {
  final List<String> tags = ['long_hair', 'boots', 'smile', 'bed', 'gloves'];
  final List<TagGroup> groups = [];
  int _nextId = 0;

  Future<void> add(List<String> incoming) async {
    for (final tag in incoming) {
      if (!tags.contains(tag)) tags.add(tag);
    }
  }

  Future<void> remove(List<String> doomed) async {
    tags.removeWhere(doomed.contains);
    for (var i = 0; i < groups.length; i++) {
      groups[i] = groups[i].copyWith(
        tags: groups[i].tags.where((t) => !doomed.contains(t)).toList(),
      );
    }
  }

  Future<TagGroup> create(String name, int color) async {
    final group = TagGroup(
      id: 'g${_nextId++}',
      name: name,
      color: color,
      tags: const [],
    );
    groups.add(group);
    return group;
  }

  Future<void> update(String id, {String? name, int? color}) async {
    for (var i = 0; i < groups.length; i++) {
      if (groups[i].id == id) {
        groups[i] = groups[i].copyWith(name: name, color: color);
      }
    }
  }

  Future<void> delete(String id) async {
    groups.removeWhere((g) => g.id == id);
  }

  /// Same contract as AppState.setTagGroupOrder: listed groups first, the
  /// rest keep their relative order behind them.
  Future<void> reorder(List<String> ids) async {
    final byId = {for (final g in groups) g.id: g};
    final head = [
      for (final id in ids)
        if (byId.containsKey(id)) byId[id]!,
    ];
    final seen = {for (final g in head) g.id};
    final rest = groups.where((g) => !seen.contains(g.id)).toList();
    groups
      ..clear()
      ..addAll([...head, ...rest]);
  }

  Future<void> move(List<String> moving, String? groupId) async {
    final library = tags.toSet();
    final wanted = moving.where(library.contains).toSet();
    for (var i = 0; i < groups.length; i++) {
      final kept = groups[i].tags.where((t) => !wanted.contains(t)).toList();
      if (groups[i].id == groupId) {
        kept.addAll(moving.where(wanted.contains));
      }
      groups[i] = groups[i].copyWith(tags: kept);
    }
  }

  TagGroup? named(String name) =>
      groups.where((g) => g.name == name).firstOrNull;

  List<String> get ungrouped {
    final grouped = {for (final g in groups) ...g.tags.toSet()};
    return tags.where((t) => !grouped.contains(t)).toList();
  }
}

void main() {
  late _FakeLibrary library;
  late ToolRegistry registry;

  Future<Map<String, dynamic>> call(
    String tool, [
    Map<String, dynamic> args = const {},
  ]) async {
    final result = await registry.dispatch(tool, jsonEncode(args));
    return jsonDecode(result.text) as Map<String, dynamic>;
  }

  setUp(() {
    library = _FakeLibrary();
    registry = ToolRegistry(
      buildTagLibraryTools(
        TagLibraryToolsDeps(
          libraryTags: () => library.tags,
          tagGroups: () => library.groups,
          addTags: library.add,
          removeTags: library.remove,
          createGroup: library.create,
          updateGroup: library.update,
          deleteGroup: library.delete,
          reorderGroups: library.reorder,
          moveTags: library.move,
        ),
      ),
    );
  });

  group('organize_tag_library', () {
    test('files a whole plan in one call, creating the groups', () async {
      final out = await call('organize_tag_library', {
        'assignments': [
          {
            'group': '身材外貌',
            'tags': ['long_hair', 'smile'],
          },
          {
            'group': '服装',
            'tags': ['boots', 'gloves'],
          },
        ],
      });
      expect(out['moved'], 4);
      expect(out['groups_created'], 2);
      expect(library.named('身材外貌')!.tags, ['long_hair', 'smile']);
      expect(library.named('服装')!.tags, ['boots', 'gloves']);
      expect(library.ungrouped, ['bed']);
    });

    test('reuses an existing group instead of cloning it', () async {
      await library.create('服装', 0xFF000000);
      final out = await call('organize_tag_library', {
        'assignments': [
          {
            // Case and padding differ; the user's group is still the target.
            'group': ' 服装 ',
            'tags': ['boots'],
          },
        ],
      });
      expect(out['groups_created'], 0);
      expect(library.groups.length, 1);
      expect(library.named('服装')!.tags, ['boots']);
    });

    test('a tag answered in another spelling still lands', () async {
      await call('organize_tag_library', {
        'assignments': [
          {
            'group': '身材外貌',
            'tags': ['long hair'],
          },
        ],
      });
      // Filed under the library's own spelling, not the model's.
      expect(library.named('身材外貌')!.tags, ['long_hair']);
    });

    test('tags outside the library are reported, never added', () async {
      final out = await call('organize_tag_library', {
        'assignments': [
          {
            'group': '服装',
            'tags': ['boots', 'invented_tag'],
          },
        ],
      });
      expect(out['not_in_library'], ['invented_tag']);
      expect(library.tags, isNot(contains('invented_tag')));
      expect(library.named('服装')!.tags, ['boots']);
    });

    test('a group whose every tag is unknown is not created', () async {
      final out = await call('organize_tag_library', {
        'assignments': [
          {
            'group': '幻想分组',
            'tags': ['nope'],
          },
        ],
      });
      expect(out['groups_created'], 0);
      expect(library.groups, isEmpty);
    });

    test('membership stays exclusive across a re-file', () async {
      await call('organize_tag_library', {
        'assignments': [
          {
            'group': 'A',
            'tags': ['boots'],
          },
        ],
      });
      await call('organize_tag_library', {
        'assignments': [
          {
            'group': 'B',
            'tags': ['boots'],
          },
        ],
      });
      expect(library.named('A')!.tags, isEmpty);
      expect(library.named('B')!.tags, ['boots']);
    });

    test('ungroup pulls tags back out', () async {
      await call('organize_tag_library', {
        'assignments': [
          {
            'group': '服装',
            'tags': ['boots', 'gloves'],
          },
        ],
      });
      final out = await call('organize_tag_library', {
        'ungroup': ['boots'],
      });
      expect(out['moved'], 1);
      expect(library.named('服装')!.tags, ['gloves']);
      expect(library.ungrouped, contains('boots'));
    });

    test('an empty call is rejected rather than reported as success', () async {
      final result = await registry.dispatch('organize_tag_library', '{}');
      expect(result.isError, isTrue);
    });

    test('an oversized batch is rejected with the limit', () async {
      final result = await registry.dispatch(
        'organize_tag_library',
        jsonEncode({
          'assignments': [
            for (var i = 0; i < maxAssignmentsPerCall + 1; i++)
              {
                'group': 'g$i',
                'tags': ['boots'],
              },
          ],
        }),
      );
      expect(result.isError, isTrue);
      expect(result.text, contains('$maxAssignmentsPerCall'));
    });
  });

  group('add_library_tags', () {
    test('adds what is new and leaves what is not', () async {
      final out = await call('add_library_tags', {
        'tags': ['thighhighs', 'boots'],
      });
      expect(out['added'], ['thighhighs']);
      expect(out['already_in_library'], ['boots']);
      expect(library.tags.last, 'thighhighs');
    });

    test('files the new tags into a group when one is named', () async {
      final out = await call('add_library_tags', {
        'tags': ['thighhighs'],
        'group': '服装',
      });
      expect(out['group'], '服装');
      expect(library.named('服装')!.tags, ['thighhighs']);
    });

    test('an existing tag is not re-filed by an add', () async {
      await call('organize_tag_library', {
        'assignments': [
          {
            'group': 'A',
            'tags': ['boots'],
          },
        ],
      });
      await call('add_library_tags', {
        'tags': ['boots'],
        'group': 'B',
      });
      expect(library.named('A')!.tags, ['boots']);
      expect(library.named('B'), isNull);
    });
  });

  test('only the destructive calls are gated', () {
    expect(registry.find('remove_library_tags')!.isWrite, isTrue);
    expect(registry.find('organize_tag_library')!.isWrite, isFalse);
    // manage_tag_groups is gated per action: deleting a group is the one
    // call in it with no undo, and a prompt on every rename would train the
    // user to click through the one that mattered.
    final groups = registry.find('manage_tag_groups')!;
    expect(groups.needsConfirmation('{"action":"delete"}'), isTrue);
    expect(groups.needsConfirmation('{"action":"update"}'), isFalse);
    expect(groups.needsConfirmation('{"action":"reorder"}'), isFalse);
    // Arguments nobody can read are not assumed harmless.
    expect(groups.needsConfirmation('{not json'), isTrue);
  });

  test(
    'remove_library_tags drops them from the library and its groups',
    () async {
      await call('organize_tag_library', {
        'assignments': [
          {
            'group': '服装',
            'tags': ['boots', 'gloves'],
          },
        ],
      });
      final out = await call('remove_library_tags', {
        'tags': ['boots'],
      });
      expect(out['removed'], ['boots']);
      expect(library.tags, isNot(contains('boots')));
      expect(library.named('服装')!.tags, ['gloves']);
    },
  );

  group('group edits', () {
    test('rename keeps the tags', () async {
      await call('organize_tag_library', {
        'assignments': [
          {
            'group': '服装',
            'tags': ['boots'],
          },
        ],
      });
      final out = await call('manage_tag_groups', {
        'action': 'update',
        'group': '服装',
        'new_name': '衣物',
      });
      expect(out['renamed_to'], '衣物');
      expect(library.named('衣物')!.tags, ['boots']);
    });

    test('renaming onto an existing name is refused', () async {
      await library.create('服装', 0);
      await library.create('背景', 0);
      final result = await registry.dispatch(
        'manage_tag_groups',
        jsonEncode({'group': '背景', 'new_name': '服装'}),
      );
      expect(result.isError, isTrue);
      expect(library.named('背景'), isNotNull);
    });

    test('a preset color name recolors the group', () async {
      await library.create('服装', kTagGroupPresetColors.first);
      final out = await call('manage_tag_groups', {
        'action': 'update',
        'group': '服装',
        'color': 'Orange',
      });
      expect(library.named('服装')!.color, kTagGroupColorNames['orange']);
      expect(out['color'], contains('orange'));
      // A color-only edit leaves the name alone.
      expect(out['renamed_to'], isNull);
    });

    test('hex works, and 6 digits stay opaque', () async {
      await library.create('服装', 0);
      await call('manage_tag_groups', {
        'action': 'update','group': '服装', 'color': '#123456'});
      expect(library.named('服装')!.color, 0xFF123456);
    });

    test('name and color change together in one call', () async {
      await library.create('服装', 0);
      await call('manage_tag_groups', {
        'action': 'update',
        'group': '服装',
        'new_name': '衣物',
        'color': 'mint',
      });
      expect(library.named('衣物')!.color, kTagGroupColorNames['mint']);
    });

    test('a color that is neither preset nor hex is refused', () async {
      await library.create('服装', 0xFF000001);
      final result = await registry.dispatch(
        'manage_tag_groups',
        jsonEncode({'group': '服装', 'color': 'chartreuse'}),
      );
      expect(result.isError, isTrue);
      expect(library.named('服装')!.color, 0xFF000001);
    });

    test('an edit that changes nothing is rejected', () async {
      await library.create('服装', 0);
      final result = await registry.dispatch(
        'manage_tag_groups',
        jsonEncode({'group': '服装'}),
      );
      expect(result.isError, isTrue);
    });

    test('deleting a group returns its tags to ungrouped', () async {
      await call('organize_tag_library', {
        'assignments': [
          {
            'group': '服装',
            'tags': ['boots'],
          },
        ],
      });
      final out = await call('manage_tag_groups', {
        'action': 'delete','group': '服装'});
      expect(out['tags_returned_to_ungrouped'], 1);
      expect(library.groups, isEmpty);
      expect(library.tags, contains('boots'));
      expect(library.ungrouped, contains('boots'));
    });

    test('an unknown group name comes back as an error, not a crash', () async {
      final result = await registry.dispatch(
        'manage_tag_groups',
        jsonEncode({'group': 'nope'}),
      );
      expect(result.isError, isTrue);
    });
  });

  group('manage_tag_groups reorder', () {
    setUp(() async {
      for (final name in ['服装', '背景', '身材外貌']) {
        await library.create(name, 0);
      }
    });

    List<String> order() => [for (final g in library.groups) g.name];

    test('a full order is applied as given', () async {
      final out = await call('manage_tag_groups', {
        'action': 'reorder',
        'order': ['身材外貌', '服装', '背景'],
      });
      expect(order(), ['身材外貌', '服装', '背景']);
      expect(out['order'], ['身材外貌', '服装', '背景']);
    });

    test('a partial order lifts the named groups to the top', () async {
      await call('manage_tag_groups', {
        'action': 'reorder',
        'order': ['身材外貌'],
      });
      expect(order(), ['身材外貌', '服装', '背景']);
    });

    test('unknown names are reported, and the rest still moves', () async {
      final out = await call('manage_tag_groups', {
        'action': 'reorder',
        'order': ['背景', '幻想分组'],
      });
      expect(out['no_such_group'], ['幻想分组']);
      expect(order(), ['背景', '服装', '身材外貌']);
    });

    test('a name listed twice is reported, not applied twice', () async {
      final out = await call('manage_tag_groups', {
        'action': 'reorder',
        'order': ['背景', '服装', '背景'],
      });
      expect(out['listed_twice'], ['背景']);
      expect(order(), ['背景', '服装', '身材外貌']);
    });

    test('tags and membership survive a reorder', () async {
      await call('organize_tag_library', {
        'assignments': [
          {
            'group': '服装',
            'tags': ['boots'],
          },
        ],
      });
      await call('manage_tag_groups', {
        'action': 'reorder',
        'order': ['背景', '服装'],
      });
      expect(library.named('服装')!.tags, ['boots']);
      expect(library.ungrouped, isNot(contains('boots')));
    });

    test('an order naming no existing group is an error', () async {
      final result = await registry.dispatch(
        'manage_tag_groups',
        jsonEncode({
          'order': ['nope'],
        }),
      );
      expect(result.isError, isTrue);
      expect(order(), ['服装', '背景', '身材外貌']);
    });
  });
}
