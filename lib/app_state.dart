import 'package:flutter/material.dart';
import 'services/settings_service.dart';

enum MainView {
  editor,
  settings,
}

class AppState extends ChangeNotifier {
  final SettingsService _settingsService;

  AppState(this._settingsService);

  // --- Common Tags State ---
  late List<String> _commonTags;
  List<String> get commonTags => _commonTags;

  Future<void> updateCommonTags(List<String> tags) async {
    _commonTags = tags;
    notifyListeners();
    await _settingsService.saveCommonTags(tags);
  }

  Future<void> addCommonTags(List<String> tags) async {
    // De-duplicate against existing tags and within the input itself.
    final seen = _commonTags.toSet();
    final newTags = tags.where(seen.add).toList();
    if (newTags.isNotEmpty) {
      _commonTags.addAll(newTags);
      notifyListeners();
      await _settingsService.saveCommonTags(_commonTags);
    }
  }

  Future<void> removeCommonTags(List<String> tags) async {
    _commonTags.removeWhere((tag) => tags.contains(tag));
    notifyListeners();
    await _settingsService.saveCommonTags(_commonTags);
  }

  // --- Other states remain unchanged ---
  Future<void> loadSettings() async {
    _locale = await _settingsService.loadLocale();
    _themeMode = await _settingsService.loadThemeMode();
    _crossAxisCount = await _settingsService.loadCrossAxisCount();
    _includeSubdirectories = await _settingsService.loadIncludeSubdirectories();
    _browsingDirectory = await _settingsService.loadBrowsingDirectory();
    _captionExtension = await _settingsService.loadCaptionExtension();
    _commonTags = await _settingsService.loadCommonTags();
    _autoSave = await _settingsService.loadAutoSave();
    final (leftWidth, rightWidth) = await _settingsService.loadPanelWidths();
    _leftPanelWidth = leftWidth;
    _rightPanelWidth = rightWidth;

    notifyListeners();
  }

  late double _leftPanelWidth;
  late double _rightPanelWidth;
  double get leftPanelWidth => _leftPanelWidth;
  double get rightPanelWidth => _rightPanelWidth;

  /// Called on drag end (not per pixel) so preferences are written once per
  /// resize gesture.
  Future<void> updatePanelWidths(double left, double right) async {
    if (_leftPanelWidth == left && _rightPanelWidth == right) return;
    _leftPanelWidth = left;
    _rightPanelWidth = right;
    notifyListeners();
    await _settingsService.savePanelWidths(left, right);
  }

  late bool _autoSave;
  bool get autoSave => _autoSave;

  Future<void> updateAutoSave(bool value) async {
    if (_autoSave == value) return;
    _autoSave = value;
    notifyListeners();
    await _settingsService.saveAutoSave(value);
  }

  Future<void> resetSettings() async {
    await _settingsService.resetSettings();
    await loadSettings();
  }

  late String _captionExtension;
  String get captionExtension => _captionExtension;

  Future<void> updateCaptionExtension(String extension) async {
    if (_captionExtension == extension) return;
    _captionExtension = extension;
    notifyListeners();
    await _settingsService.saveCaptionExtension(extension);
  }

  late int _crossAxisCount;
  int get crossAxisCount => _crossAxisCount;

  late bool _includeSubdirectories;
  bool get includeSubdirectories => _includeSubdirectories;

  String? _browsingDirectory;
  String? get browsingDirectory => _browsingDirectory;

  Future<void> updateCrossAxisCount(int count) async {
    if (_crossAxisCount == count) return;
    _crossAxisCount = count;
    notifyListeners();
    await _settingsService.saveCrossAxisCount(count);
  }

  Future<void> updateIncludeSubdirectories(bool value) async {
    if (_includeSubdirectories == value) return;
    _includeSubdirectories = value;
    notifyListeners();
    await _settingsService.saveIncludeSubdirectories(value);
  }

  Future<void> setBrowsingDirectory(String? path) async {
    if (_browsingDirectory == path) return;
    _browsingDirectory = path;
    notifyListeners();
    await _settingsService.saveBrowsingDirectory(path);
  }

  late Locale _locale;
  Locale get currentLocale => _locale;

  Future<void> updateLocale(Locale locale) async {
    if (_locale == locale) return;
    _locale = locale;
    notifyListeners();
    await _settingsService.saveLocale(locale);
  }

  late ThemeMode _themeMode;
  ThemeMode get currentThemeMode => _themeMode;

  Future<void> updateThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    notifyListeners();
    await _settingsService.saveThemeMode(mode);
  }

  MainView _mainView = MainView.editor;
  MainView get currentView => _mainView;

  void updateView(MainView view) {
    if (_mainView == view) return;
    _mainView = view;
    notifyListeners();
  }

  String? _cachePath;
  String? get cachePath => _cachePath;

  String? _outputDirectory;
  String? get outputDirectory => _outputDirectory;

  void setCachePath(String path) {
    _cachePath = path;
    notifyListeners();
  }

  void setOutputDirectory(String path) {
    _outputDirectory = path;
    notifyListeners();
  }
}
