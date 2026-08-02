import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../l10n/app_localizations.dart';
import '../../models/llm_models.dart';
import '../../models/tag_dictionary.dart';
import '../../models/tag_translation.dart';
import '../../services/danbooru_api.dart';
import '../../services/llm/llm_client.dart';
import '../../services/tag_ai_translate.dart';
import '../../services/tag_dictionary_service.dart';
import '../../services/tag_translation_service.dart';
import '../../state/dataset_state.dart';
import '../../state/editor_session.dart';
import '../../theme/app_theme.dart';
import '../../utils/external_links.dart';
import '../../utils/tag_text.dart';
import '../../widgets/panel_widgets.dart';

/// What the dictionary knows about the workbench it was opened from.
///
/// A snapshot, not a live view: the manager is modal, so nothing behind it can
/// move while it is up, and taking a copy is what lets the same dialog open
/// from settings — where the dataset providers are not in scope at all — with
/// the dataset-shaped affordances simply absent instead of broken.
class TagDictionaryScope {
  const TagDictionaryScope({
    this.imageTags = const [],
    this.datasetTags = const [],
    this.datasetUsage = const {},
    this.imageCount = 0,
  });

  /// Tags on the image currently open in the editor, in caption order.
  final List<String> imageTags;

  /// Every tag in the dataset, busiest first, in the dataset's own spelling.
  ///
  /// Kept beside [datasetUsage] rather than derived from its keys: those are
  /// folded through [tagLookupKey], which lower-cases and turns underscores
  /// into spaces. Rendering a chip from one would show the user a tag their
  /// captions do not contain.
  final List<String> datasetTags;

  /// [tagLookupKey] of every tag in the dataset to how many images carry it.
  final Map<String, int> datasetUsage;

  /// Images in the active scope; the denominator of the usage bar.
  final int imageCount;

  bool get hasDataset => datasetTags.isNotEmpty;

  int? usageOf(String tag) => datasetUsage[tagLookupKey(tag)];
}

/// Snapshots the workbench state the dictionary can make use of.
TagDictionaryScope tagDictionaryScope({
  DatasetState? dataset,
  EditorSession? session,
}) {
  if (dataset == null) return const TagDictionaryScope();
  final tags = dataset.datasetTags;
  return TagDictionaryScope(
    imageTags: session?.hasImage == true ? List.of(session!.tags) : const [],
    datasetTags: [for (final entry in tags) entry.tag],
    datasetUsage: {
      for (final entry in tags) tagLookupKey(entry.tag): entry.count,
    },
    imageCount: dataset.totalCount,
  );
}

/// The same snapshot, taken off whatever providers [context] can see.
///
/// Nullable reads: provider answers null rather than throwing for a `T?`,
/// which is exactly the "opened from somewhere without a workbench above it"
/// case — the settings dialog lives above those providers.
TagDictionaryScope _scopeOf(BuildContext context) => tagDictionaryScope(
  dataset: context.read<DatasetState?>(),
  session: context.read<EditorSession?>(),
);

/// The dictionary window: browse and search tags, write their translations,
/// and add vocabulary danbooru does not have.
///
/// The list on the left is one of four views, chosen by the filter strip:
/// everything translated or hand-added, the tags on the open image, the ones
/// still untranslated, and the user's own additions. A non-empty search box
/// widens the first of those to the whole dictionary *and* matches on the
/// translations themselves — searching `长发` is the whole reason a
/// Chinese-speaking user keeps a glossary at all.
///
/// [initialTag] opens straight onto that tag's editor — the path taken from a
/// tag's own context menu, where the user has already picked the tag.
/// [initialQuery] only seeds the search box, for the panel buttons that carry
/// over a filter the user was typing rather than a tag they clicked.
/// [fetchOnOpen] runs the danbooru lookup immediately, for the context-menu
/// entry that promises exactly that.
///
/// [scope] overrides what would be read off [context]. Needed by the workbench
/// shortcut, whose `State.context` sits *above* the providers it installs in
/// its own `build`.
///
/// [api] is injectable for tests; the default talks to danbooru.
Future<void> showTagDictionaryDialog(
  BuildContext context, {
  String? initialTag,
  String? initialQuery,
  DanbooruApi? api,
  bool fetchOnOpen = false,
  TagDictionaryScope? scope,
}) {
  final resolved = scope ?? _scopeOf(context);
  return showDialog(
    context: context,
    builder: (_) => ChangeNotifierProvider.value(
      value: context.read<AppState>(),
      child: _TagDictionaryDialog(
        initialTag: initialTag,
        initialQuery: initialQuery,
        api: api,
        fetchOnOpen: fetchOnOpen,
        scope: resolved,
      ),
    ),
  );
}

/// How many dictionary hits the search lists. Well past what fits on screen —
/// the list scrolls — but bounded, because a two-letter query matches
/// thousands and every row builds a translation lookup.
const _searchLimit = 80;

/// How many missing-tag chips the collect banner draws before it stops and
/// says how many are left. A dataset can arrive with hundreds of unknown tags
/// and the banner is a prompt, not a list view.
const _missingChipLimit = 18;

/// Which list the left column is showing.
enum _DictFilter { all, thisImage, untranslated, custom }

/// What the right column is showing. The two forms replace what used to be
/// nested dialogs: a modal on top of a modal hides the very list the user is
/// working against.
enum _DictPane { detail, newTag, fetch }

class _TagDictionaryDialog extends StatefulWidget {
  const _TagDictionaryDialog({
    this.initialTag,
    this.initialQuery,
    this.api,
    this.fetchOnOpen = false,
    this.scope = const TagDictionaryScope(),
  });

  final String? initialTag;
  final String? initialQuery;
  final DanbooruApi? api;
  final bool fetchOnOpen;
  final TagDictionaryScope scope;

  @override
  State<_TagDictionaryDialog> createState() => _TagDictionaryDialogState();
}

class _TagDictionaryDialogState extends State<_TagDictionaryDialog> {
  late final TextEditingController _searchController = TextEditingController(
    // Seeded so the tag is also *findable* in the list beside its editor —
    // opening onto a selection the list does not contain reads as a glitch.
    text: _initialSelection ?? widget.initialQuery?.trim() ?? '',
  );
  late String _query = _searchController.text;

  /// The tag being edited, in danbooru spelling. Held as a name rather than an
  /// index because the list under it is rebuilt on every keystroke.
  late String? _selected = _initialSelection;

  _DictFilter _filter = _DictFilter.all;
  _DictPane _pane = _DictPane.detail;

  /// The incoming tag in the spelling the dictionary and glossary key on; a
  /// caption may have handed us `long hair`.
  String? get _initialSelection {
    final tag = widget.initialTag?.trim();
    return tag == null || tag.isEmpty ? null : danbooruTagName(tag);
  }

  late final DanbooruApi _api = widget.api ?? DanbooruApi();

  /// What danbooru said about each tag looked up in this session, keyed by
  /// [tagLookupKey]. Cached for the lifetime of the dialog only: it is a
  /// reference the user is reading off, not data this app owns, and re-fetching
  /// on the next open is one request.
  final Map<String, DanbooruTagInfo> _fetched = {};

  /// Whether a lookup is in flight. One at a time by construction — danbooru
  /// asks callers to go easy, and the user is looking at one tag anyway — so
  /// which tag it is for is never in question.
  bool _fetching = false;

  /// Set once the user dismisses the "these tags are not in the dictionary"
  /// banner, for this session only: it is a prompt, and a prompt that cannot
  /// be silenced is an alarm.
  bool _missingDismissed = false;

  @override
  void initState() {
    super.initState();
    if (widget.fetchOnOpen && _selected != null) {
      // After the first frame: the lookup calls setState, and the snack bar it
      // may raise needs a mounted ScaffoldMessenger.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _lookup(_selected!);
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  TagDictionaryService get _dictionary =>
      context.read<AppState>().tagDictionary;

  TagTranslationService get _glossary =>
      context.read<AppState>().tagTranslations;

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _select(String tag) => setState(() {
    _selected = tag;
    _pane = _DictPane.detail;
  });

  // --- The list ---------------------------------------------------------

  /// [tagLookupKey] of every tag the user added by hand.
  Set<String> get _customKeys => {
    for (final entry in _dictionary.customEntries) tagLookupKey(entry.name),
  };

  bool _isCustom(String tag) => _customKeys.contains(tagLookupKey(tag));

  /// One row for [tag], however it was reached. [custom] is passed in because
  /// callers that already hold the custom key set must not rebuild it per row.
  _DictRow _rowFor(String tag, {required bool custom}) {
    final hit = _dictionary.lookup(tag);
    return _DictRow(
      tag: tag,
      category: hit?.category,
      custom: custom,
      translation: _glossary.lookup(tag),
      postCount: hit?.postCount ?? 0,
      datasetUsage: widget.scope.usageOf(tag),
      // Translated or used, but the dictionary has never heard of it — a tag
      // read out of a dataset, or one whose spelling has since changed.
      // Flagged rather than hidden: an unreachable entry is exactly the kind
      // of thing that needs finding. Only once the dictionary is actually
      // loaded, or a cold start would brand every entry unknown.
      orphan: _dictionary.isReady && hit == null && !custom,
    );
  }

  /// The rows to show, in display order.
  List<_DictRow> _rows() {
    final query = _query.trim();
    final custom = _customKeys;

    /// Whether [row] survives the search box. Name *and* gloss, so a tag can
    /// be found by its translation as readily as by its name.
    bool matches(_DictRow row) {
      if (query.isEmpty) return true;
      final needle = query.toLowerCase();
      return row.tag.toLowerCase().contains(needle) ||
          (row.translation?.text.toLowerCase().contains(needle) ?? false) ||
          (row.translation?.note?.toLowerCase().contains(needle) ?? false);
    }

    List<_DictRow> fromNames(Iterable<String> names, {bool sort = true}) {
      final seen = <String>{};
      final rows = [
        for (final name in names)
          if (seen.add(tagLookupKey(name)))
            _rowFor(name, custom: custom.contains(tagLookupKey(name))),
      ].where(matches).toList();
      if (sort) rows.sort((a, b) => a.tag.compareTo(b.tag));
      return rows;
    }

    switch (_filter) {
      case _DictFilter.thisImage:
        // Caption order: the list should read like the tag row it mirrors.
        return fromNames(widget.scope.imageTags, sort: false);
      case _DictFilter.custom:
        return fromNames([
          for (final entry in _dictionary.customEntries) entry.name,
        ], sort: false);
      case _DictFilter.untranslated:
        // The user's own additions first, then the dataset busiest-first: the
        // tag on four hundred images is the one whose missing gloss actually
        // costs something. Never the whole dictionary — a hundred thousand
        // untranslated tags is not a to-do list.
        return fromNames([
          for (final entry in _dictionary.customEntries)
            if (!_glossary.has(entry.name)) entry.name,
          for (final tag in widget.scope.datasetTags)
            if (!_glossary.has(tag)) tag,
        ], sort: false);
      case _DictFilter.all:
        return _allRows(query, custom);
    }
  }

  /// The "everything" view: what the user has actually touched when the search
  /// box is empty, the whole dictionary when it is not.
  List<_DictRow> _allRows(String query, Set<String> custom) {
    final seen = <String>{};
    final rows = <_DictRow>[];

    if (query.isEmpty) {
      for (final entry in _dictionary.customEntries) {
        if (!seen.add(tagLookupKey(entry.name))) continue;
        rows.add(_rowFor(entry.name, custom: true));
      }
      // Custom entries went out above and `seen` skips them, so nothing left
      // here can be one.
      for (final entry in _glossary.entries) {
        if (!seen.add(tagLookupKey(entry.tag))) continue;
        rows.add(_rowFor(entry.tag, custom: false));
      }
      return rows;
    }

    for (final hit in _dictionary.search(query, limit: _searchLimit)) {
      if (!seen.add(tagLookupKey(hit.name))) continue;
      rows.add(_rowFor(hit.name, custom: hit.isCustom));
    }
    // Then the glossary, matched on the translation itself — the direction the
    // dictionary cannot answer, and the reason to keep one.
    final needle = query.toLowerCase();
    for (final entry in _glossary.entries) {
      if (!entry.text.toLowerCase().contains(needle) &&
          !(entry.note?.toLowerCase().contains(needle) ?? false)) {
        continue;
      }
      final key = tagLookupKey(entry.tag);
      if (!seen.add(key)) continue;
      rows.add(_rowFor(entry.tag, custom: custom.contains(key)));
    }
    return rows;
  }

  /// Dataset tags the dictionary has never heard of, busiest first. The one
  /// list that is worth putting in front of the user unprompted: these tags
  /// render untranslated everywhere and never reach the completion list.
  List<({String tag, int count})> _missingTags() {
    if (_missingDismissed || !_dictionary.isReady) return const [];
    // Already busiest-first; the dataset index sorts on the same key.
    return [
      for (final tag in widget.scope.datasetTags)
        if (_dictionary.lookup(tag) == null)
          (tag: tag, count: widget.scope.usageOf(tag) ?? 0),
    ];
  }

  // --- Mutation ---------------------------------------------------------

  Future<void> _saveTranslation(
    String tag,
    String text,
    String? note,
    TagTranslationSource source,
  ) async {
    final trimmed = text.trim();
    // An empty field is "nothing to save", not "delete it". Deleting used to
    // ride on this, which meant a select-all-and-type that ended up empty
    // silently dropped a translation; it is now its own confirmed action.
    if (trimmed.isEmpty) return;
    await _glossary.upsert(
      TagTranslation(
        tag: tag,
        text: trimmed,
        note: note == null || note.trim().isEmpty ? null : note.trim(),
        // The form decides: text taken verbatim from danbooru is recorded as
        // danbooru's, anything typed over it becomes the user's own.
        source: source,
      ),
    );
  }

  /// Appends entries to the user's dictionary additions. The service takes the
  /// whole list, so every caller has to hand back what is already there.
  Future<void> _appendCustom(Iterable<TagDictionaryEntry> entries) {
    final dictionary = _dictionary;
    return dictionary.setCustomEntries([
      ...dictionary.customEntries,
      ...entries,
    ]);
  }

  /// Adds a tag danbooru knows but this dictionary does not, with danbooru's
  /// own category and post count. Turns a lookup into a completable tag.
  Future<void> _addFromDanbooru(DanbooruTagInfo info) async {
    final l10n = AppLocalizations.of(context)!;
    await _appendCustom([
      TagDictionaryEntry(
        name: info.name,
        category: info.category ?? TagCategory.general,
        postCount: info.postCount,
        aliases: info.otherNames,
      ),
    ]);
    if (!mounted) return;
    setState(() {
      _selected = info.name;
      _pane = _DictPane.detail;
    });
    _snack(l10n.dictFetchAdded(info.name));
  }

  Future<void> _addCustomTag(TagDictionaryEntry entry, String gloss) async {
    final l10n = AppLocalizations.of(context)!;
    if (_dictionary.lookup(entry.name) != null) {
      _snack(l10n.dictAddTagExists(entry.name));
      return;
    }
    // Started together, not one after the other: the dictionary and the
    // glossary are separate stores with nothing to say to each other, and
    // sequencing them would leave the translation waiting on a disk write it
    // does not depend on.
    await Future.wait([
      _appendCustom([entry]),
      if (gloss.trim().isNotEmpty)
        _saveTranslation(entry.name, gloss, null, TagTranslationSource.manual),
    ]);
    if (!mounted) return;
    setState(() {
      _searchController.clear();
      _query = '';
      _filter = _DictFilter.custom;
      _selected = entry.name;
      _pane = _DictPane.detail;
    });
  }

  /// Takes tags the dataset uses into the dictionary in one write, so a
  /// freshly opened folder stops rendering half its vocabulary as unknown.
  Future<void> _collectMissing(Iterable<String> tags) async {
    final l10n = AppLocalizations.of(context)!;
    final entries = [
      for (final tag in tags)
        TagDictionaryEntry(
          name: danbooruTagName(tag),
          category: TagCategory.general,
          // The dataset's own count: not a danbooru popularity, but the only
          // honest ranking signal these entries have.
          postCount: widget.scope.usageOf(tag) ?? 0,
        ),
    ];
    if (entries.isEmpty) return;
    await _appendCustom(entries);
    if (!mounted) return;
    setState(() {});
    _snack(l10n.dictCollectedCount(entries.length));
  }

  // --- Deleting ----------------------------------------------------------
  //
  // Both of these throw away something the user typed and neither is undoable,
  // so both ask first. They are separate questions: a translation can be wrong
  // for a tag that still belongs in the dictionary, and a hand-added tag can be
  // a mistake while its translation was fine.

  /// Yes/no, with [action] as both the title and the confirming button — the
  /// button that performs a delete should say which delete.
  Future<bool> _confirmDestructive(String action, String message) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(action),
        content: SizedBox(width: 360, child: Text(message)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<void> _deleteTranslation(String tag) async {
    final l10n = AppLocalizations.of(context)!;
    if (!await _confirmDestructive(
      l10n.dictDeleteTranslationAction,
      l10n.dictDeleteTranslationConfirm(tag),
    )) {
      return;
    }
    await _glossary.remove([tag]);
    if (mounted) setState(() {});
  }

  Future<void> _removeCustomTag(String tag) async {
    final l10n = AppLocalizations.of(context)!;
    if (!await _confirmDestructive(
      l10n.dictRemoveCustomAction,
      l10n.dictRemoveCustomConfirm(tag),
    )) {
      return;
    }
    final key = tagLookupKey(tag);
    final dictionary = _dictionary;
    await dictionary.setCustomEntries([
      for (final entry in dictionary.customEntries)
        if (tagLookupKey(entry.name) != key) entry,
    ]);
    if (mounted) setState(() {});
  }

  /// A row's own menu: the two deletions, offered only where they apply.
  ///
  /// Right-click reaches them without selecting the row first, which is what
  /// makes clearing out a batch of stray entries bearable.
  Future<void> _showRowMenu(Offset position, _DictRow row) async {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final items = [
      if (row.orphan)
        panelMenuItem(
          context: context,
          value: 'collect',
          icon: Icons.library_add_outlined,
          label: l10n.dictCollectAction,
        ),
      if (row.translation != null)
        panelMenuItem(
          context: context,
          value: 'translation',
          icon: Icons.translate,
          label: l10n.dictDeleteTranslationAction,
          color: scheme.error,
        ),
      if (row.custom)
        panelMenuItem(
          context: context,
          value: 'entry',
          icon: Icons.delete_outline,
          label: l10n.dictRemoveCustomAction,
          color: scheme.error,
        ),
    ];
    // A dictionary row the user has neither translated nor added has nothing
    // to delete; an empty menu is worse than none.
    if (items.isEmpty) return;
    final action = await showPanelContextMenu<String>(
      context: context,
      position: position,
      items: items,
    );
    if (action == null || !mounted) return;
    switch (action) {
      case 'collect':
        await _collectMissing([row.tag]);
      case 'translation':
        await _deleteTranslation(row.tag);
      case 'entry':
        await _removeCustomTag(row.tag);
    }
  }

  // --- Danbooru lookup ---------------------------------------------------

  /// Fetches [query] — a tag name or a pasted danbooru URL — and selects the
  /// tag it resolves to.
  ///
  /// A tag danbooru has never heard of is not treated as a failure: it comes
  /// back with `knownToDanbooru == false`, and saying so is more useful than an
  /// error, because "danbooru doesn't have this either" is exactly what
  /// confirms a typo.
  Future<DanbooruTagInfo?> _lookup(String query, {bool select = true}) async {
    final l10n = AppLocalizations.of(context)!;
    setState(() => _fetching = true);
    try {
      final info = await _api.fetch(query);
      if (!mounted) return null;
      setState(() {
        _fetched[tagLookupKey(info.name)] = info;
        if (select) {
          _selected = info.name;
          // The list is keyed off the search box, so point it at the tag that
          // came back — otherwise the editor shows a tag the list beside it
          // does not contain.
          _searchController.text = info.name;
          _query = info.name;
          _filter = _DictFilter.all;
        }
      });
      if (!info.knownToDanbooru) _snack(l10n.dictFetchUnknown(info.name));
      return info;
    } on DanbooruApiException catch (e) {
      if (mounted) _snack(l10n.dictFetchFailed(e.message));
      return null;
    } finally {
      if (mounted) setState(() => _fetching = false);
    }
  }

  // --- Import / export ---------------------------------------------------

  Future<void> _import() async {
    final l10n = AppLocalizations.of(context)!;
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    final path = result?.files.single.path;
    if (path == null) return;
    try {
      final (written, skipped) = await _glossary.importJson(
        await File(path).readAsString(),
      );
      if (!mounted) return;
      setState(() {});
      _snack(l10n.dictImportSummary(written, skipped));
    } on FormatException catch (e) {
      _snack(l10n.importFailedMsg(e.message));
    } on FileSystemException catch (e) {
      _snack(l10n.importFailedMsg(e.message));
    }
  }

  Future<void> _export() async {
    final l10n = AppLocalizations.of(context)!;
    final glossary = _glossary;
    final path = await FilePicker.saveFile(
      fileName: 'tag_translations_${glossary.languageCode}.json',
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (path == null) return;
    try {
      await File(path).writeAsString(glossary.exportJson());
      if (!mounted) return;
      _snack(l10n.exportedTo(path));
    } on FileSystemException catch (e) {
      if (mounted) _snack(l10n.exportFailedMsg(e.message));
    }
  }

  Future<void> _clearMachineTranslations() async {
    final l10n = AppLocalizations.of(context)!;
    final glossary = _glossary;
    final count = glossary.countBySource(TagTranslationSource.llm);
    if (count == 0) {
      _snack(l10n.dictClearAiNone);
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.dictClearAiTitle),
        content: Text(l10n.dictClearAiConfirm(count)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final removed = await glossary.clearBySource(TagTranslationSource.llm);
    if (!mounted) return;
    setState(() {});
    _snack(l10n.dictClearAiDone(removed));
  }

  // --- Build -------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final semantic = context.semantic;

    // Both services mutate in place, so the dialog subscribes to them rather
    // than to AppState — which never forwards their notifications.
    return ListenableBuilder(
      listenable: Listenable.merge([_dictionary, _glossary]),
      builder: (context, _) {
        final rows = _rows();
        final missing = _missingTags();
        return Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 28,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900, maxHeight: 640),
            child: GlassSurface(
              borderRadius: BorderRadius.circular(14),
              blurSigma: 14,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _header(l10n, semantic),
                  _toolbar(l10n, semantic),
                  if (missing.isNotEmpty)
                    _MissingBanner(
                      missing: missing,
                      onIgnore: () => setState(() => _missingDismissed = true),
                      onCollectAll: () =>
                          _collectMissing([for (final m in missing) m.tag]),
                      onCollect: (tag) => _collectMissing([tag]),
                    ),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, area) => Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            // A fixed 296 leaves a shrunken window's editor
                            // with nothing to lay out in. The list is the
                            // cheaper of the two to narrow, but only down to
                            // where a tag and its gloss still read.
                            width: (area.maxWidth * 0.36).clamp(200.0, 296.0),
                            child: _list(l10n, semantic, rows),
                          ),
                          Container(width: 1, color: semantic.line),
                          Expanded(child: _rightPane(l10n, semantic)),
                        ],
                      ),
                    ),
                  ),
                  _footer(l10n, semantic),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _header(
    AppLocalizations l10n,
    AppSemanticColors semantic,
  ) => Container(
    padding: const EdgeInsets.fromLTRB(18, 12, 10, 12),
    decoration: BoxDecoration(
      border: Border(bottom: BorderSide(color: semantic.line)),
    ),
    child: Row(
      children: [
        Icon(
          Icons.translate,
          size: 15,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(width: 8),
        Text(
          l10n.dictManagerTitle,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        const SizedBox(width: 10),
        // Which glossary is being edited is the one thing a user must not have
        // to guess: translations are per language, and the language follows
        // the app's own setting.
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.dictManagerCounts(
                  _glossary.languageCode.toUpperCase(),
                  _dictionary.entryCount,
                  _dictionary.customEntries.length,
                  _glossary.count,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: AppText.micro,
                  color: semantic.muted,
                ),
              ),
              // An unreadable glossary file otherwise looks exactly like an
              // empty one, which invites the user to translate everything a
              // second time — and, when the file came from a newer build, this
              // is also the only sign that their edits are being refused.
              if (_glossary.lastError case final error?)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Row(
                    children: [
                      Icon(
                        Icons.warning_amber_outlined,
                        size: 12,
                        color: semantic.warn,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          l10n.dictGlossaryError(error),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: AppText.micro,
                            color: semantic.warn,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        PanelIconButton(
          icon: Icons.close,
          tooltip: l10n.close,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    ),
  );

  Widget _toolbar(AppLocalizations l10n, AppSemanticColors semantic) =>
      Container(
        padding: const EdgeInsets.fromLTRB(14, 9, 14, 9),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: semantic.line)),
        ),
        child: _ToolbarStrip(
          search: PanelSearchField(
            hint: l10n.dictSearchHint,
            controller: _searchController,
            padding: EdgeInsets.zero,
            onChanged: (value) => setState(() => _query = value),
          ),
          entries: _toolbarEntries(l10n),
          overflowTooltip: l10n.moreActionsTooltip,
        ),
      );

  /// Everything on the toolbar's right-hand side, in the order it should be
  /// given up when the window is too narrow to hold it all.
  ///
  /// The filter group leads because it steers the list; the two actions trail
  /// because each is reachable another way (the fetch pane also opens from a
  /// tag's context menu, and adding a tag is not a per-second act).
  List<_ToolbarEntry> _toolbarEntries(AppLocalizations l10n) => [
    _ToolbarEntry.segments([
      // "This image" disappears when the dialog was opened without a workbench
      // behind it — an always-empty filter is a dead control.
      for (final (filter, label) in <(_DictFilter, String)>[
        (_DictFilter.all, l10n.dictFilterAll),
        if (widget.scope.imageTags.isNotEmpty)
          (
            _DictFilter.thisImage,
            l10n.dictFilterThisImage(widget.scope.imageTags.length),
          ),
        (_DictFilter.untranslated, l10n.dictUntranslated),
        (
          _DictFilter.custom,
          l10n.dictFilterCustom(_dictionary.customEntries.length),
        ),
      ])
        _ToolbarSegment(
          label: label,
          selected: _filter == filter,
          onTap: () => setState(() => _filter = filter),
        ),
    ]),
    _ToolbarEntry.action(
      icon: Icons.add,
      label: l10n.dictNewTagAction,
      accent: true,
      onTap: () => setState(() => _pane = _DictPane.newTag),
    ),
    _ToolbarEntry.action(
      icon: Icons.cloud_download_outlined,
      label: l10n.dictFetchSourceName,
      busy: _fetching,
      onTap: () => setState(() => _pane = _DictPane.fetch),
    ),
  ];

  Widget _list(
    AppLocalizations l10n,
    AppSemanticColors semantic,
    List<_DictRow> rows,
  ) {
    final ranked = _filter == _DictFilter.all && _query.trim().isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(
            children: [
              Text(
                ranked ? l10n.dictOrderRelevance : l10n.dictOrderAlpha,
                style: TextStyle(
                  fontSize: AppText.micro,
                  color: semantic.muted,
                ),
              ),
              const Spacer(),
              Text(
                l10n.dictResultCount(rows.length),
                style: TextStyle(
                  fontSize: AppText.micro,
                  color: semantic.muted,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: rows.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      _emptyMessage(l10n),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: AppText.secondary,
                        color: semantic.muted,
                      ),
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                  itemCount: rows.length,
                  itemBuilder: (context, index) => _DictRowTile(
                    row: rows[index],
                    selected:
                        tagLookupKey(rows[index].tag) ==
                        tagLookupKey(_selected ?? ''),
                    onTap: () => _select(rows[index].tag),
                    onCollect: () => _collectMissing([rows[index].tag]),
                    onContextMenu: (position) =>
                        _showRowMenu(position, rows[index]),
                  ),
                ),
        ),
        Container(height: 1, color: semantic.line),
        const _CategoryLegend(),
      ],
    );
  }

  String _emptyMessage(AppLocalizations l10n) {
    if (_query.trim().isNotEmpty) return l10n.dictNoResults;
    return switch (_filter) {
      _DictFilter.all => l10n.dictGlossaryEmpty,
      _DictFilter.custom => l10n.dictCustomEmpty,
      _DictFilter.untranslated => l10n.dictUntranslatedEmpty,
      _DictFilter.thisImage => l10n.dictThisImageEmpty,
    };
  }

  Widget _rightPane(AppLocalizations l10n, AppSemanticColors semantic) {
    switch (_pane) {
      case _DictPane.newTag:
        return _NewTagForm(
          onCancel: () => setState(() => _pane = _DictPane.detail),
          onSubmit: _addCustomTag,
        );
      case _DictPane.fetch:
        return _FetchForm(
          initial: _selected ?? _query.trim(),
          fetching: _fetching,
          onCancel: () => setState(() => _pane = _DictPane.detail),
          onLookup: (query) => _lookup(query, select: false),
          isKnownLocally: (name) => _dictionary.lookup(name) != null,
          onWrite: _addFromDanbooru,
          onOpen: _select,
        );
      case _DictPane.detail:
        final selected = _selected;
        if (selected == null) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                l10n.dictSelectHint,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: AppText.secondary,
                  color: semantic.muted,
                ),
              ),
            ),
          );
        }
        return _TranslationForm(
          // New controllers when the selection moves. Deliberately *not* keyed
          // on the fetched info: a lookup must not throw away whatever the
          // user was typing.
          key: ValueKey('$selected/${_glossary.lookup(selected)?.text}'),
          tag: selected,
          entry: _glossary.lookup(selected),
          dictionaryEntry: _dictionary.lookup(selected),
          custom: _isCustom(selected),
          info: _fetched[tagLookupKey(selected)],
          fetching: _fetching,
          datasetUsage: widget.scope.usageOf(selected),
          datasetImages: widget.scope.imageCount,
          glossaryLanguage: _glossary.languageCode,
          onSave: (text, note, source) =>
              _saveTranslation(selected, text, note, source),
          onFetch: () => _lookup(selected),
          onDeleteTranslation: () => _deleteTranslation(selected),
          onRemoveCustom: () => _removeCustomTag(selected),
          // Only offered when danbooru has the tag and this dictionary does
          // not — otherwise there is nothing to add.
          onAddFromDanbooru: _dictionary.lookup(selected) == null
              ? _addFromDanbooru
              : null,
        );
    }
  }

  Widget _footer(AppLocalizations l10n, AppSemanticColors semantic) =>
      Container(
        padding: const EdgeInsets.fromLTRB(14, 6, 12, 6),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: semantic.line)),
        ),
        // The hint is the *only* flex child, so it absorbs every pixel of
        // slack and the actions keep the right edge. `Expanded` + `Flexible`
        // does not: those are two flex children of equal weight, so the
        // actions get half the band and align right within that half — which
        // is the middle of the footer.
        child: LayoutBuilder(
          builder: (context, band) => Row(
            children: [
              Expanded(
                child: Text(
                  l10n.dictFooterHint,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: AppText.micro,
                    color: semantic.muted,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // Bounded from the outside — a non-flex Row child is handed
              // unbounded width, and an unbounded Wrap never wraps — so three
              // long localized labels break onto a second line instead of off
              // the edge.
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: band.maxWidth * 0.78),
                child: Wrap(
                  alignment: WrapAlignment.end,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    TextButton.icon(
                      onPressed: _clearMachineTranslations,
                      icon: const Icon(Icons.auto_awesome_outlined, size: 14),
                      label: Text(
                        l10n.dictClearAiAction,
                        style: const TextStyle(fontSize: AppText.secondary),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _import,
                      icon: const Icon(Icons.file_download_outlined, size: 14),
                      label: Text(
                        l10n.dictImportAction,
                        style: const TextStyle(fontSize: AppText.secondary),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _glossary.isEmpty ? null : _export,
                      icon: const Icon(Icons.file_upload_outlined, size: 14),
                      label: Text(
                        l10n.dictExportAction,
                        style: const TextStyle(fontSize: AppText.secondary),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}

// --- The list ------------------------------------------------------------

/// One row of the manager's list.
class _DictRow {
  const _DictRow({
    required this.tag,
    this.category,
    this.custom = false,
    this.translation,
    this.orphan = false,
    this.postCount = 0,
    this.datasetUsage,
  });

  final String tag;

  /// Null when nothing in the dictionary claims this tag.
  final TagCategory? category;

  /// A tag the user added to the dictionary by hand.
  final bool custom;

  final TagTranslation? translation;

  /// Known to neither the dictionary nor the user's additions.
  final bool orphan;

  final int postCount;

  /// How many images in the open dataset carry the tag; null when there is no
  /// dataset behind this dialog, or the dataset does not use the tag.
  final int? datasetUsage;
}

class _DictRowTile extends StatelessWidget {
  const _DictRowTile({
    required this.row,
    required this.selected,
    required this.onTap,
    required this.onCollect,
    required this.onContextMenu,
  });

  final _DictRow row;
  final bool selected;
  final VoidCallback onTap;

  /// Takes an orphan row into the dictionary as a custom entry.
  final VoidCallback onCollect;

  /// Right-click: the row's deletions, without selecting it first.
  final ValueChanged<Offset> onContextMenu;

  /// The second line: the translation when there is one, and otherwise what
  /// the row is instead — untranslated, unknown, or both.
  String _subtitle(AppLocalizations l10n) {
    final gloss = row.translation?.text;
    if (gloss != null) {
      return row.orphan ? '$gloss · ${l10n.dictOrphanBadge}' : gloss;
    }
    if (row.orphan) return l10n.dictOrphanBadge;
    final category = row.category;
    return category == null
        ? l10n.dictUntranslated
        : '${l10n.dictUntranslated} · ${_categoryLabel(l10n, category)}';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final semantic = context.semantic;
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          onSecondaryTapDown: (details) =>
              onContextMenu(details.globalPosition),
          onLongPressStart: (details) => onContextMenu(details.globalPosition),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
            decoration: BoxDecoration(
              color: selected
                  ? scheme.primary.withValues(alpha: 0.18)
                  : row.orphan
                  ? semantic.warn.withValues(alpha: 0.07)
                  : Colors.transparent,
              border: Border.all(
                color: selected
                    ? scheme.primary.withValues(alpha: 0.45)
                    : row.orphan
                    ? semantic.warn.withValues(alpha: 0.34)
                    : Colors.transparent,
              ),
              borderRadius: BorderRadius.circular(AppRadii.control),
            ),
            child: Row(
              children: [
                // Category as a colour, not a word: the list is scanned, and a
                // dot costs no width in a 296px column.
                Container(
                  width: 6,
                  height: 6,
                  margin: const EdgeInsets.only(right: 9),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: row.orphan
                        ? semantic.warn
                        : _categoryColor(context, row.category),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        row.tag,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: monoStyle(
                          context,
                          size: AppText.secondary,
                          color: selected ? scheme.onSurface : null,
                        ),
                      ),
                      Text(
                        _subtitle(l10n),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: AppText.micro,
                          color: semantic.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                if (row.orphan)
                  _MiniAction(
                    label: l10n.dictCollectAction,
                    color: semantic.warn,
                    onTap: onCollect,
                  )
                else if (row.custom)
                  _Badge(label: l10n.dictCustomBadge, color: scheme.primary)
                else if (row.postCount > 0)
                  Text(
                    compactCount(row.postCount),
                    style: monoStyle(
                      context,
                      size: AppText.micro,
                      color: selected ? scheme.primary : semantic.muted,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// What the dots in the list mean. A four-line key is cheaper than repeating
/// the category on every row, and the colours are otherwise unguessable.
class _CategoryLegend extends StatelessWidget {
  const _CategoryLegend();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final semantic = context.semantic;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: Wrap(
        spacing: 10,
        runSpacing: 4,
        children: [
          for (final category in const [
            TagCategory.general,
            TagCategory.character,
            TagCategory.copyright,
            TagCategory.artist,
          ])
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _categoryColor(context, category),
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  _categoryLabel(l10n, category),
                  style: TextStyle(
                    fontSize: AppText.micro,
                    color: semantic.muted,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// The banner over the list: tags this dataset uses that the dictionary has
/// never heard of. Every one of them renders untranslated everywhere and is
/// missing from the completion list, which is a state worth naming.
class _MissingBanner extends StatelessWidget {
  const _MissingBanner({
    required this.missing,
    required this.onIgnore,
    required this.onCollectAll,
    required this.onCollect,
  });

  final List<({String tag, int count})> missing;
  final VoidCallback onIgnore;
  final VoidCallback onCollectAll;
  final ValueChanged<String> onCollect;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final semantic = context.semantic;
    final shown = missing.take(_missingChipLimit).toList();
    final rest = missing.length - shown.length;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 9, 14, 10),
      decoration: BoxDecoration(
        color: semantic.warn.withValues(alpha: 0.06),
        border: Border(bottom: BorderSide(color: semantic.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // One tight Expanded holding every piece of text, so the two
              // actions keep the right edge: a Spacer among several flex
              // children only ever gets its own share of the slack, and the
              // rest lands after the buttons.
              Expanded(
                child: Row(
                  children: [
                    Icon(
                      Icons.warning_amber_outlined,
                      size: 14,
                      color: semantic.warn,
                    ),
                    const SizedBox(width: 7),
                    // Both texts shrink; neither may push the actions off the
                    // end, because the whole banner exists to offer them.
                    Flexible(
                      child: Text(
                        l10n.dictMissingTitle(missing.length),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: AppText.secondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 9),
                    Flexible(
                      child: Text(
                        l10n.dictMissingDesc,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: AppText.micro,
                          color: semantic.muted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: onIgnore,
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  foregroundColor: semantic.muted,
                ),
                child: Text(
                  l10n.dictMissingIgnore,
                  style: const TextStyle(fontSize: AppText.secondary),
                ),
              ),
              OutlinedButton(
                onPressed: onCollectAll,
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
                child: Text(
                  l10n.dictMissingCollectAll,
                  style: const TextStyle(fontSize: AppText.secondary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              for (final entry in shown)
                _MissingChip(
                  tag: entry.tag,
                  count: entry.count,
                  onTap: () => onCollect(entry.tag),
                ),
              if (rest > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    l10n.dictMissingMore(rest),
                    style: TextStyle(
                      fontSize: AppText.micro,
                      color: semantic.muted,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MissingChip extends StatelessWidget {
  const _MissingChip({
    required this.tag,
    required this.count,
    required this.onTap,
  });

  final String tag;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final semantic = context.semantic;
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: l10n.dictCollectAction,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
            decoration: BoxDecoration(
              color: semantic.raised,
              border: Border.all(color: semantic.line),
              borderRadius: BorderRadius.circular(AppRadii.control),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(tag, style: monoStyle(context, size: AppText.secondary)),
                const SizedBox(width: 7),
                Text(
                  l10n.dictMissingUsage(count),
                  style: TextStyle(
                    fontSize: AppText.micro,
                    color: semantic.muted,
                  ),
                ),
                const SizedBox(width: 6),
                Icon(Icons.add, size: 12, color: scheme.primary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// --- The editor ----------------------------------------------------------

/// The editor for one tag: its translation, its note, and the actions that
/// only make sense for the kind of tag it is.
class _TranslationForm extends StatefulWidget {
  const _TranslationForm({
    super.key,
    required this.tag,
    required this.entry,
    required this.dictionaryEntry,
    required this.custom,
    required this.info,
    required this.fetching,
    required this.datasetUsage,
    required this.datasetImages,
    required this.glossaryLanguage,
    required this.onSave,
    required this.onFetch,
    required this.onDeleteTranslation,
    required this.onRemoveCustom,
    required this.onAddFromDanbooru,
  });

  final String tag;
  final TagTranslation? entry;
  final TagDictionaryEntry? dictionaryEntry;
  final bool custom;

  /// What danbooru said about this tag, once it has been looked up.
  final DanbooruTagInfo? info;

  final bool fetching;

  /// Images in the open dataset carrying this tag, and the size of the dataset
  /// they are a share of. Null / zero when there is no dataset behind this.
  final int? datasetUsage;
  final int datasetImages;

  /// Which glossary the save writes into; the AI prompt needs it.
  final String glossaryLanguage;

  final Future<void> Function(
    String text,
    String? note,
    TagTranslationSource source,
  )
  onSave;
  final Future<void> Function() onFetch;

  /// Both confirm before they act, and both live on the host: the dialog owns
  /// the two stores, and this form is rebuilt from scratch whenever either
  /// changes.
  final Future<void> Function() onDeleteTranslation;
  final Future<void> Function() onRemoveCustom;

  /// Null when there is nothing to add — the dictionary already has the tag.
  final Future<void> Function(DanbooruTagInfo info)? onAddFromDanbooru;

  @override
  State<_TranslationForm> createState() => _TranslationFormState();
}

class _TranslationFormState extends State<_TranslationForm> {
  late final TextEditingController _text = TextEditingController(
    text: widget.entry?.text ?? '',
  );
  late final TextEditingController _note = TextEditingController(
    text: widget.entry?.note ?? '',
  );
  bool _dirty = false;
  bool _translating = false;

  /// Provenance for the next save. Set to [TagTranslationSource.danbooru] only
  /// while the field holds text taken verbatim from danbooru; typing over it
  /// makes it the user's own again, so the "clear AI/danbooru translations"
  /// escape hatch never throws away something hand-edited.
  TagTranslationSource _source = TagTranslationSource.manual;

  @override
  void dispose() {
    _text.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await widget.onSave(_text.text, _note.text, _source);
    if (mounted) setState(() => _dirty = false);
  }

  /// Back to what is on disk. The counterpart to a field that saves on Enter:
  /// without it, a half-typed replacement can only be undone by remembering
  /// the original.
  void _revert() {
    _text.text = widget.entry?.text ?? '';
    _note.text = widget.entry?.note ?? '';
    setState(() {
      _dirty = false;
      _source = widget.entry?.source ?? TagTranslationSource.manual;
    });
  }

  void _useAsTranslation(String value) {
    _text.text = value;
    setState(() {
      _dirty = true;
      _source = TagTranslationSource.danbooru;
    });
  }

  void _useAsNote(String value) {
    _note.text = value;
    setState(() => _dirty = true);
  }

  /// Asks the configured backend for a gloss. Fills the field and marks the
  /// entry as the assistant's — never saves on the user's behalf, so a wrong
  /// answer costs one glance and no cleanup.
  Future<void> _aiTranslate(LlmProviderProfile profile) async {
    final l10n = AppLocalizations.of(context)!;
    setState(() => _translating = true);
    try {
      final gloss = await translateTagWithLlm(
        profile: profile,
        tag: widget.tag,
        languageCode: widget.glossaryLanguage,
        // Whatever this dialog already knows about the tag: the wiki excerpt
        // is what turns a guess at an opaque tag into an answer.
        note: widget.info?.wikiExcerpt ?? _note.text,
      );
      if (!mounted) return;
      _text.text = gloss;
      setState(() {
        _dirty = true;
        _source = TagTranslationSource.llm;
      });
    } on LlmException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.dictAiTranslateFailed(e.message))),
      );
    } finally {
      if (mounted) setState(() => _translating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final semantic = context.semantic;
    final scheme = Theme.of(context).colorScheme;
    final entry = widget.entry;
    final hit = widget.dictionaryEntry;
    final profile = context.select<AppState, LlmProviderProfile?>(
      (s) => s.activeLlmProfile,
    );
    final aliases = hit?.aliases ?? const <String>[];

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 15, 18, 15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, pane) => Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(widget.tag, style: monoStyle(context, size: 16)),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _categoryColor(context, hit?.category),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              hit == null
                                  ? l10n.dictOrphanBadge
                                  : l10n.dictCategoryAndCount(
                                      _categoryLabel(l10n, hit.category),
                                      hit.postCount,
                                    ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: AppText.micro,
                                color: semantic.muted,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // A hand-added tag is the user's own invention: danbooru has
                // neither a wiki page nor a tag record for it, so both the link
                // and the lookup would come back empty.
                if (!widget.custom) ...[
                  const SizedBox(width: 8),
                  // Non-flex, so the two actions keep the right edge; the tag
                  // column beside them is the tight Expanded that absorbs the
                  // slack. The inner Wrap still bounds them, because two
                  // localized labels can be wider than a narrow pane.
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: pane.maxWidth * 0.62),
                    child: Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _MiniAction(
                          icon: Icons.cloud_download_outlined,
                          label: widget.fetching
                              ? l10n.dictFetching
                              : l10n.dictFetchAction,
                          busy: widget.fetching,
                          onTap: widget.fetching ? null : widget.onFetch,
                        ),
                        _MiniAction(
                          icon: Icons.menu_book_outlined,
                          label: l10n.tagWikiAction,
                          onTap: () =>
                              openExternalUrl(danbooruWikiUrl(widget.tag)),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (aliases.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  l10n.dictAliasesLabel,
                  style: TextStyle(
                    fontSize: AppText.micro,
                    color: semantic.muted,
                  ),
                ),
                for (final alias in aliases.take(8))
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.surface,
                      border: Border.all(color: semantic.line),
                      borderRadius: BorderRadius.circular(AppRadii.input),
                    ),
                    child: Text(
                      alias,
                      style: monoStyle(context, size: AppText.micro),
                    ),
                  ),
                Text(
                  l10n.dictAliasesHint,
                  style: TextStyle(
                    fontSize: AppText.micro,
                    color: semantic.muted.withValues(alpha: 0.75),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: _label(l10n.dictTranslationLabel, semantic)),
              // Offered only when there is a backend to ask. A button whose
              // only outcome is "configure a backend first" is a dead end.
              if (profile != null)
                _MiniAction(
                  icon: Icons.auto_awesome_outlined,
                  label: _translating
                      ? l10n.dictAiTranslating
                      : l10n.dictAiTranslateAction,
                  accent: true,
                  busy: _translating,
                  onTap: _translating ? null : () => _aiTranslate(profile),
                ),
            ],
          ),
          const SizedBox(height: 5),
          TextField(
            controller: _text,
            autofocus: true,
            style: const TextStyle(fontSize: AppText.secondary),
            decoration: InputDecoration(
              hintText: l10n.dictTranslationHint,
              isDense: true,
            ),
            // Every keystroke, not only the first: the save button now also
            // watches whether the field is empty.
            onChanged: (_) => setState(() {
              _dirty = true;
              // Typing over danbooru's or the model's own wording makes the
              // entry the user's again, so a later "clear fetched translations"
              // leaves it alone.
              _source = TagTranslationSource.manual;
            }),
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: 5),
          Text(
            l10n.dictDeleteHint,
            style: TextStyle(fontSize: AppText.micro, color: semantic.muted),
          ),
          const SizedBox(height: 12),
          _label(l10n.dictNoteLabel, semantic),
          TextField(
            controller: _note,
            minLines: 2,
            maxLines: 4,
            style: const TextStyle(fontSize: AppText.secondary),
            decoration: InputDecoration(
              hintText: l10n.dictNoteHint,
              isDense: true,
            ),
            onChanged: (_) {
              if (!_dirty) setState(() => _dirty = true);
            },
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              // One Expanded holding the whole provenance line, so the two
              // buttons stay pinned to the right edge instead of drifting as
              // that line grows and shrinks. The Spacer this replaces was one
              // flex child among three, which handed it a third of the slack
              // and moved the buttons on every rebuild.
              Expanded(
                child: Row(
                  children: [
                    if (entry != null) ...[
                      Flexible(
                        child: _Badge(
                          label: _sourceLabel(l10n, entry.source),
                          color: entry.source == TagTranslationSource.manual
                              ? semantic.muted
                              : scheme.primary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (_dirty && _source != entry.source)
                        Flexible(
                          child: Text(
                            l10n.dictSourceBecomes(_sourceLabel(l10n, _source)),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: AppText.micro,
                              color: semantic.muted,
                            ),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: _dirty ? _revert : null,
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
                child: Text(
                  l10n.dictRevertAction,
                  style: const TextStyle(fontSize: AppText.secondary),
                ),
              ),
              const SizedBox(width: 6),
              FilledButton(
                // An empty field no longer means "delete"; with nothing to
                // write, saving would be a no-op that looks like a success.
                onPressed: _dirty && _text.text.trim().isNotEmpty
                    ? _save
                    : null,
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  minimumSize: const Size(0, 30),
                ),
                child: Text(
                  l10n.save,
                  style: const TextStyle(fontSize: AppText.secondary),
                ),
              ),
            ],
          ),
          if (entry != null || widget.custom) ...[
            const SizedBox(height: 14),
            Container(height: 1, color: semantic.line),
            const SizedBox(height: 10),
            // Two separate questions, so two separate buttons: a translation
            // can be wrong for a tag that still belongs in the dictionary, and
            // a hand-added tag can be a mistake while its translation was fine.
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                if (entry != null)
                  OutlinedButton.icon(
                    onPressed: widget.onDeleteTranslation,
                    icon: const Icon(Icons.translate, size: 14),
                    label: Text(
                      l10n.dictDeleteTranslationAction,
                      style: const TextStyle(fontSize: AppText.secondary),
                    ),
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      foregroundColor: scheme.error,
                    ),
                  ),
                if (widget.custom)
                  OutlinedButton.icon(
                    onPressed: widget.onRemoveCustom,
                    icon: const Icon(Icons.delete_outline, size: 14),
                    label: Text(
                      l10n.dictRemoveCustomAction,
                      style: const TextStyle(fontSize: AppText.secondary),
                    ),
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      foregroundColor: scheme.error,
                    ),
                  ),
              ],
            ),
          ],
          if (widget.info case final info?) ...[
            const SizedBox(height: 14),
            _danbooruSection(l10n, semantic, info),
          ],
          if (widget.datasetUsage case final uses?
              when widget.datasetImages > 0)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: _UsageBar(uses: uses, total: widget.datasetImages),
            ),
        ],
      ),
    );
  }

  /// What the lookup came back with. Everything here is a *candidate* — one
  /// click to adopt, never written on the user's behalf. Danbooru's
  /// `other_names` are given translations rather than guesses, but which of
  /// them is the right gloss (and whether it is in the right language at all)
  /// is a judgment only the user can make.
  Widget _danbooruSection(
    AppLocalizations l10n,
    AppSemanticColors semantic,
    DanbooruTagInfo info,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: semantic.raised,
        border: Border.all(color: semantic.line),
        borderRadius: BorderRadius.circular(AppRadii.control),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.cloud_done_outlined, size: 13, color: semantic.muted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  info.knownToDanbooru
                      ? l10n.dictFetchedHeader(
                          _categoryLabel(
                            l10n,
                            info.category ?? TagCategory.general,
                          ),
                          info.postCount,
                        )
                      : l10n.dictFetchUnknown(info.name),
                  style: TextStyle(
                    fontSize: AppText.micro,
                    color: semantic.muted,
                  ),
                ),
              ),
            ],
          ),
          // A tag danbooru has but this dictionary does not: adding it is what
          // turns the lookup into a tag the completion list can offer.
          if (info.knownToDanbooru && widget.onAddFromDanbooru != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () => widget.onAddFromDanbooru!(info),
                icon: const Icon(Icons.library_add_outlined, size: 14),
                label: Text(
                  l10n.dictFetchAddAction,
                  style: const TextStyle(fontSize: AppText.secondary),
                ),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
          ],
          if (info.otherNames.isNotEmpty) ...[
            const SizedBox(height: 10),
            _label(l10n.dictFetchOtherNames, semantic),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final name in info.otherNames)
                  _CandidateChip(
                    label: name,
                    onTap: () => _useAsTranslation(name),
                  ),
              ],
            ),
          ],
          if (info.wikiExcerpt case final excerpt?) ...[
            const SizedBox(height: 10),
            _label(l10n.dictFetchWikiLabel, semantic),
            Text(
              excerpt,
              style: TextStyle(
                fontSize: AppText.micro,
                color: scheme.onSurface,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => _useAsNote(excerpt),
                icon: const Icon(Icons.subject, size: 14),
                label: Text(
                  l10n.dictFetchUseAsNote,
                  style: const TextStyle(fontSize: AppText.secondary),
                ),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                ),
              ),
            ),
          ] else if (info.knownToDanbooru) ...[
            const SizedBox(height: 8),
            Text(
              l10n.dictFetchNoWiki,
              style: TextStyle(fontSize: AppText.micro, color: semantic.muted),
            ),
          ],
        ],
      ),
    );
  }
}

/// How much of the open dataset carries this tag. The number that decides
/// whether a translation is worth writing at all.
class _UsageBar extends StatelessWidget {
  const _UsageBar({required this.uses, required this.total});

  final int uses;
  final int total;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final semantic = context.semantic;
    final scheme = Theme.of(context).colorScheme;
    final fraction = total == 0 ? 0.0 : (uses / total).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 11),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border.all(color: semantic.line),
        borderRadius: BorderRadius.circular(AppRadii.control),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                l10n.dictUsageLabel,
                style: TextStyle(
                  fontSize: AppText.micro,
                  color: semantic.muted,
                ),
              ),
              const Spacer(),
              Text(
                l10n.dictUsageValue(uses, (fraction * 100).round()),
                style: TextStyle(
                  fontSize: AppText.micro,
                  color: semantic.muted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 3,
              backgroundColor: semantic.line,
              color: scheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}

// --- New custom tag ------------------------------------------------------

/// Name, category, gloss and aliases for a tag danbooru does not have.
///
/// A pane rather than a dialog: it replaces the tag editor in the same column,
/// so the list of what is already in the dictionary stays visible while a new
/// entry is being written — which is exactly what tells the user whether they
/// need one.
class _NewTagForm extends StatefulWidget {
  const _NewTagForm({required this.onCancel, required this.onSubmit});

  final VoidCallback onCancel;

  /// Takes the finished entry plus the translation to write alongside it.
  final Future<void> Function(TagDictionaryEntry entry, String gloss) onSubmit;

  @override
  State<_NewTagForm> createState() => _NewTagFormState();
}

class _NewTagFormState extends State<_NewTagForm> {
  final _name = TextEditingController();
  final _gloss = TextEditingController();
  final _aliases = TextEditingController();
  TagCategory _category = TagCategory.character;
  bool _autocomplete = true;

  @override
  void dispose() {
    _name.dispose();
    _gloss.dispose();
    _aliases.dispose();
    super.dispose();
  }

  String get _canonical => danbooruTagName(_name.text.trim());

  void _submit() {
    if (_canonical.isEmpty) return;
    widget.onSubmit(
      TagDictionaryEntry(
        name: _canonical,
        category: _category,
        aliases: [
          for (final alias in _aliases.text.split(','))
            if (alias.trim().isNotEmpty) alias.trim(),
        ],
        autocomplete: _autocomplete,
      ),
      _gloss.text,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final semantic = context.semantic;
    final scheme = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 15, 18, 15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Flexible(
                child: Text(
                  l10n.dictNewTagTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 9),
              Flexible(
                child: Text(
                  l10n.dictNewTagDesc,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: AppText.micro,
                    color: semantic.muted,
                  ),
                ),
              ),
              const Spacer(),
              PanelIconButton(
                icon: Icons.close,
                tooltip: l10n.cancel,
                size: 15,
                onPressed: widget.onCancel,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _label(l10n.dictAddTagNameLabel, semantic),
                    TextField(
                      controller: _name,
                      autofocus: true,
                      style: monoStyle(context, size: AppText.secondary),
                      decoration: InputDecoration(
                        hintText: l10n.dictAddTagNameHint,
                        isDense: true,
                      ),
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) => _submit(),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      // The canonical spelling, live: the field accepts what
                      // the user has in hand and this line says what will
                      // actually be stored.
                      _canonical.isEmpty
                          ? l10n.dictNewTagSpellingHint
                          : l10n.dictNewTagSpellingPreview(_canonical),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: AppText.micro,
                        color: semantic.muted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 160,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _label(l10n.dictAddTagCategoryLabel, semantic),
                    DropdownButtonFormField<TagCategory>(
                      initialValue: _category,
                      // Without this the button sizes to its widest item and
                      // overflows a fixed-width column the moment a localized
                      // category name is long.
                      isExpanded: true,
                      decoration: const InputDecoration(isDense: true),
                      style: const TextStyle(fontSize: AppText.secondary),
                      items: [
                        for (final category in TagCategory.values)
                          DropdownMenuItem(
                            value: category,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: _categoryColor(context, category),
                                  ),
                                ),
                                const SizedBox(width: 7),
                                // The menu is 160px wide and a localized
                                // category name can outgrow it.
                                Flexible(
                                  child: Text(
                                    _categoryLabel(l10n, category),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                      onChanged: (value) => setState(
                        () => _category = value ?? TagCategory.general,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _label(l10n.dictTranslationLabel, semantic),
          TextField(
            controller: _gloss,
            style: const TextStyle(fontSize: AppText.secondary),
            decoration: InputDecoration(
              hintText: l10n.dictTranslationHint,
              isDense: true,
            ),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 12),
          _label(l10n.dictNewTagAliasesLabel, semantic),
          TextField(
            controller: _aliases,
            style: monoStyle(context, size: AppText.secondary),
            decoration: InputDecoration(
              hintText: l10n.dictNewTagAliasesHint,
              isDense: true,
            ),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            decoration: BoxDecoration(
              color: scheme.surface,
              border: Border.all(color: semantic.line),
              borderRadius: BorderRadius.circular(AppRadii.control),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        l10n.dictNewTagAutocompleteTitle,
                        style: const TextStyle(fontSize: AppText.secondary),
                      ),
                      Text(
                        l10n.dictNewTagAutocompleteDesc,
                        style: TextStyle(
                          fontSize: AppText.micro,
                          color: semantic.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                AppSwitch(
                  value: _autocomplete,
                  onChanged: (value) => setState(() => _autocomplete = value),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.dictNewTagExistsHint,
                  style: TextStyle(
                    fontSize: AppText.micro,
                    color: semantic.muted,
                  ),
                ),
              ),
              TextButton(
                onPressed: widget.onCancel,
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
                child: Text(
                  l10n.cancel,
                  style: const TextStyle(fontSize: AppText.secondary),
                ),
              ),
              const SizedBox(width: 6),
              FilledButton(
                onPressed: _canonical.isEmpty ? null : _submit,
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  minimumSize: const Size(0, 30),
                ),
                child: Text(
                  l10n.dictNewTagSubmit,
                  style: const TextStyle(fontSize: AppText.secondary),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// --- Danbooru lookup pane ------------------------------------------------

/// Look a tag up on danbooru and decide, from the answer, whether to write it
/// into the dictionary.
///
/// The order matters: the previous flow asked for a name, wrote nothing, and
/// left the result to be discovered in the editor. Here the result is the
/// point — category, post count, wiki excerpt and exactly which fields a write
/// would touch, before anything is written.
class _FetchForm extends StatefulWidget {
  const _FetchForm({
    required this.initial,
    required this.fetching,
    required this.onCancel,
    required this.onLookup,
    required this.isKnownLocally,
    required this.onWrite,
    required this.onOpen,
  });

  final String initial;
  final bool fetching;
  final VoidCallback onCancel;
  final Future<DanbooruTagInfo?> Function(String query) onLookup;

  /// Whether this dictionary already has the tag; decides whether the primary
  /// action writes it or simply goes to it.
  final bool Function(String name) isKnownLocally;

  final Future<void> Function(DanbooruTagInfo info) onWrite;
  final ValueChanged<String> onOpen;

  @override
  State<_FetchForm> createState() => _FetchFormState();
}

class _FetchFormState extends State<_FetchForm> {
  late final TextEditingController _query = TextEditingController(
    text: widget.initial,
  );
  DanbooruTagInfo? _result;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    final value = _query.text.trim();
    if (value.isEmpty) return;
    final info = await widget.onLookup(value);
    if (mounted) setState(() => _result = info);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final semantic = context.semantic;
    final scheme = Theme.of(context).colorScheme;
    final result = _result;
    final known = result != null && widget.isKnownLocally(result.name);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 15, 18, 15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                l10n.dictFetchAction,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  l10n.dictFetchPrivacyNote,
                  maxLines: 2,
                  style: TextStyle(
                    fontSize: AppText.micro,
                    color: semantic.muted,
                  ),
                ),
              ),
              PanelIconButton(
                icon: Icons.close,
                tooltip: l10n.cancel,
                size: 15,
                onPressed: widget.onCancel,
              ),
            ],
          ),
          const SizedBox(height: 12),
          _label(l10n.dictFetchPromptLabel, semantic),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _query,
                  autofocus: true,
                  style: monoStyle(context, size: AppText.secondary),
                  decoration: InputDecoration(
                    hintText: l10n.dictFetchPromptHint,
                    isDense: true,
                  ),
                  onSubmitted: (_) => _run(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: widget.fetching ? null : _run,
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  minimumSize: const Size(0, 34),
                ),
                child: widget.fetching
                    ? const SizedBox(
                        width: 13,
                        height: 13,
                        child: CircularProgressIndicator(strokeWidth: 1.5),
                      )
                    : Text(
                        l10n.dictFetchLookupAction,
                        style: const TextStyle(fontSize: AppText.secondary),
                      ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            l10n.dictFetchPromptNote,
            style: TextStyle(fontSize: AppText.micro, color: semantic.muted),
          ),
          if (result != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.fromLTRB(13, 11, 13, 12),
              decoration: BoxDecoration(
                color: scheme.surface,
                border: Border.all(color: semantic.line),
                borderRadius: BorderRadius.circular(AppRadii.control),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          result.name,
                          overflow: TextOverflow.ellipsis,
                          style: monoStyle(context, size: AppText.base),
                        ),
                      ),
                      const SizedBox(width: 9),
                      Icon(
                        result.knownToDanbooru
                            ? Icons.check_circle_outline
                            : Icons.help_outline,
                        size: 12,
                        color: result.knownToDanbooru
                            ? semantic.ok
                            : semantic.warn,
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          result.knownToDanbooru
                              ? l10n.dictFetchedHeader(
                                  _categoryLabel(
                                    l10n,
                                    result.category ?? TagCategory.general,
                                  ),
                                  result.postCount,
                                )
                              : l10n.dictFetchUnknown(result.name),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: AppText.micro,
                            color: semantic.muted,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (result.wikiExcerpt case final excerpt?) ...[
                    const SizedBox(height: 8),
                    Text(
                      excerpt,
                      style: TextStyle(
                        fontSize: AppText.micro,
                        color: scheme.onSurface,
                        height: 1.45,
                      ),
                    ),
                  ],
                  if (result.knownToDanbooru && !known) ...[
                    const SizedBox(height: 9),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          l10n.dictFetchWillWrite,
                          style: TextStyle(
                            fontSize: AppText.micro,
                            color: semantic.muted,
                          ),
                        ),
                        for (final field in [
                          l10n.dictAddTagCategoryLabel,
                          l10n.dictFetchFieldPostCount,
                          l10n.dictAliasesLabel,
                        ])
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: semantic.raised,
                              border: Border.all(color: semantic.line),
                              borderRadius: BorderRadius.circular(
                                AppRadii.input,
                              ),
                            ),
                            child: Text(
                              field,
                              style: const TextStyle(fontSize: AppText.micro),
                            ),
                          ),
                        Text(
                          l10n.dictFetchKeepsEdits,
                          style: TextStyle(
                            fontSize: AppText.micro,
                            color: semantic.muted.withValues(alpha: 0.75),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (known) ...[
                    const SizedBox(height: 8),
                    Text(
                      l10n.dictFetchAlreadyKnown,
                      style: TextStyle(
                        fontSize: AppText.micro,
                        color: semantic.muted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                const Spacer(),
                TextButton(
                  onPressed: widget.onCancel,
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                  child: Text(
                    l10n.cancel,
                    style: const TextStyle(fontSize: AppText.secondary),
                  ),
                ),
                const SizedBox(width: 6),
                FilledButton(
                  onPressed: !result.knownToDanbooru
                      ? null
                      : known
                      ? () => widget.onOpen(result.name)
                      : () => widget.onWrite(result),
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    minimumSize: const Size(0, 30),
                  ),
                  child: Text(
                    known
                        ? l10n.dictFetchOpenAction
                        : l10n.dictFetchWriteAction,
                    style: const TextStyle(fontSize: AppText.secondary),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// --- Small shared pieces -------------------------------------------------

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(AppRadii.pill),
    ),
    child: Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: AppText.micro, color: color),
    ),
  );
}

/// A hairline text button sized for a header row — smaller than an
/// [OutlinedButton] and quiet enough to sit beside a title.
class _MiniAction extends StatelessWidget {
  const _MiniAction({
    required this.label,
    this.icon,
    this.color,
    this.accent = false,
    this.busy = false,
    this.onTap,
  });

  final String label;
  final IconData? icon;
  final Color? color;
  final bool accent;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    final scheme = Theme.of(context).colorScheme;
    final tint = color ?? (accent ? scheme.primary : semantic.muted);
    return MouseRegion(
      cursor: onTap == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            border: Border.all(
              color: accent ? tint.withValues(alpha: 0.5) : semantic.line,
            ),
            borderRadius: BorderRadius.circular(AppRadii.input),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (busy)
                SizedBox(
                  width: 11,
                  height: 11,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: tint,
                  ),
                )
              else if (icon != null)
                Icon(icon, size: 12, color: tint),
              if (busy || icon != null) const SizedBox(width: 5),
              // Flexible even though the row is min-sized: these sit in wraps
              // that hand down a bounded width, and a localized label longer
              // than its slot must ellipsize rather than overflow.
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: AppText.micro, color: tint),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Width of [label] as this toolbar will draw it.
///
/// Always measured at the *selected* weight, whatever the segment's current
/// state: a control that grew by two pixels every time it was clicked would
/// nudge its neighbours on every click.
double _labelWidth(BuildContext context, String label) {
  final painter = TextPainter(
    text: TextSpan(
      text: label,
      style: DefaultTextStyle.of(context).style.merge(
        const TextStyle(
          fontSize: AppText.secondary,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    textDirection: Directionality.of(context),
    maxLines: 1,
  )..layout();
  return painter.width;
}

/// One choice inside the filter group.
class _ToolbarSegment {
  const _ToolbarSegment({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// 11px of padding a side around the label.
  double width(BuildContext context) => _labelWidth(context, label) + 22;
}

/// One control on the toolbar's right-hand side, in whichever of its two
/// shapes: the filter group, or an icon action.
class _ToolbarEntry {
  const _ToolbarEntry.segments(this.segments)
    : icon = null,
      label = '',
      accent = false,
      busy = false,
      onTap = null;

  const _ToolbarEntry.action({
    required IconData this.icon,
    required this.label,
    required VoidCallback this.onTap,
    this.accent = false,
    this.busy = false,
  }) : segments = const [];

  /// Non-empty for the filter group, which moves as one: half a segmented
  /// control is not a control.
  final List<_ToolbarSegment> segments;

  final IconData? icon;
  final String label;
  final bool accent;
  final bool busy;
  final VoidCallback? onTap;

  bool get isSegments => segments.isNotEmpty;

  /// What this control will measure once built, so the strip can decide what
  /// fits before building anything. An action adds a 13px icon and its 6px
  /// gap to 11px of padding and a 1px border a side; the group adds the 2px
  /// inset of its slot.
  double width(BuildContext context) => isSegments
      ? segments.fold(0.0, (sum, s) => sum + s.width(context)) + 4
      : _labelWidth(context, label) + 43;
}

/// The toolbar band: a search field that takes the slack, and as many controls
/// beside it as the window can hold.
///
/// One row, always — the previous `Wrap` grew a second line on a narrow window
/// and took the search field's vertical centre with it. What no longer fits
/// moves into an overflow menu instead, so the band keeps one baseline at
/// every width.
class _ToolbarStrip extends StatelessWidget {
  const _ToolbarStrip({
    required this.search,
    required this.entries,
    required this.overflowTooltip,
  });

  final Widget search;
  final List<_ToolbarEntry> entries;
  final String overflowTooltip;

  /// The search field is never squeezed below this; past it the controls give
  /// way instead, because a two-character search box is not a search box.
  static const double _searchMin = 190;
  static const double _gap = 6;
  static const double _searchGap = 10;
  static const double _overflowWidth = 32;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final widths = [for (final entry in entries) entry.width(context)];
      final budget = constraints.maxWidth - _searchMin - _searchGap;

      double widthFor(int count, {required bool withOverflow}) {
        var width = count == 0
            ? 0.0
            : widths.take(count).fold(0.0, (a, b) => a + b) +
                  _gap * (count - 1);
        if (withOverflow) width += (count == 0 ? 0 : _gap) + _overflowWidth;
        return width;
      }

      var visible = entries.length;
      if (widthFor(visible, withOverflow: false) > budget) {
        // Drop from the end — the list order is the give-up order — until what
        // is left plus the overflow button fits.
        visible = entries.length - 1;
        while (visible > 0 && widthFor(visible, withOverflow: true) > budget) {
          visible--;
        }
      }

      return Row(
        children: [
          Expanded(child: search),
          const SizedBox(width: _searchGap),
          for (final (index, entry) in entries.take(visible).indexed) ...[
            if (index > 0) const SizedBox(width: _gap),
            _ToolbarEntryView(entry: entry),
          ],
          if (visible < entries.length) ...[
            if (visible > 0) const SizedBox(width: _gap),
            _ToolbarOverflowButton(
              entries: entries.sublist(visible),
              tooltip: overflowTooltip,
            ),
          ],
        ],
      );
    },
  );
}

/// Renders one [_ToolbarEntry] in its own shape.
class _ToolbarEntryView extends StatelessWidget {
  const _ToolbarEntryView({required this.entry});

  final _ToolbarEntry entry;

  @override
  Widget build(BuildContext context) => entry.isSegments
      ? _FilterSegments(segments: entry.segments)
      : _ToolbarButton(
          icon: entry.icon!,
          label: entry.label,
          accent: entry.accent,
          busy: entry.busy,
          onTap: entry.onTap!,
        );
}

/// The filter group: one recessed slot holding the four views of the list,
/// with the active one raised out of it.
///
/// A segmented control rather than four pills, because these are four states
/// of one thing — exactly one is always active — and pills say "toggles" to a
/// reader. Not [SegmentedControl]: that one is equal-width, which is what
/// makes its sliding thumb cheap, and here the labels carry counts and run
/// from "All" to "Untranslated". Each segment is instead pinned to its own
/// measured width so the group never resizes as the selection moves.
class _FilterSegments extends StatelessWidget {
  const _FilterSegments({required this.segments});

  final List<_ToolbarSegment> segments;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppRadii.control),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final segment in segments)
            _FilterSegment(segment: segment, width: segment.width(context)),
        ],
      ),
    );
  }
}

class _FilterSegment extends StatelessWidget {
  const _FilterSegment({required this.segment, required this.width});

  final _ToolbarSegment segment;
  final double width;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final semantic = context.semantic;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: segment.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 170),
          curve: Curves.easeOut,
          width: width,
          padding: const EdgeInsets.symmetric(vertical: 4),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: segment.selected ? semantic.raised : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadii.input),
          ),
          child: Text(
            segment.label,
            maxLines: 1,
            style: TextStyle(
              fontSize: AppText.secondary,
              fontWeight: segment.selected ? FontWeight.w600 : FontWeight.w400,
              color: segment.selected ? scheme.onSurface : semantic.muted,
            ),
          ),
        ),
      ),
    );
  }
}

/// What did not fit, in the app's own popup surface rather than Material's
/// default one.
class _ToolbarOverflowButton extends StatelessWidget {
  const _ToolbarOverflowButton({required this.entries, required this.tooltip});

  final List<_ToolbarEntry> entries;
  final String tooltip;

  /// The hidden controls flattened into menu rows: the filter group expands
  /// into one row per segment, since a segmented control cannot be drawn in a
  /// popup menu but its choices still have to be reachable.
  List<VoidCallback> _actions() => [
    for (final entry in entries)
      if (entry.isSegments)
        for (final segment in entry.segments) segment.onTap
      else
        entry.onTap!,
  ];

  Future<void> _show(BuildContext context) async {
    final scheme = Theme.of(context).colorScheme;
    final box = context.findRenderObject()! as RenderBox;
    var index = 0;
    final items = <PopupMenuEntry<int>>[];
    for (final entry in entries) {
      if (entry.isSegments) {
        for (final segment in entry.segments) {
          items.add(
            panelMenuItem(
              context: context,
              value: index++,
              icon: segment.selected ? Icons.check : Icons.filter_list_outlined,
              label: segment.label,
              color: segment.selected ? scheme.primary : null,
            ),
          );
        }
      } else {
        items.add(
          panelMenuItem(
            context: context,
            value: index++,
            icon: entry.icon!,
            label: entry.label,
            color: entry.accent ? scheme.primary : null,
          ),
        );
      }
    }
    final picked = await showPanelContextMenu<int>(
      context: context,
      position: box.localToGlobal(Offset(0, box.size.height + 4)),
      items: items,
    );
    if (picked != null) _actions()[picked]();
  }

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    // A filter that is not "all" hiding in the menu has to say so from the
    // outside, or the strip reads as if nothing were filtering the list.
    final flagged = entries.any(
      (e) => e.isSegments && !e.segments.first.selected,
    );
    final tint = flagged
        ? Theme.of(context).colorScheme.primary
        : semantic.muted;
    return Tooltip(
      message: tooltip,
      child: Builder(
        builder: (buttonContext) => MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _show(buttonContext),
            child: Container(
              width: _ToolbarStrip._overflowWidth,
              height: 26,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                border: Border.all(
                  color: flagged ? tint.withValues(alpha: 0.5) : semantic.line,
                ),
                borderRadius: BorderRadius.circular(AppRadii.control),
              ),
              child: Icon(Icons.more_horiz, size: 15, color: tint),
            ),
          ),
        ),
      ),
    );
  }
}

/// The toolbar's own button size: bigger than [_MiniAction], quieter than a
/// [FilledButton], because neither of the two actions up there is the one the
/// user came for.
class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.accent = false,
    this.busy = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool accent;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    final scheme = Theme.of(context).colorScheme;
    final tint = accent ? scheme.primary : semantic.muted;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
          decoration: BoxDecoration(
            border: Border.all(
              color: accent ? tint.withValues(alpha: 0.5) : semantic.line,
            ),
            borderRadius: BorderRadius.circular(AppRadii.control),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (busy)
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: tint,
                  ),
                )
              else
                Icon(icon, size: 13, color: tint),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: AppText.secondary, color: tint),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A one-click translation candidate from danbooru's `other_names`.
class _CandidateChip extends StatelessWidget {
  const _CandidateChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: AppLocalizations.of(context)!.dictFetchUseAsTranslation,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
            decoration: BoxDecoration(
              color: semantic.panel,
              border: Border.all(color: scheme.primary.withValues(alpha: 0.45)),
              borderRadius: BorderRadius.circular(AppRadii.pill),
            ),
            child: Text(
              label,
              style: const TextStyle(fontSize: AppText.secondary),
            ),
          ),
        ),
      ),
    );
  }
}

Widget _label(String text, AppSemanticColors semantic) => Padding(
  padding: const EdgeInsets.only(bottom: 5),
  child: Text(
    text,
    style: TextStyle(
      fontSize: AppText.micro,
      color: semantic.muted,
      fontWeight: FontWeight.w600,
    ),
  ),
);

/// Danbooru's own category hues, which is what makes them worth using: a user
/// who has ever browsed danbooru already reads blue as general and green as a
/// character. Fixed rather than derived from the accent — they are data, and
/// the accent means selection.
Color _categoryColor(BuildContext context, TagCategory? category) =>
    switch (category) {
      TagCategory.general => const Color(0xFF7FA7D9),
      TagCategory.character => const Color(0xFF8FCB9B),
      TagCategory.copyright => const Color(0xFFB79AD6),
      TagCategory.artist => const Color(0xFFD98E8E),
      TagCategory.meta => const Color(0xFFD9B384),
      null => context.semantic.muted,
    };

String _categoryLabel(AppLocalizations l10n, TagCategory category) =>
    switch (category) {
      TagCategory.general => l10n.dictCategoryGeneral,
      TagCategory.artist => l10n.dictCategoryArtist,
      TagCategory.copyright => l10n.dictCategoryCopyright,
      TagCategory.character => l10n.dictCategoryCharacter,
      TagCategory.meta => l10n.dictCategoryMeta,
    };

String _sourceLabel(AppLocalizations l10n, TagTranslationSource source) =>
    switch (source) {
      TagTranslationSource.manual => l10n.dictSourceManual,
      TagTranslationSource.llm => l10n.dictSourceLlm,
      TagTranslationSource.danbooru => l10n.dictSourceDanbooru,
    };

/// `7.1M` rather than `7148213`: the list column is 40px wide and the exact
/// figure was never the point — only the order of magnitude is.
String compactCount(int count) {
  if (count >= 1000000) {
    final m = count / 1000000;
    return '${m >= 10 ? m.toStringAsFixed(0) : m.toStringAsFixed(1)}M';
  }
  if (count >= 1000) {
    final k = count / 1000;
    return '${k >= 10 ? k.toStringAsFixed(0) : k.toStringAsFixed(1)}K';
  }
  return '$count';
}
