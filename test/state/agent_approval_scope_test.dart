import 'dart:async';
import 'dart:io';

import 'package:dataset_training_tool/models/llm_models.dart';
import 'package:dataset_training_tool/services/settings_service.dart';
import 'package:dataset_training_tool/state/agent_chat_state.dart';
import 'package:dataset_training_tool/state/ai_tagger_state.dart';
import 'package:dataset_training_tool/state/app_state.dart';
import 'package:dataset_training_tool/state/dataset_state.dart';
import 'package:dataset_training_tool/state/tag_ops.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../agent/agent_session_test.dart' show FakeLlmClient;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final change in ['scope', 'caption', 'stop']) {
    test('pending approval refuses $change changes', () async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsService();
      final app = AppState(settings);
      await app.loadSettings();
      await app.updateLlmProviders([
        const LlmProvider(
          id: 'fake',
          name: 'Fake',
          models: [LlmModelConfig(id: 'fake', modelId: 'fake')],
        ),
      ]);
      final temp = await Directory.systemTemp.createTemp('approval_scope_');
      addTearDown(() => temp.delete(recursive: true));
      for (final folder in ['a', 'b']) {
        await Directory(p.join(temp.path, folder)).create();
        await File(p.join(temp.path, folder, '1.png')).writeAsBytes([1]);
        await File(
          p.join(temp.path, folder, '1.txt'),
        ).writeAsString('original');
      }
      await app.setBrowsingDirectory(temp.path);
      final dataset = DatasetState();
      await dataset.scan(
        directoryPath: temp.path,
        recursive: true,
        captionExtension: '.txt',
      );
      dataset.setSubdirectory('a');
      final ai = AiTaggerState(settings);
      final tags = TagOps(dataset: dataset);
      final client = FakeLlmClient([
        [
          ToolCallsReady([
            const ChatToolCall(
              id: 'write',
              name: 'edit_captions',
              argumentsJson: '{"add":["new"]}',
            ),
          ]),
          StreamDone(),
        ],
        [TextDelta('done'), StreamDone()],
      ]);
      final chat = AgentChatState(
        app: app,
        dataset: dataset,
        tagOps: tags,
        aiTagger: ai,
        clients: {LlmApiKind.openaiCompat: client},
      );
      addTearDown(chat.dispose);
      addTearDown(tags.dispose);
      addTearDown(ai.dispose);
      addTearDown(dataset.dispose);
      final pending = Completer<void>();
      chat.addListener(() {
        if (chat.pendingConfirm != null && !pending.isCompleted) {
          pending.complete();
        }
      });
      final run = chat.send('edit');
      await pending.future.timeout(const Duration(seconds: 5));
      if (change == 'scope') dataset.setSubdirectory('b');
      if (change == 'caption') {
        await File(
          p.join(temp.path, 'a', '1.txt'),
        ).writeAsString('external edit');
      }
      if (change == 'stop') {
        chat.stopRun();
      } else {
        chat.resolveConfirm(allow: true);
      }
      await run;
      expect(
        await File(p.join(temp.path, 'a', '1.txt')).readAsString(),
        change == 'caption' ? 'external edit' : 'original',
      );
      expect(
        await File(p.join(temp.path, 'b', '1.txt')).readAsString(),
        'original',
      );
      expect(chat.busy, false);
    });
  }
}
