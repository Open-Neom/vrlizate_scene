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
///
/// Experimental spatial mapping helper: projections without calibrated camera
/// extrinsics are heuristic estimates and do not constitute certified physical
/// obstacle measurements.
class VrMultiCameraSpaceMapper {
  VrMultiCameraSpaceMapper({
    this.mode = VrPassthroughMode.multiCameraHybridSpace,
    this.safetyRadiusMeters =
        VrSceneConstants.defaultSafetyProximityRadiusMeters,
    double controllerPassthroughMix = 0.0,
    bool showObjectBoundingBoxes = true,
    this.temporalSmoothingAlpha = 0.25,
    this.minRenderableConfidence = 0.30,
    this.allowGuardianPassthroughWhenOff = false,
    this.maxTrackedObjects = VrSceneConstants.defaultMaxTrackedSpatialObjects,
    this.maxFreeContours = VrSceneConstants.defaultMaxFreeContourSegments,
  }) : assert(maxTrackedObjects > 0),
       assert(maxFreeContours > 0),
       _controllerPassthroughMix = controllerPassthroughMix.clamp(0.0, 1.0),
       _showObjectBoundingBoxes = showObjectBoundingBoxes;

  VrPassthroughMode mode;
  double safetyRadiusMeters;
  double _controllerPassthroughMix;
  double _guardianPassthroughFloorMix = 0.0;
  bool _guardianFloorOverridesOffMode = false;
  bool _showObjectBoundingBoxes;

  /// Whether automatic Guardian proximity alerts are permitted to raise
  /// passthrough visibility while [mode] is [VrPassthroughMode.off].
  ///
  /// Defaults to `false` so explicit `off` mode never turns on the camera feed
  /// automatically unless opted in by the host.
  bool allowGuardianPassthroughWhenOff;

  /// Maximum number of tracked 3D spatial objects retained concurrently.
  final int maxTrackedObjects;

  /// Maximum number of free 3D contour segments retained concurrently.
  final int maxFreeContours;

  /// Exponential smoothing factor (`0.05 .. 1.0`) applied when updating an
  /// existing [VrDetectedSpatialObject]'s 3D position, extents, and confidence
  /// so bounding boxes glide smoothly instead of snapping frame-to-frame.
  double temporalSmoothingAlpha;

  /// Minimum object detection confidence required to emit bounding box lines.
  double minRenderableConfidence;

  /// Whether 3D object bounding boxes are rendered in [allContourSegments].
  /// Live visor sessions default this to `false` so unverified boxes never
  /// obstruct the user's field of view unless explicitly enabled.
  bool get showObjectBoundingBoxes => _showObjectBoundingBoxes;
  set showObjectBoundingBoxes(bool value) {
    if (_showObjectBoundingBoxes == value) return;
    _showObjectBoundingBoxes = value;
    _cachedContourSegments = null;
  }

  /// Manual passthrough mix percentage (`0.0 .. 1.0`) driven by the
  /// dual-thumb center-to-lateral slide gesture on the Smartphone Joystick.
  ///
  /// Never overwritten by automatic Guardian proximity floors.
  double get controllerPassthroughMix => _controllerPassthroughMix;

  /// Temporary automatic passthrough floor (`0.0 .. 1.0`) applied by
  /// `VrPhysicalGuardianService` while an obstacle alert is active, and
  /// cleared back to `0.0` once the proximity alert resolves.
  double get guardianPassthroughFloorMix => _guardianPassthroughFloorMix;

  /// Effective passthrough mix combining manual [controllerPassthroughMix] and
  /// temporary [guardianPassthroughFloorMix] according to [mode],
  /// [allowGuardianPassthroughWhenOff], and any active per-call Guardian
  /// override.
  double get effectivePassthroughMix {
    final manual = _controllerPassthroughMix.clamp(0.0, 1.0);
    if (mode == VrPassthroughMode.off &&
        !allowGuardianPassthroughWhenOff &&
        !_guardianFloorOverridesOffMode) {
      return manual;
    }
    return math.max(manual, _guardianPassthroughFloorMix).clamp(0.0, 1.0);
  }

  /// Updates the manual passthrough mix percentage (`0.0 .. 1.0`) received from
  /// the Smartphone Joystick (`RemoteControllerState.passthroughMix`).
  void applyControllerPassthroughMix(double mix) {
    _controllerPassthroughMix = mix.clamp(0.0, 1.0);
  }

  /// Applies or updates the temporary automatic Guardian passthrough floor
  /// (`0.0 .. 1.0`) without modifying manual [controllerPassthroughMix] or
  /// [allowGuardianPassthroughWhenOff].
  ///
  /// When [overrideOffMode] is `true` and [floorMix] `> 0`, this temporary
  /// floor is permitted to raise [effectivePassthroughMix] while [mode] is
  /// [VrPassthroughMode.off] until [clearGuardianPassthroughFloor], [clear],
  /// or a subsequent call with [overrideOffMode] `false`.
  void applyGuardianPassthroughFloor(
    double floorMix, {
    bool overrideOffMode = false,
  }) {
    final normalized = floorMix.isFinite ? floorMix.clamp(0.0, 1.0) : 0.0;
    _guardianPassthroughFloorMix = normalized;
    _guardianFloorOverridesOffMode = normalized > 0.0 && overrideOffMode;
  }

  /// Clears any temporary automatic Guardian passthrough floor, restoring
  /// visibility strictly to the user's manual [controllerPassthroughMix].
  void clearGuardianPassthroughFloor() {
    _guardianPassthroughFloorMix = 0.0;
    _guardianFloorOverridesOffMode = false;
  }

  final Map<String, VrDetectedSpatialObject> _objectsById =
      <String, VrDetectedSpatialObject>{};
  final Map<String, int> _objectUpdatedAtMicros = <String, int>{};
  final List<VrSpatialContourSegment> _freeContours =
      <VrSpatialContourSegment>[];
  final List<int?> _freeContourTimestampsMicros = <int?>[];
  List<VrSpatialContourSegment>? _cachedContourSegments;

  /// All currently tracked 3D objects across the 3 cameras.
  List<VrDetectedSpatialObject> get objects =>
      List<VrDetectedSpatialObject>.unmodifiable(_objectsById.values);

  /// All active 3D wireframe contour segments (object bounding contours when
  /// [showObjectBoundingBoxes] is enabled + free floor/wall edge segments).
  List<VrSpatialContourSegment> get allContourSegments =>
      _cachedContourSegments ??= List<VrSpatialContourSegment>.unmodifiable(
        <VrSpatialContourSegment>[
          if (_showObjectBoundingBoxes)
            for (final obj in _objectsById.values)
              if (obj.confidence >= minRenderableConfidence)
                ...obj.contourSegments,
          ..._freeContours,
        ],
      );

  /// Registers or updates a 3D AI-detected object in the shared room map,
  /// applying exponential temporal smoothing when [temporalSmoothingAlpha] `< 1.0`.
  void upsertObject(VrDetectedSpatialObject object, {int? timestampMicros}) {
    final existing = _objectsById[object.id];
    if (existing == null && _objectsById.length >= maxTrackedObjects) {
      final oldestDynamicKey = _objectsById.keys.firstWhere(
        (k) =>
            k.startsWith('lidar_') ||
            k.startsWith('ble_') ||
            k.startsWith('verify_'),
        orElse: () => _objectsById.keys.first,
      );
      _objectsById.remove(oldestDynamicKey);
      _objectUpdatedAtMicros.remove(oldestDynamicKey);
    }

    final alpha = temporalSmoothingAlpha.clamp(0.05, 1.0);
    VrDetectedSpatialObject resolved = object;
    if (existing != null && alpha < 0.999 && object.contourSegments.length == 12) {
      final smoothedCenter =
          existing.centerWorld +
          (object.centerWorld - existing.centerWorld) * alpha;
      final smoothedExtents =
          existing.extentsWorld +
          (object.extentsWorld - existing.extentsWorld) * alpha;
      final smoothedConf =
          existing.confidence +
          (object.confidence - existing.confidence) * alpha;
      resolved = VrDetectedSpatialObject.fromBoundingBox3D(
        id: object.id,
        label: object.label,
        category: object.category,
        centerWorld: smoothedCenter,
        extentsWorld: smoothedExtents,
        confidence: smoothedConf,
        sourceCameraId: object.sourceCameraId,
      );
    }

    _objectsById[object.id] = resolved;
    if (timestampMicros != null) {
      _objectUpdatedAtMicros[object.id] = timestampMicros;
    }
    _cachedContourSegments = null;
  }

  /// Decays confidence and prunes stale bounding boxes (and timestamped free
  /// contours) that have stopped receiving detections so ghost geometry never
  /// lingers in space.
  void pruneStaleObjects({
    required int nowMicros,
    int maxAgeMicros = VrSceneConstants.defaultMaxSpatialObjectAgeMicros,
  }) {
    var modified = false;
    if (_objectUpdatedAtMicros.isNotEmpty) {
      final toRemove = <String>[];
      for (final entry in _objectUpdatedAtMicros.entries) {
        if (nowMicros - entry.value > maxAgeMicros) {
          toRemove.add(entry.key);
        }
      }
      if (toRemove.isNotEmpty) {
        for (final id in toRemove) {
          _objectsById.remove(id);
          _objectUpdatedAtMicros.remove(id);
        }
        modified = true;
      }
    }
    if (pruneStaleContours(nowMicros: nowMicros, maxAgeMicros: maxAgeMicros)) {
      modified = true;
    }
    if (modified) {
      _cachedContourSegments = null;
    }
  }

  /// Prunes timestamped free contour segments older than [maxAgeMicros].
  bool pruneStaleContours({
    required int nowMicros,
    int maxAgeMicros = VrSceneConstants.defaultMaxContourAgeMicros,
  }) {
    if (_freeContours.isEmpty) return false;
    var removed = false;
    for (var i = _freeContours.length - 1; i >= 0; i--) {
      final ts = _freeContourTimestampsMicros[i];
      if (ts != null && nowMicros - ts > maxAgeMicros) {
        _freeContours.removeAt(i);
        _freeContourTimestampsMicros.removeAt(i);
        removed = true;
      }
    }
    if (removed) {
      _cachedContourSegments = null;
    }
    return removed;
  }

  /// Removes a tracked object by [id].
  void removeObject(String id) {
    _objectsById.remove(id);
    _objectUpdatedAtMicros.remove(id);
    _cachedContourSegments = null;
  }

  /// Clears all objects, free contours, and temporary Guardian passthrough
  /// floors (e.g. on room recenter) while preserving manual
  /// [controllerPassthroughMix].
  void clear() {
    _objectsById.clear();
    _objectUpdatedAtMicros.clear();
    _freeContours.clear();
    _freeContourTimestampsMicros.clear();
    _guardianPassthroughFloorMix = 0.0;
    _guardianFloorOverridesOffMode = false;
    _cachedContourSegments = null;
  }

  /// Current number of free 3D contour segments stored in the room map.
  int get freeContourCount => _freeContours.length;

  /// Projects a 2D image contour segment `(uvStart, uvEnd)` (normalized `0..1`)
  /// captured by a camera at [cameraPosition] and [cameraOrientation] onto the
  /// floor plane (`y = floorY`) or at a known metric [depthMeters], adding the
  /// resulting 3D [VrSpatialContourSegment] to the shared space map within
  /// [maxFreeContours] budget.
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
    int? timestampMicros,
  }) {
    if (timestampMicros != null) {
      pruneStaleContours(nowMicros: timestampMicros);
    }
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

    final clampedConfidence = confidence.isFinite
        ? confidence.clamp(0.0, 1.0)
        : 0.0;
    final segment = VrSpatialContourSegment(
      startWorld: start3D,
      endWorld: end3D,
      category: category,
      confidence: clampedConfidence,
    );
    while (_freeContours.length >= maxFreeContours) {
      _freeContours.removeAt(0);
      _freeContourTimestampsMicros.removeAt(0);
    }
    _freeContours.add(segment);
    _freeContourTimestampsMicros.add(timestampMicros);
    _cachedContourSegments = null;
    return segment;
  }

  /// Returns the distance in meters to the closest physical obstacle/object
  /// meeting [minRenderableConfidence] relative to [viewerPosition], or
  /// `double.infinity` if none are registered.
  double nearestObstacleDistanceMeters(Vector3 viewerPosition) {
    var minDistance = double.infinity;
    for (final obj in _objectsById.values) {
      if (obj.category == VrSpatialObjectCategory.handController) continue;
      if (!obj.confidence.isFinite ||
          obj.confidence < minRenderableConfidence) {
        continue;
      }
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
    final mix = effectivePassthroughMix;
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
