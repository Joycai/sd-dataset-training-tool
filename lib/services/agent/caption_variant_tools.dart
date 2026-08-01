/// Agent tools for datasets that carry several caption flavors side by side
/// (e.g. `.txt` WD14 tags next to `.ntxt` natural-language prose).
///
/// The rest of the tool set only ever sees the *active* caption type — the
/// one the dataset was scanned with. These tools are the deliberate escape
/// hatch: they audit which images have which variant files, read a variant
/// raw, and write one, so the model can verify coverage and generate one
/// flavor from another. They are only registered when more than one type is
/// enabled.
///
/// Writes join the shared [TagOps] undo stack via [TagOps.pushOperation];
/// undoing restores the variant file's bytes without touching the active
/// caption state (see the guard in [TagOps]'s replay).
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../models/caption_type.dart';
import '../../state/dataset_state.dart';
import '../../state/tag_ops.dart';
import '../../utils/tag_text.dart';
import 'agent_tools.dart';
import 'dataset_tools.dart';

/// Per-file text cap for read_caption_file; prose captions are short, so
/// anything past this is almost certainly not a caption at all.
const int _maxCaptionRead = 4000;

List<AgentTool> buildCaptionVariantTools(
  DatasetToolsDeps deps,
  TagOps tagOps,
) => [
  AgentTool(
    spec: const AgentToolSpec(
      name: 'check_caption_variants',
      description:
          'Audit which caption types each image has. Without arguments: '
          'per-type counts of images with a non-empty caption file, over '
          'the active scope. Pass `missing_extension` to page through the '
          'images lacking that type\'s caption file (the work list for '
          'generating one type from another), or `paths` for a per-image '
          'breakdown.',
      parametersSchema: {
        'type': 'object',
        'properties': {
          'paths': {
            'type': 'array',
            'items': {'type': 'string'},
            'description':
                'image paths as returned by list_images (max 50); '
                'returns which caption types each one has',
          },
          'missing_extension': {
            'type': 'string',
            'description':
                'a configured caption extension (e.g. ".ntxt"); lists '
                'images that have no caption file of this type',
          },
          'limit': {
            'type': 'integer',
            'description': 'max missing paths to return (default 100)',
          },
          'offset': {'type': 'integer'},
        },
      },
    ),
    handler: (args) async {
      final root = deps.rootDir();
      if (root == null) return toolError('no dataset directory is open');
      final types = deps.captionTypes();
      if (types.length < 2) {
        return toolError('only one caption type is configured');
      }
      final d = deps.dataset;

      final paths = optStringList(args, 'paths', maxLength: 50);
      if (paths.isNotEmpty) {
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
            'captions': {
              for (final t in types) t.extension: await _hasVariant(d, t, key),
            },
          });
        }
        return toolOk({'images': out});
      }

      CaptionType? missingType;
      final missingExt = optString(args, 'missing_extension');
      if (missingExt != null) {
        missingType = _findType(types, missingExt);
        if (missingType == null) {
          return toolError(_unknownType(missingExt, types));
        }
      }
      final limit = optInt(args, 'limit', fallback: 100, min: 1, max: 500);
      final offset = optInt(args, 'offset', fallback: 0, min: 0);

      final present = {for (final t in types) t.extension: 0};
      final missing = <String>[];
      for (final f in d.scopedFiles) {
        for (final t in types) {
          if (await _hasVariant(d, t, f.path)) {
            present[t.extension] = present[t.extension]! + 1;
          } else if (t.extension == missingType?.extension) {
            missing.add(p.relative(f.path, from: root));
          }
        }
      }
      final page = missing.skip(offset).take(limit).toList();
      return toolOk({
        'scope': scopeLabel(d),
        'total_images': d.totalCount,
        'types': [
          for (final t in types)
            {
              'name': t.label,
              'extension': t.extension,
              'active': t.extension == d.captionExtension,
              'images_with_caption': present[t.extension],
              'images_missing': d.totalCount - present[t.extension]!,
            },
        ],
        if (missingType != null) ...{
          'missing_extension': missingType.extension,
          'offset': offset,
          'returned': page.length,
          'truncated': offset + page.length < missing.length,
          'missing_images': page,
        },
      });
    },
  ),
  AgentTool(
    spec: const AgentToolSpec(
      name: 'read_caption_file',
      description:
          'Read the raw text of a specific caption type\'s files for up '
          'to 20 images — the source material when generating one caption '
          'type from another. Unlike read_captions this does not parse '
          'tags: natural-language captions come back as-is.',
      parametersSchema: {
        'type': 'object',
        'properties': {
          'paths': {
            'type': 'array',
            'items': {'type': 'string'},
            'description': 'image paths as returned by list_images (max 20)',
          },
          'extension': {
            'type': 'string',
            'description': 'a configured caption extension (e.g. ".txt")',
          },
        },
        'required': ['paths', 'extension'],
      },
    ),
    handler: (args) async {
      final root = deps.rootDir();
      if (root == null) return toolError('no dataset directory is open');
      final types = deps.captionTypes();
      final type = _findType(types, requireString(args, 'extension'));
      if (type == null) {
        return toolError(_unknownType(requireString(args, 'extension'), types));
      }
      final paths = requireStringList(args, 'paths', maxLength: 20);
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
        final file = File(_variantPath(key, type));
        try {
          if (!await file.exists()) {
            out.add({'path': rel, 'exists': false, 'text': ''});
            continue;
          }
          final text = await file.readAsString();
          out.add({
            'path': rel,
            'exists': true,
            'text': text.length > _maxCaptionRead
                ? text.substring(0, _maxCaptionRead)
                : text,
            if (text.length > _maxCaptionRead) 'truncated': true,
          });
        } catch (e) {
          out.add({'path': rel, 'error': 'cannot read: $e'});
        }
      }
      // Pinned for the same reason as read_captions: a conversion sweep
      // reads sources once and then writes for many turns.
      return toolOk({
        'extension': type.extension,
        'captions': out,
      }, pinned: true);
    },
  ),
  AgentTool(
    isWrite: true,
    spec: const AgentToolSpec(
      name: 'write_caption_file',
      description:
          'Overwrite one image\'s caption file of a specific caption type '
          'with exactly the given text — how a caption generated from '
          'another type gets written. The text is stored verbatim (prose '
          'stays prose), except that writing a ".json" type rejects text '
          'that does not parse as JSON. When restructuring tags into '
          'another format must not lose or invent any, set '
          'expect_tags_from: the write is then rejected unless its tags '
          'exactly match the source caption\'s. Writing the *active* type '
          'behaves exactly like write_caption. Undoable.',
      parametersSchema: {
        'type': 'object',
        'properties': {
          'path': {
            'type': 'string',
            'description': 'image path as returned by list_images',
          },
          'extension': {
            'type': 'string',
            'description': 'a configured caption extension (e.g. ".ntxt")',
          },
          'text': {'type': 'string'},
          'expect_tags_from': {
            'type': 'string',
            'description':
                'a configured caption extension (e.g. ".txt"): reject the '
                'write unless the tags found in the new text — every JSON '
                'string value for a ".json" target, the comma-separated '
                'tags otherwise — exactly match that source caption\'s '
                'tags. Set it whenever converting one type into another '
                'must not lose or invent tags.',
          },
          'ignore_keys': {
            'type': 'array',
            'items': {'type': 'string'},
            'description':
                'for a ".json" target with expect_tags_from: keys whose '
                'values are not tags (e.g. a natural-language field) and '
                'are excluded from the comparison',
          },
        },
        'required': ['path', 'extension', 'text'],
      },
    ),
    handler: guardBusy(tagOps, (args) async {
      final root = deps.rootDir();
      if (root == null) return toolError('no dataset directory is open');
      final types = deps.captionTypes();
      final type = _findType(types, requireString(args, 'extension'));
      if (type == null) {
        return toolError(_unknownType(requireString(args, 'extension'), types));
      }
      final rel = requireString(args, 'path');
      final text = args['text'];
      if (text is! String) {
        return toolError('missing required string parameter "text"');
      }
      final d = deps.dataset;
      final key = resolveImageKey(d, root, rel);
      if (key == null) {
        return toolError('image ${notFoundMessage(d, rel)}');
      }

      // A .json caption that does not parse would poison whatever consumes
      // it downstream, so it is rejected before anything touches the disk.
      dynamic decoded;
      final isJson = type.extension == '.json';
      if (isJson) {
        try {
          decoded = jsonDecode(text);
        } on FormatException catch (e) {
          return toolError(
            'nothing was written for $rel: the text is not valid JSON — '
            '${e.message}${e.offset == null ? '' : ' (offset ${e.offset})'}',
          );
        }
      }

      int? verifiedTags;
      final expectFrom = optString(args, 'expect_tags_from');
      if (expectFrom != null) {
        final guard = await _checkLossless(
          deps: deps,
          types: types,
          target: type,
          sourceExtension: expectFrom,
          key: key,
          rel: rel,
          text: text,
          decoded: decoded,
          isJson: isJson,
          ignoreKeys: optStringList(args, 'ignore_keys').toSet(),
        );
        if (guard.error != null) return guard.error!;
        verifiedTags = guard.verified;
      }

      // The active type's file is what the dataset state, the editor and the
      // undo replay all track; route through the same path as write_caption
      // so none of them fall out of sync.
      if (type.extension == d.captionExtension) {
        final result = await tagOps.rewriteOne(
          key,
          text,
          label: 'AI: write ${p.basename(key)}',
        );
        if (result.failed) {
          return toolError('nothing was written for $rel: ${result.error}');
        }
        return toolOk({
          'extension': type.extension,
          'written': result.written,
          'unchanged': result.unchanged,
          'tags_verified': ?verifiedTags,
        });
      }

      final captionPath = _variantPath(key, type);
      final file = File(captionPath);
      var before = '';
      try {
        if (await file.exists()) {
          before = await file.readAsString();
        }
      } catch (e) {
        return toolError(
          'nothing was written for $rel: cannot read "$captionPath": $e',
        );
      }
      if (before == text) {
        return toolOk({
          'extension': type.extension,
          'written': false,
          'unchanged': true,
          'tags_verified': ?verifiedTags,
        });
      }
      try {
        await file.writeAsString(text);
      } catch (e) {
        return toolError(
          'nothing was written for $rel: cannot write "$captionPath": $e',
        );
      }
      tagOps.pushOperation(
        TagOperation(
          label: 'AI: write ${p.basename(captionPath)}',
          edits: [
            CaptionEdit(
              imagePath: key,
              captionPath: captionPath,
              before: before,
              after: text,
            ),
          ],
        ),
      );
      return toolOk({
        'extension': type.extension,
        'written': true,
        'unchanged': false,
        'tags_verified': ?verifiedTags,
      });
    }),
  ),
];

/// The outcome of the expect_tags_from guard: an error to return verbatim,
/// or the number of source tags the new text was verified against.
typedef _LosslessCheck = ({AgentToolResult? error, int verified});

/// Verifies that the caption text about to be written carries exactly the
/// tags of the image's [sourceExtension] caption — the machine guarantee
/// behind "convert without losing or inventing tags".
///
/// Matching folds case and underscore style (via [matchPermutation]), so a
/// restyled spelling still counts as the same tag. Order is deliberately not
/// checked: a conversion regroups tags by design.
Future<_LosslessCheck> _checkLossless({
  required DatasetToolsDeps deps,
  required List<CaptionType> types,
  required CaptionType target,
  required String sourceExtension,
  required String key,
  required String rel,
  required String text,
  required dynamic decoded,
  required bool isJson,
  required Set<String> ignoreKeys,
}) async {
  final source = _findType(types, sourceExtension);
  if (source == null) {
    return (error: toolError(_unknownType(sourceExtension, types)), verified: 0);
  }
  // Prose has no tag grammar on either side of the comparison.
  if (source.prose) {
    return (
      error: toolError(
        'expect_tags_from needs a tag-style caption type; '
        '"${source.extension}" is prose',
      ),
      verified: 0,
    );
  }
  if (!isJson && target.prose) {
    return (
      error: toolError(
        'expect_tags_from cannot verify a prose target '
        '("${target.extension}"); it works for ".json" and tag-style types',
      ),
      verified: 0,
    );
  }

  final d = deps.dataset;
  List<String> sourceTags;
  if (source.extension == d.captionExtension) {
    sourceTags = d.tagsOf(key);
  } else {
    try {
      final file = File(_variantPath(key, source));
      sourceTags = await file.exists()
          ? parseTagText(await file.readAsString())
          : const [];
    } catch (e) {
      return (
        error: toolError(
          'nothing was written for $rel: cannot read its '
          '${source.extension} caption: $e',
        ),
        verified: 0,
      );
    }
  }

  final writtenTags = isJson
      ? _jsonTags(decoded, ignoreKeys)
      : parseTagText(text);
  final match = matchPermutation(sourceTags, writtenTags);
  if (match.unknown.isNotEmpty || match.missing.isNotEmpty) {
    return (
      error: toolError(
        'nothing was written: the new ${target.extension} caption does not '
        'carry the same tags as $rel\'s ${source.extension} caption'
        '${match.missing.isEmpty ? '' : '; lost: ${match.missing.join(", ")}'}'
        '${match.unknown.isEmpty ? '' : '; invented or duplicated: '
                  '${match.unknown.join(", ")}'}'
        '. The source\'s ${sourceTags.length} tags are: '
        '${sourceTags.join(", ")}',
      ),
      verified: 0,
    );
  }
  return (error: null, verified: sourceTags.length);
}

/// Every tag carried by a decoded JSON caption: string leaves are split by
/// the tag grammar (so both `["a", "b"]` and `"a, b"` styles count their
/// tags), subtrees under [ignoreKeys] are skipped, and non-string leaves
/// carry none.
List<String> _jsonTags(dynamic node, Set<String> ignoreKeys) {
  final out = <String>[];
  void walk(dynamic n) {
    if (n is String) {
      out.addAll(parseTagText(n));
    } else if (n is List) {
      n.forEach(walk);
    } else if (n is Map) {
      n.forEach((k, v) {
        if (!ignoreKeys.contains(k)) walk(v);
      });
    }
  }

  walk(node);
  return out;
}

String _variantPath(String imagePath, CaptionType type) =>
    '${p.withoutExtension(imagePath)}${type.extension}';

/// Whether the image has a non-empty caption file of this type. The active
/// type answers from the dataset state (the scan's authority); other types
/// are checked on disk, with a non-empty file as the proxy for "captioned".
Future<bool> _hasVariant(
  DatasetState dataset,
  CaptionType type,
  String imagePath,
) async {
  if (type.extension == dataset.captionExtension) {
    return dataset.hasCaption(imagePath);
  }
  final file = File(_variantPath(imagePath, type));
  try {
    return await file.exists() && await file.length() > 0;
  } catch (_) {
    return false;
  }
}

/// Resolves a model-supplied extension (with or without the dot, any case)
/// against the enabled types.
CaptionType? _findType(List<CaptionType> types, String extension) {
  var normalized = extension.trim().toLowerCase();
  if (!normalized.startsWith('.')) normalized = '.$normalized';
  for (final t in types) {
    if (t.extension == normalized) return t;
  }
  return null;
}

String _unknownType(String extension, List<CaptionType> types) =>
    '"$extension" is not a configured caption type; available: '
    '${types.map((t) => '${t.extension} (${t.label})').join(', ')}';
