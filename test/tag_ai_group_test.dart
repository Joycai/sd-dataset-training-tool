import 'package:flutter_test/flutter_test.dart';

import 'package:dataset_training_tool/models/llm_models.dart';
import 'package:dataset_training_tool/services/llm/llm_client.dart';
import 'package:dataset_training_tool/services/tag_ai_group.dart';

/// Answers each turn with the next scripted reply.
///
/// [asToolCall] picks the channel: the service asks for a `file_tags` call and
/// only falls back to assistant text, so both have to be exercised. Text
/// replies arrive in two deltas — a real stream never hands a JSON array over
/// in one piece.
class _FakeLlm implements LlmClient {
  _FakeLlm(
    this.replies, {
    this.asToolCall = false,
    this.finishReason = '',
    this.toolCallBatch,
  });

  /// Answers via the `file_tags` tool call instead of assistant text.
  _FakeLlm.toolCall(List<String> replies) : this(replies, asToolCall: true);

  /// Answers with several `file_tags` calls in the same turn, each carrying
  /// one entry of [batch] — a relay splitting the answer across parallel
  /// tool calls instead of a single one.
  _FakeLlm.toolCallBatch(List<String> batch)
    : this(const [], asToolCall: true, toolCallBatch: batch);

  final List<String> replies;
  final bool asToolCall;
  final String finishReason;
  final List<String>? toolCallBatch;
  final List<List<ChatMessage>> sent = [];
  final List<LlmProviderProfile> profiles = [];
  final List<List<AgentToolSpec>> offeredTools = [];
  bool disposed = false;

  @override
  Stream<LlmStreamEvent> chat({
    required LlmProviderProfile profile,
    required List<ChatMessage> messages,
    List<AgentToolSpec> tools = const [],
    CancellationToken? cancel,
  }) async* {
    final batch = toolCallBatch;
    if (batch != null) {
      sent.add(messages);
      profiles.add(profile);
      offeredTools.add(tools);
      yield ToolCallsReady([
        for (var i = 0; i < batch.length; i++)
          ChatToolCall(id: 't$i', name: 'file_tags', argumentsJson: batch[i]),
      ]);
      yield StreamDone(finishReason: finishReason);
      return;
    }
    final reply = replies[sent.length.clamp(0, replies.length - 1)];
    sent.add(messages);
    profiles.add(profile);
    offeredTools.add(tools);
    if (asToolCall) {
      yield ToolCallsReady([
        ChatToolCall(id: 't1', name: 'file_tags', argumentsJson: reply),
      ]);
    } else {
      final cut = reply.length ~/ 2;
      if (cut > 0) yield TextDelta(reply.substring(0, cut));
      if (reply.length > cut) yield TextDelta(reply.substring(cut));
    }
    yield StreamDone(finishReason: finishReason);
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
  void Function(TagGroupBatchProblem, String)? onBatchProblem,
}) => suggestTagGroupsWithLlm(
  profile: _profile,
  tags: tags,
  existingGroups: groups,
  glosses: glosses,
  batchSize: batchSize,
  client: llm,
  onProgress: onProgress,
  onBatchProblem: onBatchProblem,
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
    final problems = <TagGroupBatchProblem>[];
    final out = await ask(
      llm,
      tags: ['a', 'b', 'c', 'd'],
      batchSize: 2,
      onBatchProblem: (p, _) => problems.add(p),
    );
    expect(out.map((s) => s.tag), ['c']);
    // Skipped, but reported: an empty result that cannot say why is the bug
    // this callback exists for.
    expect(problems, [TagGroupBatchProblem.unparseable]);
  });

  group('the tool-call channel', () {
    test('the request offers the file_tags tool', () async {
      // Text-only answers are what a reasoning model behind a relay fails to
      // deliver; the tool call is the channel this feature relies on.
      final llm = _FakeLlm(['[]']);
      await ask(llm, tags: ['boots']);
      expect(llm.offeredTools.single.map((t) => t.name), ['file_tags']);
    });

    test('an answer arriving as tool arguments is read', () async {
      final llm = _FakeLlm.toolCall([
        '{"assignments":[{"tag":"boots","group":"鞋靴"}]}',
      ]);
      final out = await ask(llm, tags: ['boots']);
      expect(out.single.group, '鞋靴');
    });

    test('tool arguments win over any accompanying text', () async {
      final llm = _FakeLlm.toolCall([
        '{"assignments":[{"tag":"boots","group":"鞋靴"}]}',
      ]);
      final out = await ask(llm, tags: ['boots']);
      expect(out.single.tag, 'boots');
    });

    test(
      'a model that ignores the tool and answers in text still lands',
      () async {
        final llm = _FakeLlm(['[{"tag":"boots","group":"鞋靴"}]']);
        final out = await ask(llm, tags: ['boots']);
        expect(out.single.group, '鞋靴');
      },
    );

    test(
      'assignments split across parallel tool calls are all kept',
      () async {
        // A relay is free to answer with several parallel `file_tags` calls
        // instead of the one the prompt asks for; every call's assignments
        // must land, not just the first.
        final llm = _FakeLlm.toolCallBatch([
          '{"assignments":[{"tag":"boots","group":"鞋靴"}]}',
          '{"assignments":[{"tag":"gloves","group":"服装"}]}',
        ]);
        final out = await ask(llm, tags: ['boots', 'gloves']);
        expect(out.map((s) => s.tag), ['boots', 'gloves']);
        expect(out.map((s) => s.group), ['鞋靴', '服装']);
      },
    );

    test('truncated-by-budget is reported as its own problem', () async {
      // finish_reason "length" means the answer ran out of output tokens —
      // the user can fix that, but only if we say so.
      final llm = _FakeLlm([''], finishReason: 'length');
      final problems = <TagGroupBatchProblem>[];
      await ask(
        llm,
        tags: ['boots'],
        onBatchProblem: (p, _) => problems.add(p),
      );
      expect(problems, [TagGroupBatchProblem.truncated]);
    });
  });

  test('a reply with no text at all is reported as such', () async {
    // What a reasoning model does when max_tokens runs out during thinking.
    final llm = _FakeLlm(['']);
    final problems = <TagGroupBatchProblem>[];
    final out = await ask(
      llm,
      tags: ['a'],
      onBatchProblem: (p, _) => problems.add(p),
    );
    expect(out, isEmpty);
    expect(problems, [TagGroupBatchProblem.emptyReply]);
  });

  test('a bracket in the lead-in does not swallow the array', () async {
    // `indexOf('[') … lastIndexOf(']')` used to slice from "[the ones" here
    // and fail to decode, losing the whole batch.
    final llm = _FakeLlm([
      'I grouped [the ones I recognised] as follows:\n'
          '[{"tag":"boots","group":"鞋靴"}]',
    ]);
    final out = await ask(llm, tags: ['boots']);
    expect(out.single.group, '鞋靴');
  });

  test('an answer cut off mid-array keeps what did arrive', () async {
    // Truncation by the output limit: no closing bracket exists, so the
    // objects themselves are all there is to salvage.
    final llm = _FakeLlm([
      '[{"tag":"boots","group":"鞋靴"},{"tag":"gloves","group":"服装"},'
          '{"tag":"sm',
    ]);
    final out = await ask(llm, tags: ['boots', 'gloves', 'smile']);
    expect(out.map((s) => s.tag), ['boots', 'gloves']);
  });

  test('a bracket inside a group name does not break the scan', () async {
    final llm = _FakeLlm(['[{"tag":"boots","group":"鞋靴 [靴]"}]']);
    final out = await ask(llm, tags: ['boots']);
    expect(out.single.group, '鞋靴 [靴]');
  });

  test('an object-wrapped array is unwrapped', () async {
    final llm = _FakeLlm(['{"suggestions":[{"tag":"boots","group":"鞋靴"}]}']);
    final out = await ask(llm, tags: ['boots']);
    expect(out.single.group, '鞋靴');
  });

  test(
    'the request gets output headroom the chat profile may not have',
    () async {
      // A 4096-token budget is enough for the answer but not for a reasoning
      // model's thinking, which is how this call came back empty.
      final llm = _FakeLlm(['[]']);
      await ask(llm, tags: ['boots']);
      expect(llm.profiles.single.maxOutputTokens, greaterThanOrEqualTo(8192));
    },
  );

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

  test(
    'cancelling after a batch completes stops the remaining ones',
    () async {
      // A dialog the user closed mid-run has no other way to stop the loop
      // — without this, every remaining batch still goes out and spends
      // tokens for a result nobody is reading anymore.
      final llm = _FakeLlm([
        '[{"tag":"a","group":"G"}]',
        '[{"tag":"b","group":"G"}]',
        '[{"tag":"c","group":"G"}]',
      ]);
      var cancelled = false;
      final out = await suggestTagGroupsWithLlm(
        profile: _profile,
        tags: ['a', 'b', 'c'],
        existingGroups: const [],
        batchSize: 1,
        client: llm,
        isCancelled: () => cancelled,
        onBatchDone: (_, _, _) => cancelled = true,
      );
      expect(out.map((s) => s.tag), ['a']);
      expect(llm.sent, hasLength(1));
    },
  );
}
