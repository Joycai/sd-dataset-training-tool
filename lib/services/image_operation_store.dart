import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../models/image_operation_plan.dart';
import 'dataset_store.dart';

/// Durable transaction journal. Artifacts live outside the scanned dataset
/// contents in .dataset-toolkit. Each image and its sidecars is one recoverable
/// unit. Rollback/undo refuse to overwrite a newer user edit.
class ImageOperationStore {
  ImageOperationStore(this.dataset);
  final DatasetStore dataset;

  String _directory(String root, String id) {
    if (!RegExp(r'^[0-9]+-[0-9]+$').hasMatch(id)) {
      throw const FormatException('Invalid operation ID');
    }
    return p.join(root, '.dataset-toolkit', id);
  }

  Future<void> _save(
    String root,
    String id,
    Map<String, dynamic> journal,
  ) async {
    final path = p.join(_directory(root, id), 'journal.json');
    await dataset.validateAssetPath(root, path);
    await Directory(p.dirname(path)).create(recursive: true);
    await dataset.writeAsset(
      root,
      path,
      utf8.encode(jsonEncode(journal)),
      overwrite: true,
    );
  }

  Future<Map<String, dynamic>> load(String root, String id) async {
    final bytes = await dataset.readAsset(
      root,
      p.join(_directory(root, id), 'journal.json'),
    );
    final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    if (json['version'] != 1 || json['root'] != root || json['id'] != id) {
      throw StateError('Invalid operation journal');
    }
    return json;
  }

  Future<List<ImageOperationResult>> listOperations(String root) async {
    final directory = Directory(p.join(root, '.dataset-toolkit'));
    await dataset.validateAssetPath(root, directory.path);
    if (!await directory.exists()) return [];
    final results = <ImageOperationResult>[];
    await for (final entry in directory.list(followLinks: false)) {
      if (entry is! Directory) continue;
      final id = p.basename(entry.path);
      if (!RegExp(r'^[0-9]+-[0-9]+$').hasMatch(id)) continue;
      try {
        results.add(result(await load(root, id)));
      } catch (e) {
        results.add(
          ImageOperationResult(
            id: id,
            status: 'unreadable',
            completed: 0,
            total: 0,
            error: '$e',
          ),
        );
      }
    }
    results.sort((a, b) => b.id.compareTo(a.id));
    return results;
  }

  Future<bool> exists(String root, String id) =>
      dataset.assetExists(p.join(_directory(root, id), 'journal.json'));

  Future<void> create(ImageOperationPlan plan) => _save(plan.root, plan.id, {
    'version': 1,
    'root': plan.root,
    'id': plan.id,
    'plan': plan.toJson(),
    'status': 'ready',
    'units': <Object>[],
  });

  Future<void> saveStaged(
    ImageOperationPlan plan,
    int index,
    Uint8List bytes,
  ) async {
    await dataset.writeAsset(
      plan.root,
      p.join(_directory(plan.root, plan.id), '$index.image'),
      bytes,
      overwrite: true,
    );
    final journal = await load(plan.root, plan.id);
    final hashes = (journal['staged'] as Map?) ?? <String, dynamic>{};
    hashes['$index'] = sha256.convert(bytes).toString();
    journal['staged'] = hashes;
    await _save(plan.root, plan.id, journal);
  }

  Future<Uint8List> staged(ImageOperationPlan plan, int index) async {
    final bytes = await dataset.readAsset(
      plan.root,
      p.join(_directory(plan.root, plan.id), '$index.image'),
    );
    final journal = await load(plan.root, plan.id);
    if (sha256.convert(bytes).toString() !=
        (journal['staged'] as Map?)?['$index']) {
      throw StateError('Staged preview changed; prepare again');
    }
    return bytes;
  }

  /// Persist all backups and expected output hashes before the first mutation.
  Future<void> commitItem(ImageOperationPlan plan, int index) async {
    final item = plan.items[index];
    final journal = await load(plan.root, plan.id);
    final units = journal['units'] as List;
    if (units.any((u) => u['index'] == index)) {
      throw StateError('Item already attempted');
    }
    final mappings = {item.source: item.target, ...item.sidecars};
    final entries = <Map<String, dynamic>>[];
    var n = 0;
    for (final mapping in mappings.entries) {
      final expected = mapping.key == item.source
          ? item.fingerprint
          : item.sidecarFingerprints[mapping.key];
      await dataset.validateAssetPath(plan.root, mapping.key);
      if (await dataset.fingerprint(mapping.key) != expected) {
        throw StateError('Source changed: ${mapping.key}');
      }
      final original = await dataset.readAsset(plan.root, mapping.key);
      if (sha256.convert(original).toString() != expected) {
        throw StateError('Source changed while backing up');
      }
      final output = mapping.key == item.source
          ? await staged(plan, index)
          : original;
      final backup = p.join(
        _directory(plan.root, plan.id),
        '$index-${n++}.backup',
      );
      await dataset.writeAsset(plan.root, backup, original, overwrite: true);
      entries.add({
        'source': mapping.key,
        'target': mapping.value,
        'backup': backup,
        'before': expected,
        'after': sha256.convert(output).toString(),
      });
    }
    final unit = {'index': index, 'state': 'committing', 'entries': entries};
    units.add(unit);
    journal['status'] = 'running';
    await _save(plan.root, plan.id, journal);
    try {
      for (var i = 0; i < entries.length; i++) {
        final entry = entries[i];
        final source = entry['source'] as String;
        final target = entry['target'] as String;
        final bytes = i == 0
            ? await staged(plan, index)
            : await dataset.readAsset(plan.root, entry['backup'] as String);
        if (await dataset.fingerprint(source) != entry['before']) {
          throw StateError('Source changed during commit');
        }
        await dataset.checkPortableCollision(
          target,
          sameSource: plan.replace ? source : null,
        );
        await dataset.writeAsset(
          plan.output,
          target,
          bytes,
          overwrite: plan.replace && source == target,
        );
      }
      // All companion outputs exist before any renamed original is removed.
      if (plan.replace) {
        for (final entry in entries) {
          if (entry['source'] != entry['target']) {
            final source = entry['source'] as String;
            if (await dataset.fingerprint(source) != entry['before']) {
              throw StateError('Source changed before rename cleanup');
            }
            await dataset.deleteAsset(plan.root, source);
          }
        }
      }
      unit['state'] = 'completed';
      await _save(plan.root, plan.id, journal);
    } catch (e) {
      journal['status'] = 'recovery_required';
      journal['error'] = '$e';
      await _save(plan.root, plan.id, journal);
      // Keep the failed unit's backups/journal. Explicit recovery can inspect
      // conflicts and restore this unit without touching earlier successes.
      rethrow;
    }
  }

  Future<void> setStatus(
    ImageOperationPlan plan,
    String status, [
    String? error,
  ]) async {
    final journal = await load(plan.root, plan.id);
    journal['status'] = status;
    if (error != null) journal['error'] = error;
    await _save(plan.root, plan.id, journal);
  }

  ImageOperationResult result(Map<String, dynamic> journal) =>
      ImageOperationResult(
        id: journal['id'] as String,
        status: journal['status'] as String,
        completed: (journal['units'] as List)
            .where((u) => u['state'] == 'completed')
            .length,
        total: ((journal['plan'] as Map)['items'] as List).length,
        error: journal['error'] as String?,
      );

  /// Undo also recovers an interrupted commit. Check every affected file before
  /// changing any, then persist per-unit progress so recovery is retryable.
  Future<ImageOperationResult> undo(String root, String id) async {
    final journal = await load(root, id);
    final plan = journal['plan'] as Map;
    final output = plan['output'] as String;
    final replace = plan['replace'] as bool;
    if (replace
        ? output != root
        : p.dirname(output) != p.dirname(root) || output == root) {
      throw StateError('Invalid journal output root');
    }
    final units = (journal['units'] as List).reversed.toList();
    // Validate journal paths against the recorded dataset and known artifact
    // directory before reading or restoring anything.
    for (final unit in units) {
      if (unit['state'] == 'undone') continue;
      for (final entry in unit['entries'] as List) {
        final source = entry['source'] as String;
        final target = entry['target'] as String;
        final backup = entry['backup'] as String;
        await dataset.validateAssetPath(root, source);
        await dataset.validateAssetPath(output, target);
        await dataset.validateAssetPath(_directory(root, id), backup);
        if (await dataset.fingerprint(backup) != entry['before']) {
          throw StateError('Backup is damaged');
        }
        if (await dataset.assetExists(target)) {
          final hash = await dataset.fingerprint(target);
          if (hash != entry['after'] &&
              !(source == target && hash == entry['before'])) {
            throw StateError('Undo conflict: $target was edited');
          }
        }
        if (replace &&
            source != target &&
            await dataset.assetExists(source) &&
            await dataset.fingerprint(source) != entry['before']) {
          throw StateError('Undo conflict: $source was edited');
        }
      }
    }
    journal['status'] = 'undoing';
    await _save(root, id, journal);
    for (final unit in units) {
      if (unit['state'] == 'undone') continue;
      for (final entry in (unit['entries'] as List).reversed) {
        final source = entry['source'] as String;
        final target = entry['target'] as String;
        if (replace) {
          await dataset.writeAsset(
            root,
            source,
            await dataset.readAsset(root, entry['backup'] as String),
            overwrite: true,
          );
        }
        if (!replace || source != target) {
          await dataset.deleteAsset(output, target);
        }
      }
      unit['state'] = 'undone';
      await _save(root, id, journal);
    }
    journal['status'] = 'undone';
    journal.remove('error');
    await _save(root, id, journal);
    return result(journal);
  }
}
