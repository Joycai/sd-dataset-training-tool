/// Phase 3 agent tools: the WD-tagger bridge (via AiApiServer) and the
/// vision tool that lets multimodal models look at images.
///
/// `run_wd_tagger` never writes captions — it returns tags to the model,
/// which then decides what to keep and writes via the write tools. Results
/// are also stored in [AiTaggerState]'s cache, so the user can review them
/// in the existing compare view.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../../models/ai_tagger_models.dart';
import '../../models/llm_models.dart';
import '../../state/ai_tagger_state.dart';
import '../ai_tagger_service.dart';
import 'agent_tools.dart';
import 'dataset_tools.dart';

// --- WD tagger bridge ---------------------------------------------------

List<AgentTool> buildTaggerTools(DatasetToolsDeps deps, AiTaggerState ai) => [
  AgentTool(
    spec: const AgentToolSpec(
      name: 'list_tagger_models',
      description:
          'List the WD/booru tagger models available on the local '
          'AiApiServer, and which one is currently selected in the UI.',
      parametersSchema: {'type': 'object', 'properties': {}},
    ),
    handler: (args) async {
      try {
        final models = await ai.service.listTaggers(ai.serverUrl);
        return toolOk({
          'server': ai.serverUrl,
          'current': ai.modelName,
          'models': [for (final m in models) m.modelName],
        });
      } on AiTaggerException catch (e) {
        return toolError('AI tagger server unavailable: ${e.message}');
      }
    },
  ),
  AgentTool(
    spec: const AgentToolSpec(
      name: 'run_wd_tagger',
      description:
          'Run the WD/booru tagger on specific images (max 10 per '
          'call, executed serially — the server processes one request '
          'at a time, so this can take a while). Returns predicted '
          'tags per image; nothing is written to disk. To apply '
          'results, filter them yourself and use the write tools.',
      parametersSchema: {
        'type': 'object',
        'properties': {
          'paths': {
            'type': 'array',
            'items': {'type': 'string'},
            'description': 'image paths as returned by list_images',
          },
          'model': {
            'type': 'string',
            'description':
                'tagger model name; defaults to the one selected in '
                'the UI',
          },
          'threshold': {
            'type': 'number',
            'description':
                'confidence threshold override (e.g. 0.35); defaults '
                'to the UI setting / model default',
          },
        },
        'required': ['paths'],
      },
    ),
    handler: (args) async {
      final root = deps.rootDir();
      if (root == null) return toolError('no dataset directory is open');
      final paths = requireStringList(args, 'paths', maxLength: 10);
      final model = optString(args, 'model') ?? ai.modelName;
      if (model == null) {
        return toolError(
          'no tagger model selected; call list_tagger_models and pass '
          'one explicitly, or ask the user to pick one in the UI',
        );
      }
      final threshold = args['threshold'] is num
          ? (args['threshold'] as num).toDouble()
          : ai.threshold;
      final ignore = ai.ignoreTags.map((t) => t.toLowerCase()).toSet();
      final canonical = {
        for (final f in deps.dataset.allFiles) p.canonicalize(f.path): f.path,
      };

      final out = <Map<String, dynamic>>[];
      for (final rel in paths) {
        final resolved = resolveDatasetPath(root, rel);
        final key = resolved == null ? null : canonical[resolved];
        if (key == null) {
          out.add({'path': rel, 'error': 'not found in dataset'});
          continue;
        }
        try {
          final resp = await ai.service.interrogateImageFile(
            ai.serverUrl,
            File(key),
            models: [AiModelRequest.wd(modelName: model, threshold: threshold)],
          );
          // Feed the UI cache too: the user can audit these runs in the
          // compare view.
          ai.storeResult(key, resp);
          final tags = resp.allTags
              .map(
                (t) => AiTaggerService.normalizeTag(
                  t,
                  underscoreStyle: ai.underscoreToSpaces
                      ? TagUnderscoreStyle.toSpaces
                      : TagUnderscoreStyle.keep,
                  escapeParentheses: ai.escapeParentheses,
                ),
              )
              .where((t) => t.isNotEmpty && !ignore.contains(t.toLowerCase()))
              .toList();
          out.add({'path': rel, 'tags': tags});
        } on AiTaggerException catch (e) {
          out.add({'path': rel, 'error': e.message});
        }
      }
      return toolOk({'model': model, 'results': out});
    },
  ),
];

// --- Vision -------------------------------------------------------------

/// Longest-side target for images sent to the model.
const int kVisionMaxDimension = 768;
const int kVisionJpegQuality = 80;

/// Decode → downscale → JPEG, off the UI thread. Returns null when the
/// bytes are not a decodable image.
///
/// The whole pipeline runs inside try/catch: package:image's format
/// sniffers don't guarantee a clean null on garbage input (e.g. the PSD
/// probe throws RangeError on very short buffers).
Future<Uint8List?> compressForVision(Uint8List bytes) => Isolate.run(() {
  try {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    var out = decoded;
    final longest = math.max(out.width, out.height);
    if (longest > kVisionMaxDimension) {
      final scale = kVisionMaxDimension / longest;
      out = img.copyResize(
        out,
        width: math.max(1, (out.width * scale).round()),
        height: math.max(1, (out.height * scale).round()),
        interpolation: img.Interpolation.linear,
      );
    }
    return Uint8List.fromList(img.encodeJpg(out, quality: kVisionJpegQuality));
  } catch (_) {
    return null;
  }
});

/// Only registered for profiles with vision enabled.
List<AgentTool> buildVisionTools(DatasetToolsDeps deps) => [
  AgentTool(
    spec: const AgentToolSpec(
      name: 'view_image',
      description:
          'Attach up to 4 dataset images (downscaled) to the '
          'conversation so you can see them. Expensive in tokens: use '
          'it to spot-check individual images, never to sweep the '
          'dataset — bulk visual tagging belongs to run_wd_tagger.',
      parametersSchema: {
        'type': 'object',
        'properties': {
          'paths': {
            'type': 'array',
            'items': {'type': 'string'},
            'description': 'image paths as returned by list_images',
          },
        },
        'required': ['paths'],
      },
    ),
    handler: (args) async {
      final root = deps.rootDir();
      if (root == null) return toolError('no dataset directory is open');
      final paths = requireStringList(args, 'paths', maxLength: 4);
      final canonical = {
        for (final f in deps.dataset.allFiles) p.canonicalize(f.path): f.path,
      };
      final attached = <String>[];
      final failed = <Map<String, String>>[];
      final parts = <ChatContentPart>[];
      for (final rel in paths) {
        final resolved = resolveDatasetPath(root, rel);
        final key = resolved == null ? null : canonical[resolved];
        if (key == null) {
          failed.add({'path': rel, 'error': 'not found in dataset'});
          continue;
        }
        Uint8List? jpeg;
        try {
          jpeg = await compressForVision(await File(key).readAsBytes());
        } catch (e) {
          failed.add({'path': rel, 'error': 'cannot read image: $e'});
          continue;
        }
        if (jpeg == null) {
          failed.add({'path': rel, 'error': 'not a decodable image'});
          continue;
        }
        attached.add(rel);
        parts.add(ChatContentPart.image(jpeg));
      }
      return AgentToolResult(
        jsonEncode({
          'attached': attached.length,
          // The order of attached images matches this list.
          'paths': attached,
          if (failed.isNotEmpty) 'failed': failed,
        }),
        isError: attached.isEmpty,
        extraParts: parts,
      );
    },
  ),
];
