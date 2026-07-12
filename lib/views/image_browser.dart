import 'dart:convert';
import 'dart:io';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import '../app_state.dart';

class ImageBrowser extends StatefulWidget {
  final ValueChanged<File?>? onImageSelected;

  const ImageBrowser({super.key, this.onImageSelected});

  @override
  State<ImageBrowser> createState() => _ImageBrowserState();
}

class _ImageBrowserState extends State<ImageBrowser> {
  List<File> _imageFiles = [];
  bool _isLoading = false;
  WindowController? _previewWindow;
  int? _selectedIndex;

  @override
  void initState() {
    super.initState();
    // FIX: Defer the initial scan until after the first frame is built.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final initialDirectory = context.read<AppState>().browsingDirectory;
      if (initialDirectory != null && Directory(initialDirectory).existsSync()) {
        _scanDirectory();
      }
    });
  }

  Future<void> _scanDirectory() async {
    final appState = context.read<AppState>();
    final directoryPath = appState.browsingDirectory;
    if (directoryPath == null) return;

    setState(() {
      _isLoading = true;
      _imageFiles = [];
      _selectedIndex = null;
    });
    // This call is now safe because it's triggered by user actions or post-frame callbacks,
    // not during the initial build.
    widget.onImageSelected?.call(null);

    final directory = Directory(directoryPath);
    final List<File> foundFiles = [];
    final supportedExtensions = ['.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp'];
    String? errorMessage;

    try {
      final stream = directory.list(
        recursive: appState.includeSubdirectories,
        followLinks: false,
      );
      await for (final entity in stream) {
        if (entity is File) {
          if (supportedExtensions.contains(p.extension(entity.path).toLowerCase())) {
            foundFiles.add(entity);
          }
        }
      }
    } catch (e) {
      errorMessage = 'Error scanning directory: $e';
    }

    // Stable, platform-independent ordering.
    foundFiles.sort((a, b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()));

    // Check if the widget is still in the tree before calling setState
    if (mounted) {
      setState(() {
        _imageFiles = foundFiles;
        _isLoading = false;
      });
      if (errorMessage != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorMessage)));
      }
    }
  }

  Future<void> _openDirectoryPicker() async {
    final String? directoryPath = await FilePicker.getDirectoryPath();
    if (directoryPath != null && mounted) {
      context.read<AppState>().setBrowsingDirectory(directoryPath);
      _scanDirectory();
    }
  }

  Future<void> _showPreviewWindow(int index) async {
    final allImagePaths = _imageFiles.map((f) => f.path).toList();
    final args = jsonEncode({
      'imagePaths': allImagePaths,
      'currentIndex': index,
    });

    final existing = _previewWindow;
    if (existing != null) {
      try {
        await existing.invokeMethod('update_image', args);
        await existing.show();
        return;
      } on WindowChannelException {
        // The preview window was closed; create a new one below.
        _previewWindow = null;
      }
    }

    final window = await WindowController.create(
      WindowConfiguration(arguments: args),
    );
    _previewWindow = window;
    await window.show();
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    return Column(
      children: [
        _buildControlBar(appState),
        const Divider(height: 1),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _imageFiles.isEmpty
                  ? Center(child: Text('No images found. Try opening a directory.'))
                  : _buildImageGrid(),
        ),
      ],
    );
  }

  Widget _buildControlBar(AppState appState) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      // Wrap instead of Row so the controls flow onto extra lines when the
      // browser panel is too narrow to fit them all side by side.
      child: Wrap(
        spacing: 8.0,
        runSpacing: 4.0,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ElevatedButton.icon(
                icon: const Icon(Icons.folder_open),
                label: const Text('Open'),
                onPressed: _openDirectoryPicker,
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'Refresh',
                onPressed: _scanDirectory,
              ),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Columns:'),
              SizedBox(
                width: 150,
                child: Slider(
                  value: appState.crossAxisCount.toDouble(),
                  min: 1,
                  max: 10,
                  divisions: 9,
                  label: appState.crossAxisCount.toString(),
                  onChanged: (value) {
                    appState.updateCrossAxisCount(value.toInt());
                  },
                ),
              ),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.subdirectory_arrow_right),
              Switch(
                value: appState.includeSubdirectories,
                onChanged: (value) {
                  appState.updateIncludeSubdirectories(value);
                  _scanDirectory();
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildImageGrid() {
    final appState = context.read<AppState>();
    return GridView.builder(
      padding: const EdgeInsets.all(8.0),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: appState.crossAxisCount,
        crossAxisSpacing: 8.0,
        mainAxisSpacing: 8.0,
      ),
      itemCount: _imageFiles.length,
      itemBuilder: (context, index) {
        final file = _imageFiles[index];
        final isSelected = _selectedIndex == index;

        return GestureDetector(
          onTap: () {
            setState(() => _selectedIndex = index);
            widget.onImageSelected?.call(file);
          },
          onDoubleTap: () => _showPreviewWindow(index),
          child: Container(
            decoration: BoxDecoration(
              border: isSelected
                  ? Border.all(color: Theme.of(context).primaryColor, width: 3)
                  : null,
              borderRadius: BorderRadius.circular(4),
            ),
            child: GridTile(
              footer: GridTileBar(
                backgroundColor: Colors.black45,
                title: Text(
                  p.basename(file.path),
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              child: Image.file(
                file,
                fit: BoxFit.contain,
                // Decode at thumbnail size instead of full resolution —
                // large training images (1024px+) would otherwise eat
                // hundreds of MB of memory in a big grid.
                cacheWidth: 384,
                errorBuilder: (context, error, stackTrace) {
                  return const Center(child: Icon(Icons.broken_image));
                },
              ),
            ),
          ),
        );
      },
    );
  }
}
