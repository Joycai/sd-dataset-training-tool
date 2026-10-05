import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../l10n/app_localizations.dart';
import '../../models/image_operation.dart';
import '../../models/image_operation_plan.dart';
import '../../state/image_operation_state.dart';

Future<bool> showImageOperationReview(
  BuildContext context,
  ImageOperationState state,
  ImageOperationPlan plan,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) {
        final l10n = AppLocalizations.of(context)!;
        return AlertDialog(
          title: Text(l10n.imageProcessingReview),
          content: SizedBox(
            width: 720,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('${plan.items.length} ${l10n.imageProcessingImages}'),
                  SelectableText(plan.output),
                  Text(
                    plan.replace
                        ? l10n.imageProcessingReplaceWarning
                        : l10n.imageProcessingCopyWarning,
                  ),
                  const SizedBox(height: 8),
                  Text(l10n.imageProcessingCaptionWarning),
                  if (plan.recipe.cropForeground)
                    Text(l10n.imageProcessingForegroundWarning),
                  const SizedBox(height: 12),
                  Text(
                    '${l10n.imageProcessingBefore} / ${l10n.imageProcessingAfter}',
                  ),
                  for (final preview
                      in state.previews[plan.id] ?? <ImagePreview>[]) ...[
                    Text(
                      '${p.basename(preview.source)} → ${preview.width} × ${preview.height}',
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: Image.memory(
                            preview.before,
                            height: 180,
                            fit: BoxFit.contain,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Image.memory(
                            preview.after,
                            height: 180,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 12),
                  for (final item in plan.items)
                    Text(
                      '${p.relative(item.source, from: plan.root)} → ${p.relative(item.target, from: plan.output)} (${item.sidecars.length} ${l10n.imageProcessingCaptions})',
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(l10n.imageProcessingApprove),
            ),
          ],
        );
      },
    ) ??
    false;

Future<void> showImageProcessingDialog(
  BuildContext context,
  ImageOperationState state,
) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _ImageProcessingDialog(state: state),
);

class _ImageProcessingDialog extends StatefulWidget {
  const _ImageProcessingDialog({required this.state});
  final ImageOperationState state;
  @override
  State<_ImageProcessingDialog> createState() => _ImageProcessingDialogState();
}

class _ImageProcessingDialogState extends State<_ImageProcessingDialog> {
  final _width = TextEditingController(text: '1024');
  final _height = TextEditingController(text: '1024');
  final _prefix = TextEditingController();
  final _crop = TextEditingController();
  final _operationId = TextEditingController();
  String _format = 'png', _mode = 'fit';
  String? _model;
  List<String> _models = [];
  List<ImageOperationResult> _operations = [];
  bool _resize = true,
      _replace = false,
      _remove = false,
      _foreground = false,
      _upscale = false;
  bool _working = false;
  String? _message;

  @override
  void dispose() {
    for (final controller in [_width, _height, _prefix, _crop, _operationId]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _prepare() async {
    final state = widget.state;
    setState(() {
      _working = true;
      _message = null;
    });
    try {
      final root = state.dataset.rootPath;
      if (root == null) throw StateError('Open a dataset first');
      final recipe = ImageRecipe.fromJson({
        if (_resize) 'width': int.parse(_width.text),
        if (_resize) 'height': int.parse(_height.text),
        'resize_mode': _mode,
        'format': _format,
        'upscale': _upscale,
        if (_format == 'jpeg' || _mode == 'pad') 'background': [255, 255, 255],
        if (_prefix.text.trim().isNotEmpty) 'prefix': _prefix.text.trim(),
        if (_crop.text.trim().isNotEmpty)
          'crop': _crop.text
              .split(',')
              .map((v) => int.parse(v.trim()))
              .toList(),
        'remove_background': _remove,
        'crop_foreground': _foreground,
        if (_remove || _foreground) 'model': _model,
      });
      final plan = await state.prepare(
        paths: state.dataset.scopedFiles
            .map((f) => p.relative(f.path, from: root))
            .toList(),
        recipe: recipe,
        replace: _replace,
      );
      _operationId.text = plan.id;
      if (!mounted) return;
      if (await showImageOperationReview(context, state, plan)) {
        final result = await state.apply(plan.id, plan.digest, approved: true);
        _message =
            '${result.status}: ${result.completed}/${result.total}\n${plan.output}\n${result.error ?? ''}';
      }
    } catch (e) {
      _message = '$e';
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _undo() async {
    setState(() => _working = true);
    try {
      final result = await widget.state.undo(
        _operationId.text.trim(),
        approved: true,
      );
      _message = result.status;
    } catch (e) {
      _message = '$e';
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(l10n.imageProcessingTitle),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.imageProcessingScope),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.imageProcessingResize),
                value: _resize,
                onChanged: _working ? null : (v) => setState(() => _resize = v),
              ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _width,
                      enabled: !_working && _resize,
                      decoration: InputDecoration(
                        labelText: l10n.imageProcessingWidth,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _height,
                      enabled: !_working && _resize,
                      decoration: InputDecoration(
                        labelText: l10n.imageProcessingHeight,
                      ),
                    ),
                  ),
                ],
              ),
              DropdownButton<String>(
                value: _mode,
                isExpanded: true,
                items: [
                  DropdownMenuItem(
                    value: 'fit',
                    child: Text(l10n.imageProcessingFit),
                  ),
                  DropdownMenuItem(
                    value: 'crop',
                    child: Text(l10n.imageProcessingCenterCrop),
                  ),
                  DropdownMenuItem(
                    value: 'pad',
                    child: Text(l10n.imageProcessingPad),
                  ),
                ],
                onChanged: _working ? null : (v) => setState(() => _mode = v!),
              ),
              DropdownButton<String>(
                value: _format,
                isExpanded: true,
                items: [
                  const DropdownMenuItem(value: 'png', child: Text('PNG')),
                  const DropdownMenuItem(value: 'jpeg', child: Text('JPEG')),
                  DropdownMenuItem(
                    value: 'keep',
                    child: Text(l10n.imageProcessingOriginal),
                  ),
                ],
                onChanged: _working
                    ? null
                    : (v) => setState(() {
                        _format = v!;
                        if (v == 'keep') {
                          _resize = false;
                          _remove = false;
                          _foreground = false;
                          _crop.clear();
                        }
                      }),
              ),
              TextField(
                controller: _prefix,
                enabled: !_working,
                decoration: InputDecoration(
                  labelText: l10n.imageProcessingPrefix,
                ),
              ),
              TextField(
                controller: _crop,
                enabled: !_working && !_foreground,
                decoration: InputDecoration(
                  labelText: l10n.imageProcessingCrop,
                ),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.imageProcessingUpscale),
                value: _upscale,
                onChanged: _working
                    ? null
                    : (v) => setState(() => _upscale = v!),
              ),
              TextButton(
                onPressed: _working
                    ? null
                    : () async {
                        setState(() => _working = true);
                        try {
                          _models = await widget.state.ai.models(
                            widget.state.serverUrl(),
                          );
                          _model = _models.firstOrNull;
                        } catch (e) {
                          _message = '$e';
                        } finally {
                          if (mounted) setState(() => _working = false);
                        }
                      },
                child: Text(l10n.imageProcessingLoadModels),
              ),
              if (_models.isNotEmpty)
                DropdownButton<String>(
                  value: _model,
                  isExpanded: true,
                  items: [
                    for (final m in _models)
                      DropdownMenuItem(value: m, child: Text(m)),
                  ],
                  onChanged: _working
                      ? null
                      : (v) => setState(() => _model = v),
                ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.imageProcessingRemoveBackground),
                value: _remove,
                onChanged: _working || _model == null
                    ? null
                    : (v) => setState(() => _remove = v!),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.imageProcessingCropForeground),
                value: _foreground,
                onChanged: _working || _model == null
                    ? null
                    : (v) => setState(() => _foreground = v!),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.imageProcessingReplace),
                value: _replace,
                onChanged: _working
                    ? null
                    : (v) => setState(() => _replace = v!),
              ),
              Text(l10n.imageProcessingCaptionWarning),
              if (_working)
                ListenableBuilder(
                  listenable: widget.state,
                  builder: (_, _) =>
                      Text('${widget.state.completed}/${widget.state.total}'),
                ),
              if (_message != null) SelectableText(_message!),
              TextButton(
                onPressed: _working
                    ? null
                    : () async {
                        try {
                          _operations = await widget.state.listOperations();
                        } catch (e) {
                          _message = '$e';
                        }
                        if (mounted) setState(() {});
                      },
                child: Text(l10n.imageProcessingSaved),
              ),
              for (final operation in _operations.take(20))
                ListTile(
                  dense: true,
                  title: Text(operation.id),
                  subtitle: Text(
                    '${operation.status} (${operation.completed}/${operation.total})',
                  ),
                  onTap: _working
                      ? null
                      : () => setState(() => _operationId.text = operation.id),
                ),
              TextField(
                controller: _operationId,
                enabled: !_working,
                decoration: InputDecoration(
                  labelText: l10n.imageProcessingOperationId,
                ),
              ),
              TextButton(
                onPressed: _working ? null : _undo,
                child: Text(l10n.imageProcessingUndo),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _working
              ? widget.state.cancel
              : () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: _working ? null : _prepare,
          child: Text(l10n.imageProcessingReview),
        ),
      ],
    );
  }
}
