import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dataset_training_tool/models/caption_type.dart';
import 'package:dataset_training_tool/services/ai_tagger_service.dart';
import 'package:dataset_training_tool/services/settings_service.dart';
import 'package:dataset_training_tool/state/ai_tagger_state.dart';
import 'package:dataset_training_tool/state/batch_tag_state.dart';
import 'package:dataset_training_tool/state/dataset_state.dart';

/// Prose captions are described by a caption model instead of tagged, and
/// JSON captions have no batch path at all. Before this, both were parsed as
/// comma-separated tags and written back as one line, which destroyed them.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late DatasetState dataset;
  late AiTaggerState ai;
  late List<Map<String, dynamic>> sentRequests;

  /// What the fake server answers every interrogation with; set by
  /// [buildState] so one client serves both states below.
  late String description;
  late MockClient client;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('batch_prose_test');
    dataset = DatasetState();
    sentRequests = [];
    description = '';
    client = MockClient((request) async {
      Map<String, dynamic> body;
      if (request.url.path == '/getconfig') {
        body = {
          'Interrogators': [
            {'ModelName': 'wd-tagger', 'Category': 'tag'},
            {'ModelName': 'joycaption', 'Category': 'caption'},
          ],
        };
      } else {
        sentRequests.add(jsonDecode(request.body) as Map<String, dynamic>);
        body = {
          'Success': true,
          'ErrorMessage': '',
          'Result': [
            {
              'ModelName': 'joycaption',
              'Tags': [
                {'Tag': description, 'Probability': 1.0},
              ],
            },
          ],
        };
      }
      return http.Response(
        jsonEncode(body),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    // The AI state fetches the model list through its own service, and the
    // category it reads there is what decides whether a prose run is allowed
    // — so it has to talk to the same fake server as the batch.
    ai = AiTaggerState(
      SettingsService(),
      service: AiTaggerService(client: client),
    );
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  Future<File> addImage(
    String name, {
    required String caption,
    String extension = '.ntxt',
  }) async {
    final image = File('${tempDir.path}/$name.png');
    await image.writeAsBytes([1, 2, 3]);
    await File('${tempDir.path}/$name$extension').writeAsString(caption);
    return image;
  }

  Future<void> scan({
    String extension = '.ntxt',
    CaptionFormat format = CaptionFormat.prose,
  }) => dataset.scan(
    directoryPath: tempDir.path,
    recursive: false,
    captionExtension: extension,
    captionFormat: format,
  );

  /// A batch state talking to the fake server, which answers every
  /// interrogation with [describeAs].
  BatchTagState buildState({required String describeAs}) {
    description = describeAs;
    return BatchTagState(
      dataset: dataset,
      ai: ai,
      settings: SettingsService(),
      service: AiTaggerService(client: client),
    );
  }

  test('append adds the described sentences, keeping what is there', () async {
    final img = await addImage('a', caption: 'A girl smiles.');
    await scan();
    await ai.setModelName('joycaption');
    final state = buildState(
      describeAs: 'A girl smiles. She wears a red hat, outdoors.',
    );

    final ok = await state.run(files: [img], operationLabel: 'batch');

    expect(ok, isTrue);
    expect(state.changed, 1);
    // The sentence the caption already had is not written twice, and the
    // comma inside the new one does not split it into two.
    expect(
      await File('${tempDir.path}/a.ntxt').readAsString(),
      'A girl smiles. She wears a red hat, outdoors.',
    );
    state.dispose();
  });

  test('a re-run over an already described caption changes nothing', () async {
    final img = await addImage('a', caption: 'A girl smiles.');
    await scan();
    await ai.setModelName('joycaption');
    final state = buildState(describeAs: 'A girl smiles.');

    await state.run(files: [img], operationLabel: 'batch');

    expect(state.changed, 0);
    expect(state.failed, 0);
    state.dispose();
  });

  test('overwrite replaces the whole caption', () async {
    final img = await addImage('a', caption: 'An old description.');
    await scan();
    await ai.setModelName('joycaption');
    final state = buildState(describeAs: 'A girl smiles.');
    await state.setMode(BatchTagMode.overwrite);

    await state.run(files: [img], operationLabel: 'batch');

    expect(
      await File('${tempDir.path}/a.ntxt').readAsString(),
      'A girl smiles.',
    );
    state.dispose();
  });

  test(
    'no threshold is sent, and the tag-only modes fall back to append',
    () async {
      final img = await addImage('a', caption: 'A girl smiles.');
      await scan();
      await ai.setModelName('joycaption');
      await ai.setThreshold(0.42);
      final state = buildState(describeAs: 'Outdoors, at noon.');
      // Compare mode and character sheets are tag concepts; a prose run must
      // not silently become one of them.
      await state.setMode(BatchTagMode.recognizeOnly);
      expect(state.effectiveMode, BatchTagMode.append);

      await state.run(files: [img], operationLabel: 'batch');

      final models = sentRequests.single['Models'] as List;
      expect((models.single as Map)['AdditionalParameters'], isEmpty);
      expect(
        await File('${tempDir.path}/a.ntxt').readAsString(),
        'A girl smiles. Outdoors, at noon.',
      );
      // The persisted choice survives for whenever a tag type is active again.
      expect(state.mode, BatchTagMode.recognizeOnly);
      state.dispose();
    },
  );

  test('an empty answer fails the file instead of erasing it', () async {
    final img = await addImage('a', caption: 'Keep me.');
    await scan();
    await ai.setModelName('joycaption');
    final state = buildState(describeAs: '   ');
    await state.setMode(BatchTagMode.overwrite);

    await state.run(files: [img], operationLabel: 'batch');

    expect(state.failed, 1);
    expect(state.changed, 0);
    expect(await File('${tempDir.path}/a.ntxt').readAsString(), 'Keep me.');
    state.dispose();
  });

  test('a tagger model is refused before any image is touched', () async {
    final img = await addImage('a', caption: 'Keep me.');
    await scan();
    final state = buildState(describeAs: '1girl, smile');
    await ai.refreshModels();
    await ai.setModelName('wd-tagger');

    final ok = await state.run(files: [img], operationLabel: 'batch');

    expect(ok, isFalse);
    expect(sentRequests, isEmpty);
    expect(state.lastError, contains('caption model'));
    expect(await File('${tempDir.path}/a.ntxt').readAsString(), 'Keep me.');
    state.dispose();
  });

  test('a JSON caption type is refused outright', () async {
    const document = '{"tags": ["1girl", "smile"]}';
    final img = await addImage('a', caption: document, extension: '.json');
    await scan(extension: '.json', format: CaptionFormat.json);
    await ai.setModelName('joycaption');
    final state = buildState(describeAs: 'A girl smiles.');

    final ok = await state.run(files: [img], operationLabel: 'batch');

    expect(ok, isFalse);
    expect(sentRequests, isEmpty);
    // The document is intact — the tag merge would have written it back as a
    // comma-separated line.
    expect(await File('${tempDir.path}/a.json').readAsString(), document);
    state.dispose();
  });
}
