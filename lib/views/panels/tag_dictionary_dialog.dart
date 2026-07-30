import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../l10n/app_localizations.dart';
import '../../models/tag_dictionary.dart';
import '../../models/tag_translation.dart';
import '../../services/danbooru_api.dart';
import '../../services/tag_dictionary_service.dart';
import '../../services/tag_translation_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/external_links.dart';
import '../../utils/tag_text.dart';
import '../../widgets/panel_widgets.dart';

/// The dictionary manager: browse and search tags, write their translations,
/// and add vocabulary danbooru does not have.
///
/// Two lists in one, switched by the search box being empty:
///
///  * empty — the glossary itself, plus the user's own dictionary additions.
///    This is the "what have I translated" view, and the only place a stray
///    entry can be found and removed.
///  * non-empty — dictionary hits *and* glossary hits, so a tag can be found
///    by its translation as readily as by its name. Searching `长发` is the
///    whole reason a Chinese-speaking user keeps a glossary at all.
/// [initialTag] opens straight onto that tag's editor — the path taken from a
/// tag's own context menu, where the user has already picked the tag.
///
/// [api] is injectable for tests; the default talks to danbooru.
Future<void> showTagDictionaryDialog(
  BuildContext context, {
  String? initialTag,
  DanbooruApi? api,
}) => showDialog(
  context: context,
  builder: (_) => ChangeNotifierProvider.value(
    value: context.read<AppState>(),
    child: _TagDictionaryDialog(initialTag: initialTag, api: api),
  ),
);

/// How many dictionary hits the search lists. Well past what fits on screen —
/// the list scrolls — but bounded, because a two-letter query matches
/// thousands and every row builds a translation lookup.
const _searchLimit = 80;

class _TagDictionaryDialog extends StatefulWidget {
  const _TagDictionaryDialog({this.initialTag, this.api});

  final String? initialTag;
  final DanbooruApi? api;

  @override
  State<_TagDictionaryDialog> createState() => _TagDictionaryDialogState();
}

class _TagDictionaryDialogState extends State<_TagDictionaryDialog> {
  late final TextEditingController _searchController = TextEditingController(
    // Seeded so the tag is also *findable* in the list beside its editor —
    // opening onto a selection the list does not contain reads as a glitch.
    text: _initialSelection ?? '',
  );
  late String _query = _initialSelection ?? '';

  /// The tag being edited, in danbooru spelling. Held as a name rather than an
  /// index because the list under it is rebuilt on every keystroke.
  late String? _selected = _initialSelection;

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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  /// The rows to show, in display order. See the class doc for the two modes.
  List<_DictRow> _rows() {
    final glossary = _glossary;
    final dictionary = _dictionary;
    final query = _query.trim();

    // Deduplicates across the two sources below — the same tag can be both a
    // dictionary hit and a glossary hit, and it must occupy one row.
    final seen = <String>{};
    final rows = <_DictRow>[];

    /// A row for a translated tag, however it was reached. [custom] cannot be
    /// derived here: the two callers know it by different means.
    _DictRow glossaryRow(TagTranslation entry, {bool custom = false}) {
      final hit = dictionary.lookup(entry.tag);
      return _DictRow(
        tag: entry.tag,
        category: hit?.category,
        custom: custom,
        translation: entry,
        // Translated, but the dictionary has never heard of it — a tag read
        // out of a dataset, or one whose spelling has since changed. Flagged
        // rather than hidden: an unreachable translation is exactly the kind of
        // thing that needs finding. Only once the dictionary is actually
        // loaded, or a cold start would brand every entry unknown.
        orphan: dictionary.isReady && hit == null,
      );
    }

    if (query.isEmpty) {
      for (final entry in dictionary.customEntries) {
        if (!seen.add(tagLookupKey(entry.name))) continue;
        rows.add(
          _DictRow(
            tag: entry.name,
            category: entry.category,
            custom: true,
            translation: glossary.lookup(entry.name),
          ),
        );
      }
      // Custom entries went out above and `seen` skips them, so nothing left
      // here can be one.
      for (final entry in glossary.entries) {
        if (!seen.add(tagLookupKey(entry.tag))) continue;
        rows.add(glossaryRow(entry));
      }
      return rows;
    }

    for (final hit in dictionary.search(query, limit: _searchLimit)) {
      if (!seen.add(tagLookupKey(hit.name))) continue;
      rows.add(
        _DictRow(
          tag: hit.name,
          category: hit.isLocal ? null : hit.entry.category,
          custom: hit.isCustom,
          translation: glossary.lookup(hit.name),
        ),
      );
    }
    // Then the glossary, matched on the translation itself — the direction the
    // dictionary cannot answer, and the reason to keep one. A hit found this
    // way may still be a custom tag whose *name* did not match, so unlike the
    // empty-query pass this one has to check. One pass over the (short) custom
    // list rather than a scan per row: the glossary can hold thousands.
    final customKeys = {
      for (final entry in dictionary.customEntries) tagLookupKey(entry.name),
    };
    final needle = query.toLowerCase();
    for (final entry in glossary.entries) {
      if (!entry.text.toLowerCase().contains(needle) &&
          !(entry.note?.toLowerCase().contains(needle) ?? false)) {
        continue;
      }
      final key = tagLookupKey(entry.tag);
      if (!seen.add(key)) continue;
      rows.add(glossaryRow(entry, custom: customKeys.contains(key)));
    }
    return rows;
  }

  bool _isCustom(String tag) {
    final key = tagLookupKey(tag);
    return _dictionary.customEntries.any((e) => tagLookupKey(e.name) == key);
  }

  Future<void> _saveTranslation(
    String tag,
    String text,
    String? note,
    TagTranslationSource source,
  ) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      // Clearing the field is how a translation is deleted; a separate empty
      // entry would render as a blank gloss on every chip.
      await _glossary.remove([tag]);
      return;
    }
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

  // --- Danbooru lookup ---------------------------------------------------

  /// Fetches [query] — a tag name or a pasted danbooru URL — and selects the
  /// tag it resolves to.
  ///
  /// A tag danbooru has never heard of is not treated as a failure: it comes
  /// back with `knownToDanbooru == false`, and saying so is more useful than an
  /// error, because "danbooru doesn't have this either" is exactly what
  /// confirms a typo.
  Future<void> _lookup(String query) async {
    final l10n = AppLocalizations.of(context)!;
    setState(() => _fetching = true);
    try {
      final info = await _api.fetch(query);
      if (!mounted) return;
      setState(() {
        _fetched[tagLookupKey(info.name)] = info;
        _selected = info.name;
        // The list is keyed off the search box, so point it at the tag that
        // came back — otherwise the editor shows a tag the list beside it does
        // not contain.
        _searchController.text = info.name;
        _query = info.name;
      });
      if (!info.knownToDanbooru) _snack(l10n.dictFetchUnknown(info.name));
    } on DanbooruApiException catch (e) {
      if (mounted) _snack(l10n.dictFetchFailed(e.message));
    } finally {
      if (mounted) setState(() => _fetching = false);
    }
  }

  /// Asks for a tag name or URL, then looks it up. The entry point for a tag
  /// that is in neither the dictionary nor the glossary — which is precisely
  /// the case a pasted wiki URL solves.
  Future<void> _promptLookup() async {
    final query = await showDialog<String>(
      context: context,
      builder: (_) => _LookupPromptDialog(initial: _selected ?? ''),
    );
    if (query == null || !mounted) return;
    await _lookup(query);
  }

  /// Appends one entry to the user's dictionary additions. The service takes
  /// the whole list, so every caller has to hand back what is already there.
  Future<void> _appendCustom(TagDictionaryEntry entry) {
    final dictionary = _dictionary;
    return dictionary.setCustomEntries([...dictionary.customEntries, entry]);
  }

  /// Adds a tag danbooru knows but this dictionary does not, with danbooru's
  /// own category and post count. Turns a lookup into a completable tag.
  Future<void> _addFromDanbooru(DanbooruTagInfo info) async {
    final l10n = AppLocalizations.of(context)!;
    await _appendCustom(
      TagDictionaryEntry(
        name: info.name,
        category: info.category ?? TagCategory.general,
        postCount: info.postCount,
      ),
    );
    if (!mounted) return;
    setState(() {});
    _snack(l10n.dictFetchAdded(info.name));
  }

  Future<void> _addCustomTag() async {
    // Already canonical and complete — _AddTagDialog normalizes the name it
    // pops, so there is nothing left to rebuild here.
    final result = await showDialog<TagDictionaryEntry>(
      context: context,
      builder: (_) => const _AddTagDialog(),
    );
    if (result == null || !mounted) return;
    final l10n = AppLocalizations.of(context)!;
    if (_dictionary.lookup(result.name) != null) {
      _snack(l10n.dictAddTagExists(result.name));
      return;
    }
    await _appendCustom(result);
    if (!mounted) return;
    setState(() {
      _searchController.clear();
      _query = '';
      _selected = result.name;
    });
  }

  Future<void> _removeCustomTag(String tag) async {
    final key = tagLookupKey(tag);
    final dictionary = _dictionary;
    await dictionary.setCustomEntries([
      for (final entry in dictionary.customEntries)
        if (tagLookupKey(entry.name) != key) entry,
    ]);
    if (mounted) setState(() {});
  }

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
        final selected = _selected;
        return Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820, maxHeight: 580),
            child: GlassSurface(
              borderRadius: BorderRadius.circular(14),
              blurSigma: 14,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _header(l10n, semantic),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(width: 330, child: _list(l10n, semantic, rows)),
                        Container(width: 1, color: semantic.line),
                        Expanded(
                          child: selected == null
                              ? Center(
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
                                )
                              : _TranslationForm(
                                  // New controllers when the selection moves.
                                  // Deliberately *not* keyed on the fetched
                                  // info: a lookup must not throw away
                                  // whatever the user was typing.
                                  key: ValueKey(
                                    '$selected/'
                                    '${_glossary.lookup(selected)?.text}',
                                  ),
                                  tag: selected,
                                  entry: _glossary.lookup(selected),
                                  dictionaryEntry: _dictionary.lookup(selected),
                                  custom: _isCustom(selected),
                                  info: _fetched[tagLookupKey(selected)],
                                  fetching: _fetching,
                                  onSave: (text, note, source) =>
                                      _saveTranslation(
                                        selected,
                                        text,
                                        note,
                                        source,
                                      ),
                                  onFetch: () => _lookup(selected),
                                  onRemoveCustom: () =>
                                      _removeCustomTag(selected),
                                  // Only offered when danbooru has the tag and
                                  // this dictionary does not — otherwise there
                                  // is nothing to add.
                                  onAddFromDanbooru:
                                      _dictionary.lookup(selected) == null
                                      ? _addFromDanbooru
                                      : null,
                                ),
                        ),
                      ],
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

  Widget _header(AppLocalizations l10n, AppSemanticColors semantic) => Container(
    padding: const EdgeInsets.fromLTRB(18, 12, 10, 12),
    decoration: BoxDecoration(
      border: Border(bottom: BorderSide(color: semantic.line)),
    ),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.dictManagerTitle,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              // Which glossary is being edited is the one thing a user must
              // not have to guess: translations are per language, and the
              // language follows the app's own setting.
              Text(
                l10n.dictManagerSubtitle(
                  _glossary.languageCode.toUpperCase(),
                  _glossary.count,
                ),
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
        if (_fetching)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: SizedBox(
              width: 13,
              height: 13,
              child: CircularProgressIndicator(strokeWidth: 1.5),
            ),
          )
        else
          PanelIconButton(
            icon: Icons.cloud_download_outlined,
            tooltip: l10n.dictFetchPromptTooltip,
            onPressed: _promptLookup,
          ),
        PanelIconButton(
          icon: Icons.add,
          tooltip: l10n.dictAddTagAction,
          onPressed: _addCustomTag,
        ),
        PanelIconButton(
          icon: Icons.close,
          tooltip: l10n.close,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    ),
  );

  Widget _list(
    AppLocalizations l10n,
    AppSemanticColors semantic,
    List<_DictRow> rows,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
        child: PanelSearchField(
          hint: l10n.dictSearchHint,
          controller: _searchController,
          padding: EdgeInsets.zero,
          onChanged: (value) => setState(() => _query = value),
        ),
      ),
      Expanded(
        child: rows.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    _query.trim().isEmpty
                        ? l10n.dictGlossaryEmpty
                        : l10n.dictNoResults,
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
                  selected: rows[index].tag == _selected,
                  onTap: () => setState(() => _selected = rows[index].tag),
                ),
              ),
      ),
    ],
  );

  Widget _footer(AppLocalizations l10n, AppSemanticColors semantic) => Container(
    padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
    decoration: BoxDecoration(
      border: Border(top: BorderSide(color: semantic.line)),
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(
            l10n.dictFooterHint,
            style: TextStyle(fontSize: AppText.micro, color: semantic.muted),
          ),
        ),
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
  );
}

/// One row of the manager's list.
class _DictRow {
  const _DictRow({
    required this.tag,
    this.category,
    this.custom = false,
    this.translation,
    this.orphan = false,
  });

  final String tag;

  /// Null when nothing in the dictionary claims this tag.
  final TagCategory? category;

  /// A tag the user added to the dictionary by hand.
  final bool custom;

  final TagTranslation? translation;

  /// Translated, but no longer (or never) a tag the dictionary knows.
  final bool orphan;
}

class _DictRowTile extends StatelessWidget {
  const _DictRowTile({
    required this.row,
    required this.selected,
    required this.onTap,
  });

  final _DictRow row;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final semantic = context.semantic;
    final scheme = Theme.of(context).colorScheme;
    final gloss = row.translation?.text;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: selected
                  ? scheme.primary.withValues(alpha: 0.20)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(AppRadii.input),
            ),
            child: Row(
              children: [
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
                      if (gloss != null)
                        Text(
                          gloss,
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
                if (row.custom)
                  _Badge(label: l10n.dictCustomBadge, color: scheme.primary)
                else if (row.orphan)
                  _Badge(label: l10n.dictOrphanBadge, color: semantic.warn)
                else if (gloss == null)
                  Icon(
                    Icons.translate_outlined,
                    size: 13,
                    color: semantic.muted.withValues(alpha: 0.5),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

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
      style: TextStyle(fontSize: AppText.micro, color: color),
    ),
  );
}

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
    required this.onSave,
    required this.onFetch,
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
  final Future<void> Function(
    String text,
    String? note,
    TagTranslationSource source,
  )
  onSave;
  final Future<void> Function() onFetch;
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final semantic = context.semantic;
    final entry = widget.entry;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.tag,
                  style: monoStyle(context, size: 14),
                ),
              ),
              if (widget.dictionaryEntry case final hit?)
                Text(
                  l10n.dictCategoryAndCount(
                    _categoryLabel(l10n, hit.category),
                    hit.postCount,
                  ),
                  style: TextStyle(
                    fontSize: AppText.micro,
                    color: semantic.muted,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          _label(l10n.dictTranslationLabel, semantic),
          TextField(
            controller: _text,
            autofocus: true,
            style: const TextStyle(fontSize: AppText.secondary),
            decoration: InputDecoration(
              hintText: l10n.dictTranslationHint,
              isDense: true,
            ),
            onChanged: (_) {
              // Typing over danbooru's own wording makes the entry the user's
              // again, so a later "clear fetched translations" leaves it alone.
              if (!_dirty || _source != TagTranslationSource.manual) {
                setState(() {
                  _dirty = true;
                  _source = TagTranslationSource.manual;
                });
              }
            },
            onSubmitted: (_) => _save(),
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
              if (entry != null)
                Text(
                  _sourceLabel(l10n, entry.source),
                  style: TextStyle(
                    fontSize: AppText.micro,
                    color: semantic.muted,
                  ),
                ),
              const Spacer(),
              FilledButton(
                onPressed: _dirty ? _save : null,
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
          const SizedBox(height: 18),
          Container(height: 1, color: semantic.line),
          const SizedBox(height: 10),
          // Clearing the field is the documented way to delete a translation,
          // so there is no separate delete button for it — one action, one
          // meaning.
          Text(
            l10n.dictClearFieldHint,
            style: TextStyle(fontSize: AppText.micro, color: semantic.muted),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              // A hand-added tag is the user's own invention: danbooru has
              // neither a wiki page nor a tag record for it, so both the link
              // and the lookup would come back empty.
              if (!widget.custom) ...[
                OutlinedButton.icon(
                  onPressed: widget.fetching ? null : widget.onFetch,
                  icon: widget.fetching
                      ? const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 1.5),
                        )
                      : const Icon(Icons.cloud_download_outlined, size: 14),
                  label: Text(
                    widget.fetching ? l10n.dictFetching : l10n.dictFetchAction,
                    style: const TextStyle(fontSize: AppText.secondary),
                  ),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () =>
                      openExternalUrl(danbooruWikiUrl(widget.tag)),
                  icon: const Icon(Icons.menu_book_outlined, size: 14),
                  label: Text(
                    l10n.tagWikiAction,
                    style: const TextStyle(fontSize: AppText.secondary),
                  ),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
              if (widget.custom)
                OutlinedButton.icon(
                  onPressed: widget.onRemoveCustom,
                  icon: const Icon(Icons.remove_circle_outline, size: 14),
                  label: Text(
                    l10n.dictRemoveCustomAction,
                    style: const TextStyle(fontSize: AppText.secondary),
                  ),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    foregroundColor: Theme.of(context).colorScheme.error,
                  ),
                ),
            ],
          ),
          if (widget.info case final info?) ...[
            const SizedBox(height: 14),
            _danbooruSection(l10n, semantic, info),
          ],
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
              style: TextStyle(
                fontSize: AppText.micro,
                color: semantic.muted,
              ),
            ),
          ],
        ],
      ),
    );
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

/// Asks for a tag name or a pasted danbooru URL. Pops the raw text — parsing
/// it is [DanbooruApi.parseQuery]'s job, and it is the only thing that knows
/// which URL shapes are understood.
class _LookupPromptDialog extends StatefulWidget {
  const _LookupPromptDialog({required this.initial});

  final String initial;

  @override
  State<_LookupPromptDialog> createState() => _LookupPromptDialogState();
}

class _LookupPromptDialogState extends State<_LookupPromptDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    if (value.isEmpty) return;
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(l10n.dictFetchPromptTitle),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              style: const TextStyle(fontSize: AppText.secondary),
              decoration: InputDecoration(
                labelText: l10n.dictFetchPromptLabel,
                hintText: l10n.dictFetchPromptHint,
                isDense: true,
              ),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 10),
            Text(
              l10n.dictFetchPromptNote,
              style: TextStyle(
                fontSize: AppText.micro,
                color: context.semantic.muted,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        TextButton(onPressed: _submit, child: Text(l10n.confirm)),
      ],
    );
  }
}

/// Name + category for a tag danbooru does not have.
class _AddTagDialog extends StatefulWidget {
  const _AddTagDialog();

  @override
  State<_AddTagDialog> createState() => _AddTagDialogState();
}

class _AddTagDialogState extends State<_AddTagDialog> {
  final _controller = TextEditingController();
  TagCategory _category = TagCategory.general;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    Navigator.of(context).pop(
      TagDictionaryEntry(name: danbooruTagName(name), category: _category),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(l10n.dictAddTagTitle),
      content: SizedBox(
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              style: const TextStyle(fontSize: AppText.secondary),
              decoration: InputDecoration(
                labelText: l10n.dictAddTagNameLabel,
                hintText: l10n.dictAddTagNameHint,
                isDense: true,
              ),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<TagCategory>(
              initialValue: _category,
              decoration: InputDecoration(
                labelText: l10n.dictAddTagCategoryLabel,
                isDense: true,
              ),
              style: const TextStyle(fontSize: AppText.secondary),
              items: [
                for (final category in TagCategory.values)
                  DropdownMenuItem(
                    value: category,
                    child: Text(_categoryLabel(l10n, category)),
                  ),
              ],
              onChanged: (value) =>
                  setState(() => _category = value ?? TagCategory.general),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        TextButton(onPressed: _submit, child: Text(l10n.confirm)),
      ],
    );
  }
}

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
