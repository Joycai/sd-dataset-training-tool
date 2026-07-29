import 'package:flutter_test/flutter_test.dart';

import 'package:dataset_training_tool/models/merge_rules.dart';

/// The rule set most tests use: a blonde twintailed character in a dress,
/// gloves and high heel boots, where the tagger habitually undersells the
/// dress as a skirt and the boots as plain heels.
const _rules = CharacterMergeRules(
  id: 'r1',
  character: 'Aoi',
  triggerWord: 'aoichr',
  identityTags: ['blonde hair', 'twintails', 'large breasts'],
  conflictTags: ['brown hair', 'black hair', 'medium breasts', 'ponytail'],
  garments: [
    GarmentRule(tag: 'dress', evidence: ['dress', 'skirt']),
    GarmentRule(tag: 'gloves', evidence: ['gloves', 'elbow gloves']),
    GarmentRule(tag: 'high heel boots', evidence: ['high heels', 'boots']),
  ],
);

List<ScoredTag> _scored(Map<String, double> tags) =>
    [for (final e in tags.entries) (tag: e.key, probability: e.value)]
      ..sort((a, b) => b.probability.compareTo(a.probability));

List<String>? _apply(
  Map<String, double> predicted, {
  List<String> current = const [],
  CharacterMergeRules rules = _rules,
  double threshold = 0.35,
  double evidenceThreshold = 0.2,
}) => applyMergeRules(
  current: current,
  predicted: _scored(predicted),
  rules: rules,
  threshold: threshold,
  evidenceThreshold: evidenceThreshold,
);

void main() {
  test('the trigger word leads and the fixed traits always follow', () {
    final out = _apply({'1girl': 0.99, 'smile': 0.8})!;
    expect(out.take(4), [
      'aoichr',
      'blonde hair',
      'twintails',
      'large breasts',
    ]);
  });

  test('the tagger keeps expression, background, pose and framing', () {
    final out = _apply({
      'smile': 0.9,
      'outdoors': 0.8,
      'standing': 0.7,
      'upper body': 0.6,
    })!;
    expect(out, containsAll(['smile', 'outdoors', 'standing', 'upper body']));
  });

  test('passthrough keeps the tagger\'s confidence order', () {
    final out = _apply({'standing': 0.5, 'smile': 0.9, 'outdoors': 0.7})!;
    expect(out.sublist(out.indexOf('smile')), [
      'smile',
      'outdoors',
      'standing',
    ]);
  });

  test('a lower-body crop\'s skirt becomes the dress and is spent', () {
    final out = _apply({'skirt': 0.9, 'thighs': 0.6})!;
    expect(out, contains('dress'));
    expect(out, isNot(contains('skirt')));
    expect(out, contains('thighs'));
  });

  test('an outfit item the tagger never saw is not written', () {
    // A close-up of the face: no garment evidence at all.
    final out = _apply({'close-up': 0.9, 'smile': 0.8})!;
    expect(out, isNot(contains('gloves')));
    expect(out, isNot(contains('dress')));
    expect(out, isNot(contains('high heel boots')));
    expect(out, [
      'aoichr',
      'blonde hair',
      'twintails',
      'large breasts',
      'close-up',
      'smile',
    ]);
  });

  test('several evidence tags for one garment collapse into one tag', () {
    final out = _apply({'high heels': 0.8, 'boots': 0.7})!;
    expect(out.where((t) => t == 'high heel boots'), hasLength(1));
    expect(out, isNot(contains('high heels')));
    expect(out, isNot(contains('boots')));
  });

  test('conflicting traits from the tagger are removed', () {
    final out = _apply({'brown hair': 0.9, 'ponytail': 0.8, 'smile': 0.7})!;
    expect(out, isNot(contains('brown hair')));
    expect(out, isNot(contains('ponytail')));
    expect(out, contains('blonde hair'));
    expect(out, contains('twintails'));
  });

  test('a trait the tagger also saw is not written twice', () {
    final out = _apply({'blonde hair': 0.95, 'smile': 0.7})!;
    expect(out.where((t) => t == 'blonde hair'), hasLength(1));
    expect(out.indexOf('blonde hair'), 1);
  });

  group('the two thresholds', () {
    test('faint garment evidence still fires the garment', () {
      final out = _apply({'gloves': 0.25, 'smile': 0.9})!;
      expect(out, contains('gloves'));
    });

    test('a faint ordinary tag does not survive', () {
      final out = _apply({'gloves': 0.25, 'castle': 0.25, 'smile': 0.9})!;
      expect(out, isNot(contains('castle')));
    });

    test('evidence below even the lower bar does not fire', () {
      final out = _apply({'gloves': 0.1, 'smile': 0.9})!;
      expect(out, isNot(contains('gloves')));
    });

    test(
      'raising the evidence bar to the threshold disables the allowance',
      () {
        final out = _apply({
          'gloves': 0.25,
          'smile': 0.9,
        }, evidenceThreshold: 0.35)!;
        expect(out, isNot(contains('gloves')));
      },
    );

    test('an evidence bar above the threshold is clamped, not honoured', () {
      // Otherwise `skirt` would clear the passthrough cut, fail the evidence
      // cut, and leak through as itself — the one outcome the rules exist to
      // prevent.
      final out = _apply({'skirt': 0.5}, evidenceThreshold: 0.9)!;
      expect(out, contains('dress'));
      expect(out, isNot(contains('skirt')));
    });
  });

  group('degenerate rule sets', () {
    test('a garment the tagger names outright fires it', () {
      const rules = CharacterMergeRules(
        id: 'r',
        triggerWord: 'x',
        garments: [
          GarmentRule(tag: 'gloves', evidence: ['elbow gloves']),
        ],
      );
      final out = _apply({'gloves': 0.8}, rules: rules)!;
      expect(out, ['x', 'gloves']);
    });

    test('an empty rule set still writes the tagger\'s output', () {
      const rules = CharacterMergeRules(id: 'r', triggerWord: 'x');
      final out = _apply({'smile': 0.9, 'faint': 0.1}, rules: rules)!;
      expect(out, ['x', 'smile']);
    });
  });

  group('the unchanged contract', () {
    test('an identical caption is reported as no change', () {
      final result = _apply(
        {'smile': 0.9},
        current: [
          'aoichr',
          'blonde hair',
          'twintails',
          'large breasts',
          'smile',
        ],
      );
      expect(result, isNull);
    });

    test('a reordered caption counts as a change', () {
      final result = _apply(
        {'smile': 0.9},
        current: [
          'smile',
          'aoichr',
          'blonde hair',
          'twintails',
          'large breasts',
        ],
      );
      expect(result, isNotNull);
    });

    test('an empty caption on an untagged image is a change', () {
      expect(_apply({'smile': 0.9}), isNotNull);
    });
  });
}
