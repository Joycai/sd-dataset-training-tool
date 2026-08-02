/// The dataset-facing agent tools (Phase 1: read-only).
///
/// Handlers close over live app state via [DatasetToolsDeps] accessors, so
/// they always see the current dataset. All image paths exchanged with the
/// model are *relative to the dataset root* — shorter, and resolving them
/// back is guarded against directory traversal.
///
/// Every tool here — read and write alike — sees only
/// [DatasetState.scopedFiles], the dataset's active subdirectory scope. The
/// model is never handed a path it may not also write to, which is what keeps
/// "remove this tag everywhere" honest when the user has narrowed the app to
/// one folder.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../models/caption_type.dart';
import '../../models/tag_group.dart';
import '../../state/dataset_state.dart';
import '../../state/tag_ops.dart';
import '../../utils/tag_text.dart';
import 'agent_tools.dart';
import 'tag_library_tools.dart' show formatTagGroupColor;

class DatasetToolsDeps {
  const DatasetToolsDeps({
    required this.dataset,
    required this.rootDir,
    required this.libraryTags,
    required this.tagGroups,
    this.captionTypes = _noCaptionTypes,
  });

  static List<CaptionType> _noCaptionTypes() => const [];

  final DatasetState dataset;

  /// The currently open dataset directory, or null when none is open.
  final String? Function() rootDir;

  final List<String> Function() libraryTags;
  final List<TagGroup> Function() tagGroups;

  /// The *enabled* caption types, default first. The active one is whichever
  /// matches [DatasetState.captionExtension] — the scan is the authority, not
  /// the settings, which can change mid-conversation.
  final List<CaptionType> Function() captionTypes;
}

List<AgentTool> buildReadOnlyTools(DatasetToolsDeps deps) => [
  AgentTool(
    spec: const AgentToolSpec(
      name: 'get_dataset_overview',
      description:
          'Overview of the currently open dataset: image counts, caption '
          'status, number of unique tags, and the active subdirectory '
          'scope. Call this first, and again before a batch write if the '
          'conversation has been going for a while — the user can change '
          'the scope at any time.',
      parametersSchema: {'type': 'object', 'properties': {}},
    ),
    handler: (args) async {
      final root = deps.rootDir();
      if (root == null) {
        return toolError('no dataset directory is open');
      }
      final d = deps.dataset;
      return toolOk({
        'root': root,
        'scope': scopeLabel(d),
        if (d.subdirectories.length > 1)
          'subdirectories': [
            for (final s in d.subdirectories)
              {'path': s.isRoot ? '.' : s.path, 'images': s.count},
          ],
        'total_images': d.totalCount,
        'captioned': d.taggedCount,
        'uncaptioned': d.untaggedCount,
        'unique_tags': d.datasetTags.length,
        'caption_extension': d.captionExtension,
        if (deps.captionTypes().length > 1)
          'caption_types': [
            for (final t in deps.captionTypes())
              {
                'name': t.label,
                'extension': t.extension,
                'active': t.extension == d.captionExtension,
                if (t.format != CaptionFormat.tags) 'format': t.format.name,
              },
          ],
      });
    },
  ),
  AgentTool(
    spec: const AgentToolSpec(
      name: 'get_tag_stats',
      description:
          'Tags across the dataset (or the active subdirectory scope) '
          'with how many images carry each, as [tag, count] pairs. The '
          'primary way to understand the tag vocabulary — prefer this '
          'over reading captions image by image.',
      parametersSchema: {
        'type': 'object',
        'properties': {
          'sort': {
            'type': 'string',
            'enum': ['count', 'alpha'],
            'description':
                'count (default): most frequent first; '
                'alpha: alphabetical',
          },
          'limit': {
            'type': 'integer',
            'description': 'max entries to return (default 200, max 1000)',
          },
          'offset': {'type': 'integer'},
        },
      },
    ),
    handler: (args) async {
      final sort = optString(args, 'sort') ?? 'count';
      final limit = optInt(args, 'limit', fallback: 200, min: 1, max: 1000);
      final offset = optInt(args, 'offset', fallback: 0, min: 0);
      var tags = deps.dataset.datasetTags;
      if (sort == 'alpha') {
        tags = [...tags]
          ..sort((a, b) => a.tag.toLowerCase().compareTo(b.tag.toLowerCase()));
      }
      final page = tags.skip(offset).take(limit).toList();
      return toolOk({
        'total_unique': tags.length,
        'offset': offset,
        'returned': page.length,
        'truncated': offset + page.length < tags.length,
        'tags': [
          for (final t in page) [t.tag, t.count],
        ],
      });
    },
  ),
  AgentTool(
    spec: const AgentToolSpec(
      name: 'search_tags',
      description:
          'Case-insensitive substring search over the dataset tag list. '
          'Returns [tag, image_count] pairs.',
      parametersSchema: {
        'type': 'object',
        'properties': {
          'query': {'type': 'string'},
          'limit': {'type': 'integer', 'description': 'default 50, max 200'},
        },
        'required': ['query'],
      },
    ),
    handler: (args) async {
      final query = requireString(args, 'query').toLowerCase();
      final limit = optInt(args, 'limit', fallback: 50, min: 1, max: 200);
      final matches = deps.dataset.datasetTags
          .where((t) => t.tag.toLowerCase().contains(query))
          .toList();
      return toolOk({
        'total_matches': matches.length,
        'truncated': matches.length > limit,
        'tags': [
          for (final t in matches.take(limit)) [t.tag, t.count],
        ],
      });
    },
  ),
  AgentTool(
    spec: const AgentToolSpec(
      name: 'list_images',
      description:
          'List images (paths relative to the dataset root), filterable '
          'by tags and caption status. Only images inside the active '
          'subdirectory scope are listed. Use the filters plus '
          'pagination — do not page through the whole dataset without '
          'need.',
      parametersSchema: {
        'type': 'object',
        'properties': {
          'include_tags': {
            'type': 'array',
            'items': {'type': 'string'},
            'description': 'only images carrying ALL of these tags',
          },
          'exclude_tags': {
            'type': 'array',
            'items': {'type': 'string'},
            'description': 'only images carrying NONE of these tags',
          },
          'untagged_only': {
            'type': 'boolean',
            'description': 'only images without a caption',
          },
          'name_query': {
            'type': 'string',
            'description': 'case-insensitive filename substring',
          },
          'limit': {'type': 'integer', 'description': 'default 100, max 500'},
          'offset': {'type': 'integer'},
        },
      },
    ),
    handler: (args) async {
      final root = deps.rootDir();
      if (root == null) return toolError('no dataset directory is open');
      final include = optStringList(args, 'include_tags');
      final exclude = optStringList(args, 'exclude_tags');
      final untaggedOnly = optBool(args, 'untagged_only');
      final nameQuery = optString(args, 'name_query')?.toLowerCase();
      final limit = optInt(args, 'limit', fallback: 100, min: 1, max: 500);
      final offset = optInt(args, 'offset', fallback: 0, min: 0);

      final d = deps.dataset;
      final matched = <({String path, int nTags, bool captioned})>[];
      for (final f in d.scopedFiles) {
        if (nameQuery != null &&
            !p.basename(f.path).toLowerCase().contains(nameQuery)) {
          continue;
        }
        final captioned = d.hasCaption(f.path);
        if (untaggedOnly && captioned) continue;
        final tags = d.tagsOf(f.path).toSet();
        if (include.isNotEmpty && !include.every(tags.contains)) continue;
        if (exclude.isNotEmpty && exclude.any(tags.contains)) continue;
        matched.add((
          path: p.relative(f.path, from: root),
          nTags: tags.length,
          captioned: captioned,
        ));
      }
      final page = matched.skip(offset).take(limit).toList();
      return toolOk({
        'scope': scopeLabel(d),
        'total_matches': matched.length,
        'offset': offset,
        'returned': page.length,
        'truncated': offset + page.length < matched.length,
        'images': [
          for (final m in page)
            {'path': m.path, 'tags': m.nTags, 'captioned': m.captioned},
        ],
      });
    },
  ),
  AgentTool(
    spec: const AgentToolSpec(
      name: 'read_captions',
      description:
          'Read the caption tags of specific images (paths as returned '
          'by list_images). Max 50 per call.',
      parametersSchema: {
        'type': 'object',
        'properties': {
          'paths': {
            'type': 'array',
            'items': {'type': 'string'},
          },
        },
        'required': ['paths'],
      },
    ),
    handler: (args) async {
      final root = deps.rootDir();
      if (root == null) return toolError('no dataset directory is open');
      final paths = requireStringList(args, 'paths', maxLength: 50);
      final d = deps.dataset;
      final canonical = canonicalIndex(d);
      final out = <Map<String, dynamic>>[];
      for (final rel in paths) {
        final resolved = resolveDatasetPath(root, rel);
        final key = resolved == null ? null : canonical[resolved];
        if (key == null) {
          out.add({'path': rel, 'error': notFoundMessage(d, rel)});
          continue;
        }
        out.add({
          'path': rel,
          'captioned': d.hasCaption(key),
          'tags': d.tagsOf(key),
        });
      }
      // Pinned: per-image rewrites read this once and then work from it for
      // many turns, so it must outlive ordinary compaction.
      return toolOk({'captions': out}, pinned: true);
    },
  ),
  AgentTool(
    spec: const AgentToolSpec(
      name: 'get_tag_library',
      description:
          'The user\'s curated tag library (their standard tag set), '
          'with its named groups, in the order and colors the panel shows '
          'them. Useful as the normalization target when cleaning dataset '
          'tags, and as the starting point for tidying the library itself — '
          'organize_tag_library files these tags into groups, '
          'add_library_tags extends it, update_tag_group and '
          'reorder_tag_groups change how the groups themselves look.',
      parametersSchema: {'type': 'object', 'properties': {}},
    ),
    handler: (args) async {
      final groups = deps.tagGroups();
      final grouped = {
        for (final g in groups) ...{for (final t in g.tags) t: true},
      };
      return toolOk({
        'groups': [
          for (final g in groups)
            {
              'name': g.name,
              'color': formatTagGroupColor(g.color),
              'tags': g.tags,
            },
        ],
        'ungrouped': [
          for (final t in deps.libraryTags())
            if (!grouped.containsKey(t)) t,
        ],
      });
    },
  ),
];

/// The write tools (Phase 2). Every mutation goes through [TagOps], so it
/// lands on the shared undo stack with an `AI: ` label the user can inspect
/// in the top bar and revert with Ctrl+Z.
///
/// The "everywhere" tools sweep the active subdirectory scope, not
/// necessarily the whole dataset; each result carries the scope it ran under
/// so the model reports what actually happened.
///
/// Every handler here is wrapped in [_guardBusy]: [TagOps] refuses reentrant
/// runs by returning "0 files changed", which the model would otherwise read
/// as "no image matched" and move on from a write that never happened.
List<AgentTool> buildWriteTools(DatasetToolsDeps deps, TagOps tagOps) => [
  for (final tool in _writeTools(deps, tagOps))
    AgentTool(
      spec: tool.spec,
      isWrite: tool.isWrite,
      handler: guardBusy(tagOps, tool.handler),
    ),
];

/// Wraps a write handler so it refuses to run while [TagOps] is busy —
/// without this, [TagOps] would return "0 files changed", which the model
/// reads as "no image matched" and moves on from a write that never
/// happened. Shared with the caption-variant write tools.
AgentToolHandler guardBusy(TagOps tagOps, AgentToolHandler inner) =>
    (args) async {
      if (tagOps.busy) {
        return toolError(
          'another caption operation is still running; nothing was '
          'written — wait and retry',
        );
      }
      return inner(args);
    };

List<AgentTool> _writeTools(DatasetToolsDeps deps, TagOps tagOps) => [
  AgentTool(
    isWrite: true,
    spec: const AgentToolSpec(
      name: 'remove_tag_everywhere',
      description:
          'Remove one tag from every caption that has it, within the '
          'active subdirectory scope. Undoable.',
      parametersSchema: {
        'type': 'object',
        'properties': {
          'tag': {'type': 'string'},
        },
        'required': ['tag'],
      },
    ),
    handler: (args) async {
      final tag = requireString(args, 'tag');
      return _batchResult(
        await tagOps.deleteEverywhere(tag, label: 'AI: remove "$tag"'),
        scope: scopeLabel(deps.dataset),
      );
    },
  ),
  AgentTool(
    isWrite: true,
    spec: const AgentToolSpec(
      name: 'replace_tag_everywhere',
      description:
          'Replace one tag, in place, in every caption that has it. The '
          'replacement may be several comma-separated tags; duplicates '
          'already present in a caption are skipped. Undoable.',
      parametersSchema: {
        'type': 'object',
        'properties': {
          'tag': {'type': 'string'},
          'replacement': {
            'type': 'string',
            'description': 'one or more comma-separated tags',
          },
        },
        'required': ['tag', 'replacement'],
      },
    ),
    handler: (args) async {
      final tag = requireString(args, 'tag');
      final replacement = requireString(args, 'replacement');
      return _batchResult(
        await tagOps.replaceEverywhere(
          tag,
          replacement,
          label: 'AI: replace "$tag" → "$replacement"',
        ),
        scope: scopeLabel(deps.dataset),
      );
    },
  ),
  AgentTool(
    isWrite: true,
    spec: const AgentToolSpec(
      name: 'insert_beside_tag',
      description:
          'Insert tags directly before or after an anchor tag in every '
          'caption that has the anchor. Tags a caption already contains '
          'are skipped. Undoable.',
      parametersSchema: {
        'type': 'object',
        'properties': {
          'anchor_tag': {'type': 'string'},
          'tags': {
            'type': 'array',
            'items': {'type': 'string'},
          },
          'after': {
            'type': 'boolean',
            'description':
                'true (default): insert after the anchor; '
                'false: before it',
          },
        },
        'required': ['anchor_tag', 'tags'],
      },
    ),
    handler: (args) async {
      final anchor = requireString(args, 'anchor_tag');
      final tags = requireStringList(args, 'tags', maxLength: 50);
      final after = optBool(args, 'after', fallback: true);
      return _batchResult(
        await tagOps.insertBeside(
          anchor,
          tags.join(', '),
          after: after,
          label:
              'AI: insert ${tags.join(", ")} '
              '${after ? 'after' : 'before'} "$anchor"',
        ),
        scope: scopeLabel(deps.dataset),
      );
    },
  ),
  AgentTool(
    isWrite: true,
    spec: const AgentToolSpec(
      name: 'add_tags_everywhere',
      description:
          'Add tags to captions at a given position (0 = first, omitted '
          '= append at end). By default affects everything in the active '
          'subdirectory scope; narrow it further with the same filters '
          'as list_images. Captions '
          'that already contain a tag are skipped; uncaptioned images '
          'get a caption file created. Undoable.',
      parametersSchema: {
        'type': 'object',
        'properties': {
          'tags': {
            'type': 'array',
            'items': {'type': 'string'},
          },
          'index': {
            'type': 'integer',
            'description': 'insertion position; omit to append at end',
          },
          'include_tags': {
            'type': 'array',
            'items': {'type': 'string'},
          },
          'exclude_tags': {
            'type': 'array',
            'items': {'type': 'string'},
          },
          'untagged_only': {'type': 'boolean'},
          'name_query': {'type': 'string'},
        },
        'required': ['tags'],
      },
    ),
    handler: (args) async {
      final tags = requireStringList(args, 'tags', maxLength: 50);
      final index = args['index'] == null
          ? null
          : optInt(args, 'index', fallback: 0, min: 0);
      final files = filterDatasetFiles(
        deps.dataset,
        include: optStringList(args, 'include_tags'),
        exclude: optStringList(args, 'exclude_tags'),
        untaggedOnly: optBool(args, 'untagged_only'),
        nameQuery: optString(args, 'name_query')?.toLowerCase(),
      );
      return _batchResult(
        await tagOps.addEverywhere(
          tags.join(', '),
          index: index,
          files: files,
          label: 'AI: add ${tags.join(", ")}',
        ),
        scope: scopeLabel(deps.dataset),
      );
    },
  ),
  AgentTool(
    isWrite: true,
    spec: const AgentToolSpec(
      name: 'sort_captions_everywhere',
      description:
          'Sort the tags of many captions at once against a single '
          'priority list — the tool for "order tags by category" over a '
          'whole dataset or a filtered subset. Tags named in `priority` '
          'come first, in that order; every other tag keeps its relative '
          'position. No tag is ever added, removed or reworded, so you do '
          'not have to read the captions first and there is nothing to '
          'get wrong per image. Always prefer this over calling '
          'reorder_caption in a loop — that one is for touching up a '
          'single image. Build the priority list from get_tag_stats or '
          'get_tag_library. Narrow the scope with the same filters as '
          'list_images. Undoable as one operation.',
      parametersSchema: {
        'type': 'object',
        'properties': {
          'priority': {
            'type': 'array',
            'items': {'type': 'string'},
            'description':
                'tags in the order they should appear; matching ignores '
                'case and underscore/space differences, and tags no image '
                'has are simply unused',
          },
          'keep_first': {
            'type': 'integer',
            'description':
                'leave this many leading tags of each caption untouched '
                '(the trigger word); default 0',
          },
          'unlisted': {
            'type': 'string',
            'description':
                'where tags missing from priority go: "end" (default) or '
                '"start"',
          },
          'include_tags': {
            'type': 'array',
            'items': {'type': 'string'},
          },
          'exclude_tags': {
            'type': 'array',
            'items': {'type': 'string'},
          },
          'untagged_only': {'type': 'boolean'},
          'name_query': {'type': 'string'},
        },
        'required': ['priority'],
      },
    ),
    handler: (args) async {
      final priority = requireStringList(args, 'priority', maxLength: 500);
      final keepFirst = optInt(args, 'keep_first', fallback: 0, min: 0);
      final unlisted = optString(args, 'unlisted')?.toLowerCase();
      if (unlisted != null && unlisted != 'end' && unlisted != 'start') {
        return toolError('"unlisted" must be either "end" or "start"');
      }
      final files = filterDatasetFiles(
        deps.dataset,
        include: optStringList(args, 'include_tags'),
        exclude: optStringList(args, 'exclude_tags'),
        untaggedOnly: optBool(args, 'untagged_only'),
        nameQuery: optString(args, 'name_query')?.toLowerCase(),
      );
      return _batchResult(
        await tagOps.reorderEverywhere(
          priority,
          files: files,
          keepFirst: keepFirst,
          unlistedFirst: unlisted == 'start',
          label: 'AI: sort caption tags',
        ),
        scope: scopeLabel(deps.dataset),
        extra: {'scanned_files': files.length},
      );
    },
  ),
  AgentTool(
    isWrite: true,
    spec: const AgentToolSpec(
      name: 'reorder_caption',
      description:
          'Reorder ONE image\'s caption tags, for a touch-up that a '
          'priority list cannot express. To sort more than a couple of '
          'images use sort_captions_everywhere instead — looping this '
          'tool over a batch is slow and fails as soon as one tag is '
          'mistyped. The order you give must be a permutation of the '
          'tags the image already has: nothing may be added, removed or '
          'reworded. A mismatch writes nothing and returns the image\'s '
          'current tags, so reorder from a fresh read_captions rather '
          'than from memory. Use write_caption only when the tags '
          'themselves have to change. Undoable.',
      parametersSchema: {
        'type': 'object',
        'properties': {
          'path': {
            'type': 'string',
            'description': 'image path as returned by list_images',
          },
          'order': {
            'type': 'array',
            'items': {'type': 'string'},
            'description':
                'every tag the image already has, exactly once, in the '
                'new order',
          },
        },
        'required': ['path', 'order'],
      },
    ),
    handler: (args) async {
      final root = deps.rootDir();
      if (root == null) return toolError('no dataset directory is open');
      // A JSON caption's tags are its string leaves; writing them back as a
      // comma-joined list would replace the whole document with a tag line.
      // Reordering a JSON caption is a restructure, not a permutation.
      if (deps.dataset.captionFormat == CaptionFormat.json) {
        return toolError(
          'nothing was written: the active caption type '
          '("${deps.dataset.captionExtension}") is JSON, whose tags live '
          'inside a document this tool cannot rebuild. Use '
          'restructure_json_captions to change a JSON caption\'s field '
          'order or layout.',
        );
      }
      final rel = requireString(args, 'path');
      final order = requireStringList(args, 'order');
      final key = resolveImageKey(deps.dataset, root, rel);
      if (key == null) {
        return toolError('image ${notFoundMessage(deps.dataset, rel)}');
      }

      final current = deps.dataset.tagsOf(key);
      if (current.isEmpty) return toolError('$rel has no caption to reorder');

      final match = matchPermutation(current, order);
      if (match.unknown.isNotEmpty || match.missing.isNotEmpty) {
        return toolError(
          'nothing was written: the given order is not a permutation of '
          '$rel\'s tags'
          '${match.unknown.isEmpty ? '' : '; not on this image: '
                    '${match.unknown.join(", ")}'}'
          '${match.missing.isEmpty ? '' : '; left out: '
                    '${match.missing.join(", ")}'}'
          '. Its ${current.length} current tags are: ${current.join(", ")}'
          '. If you are sorting a batch of images, stop looping this tool '
          'and use sort_captions_everywhere: it takes one priority list '
          'for all of them and cannot mismatch.',
        );
      }
      final result = await tagOps.rewriteOne(
        key,
        match.ordered.join(', '),
        label: 'AI: reorder ${p.basename(key)}',
      );
      if (result.failed) {
        return toolError('nothing was written for $rel: ${result.error}');
      }
      return toolOk({
        'written': result.written,
        'unchanged': result.unchanged,
        'tags': match.ordered,
      });
    },
  ),
  AgentTool(
    isWrite: true,
    spec: const AgentToolSpec(
      name: 'write_caption',
      description:
          'Overwrite one image\'s caption with exactly the given text '
          '(comma-separated tags). For changing *which* tags an image '
          'carries; to change only their order use reorder_caption, and '
          'for dataset-wide changes prefer the batch tools. The result '
          'reports which tags this write added and removed. If the active '
          'caption type is JSON the text must be a whole JSON document — '
          'to change many JSON captions\' layout use '
          'restructure_json_captions instead. Undoable.',
      parametersSchema: {
        'type': 'object',
        'properties': {
          'path': {
            'type': 'string',
            'description': 'image path as returned by list_images',
          },
          'caption': {'type': 'string'},
          'expect_same_tags': {
            'type': 'boolean',
            'description':
                'reject the write if it would add or remove any tag; set '
                'it whenever you mean to rewrite without changing the '
                'tag set',
          },
        },
        'required': ['path', 'caption'],
      },
    ),
    handler: (args) async {
      final root = deps.rootDir();
      if (root == null) return toolError('no dataset directory is open');
      final rel = requireString(args, 'path');
      final caption = args['caption'];
      if (caption is! String) {
        return toolError('missing required string parameter "caption"');
      }
      final key = resolveImageKey(deps.dataset, root, rel);
      if (key == null) {
        return toolError('image ${notFoundMessage(deps.dataset, rel)}');
      }

      // The active type decides the grammar. A JSON caption must stay a
      // parseable document, and its "tags" are its string leaves — reading
      // the new text with the tag grammar instead would make the
      // expect_same_tags guard below compare nonsense and let a write that
      // flattens the document pass as unchanged.
      final format = deps.dataset.captionFormat;
      if (format == CaptionFormat.json) {
        try {
          jsonDecode(caption);
        } on FormatException catch (e) {
          return toolError(
            'nothing was written for $rel: the active caption type '
            '("${deps.dataset.captionExtension}") is JSON but this text does '
            'not parse — ${e.message}'
            '${e.offset == null ? '' : ' (offset ${e.offset})'}',
          );
        }
      }
      final before = deps.dataset.tagsOf(key);
      final after = parseCaptionText(caption, format: format);
      final beforeSet = before.toSet();
      final afterSet = after.toSet();
      final added = [
        for (final t in after)
          if (!beforeSet.contains(t)) t,
      ];
      final removed = [
        for (final t in before)
          if (!afterSet.contains(t)) t,
      ];

      if (optBool(args, 'expect_same_tags') &&
          (added.isNotEmpty || removed.isNotEmpty)) {
        return toolError(
          'nothing was written: expect_same_tags was set but this caption '
          'would change the tag set'
          '${added.isEmpty ? '' : '; added: ${added.join(", ")}'}'
          '${removed.isEmpty ? '' : '; removed: ${removed.join(", ")}'}'
          '. Its ${before.length} current tags are: ${before.join(", ")}',
        );
      }
      final result = await tagOps.rewriteOne(
        key,
        caption,
        label: 'AI: rewrite ${p.basename(key)}',
      );
      if (result.failed) {
        return toolError('nothing was written for $rel: ${result.error}');
      }
      return toolOk({
        'written': result.written,
        'unchanged': result.unchanged,
        'added': added,
        'removed': removed,
      });
    },
  ),
  AgentTool(
    isWrite: true,
    spec: const AgentToolSpec(
      name: 'undo_last_operation',
      description:
          'Undo the most recent caption operation, but only if it was '
          'performed by the assistant (its label starts with "AI:"). '
          'User operations are never undone by this tool.',
      parametersSchema: {'type': 'object', 'properties': {}},
    ),
    handler: (args) async {
      final label = tagOps.undoLabel;
      if (!tagOps.canUndo || label == null) {
        return toolError('nothing to undo');
      }
      if (!label.startsWith('AI:')) {
        return toolError(
          'the most recent operation ("$label") was made by the user; '
          'refusing to undo it',
        );
      }
      final result = await tagOps.undo();
      if (result.failed > 0) {
        const sample = 5;
        return toolError(
          'the undo only restored ${result.restored} file(s): '
          '${result.failed} could not be written — '
          '${result.failures.take(sample).join('; ')}'
          '${result.failed > sample ? '; …' : ''}'
          '. The operation is still on the undo stack, so the dataset is '
          'half-reverted; tell the user rather than writing over it.',
        );
      }
      return toolOk({'undone': label, 'restored_files': result.restored});
    },
  ),
];

/// Reports a dataset-wide rewrite back to the model.
///
/// A sweep skips caption files it cannot read or write instead of aborting,
/// so the skipped ones must be named here: reporting only `changed_files`
/// would let a sweep that failed on every file read as "nothing matched".
/// Nothing written *and* files failed is an error, not a no-op.
///
/// [scope] travels with every success: the user can narrow the app to one
/// subdirectory mid-conversation, and a model working from a stale overview
/// would otherwise report a folder-wide sweep as a dataset-wide one.
AgentToolResult _batchResult(
  BatchRewriteResult result, {
  required String scope,
  Map<String, dynamic> extra = const {},
}) {
  if (result.failures.isEmpty) {
    return toolOk({'changed_files': result.changed, 'scope': scope, ...extra});
  }
  const sample = 5;
  if (result.changed == 0) {
    return toolError(
      'nothing was written: all ${result.failed} caption files this '
      'operation tried to rewrite failed — '
      '${result.failures.take(sample).join('; ')}'
      '${result.failed > sample ? '; …' : ''}',
    );
  }
  return toolOk({
    'changed_files': result.changed,
    'scope': scope,
    'failed_files': result.failed,
    'failures': [
      for (final f in result.failures.take(sample))
        {'caption_file': p.basename(f.captionPath), 'error': f.error},
    ],
    'failures_truncated': result.failed > sample,
    ...extra,
  });
}

/// The "no such image" message. It has to name the scope when one is active:
/// a path that merely sits in another subdirectory reads as a typo otherwise,
/// and the model retries it instead of asking about the scope.
String notFoundMessage(DatasetState dataset, String rel) {
  final scope = dataset.activeSubdirectory;
  if (scope == null) return 'not found in dataset: $rel';
  return 'not found in the active scope (subdirectory '
      '"${scope.isEmpty ? '.' : scope}"): $rel';
}

/// How the active subdirectory scope is described to the model.
String scopeLabel(DatasetState dataset) {
  final scope = dataset.activeSubdirectory;
  if (scope == null) return 'whole dataset';
  return 'subdirectory "${scope.isEmpty ? '.' : scope}" only';
}

/// The images of the active scope that pass the shared list_images-style
/// filters — the file list every batch write sweeps.
List<File> filterDatasetFiles(
  DatasetState dataset, {
  required List<String> include,
  required List<String> exclude,
  required bool untaggedOnly,
  String? nameQuery,
}) {
  final out = <File>[];
  for (final f in dataset.scopedFiles) {
    if (nameQuery != null &&
        !p.basename(f.path).toLowerCase().contains(nameQuery)) {
      continue;
    }
    if (untaggedOnly && dataset.hasCaption(f.path)) continue;
    final tags = dataset.tagsOf(f.path).toSet();
    if (include.isNotEmpty && !include.every(tags.contains)) continue;
    if (exclude.isNotEmpty && exclude.any(tags.contains)) continue;
    out.add(f);
  }
  return out;
}

/// Canonicalized path → the dataset's own path key, over the active scope
/// only: an image the model may not write to must not resolve at all.
/// Canonicalizing tolerates the case and separator differences a model
/// introduces on Windows.
Map<String, String> canonicalIndex(DatasetState dataset) => {
  for (final f in dataset.scopedFiles) p.canonicalize(f.path): f.path,
};

/// Resolves one model-supplied relative path to the dataset's path key, or
/// null when it escapes the root or names no image in the dataset.
String? resolveImageKey(DatasetState dataset, String root, String rel) {
  final resolved = resolveDatasetPath(root, rel);
  return resolved == null ? null : canonicalIndex(dataset)[resolved];
}

/// The outcome of lining a model-supplied tag order up against a caption's
/// own tags: [ordered] is the reordered caption, [unknown] the entries that
/// match no tag on the image, [missing] the tags left out of the order.
typedef PermutationMatch = ({
  List<String> ordered,
  List<String> unknown,
  List<String> missing,
});

/// Maps a requested tag order onto the caption's own tag spellings.
///
/// Matching folds case and underscore style ([tagLookupKey]), so a model
/// that types `long hair` where the file says `long_hair` still reorders
/// instead of silently rewording — [ordered] always carries the file's
/// original spelling. Anything that does not line up one-to-one is reported
/// rather than written, which is what keeps a reorder from inventing or
/// dropping tags.
PermutationMatch matchPermutation(List<String> current, List<String> order) {
  final remaining = <String, List<String>>{};
  for (final tag in current) {
    (remaining[tagLookupKey(tag)] ??= <String>[]).add(tag);
  }
  final ordered = <String>[];
  final unknown = <String>[];
  for (final tag in order) {
    final bucket = remaining[tagLookupKey(tag)];
    if (bucket == null || bucket.isEmpty) {
      unknown.add(tag);
      continue;
    }
    ordered.add(bucket.removeAt(0));
  }
  return (
    ordered: ordered,
    unknown: unknown,
    missing: [for (final bucket in remaining.values) ...bucket],
  );
}

/// Resolves a model-supplied path against the dataset root; returns the
/// canonicalized absolute path, or null when it escapes the root.
String? resolveDatasetPath(String root, String path) {
  final abs = p.isAbsolute(path) ? p.normalize(path) : p.join(root, path);
  final canonical = p.canonicalize(abs);
  final canonicalRoot = p.canonicalize(root);
  if (canonical != canonicalRoot && !p.isWithin(canonicalRoot, canonical)) {
    return null;
  }
  return canonical;
}
