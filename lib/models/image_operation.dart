/// Validated, serializable image recipe. Coordinates are in EXIF-normalized
/// source pixels. Unknown options are rejected so typos cannot silently alter a
/// training dataset.
class ImageRecipe {
  ImageRecipe._(
    this.width,
    this.height,
    this.resizeMode,
    this.upscale,
    this.format,
    this.quality,
    this.background,
    this.crop,
    this.removeBackground,
    this.cropForeground,
    this.margin,
    this.model,
    this.prefix,
  );

  final int? width, height;
  final String resizeMode, format;
  final bool upscale, removeBackground, cropForeground;
  final int quality, margin;
  final List<int>? background, crop;
  final String? model, prefix;

  factory ImageRecipe.fromJson(Map<String, dynamic> json) {
    const keys = {
      'width',
      'height',
      'resize_mode',
      'upscale',
      'format',
      'quality',
      'background',
      'crop',
      'remove_background',
      'crop_foreground',
      'margin',
      'model',
      'prefix',
    };
    for (final key in json.keys) {
      if (!keys.contains(key)) {
        throw FormatException('Unknown recipe option: $key');
      }
    }
    int? integer(String key, int min, int max, [int? fallback]) {
      final value = json[key] ?? fallback;
      if (value == null) return null;
      if (value is! int || value < min || value > max) {
        throw FormatException('$key must be an integer from $min to $max');
      }
      return value;
    }

    bool flag(String key) {
      final value = json[key] ?? false;
      if (value is! bool) throw FormatException('$key must be a boolean');
      return value;
    }

    List<int>? numbers(String key, int count, int max) {
      final value = json[key];
      if (value == null) return null;
      if (value is! List ||
          value.length != count ||
          value.any((v) => v is! int || v < 0 || v > max)) {
        throw FormatException(
          '$key must contain $count integers from 0 to $max',
        );
      }
      return List<int>.unmodifiable(value.cast<int>());
    }

    final width = integer('width', 1, 16384);
    final height = integer('height', 1, 16384);
    if ((width == null) != (height == null)) {
      throw const FormatException('Specify both width and height');
    }
    if (width != null && width * height! > 40000000) {
      throw const FormatException('Output exceeds 40 megapixels');
    }
    final mode = json['resize_mode'] ?? 'fit';
    if (!['fit', 'crop', 'pad'].contains(mode)) {
      throw const FormatException('resize_mode must be fit, crop or pad');
    }
    final format = json['format'] ?? 'png';
    if (!['png', 'jpeg', 'keep'].contains(format)) {
      throw const FormatException('format must be png, jpeg or keep');
    }
    final crop = numbers('crop', 4, 100000);
    if (crop != null && (crop[2] == 0 || crop[3] == 0)) {
      throw const FormatException('Crop width and height must be positive');
    }
    final prefix = json['prefix'];
    if (prefix != null) validateImageName(prefix);
    final model = json['model'];
    if (model != null && (model is! String || model.trim().isEmpty)) {
      throw const FormatException('model must be a nonempty string');
    }
    final remove = flag('remove_background');
    final foreground = flag('crop_foreground');
    if ((remove || foreground) && model == null) {
      throw const FormatException('AI processing requires an explicit model');
    }
    if (foreground && crop != null) {
      throw const FormatException('Choose explicit crop or foreground crop');
    }
    if (format == 'keep' &&
        (width != null || crop != null || remove || foreground)) {
      throw const FormatException(
        'keep is only for byte-preserving copies/renames',
      );
    }
    return ImageRecipe._(
      width,
      height,
      mode as String,
      flag('upscale'),
      format as String,
      integer('quality', 1, 100, 95)!,
      numbers('background', 3, 255),
      crop,
      remove,
      foreground,
      integer('margin', 0, 4096, 32)!,
      model as String?,
      prefix as String?,
    );
  }

  bool get needsAi => removeBackground || cropForeground;
  Map<String, dynamic> toJson() => {
    if (width != null) 'width': width,
    if (height != null) 'height': height,
    'resize_mode': resizeMode,
    'upscale': upscale,
    'format': format,
    'quality': quality,
    if (background != null) 'background': background,
    if (crop != null) 'crop': crop,
    'remove_background': removeBackground,
    'crop_foreground': cropForeground,
    'margin': margin,
    if (model != null) 'model': model,
    if (prefix != null) 'prefix': prefix,
  };
}

void validateImageName(Object value) {
  if (value is! String ||
      value.isEmpty ||
      value.length > 100 ||
      !RegExp(r'^[a-zA-Z0-9_][a-zA-Z0-9_.-]*$').hasMatch(value) ||
      value.endsWith('.') ||
      value.contains('..') ||
      RegExp(
        r'^(con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\.|$)',
        caseSensitive: false,
      ).hasMatch(value)) {
    throw const FormatException(
      'Use a portable name of letters, digits, _, - or .',
    );
  }
}
