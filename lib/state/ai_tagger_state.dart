import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/ai_tagger_models.dart';
import '../services/ai_tagger_service.dart';
import '../services/settings_service.dart';

/// One normalized AI prediction: the display-ready tag string plus the best
/// probability seen across models.
class AiPrediction {
  const AiPrediction({required this.tag, required this.probability});

  final String tag;
  final double probability;
}

/// The comparison between an image's current tags and the AI predictions for
/// it. Pure data, computed by [compute] so it is unit-testable.
class AiTagDiff {
  const AiTagDiff({
    required this.newSuggestions,
    required this.missing,
    required this.matched,
  });

  /// Predicted but not on the image yet — the candidates to add.
  final List<AiPrediction> newSuggestions;

  /// On the image but absent from the predictions (possible mis-tags, or
  /// concepts the model's vocabulary simply lacks, like character names).
  final Set<String> missing;

  /// Present on both sides.
  final Set<String> matched;

  static AiTagDiff compute(
    List<String> currentTags,
    List<AiPrediction> predictions,
  ) {
    final current = currentTags.toSet();
    final predicted = predictions.map((p) => p.tag).toSet();
    return AiTagDiff(
      newSuggestions: predictions
          .where((p) => !current.contains(p.tag))
          .toList(),
      missing: current.difference(predicted),
      matched: current.intersection(predicted),
    );
  }
}

/// Owns everything the AI-tagging UI needs: the persisted parameters, the
/// model list fetched from the server, the per-image prediction cache, and
/// the compare-mode flag the caption editor switches on.
///
/// Results are cached raw (normalized, unfiltered) per image path; the ignore
/// list is applied on read so editing it re-filters without a re-run.
class AiTaggerState extends ChangeNotifier {
  AiTaggerState(this._settings, {AiTaggerService? service})
    : _service = service ?? AiTaggerService();

  final SettingsService _settings;
  final AiTaggerService _service;

  String _serverUrl = SettingsService.defaultAiServerUrl;
  String? _modelName;
  double? _threshold;
  bool _underscoreToSpaces = true;
  bool _escapeParentheses = false;
  bool _showNewOnly = false;
  List<String> _ignoreTags = [];

  List<AiModelInfo> _models = const [];
  bool _loadingModels = false;
  bool _running = false;
  bool _compareMode = false;
  String? _lastError;

  final Map<String, List<AiPrediction>> _cache = {};

  String get serverUrl => _serverUrl;
  String? get modelName => _modelName;

  /// User threshold override; null means the model default.
  double? get threshold => _threshold;
  bool get underscoreToSpaces => _underscoreToSpaces;
  bool get escapeParentheses => _escapeParentheses;

  /// Compare-view "new suggestions only" filter; remembered across image
  /// switches and app restarts.
  bool get showNewOnly => _showNewOnly;
  List<String> get ignoreTags => _ignoreTags;
  List<AiModelInfo> get models => _models;
  bool get loadingModels => _loadingModels;
  bool get running => _running;
  bool get compareMode => _compareMode;
  String? get lastError => _lastError;

  Future<void> loadSettings() async {
    _serverUrl = await _settings.loadAiServerUrl();
    _modelName = await _settings.loadAiModelName();
    _threshold = await _settings.loadAiThreshold();
    _underscoreToSpaces = await _settings.loadAiUnderscoreToSpaces();
    _escapeParentheses = await _settings.loadAiEscapeParentheses();
    _showNewOnly = await _settings.loadAiShowNewOnly();
    _ignoreTags = await _settings.loadAiIgnoreTags();
    notifyListeners();
  }

  // --- Parameter setters (persisted immediately) ----------------------

  Future<void> setServerUrl(String url) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty || trimmed == _serverUrl) return;
    _serverUrl = trimmed;
    // The model list belongs to the previous server.
    _models = const [];
    notifyListeners();
    await _settings.saveAiServerUrl(trimmed);
  }

  Future<void> setModelName(String? name) async {
    if (name == _modelName) return;
    _modelName = name;
    notifyListeners();
    await _settings.saveAiModelName(name);
  }

  Future<void> setThreshold(double? value) async {
    if (value == _threshold) return;
    _threshold = value;
    notifyListeners();
    await _settings.saveAiThreshold(value);
  }

  Future<void> setUnderscoreToSpaces(bool value) async {
    if (value == _underscoreToSpaces) return;
    _underscoreToSpaces = value;
    notifyListeners();
    await _settings.saveAiUnderscoreToSpaces(value);
  }

  Future<void> setShowNewOnly(bool value) async {
    if (value == _showNewOnly) return;
    _showNewOnly = value;
    notifyListeners();
    await _settings.saveAiShowNewOnly(value);
  }

  Future<void> setEscapeParentheses(bool value) async {
    if (value == _escapeParentheses) return;
    _escapeParentheses = value;
    notifyListeners();
    await _settings.saveAiEscapeParentheses(value);
  }

  Future<void> setIgnoreTagsFromInput(String input) async {
    final seen = <String>{};
    final tags = input
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty && seen.add(s.toLowerCase()))
        .toList();
    if (listEquals(tags, _ignoreTags)) return;
    _ignoreTags = tags;
    notifyListeners();
    await _settings.saveAiIgnoreTags(tags);
  }

  // --- Server interaction ---------------------------------------------

  /// Fetches the interrogator list. Keeps the saved model when it is still
  /// available, otherwise falls back to the first model on the server.
  Future<void> refreshModels() async {
    if (_loadingModels) return;
    _loadingModels = true;
    _lastError = null;
    notifyListeners();
    try {
      _models = await _service.listTaggers(_serverUrl);
      if (_models.isNotEmpty &&
          !_models.any((m) => m.modelName == _modelName)) {
        await setModelName(_models.first.modelName);
      }
    } on AiTaggerException catch (e) {
      _lastError = e.message;
    } finally {
      _loadingModels = false;
      notifyListeners();
    }
  }

  /// Interrogates [image] with the current model and threshold. Returns true
  /// on success (result cached, compare mode switched on); on failure
  /// [lastError] carries the message.
  ///
  /// The server holds a global interrogation lock, so calls are serialized
  /// here as well: a second click while running is a no-op.
  Future<bool> interrogate(File image) async {
    if (_running) return false;
    final model = _modelName;
    if (model == null) return false;
    _running = true;
    _lastError = null;
    notifyListeners();
    try {
      final resp = await _service.interrogateImageFile(
        _serverUrl,
        image,
        models: [AiModelRequest.wd(modelName: model, threshold: _threshold)],
      );
      _cache[image.path] = _normalize(resp);
      _compareMode = true;
      return true;
    } on AiTaggerException catch (e) {
      _lastError = e.message;
      return false;
    } finally {
      _running = false;
      notifyListeners();
    }
  }

  /// Cached predictions for [path] with the ignore list applied, or null if
  /// this image has not been interrogated yet.
  List<AiPrediction>? resultFor(String path) {
    final raw = _cache[path];
    if (raw == null || _ignoreTags.isEmpty) return raw;
    final ignore = _ignoreTags.map((t) => t.toLowerCase()).toSet();
    return raw.where((p) => !ignore.contains(p.tag.toLowerCase())).toList();
  }

  bool hasResultFor(String path) => _cache.containsKey(path);

  /// Stores a response obtained outside [interrogate] (the batch recognize
  /// run) in the per-image cache, with the same normalization, so it feeds
  /// the compare view exactly like a single-image run.
  void storeResult(String path, AiInterrogateResponse resp) {
    _cache[path] = _normalize(resp);
    notifyListeners();
  }

  void enterCompareMode() {
    if (_compareMode) return;
    _compareMode = true;
    notifyListeners();
  }

  void exitCompareMode() {
    if (!_compareMode) return;
    _compareMode = false;
    notifyListeners();
  }

  /// Flattens a response into normalized predictions: tags cleaned with the
  /// current normalization settings, de-duplicated keeping the best
  /// probability, sorted by probability descending.
  List<AiPrediction> _normalize(AiInterrogateResponse resp) {
    final best = <String, double>{};
    for (final result in resp.results) {
      for (final t in result.tags) {
        final tag = AiTaggerService.normalizeTag(
          t.tag,
          underscoreStyle: _underscoreToSpaces
              ? TagUnderscoreStyle.toSpaces
              : TagUnderscoreStyle.keep,
          escapeParentheses: _escapeParentheses,
        );
        if (tag.isEmpty) continue;
        final prev = best[tag];
        if (prev == null || t.probability > prev) {
          best[tag] = t.probability;
        }
      }
    }
    return best.entries
        .map((e) => AiPrediction(tag: e.key, probability: e.value))
        .toList()
      ..sort((a, b) => b.probability.compareTo(a.probability));
  }

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }
}
