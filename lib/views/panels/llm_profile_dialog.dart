import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../l10n/app_localizations.dart';
import '../../models/llm_models.dart';
import '../../services/llm/anthropic_client.dart';
import '../../services/llm/llm_client.dart';
import '../../services/llm/openai_compat_client.dart';
import '../../theme/app_theme.dart';

/// Management dialog for LLM backend profiles: list, edit, test, delete.
Future<void> showLlmProfilesDialog(BuildContext context) => showDialog(
      context: context,
      builder: (_) => ChangeNotifierProvider.value(
        value: context.read<AppState>(),
        child: const _LlmProfilesDialog(),
      ),
    );

class _LlmProfilesDialog extends StatefulWidget {
  const _LlmProfilesDialog();

  @override
  State<_LlmProfilesDialog> createState() => _LlmProfilesDialogState();
}

class _LlmProfilesDialogState extends State<_LlmProfilesDialog> {
  final _name = TextEditingController();
  final _baseUrl = TextEditingController();
  final _apiKey = TextEditingController();
  final _model = TextEditingController();
  final _contextWindow = TextEditingController();
  final _maxOutput = TextEditingController();
  final _temperature = TextEditingController();

  final _openaiClient = OpenAiCompatClient();
  final _anthropicClient = AnthropicClient();

  String? _selectedId;
  LlmApiKind _kind = LlmApiKind.openaiCompat;
  bool _supportsVision = false;
  bool _obscureKey = true;
  bool _probing = false;
  String? _probeResult;
  bool _probeOk = false;
  bool _fetchingModels = false;

  static int _idCounter = 0;

  @override
  void dispose() {
    _name.dispose();
    _baseUrl.dispose();
    _apiKey.dispose();
    _model.dispose();
    _contextWindow.dispose();
    _maxOutput.dispose();
    _temperature.dispose();
    _openaiClient.dispose();
    _anthropicClient.dispose();
    super.dispose();
  }

  LlmProviderProfile? _selected(AppState app) {
    for (final p in app.llmProfiles) {
      if (p.id == _selectedId) return p;
    }
    return null;
  }

  void _loadForm(LlmProviderProfile p) {
    _selectedId = p.id;
    _name.text = p.name;
    _kind = p.kind;
    _baseUrl.text = p.baseUrl;
    _apiKey.text = p.apiKey;
    _model.text = p.model;
    _supportsVision = p.supportsVision;
    _contextWindow.text = '${p.contextWindow}';
    _maxOutput.text = '${p.maxOutputTokens}';
    _temperature.text = '${p.temperature}';
    _probeResult = null;
  }

  /// The profile as currently described by the form fields.
  LlmProviderProfile _formProfile(String id) => LlmProviderProfile(
        id: id,
        name: _name.text.trim(),
        kind: _kind,
        baseUrl: _baseUrl.text.trim(),
        apiKey: _apiKey.text.trim(),
        model: _model.text.trim(),
        supportsVision: _supportsVision,
        contextWindow: int.tryParse(_contextWindow.text.trim()) ?? 32768,
        maxOutputTokens: int.tryParse(_maxOutput.text.trim()) ?? 4096,
        temperature: double.tryParse(_temperature.text.trim()) ?? 0.7,
      );

  Future<void> _add(AppState app) async {
    final l10n = AppLocalizations.of(context)!;
    final profile = LlmProviderProfile(
      id: '${DateTime.now().microsecondsSinceEpoch}-${_idCounter++}',
      name: l10n.llmNewProfileName,
      baseUrl: 'https://api.openai.com/v1',
    );
    await app.updateLlmProfiles([...app.llmProfiles, profile]);
    setState(() => _loadForm(profile));
  }

  Future<void> _save(AppState app) async {
    final id = _selectedId;
    if (id == null) return;
    final updated = _formProfile(id);
    await app.updateLlmProfiles([
      for (final p in app.llmProfiles) p.id == id ? updated : p,
    ]);
    if (mounted) setState(() {});
  }

  Future<void> _delete(AppState app) async {
    final l10n = AppLocalizations.of(context)!;
    final selected = _selected(app);
    if (selected == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.llmDeleteConfirmTitle),
        content: Text(l10n.llmDeleteConfirmContent(selected.name)),
        actions: [
          TextButton(
            child: Text(l10n.cancel),
            onPressed: () => Navigator.of(context).pop(false),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text(l10n.delete),
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await app.updateLlmProfiles(
      app.llmProfiles.where((p) => p.id != selected.id).toList(),
    );
    setState(() => _selectedId = null);
  }

  Future<void> _probe() async {
    final l10n = AppLocalizations.of(context)!;
    setState(() {
      _probing = true;
      _probeResult = null;
    });
    final profile = _formProfile(_selectedId ?? 'probe');
    final client = profile.kind == LlmApiKind.anthropic
        ? _anthropicClient as LlmClient
        : _openaiClient;
    final watch = Stopwatch()..start();
    final error = await client.probe(profile);
    watch.stop();
    if (!mounted) return;
    setState(() {
      _probing = false;
      _probeOk = error == null;
      _probeResult = error == null
          ? l10n.llmTestOk(watch.elapsedMilliseconds)
          : l10n.llmTestFailed(error);
    });
  }

  /// `GET /models` against the backend as currently described by the form,
  /// then a filterable picker; the choice lands in the model field.
  Future<void> _fetchModels() async {
    final l10n = AppLocalizations.of(context)!;
    setState(() {
      _fetchingModels = true;
      _probeResult = null;
    });
    final profile = _formProfile(_selectedId ?? 'fetch');
    final client = profile.kind == LlmApiKind.anthropic
        ? _anthropicClient as LlmClient
        : _openaiClient;
    List<String> models;
    try {
      models = await client.listModels(profile);
    } on LlmException catch (e) {
      if (!mounted) return;
      setState(() {
        _fetchingModels = false;
        _probeOk = false;
        _probeResult = l10n.llmTestFailed(e.message);
      });
      return;
    }
    if (!mounted) return;
    setState(() => _fetchingModels = false);
    if (models.isEmpty) {
      setState(() {
        _probeOk = false;
        _probeResult = l10n.llmTestFailed(l10n.llmNoModelsFound);
      });
      return;
    }
    final picked = await showDialog<String>(
      context: context,
      builder: (_) => _ModelPickerDialog(
        models: models,
        current: _model.text.trim(),
      ),
    );
    if (picked != null && mounted) {
      setState(() => _model.text = picked);
    }
  }

  void _applyPreset(String label) {
    final preset = LlmProviderProfile.presets[label];
    if (preset == null) return;
    setState(() {
      _kind = preset.$1;
      _baseUrl.text = preset.$2;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final semantic = context.semantic;
    final app = context.watch<AppState>();
    final selected = _selected(app);

    return AlertDialog(
      title: Text(l10n.llmProfilesTitle),
      content: SizedBox(
        width: 660,
        height: 460,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 180,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: semantic.line),
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: app.llmProfiles.isEmpty
                          ? Center(
                              child: Text(
                                l10n.llmNoProfiles,
                                style: TextStyle(
                                    fontSize: 12, color: semantic.muted),
                              ),
                            )
                          : ListView(
                              children: [
                                for (final p in app.llmProfiles)
                                  ListTile(
                                    dense: true,
                                    selected: p.id == _selectedId,
                                    title: Text(
                                      p.name,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 12.5),
                                    ),
                                    subtitle: Text(
                                      p.model.isEmpty ? '—' : p.model,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        color: semantic.muted,
                                      ),
                                    ),
                                    onTap: () =>
                                        setState(() => _loadForm(p)),
                                  ),
                              ],
                            ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                    onPressed: () => _add(app),
                    icon: const Icon(Icons.add, size: 15),
                    label: Text(l10n.add),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: selected == null
                  ? Center(
                      child: Text(
                        l10n.llmSelectProfileHint,
                        style:
                            TextStyle(fontSize: 12, color: semantic.muted),
                      ),
                    )
                  : _buildForm(context, app),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          child: Text(l10n.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  Widget _buildForm(BuildContext context, AppState app) {
    final l10n = AppLocalizations.of(context)!;
    final semantic = context.semantic;
    final scheme = Theme.of(context).colorScheme;

    InputDecoration deco(String label) => InputDecoration(
          labelText: label,
          isDense: true,
          border: const OutlineInputBorder(),
          labelStyle: const TextStyle(fontSize: 12),
        );
    const fieldStyle = TextStyle(fontSize: 12.5);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _name,
                  style: fieldStyle,
                  decoration: deco(l10n.llmProfileName),
                ),
              ),
              const SizedBox(width: 8),
              DropdownButton<String>(
                hint: Text(l10n.llmPreset,
                    style: const TextStyle(fontSize: 12)),
                underline: const SizedBox.shrink(),
                borderRadius: BorderRadius.circular(7),
                items: [
                  for (final label in LlmProviderProfile.presets.keys)
                    DropdownMenuItem(
                      value: label,
                      child: Text(label,
                          style: const TextStyle(fontSize: 12)),
                    ),
                ],
                onChanged: (label) {
                  if (label != null) _applyPreset(label);
                },
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              DropdownButton<LlmApiKind>(
                value: _kind,
                underline: const SizedBox.shrink(),
                borderRadius: BorderRadius.circular(7),
                items: [
                  DropdownMenuItem(
                    value: LlmApiKind.openaiCompat,
                    child: Text(l10n.llmKindOpenAi,
                        style: const TextStyle(fontSize: 12)),
                  ),
                  DropdownMenuItem(
                    value: LlmApiKind.anthropic,
                    child: Text(l10n.llmKindAnthropic,
                        style: const TextStyle(fontSize: 12)),
                  ),
                ],
                onChanged: (kind) {
                  if (kind != null) setState(() => _kind = kind);
                },
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _baseUrl,
                  style: monoStyle(context, size: 12),
                  decoration: deco(l10n.llmBaseUrl),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _apiKey,
            obscureText: _obscureKey,
            style: monoStyle(context, size: 12),
            decoration: deco(l10n.llmApiKey).copyWith(
              helperText: l10n.llmApiKeyPlaintextNote,
              helperStyle: TextStyle(fontSize: 10.5, color: semantic.muted),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureKey ? Icons.visibility_off : Icons.visibility,
                  size: 15,
                ),
                onPressed: () => setState(() => _obscureKey = !_obscureKey),
              ),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _model,
            style: monoStyle(context, size: 12),
            decoration: deco(l10n.llmModel).copyWith(
              suffixIcon: _fetchingModels
                  ? const Padding(
                      padding: EdgeInsets.all(10),
                      child: SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 1.5),
                      ),
                    )
                  : IconButton(
                      icon: const Icon(Icons.cloud_download_outlined, size: 16),
                      tooltip: l10n.llmFetchModels,
                      onPressed: _fetchModels,
                    ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _contextWindow,
                  keyboardType: TextInputType.number,
                  style: fieldStyle,
                  decoration: deco(l10n.llmContextWindow),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _maxOutput,
                  keyboardType: TextInputType.number,
                  style: fieldStyle,
                  decoration: deco(l10n.llmMaxOutput),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 90,
                child: TextField(
                  controller: _temperature,
                  keyboardType: TextInputType.number,
                  style: fieldStyle,
                  decoration: deco(l10n.llmTemperature),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.llmSupportsVision,
                style: const TextStyle(fontSize: 12.5)),
            subtitle: Text(
              l10n.llmSupportsVisionDesc,
              style: TextStyle(fontSize: 10.5, color: semantic.muted),
            ),
            value: _supportsVision,
            onChanged: (v) => setState(() => _supportsVision = v),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  textStyle: const TextStyle(fontSize: 12),
                ),
                onPressed: _probing ? null : _probe,
                icon: _probing
                    ? const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(strokeWidth: 1.5),
                      )
                    : const Icon(Icons.network_check, size: 15),
                label: Text(l10n.llmTestConnection),
              ),
              const SizedBox(width: 10),
              FilledButton(
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  textStyle: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600),
                ),
                onPressed: () => _save(app),
                child: Text(l10n.save),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 17),
                tooltip: l10n.delete,
                color: scheme.error,
                visualDensity: VisualDensity.compact,
                onPressed: () => _delete(app),
              ),
            ],
          ),
          if (_probeResult != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: SelectableText(
                _probeResult!,
                style: TextStyle(
                  fontSize: 11.5,
                  color: _probeOk ? scheme.primary : scheme.error,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Filterable picker over the ids returned by `GET /models`; pops with the
/// chosen id.
class _ModelPickerDialog extends StatefulWidget {
  const _ModelPickerDialog({required this.models, required this.current});

  final List<String> models;
  final String current;

  @override
  State<_ModelPickerDialog> createState() => _ModelPickerDialogState();
}

class _ModelPickerDialogState extends State<_ModelPickerDialog> {
  final TextEditingController _filter = TextEditingController();

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final semantic = context.semantic;
    final query = _filter.text.trim().toLowerCase();
    final visible = query.isEmpty
        ? widget.models
        : widget.models
            .where((m) => m.toLowerCase().contains(query))
            .toList();

    return AlertDialog(
      title: Text(l10n.llmFetchModels),
      content: SizedBox(
        width: 420,
        height: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _filter,
              autofocus: true,
              style: const TextStyle(fontSize: 12.5),
              decoration: InputDecoration(
                hintText: l10n.aiModelFilterHint,
                hintStyle: TextStyle(fontSize: 12, color: semantic.muted),
                prefixIcon: const Icon(Icons.search, size: 16),
                isDense: true,
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: visible.isEmpty
                  ? Center(
                      child: Text(
                        l10n.aiModelFilterNoMatch,
                        style:
                            TextStyle(fontSize: 12, color: semantic.muted),
                      ),
                    )
                  : ListView.builder(
                      itemCount: visible.length,
                      itemBuilder: (context, index) {
                        final id = visible[index];
                        return ListTile(
                          dense: true,
                          selected: id == widget.current,
                          title: Text(
                            id,
                            overflow: TextOverflow.ellipsis,
                            style: monoStyle(context, size: 12),
                          ),
                          onTap: () => Navigator.of(context).pop(id),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          child: Text(l10n.cancel),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}
