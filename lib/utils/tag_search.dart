import 'package:pinyin/pinyin.dart';

import 'tag_text.dart';

/// Matches a library filter query against a tag and its translation.
///
/// A library big enough to need filtering is also a library the user no longer
/// remembers the English spelling of, so three surfaces answer one query:
/// the tag itself (folded through [tagLookupKey], so `long hair` finds
/// `long_hair`), the translation text, and the translation's pinyin — both the
/// full reading (`长发` → `changfa`) and the initials (`长发` → `cf`), which is
/// how a Chinese keyboard user actually types a half-remembered word.
///
/// Built once per filter pass, not once per tag: the query side is folded in
/// the constructor and the (expensive) pinyin of a translation is cached
/// process-wide, keyed by the translation text.
class TagSearchMatcher {
  TagSearchMatcher(String query)
    : _tagQuery = tagLookupKey(query),
      _rawQuery = query.trim().toLowerCase(),
      // Pinyin never contains spaces or underscores, so a query typed with
      // either would match nothing on that surface; folding them out lets
      // "chang fa" reach `changfa` too.
      _pinyinQuery = query.replaceAll(RegExp(r'[\s_]+'), '').toLowerCase();

  final String _tagQuery;
  final String _rawQuery;
  final String _pinyinQuery;

  bool get isEmpty => _rawQuery.isEmpty;

  /// Whether [tag] — optionally carrying the translation [gloss] — answers the
  /// query. An empty query matches everything.
  bool matches(String tag, [String? gloss]) {
    if (_rawQuery.isEmpty) return true;
    if (tagLookupKey(tag).contains(_tagQuery)) return true;
    if (gloss == null || gloss.isEmpty) return false;
    if (gloss.toLowerCase().contains(_rawQuery)) return true;
    if (_pinyinQuery.isEmpty) return false;
    final reading = _readingOf(gloss);
    return reading.full.contains(_pinyinQuery) ||
        reading.initials.contains(_pinyinQuery);
  }
}

/// A translation's two searchable pinyin forms.
typedef _Reading = ({String full, String initials});

/// Conversions are phrase-aware table lookups per character — cheap once,
/// wasteful on every keystroke over a few hundred tags. Translations are
/// short and few, so the cache is bounded in practice by the glossary size.
final Map<String, _Reading> _readingCache = {};

_Reading _readingOf(String gloss) {
  return _readingCache.putIfAbsent(gloss, () {
    // Non-Chinese characters pass through both helpers unchanged, so a mixed
    // gloss like "V字领" still yields "vziling" / "vzl".
    final full = PinyinHelper.getPinyinE(
      gloss,
      separator: '',
      defPinyin: '',
    ).toLowerCase();
    final initials = PinyinHelper.getShortPinyin(
      gloss,
    ).replaceAll(RegExp(r'\s+'), '').toLowerCase();
    return (full: full, initials: initials);
  });
}

/// Test seam: drops the memoized pinyin readings.
void resetTagSearchCache() => _readingCache.clear();
