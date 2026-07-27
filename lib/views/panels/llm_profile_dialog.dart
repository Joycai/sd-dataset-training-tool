import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../l10n/app_localizations.dart';
import '../../models/llm_models.dart';
import '../../services/llm/anthropic_client.dart';
import '../../services/llm/llm_client.dart';
import '../../services/llm/openai_compat_client.dart';
import '../../theme/app_theme.dart';
import '../../widgets/panel_widgets.dart';

/// Management dialog for LLM backends, as a provider → model tree.
///
/// The endpoint and its credentials belong to the provider and are entered
/// once; each model under it carries only what actually differs per model.
/// That is the whole point of the two levels — adding a second model from
/// the same vendor used to mean re-typing the URL and the key.
Future<void> showLlmProfilesDialog(BuildContext context) => showDialog(
  context: context,
  builder: (_) => ChangeNotifierProvider.value(
    value: context.read<AppState>(),
    child: const _LlmProvidersDialog(),
  ),
);

/// Context window stops. The slider is evenly spaced across them rather than
/// linear in tokens: 8K and 16K would otherwise share the first percent of
/// the track while 1M swallowed the rest.
const List<int> _contextStops = [
  8192,
  16384,
  32768,
  65536,
  131072,
  200000,
  1000000,
];

String _formatTokens(int tokens) {
  if (tokens >= 1000000) return '${(tokens / 1048576).round()}M';
  return '${(tokens / 1024).round()}K';
}

class _LlmProvidersDialog extends StatefulWidget {
  const _LlmProvidersDialog();

  @override
  State<_LlmProvidersDialog> createState() => _LlmProvidersDialogState();
}

class _LlmProvidersDialogState extends State<_LlmProvidersDialog> {
  final _openaiClient = OpenAiCompatClient();
  final _anthropicClient = AnthropicClient();

  String? _selectedProviderId;
  String? _selectedModelId;
  final Set<String> _collapsed = {};

  bool _probing = false;
  bool _probeOk = false;
  String? _probeResult;

  int _idCounter = 0;

  String _newId(String prefix) =>
      '$prefix-${DateTime.now().microsecondsSinceEpoch}-${_idCounter++}';

  List<LlmProvider> get _providers => context.read<AppState>().llmProviders;

  LlmProvider? get _selectedProvider {
    for (final p in _providers) {
      if (p.id == _selectedProviderId) return p;
    }
    return null;
  }

  LlmModelConfig? get _selectedModel {
    final provider = _selectedProvider;
    if (provider == null || _selectedModelId == null) return null;
    for (final m in provider.models) {
      if (m.id == _selectedModelId) return m;
    }
    return null;
  }

  LlmClient _clientFor(LlmApiKind kind) =>
      kind == LlmApiKind.anthropic ? _anthropicClient : _openaiClient;

  Future<void> _save(List<LlmProvider> next) =>
      context.read<AppState>().updateLlmProviders(next);

  Future<void> _replaceProvider(LlmProvider updated) => _save([
    for (final p in _providers)
      if (p.id == updated.id) updated else p,
  ]);

  Future<void> _addProvider() async {
    final l10n = AppLocalizations.of(context)!;
    final provider = LlmProvider(
      id: _newId('provider'),
      name: l10n.llmNewProfileName,
    );
    await _save([..._providers, provider]);
    if (!mounted) return;
    setState(() {
      _selectedProviderId = provider.id;
      _selectedModelId = null;
    });
  }

  Future<void> _addModel(LlmProvider provider) async {
    final model = LlmModelConfig(id: _newId('model'), modelId: '');
    await _replaceProvider(
      provider.copyWith(models: [...provider.models, model]),
    );
    if (!mounted) return;
    setState(() {
      _selectedProviderId = provider.id;
      _selectedModelId = model.id;
      _probeResult = null;
    });
  }

  Future<void> _deleteProvider(LlmProvider provider) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.llmDeleteConfirmTitle),
        content: Text(l10n.llmDeleteConfirmContent(provider.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _save(_providers.where((p) => p.id != provider.id).toList());
    if (!mounted) return;
    setState(() {
      _selectedProviderId = null;
      _selectedModelId = null;
    });
  }

  Future<void> _deleteModel(LlmProvider provider, LlmModelConfig model) async {
    await _replaceProvider(
      provider.copyWith(
        models: provider.models.where((m) => m.id != model.id).toList(),
      ),
    );
    if (!mounted) return;
    setState(() => _selectedModelId = null);
  }

  Future<void> _probe(LlmProvider provider) async {
    final l10n = AppLocalizations.of(context)!;
    setState(() {
      _probing = true;
      _probeResult = null;
    });
    // Probing is about the endpoint, so any model name will do.
    final probeProfile = provider.resolve(
      provider.models.isNotEmpty
          ? provider.models.first
          : const LlmModelConfig(id: 'probe', modelId: ''),
    );
    final watch = Stopwatch()..start();
    final error = await _clientFor(provider.kind).probe(probeProfile);
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

  /// `GET /models` against the provider, then a filterable picker; the
  /// choice lands in the selected model's id field.
  Future<void> _fetchModels(LlmProvider provider, LlmModelConfig model) async {
    final l10n = AppLocalizations.of(context)!;
    setState(() => _probeResult = null);
    List<String> names;
    try {
      names = await _clientFor(
        provider.kind,
      ).listModels(provider.resolve(model));
    } on LlmException catch (e) {
      if (!mounted) return;
      setState(() {
        _probeOk = false;
        _probeResult = l10n.llmTestFailed(e.message);
      });
      return;
    }
    if (!mounted) return;
    if (names.isEmpty) {
      setState(() {
        _probeOk = false;
        _probeResult = l10n.llmNoModelsFound;
      });
      return;
    }
    final picked = await showDialog<String>(
      context: context,
      builder: (_) => _ModelNamePicker(names: names),
    );
    if (picked == null || !mounted) return;
    await _replaceProvider(
      provider.copyWith(
        models: [
          for (final m in provider.models)
            if (m.id == model.id) m.copyWith(modelId: picked) else m,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final semantic = context.semantic;
    // watch, not read: saving rebuilds the tree and the form underneath.
    context.watch<AppState>();
    final providers = _providers;
    final provider = _selectedProvider;
    final model = _selectedModel;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 880, maxHeight: 620),
        child: GlassSurface(
          borderRadius: BorderRadius.circular(14),
          blurSigma: 14,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(18, 12, 10, 12),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: semantic.line)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.llmProfilesTitle,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    PanelIconButton(
                      icon: Icons.close,
                      tooltip: l10n.cancel,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: 236,
                      child: _ProviderTree(
                        providers: providers,
                        selectedProviderId: _selectedProviderId,
                        selectedModelId: _selectedModelId,
                        collapsed: _collapsed,
                        onToggleCollapse: (id) => setState(() {
                          if (!_collapsed.remove(id)) _collapsed.add(id);
                        }),
                        onSelectProvider: (id) => setState(() {
                          _selectedProviderId = id;
                          _selectedModelId = null;
                          _probeResult = null;
                        }),
                        onSelectModel: (providerId, modelId) => setState(() {
                          _selectedProviderId = providerId;
                          _selectedModelId = modelId;
                          _probeResult = null;
                        }),
                        onAddModel: _addModel,
                        onAddProvider: _addProvider,
                      ),
                    ),
                    Container(width: 1, color: semantic.line),
                    Expanded(
                      child: provider == null
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text(
                                  l10n.llmSelectProfileHint,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: AppText.secondary,
                                    color: semantic.muted,
                                  ),
                                ),
                              ),
                            )
                          : SingleChildScrollView(
                              padding: const EdgeInsets.fromLTRB(
                                20,
                                16,
                                20,
                                20,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _ProviderCard(
                                    provider: provider,
                                    probing: _probing,
                                    probeOk: _probeOk,
                                    probeResult: _probeResult,
                                    onProbe: () => _probe(provider),
                                    onChanged: _replaceProvider,
                                    onDelete: () => _deleteProvider(provider),
                                  ),
                                  const SizedBox(height: 16),
                                  if (model != null)
                                    _ModelForm(
                                      // Rebuild the form's controllers when
                                      // the selection moves to another model.
                                      key: ValueKey(
                                        '${provider.id}/${model.id}',
                                      ),
                                      provider: provider,
                                      model: model,
                                      onFetchModels: () =>
                                          _fetchModels(provider, model),
                                      onChanged: (updated) => _replaceProvider(
                                        provider.copyWith(
                                          models: [
                                            for (final m in provider.models)
                                              if (m.id == updated.id)
                                                updated
                                              else
                                                m,
                                          ],
                                        ),
                                      ),
                                      onDelete: () =>
                                          _deleteModel(provider, model),
                                    ),
                                ],
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// --- Tree -------------------------------------------------------------

class _ProviderTree extends StatelessWidget {
  const _ProviderTree({
    required this.providers,
    required this.selectedProviderId,
    required this.selectedModelId,
    required this.collapsed,
    required this.onToggleCollapse,
    required this.onSelectProvider,
    required this.onSelectModel,
    required this.onAddModel,
    required this.onAddProvider,
  });

  final List<LlmProvider> providers;
  final String? selectedProviderId;
  final String? selectedModelId;
  final Set<String> collapsed;
  final ValueChanged<String> onToggleCollapse;
  final ValueChanged<String> onSelectProvider;
  final void Function(String providerId, String modelId) onSelectModel;
  final ValueChanged<LlmProvider> onAddModel;
  final VoidCallback onAddProvider;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final semantic = context.semantic;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(8, 10, 8, 8),
            children: [
              for (final provider in providers) ...[
                _TreeRow(
                  label: provider.name,
                  detail:
                      '${_kindLabel(l10n, provider.kind)} · '
                      '${provider.models.length}',
                  selected:
                      provider.id == selectedProviderId &&
                      selectedModelId == null,
                  leading: _DisclosureArrow(
                    expanded: !collapsed.contains(provider.id),
                    onTap: () => onToggleCollapse(provider.id),
                  ),
                  trailing: _EndpointDot(provider: provider),
                  onTap: () => onSelectProvider(provider.id),
                ),
                if (!collapsed.contains(provider.id)) ...[
                  for (final model in provider.models)
                    _TreeRow(
                      indent: 22,
                      label: model.label,
                      mono: true,
                      badge: model.supportsVision ? l10n.llmVisionBadge : null,
                      selected:
                          provider.id == selectedProviderId &&
                          model.id == selectedModelId,
                      onTap: () => onSelectModel(provider.id, model.id),
                    ),
                  _TreeRow(
                    indent: 22,
                    label: l10n.llmAddModel,
                    muted: true,
                    selected: false,
                    onTap: () => onAddModel(provider),
                  ),
                ],
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
          child: _DashedAddButton(
            label: l10n.llmAddProvider,
            onTap: onAddProvider,
            color: semantic.muted,
            lineColor: semantic.line,
          ),
        ),
      ],
    );
  }
}

String _kindLabel(AppLocalizations l10n, LlmApiKind kind) =>
    kind == LlmApiKind.anthropic ? l10n.llmKindAnthropic : l10n.llmKindOpenAi;

class _TreeRow extends StatelessWidget {
  const _TreeRow({
    required this.label,
    required this.selected,
    required this.onTap,
    this.detail,
    this.badge,
    this.leading,
    this.trailing,
    this.indent = 0,
    this.mono = false,
    this.muted = false,
  });

  final String label;
  final String? detail;
  final String? badge;
  final bool selected;
  final VoidCallback onTap;
  final Widget? leading;
  final Widget? trailing;
  final double indent;
  final bool mono;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final semantic = context.semantic;
    final color = muted
        ? semantic.muted
        : selected
        ? scheme.onSurface
        : semantic.muted;

    return Padding(
      padding: EdgeInsets.fromLTRB(indent, 1, 0, 1),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: selected
                  ? scheme.primary.withValues(alpha: 0.20)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(AppRadii.input),
            ),
            child: Row(
              children: [
                if (leading != null) ...[leading!, const SizedBox(width: 4)],
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: mono
                        ? monoStyle(context, size: AppText.small, color: color)
                        : TextStyle(
                            fontSize: AppText.secondary,
                            fontWeight: selected
                                ? FontWeight.w600
                                : FontWeight.w400,
                            color: color,
                          ),
                  ),
                ),
                if (badge != null) ...[
                  const SizedBox(width: 6),
                  _MiniBadge(text: badge!),
                ],
                if (detail != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    detail!,
                    style: TextStyle(
                      fontSize: AppText.micro,
                      color: semantic.muted,
                    ),
                  ),
                ],
                if (trailing != null) ...[const SizedBox(width: 6), trailing!],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DisclosureArrow extends StatelessWidget {
  const _DisclosureArrow({required this.expanded, required this.onTap});

  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Icon(
        expanded ? Icons.expand_more : Icons.chevron_right,
        size: 15,
        color: context.semantic.muted,
      ),
    );
  }
}

/// Whether the provider looks usable at a glance — it needs an endpoint.
class _EndpointDot extends StatelessWidget {
  const _EndpointDot({required this.provider});

  final LlmProvider provider;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    final configured = provider.baseUrl.trim().isNotEmpty;
    return Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: configured ? semantic.ok : semantic.muted,
      ),
    );
  }
}

class _MiniBadge extends StatelessWidget {
  const _MiniBadge({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: AppText.micro, color: scheme.primary),
      ),
    );
  }
}

class _DashedAddButton extends StatelessWidget {
  const _DashedAddButton({
    required this.label,
    required this.onTap,
    required this.color,
    required this.lineColor,
  });

  final String label;
  final VoidCallback onTap;
  final Color color;
  final Color lineColor;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 7),
          decoration: BoxDecoration(
            border: Border.all(color: lineColor),
            borderRadius: BorderRadius.circular(AppRadii.input),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add, size: 14, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(fontSize: AppText.secondary, color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// --- Provider card ----------------------------------------------------

class _ProviderCard extends StatefulWidget {
  const _ProviderCard({
    required this.provider,
    required this.probing,
    required this.probeOk,
    required this.probeResult,
    required this.onProbe,
    required this.onChanged,
    required this.onDelete,
  });

  final LlmProvider provider;
  final bool probing;
  final bool probeOk;
  final String? probeResult;
  final VoidCallback onProbe;
  final ValueChanged<LlmProvider> onChanged;
  final VoidCallback onDelete;

  @override
  State<_ProviderCard> createState() => _ProviderCardState();
}

class _ProviderCardState extends State<_ProviderCard> {
  late final TextEditingController _name;
  late final TextEditingController _baseUrl;
  late final TextEditingController _apiKey;
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.provider.name);
    _baseUrl = TextEditingController(text: widget.provider.baseUrl);
    _apiKey = TextEditingController(text: widget.provider.apiKey);
    // A provider with no endpoint yet has nothing to summarise.
    _editing = widget.provider.baseUrl.trim().isEmpty;
  }

  @override
  void didUpdateWidget(_ProviderCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.provider.id != widget.provider.id) {
      _name.text = widget.provider.name;
      _baseUrl.text = widget.provider.baseUrl;
      _apiKey.text = widget.provider.apiKey;
      _editing = widget.provider.baseUrl.trim().isEmpty;
    } else if (_baseUrl.text != widget.provider.baseUrl) {
      // A preset wrote the URL from outside the form.
      _baseUrl.text = widget.provider.baseUrl;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _baseUrl.dispose();
    _apiKey.dispose();
    super.dispose();
  }

  void _commit() {
    widget.onChanged(
      widget.provider.copyWith(
        name: _name.text.trim(),
        baseUrl: _baseUrl.text.trim(),
        apiKey: _apiKey.text.trim(),
      ),
    );
  }

  /// Keys are secrets even on screen: show just enough to tell two apart.
  String get _maskedKey {
    final key = widget.provider.apiKey;
    if (key.isEmpty) return '—';
    if (key.length <= 8) return '••••';
    return '${key.substring(0, 4)}••••${key.substring(key.length - 4)}';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final semantic = context.semantic;
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 10, 14),
      decoration: BoxDecoration(
        color: semantic.raised,
        border: Border.all(color: semantic.line),
        borderRadius: BorderRadius.circular(AppRadii.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                l10n.llmProviderLabel,
                style: TextStyle(
                  fontSize: AppText.micro,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1,
                  color: semantic.muted,
                ),
              ),
              const SizedBox(width: 10),
              if (widget.probeResult != null)
                Expanded(
                  child: Text(
                    widget.probeResult!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: AppText.small,
                      color: widget.probeOk ? semantic.ok : scheme.error,
                    ),
                  ),
                )
              else
                const Spacer(),
              TextButton(
                onPressed: widget.probing ? null : widget.onProbe,
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  textStyle: const TextStyle(fontSize: AppText.secondary),
                ),
                child: Text(l10n.llmTestConnection),
              ),
              TextButton(
                onPressed: () => setState(() {
                  if (_editing) _commit();
                  _editing = !_editing;
                }),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  textStyle: const TextStyle(fontSize: AppText.secondary),
                ),
                child: Text(_editing ? l10n.save : l10n.llmEditProvider),
              ),
              PanelIconButton(
                icon: Icons.delete_outline,
                tooltip: l10n.delete,
                size: 15,
                color: scheme.error,
                onPressed: widget.onDelete,
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (!_editing)
            Wrap(
              spacing: 16,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  widget.provider.name,
                  style: const TextStyle(
                    fontSize: AppText.base,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                _Fact(
                  label: _kindLabel(l10n, widget.provider.kind),
                  mono: false,
                ),
                _Fact(label: widget.provider.baseUrl),
                _Fact(label: _maskedKey),
              ],
            )
          else ...[
            _LabeledField(
              label: l10n.llmProfileName,
              controller: _name,
              onChanged: (_) => _commit(),
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(
                    l10n.llmPreset,
                    style: TextStyle(
                      fontSize: AppText.secondary,
                      color: semantic.muted,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final entry in LlmProviderProfile.presets.entries)
                        _PresetChip(
                          label: entry.key,
                          onTap: () => widget.onChanged(
                            widget.provider.copyWith(
                              kind: entry.value.$1,
                              baseUrl: entry.value.$2,
                              name: _name.text.trim(),
                              apiKey: _apiKey.text.trim(),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _LabeledField(
              label: l10n.llmBaseUrl,
              controller: _baseUrl,
              mono: true,
              onChanged: (_) => _commit(),
            ),
            const SizedBox(height: 10),
            _LabeledField(
              label: l10n.llmApiKey,
              controller: _apiKey,
              mono: true,
              obscure: true,
              onChanged: (_) => _commit(),
            ),
            const SizedBox(height: 5),
            Text(
              l10n.llmApiKeyPlaintextNote,
              style: TextStyle(fontSize: AppText.small, color: semantic.muted),
            ),
          ],
        ],
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, this.mono = true});

  final String label;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    return Text(
      label.isEmpty ? '—' : label,
      style: mono
          ? monoStyle(context, size: AppText.small, color: semantic.muted)
          : TextStyle(fontSize: AppText.small, color: semantic.muted),
    );
  }
}

class _PresetChip extends StatelessWidget {
  const _PresetChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
          decoration: BoxDecoration(
            border: Border.all(color: semantic.line),
            borderRadius: BorderRadius.circular(AppRadii.pill),
          ),
          child: Text(
            label,
            style: TextStyle(fontSize: AppText.small, color: semantic.muted),
          ),
        ),
      ),
    );
  }
}

// --- Model form -------------------------------------------------------

class _ModelForm extends StatefulWidget {
  const _ModelForm({
    super.key,
    required this.provider,
    required this.model,
    required this.onChanged,
    required this.onFetchModels,
    required this.onDelete,
  });

  final LlmProvider provider;
  final LlmModelConfig model;
  final ValueChanged<LlmModelConfig> onChanged;
  final VoidCallback onFetchModels;
  final VoidCallback onDelete;

  @override
  State<_ModelForm> createState() => _ModelFormState();
}

class _ModelFormState extends State<_ModelForm> {
  late final TextEditingController _modelId;
  late final TextEditingController _displayName;
  late final TextEditingController _maxOutput;

  @override
  void initState() {
    super.initState();
    _modelId = TextEditingController(text: widget.model.modelId);
    _displayName = TextEditingController(text: widget.model.displayName);
    _maxOutput = TextEditingController(text: '${widget.model.maxOutputTokens}');
  }

  @override
  void didUpdateWidget(_ModelForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The fetch-from-server picker writes the id from outside the form.
    if (_modelId.text != widget.model.modelId) {
      _modelId.text = widget.model.modelId;
    }
  }

  @override
  void dispose() {
    _modelId.dispose();
    _displayName.dispose();
    _maxOutput.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final semantic = context.semantic;
    final scheme = Theme.of(context).colorScheme;
    final model = widget.model;
    // Snap to the nearest stop so a value from an older build still lands on
    // the track instead of between two notches.
    var stopIndex = 0;
    for (var i = 0; i < _contextStops.length; i++) {
      if (_contextStops[i] <= model.contextWindow) stopIndex = i;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: _LabeledField(
                label: l10n.llmModel,
                controller: _modelId,
                mono: true,
                onChanged: (value) =>
                    widget.onChanged(model.copyWith(modelId: value.trim())),
              ),
            ),
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: widget.onFetchModels,
              icon: const Icon(Icons.download, size: 14),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                textStyle: const TextStyle(fontSize: AppText.secondary),
              ),
              label: Text(l10n.llmFetchModels),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _LabeledField(
          label: l10n.llmDisplayName,
          controller: _displayName,
          onChanged: (value) =>
              widget.onChanged(model.copyWith(displayName: value)),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Text(
              l10n.llmContextWindow,
              style: TextStyle(
                fontSize: AppText.secondary,
                color: semantic.muted,
              ),
            ),
            const Spacer(),
            Text(
              _formatTokens(model.contextWindow),
              style: monoStyle(
                context,
                size: AppText.secondary,
                color: scheme.onSurface,
              ),
            ),
          ],
        ),
        Slider(
          value: stopIndex.toDouble(),
          max: (_contextStops.length - 1).toDouble(),
          divisions: _contextStops.length - 1,
          label: _formatTokens(_contextStops[stopIndex]),
          onChanged: (value) => widget.onChanged(
            model.copyWith(contextWindow: _contextStops[value.round()]),
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (final stop in _contextStops)
              Text(
                _formatTokens(stop),
                style: monoStyle(
                  context,
                  size: AppText.micro,
                  color: semantic.muted,
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _LabeledField(
                label: l10n.llmMaxOutput,
                controller: _maxOutput,
                mono: true,
                keyboardType: TextInputType.number,
                onChanged: (value) {
                  final parsed = int.tryParse(value.trim());
                  if (parsed != null && parsed > 0) {
                    widget.onChanged(model.copyWith(maxOutputTokens: parsed));
                  }
                },
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        l10n.llmTemperature,
                        style: TextStyle(
                          fontSize: AppText.secondary,
                          color: semantic.muted,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        model.temperature.toStringAsFixed(2),
                        style: monoStyle(context, size: AppText.secondary),
                      ),
                    ],
                  ),
                  Slider(
                    value: model.temperature.clamp(0, 2),
                    max: 2,
                    divisions: 20,
                    onChanged: (value) =>
                        widget.onChanged(model.copyWith(temperature: value)),
                  ),
                ],
              ),
            ),
          ],
        ),
        _InlineSwitchRow(
          label: l10n.llmSupportsVision,
          description: l10n.llmSupportsVisionDesc,
          value: model.supportsVision,
          onChanged: (value) =>
              widget.onChanged(model.copyWith(supportsVision: value)),
        ),
        const SizedBox(height: 6),
        _PricingCard(
          pricing: model.pricing,
          onChanged: (pricing) => widget.onChanged(
            pricing == null
                ? model.copyWith(clearPricing: true)
                : model.copyWith(pricing: pricing),
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.llmInheritsFromProvider(widget.provider.name),
                style: TextStyle(
                  fontSize: AppText.small,
                  color: semantic.muted,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: widget.onDelete,
              icon: const Icon(Icons.delete_outline, size: 15),
              style: TextButton.styleFrom(
                foregroundColor: scheme.error,
                visualDensity: VisualDensity.compact,
                textStyle: const TextStyle(fontSize: AppText.secondary),
              ),
              label: Text(l10n.llmDeleteModel),
            ),
          ],
        ),
      ],
    );
  }
}

class _PricingCard extends StatelessWidget {
  const _PricingCard({required this.pricing, required this.onChanged});

  final LlmPricing? pricing;
  final ValueChanged<LlmPricing?> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final semantic = context.semantic;
    final enabled = pricing != null;
    final value = pricing ?? const LlmPricing();

    return Container(
      padding: EdgeInsets.fromLTRB(14, 8, 14, enabled ? 12 : 8),
      decoration: BoxDecoration(
        border: Border.all(color: semantic.line),
        borderRadius: BorderRadius.circular(AppRadii.control),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.llmPricingTitle,
                  style: const TextStyle(
                    fontSize: AppText.secondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              AppSwitch(
                value: enabled,
                onChanged: (on) => onChanged(on ? const LlmPricing() : null),
              ),
            ],
          ),
          if (enabled) ...[
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _PriceField(
                    label: l10n.llmPriceInput,
                    value: value.input,
                    onChanged: (v) => onChanged(value.copyWith(input: v)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _PriceField(
                    label: l10n.llmPriceOutput,
                    value: value.output,
                    onChanged: (v) => onChanged(value.copyWith(output: v)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _PriceField(
                    label: l10n.llmPriceCacheRead,
                    value: value.cacheRead,
                    onChanged: (v) => onChanged(value.copyWith(cacheRead: v)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _PriceField(
                    label: l10n.llmPriceCacheWrite,
                    value: value.cacheWrite,
                    onChanged: (v) => onChanged(value.copyWith(cacheWrite: v)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              l10n.llmPricingNote,
              style: TextStyle(fontSize: AppText.small, color: semantic.muted),
            ),
          ],
        ],
      ),
    );
  }
}

class _PriceField extends StatefulWidget {
  const _PriceField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  State<_PriceField> createState() => _PriceFieldState();
}

class _PriceFieldState extends State<_PriceField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value == 0 ? '' : widget.value.toStringAsFixed(2),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: AppText.micro, color: semantic.muted),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: _controller,
          keyboardType: TextInputType.number,
          style: monoStyle(context, size: AppText.secondary),
          decoration: const InputDecoration(prefixText: r'$ '),
          onChanged: (text) =>
              widget.onChanged(double.tryParse(text.trim()) ?? 0),
        ),
      ],
    );
  }
}

class _InlineSwitchRow extends StatelessWidget {
  const _InlineSwitchRow({
    required this.label,
    required this.description,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String description;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: AppText.base)),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: AppText.small,
                    color: semantic.muted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          AppSwitch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _LabeledField extends StatelessWidget {
  const _LabeledField({
    required this.label,
    required this.controller,
    required this.onChanged,
    this.mono = false,
    this.obscure = false,
    this.keyboardType,
  });

  final String label;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final bool mono;
  final bool obscure;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: AppText.secondary, color: semantic.muted),
        ),
        const SizedBox(height: 5),
        TextField(
          controller: controller,
          obscureText: obscure,
          keyboardType: keyboardType,
          onChanged: onChanged,
          style: mono
              ? monoStyle(context, size: AppText.secondary)
              : const TextStyle(fontSize: AppText.base),
        ),
      ],
    );
  }
}

/// Filterable list of the model names the server reported.
class _ModelNamePicker extends StatefulWidget {
  const _ModelNamePicker({required this.names});

  final List<String> names;

  @override
  State<_ModelNamePicker> createState() => _ModelNamePickerState();
}

class _ModelNamePickerState extends State<_ModelNamePicker> {
  String _filter = '';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final query = _filter.trim().toLowerCase();
    final visible = query.isEmpty
        ? widget.names
        : widget.names.where((n) => n.toLowerCase().contains(query)).toList();

    return AlertDialog(
      title: Text(l10n.llmModel),
      content: SizedBox(
        width: 420,
        height: 380,
        child: Column(
          children: [
            PanelSearchField(
              hint: l10n.aiModelFilterHint,
              padding: EdgeInsets.zero,
              onChanged: (value) => setState(() => _filter = value),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: visible.length,
                itemBuilder: (context, index) => ListTile(
                  dense: true,
                  title: Text(
                    visible[index],
                    style: monoStyle(context, size: AppText.secondary),
                  ),
                  onTap: () => Navigator.of(context).pop(visible[index]),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
      ],
    );
  }
}
