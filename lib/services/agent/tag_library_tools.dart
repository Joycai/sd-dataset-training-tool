/// The assistant's tag-library tools: file tags into groups, add and remove
/// library entries, rename and delete groups.
///
/// The library is the user's curated standard tag set — the thing the tag
/// panel shows and every caption gets normalized against. Until these tools
/// existed the assistant could *read* it (`get_tag_library`) and nothing else,
/// so "help me tidy my tag library" ended in a list of proposals the user had
/// to drag into place by hand, one chip at a time.
///
/// No tool here touches a caption file: the library is a settings list, and
/// moving a tag between groups changes nothing on disk. That is also why the
/// additive ones are not behind the write-confirmation gate — filing a hundred
/// tags is unusable if every batch needs a click, and a wrong home for a tag
/// is one drag to fix. The two that destroy something the user typed
/// ([removeLibraryTags], [deleteTagGroup]) are gated, because no undo covers
/// them.
library;

import '../../models/tag_group.dart';
import '../../utils/tag_text.dart';
import 'agent_tools.dart';

class TagLibraryToolsDeps {
  const TagLibraryToolsDeps({
    required this.libraryTags,
    required this.tagGroups,
    required this.addTags,
    required this.removeTags,
    required this.createGroup,
    required this.renameGroup,
    required this.deleteGroup,
    required this.moveTags,
  });

  final List<String> Function() libraryTags;
  final List<TagGroup> Function() tagGroups;

  /// Appends tags that are not in the library yet, in caller order.
  final Future<void> Function(List<String> tags) addTags;

  final Future<void> Function(List<String> tags) removeTags;

  /// Creates an empty group and returns it.
  final Future<TagGroup> Function(String name, int color) createGroup;

  final Future<void> Function(String id, String name) renameGroup;

  /// Deletes the group; its tags fall back to ungrouped.
  final Future<void> Function(String id) deleteGroup;

  /// Moves library tags into [groupId] (null = ungrouped). Membership is
  /// exclusive, so this also removes them from wherever they were.
  final Future<void> Function(List<String> tags, String? groupId) moveTags;
}

/// Most tags one call may touch.
///
/// Generous for the same reason `write_tag_translations` is: a tool that files
/// one tag per call turns a two-hundred-tag library into two hundred round
/// trips, and the run dies of context exhaustion long before it finishes.
const int maxLibraryTagsPerCall = 300;

/// Most groups one `organize_tag_library` call may address.
const int maxAssignmentsPerCall = 40;

List<AgentTool> buildTagLibraryTools(TagLibraryToolsDeps deps) {
  /// Finds a group by the name the model used: exact first, then folded, so
  /// "服装 " and "Clothing"/"clothing" reach the group that already exists
  /// instead of creating a near-duplicate beside it.
  TagGroup? findGroup(String name) {
    final groups = deps.tagGroups();
    final exact = groups.where((g) => g.name == name).firstOrNull;
    if (exact != null) return exact;
    final folded = name.trim().toLowerCase();
    return groups
        .where((g) => g.name.trim().toLowerCase() == folded)
        .firstOrNull;
  }

  /// Resolves the model's spellings to the library's own.
  ///
  /// Models answer `long hair` for a library holding `long_hair` constantly;
  /// dropping those would make the tool look broken while being "correct".
  /// Tags the library does not hold at all come back separately — they are
  /// never added silently, because a typo would otherwise enter the library
  /// through a filing call.
  ({List<String> known, List<String> unknown}) resolve(List<String> asked) {
    final byKey = {
      for (final tag in deps.libraryTags()) tagLookupKey(tag): tag,
    };
    final seen = <String>{};
    final known = <String>[];
    final unknown = <String>[];
    for (final raw in asked) {
      final tag = byKey[tagLookupKey(raw)];
      if (tag == null) {
        unknown.add(raw);
      } else if (seen.add(tag)) {
        known.add(tag);
      }
    }
    return (known: known, unknown: unknown);
  }

  Future<TagGroup> groupNamed(String name) async {
    final existing = findGroup(name);
    if (existing != null) return existing;
    // Cycle the presets so a batch of new groups is visually separable
    // without asking anyone to pick eight colors.
    return deps.createGroup(
      name,
      kTagGroupPresetColors[deps.tagGroups().length %
          kTagGroupPresetColors.length],
    );
  }

  /// The library as the model should see it after a change: counts plus the
  /// names, so it can decide whether it is done without a second read.
  Map<String, Object?> librarySummary() {
    final groups = deps.tagGroups();
    final grouped = {for (final g in groups) ...g.tags.toSet()};
    return {
      'library_total': deps.libraryTags().length,
      'ungrouped_total': deps
          .libraryTags()
          .where((t) => !grouped.contains(t))
          .length,
      'groups': [
        for (final g in groups) {'name': g.name, 'tags': g.tags.length},
      ],
    };
  }

  return [
    AgentTool(
      spec: const AgentToolSpec(
        name: 'organize_tag_library',
        description:
            'File library tags into groups. This is the tool for tidying '
            'the tag library: send the whole plan in ONE call — every '
            'group with the tags that belong in it — instead of one call '
            'per tag or per group.\n'
            'Groups named here that do not exist yet are created (with an '
            'automatic color). Group membership is exclusive, so a tag '
            'named under one group leaves whichever group it was in. Tags '
            'not in the library are reported back untouched, never added: '
            'use add_library_tags for those.\n'
            'Changes nothing on disk — the library is the user\'s own tag '
            'list, not the dataset\'s captions.',
        parametersSchema: {
          'type': 'object',
          'properties': {
            'assignments': {
              'type': 'array',
              'description':
                  'Up to $maxAssignmentsPerCall groups, each with its tags. '
                  'Reuse the user\'s existing group names wherever the tag '
                  'plausibly fits; invent a group only when several tags '
                  'need it, and name it in the language the existing groups '
                  'use.',
              'items': {
                'type': 'object',
                'properties': {
                  'group': {'type': 'string'},
                  'tags': {
                    'type': 'array',
                    'items': {'type': 'string'},
                  },
                },
                'required': ['group', 'tags'],
              },
            },
            'ungroup': {
              'type': 'array',
              'items': {'type': 'string'},
              'description':
                  'Tags to pull out of their group and back into the '
                  'ungrouped bucket.',
            },
          },
        },
      ),
      handler: (args) async {
        final raw = args['assignments'];
        final ungroup = optStringList(args, 'ungroup');
        if (raw != null && raw is! List) {
          throw ToolArgError('"assignments" must be an array of objects');
        }
        final assignments = (raw as List?) ?? const [];
        if (assignments.isEmpty && ungroup.isEmpty) {
          throw ToolArgError(
            'nothing to do: pass "assignments", "ungroup", or both',
          );
        }
        if (assignments.length > maxAssignmentsPerCall) {
          throw ToolArgError(
            '"assignments" accepts at most $maxAssignmentsPerCall groups per '
            'call; got ${assignments.length}. Split the batch.',
          );
        }

        final results = <Map<String, Object?>>[];
        final unknown = <String>[];
        var moved = 0;
        var created = 0;

        for (final element in assignments) {
          if (element is! Map) {
            throw ToolArgError('each assignment must be an object');
          }
          final name = '${element['group'] ?? ''}'.trim();
          if (name.isEmpty) {
            throw ToolArgError('each assignment needs a non-empty "group"');
          }
          final tags = element['tags'];
          if (tags is! List) {
            throw ToolArgError('assignment "$name" needs a "tags" array');
          }
          final asked = [
            for (final t in tags)
              if (t is String && t.trim().isNotEmpty) t.trim(),
          ];
          if (asked.length > maxLibraryTagsPerCall) {
            throw ToolArgError(
              'assignment "$name" carries ${asked.length} tags; at most '
              '$maxLibraryTagsPerCall per group per call.',
            );
          }
          final resolved = resolve(asked);
          unknown.addAll(resolved.unknown);
          final isNew = findGroup(name) == null;
          if (resolved.known.isEmpty) {
            // A group whose every tag was unknown is not worth creating —
            // it would land empty and read as a successful filing.
            results.add({'group': name, 'moved': 0, 'created': false});
            continue;
          }
          final group = await groupNamed(name);
          if (isNew) created++;
          await deps.moveTags(resolved.known, group.id);
          moved += resolved.known.length;
          results.add({
            'group': group.name,
            'moved': resolved.known.length,
            'created': isNew,
          });
        }

        if (ungroup.isNotEmpty) {
          final resolved = resolve(ungroup);
          unknown.addAll(resolved.unknown);
          if (resolved.known.isNotEmpty) {
            await deps.moveTags(resolved.known, null);
            moved += resolved.known.length;
          }
          results.add({
            'group': null,
            'moved': resolved.known.length,
            'created': false,
          });
        }

        return toolOk({
          'moved': moved,
          'groups_created': created,
          'assignments': results,
          if (unknown.isNotEmpty) ...{
            'not_in_library': unknown,
            'hint':
                'these tags are not in the library, so nothing was filed for '
                'them; add them with add_library_tags first if they belong '
                'there',
          },
          'library': librarySummary(),
        });
      },
    ),

    AgentTool(
      spec: const AgentToolSpec(
        name: 'add_library_tags',
        description:
            'Add tags to the user\'s tag library, optionally straight into '
            'a group (created if it does not exist). Tags already in the '
            'library are left where they are — this never re-files them.\n'
            'The library is a curated standard set, not a dump of every tag '
            'the dataset happens to contain: add tags the user will reuse, '
            'and say which you added.',
        parametersSchema: {
          'type': 'object',
          'properties': {
            'tags': {
              'type': 'array',
              'items': {'type': 'string'},
              'description':
                  'Up to $maxLibraryTagsPerCall tags, in the spelling they '
                  'should have in the library.',
            },
            'group': {
              'type': 'string',
              'description':
                  'Optional group for the newly added tags. Omit to leave '
                  'them ungrouped.',
            },
          },
          'required': ['tags'],
        },
      ),
      handler: (args) async {
        final asked = requireStringList(
          args,
          'tags',
          maxLength: maxLibraryTagsPerCall,
        );
        final existing = {
          for (final tag in deps.libraryTags()) tagLookupKey(tag): tag,
        };
        final seen = <String>{};
        final fresh = <String>[];
        final already = <String>[];
        for (final tag in asked) {
          final key = tagLookupKey(tag);
          if (!seen.add(key)) continue;
          if (existing.containsKey(key)) {
            already.add(existing[key]!);
          } else {
            fresh.add(tag);
          }
        }
        if (fresh.isNotEmpty) await deps.addTags(fresh);

        final name = optString(args, 'group');
        String? intoGroup;
        if (name != null && fresh.isNotEmpty) {
          final group = await groupNamed(name);
          await deps.moveTags(fresh, group.id);
          intoGroup = group.name;
        }
        return toolOk({
          'added': fresh,
          'already_in_library': already,
          'group': ?intoGroup,
          'library': librarySummary(),
        });
      },
    ),

    AgentTool(
      isWrite: true,
      spec: const AgentToolSpec(
        name: 'remove_library_tags',
        description:
            'Remove tags from the user\'s tag library. Captions are not '
            'touched — the images keep these tags; they just stop being '
            'part of the user\'s standard set.\n'
            'There is no undo for this. Only remove tags the user has '
            'explicitly agreed to remove.',
        parametersSchema: {
          'type': 'object',
          'properties': {
            'tags': {
              'type': 'array',
              'items': {'type': 'string'},
            },
          },
          'required': ['tags'],
        },
      ),
      handler: (args) async {
        final asked = requireStringList(
          args,
          'tags',
          maxLength: maxLibraryTagsPerCall,
        );
        final resolved = resolve(asked);
        if (resolved.known.isNotEmpty) await deps.removeTags(resolved.known);
        return toolOk({
          'removed': resolved.known,
          if (resolved.unknown.isNotEmpty) 'not_in_library': resolved.unknown,
          'library': librarySummary(),
        });
      },
    ),

    AgentTool(
      spec: const AgentToolSpec(
        name: 'rename_tag_group',
        description:
            'Rename a group in the tag library. Its tags and color stay as '
            'they are.',
        parametersSchema: {
          'type': 'object',
          'properties': {
            'group': {'type': 'string', 'description': 'Current name.'},
            'new_name': {'type': 'string'},
          },
          'required': ['group', 'new_name'],
        },
      ),
      handler: (args) async {
        final name = requireString(args, 'group');
        final next = requireString(args, 'new_name');
        final group = findGroup(name);
        if (group == null) {
          return toolError(
            'no group named "$name"; existing groups: '
            '${deps.tagGroups().map((g) => g.name).join(', ')}',
          );
        }
        final clash = findGroup(next);
        if (clash != null && clash.id != group.id) {
          return toolError(
            'a group named "${clash.name}" already exists; move the tags '
            'into it with organize_tag_library instead of renaming',
          );
        }
        await deps.renameGroup(group.id, next);
        return toolOk({
          'renamed': group.name,
          'to': next,
          'tags': group.tags.length,
        });
      },
    ),

    AgentTool(
      isWrite: true,
      spec: const AgentToolSpec(
        name: 'delete_tag_group',
        description:
            'Delete a group from the tag library. Its tags are kept — they '
            'fall back to the ungrouped bucket. Only the grouping is lost, '
            'and there is no undo for it.',
        parametersSchema: {
          'type': 'object',
          'properties': {
            'group': {'type': 'string'},
          },
          'required': ['group'],
        },
      ),
      handler: (args) async {
        final name = requireString(args, 'group');
        final group = findGroup(name);
        if (group == null) {
          return toolError(
            'no group named "$name"; existing groups: '
            '${deps.tagGroups().map((g) => g.name).join(', ')}',
          );
        }
        await deps.deleteGroup(group.id);
        return toolOk({
          'deleted': group.name,
          'tags_returned_to_ungrouped': group.tags.length,
          'library': librarySummary(),
        });
      },
    ),
  ];
}
