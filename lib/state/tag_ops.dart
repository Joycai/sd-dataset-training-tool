import 'dart:io';

import 'package:flutter/foundation.dart';

import '../utils/tag_text.dart';
import 'dataset_state.dart';

/// One caption file rewrite: the exact text before and after.
class CaptionEdit {
  const CaptionEdit({
    required this.imagePath,
    required this.captionPath,
    required this.before,
    required this.after,
  });

  final String imagePath;
  final String captionPath;
  final String before;
  final String after;
}

/// A dataset-wide operation: a user-facing label plus every file it touched.
class TagOperation {
  const TagOperation({required this.label, required this.edits});

  final String label;
  final List<CaptionEdit> edits;
}

/// Dataset-wide caption rewrites — delete / replace / insert next to a tag —
/// with an undo/redo history. Each operation snapshots the exact on-disk text
/// of every file it touches, so undo restores files byte-for-byte even though
/// the rewrite itself normalizes separators to ", ".
class TagOps extends ChangeNotifier {
  TagOps({required this.dataset, this.beforeMutate, this.onCaptionsChanged});

  final DatasetState dataset;

  /// Awaited before any disk mutation; the workbench flushes the editor
  /// session here so pending edits are not silently overwritten.
  Future<void> Function()? beforeMutate;

  /// Reports every image whose caption file was rewritten, so the currently
  /// open image can be reloaded from disk.
  void Function(Set<String> imagePaths)? onCaptionsChanged;

  final List<TagOperation> _undoStack = [];
  final List<TagOperation> _redoStack = [];
  bool _busy = false;

  bool get busy => _busy;
  bool get canUndo => !_busy && _undoStack.isNotEmpty;
  bool get canRedo => !_busy && _redoStack.isNotEmpty;
  String? get undoLabel => _undoStack.isEmpty ? null : _undoStack.last.label;
  String? get redoLabel => _redoStack.isEmpty ? null : _redoStack.last.label;

  /// Dropped when the dataset directory changes: the snapshots would point at
  /// files of the previous dataset.
  void clearHistory() {
    if (_undoStack.isEmpty && _redoStack.isEmpty) return;
    _undoStack.clear();
    _redoStack.clear();
    notifyListeners();
  }

  /// Removes [tag] from every caption. Returns the number of files changed.
  Future<int> deleteEverywhere(String tag, {required String label}) {
    return _rewriteAll(label, (tags) {
      if (!tags.contains(tag)) return null;
      return tags.where((t) => t != tag).toList();
    });
  }

  /// Replaces [tag] in place with the (comma-splittable) replacement,
  /// de-duplicating against the file's remaining tags.
  Future<int> replaceEverywhere(
    String tag,
    String replacementInput, {
    required String label,
  }) {
    final parts = parseTagText(replacementInput);
    return _rewriteAll(label, (tags) {
      final index = tags.indexOf(tag);
      if (index < 0) return null;
      final next = [...tags]..removeAt(index);
      final seen = next.toSet();
      next.insertAll(index, parts.where(seen.add));
      return next;
    });
  }

  /// Inserts the (comma-splittable) input directly before or after [tag] in
  /// every caption that has it, skipping tags the file already contains.
  Future<int> insertBeside(
    String tag,
    String insertionInput, {
    required bool after,
    required String label,
  }) {
    final parts = parseTagText(insertionInput);
    return _rewriteAll(label, (tags) {
      final index = tags.indexOf(tag);
      if (index < 0) return null;
      final next = [...tags];
      final seen = next.toSet();
      next.insertAll(after ? index + 1 : index, parts.where(seen.add));
      return next;
    });
  }

  /// Adds the (comma-splittable) input to every caption at [index] (0 =
  /// first, null = after the last tag; clamped), skipping tags a file
  /// already has. Uncaptioned images get their caption file created; undoing
  /// writes the empty string back rather than deleting the file. Restrict
  /// the sweep with [files] (e.g. the filtered gallery); defaults to the
  /// whole dataset.
  Future<int> addEverywhere(
    String input, {
    int? index,
    List<File>? files,
    required String label,
  }) {
    final parts = parseTagText(input);
    if (parts.isEmpty) return Future.value(0);
    return _rewriteAll(label, (tags) {
      final next = [...tags];
      final seen = next.toSet();
      final fresh = parts.where(seen.add).toList();
      if (fresh.isEmpty) return null;
      next.insertAll((index ?? next.length).clamp(0, next.length), fresh);
      return next;
    }, files: files, createMissing: true);
  }

  /// Records an operation whose file rewrites already happened elsewhere
  /// (e.g. a batch AI tagging run) so it participates in undo/redo.
  void pushOperation(TagOperation op) {
    if (op.edits.isEmpty) return;
    _undoStack.add(op);
    _redoStack.clear();
    notifyListeners();
  }

  Future<void> undo() => _replay(from: _undoStack, to: _redoStack, undo: true);

  Future<void> redo() => _replay(from: _redoStack, to: _undoStack, undo: false);

  /// Runs [transform] over every captioned image ([files] defaults to the
  /// whole dataset); a null return leaves the file untouched. With
  /// [createMissing], uncaptioned images run through as the empty tag list
  /// and get their caption file created. IO failures skip the file so one
  /// bad path never aborts the batch — only files actually rewritten enter
  /// the history.
  Future<int> _rewriteAll(
    String label,
    List<String>? Function(List<String> tags) transform, {
    List<File>? files,
    bool createMissing = false,
  }) async {
    if (_busy) return 0;
    _busy = true;
    notifyListeners();
    final edits = <CaptionEdit>[];
    try {
      await beforeMutate?.call();
      for (final file in files ?? dataset.allFiles) {
        final captionPath = dataset.captionPathFor(file.path);
        final captionFile = File(captionPath);
        var before = '';
        try {
          if (await captionFile.exists()) {
            before = await captionFile.readAsString();
          } else if (!createMissing) {
            continue;
          }
        } catch (_) {
          continue;
        }
        final tags = parseTagText(before);
        final next = transform(tags);
        // No semantic change: don't rewrite the file just to normalize
        // separators.
        if (next == null || listEquals(next, tags)) continue;
        final after = next.join(', ');
        try {
          await captionFile.writeAsString(after);
        } catch (_) {
          continue;
        }
        edits.add(
          CaptionEdit(
            imagePath: file.path,
            captionPath: captionPath,
            before: before,
            after: after,
          ),
        );
      }
      if (edits.isNotEmpty) {
        dataset.updateCaptionTexts({
          for (final e in edits) e.imagePath: e.after,
        });
        _undoStack.add(TagOperation(label: label, edits: edits));
        _redoStack.clear();
      }
    } finally {
      _busy = false;
      notifyListeners();
    }
    if (edits.isNotEmpty) {
      onCaptionsChanged?.call({for (final e in edits) e.imagePath});
    }
    return edits.length;
  }

  Future<void> _replay({
    required List<TagOperation> from,
    required List<TagOperation> to,
    required bool undo,
  }) async {
    if (_busy || from.isEmpty) return;
    _busy = true;
    notifyListeners();
    final touched = <String>{};
    try {
      await beforeMutate?.call();
      final op = from.removeLast();
      final applied = <String, String>{};
      for (final edit in op.edits) {
        final text = undo ? edit.before : edit.after;
        try {
          await File(edit.captionPath).writeAsString(text);
        } catch (_) {
          continue;
        }
        applied[edit.imagePath] = text;
        touched.add(edit.imagePath);
      }
      dataset.updateCaptionTexts(applied);
      to.add(op);
    } finally {
      _busy = false;
      notifyListeners();
    }
    if (touched.isNotEmpty) {
      onCaptionsChanged?.call(touched);
    }
  }
}
