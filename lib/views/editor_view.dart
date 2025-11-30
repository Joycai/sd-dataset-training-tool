import 'dart:io';
import 'package:flutter/material.dart';
import 'image_browser.dart';
import 'workspace_view.dart';

class EditorView extends StatefulWidget {
  const EditorView({super.key});

  @override
  State<EditorView> createState() => _EditorViewState();
}

class _EditorViewState extends State<EditorView> {
  File? _selectedImage;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Left Panel: Image Browser
        Expanded(
          // 1. Change flex from 6 to 4
          flex: 4,
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
          // 2. Change flex from 4 to 6
          flex: 6,
          child: WorkspaceView(
            selectedImage: _selectedImage,
          ),
        ),
      ],
    );
  }
}
