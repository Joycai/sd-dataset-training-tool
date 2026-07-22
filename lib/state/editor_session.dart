import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;

import '../utils/tag_text.dart';

enum SaveState { clean, dirty, saving, saved, error }

/// Owns the caption being edited for the currently selected image: the text
/// controller, the parsed tag list, and a debounced autosave.
///
/// The center editor and the tag library both mutate the caption through this
/// object so they stay in sync.
class EditorSession extends ChangeNotifier {
  EditorSession() {
    captionController.addListener(_onTextChanged);
  }

  static const autoSaveDelay = Duration(milliseconds: 800);

  final TextEditingController captionController = TextEditingController();

  File? _image;
  String _captionPath = '';
  List<String> _tags = [];
  SaveState _saveState = SaveState.clean;
  DateTime? _lastSavedAt;
  String? _lastError;
  int? _imageWidth;
  int? _imageHeight;
  int? _imageBytes;
  Timer? _autoSaveTimer;
  bool _autoSaveEnabled = true;
  bool _suppressTextEvents = false;
  String _lastText = '';
  int _loadGeneration = 0;

  /// Notified after every successful save with the caption's on-disk text,
  /// so the dataset can update status dots and its tag index without
  /// rescanning.
  void Function(String imagePath, String captionText)? onSaved;

  File? get image => _image;
  String get captionPath => _captionPath;
  List<String> get tags => _tags;
  SaveState get saveState => _saveState;
  DateTime? get lastSavedAt => _lastSavedAt;
  String? get lastError => _lastError;
  int? get imageWidth => _imageWidth;
  int? get imageHeight => _imageHeight;
  int? get imageBytes => _imageBytes;
  bool get hasImage => _image != null;

  // ignore: avoid_setters_without_getters
  set autoSaveEnabled(bool value) {
    _autoSaveEnabled = value;
    if (!value) _autoSaveTimer?.cancel();
  }

  Future<void> load(File imageFile, String captionExtension) async {
    // Flush pending edits of the previous image before switching.
    await flush();

    final generation = ++_loadGeneration;
    final captionPath =
        '${p.withoutExtension(imageFile.path)}$captionExtension';

    String content = '';
    String? error;
    int? bytes;
    try {
      final captionFile = File(captionPath);
      if (await captionFile.exists()) {
        content = await captionFile.readAsString();
      }
      bytes = await imageFile.length();
    } catch (e) {
      error = e.toString();
    }

    if (generation != _loadGeneration) return;

    _image = imageFile;
    _captionPath = captionPath;
    _imageBytes = bytes;
    _imageWidth = null;
    _imageHeight = null;
    _lastError = error;
    _saveState = error == null ? SaveState.clean : SaveState.error;
    _setText(content);
    _tags = _parseTags(content);
    notifyListeners();
  }

  Future<void> unload() async {
    await flush();
    _loadGeneration++;
    _image = null;
    _captionPath = '';
    _imageWidth = null;
    _imageHeight = null;
    _imageBytes = null;
    _tags = [];
    _saveState = SaveState.clean;
    _lastError = null;
    _setText('');
    notifyListeners();
  }

  /// Reported by the preview once the image is decoded; the status bar shows
  /// the resolution from here.
  void setImageDimensions(int width, int height) {
    if (_imageWidth == width && _imageHeight == height) return;
    _imageWidth = width;
    _imageHeight = height;
    notifyListeners();
  }

  // --- Tag operations -------------------------------------------------

  bool hasTag(String tag) => _tags.contains(tag);

  void applyTag(String tag) {
    if (_tags.contains(tag)) return;
    _tags = [..._tags, tag];
    _writeTagsToText();
  }

  void removeTag(String tag) {
    if (!_tags.contains(tag)) return;
    _tags = _tags.where((t) => t != tag).toList();
    _writeTagsToText();
  }

  void toggleTag(String tag) => hasTag(tag) ? removeTag(tag) : applyTag(tag);

  void addTagsFromInput(String input) {
    final parts = _parseTags(input).where((t) => !_tags.contains(t)).toList();
    if (parts.isEmpty) return;
    _tags = [..._tags, ...parts];
    _writeTagsToText();
  }

  void reorderTag(int oldIndex, int newIndex) {
    if (oldIndex == newIndex) return;
    final next = [..._tags];
    final tag = next.removeAt(oldIndex);
    next.insert(newIndex, tag);
    _tags = next;
    _writeTagsToText();
  }

  /// Replaces the tag at [index] with the (comma-splittable) replacement.
  void replaceTagAt(int index, String replacement) {
    final parts = _parseTags(replacement);
    final next = [..._tags];
    next.removeAt(index);
    // Re-de-duplicate against the remaining tags.
    final seen = next.toSet();
    next.insertAll(index, parts.where(seen.add));
    _tags = next;
    _writeTagsToText();
  }

  // --- Saving ---------------------------------------------------------

  Future<void> save() async {
    if (_image == null || _captionPath.isEmpty) return;
    _autoSaveTimer?.cancel();
    final path = _captionPath;
    final text = captionController.text;
    _saveState = SaveState.saving;
    notifyListeners();
    try {
      await File(path).writeAsString(text);
      if (path != _captionPath) return; // switched image mid-write
      _saveState = SaveState.saved;
      _lastSavedAt = DateTime.now();
      _lastError = null;
      onSaved?.call(_image!.path, text);
    } catch (e) {
      if (path != _captionPath) return;
      _saveState = SaveState.error;
      _lastError = e.toString();
    }
    notifyListeners();
  }

  /// Writes pending changes immediately (used before switching images and on
  /// window-level shortcuts).
  Future<void> flush() async {
    if (_saveState == SaveState.dirty) {
      await save();
    }
  }

  // --- Internals ------------------------------------------------------

  void _onTextChanged() {
    if (_suppressTextEvents) return;
    // The controller also notifies on cursor/selection changes; only actual
    // text edits should mark the session dirty and fan out rebuilds.
    final text = captionController.text;
    if (text == _lastText) return;
    _lastText = text;
    _tags = _parseTags(text);
    _saveState = SaveState.dirty;
    _autoSaveTimer?.cancel();
    if (_autoSaveEnabled && _image != null) {
      _autoSaveTimer = Timer(autoSaveDelay, save);
    }
    notifyListeners();
  }

  void _writeTagsToText() {
    _setText(_tags.join(', '));
    _saveState = SaveState.dirty;
    _autoSaveTimer?.cancel();
    if (_autoSaveEnabled && _image != null) {
      _autoSaveTimer = Timer(autoSaveDelay, save);
    }
    notifyListeners();
  }

  void _setText(String text) {
    _suppressTextEvents = true;
    captionController.text = text;
    _suppressTextEvents = false;
    _lastText = text;
  }

  static List<String> _parseTags(String text) => parseTagText(text);

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    captionController.removeListener(_onTextChanged);
    captionController.dispose();
    super.dispose();
  }
}
