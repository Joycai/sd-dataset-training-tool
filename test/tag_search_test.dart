import 'package:flutter_test/flutter_test.dart';

import 'package:dataset_training_tool/utils/tag_search.dart';

void main() {
  setUp(resetTagSearchCache);

  test('an empty query matches everything', () {
    final matcher = TagSearchMatcher('   ');
    expect(matcher.isEmpty, isTrue);
    expect(matcher.matches('long_hair', '长发'), isTrue);
    expect(matcher.matches('anything'), isTrue);
  });

  test('the tag matches through underscore/space style', () {
    // The library, the captions and the user all spell tags differently; the
    // filter must not be the place that cares.
    expect(TagSearchMatcher('long hair').matches('long_hair'), isTrue);
    expect(TagSearchMatcher('long_hair').matches('long hair'), isTrue);
    expect(TagSearchMatcher('HAIR').matches('long_hair'), isTrue);
  });

  test('the translation is searchable', () {
    expect(TagSearchMatcher('长发').matches('long_hair', '长发'), isTrue);
    expect(TagSearchMatcher('长').matches('long_hair', '长发'), isTrue);
    expect(TagSearchMatcher('短').matches('long_hair', '长发'), isFalse);
  });

  test('full pinyin of the translation is searchable', () {
    expect(TagSearchMatcher('changfa').matches('long_hair', '长发'), isTrue);
    expect(TagSearchMatcher('chang').matches('long_hair', '长发'), isTrue);
    // Typed with a space, the way a pinyin keyboard segments it.
    expect(TagSearchMatcher('chang fa').matches('long_hair', '长发'), isTrue);
  });

  test('pinyin initials of the translation are searchable', () {
    expect(TagSearchMatcher('cf').matches('long_hair', '长发'), isTrue);
    expect(TagSearchMatcher('bslkw').matches('pantyhose', '白色连裤袜'), isTrue);
  });

  test('a mixed-script translation keeps its latin letters', () {
    expect(TagSearchMatcher('vzl').matches('v_neck', 'V字领'), isTrue);
    expect(TagSearchMatcher('V').matches('v_neck', 'V字领'), isTrue);
  });

  test('a tag with no translation only answers on its own spelling', () {
    final matcher = TagSearchMatcher('changfa');
    expect(matcher.matches('long_hair'), isFalse);
    expect(matcher.matches('long_hair', ''), isFalse);
  });

  test('a phrase reading beats the per-character one', () {
    // 长 alone reads "zhang"; the phrase table is what makes 长发 "changfa".
    expect(TagSearchMatcher('zhangfa').matches('long_hair', '长发'), isFalse);
  });
}
