import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../services/preview_window_launcher.dart';
import '../services/settings_service.dart';
import '../state/ai_tagger_state.dart';
import '../state/dataset_state.dart';
import '../state/editor_session.dart';
import '../state/tag_ops.dart';
import '../widgets/resize_handle.dart';
import '../widgets/status_bar.dart';
import '../widgets/workbench_top_bar.dart';
import 'panels/assets_panel.dart';
import 'panels/caption_panel.dart';
import 'panels/preview_panel.dart';
import 'panels/tag_library_panel.dart';

/// The main editing surface: assets panel, inline preview + caption editor,
/// and the tag library, wired to the shared [DatasetState] / [EditorSession].
class WorkbenchView extends StatefulWidget {
  const WorkbenchView({super.key});

  @override
  State<WorkbenchView> createState() => _WorkbenchViewState();
}

class _WorkbenchViewState extends State<WorkbenchView> {
  // Side panels stay usable within these bounds; the center column always
  // keeps at least [_centerMinWidth] for the preview and editor.
  static const double _panelMinWidth = 200;
  static const double _panelMaxWidth = 480;
  static const double _centerMinWidth = 320;
  static const double _handleWidth = 7;
  // Vertical split of the center column: both panes keep a usable minimum.
  static const double _previewMinHeight = 160;
  static const double _captionMinHeight = 150;

  final DatasetState _dataset = DatasetState();
  final EditorSession _session = EditorSession();
  final AiTaggerState _aiTagger = AiTaggerState(SettingsService());
  late final TagOps _tagOps = TagOps(
    dataset: _dataset,
    // Flush pending editor changes before any batch rewrite so they can't be
    // overwritten, then reload the open image if the batch touched it.
    beforeMutate: () => _session.flush(),
    onCaptionsChanged: _reloadSessionIfTouched,
  );
  final PreviewWindowLauncher _previewWindow = PreviewWindowLauncher();
  final FocusNode _libraryFilterFocus = FocusNode();
  String? _lastLoadedPath;
  late double _leftWidth;
  late double _rightWidth;
  late double _centerSplit;
  // Drag anchor: pointer x and panel width at drag start. Widths are computed
  // from the anchor on every update, so events arriving between frames can
  // never be lost to a stale build snapshot.
  double _dragAnchorX = 0;
  double _dragStartWidth = 0;
  double _dragAnchorY = 0;
  double _dragStartTopHeight = 0;

  @override
  void initState() {
    super.initState();
    final appState = context.read<AppState>();
    _leftWidth = appState.leftPanelWidth;
    _rightWidth = appState.rightPanelWidth;
    _centerSplit = appState.centerSplit;
    _session.onSaved = _dataset.updateCaptionText;
    _dataset.addListener(_onDatasetChanged);
    _aiTagger.loadSettings();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final appState = context.read<AppState>();
      final directory = appState.browsingDirectory;
      if (directory != null && Directory(directory).existsSync()) {
        _scan(directory);
      }
    });
  }

  @override
  void dispose() {
    _dataset.removeListener(_onDatasetChanged);
    _dataset.dispose();
    _session.dispose();
    _aiTagger.dispose();
    _tagOps.dispose();
    _libraryFilterFocus.dispose();
    super.dispose();
  }

  void _onDatasetChanged() {
    final selected = _dataset.selectedFile;
    if (selected?.path == _lastLoadedPath) return;
    _lastLoadedPath = selected?.path;
    if (selected == null) {
      _session.unload();
    } else {
      _session.load(selected, context.read<AppState>().captionExtension);
    }
  }

  Future<void> _scan(String directory) async {
    final appState = context.read<AppState>();
    await _dataset.scan(
      directoryPath: directory,
      recursive: appState.includeSubdirectories,
      captionExtension: appState.captionExtension,
    );
  }

  /// A batch rewrite may have replaced the caption of the open image; reload
  /// it so the editor shows the on-disk state.
  void _reloadSessionIfTouched(Set<String> imagePaths) {
    if (!mounted) return;
    final selected = _dataset.selectedFile;
    if (selected == null || !imagePaths.contains(selected.path)) return;
    _session.load(selected, context.read<AppState>().captionExtension);
  }

  Future<void> _openFolder() async {
    final directory = await FilePicker.getDirectoryPath();
    if (directory == null || !mounted) return;
    // The tag filter and the undo history both reference the previous
    // dataset's contents.
    _dataset.clearTagFilter();
    _tagOps.clearHistory();
    await context.read<AppState>().setBrowsingDirectory(directory);
    await _scan(directory);
  }

  Future<void> _refresh() async {
    final directory = context.read<AppState>().browsingDirectory;
    if (directory != null) {
      await _scan(directory);
    }
  }

  Future<void> _openExternalPreview([File? file]) async {
    final target = file ?? _dataset.selectedFile;
    if (target == null) return;
    final visible = _dataset.visibleFiles;
    var index = visible.indexWhere((f) => f.path == target.path);
    if (index < 0) index = 0;
    await _previewWindow.show(visible.map((f) => f.path).toList(), index);
  }

  /// Clamps a panel width to its own bounds and to whatever room the window
  /// leaves after the other panel and the center minimum.
  double _clampPanelWidth(double value, double otherPanel, double total) {
    final available = total - otherPanel - _centerMinWidth - 2 * _handleWidth;
    final max = available < _panelMinWidth
        ? _panelMinWidth
        : available.clamp(_panelMinWidth, _panelMaxWidth).toDouble();
    return value.clamp(_panelMinWidth, max).toDouble();
  }

  void _persistPanelWidths() {
    context.read<AppState>().updatePanelWidths(_leftWidth, _rightWidth);
  }

  /// Clamps the preview pane's height so both center panes stay usable; on
  /// very short windows the panes just share what's there.
  double _clampTopHeight(double value, double total) {
    final max = total - _captionMinHeight - _handleWidth;
    if (max <= _previewMinHeight) {
      return value.clamp(0, max < 0 ? 0 : max).toDouble();
    }
    return value.clamp(_previewMinHeight, max).toDouble();
  }

  void _persistCenterSplit() {
    context.read<AppState>().updateCenterSplit(_centerSplit);
  }

  @override
  Widget build(BuildContext context) {
    // Keep the session's autosave behavior in sync with the setting. select
    // (not watch): a full watch would rebuild the whole workbench on every
    // AppState notification, including each tag-library edit.
    _session.autoSaveEnabled =
        context.select<AppState, bool>((s) => s.autoSave);

    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _dataset),
        ChangeNotifierProvider.value(value: _session),
        ChangeNotifierProvider.value(value: _aiTagger),
        ChangeNotifierProvider.value(value: _tagOps),
      ],
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
              _dataset.selectByOffset(-1),
          const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
              _dataset.selectByOffset(1),
          const SingleActivator(LogicalKeyboardKey.keyS, control: true):
              _session.save,
          const SingleActivator(LogicalKeyboardKey.keyF, control: true):
              _libraryFilterFocus.requestFocus,
        },
        child: Focus(
          autofocus: true,
          child: Column(
            children: [
              WorkbenchTopBar(onOpenFolder: _openFolder),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final total = constraints.maxWidth;
                    final left = _clampPanelWidth(
                      _leftWidth,
                      _rightWidth,
                      total,
                    );
                    final right = _clampPanelWidth(_rightWidth, left, total);
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          width: left,
                          child: AssetsPanel(
                            onOpenFolder: _openFolder,
                            onRefresh: _refresh,
                            onOpenExternalPreview: _openExternalPreview,
                          ),
                        ),
                        ResizeHandle(
                          onDragStart: (x) {
                            _dragAnchorX = x;
                            _dragStartWidth = left;
                          },
                          onDragUpdate: (x) => setState(() {
                            _leftWidth = _clampPanelWidth(
                              _dragStartWidth + (x - _dragAnchorX),
                              right,
                              total,
                            );
                          }),
                          onDragEnd: _persistPanelWidths,
                          onReset: () {
                            setState(() {
                              _leftWidth =
                                  SettingsService.defaultLeftPanelWidth;
                            });
                            _persistPanelWidths();
                          },
                        ),
                        Expanded(
                          child: LayoutBuilder(
                            builder: (context, center) {
                              final totalHeight = center.maxHeight;
                              final topHeight = _clampTopHeight(
                                _centerSplit * totalHeight,
                                totalHeight,
                              );
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  SizedBox(
                                    height: topHeight,
                                    child: Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        8,
                                        14,
                                        8,
                                        4,
                                      ),
                                      child: PreviewPanel(
                                        onOpenExternalPreview:
                                            _openExternalPreview,
                                      ),
                                    ),
                                  ),
                                  ResizeHandle(
                                    axis: Axis.vertical,
                                    onDragStart: (y) {
                                      _dragAnchorY = y;
                                      _dragStartTopHeight = topHeight;
                                    },
                                    onDragUpdate: (y) => setState(() {
                                      _centerSplit =
                                          _clampTopHeight(
                                            _dragStartTopHeight +
                                                (y - _dragAnchorY),
                                            totalHeight,
                                          ) /
                                          totalHeight;
                                    }),
                                    onDragEnd: _persistCenterSplit,
                                    onReset: () {
                                      setState(() {
                                        _centerSplit =
                                            SettingsService.defaultCenterSplit;
                                      });
                                      _persistCenterSplit();
                                    },
                                  ),
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        8,
                                        3,
                                        8,
                                        14,
                                      ),
                                      child: const CaptionPanel(),
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                        ResizeHandle(
                          onDragStart: (x) {
                            _dragAnchorX = x;
                            _dragStartWidth = right;
                          },
                          onDragUpdate: (x) => setState(() {
                            _rightWidth = _clampPanelWidth(
                              _dragStartWidth - (x - _dragAnchorX),
                              left,
                              total,
                            );
                          }),
                          onDragEnd: _persistPanelWidths,
                          onReset: () {
                            setState(() {
                              _rightWidth =
                                  SettingsService.defaultRightPanelWidth;
                            });
                            _persistPanelWidths();
                          },
                        ),
                        SizedBox(
                          width: right,
                          child: TagLibraryPanel(
                            filterFocusNode: _libraryFilterFocus,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              const StatusBar(),
            ],
          ),
        ),
      ),
    );
  }
}
