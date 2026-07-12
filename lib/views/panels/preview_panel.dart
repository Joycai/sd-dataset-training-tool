import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../state/dataset_state.dart';
import '../../state/editor_session.dart';
import '../../theme/app_theme.dart';

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

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border.all(color: semantic.line),
        borderRadius: BorderRadius.circular(10),
      ),
      child: file == null
          ? _EmptyPreview(message: l10n.selectImageHint)
          : Stack(
              fit: StackFit.expand,
              children: [
                InteractiveViewer(
                  transformationController: _transformation,
                  minScale: 0.1,
                  maxScale: 8,
                  child: Center(
                    child: Image.file(
                      file,
                      fit: BoxFit.contain,
                      gaplessPlayback: true,
                      errorBuilder: (context, error, stackTrace) =>
                          const Icon(Icons.broken_image_outlined, size: 40),
                    ),
                  ),
                ),
                Positioned(
                  left: 10,
                  top: 10,
                  right: 10,
                  child: Row(
                    children: [
                      Flexible(
                        child: _OverlayPill(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: Text(
                                  p.basename(file.path),
                                  overflow: TextOverflow.ellipsis,
                                  style: monoStyle(context,
                                      size: 11.5, color: Colors.white),
                                ),
                              ),
                              if (session.imageWidth != null) ...[
                                const SizedBox(width: 8),
                                Text(
                                  '${session.imageWidth} x ${session.imageHeight}',
                                  style: monoStyle(context,
                                      size: 11.5,
                                      color: const Color(0xFF9AA3B4)),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  bottom: 10,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: _OverlayPill(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _OverlayButton(
                            icon: Icons.chevron_left,
                            tooltip: l10n.previousImage,
                            onPressed: index > 0
                                ? () => dataset.selectByOffset(-1)
                                : null,
                          ),
                          Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 6),
                            child: Text(
                              '${index + 1} / ${visible.length}',
                              style: monoStyle(context,
                                  size: 11.5, color: const Color(0xFF9AA3B4)),
                            ),
                          ),
                          _OverlayButton(
                            icon: Icons.chevron_right,
                            tooltip: l10n.nextImage,
                            onPressed: index < visible.length - 1
                                ? () => dataset.selectByOffset(1)
                                : null,
                          ),
                          Container(
                            width: 1,
                            height: 16,
                            margin: const EdgeInsets.symmetric(horizontal: 6),
                            color: Colors.white24,
                          ),
                          _OverlayButton(
                            icon: Icons.fit_screen_outlined,
                            tooltip: l10n.fitToWindow,
                            onPressed: () =>
                                _transformation.value = Matrix4.identity(),
                          ),
                          _OverlayButton(
                            icon: Icons.open_in_new,
                            tooltip: l10n.openInNewWindow,
                            onPressed: widget.onOpenExternalPreview,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _OverlayPill extends StatelessWidget {
  const _OverlayPill({
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: const Color(0xB80C0E12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: child,
    );
  }
}

class _OverlayButton extends StatelessWidget {
  const _OverlayButton({
    required this.icon,
    required this.tooltip,
    this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: 18),
      tooltip: tooltip,
      onPressed: onPressed,
      color: Colors.white,
      disabledColor: Colors.white30,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
      padding: EdgeInsets.zero,
    );
  }
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
          Text(
            message,
            style: TextStyle(fontSize: 13, color: semantic.muted),
          ),
        ],
      ),
    );
  }
}
