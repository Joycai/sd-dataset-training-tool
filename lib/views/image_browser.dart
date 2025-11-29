import 'dart:convert';
import 'dart:io';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import '../app_state.dart';

class ImageBrowser extends StatefulWidget {
  const ImageBrowser({super.key});

  @override
  State<ImageBrowser> createState() => _ImageBrowserState();
}

class _ImageBrowserState extends State<ImageBrowser> {
  List<File> _imageFiles = [];
  bool _isLoading = false;
  // FIX: We will store the window ID directly, not a key.
  int? _previewWindowId;

  @override
  void initState() {
    super.initState();
    final initialDirectory = context.read<AppState>().browsingDirectory;
    if (initialDirectory != null && Directory(initialDirectory).existsSync()) {
      _scanDirectory();
    }
  }

  Future<void> _scanDirectory() async {
    final appState = context.read<AppState>();
    final directoryPath = appState.browsingDirectory;
    if (directoryPath == null) return;

    setState(() {
      _isLoading = true;
      _imageFiles = [];
    });

    final directory = Directory(directoryPath);
    final List<File> foundFiles = [];
    final supportedExtensions = ['.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp'];

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
      print('Error scanning directory: $e');
    }

    setState(() {
      _imageFiles = foundFiles;
      _isLoading = false;
    });
  }

  Future<void> _openDirectoryPicker() async {
    final String? directoryPath = await FilePicker.platform.getDirectoryPath();
    if (directoryPath != null) {
      context.read<AppState>().setBrowsingDirectory(directoryPath);
      _scanDirectory();
    }
  }

  // --- Completely Reworked Function ---
  Future<void> _showPreviewWindow(int index) async {
    final allImagePaths = _imageFiles.map((f) => f.path).toList();
    final args = {
      'imagePaths': allImagePaths,
      'currentIndex': index,
    };

    bool windowExists = false;
    if (_previewWindowId != null) {
      final allWindowIds = await DesktopMultiWindow.getAllSubWindowIds();
      if (allWindowIds.contains(_previewWindowId)) {
        windowExists = true;
      }
    }

    if (windowExists) {
      // Window exists, just send data to update it and bring to front
      DesktopMultiWindow.invokeMethod(
        _previewWindowId!,
        'update_image',
        jsonEncode(args),
      );
      WindowController.fromWindowId(_previewWindowId!).show();
    } else {
      // Window does not exist (or was closed), create it
      final window = await DesktopMultiWindow.createWindow(jsonEncode(args));
      // Store the new window's ID
      _previewWindowId = window.windowId;
      window
        ..setFrame(const Offset(0, 0) & const Size(800, 600))
        ..center()
        ..setTitle('Image Preview')
        ..show();
    }
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
      child: Row(
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
          const Spacer(),
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
          const SizedBox(width: 8),
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
        return GestureDetector(
          onDoubleTap: () => _showPreviewWindow(index),
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
              errorBuilder: (context, error, stackTrace) {
                return const Center(child: Icon(Icons.broken_image));
              },
            ),
          ),
        );
      },
    );
  }
}
