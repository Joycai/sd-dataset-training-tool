import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dataset_training_tool/app_state.dart';
import 'package:dataset_training_tool/models/merge_rules.dart';
import 'package:dataset_training_tool/services/agent/agent_tools.dart';
import 'package:dataset_training_tool/services/agent/character_sheet.dart';
import 'package:dataset_training_tool/services/agent/merge_rule_tools.dart';
import 'package:dataset_training_tool/services/settings_service.dart';

CharacterMergeRules _rules({
  String character = 'Aoi',
  String trigger = 'aoichr',
  List<String> identity = const ['blonde hair'],
  List<String> conflicts = const [],
  List<GarmentRule> garments = const [],
}) => CharacterMergeRules(
  id: '',
  character: character,
  triggerWord: trigger,
  identityTags: identity,
  conflictTags: conflicts,
  garments: garments,
);

void main() {
  group('parseSheetTags', () {
    test('splits on commas and newlines and trims', () {
      expect(
        parseSheetTags('dress, gloves\nhigh heel boots ,\n\n hair ribbon'),
        ['dress', 'gloves', 'high heel boots', 'hair ribbon'],
      );
    });

    test('an empty field yields no tags', () {
      expect(parseSheetTags('  ,\n , '), isEmpty);
    });
  });

  group('buildCharacterSheetTask', () {
    test('carries every filled field and the sample size', () {
      final task = buildCharacterSheetTask(
        const CharacterSheetInput(
          triggerWord: 'aoichr',
          identityTags: 'blonde hair, twintails',
          garmentTags: 'dress\nhigh heel boots',
          extraNotes: 'keep the ribbon out of the caption',
          sampleSize: 8,
        ),
      );
      expect(task, contains('aoichr'));
      expect(task, contains('- blonde hair'));
      expect(task, contains('- twintails'));
      expect(task, contains('- dress'));
      expect(task, contains('- high heel boots'));
      expect(task, contains('keep the ribbon out of the caption'));
      expect(task, contains('pick 8 images'));
      expect(task, contains('propose_merge_rules'));
    });

    test('an empty sheet still produces a runnable task', () {
      final task = buildCharacterSheetTask(const CharacterSheetInput());
      expect(task, contains('empty'));
      expect(task, contains('propose_merge_rules'));
    });

    test('forbids writing captions during the planning phase', () {
      final task = buildCharacterSheetTask(
        const CharacterSheetInput(triggerWord: 'aoichr'),
      );
      expect(task, contains('do NOT write any caption'));
    });
  });

  group('validateMergeRules', () {
    test('accepts a consistent rule set', () {
      expect(
        validateMergeRules(
          _rules(
            identity: ['blonde hair', 'large breasts'],
            conflicts: ['brown hair', 'medium breasts'],
            garments: const [
              GarmentRule(
                tag: 'high heel boots',
                evidence: ['high heels', 'boots'],
              ),
              GarmentRule(tag: 'gloves', evidence: ['gloves']),
            ],
          ),
        ),
        isNull,
      );
    });

    test('rejects a tag that is both written and removed', () {
      expect(
        validateMergeRules(
          _rules(identity: ['blonde hair'], conflicts: ['Blonde Hair']),
        ),
        contains('blonde hair'),
      );
    });

    test('rejects evidence shared by two garments', () {
      final problem = validateMergeRules(
        _rules(
          garments: const [
            GarmentRule(tag: 'high heel boots', evidence: ['boots']),
            GarmentRule(tag: 'thigh boots', evidence: ['Boots']),
          ],
        ),
      );
      expect(problem, contains('only one garment'));
    });

    test('rejects evidence that conflict_tags would strip first', () {
      final problem = validateMergeRules(
        _rules(
          conflicts: ['skirt'],
          garments: const [
            GarmentRule(tag: 'dress', evidence: ['skirt']),
          ],
        ),
      );
      expect(problem, contains('never be written'));
    });

    test('rejects a garment tag that conflict_tags removes', () {
      final problem = validateMergeRules(
        _rules(
          conflicts: ['dress'],
          garments: const [
            GarmentRule(tag: 'dress', evidence: ['skirt']),
          ],
        ),
      );
      expect(problem, contains('as fast as it is written'));
    });

    test('rejects two garments writing the same tag', () {
      final problem = validateMergeRules(
        _rules(
          garments: const [
            GarmentRule(tag: 'gloves', evidence: ['gloves']),
            GarmentRule(tag: 'Gloves', evidence: ['elbow gloves']),
          ],
        ),
      );
      expect(problem, contains('same tag'));
    });

    test('rejects a garment tag claimed as another garment\'s evidence', () {
      // The application pass treats a garment's own tag as evidence for
      // itself, so this leaves "dress" with two owners.
      final problem = validateMergeRules(
        _rules(
          garments: const [
            GarmentRule(tag: 'dress', evidence: ['skirt']),
            GarmentRule(tag: 'gown', evidence: ['Dress']),
          ],
        ),
      );
      expect(problem, contains('which one it means'));
    });

    test('a garment with no evidence is legal — it simply never fires', () {
      expect(
        validateMergeRules(
          _rules(garments: const [GarmentRule(tag: 'gloves')]),
        ),
        isNull,
      );
    });
  });

  group('propose_merge_rules', () {
    late List<CharacterMergeRules> saved;
    late ToolRegistry registry;

    setUp(() {
      saved = [];
      registry = ToolRegistry(
        buildMergeRuleTools((rules) async {
          final stored = rules.withId('r${saved.length}');
          saved.add(stored);
          return stored;
        }),
      );
    });

    Future<Map<String, dynamic>> call(Map<String, dynamic> args) async {
      final result = await registry.dispatch(
        'propose_merge_rules',
        jsonEncode(args),
      );
      return jsonDecode(result.text) as Map<String, dynamic>;
    }

    test('saves a well-formed proposal and reports what never fires', () async {
      final out = await call({
        'character': 'Aoi',
        'trigger_word': 'aoichr',
        'identity_tags': ['blonde hair', 'twintails'],
        'conflict_tags': ['brown hair'],
        'garments': [
          {
            'tag': 'dress',
            'evidence': ['dress', 'skirt'],
            'note': '下半身特写只会给 skirt',
          },
          {'tag': 'gloves', 'evidence': <String>[]},
        ],
        'passthrough': ['expression', 'background'],
        'sampled_images': 12,
      });

      expect(out['saved'], isTrue);
      expect(out['id'], 'r0');
      expect(out['never_written'], ['gloves']);
      expect(saved.single.triggerWord, 'aoichr');
      expect(saved.single.garments.first.evidence, ['dress', 'skirt']);
      expect(saved.single.sampledImages, 12);
    });

    test('a contradiction is rejected and nothing is saved', () async {
      final out = await call({
        'trigger_word': 'aoichr',
        'conflict_tags': ['skirt'],
        'garments': [
          {
            'tag': 'dress',
            'evidence': ['skirt'],
          },
        ],
      });
      expect(out['error'], contains('nothing was saved'));
      expect(saved, isEmpty);
    });

    test('a garment without a tag is reported, not silently dropped', () async {
      final out = await call({
        'trigger_word': 'aoichr',
        'garments': [
          {'tag': 'dress', 'evidence': <String>[]},
          {
            'tag': '',
            'evidence': <String>['gloves'],
          },
        ],
      });
      expect(out['error'], contains('empty or missing "tag"'));
      expect(saved, isEmpty);
    });

    test('rules that would change nothing are rejected', () async {
      final out = await call({
        'passthrough': ['expression'],
        'garments': <Map<String, dynamic>>[],
      });
      expect(out['error'], contains('would not change any caption'));
      expect(saved, isEmpty);
    });
  });

  group('merge rules persistence', () {
    test('round-trips through JSON', () {
      final decoded = decodeMergeRules(
        encodeMergeRules([
          _rules(
            conflicts: ['brown hair'],
            garments: const [
              GarmentRule(tag: 'dress', evidence: ['skirt'], note: 'why'),
            ],
          ).withId('r1'),
        ]),
      );
      expect(decoded.single.character, 'Aoi');
      expect(decoded.single.garments.single.note, 'why');
      expect(decoded.single.garments.single.evidence, ['skirt']);
    });

    test('a corrupt preference decodes to nothing rather than throwing', () {
      expect(decodeMergeRules('{not json'), isEmpty);
      expect(decodeMergeRules('{"a":1}'), isEmpty);
    });

    group('AppState', () {
      setUp(() => SharedPreferences.setMockInitialValues({}));

      Future<AppState> load() async {
        final state = AppState(SettingsService());
        await state.loadSettings();
        return state;
      }

      test('re-running the skill replaces the same character', () async {
        final state = await load();
        await state.saveMergeRules(_rules(identity: ['blonde hair']));
        await state.saveMergeRules(_rules(identity: ['silver hair']));
        expect(state.mergeRuleSets, hasLength(1));
        expect(state.mergeRuleSets.single.identityTags, ['silver hair']);
      });

      test('a different character is kept alongside, newest first', () async {
        final state = await load();
        await state.saveMergeRules(_rules(character: 'Aoi'));
        await state.saveMergeRules(_rules(character: 'Rin'));
        expect(
          [for (final r in state.mergeRuleSets) r.character],
          ['Rin', 'Aoi'],
        );
      });

      test('unnamed rule sets stack instead of overwriting', () async {
        final state = await load();
        await state.saveMergeRules(_rules(character: ''));
        await state.saveMergeRules(_rules(character: ''));
        expect(state.mergeRuleSets, hasLength(2));
      });

      test('the list is capped', () async {
        final state = await load();
        for (var i = 0; i < AppState.kMaxMergeRuleSets + 5; i++) {
          await state.saveMergeRules(_rules(character: 'c$i'));
        }
        expect(state.mergeRuleSets, hasLength(AppState.kMaxMergeRuleSets));
        expect(state.mergeRuleSets.first.character, isNot('c0'));
      });

      test('saved rules survive a reload', () async {
        final state = await load();
        await state.saveMergeRules(
          _rules(
            garments: const [
              GarmentRule(tag: 'dress', evidence: ['skirt']),
            ],
          ),
        );
        final reloaded = await load();
        expect(reloaded.mergeRuleSets.single.garments.single.tag, 'dress');
      });

      test('delete removes one rule set', () async {
        final state = await load();
        final stored = await state.saveMergeRules(_rules());
        await state.deleteMergeRules(stored.id);
        expect(state.mergeRuleSets, isEmpty);
      });
    });
  });
}
