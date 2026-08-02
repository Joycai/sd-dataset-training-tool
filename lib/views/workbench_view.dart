import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../l10n/app_localizations.dart';
import '../services/preview_window_launcher.dart';
import '../services/settings_service.dart';
import '../state/agent_chat_state.dart';
import '../state/ai_tagger_state.dart';
import '../state/batch_tag_state.dart';
import '../state/dataset_state.dart';
import '../state/editor_session.dart';
import '../state/shortcut_relay.dart';
import '../state/tag_ops.dart';
import '../state/workbench_layout.dart';
import '../widgets/icon_nav_rail.dart';
import '../widgets/resize_handle.dart';
import '../widgets/status_bar.dart';
import '../widgets/workbench_top_bar.dart';
import 'panels/agent_dock.dart';
import 'panels/assets_panel.dart';
import 'panels/caption_panel.dart';
import 'panels/preview_panel.dart';
import 'panels/tag_dictionary_dialog.dart';
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
  late final BatchTagState _batchTag = BatchTagState(
    dataset: _dataset,
    ai: _aiTagger,
    settings: SettingsService(),
    beforeMutate: () => _session.flush(),
    // The run rewrites files itself; the finished operation joins the same
    // undo history as the manual batch edits.
    onOperation: _tagOps.pushOperation,
    onCaptionsChanged: _reloadSessionIfTouched,
  );
  final PreviewWindowLauncher _previewWindow = PreviewWindowLauncher();
  final FocusNode _libraryFilterFocus = FocusNode();
  final ShortcutRelay _shortcutRelay = ShortcutRelay();
  final WorkbenchLayout _layout = WorkbenchLayout();
  late final AppState _appState;
  late final AgentChatState _agentChat;
  bool _agentOpen = false;
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
    // Held as a field, not re-read on demand: dispose() unsubscribes from it,
    // and by then the element is deactivated and an ancestor lookup throws.
    final appState = _appState = context.read<AppState>();
    _leftWidth = appState.leftPanelWidth;
    _rightWidth = appState.rightPanelWidth;
    _centerSplit = appState.centerSplit;
    _session.onSaved = _dataset.updateCaptionText;
    _dataset.addListener(_onDatasetChanged);
    // Library edits are the other half of the local vocabulary; the dataset
    // half rides along on [_onDatasetChanged].
    appState.addListener(_syncLocalTags);
    // Switching the active caption type (navigator picker or the settings
    // dialog) changes which files the app reads; the scan must follow.
    appState.addListener(_rescanIfCaptionTypeChanged);
    _syncLocalTags();
    _aiTagger.loadSettings();
    // The rule sets live on AppState; BatchTagState only remembers which one
    // was chosen, so it asks for the body at run time.
    _batchTag.resolveRules = (id) {
      for (final r in appState.mergeRuleSets) {
        if (r.id == id) return r;
      }
      return null;
    };
    _batchTag.loadSettings();
    _agentChat = AgentChatState(
      app: appState,
      dataset: _dataset,
      tagOps: _tagOps,
      aiTagger: _aiTagger,
    );
    SettingsService().loadAgentPanelOpen().then((value) {
      if (mounted) setState(() => _agentOpen = value);
    });

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
    _appState.removeListener(_syncLocalTags);
    _appState.removeListener(_rescanIfCaptionTypeChanged);
    _dataset.removeListener(_onDatasetChanged);
    _dataset.dispose();
    _session.dispose();
    _aiTagger.dispose();
    _batchTag.dispose();
    _tagOps.dispose();
    _agentChat.dispose();
    _layout.dispose();
    _libraryFilterFocus.dispose();
    super.dispose();
  }

  void _onDatasetChanged() {
    _syncLocalTags();
    final selected = _dataset.selectedFile;
    if (selected?.path == _lastLoadedPath) return;
    _lastLoadedPath = selected?.path;
    if (selected == null) {
      _session.unload();
    } else {
      // The dataset's own extension/grammar, not the app state's: a type
      // switch mid-flight must not load the editor in a grammar the scan
      // has not indexed yet ([_rescanIfCaptionTypeChanged] follows up).
      _session.load(
        selected,
        _dataset.captionExtension,
        format: _dataset.captionFormat,
      );
    }
  }

  List<DatasetTag>? _lastDatasetTags;
  List<String>? _lastLibraryTags;
  int _lastLibraryLength = -1;

  /// Feeds the tag dictionary the vocabulary this user actually writes, so
  /// autocomplete also offers the tags danbooru has never heard of — trigger
  /// words, private character names, project conventions.
  ///
  /// Both sources notify far more often than they change: the dataset on
  /// every selection move, the app state on every panel drag. `datasetTags`
  /// is a cache that only gets a new list instance when captions change, and
  /// the library's identity-plus-length pair catches every way it can be
  /// edited (add and remove mutate it in place; replace and import swap it),
  /// so this bails out without touching the map in the common case.
  void _syncLocalTags() {
    final datasetTags = _dataset.datasetTags;
    final library = _appState.commonTags;
    if (identical(datasetTags, _lastDatasetTags) &&
        identical(library, _lastLibraryTags) &&
        library.length == _lastLibraryLength) {
      return;
    }
    _lastDatasetTags = datasetTags;
    _lastLibraryTags = library;
    _lastLibraryLength = library.length;
    _appState.tagDictionary.setLocalTags(
      datasetUsage: {for (final tag in datasetTags) tag.tag: tag.count},
      libraryTags: library,
    );
  }

  /// Rescans when the active caption extension or format no longer matches
  /// what the dataset was scanned with. The scan itself updates both, so
  /// this cannot loop.
  void _rescanIfCaptionTypeChanged() {
    final directory = _appState.browsingDirectory;
    if (directory == null || _dataset.rootPath == null) return;
    if (_appState.captionExtension == _dataset.captionExtension &&
        _appState.captionFormat == _dataset.captionFormat) {
      return;
    }
    _scan(directory);
  }

  Future<void> _scan(String directory) async {
    final appState = context.read<AppState>();
    // Pending edits belong to the caption file the editor loaded; write them
    // out before the scan re-reads the disk (and possibly switches type).
    await _session.flush();
    await _dataset.scan(
      directoryPath: directory,
      recursive: appState.includeSubdirectories,
      captionExtension: appState.captionExtension,
      captionFormat: appState.captionFormat,
    );
    if (!mounted) return;
    // The selected path usually survives a rescan, so [_onDatasetChanged]
    // alone would keep showing the previous type's caption; reload
    // explicitly with the extension the scan just indexed.
    final selected = _dataset.selectedFile;
    if (selected != null) {
      _lastLoadedPath = selected.path;
      await _session.load(
        selected,
        _dataset.captionExtension,
        format: _dataset.captionFormat,
      );
    }
  }

  /// A batch rewrite may have replaced the caption of the open image; reload
  /// it so the editor shows the on-disk state.
  void _reloadSessionIfTouched(Set<String> imagePaths) {
    if (!mounted) return;
    final selected = _dataset.selectedFile;
    if (selected == null || !imagePaths.contains(selected.path)) return;
    _session.load(
      selected,
      _dataset.captionExtension,
      format: _dataset.captionFormat,
    );
  }

  Future<void> _openFolder() async {
    final directory = await FilePicker.getDirectoryPath();
    if (directory == null || !mounted) return;
    // The tag filter and the undo history both reference the previous
    // dataset's contents; a running batch would keep writing into it. The
    // agent conversation is likewise about the old dataset.
    _batchTag.requestCancel();
    _dataset.clearTagFilter();
    // A scope named for the previous dataset's folder would otherwise
    // survive into the new one if both happen to have a folder by that name.
    _dataset.setSubdirectory(null);
    _tagOps.clearHistory();
    _agentChat.resetSession(datasetSwitched: true);
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

  void _toggleAgentPanel() {
    setState(() => _agentOpen = !_agentOpen);
    SettingsService().saveAgentPanelOpen(_agentOpen);
  }

  // Workbench shortcuts, dispatched from the root Focus node instead of a
  // CallbackShortcuts widget: unmatched keys keep bubbling up to the
  // app-level text-editing shortcuts instead of being swallowed here.
  //
  // Global bindings stay active while typing; the rest would conflict with
  // text editing (caret movement, the text field's own undo) and only fire
  // when focus is outside any text field.
  late final Map<SingleActivator, VoidCallback> _globalShortcuts = {
    const SingleActivator(LogicalKeyboardKey.keyS, control: true):
        _session.save,
    const SingleActivator(LogicalKeyboardKey.keyF, control: true):
        _libraryFilterFocus.requestFocus,
    const SingleActivator(LogicalKeyboardKey.keyE, control: true): () =>
        _shortcutRelay.runAiForCurrentImage?.call(),
    // Global, not text-guarded: the question "what does this tag mean" comes
    // up mid-caption, with the cursor in the editor.
    const SingleActivator(LogicalKeyboardKey.keyD, control: true):
        _openDictionary,
  };

  /// Opens the dictionary window.
  ///
  /// The scope is handed over explicitly: this State's context sits above the
  /// [MultiProvider] that `build` installs, so the dialog could not read the
  /// dataset off it and would lose the per-image filter and the usage bar.
  void _openDictionary() {
    showTagDictionaryDialog(
      context,
      scope: tagDictionaryScope(dataset: _dataset),
    );
  }

  late final Map<SingleActivator, VoidCallback> _nonTextShortcuts = {
    const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
        _dataset.selectByOffset(-1),
    const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
        _dataset.selectByOffset(1),
    // Insertion anchor: step it across the tag list (and the append-at-end
    // state) without reaching for the mouse.
    const SingleActivator(LogicalKeyboardKey.bracketLeft): () =>
        _session.moveAnchor(-1),
    const SingleActivator(LogicalKeyboardKey.bracketRight): () =>
        _session.moveAnchor(1),
    const SingleActivator(LogicalKeyboardKey.keyZ, control: true): _undo,
    const SingleActivator(LogicalKeyboardKey.keyZ, control: true, shift: true):
        _redo,
    const SingleActivator(LogicalKeyboardKey.keyY, control: true): _redo,
  };

  void _undo() {
    if (_tagOps.canUndo) _replay(_tagOps.undo());
  }

  void _redo() {
    if (_tagOps.canRedo) _replay(_tagOps.redo());
  }

  /// Undo/redo write files, and a file that refuses to be written would
  /// otherwise leave the dataset half-reverted in silence.
  Future<void> _replay(Future<ReplayResult> pending) async {
    final result = await pending;
    if (!mounted || result.failed == 0) return;
    final l10n = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.undoFailedRetryHint(result.failed))),
    );
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    for (final entry in _globalShortcuts.entries) {
      if (entry.key.accepts(event, HardwareKeyboard.instance)) {
        entry.value();
        return KeyEventResult.handled;
      }
    }
    final inTextField =
        FocusManager.instance.primaryFocus?.context
            ?.findAncestorStateOfType<EditableTextState>() !=
        null;
    if (!inTextField) {
      for (final entry in _nonTextShortcuts.entries) {
        if (entry.key.accepts(event, HardwareKeyboard.instance)) {
          entry.value();
          return KeyEventResult.handled;
        }
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    // Keep the session's autosave behavior in sync with the setting. select
    // (not watch): a full watch would rebuild the whole workbench on every
    // AppState notification, including each tag-library edit.
    _session.autoSaveEnabled = context.select<AppState, bool>(
      (s) => s.autoSave,
    );

    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _dataset),
        ChangeNotifierProvider.value(value: _session),
        ChangeNotifierProvider.value(value: _aiTagger),
        ChangeNotifierProvider.value(value: _batchTag),
        ChangeNotifierProvider.value(value: _tagOps),
        ChangeNotifierProvider.value(value: _agentChat),
        ChangeNotifierProvider.value(value: _layout),
      ],
      child: Focus(
        autofocus: true,
        onKeyEvent: _handleKeyEvent,
        child: Column(
          children: [
            WorkbenchTopBar(
              onOpenFolder: _openFolder,
              agentOpen: _agentOpen,
              onToggleAgent: _toggleAgentPanel,
              onUndo: _undo,
              onRedo: _redo,
            ),
            Expanded(
              // The assistant floats over this area, so it is a Stack rather
              // than another column.
              child: LayoutBuilder(
                builder: (context, area) => Stack(
                  children: [
                    Positioned.fill(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const IconNavRail(),
                          Expanded(
                            // The rail sits outside the inner LayoutBuilder so
                            // `total` is already the width the resizable
                            // columns get to share.
                            child: ListenableBuilder(
                              listenable: _layout,
                              builder: (context, _) => LayoutBuilder(
                                builder: (context, constraints) {
                                  final total = constraints.maxWidth;
                                  final showNavigator =
                                      _layout.navigatorVisible;
                                  final showInspector =
                                      _layout.inspectorVisible;
                                  // A hidden column contributes nothing to the other's clamp.
                                  final left = showNavigator
                                      ? _clampPanelWidth(
                                          _leftWidth,
                                          showInspector ? _rightWidth : 0,
                                          total,
                                        )
                                      : 0.0;
                                  final right = showInspector
                                      ? _clampPanelWidth(
                                          _rightWidth,
                                          left,
                                          total,
                                        )
                                      : 0.0;
                                  return Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      if (showNavigator) ...[
                                        SizedBox(
                                          width: left,
                                          child: AssetsPanel(
                                            onOpenFolder: _openFolder,
                                            onRefresh: _refresh,
                                            onOpenExternalPreview:
                                                _openExternalPreview,
                                          ),
                                        ),
                                        ResizeHandle(
                                          onDragStart: (x) {
                                            _dragAnchorX = x;
                                            _dragStartWidth = left;
                                          },
                                          onDragUpdate: (x) => setState(() {
                                            _leftWidth = _clampPanelWidth(
                                              _dragStartWidth +
                                                  (x - _dragAnchorX),
                                              right,
                                              total,
                                            );
                                          }),
                                          onDragEnd: _persistPanelWidths,
                                          onReset: () {
                                            setState(() {
                                              _leftWidth = SettingsService
                                                  .defaultLeftPanelWidth;
                                            });
                                            _persistPanelWidths();
                                          },
                                        ),
                                      ],
                                      Expanded(
                                        child: LayoutBuilder(
                                          builder: (context, center) {
                                            final totalHeight =
                                                center.maxHeight;
                                            final topHeight = _clampTopHeight(
                                              _centerSplit * totalHeight,
                                              totalHeight,
                                            );
                                            return Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.stretch,
                                              children: [
                                                SizedBox(
                                                  height: topHeight,
                                                  // No padding: the canvas *is* the
                                                  // window background, and the image
                                                  // carries its own radius + shadow.
                                                  child: PreviewPanel(
                                                    onOpenExternalPreview:
                                                        _openExternalPreview,
                                                  ),
                                                ),
                                                ResizeHandle(
                                                  axis: Axis.vertical,
                                                  onDragStart: (y) {
                                                    _dragAnchorY = y;
                                                    _dragStartTopHeight =
                                                        topHeight;
                                                  },
                                                  onDragUpdate: (y) => setState(
                                                    () {
                                                      _centerSplit =
                                                          _clampTopHeight(
                                                            _dragStartTopHeight +
                                                                (y -
                                                                    _dragAnchorY),
                                                            totalHeight,
                                                          ) /
                                                          totalHeight;
                                                    },
                                                  ),
                                                  onDragEnd:
                                                      _persistCenterSplit,
                                                  onReset: () {
                                                    setState(() {
                                                      _centerSplit =
                                                          SettingsService
                                                              .defaultCenterSplit;
                                                    });
                                                    _persistCenterSplit();
                                                  },
                                                ),
                                                Expanded(
                                                  // Flush like the canvas: the editor
                                                  // is a panel, and its own top
                                                  // hairline is the only separator.
                                                  child: CaptionPanel(
                                                    shortcutRelay:
                                                        _shortcutRelay,
                                                  ),
                                                ),
                                              ],
                                            );
                                          },
                                        ),
                                      ),
                                      if (showInspector) ...[
                                        ResizeHandle(
                                          onDragStart: (x) {
                                            _dragAnchorX = x;
                                            _dragStartWidth = right;
                                          },
                                          onDragUpdate: (x) => setState(() {
                                            _rightWidth = _clampPanelWidth(
                                              _dragStartWidth -
                                                  (x - _dragAnchorX),
                                              left,
                                              total,
                                            );
                                          }),
                                          onDragEnd: _persistPanelWidths,
                                          onReset: () {
                                            setState(() {
                                              _rightWidth = SettingsService
                                                  .defaultRightPanelWidth;
                                            });
                                            _persistPanelWidths();
                                          },
                                        ),
                                        SizedBox(
                                          width: right,
                                          child: TagLibraryPanel(
                                            filterFocusNode:
                                                _libraryFilterFocus,
                                          ),
                                        ),
                                      ],
                                    ],
                                  );
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_agentOpen)
                      AgentDock(area: area.biggest, onClose: _toggleAgentPanel),
                  ],
                ),
              ),
            ),
            const StatusBar(),
          ],
        ),
      ),
    );
  }
}
