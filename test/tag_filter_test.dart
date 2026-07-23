import 'package:flutter_test/flutter_test.dart';

import 'package:dataset_training_tool/models/tag_filter.dart';

TagFilterCondition has(String tag) =>
    TagFilterCondition.create(tag, exclude: false);
TagFilterCondition lacks(String tag) =>
    TagFilterCondition.create(tag, exclude: true);
TagFilterGroup and(List<TagFilterNode> children) =>
    TagFilterGroup.create(TagFilterOp.and, children: children);
TagFilterGroup or(List<TagFilterNode> children) =>
    TagFilterGroup.create(TagFilterOp.or, children: children);

void main() {
  group('matches', () {
    test('conditions and empty group', () {
      expect(has('a').matches({'a', 'b'}), isTrue);
      expect(has('a').matches({'b'}), isFalse);
      expect(lacks('a').matches({'b'}), isTrue);
      expect(lacks('a').matches({'a'}), isFalse);
      // Empty group is neutral.
      expect(and([]).matches({'a'}), isTrue);
      expect(or([]).matches(const {}), isTrue);
    });

    test('and / or semantics', () {
      final both = and([has('a'), has('b')]);
      expect(both.matches({'a', 'b'}), isTrue);
      expect(both.matches({'a'}), isFalse);

      final either = or([has('a'), has('b')]);
      expect(either.matches({'a'}), isTrue);
      expect(either.matches({'c'}), isFalse);
    });

    test('nested: (a or b) and not c', () {
      final expr = and([
        or([has('a'), has('b')]),
        lacks('c'),
      ]);
      expect(expr.matches({'a'}), isTrue);
      expect(expr.matches({'b', 'd'}), isTrue);
      expect(expr.matches({'a', 'c'}), isFalse);
      expect(expr.matches({'d'}), isFalse);
      // Uncaptioned image: empty tag set fails the include arm.
      expect(expr.matches(const {}), isFalse);
    });
  });

  group('rebuild helpers', () {
    test('add / remove / toggle keep ids stable elsewhere', () {
      var root = and([has('a')]);
      final aId = root.children.single.id;

      root = filterAddTo(root, root.id, has('b'));
      expect(root.children, hasLength(2));
      expect(root.children.first.id, aId);

      root = filterToggleOp(root, root.id);
      expect(root.op, TagFilterOp.or);

      final b = root.children.last as TagFilterCondition;
      root = filterToggleRole(root, b.id);
      expect((root.children.last as TagFilterCondition).exclude, isTrue);
      expect((root.children.first as TagFilterCondition).exclude, isFalse);

      root = filterRemove(root, aId);
      expect(root.children.single.id, b.id);
    });

    test('removing down to one child lifts the sub-group', () {
      var root = and([
        or([has('a'), has('x')]),
        has('b'),
      ]);
      final subGroup = root.children.first as TagFilterGroup;
      root = filterRemove(root, subGroup.children.first.id);
      // One child left in the sub-group -> lifted into the root.
      expect(root.children.whereType<TagFilterGroup>(), isEmpty);
      expect(
        root.children.whereType<TagFilterCondition>().map((c) => c.tag),
        ['x', 'b'],
      );
    });

    test('dissolve lifts children at the group position', () {
      final sub = or([has('a'), has('b')]);
      var root = and([has('x'), sub, has('y')]);
      root = filterDissolve(root, sub.id);
      expect(
        root.children.whereType<TagFilterCondition>().map((c) => c.tag),
        ['x', 'a', 'b', 'y'],
      );
    });

    test('filterRemoveTag drops every condition on the tag', () {
      var root = and([
        has('a'),
        or([lacks('a'), has('b')]),
      ]);
      root = filterRemoveTag(root, 'a');
      // The or-group is left with one child and gets lifted.
      expect(
        root.children.whereType<TagFilterCondition>().map((c) => c.tag),
        ['b'],
      );
    });

    test('normalize keeps the root group even when empty', () {
      var root = and([or([])]);
      root = filterNormalize(root);
      expect(root.isEmpty, isTrue);
      expect(root.op, TagFilterOp.and);
    });
  });

  test('referenced tags split by role', () {
    final root = and([
      has('a'),
      or([lacks('b'), has('a'), lacks('c')]),
    ]);
    final refs = filterReferencedTags(root);
    expect(refs.included, {'a'});
    expect(refs.excluded, {'b', 'c'});
  });

  test('JSON round trip', () {
    final root = and([
      has('shiny clothes'),
      or([has('leotard'), lacks('shiny skin')]),
    ]);
    final decoded = TagFilterGroup.decode(root.encode());
    expect(decoded, isNotNull);
    expect(decoded!.encode(), root.encode());
    expect(TagFilterGroup.decode('not json'), isNull);
  });
}
