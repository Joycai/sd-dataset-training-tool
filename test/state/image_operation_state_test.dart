import 'dart:io';

import 'package:dataset_training_tool/models/image_operation.dart';
import 'package:dataset_training_tool/services/dataset_store.dart';
import 'package:dataset_training_tool/state/dataset_state.dart';
import 'package:dataset_training_tool/state/image_operation_state.dart';
import 'package:dataset_training_tool/state/tag_ops.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

class FailingStore extends DatasetStore {
  bool failCaption = false;
  @override
  Future<void> writeAsset(
    String root,
    String path,
    List<int> bytes, {
    bool overwrite = false,
  }) async {
    if (failCaption && path.endsWith('.txt')) {
      failCaption = false;
      throw const FileSystemException('injected full disk');
    }
    await super.writeAsset(root, path, bytes, overwrite: overwrite);
  }
}

void main() {
  late Directory temp;
  late DatasetState dataset;
  late TagOps tags;
  late ImageOperationState state;
  late FailingStore store;
  late String root;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('image_operations_');
    root = p.join(temp.path, 'source');
    await Directory(root).create();
    for (final name in ['a', 'b']) {
      await File(
        p.join(root, '$name.png'),
      ).writeAsBytes(img.encodePng(img.Image(width: 40, height: 20)));
      await File(p.join(root, '$name.txt')).writeAsString('subject, blue');
      await File(p.join(root, '$name.ntxt')).writeAsString('A subject.\r\n');
    }
    store = FailingStore();
    dataset = DatasetState(store: store);
    await dataset.scan(
      directoryPath: root,
      recursive: true,
      captionExtension: '.txt',
    );
    tags = TagOps(dataset: dataset);
    state = ImageOperationState(
      dataset: dataset,
      tagOps: tags,
      serverUrl: () => 'http://unused',
    );
  });
  tearDown(() async {
    state.dispose();
    tags.dispose();
    dataset.dispose();
    await temp.delete(recursive: true);
  });

  test(
    'undoing derived outputs preserves source caption undo history',
    () async {
      await tags.rewriteOne(
        p.join(root, 'a.png'),
        'caption edit',
        label: 'caption edit',
      );
      final plan = await state.prepare(
        paths: ['a.png'],
        recipe: ImageRecipe.fromJson({}),
      );
      await state.apply(plan.id, plan.digest, approved: true);
      await state.undo(plan.id, approved: true);
      expect(tags.canUndo, true);
      await tags.undo();
      expect(await File(p.join(root, 'a.txt')).readAsString(), 'subject, blue');
    },
  );
  test('failed editor flush prevents staging and dataset changes', () async {
    state.dispose();
    state = ImageOperationState(
      dataset: dataset,
      tagOps: tags,
      serverUrl: () => '',
      checkEditor: () => throw StateError('unsaved caption'),
    );
    await expectLater(
      state.prepare(paths: ['a.png'], recipe: ImageRecipe.fromJson({})),
      throwsStateError,
    );
    expect(await Directory(p.join(root, '.dataset-toolkit')).exists(), false);
    expect(state.busy, false);
  });
  test('in-place apply and undo report selection remapping', () async {
    state.dispose();
    Map<String, String>? mapping;
    state = ImageOperationState(
      dataset: dataset,
      tagOps: tags,
      serverUrl: () => '',
      onApplied: (paths) async {
        mapping = paths;
      },
    );
    final plan = await state.prepare(
      paths: ['a.png'],
      recipe: ImageRecipe.fromJson({'prefix': 'renamed', 'format': 'keep'}),
      replace: true,
    );
    await state.apply(plan.id, plan.digest, approved: true);
    expect(mapping, {plan.items.single.source: plan.items.single.target});
    await state.undo(plan.id, approved: true);
    expect(mapping, {plan.items.single.target: plan.items.single.source});
  });
  test(
    'derived rename/resize preserves all sidecars and supports restart undo',
    () async {
      final plan = await state.prepare(
        paths: ['a.png'],
        recipe: ImageRecipe.fromJson({
          'prefix': 'train',
          'width': 20,
          'height': 20,
        }),
      );
      expect(await File(plan.items.single.target).exists(), false);
      expect(state.previews[plan.id]!.single.width, 20);
      final result = await state.apply(plan.id, plan.digest, approved: true);
      expect(result.status, 'completed');
      expect(
        await File(p.join(plan.output, 'train_00001.ntxt')).readAsString(),
        'A subject.\r\n',
      );
      expect(await File(p.join(root, 'a.png')).exists(), true);
      expect(
        (await state.apply(plan.id, plan.digest, approved: true)).status,
        'completed',
      );
      state.dispose();
      state = ImageOperationState(
        dataset: dataset,
        tagOps: tags,
        serverUrl: () => '',
      );
      expect((await state.status(plan.id)).status, 'completed');
      expect((await state.listOperations()).single.id, plan.id);
      expect((await state.undo(plan.id, approved: true)).status, 'undone');
      expect(await File(plan.items.single.target).exists(), false);
      expect(await File(p.join(root, 'a.png')).exists(), true);
    },
  );
  test('changed source or generation prevents every write', () async {
    final plan = await state.prepare(
      paths: ['a.png'],
      recipe: ImageRecipe.fromJson({}),
    );
    await File(p.join(root, 'a.txt')).writeAsString('new edit');
    await expectLater(
      state.apply(plan.id, plan.digest, approved: true),
      throwsStateError,
    );
    expect(await File(plan.items.single.target).exists(), false);
    final next = await state.prepare(
      paths: ['b.png'],
      recipe: ImageRecipe.fromJson({}),
    );
    await dataset.scan(
      directoryPath: root,
      recursive: true,
      captionExtension: '.txt',
    );
    await expectLater(
      state.apply(next.id, next.digest, approved: true),
      throwsStateError,
    );
  });
  test('missing approval and wrong digest refuse commit', () async {
    final plan = await state.prepare(
      paths: ['a.png'],
      recipe: ImageRecipe.fromJson({}),
    );
    await expectLater(
      state.apply(plan.id, plan.digest, approved: false),
      throwsStateError,
    );
    await expectLater(
      state.apply(plan.id, 'other', approved: true),
      throwsStateError,
    );
    expect(await File(plan.items.single.target).exists(), false);
  });
  test('in-place rename restores image and exact caption bytes', () async {
    final before = await File(p.join(root, 'a.png')).readAsBytes();
    final plan = await state.prepare(
      paths: ['a.png'],
      recipe: ImageRecipe.fromJson({'prefix': 'renamed', 'format': 'keep'}),
      replace: true,
    );
    expect(
      (await state.apply(plan.id, plan.digest, approved: true)).status,
      'completed',
    );
    expect(await File(p.join(root, 'a.png')).exists(), false);
    await state.undo(plan.id, approved: true);
    expect(await File(p.join(root, 'a.png')).readAsBytes(), before);
    expect(await File(plan.items.single.target).exists(), false);
    expect(await File(p.join(root, 'a.ntxt')).readAsString(), 'A subject.\r\n');
  });
  test(
    'partial paired write failure is recoverable without losing originals',
    () async {
      final plan = await state.prepare(
        paths: ['a.png'],
        recipe: ImageRecipe.fromJson({'prefix': 'renamed'}),
        replace: true,
      );
      store.failCaption = true;
      expect(
        (await state.apply(plan.id, plan.digest, approved: true)).status,
        'recovery_required',
      );
      expect((await state.undo(plan.id, approved: true)).status, 'undone');
      expect(await File(p.join(root, 'a.txt')).readAsString(), 'subject, blue');
      expect(await File(plan.items.single.target).exists(), false);
    },
  );
  test(
    'undo refuses edited output before touching any other companion',
    () async {
      final plan = await state.prepare(
        paths: ['a.png'],
        recipe: ImageRecipe.fromJson({}),
      );
      await state.apply(plan.id, plan.digest, approved: true);
      await File(p.join(plan.output, 'a.txt')).writeAsString('user edit');
      await expectLater(state.undo(plan.id, approved: true), throwsStateError);
      expect(await File(plan.items.single.target).exists(), true);
      expect(
        await File(p.join(plan.output, 'a.txt')).readAsString(),
        'user edit',
      );
    },
  );
  test('cancel finishes current pair and skips remaining images', () async {
    final plan = await state.prepare(
      paths: ['a.png', 'b.png'],
      recipe: ImageRecipe.fromJson({}),
    );
    void stop() {
      if (state.completed == 1) state.cancel();
    }

    state.addListener(stop);
    final result = await state.apply(plan.id, plan.digest, approved: true);
    state.removeListener(stop);
    expect(result.status, 'cancelled');
    expect(result.completed, 1);
    expect(await File(plan.items[1].target).exists(), false);
    await state.undo(plan.id, approved: true);
    expect(await File(plan.items[0].target).exists(), false);
  });
  test(
    'rejects ambiguous stems, output collisions, and outside paths',
    () async {
      await File(p.join(root, 'a.jpg')).writeAsBytes([1]);
      await expectLater(
        state.prepare(paths: ['a.png'], recipe: ImageRecipe.fromJson({})),
        throwsA(isA<FileSystemException>()),
      );
      await expectLater(
        state.prepare(
          paths: ['../escape.png'],
          recipe: ImageRecipe.fromJson({}),
        ),
        throwsStateError,
      );
      await Directory(p.join(temp.path, 'existing')).create();
      await expectLater(
        state.prepare(
          paths: ['b.png'],
          recipe: ImageRecipe.fromJson({}),
          outputName: 'existing',
        ),
        throwsStateError,
      );
    },
  );
  test(
    'rejects symlink traversal at the I/O boundary',
    () async {
      final link = Link(p.join(root, 'escape'));
      await link.create(temp.path);
      await expectLater(
        store.writeAsset(root, p.join(link.path, 'bad.png'), [1]),
        throwsA(isA<FileSystemException>()),
      );
    },
    skip: Platform.isWindows
        ? 'Symlink privileges are environment-dependent'
        : false,
  );
}
