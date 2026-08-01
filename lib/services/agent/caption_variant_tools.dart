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
          'that does not parse as JSON. JSON string values carry plain '
          'parentheses — never a caption\'s backslash-escaped \\( style. '
          'When restructuring tags into '
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
  AgentTool(
    isWrite: true,
    spec: const AgentToolSpec(
      name: 'convert_captions_to_json',
      description:
          'Convert MANY tag captions into a structured JSON caption type '
          'in one call — always prefer this over looping '
          'write_caption_file. You describe the JSON shape once (the '
          'ordered fields, fixed values, and a tag→field assignment) and '
          'the tool assembles each image\'s JSON itself, so the output is '
          'always valid JSON, keeps the field order, and can neither lose '
          'nor invent a tag. Caption-style backslash escapes (\\( \\)) '
          'are stripped from tag values — JSON carries plain parentheses. '
          'Tags not named in assign go to unassigned_field, and the '
          'result lists the distinct tags that took that route so you can '
          'audit the assignment. Images that already have a non-empty '
          'target file are skipped unless overwrite is set. Undoable as '
          'one operation.',
      parametersSchema: {
        'type': 'object',
        'properties': {
          'source_extension': {
            'type': 'string',
            'description':
                'the tag-style caption type to read (e.g. ".txt")',
          },
          'target_extension': {
            'type': 'string',
            'description':
                'the configured caption type to write (e.g. ".json"); '
                'must be neither the source nor the active type',
          },
          'fields': {
            'type': 'array',
            'items': {
              'type': 'object',
              'properties': {
                'name': {'type': 'string'},
                'kind': {
                  'type': 'string',
                  'enum': ['string', 'array'],
                },
              },
              'required': ['name', 'kind'],
            },
            'description':
                'the JSON fields in output order; a "string" field takes '
                'at most one tag per image (empty string when none), an '
                '"array" field any number',
          },
          'constants': {
            'type': 'object',
            'description':
                'field name → fixed JSON value written verbatim for '
                'every image (e.g. {"quality": [""], "artist": "", '
                '"nl": ""}); such a field takes no tags',
          },
          'assign': {
            'type': 'object',
            'description':
                'tag → field name; matching folds case and '
                'underscore/space style. Build it from get_tag_stats so '
                'every tag of the dataset is considered.',
          },
          'unassigned_field': {
            'type': 'string',
            'description':
                'the array field that receives tags not named in assign '
                '(the catch-all, e.g. "tags")',
          },
          'include_tags': {
            'type': 'array',
            'items': {'type': 'string'},
          },
          'exclude_tags': {
            'type': 'array',
            'items': {'type': 'string'},
          },
          'name_query': {'type': 'string'},
          'overwrite': {
            'type': 'boolean',
            'description':
                'false (default): skip images that already have a '
                'non-empty target file; true: rebuild them too',
          },
        },
        'required': [
          'source_extension',
          'target_extension',
          'fields',
          'unassigned_field',
        ],
      },
    ),
    handler: guardBusy(tagOps, (args) async {
      final root = deps.rootDir();
      if (root == null) return toolError('no dataset directory is open');
      final types = deps.captionTypes();
      final d = deps.dataset;

      final source = _findType(types, requireString(args, 'source_extension'));
      if (source == null) {
        return toolError(
          _unknownType(requireString(args, 'source_extension'), types),
        );
      }
      if (source.prose) {
        return toolError(
          'the source must be a tag-style caption type; '
          '"${source.extension}" is prose',
        );
      }
      final target = _findType(types, requireString(args, 'target_extension'));
      if (target == null) {
        return toolError(
          _unknownType(requireString(args, 'target_extension'), types),
        );
      }
      if (target.extension == source.extension) {
        return toolError('the source and target are the same caption type');
      }
      if (target.extension == d.captionExtension) {
        return toolError(
          'the target is the active caption type; this converter only '
          'writes non-active types so the tag index stays a tag index — '
          'the user would have to switch the active type first',
        );
      }

      // The JSON shape: field order, kinds, fixed values, tag routing. All
      // of it is validated up front — a bad shape must fail the whole call,
      // never image #57 of a sweep.
      final rawFields = args['fields'];
      if (rawFields is! List || rawFields.isEmpty) {
        return toolError('missing required array parameter "fields"');
      }
      final fieldKinds = <String, String>{};
      for (final f in rawFields) {
        if (f is! Map) {
          return toolError(
            'every "fields" entry must be an object with "name" and "kind"',
          );
        }
        final name = f['name'];
        final kind = f['kind'];
        if (name is! String || name.trim().isEmpty) {
          return toolError('every "fields" entry needs a non-empty "name"');
        }
        if (kind != 'string' && kind != 'array') {
          return toolError(
            'field "$name": "kind" must be "string" or "array"',
          );
        }
        if (fieldKinds.containsKey(name)) {
          return toolError('duplicate field "$name"');
        }
        fieldKinds[name] = kind;
      }

      final rawConstants = args['constants'] ?? const <String, dynamic>{};
      if (rawConstants is! Map) {
        return toolError(
          '"constants" must be an object mapping field names to values',
        );
      }
      final constants = <String, dynamic>{};
      for (final entry in rawConstants.entries) {
        final name = entry.key;
        if (name is! String || !fieldKinds.containsKey(name)) {
          return toolError('constant "$name" is not a declared field');
        }
        constants[name] = entry.value;
      }

      final unassignedField = requireString(args, 'unassigned_field');
      if (!fieldKinds.containsKey(unassignedField)) {
        return toolError(
          'unassigned_field "$unassignedField" is not a declared field',
        );
      }
      if (fieldKinds[unassignedField] != 'array') {
        return toolError(
          'unassigned_field "$unassignedField" must be an "array" field',
        );
      }
      if (constants.containsKey(unassignedField)) {
        return toolError(
          'unassigned_field "$unassignedField" cannot also be a constant',
        );
      }

      final rawAssign = args['assign'] ?? const <String, dynamic>{};
      if (rawAssign is! Map) {
        return toolError(
          '"assign" must be an object mapping tags to field names',
        );
      }
      final assign = <String, String>{};
      for (final entry in rawAssign.entries) {
        final tag = entry.key;
        final field = entry.value;
        if (tag is! String || field is! String) {
          return toolError(
            '"assign" must map tag strings to field-name strings',
          );
        }
        if (!fieldKinds.containsKey(field)) {
          return toolError(
            'assign: "$tag" → "$field", which is not a declared field',
          );
        }
        if (constants.containsKey(field)) {
          return toolError(
            'assign: "$tag" → "$field", which already has a constant value',
          );
        }
        final folded = tagLookupKey(tag);
        final previous = assign[folded];
        if (previous != null && previous != field) {
          return toolError(
            'assign: "$tag" is assigned to both "$previous" and "$field"',
          );
        }
        assign[folded] = field;
      }

      final files = filterDatasetFiles(
        d,
        include: optStringList(args, 'include_tags'),
        exclude: optStringList(args, 'exclude_tags'),
        untaggedOnly: false,
        nameQuery: optString(args, 'name_query')?.toLowerCase(),
      );
      final overwrite = optBool(args, 'overwrite');

      const encoder = JsonEncoder.withIndent('  ');
      var written = 0;
      var unchanged = 0;
      var skippedExisting = 0;
      var skippedUncaptioned = 0;
      final failures = <({String path, String error})>[];
      final unassignedSeen = <String>{};
      final edits = <CaptionEdit>[];

      for (final f in files) {
        final rel = p.relative(f.path, from: root);

        List<String> tags;
        if (source.extension == d.captionExtension) {
          tags = d.tagsOf(f.path);
        } else {
          try {
            final sourceFile = File(_variantPath(f.path, source));
            tags = await sourceFile.exists()
                ? parseTagText(await sourceFile.readAsString())
                : const [];
          } catch (e) {
            failures.add((path: rel, error: 'cannot read source: $e'));
            continue;
          }
        }
        if (tags.isEmpty) {
          skippedUncaptioned++;
          continue;
        }

        final targetFile = File(_variantPath(f.path, target));
        var before = '';
        try {
          if (await targetFile.exists()) {
            before = await targetFile.readAsString();
            if (!overwrite && before.trim().isNotEmpty) {
              skippedExisting++;
              continue;
            }
          }
        } catch (e) {
          failures.add((path: rel, error: 'cannot read target: $e'));
          continue;
        }

        final buckets = <String, List<String>>{};
        for (final tag in tags) {
          final field = assign[tagLookupKey(tag)];
          if (field == null) unassignedSeen.add(tag);
          (buckets[field ?? unassignedField] ??= []).add(
            unescapeTagParens(tag),
          );
        }
        String? collision;
        for (final bucket in buckets.entries) {
          if (fieldKinds[bucket.key] == 'string' && bucket.value.length > 1) {
            collision =
                'string field "${bucket.key}" got ${bucket.value.length} '
                'tags: ${bucket.value.join(", ")}';
            break;
          }
        }
        if (collision != null) {
          failures.add((path: rel, error: collision));
          continue;
        }

        final out = <String, dynamic>{};
        for (final field in fieldKinds.entries) {
          if (constants.containsKey(field.key)) {
            out[field.key] = constants[field.key];
            continue;
          }
          final bucket = buckets[field.key] ?? const <String>[];
          out[field.key] = field.value == 'string'
              ? (bucket.isEmpty ? '' : bucket.first)
              : bucket;
        }
        final text = encoder.convert(out);
        if (text == before) {
          unchanged++;
          continue;
        }
        try {
          await targetFile.writeAsString(text);
        } catch (e) {
          failures.add((path: rel, error: 'cannot write: $e'));
          continue;
        }
        written++;
        edits.add(
          CaptionEdit(
            imagePath: f.path,
            captionPath: targetFile.path,
            before: before,
            after: text,
          ),
        );
      }

      if (edits.isNotEmpty) {
        tagOps.pushOperation(
          TagOperation(
            label:
                'AI: convert ${edits.length} captions to ${target.extension}',
            edits: edits,
          ),
        );
      }

      const sample = 5;
      if (written == 0 && failures.isNotEmpty) {
        return toolError(
          'nothing was written: ${failures.length} image(s) failed — '
          '${failures.take(sample).map((f) => '${f.path}: ${f.error}').join('; ')}'
          '${failures.length > sample ? '; …' : ''}',
        );
      }
      const unassignedSample = 100;
      final unassignedList = unassignedSeen.toList();
      return toolOk({
        'scope': scopeLabel(d),
        'source_extension': source.extension,
        'target_extension': target.extension,
        'written': written,
        'unchanged': unchanged,
        'skipped_existing': skippedExisting,
        'skipped_uncaptioned': skippedUncaptioned,
        if (failures.isNotEmpty) ...{
          'failed_images': failures.length,
          'failures': [
            for (final f in failures.take(sample))
              {'path': f.path, 'error': f.error},
          ],
          'failures_truncated': failures.length > sample,
        },
        'unassigned_tags_seen': unassignedList.take(unassignedSample).toList(),
        if (unassignedList.length > unassignedSample)
          'unassigned_tags_truncated': true,
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
