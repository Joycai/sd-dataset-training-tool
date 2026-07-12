import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

enum CaptionFilter { all, untagged, tagged }

/// Scans a dataset directory and tracks per-image caption status, the
/// search/filter state of the assets panel, and the current selection.
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
  bool _isLoading = false;
  String? _error;
  String _query = '';
  CaptionFilter _filter = CaptionFilter.all;
  String? _selectedPath;
  int _scanGeneration = 0;

  bool get isLoading => _isLoading;
  String? get error => _error;
  String get query => _query;
  CaptionFilter get filter => _filter;

  List<File> get allFiles => _files;
  int get totalCount => _files.length;
  int get taggedCount =>
      _files.where((f) => _hasCaption[f.path] == true).length;
  int get untaggedCount => totalCount - taggedCount;

  /// Files after search + caption-status filtering; the grid and the
  /// previous/next navigation both operate on this list.
  List<File> get visibleFiles {
    final q = _query.trim().toLowerCase();
    return _files.where((f) {
      if (q.isNotEmpty && !p.basename(f.path).toLowerCase().contains(q)) {
        return false;
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
    notifyListeners();
  }

  void setFilter(CaptionFilter value) {
    if (_filter == value) return;
    _filter = value;
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

  /// Called after a caption write so the status dot and the filter counts
  /// follow the file on disk without a rescan.
  void markCaptioned(String imagePath, bool captioned) {
    if (_hasCaption[imagePath] == captioned) return;
    _hasCaption[imagePath] = captioned;
    notifyListeners();
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
    String? error;
    try {
      final stream = Directory(directoryPath).list(
        recursive: recursive,
        followLinks: false,
      );
      await for (final entity in stream) {
        if (entity is! File) continue;
        if (!supportedExtensions
            .contains(p.extension(entity.path).toLowerCase())) {
          continue;
        }
        found.add(entity);
        final captionFile =
            File('${p.withoutExtension(entity.path)}$captionExtension');
        bool has = false;
        try {
          has = await captionFile.exists() &&
              (await captionFile.length()) > 0;
        } catch (_) {
          // Unreadable caption file: treat as untagged.
        }
        captioned[entity.path] = has;
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
    _selectedPath = null;
    _isLoading = false;
    _error = null;
    notifyListeners();
  }
}
