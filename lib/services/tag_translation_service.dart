import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/tag_translation.dart';
import '../utils/tag_text.dart';

/// Per-language tag translations, stored beside the dictionary but entirely
/// independent of it.
///
/// One file per language — `<app-support>/tags/translations/<code>.json` — so
/// switching the app language switches the whole glossary, and a language the
/// user has never translated simply renders no glosses instead of falling back
/// to somebody else's. The dictionary CSV is never touched: it is downloaded
/// and replaced wholesale, and any edit written into it would be lost on the
/// next refresh.
///
/// Keys are danbooru's own spelling; the in-memory index folds them through
/// [tagLookupKey], so a caption written `long hair` finds the translation
/// stored for `long_hair`.
class TagTranslationService extends ChangeNotifier {
  TagTranslationService({Future<Directory> Function()? storageDirectory})
    : _storageDirectory = storageDirectory ?? _defaultDirectory;

  /// Bumped only on a breaking layout change. A file from a *newer* schema is
  /// refused by [_parse] and freezes the service, so downgrading the app cannot
  /// destroy translations it does not understand.
  static const schemaVersion = 1;

  static Future<Directory> _defaultDirectory() async {
    final support = await getApplicationSupportDirectory();
    return Directory(p.join(support.path, 'tags', 'translations'));
  }

  final Future<Directory> Function() _storageDirectory;

  /// Language code of the loaded glossary; empty before the first [load].
  String _languageCode = '';
  String get languageCode => _languageCode;

  /// Canonical tag -> translation, in insertion order of the file.
  final Map<String, TagTranslation> _byTag = {};

  /// [tagLookupKey] -> the same entries, which is what lookups go through.
  final Map<String, TagTranslation> _byKey = {};

  /// Bumped on every load and every mutation.
  ///
  /// Needed because the glossary mutates in place: neither identity nor
  /// [count] moves when an existing translation's *text* is edited, so
  /// listeners that cache by either would keep painting the old gloss.
  int _revision = 0;
  int get revision => _revision;

  /// Why the active glossary could not be read or written, for the manager to
  /// show. Null once a load or a write succeeds.
  String? _lastError;
  String? get lastError => _lastError;

  /// Set when [load] refused the file because a newer build wrote it.
  ///
  /// Refusing to *read* such a file is only half the protection: the other half
  /// is never writing over it, so while this is set every mutation is a no-op.
  /// A merely corrupt file does not set it — there the user has nothing left to
  /// lose, and locking them out of re-importing would be the worse failure.
  bool _frozen = false;

  /// Number of translated tags in the active language.
  int get count => _byTag.length;

  bool get isEmpty => _byTag.isEmpty;

  /// [entries]'s sorted view, and the revision it was built for. The manager
  /// asks for it once per row-pass — on every keystroke — so sorting a glossary
  /// of thousands per frame is worth avoiding.
  List<TagTranslation>? _sorted;
  int _sortedAt = -1;

  /// Every entry, sorted by tag name — the order the manager lists them in.
  List<TagTranslation> get entries {
    if (_sorted case final cached? when _sortedAt == _revision) return cached;
    _sortedAt = _revision;
    return _sorted = List.unmodifiable(
      _byTag.values.toList()..sort((a, b) => a.tag.compareTo(b.tag)),
    );
  }

  /// How many entries came from [source]; drives the "clear AI translations"
  /// affordance.
  int countBySource(TagTranslationSource source) =>
      _byTag.values.where((e) => e.source == source).length;

  Future<File> _file(String languageCode) async {
    final dir = await _storageDirectory();
    return File(p.join(dir.path, '$languageCode.json'));
  }

  /// Loads the glossary for [languageCode], replacing whatever was loaded.
  ///
  /// A missing file is the normal case (nothing translated yet) and leaves the
  /// service empty without an error. A corrupt file is reported but still
  /// leaves the service usable — losing glosses must never block the app, and
  /// the manager surfaces [lastError] so the user can fix or re-import. A file
  /// from a newer [schemaVersion] is reported the same way but also freezes
  /// writes, so this build cannot overwrite what it could not read.
  Future<void> load(String languageCode) async {
    _languageCode = languageCode;
    _byTag.clear();
    _byKey.clear();
    _frozen = false;
    _revision++;
    // Notified after the clear and the revision bump, so glosses from the
    // previous language stop being painted at once instead of lingering until
    // the new file lands.
    notifyListeners();
    try {
      final file = await _file(languageCode);
      if (await file.exists()) {
        for (final entry in _parse(await file.readAsString())) {
          _byTag[entry.tag] = entry;
          _byKey[tagLookupKey(entry.tag)] = entry;
        }
      }
      _lastError = null;
    } catch (e) {
      _lastError = e.toString();
      _frozen = e is _FutureSchemaException;
    } finally {
      notifyListeners();
    }
  }

  /// The translation for [tag] written in any caption style, or null.
  TagTranslation? lookup(String tag) => _byKey[tagLookupKey(tag)];

  /// Just the display text for [tag] — what the chips and suggestion rows ask
  /// for. Null when the tag has no translation in the active language.
  String? glossFor(String tag) => lookup(tag)?.text;

  /// Whether any translation exists for [tag].
  bool has(String tag) => _byKey.containsKey(tagLookupKey(tag));

  // --- Mutation ---------------------------------------------------------

  /// Writes [items] into the glossary and persists it.
  ///
  /// Strictly an upsert: entries not mentioned are left alone. There is
  /// deliberately no "replace the file" entry point, because the one thing a
  /// bulk producer must never be able to do is drop translations it did not
  /// know about.
  ///
  /// With [overwrite] false an existing entry is kept and counted as skipped —
  /// the default for machine-produced batches, so a run cannot clobber
  /// hand-written text.
  ///
  /// Returns `(written, skipped)`.
  Future<(int, int)> upsertAll(
    Iterable<TagTranslation> items, {
    bool overwrite = true,
  }) async {
    // Everything is skipped rather than half-applied: a frozen glossary must
    // not diverge from the file on disk that it refused to read.
    if (_frozen) return (0, items.length);
    final (written, skipped) = _mergeInto(
      _byTag,
      _byKey,
      items,
      overwrite: overwrite,
    );
    if (written > 0) await _persist();
    return (written, skipped);
  }

  /// Merges [items] into a `(canonical tag -> entry, lookup key -> entry)`
  /// pair, returning `(written, skipped)`.
  ///
  /// Shared by the active glossary and by [upsertAllFor]'s off-line path, so a
  /// language the user is not currently viewing is normalized by exactly the
  /// same rules as the one they are.
  static (int, int) _mergeInto(
    Map<String, TagTranslation> byTag,
    Map<String, TagTranslation> byKey,
    Iterable<TagTranslation> items, {
    required bool overwrite,
  }) {
    var written = 0;
    var skipped = 0;
    for (final item in items) {
      final tag = danbooruTagName(item.tag);
      final text = item.text.trim();
      if (tag.isEmpty || text.isEmpty) {
        skipped++;
        continue;
      }
      final key = tagLookupKey(tag);
      if (!overwrite && byKey.containsKey(key)) {
        skipped++;
        continue;
      }
      // Stored under the incoming canonical spelling, and any previous entry
      // that folds to the same key is dropped — otherwise `long hair` and
      // `long_hair` would both sit in the file, fighting over one lookup.
      final previous = byKey[key];
      if (previous != null && previous.tag != tag) byTag.remove(previous.tag);
      final entry = item.copyWith(tag: tag, text: text);
      byTag[tag] = entry;
      byKey[key] = entry;
      written++;
    }
    return (written, skipped);
  }

  /// Convenience single-entry upsert used by the manager's editor.
  Future<void> upsert(TagTranslation item) => upsertAll([item]);

  /// Deletes the translations for [tags]. Returns how many were removed.
  Future<int> remove(Iterable<String> tags) async {
    if (_frozen) return 0;
    var removed = 0;
    for (final tag in tags) {
      final entry = _byKey.remove(tagLookupKey(tag));
      if (entry == null) continue;
      _byTag.remove(entry.tag);
      removed++;
    }
    if (removed > 0) await _persist();
    return removed;
  }

  /// Deletes every entry produced by [source] — the undo for a bulk run that
  /// went wrong. Returns how many were removed.
  Future<int> clearBySource(TagTranslationSource source) async {
    final doomed = [
      for (final entry in _byTag.values)
        if (entry.source == source) entry.tag,
    ];
    return remove(doomed);
  }

  // --- Import / export --------------------------------------------------

  /// The active glossary as pretty JSON, for saving next to a dataset or
  /// sharing. Same layout the service reads, so an export round-trips.
  String exportJson() => _encode();

  /// Merges an exported or hand-written glossary into the active language.
  ///
  /// Accepts both this service's own layout and a bare `{"tag": "译文"}` map,
  /// which is what a human writes by hand. Returns `(written, skipped)`;
  /// throws [FormatException] on text that is not a JSON object at all, so the
  /// caller can tell "wrong file" from "nothing new in it".
  Future<(int, int)> importJson(String text, {bool overwrite = true}) async {
    final incoming = _parse(text);
    return upsertAll(incoming, overwrite: overwrite);
  }

  List<TagTranslation> _parse(String text) {
    final decoded = jsonDecode(text);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('translation file must be a JSON object');
    }
    // A file a newer build wrote may hold fields this one would drop on the
    // next save, so it is refused outright rather than read as far as it parses.
    if (decoded['schema'] case final num schema when schema > schemaVersion) {
      throw _FutureSchemaException(schema.toInt());
    }
    // Either wrapped (`{"schema":1,"entries":{...}}`) or the bare map a human
    // would write. Anything else and there is nothing to read.
    final raw = decoded['entries'] ?? decoded;
    if (raw is! Map) {
      throw const FormatException('"entries" must be a JSON object');
    }
    return [
      for (final entry in raw.entries)
        ?TagTranslation.fromJson('${entry.key}', entry.value),
    ];
  }

  String _encode() => _encodeEntries(_languageCode, entries);

  static String _encodeEntries(
    String languageCode,
    Iterable<TagTranslation> entries,
  ) {
    final sorted = entries.toList()..sort((a, b) => a.tag.compareTo(b.tag));
    return '${const JsonEncoder.withIndent('  ').convert({
      'schema': schemaVersion,
      'locale': languageCode,
      'entries': {for (final e in sorted) e.tag: e.toJson()},
    })}\n';
  }

  Future<void> _persist() async {
    // Notified before the write, not after: the glosses are already live in
    // memory and the UI should not wait on a disk round-trip to show them.
    _revision++;
    notifyListeners();
    try {
      await _write(await _file(_languageCode), _encode());
      _lastError = null;
    } catch (e) {
      _lastError = e.toString();
      notifyListeners();
    }
  }

  /// Write-then-rename: a half-written glossary that still parses is worse
  /// than no glossary, because the missing half looks like untranslated tags
  /// and invites a second bulk run over them.
  static Future<void> _write(File file, String text) async {
    await file.parent.create(recursive: true);
    final temp = File('${file.path}.part');
    await temp.writeAsString(text);
    await temp.rename(file.path);
  }

  // --- Every language, not just the active one --------------------------
  //
  // The app language is a display choice, so a backup that carried only the
  // glossary the user happened to be looking at would lose the rest without
  // saying so. These three are what the data exporter walks.

  /// Language codes with a glossary file on disk, sorted. The active language
  /// is included even when nothing has been written for it yet only if its
  /// file exists — an empty glossary has nothing to back up.
  Future<List<String>> storedLanguages() async {
    try {
      final dir = await _storageDirectory();
      if (!await dir.exists()) return const [];
      final codes = <String>[];
      await for (final entity in dir.list()) {
        if (entity is! File) continue;
        final name = p.basename(entity.path);
        if (!name.endsWith('.json')) continue;
        final code = name.substring(0, name.length - '.json'.length);
        if (code.isNotEmpty) codes.add(code);
      }
      return codes..sort();
    } catch (e) {
      _lastError = e.toString();
      return const [];
    }
  }

  /// The glossary stored for [languageCode]. The active language answers from
  /// memory, which is also the only copy that is guaranteed current — unsaved
  /// state does not exist, but a pending write might.
  ///
  /// Returns empty for a language with no file. Throws [FormatException] on a
  /// file this build cannot read, so a backup never silently omits it.
  Future<List<TagTranslation>> entriesFor(String languageCode) async {
    if (languageCode == _languageCode) return entries;
    final file = await _file(languageCode);
    if (!await file.exists()) return const [];
    return _parse(await file.readAsString());
  }

  /// [upsertAll] for a language that may not be the active one.
  ///
  /// The active language goes through the in-memory path so the glosses on
  /// screen update with it; any other language is read, merged and written
  /// straight back. Returns `(written, skipped)`.
  Future<(int, int)> upsertAllFor(
    String languageCode,
    Iterable<TagTranslation> items, {
    bool overwrite = true,
  }) async {
    if (languageCode == _languageCode) {
      return upsertAll(items, overwrite: overwrite);
    }
    final byTag = <String, TagTranslation>{};
    final byKey = <String, TagTranslation>{};
    final file = await _file(languageCode);
    // A file this build cannot read is left strictly alone — the same rule the
    // active glossary's freeze enforces, applied one language at a time.
    if (await file.exists()) {
      for (final entry in _parse(await file.readAsString())) {
        byTag[entry.tag] = entry;
        byKey[tagLookupKey(entry.tag)] = entry;
      }
    }
    final result = _mergeInto(byTag, byKey, items, overwrite: overwrite);
    if (result.$1 > 0) {
      await _write(file, _encodeEntries(languageCode, byTag.values));
    }
    return result;
  }
}

/// A glossary this build does not understand, as opposed to one that is merely
/// broken — the difference decides whether the service stays writable. A
/// [FormatException] so that [TagTranslationService.importJson]'s contract
/// still covers it.
class _FutureSchemaException extends FormatException {
  _FutureSchemaException(int schema)
    : super(
        'translation file uses schema $schema, newer than this app understands '
        '(${TagTranslationService.schemaVersion}); left untouched',
      );
}
