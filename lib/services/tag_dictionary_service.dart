import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/tag_dictionary.dart';
import '../utils/tag_text.dart';

/// Which dictionary is currently loaded.
enum TagDictionarySource {
  /// Nothing loaded yet, or loading failed.
  none,

  /// The bundled WD tagger label file.
  bundled,

  /// The downloaded full danbooru dictionary.
  full,
}

/// Tag name/alias lookup behind the caption editor's autocomplete.
///
/// Two sources, smallest first:
///
///  * `assets/tags/wd_tags.csv` — the WD tagger's own label file (~10.8k
///    tags). Ships with the app, works offline, and by construction it is
///    exactly the vocabulary the AI tagger can produce, so a hand-typed tag
///    and an AI-suggested one stay spelled the same.
///  * an optional full danbooru dictionary (~100k tags, *with aliases* and
///    artist/copyright/meta categories) downloaded on demand into
///    `<app-support>/tags/`. A superset, so it simply replaces the bundled one
///    once present.
///
/// Entries are stored in danbooru's own spelling; converting to the user's
/// caption style happens at insertion time, not here.
class TagDictionaryService extends ChangeNotifier {
  TagDictionaryService({
    http.Client Function()? clientFactory,
    Future<Directory> Function()? storageDirectory,
  }) : _clientFactory = clientFactory ?? http.Client.new,
       _storageDirectory = storageDirectory ?? _defaultDirectory;

  static Future<Directory> _defaultDirectory() async {
    final support = await getApplicationSupportDirectory();
    return Directory(p.join(support.path, 'tags'));
  }

  static const bundledAsset = 'assets/tags/wd_tags.csv';

  /// Top 100k danbooru tags with aliases, from the (MIT-licensed) tagcomplete
  /// project. Tried in order: upstream first, then the same gh-proxy mirror
  /// the font downloader falls back to.
  static const fullDictionaryUrls = [
    'https://raw.githubusercontent.com/DominikDoom/'
        'a1111-sd-webui-tagcomplete/main/tags/danbooru.csv',
    'https://ghfast.top/https://raw.githubusercontent.com/DominikDoom/'
        'a1111-sd-webui-tagcomplete/main/tags/danbooru.csv',
  ];

  static const _fullFileName = 'danbooru.csv';

  /// User-added tags, kept in their own file rather than merged into the
  /// downloaded CSV: that file is replaced wholesale on every refresh, so an
  /// edit written into it would silently disappear.
  static const _customFileName = 'custom_tags.json';

  final http.Client Function() _clientFactory;
  final Future<Directory> Function() _storageDirectory;

  _TagIndex? _index;
  TagDictionarySource _source = TagDictionarySource.none;
  bool _busy = false;
  double? _progress;
  String? _lastError;

  TagDictionarySource get source => _source;

  /// Number of tags available for completion; 0 before the first load.
  int get entryCount => _index?.entries.length ?? 0;

  bool get isReady => _index != null;

  /// True while a load or download is in flight.
  bool get busy => _busy;

  /// Download progress 0-1, or null when not downloading / size unknown.
  double? get progress => _progress;

  String? get lastError => _lastError;

  /// Whether the full dictionary has already been downloaded. Cached from
  /// [init] so the settings row can render without touching the disk.
  bool _fullOnDisk = false;
  bool get hasFullDictionary => _fullOnDisk;

  Future<File> _fullFile() => _supportFile(_fullFileName);

  Future<File> _supportFile(String name) async =>
      File(p.join((await _storageDirectory()).path, name));

  /// Loads the best dictionary available on this machine. Safe to call on a
  /// cold start: a missing or corrupt download silently falls back to the
  /// bundled file, because losing autocomplete is not worth blocking startup.
  Future<void> init() async {
    // Before the dictionary, so the first index build already knows which keys
    // the user's own entries cover.
    await _loadCustomEntries();
    try {
      final file = await _fullFile();
      if (await file.exists()) {
        _fullOnDisk = true;
        await _loadFrom(
          await file.readAsString(),
          _CsvFormat.tagcomplete,
          TagDictionarySource.full,
        );
        return;
      }
    } catch (e) {
      _lastError = e.toString();
    }
    await loadBundled();
  }

  /// Parses the bundled WD label file into the index.
  Future<void> loadBundled() async {
    try {
      final csv = await rootBundle.loadString(bundledAsset);
      await _loadFrom(csv, _CsvFormat.wdLabels, TagDictionarySource.bundled);
    } catch (e) {
      _lastError = e.toString();
      notifyListeners();
    }
  }

  /// Builds the index straight from CSV text, bypassing the asset bundle and
  /// the network. [full] selects the tagcomplete column layout (with the
  /// alias column) over the WD label layout.
  @visibleForTesting
  Future<void> loadCsv(String csv, {bool full = false}) => _loadFrom(
    csv,
    full ? _CsvFormat.tagcomplete : _CsvFormat.wdLabels,
    full ? TagDictionarySource.full : TagDictionarySource.bundled,
  );

  Future<void> _loadFrom(
    String csv,
    _CsvFormat format,
    TagDictionarySource source,
  ) async {
    _busy = true;
    notifyListeners();
    try {
      // Off the main isolate: the full dictionary is ~100k rows and building
      // the token index for it janks several frames if done inline.
      _index = await compute(_buildIndex, _ParseRequest(csv, format));
      // The local index is defined by what the dictionary does *not* cover,
      // so a new dictionary invalidates it.
      _localIndex = null;
      _source = source;
      _lastError = null;
    } catch (e) {
      _lastError = e.toString();
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Downloads the full dictionary and switches to it. Throws on failure;
  /// the previously loaded dictionary stays active in that case.
  Future<void> downloadFullDictionary() async {
    if (_busy) return;
    _busy = true;
    _progress = null;
    _lastError = null;
    notifyListeners();

    final target = await _fullFile();
    await target.parent.create(recursive: true);
    // Download beside the real file and rename on success, so an interrupted
    // download can never be mistaken for a dictionary on the next start.
    final temp = File('${target.path}.part');
    try {
      Object? lastError;
      var body = '';
      for (final url in fullDictionaryUrls) {
        try {
          body = await _download(url, temp);
          lastError = null;
          break;
        } catch (e) {
          lastError = e;
        }
      }
      if (lastError != null) throw lastError;

      await temp.rename(target.path);
      _fullOnDisk = true;
      _busy = false; // _loadFrom drives the flag from here on
      await _loadFrom(body, _CsvFormat.tagcomplete, TagDictionarySource.full);
    } catch (e) {
      _lastError = e.toString();
      _busy = false;
      notifyListeners();
      rethrow;
    } finally {
      _progress = null;
      try {
        if (await temp.exists()) await temp.delete();
      } catch (_) {}
    }
  }

  /// Deletes the downloaded dictionary and falls back to the bundled one.
  Future<void> removeFullDictionary() async {
    try {
      final file = await _fullFile();
      if (await file.exists()) await file.delete();
    } catch (e) {
      _lastError = e.toString();
    }
    _fullOnDisk = false;
    await loadBundled();
  }

  Future<String> _download(String url, File target) async {
    final client = _clientFactory();
    try {
      final response = await client.send(http.Request('GET', Uri.parse(url)));
      if (response.statusCode != 200) {
        throw HttpException('HTTP ${response.statusCode}', uri: Uri.parse(url));
      }
      final total = response.contentLength ?? 0;
      var received = 0;
      var lastNotified = 0;
      final chunks = <List<int>>[];
      final sink = target.openWrite();
      try {
        await for (final chunk in response.stream) {
          sink.add(chunk);
          chunks.add(chunk);
          received += chunk.length;
          if (total > 0) _progress = (received / total).clamp(0.0, 1.0);
          // Every 256 KB, matching the font downloader: per-chunk notifies
          // rebuild the progress dialog far more often than it can paint.
          if (received - lastNotified >= 256 * 1024) {
            lastNotified = received;
            notifyListeners();
          }
        }
      } finally {
        await sink.close();
      }
      notifyListeners();
      // Decoded here rather than re-read from disk: the bytes are already in
      // memory and the caller parses them immediately.
      return const Utf8Decoder(
        allowMalformed: true,
      ).convert(chunks.expand((c) => c).toList());
    } finally {
      client.close();
    }
  }

  // --- User-added dictionary entries -----------------------------------

  List<TagDictionaryEntry> _customEntries = const [];
  _TagIndex? _customIndex;

  /// Tags the user added to the dictionary by hand, in the order they were
  /// added. Unlike the local vocabulary these are not derived from anything —
  /// they persist across datasets and carry a category of their own.
  List<TagDictionaryEntry> get customEntries => _customEntries;

  Future<void> _loadCustomEntries() async {
    try {
      final file = await _supportFile(_customFileName);
      if (!await file.exists()) return;
      final decoded = jsonDecode(await file.readAsString());
      final raw = decoded is Map ? decoded['entries'] : decoded;
      if (raw is! List) return;
      _customEntries = [for (final e in raw) ?TagDictionaryEntry.fromJson(e)];
      _customIndex = null;
      _localIndex = null;
    } catch (e) {
      // A broken overlay must not cost the user their dictionary.
      _lastError = e.toString();
    }
  }

  /// Replaces the user's dictionary additions and persists them.
  ///
  /// Entries whose name the dictionary already covers are dropped: the point
  /// of this list is vocabulary danbooru does not have, and keeping a shadow
  /// copy of a real tag would give it two rows in every suggestion list.
  Future<void> setCustomEntries(List<TagDictionaryEntry> entries) async {
    final dictionary = _index;
    final seen = <String>{};
    _customEntries = [
      for (final entry in entries)
        if (entry.name.trim().isNotEmpty &&
            seen.add(tagLookupKey(entry.name)) &&
            (dictionary == null ||
                !dictionary.byKey.containsKey(tagLookupKey(entry.name))))
          entry,
    ];
    _customIndex = null;
    // "Local" means "covered by neither the dictionary nor this list".
    _localIndex = null;
    notifyListeners();
    try {
      final file = await _supportFile(_customFileName);
      await file.parent.create(recursive: true);
      await file.writeAsString(
        '${const JsonEncoder.withIndent('  ').convert({
          'entries': [for (final e in _customEntries) e.toJson()],
        })}\n',
      );
      _lastError = null;
    } catch (e) {
      _lastError = e.toString();
      notifyListeners();
    }
  }

  _TagIndex? get _customIndexOrBuild {
    if (_customIndex != null) return _customIndex;
    if (_customEntries.isEmpty) return null;
    final sorted = [..._customEntries]
      ..sort((a, b) => b.postCount.compareTo(a.postCount));
    return _customIndex = _indexTagEntries(sorted);
  }

  // --- The user's own vocabulary ---------------------------------------

  /// How many images a dataset tag has to appear on before it is offered as a
  /// completion.
  ///
  /// The dataset's tags are taken verbatim, and a typo is as much a tag as
  /// anything else — without a floor, every slip the user has ever made comes
  /// back as a suggestion and gets re-entered. A tag that survived onto five
  /// images was meant.
  ///
  /// Tag-library entries bypass this: putting a tag in the library is a
  /// deliberate act, which is the very signal this threshold is estimating.
  static const minDatasetUsage = 5;

  /// The vocabulary this user actually writes.
  ///
  /// [datasetUsage] maps each tag in the open dataset to the number of images
  /// carrying it; [libraryTags] is the curated tag library. Only the ones
  /// danbooru has never heard of become suggestions — trigger words, private
  /// character names, project conventions. Anything the dictionary already
  /// covers is dropped so it cannot occupy two rows.
  ///
  /// Both derived views are rebuilt lazily: this is called after every caption
  /// save, and most saves are never followed by a keystroke in a tag field.
  void setLocalTags({
    Map<String, int> datasetUsage = const {},
    Iterable<String> libraryTags = const [],
  }) {
    _datasetUsage = datasetUsage;
    _libraryTags = libraryTags;
    _usageByKey = null;
    _localIndex = null;
    notifyListeners();
  }

  Map<String, int> _datasetUsage = const {};
  Iterable<String> _libraryTags = const [];
  Map<String, int>? _usageByKey;
  _TagIndex? _localIndex;

  /// How many dataset images carry [tag], or null when the open dataset does
  /// not use it at all.
  ///
  /// Deliberately answers from the *unfiltered* usage, unlike the suggestion
  /// list: the tag lookup menu exists to tell a trigger word apart from a
  /// typo, and the tags below [minDatasetUsage] are exactly the ones that
  /// question is about.
  int? localUsage(String tag) {
    final byKey = _usageByKey ??= {
      for (final entry in _datasetUsage.entries)
        tagLookupKey(entry.key): entry.value,
    };
    return byKey[tagLookupKey(tag)];
  }

  _TagIndex? get _localIndexOrBuild {
    if (_localIndex != null) return _localIndex;
    if (_datasetUsage.isEmpty && _libraryTags.isEmpty) return null;
    final dictionary = _index;

    // Library tags first and unconditionally; a dataset count then upgrades
    // the weight from the library's "not on any image" zero.
    final weights = <String, int>{
      for (final tag in _libraryTags) tag: _datasetUsage[tag] ?? 0,
      for (final entry in _datasetUsage.entries)
        if (entry.value >= minDatasetUsage) entry.key: entry.value,
    };

    final custom = _customIndexOrBuild;
    final entries = <TagDictionaryEntry>[
      for (final entry in weights.entries)
        if (entry.key.trim().isNotEmpty &&
            (dictionary == null ||
                !dictionary.byKey.containsKey(tagLookupKey(entry.key))) &&
            (custom == null ||
                !custom.byKey.containsKey(tagLookupKey(entry.key))))
          TagDictionaryEntry(
            name: entry.key,
            category: TagCategory.general,
            postCount: entry.value,
          ),
    ]..sort((a, b) => b.postCount.compareTo(a.postCount));
    // Built inline, not in an isolate: a dataset's unknown tags number in the
    // hundreds, against a dictionary's hundred thousand.
    return _localIndex = _indexTagEntries(entries);
  }

  // --- Lookup ---------------------------------------------------------

  /// Every entry this dictionary can offer, popularity-descending within each
  /// source and the user's own additions first.
  ///
  /// For callers that need to *walk* the vocabulary rather than match against
  /// it — seeding a glossary from the busiest tags, for instance. The
  /// completion path never uses this: it asks [search] for matches.
  Iterable<TagDictionaryEntry> get allEntries => [
    ..._customEntries,
    ...?_index?.entries,
  ];

  /// The dictionary entry for [tag], written in any caption style, or null
  /// when the tag is known to neither danbooru nor the user's own additions.
  ///
  /// User additions are consulted first: [setCustomEntries] already refuses
  /// names the dictionary covers, so the two can only disagree when a
  /// dictionary download has since added the tag — and until the user prunes
  /// their list, the category they chose is the more specific answer.
  TagDictionaryEntry? lookup(String tag) {
    final key = tagLookupKey(tag);
    final custom = _customIndexOrBuild;
    if (custom != null) {
      final at = custom.byKey[key];
      if (at != null) return custom.entries[at];
    }
    final index = _index;
    if (index == null) return null;
    final at = index.byKey[key];
    return at == null ? null : index.entries[at];
  }

  /// Best matches for a partially typed tag, best-first.
  ///
  /// [query] may be written in any caption style — it is folded through
  /// [tagLookupKey] just like the index was.
  ///
  /// The user's own dictionary additions lead, then dictionary hits, but local
  /// tags are guaranteed a slice of the list: a project's own trigger word
  /// must not be pushed out by eight danbooru tags that merely share a prefix.
  List<TagSuggestion> search(String query, {int limit = 8}) {
    final key = tagLookupKey(query);
    if (key.isEmpty || limit <= 0) return const [];

    // Hand-added entries go first — adding one is a deliberate act, so it
    // outranks popularity — but never take more than half the list, or a
    // handful of them would hide danbooru entirely behind a shared prefix.
    final custom = _matches(
      _customIndexOrBuild,
      key,
      (limit / 2).ceil(),
      TagSuggestionOrigin.custom,
    );
    final room = limit - custom.length;
    final local = _matches(
      _localIndexOrBuild,
      key,
      room,
      TagSuggestionOrigin.local,
    );
    final reserved = local.isEmpty
        ? 0
        : (local.length < (room / 3).ceil() ? local.length : (room / 3).ceil());
    final customKeys = {for (final hit in custom) tagLookupKey(hit.name)};
    // Only bites when a dictionary download has since added a tag the user had
    // already entered by hand; the addition wins until they prune it.
    final dictionary =
        _matches(_index, key, room - reserved, TagSuggestionOrigin.dictionary)
            .where((hit) => !customKeys.contains(tagLookupKey(hit.name)))
            .toList();
    return [...custom, ...dictionary, ...local.take(room - dictionary.length)];
  }

  List<TagSuggestion> _matches(
    _TagIndex? index,
    String key,
    int limit,
    TagSuggestionOrigin origin,
  ) {
    if (index == null || limit <= 0) return const [];

    // Best hit per entry: one tag can match on its name and on two aliases,
    // and it must still occupy a single row.
    final best = <int, TagSuggestion>{};
    for (final token in index.bucket(key[0])) {
      final text = index.tokens[token];
      if (!text.startsWith(key)) continue;
      final entryAt = index.tokenEntry[token];
      final exact = text.length == key.length;
      final isAlias = index.tokenIsAlias[token] == 1;
      final kind = isAlias
          ? (exact ? TagMatchKind.exactAlias : TagMatchKind.aliasPrefix)
          : index.tokenIsWord[token] == 1
          ? TagMatchKind.nameWordPrefix
          : (exact ? TagMatchKind.exactName : TagMatchKind.namePrefix);
      final previous = best[entryAt];
      if (previous != null && previous.kind.index <= kind.index) continue;
      best[entryAt] = TagSuggestion(
        entry: index.entries[entryAt],
        kind: kind,
        origin: origin,
        matchedAlias: isAlias ? text : null,
      );
    }

    final hits = best.entries.toList()
      ..sort((a, b) {
        final byKind = a.value.kind.index.compareTo(b.value.kind.index);
        if (byKind != 0) return byKind;
        // Entries are stored count-descending, so the index doubles as the
        // popularity tie-break without re-reading the counts.
        return a.key.compareTo(b.key);
      });
    return [for (final hit in hits.take(limit)) hit.value];
  }
}

/// Which column layout a CSV uses.
enum _CsvFormat {
  /// `tag_id,name,category,count`, with a header row (WD label file).
  wdLabels,

  /// `name,category,count,"alias,alias"`, no header (tagcomplete).
  tagcomplete,
}

class _ParseRequest {
  const _ParseRequest(this.csv, this.format);

  final String csv;
  final _CsvFormat format;
}

/// The searchable form of a dictionary: entries plus a flat token table.
///
/// Every name, every word inside a name and every alias becomes one token, so
/// a query is a `startsWith` scan over a single-character bucket rather than a
/// re-split of every entry on every keystroke.
class _TagIndex {
  _TagIndex({
    required this.entries,
    required this.byKey,
    required this.tokens,
    required this.tokenEntry,
    required this.tokenIsWord,
    required this.tokenIsAlias,
    required this.buckets,
  });

  /// Post-count descending — search relies on this order for its tie-break.
  final List<TagDictionaryEntry> entries;

  /// [tagLookupKey] of the canonical name to its position in [entries].
  final Map<String, int> byKey;

  final List<String> tokens;
  final Uint32List tokenEntry;
  final Uint8List tokenIsWord;
  final Uint8List tokenIsAlias;

  /// First character of a token to the tokens starting with it.
  final Map<String, Uint32List> buckets;

  static final Uint32List _empty = Uint32List(0);

  Uint32List bucket(String firstChar) => buckets[firstChar] ?? _empty;
}

/// Isolate entry point: CSV text in, ready-to-query index out.
_TagIndex _buildIndex(_ParseRequest request) {
  final entries = <TagDictionaryEntry>[];

  for (final line in const LineSplitter().convert(request.csv)) {
    if (line.isEmpty) continue;
    final fields = _splitCsvLine(line);
    if (fields.length < 3) continue;

    final String name;
    final int categoryId;
    final int count;
    final List<String> aliases;
    if (request.format == _CsvFormat.wdLabels) {
      if (fields.length < 4) continue;
      name = fields[1];
      categoryId = int.tryParse(fields[2]) ?? -1;
      count = int.tryParse(fields[3]) ?? 0;
      aliases = const [];
    } else {
      name = fields[0];
      categoryId = int.tryParse(fields[1]) ?? -1;
      count = int.tryParse(fields[2]) ?? 0;
      aliases = fields.length > 3
          ? fields[3]
                .split(',')
                .map((a) => a.trim())
                .where((a) => a.isNotEmpty)
                .toList()
          : const [];
    }

    final category = TagCategory.fromId(categoryId);
    // Skips the header row (`category` parses to -1) and the WD label file's
    // four rating pseudo-tags in one test.
    if (category == null || name.isEmpty) continue;

    entries.add(
      TagDictionaryEntry(
        name: name,
        category: category,
        postCount: count,
        aliases: aliases,
      ),
    );
  }

  entries.sort((a, b) => b.postCount.compareTo(a.postCount));
  return _indexTagEntries(entries);
}

/// Builds the searchable index over [entries], which must already be sorted
/// count-descending — [TagDictionaryService.search] tie-breaks on that order.
///
/// Shared by the dictionary (built in an isolate) and the much smaller local
/// vocabulary (built inline), so both rank and match by identical rules.
_TagIndex _indexTagEntries(List<TagDictionaryEntry> entries) {
  final byKey = <String, int>{};
  final tokens = <String>[];
  final tokenEntry = <int>[];
  final tokenIsWord = <int>[];
  final tokenIsAlias = <int>[];

  void addToken(
    String text,
    int entryAt, {
    bool word = false,
    bool alias = false,
  }) {
    if (text.isEmpty) return;
    tokens.add(text);
    tokenEntry.add(entryAt);
    tokenIsWord.add(word ? 1 : 0);
    tokenIsAlias.add(alias ? 1 : 0);
  }

  for (var i = 0; i < entries.length; i++) {
    final entry = entries[i];
    final key = tagLookupKey(entry.name);
    // First writer wins: entries are popularity-sorted, so a duplicated name
    // keeps the busier of the two.
    byKey.putIfAbsent(key, () => i);
    addToken(key, i);
    // Interior words only — the whole-name token already covers the first.
    var at = key.indexOf(' ');
    while (at >= 0 && at + 1 < key.length) {
      addToken(key.substring(at + 1), i, word: true);
      at = key.indexOf(' ', at + 1);
    }
    for (final alias in entry.aliases) {
      final aliasKey = tagLookupKey(alias);
      if (aliasKey.isNotEmpty && aliasKey != key) {
        addToken(aliasKey, i, alias: true);
      }
    }
  }

  final grouped = <String, List<int>>{};
  for (var i = 0; i < tokens.length; i++) {
    grouped.putIfAbsent(tokens[i][0], () => <int>[]).add(i);
  }

  return _TagIndex(
    entries: entries,
    byKey: byKey,
    tokens: tokens,
    tokenEntry: Uint32List.fromList(tokenEntry),
    tokenIsWord: Uint8List.fromList(tokenIsWord),
    tokenIsAlias: Uint8List.fromList(tokenIsAlias),
    buckets: {
      for (final entry in grouped.entries)
        entry.key: Uint32List.fromList(entry.value),
    },
  );
}

/// Splits one CSV row, honouring double-quoted fields (the alias column is
/// quoted precisely because it contains commas). Deliberately minimal — both
/// dictionary formats are machine-generated and never contain escaped quotes
/// inside a quoted field.
List<String> _splitCsvLine(String line) {
  final fields = <String>[];
  final buffer = StringBuffer();
  var quoted = false;
  for (var i = 0; i < line.length; i++) {
    final char = line[i];
    if (char == '"') {
      quoted = !quoted;
    } else if (char == ',' && !quoted) {
      fields.add(buffer.toString().trim());
      buffer.clear();
    } else {
      buffer.write(char);
    }
  }
  fields.add(buffer.toString().trim());
  return fields;
}
