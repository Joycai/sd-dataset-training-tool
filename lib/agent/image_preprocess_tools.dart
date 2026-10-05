import 'dart:convert';

import 'package:path/path.dart' as p;

import '../models/image_operation.dart';
import '../models/llm_models.dart';
import '../models/operation_context.dart';
import '../state/image_operation_state.dart';
import 'agent_tools.dart';

List<AgentTool> buildImagePreprocessTools(
  ImageOperationState state, {
  bool supportsVision = true,
}) {
  AgentTool tool(
    String name,
    String description,
    Map<String, dynamic> properties,
    List<String> required,
    AgentToolHandler handler, {
    bool write = false,
  }) => AgentTool(
    isWrite: write,
    spec: AgentToolSpec(
      name: name,
      description: description,
      parametersSchema: {
        'type': 'object',
        'properties': properties,
        'required': required,
        'additionalProperties': false,
      },
    ),
    handler: handler,
  );
  const paths = {
    'type': 'array',
    'items': {'type': 'string'},
    'minItems': 1,
    'maxItems': 200,
  };
  const id = {'type': 'string'};
  return [
    tool(
      'inspect_images',
      'Inspect up to 20 scoped dataset images in EXIF-normalized source pixels before cropping.',
      {'paths': paths},
      ['paths'],
      (args) async {
        final root = state.dataset.rootPath;
        if (root == null) return toolError('no dataset is open');
        final allowed = {
          for (final f in state.dataset.scopedFiles) p.normalize(f.path),
        };
        final results = <Map<String, dynamic>>[];
        for (final rel in requireStringList(args, 'paths', maxLength: 20)) {
          OperationContext.check();
          final source = p.normalize(p.join(root, rel));
          if (p.isAbsolute(rel) || !allowed.contains(source)) {
            return toolError('image outside dataset scope');
          }
          final size = await state.transforms.inspect(
            await state.dataset.store.readAsset(root, source),
          );
          results.add({
            'path': rel,
            'width': size.width,
            'height': size.height,
            'format': p.extension(source),
            'coordinate_frame': 'exif_normalized_pixels',
            'sidecars': (await state.dataset.store.sidecars(
              root,
              source,
            )).map((s) => p.relative(s, from: root)).toList(),
          });
        }
        return toolOk({'images': results});
      },
    ),
    tool(
      'list_image_processing_models',
      'Discover AI foreground removal models. Foreground-mask cropping is supported; named-object detection is not.',
      {},
      [],
      (_) async => toolOk({
        'models': await state.ai.models(state.serverUrl()),
        'named_object_detection': false,
      }),
    ),
    tool(
      'plan_image_operations',
      'Prepare and render an immutable image operation plan (max 200 images). No dataset images/captions change. Creates recoverable staging artifacts. Review previews before applying. Default is a separate derived dataset. Prefix renames image AND same-stem captions. Foreground crop uses a segmentation mask, not named-object detection.',
      {
        'paths': paths,
        'replace': {'type': 'boolean'},
        'output_name': id,
        'recipe': {
          'type': 'object',
          'additionalProperties': false,
          'properties': {
            'width': {'type': 'integer'},
            'height': {'type': 'integer'},
            'resize_mode': {
              'type': 'string',
              'enum': ['fit', 'crop', 'pad'],
            },
            'upscale': {'type': 'boolean'},
            'format': {
              'type': 'string',
              'enum': ['png', 'jpeg', 'keep'],
            },
            'quality': {'type': 'integer'},
            'background': {
              'type': 'array',
              'items': {'type': 'integer'},
              'minItems': 3,
              'maxItems': 3,
            },
            'crop': {
              'type': 'array',
              'items': {'type': 'integer'},
              'minItems': 4,
              'maxItems': 4,
              'description': '[x,y,width,height] in oriented source pixels',
            },
            'remove_background': {'type': 'boolean'},
            'crop_foreground': {'type': 'boolean'},
            'margin': {'type': 'integer'},
            'model': id,
            'prefix': id,
          },
        },
      },
      ['paths', 'recipe'],
      (args) async {
        final recipe = args['recipe'];
        if (recipe is! Map<String, dynamic>) {
          return toolError('recipe must be an object');
        }
        final plan = await state.prepare(
          paths: requireStringList(args, 'paths', maxLength: 200),
          recipe: ImageRecipe.fromJson(recipe),
          replace: optBool(args, 'replace'),
          outputName: optString(args, 'output_name'),
        );
        return toolOk({
          'id': plan.id,
          'digest': plan.digest,
          'count': plan.items.length,
          'output': plan.output,
          'replace': plan.replace,
          'recipe': plan.recipe.toJson(),
          'warnings': plan.warnings,
          'sample': plan.items.take(4).map((i) => i.toJson()).toList(),
        });
      },
    ),
    tool(
      'preview_image_operations',
      'Read before/after preview pairs for a prepared plan. The review UI also displays these. Output previews are the staged bytes used for apply.',
      {'id': id},
      ['id'],
      (args) async {
        final previews = state.previews[requireString(args, 'id')]
            ?.take(2)
            .toList();
        if (previews == null) return toolError('unknown prepared plan');
        return toolOk(
          {
            'images': [
              for (final preview in previews)
                {
                  'source': preview.source,
                  'width': preview.width,
                  'height': preview.height,
                },
            ],
            'order': 'before, after for each source',
          },
          extraParts: supportsVision
              ? [
                  for (final preview in previews) ...[
                    ChatContentPart.image(
                      preview.before,
                      imageMimeType: 'image/png',
                    ),
                    ChatContentPart.image(
                      preview.after,
                      imageMimeType: 'image/png',
                    ),
                  ],
                ]
              : const [],
        );
      },
    ),
    tool(
      'apply_image_operation_plan',
      'Apply the exact reviewed plan and digest. Requires write authorization. Stale sources/scopes fail. Check the returned status; partial/cancelled/recovery_required is not completion.',
      {'id': id, 'digest': id},
      ['id', 'digest'],
      (args) async {
        final result = await state.apply(
          requireString(args, 'id'),
          requireString(args, 'digest'),
          approved: OperationContext.current?.writeAuthorized ?? false,
        );
        return AgentToolResult(
          jsonEncode(result.toJson()),
          isError: result.status != 'completed',
        );
      },
      write: true,
    ),
    tool(
      'list_image_operations',
      'List durable image operations for the open source dataset, including interrupted operations after restart.',
      {},
      [],
      (_) async => toolOk({
        'operations': (await state.listOperations())
            .take(50)
            .map((r) => r.toJson())
            .toList(),
      }),
    ),
    tool(
      'get_image_operation_status',
      'Read durable operation status by ID, including after restarting with the source dataset open.',
      {'id': id},
      ['id'],
      (args) async =>
          toolOk((await state.status(requireString(args, 'id'))).toJson()),
    ),
    tool(
      'undo_image_operation',
      'Undo or recover an image operation by ID. Restores originals and removes generated outputs only if fingerprints still match; newer edits are protected.',
      {'id': id},
      ['id'],
      (args) async => toolOk(
        (await state.undo(
          requireString(args, 'id'),
          approved: OperationContext.current?.writeAuthorized ?? false,
        )).toJson(),
      ),
      write: true,
    ),
  ];
}
