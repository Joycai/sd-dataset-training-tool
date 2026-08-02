import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';

/// What the merge dialog came back with.
typedef MergeTagsInput = ({String target, bool rewriteCaptions});

/// Asks which single tag [tags] should collapse into, and whether the dataset's
/// captions should follow.
///
/// The caption rewrite is a switch rather than an implied side effect: merging
/// two entries in the library is a filing decision, while rewriting a few
/// hundred caption files is a dataset edit, and the two are not always wanted
/// together. It defaults on when there is a dataset to rewrite, because a
/// merge that leaves the old spellings on disk usually means doing the work
/// twice.
Future<MergeTagsInput?> showMergeTagsDialog(
  BuildContext context, {
  required List<String> tags,
  required bool canRewriteCaptions,
}) {
  return showDialog<MergeTagsInput>(
    context: context,
    builder: (context) =>
        _MergeTagsDialog(tags: tags, canRewriteCaptions: canRewriteCaptions),
  );
}

class _MergeTagsDialog extends StatefulWidget {
  const _MergeTagsDialog({
    required this.tags,
    required this.canRewriteCaptions,
  });

  final List<String> tags;
  final bool canRewriteCaptions;

  @override
  State<_MergeTagsDialog> createState() => _MergeTagsDialogState();
}

class _MergeTagsDialogState extends State<_MergeTagsDialog> {
  late final TextEditingController _controller = TextEditingController(
    // The first selected tag is the likeliest survivor of a near-duplicate
    // cluster, and it is one keystroke away from being any of the others.
    text: widget.tags.isEmpty ? '' : widget.tags.first,
  );
  late bool _rewrite = widget.canRewriteCaptions;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final target = _controller.text.trim();
    if (target.isEmpty) return;
    Navigator.of(context).pop((target: target, rewriteCaptions: _rewrite));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final semantic = context.semantic;

    return AlertDialog(
      title: Text(l10n.mergeTagsTitle),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.mergeTagsSources(widget.tags.length),
              style: TextStyle(fontSize: AppText.small, color: semantic.muted),
            ),
            const SizedBox(height: 6),
            // The full list, so a stray selection is caught before the merge
            // rather than after it.
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 96),
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final tag in widget.tags)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: semantic.raised,
                          border: Border.all(color: semantic.line),
                          borderRadius: BorderRadius.circular(AppRadii.pill),
                        ),
                        child: Text(
                          tag,
                          style: TextStyle(
                            fontSize: AppText.small,
                            color: semantic.muted,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _controller,
              autofocus: true,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(labelText: l10n.mergeTagsTargetLabel),
            ),
            if (widget.canRewriteCaptions) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.mergeTagsRewriteCaptions,
                          style: const TextStyle(fontSize: AppText.secondary),
                        ),
                        Text(
                          l10n.mergeTagsRewriteHint,
                          style: TextStyle(
                            fontSize: AppText.small,
                            color: semantic.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Switch(
                    value: _rewrite,
                    onChanged: (value) => setState(() => _rewrite = value),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        TextButton(onPressed: _submit, child: Text(l10n.confirm)),
      ],
    );
  }
}
