/// Collects the user's hand-built settings into a [DataBundle] and applies one
/// back — the engine behind settings' "export / import data".
///
/// Kept out of [AppState] and off its own storage: everything here goes
/// through the same public mutators the UI uses, so an import is
/// indistinguishable from the user having entered it all by hand, and nothing
/// can end up persisted through a path the rest of the app does not know about.
library;

import 'dart:convert';

import '../app_info.dart';
import '../app_state.dart';
import '../models/data_bundle.dart';
import '../models/llm_models.dart';
import '../models/prompt_preset.dart';
import '../models/tag_dictionary.dart';
import '../models/tag_translation.dart';
import '../utils/tag_text.dart';

class DataTransfer {
  DataTransfer(this.state);

  final AppState state;

  // Same reason as AppState's own id counters: two ids minted inside one clock
  // tick would otherwise collide, and an import mints a whole batch at once.
  static int _idCounter = 0;

  static String _freshId() =>
      '${DateTime.now().microsecondsSinceEpoch}-${_idCounter++}';

  // --- Export -----------------------------------------------------------

  /// Gathers [sections] from the running app.
  ///
  /// With [includeApiKeys] false every key is blanked. The rest of the backend
  /// — endpoint, model list, context window, pricing — is the tedious part to
  /// re-enter and is kept either way, so a stripped export is still worth
  /// carrying to another machine.
  Future<DataBundle> collect({
    required Set<DataSection> sections,
    bool includeApiKeys = true,
    DateTime? exportedAt,
  }) async {
    return DataBundle(
      appVersion: AppInfo.version,
      exportedAt: exportedAt ?? DateTime.now(),
      providers: sections.contains(DataSection.llm)
          ? [
              for (final provider in state.llmProviders)
                includeApiKeys ? provider : provider.copyWith(apiKey: ''),
            ]
          : null,
      tagLibrary: sections.contains(DataSection.tagLibrary)
          ? await _collectLibrary()
          : null,
      presets: sections.contains(DataSection.promptPresets)
          ? state.promptPresets
          : null,
    );
  }

  Future<TagLibraryBundle> _collectLibrary() async {
    final translations = <String, List<TagTranslation>>{};
    for (final code in await state.tagTranslations.storedLanguages()) {
      try {
        final entries = await state.tagTranslations.entriesFor(code);
        if (entries.isNotEmpty) translations[code] = entries;
      } catch (_) {
        // A glossary this build cannot read (a newer schema, a corrupt file)
        // is left out rather than aborting the whole export. The dialog shows
        // the translation count it actually collected, so a missing language
        // shows up as a smaller number instead of a silent success.
      }
    }
    return TagLibraryBundle(
      groups: state.tagGroups,
      ungrouped: state.ungroupedTags,
      customTags: state.tagDictionary.customEntries,
      translations: translations,
      // Rebuilding these means asking danbooru about every tag again, one
      // request at a time — exactly the slow walk a backup exists to spare.
      danbooruMeta: state.danbooruMeta.exportEntries(),
    );
  }

  // --- Import -----------------------------------------------------------

  /// Applies the [sections] of [bundle] the caller selected.
  ///
  /// Never deletes: [DataImportMode] only decides who wins where the file and
  /// the local side both have a value. Sections the bundle does not carry are
  /// ignored even when selected.
  Future<DataImportReport> apply(
    DataBundle bundle, {
    required Set<DataSection> sections,
    DataImportMode mode = DataImportMode.merge,
  }) async {
    var report = const DataImportReport();
    if (sections.contains(DataSection.llm) && bundle.providers != null) {
      report = _mergeReports(report, await _applyLlm(bundle.providers!, mode));
    }
    if (sections.contains(DataSection.tagLibrary) &&
        bundle.tagLibrary != null) {
      report = _mergeReports(
        report,
        await _applyLibrary(bundle.tagLibrary!, mode),
      );
    }
    if (sections.contains(DataSection.promptPresets) &&
        bundle.presets != null) {
      report = _mergeReports(
        report,
        await _applyPresets(bundle.presets!, mode),
      );
    }
    return report;
  }

  /// Providers are matched by name — ids are local handles, and a restore onto
  /// a machine that has never seen this backend would match nothing by id.
  Future<DataImportReport> _applyLlm(
    List<LlmProvider> incoming,
    DataImportMode mode,
  ) async {
    final startedEmpty = state.llmProviders.isEmpty;
    final next = [...state.llmProviders];
    final byName = <String, int>{
      for (var i = 0; i < next.length; i++) next[i].name.trim(): i,
    };
    final takenIds = {for (final p in next) p.id};

    var added = 0;
    var updated = 0;
    var modelsAdded = 0;

    for (final provider in incoming) {
      final name = provider.name.trim();
      if (name.isEmpty) continue;
      final at = byName[name];
      if (at == null) {
        // Its own id is kept when free, so an "active model" pointer written
        // by the same export still resolves after a fresh restore.
        final id = provider.id.isEmpty || takenIds.contains(provider.id)
            ? _freshId()
            : provider.id;
        takenIds.add(id);
        final restored = LlmProvider(
          id: id,
          name: provider.name,
          kind: provider.kind,
          baseUrl: provider.baseUrl,
          apiKey: provider.apiKey,
          models: provider.models,
        );
        byName[name] = next.length;
        next.add(restored);
        added++;
        modelsAdded += restored.models.length;
        continue;
      }

      final local = next[at];
      final (merged, newModels) = _mergeProvider(local, provider, mode);
      modelsAdded += newModels;
      if (!identical(merged, local)) {
        next[at] = merged;
        updated++;
      }
    }

    if (added == 0 && updated == 0 && modelsAdded == 0) {
      return const DataImportReport();
    }
    await state.updateLlmProviders(next);
    // Only on a restore onto an unconfigured app: with providers already set
    // up, silently repointing the assistant at a backend from a file would be
    // a change the user never asked for.
    if (startedEmpty && state.llmProfiles.isNotEmpty) {
      await state.setActiveLlmProfile(state.llmProfiles.first.id);
    }
    return DataImportReport(
      providersAdded: added,
      providersUpdated: updated,
      modelsAdded: modelsAdded,
    );
  }

  /// Returns the merged provider (identical to [local] when nothing changed)
  /// and how many models were added.
  (LlmProvider, int) _mergeProvider(
    LlmProvider local,
    LlmProvider incoming,
    DataImportMode mode,
  ) {
    final overwrite = mode == DataImportMode.overwrite;

    // An empty local field is not a value the user chose, so it is filled in
    // even in merge mode. An empty *incoming* key never overwrites a local
    // one: that is what a key-stripped export looks like, and losing the
    // credential to a backup that never carried it would be the worst outcome.
    String pick(String localValue, String incomingValue) {
      if (localValue.trim().isEmpty) return incomingValue;
      if (overwrite && incomingValue.trim().isNotEmpty) return incomingValue;
      return localValue;
    }

    final models = [...local.models];
    final byModelId = <String, int>{
      for (var i = 0; i < models.length; i++) models[i].modelId: i,
    };
    final takenIds = {for (final m in models) m.id};
    var added = 0;
    var changed = false;

    for (final model in incoming.models) {
      final at = byModelId[model.modelId];
      if (at == null) {
        final id = model.id.isEmpty || takenIds.contains(model.id)
            ? _freshId()
            : model.id;
        takenIds.add(id);
        byModelId[model.modelId] = models.length;
        models.add(
          LlmModelConfig(
            id: id,
            modelId: model.modelId,
            displayName: model.displayName,
            contextWindow: model.contextWindow,
            maxOutputTokens: model.maxOutputTokens,
            temperature: model.temperature,
            supportsVision: model.supportsVision,
            pricing: model.pricing,
          ),
        );
        added++;
        changed = true;
      } else if (overwrite) {
        // Keeps the local id: it is what the active-profile pointer and any
        // open chat session already reference.
        models[at] = LlmModelConfig(
          id: models[at].id,
          modelId: model.modelId,
          displayName: model.displayName,
          contextWindow: model.contextWindow,
          maxOutputTokens: model.maxOutputTokens,
          temperature: model.temperature,
          supportsVision: model.supportsVision,
          pricing: model.pricing,
        );
        changed = true;
      }
    }

    final baseUrl = pick(local.baseUrl, incoming.baseUrl);
    final apiKey = pick(local.apiKey, incoming.apiKey);
    final kind = overwrite ? incoming.kind : local.kind;
    if (!changed &&
        baseUrl == local.baseUrl &&
        apiKey == local.apiKey &&
        kind == local.kind) {
      return (local, 0);
    }
    return (
      local.copyWith(kind: kind, baseUrl: baseUrl, apiKey: apiKey, models: models),
      added,
    );
  }

  Future<DataImportReport> _applyLibrary(
    TagLibraryBundle library,
    DataImportMode mode,
  ) async {
    var tagsAdded = 0;
    var groupsCreated = 0;

    if (library.groups.isNotEmpty || library.ungrouped.isNotEmpty) {
      final result = await state.importLibraryJson(
        _libraryExportJson(library),
      );
      tagsAdded = result.tagsAdded;
      groupsCreated = result.groupsCreated;
      // importLibraryJson keeps a pre-existing group's local color, which is
      // the right default; in overwrite mode the file gets its say.
      if (mode == DataImportMode.overwrite) {
        for (final group in library.groups) {
          final local = state.tagGroups
              .where((g) => g.name == group.name)
              .firstOrNull;
          if (local != null && local.color != group.color) {
            await state.updateTagGroup(local.id, color: group.color);
          }
        }
      }
    }

    final customTagsAdded = await _applyCustomTags(library.customTags, mode);

    var translationsWritten = 0;
    for (final entry in library.translations.entries) {
      try {
        final (written, _) = await state.tagTranslations.upsertAllFor(
          entry.key,
          entry.value,
          overwrite: mode == DataImportMode.overwrite,
        );
        translationsWritten += written;
      } catch (_) {
        // Same rule as the export side: a glossary file this build refuses to
        // read is left untouched rather than overwritten.
      }
    }

    final danbooruRecordsWritten = await state.danbooruMeta.importEntries(
      library.danbooruMeta,
      overwrite: mode == DataImportMode.overwrite,
    );

    return DataImportReport(
      tagsAdded: tagsAdded,
      groupsCreated: groupsCreated,
      customTagsAdded: customTagsAdded,
      translationsWritten: translationsWritten,
      danbooruRecordsWritten: danbooruRecordsWritten,
    );
  }

  /// The shape [AppState.importLibraryJson] parses, built straight from the
  /// bundle so the tag panel's own JSON import and a restore share one code
  /// path — group-by-name matching, exclusive membership and all.
  String _libraryExportJson(TagLibraryBundle library) {
    return jsonEncode({
      'version': 1,
      'groups': [
        for (final g in library.groups)
          {'name': g.name, 'color': g.color, 'tags': g.tags},
      ],
      'ungrouped': library.ungrouped,
    });
  }

  Future<int> _applyCustomTags(
    List<TagDictionaryEntry> incoming,
    DataImportMode mode,
  ) async {
    if (incoming.isEmpty) return 0;
    final dictionary = state.tagDictionary;
    final entries = [...dictionary.customEntries];
    final byKey = <String, int>{
      for (var i = 0; i < entries.length; i++) tagLookupKey(entries[i].name): i,
    };
    var added = 0;
    var changed = false;
    for (final entry in incoming) {
      final key = tagLookupKey(entry.name);
      if (key.isEmpty) continue;
      final at = byKey[key];
      if (at == null) {
        byKey[key] = entries.length;
        entries.add(entry);
        added++;
        changed = true;
      } else if (mode == DataImportMode.overwrite) {
        entries[at] = entry;
        changed = true;
      }
    }
    // setCustomEntries drops anything the dictionary already covers, so the
    // count reported is the ceiling rather than the exact number kept — the
    // dictionary manager shows the truth either way.
    if (changed) await dictionary.setCustomEntries(entries);
    return added;
  }

  /// Presets are matched by title, falling back to their text for the
  /// untitled ones. Re-importing the same backup twice must not leave two
  /// copies of every prompt.
  Future<DataImportReport> _applyPresets(
    List<PromptPreset> incoming,
    DataImportMode mode,
  ) async {
    String keyOf(PromptPreset p) => p.title.trim().isEmpty
        ? 'body:${p.content.trim()}'
        : 'title:${p.title.trim()}';

    final local = {for (final p in state.promptPresets) keyOf(p): p};
    final fresh = <PromptPreset>[];
    var updated = 0;

    for (final preset in incoming) {
      if (preset.title.trim().isEmpty && preset.content.trim().isEmpty) {
        continue;
      }
      final existing = local[keyOf(preset)];
      if (existing == null) {
        local[keyOf(preset)] = preset;
        fresh.add(preset);
        continue;
      }
      if (mode == DataImportMode.overwrite &&
          existing.content != preset.content) {
        await state.updatePromptPreset(existing.id, content: preset.content);
        updated++;
      }
    }

    if (fresh.isNotEmpty) await state.addPromptPresets(fresh);
    return DataImportReport(
      presetsAdded: fresh.length,
      presetsUpdated: updated,
    );
  }

  static DataImportReport _mergeReports(DataImportReport a, DataImportReport b) {
    return DataImportReport(
      providersAdded: a.providersAdded + b.providersAdded,
      providersUpdated: a.providersUpdated + b.providersUpdated,
      modelsAdded: a.modelsAdded + b.modelsAdded,
      tagsAdded: a.tagsAdded + b.tagsAdded,
      groupsCreated: a.groupsCreated + b.groupsCreated,
      customTagsAdded: a.customTagsAdded + b.customTagsAdded,
      translationsWritten: a.translationsWritten + b.translationsWritten,
      danbooruRecordsWritten:
          a.danbooruRecordsWritten + b.danbooruRecordsWritten,
      presetsAdded: a.presetsAdded + b.presetsAdded,
      presetsUpdated: a.presetsUpdated + b.presetsUpdated,
    );
  }
}
