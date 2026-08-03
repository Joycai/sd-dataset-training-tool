/// Agent tools for JSON-format caption types: surveying the shape of the
/// documents a dataset carries, and restructuring them in bulk.
///
/// The restructure is why this file exists. Reshaping a JSON caption through
/// a text-level tool means the model retypes the whole document once per
/// image and nothing checks that it retyped every tag — the exact failure
/// the tag tools grew their own guards for. Here the model describes the
/// *target shape* once and the tool assembles each document itself, so the
/// output is valid JSON, the field order is the declared one, and the tags
/// are the file's own tags moved around: never reworded, never dropped,
/// never invented.
///
/// Both tools take a caption type by extension and key on its configured
/// [CaptionFormat], never on the extension itself. The restructure writes
/// *in place*, including the active type — that is the common case, since a
/// dataset may well carry nothing but JSON captions.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../models/caption_type.dart';
import '../../state/tag_ops.dart';
import '../../utils/tag_text.dart';
import 'agent_tools.dart';
import 'caption_variant_tools.dart';
import 'dataset_tools.dart';

/// How many key paths one inspect call reports. A caption document with more
/// distinct keys than this is not a caption schema any more.
const int _maxInspectKeys = 200;

/// How many distinct tags of the catch-all field the restructure result
/// names back to the model.
const int _maxUnassignedSample = 100;

/// How many per-image failures travel back in a result.
const int _failureSample = 5;

List<AgentTool> buildJsonCaptionTools(DatasetToolsDeps deps, TagOps tagOps) => [
  _inspectTool(deps),
  AgentTool(
    isWrite: true,
    spec: _restructureSpec,
    handler: guardBusy(tagOps, (args) => _restructure(deps, tagOps, args)),
  ),
  AgentTool(
    isWrite: true,
    spec: _editSpec,
    handler: guardBusy(tagOps, (args) => _edit(deps, tagOps, args)),
  ),
];

// --- inspect_json_captions ----------------------------------------------

AgentTool _inspectTool(DatasetToolsDeps deps) => AgentTool(
  spec: const AgentToolSpec(
    name: 'inspect_json_captions',
    description:
        'Survey the shape of a JSON caption type across the dataset: which '
        'keys the documents carry, how many images have each, what kind of '
        'value it holds, how many tags live under it with a few examples, '
        'and which top-level key orders occur. This is what a restructure '
        'is planned from — read it before restructure_json_captions '
        'instead of paging through raw files with read_caption_file. Files '
        'that do not parse are counted and named, so a broken caption '
        'cannot hide behind a sampled read.',
    parametersSchema: {
      'type': 'object',
      'properties': {
        'extension': {
          'type': 'string',
          'description':
              'a configured caption type whose format is JSON (e.g. '
              '".json")',
        },
        'samples': {
          'type': 'integer',
          'description': 'example tag values per key (default 5, max 20)',
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
      },
      'required': ['extension'],
    },
  ),
  handler: (args) async {
    final root = deps.rootDir();
    if (root == null) return toolError('no dataset directory is open');
    final types = deps.captionTypes();
    final requested = requireString(args, 'extension');
    final type = findCaptionType(types, requested);
    if (type == null) return toolError(unknownCaptionType(requested, types));
    if (type.format != CaptionFormat.json) {
      return toolError(
        '"${type.extension}" is configured as ${type.format.name}, not '
        'JSON; there is no document structure to inspect',
      );
    }
    final samples = optInt(args, 'samples', fallback: 5, min: 1, max: 20);
    final files = filterDatasetFiles(
      deps.dataset,
      include: optStringList(args, 'include_tags'),
      exclude: optStringList(args, 'exclude_tags'),
      untaggedOnly: false,
      nameQuery: optString(args, 'name_query')?.toLowerCase(),
    );

    final keys = <String, _KeyStats>{};
    final keyOrders = <String, int>{};
    final rootKinds = <String, int>{};
    final unparseable = <({String path, String error})>[];
    var withFile = 0;
    var missingFile = 0;

    for (final f in files) {
      final file = File(captionVariantPath(f.path, type));
      final rel = p.relative(f.path, from: root);
      String text;
      try {
        if (!await file.exists()) {
          missingFile++;
          continue;
        }
        text = await file.readAsString();
      } catch (e) {
        unparseable.add((path: rel, error: 'cannot read: $e'));
        continue;
      }
      if (text.trim().isEmpty) {
        missingFile++;
        continue;
      }
      dynamic decoded;
      try {
        decoded = jsonDecode(text);
      } on FormatException catch (e) {
        unparseable.add((path: rel, error: 'not valid JSON — ${e.message}'));
        continue;
      }
      withFile++;
      rootKinds.update(_kindOf(decoded), (n) => n + 1, ifAbsent: () => 1);
      if (decoded is Map) {
        final order = decoded.keys.join(' | ');
        keyOrders.update(order, (n) => n + 1, ifAbsent: () => 1);
      }
      final seen = <String>{};
      _walkKeys(decoded, '', (path, value) {
        final stats = keys.putIfAbsent(path, _KeyStats.new);
        if (seen.add(path)) stats.images++;
        stats.kinds.add(_kindOf(value));
        for (final tag in jsonCaptionTags(value)) {
          stats.tags++;
          stats.tagCounts.update(tag, (n) => n + 1, ifAbsent: () => 1);
        }
      });
    }

    final ordered = keys.entries.toList()
      ..sort((a, b) => b.value.images.compareTo(a.value.images));
    final orders = keyOrders.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return toolOk({
      'scope': scopeLabel(deps.dataset),
      'extension': type.extension,
      'active': type.extension == deps.dataset.captionExtension,
      'images_scanned': files.length,
      'with_caption': withFile,
      'without_caption': missingFile,
      'unparseable': unparseable.length,
      if (unparseable.isNotEmpty) ...{
        'unparseable_examples': [
          for (final u in unparseable.take(_failureSample))
            {'path': u.path, 'error': u.error},
        ],
        'unparseable_truncated': unparseable.length > _failureSample,
      },
      'root_kinds': rootKinds,
      'key_orders': [
        for (final o in orders.take(5))
          {'keys': o.key.split(' | '), 'images': o.value},
      ],
      'key_orders_truncated': orders.length > 5,
      'keys': [
        for (final e in ordered.take(_maxInspectKeys))
          {
            'path': e.key,
            'images': e.value.images,
            'kinds': e.value.kinds.toList(),
            'tags': e.value.tags,
            'distinct_tags': e.value.tagCounts.length,
            'samples': e.value.topTags(samples),
          },
      ],
      'keys_truncated': ordered.length > _maxInspectKeys,
    });
  },
);

class _KeyStats {
  int images = 0;
  int tags = 0;
  final Set<String> kinds = {};
  final Map<String, int> tagCounts = {};

  List<String> topTags(int limit) {
    final entries = tagCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return [for (final e in entries.take(limit)) e.key];
  }
}

/// Reports every key of a decoded document to [visit] as a dotted path;
/// keys inside an array of objects get a `[]` segment (`chars[].name`), so
/// one path describes the whole array rather than one index per image.
/// Counts under a key cover its entire subtree — a nested key's tags are
/// counted again at its parent, which is what makes the parent's number
/// mean "everything under here".
void _walkKeys(
  dynamic node,
  String prefix,
  void Function(String path, dynamic value) visit,
) {
  if (node is Map) {
    node.forEach((key, value) {
      final path = prefix.isEmpty ? '$key' : '$prefix.$key';
      visit(path, value);
      _walkKeys(value, path, visit);
    });
  } else if (node is List) {
    for (final element in node) {
      if (element is Map || element is List) {
        _walkKeys(element, '$prefix[]', visit);
      }
    }
  }
}

String _kindOf(dynamic value) {
  if (value == null) return 'null';
  if (value is String) return 'string';
  if (value is bool) return 'bool';
  if (value is num) return 'number';
  if (value is Map) return 'object';
  if (value is List) {
    if (value.isEmpty) return 'array<empty>';
    final kinds = {for (final e in value) _kindOf(e)};
    return kinds.length == 1 ? 'array<${kinds.first}>' : 'array<mixed>';
  }
  return 'unknown';
}

// --- restructure_json_captions ------------------------------------------

const AgentToolSpec _restructureSpec = AgentToolSpec(
  name: 'restructure_json_captions',
  description:
      'Rewrite MANY JSON captions into a new document shape in one call — '
      'the tool for "change the JSON structure / reorder the fields" over a '
      'dataset, and the only one that can do it without risking the tags. '
      'You describe the target shape once (the ordered fields, where each '
      'one\'s tags come from, fixed values, a catch-all) and the tool '
      'assembles every document itself, so the result is always valid '
      'JSON, always in the declared field order, and carries exactly the '
      'tags the file already had — none added, none dropped, none '
      'reworded. A document whose tags would not come out identical is '
      'skipped and reported instead of written. Plan the shape from '
      'inspect_json_captions, never from memory, and never loop '
      'write_caption_file over a dataset to do this. Rewrites the type in '
      'place, the active one included. Undoable as one operation.',
  parametersSchema: {
    'type': 'object',
    'properties': {
      'extension': {
        'type': 'string',
        'description':
            'the caption type to restructure; its configured format must '
            'be JSON (e.g. ".json")',
      },
      'fields': {
        'type': 'array',
        'items': {
          'type': 'object',
          'properties': {
            'name': {'type': 'string'},
            'kind': {
              'type': 'string',
              'enum': ['string', 'array', 'preserve'],
            },
          },
          'required': ['name', 'kind'],
        },
        'description':
            'the fields of the NEW document, in output order. "array" '
            'takes any number of tags, "string" at most one (empty string '
            'when none), and "preserve" copies its source key\'s value '
            'over verbatim — use it for a field that is not tags at all, '
            'e.g. a natural-language description.',
      },
      'from': {
        'type': 'object',
        'description':
            'new field name → array of OLD top-level key names whose tags '
            'flow into it; this is how keys get renamed or merged. A field '
            'not named here sources from the old key of its own name. Old '
            'keys that end up routed nowhere send their tags to '
            'unassigned_field, and the result names them. A "preserve" '
            'field takes exactly one source key.',
      },
      'assign': {
        'type': 'object',
        'description':
            'tag → field name, for individual tags that must move '
            'regardless of which key they sit under now; overrides the '
            '`from` routing. Matching folds case and underscore/space '
            'style.',
      },
      'constants': {
        'type': 'object',
        'description':
            'field name → fixed JSON value written verbatim into every '
            'document (e.g. {"artist": ""}); such a field takes no tags '
            'and is excluded from the lossless check.',
      },
      'unassigned_field': {
        'type': 'string',
        'description':
            'the "array" field that receives every tag not routed '
            'anywhere else — the catch-all that makes losing a tag '
            'impossible',
      },
      'tag_priority': {
        'type': 'array',
        'items': {'type': 'string'},
        'description':
            'optional: inside every array field, these tags come first in '
            'this order; the rest keep their current relative order. '
            'Matching folds case and underscore/space style.',
      },
      'drop_empty': {
        'type': 'boolean',
        'description':
            'omit fields that come out empty ("" or []); default false, '
            'which keeps the shape identical across every image',
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
    },
    'required': ['extension', 'fields', 'unassigned_field'],
  },
);

// --- edit_json_captions --------------------------------------------------

const AgentToolSpec _editSpec = AgentToolSpec(
  name: 'edit_json_captions',
  description:
      'Add, remove and rename TAGS inside MANY JSON captions in one call — '
      'the tool for "delete this tag everywhere", "rename this tag", "give '
      'every image this tag" when the caption type is JSON. The tag-level '
      'batch tools (remove_tag_everywhere, add_tags_everywhere, …) refuse a '
      'JSON caption because they would flatten the document into a comma '
      'line; this one edits the tags in place and leaves the document\'s '
      'shape — its keys, their order, and every value no rule touches — '
      'exactly as it was. Never loop write_caption_file over a dataset to '
      'do this. Rules are dataset-wide and matching folds case and '
      'underscore/space style, so "long_hair" and "Long Hair" are the same '
      'tag. The result reports every tag added, removed and renamed with '
      'how many captions it came out of, so the edit can be audited from '
      'one answer. Use restructure_json_captions instead to move tags '
      'between fields, reorder or rename FIELDS, or write a fixed value '
      'into one. Rewrites the type in place, the active one included. '
      'Undoable as one operation.',
  parametersSchema: {
    'type': 'object',
    'properties': {
      'extension': {
        'type': 'string',
        'description':
            'the caption type to edit; its configured format must be JSON '
            '(e.g. ".json")',
      },
      'add': {
        'type': 'object',
        'description':
            'field name → tags to append to that field, e.g. '
            '{"appearance": ["blonde hair"], "tags": ["solo"]}. A tag the '
            'field already carries is not duplicated. Only top-level ARRAY '
            'fields take additions: a document that holds something else '
            'under that name is reported instead of written, and a document '
            'missing the key gets it created as an array at the end. Use '
            'restructure_json_captions constants to set a scalar field.',
      },
      'remove': {
        'type': 'array',
        'items': {'type': 'string'},
        'description':
            'tags to delete wherever they occur in the document; a string '
            'field that held nothing else is left as "", never deleted',
      },
      'rename': {
        'type': 'object',
        'description':
            'tag → replacement tag, applied wherever the tag occurs. A '
            'rename that lands on a tag the same field already carries '
            'merges into it instead of duplicating. Renaming to a different '
            'spelling of the same tag ("long_hair" → "long hair") is a '
            'legitimate respelling. Use remove to delete a tag, not a '
            'rename to an empty string.',
      },
      'skip_fields': {
        'type': 'array',
        'items': {'type': 'string'},
        'description':
            'key names left completely untouched wherever they occur — use '
            'it for fields that hold prose rather than tags (e.g. "nl"), '
            'whose sentences would otherwise be read with the tag grammar',
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
    },
    'required': ['extension'],
  },
);

/// The validated dataset-wide edit: which tags go, which get another
/// spelling, which arrive, and what is off limits.
class _EditRules {
  _EditRules({
    required this.remove,
    required this.rename,
    required this.add,
    required this.skipFields,
  });

  /// Folded tags to delete.
  final Set<String> remove;

  /// Folded tag → its replacement, spelled as the caller wrote it.
  final Map<String, String> rename;

  /// Top-level array field → the tags appended to it, in order.
  final Map<String, List<String>> add;

  /// Key names skipped wherever they occur — the same "invisible subtree"
  /// rule [jsonCaptionTags] reads with.
  final Set<String> skipFields;

  bool get isEmpty => remove.isEmpty && rename.isEmpty && add.isEmpty;
}

typedef _RulesResult = ({AgentToolResult? error, _EditRules? rules});

_RulesResult _buildEditRules(Map<String, dynamic> args) {
  _RulesResult fail(String message) => (error: toolError(message), rules: null);

  final skipFields = optStringList(args, 'skip_fields').toSet();

  final remove = <String, String>{};
  for (final tag in optStringList(args, 'remove')) {
    if (tag.trim().isEmpty) return fail('"remove" holds an empty tag');
    remove[tagLookupKey(tag)] = tag;
  }

  final rawRename = args['rename'] ?? const <String, dynamic>{};
  if (rawRename is! Map) {
    return fail('"rename" must be an object mapping tags to their replacement');
  }
  final rename = <String, String>{};
  for (final entry in rawRename.entries) {
    final from = entry.key;
    final to = entry.value;
    if (from is! String || to is! String) {
      return fail('"rename" must map tag strings to tag strings');
    }
    if (from.trim().isEmpty || to.trim().isEmpty) {
      return fail('"rename" holds an empty tag; use "remove" to delete one');
    }
    final key = tagLookupKey(from);
    // A tag that is both removed and renamed has no defined outcome, and
    // guessing one would quietly do half of what was asked.
    if (remove.containsKey(key)) {
      return fail('"$from" is in both "remove" and "rename" — pick one');
    }
    final previous = rename[key];
    if (previous != null && previous != to) {
      return fail('rename: "$from" is renamed to both "$previous" and "$to"');
    }
    // JSON captions carry plain parentheses; the backslashes are plain-text
    // caption syntax and would be written into the document verbatim.
    rename[key] = unescapeTagParens(to);
  }

  final rawAdd = args['add'] ?? const <String, dynamic>{};
  if (rawAdd is! Map) {
    return fail('"add" must be an object mapping field names to tag arrays');
  }
  final add = <String, List<String>>{};
  for (final entry in rawAdd.entries) {
    final field = entry.key;
    if (field is! String || field.trim().isEmpty) {
      return fail('"add" needs a non-empty field name');
    }
    if (skipFields.contains(field)) {
      return fail('add: "$field" is also in skip_fields — pick one');
    }
    final value = entry.value;
    final tags = value is String ? [value] : value;
    if (tags is! List || tags.any((e) => e is! String)) {
      return fail('add: "$field" must map to an array of tags');
    }
    final seen = <String>{};
    final list = <String>[];
    for (final tag in tags.cast<String>()) {
      if (tag.trim().isEmpty) return fail('add: "$field" holds an empty tag');
      final key = tagLookupKey(tag);
      if (remove.containsKey(key) || rename.containsKey(key)) {
        return fail(
          'add: "$tag" is also named in "remove" or "rename" — the two rules '
          'would fight over it',
        );
      }
      if (seen.add(key)) list.add(unescapeTagParens(tag));
    }
    if (list.isEmpty) return fail('add: "$field" has no tags');
    add[field] = list;
  }

  return (
    error: null,
    rules: _EditRules(
      remove: remove.keys.toSet(),
      rename: rename,
      add: add,
      skipFields: skipFields,
    ),
  );
}

typedef _EditResult = ({String? error, dynamic document});

/// Applies the rules to one decoded document.
///
/// The document is rewritten node by node rather than reassembled from a
/// declared shape: every key keeps its place and every value no rule matches
/// comes out byte-identical, which is what makes this safe to run over a
/// dataset whose JSON layout the model has never seen in full.
_EditResult _editDocument(
  _EditRules rules,
  dynamic decoded, {
  required void Function(String tag) onRemoved,
  required void Function(String tag) onRenamed,
  required void Function(String field, String tag) onAdded,
  required void Function(String field) onFieldCreated,
}) {
  String editText(String text) {
    if (rules.remove.isEmpty && rules.rename.isEmpty) return text;
    final tags = parseTagText(text);
    if (tags.isEmpty) return text;
    var touched = false;
    final kept = <String>[];
    for (final tag in tags) {
      final key = tagLookupKey(tag);
      if (rules.remove.contains(key)) {
        onRemoved(tag);
        touched = true;
        continue;
      }
      final replacement = rules.rename[key];
      if (replacement != null && replacement != tag) {
        onRenamed(tag);
        touched = true;
        kept.add(replacement);
        continue;
      }
      kept.add(tag);
    }
    // A leaf no rule matched is returned as it was read. Prose that happens
    // to sit in a tag field must not be re-joined into tag grammar just
    // because the walk passed over it.
    return touched ? kept.join(', ') : text;
  }

  dynamic walk(dynamic node) {
    if (node is String) return editText(node);
    if (node is List) {
      final out = <dynamic>[];
      final seen = <String>{};
      for (final element in node) {
        final edited = walk(element);
        if (element is String && edited is String) {
          // Only a rule can empty a leaf; an element that arrived empty
          // stays, so the tool never quietly compacts what it was not asked
          // to touch.
          if (edited.trim().isEmpty) {
            if (element.trim().isNotEmpty) continue;
          } else if (!seen.add(tagLookupKey(edited)) && edited != element) {
            // A rename landed on a tag this array already carries: merge
            // into it rather than write the tag twice. A duplicate that was
            // already in the file is left alone.
            continue;
          }
        }
        out.add(edited);
      }
      return out;
    }
    if (node is Map) {
      final out = <String, dynamic>{};
      node.forEach((key, value) {
        final name = '$key';
        out[name] = rules.skipFields.contains(name) ? value : walk(value);
      });
      return out;
    }
    return node;
  }

  final edited = walk(decoded);
  if (rules.add.isEmpty) return (error: null, document: edited);
  if (edited is! Map<String, dynamic>) {
    return (
      error:
          'skipped, "add" needs an object document and this one is a '
          '${edited is List ? 'array' : 'scalar'}',
      document: null,
    );
  }
  for (final entry in rules.add.entries) {
    final field = entry.key;
    if (!edited.containsKey(field)) {
      edited[field] = [...entry.value];
      onFieldCreated(field);
      for (final tag in entry.value) {
        onAdded(field, tag);
      }
      continue;
    }
    final current = edited[field];
    // Appending into a scalar is almost always a mis-aimed rule, and turning
    // "1girl" into a list behind the caller's back would be worse than
    // saying so.
    if (current is! List) {
      return (
        error:
            'skipped, the field "$field" holds '
            '${current is String ? 'a string' : 'a ${current.runtimeType}'}, '
            'not an array — only array fields take "add"',
        document: null,
      );
    }
    final seen = <String>{
      for (final element in current)
        if (element is String)
          for (final tag in parseTagText(element)) tagLookupKey(tag),
    };
    for (final tag in entry.value) {
      if (!seen.add(tagLookupKey(tag))) continue;
      current.add(tag);
      onAdded(field, tag);
    }
  }
  return (error: null, document: edited);
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
  final requested = requireString(args, 'extension');
  final type = findCaptionType(types, requested);
  if (type == null) return toolError(unknownCaptionType(requested, types));
  if (type.format != CaptionFormat.json) {
    return toolError(
      'the caption type "${type.extension}" is configured as '
      '${type.format.name}, not JSON — for a tag-list type use the tag tools '
      '(remove_tag_everywhere, add_tags_everywhere, replace_tag_everywhere) '
      'or convert_captions_to_tags',
    );
  }

  // The rules are validated in full before anything touches the disk: a
  // contradictory rule must fail the whole call, never image #57 of a sweep.
  final built = _buildEditRules(args);
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
    untaggedOnly: false,
    nameQuery: optString(args, 'name_query')?.toLowerCase(),
  );

  const encoder = JsonEncoder.withIndent('  ');
  var written = 0;
  var unchanged = 0;
  var skippedNoCaption = 0;
  var fieldsCreated = 0;
  final failures = <({String path, String error})>[];
  final removed = <String, int>{};
  final renamed = <String, int>{};
  final added = <String, int>{};
  final edits = <CaptionEdit>[];

  for (final f in files) {
    final rel = p.relative(f.path, from: root);
    final file = File(captionVariantPath(f.path, type));
    String before;
    try {
      if (!await file.exists()) {
        skippedNoCaption++;
        continue;
      }
      before = await file.readAsString();
    } catch (e) {
      failures.add((path: rel, error: 'cannot read: $e'));
      continue;
    }
    if (before.trim().isEmpty) {
      skippedNoCaption++;
      continue;
    }
    dynamic decoded;
    try {
      decoded = jsonDecode(before);
    } on FormatException catch (e) {
      failures.add((path: rel, error: 'not valid JSON — ${e.message}'));
      continue;
    }

    // Counted per caption, not per occurrence, and only once the write
    // lands: a rule that fired into a document this image then failed on
    // must not show up as work done.
    final removedHere = <String>{};
    final renamedHere = <String>{};
    final addedHere = <String>{};
    var createdHere = 0;
    final result = _editDocument(
      rules,
      decoded,
      onRemoved: removedHere.add,
      onRenamed: renamedHere.add,
      onAdded: (field, tag) => addedHere.add('$field: $tag'),
      onFieldCreated: (_) => createdHere++,
    );
    if (result.error != null) {
      failures.add((path: rel, error: result.error!));
      continue;
    }

    final text = encoder.convert(result.document);
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
    for (final tag in removedHere) {
      removed[tag] = (removed[tag] ?? 0) + 1;
    }
    for (final tag in renamedHere) {
      renamed[tag] = (renamed[tag] ?? 0) + 1;
    }
    for (final entry in addedHere) {
      added[entry] = (added[entry] ?? 0) + 1;
    }
    fieldsCreated += createdHere;
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
        label: 'AI: edit ${edits.length} ${type.extension} captions',
        edits: edits,
      ),
      // The type may well be the active one — the gallery and the tag index
      // have to follow the edit rather than keep the old documents.
      syncActiveCaptions: true,
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
    'extension': type.extension,
    'written': written,
    'unchanged': unchanged,
    'skipped_without_caption': skippedNoCaption,
    // Keyed by the tag as it was spelled in the document, so a rule that
    // never fired is visible by its absence — it probably names a tag the
    // dataset does not carry, or one that sits in a skipped field.
    'added_tags': _topCounts(added),
    'removed_tags': _topCounts(removed),
    'renamed_tags': _topCounts(renamed),
    if (fieldsCreated > 0) 'fields_created': fieldsCreated,
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
Map<String, int> _topCounts(Map<String, int> counts, {int limit = 60}) {
  final entries = counts.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return {for (final e in entries.take(limit)) e.key: e.value};
}

/// The validated target shape: which fields exist, in what order, what each
/// one is, and where its content comes from.
class _Shape {
  _Shape({
    required this.order,
    required this.kinds,
    required this.constants,
    required this.keyToField,
    required this.preserveSource,
    required this.assign,
    required this.unassignedField,
    required this.priorityRank,
    required this.priorityLength,
    required this.dropEmpty,
  }) : preservedKeys = preserveSource.values.toSet(),
       untaggedFields = {...constants.keys, ...preserveSource.keys};

  final List<String> order;
  final Map<String, String> kinds;
  final Map<String, dynamic> constants;

  /// Old top-level key → the field its tags flow into.
  final Map<String, String> keyToField;

  /// Preserve field → the single old key whose value it copies.
  final Map<String, String> preserveSource;

  /// Folded tag → field, overriding [keyToField].
  final Map<String, String> assign;

  final String unassignedField;
  final Map<String, int> priorityRank;
  final int priorityLength;
  final bool dropEmpty;

  /// The old keys whose values are copied verbatim; excluded from the tag
  /// comparison on the source side.
  final Set<String> preservedKeys;

  /// The new fields that hold no tags of the source document; excluded from
  /// the tag comparison on the written side.
  final Set<String> untaggedFields;
}

Future<AgentToolResult> _restructure(
  DatasetToolsDeps deps,
  TagOps tagOps,
  Map<String, dynamic> args,
) async {
  final root = deps.rootDir();
  if (root == null) return toolError('no dataset directory is open');
  final d = deps.dataset;
  final types = deps.captionTypes();
  final requested = requireString(args, 'extension');
  final type = findCaptionType(types, requested);
  if (type == null) return toolError(unknownCaptionType(requested, types));
  if (type.format != CaptionFormat.json) {
    return toolError(
      'the caption type "${type.extension}" is configured as '
      '${type.format.name}, not JSON — the user sets a caption type\'s '
      'format in the caption type settings',
    );
  }

  // The shape is validated in full before anything touches the disk: a bad
  // declaration must fail the whole call, never image #57 of a sweep.
  final shape = _buildShape(args);
  if (shape.error != null) return shape.error!;
  final s = shape.shape!;

  final files = filterDatasetFiles(
    d,
    include: optStringList(args, 'include_tags'),
    exclude: optStringList(args, 'exclude_tags'),
    untaggedOnly: false,
    nameQuery: optString(args, 'name_query')?.toLowerCase(),
  );

  const encoder = JsonEncoder.withIndent('  ');
  var written = 0;
  var unchanged = 0;
  var skippedNoCaption = 0;
  var nonObjectRoots = 0;
  final failures = <({String path, String error})>[];
  final unroutedKeys = <String>{};
  final unassignedTags = <String>{};
  final edits = <CaptionEdit>[];

  for (final f in files) {
    final rel = p.relative(f.path, from: root);
    final file = File(captionVariantPath(f.path, type));
    String before;
    try {
      if (!await file.exists()) {
        skippedNoCaption++;
        continue;
      }
      before = await file.readAsString();
    } catch (e) {
      failures.add((path: rel, error: 'cannot read: $e'));
      continue;
    }
    if (before.trim().isEmpty) {
      skippedNoCaption++;
      continue;
    }
    dynamic decoded;
    try {
      decoded = jsonDecode(before);
    } on FormatException catch (e) {
      failures.add((path: rel, error: 'not valid JSON — ${e.message}'));
      continue;
    }
    if (decoded is! Map) nonObjectRoots++;

    final built = _buildDocument(
      s,
      decoded,
      onUnrouted: unroutedKeys.add,
      onUnassigned: unassignedTags.add,
    );
    if (built.error != null) {
      failures.add((path: rel, error: built.error!));
      continue;
    }

    // Belt and braces on top of the assembly: the document is rebuilt from
    // the file's own tags, so this can only fire on a bug — but a silent
    // bug here means silently mangled captions, which is the one outcome
    // this tool exists to make impossible.
    final sourceTags = jsonCaptionTags(decoded, ignoreKeys: s.preservedKeys);
    final writtenTags = jsonCaptionTags(
      built.document!,
      ignoreKeys: s.untaggedFields,
    );
    final match = matchPermutation(sourceTags, writtenTags);
    if (match.unknown.isNotEmpty || match.missing.isNotEmpty) {
      failures.add((
        path: rel,
        error:
            'skipped, the rebuilt document would not carry the same tags'
            '${match.missing.isEmpty ? '' : '; lost: '
                      '${match.missing.join(", ")}'}'
            '${match.unknown.isEmpty ? '' : '; invented: '
                      '${match.unknown.join(", ")}'}',
      ));
      continue;
    }

    final text = encoder.convert(built.document);
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
        label: 'AI: restructure ${edits.length} ${type.extension} captions',
        edits: edits,
      ),
      // The type may well be the active one — the gallery and the tag index
      // have to follow the rewrite rather than keep the old documents.
      syncActiveCaptions: true,
    );
  }

  if (written == 0 && failures.isNotEmpty) {
    return toolError(
      'nothing was written: ${failures.length} image(s) failed — '
      '${failures.take(_failureSample).map((f) => '${f.path}: ${f.error}').join('; ')}'
      '${failures.length > _failureSample ? '; …' : ''}',
    );
  }
  final unassignedList = unassignedTags.toList();
  return toolOk({
    'scope': scopeLabel(d),
    'extension': type.extension,
    'written': written,
    'unchanged': unchanged,
    'skipped_without_caption': skippedNoCaption,
    if (nonObjectRoots > 0) 'non_object_documents': nonObjectRoots,
    if (failures.isNotEmpty) ...{
      'failed_images': failures.length,
      'failures': [
        for (final f in failures.take(_failureSample))
          {'path': f.path, 'error': f.error},
      ],
      'failures_truncated': failures.length > _failureSample,
    },
    'unrouted_keys_seen': unroutedKeys.toList(),
    'unassigned_tags_seen': unassignedList.take(_maxUnassignedSample).toList(),
    if (unassignedList.length > _maxUnassignedSample)
      'unassigned_tags_truncated': true,
  });
}

typedef _ShapeResult = ({AgentToolResult? error, _Shape? shape});

_ShapeResult _buildShape(Map<String, dynamic> args) {
  _ShapeResult fail(String message) => (error: toolError(message), shape: null);

  final rawFields = args['fields'];
  if (rawFields is! List || rawFields.isEmpty) {
    return fail('missing required array parameter "fields"');
  }
  final order = <String>[];
  final kinds = <String, String>{};
  for (final entry in rawFields) {
    if (entry is! Map) {
      return fail(
        'every "fields" entry must be an object with "name" and "kind"',
      );
    }
    final name = entry['name'];
    final kind = entry['kind'];
    if (name is! String || name.trim().isEmpty) {
      return fail('every "fields" entry needs a non-empty "name"');
    }
    if (kind != 'string' && kind != 'array' && kind != 'preserve') {
      return fail(
        'field "$name": "kind" must be "string", "array" or "preserve"',
      );
    }
    if (kinds.containsKey(name)) return fail('duplicate field "$name"');
    kinds[name] = kind as String;
    order.add(name);
  }

  final rawConstants = args['constants'] ?? const <String, dynamic>{};
  if (rawConstants is! Map) {
    return fail('"constants" must be an object mapping field names to values');
  }
  final constants = <String, dynamic>{};
  for (final entry in rawConstants.entries) {
    final name = entry.key;
    if (name is! String || !kinds.containsKey(name)) {
      return fail('constant "$name" is not a declared field');
    }
    if (kinds[name] == 'preserve') {
      return fail(
        'field "$name" is both a constant and "preserve"; a preserved field '
        'copies the old value, a constant replaces it — pick one',
      );
    }
    constants[name] = entry.value;
  }

  final unassignedField = requireString(args, 'unassigned_field');
  if (!kinds.containsKey(unassignedField)) {
    return fail('unassigned_field "$unassignedField" is not a declared field');
  }
  if (kinds[unassignedField] != 'array') {
    return fail('unassigned_field "$unassignedField" must be an "array" field');
  }
  if (constants.containsKey(unassignedField)) {
    return fail(
      'unassigned_field "$unassignedField" cannot also be a constant',
    );
  }

  // `from` maps a field to the old keys feeding it; the sweep needs the
  // inverse, and building it is where a key routed to two fields surfaces.
  final rawFrom = args['from'] ?? const <String, dynamic>{};
  if (rawFrom is! Map) {
    return fail(
      '"from" must be an object mapping field names to arrays of old keys',
    );
  }
  final keyToField = <String, String>{};
  final preserveSource = <String, String>{};
  for (final entry in rawFrom.entries) {
    final field = entry.key;
    if (field is! String || !kinds.containsKey(field)) {
      return fail('from: "${entry.key}" is not a declared field');
    }
    if (constants.containsKey(field)) {
      return fail('from: "$field" already has a constant value');
    }
    final value = entry.value;
    final sources = value is String ? [value] : value;
    if (sources is! List || sources.any((e) => e is! String)) {
      return fail('from: "$field" must map to an array of old key names');
    }
    final keys = sources.cast<String>().map((e) => e.trim()).toList();
    if (kinds[field] == 'preserve' && keys.length != 1) {
      return fail(
        'from: the "preserve" field "$field" needs exactly one source key, '
        'got ${keys.length}',
      );
    }
    for (final key in keys) {
      if (key.isEmpty) return fail('from: "$field" has an empty source key');
      final previous = keyToField[key];
      if (previous != null && previous != field) {
        return fail(
          'from: the old key "$key" is routed to both "$previous" and '
          '"$field"',
        );
      }
      keyToField[key] = field;
    }
    if (kinds[field] == 'preserve') preserveSource[field] = keys.first;
  }
  // A field with no explicit source takes the old key of its own name —
  // the identity route that makes "just reorder the fields" a one-liner.
  for (final field in order) {
    if (constants.containsKey(field)) continue;
    if (kinds[field] != 'preserve') {
      keyToField.putIfAbsent(field, () => field);
      continue;
    }
    if (preserveSource.containsKey(field)) continue;
    final owner = keyToField[field];
    if (owner != null && owner != field) {
      return fail(
        'the "preserve" field "$field" has no source key: the old key '
        '"$field" is already routed to "$owner". Give it its own "from" '
        'entry.',
      );
    }
    keyToField[field] = field;
    preserveSource[field] = field;
  }

  final rawAssign = args['assign'] ?? const <String, dynamic>{};
  if (rawAssign is! Map) {
    return fail('"assign" must be an object mapping tags to field names');
  }
  final assign = <String, String>{};
  for (final entry in rawAssign.entries) {
    final tag = entry.key;
    final field = entry.value;
    if (tag is! String || field is! String) {
      return fail('"assign" must map tag strings to field-name strings');
    }
    if (!kinds.containsKey(field)) {
      return fail('assign: "$tag" → "$field", which is not a declared field');
    }
    if (constants.containsKey(field)) {
      return fail('assign: "$tag" → "$field", which has a constant value');
    }
    if (kinds[field] == 'preserve') {
      return fail(
        'assign: "$tag" → "$field", which is a "preserve" field; preserved '
        'values are copied over untouched and cannot receive tags',
      );
    }
    final folded = tagLookupKey(tag);
    final previous = assign[folded];
    if (previous != null && previous != field) {
      return fail(
        'assign: "$tag" is assigned to both "$previous" and "$field"',
      );
    }
    assign[folded] = field;
  }

  // First occurrence wins, as in the tag sorter: a repeated priority entry
  // must not open a second bucket that reorders past the first.
  final priority = optStringList(args, 'tag_priority', maxLength: 500);
  final rank = <String, int>{};
  for (var i = 0; i < priority.length; i++) {
    rank.putIfAbsent(tagLookupKey(priority[i]), () => i);
  }

  return (
    error: null,
    shape: _Shape(
      order: order,
      kinds: kinds,
      constants: constants,
      keyToField: keyToField,
      preserveSource: preserveSource,
      assign: assign,
      unassignedField: unassignedField,
      priorityRank: rank,
      priorityLength: priority.length,
      dropEmpty: optBool(args, 'drop_empty'),
    ),
  );
}

typedef _BuildResult = ({String? error, Map<String, dynamic>? document});

/// Assembles one image's new document from its decoded old one.
///
/// Tags are bucketed, never re-typed: every tag written comes from the old
/// document's own string leaves, which is what makes the result a pure
/// regrouping. A tag whose source key is routed nowhere lands in the
/// catch-all rather than being dropped.
_BuildResult _buildDocument(
  _Shape shape,
  dynamic decoded, {
  required void Function(String key) onUnrouted,
  required void Function(String tag) onUnassigned,
}) {
  final buckets = <String, List<String>>{};
  void route(String tag, String? sourceKey) {
    var field = shape.assign[tagLookupKey(tag)];
    if (field == null && sourceKey != null) {
      field = shape.keyToField[sourceKey];
      if (field == null) onUnrouted(sourceKey);
    }
    if (field == null) onUnassigned(tag);
    (buckets[field ?? shape.unassignedField] ??= []).add(tag);
  }

  if (decoded is Map) {
    decoded.forEach((key, value) {
      final name = '$key';
      // A preserved key's value is copied whole; splitting it into tags and
      // re-emitting them is exactly what would destroy a prose field.
      if (shape.preservedKeys.contains(name)) return;
      // The same ignoreKeys the lossless check reads the source with: a
      // nested key that shares a preserved key's name must be invisible to
      // both sides, or the check fires on a tag the walk never offered.
      for (final tag in jsonCaptionTags(
        value,
        ignoreKeys: shape.preservedKeys,
      )) {
        route(tag, name);
      }
    });
  } else {
    // A document that is not an object has no keys to route by; everything
    // it carries flows through assign or into the catch-all.
    for (final tag in jsonCaptionTags(
      decoded,
      ignoreKeys: shape.preservedKeys,
    )) {
      route(tag, null);
    }
  }

  final out = <String, dynamic>{};
  for (final field in shape.order) {
    if (shape.constants.containsKey(field)) {
      out[field] = shape.constants[field];
      continue;
    }
    if (shape.kinds[field] == 'preserve') {
      final key = shape.preserveSource[field]!;
      if (decoded is Map && decoded.containsKey(key)) out[field] = decoded[key];
      continue;
    }
    final bucket = _applyPriority(
      buckets[field] ?? const [],
      shape.priorityRank,
      shape.priorityLength,
    );
    if (shape.kinds[field] == 'string') {
      if (bucket.length > 1) {
        return (
          error:
              'skipped, the "string" field "$field" would get '
              '${bucket.length} tags: ${bucket.join(", ")}',
          document: null,
        );
      }
      if (bucket.isEmpty && shape.dropEmpty) continue;
      out[field] = bucket.isEmpty ? '' : bucket.first;
      continue;
    }
    if (bucket.isEmpty && shape.dropEmpty) continue;
    out[field] = bucket;
  }
  return (error: null, document: out);
}

/// Orders one field's tags against the priority list: listed tags first in
/// that order, everything else keeping its relative position. A permutation
/// by construction — tags are bucketed, never re-typed.
List<String> _applyPriority(
  List<String> tags,
  Map<String, int> rank,
  int length,
) {
  if (rank.isEmpty || tags.length < 2) return tags;
  final buckets = List.generate(length, (_) => <String>[]);
  final rest = <String>[];
  for (final tag in tags) {
    final index = rank[tagLookupKey(tag)];
    if (index == null) {
      rest.add(tag);
    } else {
      buckets[index].add(tag);
    }
  }
  return [for (final bucket in buckets) ...bucket, ...rest];
}
