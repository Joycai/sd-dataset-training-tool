import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/tag_group.dart';

class SettingsService {
  // --- 新增：Common Tags ---
  Future<void> saveCommonTags(List<String> tags) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('commonTags', tags);
  }

  Future<List<String>> loadCommonTags() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList('commonTags') ?? []; // 默认空列表
  }

  // --- Tag groups (JSON blob, see models/tag_group.dart) ---
  Future<void> saveTagGroups(List<TagGroup> groups) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('tagGroups', encodeTagGroups(groups));
  }

  Future<List<TagGroup>> loadTagGroups() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString('tagGroups');
    return json == null ? const [] : decodeTagGroups(json);
  }

  // --- 其他设置 (保持不变) ---
  Future<void> resetSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }
  
  Future<void> saveCaptionExtension(String extension) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('captionExtension', extension);
  }

  Future<String> loadCaptionExtension() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('captionExtension') ?? '.txt';
  }

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

  static const double defaultLeftPanelWidth = 264;
  static const double defaultRightPanelWidth = 300;

  Future<void> savePanelWidths(double left, double right) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('leftPanelWidth', left);
    await prefs.setDouble('rightPanelWidth', right);
  }

  Future<(double, double)> loadPanelWidths() async {
    final prefs = await SharedPreferences.getInstance();
    return (
      prefs.getDouble('leftPanelWidth') ?? defaultLeftPanelWidth,
      prefs.getDouble('rightPanelWidth') ?? defaultRightPanelWidth,
    );
  }

  /// 中栏预览区占中栏总高的比例（0-1），对应原来的 flex 4:3。
  static const double defaultCenterSplit = 4 / 7;

  Future<void> saveCenterSplit(double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('centerSplit', value);
  }

  Future<double> loadCenterSplit() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble('centerSplit') ?? defaultCenterSplit;
  }

  Future<void> saveAutoSave(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('autoSave', value);
  }

  Future<bool> loadAutoSave() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('autoSave') ?? true;
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

  // --- AI 打标服务 (AiApiServer) ---
  static const String defaultAiServerUrl = 'http://127.0.0.1:50051';

  Future<void> saveAiServerUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('aiServerUrl', url);
  }

  Future<String> loadAiServerUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('aiServerUrl') ?? defaultAiServerUrl;
  }

  /// 上次选择的打标模型（完整 HuggingFace 仓库名），未选择时为 null。
  Future<void> saveAiModelName(String? modelName) async {
    final prefs = await SharedPreferences.getInstance();
    if (modelName == null) {
      await prefs.remove('aiModelName');
    } else {
      await prefs.setString('aiModelName', modelName);
    }
  }

  Future<String?> loadAiModelName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('aiModelName');
  }

  /// 用户覆盖的阈值；返回 null 表示用模型默认值。
  Future<void> saveAiThreshold(double? threshold) async {
    final prefs = await SharedPreferences.getInstance();
    if (threshold == null) {
      await prefs.remove('aiThreshold');
    } else {
      await prefs.setDouble('aiThreshold', threshold);
    }
  }

  Future<double?> loadAiThreshold() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble('aiThreshold');
  }

  /// 是否把 tag 里的下划线转为空格（默认 true）。
  Future<void> saveAiUnderscoreToSpaces(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('aiUnderscoreToSpaces', value);
  }

  Future<bool> loadAiUnderscoreToSpaces() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('aiUnderscoreToSpaces') ?? true;
  }

  /// 是否转义括号 ( ) -> \( \)（默认 false）。
  Future<void> saveAiEscapeParentheses(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('aiEscapeParentheses', value);
  }

  Future<bool> loadAiEscapeParentheses() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('aiEscapeParentheses') ?? false;
  }

  /// 全局忽略标签：这些标签永远不出现在 AI 识别结果里。
  Future<void> saveAiIgnoreTags(List<String> tags) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('aiIgnoreTags', tags);
  }

  Future<List<String>> loadAiIgnoreTags() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList('aiIgnoreTags') ?? [];
  }
}
