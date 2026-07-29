/// The `propose_merge_rules` tool: phase A's only output.
///
/// The tool exists instead of letting the model print JSON in a reply because
/// the rules are meant to be *executed* later. That makes contradictions the
/// model cannot see — a tag that is both unconditionally stripped and used as
/// garment evidence — a real failure mode, so they are rejected here with an
/// explanation the model can act on rather than stored and hit in phase B.
library;

import '../../models/merge_rules.dart';
import 'agent_tools.dart';

/// Persists a proposal and returns it as stored (with its assigned id).
typedef MergeRulesSink =
    Future<CharacterMergeRules> Function(CharacterMergeRules rules);

List<AgentTool> buildMergeRuleTools(MergeRulesSink save) => [
  AgentTool(
    spec: const AgentToolSpec(
      name: 'propose_merge_rules',
      description:
          'Submit the merge rules for a character dataset: how the '
          'user\'s character sheet combines with the tagger\'s output '
          'for one image. Writes no captions — it saves the rules and '
          'shows them to the user for review. Call it once, at the end '
          'of the planning phase.\n'
          'The rules are applied per image as: trigger_word first, then '
          'identity_tags always, then every garment whose evidence the '
          'tagger produced for that image (replacing the evidence '
          'tags), then whatever the tagger said that no rule touched. '
          'conflict_tags are removed unconditionally.',
      parametersSchema: {
        'type': 'object',
        'properties': {
          'character': {
            'type': 'string',
            'description': 'short name for this rule set, for the user',
          },
          'trigger_word': {
            'type': 'string',
            'description': 'the LoRA trigger word; written as the first tag',
          },
          'identity_tags': {
            'type': 'array',
            'items': {'type': 'string'},
            'description':
                'fixed traits written on every image regardless of what '
                'the tagger saw (hair colour, hairstyle, breast size, '
                'eye colour)',
          },
          'conflict_tags': {
            'type': 'array',
            'items': {'type': 'string'},
            'description':
                'tagger tags removed from every image because they '
                'contradict identity_tags (other hair colours, other '
                'breast sizes). Never put garment evidence here — that '
                'is removed only when its garment fires.',
          },
          'garments': {
            'type': 'array',
            'description':
                'one entry per outfit item on the character sheet, '
                'including items the sample never showed (with empty '
                'evidence, so they are never written)',
            'items': {
              'type': 'object',
              'properties': {
                'tag': {
                  'type': 'string',
                  'description': 'the tag to write — the user\'s wording',
                },
                'evidence': {
                  'type': 'array',
                  'items': {'type': 'string'},
                  'description':
                      'tagger tags meaning this item is visible; any hit '
                      'writes "tag" and drops the hits. Each tag may be '
                      'evidence for one garment only.',
                },
                'note': {
                  'type': 'string',
                  'description':
                      'why this mapping, in the user\'s language; shown '
                      'on the review card',
                },
              },
              'required': ['tag'],
            },
          },
          'passthrough': {
            'type': 'array',
            'items': {'type': 'string'},
            'description':
                'tagger categories kept verbatim, as labels for the '
                'user (e.g. "expression", "background", "framing")',
          },
          'sampled_images': {
            'type': 'integer',
            'description': 'how many images you ran through the tagger',
          },
          'notes': {
            'type': 'string',
            'description':
                'caveats for the user, in their language: outfit items '
                'the sample never showed, traits the tagger disagreed '
                'with',
          },
        },
        'required': ['garments'],
      },
    ),
    handler: (args) async {
      final rules = CharacterMergeRules.fromJson({'id': '', ...args});
      // fromJson drops garments without a tag. Silently losing one would
      // leave the user reviewing a card that is missing an outfit item they
      // asked for, so make the model resend instead.
      final submitted = args['garments'];
      if (submitted is List && submitted.length != rules.garments.length) {
        return toolError(
          'nothing was saved: ${submitted.length - rules.garments.length} of '
          'the ${submitted.length} garments have an empty or missing "tag"',
        );
      }
      final problem = validateMergeRules(rules);
      if (problem != null) return toolError('nothing was saved: $problem');
      if (rules.isEmpty) {
        return toolError(
          'nothing was saved: the rules carry no trigger word, no '
          'identity tags and no garments, so they would not change any '
          'caption',
        );
      }
      final stored = await save(rules);
      return toolOk({
        'saved': true,
        'id': stored.id,
        'character': stored.character,
        'identity_tags': stored.identityTags.length,
        'conflict_tags': stored.conflictTags.length,
        'garments': [
          for (final g in stored.garments)
            {'tag': g.tag, 'evidence': g.evidence.length},
        ],
        'never_written': [
          for (final g in stored.garments)
            if (g.evidence.isEmpty) g.tag,
        ],
      });
    },
  ),
];

/// Returns the first contradiction that would make the rules unusable in the
/// application pass, or null when they are consistent.
///
/// Case-insensitive throughout: taggers and hand-typed sheets disagree on
/// capitalization, and two rules that differ only in case are the same rule
/// as far as caption text is concerned.
String? validateMergeRules(CharacterMergeRules rules) {
  final identity = {for (final t in rules.identityTags) t.toLowerCase()};
  final conflicts = {for (final t in rules.conflictTags) t.toLowerCase()};

  final bothWays = identity.intersection(conflicts);
  if (bothWays.isNotEmpty) {
    return 'these tags are listed as both identity_tags and conflict_tags, '
        'so they would be written and removed at once: '
        '${bothWays.join(", ")}';
  }

  // Evidence must map to exactly one garment: the application pass replaces
  // an evidence tag with its garment's tag, and two candidates have no
  // defensible winner.
  final owner = <String, String>{};
  for (final g in rules.garments) {
    for (final e in g.evidence) {
      final key = e.toLowerCase();
      final previous = owner[key];
      if (previous != null && previous != g.tag) {
        return '"$e" is evidence for both "$previous" and "${g.tag}"; each '
            'tagger tag may belong to only one garment';
      }
      owner[key] = g.tag;
      if (conflicts.contains(key)) {
        return '"$e" is evidence for "${g.tag}" but also listed in '
            'conflict_tags; conflict_tags are removed before any garment '
            'can fire, so the garment would never be written';
      }
    }
  }

  // A garment writing a tag that conflict_tags then strips is a rule that
  // undoes itself.
  for (final g in rules.garments) {
    if (conflicts.contains(g.tag.toLowerCase())) {
      return '"${g.tag}" is both a garment tag and a conflict_tag, so it '
          'would be removed as fast as it is written';
    }
  }

  final seen = <String>{};
  for (final g in rules.garments) {
    if (!seen.add(g.tag.toLowerCase())) {
      return 'two garment rules write the same tag "${g.tag}"; merge their '
          'evidence into one entry';
    }
  }

  return null;
}
