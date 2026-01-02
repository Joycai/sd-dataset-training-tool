import 'dart:convert';
import 'dart:io';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

class ImagePreviewWindow extends StatefulWidget {
  final WindowController windowController;
  final Map<String, dynamic> args;

  const ImagePreviewWindow({
    super.key,
    required this.windowController,
    required this.args,
  });

  @override
  State<ImagePreviewWindow> createState() => _ImagePreviewWindowState();
}

class _ImagePreviewWindowState extends State<ImagePreviewWindow> {
  late List<String> _imagePaths;
  late int _currentIndex;
  final TransformationController _transformationController = TransformationController();

  @override
  void initState() {
    super.initState();
    // Initialize state from widget arguments
    _updateStateFromArgs(widget.args);

    // Listen for updates from the main window
    DesktopMultiWindow.setMethodHandler((call, fromWindowId) async {
      if (call.method == 'update_image') {
        // The arguments come as a JSON string, so we need to decode it
        final args = jsonDecode(call.arguments) as Map<String, dynamic>;
        setState(() {
          _updateStateFromArgs(args);
          _resetZoom();
        });
      }
      return '';
    });
  }

  void _updateStateFromArgs(Map<String, dynamic> args) {
    // Safely parse imagePaths
    if (args['imagePaths'] != null) {
      final rawPaths = args['imagePaths'] as List;
      _imagePaths = rawPaths.map((e) => e.toString()).toList();
    } else {
      _imagePaths = [];
    }

    // Safely parse currentIndex
    if (args['currentIndex'] != null) {
      _currentIndex = args['currentIndex'] as int;
    } else {
      _currentIndex = 0;
    }
  }

  void _changeImage(int newIndex) {
    if (newIndex >= 0 && newIndex < _imagePaths.length) {
      setState(() {
        _currentIndex = newIndex;
        _resetZoom();
      });
    }
  }

  void _resetZoom() {
    _transformationController.value = Matrix4.identity();
  }

  Future<void> _saveImage() async {
    if (_imagePaths.isEmpty) return;
    final currentPath = _imagePaths[_currentIndex];
    final fileName = p.basename(currentPath);
    await FileSaver.instance.saveFile(
      name: fileName,
      file: File(currentPath),
    );
  }

  @override
  Widget build(BuildContext context) {
    // If no images, show a placeholder or loading
    if (_imagePaths.isEmpty) {
      return const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: Colors.black,
          body: Center(child: Text('No image to display', style: TextStyle(color: Colors.white))),
        ),
      );
    }

    final currentImagePath = _imagePaths[_currentIndex];
    final imageFile = File(currentImagePath);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            // Main Image Area
            Positioned.fill(
              child: InteractiveViewer(
                transformationController: _transformationController,
                minScale: 0.1,
                maxScale: 4.0,
                child: Image.file(
                  imageFile,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) {
                    return Center(
                      child: Text(
                        'Error loading image:\n$error',
                        style: const TextStyle(color: Colors.red),
                        textAlign: TextAlign.center,
                      ),
                    );
                  },
                ),
              ),
            ),
            
            // Navigation Arrows (Overlay)
            if (_currentIndex > 0)
              Positioned(
                left: 10,
                top: 0,
                bottom: 0,
                child: Center(
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back_ios, color: Colors.white70, size: 40),
                    onPressed: () => _changeImage(_currentIndex - 1),
                  ),
                ),
              ),
            if (_currentIndex < _imagePaths.length - 1)
              Positioned(
                right: 10,
                top: 0,
                bottom: 0,
                child: Center(
                  child: IconButton(
                    icon: const Icon(Icons.arrow_forward_ios, color: Colors.white70, size: 40),
                    onPressed: () => _changeImage(_currentIndex + 1),
                  ),
                ),
              ),

            // Bottom Control Bar
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                color: Colors.black54,
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.zoom_out_map, color: Colors.white),
                      tooltip: 'Fit to Screen',
                      onPressed: _resetZoom,
                    ),
                    const SizedBox(width: 20),
                    IconButton(
                      icon: const Icon(Icons.download, color: Colors.white),
                      tooltip: 'Save Image',
                      onPressed: _saveImage,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
