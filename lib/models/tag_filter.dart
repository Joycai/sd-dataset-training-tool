import 'dart:convert';

/// Boolean tag-filter expression for the dataset gallery.
///
/// Two node kinds: a condition ("has tag" / "lacks tag") and a group. A group
/// is one pair of parentheses and carries a single operator for all of its
/// children — mixing AND and OR at one level is unrepresentable, so the
/// classic `a OR b AND c` precedence ambiguity cannot be built. Sub-groups
/// give the full expressive power of arbitrarily parenthesized expressions.
///
/// Nodes are immutable; edits go through the rebuild helpers below, which
/// return new trees. Ids are stable across rebuilds so the UI can target
/// nodes.
enum TagFilterOp { and, or }

sealed class TagFilterNode {
  const TagFilterNode(this.id);

  final int id;

  /// Process-wide id source; uniqueness only matters within one tree.
  static int _nextId = 0;
  static int nextId() => _nextId++;

  bool matches(Set<String> tags);

  Map<String, dynamic> toJson();

  static TagFilterNode fromJson(Map<String, dynamic> json) {
    if (json.containsKey('tag')) {
      return TagFilterCondition.create(
        json['tag'] as String,
        exclude: json['exclude'] as bool? ?? false,
      );
    }
    return TagFilterGroup.create(
      json['op'] == 'or' ? TagFilterOp.or : TagFilterOp.and,
      children: [
        for (final child in (json['children'] as List<dynamic>? ?? const []))
          TagFilterNode.fromJson(child as Map<String, dynamic>),
      ],
    );
  }
}

class TagFilterCondition extends TagFilterNode {
  const TagFilterCondition(super.id, this.tag, {required this.exclude});

  TagFilterCondition.create(String tag, {required bool exclude})
      : this(TagFilterNode.nextId(), tag, exclude: exclude);

  final String tag;

  /// false = image must have the tag; true = image must not.
  final bool exclude;

  @override
  bool matches(Set<String> tags) => tags.contains(tag) != exclude;

  @override
  Map<String, dynamic> toJson() => {'tag': tag, 'exclude': exclude};
}

class TagFilterGroup extends TagFilterNode {
  const TagFilterGroup(super.id, this.op, this.children);

  TagFilterGroup.create(TagFilterOp op, {List<TagFilterNode>? children})
      : this(TagFilterNode.nextId(), op, children ?? const []);

  final TagFilterOp op;
  final List<TagFilterNode> children;

  /// An empty group is neutral: it never constrains the gallery.
  bool get isEmpty => children.isEmpty;

  @override
  bool matches(Set<String> tags) {
    if (children.isEmpty) return true;
    return op == TagFilterOp.and
        ? children.every((c) => c.matches(tags))
        : children.any((c) => c.matches(tags));
  }

  TagFilterGroup copyWith({TagFilterOp? op, List<TagFilterNode>? children}) =>
      TagFilterGroup(id, op ?? this.op, children ?? this.children);

  @override
  Map<String, dynamic> toJson() => {
        'op': op == TagFilterOp.or ? 'or' : 'and',
        'children': [for (final c in children) c.toJson()],
      };

  String encode() => jsonEncode(toJson());

  static TagFilterGroup? decode(String json) {
    try {
      final node = TagFilterNode.fromJson(
        jsonDecode(json) as Map<String, dynamic>,
      );
      return node is TagFilterGroup ? node : null;
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }
}

// --- Rebuild helpers -----------------------------------------------------
//
// All take the root and return a new root; unknown ids are no-ops. The root
// group itself is never lifted or dropped — an empty root means "filter off".

/// Appends [child] to the group with [groupId].
TagFilterGroup filterAddTo(
  TagFilterGroup root,
  int groupId,
  TagFilterNode child,
) {
  TagFilterNode walk(TagFilterNode node) {
    if (node is! TagFilterGroup) return node;
    if (node.id == groupId) {
      return node.copyWith(children: [...node.children, child]);
    }
    return node.copyWith(children: [for (final c in node.children) walk(c)]);
  }

  return walk(root) as TagFilterGroup;
}

/// Removes the node with [nodeId] (condition or whole sub-group).
TagFilterGroup filterRemove(TagFilterGroup root, int nodeId) {
  TagFilterNode walk(TagFilterNode node) {
    if (node is! TagFilterGroup) return node;
    return node.copyWith(children: [
      for (final c in node.children)
        if (c.id != nodeId) walk(c),
    ]);
  }

  return filterNormalize(walk(root) as TagFilterGroup);
}

/// Flips the operator of the group with [groupId].
TagFilterGroup filterToggleOp(TagFilterGroup root, int groupId) {
  TagFilterNode walk(TagFilterNode node) {
    if (node is! TagFilterGroup) return node;
    final flipped = node.id == groupId
        ? (node.op == TagFilterOp.and ? TagFilterOp.or : TagFilterOp.and)
        : node.op;
    return node.copyWith(
      op: flipped,
      children: [for (final c in node.children) walk(c)],
    );
  }

  return walk(root) as TagFilterGroup;
}

/// Flips include/exclude on the condition with [conditionId].
TagFilterGroup filterToggleRole(TagFilterGroup root, int conditionId) {
  TagFilterNode walk(TagFilterNode node) {
    if (node is TagFilterCondition) {
      return node.id == conditionId
          ? TagFilterCondition(node.id, node.tag, exclude: !node.exclude)
          : node;
    }
    final group = node as TagFilterGroup;
    return group.copyWith(children: [for (final c in group.children) walk(c)]);
  }

  return walk(root) as TagFilterGroup;
}

/// Dissolves the sub-group with [groupId]: its children lift into the parent
/// at its position. The root cannot be dissolved.
TagFilterGroup filterDissolve(TagFilterGroup root, int groupId) {
  TagFilterNode walk(TagFilterNode node) {
    if (node is! TagFilterGroup) return node;
    final next = <TagFilterNode>[];
    for (final c in node.children) {
      if (c is TagFilterGroup && c.id == groupId) {
        next.addAll(c.children);
      } else {
        next.add(walk(c));
      }
    }
    return node.copyWith(children: next);
  }

  return filterNormalize(walk(root) as TagFilterGroup);
}

/// Drops every condition on [tag] — used when the tag is deleted from the
/// dataset (an include would blank the gallery, an exclude is trivially
/// true; both are stale).
TagFilterGroup filterRemoveTag(TagFilterGroup root, String tag) {
  TagFilterNode walk(TagFilterNode node) {
    if (node is! TagFilterGroup) return node;
    return node.copyWith(children: [
      for (final c in node.children)
        if (c is! TagFilterCondition || c.tag != tag) walk(c),
    ]);
  }

  return filterNormalize(walk(root) as TagFilterGroup);
}

/// Drops empty sub-groups and lifts single-child sub-groups; the root is
/// kept as a group regardless.
TagFilterGroup filterNormalize(TagFilterGroup root) {
  TagFilterNode? walk(TagFilterNode node, {required bool isRoot}) {
    if (node is! TagFilterGroup) return node;
    final children = <TagFilterNode>[];
    for (final c in node.children) {
      final kept = walk(c, isRoot: false);
      if (kept != null) children.add(kept);
    }
    if (!isRoot) {
      if (children.isEmpty) return null;
      if (children.length == 1) return children.single;
    }
    return node.copyWith(children: children);
  }

  return walk(root, isRoot: true)! as TagFilterGroup;
}

/// Every tag referenced anywhere, split by role — drives the chip highlights
/// in the dataset tag list.
({Set<String> included, Set<String> excluded}) filterReferencedTags(
  TagFilterGroup root,
) {
  final included = <String>{};
  final excluded = <String>{};
  void walk(TagFilterNode node) {
    if (node is TagFilterCondition) {
      (node.exclude ? excluded : included).add(node.tag);
    } else if (node is TagFilterGroup) {
      node.children.forEach(walk);
    }
  }

  walk(root);
  return (included: included, excluded: excluded);
}
