import 'dart:convert';
import 'dart:typed_data';

import 'package:dataset_training_tool/services/ai_image_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'foreground request uses versioned byte contract and preserves PNG result',
    () async {
      final service = AiImageService(
        client: MockClient((request) async {
          expect(request.url.path, '/v1/imageprocessing/foreground');
          final body = jsonDecode(request.body) as Map;
          expect(body['version'], 1);
          expect(body['model'], 'rmbg');
          expect(base64Decode(body['image'] as String), [1, 2, 3]);
          return http.Response(
            jsonEncode({
              'version': 1,
              'mime_type': 'image/png',
              'coordinate_frame': 'exif_normalized_pixels',
              'image': base64Encode([4, 5]),
            }),
            200,
          );
        }),
      );
      addTearDown(service.dispose);
      expect(
        await service.foreground(
          'http://localhost/',
          'rmbg',
          Uint8List.fromList([1, 2, 3]),
        ),
        [4, 5],
      );
    },
  );
  test('rejects legacy opaque or unversioned image response', () async {
    final service = AiImageService(
      client: MockClient(
        (_) async => http.Response('{"Success":true,"Image":"AA=="}', 200),
      ),
    );
    addTearDown(service.dispose);
    await expectLater(
      service.foreground('http://localhost', 'rmbg', Uint8List(0)),
      throwsFormatException,
    );
  });
  test('discovery does not claim named object detection', () async {
    final service = AiImageService(
      client: MockClient((request) async {
        expect(request.url.path, '/v1/imageprocessing/capabilities');
        return http.Response(
          '{"version":1,"foreground_models":["rmbg"],"named_object_detection":false}',
          200,
        );
      }),
    );
    addTearDown(service.dispose);
    expect(await service.models('http://localhost'), ['rmbg']);
  });
}
