/// The assistant's tag-glossary tools: list what needs translating, look a tag
/// up on danbooru, write translations in bulk.
///
/// These tools touch no caption file. They write only the UI-only glossary, so
/// the worst a bad run can do is show wrong words next to the right tags — and
/// [TagTranslationSource.llm] is recorded on every entry, so the whole run can
/// be cleared in one action from the dictionary manager. That is why they are
/// not behind the write-confirmation gate: a five-hundred-tag translation pass
/// is unusable if every batch needs a click, and the damage it can do is
/// reversible in one.
library;

import '../../models/tag_translation.dart';
import '../../state/dataset_state.dart';
import '../../utils/tag_text.dart';
import '../danbooru_api.dart';
import '../tag_dictionary_service.dart';
import '../tag_translation_service.dart';
import 'agent_tools.dart';

class TagTranslationToolsDeps {
  const TagTranslationToolsDeps({
    required this.glossary,
    required this.dictionary,
    required this.dataset,
    required this.libraryTags,
    this.api,
  });

  final TagTranslationService glossary;
  final TagDictionaryService dictionary;

  /// Read for its tag statistics, which honour the active subdirectory scope
  /// like every other tool's view of the dataset.
  final DatasetState dataset;

  final List<String> Function() libraryTags;

  /// Injectable for tests; defaults to the real danbooru client.
  final DanbooruApi? api;
}

/// Most entries one `write_tag_translations` call accepts.
///
/// Generous on purpose. The failure mode this avoids is the one that sank
/// per-image tag reordering: a tool that handles one item at a time turns a
/// few-hundred-item job into a few hundred round trips, and the run dies of
/// context exhaustion long before it finishes. One call per few hundred tags
/// is the shape that actually completes.
const maxTranslationEntries = 200;

/// Most tags one `list_tag_translations` call returns.
const _maxListed = 400;

/// Most danbooru lookups one conversation may make.
///
/// A model asked to translate a thousand tags will happily call the lookup a
/// thousand times. Danbooru asks API clients to go easy, and this app must not
/// turn one user's request into a scrape — past this point the model is told to
/// fall back on its own knowledge, which is what it would do for common tags
/// anyway.
const maxDanbooruLookupsPerSession = 60;

List<AgentTool> buildTagTranslationTools(TagTranslationToolsDeps deps) {
  final api = deps.api ?? DanbooruApi();
  // Per-session, because the builder runs once per conversation.
  var lookupsUsed = 0;

  /// Everything known about one tag, for the list tool's rows.
  Map<String, Object?> describe(String tag, {int? images}) {
    final entry = deps.dictionary.lookup(tag);
    final translation = deps.glossary.lookup(tag);
    return {
      'tag': tag,
      'images': ?images,
      if (entry != null) ...{
        'category': entry.category.name,
        if (entry.postCount > 0) 'post_count': entry.postCount,
      },
      if (translation != null) ...{
        'translation': translation.text,
        'note': ?translation.note,
        'source': translation.source.id,
      },
    };
  }

  return [
    AgentTool(
      spec: const AgentToolSpec(
        name: 'list_tag_translations',
        description:
            'Tags and their translations in the glossary for the app\'s '
            'current language. Translations are shown next to tags in the '
            'UI only — they are never written into a caption file.\n'
            'Defaults to the tags this dataset actually uses that have no '
            'translation yet, busiest first: those are the ones the user '
            'sees. Call this first to find the work, and again at the end '
            'to confirm what is left.',
        parametersSchema: {
          'type': 'object',
          'properties': {
            'scope': {
              'type': 'string',
              'enum': ['dataset', 'library', 'dictionary'],
              'description':
                  '"dataset" (default): tags used by images in the current '
                  'scope, most-used first. "library": the user\'s curated '
                  'tag library. "dictionary": the most popular danbooru '
                  'tags overall — for seeding a glossary from nothing, not '
                  'for a dataset that is already tagged.',
            },
            'only_missing': {
              'type': 'boolean',
              'description':
                  'Default true — list only tags with no translation. Set '
                  'false to review existing ones (each row then carries its '
                  'translation, note and source).',
            },
            'tags': {
              'type': 'array',
              'items': {'type': 'string'},
              'description':
                  'Look up these specific tags instead of a scope. Ignores '
                  'only_missing — every tag asked for comes back, whether '
                  'or not it is translated.',
            },
            'limit': {
              'type': 'integer',
              'description': 'Max rows to return; default 100, max 400.',
            },
          },
        },
      ),
      handler: (args) async {
        final glossary = deps.glossary;
        final limit = optInt(args, 'limit', fallback: 100, min: 1, max: _maxListed);
        final asked = optStringList(args, 'tags');

        if (asked.isNotEmpty) {
          return toolOk({
            'locale': glossary.languageCode,
            'tags': [for (final tag in asked.take(limit)) describe(tag)],
          });
        }

        final onlyMissing = optBool(args, 'only_missing', fallback: true);
        final scope = optString(args, 'scope') ?? 'dataset';
        bool wanted(String tag) => !onlyMissing || !glossary.has(tag);

        final List<Map<String, Object?>> rows;
        final int totalMatching;
        switch (scope) {
          case 'library':
            final tags = deps.libraryTags().where(wanted).toList();
            totalMatching = tags.length;
            rows = [for (final tag in tags.take(limit)) describe(tag)];
          case 'dictionary':
            // Entries are already popularity-descending, so this is a prefix
            // scan rather than a sort of a hundred thousand rows.
            final picked = <Map<String, Object?>>[];
            var seen = 0;
            for (final entry in deps.dictionary.allEntries) {
              if (!wanted(entry.name)) continue;
              seen++;
              if (picked.length < limit) picked.add(describe(entry.name));
              // The dictionary's tail is endless; counting all of it says
              // nothing useful and costs a full pass.
              if (seen >= _maxListed * 4) break;
            }
            totalMatching = seen;
            rows = picked;
          default:
            // datasetTags is already sorted by usage and honours the active
            // subdirectory scope, like every other tool's view.
            final tags = [
              for (final t in deps.dataset.datasetTags)
                if (wanted(t.tag)) t,
            ];
            totalMatching = tags.length;
            rows = [
              for (final t in tags.take(limit)) describe(t.tag, images: t.count),
            ];
        }

        return toolOk({
          'locale': glossary.languageCode,
          'scope': scope,
          'only_missing': onlyMissing,
          'translated_total': glossary.count,
          'matching': totalMatching,
          'returned': rows.length,
          'tags': rows,
        });
      },
    ),

    AgentTool(
      spec: const AgentToolSpec(
        name: 'fetch_danbooru_tag',
        description:
            'What danbooru itself records about a tag: category, post '
            'count, wiki summary, and other_names — the names danbooru '
            'lists for it in other languages, usually Japanese.\n'
            'Use it for characters, copyrights and artists, where the '
            'right answer is a proper name you must not invent: '
            'other_names is a given name, not a guess. Ordinary '
            'descriptive tags (long_hair, sitting) need no lookup. '
            'Reads danbooru\'s public API and is rate-limited — the '
            'conversation gets a fixed budget of these, so spend them on '
            'the tags you cannot translate from your own knowledge.',
        parametersSchema: {
          'type': 'object',
          'properties': {
            'tags': {
              'type': 'array',
              'items': {'type': 'string'},
              'description': 'Tag names to look up; at most 5 per call.',
            },
          },
          'required': ['tags'],
        },
      ),
      handler: (args) async {
        final tags = requireStringList(args, 'tags', maxLength: 5);
        final remaining = maxDanbooruLookupsPerSession - lookupsUsed;
        if (remaining <= 0) {
          return toolError(
            'danbooru lookup budget for this conversation is used up '
            '($maxDanbooruLookupsPerSession requests). Translate the '
            'remaining tags from your own knowledge, or ask the user to '
            'look specific ones up in the dictionary manager.',
          );
        }

        final results = <Map<String, Object?>>[];
        for (final tag in tags.take(remaining)) {
          lookupsUsed++;
          try {
            final info = await api.fetch(tag);
            results.add({
              'tag': info.name,
              'known_to_danbooru': info.knownToDanbooru,
              if (info.category != null) 'category': info.category!.name,
              if (info.postCount > 0) 'post_count': info.postCount,
              if (info.otherNames.isNotEmpty) 'other_names': info.otherNames,
              if (info.wikiExcerpt != null) 'wiki': info.wikiExcerpt,
            });
          } on DanbooruApiException catch (e) {
            // One bad tag must not fail the batch; the model needs to know
            // which one so it can move on rather than retry blindly.
            results.add({'tag': tag, 'error': e.message});
          }
        }
        return toolOk({
          'results': results,
          'lookups_remaining': maxDanbooruLookupsPerSession - lookupsUsed,
        });
      },
    ),

    AgentTool(
      spec: const AgentToolSpec(
        name: 'write_tag_translations',
        description:
            'Write translations into the glossary for the app\'s current '
            'language, up to $maxTranslationEntries per call. Send them in '
            'batches this size — never one call per tag.\n'
            'This is an upsert: tags not mentioned are untouched, and by '
            'default a tag that already has a translation is skipped '
            'rather than overwritten, so a bulk pass cannot destroy what '
            'the user wrote by hand. Writes no caption files; the user can '
            'clear every translation from this conversation in one action.',
        parametersSchema: {
          'type': 'object',
          'properties': {
            'entries': {
              'type': 'array',
              'description': 'Up to $maxTranslationEntries translations.',
              'items': {
                'type': 'object',
                'properties': {
                  'tag': {
                    'type': 'string',
                    'description':
                        'The tag, in danbooru spelling (long_hair). Any '
                        'caption style is accepted and normalized.',
                  },
                  'translation': {
                    'type': 'string',
                    'description':
                        'Short — it is rendered beside the tag on a chip. A '
                        'few characters, not a sentence.',
                  },
                  'note': {
                    'type': 'string',
                    'description':
                        'Optional longer gloss, for when the translation '
                        'alone is ambiguous. Shown in tooltips only.',
                  },
                },
                'required': ['tag', 'translation'],
              },
            },
            'overwrite': {
              'type': 'boolean',
              'description':
                  'Default false. Set true only when the user asked you to '
                  'redo translations that already exist.',
            },
          },
          'required': ['entries'],
        },
      ),
      handler: (args) async {
        final raw = args['entries'];
        if (raw is! List || raw.isEmpty) {
          throw ToolArgError('"entries" must be a non-empty array of objects');
        }
        if (raw.length > maxTranslationEntries) {
          throw ToolArgError(
            '"entries" accepts at most $maxTranslationEntries items per call; '
            'got ${raw.length}. Split the batch.',
          );
        }

        final items = <TagTranslation>[];
        final rejected = <Map<String, Object?>>[];
        for (final element in raw) {
          if (element is! Map) {
            rejected.add({'entry': '$element', 'reason': 'not an object'});
            continue;
          }
          final tag = '${element['tag'] ?? ''}'.trim();
          final text = '${element['translation'] ?? ''}'.trim();
          if (tag.isEmpty || text.isEmpty) {
            rejected.add({
              'tag': tag,
              'reason': 'tag and translation are both required',
            });
            continue;
          }
          final note = '${element['note'] ?? ''}'.trim();
          items.add(
            TagTranslation(
              tag: danbooruTagName(tag),
              text: text,
              note: note.isEmpty ? null : note,
              // Always llm, whatever the model claims: this is the flag the
              // user's "clear AI translations" action keys on, so it is not
              // the model's to set.
              source: TagTranslationSource.llm,
            ),
          );
        }

        final overwrite = optBool(args, 'overwrite');
        final (written, skipped) = await deps.glossary.upsertAll(
          items,
          overwrite: overwrite,
        );
        return toolOk({
          'locale': deps.glossary.languageCode,
          'written': written,
          'skipped_existing': skipped,
          if (rejected.isNotEmpty) 'rejected': rejected,
          'translated_total': deps.glossary.count,
        });
      },
    ),
  ];
}
