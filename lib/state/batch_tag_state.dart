import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/ai_tagger_models.dart';
import '../services/ai_tagger_service.dart';
import '../services/settings_service.dart';
import '../utils/tag_text.dart';
import 'ai_tagger_state.dart';
import 'dataset_state.dart';
import 'tag_ops.dart';

/// How batch tagging combines AI predictions with a file's existing tags.
enum BatchTagMode {
  /// Predictions replace the existing tags; a preserved-tag list and a
  /// keep-first-N count decide which existing tags survive.
  overwrite,

  /// Predictions not already present are appended after the existing tags;
  /// blacklisted predictions are dropped.
  append,
}

/// The per-run configuration of a batch tagging pass. Pure data so the merge
/// is unit-testable without any state object.
class BatchTagConfig {
  const BatchTagConfig({
    required this.mode,
    this.preservedTags = const [],
    this.keepFirstN = 0,
    this.blacklist = const [],
  });

  final BatchTagMode mode;

  /// Overwrite mode: existing tags matching this list (case-insensitively)
  /// survive the overwrite.
  final List<String> preservedTags;

  /// Overwrite mode: the first N existing tags survive regardless of the
  /// preserved list (kohya keep-tokens style).
  final int keepFirstN;

  /// Append mode: predictions matching this list are never appended.
  final List<String> blacklist;
}

/// Merges AI [predicted] tags into [current] according to [config]. Returns
/// the new tag list, or null when the file would not change — mirroring the
/// TagOps transform contract so unchanged files are never rewritten.
///
/// Matching is case-insensitive everywhere; the surviving spelling is the one
/// that appears first (existing tags win over predictions).
List<String>? mergeBatchTags({
  required List<String> current,
  required List<String> predicted,
  required BatchTagConfig config,
}) {
  final List<String> next;
  switch (config.mode) {
    case BatchTagMode.overwrite:
      final preserved =
          config.preservedTags.map((t) => t.toLowerCase()).toSet();
      final kept = <String>[];
      for (var i = 0; i < current.length; i++) {
        final tag = current[i];
        if (i < config.keepFirstN || preserved.contains(tag.toLowerCase())) {
          kept.add(tag);
        }
      }
      final seen = kept.map((t) => t.toLowerCase()).toSet();
      next = [
        ...kept,
        ...predicted.where((t) => seen.add(t.toLowerCase())),
      ];
    case BatchTagMode.append:
      final blacklist = config.blacklist.map((t) => t.toLowerCase()).toSet();
      final seen = current.map((t) => t.toLowerCase()).toSet();
      next = [
        ...current,
        ...predicted.where((t) =>
            !blacklist.contains(t.toLowerCase()) && seen.add(t.toLowerCase())),
      ];
  }
  return listEquals(next, current) ? null : next;
}

/// Runs a whole-dataset AI tagging pass: interrogates every target image
/// sequentially (the server holds a global interrogation lock), merges the
/// predictions into each caption file per [BatchTagConfig], and reports the
/// rewrites as one undoable [TagOperation].
///
/// Server URL, model, threshold, normalization and the global ignore list all
/// follow [AiTaggerState] so batch runs behave exactly like single-image runs.
class BatchTagState extends ChangeNotifier {
  BatchTagState({
    required this.dataset,
    required this.ai,
    required SettingsService settings,
    AiTaggerService? service,
    this.beforeMutate,
    this.onOperation,
    this.onCaptionsChanged,
  })  : _settings = settings,
        _service = service ?? AiTaggerService();

  final DatasetState dataset;
  final AiTaggerState ai;
  final SettingsService _settings;
  final AiTaggerService _service;

  /// Awaited before any disk mutation; the workbench flushes the editor
  /// session here so pending edits are not silently overwritten.
  Future<void> Function()? beforeMutate;

  /// Receives the finished run as one operation for the undo history.
  void Function(TagOperation op)? onOperation;

  /// Reports every image whose caption file was rewritten, so the currently
  /// open image can be reloaded from disk.
  void Function(Set<String> imagePaths)? onCaptionsChanged;

  // --- Persisted configuration ----------------------------------------

  BatchTagMode _mode = BatchTagMode.append;
  List<String> _preservedTags = [];
  int _keepFirstN = 0;
  List<String> _blacklist = [];

  BatchTagMode get mode => _mode;
  List<String> get preservedTags => _preservedTags;
  int get keepFirstN => _keepFirstN;
  List<String> get blacklist => _blacklist;

  // --- Run progress ----------------------------------------------------

  bool _running = false;
  bool _cancelRequested = false;
  int _total = 0;
  int _completed = 0;
  int _changed = 0;
  int _failed = 0;
  String? _currentPath;
  String? _lastError;

  bool get running => _running;
  bool get cancelRequested => _cancelRequested;
  int get total => _total;
  int get completed => _completed;
  int get changed => _changed;
  int get failed => _failed;

  /// The image currently being interrogated, or null when idle.
  String? get currentPath => _currentPath;

  /// The most recent per-file error message of the current/last run.
  String? get lastError => _lastError;

  double? get progress => _total == 0 ? null : _completed / _total;

  Future<void> loadSettings() async {
    final modeName = await _settings.loadBatchTagMode();
    _mode = BatchTagMode.values.firstWhere(
      (e) => e.name == modeName,
      orElse: () => BatchTagMode.append,
    );
    _preservedTags = await _settings.loadBatchTagPreservedTags();
    _keepFirstN = await _settings.loadBatchTagKeepFirstN();
    _blacklist = await _settings.loadBatchTagBlacklist();
    notifyListeners();
  }

  Future<void> setMode(BatchTagMode value) async {
    if (value == _mode) return;
    _mode = value;
    notifyListeners();
    await _settings.saveBatchTagMode(value.name);
  }

  Future<void> setPreservedTagsFromInput(String input) async {
    final tags = parseTagText(input);
    if (listEquals(tags, _preservedTags)) return;
    _preservedTags = tags;
    notifyListeners();
    await _settings.saveBatchTagPreservedTags(tags);
  }

  Future<void> setKeepFirstN(int value) async {
    final clamped = value < 0 ? 0 : value;
    if (clamped == _keepFirstN) return;
    _keepFirstN = clamped;
    notifyListeners();
    await _settings.saveBatchTagKeepFirstN(clamped);
  }

  Future<void> setBlacklistFromInput(String input) async {
    final tags = parseTagText(input);
    if (listEquals(tags, _blacklist)) return;
    _blacklist = tags;
    notifyListeners();
    await _settings.saveBatchTagBlacklist(tags);
  }

  /// The config assembled from the persisted fields.
  BatchTagConfig get config => BatchTagConfig(
        mode: _mode,
        preservedTags: _preservedTags,
        keepFirstN: _keepFirstN,
        blacklist: _blacklist,
      );

  /// Stops the run after the in-flight interrogation finishes. Files already
  /// rewritten stay rewritten (and undoable); the rest are left untouched.
  void requestCancel() {
    if (!_running || _cancelRequested) return;
    _cancelRequested = true;
    notifyListeners();
  }

  /// Interrogates and rewrites [files] sequentially. Returns false when a run
  /// is already active, [files] is empty, or no model is selected (the latter
  /// also sets [lastError] via the AI state's own message conventions).
  ///
  /// [operationLabel] is the localized undo-history label for this run.
  Future<bool> run({
    required List<File> files,
    required String operationLabel,
  }) async {
    if (_running || files.isEmpty) return false;
    final model = ai.modelName;
    if (model == null) return false;
    final runConfig = config;

    _running = true;
    _cancelRequested = false;
    _total = files.length;
    _completed = 0;
    _changed = 0;
    _failed = 0;
    _lastError = null;
    notifyListeners();

    final edits = <CaptionEdit>[];
    try {
      await beforeMutate?.call();
      for (final file in files) {
        if (_cancelRequested) break;
        _currentPath = file.path;
        notifyListeners();
        try {
          final resp = await _service.interrogateImageFile(
            ai.serverUrl,
            file,
            models: [
              AiModelRequest.wd(modelName: model, threshold: ai.threshold),
            ],
          );
          final predicted = _normalizePredictions(resp);
          final edit = await _applyToCaption(file.path, predicted, runConfig);
          if (edit != null) {
            edits.add(edit);
            _changed++;
          }
        } catch (e) {
          _failed++;
          _lastError = e is AiTaggerException ? e.message : e.toString();
        }
        _completed++;
        notifyListeners();
      }
    } finally {
      if (edits.isNotEmpty) {
        dataset.updateCaptionTexts({for (final e in edits) e.imagePath: e.after});
        onOperation?.call(TagOperation(label: operationLabel, edits: edits));
      }
      _running = false;
      _cancelRequested = false;
      _currentPath = null;
      notifyListeners();
      if (edits.isNotEmpty) {
        onCaptionsChanged?.call({for (final e in edits) e.imagePath});
      }
    }
    return true;
  }

  /// Merges [predicted] into the caption file of [imagePath]; returns the
  /// resulting edit, or null when the caption did not change. A missing
  /// caption file counts as an empty one and is created on write.
  Future<CaptionEdit?> _applyToCaption(
    String imagePath,
    List<String> predicted,
    BatchTagConfig runConfig,
  ) async {
    final captionPath = dataset.captionPathFor(imagePath);
    final captionFile = File(captionPath);
    var before = '';
    if (await captionFile.exists()) {
      before = await captionFile.readAsString();
    }
    final next = mergeBatchTags(
      current: parseTagText(before),
      predicted: predicted,
      config: runConfig,
    );
    if (next == null) return null;
    final after = next.join(', ');
    await captionFile.writeAsString(after);
    return CaptionEdit(
      imagePath: imagePath,
      captionPath: captionPath,
      before: before,
      after: after,
    );
  }

  /// Flattens a response into a normalized tag list: cleaned with the AI
  /// state's normalization settings, de-duplicated keeping the best
  /// probability, sorted by probability descending, ignore list applied.
  List<String> _normalizePredictions(AiInterrogateResponse resp) {
    final best = <String, double>{};
    for (final result in resp.results) {
      for (final t in result.tags) {
        final tag = AiTaggerService.normalizeTag(
          t.tag,
          underscoreStyle: ai.underscoreToSpaces
              ? TagUnderscoreStyle.toSpaces
              : TagUnderscoreStyle.keep,
          escapeParentheses: ai.escapeParentheses,
        );
        if (tag.isEmpty) continue;
        final prev = best[tag];
        if (prev == null || t.probability > prev) {
          best[tag] = t.probability;
        }
      }
    }
    final ignore = ai.ignoreTags.map((t) => t.toLowerCase()).toSet();
    final entries = best.entries
        .where((e) => !ignore.contains(e.key.toLowerCase()))
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return [for (final e in entries) e.key];
  }

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }
}
