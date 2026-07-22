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
    this.category = '',
    this.recommended = false,
    this.uncensored = false,
    this.legacy = false,
    this.vramGb = 0,
    this.description = '',
    this.advice = '',
  });

  final String modelName;
  final bool supportedVideo;
  final String repositoryLink;

  /// Picker grouping: `tag` (booru-style tagger) or `caption` (natural
  /// language). Empty on servers that predate the metadata fields — the
  /// picker then falls back to an ungrouped list.
  final String category;
  final bool recommended;
  final bool uncensored;
  final bool legacy;

  /// Rough VRAM estimate in GB; 0 means unknown.
  final double vramGb;
  final String description;
  final String advice;

  factory AiModelInfo.fromJson(Map<String, dynamic> json) => AiModelInfo(
        modelName: (json['ModelName'] as String?) ?? '',
        supportedVideo: (json['SupportedVideo'] as bool?) ?? false,
        repositoryLink: (json['RepositoryLink'] as String?) ?? '',
        category: (json['Category'] as String?) ?? '',
        recommended: (json['Recommended'] as bool?) ?? false,
        uncensored: (json['Uncensored'] as bool?) ?? false,
        legacy: (json['Legacy'] as bool?) ?? false,
        vramGb: (json['VramGB'] as num?)?.toDouble() ?? 0,
        description: (json['Description'] as String?) ?? '',
        advice: (json['Advice'] as String?) ?? '',
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
