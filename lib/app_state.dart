import 'package:flutter/material.dart';
import 'services/settings_service.dart';

enum MainView {
  editor,
  settings,
}

class AppState extends ChangeNotifier {
  final SettingsService _settingsService;

  AppState(this._settingsService);

  // --- 新增：Caption Extension 状态 ---
  late String _captionExtension;
  String get captionExtension => _captionExtension;

  void updateCaptionExtension(String extension) async {
    if (_captionExtension == extension) return;
    _captionExtension = extension;
    notifyListeners();
    await _settingsService.saveCaptionExtension(extension);
  }

  // --- 新增：重置设置方法 ---
  Future<void> resetSettings() async {
    await _settingsService.resetSettings();
    // 重置后，重新加载所有设置以恢复到默认值
    await loadSettings();
  }

  // --- 加载设置的方法 ---
  Future<void> loadSettings() async {
    _locale = await _settingsService.loadLocale();
    _themeMode = await _settingsService.loadThemeMode();
    _crossAxisCount = await _settingsService.loadCrossAxisCount();
    _includeSubdirectories = await _settingsService.loadIncludeSubdirectories();
    _browsingDirectory = await _settingsService.loadBrowsingDirectory();
    _captionExtension = await _settingsService.loadCaptionExtension(); // 加载新设置

    notifyListeners();
  }

  // --- 其他状态保持不变 ---
  late int _crossAxisCount;
  int get crossAxisCount => _crossAxisCount;

  late bool _includeSubdirectories;
  bool get includeSubdirectories => _includeSubdirectories;

  String? _browsingDirectory;
  String? get browsingDirectory => _browsingDirectory;

  void updateCrossAxisCount(int count) async {
    if (_crossAxisCount == count) return;
    _crossAxisCount = count;
    notifyListeners();
    await _settingsService.saveCrossAxisCount(count);
  }

  void updateIncludeSubdirectories(bool value) async {
    if (_includeSubdirectories == value) return;
    _includeSubdirectories = value;
    notifyListeners();
    await _settingsService.saveIncludeSubdirectories(value);
  }

  void setBrowsingDirectory(String? path) async {
    if (_browsingDirectory == path) return;
    _browsingDirectory = path;
    notifyListeners();
    await _settingsService.saveBrowsingDirectory(path);
  }

  late Locale _locale;
  Locale get currentLocale => _locale;

  void updateLocale(Locale locale) async {
    if (_locale == locale) return;
    _locale = locale;
    notifyListeners();
    await _settingsService.saveLocale(locale);
  }

  late ThemeMode _themeMode;
  ThemeMode get currentThemeMode => _themeMode;

  void updateThemeMode(ThemeMode mode) async {
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
