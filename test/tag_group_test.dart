import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dataset_training_tool/app_state.dart';
import 'package:dataset_training_tool/models/tag_group.dart';
import 'package:dataset_training_tool/services/settings_service.dart';

void main() {
  group('TagGroup JSON', () {
    test('encode/decode round trip', () {
      const groups = [
        TagGroup(id: '1', name: 'outfit', color: 0xFF6A9BDD, tags: ['skirt']),
        TagGroup(id: '2', name: 'pose', color: 0xFFD9925B, tags: []),
      ];
      final decoded = decodeTagGroups(encodeTagGroups(groups));
      expect(decoded, hasLength(2));
      expect(decoded[0].id, '1');
      expect(decoded[0].name, 'outfit');
      expect(decoded[0].color, 0xFF6A9BDD);
      expect(decoded[0].tags, ['skirt']);
      expect(decoded[1].tags, isEmpty);
    });

    test('corrupt json decodes to empty', () {
      expect(decodeTagGroups('not json'), isEmpty);
      expect(decodeTagGroups('{"a":1}'), isEmpty);
      expect(decodeTagGroups('[{"id":"x"}]'), isEmpty);
    });
  });

  group('AppState tag groups', () {
    late AppState state;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      state = AppState(SettingsService());
      await state.loadSettings();
      await state.addCommonTags(['a', 'b', 'c', 'd']);
    });

    test('create / move / lookup', () async {
      final g = await state.createTagGroup('outfit', 0xFF6A9BDD);
      await state.moveTagsToGroup(['a', 'b'], g.id);

      expect(state.groupOfTag('a')?.id, g.id);
      expect(state.groupOfTag('c'), isNull);
      expect(state.ungroupedTags, ['c', 'd']);
      expect(state.tagGroups.single.tags, ['a', 'b']);
    });

    test('membership is exclusive: moving removes from the old group',
        () async {
      final g1 = await state.createTagGroup('one', 1);
      final g2 = await state.createTagGroup('two', 2);
      await state.moveTagsToGroup(['a', 'b'], g1.id);
      await state.moveTagsToGroup(['b'], g2.id);

      expect(state.tagGroups[0].tags, ['a']);
      expect(state.tagGroups[1].tags, ['b']);
      expect(state.groupOfTag('b')?.id, g2.id);
    });

    test('move to null ungroups', () async {
      final g = await state.createTagGroup('one', 1);
      await state.moveTagsToGroup(['a'], g.id);
      await state.moveTagsToGroup(['a'], null);

      expect(state.groupOfTag('a'), isNull);
      expect(state.tagGroups.single.tags, isEmpty);
    });

    test('duplicates and unknown tags are ignored on move', () async {
      final g = await state.createTagGroup('one', 1);
      await state.moveTagsToGroup(['a', 'a', 'nope'], g.id);
      expect(state.tagGroups.single.tags, ['a']);
    });

    test('deleting a group returns its tags to ungrouped', () async {
      final g = await state.createTagGroup('one', 1);
      await state.moveTagsToGroup(['a', 'b'], g.id);
      await state.deleteTagGroup(g.id);

      expect(state.tagGroups, isEmpty);
      expect(state.ungroupedTags, ['a', 'b', 'c', 'd']);
    });

    test('rename and recolor', () async {
      final g = await state.createTagGroup('one', 1);
      await state.updateTagGroup(g.id, name: 'renamed', color: 42);
      expect(state.tagGroups.single.name, 'renamed');
      expect(state.tagGroups.single.color, 42);
    });

    test('removing library tags prunes group members', () async {
      final g = await state.createTagGroup('one', 1);
      await state.moveTagsToGroup(['a', 'b'], g.id);
      await state.removeCommonTags(['a']);

      expect(state.tagGroups.single.tags, ['b']);
      expect(state.groupOfTag('a'), isNull);
    });

    test('import/replace prunes group members but keeps empty groups',
        () async {
      final g = await state.createTagGroup('one', 1);
      await state.moveTagsToGroup(['a'], g.id);
      await state.updateCommonTags(['x', 'y']);

      expect(state.tagGroups.single.tags, isEmpty);
      expect(state.ungroupedTags, ['x', 'y']);
    });

    test('groups persist across reload', () async {
      final g = await state.createTagGroup('one', 0xFF9B84E0);
      await state.moveTagsToGroup(['a'], g.id);

      final reloaded = AppState(SettingsService());
      await reloaded.loadSettings();
      expect(reloaded.tagGroups.single.name, 'one');
      expect(reloaded.tagGroups.single.color, 0xFF9B84E0);
      expect(reloaded.groupOfTag('a')?.id, g.id);
    });
  });
}
