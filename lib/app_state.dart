import 'dart:convert';

import 'package:flutter/material.dart';

import 'models/tag_group.dart';
import 'services/font_service.dart';
import 'services/settings_service.dart';

enum MainView {
  editor,
  settings,
}

class AppState extends ChangeNotifier {
  final SettingsService _settingsService;

  /// 字体下载/注册状态。注册完成会触发 notify，主题随之切到新字体。
  final FontService fontService = FontService();

  AppState(this._settingsService) {
    fontService.addListener(notifyListeners);
  }

  @override
  void dispose() {
    fontService.removeListener(notifyListeners);
    fontService.dispose();
    super.dispose();
  }

  // --- Common Tags State ---
  late List<String> _commonTags;
  List<String> get commonTags => _commonTags;

  Future<void> updateCommonTags(List<String> tags) async {
    _commonTags = tags;
    notifyListeners();
    await _settingsService.saveCommonTags(tags);
    await _pruneGroups();
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
    await _pruneGroups();
  }

  // --- Tag groups ---
  //
  // Groups reference library tags by value; membership is exclusive (a tag is
  // in at most one group). Everything not referenced is implicitly
  // "ungrouped". Any change to the library prunes dangling references.

  late List<TagGroup> _tagGroups;
  Map<String, TagGroup> _tagToGroup = {};

  List<TagGroup> get tagGroups => _tagGroups;

  /// The group [tag] belongs to, or null when ungrouped / not in the library.
  TagGroup? groupOfTag(String tag) => _tagToGroup[tag];

  /// Library tags not referenced by any group, in library order.
  List<String> get ungroupedTags =>
      _commonTags.where((t) => !_tagToGroup.containsKey(t)).toList();

  void _rebuildTagToGroup() {
    _tagToGroup = {
      for (final group in _tagGroups)
        for (final tag in group.tags) tag: group,
    };
  }

  Future<void> _saveGroups() async {
    _rebuildTagToGroup();
    notifyListeners();
    await _settingsService.saveTagGroups(_tagGroups);
  }

  /// Drops group members that no longer exist in the library. Keeps empty
  /// groups — deleting a group is an explicit user action.
  Future<void> _pruneGroups() async {
    final library = _commonTags.toSet();
    var changed = false;
    _tagGroups = [
      for (final group in _tagGroups)
        () {
          final kept = group.tags.where(library.contains).toList();
          if (kept.length != group.tags.length) changed = true;
          return kept.length == group.tags.length
              ? group
              : group.copyWith(tags: kept);
        }(),
    ];
    if (changed) await _saveGroups();
  }

  // Timestamp alone can collide when groups are created back-to-back within
  // one clock tick; the counter makes ids unique within the process.
  static int _groupIdCounter = 0;

  Future<TagGroup> createTagGroup(String name, int color) async {
    final group = TagGroup(
      id: '${DateTime.now().microsecondsSinceEpoch}-${_groupIdCounter++}',
      name: name,
      color: color,
      tags: const [],
    );
    _tagGroups = [..._tagGroups, group];
    await _saveGroups();
    return group;
  }

  Future<void> updateTagGroup(String id, {String? name, int? color}) async {
    _tagGroups = [
      for (final g in _tagGroups)
        g.id == id ? g.copyWith(name: name, color: color) : g,
    ];
    await _saveGroups();
  }

  /// Deletes the group; its tags fall back to ungrouped.
  Future<void> deleteTagGroup(String id) async {
    _tagGroups = _tagGroups.where((g) => g.id != id).toList();
    await _saveGroups();
  }

  /// Removes every tag from the library. Groups survive (emptied) so a
  /// re-import or fresh tagging session keeps the structure.
  Future<void> clearCommonTags() => updateCommonTags(<String>[]);

  /// Serializes the library for transfer. Group ids are local and omitted —
  /// import matches groups by name. [groupsOnly] exports just the group
  /// definitions (name + color) without any tags.
  String exportLibraryJson({bool groupsOnly = false}) {
    return const JsonEncoder.withIndent('  ').convert({
      'version': 1,
      'groups': [
        for (final g in _tagGroups)
          {'name': g.name, 'color': g.color, if (!groupsOnly) 'tags': g.tags},
      ],
      if (!groupsOnly) 'ungrouped': ungroupedTags,
    });
  }

  /// Imports a library export produced by [exportLibraryJson] (either
  /// flavor). Merge semantics:
  ///
  /// - groups are matched by name; missing ones are created with the file's
  ///   color, existing ones keep their local color;
  /// - tags listed under a group are added to the library when new and moved
  ///   into that group (the file is authoritative for tags it mentions);
  /// - "ungrouped" tags are added to the library when new but never pulled
  ///   out of a local group they already belong to.
  ///
  /// Throws [FormatException] when the payload does not look like an export.
  Future<({int tagsAdded, int groupsCreated})> importLibraryJson(
    String text,
  ) async {
    final Map<String, dynamic> data;
    final List<({String name, int color, List<String> tags})> entries;
    final List<String> ungrouped;
    try {
      data = jsonDecode(text) as Map<String, dynamic>;
      entries = [
        for (final raw in (data['groups'] as List<dynamic>? ?? const []))
          (
            name: (raw as Map<String, dynamic>)['name'] as String,
            color: raw['color'] as int,
            tags: (raw['tags'] as List<dynamic>? ?? const []).cast<String>(),
          ),
      ];
      ungrouped =
          (data['ungrouped'] as List<dynamic>? ?? const []).cast<String>();
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('not a tag library export');
    }

    final incoming = <String>{};
    final newTags = <String>[
      for (final tag in [...entries.expand((e) => e.tags), ...ungrouped])
        if (!_commonTags.contains(tag) && incoming.add(tag)) tag,
    ];
    if (newTags.isNotEmpty) await addCommonTags(newTags);

    var groupsCreated = 0;
    for (final entry in entries) {
      if (entry.name.trim().isEmpty) continue;
      var target = _tagGroups.where((g) => g.name == entry.name).firstOrNull;
      if (target == null) {
        target = await createTagGroup(entry.name, entry.color);
        groupsCreated++;
      }
      if (entry.tags.isNotEmpty) {
        await moveTagsToGroup(entry.tags, target.id);
      }
    }
    return (tagsAdded: newTags.length, groupsCreated: groupsCreated);
  }

  /// Moves [tags] into the group with [groupId] (null = ungrouped). Removes
  /// them from their previous group first — membership is exclusive. Tags not
  /// in the library are ignored.
  Future<void> moveTagsToGroup(List<String> tags, String? groupId) async {
    final library = _commonTags.toSet();
    // De-duplicated, in caller order, restricted to library tags.
    final seen = <String>{};
    final moving =
        tags.where((t) => library.contains(t) && seen.add(t)).toList();
    if (moving.isEmpty) return;
    _tagGroups = [
      for (final g in _tagGroups)
        () {
          final kept = g.tags.where((t) => !seen.contains(t)).toList();
          if (g.id == groupId) kept.addAll(moving);
          return g.copyWith(tags: kept);
        }(),
    ];
    await _saveGroups();
  }

  // --- Other states remain unchanged ---
  Future<void> loadSettings() async {
    _locale = await _settingsService.loadLocale();
    _fontChoice = AppFontChoiceX.fromId(await _settingsService.loadFontChoice());
    _themeMode = await _settingsService.loadThemeMode();
    _crossAxisCount = await _settingsService.loadCrossAxisCount();
    _includeSubdirectories = await _settingsService.loadIncludeSubdirectories();
    _browsingDirectory = await _settingsService.loadBrowsingDirectory();
    _captionExtension = await _settingsService.loadCaptionExtension();
    _commonTags = await _settingsService.loadCommonTags();
    _tagGroups = await _settingsService.loadTagGroups();
    _rebuildTagToGroup();
    _autoSave = await _settingsService.loadAutoSave();
    final (leftWidth, rightWidth) = await _settingsService.loadPanelWidths();
    _leftPanelWidth = leftWidth;
    _rightPanelWidth = rightWidth;
    _centerSplit = await _settingsService.loadCenterSplit();

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

  late double _centerSplit;

  /// Fraction of the center column's height taken by the preview pane.
  double get centerSplit => _centerSplit;

  /// Called on drag end (not per pixel), matching [updatePanelWidths].
  Future<void> updateCenterSplit(double value) async {
    if (_centerSplit == value) return;
    _centerSplit = value;
    notifyListeners();
    await _settingsService.saveCenterSplit(value);
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

  late AppFontChoice _fontChoice;
  AppFontChoice get fontChoice => _fontChoice;

  /// 传给 ThemeData 的字体家族名；系统字体或所选字体尚未注册时为 null。
  String? get uiFontFamily => fontService.familyFor(_fontChoice);

  /// 只负责记录选择并持久化——下载/注册由设置页先行完成。
  Future<void> updateFontChoice(AppFontChoice choice) async {
    if (_fontChoice == choice) return;
    _fontChoice = choice;
    notifyListeners();
    await _settingsService.saveFontChoice(choice.id);
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
