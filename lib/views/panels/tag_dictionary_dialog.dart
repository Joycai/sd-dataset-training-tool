import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../l10n/app_localizations.dart';
import '../../models/tag_dictionary.dart';
import '../../models/tag_translation.dart';
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
Future<void> showTagDictionaryDialog(
  BuildContext context, {
  String? initialTag,
}) => showDialog(
  context: context,
  builder: (_) => ChangeNotifierProvider.value(
    value: context.read<AppState>(),
    child: _TagDictionaryDialog(initialTag: initialTag),
  ),
);

/// How many dictionary hits the search lists. Well past what fits on screen —
/// the list scrolls — but bounded, because a two-letter query matches
/// thousands and every row builds a translation lookup.
const _searchLimit = 80;

class _TagDictionaryDialog extends StatefulWidget {
  const _TagDictionaryDialog({this.initialTag});

  final String? initialTag;

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

    // One pass over the (short) custom list per rebuild instead of a scan per
    // row: the glossary can hold thousands of entries.
    final customKeys = {
      for (final entry in dictionary.customEntries) tagLookupKey(entry.name),
    };
    // Deduplicates across the two sources below — the same tag can be both a
    // dictionary hit and a glossary hit, and it must occupy one row.
    final seen = <String>{};
    final rows = <_DictRow>[];

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
      for (final entry in glossary.entries) {
        if (!seen.add(tagLookupKey(entry.tag))) continue;
        final hit = dictionary.lookup(entry.tag);
        rows.add(
          _DictRow(
            tag: entry.tag,
            category: hit?.category,
            translation: entry,
            // Translated, but the dictionary has never heard of it — a tag
            // read out of a dataset, or one whose spelling has since changed.
            // Flagged rather than hidden: an unreachable translation is
            // exactly the kind of thing that needs finding. Only once the
            // dictionary is actually loaded, or a cold start would brand every
            // entry unknown.
            orphan: dictionary.isReady && hit == null,
          ),
        );
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
    // dictionary cannot answer, and the reason to keep one.
    final needle = query.toLowerCase();
    for (final entry in glossary.entries) {
      if (!entry.text.toLowerCase().contains(needle) &&
          !(entry.note?.toLowerCase().contains(needle) ?? false)) {
        continue;
      }
      if (!seen.add(tagLookupKey(entry.tag))) continue;
      final hit = dictionary.lookup(entry.tag);
      rows.add(
        _DictRow(
          tag: entry.tag,
          category: hit?.category,
          custom: customKeys.contains(tagLookupKey(entry.tag)),
          translation: entry,
          orphan: dictionary.isReady && hit == null,
        ),
      );
    }
    return rows;
  }

  bool _isCustom(String tag) {
    final key = tagLookupKey(tag);
    return _dictionary.customEntries.any((e) => tagLookupKey(e.name) == key);
  }

  Future<void> _saveTranslation(String tag, String text, String? note) async {
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
        // Anything edited here is the user's word on it, whoever drafted it.
        source: TagTranslationSource.manual,
      ),
    );
  }

  Future<void> _addCustomTag() async {
    final result = await showDialog<TagDictionaryEntry>(
      context: context,
      builder: (_) => const _AddTagDialog(),
    );
    if (result == null || !mounted) return;
    final l10n = AppLocalizations.of(context)!;
    final dictionary = _dictionary;
    if (dictionary.lookup(result.name) != null) {
      _snack(l10n.dictAddTagExists(danbooruTagName(result.name)));
      return;
    }
    await dictionary.setCustomEntries([
      ...dictionary.customEntries,
      TagDictionaryEntry(
        name: danbooruTagName(result.name),
        category: result.category,
        postCount: result.postCount,
      ),
    ]);
    if (!mounted) return;
    setState(() {
      _searchController.clear();
      _query = '';
      _selected = danbooruTagName(result.name);
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
                                  key: ValueKey(
                                    '$selected/'
                                    '${_glossary.lookup(selected)?.text}',
                                  ),
                                  tag: selected,
                                  entry: _glossary.lookup(selected),
                                  dictionaryEntry: _dictionary.lookup(selected),
                                  custom: _isCustom(selected),
                                  onSave: (text, note) =>
                                      _saveTranslation(selected, text, note),
                                  onRemoveCustom: () =>
                                      _removeCustomTag(selected),
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
            ],
          ),
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
    required this.onSave,
    required this.onRemoveCustom,
  });

  final String tag;
  final TagTranslation? entry;
  final TagDictionaryEntry? dictionaryEntry;
  final bool custom;
  final Future<void> Function(String text, String? note) onSave;
  final Future<void> Function() onRemoveCustom;

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

  @override
  void dispose() {
    _text.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await widget.onSave(_text.text, _note.text);
    if (mounted) setState(() => _dirty = false);
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
              if (!_dirty) setState(() => _dirty = true);
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
              // A hand-added tag has no danbooru page; offering the link would
              // just send the user to a 404.
              if (!widget.custom)
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
      TagDictionaryEntry(
        name: danbooruTagName(name),
        category: _category,
        postCount: 0,
      ),
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
