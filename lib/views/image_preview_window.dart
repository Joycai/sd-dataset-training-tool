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
    _imagePaths = List<String>.from(widget.args['imagePaths']);
    _currentIndex = widget.args['currentIndex'];

    // Listen for messages from the main window to update the image
    DesktopMultiWindow.setMethodHandler((call, fromWindowId) async {
      if (call.method == 'update_image') {
        final args = jsonDecode(call.arguments) as Map<String, dynamic>;
        setState(() {
          _imagePaths = List<String>.from(args['imagePaths']);
          _currentIndex = args['currentIndex'];
          _resetZoom(); // Reset zoom when image changes
        });
      }
      return '';
    });
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
    final currentPath = _imagePaths[_currentIndex];
    final fileName = p.basename(currentPath);
    await FileSaver.instance.saveFile(
      name: fileName,
      file: File(currentPath),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentImagePath = _imagePaths[_currentIndex];
    final imageFile = File(currentImagePath);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.black,
        body: Column(
          children: [
            // Main Preview Area
            Expanded(
              child: Row(
                children: [
                  // Previous Button
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
                    onPressed: _currentIndex > 0 ? () => _changeImage(_currentIndex - 1) : null,
                  ),
                  // Interactive Image Viewer
                  Expanded(
                    child: InteractiveViewer(
                      transformationController: _transformationController,
                      minScale: 0.1,
                      maxScale: 4.0,
                      child: Image.file(imageFile, fit: BoxFit.contain),
                    ),
                  ),
                  // Next Button
                  IconButton(
                    icon: const Icon(Icons.arrow_forward_ios, color: Colors.white),
                    onPressed: _currentIndex < _imagePaths.length - 1
                        ? () => _changeImage(_currentIndex + 1)
                        : null,
                  ),
                ],
              ),
            ),
            // Bottom Control Bar
            Container(
              color: Colors.black.withOpacity(0.5),
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
          ],
        ),
      ),
    );
  }
}
