import 'package:dataset_training_tool/models/llm_models.dart';
import 'package:dataset_training_tool/services/llm/llm_client.dart';
import 'package:dataset_training_tool/services/settings_service.dart';
import 'package:dataset_training_tool/state/agent_chat_state.dart';
import 'package:dataset_training_tool/state/ai_tagger_state.dart';
import 'package:dataset_training_tool/state/app_state.dart';
import 'package:dataset_training_tool/state/dataset_state.dart';
import 'package:dataset_training_tool/state/tag_ops.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FailingClient implements LlmClient {
  final seen = <LlmProviderProfile>[];
  final histories = <List<ChatMessage>>[];
  @override
  Stream<LlmStreamEvent> chat({
    required LlmProviderProfile profile,
    required List<ChatMessage> messages,
    List<AgentToolSpec> tools = const [],
    CancellationToken? cancel,
  }) {
    seen.add(profile);
    histories.add(List.of(messages));
    return Stream.error(LlmException('Connection failed'));
  }

  @override
  Future<String?> probe(LlmProviderProfile p) async => null;
  @override
  Future<List<String>> listModels(LlmProviderProfile p) async => [];
  @override
  void dispose() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final change in ['effort', 'protocol', 'key', 'removed', 'unchanged']) {
    test('retry after settings $change', () async {
      SharedPreferences.setMockInitialValues({});
      final app = AppState(SettingsService());
      await app.loadSettings();
      const provider = LlmProvider(
        id: 'p',
        name: 'p',
        models: [
          LlmModelConfig(
            id: 'm',
            modelId: 'gpt-6.1-sol',
            effort: LlmEffort.high,
          ),
        ],
      );
      await app.updateLlmProviders([provider]);
      final dataset = DatasetState();
      final ai = AiTaggerState(SettingsService());
      final ops = TagOps(dataset: dataset);
      final chatClient = FailingClient();
      final responsesClient = FailingClient();
      final chat = AgentChatState(
        app: app,
        dataset: dataset,
        tagOps: ops,
        aiTagger: ai,
        clients: {
          LlmApiKind.openaiCompat: chatClient,
          LlmApiKind.responses: responsesClient,
        },
      );
      addTearDown(() {
        chat.dispose();
        ops.dispose();
        ai.dispose();
        dataset.dispose();
        app.dispose();
      });
      await chat.send('original request');
      expect(chat.canRetry, isTrue);
      final updated = switch (change) {
        'effort' => provider.copyWith(
          models: [provider.models.single.copyWith(effort: LlmEffort.low)],
        ),
        'protocol' => provider.copyWith(
          models: [
            provider.models.single.copyWith(protocol: LlmApiKind.responses),
          ],
        ),
        'key' => provider.copyWith(apiKey: 'new-key'),
        _ => provider,
      };
      await app.updateLlmProviders(change == 'removed' ? [] : [updated]);
      await chat.retry();
      if (change == 'unchanged') {
        expect(chatClient.seen, hasLength(2));
        expect(chatClient.histories.last, chatClient.histories.first);
        return;
      }
      expect(chatClient.seen, hasLength(1));
      expect(responsesClient.seen, isEmpty);
      expect(chat.canRetry, isFalse);
      expect(
        chat.entries.last.noticeType,
        AgentNoticeType.retrySettingsChanged,
      );
      await chat.retry();
      expect(chatClient.seen, hasLength(1));
      if (change == 'removed') return;
      await chat.send('new request');
      final used = change == 'protocol' ? responsesClient : chatClient;
      expect(used.seen.last.toJson(), app.activeLlmProfile!.toJson());
      expect(
        used.histories.last
            .where((m) => m.role == ChatRole.user)
            .map((m) => m.text),
        ['new request'],
      );
    });
  }
}
