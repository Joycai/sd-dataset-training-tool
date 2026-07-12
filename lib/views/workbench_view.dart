import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../services/preview_window_launcher.dart';
import '../state/dataset_state.dart';
import '../state/editor_session.dart';
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
  final DatasetState _dataset = DatasetState();
  final EditorSession _session = EditorSession();
  final PreviewWindowLauncher _previewWindow = PreviewWindowLauncher();
  final FocusNode _libraryFilterFocus = FocusNode();
  String? _lastLoadedPath;

  @override
  void initState() {
    super.initState();
    _session.onSaved = _dataset.markCaptioned;
    _dataset.addListener(_onDatasetChanged);

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

  Future<void> _openFolder() async {
    final directory = await FilePicker.getDirectoryPath();
    if (directory == null || !mounted) return;
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

  @override
  Widget build(BuildContext context) {
    // Keep the session's autosave behavior in sync with the setting.
    _session.autoSaveEnabled = context.watch<AppState>().autoSave;

    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _dataset),
        ChangeNotifierProvider.value(value: _session),
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
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: 264,
                      child: AssetsPanel(
                        onOpenFolder: _openFolder,
                        onRefresh: _refresh,
                        onOpenExternalPreview: _openExternalPreview,
                      ),
                    ),
                    Expanded(
                      child: Column(
                        children: [
                          Expanded(
                            flex: 4,
                            child: Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(14, 14, 14, 0),
                              child: PreviewPanel(
                                onOpenExternalPreview: _openExternalPreview,
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 3,
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: const CaptionPanel(),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(
                      width: 300,
                      child: TagLibraryPanel(
                        filterFocusNode: _libraryFilterFocus,
                      ),
                    ),
                  ],
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
