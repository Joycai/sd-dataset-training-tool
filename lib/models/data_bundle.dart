/// The transfer format behind settings' "export / import data": one JSON file
/// carrying the settings a user builds up by hand, so a new machine — or a
/// reinstall — can be brought back to where they left off.
///
/// Pure data. Collecting a bundle from the running app and applying one to it
/// live in `services/data_transfer.dart`; this file only knows the layout.
///
/// Deliberately *not* in the file: anything the app can fetch or regenerate on
/// its own — the bundled WD label file, the downloaded danbooru dictionary,
/// thumbnails, window geometry, the open dataset. A backup of those would be
/// megabytes of data that a single button already restores.
library;

import 'dart:convert';

import 'llm_models.dart';
import 'prompt_preset.dart';
import 'tag_dictionary.dart';
import 'tag_group.dart';
import 'tag_translation.dart';

/// One independently selectable part of a bundle.
///
/// A section is either wholly present in the file or wholly absent; the picker
/// lets the user drop the ones they do not want on either end of the trip.
enum DataSection {
  /// LLM providers and their models, optionally including API keys.
  llm('llm'),

  /// The tag library: groups, their tags, hand-added dictionary entries and
  /// every translation glossary on disk.
  tagLibrary('tagLibrary'),

  /// The assistant's saved prompts.
  promptPresets('promptPresets');

  const DataSection(this.key);

  /// The bundle's top-level object key. Stable — never rename these.
  final String key;
}

/// How an import resolves a collision with something already configured.
///
/// Neither mode ever deletes: an import can only add to what is here, or
/// overwrite the value of something the file also carries. Wiping the local
/// side is left to the per-area "clear" actions, where the user can see what
/// they are throwing away.
enum DataImportMode {
  /// The local value wins; only what is missing gets added.
  merge,

  /// The file's value wins for anything it names.
  overwrite,
}

/// The tag library half of a bundle.
class TagLibraryBundle {
  const TagLibraryBundle({
    this.groups = const [],
    this.ungrouped = const [],
    this.customTags = const [],
    this.translations = const {},
    this.danbooruMeta = const {},
  });

  /// Groups with the tags they hold. Ids are local handles and are not
  /// transferred — import matches groups by name, exactly as the tag panel's
  /// own JSON import does.
  final List<TagGroup> groups;

  /// Library tags belonging to no group.
  final List<String> ungrouped;

  /// The user's hand-added dictionary entries (`custom_tags.json`).
  final List<TagDictionaryEntry> customTags;

  /// Language code -> that language's glossary. Every glossary on disk is
  /// carried, not just the active one: the app language is a display choice
  /// and losing the other languages on a restore would be silent data loss.
  final Map<String, List<TagTranslation>> translations;

  /// What danbooru answered about each looked-up tag (`danbooru_meta.json`),
  /// carried verbatim in that file's own `entries` layout — including the
  /// "not on danbooru" marks a batch update skips by. Kept raw here so the
  /// layout stays owned by the meta service, which validates it on both ends.
  final Map<String, dynamic> danbooruMeta;

  bool get isEmpty =>
      groups.isEmpty &&
      ungrouped.isEmpty &&
      customTags.isEmpty &&
      translations.isEmpty &&
      danbooruMeta.isEmpty;

  /// Every library tag, grouped or not.
  int get tagCount =>
      ungrouped.length + groups.fold(0, (sum, g) => sum + g.tags.length);

  int get translationCount =>
      translations.values.fold(0, (sum, list) => sum + list.length);

  int get danbooruMetaCount => danbooruMeta.length;

  Map<String, dynamic> toJson() => {
    'groups': [
      for (final g in groups) {'name': g.name, 'color': g.color, 'tags': g.tags},
    ],
    'ungrouped': ungrouped,
    'customTags': [for (final e in customTags) e.toJson()],
    'translations': {
      for (final entry in translations.entries)
        entry.key: {for (final t in entry.value) t.tag: t.toJson()},
    },
    if (danbooruMeta.isNotEmpty) 'danbooruMeta': danbooruMeta,
  };

  /// Tolerant by design: a bundle with one unreadable part should still
  /// restore the rest, so every field falls back to empty rather than throwing.
  factory TagLibraryBundle.fromJson(Map<String, dynamic> json) {
    return TagLibraryBundle(
      groups: [
        for (final raw in _listOf(json['groups']))
          if (raw is Map && raw['name'] is String)
            TagGroup(
              // Placeholder: import matches by name and mints its own id.
              id: '',
              name: raw['name'] as String,
              color: (raw['color'] as num?)?.toInt() ?? kTagGroupPresetColors[0],
              tags: _stringsOf(raw['tags']),
            ),
      ],
      ungrouped: _stringsOf(json['ungrouped']),
      customTags: [
        for (final raw in _listOf(json['customTags']))
          ?TagDictionaryEntry.fromJson(raw),
      ],
      translations: {
        if (json['translations'] case final Map raw)
          for (final entry in raw.entries)
            if (entry.value is Map && '${entry.key}'.trim().isNotEmpty)
              '${entry.key}': [
                for (final e in (entry.value as Map).entries)
                  ?TagTranslation.fromJson('${e.key}', e.value),
              ],
      },
      danbooruMeta: switch (json['danbooruMeta']) {
        final Map raw => raw.cast<String, dynamic>(),
        _ => const {},
      },
    );
  }
}

/// A parsed export file.
class DataBundle {
  const DataBundle({
    this.appVersion = '',
    this.exportedAt,
    this.providers,
    this.tagLibrary,
    this.presets,
  });

  /// Bumped only on a breaking layout change. A file from a newer schema is
  /// refused outright by [DataBundle.decode] rather than half-read: applying
  /// the parts this build happens to understand would leave the user with a
  /// restore they cannot tell apart from a complete one.
  static const int schemaVersion = 1;

  /// Identifies the producing app, so a JSON file picked by mistake fails with
  /// "not an export" instead of importing zero of everything.
  static const String appId = 'dataset_training_tool';

  /// Version of the app that wrote the file; shown in the import dialog.
  final String appVersion;

  final DateTime? exportedAt;

  /// Null when the section was not exported — distinct from an empty list,
  /// which means "exported, and there was nothing configured".
  final List<LlmProvider>? providers;
  final TagLibraryBundle? tagLibrary;
  final List<PromptPreset>? presets;

  bool has(DataSection section) => switch (section) {
    DataSection.llm => providers != null,
    DataSection.tagLibrary => tagLibrary != null,
    DataSection.promptPresets => presets != null,
  };

  /// The sections actually carried, in enum order.
  Set<DataSection> get sections => {
    for (final s in DataSection.values)
      if (has(s)) s,
  };

  bool get isEmpty => sections.isEmpty;

  int get providerCount => providers?.length ?? 0;

  int get modelCount =>
      providers?.fold(0, (sum, p) => sum! + p.models.length) ?? 0;

  /// Whether any provider carries a non-empty key. Drives the import dialog's
  /// note about credentials — and its absence tells a user restoring a
  /// key-stripped export why they still have to paste them in.
  bool get hasApiKeys =>
      providers?.any((p) => p.apiKey.trim().isNotEmpty) ?? false;

  int get presetCount => presets?.length ?? 0;

  String encode() {
    return '${const JsonEncoder.withIndent('  ').convert({
      'schema': schemaVersion,
      'app': appId,
      'appVersion': appVersion,
      if (exportedAt != null) 'exportedAt': exportedAt!.toIso8601String(),
      if (providers case final list?)
        DataSection.llm.key: {'providers': [for (final p in list) p.toJson()]},
      if (tagLibrary case final library?)
        DataSection.tagLibrary.key: library.toJson(),
      if (presets case final list?)
        DataSection.promptPresets.key: [for (final p in list) p.toJson()],
    })}\n';
  }

  /// Reads an export file.
  ///
  /// Throws [FormatException] when [text] is not this app's export at all, or
  /// when it comes from a schema this build does not understand.
  factory DataBundle.decode(String text) {
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      throw const FormatException('not a JSON file');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('not an export file');
    }
    if (decoded['app'] != appId) {
      throw const FormatException('not an export of this app');
    }
    final schema = (decoded['schema'] as num?)?.toInt() ?? 0;
    if (schema > schemaVersion) {
      throw FormatException(
        'the file uses schema $schema, newer than this app understands '
        '($schemaVersion)',
      );
    }

    return DataBundle(
      appVersion: (decoded['appVersion'] as String?) ?? '',
      exportedAt: DateTime.tryParse((decoded['exportedAt'] as String?) ?? ''),
      providers: switch (decoded[DataSection.llm.key]) {
        final Map raw => decodeLlmProviders(jsonEncode(raw['providers'] ?? [])),
        _ => null,
      },
      tagLibrary: switch (decoded[DataSection.tagLibrary.key]) {
        final Map raw => TagLibraryBundle.fromJson(
          raw.cast<String, dynamic>(),
        ),
        _ => null,
      },
      presets: switch (decoded[DataSection.promptPresets.key]) {
        final List raw => decodePromptPresets(jsonEncode(raw)),
        _ => null,
      },
    );
  }
}

/// What an import actually changed, for the summary the user is shown.
///
/// Counted rather than merely reported as "done": an import that silently did
/// nothing (wrong file, everything already present) and one that restored a
/// hundred tags must not look the same.
class DataImportReport {
  const DataImportReport({
    this.providersAdded = 0,
    this.providersUpdated = 0,
    this.modelsAdded = 0,
    this.tagsAdded = 0,
    this.groupsCreated = 0,
    this.customTagsAdded = 0,
    this.translationsWritten = 0,
    this.danbooruRecordsWritten = 0,
    this.presetsAdded = 0,
    this.presetsUpdated = 0,
  });

  final int providersAdded;
  final int providersUpdated;
  final int modelsAdded;
  final int tagsAdded;
  final int groupsCreated;
  final int customTagsAdded;
  final int translationsWritten;
  final int danbooruRecordsWritten;
  final int presetsAdded;
  final int presetsUpdated;

  int get total =>
      providersAdded +
      providersUpdated +
      modelsAdded +
      tagsAdded +
      groupsCreated +
      customTagsAdded +
      translationsWritten +
      danbooruRecordsWritten +
      presetsAdded +
      presetsUpdated;

  bool get isEmpty => total == 0;
}

List<Object?> _listOf(Object? value) =>
    value is List ? value : const <Object?>[];

List<String> _stringsOf(Object? value) => [
  for (final item in _listOf(value))
    if (item is String) item,
];
