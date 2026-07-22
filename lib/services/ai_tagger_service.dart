import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../models/ai_tagger_models.dart';

/// Raised when the AI tagging server is unreachable or returns an error.
class AiTaggerException implements Exception {
  AiTaggerException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// How WD tag underscores should be presented locally, independent of the
/// server's own `tagger_use_spaces` setting.
enum TagUnderscoreStyle { keep, toSpaces }

/// Client for the AiApiServer (BooruDatasetTagManager's Python backend).
///
/// The server is a plain Flask REST API on :50051. This client mirrors the
/// three endpoints DataSetTrainingTool needs — model discovery, model params,
/// and image interrogation. It holds no UI state; callers own image selection
/// and decide where the returned tags land (e.g. EditorSession).
class AiTaggerService {
  AiTaggerService({
    http.Client? client,
    this.requestTimeout = const Duration(minutes: 5),
    this.connectTimeout = const Duration(seconds: 10),
  }) : _client = client ?? http.Client();

  final http.Client _client;

  /// Long by design: the very first request for a model can trigger a
  /// HuggingFace download + VRAM load on the server (tens of seconds or more).
  final Duration requestTimeout;

  /// Short timeout for the lightweight discovery calls and the health probe.
  final Duration connectTimeout;

  // --- URL helpers ----------------------------------------------------

  Uri _uri(String baseUrl, String path, [Map<String, String>? query]) {
    final trimmed = baseUrl.trim();
    final normalized = trimmed.endsWith('/')
        ? trimmed.substring(0, trimmed.length - 1)
        : trimmed;
    final base = Uri.parse('$normalized$path');
    if (query == null || query.isEmpty) return base;
    return base.replace(queryParameters: {...base.queryParameters, ...query});
  }

  Future<http.Response> _get(
    String baseUrl,
    String path,
    Duration timeout, [
    Map<String, String>? query,
  ]) async {
    try {
      return await _client.get(_uri(baseUrl, path, query)).timeout(timeout);
    } on TimeoutException {
      throw AiTaggerException('Request timed out after ${timeout.inSeconds}s.');
    } on SocketException catch (e) {
      throw AiTaggerException('Cannot reach AI server at $baseUrl: ${e.message}');
    } on http.ClientException catch (e) {
      throw AiTaggerException('HTTP error: ${e.message}');
    }
  }

  Future<http.Response> _post(
    String baseUrl,
    String path,
    Object body,
    Duration timeout,
  ) async {
    try {
      return await _client
          .post(
            _uri(baseUrl, path),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(timeout);
    } on TimeoutException {
      throw AiTaggerException('Request timed out after ${timeout.inSeconds}s.');
    } on SocketException catch (e) {
      throw AiTaggerException('Cannot reach AI server at $baseUrl: ${e.message}');
    } on http.ClientException catch (e) {
      throw AiTaggerException('HTTP error: ${e.message}');
    }
  }

  Map<String, dynamic> _decodeObject(http.Response resp) {
    if (resp.statusCode != 200) {
      throw AiTaggerException(
          'Server returned HTTP ${resp.statusCode}: ${resp.body}');
    }
    try {
      final decoded = jsonDecode(utf8.decode(resp.bodyBytes));
      if (decoded is Map<String, dynamic>) return decoded;
      throw AiTaggerException('Unexpected response shape from server.');
    } on FormatException catch (e) {
      throw AiTaggerException('Invalid JSON from server: ${e.message}');
    }
  }

  // --- Endpoints ------------------------------------------------------

  /// Quick reachability probe. Returns true if `/getconfig` answers 200.
  /// Never throws — use it to drive a "connected" indicator.
  Future<bool> ping(String baseUrl) async {
    try {
      final resp =
          await _client.get(_uri(baseUrl, '/getconfig')).timeout(connectTimeout);
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// `GET /getconfig` — every model the server exposes.
  Future<AiServerConfig> getConfig(String baseUrl) async {
    final resp = await _get(baseUrl, '/getconfig', connectTimeout);
    return AiServerConfig.fromJson(_decodeObject(resp));
  }

  /// Convenience: the interrogator (tagger) models only — what a WD tagger
  /// picker would show.
  Future<List<AiModelInfo>> listTaggers(String baseUrl) async {
    final config = await getConfig(baseUrl);
    return config.interrogators;
  }

  /// `GET /listmodelsbytype?name=<type>` — models of one server-side type
  /// (e.g. `wd` for WD14 taggers, `dd` for DeepDanbooru). Returned in the
  /// same three-bucket shape as `/getconfig`.
  Future<AiServerConfig> listModelsByType(String baseUrl, String type) async {
    final resp =
        await _get(baseUrl, '/listmodelsbytype', connectTimeout, {'name': type});
    return AiServerConfig.fromJson(_decodeObject(resp));
  }

  /// `POST /getmodelparams` — the tunable parameters of one model. For WD
  /// taggers the useful field is [AiModelParams.threshold].
  Future<AiModelParams> getModelParams(String baseUrl, String modelName) async {
    final resp = await _post(
        baseUrl, '/getmodelparams', {'Name': modelName}, connectTimeout);
    return AiModelParams.fromJson(_decodeObject(resp));
  }

  /// `POST /interrogateimage` for an image file on disk. The file is read and
  /// base64-encoded as `DataObject`. Returns the raw response; use
  /// [interrogateTags] if you just want a cleaned tag-string list.
  ///
  /// Throws [AiTaggerException] on transport failure or when the server sets
  /// `Success = false`.
  Future<AiInterrogateResponse> interrogateImageFile(
    String baseUrl,
    File imageFile, {
    required List<AiModelRequest> models,
    bool skipInternetRequests = false,
    bool serializeVramUsage = false,
  }) async {
    final Uint8List bytes;
    try {
      bytes = await imageFile.readAsBytes();
    } catch (e) {
      throw AiTaggerException('Cannot read image ${imageFile.path}: $e');
    }
    return interrogateImageBytes(
      baseUrl,
      bytes,
      fileName: p.basename(imageFile.path),
      models: models,
      skipInternetRequests: skipInternetRequests,
      serializeVramUsage: serializeVramUsage,
    );
  }

  /// `POST /interrogateimage` for raw image bytes already in memory.
  Future<AiInterrogateResponse> interrogateImageBytes(
    String baseUrl,
    Uint8List bytes, {
    required String fileName,
    required List<AiModelRequest> models,
    bool skipInternetRequests = false,
    bool serializeVramUsage = false,
  }) async {
    if (models.isEmpty) {
      throw AiTaggerException('No model specified for interrogation.');
    }
    final body = <String, dynamic>{
      'DataObject': base64Encode(bytes),
      'DataType': AiDataType.imageByteArray.value,
      'SkipInternetRequests': skipInternetRequests,
      'SerializeVramUsage': serializeVramUsage,
      'FileName': fileName,
      'Models': models.map((m) => m.toJson()).toList(),
    };
    final resp =
        await _post(baseUrl, '/interrogateimage', body, requestTimeout);
    final result = AiInterrogateResponse.fromJson(_decodeObject(resp));
    if (!result.success) {
      throw AiTaggerException(result.errorMessage.isEmpty
          ? 'Interrogation failed.'
          : result.errorMessage);
    }
    return result;
  }

  /// Interrogate a file and return a cleaned, de-duplicated tag list ready to
  /// feed into EditorSession (e.g. `addTagsFromInput(tags.join(', '))`).
  Future<List<String>> interrogateTags(
    String baseUrl,
    File imageFile, {
    required List<AiModelRequest> models,
    bool skipInternetRequests = false,
    bool serializeVramUsage = false,
    TagUnderscoreStyle underscoreStyle = TagUnderscoreStyle.toSpaces,
    bool escapeParentheses = false,
  }) async {
    final resp = await interrogateImageFile(
      baseUrl,
      imageFile,
      models: models,
      skipInternetRequests: skipInternetRequests,
      serializeVramUsage: serializeVramUsage,
    );
    return resp.allTags
        .map((t) => normalizeTag(
              t,
              underscoreStyle: underscoreStyle,
              escapeParentheses: escapeParentheses,
            ))
        .where((t) => t.isNotEmpty)
        .toList();
  }

  /// Local tag normalization, independent of the server's `tagger_use_spaces`.
  ///
  /// - [underscoreStyle] `toSpaces` turns `long_hair` into `long hair`.
  /// - [escapeParentheses] turns `smile (expression)` into `smile \(expression\)`,
  ///   which SDXL/kohya prompt parsing expects for literal parens.
  static String normalizeTag(
    String tag, {
    TagUnderscoreStyle underscoreStyle = TagUnderscoreStyle.toSpaces,
    bool escapeParentheses = false,
  }) {
    var out = tag.trim();
    if (underscoreStyle == TagUnderscoreStyle.toSpaces) {
      out = out.replaceAll('_', ' ');
    }
    if (escapeParentheses) {
      out = out.replaceAll('(', r'\(').replaceAll(')', r'\)');
    }
    return out;
  }

  /// Release the underlying HTTP client. Call from the owner's dispose().
  void dispose() => _client.close();
}
