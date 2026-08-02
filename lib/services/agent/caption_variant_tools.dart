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
        missingType = findCaptionType(types, missingExt);
        if (missingType == null) {
          return toolError(unknownCaptionType(missingExt, types));
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
      final type = findCaptionType(types, requireString(args, 'extension'));
      if (type == null) {
        return toolError(
          unknownCaptionType(requireString(args, 'extension'), types),
        );
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
        final file = File(captionVariantPath(key, type));
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
          'stays prose), except that writing a JSON-format type rejects '
          'text that does not parse as JSON. JSON string values carry '
          'plain parentheses — never a caption\'s backslash-escaped \\( '
          'style. When restructuring tags into '
          'another format must not lose or invent any, set '
          'expect_tags_from: the write is then rejected unless its tags '
          'exactly match the source caption\'s; to reshape a caption into '
          'itself, set expect_same_tags and it is checked against the '
          'file\'s own current content. Writing the *active* type '
          'behaves exactly like write_caption. To reshape many JSON '
          'captions use restructure_json_captions — never loop this tool '
          'over a dataset. Undoable.',
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
                'string value for a JSON-format target, the '
                'comma-separated tags otherwise — exactly match that '
                'source caption\'s tags. Set it whenever converting one '
                'type into another must not lose or invent tags.',
          },
          'expect_same_tags': {
            'type': 'boolean',
            'description':
                'reject the write unless the new text carries exactly the '
                'tags this caption file already has — the guard for '
                'reshaping a caption in place (reordering JSON fields, '
                'moving tags between them). Cannot be combined with '
                'expect_tags_from.',
          },
          'ignore_keys': {
            'type': 'array',
            'items': {'type': 'string'},
            'description':
                'for a JSON-format target with expect_tags_from or '
                'expect_same_tags: keys whose values are not tags (e.g. a '
                'natural-language field) and are excluded from the '
                'comparison',
          },
        },
        'required': ['path', 'extension', 'text'],
      },
    ),
    handler: guardBusy(tagOps, (args) async {
      final root = deps.rootDir();
      if (root == null) return toolError('no dataset directory is open');
      final types = deps.captionTypes();
      final type = findCaptionType(types, requireString(args, 'extension'));
      if (type == null) {
        return toolError(
          unknownCaptionType(requireString(args, 'extension'), types),
        );
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

      // A JSON caption that does not parse would poison whatever consumes
      // it downstream, so it is rejected before anything touches the disk.
      // The type's configured format decides, not its extension.
      dynamic decoded;
      final isJson = type.format == CaptionFormat.json;
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
      final ignoreKeys = optStringList(args, 'ignore_keys').toSet();
      final expectFrom = optString(args, 'expect_tags_from');
      final expectSame = optBool(args, 'expect_same_tags');
      if (expectSame && expectFrom != null) {
        return toolError(
          'nothing was written: expect_same_tags and expect_tags_from '
          'compare against different sources — set only one',
        );
      }
      if (expectSame) {
        final guard = await _checkUnchangedTags(
          target: type,
          key: key,
          rel: rel,
          decoded: decoded,
          isJson: isJson,
          text: text,
          ignoreKeys: ignoreKeys,
        );
        if (guard.error != null) return guard.error!;
        verifiedTags = guard.verified;
      }
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
          ignoreKeys: ignoreKeys,
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

      final captionPath = captionVariantPath(key, type);
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
          'audit the assignment. An Anima Tag source works too: set '
          'nl_field to carry each caption\'s trailing sentence into that '
          'JSON field, or leave it unset and the result reports how many '
          'descriptions were dropped. Images that already have a '
          'non-empty target file are skipped unless overwrite is set. '
          'Undoable as one operation.',
      parametersSchema: {
        'type': 'object',
        'properties': {
          'source_extension': {
            'type': 'string',
            'description':
                'the tag-list caption type to read — WD14 tags or Anima '
                'Tag (e.g. ".txt")',
          },
          'target_extension': {
            'type': 'string',
            'description':
                'a configured caption type whose format is JSON (e.g. '
                '".json"); must not be the active type',
          },
          'nl_field': {
            'type': 'string',
            'description':
                'Anima Tag sources only: the declared "string" field that '
                'receives each caption\'s trailing natural-language '
                'sentence (e.g. "nl"). Images without one get "". Leave '
                'it unset to drop the descriptions instead.',
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

      final source = findCaptionType(
        types,
        requireString(args, 'source_extension'),
      );
      if (source == null) {
        return toolError(
          unknownCaptionType(requireString(args, 'source_extension'), types),
        );
      }
      if (!source.format.isTagList) {
        return toolError(
          'the source must be a tag-list caption type (WD14 tags or Anima '
          'Tag); "${source.extension}" is ${source.format.name}',
        );
      }
      final target = findCaptionType(
        types,
        requireString(args, 'target_extension'),
      );
      if (target == null) {
        return toolError(
          unknownCaptionType(requireString(args, 'target_extension'), types),
        );
      }
      if (target.format != CaptionFormat.json) {
        return toolError(
          'the target\'s configured format is ${target.format.name}, not '
          'JSON — the user sets a caption type\'s format in the caption '
          'type settings',
        );
      }
      if (target.extension == d.captionExtension) {
        return toolError(
          'the target is the active caption type; this converter only '
          'writes non-active types — the user would have to switch the '
          'active type first',
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
          return toolError('field "$name": "kind" must be "string" or "array"');
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

      // The Anima Tag tail is per-image prose, so it can only travel into a
      // string field of its own — not a constant (which is one value for the
      // whole dataset) and not the tag catch-all.
      final nlField = optString(args, 'nl_field');
      if (nlField != null) {
        if (source.format != CaptionFormat.animaTag) {
          return toolError(
            'nl_field only applies to an Anima Tag source; '
            '"${source.extension}" is ${source.format.name} and carries no '
            'natural-language part',
          );
        }
        if (!fieldKinds.containsKey(nlField)) {
          return toolError('nl_field "$nlField" is not a declared field');
        }
        if (fieldKinds[nlField] != 'string') {
          return toolError(
            'nl_field "$nlField" must be a "string" field — a description '
            'is one sentence, not a tag list',
          );
        }
        if (constants.containsKey(nlField)) {
          return toolError(
            'nl_field "$nlField" cannot also be a constant: it takes a '
            'different value per image',
          );
        }
        if (nlField == unassignedField) {
          return toolError(
            'nl_field "$nlField" cannot also be unassigned_field',
          );
        }
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
      // Reported either way: carrying descriptions across is the point of
      // nl_field, and dropping them silently is the failure mode it exists
      // to make visible.
      var carriedDescriptions = 0;
      var droppedDescriptions = 0;
      final failures = <({String path, String error})>[];
      final unassignedSeen = <String>{};
      final edits = <CaptionEdit>[];

      for (final f in files) {
        final rel = p.relative(f.path, from: root);

        List<String> parts;
        if (source.extension == d.captionExtension) {
          parts = d.tagsOf(f.path);
        } else {
          try {
            final sourceFile = File(captionVariantPath(f.path, source));
            parts = await sourceFile.exists()
                ? parseCaptionText(
                    await sourceFile.readAsString(),
                    format: source.format,
                  )
                : const [];
          } catch (e) {
            failures.add((path: rel, error: 'cannot read source: $e'));
            continue;
          }
        }
        // An Anima Tag caption's trailing sentence is not a tag: it never
        // enters the buckets, and it only reaches the document through
        // nl_field.
        final split = source.format == CaptionFormat.animaTag
            ? splitAnimaParts(parts)
            : (tags: parts, nl: null);
        final tags = split.tags;
        final sourceNl = split.nl;
        if (tags.isEmpty && sourceNl == null) {
          skippedUncaptioned++;
          continue;
        }
        if (sourceNl != null && nlField == null) droppedDescriptions++;

        final targetFile = File(captionVariantPath(f.path, target));
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
          if (field.key == nlField) {
            out[field.key] = sourceNl ?? '';
            if (sourceNl != null) carriedDescriptions++;
            continue;
          }
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
        if (nlField != null) 'descriptions_carried': carriedDescriptions,
        if (droppedDescriptions > 0)
          'descriptions_dropped': droppedDescriptions,
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
  _convertCaptionsToTags(deps, tagOps),
];

/// Batch converter between the two tag-list formats — WD14 tags and Anima
/// Tag — in either direction and in one call.
///
/// The tag-level batch tools ([TagOps]) can only ever touch the *active*
/// caption type, so generating one type from another used to mean looping
/// write_caption_file once per image. Every rule such a conversion applies
/// (drop these tags, strip an `@`, escape parentheses, put the trigger word
/// first) is a dataset-wide rule, not a per-image judgement, which made that
/// loop pure waste: the model decided the rules once and then paid an LLM
/// round trip per image to apply them.
AgentTool _convertCaptionsToTags(
  DatasetToolsDeps deps,
  TagOps tagOps,
) => AgentTool(
  isWrite: true,
  spec: const AgentToolSpec(
    name: 'convert_captions_to_tags',
    description:
        'Convert MANY captions from one tag-list caption type into '
        'another (WD14 tags ⇄ Anima Tag) in one call — always prefer '
        'this over looping write_caption_file, which costs a round '
        'trip per image to apply rules you already decided once. You '
        'give the rules once: drop tags, rename tags, normalise '
        'spelling, order by priority, prepend a trigger word. Nothing '
        'is invented — every output tag comes from the source or from '
        'prepend. An Anima Tag source\'s trailing sentence is carried '
        'over when the target is Anima Tag too, and dropped (and '
        'counted in the result) when the target is plain tags. The '
        'result reports each dropped and renamed tag with how many '
        'captions it came out of, so the whole conversion can be '
        'audited from one answer. The target may be the active type. '
        'Images that already have a non-empty target file are skipped '
        'unless overwrite is set. Undoable as one operation.',
    parametersSchema: {
      'type': 'object',
      'properties': {
        'source_extension': {
          'type': 'string',
          'description': 'the tag-list caption type to read (e.g. ".atxt")',
        },
        'target_extension': {
          'type': 'string',
          'description':
              'the tag-list caption type to write (e.g. ".txt"); may '
              'be the active type, but not the source',
        },
        'drop': {
          'type': 'array',
          'items': {'type': 'string'},
          'description':
              'tags to remove entirely (quality, rating, year, meta…); '
              'matching folds case and underscore/space style',
        },
        'rename': {
          'type': 'object',
          'description':
              'tag → replacement tag, e.g. mapping "@wlop" to "wlop". '
              'Matching folds case and underscore/space style. Use '
              'drop to remove a tag, not a rename to an empty string.',
        },
        'spacing': {
          'type': 'string',
          'description':
              '"spaces" rewrites long_hair to "long hair", '
              '"underscores" the other way; omit to keep each tag\'s '
              'own spelling. One style for the whole dataset is what '
              'training scripts expect.',
        },
        'parentheses': {
          'type': 'string',
          'description':
              '"escape" writes danbooru variants as '
              'hatsune miku \\(racing\\) — required for plain-text '
              'captions, where bare parentheses are prompt attention '
              'syntax; "plain" strips the backslashes; omit to leave '
              'them as they are',
        },
        'priority': {
          'type': 'array',
          'items': {'type': 'string'},
          'description':
              'tags in the order they should appear; every tag not '
              'named keeps its relative position after them. Same '
              'semantics as sort_captions_everywhere.',
        },
        'prepend': {
          'type': 'array',
          'items': {'type': 'string'},
          'description':
              'tags to put at the very front of every caption, in this '
              'order — the LoRA trigger word. A caption that already '
              'has one gets it moved, not duplicated.',
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
      'required': ['source_extension', 'target_extension'],
    },
  ),
  handler: guardBusy(tagOps, (args) async {
    final root = deps.rootDir();
    if (root == null) return toolError('no dataset directory is open');
    final types = deps.captionTypes();
    final d = deps.dataset;

    final source = findCaptionType(
      types,
      requireString(args, 'source_extension'),
    );
    if (source == null) {
      return toolError(
        unknownCaptionType(requireString(args, 'source_extension'), types),
      );
    }
    final target = findCaptionType(
      types,
      requireString(args, 'target_extension'),
    );
    if (target == null) {
      return toolError(
        unknownCaptionType(requireString(args, 'target_extension'), types),
      );
    }
    for (final type in [source, target]) {
      if (!type.format.isTagList) {
        return toolError(
          'both types must be tag-list caption types (WD14 tags or '
          'Anima Tag); "${type.extension}" is ${type.format.name}'
          '${type.format == CaptionFormat.json ? ' — use convert_captions_to_json or '
                    'restructure_json_captions for JSON' : ''}',
        );
      }
    }
    if (source.extension == target.extension) {
      return toolError(
        'source and target are the same caption type '
        '("${source.extension}"); to rewrite a type in place use the '
        'tag tools on the active type instead',
      );
    }

    // Every rule is validated before a single file is touched: a bad
    // rule must fail the whole call, never image #57 of a sweep.
    final spacing = optString(args, 'spacing')?.toLowerCase();
    if (spacing != null && spacing != 'spaces' && spacing != 'underscores') {
      return toolError('"spacing" must be "spaces" or "underscores"');
    }
    final parens = optString(args, 'parentheses')?.toLowerCase();
    if (parens != null && parens != 'escape' && parens != 'plain') {
      return toolError('"parentheses" must be "escape" or "plain"');
    }

    final drop = {
      for (final tag in optStringList(args, 'drop', maxLength: 500))
        tagLookupKey(tag),
    };
    final rawRename = args['rename'] ?? const <String, dynamic>{};
    if (rawRename is! Map) {
      return toolError(
        '"rename" must be an object mapping tags to replacement tags',
      );
    }
    final rename = <String, String>{};
    for (final entry in rawRename.entries) {
      final from = entry.key;
      final to = entry.value;
      if (from is! String || to is! String) {
        return toolError('"rename" must map tag strings to tag strings');
      }
      if (to.trim().isEmpty) {
        return toolError('rename: "$from" → "" — use drop to remove a tag');
      }
      rename[tagLookupKey(from)] = to.trim();
    }
    final priority = <String, int>{};
    for (final (i, tag) in optStringList(
      args,
      'priority',
      maxLength: 500,
    ).indexed) {
      priority.putIfAbsent(tagLookupKey(tag), () => i);
    }
    final prepend = optStringList(args, 'prepend', maxLength: 20);

    /// The whole per-tag rewrite, in the one order that composes: undo
    /// any existing escaping first so spacing sees plain text, then the
    /// spelling style, then escaping last so nothing re-escapes a
    /// backslash it just wrote.
    String respell(String tag) {
      var out = unescapeTagParens(tag);
      if (spacing == 'spaces') out = out.replaceAll('_', ' ');
      if (spacing == 'underscores') {
        out = out.trim().replaceAll(RegExp(r'\s+'), '_');
      }
      if (parens == 'escape') {
        out = out.replaceAll('(', r'\(').replaceAll(')', r'\)');
      }
      return out;
    }

    final files = filterDatasetFiles(
      d,
      include: optStringList(args, 'include_tags'),
      exclude: optStringList(args, 'exclude_tags'),
      untaggedOnly: false,
      nameQuery: optString(args, 'name_query')?.toLowerCase(),
    );
    final overwrite = optBool(args, 'overwrite');
    final activeTarget = target.extension == d.captionExtension;
    // The editor's pending edits would otherwise be written over this
    // sweep's result a moment later — the same flush every TagOps
    // mutation does.
    if (activeTarget) await tagOps.beforeMutate?.call();

    var written = 0;
    var unchanged = 0;
    var skippedExisting = 0;
    var skippedUncaptioned = 0;
    var droppedDescriptions = 0;
    var carriedDescriptions = 0;
    final dropped = <String, int>{};
    final renamed = <String, int>{};
    final failures = <({String path, String error})>[];
    final edits = <CaptionEdit>[];

    for (final f in files) {
      final rel = p.relative(f.path, from: root);

      List<String> parts;
      if (source.extension == d.captionExtension) {
        parts = d.tagsOf(f.path);
      } else {
        try {
          final sourceFile = File(captionVariantPath(f.path, source));
          parts = await sourceFile.exists()
              ? parseCaptionText(
                  await sourceFile.readAsString(),
                  format: source.format,
                )
              : const [];
        } catch (e) {
          failures.add((path: rel, error: 'cannot read source: $e'));
          continue;
        }
      }
      final split = source.format == CaptionFormat.animaTag
          ? splitAnimaParts(parts)
          : (tags: parts, nl: null);
      if (split.tags.isEmpty && split.nl == null) {
        skippedUncaptioned++;
        continue;
      }
      // A description only survives into a format that has somewhere to
      // put it. Losing it is legitimate here — it is what "convert to
      // WD14" means — but it is never silent.
      final nl = target.format == CaptionFormat.animaTag ? split.nl : null;
      if (split.nl != null) {
        nl == null ? droppedDescriptions++ : carriedDescriptions++;
      }

      final kept = <String>[];
      for (final tag in split.tags) {
        final key = tagLookupKey(tag);
        if (drop.contains(key)) {
          dropped[tag] = (dropped[tag] ?? 0) + 1;
          continue;
        }
        final replacement = rename[key];
        if (replacement != null) renamed[tag] = (renamed[tag] ?? 0) + 1;
        kept.add(respell(replacement ?? tag));
      }

      // Sort, then hoist the trigger words — a prepended tag that the
      // caption already carried must end up in front exactly once, not
      // once in its priority bucket and once at the head.
      final ordered = priority.isEmpty ? kept : _byPriority(kept, priority);
      final head = [for (final tag in prepend) respell(tag)];
      final headKeys = {for (final tag in head) tagLookupKey(tag)};
      final seen = <String>{};
      final finalTags = [
        for (final tag in [
          ...head,
          ...ordered.where((t) => !headKeys.contains(tagLookupKey(t))),
        ])
          if (seen.add(tagLookupKey(tag))) tag,
      ];

      final text = joinCaptionText([
        ...finalTags,
        if (nl != null) '$animaNlPrefix$nl',
      ], format: target.format);

      final targetFile = File(captionVariantPath(f.path, target));
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
          label: 'AI: convert ${edits.length} captions to ${target.extension}',
          edits: edits,
        ),
        // Writing the active type behind the dataset's back would leave
        // the gallery, the tag index and the open editor showing the
        // pre-conversion text.
        syncActiveCaptions: activeTarget,
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
    return toolOk({
      'scope': scopeLabel(d),
      'source_extension': source.extension,
      'target_extension': target.extension,
      'written': written,
      'unchanged': unchanged,
      'skipped_existing': skippedExisting,
      'skipped_uncaptioned': skippedUncaptioned,
      if (carriedDescriptions > 0) 'descriptions_carried': carriedDescriptions,
      if (droppedDescriptions > 0) 'descriptions_dropped': droppedDescriptions,
      // Keyed by the tag as it was spelled in the source, so an entry
      // that never fired is visible by its absence — a drop rule with no
      // count matched nothing and probably names a tag that is not there.
      'dropped_tags': _topCounts(dropped),
      'renamed_tags': _topCounts(renamed),
      if (failures.isNotEmpty) ...{
        'failed_images': failures.length,
        'failures': [
          for (final f in failures.take(sample))
            {'path': f.path, 'error': f.error},
        ],
        'failures_truncated': failures.length > sample,
      },
    });
  }),
);

/// Buckets [tags] by [priority] (folded key → rank), leaving tags it does not
/// name in their relative order at the end. The same rule
/// `sort_captions_everywhere` applies, so a priority list means one thing
/// across the app.
List<String> _byPriority(List<String> tags, Map<String, int> priority) {
  final buckets = <int, List<String>>{};
  final rest = <String>[];
  for (final tag in tags) {
    final rank = priority[tagLookupKey(tag)];
    if (rank == null) {
      rest.add(tag);
    } else {
      (buckets[rank] ??= []).add(tag);
    }
  }
  final ranks = buckets.keys.toList()..sort();
  return [for (final rank in ranks) ...buckets[rank]!, ...rest];
}

/// Counts as a plain map, biggest first and capped — a dataset can carry
/// hundreds of distinct dropped tags and the whole list would crowd out the
/// rest of the answer.
Map<String, int> _topCounts(Map<String, int> counts, {int limit = 60}) {
  final entries = counts.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return {for (final e in entries.take(limit)) e.key: e.value};
}

/// The outcome of a lossless guard (expect_tags_from / expect_same_tags):
/// an error to return verbatim, or the number of source tags the new text
/// was verified against.
typedef _LosslessCheck = ({AgentToolResult? error, int verified});

/// Verifies that the caption text about to be written carries exactly the
/// tags the file *already* holds — the guarantee behind reshaping a caption
/// into itself (reordering a JSON document's fields, moving tags between
/// them) rather than converting one type into another.
///
/// Both sides are read with the same grammar, which for JSON is the raw
/// multiset of string leaves: a restructure that quietly merged a tag
/// appearing under two fields into one did change the document, and must be
/// caught here rather than pass as "same tags". A missing or empty file has
/// no tags, so any non-empty write is rejected — creating a caption is not
/// reshaping one.
Future<_LosslessCheck> _checkUnchangedTags({
  required CaptionType target,
  required String key,
  required String rel,
  required String text,
  required dynamic decoded,
  required bool isJson,
  required Set<String> ignoreKeys,
}) async {
  final path = captionVariantPath(key, target);
  String current;
  try {
    final file = File(path);
    current = await file.exists() ? await file.readAsString() : '';
  } catch (e) {
    return (
      error: toolError(
        'nothing was written for $rel: cannot read "$path" to compare '
        'against: $e',
      ),
      verified: 0,
    );
  }

  List<String> currentTags;
  List<String> writtenTags;
  if (isJson) {
    dynamic before;
    try {
      before = current.trim().isEmpty ? null : jsonDecode(current);
    } on FormatException catch (e) {
      return (
        error: toolError(
          'nothing was written for $rel: its current ${target.extension} '
          'caption is not valid JSON (${e.message}), so there is no tag set '
          'to compare against — drop expect_same_tags to overwrite it',
        ),
        verified: 0,
      );
    }
    currentTags = jsonCaptionTags(before, ignoreKeys: ignoreKeys);
    writtenTags = jsonCaptionTags(decoded, ignoreKeys: ignoreKeys);
  } else {
    currentTags = parseCaptionText(current, format: target.format);
    writtenTags = parseCaptionText(text, format: target.format);
  }

  final match = matchPermutation(currentTags, writtenTags);
  if (match.unknown.isNotEmpty || match.missing.isNotEmpty) {
    return (
      error: toolError(
        'nothing was written: expect_same_tags was set but the new '
        '${target.extension} caption of $rel does not carry the same tags '
        'as the one on disk'
        '${match.missing.isEmpty ? '' : '; lost: ${match.missing.join(", ")}'}'
        '${match.unknown.isEmpty ? '' : '; invented or duplicated: '
                  '${match.unknown.join(", ")}'}'
        '. Its ${currentTags.length} current tags are: '
        '${currentTags.join(", ")}',
      ),
      verified: 0,
    );
  }
  return (error: null, verified: currentTags.length);
}

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
  final source = findCaptionType(types, sourceExtension);
  if (source == null) {
    return (
      error: toolError(unknownCaptionType(sourceExtension, types)),
      verified: 0,
    );
  }
  // Only the tag-list formats have a tag grammar to read the source with.
  if (!source.format.isTagList) {
    return (
      error: toolError(
        'expect_tags_from needs a tag-list caption type; '
        '"${source.extension}" is ${source.format.name}',
      ),
      verified: 0,
    );
  }
  if (!isJson && !target.format.isTagList) {
    return (
      error: toolError(
        'expect_tags_from cannot verify a ${target.format.name} target '
        '("${target.extension}"); it works for JSON-format and tag-list '
        'types',
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
      final file = File(captionVariantPath(key, source));
      sourceTags = await file.exists()
          ? parseCaptionText(await file.readAsString(), format: source.format)
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
  // Same reasoning as for the target below: an Anima Tag source's tail is a
  // sentence, not a tag the conversion has to carry across.
  if (source.format == CaptionFormat.animaTag) {
    sourceTags = splitAnimaParts(sourceTags).tags;
  }

  // An Anima Tag target's natural-language tail is new writing, not a tag the
  // source had to carry, so it is excluded from the comparison — the guard is
  // about tags surviving the conversion, and requiring the tail to match a
  // source tag would make the format impossible to write.
  final writtenTags = isJson
      ? jsonCaptionTags(decoded, ignoreKeys: ignoreKeys)
      : target.format == CaptionFormat.animaTag
      ? splitAnimaParts(parseAnimaTagText(text)).tags
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

String captionVariantPath(String imagePath, CaptionType type) =>
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
  final file = File(captionVariantPath(imagePath, type));
  try {
    return await file.exists() && await file.length() > 0;
  } catch (_) {
    return false;
  }
}

/// Resolves a model-supplied extension (with or without the dot, any case)
/// against the enabled types.
CaptionType? findCaptionType(List<CaptionType> types, String extension) {
  var normalized = extension.trim().toLowerCase();
  if (!normalized.startsWith('.')) normalized = '.$normalized';
  for (final t in types) {
    if (t.extension == normalized) return t;
  }
  return null;
}

String unknownCaptionType(String extension, List<CaptionType> types) =>
    '"$extension" is not a configured caption type; available: '
    '${types.map((t) => '${t.extension} (${t.label})').join(', ')}';
