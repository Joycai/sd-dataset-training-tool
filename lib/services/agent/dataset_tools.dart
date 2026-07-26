/// The dataset-facing agent tools (Phase 1: read-only).
///
/// Handlers close over live app state via [DatasetToolsDeps] accessors, so
/// they always see the current dataset. All image paths exchanged with the
/// model are *relative to the dataset root* — shorter, and resolving them
/// back is guarded against directory traversal.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import '../../models/tag_group.dart';
import '../../state/dataset_state.dart';
import '../../state/tag_ops.dart';
import 'agent_tools.dart';

class DatasetToolsDeps {
  const DatasetToolsDeps({
    required this.dataset,
    required this.rootDir,
    required this.libraryTags,
    required this.tagGroups,
  });

  final DatasetState dataset;

  /// The currently open dataset directory, or null when none is open.
  final String? Function() rootDir;

  final List<String> Function() libraryTags;
  final List<TagGroup> Function() tagGroups;
}

List<AgentTool> buildReadOnlyTools(DatasetToolsDeps deps) => [
      AgentTool(
        spec: const AgentToolSpec(
          name: 'get_dataset_overview',
          description:
              'Overview of the currently open dataset: image counts, caption '
              'status, number of unique tags. Call this first.',
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
            'total_images': d.totalCount,
            'captioned': d.taggedCount,
            'uncaptioned': d.untaggedCount,
            'unique_tags': d.datasetTags.length,
            'caption_extension': d.captionExtension,
          });
        },
      ),
      AgentTool(
        spec: const AgentToolSpec(
          name: 'get_tag_stats',
          description:
              'Tags across the whole dataset with how many images carry '
              'each, as [tag, count] pairs. The primary way to understand '
              'the tag vocabulary — prefer this over reading captions '
              'image by image.',
          parametersSchema: {
            'type': 'object',
            'properties': {
              'sort': {
                'type': 'string',
                'enum': ['count', 'alpha'],
                'description': 'count (default): most frequent first; '
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
            tags = [...tags]..sort(
                (a, b) => a.tag.toLowerCase().compareTo(b.tag.toLowerCase()));
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
              'limit': {
                'type': 'integer',
                'description': 'default 50, max 200',
              },
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
              'by tags and caption status. Use the filters plus pagination — '
              'do not page through the whole dataset without need.',
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
              'limit': {
                'type': 'integer',
                'description': 'default 100, max 500',
              },
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
          for (final f in d.allFiles) {
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
          // Canonical lookup tolerates case/separator differences on Windows.
          final canonical = {
            for (final f in d.allFiles) p.canonicalize(f.path): f.path,
          };
          final out = <Map<String, dynamic>>[];
          for (final rel in paths) {
            final resolved = resolveDatasetPath(root, rel);
            final key = resolved == null ? null : canonical[resolved];
            if (key == null) {
              out.add({'path': rel, 'error': 'not found in dataset'});
              continue;
            }
            out.add({
              'path': rel,
              'captioned': d.hasCaption(key),
              'tags': d.tagsOf(key),
            });
          }
          return toolOk({'captions': out});
        },
      ),
      AgentTool(
        spec: const AgentToolSpec(
          name: 'get_tag_library',
          description:
              'The user\'s curated tag library (their standard tag set), '
              'with its named groups. Useful as the normalization target '
              'when cleaning dataset tags.',
          parametersSchema: {'type': 'object', 'properties': {}},
        ),
        handler: (args) async {
          final groups = deps.tagGroups();
          final grouped = {for (final g in groups) ...{for (final t in g.tags) t: true}};
          return toolOk({
            'groups': [
              for (final g in groups) {'name': g.name, 'tags': g.tags},
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
List<AgentTool> buildWriteTools(DatasetToolsDeps deps, TagOps tagOps) => [
      AgentTool(
        isWrite: true,
        spec: const AgentToolSpec(
          name: 'remove_tag_everywhere',
          description:
              'Remove one tag from every caption in the dataset that has '
              'it. Undoable.',
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
          final changed = await tagOps.deleteEverywhere(
            tag,
            label: 'AI: remove "$tag"',
          );
          return toolOk({'changed_files': changed});
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
          final changed = await tagOps.replaceEverywhere(
            tag,
            replacement,
            label: 'AI: replace "$tag" → "$replacement"',
          );
          return toolOk({'changed_files': changed});
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
                'description': 'true (default): insert after the anchor; '
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
          final changed = await tagOps.insertBeside(
            anchor,
            tags.join(', '),
            after: after,
            label: 'AI: insert ${tags.join(", ")} '
                '${after ? 'after' : 'before'} "$anchor"',
          );
          return toolOk({'changed_files': changed});
        },
      ),
      AgentTool(
        isWrite: true,
        spec: const AgentToolSpec(
          name: 'add_tags_everywhere',
          description:
              'Add tags to captions at a given position (0 = first, omitted '
              '= append at end). By default affects the whole dataset; '
              'narrow it with the same filters as list_images. Captions '
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
          final files = _filterFiles(
            deps.dataset,
            include: optStringList(args, 'include_tags'),
            exclude: optStringList(args, 'exclude_tags'),
            untaggedOnly: optBool(args, 'untagged_only'),
            nameQuery: optString(args, 'name_query')?.toLowerCase(),
          );
          final changed = await tagOps.addEverywhere(
            tags.join(', '),
            index: index,
            files: files,
            label: 'AI: add ${tags.join(", ")}',
          );
          return toolOk({'changed_files': changed});
        },
      ),
      AgentTool(
        isWrite: true,
        spec: const AgentToolSpec(
          name: 'write_caption',
          description:
              'Overwrite one image\'s caption with exactly the given text '
              '(comma-separated tags). Use for per-image edits such as '
              'reordering; prefer the batch tools for dataset-wide '
              'changes. Undoable.',
          parametersSchema: {
            'type': 'object',
            'properties': {
              'path': {
                'type': 'string',
                'description': 'image path as returned by list_images',
              },
              'caption': {'type': 'string'},
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
          final resolved = resolveDatasetPath(root, rel);
          final canonical = {
            for (final f in deps.dataset.allFiles) p.canonicalize(f.path): f.path,
          };
          final key = resolved == null ? null : canonical[resolved];
          if (key == null) {
            return toolError('image not found in dataset: $rel');
          }
          final written = await tagOps.rewriteOne(
            key,
            caption,
            label: 'AI: rewrite ${p.basename(key)}',
          );
          return toolOk({'written': written, 'unchanged': !written});
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
                'refusing to undo it');
          }
          await tagOps.undo();
          return toolOk({'undone': label});
        },
      ),
    ];

List<File> _filterFiles(
  DatasetState dataset, {
  required List<String> include,
  required List<String> exclude,
  required bool untaggedOnly,
  String? nameQuery,
}) {
  final out = <File>[];
  for (final f in dataset.allFiles) {
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
