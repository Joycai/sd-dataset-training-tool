/// `edit_captions`: the one batch tag editor for tag-list caption types.
///
/// It replaces four separate tools — remove_tag_everywhere,
/// replace_tag_everywhere, insert_beside_tag and add_tags_everywhere — that
/// said the same three things (delete, rename, add) in three vocabularies, one
/// verb per tool. The JSON side had already converged on one
/// `edit_json_captions` with `add` / `remove` / `rename`; a model switching
/// between a `.txt` and a `.json` type now meets the same shape on both.
///
/// Two capabilities the four never had come with the merge, because they cost
/// nothing once the sweep is written once: the same
/// include/exclude/name_query filters every other batch tool takes (three of
/// the four could only ever hit the whole scope), and an explicit `extension`,
/// so a *non-active* tag-list type can be edited without asking the user to
/// switch types first — which is what the JSON tools have always allowed.
///
/// Lives in its own file because it needs the caption-type helpers from
/// `caption_variant_tools.dart`, which already imports `dataset_tools.dart`;
/// putting it in the latter would close the import cycle. It is registered
/// unconditionally all the same — it is a core write tool, not a variant one.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import '../../models/caption_type.dart';
import '../../state/tag_ops.dart';
import '../../utils/tag_text.dart';
import 'agent_tools.dart';
import 'caption_variant_tools.dart';
import 'dataset_tools.dart';

/// How many per-image failures travel back in a result.
const int _failureSample = 5;

/// How many distinct tags each of the three counters names back.
const int _countSample = 60;

List<AgentTool> buildCaptionEditTools(DatasetToolsDeps deps, TagOps tagOps) => [
  AgentTool(
    isWrite: true,
    spec: _spec,
    handler: guardBusyExclusive(tagOps, (args) => _edit(deps, tagOps, args)),
  ),
];

const AgentToolSpec _spec = AgentToolSpec(
  name: 'edit_captions',
  description:
      'Add, remove and rename TAGS across MANY captions in one call — the '
      'batch editor for tag-list caption types (WD14 tags and Anima Tag). '
      'Give the rules once and every caption in scope is rewritten: this is '
      'the tool for "delete this tag everywhere", "rename this tag", "give '
      'every image this tag". Matching folds case and underscore/space '
      'style, so "long_hair" and "Long Hair" are the same tag, while each '
      'file keeps its own spelling unless a rename changes it. The result '
      'reports every tag added, removed and renamed with how many captions '
      'it came out of, so the whole edit can be audited from one answer. '
      'Sorting is a different job — use sort_captions_everywhere. For a '
      'JSON caption type use edit_json_captions, which is this tool\'s '
      'counterpart and takes the same add / remove / rename rules. An Anima '
      'Tag caption\'s trailing sentence is never touched. On a '
      'natural-language (prose) type there are no tags: the parts are whole '
      'SENTENCES, so a rule has to name one exactly, punctuation and all '
      '("She wears a red hat, outdoors."), and a rule naming a tag matches '
      'nothing. Undoable as one operation.',
  parametersSchema: {
    'type': 'object',
    'properties': {
      'extension': {
        'type': 'string',
        'description':
            'the caption type to edit (e.g. ".txt"); omit for the active '
            'one. Its format must be a tag list — for a JSON type use '
            'edit_json_captions.',
      },
      'add': {
        'type': 'array',
        'items': {'type': 'string'},
        'description':
            'tags to add to every caption in scope. A caption that already '
            'carries one is not given it twice. Uncaptioned images get a '
            'caption file created unless create_missing is false.',
      },
      'add_index': {
        'type': 'integer',
        'description':
            'where the added tags go: 0 = first (the LoRA trigger word), '
            'omit = appended at the end',
      },
      'add_anchor': {
        'type': 'string',
        'description':
            'add next to this tag instead of at a fixed position; captions '
            'that do not carry the anchor get nothing added (their remove '
            'and rename rules still apply). Cannot be combined with '
            'add_index.',
      },
      'add_after': {
        'type': 'boolean',
        'description':
            'with add_anchor: true (default) inserts after the anchor, '
            'false before it',
      },
      'remove': {
        'type': 'array',
        'items': {'type': 'string'},
        'description': 'tags to delete from every caption that has them',
      },
      'rename': {
        'type': 'object',
        'description':
            'tag → replacement, applied in place so the tag keeps its '
            'position. The replacement may be several comma-separated tags. '
            'A rename onto a tag the caption already carries merges into it '
            'rather than duplicating. Use remove to delete a tag, not a '
            'rename to an empty string.',
      },
      'create_missing': {
        'type': 'boolean',
        'description':
            'true (default): images with no caption file get one created by '
            'an "add" rule; false: they are skipped and counted',
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
  },
);

/// The validated dataset-wide edit.
class _Rules {
  _Rules({
    required this.add,
    required this.addIndex,
    required this.addAnchor,
    required this.addAfter,
    required this.remove,
    required this.rename,
    required this.createMissing,
  });

  final List<String> add;
  final int? addIndex;

  /// Folded anchor tag, or null for a positional add.
  final String? addAnchor;
  final bool addAfter;

  /// Folded tags to delete.
  final Set<String> remove;

  /// Folded tag → its replacement tags, spelled as the caller wrote them.
  final Map<String, List<String>> rename;

  final bool createMissing;

  bool get isEmpty => add.isEmpty && remove.isEmpty && rename.isEmpty;
}

typedef _RulesResult = ({AgentToolResult? error, _Rules? rules});

_RulesResult _buildRules(Map<String, dynamic> args) {
  _RulesResult fail(String message) => (error: toolError(message), rules: null);

  final remove = <String>{};
  for (final tag in optStringList(args, 'remove', maxLength: 500)) {
    remove.add(tagLookupKey(tag));
  }

  final rawRename = args['rename'] ?? const <String, dynamic>{};
  if (rawRename is! Map) {
    return fail('"rename" must be an object mapping tags to their replacement');
  }
  final rename = <String, List<String>>{};
  for (final entry in rawRename.entries) {
    final from = entry.key;
    final to = entry.value;
    if (from is! String || to is! String) {
      return fail('"rename" must map tag strings to tag strings');
    }
    final parts = parseTagText(to);
    if (from.trim().isEmpty || parts.isEmpty) {
      return fail('"rename" holds an empty tag; use "remove" to delete one');
    }
    final key = tagLookupKey(from);
    // A tag that is both removed and renamed has no defined outcome, and
    // guessing one would quietly do half of what was asked.
    if (remove.contains(key)) {
      return fail('"$from" is in both "remove" and "rename" — pick one');
    }
    if (rename.containsKey(key)) {
      return fail('rename: "$from" is renamed twice');
    }
    rename[key] = parts;
  }

  final add = optStringList(args, 'add', maxLength: 50);
  for (final tag in add) {
    final key = tagLookupKey(tag);
    if (remove.contains(key) || rename.containsKey(key)) {
      return fail(
        'add: "$tag" is also named in "remove" or "rename" — the two rules '
        'would fight over it',
      );
    }
  }

  final anchor = optString(args, 'add_anchor');
  final hasIndex = args['add_index'] != null;
  if (anchor != null && hasIndex) {
    return fail('pass either add_index or add_anchor, not both');
  }
  if ((anchor != null || hasIndex) && add.isEmpty) {
    return fail('add_index / add_anchor need an "add" list to place');
  }

  return (
    error: null,
    rules: _Rules(
      add: add,
      addIndex: hasIndex ? optInt(args, 'add_index', fallback: 0, min: 0) : null,
      addAnchor: anchor == null ? null : tagLookupKey(anchor),
      addAfter: optBool(args, 'add_after', fallback: true),
      remove: remove,
      rename: rename,
      createMissing: optBool(args, 'create_missing', fallback: true),
    ),
  );
}

/// One caption's rewrite, or null when no rule touched it.
///
/// Tags are only ever dropped by a rule: a duplicate the file already carried
/// is left alone, so a sweep never quietly compacts captions it was not asked
/// to change.
List<String>? _editTags(
  _Rules rules,
  List<String> tags, {
  required void Function(String tag) onRemoved,
  required void Function(String tag) onRenamed,
  required void Function(String tag) onAdded,
}) {
  var touched = false;
  // (tag, produced by a rule) — the flag decides whether a collision merges
  // or is left in place.
  final out = <(String, bool)>[];
  for (final tag in tags) {
    final key = tagLookupKey(tag);
    if (rules.remove.contains(key)) {
      onRemoved(tag);
      touched = true;
      continue;
    }
    final replacement = rules.rename[key];
    if (replacement == null) {
      out.add((tag, false));
      continue;
    }
    onRenamed(tag);
    touched = true;
    for (final part in replacement) {
      out.add((part, true));
    }
  }

  if (rules.add.isNotEmpty) {
    final present = {for (final e in out) tagLookupKey(e.$1)};
    final fresh = [
      for (final tag in rules.add)
        if (!present.contains(tagLookupKey(tag))) tag,
    ];
    if (fresh.isNotEmpty) {
      int? at;
      if (rules.addAnchor != null) {
        final index = out.indexWhere((e) => tagLookupKey(e.$1) == rules.addAnchor);
        // A caption without the anchor is not a caption to append to: that
        // was insert_beside_tag's whole contract.
        if (index >= 0) at = rules.addAfter ? index + 1 : index;
      } else {
        at = (rules.addIndex ?? out.length).clamp(0, out.length);
      }
      if (at != null) {
        out.insertAll(at, [for (final tag in fresh) (tag, true)]);
        for (final tag in fresh) {
          onAdded(tag);
        }
        touched = true;
      }
    }
  }

  if (!touched) return null;
  // A collision merges when *either* copy came from a rule — the renamed tag
  // may land either side of the one already there. Two copies that were both
  // already in the file (different spellings of the same tag) are left alone:
  // this sweep only changes what it was asked to.
  final firstFromRule = <String, bool>{};
  final result = <String>[];
  for (final (tag, fromRule) in out) {
    final key = tagLookupKey(tag);
    final earlier = firstFromRule[key];
    if (earlier == null) {
      firstFromRule[key] = fromRule;
      result.add(tag);
      continue;
    }
    if (earlier || fromRule) continue;
    result.add(tag);
  }
  return result;
}

Future<AgentToolResult> _edit(
  DatasetToolsDeps deps,
  TagOps tagOps,
  Map<String, dynamic> args,
) async {
  final root = deps.rootDir();
  if (root == null) return toolError('no dataset directory is open');
  final d = deps.dataset;
  final types = deps.captionTypes();

  // Without an extension the target is whatever the dataset was scanned with,
  // read from the dataset rather than looked up in the configured types: the
  // scan is the authority on the active type, and the settings can change
  // mid-conversation. A named extension does go through the type list, which
  // is the only place a *non-active* type's format is recorded.
  final requested = optString(args, 'extension');
  final CaptionType? type;
  final String extension;
  final CaptionFormat format;
  if (requested == null) {
    type = null;
    extension = d.captionExtension;
    format = d.captionFormat;
  } else {
    type = findCaptionType(types, requested);
    if (type == null) return toolError(unknownCaptionType(requested, types));
    extension = type.extension;
    format = type.format;
  }
  if (format == CaptionFormat.json) {
    return toolError(
      'the caption type "$extension" is JSON, whose tags live inside a '
      'document this tool cannot rebuild — use edit_json_captions, which '
      'takes the same add / remove / rename rules and names the field each '
      'added tag goes into',
    );
  }

  // The rules are validated in full before anything touches the disk: a
  // contradictory rule must fail the whole call, never image #57 of a sweep.
  final built = _buildRules(args);
  if (built.error != null) return built.error!;
  final rules = built.rules!;
  if (rules.isEmpty) {
    return toolError(
      'nothing to do: give at least one of "add", "remove" or "rename"',
    );
  }

  final files = filterDatasetFiles(
    d,
    include: optStringList(args, 'include_tags'),
    exclude: optStringList(args, 'exclude_tags'),
    untaggedOnly: optBool(args, 'untagged_only'),
    nameQuery: optString(args, 'name_query')?.toLowerCase(),
  );

  final active = extension == d.captionExtension;
  // The editor's pending edits would otherwise be written over this sweep's
  // result a moment later — the same flush every TagOps mutation does.
  if (active) await tagOps.beforeMutate?.call();

  var written = 0;
  var unchanged = 0;
  var skippedUncaptioned = 0;
  final added = <String, int>{};
  final removed = <String, int>{};
  final renamed = <String, int>{};
  final failures = <({String path, String error})>[];
  final edits = <CaptionEdit>[];

  for (final f in files) {
    final rel = p.relative(f.path, from: root);
    final file = File(
      active ? d.captionPathFor(f.path) : captionVariantPath(f.path, type!),
    );
    String before;
    try {
      before = await file.exists() ? await file.readAsString() : '';
    } catch (e) {
      failures.add((path: rel, error: 'cannot read: $e'));
      continue;
    }
    if (before.trim().isEmpty && !(rules.add.isNotEmpty && rules.createMissing)) {
      skippedUncaptioned++;
      continue;
    }
    // An Anima Tag caption's trailing sentence is not a tag: it is held aside
    // and re-appended, never matched, reordered or removed by a rule.
    final parts = parseCaptionText(before, format: format);
    final split = format == CaptionFormat.animaTag
        ? splitAnimaParts(parts)
        : (tags: parts, nl: null);

    final removedHere = <String>{};
    final renamedHere = <String>{};
    final addedHere = <String>{};
    final next = _editTags(
      rules,
      split.tags,
      onRemoved: removedHere.add,
      onRenamed: renamedHere.add,
      onAdded: addedHere.add,
    );
    if (next == null) {
      unchanged++;
      continue;
    }

    final text = joinCaptionText([
      ...next,
      if (split.nl case final nl?) '$animaNlPrefix$nl',
    ], format: format);
    if (text == before) {
      unchanged++;
      continue;
    }
    try {
      await file.writeAsString(text);
    } catch (e) {
      failures.add((path: rel, error: 'cannot write: $e'));
      continue;
    }
    written++;
    // Counted per caption, not per occurrence, and only once the write lands.
    for (final tag in removedHere) {
      removed[tag] = (removed[tag] ?? 0) + 1;
    }
    for (final tag in renamedHere) {
      renamed[tag] = (renamed[tag] ?? 0) + 1;
    }
    for (final tag in addedHere) {
      added[tag] = (added[tag] ?? 0) + 1;
    }
    edits.add(
      CaptionEdit(
        imagePath: f.path,
        captionPath: file.path,
        before: before,
        after: text,
      ),
    );
  }

  if (edits.isNotEmpty) {
    tagOps.pushOperation(
      TagOperation(
        label: 'AI: edit ${edits.length} $extension captions',
        edits: edits,
      ),
      // Writing the active type behind the dataset's back would leave the
      // gallery, the tag index and the open editor showing the old text.
      syncActiveCaptions: active,
    );
  }

  if (written == 0 && failures.isNotEmpty) {
    return toolError(
      'nothing was written: ${failures.length} image(s) failed — '
      '${failures.take(_failureSample).map((f) => '${f.path}: ${f.error}').join('; ')}'
      '${failures.length > _failureSample ? '; …' : ''}',
    );
  }
  return toolOk({
    'scope': scopeLabel(d),
    'extension': extension,
    'written': written,
    'unchanged': unchanged,
    'skipped_uncaptioned': skippedUncaptioned,
    // Keyed by the tag as it was spelled in the caption, so a rule that never
    // fired is visible by its absence rather than passing for "already done".
    'added_tags': _topCounts(added),
    'removed_tags': _topCounts(removed),
    'renamed_tags': _topCounts(renamed),
    if (failures.isNotEmpty) ...{
      'failed_images': failures.length,
      'failures': [
        for (final f in failures.take(_failureSample))
          {'path': f.path, 'error': f.error},
      ],
      'failures_truncated': failures.length > _failureSample,
    },
  });
}

/// The busiest rules first, capped: an audit trail, not a full index.
Map<String, int> _topCounts(Map<String, int> counts) {
  final entries = counts.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return {for (final e in entries.take(_countSample)) e.key: e.value};
}
