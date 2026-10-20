import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

import '../../utils/constants/vr_scene_constants.dart';
import '../../utils/enums/vr_passthrough_mode.dart';
import '../../utils/enums/vr_spatial_object_category.dart';
import '../models/vr_detected_spatial_object.dart';
import '../models/vr_spatial_contour_segment.dart';

/// Fuses AI object detections and 2D/3D edge contours captured by the
/// **Visor Forward Camera** (`visor_front`), **Joystick Rear Camera**
/// (`joystick_rear`), and **Joystick Front Camera** (`joystick_front`) into a
/// unified 3D spatial map of the user's physical room.
class VrMultiCameraSpaceMapper {
  VrMultiCameraSpaceMapper({
    this.mode = VrPassthroughMode.multiCameraHybridSpace,
    this.safetyRadiusMeters =
        VrSceneConstants.defaultSafetyProximityRadiusMeters,
    double controllerPassthroughMix = 0.0,
  }) : _controllerPassthroughMix = controllerPassthroughMix.clamp(0.0, 1.0);

  VrPassthroughMode mode;
  double safetyRadiusMeters;
  double _controllerPassthroughMix;

  /// Manual passthrough mix percentage (`0.0 .. 1.0`) driven by the
  /// dual-thumb center-to-lateral slide gesture on the Smartphone Joystick.
  double get controllerPassthroughMix => _controllerPassthroughMix;

  /// Updates the passthrough mix percentage (`0.0 .. 1.0`) received from the
  /// Smartphone Joystick (`RemoteControllerState.passthroughMix`).
  void applyControllerPassthroughMix(double mix) {
    _controllerPassthroughMix = mix.clamp(0.0, 1.0);
  }

  final Map<String, VrDetectedSpatialObject> _objectsById =
      <String, VrDetectedSpatialObject>{};
  final List<VrSpatialContourSegment> _freeContours =
      <VrSpatialContourSegment>[];

  /// All currently tracked 3D objects across the 3 cameras.
  List<VrDetectedSpatialObject> get objects =>
      List<VrDetectedSpatialObject>.unmodifiable(_objectsById.values);

  /// All active 3D wireframe contour segments (object bounding contours + free
  /// floor/wall edge segments).
  List<VrSpatialContourSegment> get allContourSegments =>
      <VrSpatialContourSegment>[
        for (final obj in _objectsById.values) ...obj.contourSegments,
        ..._freeContours,
      ];

  /// Registers or updates a 3D AI-detected object in the shared room map.
  void upsertObject(VrDetectedSpatialObject object) {
    _objectsById[object.id] = object;
  }

  /// Removes a tracked object by [id].
  void removeObject(String id) {
    _objectsById.remove(id);
  }

  /// Clears all objects and free contours (e.g. on room recenter).
  void clear() {
    _objectsById.clear();
    _freeContours.clear();
  }

  /// Projects a 2D image contour segment `(uvStart, uvEnd)` (normalized `0..1`)
  /// captured by a camera at [cameraPosition] and [cameraOrientation] onto the
  /// floor plane (`y = floorY`) or at a known metric [depthMeters], adding the
  /// resulting 3D [VrSpatialContourSegment] to the shared space map.
  VrSpatialContourSegment projectImageContourToWorld({
    required Vector2 uvStart,
    required Vector2 uvEnd,
    required Vector3 cameraPosition,
    required Quaternion cameraOrientation,
    double horizontalFovRadians =
        VrSceneConstants.defaultContourHorizontalFovRadians,
    double verticalFovRadians =
        VrSceneConstants.defaultContourVerticalFovRadians,
    double? depthMeters,
    double floorY = 0.0,
    VrSpatialObjectCategory category = VrSpatialObjectCategory.floorBoundary,
    double confidence = 1.0,
  }) {
    final rayStart = _worldRayForUv(
      uv: uvStart,
      cameraOrientation: cameraOrientation,
      horizontalFovRadians: horizontalFovRadians,
      verticalFovRadians: verticalFovRadians,
    );
    final rayEnd = _worldRayForUv(
      uv: uvEnd,
      cameraOrientation: cameraOrientation,
      horizontalFovRadians: horizontalFovRadians,
      verticalFovRadians: verticalFovRadians,
    );

    final start3D = _resolvePointAlongRay(
      origin: cameraPosition,
      ray: rayStart,
      depthMeters: depthMeters,
      floorY: floorY,
    );
    final end3D = _resolvePointAlongRay(
      origin: cameraPosition,
      ray: rayEnd,
      depthMeters: depthMeters,
      floorY: floorY,
    );

    final segment = VrSpatialContourSegment(
      startWorld: start3D,
      endWorld: end3D,
      category: category,
      confidence: confidence,
    );
    _freeContours.add(segment);
    return segment;
  }

  /// Returns the distance in meters to the closest physical obstacle/object
  /// relative to [viewerPosition], or `double.infinity` if none are registered.
  double nearestObstacleDistanceMeters(Vector3 viewerPosition) {
    var minDistance = double.infinity;
    for (final obj in _objectsById.values) {
      if (obj.category == VrSpatialObjectCategory.handController) continue;
      final d = obj.horizontalDistanceToViewerMeters(viewerPosition);
      if (d < minDistance) {
        minDistance = d;
      }
    }
    return minDistance;
  }

  /// Computes the recommended wireframe contour visibility (`0.0..1.0`) and
  /// camera passthrough blend opacity (`0.0..1.0`) given the viewer's
  /// [viewerPosition] and head pitch angle [headPitchRadians] (`< 0` looking down).
  ({double wireframeOpacity, double cameraFeedOpacity}) evaluateVisibility({
    required Vector3 viewerPosition,
    required double headPitchRadians,
  }) {
    final mix = _controllerPassthroughMix.clamp(0.0, 1.0);
    switch (mode) {
      case VrPassthroughMode.off:
        if (mix > 0.0) {
          return (wireframeOpacity: mix, cameraFeedOpacity: mix);
        }
        return (wireframeOpacity: 0.0, cameraFeedOpacity: 0.0);
      case VrPassthroughMode.visorCameraPassthrough:
        final scale = mix > 0.0 ? mix : 1.0;
        return (
          wireframeOpacity:
              (VrSceneConstants.visorPassthroughWireframeScale * scale).clamp(
                0.0,
                1.0,
              ),
          cameraFeedOpacity:
              (VrSceneConstants.visorPassthroughCameraScale * scale).clamp(
                0.0,
                1.0,
              ),
        );
      case VrPassthroughMode.aiWireframeContours:
        final scale = mix > 0.0 ? mix : 1.0;
        return (
          wireframeOpacity: scale.clamp(0.0, 1.0),
          cameraFeedOpacity:
              (mix * VrSceneConstants.wireframeModeCameraMixScale).clamp(
                0.0,
                1.0,
              ),
        );
      case VrPassthroughMode.multiCameraHybridSpace:
        final nearestDist = nearestObstacleDistanceMeters(viewerPosition);
        var proximityFactor = 0.0;
        if (nearestDist < safetyRadiusMeters) {
          proximityFactor =
              ((safetyRadiusMeters - nearestDist) /
                      math.max(
                        VrSceneConstants.minFloorRayDistanceMeters,
                        safetyRadiusMeters -
                            VrSceneConstants
                                .criticalSafetyProximityRadiusMeters,
                      ))
                  .clamp(0.0, 1.0);
        }

        var glanceDownFactor = 0.0;
        if (headPitchRadians <
            VrSceneConstants.glanceDownPitchThresholdRadians) {
          glanceDownFactor =
              ((VrSceneConstants.glanceDownPitchThresholdRadians -
                          headPitchRadians) /
                      (VrSceneConstants.glanceDownPitchThresholdRadians -
                          VrSceneConstants.fullGlanceDownPitchRadians))
                  .clamp(0.0, 1.0);
        }

        final wireframeAlpha = math
            .max(
              mix,
              math.max(
                VrSceneConstants.hybridBaseWireframeOpacity,
                math.max(proximityFactor, glanceDownFactor),
              ),
            )
            .clamp(0.0, 1.0);
        final autoCameraAlpha =
            (glanceDownFactor * VrSceneConstants.hybridGlanceDownCameraWeight +
                    proximityFactor *
                        VrSceneConstants.hybridProximityCameraWeight)
                .clamp(0.0, VrSceneConstants.hybridMaxAutoCameraOpacity);
        final cameraAlpha = math.max(mix, autoCameraAlpha).clamp(0.0, 1.0);
        return (
          wireframeOpacity: wireframeAlpha,
          cameraFeedOpacity: cameraAlpha,
        );
    }
  }

  static Vector3 _worldRayForUv({
    required Vector2 uv,
    required Quaternion cameraOrientation,
    required double horizontalFovRadians,
    required double verticalFovRadians,
  }) {
    final tanHalfH = math.tan(horizontalFovRadians * 0.5);
    final tanHalfV = math.tan(verticalFovRadians * 0.5);
    final ndcX = (uv.x - 0.5) * 2.0;
    final ndcY = (0.5 - uv.y) * 2.0;
    final v = Vector3(ndcX * tanHalfH, ndcY * tanHalfV, -1.0)..normalize();
    final u = Vector3(
      cameraOrientation.x,
      cameraOrientation.y,
      cameraOrientation.z,
    );
    final w = cameraOrientation.w;
    final uvCross = u.cross(v);
    final uuvCross = u.cross(uvCross);
    return (v + uvCross * (2.0 * w) + uuvCross * 2.0)..normalize();
  }

  static Vector3 _resolvePointAlongRay({
    required Vector3 origin,
    required Vector3 ray,
    required double? depthMeters,
    required double floorY,
  }) {
    if (depthMeters != null &&
        depthMeters > VrSceneConstants.minValidContourDepthMeters) {
      return origin + ray * depthMeters;
    }
    if (ray.y < VrSceneConstants.minFloorRaySlopeY && origin.y > floorY) {
      final t = ((floorY - origin.y) / ray.y).clamp(
        VrSceneConstants.minFloorRayDistanceMeters,
        VrSceneConstants.maxFloorRayDistanceMeters,
      );
      return origin + ray * t;
    }
    return origin + ray * VrSceneConstants.defaultFallbackRayDepthMeters;
  }
}
