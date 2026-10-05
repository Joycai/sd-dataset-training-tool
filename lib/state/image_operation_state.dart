import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../models/image_operation.dart';
import '../models/image_operation_plan.dart';
import '../models/operation_context.dart';
import '../services/ai_image_service.dart';
import '../services/image_operation_store.dart';
import '../services/image_transform_service.dart';
import 'dataset_state.dart';
import 'tag_ops.dart';

/// Shared by the manual review UI and agent tools. File mutations use TagOps'
/// existing dataset-wide lease, keeping caption undo and image commits serial.
class ImageOperationState extends ChangeNotifier {
  ImageOperationState({
    required this.dataset,
    required this.tagOps,
    required this.serverUrl,
    this.externalBusy,
    this.onApplied,
    this.checkEditor,
    AiImageService? ai,
    ImageTransformService? transforms,
  }) : ai = ai ?? AiImageService(),
       transforms = transforms ?? ImageTransformService(),
       store = ImageOperationStore(dataset.store);
  final DatasetState dataset;
  final TagOps tagOps;
  final String Function() serverUrl;
  final bool Function()? externalBusy;
  final Future<void> Function(Map<String, String> paths)? onApplied;
  final void Function()? checkEditor;
  final AiImageService ai;
  final ImageTransformService transforms;
  final ImageOperationStore store;
  final Map<String, ImageOperationPlan> plans = {};
  final Map<String, List<ImagePreview>> previews = {};
  bool _busy = false, _cancel = false, _disposed = false;
  int completed = 0, total = 0;
  String? currentId;
  ImageOperationResult? lastResult;
  Future<void> get whenIdle {
    if (!_busy) return Future.value();
    final done = Completer<void>();
    void changed() {
      if (!_busy) {
        removeListener(changed);
        done.complete();
      }
    }

    addListener(changed);
    return done.future;
  }

  bool get busy => _busy;
  Completer<void>? _cancelSignal;
  void cancel() {
    _cancel = true;
    final signal = _cancelSignal;
    if (signal != null && !signal.isCompleted) signal.complete();
  }

  bool get _stopped => _cancel || OperationContext.stopped;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _check() {
    OperationContext.check();
    if (_cancel) throw StateError('operation cancelled');
  }

  Future<T> _run<T>(Future<T> Function() body) async {
    if (_busy || tagOps.busy || (externalBusy?.call() ?? false)) {
      throw StateError('Another dataset operation is running');
    }
    _busy = true;
    _cancel = false;
    _cancelSignal = Completer<void>();
    completed = 0;
    _notify();
    try {
      final parent = OperationContext.current;
      return await OperationContext(
        cancelled: () => _cancel || (parent?.cancelled() ?? false),
        invalidReason: parent?.invalidReason,
        writeAuthorized: parent?.writeAuthorized ?? false,
        cancelSignal: Future.any([
          _cancelSignal!.future,
          ?parent?.cancelSignal,
        ]),
      ).run(body);
    } finally {
      _cancelSignal = null;
      _busy = false;
      _notify();
    }
  }

  Future<ImageOperationPlan> prepare({
    required List<String> paths,
    required ImageRecipe recipe,
    bool replace = false,
    String? outputName,
  }) => _run(() async {
    final root = dataset.rootPath;
    if (root == null || dataset.isLoading) {
      throw StateError('Open a dataset first');
    }
    await tagOps.beforeMutate?.call();
    checkEditor?.call();
    final identity = dataset.scopeIdentity;
    if (paths.isEmpty ||
        paths.length > 200 ||
        paths.toSet().length != paths.length) {
      throw const FormatException('Choose 1–200 unique image paths');
    }
    final id =
        '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';
    final output = replace
        ? root
        : p.join(
            p.dirname(root),
            outputName ?? '${p.basename(root)}-processed-$id',
          );
    if (outputName != null) validateImageName(outputName);
    if (!replace && (p.equals(root, output) || p.isWithin(root, output))) {
      throw const FormatException(
        'Derived output must be outside the source dataset',
      );
    }
    await dataset.store.validateAssetPath(p.dirname(root), output);
    if (!replace && await dataset.store.assetExists(output)) {
      throw StateError('Output directory already exists');
    }
    final available = {
      for (final f in dataset.scopedFiles) p.normalize(f.path),
    };
    final items = <ImagePlanItem>[];
    final targets = <String>{};
    final warnings = <String>[
      'Captions are copied unchanged. Review descriptions after cropping or removing backgrounds.',
      'Transformed images have EXIF removed; verify color on a sample before training.',
      if (replace)
        'Originals will be replaced. Backups remain in .dataset-toolkit until you remove them.',
      if (recipe.cropForeground)
        'Foreground mask bounds are not named-object detection; review every crop.',
    ];
    if (recipe.needsAi &&
        !(await ai.models(serverUrl())).contains(recipe.model)) {
      throw StateError('Selected foreground model is unavailable');
    }
    total = paths.length;
    for (var index = 0; index < paths.length; index++) {
      _check();
      final source = p.normalize(p.join(root, paths[index]));
      if (p.isAbsolute(paths[index]) || !available.contains(source)) {
        throw StateError('Image outside the active dataset scope');
      }
      await dataset.store.validateAssetPath(root, source);
      final relative = p.relative(source, from: root);
      final stem = recipe.prefix == null
          ? p.basenameWithoutExtension(source)
          : '${recipe.prefix}_${(index + 1).toString().padLeft(5, '0')}';
      final extension = recipe.format == 'keep'
          ? p.extension(source)
          : recipe.format == 'jpeg'
          ? '.jpg'
          : '.png';
      final target = p.join(output, p.dirname(relative), '$stem$extension');
      final companions = await dataset.store.sidecars(root, source);
      final sidecars = <String, String>{};
      final hashes = <String, String>{};
      for (final caption in companions) {
        sidecars[caption] =
            '${p.withoutExtension(target)}${p.extension(caption)}';
        hashes[caption] = await dataset.store.fingerprint(caption);
      }
      for (final mapping in {source: target, ...sidecars}.entries) {
        if (!targets.add(mapping.value.toLowerCase())) {
          throw StateError('Duplicate output path');
        }
        await dataset.store.validateAssetPath(output, mapping.value);
        await dataset.store.checkPortableCollision(
          mapping.value,
          sameSource: replace ? mapping.key : null,
        );
      }
      items.add(
        ImagePlanItem(
          source: source,
          target: target,
          fingerprint: await dataset.store.fingerprint(source),
          sidecars: sidecars,
          sidecarFingerprints: hashes,
        ),
      );
    }
    final digest = sha256
        .convert(
          utf8.encode(
            jsonEncode({
              'id': id,
              'root': root,
              'output': output,
              'identity': identity,
              'replace': replace,
              'recipe': recipe.toJson(),
              'items': items.map((i) => i.toJson()).toList(),
            }),
          ),
        )
        .toString();
    final plan = ImageOperationPlan(
      id: id,
      digest: digest,
      root: root,
      output: output,
      identity: identity,
      recipe: recipe,
      replace: replace,
      items: items,
      warnings: warnings,
    );
    await store.create(plan);
    currentId = id;
    final thumbs = <ImagePreview>[];
    try {
      for (var index = 0; index < items.length; index++) {
        _check();
        final item = items[index];
        final bytes = await dataset.store.readAsset(root, item.source);
        if (sha256.convert(bytes).toString() != item.fingerprint) {
          throw StateError('Source changed while preparing');
        }
        final foreground = recipe.needsAi
            ? await ai.foreground(serverUrl(), recipe.model!, bytes)
            : null;
        _check();
        final transformed = await transforms.transform(
          bytes,
          recipe,
          foreground: foreground,
        );
        _check();
        await store.saveStaged(plan, index, transformed.bytes);
        if (thumbs.length < 4) {
          thumbs.add(
            ImagePreview(
              item.source,
              await transforms.thumbnail(bytes),
              await transforms.thumbnail(transformed.bytes),
              transformed.width,
              transformed.height,
            ),
          );
        }
        completed++;
        _notify();
      }
      if (dataset.scopeIdentity != identity) {
        throw StateError('Dataset scope changed while preparing');
      }
      plans[id] = plan;
      previews[id] = List.unmodifiable(thumbs);
      await store.setStatus(plan, 'prepared');
      return plan;
    } catch (e) {
      await store.setStatus(plan, _stopped ? 'cancelled' : 'failed', '$e');
      rethrow;
    }
  });

  Future<ImageOperationResult> apply(
    String id,
    String digest, {
    required bool approved,
  }) => _run(() async {
    if (!approved) throw StateError('Image plan approval is required');
    final plan = plans[id];
    if (plan == null || plan.digest != digest) {
      throw StateError('Unknown or changed plan');
    }
    final journal = await store.load(plan.root, id);
    if (journal['status'] == 'completed') return store.result(journal);
    if (journal['status'] != 'prepared') {
      throw StateError(
        'Plan already attempted; inspect status and undo before preparing again',
      );
    }
    if (dataset.scopeIdentity != plan.identity) {
      throw StateError('Dataset scope changed; prepare again');
    }
    currentId = id;
    total = plan.items.length;
    final result = await tagOps.runExclusive(() async {
      await tagOps.beforeMutate?.call();
      checkEditor?.call();
      // Preflight every input and sidecar before any item changes.
      for (final item in plan.items) {
        _check();
        final now = await dataset.store.sidecars(plan.root, item.source);
        if (!listEquals(now, item.sidecars.keys.toList())) {
          throw StateError('Caption sidecars changed');
        }
        for (final entry in {
          item.source: item.fingerprint,
          ...item.sidecarFingerprints,
        }.entries) {
          await dataset.store.validateAssetPath(plan.root, entry.key);
          if (await dataset.store.fingerprint(entry.key) != entry.value) {
            throw StateError('Source changed: ${entry.key}');
          }
        }
      }
      for (var index = 0; index < plan.items.length; index++) {
        if (_stopped || dataset.scopeIdentity != plan.identity) {
          await store.setStatus(plan, 'cancelled');
          break;
        }
        try {
          await store.commitItem(plan, index);
          completed++;
          _notify();
        } catch (e) {
          // commitItem preserves recovery_required if a unit was started.
          final current = await store.load(plan.root, id);
          if (current['status'] != 'recovery_required') {
            await store.setStatus(plan, 'failed', '$e');
          }
          break;
        }
      }
      if (completed == total) await store.setStatus(plan, 'completed');
      final journal = await store.load(plan.root, id);
      if (plan.replace && (journal['units'] as List).isNotEmpty) {
        tagOps.clearHistory();
      }
      return store.result(journal);
    });
    if (result == null) throw StateError('Dataset is busy');
    lastResult = result;
    if (plan.replace) {
      await onApplied?.call({
        for (final item in plan.items.take(result.completed))
          item.source: item.target,
      });
    }
    return result;
  });

  Future<List<ImageOperationResult>> listOperations() async {
    final root = dataset.rootPath;
    if (root == null) throw StateError('Open the source dataset first');
    return store.listOperations(root);
  }

  Future<ImageOperationResult> status(String id) async {
    final root = dataset.rootPath;
    if (root == null) throw StateError('Open the source dataset first');
    return store.result(await store.load(root, id));
  }

  Future<ImageOperationResult> undo(String id, {required bool approved}) =>
      _run(() async {
        if (!approved) throw StateError('Undo approval is required');
        final root = dataset.rootPath;
        if (root == null) throw StateError('Open the source dataset first');
        final journal = await store.load(root, id);
        final plan = journal['plan'] as Map;
        final result = await tagOps.runExclusive(() async {
          await tagOps.beforeMutate?.call();
          checkEditor?.call();
          final restored = await store.undo(root, id);
          if (plan['replace'] == true) tagOps.clearHistory();
          return restored;
        });
        if (result == null) throw StateError('Dataset is busy');
        lastResult = result;
        if (plan['replace'] == true) {
          await onApplied?.call({
            for (final item in plan['items'] as List)
              item['target'] as String: item['source'] as String,
          });
        }
        return result;
      });

  @override
  void dispose() {
    _disposed = true;
    cancel();
    ai.dispose();
    super.dispose();
  }
}
