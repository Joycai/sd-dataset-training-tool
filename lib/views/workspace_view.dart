import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path/path.dart' as p;
import '../app_state.dart';
import '../l10n/app_localizations.dart';

class WorkspaceView extends StatefulWidget {
  final File? selectedImage;

  const WorkspaceView({super.key, this.selectedImage});

  @override
  State<WorkspaceView> createState() => _WorkspaceViewState();
}

class _WorkspaceViewState extends State<WorkspaceView> {
  final TextEditingController _captionController = TextEditingController();
  List<String> _tags = [];
  bool _tagViewEnabled = false;
  bool _isLoading = false;
  String _captionFilePath = '';

  @override
  void initState() {
    super.initState();
    _captionController.addListener(_onCaptionTextChanged);
    if (widget.selectedImage != null) {
      _loadCaption(widget.selectedImage!);
    }
  }

  @override
  void didUpdateWidget(WorkspaceView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedImage != oldWidget.selectedImage) {
      if (widget.selectedImage != null) {
        _loadCaption(widget.selectedImage!);
      } else {
        _clearWorkspace();
      }
    }
  }

  @override
  void dispose() {
    _captionController.removeListener(_onCaptionTextChanged);
    _captionController.dispose();
    super.dispose();
  }

  void _onCaptionTextChanged() {
    if (_tagViewEnabled) {
      setState(() {
        _tags = _captionController.text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
      });
    }
  }

  Future<void> _loadCaption(File imageFile) async {
    setState(() => _isLoading = true);
    final appState = context.read<AppState>();
    final extension = appState.captionExtension;
    _captionFilePath = '${p.withoutExtension(imageFile.path)}$extension';

    String content = '';
    try {
      final captionFile = File(_captionFilePath);
      if (await captionFile.exists()) {
        content = await captionFile.readAsString();
      }
    } catch (e) {
      print("Error loading caption: $e");
    }

    _captionController.text = content;
    _onCaptionTextChanged(); // Initial parse
    setState(() => _isLoading = false);
  }

  Future<void> _saveCaption() async {
    if (_captionFilePath.isEmpty) return;
    try {
      final captionFile = File(_captionFilePath);
      await captionFile.writeAsString(_captionController.text);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Caption saved to $_captionFilePath')),
      );
    } catch (e) {
      print("Error saving caption: $e");
    }
  }

  void _clearWorkspace() {
    _captionController.clear();
    setState(() {
      _tags = [];
      _captionFilePath = '';
    });
  }

  void _rebuildCaptionFromTags() {
    _captionController.text = _tags.join(', ');
  }

  Future<void> _editTag(int index) async {
    final tagController = TextEditingController(text: _tags[index]);
    final newTag = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Tag'),
        content: TextField(controller: tagController, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(context).pop(tagController.text), child: const Text('OK')),
        ],
      ),
    );

    if (newTag != null && newTag.isNotEmpty) {
      setState(() {
        _tags[index] = newTag;
        _rebuildCaptionFromTags();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    if (widget.selectedImage == null) {
      return const Center(child: Text('Select an image to start editing.'));
    }
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Caption Text Editor
          Expanded(
            flex: 2,
            child: TextField(
              controller: _captionController,
              maxLines: null,
              expands: true,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Caption',
              ),
              textAlignVertical: TextAlignVertical.top,
            ),
          ),
          const SizedBox(height: 8),
          // Tag View Toggle
          Row(
            children: [
              const Text('Tag View'),
              Switch(
                value: _tagViewEnabled,
                onChanged: (value) {
                  setState(() => _tagViewEnabled = value);
                  _onCaptionTextChanged(); // Parse text when enabling
                },
              ),
            ],
          ),
          // Tag List
          Expanded(
            flex: 3,
            child: AbsorbPointer(
              absorbing: !_tagViewEnabled,
              child: Opacity(
                opacity: _tagViewEnabled ? 1.0 : 0.4,
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Theme.of(context).dividerColor),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: _tags.isEmpty
                      ? const Center(child: Text('No tags found.'))
                      : SingleChildScrollView(
                          padding: const EdgeInsets.all(8.0),
                          child: Wrap(
                            spacing: 8.0,
                            runSpacing: 4.0,
                            children: List.generate(_tags.length, (index) {
                              return GestureDetector(
                                onDoubleTap: () => _editTag(index),
                                child: Chip(
                                  label: Text(_tags[index]),
                                  onDeleted: () {
                                    setState(() {
                                      _tags.removeAt(index);
                                      _rebuildCaptionFromTags();
                                    });
                                  },
                                ),
                              );
                            }),
                          ),
                        ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          // Save Button
          ElevatedButton.icon(
            icon: const Icon(Icons.save),
            label: Text(l10n.save),
            onPressed: _saveCaption,
            style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
          ),
        ],
      ),
    );
  }
}
