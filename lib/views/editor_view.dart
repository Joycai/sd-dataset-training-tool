import 'dart:io';
import 'package:flutter/material.dart';
import 'image_browser.dart';
import 'workspace_view.dart'; // 1. Import the new workspace view

// 2. Convert to StatefulWidget
class EditorView extends StatefulWidget {
  const EditorView({super.key});

  @override
  State<EditorView> createState() => _EditorViewState();
}

class _EditorViewState extends State<EditorView> {
  // 3. Add state to hold the selected image
  File? _selectedImage;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Left Panel: Image Browser
        Expanded(
          flex: 6,
          // 4. Pass the callback to ImageBrowser
          child: ImageBrowser(
            onImageSelected: (file) {
              setState(() {
                _selectedImage = file;
              });
            },
          ),
        ),
        const VerticalDivider(width: 1, thickness: 1),
        // Right Panel: Workspace
        Expanded(
          flex: 4,
          // 5. Pass the selected image to WorkspaceView
          child: WorkspaceView(
            selectedImage: _selectedImage,
          ),
        ),
      ],
    );
  }
}
