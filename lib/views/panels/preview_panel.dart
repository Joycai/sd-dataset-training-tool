import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../state/dataset_state.dart';
import '../../state/editor_session.dart';
import '../../theme/app_theme.dart';
import '../../widgets/panel_widgets.dart';

/// Zoom floor. InteractiveViewer's default zero boundary margin requires the
/// child to keep covering the viewport, and the child here *is* the viewport —
/// so the fitted view is the smallest reachable scale, whatever `minScale`
/// claims. Naming it 1.0 keeps the readout and the buttons honest.
const double _minScale = 1.0;
const double _maxScale = 8;
const double _zoomStep = 1.25;

/// Center-top: the inline preview. Shows the selected image with pan/zoom,
/// a filename/resolution chip, and previous/next + window controls.
class PreviewPanel extends StatefulWidget {
  const PreviewPanel({super.key, required this.onOpenExternalPreview});

  final VoidCallback onOpenExternalPreview;

  @override
  State<PreviewPanel> createState() => _PreviewPanelState();
}

class _PreviewPanelState extends State<PreviewPanel> {
  final TransformationController _transformation = TransformationController();
  ImageStream? _imageStream;
  ImageStreamListener? _imageListener;
  String? _resolvedPath;

  @override
  void dispose() {
    _detachImageStream();
    _transformation.dispose();
    super.dispose();
  }

  void _detachImageStream() {
    if (_imageStream != null && _imageListener != null) {
      _imageStream!.removeListener(_imageListener!);
    }
    _imageStream = null;
    _imageListener = null;
  }

  /// Zooms by [factor] about the middle of the viewport, so the part of the
  /// picture you are looking at stays put.
  ///
  /// The matrix is written out by hand rather than composed from
  /// translate/scale helpers: for a 2D transform, `T(c)·S(k)·T(-c)` is just
  /// a scale on the diagonal plus an offset, and spelling it out avoids
  /// depending on vector_math's shifting helper signatures.
  void _zoomBy(double factor) {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    final current = _transformation.value.getMaxScaleOnAxis();
    final target = (current * factor).clamp(_minScale, _maxScale);
    if (target == current) return;
    final k = target / current;
    final centre = box.size.center(Offset.zero);
    final step = Matrix4.identity()
      ..setEntry(0, 0, k)
      ..setEntry(1, 1, k)
      ..setEntry(0, 3, centre.dx * (1 - k))
      ..setEntry(1, 3, centre.dy * (1 - k));
    _transformation.value = step.multiplied(_transformation.value);
  }

  void _resetZoom() => _transformation.value = Matrix4.identity();

  /// Reads the decoded dimensions off the image cache (the same FileImage is
  /// used for display, so this does not decode twice). Deferred to after the
  /// frame: a cached image completes synchronously on addListener, and the
  /// resulting notifyListeners must not fire during build.
  void _resolveDimensions(File file, EditorSession session) {
    if (_resolvedPath == file.path) return;
    _resolvedPath = file.path;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _resolvedPath != file.path) return;
      _detachImageStream();
      _transformation.value = Matrix4.identity();

      final stream = FileImage(file).resolve(const ImageConfiguration());
      final listener = ImageStreamListener((info, _) {
        session.setImageDimensions(info.image.width, info.image.height);
        info.dispose();
      }, onError: (_, _) {});
      _imageStream = stream;
      _imageListener = listener;
      stream.addListener(listener);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final semantic = context.semantic;
    final scheme = Theme.of(context).colorScheme;
    final dataset = context.watch<DatasetState>();
    final session = context.watch<EditorSession>();
    final file = dataset.selectedFile;

    if (file != null) {
      _resolveDimensions(file, session);
    } else {
      _resolvedPath = null;
      _detachImageStream();
    }

    final visible = dataset.visibleFiles;
    final index = dataset.selectedVisibleIndex;

    if (file == null) {
      return ColoredBox(
        color: scheme.surface,
        child: _EmptyPreview(message: l10n.selectImageHint),
      );
    }

    // Generated frame names run long, so only the name gives way. The
    // resolution and size are the half worth keeping for dataset work.
    final facts = [
      if (session.imageWidth != null)
        '${session.imageWidth} × ${session.imageHeight}',
      if (session.imageBytes != null) _formatBytes(session.imageBytes!),
    ].join('  ·  ');

    return ColoredBox(
      color: scheme.surface,
      child: Stack(
        fit: StackFit.expand,
        children: [
          InteractiveViewer(
            transformationController: _transformation,
            minScale: _minScale,
            maxScale: _maxScale,
            child: Center(
              // The rounded corners and the drop shadow belong to the image,
              // not to a frame around it: the canvas itself is the window
              // background, so the picture reads as a sheet lying on it.
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadii.window),
                  boxShadow: [
                    BoxShadow(
                      color: semantic.shadow,
                      blurRadius: 40,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadii.window),
                  child: Image.file(
                    file,
                    fit: BoxFit.contain,
                    gaplessPlayback: true,
                    errorBuilder: (context, error, stackTrace) =>
                        const Icon(Icons.broken_image_outlined, size: 40),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 12,
            left: 14,
            right: 14,
            child: IgnorePointer(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      p.basename(file.path),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: monoStyle(
                        context,
                        size: AppText.small,
                        color: semantic.muted,
                      ),
                    ),
                  ),
                  if (facts.isNotEmpty)
                    Text(
                      '  ·  $facts',
                      style: monoStyle(
                        context,
                        size: AppText.small,
                        color: semantic.muted,
                      ),
                    ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 16,
            top: 0,
            bottom: 0,
            child: Center(
              child: _StepButton(
                icon: Icons.chevron_left,
                tooltip: l10n.previousImage,
                onPressed: index > 0 ? () => dataset.selectByOffset(-1) : null,
              ),
            ),
          ),
          Positioned(
            right: 16,
            top: 0,
            bottom: 0,
            child: Center(
              child: _StepButton(
                icon: Icons.chevron_right,
                tooltip: l10n.nextImage,
                onPressed: index < visible.length - 1
                    ? () => dataset.selectByOffset(1)
                    : null,
              ),
            ),
          ),
          Positioned(
            bottom: 12,
            left: 14,
            right: 14,
            child: Center(
              child: _CanvasControlBar(
                transformation: _transformation,
                onZoomOut: () => _zoomBy(1 / _zoomStep),
                onZoomIn: () => _zoomBy(_zoomStep),
                onFit: _resetZoom,
                onOpenExternal: widget.onOpenExternalPreview,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Round previous/next button floating over the canvas edges.
class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    final enabled = onPressed != null;
    return Tooltip(
      message: tooltip,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: GestureDetector(
          onTap: onPressed,
          child: Opacity(
            opacity: enabled ? 1 : 0.35,
            child: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: semantic.raised,
                shape: BoxShape.circle,
                border: Border.all(color: semantic.line),
              ),
              child: Icon(icon, size: 18, color: semantic.muted),
            ),
          ),
        ),
      ),
    );
  }
}

/// Frosted capsule at the bottom of the canvas: zoom, fit, detach.
class _CanvasControlBar extends StatelessWidget {
  const _CanvasControlBar({
    required this.transformation,
    required this.onZoomOut,
    required this.onZoomIn,
    required this.onFit,
    required this.onOpenExternal,
  });

  final TransformationController transformation;
  final VoidCallback onZoomOut;
  final VoidCallback onZoomIn;
  final VoidCallback onFit;
  final VoidCallback onOpenExternal;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final semantic = context.semantic;

    // The bar is centred over the canvas, so its width budget is whatever
    // the canvas has. Below that budget the two labelled actions collapse
    // to their icons rather than overflowing the capsule.
    return LayoutBuilder(
      builder: (context, constraints) {
        // The labelled bar wants roughly 330px; below that the two labels
        // drop to icons. FittedBox below is the backstop for the last few
        // pixels when font metrics push past the estimate.
        final compact = constraints.maxWidth < 330;
        // Dropping the labels covers the narrow-canvas case; scaleDown is
        // the backstop for metrics the threshold cannot predict (wide CJK
        // fonts, long translations) so the capsule can never overflow.
        return FittedBox(
          fit: BoxFit.scaleDown,
          child: GlassSurface(
            borderRadius: BorderRadius.circular(AppRadii.pill),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Only the zoom trio listens to the controller, so panning
                // and pinching don't rebuild the rest of the canvas.
                ValueListenableBuilder<Matrix4>(
                  valueListenable: transformation,
                  builder: (context, matrix, _) {
                    final scale = matrix.getMaxScaleOnAxis();
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _BarAction(
                          icon: Icons.remove,
                          tooltip: l10n.zoomOut,
                          onPressed: scale > _minScale + 1e-6
                              ? onZoomOut
                              : null,
                        ),
                        SizedBox(
                          width: 46,
                          child: Text(
                            // 100% is the fitted view — the scale the "fit"
                            // button restores, not a 1:1 source-pixel ratio.
                            '${(scale * 100).round()}%',
                            textAlign: TextAlign.center,
                            style: monoStyle(
                              context,
                              size: AppText.secondary,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                        ),
                        _BarAction(
                          icon: Icons.add,
                          tooltip: l10n.zoomIn,
                          onPressed: scale < _maxScale - 1e-6 ? onZoomIn : null,
                        ),
                      ],
                    );
                  },
                ),
                Container(
                  width: 1,
                  height: 14,
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  color: semantic.line,
                ),
                _BarAction(
                  icon: Icons.fit_screen_outlined,
                  label: compact ? null : l10n.fitToWindow,
                  tooltip: l10n.fitToWindow,
                  onPressed: onFit,
                ),
                _BarAction(
                  icon: Icons.open_in_full,
                  label: compact ? null : l10n.openInNewWindow,
                  tooltip: l10n.openInNewWindow,
                  onPressed: onOpenExternal,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _BarAction extends StatefulWidget {
  const _BarAction({
    this.icon,
    this.label,
    this.tooltip,
    required this.onPressed,
  });

  final IconData? icon;
  final String? label;
  final String? tooltip;

  /// Null disables the action — used by the zoom buttons at their limits.
  final VoidCallback? onPressed;

  @override
  State<_BarAction> createState() => _BarActionState();
}

class _BarActionState extends State<_BarAction> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final semantic = context.semantic;
    final enabled = widget.onPressed != null;
    final color = !enabled
        ? semantic.muted.withValues(alpha: 0.4)
        : _hovered
        ? scheme.onSurface
        : semantic.muted;

    Widget content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.icon != null) Icon(widget.icon, size: 15, color: color),
        if (widget.icon != null && widget.label != null)
          const SizedBox(width: 5),
        if (widget.label != null)
          Text(
            widget.label!,
            style: TextStyle(fontSize: AppText.secondary, color: color),
          ),
      ],
    );

    if (widget.tooltip != null) {
      content = Tooltip(message: widget.tooltip!, child: content);
    }

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
          child: content,
        ),
      ),
    );
  }
}

String _formatBytes(int bytes) {
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / 1024).round()} KB';
}

class _EmptyPreview extends StatelessWidget {
  const _EmptyPreview({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.image_outlined, size: 36, color: semantic.muted),
          const SizedBox(height: 10),
          Text(message, style: TextStyle(fontSize: 13, color: semantic.muted)),
        ],
      ),
    );
  }
}
