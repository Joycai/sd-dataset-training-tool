import 'package:flutter_test/flutter_test.dart';

import 'package:dataset_training_tool/models/llm_models.dart';
import 'package:dataset_training_tool/services/llm/llm_client.dart';
import 'package:dataset_training_tool/services/tag_ai_translate.dart';

/// An LLM that says whatever the test tells it to, one delta per chunk.
///
/// Chunked on purpose: a real stream splits a short answer across several
/// deltas, and a translator that read only the first one would silently
/// truncate every gloss.
class _FakeLlm implements LlmClient {
  _FakeLlm(this.chunks);

  final List<String> chunks;
  List<ChatMessage>? sent;
  bool disposed = false;

  @override
  Stream<LlmStreamEvent> chat({
    required LlmProviderProfile profile,
    required List<ChatMessage> messages,
    List<AgentToolSpec> tools = const [],
    CancellationToken? cancel,
  }) async* {
    sent = messages;
    for (final chunk in chunks) {
      yield TextDelta(chunk);
    }
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

Future<String> translate(LlmClient llm, {String tag = 'long_hair'}) =>
    translateTagWithLlm(
      profile: _profile,
      tag: tag,
      languageCode: 'zh',
      client: llm,
    );

void main() {
  test('a chunked answer is reassembled', () async {
    expect(await translate(_FakeLlm(['长', '发'])), '长发');
  });

  test('the prompt names the tag and the target language', () async {
    final llm = _FakeLlm(['长发']);
    await translate(llm);
    final user = llm.sent!.last.parts.first.text!;
    expect(user, contains('long_hair'));
    expect(user, contains('zh'));
  });

  test('an injected client is left for its owner to dispose', () async {
    final llm = _FakeLlm(['长发']);
    await translate(llm);
    expect(llm.disposed, isFalse);
  });

  group('padding a model adds to a one-word answer', () {
    // Every one of these would otherwise land in the glossary verbatim and
    // render beside every chip carrying the tag.
    for (final (raw, tidy) in const [
      ('Translation: 长发', '长发'),
      ('"长发"', '长发'),
      ('「长发」', '长发'),
      ('长发。', '长发'),
      ('  长发  ', '长发'),
      ('长发\n(literally "long hair")', '长发'),
      ('\n\n长发', '长发'),
    ]) {
      test(raw.replaceAll('\n', r'\n'), () async {
        expect(await translate(_FakeLlm([raw])), tidy);
      });
    }
  });

  test('an over-long answer is cut rather than stored as prose', () async {
    final answer = await translate(_FakeLlm(['长' * 200]));
    expect(answer.length, lessThanOrEqualTo(60));
  });

  test(
    'a model that does not know the tag fails instead of guessing',
    () async {
      // "UNKNOWN" written into the glossary would look like a translation and
      // would never be revisited.
      expect(
        () => translate(_FakeLlm(['UNKNOWN'])),
        throwsA(isA<LlmException>()),
      );
      expect(() => translate(_FakeLlm(['   '])), throwsA(isA<LlmException>()));
    },
  );
}
