import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../l10n/app_localizations.dart';
import '../models/caption_type.dart';
import '../theme/app_theme.dart';

/// The navigator's caption-type switcher, shown only when more than one
/// type is enabled in the settings.
///
/// Like the subdirectory picker above it, this is not a display filter:
/// picking a type changes which caption files the entire app — editor,
/// batch operations, assistant — reads and writes. The workbench rescans
/// the dataset when the active extension changes.
class CaptionTypePicker extends StatelessWidget {
  const CaptionTypePicker({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final semantic = context.semantic;
    final scheme = Theme.of(context).colorScheme;
    final app = context.watch<AppState>();
    final types = app.enabledCaptionTypes;
    final active = app.activeCaptionType;
    // The default type is the resting state; anything else is highlighted
    // the same way an active subdirectory scope is.
    final variant = !active.isDefault;

    return Tooltip(
      message: l10n.captionTypePickerTooltip,
      waitDuration: const Duration(milliseconds: 600),
      child: Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: semantic.raised,
          border: Border.all(
            color: variant ? scheme.primary.withAlpha(140) : semantic.line,
          ),
          borderRadius: BorderRadius.circular(AppRadii.input),
        ),
        child: Row(
          children: [
            Icon(
              variant ? Icons.notes : Icons.notes_outlined,
              size: 14,
              color: variant ? scheme.primary : semantic.muted,
            ),
            const SizedBox(width: 7),
            Expanded(
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: active.id,
                  isExpanded: true,
                  isDense: true,
                  icon: Icon(
                    Icons.expand_more,
                    size: 16,
                    color: semantic.muted,
                  ),
                  style: TextStyle(
                    fontSize: AppText.secondary,
                    color: scheme.onSurface,
                  ),
                  onChanged: (id) {
                    if (id != null) {
                      context.read<AppState>().setActiveCaptionType(id);
                    }
                  },
                  items: [for (final type in types) _item(context, type)],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  DropdownMenuItem<String> _item(BuildContext context, CaptionType type) {
    final semantic = context.semantic;
    return DropdownMenuItem<String>(
      value: type.id,
      child: Row(
        children: [
          Expanded(
            child: Text(
              type.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: AppText.secondary),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            type.extension,
            style: monoStyle(
              context,
              size: AppText.micro,
              color: semantic.muted,
            ),
          ),
        ],
      ),
    );
  }
}
