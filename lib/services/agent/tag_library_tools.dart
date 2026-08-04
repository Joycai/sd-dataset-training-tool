/// The assistant's tag-library tools: file tags into groups, add and remove
/// library entries, edit (rename / recolor), reorder and delete groups.
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
    required this.updateGroup,
    required this.deleteGroup,
    required this.reorderGroups,
    required this.moveTags,
  });

  final List<String> Function() libraryTags;
  final List<TagGroup> Function() tagGroups;

  /// Appends tags that are not in the library yet, in caller order.
  final Future<void> Function(List<String> tags) addTags;

  final Future<void> Function(List<String> tags) removeTags;

  /// Creates an empty group and returns it.
  final Future<TagGroup> Function(String name, int color) createGroup;

  /// Changes the group's name and/or its color (ARGB).
  final Future<void> Function(String id, {String? name, int? color})
  updateGroup;

  /// Deletes the group; its tags fall back to ungrouped.
  final Future<void> Function(String id) deleteGroup;

  /// Puts the groups named by [ids] at the front, in that order; everything
  /// else keeps its relative order behind them.
  final Future<void> Function(List<String> ids) reorderGroups;

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

/// Names for [kTagGroupPresetColors], in the same order.
///
/// The picker in the panel shows swatches; a model cannot point at one, and
/// asking it for ARGB integers invites `0x6A9BDD` (transparent) or a color
/// nobody would have chosen. Names keep the common case — "make it orange" —
/// exact, and hex stays available for anything else.
const Map<String, int> kTagGroupColorNames = {
  'blue': 0xFF6A9BDD,
  'purple': 0xFF9B84E0,
  'pink': 0xFFD983A6,
  'orange': 0xFFD9925B,
  'mint': 0xFF5FBF8F,
  'gold': 0xFFC7B45A,
  'slate': 0xFF8A9BB0,
  'brown': 0xFFB08A6A,
};

/// Parses a color the model wrote: a preset name, or `#RRGGBB` / `#AARRGGBB`
/// (with or without the `#`). Six-digit hex is taken as fully opaque —
/// a group tinted at 0% alpha would just look broken.
///
/// Throws [ToolArgError] on anything else rather than falling back to a
/// default, so a mistyped color is visible instead of silently applied.
int parseTagGroupColor(String raw) {
  final text = raw.trim();
  final preset = kTagGroupColorNames[text.toLowerCase()];
  if (preset != null) return preset;
  final hex = text.startsWith('#') ? text.substring(1) : text;
  if (RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(hex)) {
    return 0xFF000000 | int.parse(hex, radix: 16);
  }
  if (RegExp(r'^[0-9a-fA-F]{8}$').hasMatch(hex)) {
    return int.parse(hex, radix: 16);
  }
  throw ToolArgError(
    '"$raw" is not a color; use one of '
    '${kTagGroupColorNames.keys.join(', ')} or a hex value like #6A9BDD',
  );
}

/// The color as the model should read it back: hex, plus the preset name when
/// it landed on one.
String formatTagGroupColor(int argb) {
  final hex =
      '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
  final name = kTagGroupColorNames.entries
      .where((e) => e.value == argb)
      .map((e) => e.key)
      .firstOrNull;
  return name == null ? hex : '$name ($hex)';
}

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
      // In panel order, so a reorder or a recolor is visible in the same
      // result that performed it.
      'groups': [
        for (final g in groups)
          {
            'name': g.name,
            'tags': g.tags.length,
            'color': formatTagGroupColor(g.color),
          },
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
      // Only the delete needs the user's blessing. Gating the whole tool
      // would prompt as loudly for a rename, and a prompt that fires for
      // everything stops being read.
      isWrite: true,
      confirmWhen: (args) => optString(args, 'action') == 'delete',
      spec: AgentToolSpec(
        name: 'manage_tag_groups',
        description:
            'Change the groups of the tag library themselves — rename one, '
            'recolor it, set the order they appear in, or delete one. Tags '
            'and group membership are never touched here: use '
            'organize_tag_library to move tags between groups.\n'
            'Pick one "action" per call.',
        parametersSchema: {
          'type': 'object',
          'properties': {
            'action': {
              'type': 'string',
              'enum': ['update', 'reorder', 'delete'],
              'description':
                  '"update": rename and/or recolor the group named by '
                  '"group". "reorder": set the panel order from "order". '
                  '"delete": remove the group named by "group" — its tags '
                  'fall back to the ungrouped bucket, and there is no undo, '
                  'so only do it when the user has said so.',
            },
            'group': {
              'type': 'string',
              'description': 'for update / delete: the group\'s current name',
            },
            'new_name': {'type': 'string', 'description': 'for update'},
            'color': {
              'type': 'string',
              'description':
                  'for update: one of ${kTagGroupColorNames.keys.join(', ')}, '
                  'or a hex value like "#6A9BDD". Group colors are only a '
                  'visual aid in the panel; pick one that reads as the '
                  'group\'s theme and keep sibling groups distinguishable.',
            },
            'order': {
              'type': 'array',
              'items': {'type': 'string'},
              'description':
                  'for reorder: existing group names, top to bottom, in ONE '
                  'call. Groups left out keep their relative order behind '
                  'the ones listed, so naming a single group lifts it to the '
                  'top. Names matching no group are reported back and '
                  'skipped.',
            },
          },
          'required': ['action'],
        },
      ),
      handler: (args) async {
        final action = requireString(args, 'action');
        AgentToolResult noSuchGroup(String name) => toolError(
          'no group named "$name"; existing groups: '
          '${deps.tagGroups().map((g) => g.name).join(', ')}',
        );

        switch (action) {
          case 'update':
            final name = requireString(args, 'group');
            final next = optString(args, 'new_name');
            final rawColor = optString(args, 'color');
            if (next == null && rawColor == null) {
              throw ToolArgError(
                'nothing to change: pass "new_name", "color", or both',
              );
            }
            final color = rawColor == null
                ? null
                : parseTagGroupColor(rawColor);
            final group = findGroup(name);
            if (group == null) return noSuchGroup(name);
            if (next != null) {
              final clash = findGroup(next);
              if (clash != null && clash.id != group.id) {
                return toolError(
                  'a group named "${clash.name}" already exists; move the '
                  'tags into it with organize_tag_library instead of '
                  'renaming',
                );
              }
            }
            await deps.updateGroup(group.id, name: next, color: color);
            return toolOk({
              'group': group.name,
              'renamed_to': ?next,
              if (color != null) 'color': formatTagGroupColor(color),
              'tags': group.tags.length,
            });

          case 'reorder':
            final asked = requireStringList(args, 'order');
            final ids = <String>[];
            final seen = <String>{};
            final unknown = <String>[];
            final duplicates = <String>[];
            for (final name in asked) {
              final group = findGroup(name);
              if (group == null) {
                unknown.add(name);
              } else if (!seen.add(group.id)) {
                duplicates.add(name);
              } else {
                ids.add(group.id);
              }
            }
            if (ids.isEmpty) {
              return toolError(
                'none of these names match a group; existing groups: '
                '${deps.tagGroups().map((g) => g.name).join(', ')}',
              );
            }
            await deps.reorderGroups(ids);
            return toolOk({
              'order': [for (final g in deps.tagGroups()) g.name],
              if (unknown.isNotEmpty) 'no_such_group': unknown,
              if (duplicates.isNotEmpty) 'listed_twice': duplicates,
            });

          case 'delete':
            final name = requireString(args, 'group');
            final group = findGroup(name);
            if (group == null) return noSuchGroup(name);
            await deps.deleteGroup(group.id);
            return toolOk({
              'deleted': group.name,
              'tags_returned_to_ungrouped': group.tags.length,
              'library': librarySummary(),
            });

          default:
            return toolError(
              '"action" must be "update", "reorder" or "delete"; got '
              '"$action"',
            );
        }
      },
    ),
  ];
}
