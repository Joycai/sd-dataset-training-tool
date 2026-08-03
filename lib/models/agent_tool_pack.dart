/// Optional groups of assistant tools the user can switch off.
///
/// Tool schemas are re-sent on *every* turn, so a pack nobody uses is a
/// permanent toll on the context window rather than a one-off cost: the three
/// packs here are ~2,450 tokens together, a quarter of a 32K window, and most
/// conversations touch none of them. Everything a dataset-curation session
/// actually needs — reading, tagging, converting captions — stays unconditional
/// and is not a pack.
///
/// Switching a pack off does not hide a feature from the user; it only stops
/// the *assistant* from being handed those tools. The panels they belong to
/// keep working by hand.
enum AgentToolPack {
  /// `organize_tag_library`, `add_library_tags`, `remove_library_tags`,
  /// `update_tag_group`, `reorder_tag_groups`, `delete_tag_group`.
  ///
  /// On by default: "help me tidy my tag library" is a common ask, and the
  /// case where the library is still empty is exactly the one where the user
  /// most wants the assistant to fill it — so an "only when non-empty" rule
  /// would fire backwards.
  tagLibrary('tagLibrary', defaultEnabled: true),

  /// `list_tag_translations`, `fetch_danbooru_tag`, `write_tag_translations`.
  ///
  /// Off by default: the glossary is a deliberate side project, and the user
  /// who wants it goes looking for it.
  tagTranslation('tagTranslation', defaultEnabled: false),

  /// `propose_merge_rules` — the character-sheet flow's own tool.
  ///
  /// Off by default: it serves one specific workflow and costs 600 tokens a
  /// turn in every conversation that is not that workflow.
  mergeRules('mergeRules', defaultEnabled: false);

  const AgentToolPack(this.id, {required this.defaultEnabled});

  /// Stable persistence key; never reuse one for a different pack.
  final String id;

  final bool defaultEnabled;

  static AgentToolPack? fromId(String id) {
    for (final pack in values) {
      if (pack.id == id) return pack;
    }
    return null;
  }

  static Set<AgentToolPack> get defaults => {
    for (final pack in values)
      if (pack.defaultEnabled) pack,
  };

  /// Decodes stored ids. A null list is a first run — the defaults, not an
  /// empty set; an empty list is a user who really did switch everything off.
  static Set<AgentToolPack> decode(List<String>? ids) {
    if (ids == null) return defaults;
    return {
      for (final id in ids) ?fromId(id),
    };
  }
}
