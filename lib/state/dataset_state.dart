import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../utils/tag_text.dart';

enum CaptionFilter { all, untagged, tagged }

/// A tag that appears somewhere in the dataset and how many images carry it.
class DatasetTag {
  const DatasetTag(this.tag, this.count);

  final String tag;
  final int count;
}

/// Scans a dataset directory and tracks per-image caption status and tags,
/// the search/filter state of the assets panel, and the current selection.
class DatasetState extends ChangeNotifier {
  static const supportedExtensions = {
    '.jpg',
    '.jpeg',
    '.png',
    '.gif',
    '.bmp',
    '.webp',
  };

  List<File> _files = [];
  final Map<String, bool> _hasCaption = {};
  final Map<String, List<String>> _tagsByPath = {};
  List<DatasetTag>? _tagCountsCache;
  // Derived-list caches: several panels read these getters in every build,
  // so they are computed once per state change instead of once per read.
  List<File>? _visibleCache;
  int? _taggedCountCache;
  String _captionExtension = '.txt';
  bool _isLoading = false;
  String? _error;
  String _query = '';
  CaptionFilter _filter = CaptionFilter.all;
  String? _tagFilter;
  bool _tagFilterExclude = false;
  String? _selectedPath;
  int _scanGeneration = 0;

  bool get isLoading => _isLoading;
  String? get error => _error;
  String get query => _query;
  CaptionFilter get filter => _filter;

  /// Active dataset-tag filter, if any; [tagFilterExclude] flips it to
  /// "images without this tag".
  String? get tagFilter => _tagFilter;
  bool get tagFilterExclude => _tagFilterExclude;

  List<File> get allFiles => _files;
  int get totalCount => _files.length;
  int get taggedCount => _taggedCountCache ??=
      _files.where((f) => _hasCaption[f.path] == true).length;
  int get untaggedCount => totalCount - taggedCount;

  /// Drops every derived cache; call before notifying after any change to
  /// the files, captions, or filters.
  void _invalidateDerived() {
    _visibleCache = null;
    _taggedCountCache = null;
  }

  /// Every tag in the dataset with its image count, most frequent first
  /// (alphabetical within equal counts). Cached until captions change.
  List<DatasetTag> get datasetTags => _tagCountsCache ??= _computeTagCounts();

  List<DatasetTag> _computeTagCounts() {
    final counts = <String, int>{};
    for (final tags in _tagsByPath.values) {
      for (final tag in tags) {
        counts[tag] = (counts[tag] ?? 0) + 1;
      }
    }
    final list =
        [for (final entry in counts.entries) DatasetTag(entry.key, entry.value)]
          ..sort((a, b) {
            final byCount = b.count.compareTo(a.count);
            if (byCount != 0) return byCount;
            return a.tag.toLowerCase().compareTo(b.tag.toLowerCase());
          });
    return list;
  }

  /// Parsed tags of an image's caption ([] when uncaptioned).
  List<String> tagsOf(String imagePath) => _tagsByPath[imagePath] ?? const [];

  /// Caption file path for an image, using the extension of the last scan.
  String captionPathFor(String imagePath) =>
      '${p.withoutExtension(imagePath)}$_captionExtension';

  /// Files after search + caption-status + tag filtering; the grid and the
  /// previous/next navigation both operate on this list.
  List<File> get visibleFiles => _visibleCache ??= _computeVisibleFiles();

  List<File> _computeVisibleFiles() {
    final q = _query.trim().toLowerCase();
    return _files.where((f) {
      if (q.isNotEmpty && !p.basename(f.path).toLowerCase().contains(q)) {
        return false;
      }
      final tagFilter = _tagFilter;
      if (tagFilter != null) {
        final has = _tagsByPath[f.path]?.contains(tagFilter) ?? false;
        // Include mode drops images without the tag; exclude mode drops
        // images with it.
        if (has == _tagFilterExclude) return false;
      }
      switch (_filter) {
        case CaptionFilter.all:
          return true;
        case CaptionFilter.tagged:
          return _hasCaption[f.path] == true;
        case CaptionFilter.untagged:
          return _hasCaption[f.path] != true;
      }
    }).toList();
  }

  File? get selectedFile {
    if (_selectedPath == null) return null;
    for (final f in _files) {
      if (f.path == _selectedPath) return f;
    }
    return null;
  }

  int get selectedVisibleIndex {
    if (_selectedPath == null) return -1;
    return visibleFiles.indexWhere((f) => f.path == _selectedPath);
  }

  bool hasCaption(String imagePath) => _hasCaption[imagePath] == true;

  void setQuery(String value) {
    if (_query == value) return;
    _query = value;
    _invalidateDerived();
    notifyListeners();
  }

  void setFilter(CaptionFilter value) {
    if (_filter == value) return;
    _filter = value;
    _invalidateDerived();
    notifyListeners();
  }

  void setTagFilter(String tag, {required bool exclude}) {
    if (_tagFilter == tag && _tagFilterExclude == exclude) return;
    _tagFilter = tag;
    _tagFilterExclude = exclude;
    _invalidateDerived();
    notifyListeners();
  }

  void clearTagFilter() {
    if (_tagFilter == null) return;
    _tagFilter = null;
    _tagFilterExclude = false;
    _invalidateDerived();
    notifyListeners();
  }

  void select(String? path) {
    if (_selectedPath == path) return;
    _selectedPath = path;
    notifyListeners();
  }

  /// Moves the selection within [visibleFiles]; selects the first image when
  /// nothing is selected yet. Returns the newly selected file, if any.
  File? selectByOffset(int offset) {
    final visible = visibleFiles;
    if (visible.isEmpty) return null;
    final current = selectedVisibleIndex;
    final next = current < 0
        ? (offset > 0 ? 0 : visible.length - 1)
        : (current + offset).clamp(0, visible.length - 1);
    if (visible[next].path == _selectedPath) return null;
    _selectedPath = visible[next].path;
    notifyListeners();
    return visible[next];
  }

  /// Called after a caption write so the status dot, the filter counts and
  /// the dataset tag index follow the file on disk without a rescan.
  void updateCaptionText(String imagePath, String text) {
    if (!_applyCaptionText(imagePath, text)) return;
    _tagCountsCache = null;
    _invalidateDerived();
    notifyListeners();
  }

  /// Batch variant for dataset-wide rewrites: one notification for the whole
  /// operation instead of one rebuild per touched file.
  void updateCaptionTexts(Map<String, String> textByPath) {
    var changed = false;
    textByPath.forEach((path, text) {
      changed = _applyCaptionText(path, text) || changed;
    });
    if (!changed) return;
    _tagCountsCache = null;
    _invalidateDerived();
    notifyListeners();
  }

  bool _applyCaptionText(String imagePath, String text) {
    final tags = parseTagText(text);
    final captioned = text.trim().isNotEmpty;
    if (_hasCaption[imagePath] == captioned &&
        listEquals(_tagsByPath[imagePath], tags)) {
      return false;
    }
    _hasCaption[imagePath] = captioned;
    _tagsByPath[imagePath] = tags;
    return true;
  }

  Future<void> scan({
    required String directoryPath,
    required bool recursive,
    required String captionExtension,
  }) async {
    final generation = ++_scanGeneration;
    _isLoading = true;
    _error = null;
    notifyListeners();

    final found = <File>[];
    final captioned = <String, bool>{};
    final tagsByPath = <String, List<String>>{};
    String? error;
    try {
      final stream = Directory(
        directoryPath,
      ).list(recursive: recursive, followLinks: false);
      await for (final entity in stream) {
        if (entity is! File) continue;
        if (!supportedExtensions.contains(
          p.extension(entity.path).toLowerCase(),
        )) {
          continue;
        }
        found.add(entity);
        final captionFile = File(
          '${p.withoutExtension(entity.path)}$captionExtension',
        );
        String content = '';
        try {
          if (await captionFile.exists()) {
            content = await captionFile.readAsString();
          }
        } catch (_) {
          // Unreadable caption file: treat as untagged.
        }
        captioned[entity.path] = content.trim().isNotEmpty;
        tagsByPath[entity.path] = parseTagText(content);
      }
    } catch (e) {
      error = e.toString();
    }

    // A newer scan superseded this one while it was reading the disk.
    if (generation != _scanGeneration) return;

    found.sort((a, b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()));
    _files = found;
    _hasCaption
      ..clear()
      ..addAll(captioned);
    _tagsByPath
      ..clear()
      ..addAll(tagsByPath);
    _tagCountsCache = null;
    _invalidateDerived();
    _captionExtension = captionExtension;
    _isLoading = false;
    _error = error;
    if (_selectedPath != null && !captioned.containsKey(_selectedPath)) {
      _selectedPath = null;
    }
    notifyListeners();
  }

  void clear() {
    _scanGeneration++;
    _files = [];
    _hasCaption.clear();
    _tagsByPath.clear();
    _tagCountsCache = null;
    _invalidateDerived();
    _selectedPath = null;
    _tagFilter = null;
    _tagFilterExclude = false;
    _isLoading = false;
    _error = null;
    notifyListeners();
  }
}
