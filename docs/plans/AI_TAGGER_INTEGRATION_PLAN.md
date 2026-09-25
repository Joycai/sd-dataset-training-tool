# DataSetTrainingTool 集成 AiApiServer（WD14 打标）实施方案

> 目标：为 Flutter 桌面应用 **DataSetTrainingTool** 增加"调用 AiApiServer 识别当前图片、生成 WD14 风格 tag"的**后台能力**。
> 本阶段**只做 service 层（网络 + 数据模型 + 设置持久化）**，不涉及 UI / 交互——UI 待产品确定后另行开发。
> 本文档供 Claude Code 在本机（可运行 `flutter` / `dart`）执行。

---

## 0. 背景

- **DataSetTrainingTool**：Flutter/Dart 桌面应用（Windows/Linux），用于编辑 SDXL LoRA 训练集的 caption/tag。
- **AiApiServer**：BooruDatasetTagManager 使用的 Python/Flask 后端，监听 `0.0.0.0:50051`，提供图片识别（interrogator）、图片编辑、翻译等能力。二者之间是**纯 HTTP + JSON**，无私有协议。
- 用户会自行在本机或别处启动 AiApiServer，DataSetTrainingTool 作为客户端把图片发过去、取回 tag。

本方案就是把 BooruDatasetTagManager 的 .NET 客户端逻辑用 Dart 重写，聚焦 WD14 打标所需的三个端点。

---

## 1. 服务端协议摘要（来自 AiApiServer 源码）

Base URL 默认 `http://127.0.0.1:50051`。相关端点：

### 1.1 `GET /getconfig`
返回全部模型，按三类分桶。WD 系列 tagger 在 `Interrogators` 里，`ModelName` 是完整 HuggingFace 仓库名（如 `SmilingWolf/wd-swinv2-tagger-v3`）。

响应：
```json
{
  "Interrogators": [ {"ModelName": "...", "SupportedVideo": false, "RepositoryLink": "https://huggingface.co/..."} ],
  "Editors": [ ... ],
  "Translators": [ ... ]
}
```

> 备注：也可用 `GET /listmodelsbytype?name=wd` 只取 WD 类型，但 `/getconfig` 已足够，客户端拿 `Interrogators` 即可。

### 1.2 `POST /getmodelparams`
请求 `{"Name": "<模型名>"}`，返回该模型可调参数。WD 类型只有一个 `threshold`（`float1`，默认约 0.35，v3 系列 0.25）。

响应：
```json
{ "Success": true, "ErrorMessage": "", "Type": "wd",
  "Parameters": [ {"Key": "threshold", "Value": "0.35", "Type": "float1", "Comment": ""} ] }
```

### 1.3 `POST /interrogateimage`（核心）
请求体：
```json
{
  "DataObject": "<图片字节的 base64 字符串>",
  "DataType": 1,                 // 1=图片字节数组(IMAGE_BYTE_ARRAY), 2=视频路径
  "SkipInternetRequests": false, // true=禁止服务器联网下载模型
  "SerializeVramUsage": false,   // true=同一时刻只在显存保留一个模型
  "FileName": "001.png",
  "Models": [
    { "ModelName": "SmilingWolf/wd-swinv2-tagger-v3",
      "AdditionalParameters": [
        {"Key": "threshold", "Value": "0.35", "Type": "float1", "Comment": ""}
      ] }
  ]
}
```

响应：
```json
{
  "Success": true,
  "ErrorMessage": "Image successfully processed.",
  "Result": [
    { "ModelName": "SmilingWolf/wd-swinv2-tagger-v3",
      "Tags": [ {"Tag": "1girl", "Probability": 0.99}, {"Tag": "solo", "Probability": 0.98} ] }
  ]
}
```

**关键点**：服务端已按 threshold 过滤好，返回的即最终 tag 列表，客户端不需要再卡阈值。`Success=false` 时读 `ErrorMessage`。

---

## 2. 依赖与技术栈变更

`pubspec.yaml` 目前没有 HTTP 库，需新增 `http`。其余全用 Dart 标准库（`dart:convert` 的 `base64Encode`、`dart:io` 的 `File`、`dart:typed_data`）与已有的 `path`。

在 `dependencies:` 下加一行：
```yaml
  http: ^1.2.2
```

执行 `flutter pub get`。

---

## 3. 文件清单

| 操作 | 路径 | 说明 |
|------|------|------|
| 新建 | `lib/models/ai_tagger_models.dart` | 请求/响应 DTO（纯数据，不依赖 Flutter） |
| 新建 | `lib/services/ai_tagger_service.dart` | HTTP 客户端 service（纯 Dart，不依赖 Flutter） |
| 修改 | `lib/services/settings_service.dart` | 增加服务器地址/模型/阈值/tag 归一化设置的读写 |
| 修改 | `pubspec.yaml` | 增加 `http` 依赖 |

> service 与 models **刻意不 import Flutter**，方便未来单元测试 / 复用。

---

## 4. 完整代码

### 4.1 新建 `lib/models/ai_tagger_models.dart`

```dart
/// Data models for talking to the AiApiServer (the Python/Flask backend that
/// BooruDatasetTagManager uses for WD14-style image tagging).
///
/// These mirror the server's `server_dataclasses.py` JSON shapes 1:1. Field
/// names use the server's PascalCase keys on the wire; the Dart-side getters
/// are idiomatic camelCase. Nothing here imports Flutter — it is pure data.
library;

/// Mirrors the server's `ObjectDataType` enum. Only [imageByteArray] is used
/// by DataSetTrainingTool; [videoPath] exists for parity with the server.
enum AiDataType {
  imageByteArray(1),
  videoPath(2);

  const AiDataType(this.value);

  final int value;
}

/// One model advertised by `/getconfig` or `/listmodelsbytype`.
///
/// [modelName] is the exact key the server expects back in an interrogate
/// request. For WD taggers it is the full HuggingFace repo path, e.g.
/// `SmilingWolf/wd-swinv2-tagger-v3`.
class AiModelInfo {
  const AiModelInfo({
    required this.modelName,
    this.supportedVideo = false,
    this.repositoryLink = '',
  });

  final String modelName;
  final bool supportedVideo;
  final String repositoryLink;

  factory AiModelInfo.fromJson(Map<String, dynamic> json) => AiModelInfo(
        modelName: (json['ModelName'] as String?) ?? '',
        supportedVideo: (json['SupportedVideo'] as bool?) ?? false,
        repositoryLink: (json['RepositoryLink'] as String?) ?? '',
      );

  @override
  String toString() => modelName;
}

/// The `/getconfig` (and `/listmodelsbytype`) response: three model buckets.
///
/// For WD14 tagging you only care about [interrogators].
class AiServerConfig {
  const AiServerConfig({
    this.interrogators = const [],
    this.editors = const [],
    this.translators = const [],
  });

  final List<AiModelInfo> interrogators;
  final List<AiModelInfo> editors;
  final List<AiModelInfo> translators;

  factory AiServerConfig.fromJson(Map<String, dynamic> json) {
    List<AiModelInfo> parse(String key) => ((json[key] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(AiModelInfo.fromJson)
        .toList();

    return AiServerConfig(
      interrogators: parse('Interrogators'),
      editors: parse('Editors'),
      translators: parse('Translators'),
    );
  }
}

/// One tunable parameter of a model, as sent to `/interrogateimage` and as
/// returned by `/getmodelparams`.
///
/// [type] is the server's parameter type tag: `float1`, `int`, `string`,
/// `list`, `bool`, or `label`. WD taggers expose a single `threshold`
/// (type `float1`).
class AiModelParameter {
  const AiModelParameter({
    required this.key,
    required this.value,
    required this.type,
    this.comment = '',
  });

  final String key;
  final String value;
  final String type;
  final String comment;

  factory AiModelParameter.fromJson(Map<String, dynamic> json) =>
      AiModelParameter(
        key: (json['Key'] as String?) ?? '',
        value: (json['Value'] ?? '').toString(),
        type: (json['Type'] as String?) ?? '',
        comment: (json['Comment'] as String?) ?? '',
      );

  Map<String, dynamic> toJson() => {
        'Key': key,
        'Value': value,
        'Type': type,
        'Comment': comment,
      };
}

/// The `/getmodelparams` response. Use [threshold] to read a WD tagger's
/// default confidence threshold when present.
class AiModelParams {
  const AiModelParams({
    this.success = false,
    this.errorMessage = '',
    this.type = '',
    this.parameters = const [],
  });

  final bool success;
  final String errorMessage;

  /// The server-side model type, e.g. `wd`, `dd`, `florence2`.
  final String type;
  final List<AiModelParameter> parameters;

  factory AiModelParams.fromJson(Map<String, dynamic> json) => AiModelParams(
        success: (json['Success'] as bool?) ?? false,
        errorMessage: (json['ErrorMessage'] as String?) ?? '',
        type: (json['Type'] as String?) ?? '',
        parameters: ((json['Parameters'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(AiModelParameter.fromJson)
            .toList(),
      );

  /// The `threshold` parameter's value parsed as a double, or null if the
  /// model has no threshold parameter.
  double? get threshold {
    for (final p in parameters) {
      if (p.key == 'threshold') return double.tryParse(p.value);
    }
    return null;
  }
}

/// A model plus its parameters, as embedded in an interrogate request's
/// `Models` array.
class AiModelRequest {
  const AiModelRequest({
    required this.modelName,
    this.additionalParameters = const [],
  });

  final String modelName;
  final List<AiModelParameter> additionalParameters;

  /// Builds a WD14 tagger request. When [threshold] is given it is sent as a
  /// `float1` parameter; the server then filters tags below it before
  /// responding. Omit it to let the server use the model's default.
  factory AiModelRequest.wd({
    required String modelName,
    double? threshold,
  }) =>
      AiModelRequest(
        modelName: modelName,
        additionalParameters: [
          if (threshold != null)
            AiModelParameter(
              key: 'threshold',
              value: threshold.toString(),
              type: 'float1',
            ),
        ],
      );

  Map<String, dynamic> toJson() => {
        'ModelName': modelName,
        'AdditionalParameters':
            additionalParameters.map((e) => e.toJson()).toList(),
      };
}

/// A single predicted tag with its confidence, from an interrogate result.
class AiTag {
  const AiTag({required this.tag, required this.probability});

  final String tag;
  final double probability;

  factory AiTag.fromJson(Map<String, dynamic> json) => AiTag(
        tag: (json['Tag'] as String?) ?? '',
        probability: (json['Probability'] as num?)?.toDouble() ?? 0,
      );
}

/// The per-model block inside an interrogate response's `Result` array.
class AiModelResult {
  const AiModelResult({required this.modelName, this.tags = const []});

  final String modelName;
  final List<AiTag> tags;

  factory AiModelResult.fromJson(Map<String, dynamic> json) => AiModelResult(
        modelName: (json['ModelName'] as String?) ?? '',
        tags: ((json['Tags'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(AiTag.fromJson)
            .toList(),
      );
}

/// The `/interrogateimage` response.
class AiInterrogateResponse {
  const AiInterrogateResponse({
    this.success = false,
    this.errorMessage = '',
    this.results = const [],
  });

  final bool success;
  final String errorMessage;
  final List<AiModelResult> results;

  factory AiInterrogateResponse.fromJson(Map<String, dynamic> json) =>
      AiInterrogateResponse(
        success: (json['Success'] as bool?) ?? false,
        errorMessage: (json['ErrorMessage'] as String?) ?? '',
        results: ((json['Result'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(AiModelResult.fromJson)
            .toList(),
      );

  /// All tag strings across every model in this response, de-duplicated with
  /// original order preserved. The server has already applied each model's
  /// threshold, so these are final.
  List<String> get allTags {
    final seen = <String>{};
    final out = <String>[];
    for (final r in results) {
      for (final t in r.tags) {
        if (seen.add(t.tag)) out.add(t.tag);
      }
    }
    return out;
  }
}
```

### 4.2 新建 `lib/services/ai_tagger_service.dart`

```dart
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
```

### 4.3 修改 `lib/services/settings_service.dart`

在类 `SettingsService` 内、**结尾 `}` 之前**追加以下方法（保持文件其余部分不变）：

```dart
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
```

### 4.4 修改 `pubspec.yaml`

在 `dependencies:` 段内加入：
```yaml
  http: ^1.2.2
```
然后运行 `flutter pub get`。

---

## 5. 未来 UI 接入点（本阶段不实现，仅说明）

service 层与现有状态对接非常直接，供后续参考：

- **识别哪张图**：`DatasetState.selectedFile` 给出当前选中图片的 `File`。批量则遍历 `visibleFiles`。
- **tag 灌回哪里**：`EditorSession` 已有 `addTagsFromInput(String)`（自动去重、写回文本、触发 800ms 防抖自动保存）和 `applyTag(String)`。识别结果可以：
  ```dart
  final tags = await service.interrogateTags(serverUrl, session.image!, models: [
    AiModelRequest.wd(modelName: modelName, threshold: threshold),
  ]);
  session.addTagsFromInput(tags.join(', '));
  ```
- **服务器地址/模型/阈值**：从 `SettingsService` 读取（见 4.3）。
- **批量注意**：服务端有全局 `INTERROGATOR_LOCK`，同一时刻只处理一个请求，客户端**顺序调用**并显示进度即可，并发无收益。

---

## 6. 坑与注意事项

1. **下划线 vs 空格**：WD 原始 tag 是 `long_hair` 形式。是否转空格由客户端 `normalizeTag` 控制（默认转），不要依赖服务器的 `tagger_use_spaces` 设置，以免行为不一致。
2. **括号转义**：角色/表情 tag 常含括号，SDXL/kohya 训练一般需要 `\(` `\)`。用 `escapeParentheses` 开关控制，默认关，按你现有 pipeline 决定。
3. **首次请求很慢**：服务器第一次用某模型会去 HuggingFace 下载权重（数百 MB）再加载显存。因此 `requestTimeout` 默认给了 5 分钟；UI 层务必异步 + loading，不要卡界面。
4. **模型名必须精确匹配**：`ModelName` 要与 `/getconfig` 返回的完全一致（完整 HF 路径），不能简写。正确做法是启动/进设置时先 `/getconfig` 拉列表让用户选。
5. **DataType 传整数 1**：Dart 没有那个 Python 枚举，代码里已用 `AiDataType.imageByteArray.value == 1`。
6. **错误处理**：`AiTaggerService` 在传输失败或 `Success=false` 时抛 `AiTaggerException`，UI 捕获后提示即可；`ping()` 不抛异常，用于连接指示灯。
7. **服务未启动**：连接失败会以 `SocketException` → `AiTaggerException` 形式反馈，提示用户先启动 AiApiServer。

---

## 7. 待办清单（Claude Code 执行）

- [ ] 1. `pubspec.yaml` 增加 `http: ^1.2.2`，运行 `flutter pub get`。
- [ ] 2. 新建 `lib/models/ai_tagger_models.dart`（第 4.1 节完整内容）。
- [ ] 3. 新建 `lib/services/ai_tagger_service.dart`（第 4.2 节完整内容）。
- [ ] 4. 修改 `lib/services/settings_service.dart`，追加第 4.3 节的 AI 设置读写方法。
- [ ] 5. 运行 `dart analyze`（或 `flutter analyze`），确保无 error/warning。
- [ ] 6. （可选）写一个联调小测：启动 AiApiServer 后，临时 `main()` 或单元测试调用
       `AiTaggerService().getConfig('http://127.0.0.1:50051')` 打印模型列表，
       再对一张样图调用 `interrogateTags(...)` 打印 tag，验证端到端通路。
- [ ] 7. 确认未触碰任何 UI 文件（本阶段只做后台能力）。

---

## 8. 验证清单（完成标准）

- `flutter pub get` 成功，`http` 已解析。
- `flutter analyze` 对新增/修改文件零报错。
- `AiTaggerService` 三个端点方法签名与本文件一致，`models`/`service` 均不 import Flutter。
- 端到端联调（第 7 步第 6 项）能拿到模型列表并成功识别一张图（需本机已启动 AiApiServer）。
```
