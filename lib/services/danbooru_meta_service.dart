import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../utils/tag_text.dart';
import 'danbooru_api.dart';

/// What danbooru said about each tag the user has ever looked up, persisted.
///
/// The dictionary CSV is replaced wholesale on refresh and the glossary is
/// per-language, so neither can hold this; a third small file can. It exists
/// for two reasons:
///
///  * a fetched wiki excerpt and `other_names` keep rendering on the tag's
///    editor across sessions, instead of evaporating with the dialog;
///  * a tag danbooru has *never heard of* is recorded as exactly that, which
///    is what lets a batch run skip it forever instead of asking danbooru the
///    same hopeless question on every pass. A manual fetch ignores the mark —
///    that is the escape hatch when the tag has since been created.
///
/// One file, language-independent: `<app-support>/tags/danbooru_meta.json`.
/// Keys are stored in danbooru's own spelling and looked up through
/// [tagLookupKey], the same fold every other tag store uses.
class DanbooruMetaService extends ChangeNotifier {
  DanbooruMetaService({Future<Directory> Function()? storageDirectory})
    : _storageDirectory = storageDirectory ?? _defaultDirectory;

  /// Bumped only on a breaking layout change. A file from a newer schema
  /// freezes writes, so downgrading the app cannot destroy records it does
  /// not understand.
  static const schemaVersion = 1;

  static const _fileName = 'danbooru_meta.json';

  static Future<Directory> _defaultDirectory() async {
    final support = await getApplicationSupportDirectory();
    return Directory(p.join(support.path, 'tags'));
  }

  final Future<Directory> Function() _storageDirectory;

  /// Stored tag spelling -> what danbooru answered.
  final Map<String, DanbooruTagInfo> _byTag = {};

  /// [tagLookupKey] -> the same records, which is what lookups go through.
  final Map<String, DanbooruTagInfo> _byKey = {};

  /// When each stored tag was fetched, ISO-8601. Carried so a future "refresh
  /// stale entries" has something to decide by; nothing reads it yet.
  final Map<String, String> _fetchedAt = {};

  String? _lastError;
  String? get lastError => _lastError;

  /// Set when [init] refused the file because a newer build wrote it; every
  /// mutation is then a no-op, mirroring the glossary's own freeze.
  bool _frozen = false;

  /// Number of tags with any record — found or marked missing alike.
  int get count => _byTag.length;

  Future<File> _file() async =>
      File(p.join((await _storageDirectory()).path, _fileName));

  /// Loads the store. A missing file is the normal cold start; a corrupt file
  /// is reported but leaves the service usable — these records can all be
  /// re-fetched, so locking the user out would be the worse failure.
  Future<void> init() async {
    try {
      final file = await _file();
      if (!await file.exists()) return;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('danbooru meta file must be a JSON object');
      }
      if (decoded['schema'] case final num schema when schema > schemaVersion) {
        _frozen = true;
        throw FormatException(
          'danbooru meta file uses schema $schema, newer than this app '
          'understands ($schemaVersion); left untouched',
        );
      }
      final raw = decoded['entries'];
      if (raw is! Map) return;
      for (final entry in raw.entries) {
        final info = DanbooruTagInfo.fromJson('${entry.key}', entry.value);
        if (info == null) continue;
        _byTag[info.name] = info;
        _byKey[tagLookupKey(info.name)] = info;
        if (entry.value case {'fetchedAt': final String at}) {
          _fetchedAt[info.name] = at;
        }
      }
      _lastError = null;
    } catch (e) {
      _lastError = e.toString();
    } finally {
      notifyListeners();
    }
  }

  /// What danbooru said about [tag], in any caption style, or null when it has
  /// never been asked.
  DanbooruTagInfo? lookup(String tag) => _byKey[tagLookupKey(tag)];

  /// Whether [tag] has any record at all — the "no need to ask again" test a
  /// batch run filters on.
  bool has(String tag) => _byKey.containsKey(tagLookupKey(tag));

  /// Whether [tag] is recorded as absent from danbooru.
  bool isMissing(String tag) => lookup(tag)?.knownToDanbooru == false;

  /// Records what a fetch came back with and persists it.
  ///
  /// Stored under the info's own canonical name, and additionally under
  /// [queriedAs] when danbooru resolved the query to a different spelling —
  /// otherwise a dataset tag that is merely an alias would be re-fetched on
  /// every batch pass, never matching the canonical record it produced.
  Future<void> record(DanbooruTagInfo info, {String? queriedAs}) async {
    if (_frozen) return;
    final stamp = DateTime.now().toUtc().toIso8601String();
    _store(info.name, info, stamp);
    final queried = queriedAs == null ? '' : danbooruTagName(queriedAs);
    if (queried.isNotEmpty && tagLookupKey(queried) != tagLookupKey(info.name)) {
      _store(queried, info, stamp);
    }
    notifyListeners();
    await _persist();
  }

  /// The stored records in the file's own `entries` layout — what the data
  /// exporter writes into a backup. Same shape [importEntries] reads, so a
  /// backup round-trips, `fetchedAt` stamps included.
  Map<String, Object?> exportEntries() {
    final sorted = _byTag.keys.toList()..sort();
    return {
      for (final tag in sorted)
        tag: {..._byTag[tag]!.toJson(), 'fetchedAt': ?_fetchedAt[tag]},
    };
  }

  /// Merges records from a backup and persists the result. A record already
  /// here wins unless [overwrite] — the same bargain every other import in the
  /// app makes. Returns how many records were written.
  Future<int> importEntries(
    Map<String, Object?> raw, {
    bool overwrite = false,
  }) async {
    if (_frozen) return 0;
    var written = 0;
    for (final entry in raw.entries) {
      final info = DanbooruTagInfo.fromJson(entry.key, entry.value);
      if (info == null) continue;
      if (!overwrite && _byKey.containsKey(tagLookupKey(info.name))) continue;
      _store(info.name, info, switch (entry.value) {
        {'fetchedAt': final String at} => at,
        _ => DateTime.now().toUtc().toIso8601String(),
      });
      written++;
    }
    if (written > 0) {
      notifyListeners();
      await _persist();
    }
    return written;
  }

  void _store(String tag, DanbooruTagInfo info, String stamp) {
    // One record per lookup key: a previous entry under another spelling of
    // the same tag would otherwise fight this one over every lookup.
    final previous = _byKey[tagLookupKey(tag)];
    if (previous != null && previous.name != tag) {
      _byTag.remove(previous.name);
      _fetchedAt.remove(previous.name);
    }
    _byTag[tag] = info;
    _byKey[tagLookupKey(tag)] = info;
    _fetchedAt[tag] = stamp;
  }

  /// Drops the "not on danbooru" marks so a batch run asks about those tags
  /// again. Returns how many were dropped.
  Future<int> clearMissing() async {
    if (_frozen) return 0;
    final doomed = [
      for (final entry in _byTag.entries)
        if (!entry.value.knownToDanbooru) entry.key,
    ];
    for (final tag in doomed) {
      _byKey.remove(tagLookupKey(tag));
      _byTag.remove(tag);
      _fetchedAt.remove(tag);
    }
    if (doomed.isNotEmpty) {
      notifyListeners();
      await _persist();
    }
    return doomed.length;
  }

  Future<void> _persist() async {
    try {
      final file = await _file();
      await file.parent.create(recursive: true);
      final text =
          '${const JsonEncoder.withIndent('  ').convert({
            'schema': schemaVersion,
            'entries': exportEntries(),
          })}\n';
      // Write-then-rename, like every other tag store: a half-written file
      // that still parses would silently lose the other half of the records.
      final temp = File('${file.path}.part');
      await temp.writeAsString(text);
      await temp.rename(file.path);
      _lastError = null;
    } catch (e) {
      _lastError = e.toString();
      notifyListeners();
    }
  }
}
