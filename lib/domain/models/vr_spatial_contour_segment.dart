import 'package:vector_math/vector_math.dart';

import '../../utils/enums/vr_spatial_object_category.dart';

/// A 3D line segment in world space representing an AI-detected object edge,
/// bounding wireframe line, or floor boundary contour.
class VrSpatialContourSegment {
  VrSpatialContourSegment({
    required this.startWorld,
    required this.endWorld,
    this.category = VrSpatialObjectCategory.floorBoundary,
    this.confidence = 1.0,
    int? colorArgb,
  }) : colorArgb = colorArgb ?? category.defaultWireframeColorArgb;

  /// 3D start point in world coordinates (`+Y` up, `-Z` forward, `+X` right).
  final Vector3 startWorld;

  /// 3D end point in world coordinates (`+Y` up, `-Z` forward, `+X` right).
  final Vector3 endWorld;

  /// Semantic classification of the physical contour.
  final VrSpatialObjectCategory category;

  /// Detection confidence (`0.0..1.0`).
  final double confidence;

  /// ARGB neon wireframe color used when rendering the contour in stereo.
  final int colorArgb;

  /// Euclidean length of the 3D contour segment in meters.
  double get lengthMeters => startWorld.distanceTo(endWorld);
}
