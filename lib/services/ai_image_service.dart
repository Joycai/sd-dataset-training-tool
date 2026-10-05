import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../models/operation_context.dart';

class AiImageService {
  AiImageService({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;
  void dispose() => _client.close();

  Future<Map<String, dynamic>> _request(
    String server,
    String endpoint, [
    Map<String, dynamic>? body,
  ]) async {
    OperationContext.check();
    final request = http.AbortableRequest(
      body == null ? 'GET' : 'POST',
      Uri.parse(
        '${server.replaceFirst(RegExp(r'/+$'), '')}/v1/imageprocessing/$endpoint',
      ),
      abortTrigger: OperationContext.current?.cancelSignal,
    );
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    final response = await _client
        .send(request)
        .then(http.Response.fromStream)
        .timeout(Duration(seconds: body == null ? 10 : 300));
    OperationContext.check();
    if (response.statusCode != 200) {
      throw StateError(
        'AI image server returned ${response.statusCode}: ${response.body.substring(0, response.body.length.clamp(0, 500))}',
      );
    }
    final json = jsonDecode(response.body);
    if (json is! Map<String, dynamic> || json['version'] != 1) {
      throw const FormatException('Unsupported image processing response');
    }
    return json;
  }

  Future<List<String>> models(String server) async {
    final json = await _request(server, 'capabilities');
    return (json['foreground_models'] as List).cast<String>();
  }

  Future<Uint8List> foreground(
    String server,
    String model,
    Uint8List image,
  ) async {
    final json = await _request(server, 'foreground', {
      'version': 1,
      'model': model,
      'image': base64Encode(image),
    });
    if (json['mime_type'] != 'image/png' ||
        json['coordinate_frame'] != 'exif_normalized_pixels') {
      throw const FormatException(
        'AI image has an unsupported format or coordinate frame',
      );
    }
    return base64Decode(json['image'] as String);
  }
}
