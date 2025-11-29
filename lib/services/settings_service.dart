import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsService {
  // --- 新增：Caption Extension ---
  Future<void> saveCaptionExtension(String extension) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('captionExtension', extension);
  }

  Future<String> loadCaptionExtension() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('captionExtension') ?? '.txt'; // 默认 .txt
  }

  // --- 新增：重置所有设置 ---
  Future<void> resetSettings() async {
    final prefs = await SharedPreferences.getInstance();
    // 注意：这会清除所有 SharedPreferences 数据！
    await prefs.clear();
  }

  // --- 编辑器设置 (保持不变) ---
  Future<void> saveCrossAxisCount(int count) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('crossAxisCount', count);
  }

  Future<int> loadCrossAxisCount() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('crossAxisCount') ?? 4;
  }

  Future<void> saveIncludeSubdirectories(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('includeSubdirectories', value);
  }

  Future<bool> loadIncludeSubdirectories() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('includeSubdirectories') ?? false;
  }

  Future<void> saveBrowsingDirectory(String? path) async {
    final prefs = await SharedPreferences.getInstance();
    if (path == null) {
      await prefs.remove('browsingDirectory');
    } else {
      await prefs.setString('browsingDirectory', path);
    }
  }

  Future<String?> loadBrowsingDirectory() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('browsingDirectory');
  }

  // --- 主题和语言设置 (保持不变) ---
  Future<void> saveThemeMode(ThemeMode themeMode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('themeMode', themeMode.name);
  }

  Future<ThemeMode> loadThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    final themeModeName = prefs.getString('themeMode');
    return ThemeMode.values.firstWhere(
      (e) => e.name == themeModeName,
      orElse: () => ThemeMode.system,
    );
  }

  Future<void> saveLocale(Locale locale) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('languageCode', locale.languageCode);
  }

  Future<Locale> loadLocale() async {
    final prefs = await SharedPreferences.getInstance();
    final languageCode = prefs.getString('languageCode');
    return Locale(languageCode ?? 'en');
  }
}
