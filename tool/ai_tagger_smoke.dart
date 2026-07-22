/// One-off smoke test for AiTaggerService against a locally running
/// AiApiServer. Run with:  dart run tool/ai_tagger_smoke.dart [imagePath]
///
/// Not part of the app; pure Dart, safe to delete.
import 'dart:io';

import 'package:dataset_training_tool/models/ai_tagger_models.dart';
import 'package:dataset_training_tool/services/ai_tagger_service.dart';

Future<void> main(List<String> args) async {
  const baseUrl = 'http://127.0.0.1:50051';
  final imagePath = args.isNotEmpty ? args.first : 'assets/icon/icon.png';
  final service = AiTaggerService();

  try {
    // 1. ping
    final alive = await service.ping(baseUrl);
    print('[1] ping: $alive');
    if (!alive) {
      print('Server unreachable, aborting.');
      return;
    }

    // 2. list taggers
    final taggers = await service.listTaggers(baseUrl);
    print('[2] interrogators: ${taggers.length}');
    final wd = taggers
        .where((m) => m.modelName.contains('wd-swinv2-tagger-v3'))
        .toList();
    if (wd.isEmpty) {
      print('No wd-swinv2-tagger-v3 on server, aborting.');
      return;
    }
    final model = wd.first.modelName;
    print('    using: $model');

    // 3. model params
    final params = await service.getModelParams(baseUrl, model);
    print('[3] getmodelparams: success=${params.success} '
        'type=${params.type} threshold=${params.threshold}');

    // 4. interrogate
    print('[4] interrogating $imagePath '
        '(first call may download/load the model — please wait)...');
    final sw = Stopwatch()..start();
    final tags = await service.interrogateTags(
      baseUrl,
      File(imagePath),
      models: [
        AiModelRequest.wd(modelName: model, threshold: params.threshold),
      ],
    );
    sw.stop();
    print('    done in ${sw.elapsed.inSeconds}s, ${tags.length} tags:');
    print('    ${tags.join(', ')}');
  } on AiTaggerException catch (e) {
    print('AiTaggerException: $e');
    exitCode = 1;
  } finally {
    service.dispose();
  }
}
