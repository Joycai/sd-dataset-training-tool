import 'package:flutter_test/flutter_test.dart';

import 'package:dataset_training_tool/models/llm_models.dart';
import 'package:dataset_training_tool/services/llm/llm_client.dart';
import 'package:dataset_training_tool/services/tag_ai_group.dart';

/// Answers each turn with the next scripted reply, in two deltas — a real
/// stream never hands a JSON array over in one piece.
class _FakeLlm implements LlmClient {
  _FakeLlm(this.replies);

  final List<String> replies;
  final List<List<ChatMessage>> sent = [];
  bool disposed = false;

  @override
  Stream<LlmStreamEvent> chat({
    required LlmProviderProfile profile,
    required List<ChatMessage> messages,
    List<AgentToolSpec> tools = const [],
    CancellationToken? cancel,
  }) async* {
    final reply = replies[sent.length.clamp(0, replies.length - 1)];
    sent.add(messages);
    final cut = reply.length ~/ 2;
    yield TextDelta(reply.substring(0, cut));
    yield TextDelta(reply.substring(cut));
    yield StreamDone();
  }

  @override
  Future<String?> probe(LlmProviderProfile profile) async => null;

  @override
  Future<List<String>> listModels(LlmProviderProfile profile) async => const [];

  @override
  void dispose() => disposed = true;
}

const _profile = LlmProviderProfile(id: 'p', name: 'test');

Future<List<TagGroupSuggestion>> ask(
  // ignore: library_private_types_in_public_api
  _FakeLlm llm, {
  required List<String> tags,
  List<String> groups = const ['服装'],
  Map<String, String> glosses = const {},
  int batchSize = 60,
  void Function(int, int)? onProgress,
}) => suggestTagGroupsWithLlm(
  profile: _profile,
  tags: tags,
  existingGroups: groups,
  glosses: glosses,
  batchSize: batchSize,
  client: llm,
  onProgress: onProgress,
);

void main() {
  test('a chunked JSON answer becomes suggestions', () async {
    final llm = _FakeLlm([
      '[{"tag":"boots","group":"鞋靴"},{"tag":"gloves","group":"服装"}]',
    ]);
    final out = await ask(llm, tags: ['boots', 'gloves']);
    expect(out.map((s) => s.tag), ['boots', 'gloves']);
    expect(out.map((s) => s.group), ['鞋靴', '服装']);
  });

  test('a fenced or prefaced answer still parses', () async {
    final llm = _FakeLlm([
      'Sure! Here you go:\n```json\n[{"tag":"boots","group":"鞋靴"}]\n```',
    ]);
    final out = await ask(llm, tags: ['boots']);
    expect(out.single.group, '鞋靴');
  });

  test('the answer is restricted to the tags that were asked about', () async {
    // A model that invents tags would otherwise file something the library
    // does not contain — and the caller would create a group for it.
    final llm = _FakeLlm([
      '[{"tag":"boots","group":"鞋靴"},{"tag":"never_asked","group":"X"}]',
    ]);
    final out = await ask(llm, tags: ['boots']);
    expect(out.map((s) => s.tag), ['boots']);
  });

  test('a tag answered in another spelling still lands', () async {
    final llm = _FakeLlm(['[{"tag":"ankle boots","group":"鞋靴"}]']);
    final out = await ask(llm, tags: ['ankle_boots']);
    // Reported under the library's own spelling, not the model's.
    expect(out.single.tag, 'ankle_boots');
  });

  test('empty groups and duplicates are dropped', () async {
    final llm = _FakeLlm([
      '[{"tag":"boots","group":""},{"tag":"gloves","group":"服装"},'
          '{"tag":"gloves","group":"其他"}]',
    ]);
    final out = await ask(llm, tags: ['boots', 'gloves']);
    expect(out.single.tag, 'gloves');
    expect(out.single.group, '服装');
  });

  test('suggestions come back in request order', () async {
    final llm = _FakeLlm([
      '[{"tag":"gloves","group":"服装"},{"tag":"boots","group":"鞋靴"}]',
    ]);
    final out = await ask(llm, tags: ['boots', 'gloves']);
    expect(out.map((s) => s.tag), ['boots', 'gloves']);
  });

  test('an unparseable batch is skipped, not fatal', () async {
    final llm = _FakeLlm([
      'I cannot help with that.',
      '[{"tag":"c","group":"G"}]',
    ]);
    final out = await ask(llm, tags: ['a', 'b', 'c', 'd'], batchSize: 2);
    expect(out.map((s) => s.tag), ['c']);
  });

  test('long tag lists are batched and reported', () async {
    final llm = _FakeLlm(['[]']);
    final progress = <int>[];
    await ask(
      llm,
      tags: [for (var i = 0; i < 25; i++) 't$i'],
      batchSize: 10,
      onProgress: (done, _) => progress.add(done),
    );
    expect(llm.sent.length, 3);
    expect(progress, [10, 20, 25]);
  });

  test('the prompt carries the existing groups and the glosses', () async {
    final llm = _FakeLlm(['[]']);
    await ask(
      llm,
      tags: ['boots'],
      groups: ['服装', '背景'],
      glosses: {'boots': '靴子'},
    );
    final user = llm.sent.single.last.parts.first.text!;
    expect(user, contains('服装'));
    expect(user, contains('背景'));
    expect(user, contains('靴子'));
  });

  test('an injected client is left for its owner to dispose', () async {
    final llm = _FakeLlm(['[]']);
    await ask(llm, tags: ['boots']);
    expect(llm.disposed, isFalse);
  });

  test('no tags means no request at all', () async {
    final llm = _FakeLlm(['[]']);
    expect(await ask(llm, tags: const []), isEmpty);
    expect(llm.sent, isEmpty);
  });
}
