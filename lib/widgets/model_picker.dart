import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/ai_tagger_models.dart';
import '../state/ai_tagger_state.dart';
import '../theme/app_theme.dart';

/// Grouped model picker, shared by the AI params dialog and the batch tagging
/// dialog. A plain DropdownButtonFormField cannot express section headers, a
/// collapsed legacy group, a filter box, or per-item tooltips, so this uses
/// MenuAnchor (standard M3, themed via MenuStyle) with a custom item list.
class ModelPickerField extends StatefulWidget {
  const ModelPickerField({super.key, required this.ai, required this.l10n});

  final AiTaggerState ai;
  final AppLocalizations l10n;

  @override
  State<ModelPickerField> createState() => _ModelPickerFieldState();
}

class _ModelPickerFieldState extends State<ModelPickerField> {
  final MenuController _menu = MenuController();

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    final scheme = Theme.of(context).colorScheme;
    final ai = widget.ai;
    final l10n = widget.l10n;

    AiModelInfo? selected;
    for (final m in ai.models) {
      if (m.modelName == ai.modelName) {
        selected = m;
        break;
      }
    }

    return MenuAnchor(
      controller: _menu,
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(semantic.raised),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(7),
            side: BorderSide(color: semantic.line),
          ),
        ),
        padding: const WidgetStatePropertyAll(EdgeInsets.zero),
      ),
      menuChildren: [
        _ModelMenu(
          ai: ai,
          l10n: l10n,
          onPicked: (name) {
            ai.setModelName(name);
            _menu.close();
          },
        ),
      ],
      builder: (context, controller, child) {
        return InkWell(
          borderRadius: BorderRadius.circular(7),
          onTap: ai.models.isEmpty
              ? null
              : () => controller.isOpen ? controller.close() : controller.open(),
          child: InputDecorator(
            decoration: const InputDecoration(),
            isEmpty: false,
            child: Row(
              children: [
                Expanded(
                  child: selected == null
                      ? Text(
                          l10n.aiNoModels,
                          overflow: TextOverflow.ellipsis,
                          style:
                              TextStyle(fontSize: 12.5, color: semantic.muted),
                        )
                      : Text(
                          selected.modelName,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 12.5, color: scheme.onSurface),
                        ),
                ),
                if (selected != null && selected.recommended) ...[
                  const SizedBox(width: 6),
                  _ModelBadge(
                      text: l10n.aiBadgeRecommended, color: semantic.ok),
                ],
                const SizedBox(width: 4),
                Icon(Icons.arrow_drop_down, size: 18, color: semantic.muted),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The dropdown panel: filter box, grouped rows, collapsible legacy rows,
/// VRAM footnote. Owns its own filter/expansion state so setState rebuilds
/// stay inside the overlay.
class _ModelMenu extends StatefulWidget {
  const _ModelMenu({
    required this.ai,
    required this.l10n,
    required this.onPicked,
  });

  final AiTaggerState ai;
  final AppLocalizations l10n;
  final ValueChanged<String> onPicked;

  @override
  State<_ModelMenu> createState() => _ModelMenuState();
}

class _ModelMenuState extends State<_ModelMenu> {
  final TextEditingController _filter = TextEditingController();
  // The menu panel already owns the PrimaryScrollController; the inner list
  // needs its own so the two scrollables don't fight over one position.
  final ScrollController _scroll = ScrollController();
  final Set<String> _expandedLegacy = {};

  @override
  void dispose() {
    _filter.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    final l10n = widget.l10n;
    final models = widget.ai.models;
    final query = _filter.text.trim().toLowerCase();
    final hasCategories = models.any((m) => m.category.isNotEmpty);

    bool matches(AiModelInfo m) =>
        query.isEmpty || m.modelName.toLowerCase().contains(query);

    final rows = <Widget>[];
    if (!hasCategories) {
      // Old server without metadata: flat, ungrouped list.
      rows.addAll([for (final m in models.where(matches)) _row(m)]);
    } else {
      final sections = [
        (l10n.aiModelGroupTag, Icons.sell_outlined,
            models.where((m) => m.category == 'tag').toList()),
        (l10n.aiModelGroupCaption, Icons.notes,
            models.where((m) => m.category != 'tag').toList()),
      ];
      for (final (title, icon, sectionModels) in sections) {
        final current =
            sectionModels.where((m) => !m.legacy && matches(m)).toList();
        final legacy =
            sectionModels.where((m) => m.legacy && matches(m)).toList();
        if (current.isEmpty && legacy.isEmpty) continue;
        rows.add(_sectionHeader(title, icon));
        rows.addAll(current.map(_row));
        if (legacy.isNotEmpty) {
          // While filtering, show matching legacy rows inline instead of
          // hiding them behind the collapse.
          if (query.isNotEmpty) {
            rows.addAll(legacy.map(_row));
          } else {
            final expanded = _expandedLegacy.contains(title);
            rows.add(_legacyToggle(title, legacy.length, expanded));
            if (expanded) rows.addAll(legacy.map(_row));
          }
        }
      }
    }
    if (rows.isEmpty) {
      rows.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: Text(l10n.aiModelFilterNoMatch,
              style: TextStyle(fontSize: 12, color: semantic.muted)),
        ),
      ));
    }

    return SizedBox(
      width: 372,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
            child: TextField(
              controller: _filter,
              autofocus: true,
              style: const TextStyle(fontSize: 12.5),
              decoration: InputDecoration(
                hintText: l10n.aiModelFilterHint,
                prefixIcon:
                    Icon(Icons.search, size: 15, color: semantic.muted),
                prefixIconConstraints:
                    const BoxConstraints(minWidth: 30, minHeight: 28),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: SingleChildScrollView(
                controller: _scroll,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: rows,
                ),
              ),
            ),
          ),
          if (hasCategories) ...[
            Divider(height: 1, color: semantic.line),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 7),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 12, color: semantic.muted),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(l10n.aiVramFootnote,
                        style:
                            TextStyle(fontSize: 11, color: semantic.muted)),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _sectionHeader(String title, IconData icon) {
    final semantic = context.semantic;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 3),
      child: Row(
        children: [
          Icon(icon, size: 13, color: semantic.muted),
          const SizedBox(width: 6),
          Text(title,
              style: TextStyle(fontSize: 11, color: semantic.muted)),
        ],
      ),
    );
  }

  Widget _legacyToggle(String section, int count, bool expanded) {
    final semantic = context.semantic;
    return InkWell(
      onTap: () => setState(() {
        expanded ? _expandedLegacy.remove(section) : _expandedLegacy.add(section);
      }),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 5, 10, 5),
        child: Row(
          children: [
            Icon(expanded ? Icons.expand_more : Icons.chevron_right,
                size: 14, color: semantic.muted),
            const SizedBox(width: 4),
            Text(widget.l10n.aiModelLegacyGroup(count),
                style: TextStyle(fontSize: 11.5, color: semantic.muted)),
          ],
        ),
      ),
    );
  }

  Widget _row(AiModelInfo m) {
    final semantic = context.semantic;
    final scheme = Theme.of(context).colorScheme;
    final l10n = widget.l10n;
    final isSelected = m.modelName == widget.ai.modelName;
    // Show the repo name without the org prefix; the full name lives in the
    // info tooltip and the closed field.
    final slash = m.modelName.indexOf('/');
    final shortName =
        slash > 0 ? m.modelName.substring(slash + 1) : m.modelName;
    final highVram = m.vramGb >= 12;
    final nameColor = m.legacy
        ? semantic.muted
        : (isSelected ? scheme.primary : scheme.onSurface);

    return InkWell(
      onTap: () => widget.onPicked(m.modelName),
      child: Container(
        color: isSelected
            ? scheme.primary.withValues(alpha: 0.10)
            : Colors.transparent,
        padding: const EdgeInsets.fromLTRB(24, 5, 10, 5),
        child: Row(
          children: [
            Expanded(
              child: Text(
                shortName,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12.5, color: nameColor),
              ),
            ),
            if (m.recommended) ...[
              const SizedBox(width: 6),
              _ModelBadge(text: l10n.aiBadgeRecommended, color: semantic.ok),
            ],
            if (m.uncensored) ...[
              const SizedBox(width: 6),
              _ModelBadge(text: l10n.aiBadgeUncensored, color: scheme.error),
            ],
            if (m.vramGb > 0) ...[
              const SizedBox(width: 6),
              Text(
                _vramLabel(m.vramGb),
                style: monoStyle(context,
                    size: 10.5,
                    color: highVram ? semantic.warn : semantic.muted),
              ),
            ],
            if (m.description.isNotEmpty || m.advice.isNotEmpty) ...[
              const SizedBox(width: 6),
              Tooltip(
                margin: const EdgeInsets.symmetric(horizontal: 60),
                richMessage: TextSpan(
                  children: [
                    TextSpan(
                      text: '${m.modelName}\n\n',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    TextSpan(text: m.description),
                    if (m.advice.isNotEmpty)
                      TextSpan(text: '\n\n${m.advice}'),
                  ],
                ),
                child:
                    Icon(Icons.info_outline, size: 14, color: semantic.muted),
              ),
            ],
            if (isSelected) ...[
              const SizedBox(width: 6),
              Icon(Icons.check, size: 14, color: scheme.primary),
            ],
          ],
        ),
      ),
    );
  }

  static String _vramLabel(double gb) {
    final n = gb == gb.roundToDouble() ? gb.toInt().toString() : gb.toString();
    return gb >= 12 ? '${n}G+' : '~${n}G';
  }
}

/// A small tinted pill, e.g. "recommended" / "uncensored".
class _ModelBadge extends StatelessWidget {
  const _ModelBadge({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(text, style: TextStyle(fontSize: 10.5, color: color)),
    );
  }
}
