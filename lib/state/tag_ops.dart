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

/// How a single-file rewrite ended. "Nothing was written" is not one state
/// but three, and callers must tell them apart: a caller that reads a failed
/// write as "no change needed" moves on from a change that never landed.
enum RewriteOutcome {
  /// The file now holds the requested text.
  written,

  /// The file already held exactly this text; nothing to do.
  unchanged,

  /// Another operation was running; the rewrite was not even attempted.
  busy,

  /// Reading or writing the caption file threw.
  failed,
}

/// The result of [TagOps.rewriteOne].
class RewriteResult {
  const RewriteResult.written()
    : outcome = RewriteOutcome.written,
      error = null;

  const RewriteResult.unchanged()
    : outcome = RewriteOutcome.unchanged,
      error = null;

  const RewriteResult.busy()
    : outcome = RewriteOutcome.busy,
      error = 'another caption operation is still running';

  const RewriteResult.failed(String this.error)
    : outcome = RewriteOutcome.failed;

  final RewriteOutcome outcome;

  /// Why nothing was written; null for [written] and [unchanged].
  final String? error;

  bool get written => outcome == RewriteOutcome.written;

  /// The file already matched the requested text — a legitimate no-op.
  bool get unchanged => outcome == RewriteOutcome.unchanged;

  /// Nothing was written *and* the caller must not read that as "no change
  /// needed": the IO failed or the operation was refused.
  bool get failed => error != null;
}

/// One caption file a batch rewrite could not read or write.
class RewriteFailure {
  const RewriteFailure({required this.captionPath, required this.error});

  final String captionPath;
  final String error;

  @override
  String toString() => '$captionPath: $error';
}

/// The result of a dataset-wide rewrite. A batch never aborts on one bad
/// path, so the files it skipped have to travel back with the count — left
/// out, they read as "no change needed".
class BatchRewriteResult {
  const BatchRewriteResult({required this.changed, required this.failures});

  const BatchRewriteResult.none() : changed = 0, failures = const [];

  /// Number of caption files actually rewritten.
  final int changed;

  final List<RewriteFailure> failures;

  int get failed => failures.length;
}

/// The result of an undo or redo.
///
/// A replay writes many files and one of them can fail — a caption open in
/// another program, a folder gone read-only. Silently restoring the rest
/// leaves the dataset half-reverted with the operation gone from the stack,
/// so failures travel back and the operation stays put (see [TagOps.undo]).
class ReplayResult {
  const ReplayResult({required this.restored, required this.failures});

  const ReplayResult.none() : restored = 0, failures = const [];

  /// Number of caption files written back.
  final int restored;

  final List<RewriteFailure> failures;

  int get failed => failures.length;

  /// The operation is still on the stack: replaying again retries exactly
  /// the files that failed (the ones that succeeded already hold the text
  /// this replay wanted, so they are no-ops).
  bool get retryable => failures.isNotEmpty;
}

/// Dataset-wide caption rewrites — delete / replace / insert next to a tag —
/// with an undo/redo history. "Dataset-wide" means the dataset's active
/// subdirectory scope ([DatasetState.scopedFiles]): when the navigator is
/// showing one folder, so is every sweep here.
///
/// Each operation snapshots the exact on-disk text of every file it touches,
/// so undo restores files byte-for-byte even though the rewrite itself
/// normalizes separators to ", ".
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

  /// Removes [tag] from every caption.
  Future<BatchRewriteResult> deleteEverywhere(
    String tag, {
    required String label,
  }) {
    return _rewriteAll(label, (tags) {
      if (!tags.contains(tag)) return null;
      return tags.where((t) => t != tag).toList();
    });
  }

  /// Replaces [tag] in place with the (comma-splittable) replacement,
  /// de-duplicating against the file's remaining tags.
  Future<BatchRewriteResult> replaceEverywhere(
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
  Future<BatchRewriteResult> insertBeside(
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
  /// the sweep further with [files] (e.g. the filtered gallery); defaults to
  /// the active subdirectory scope.
  Future<BatchRewriteResult> addEverywhere(
    String input, {
    int? index,
    List<File>? files,
    required String label,
  }) {
    final parts = parseTagText(input);
    if (parts.isEmpty) return Future.value(const BatchRewriteResult.none());
    return _rewriteAll(
      label,
      (tags) {
        final next = [...tags];
        final seen = next.toSet();
        final fresh = parts.where(seen.add).toList();
        if (fresh.isEmpty) return null;
        next.insertAll((index ?? next.length).clamp(0, next.length), fresh);
        return next;
      },
      files: files,
      createMissing: true,
    );
  }

  /// Reorders many captions against one [priority] list: tags named there
  /// come first, in that order; every other tag keeps its relative position
  /// (at the end, or the front with [unlistedFirst]). [keepFirst] leaves that
  /// many leading tags where they are — the LoRA trigger word usually has to
  /// stay first.
  ///
  /// The result is a permutation of each file's own tags by construction:
  /// tags are bucketed, never re-typed, so unlike a per-image rewrite this
  /// cannot add, drop or reword anything. (Exact duplicates within one file
  /// still collapse, as they do in every rewrite — [parseTagText] is the
  /// shared grammar.) Matching folds case and underscore
  /// style ([tagLookupKey]), so a priority entry of `long hair` also ranks a
  /// file's `long_hair` — which keeps its own spelling on disk.
  Future<BatchRewriteResult> reorderEverywhere(
    List<String> priority, {
    List<File>? files,
    int keepFirst = 0,
    bool unlistedFirst = false,
    required String label,
  }) {
    // First occurrence wins: a duplicated priority entry must not create a
    // second bucket that silently reorders past the first.
    final rank = <String, int>{};
    for (var i = 0; i < priority.length; i++) {
      rank.putIfAbsent(tagLookupKey(priority[i]), () => i);
    }
    if (rank.isEmpty) return Future.value(const BatchRewriteResult.none());
    return _rewriteAll(label, (tags) {
      if (tags.length < 2) return null;
      final head = tags.take(keepFirst.clamp(0, tags.length)).toList();
      final buckets = List.generate(priority.length, (_) => <String>[]);
      final unlisted = <String>[];
      for (final tag in tags.skip(head.length)) {
        final index = rank[tagLookupKey(tag)];
        if (index == null) {
          unlisted.add(tag);
        } else {
          buckets[index].add(tag);
        }
      }
      return [
        ...head,
        if (unlistedFirst) ...unlisted,
        for (final bucket in buckets) ...bucket,
        if (!unlistedFirst) ...unlisted,
      ];
    }, files: files);
  }

  /// Rewrites one image's caption file to exactly [text], recording undo.
  /// A missing caption file is created. The result distinguishes a real
  /// write from an identical-content no-op and from an IO failure — see
  /// [RewriteOutcome].
  Future<RewriteResult> rewriteOne(
    String imagePath,
    String text, {
    required String label,
  }) async {
    if (_busy) return const RewriteResult.busy();
    _busy = true;
    notifyListeners();
    final RewriteResult result;
    try {
      result = await _rewriteOneLocked(imagePath, text, label);
    } finally {
      _busy = false;
      notifyListeners();
    }
    if (result.written) onCaptionsChanged?.call({imagePath});
    return result;
  }

  /// The body of [rewriteOne], run with [_busy] already held.
  Future<RewriteResult> _rewriteOneLocked(
    String imagePath,
    String text,
    String label,
  ) async {
    await beforeMutate?.call();
    final captionPath = dataset.captionPathFor(imagePath);
    final captionFile = File(captionPath);
    var before = '';
    try {
      if (await captionFile.exists()) {
        before = await captionFile.readAsString();
      }
    } catch (e) {
      return RewriteResult.failed('cannot read "$captionPath": $e');
    }
    if (before == text) return const RewriteResult.unchanged();
    try {
      await captionFile.writeAsString(text);
    } catch (e) {
      return RewriteResult.failed('cannot write "$captionPath": $e');
    }
    dataset.updateCaptionText(imagePath, text);
    _undoStack.add(
      TagOperation(
        label: label,
        edits: [
          CaptionEdit(
            imagePath: imagePath,
            captionPath: captionPath,
            before: before,
            after: text,
          ),
        ],
      ),
    );
    _redoStack.clear();
    return const RewriteResult.written();
  }

  /// Records an operation whose file rewrites already happened elsewhere
  /// (e.g. a batch AI tagging run) so it participates in undo/redo.
  void pushOperation(TagOperation op) {
    if (op.edits.isEmpty) return;
    _undoStack.add(op);
    _redoStack.clear();
    notifyListeners();
  }

  /// Restores every file of the most recent operation. When some file cannot
  /// be written the operation is *not* moved to the redo stack: the dataset
  /// is half-reverted, and leaving it in place lets the next undo retry those
  /// files rather than step past them. The caller must surface
  /// [ReplayResult.failed] — a partial undo that reports nothing is exactly
  /// the silent failure the write tools were fixed for.
  Future<ReplayResult> undo() =>
      _replay(from: _undoStack, to: _redoStack, undo: true);

  Future<ReplayResult> redo() =>
      _replay(from: _redoStack, to: _undoStack, undo: false);

  /// Runs [transform] over every captioned image ([files] defaults to the
  /// dataset's active subdirectory scope); a null return leaves the file
  /// untouched. With [createMissing], uncaptioned images run through as the
  /// empty tag list and get their caption file created. IO failures skip the
  /// file so one bad path never aborts the batch — only files actually
  /// rewritten enter the history — but every skip is collected into
  /// [BatchRewriteResult.failures] so the caller can report it instead of
  /// passing it off as "no change needed".
  Future<BatchRewriteResult> _rewriteAll(
    String label,
    List<String>? Function(List<String> tags) transform, {
    List<File>? files,
    bool createMissing = false,
  }) async {
    if (_busy) return const BatchRewriteResult.none();
    _busy = true;
    notifyListeners();
    final edits = <CaptionEdit>[];
    final failures = <RewriteFailure>[];
    try {
      await beforeMutate?.call();
      for (final file in files ?? dataset.scopedFiles) {
        final captionPath = dataset.captionPathFor(file.path);
        final captionFile = File(captionPath);
        var before = '';
        try {
          if (await captionFile.exists()) {
            before = await captionFile.readAsString();
          } else if (!createMissing) {
            continue;
          }
        } catch (e) {
          failures.add(
            RewriteFailure(captionPath: captionPath, error: 'cannot read: $e'),
          );
          continue;
        }
        final tags = parseCaptionText(before, prose: dataset.captionProse);
        final next = transform(tags);
        // No semantic change: don't rewrite the file just to normalize
        // separators.
        if (next == null || listEquals(next, tags)) continue;
        final after = joinCaptionText(next, prose: dataset.captionProse);
        try {
          await captionFile.writeAsString(after);
        } catch (e) {
          failures.add(
            RewriteFailure(captionPath: captionPath, error: 'cannot write: $e'),
          );
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
    return BatchRewriteResult(changed: edits.length, failures: failures);
  }

  Future<ReplayResult> _replay({
    required List<TagOperation> from,
    required List<TagOperation> to,
    required bool undo,
  }) async {
    if (_busy || from.isEmpty) return const ReplayResult.none();
    _busy = true;
    notifyListeners();
    final touched = <String>{};
    final failures = <RewriteFailure>[];
    var restored = 0;
    try {
      await beforeMutate?.call();
      // Peeked, not popped: whether the operation leaves this stack depends
      // on every file being written.
      final op = from.last;
      final applied = <String, String>{};
      for (final edit in op.edits) {
        final text = undo ? edit.before : edit.after;
        try {
          await File(edit.captionPath).writeAsString(text);
          restored++;
        } catch (e) {
          failures.add(
            RewriteFailure(captionPath: edit.captionPath, error: '$e'),
          );
          continue;
        }
        // An edit can target a non-active caption type (the assistant's
        // variant writes); its text must not enter the active caption state.
        if (edit.captionPath == dataset.captionPathFor(edit.imagePath)) {
          applied[edit.imagePath] = text;
          touched.add(edit.imagePath);
        }
      }
      dataset.updateCaptionTexts(applied);
      if (failures.isEmpty) {
        from.removeLast();
        to.add(op);
      }
    } finally {
      _busy = false;
      notifyListeners();
    }
    if (touched.isNotEmpty) {
      onCaptionsChanged?.call(touched);
    }
    return ReplayResult(restored: restored, failures: failures);
  }
}
