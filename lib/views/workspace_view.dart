import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path/path.dart' as p;
import 'package:reorderable_grid_view/reorderable_grid_view.dart';
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
  List<String> _imageTags = [];
  bool _tagViewEnabled = false;
  bool _isLoading = false;
  String _captionFilePath = '';
  final Set<String> _selectedCommonTags = {};

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
      setState(() => _selectedCommonTags.clear());
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
        _imageTags = _captionController.text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
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
    _onCaptionTextChanged();
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
      _imageTags = [];
      _captionFilePath = '';
    });
  }

  void _rebuildCaptionFromTags() {
    _captionController.text = _imageTags.join(', ');
  }

  Future<void> _editTag(int index) async {
    final tagController = TextEditingController(text: _imageTags[index]);
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
        _imageTags[index] = newTag;
        _rebuildCaptionFromTags();
      });
    }
  }

  Future<void> _showImportDialog() async {
    final l10n = AppLocalizations.of(context)!;
    final importController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.importTagsTitle),
        content: TextField(
          controller: importController,
          decoration: InputDecoration(hintText: l10n.importTagsContent),
          maxLines: 3,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(l10n.cancel)),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: Text(l10n.confirm)),
        ],
      ),
    );

    if (confirmed == true) {
      final tags = importController.text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
      context.read<AppState>().updateCommonTags(tags);
    }
  }

  Future<void> _showAddTagsDialog() async {
    final l10n = AppLocalizations.of(context)!;
    final addController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.addTagsTitle),
        content: TextField(
          controller: addController,
          decoration: InputDecoration(hintText: l10n.addTagsContent),
          maxLines: 3,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(l10n.cancel)),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: Text(l10n.confirm)),
        ],
      ),
    );

    if (confirmed == true) {
      final tags = addController.text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
      context.read<AppState>().addCommonTags(tags);
    }
  }

  void _addCommonTagToImageTags(String tag) {
    if (!_imageTags.contains(tag)) {
      setState(() {
        _imageTags.add(tag);
        _rebuildCaptionFromTags();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final appState = context.watch<AppState>();

    if (widget.selectedImage == null) {
      return const Center(child: Text('Select an image to start editing.'));
    }
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final Set<String> imageTagSet = Set.from(_imageTags);
    final Set<String> commonTagSet = Set.from(appState.commonTags);
    final List<String> newTags = imageTagSet.difference(commonTagSet).toList();

    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 120,
            child: TextField(
              controller: _captionController,
              maxLines: null,
              expands: true,
              decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Caption'),
              textAlignVertical: TextAlignVertical.top,
            ),
          ),
          const SizedBox(height: 8),
          Row(children: [
            const Text('Tag View'),
            Switch(value: _tagViewEnabled, onChanged: (v) => setState(() { _tagViewEnabled = v; _onCaptionTextChanged(); })),
          ]),
          Text(l10n.imageTags, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          Expanded(
            flex: 1,
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: Theme.of(context).dividerColor),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Opacity(
                opacity: _tagViewEnabled ? 1.0 : 0.4,
                child: _buildReorderableImageTagGrid(),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(l10n.commonTags, style: Theme.of(context).textTheme.titleSmall),
            Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(icon: const Icon(Icons.add_circle_outline), tooltip: l10n.add, onPressed: _showAddTagsDialog),
              IconButton(icon: const Icon(Icons.delete_outline), tooltip: l10n.delete, color: Colors.red, onPressed: _selectedCommonTags.isEmpty ? null : () {
                context.read<AppState>().removeCommonTags(_selectedCommonTags.toList());
                setState(() => _selectedCommonTags.clear());
              }),
              IconButton(icon: const Icon(Icons.input), tooltip: l10n.import, onPressed: _showImportDialog),
            ]),
          ]),
          const SizedBox(height: 4),
          Expanded(
            flex: 1,
            child: AbsorbPointer(
              absorbing: !_tagViewEnabled,
              child: Opacity(
                opacity: _tagViewEnabled ? 1.0 : 0.4,
                child: Container(
                  decoration: BoxDecoration(border: Border.all(color: Theme.of(context).dividerColor), borderRadius: BorderRadius.circular(4)),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(8.0),
                    child: _buildTagWrap(
                      appState.commonTags,
                      imageTagSet: imageTagSet,
                      onTagTap: (tag) => setState(() {
                        if (_selectedCommonTags.contains(tag)) { _selectedCommonTags.remove(tag); } else { _selectedCommonTags.add(tag); }
                      }),
                      onTagDoubleTap: (tag) => _addCommonTagToImageTags(tag),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          if (_tagViewEnabled && newTags.isNotEmpty) ...[
            Text(l10n.newTags, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Expanded(
              flex: 1,
              child: AbsorbPointer(
                absorbing: !_tagViewEnabled,
                child: Opacity(
                  opacity: _tagViewEnabled ? 1.0 : 0.4,
                  child: Container(
                    decoration: BoxDecoration(border: Border.all(color: Theme.of(context).dividerColor), borderRadius: BorderRadius.circular(4)),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(8.0),
                      child: _buildTagWrap(newTags, isNewTag: true, onTagTap: (tag) {
                        context.read<AppState>().addCommonTags([tag]);
                      }),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
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

  Widget _buildReorderableImageTagGrid() {
    if (_imageTags.isEmpty) return const Center(child: Text('No tags.'));

    return ReorderableGridView.builder(
      padding: const EdgeInsets.all(8.0),
      itemCount: _imageTags.length,
      dragEnabled: _tagViewEnabled,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 150,
        mainAxisSpacing: 4.0,
        crossAxisSpacing: 8.0,
        childAspectRatio: 2.5,
      ),
      onReorder: (int oldIndex, int newIndex) {
        setState(() {
          final String tag = _imageTags.removeAt(oldIndex);
          _imageTags.insert(newIndex, tag);
          _rebuildCaptionFromTags();
        });
      },
      itemBuilder: (context, index) {
        return GestureDetector(
          key: ValueKey(_imageTags[index] + index.toString()),
          onDoubleTap: !_tagViewEnabled ? null : () => _editTag(index),
          child: Chip(
            label: Text(_imageTags[index]),
            onDeleted: !_tagViewEnabled ? null : () {
              setState(() {
                _imageTags.removeAt(index);
                _rebuildCaptionFromTags();
              });
            },
          ),
        );
      },
    );
  }

  Widget _buildTagWrap(List<String> tags, {void Function(int)? onDoubleTap, void Function(int)? onDeleted, Set<String>? imageTagSet, bool isNewTag = false, void Function(String)? onTagTap, void Function(String)? onTagDoubleTap}) {
    if (tags.isEmpty) return const Center(child: Text('No tags.'));
    
    return Wrap(
      spacing: 8.0,
      runSpacing: 4.0,
      children: List.generate(tags.length, (index) {
        final tag = tags[index];
        Color? chipColor;
        bool isSelected = false;

        if (imageTagSet != null) {
          chipColor = imageTagSet.contains(tag) ? Colors.green.shade100 : Colors.orange.shade100;
          isSelected = _selectedCommonTags.contains(tag);
        }
        if (isNewTag) {
          chipColor = Colors.grey.shade300;
        }

        return GestureDetector(
          onDoubleTap: onTagDoubleTap != null ? () => onTagDoubleTap(tag) : (onDoubleTap != null ? () => onDoubleTap(index) : null),
          onTap: onTagTap != null ? () => onTagTap(tag) : null,
          child: Chip(
            label: Text(tag),
            backgroundColor: chipColor,
            shape: isSelected ? StadiumBorder(side: BorderSide(color: Theme.of(context).primaryColor, width: 2)) : null,
            onDeleted: onDeleted != null ? () => onDeleted(index) : null,
          ),
        );
      }),
    );
  }
}
