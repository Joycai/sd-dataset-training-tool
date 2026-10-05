import 'dart:io';
import 'dart:typed_data';

import 'package:dataset_training_tool/agent/agent_session.dart';
import 'package:dataset_training_tool/agent/agent_tools.dart';
import 'package:dataset_training_tool/agent/caption_edit_tools.dart';
import 'package:dataset_training_tool/agent/dataset_tools.dart';
import 'package:dataset_training_tool/agent/image_preprocess_tools.dart';
import 'package:dataset_training_tool/agent/media_tools.dart';
import 'package:dataset_training_tool/models/image_operation_plan.dart';
import 'package:dataset_training_tool/models/llm_models.dart';
import 'package:dataset_training_tool/services/dataset_store.dart';
import 'package:dataset_training_tool/services/settings_service.dart';
import 'package:dataset_training_tool/state/ai_tagger_state.dart';
import 'package:dataset_training_tool/state/dataset_state.dart';
import 'package:dataset_training_tool/state/image_operation_state.dart';
import 'package:dataset_training_tool/state/tag_ops.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'agent_session_test.dart' show FakeLlmClient;

class StopAfterWriteStore extends DatasetStore {
  void Function()? afterWrite;
  @override
  Future<void> writeCaption(String path, String text) async {
    await super.writeCaption(path, text);
    afterWrite?.call();
  }
}

void main() {
  test(
    'non-vision models receive preview metadata without image parts',
    () async {
      final dataset = DatasetState();
      final tags = TagOps(dataset: dataset);
      final state = ImageOperationState(
        dataset: dataset,
        tagOps: tags,
        serverUrl: () => '',
      );
      addTearDown(state.dispose);
      addTearDown(tags.dispose);
      addTearDown(dataset.dispose);
      state.previews['1-1'] = [
        ImagePreview('a.png', Uint8List(0), Uint8List(0), 10, 10),
      ];
      final result = await ToolRegistry(
        buildImagePreprocessTools(state, supportsVision: false),
      ).dispatch('preview_image_operations', '{"id":"1-1"}');
      expect(result.isError, false);
      expect(result.extraParts, isEmpty);
      expect(result.text, contains('a.png'));
    },
  );
  const profile = LlmProviderProfile(id: 'test', name: 'test', model: 'test');
  test(
    'cancellation during a caption batch preserves completed undo and stops writes',
    () async {
      final temp = await Directory.systemTemp.createTemp('agent_cancel_');
      addTearDown(() => temp.delete(recursive: true));
      for (var i = 0; i < 3; i++) {
        await File(p.join(temp.path, '$i.png')).writeAsBytes([1]);
        await File(p.join(temp.path, '$i.txt')).writeAsString('original');
      }
      final store = StopAfterWriteStore();
      final dataset = DatasetState(store: store);
      final ops = TagOps(dataset: dataset);
      addTearDown(dataset.dispose);
      addTearDown(ops.dispose);
      await dataset.scan(
        directoryPath: temp.path,
        recursive: false,
        captionExtension: '.txt',
      );
      final deps = DatasetToolsDeps(
        dataset: dataset,
        rootDir: () => temp.path,
        libraryTags: () => [],
        tagGroups: () => [],
      );
      final session = AgentSession(
        profile: profile,
        systemPrompt: 'test',
        client: FakeLlmClient([
          [
            ToolCallsReady([
              const ChatToolCall(
                id: '1',
                name: 'edit_captions',
                argumentsJson: '{"add":["new"]}',
              ),
            ]),
            StreamDone(),
          ],
        ]),
        registry: ToolRegistry(buildCaptionEditTools(deps, ops)),
      );
      store.afterWrite = session.stop;
      final events = await session.run('edit').toList();
      expect((events.last as AgentFinished).reason, AgentStopReason.cancelled);
      expect(
        await File(p.join(temp.path, '0.txt')).readAsString(),
        contains('new'),
      );
      expect(await File(p.join(temp.path, '1.txt')).readAsString(), 'original');
      expect(await File(p.join(temp.path, '2.txt')).readAsString(), 'original');
      expect(ops.canUndo, true);
      store.afterWrite = null;
      await ops.undo();
      expect(await File(p.join(temp.path, '0.txt')).readAsString(), 'original');
      expect(repairToolCallPairing(session.history), 0);
    },
  );
  test('stop during an approving callback prevents dispatch', () async {
    var writes = 0;
    late AgentSession session;
    session = AgentSession(
      profile: profile,
      systemPrompt: 'test',
      client: FakeLlmClient([
        [
          ToolCallsReady([
            const ChatToolCall(id: '1', name: 'write', argumentsJson: '{}'),
          ]),
          StreamDone(),
        ],
      ]),
      registry: ToolRegistry([
        AgentTool(
          isWrite: true,
          spec: const AgentToolSpec(
            name: 'write',
            description: 'write',
            parametersSchema: {},
          ),
          handler: (_) async {
            writes++;
            return toolOk({});
          },
        ),
      ]),
      confirmWrite: (_, _) async {
        session.stop();
        return true;
      },
    );
    final events = await session.run('edit').toList();
    expect(writes, 0);
    expect((events.last as AgentFinished).reason, AgentStopReason.cancelled);
    expect(repairToolCallPairing(session.history), 0);
  });
  test('all missing tagger inputs are a tool failure', () async {
    final dataset = DatasetState();
    final ai = AiTaggerState(SettingsService());
    addTearDown(dataset.dispose);
    addTearDown(ai.dispose);
    final deps = DatasetToolsDeps(
      dataset: dataset,
      rootDir: () => '/dataset',
      libraryTags: () => [],
      tagGroups: () => [],
    );
    final result = await ToolRegistry(
      buildTaggerTools(deps, ai),
    ).dispatch('run_wd_tagger', '{"paths":["missing.png"],"model":"test"}');
    expect(result.isError, true);
    expect(result.text, contains('"succeeded":0'));
  });
}
