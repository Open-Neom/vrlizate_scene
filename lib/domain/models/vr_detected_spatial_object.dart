import 'package:vector_math/vector_math.dart';

import '../../utils/constants/vr_scene_constants.dart';
import '../../utils/enums/vr_spatial_object_category.dart';
import 'vr_spatial_contour_segment.dart';

/// Represents a physical object or boundary identified by AI in one of the
/// three smartphone cameras (`visor_front`, `joystick_rear`, `joystick_front`)
/// and mapped into the shared 3D room coordinate system.
class VrDetectedSpatialObject {
  VrDetectedSpatialObject({
    required this.id,
    required this.label,
    required this.category,
    required this.centerWorld,
    required this.extentsWorld,
    this.contourSegments = const <VrSpatialContourSegment>[],
    this.confidence = 1.0,
    this.sourceCameraId = VrSceneConstants.cameraSourceVisorFront,
  });

  /// Creates a 3D bounding wireframe box of 12 [VrSpatialContourSegment]s
  /// around [centerWorld] with [extentsWorld] (`width`, `height`, `depth`).
  factory VrDetectedSpatialObject.fromBoundingBox3D({
    required String id,
    required String label,
    required VrSpatialObjectCategory category,
    required Vector3 centerWorld,
    required Vector3 extentsWorld,
    double confidence = 1.0,
    String sourceCameraId = VrSceneConstants.cameraSourceVisorFront,
  }) {
    final hx = extentsWorld.x * 0.5;
    final hy = extentsWorld.y * 0.5;
    final hz = extentsWorld.z * 0.5;
    final c = centerWorld;

    final c000 = Vector3(c.x - hx, c.y - hy, c.z - hz);
    final c100 = Vector3(c.x + hx, c.y - hy, c.z - hz);
    final c101 = Vector3(c.x + hx, c.y - hy, c.z + hz);
    final c001 = Vector3(c.x - hx, c.y - hy, c.z + hz);

    final c010 = Vector3(c.x - hx, c.y + hy, c.z - hz);
    final c110 = Vector3(c.x + hx, c.y + hy, c.z - hz);
    final c111 = Vector3(c.x + hx, c.y + hy, c.z + hz);
    final c011 = Vector3(c.x - hx, c.y + hy, c.z + hz);

    VrSpatialContourSegment seg(Vector3 a, Vector3 b) =>
        VrSpatialContourSegment(
          startWorld: a,
          endWorld: b,
          category: category,
          confidence: confidence,
        );

    return VrDetectedSpatialObject(
      id: id,
      label: label,
      category: category,
      centerWorld: centerWorld,
      extentsWorld: extentsWorld,
      confidence: confidence,
      sourceCameraId: sourceCameraId,
      contourSegments: <VrSpatialContourSegment>[
        // Bottom rectangle
        seg(c000, c100),
        seg(c100, c101),
        seg(c101, c001),
        seg(c001, c000),
        // Top rectangle
        seg(c010, c110),
        seg(c110, c111),
        seg(c111, c011),
        seg(c011, c010),
        // Vertical pillars
        seg(c000, c010),
        seg(c100, c110),
        seg(c101, c111),
        seg(c001, c011),
      ],
    );
  }

  final String id;
  final String label;
  final VrSpatialObjectCategory category;
  final Vector3 centerWorld;
  final Vector3 extentsWorld;
  final List<VrSpatialContourSegment> contourSegments;
  final double confidence;
  final String sourceCameraId;

  /// Horizontal ground-plane distance from [viewerPosition] to the nearest
  /// surface of this object's bounding box in meters.
  double horizontalDistanceToViewerMeters(Vector3 viewerPosition) {
    final dx =
        (viewerPosition.x - centerWorld.x).abs() - (extentsWorld.x * 0.5);
    final dz =
        (viewerPosition.z - centerWorld.z).abs() - (extentsWorld.z * 0.5);
    final clampedDx = dx > 0.0 ? dx : 0.0;
    final clampedDz = dz > 0.0 ? dz : 0.0;
    return Vector2(clampedDx, clampedDz).length;
  }
}
