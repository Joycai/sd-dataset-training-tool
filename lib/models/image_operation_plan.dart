import 'dart:typed_data';

import 'image_operation.dart';

class ImagePlanItem {
  ImagePlanItem({
    required this.source,
    required this.target,
    required this.fingerprint,
    required Map<String, String> sidecars,
    required Map<String, String> sidecarFingerprints,
  }) : sidecars = Map.unmodifiable(sidecars),
       sidecarFingerprints = Map.unmodifiable(sidecarFingerprints);
  final String source, target, fingerprint;

  /// Source caption path -> output caption path.
  final Map<String, String> sidecars, sidecarFingerprints;
  Map<String, dynamic> toJson() => {
    'source': source,
    'target': target,
    'fingerprint': fingerprint,
    'sidecars': sidecars,
    'sidecar_fingerprints': sidecarFingerprints,
  };
}

class ImageOperationPlan {
  ImageOperationPlan({
    required this.id,
    required this.digest,
    required this.root,
    required this.output,
    required this.identity,
    required this.recipe,
    required this.replace,
    required List<ImagePlanItem> items,
    required List<String> warnings,
  }) : items = List.unmodifiable(items),
       warnings = List.unmodifiable(warnings);
  final String id, digest, root, output, identity;
  final ImageRecipe recipe;
  final bool replace;
  final List<ImagePlanItem> items;
  final List<String> warnings;
  Map<String, dynamic> toJson() => {
    'version': 1,
    'id': id,
    'digest': digest,
    'root': root,
    'output': output,
    'identity': identity,
    'replace': replace,
    'recipe': recipe.toJson(),
    'items': items.map((i) => i.toJson()).toList(),
    'warnings': warnings,
  };
}

class ImagePreview {
  const ImagePreview(
    this.source,
    this.before,
    this.after,
    this.width,
    this.height,
  );
  final String source;
  final Uint8List before, after;
  final int width, height;
}

class ImageOperationResult {
  const ImageOperationResult({
    required this.id,
    required this.status,
    required this.completed,
    required this.total,
    this.error,
  });
  final String id, status;
  final int completed, total;
  final String? error;
  Map<String, dynamic> toJson() => {
    'id': id,
    'status': status,
    'completed': completed,
    'total': total,
    if (error != null) 'error': error,
  };
}
