import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

import '../../utils/constants/vr_scene_constants.dart';
import '../../utils/enums/vr_sensing_modality.dart';
import '../../utils/enums/vr_spatial_object_category.dart';
import '../models/vr_acoustic_sonar_echo.dart';
import '../models/vr_detected_spatial_object.dart';
import '../models/vr_rf_radio_beacon_sample.dart';
import '../models/vr_spatial_contour_segment.dart';
import '../models/vr_synthetic_lidar_point.dart';
import 'vr_multi_camera_space_mapper.dart';

/// Reconstructs a 3D room model and occupancy voxel cloud comparable to
/// hardware LiDAR by fusing standard sensors present on conventional
/// smartphones:
/// 1. **Tri-Camera Vision** (`visor_front`, `joystick_rear`, `joystick_front`)
/// 2. **Multi-Frequency Acoustic Sonar** ($4\text{–}22\text{ kHz}$ FMCW echoes
///    & dual-mic TDOA azimuth)
/// 3. **Wi-Fi Sensing** (IEEE 802.11mc RTT + Dual-Phone RSSI Shadowing)
/// 4. **Bluetooth BLE Radar** (Dual-Phone Differential RSSI/AoA Trilateration)
class VrSyntheticLidarScanner {
  VrSyntheticLidarScanner({
    this.voxelSizeMeters = VrSceneConstants.defaultLidarVoxelSizeMeters,
  }) : assert(voxelSizeMeters > 0.02);

  final double voxelSizeMeters;

  final Map<String, VrSyntheticLidarPoint> _voxels =
      <String, VrSyntheticLidarPoint>{};
  final Map<String, VrDetectedSpatialObject> _reconstructedObjects =
      <String, VrDetectedSpatialObject>{};
  final List<VrSpatialContourSegment> _reconstructedContours =
      <VrSpatialContourSegment>[];
  int _sonarSurfaceCounter = 0;

  /// All occupied 3D voxels with confidence above threshold.
  List<VrSyntheticLidarPoint> get occupiedPoints => _voxels.values
      .where(
        (point) =>
            point.confidence >= VrSceneConstants.minOccupiedVoxelConfidence,
      )
      .toList(growable: false);

  /// All 3D spatial objects synthesized from Sonar, Wi-Fi, and BLE.
  List<VrDetectedSpatialObject> get reconstructedObjects =>
      List<VrDetectedSpatialObject>.unmodifiable(_reconstructedObjects.values);

  /// All 3D wireframe contour segments synthesized from acoustic and RF scans.
  List<VrSpatialContourSegment> get reconstructedContours =>
      List<VrSpatialContourSegment>.unmodifiable(_reconstructedContours);

  /// Clears all accumulated voxels and reconstructed surfaces.
  void clear() {
    _voxels.clear();
    _reconstructedObjects.clear();
    _reconstructedContours.clear();
    _sonarSurfaceCounter = 0;
  }

  /// Ingests an acoustic/ultrasonic sonar echo captured by either the Visor or
  /// the Joystick smartphone and projects the reflecting surface patch into 3D
  /// world coordinates.
  VrSyntheticLidarPoint ingestAcousticSonarEcho({
    required VrAcousticSonarEcho echo,
    required Vector3 sensorPosition,
    required Vector3 sensorForward,
    Vector3? sensorRight,
  }) {
    final forward = sensorForward.length2 > 1e-6
        ? sensorForward.normalized()
        : Vector3(0.0, 0.0, -1.0);
    final up = Vector3(0.0, 1.0, 0.0);
    final right = (sensorRight != null && sensorRight.length2 > 1e-6)
        ? sensorRight.normalized()
        : (forward.cross(up).length2 > 1e-6
              ? forward.cross(up).normalized()
              : Vector3(1.0, 0.0, 0.0));

    final azimuth = echo.estimatedAzimuthRadians;
    final rayDir =
        (forward * math.cos(azimuth) + right * math.sin(azimuth)).normalized();
    final distance = echo.radialDistanceMeters;
    final hitPoint = sensorPosition + rayDir * distance;
    final normal = -rayDir;

    final category = hitPoint.y <= 0.18
        ? VrSpatialObjectCategory.floorBoundary
        : (distance <= VrSceneConstants.defaultSafetyProximityRadiusMeters
              ? VrSpatialObjectCategory.obstacle
              : VrSpatialObjectCategory.wall);

    final point = _upsertVoxel(
      worldPosition: hitPoint,
      normal: normal,
      modality: VrSensingModality.acousticSonarEcho,
      category: category,
      baseConfidence: (0.45 + echo.reflectionAmplitude * 0.45).clamp(0.40, 0.95),
      acousticReflectivity: echo.reflectionAmplitude,
    );

    // Synthesize a local tangent planar contour patch perpendicular to the ray
    final halfWidth = VrSceneConstants.sonarPatchHalfWidthMeters;
    final tangent = normal.cross(up).length2 > 1e-5
        ? normal.cross(up).normalized()
        : Vector3(1.0, 0.0, 0.0);
    final segStart = hitPoint - tangent * halfWidth;
    final segEnd = hitPoint + tangent * halfWidth;
    _reconstructedContours.add(
      VrSpatialContourSegment(
        startWorld: segStart,
        endWorld: segEnd,
        category: category,
        confidence: point.confidence,
      ),
    );

    _sonarSurfaceCounter++;
    final surfaceId =
        '${VrSceneConstants.syntheticSonarWallPrefix}$_sonarSurfaceCounter';
    _reconstructedObjects[surfaceId] = VrDetectedSpatialObject.fromBoundingBox3D(
      id: surfaceId,
      label: surfaceId,
      category: category,
      centerWorld: hitPoint,
      extentsWorld: Vector3(halfWidth * 2.0, halfWidth * 2.0, 0.08),
      confidence: point.confidence,
      sourceCameraId: VrSceneConstants.modalityAcousticSonarEchoId,
    );

    return point;
  }

  /// Ingests a simultaneous Wi-Fi (`802.11mc` RTT / RSSI) or Bluetooth
  /// (`BLE 5.x/6.0`) sample from both the **Visor Smartphone** ([visorPosition])
  /// and the **Joystick Smartphone** ([joystickPosition]), triangulating the
  /// 3D radio source and any intervening shadowed wall plane.
  VrSyntheticLidarPoint ingestDualPhoneRfSample({
    required VrRfRadioBeaconSample sample,
    required Vector3 visorPosition,
    required Vector3 visorForward,
    required Vector3 joystickPosition,
  }) {
    final forward = visorForward.length2 > 1e-6
        ? visorForward.normalized()
        : Vector3(0.0, 0.0, -1.0);
    final up = Vector3(0.0, 1.0, 0.0);
    final right = forward.cross(up).length2 > 1e-6
        ? forward.cross(up).normalized()
        : Vector3(1.0, 0.0, 0.0);

    final distVisor = sample.estimateDistanceFromVisorMeters();
    final distJoystick = sample.estimateDistanceFromJoystickMeters();
    final azimuth = sample.aoaAzimuthRadians ?? 0.0;

    final horizontalDir =
        (forward * math.cos(azimuth) + right * math.sin(azimuth)).normalized();

    // Use the differential distance between Visor (head) and Joystick (hands)
    // to solve vertical elevation along the Visor-Joystick baseline.
    final baselineVec = visorPosition - joystickPosition;
    final baselineLen = baselineVec.length;
    var verticalOffset = 0.0;
    if (baselineLen > 0.10) {
      final cosElevation =
          ((distJoystick * distJoystick -
                      distVisor * distVisor -
                      baselineLen * baselineLen) /
                  (2.0 * distVisor * baselineLen))
              .clamp(-0.85, 0.85);
      verticalOffset = distVisor * cosElevation * 0.35;
    }

    final estimatedPos = Vector3(
      visorPosition.x + horizontalDir.x * distVisor,
      math.max(0.15, visorPosition.y + verticalOffset),
      visorPosition.z + horizontalDir.z * distVisor,
    );

    final normal = (visorPosition - estimatedPos).length2 > 1e-6
        ? (visorPosition - estimatedPos).normalized()
        : -forward;

    final point = _upsertVoxel(
      worldPosition: estimatedPos,
      normal: normal,
      modality: sample.modality,
      category: VrSpatialObjectCategory.table,
      baseConfidence: sample.rttDistanceMeters != null ? 0.85 : 0.65,
      rfAttenuationDb: sample.estimatedWallAttenuationDb,
    );

    final anchorId = '${VrSceneConstants.syntheticRfAnchorPrefix}${sample.beaconId}';
    final boxSize = VrSceneConstants.rfBeaconBoundingSizeMeters;
    _reconstructedObjects[anchorId] = VrDetectedSpatialObject.fromBoundingBox3D(
      id: anchorId,
      label: sample.label,
      category: VrSpatialObjectCategory.table,
      centerWorld: estimatedPos,
      extentsWorld: Vector3(boxSize, boxSize, boxSize),
      confidence: point.confidence,
      sourceCameraId: sample.modality.id,
    );

    // If Wi-Fi or BLE exhibits wall shadowing (>= 6 dB attenuation), infer an
    // intervening wall plane halfway along the ray.
    if (sample.hasWallShadowing) {
      final wallPos = visorPosition + (estimatedPos - visorPosition) * 0.55;
      _upsertVoxel(
        worldPosition: wallPos,
        normal: normal,
        modality: sample.modality,
        category: VrSpatialObjectCategory.wall,
        baseConfidence: 0.72,
        rfAttenuationDb: sample.estimatedWallAttenuationDb,
      );
      final shadowWallId =
          '${VrSceneConstants.syntheticRfWallShadowPrefix}${sample.beaconId}';
      _reconstructedObjects[shadowWallId] =
          VrDetectedSpatialObject.fromBoundingBox3D(
        id: shadowWallId,
        label: shadowWallId,
        category: VrSpatialObjectCategory.wall,
        centerWorld: wallPos,
        extentsWorld: Vector3(1.20, 1.80, 0.12),
        confidence: 0.72,
        sourceCameraId: sample.modality.id,
      );
    }

    return point;
  }

  /// Ingests a 3D optical point from the Tri-Camera vision pipeline and fuses
  /// it into the shared voxel grid, boosting confidence when corroborated by
  /// Sonar or RF.
  VrSyntheticLidarPoint ingestVisualDepthPoint({
    required Vector3 worldPosition,
    required Vector3 normal,
    VrSpatialObjectCategory category = VrSpatialObjectCategory.table,
    double confidence = 0.75,
  }) {
    return _upsertVoxel(
      worldPosition: worldPosition,
      normal: normal,
      modality: VrSensingModality.triCameraVision,
      category: category,
      baseConfidence: confidence,
    );
  }

  /// Synchronizes all synthesized 3D objects and contour segments into
  /// [spaceMapper] so they render immediately in the stereo visor passthrough
  /// wireframe overlay.
  void syncToSpaceMapper(VrMultiCameraSpaceMapper spaceMapper) {
    for (final obj in _reconstructedObjects.values) {
      spaceMapper.upsertObject(obj);
    }
  }

  VrSyntheticLidarPoint _upsertVoxel({
    required Vector3 worldPosition,
    required Vector3 normal,
    required VrSensingModality modality,
    required VrSpatialObjectCategory category,
    required double baseConfidence,
    double acousticReflectivity = 0.0,
    double rfAttenuationDb = 0.0,
  }) {
    final key = _voxelKeyFor(worldPosition);
    final existing = _voxels[key];
    if (existing == null) {
      final created = VrSyntheticLidarPoint(
        voxelKey: key,
        position: worldPosition.clone(),
        normal: normal.normalized(),
        primaryModality: modality,
        contributingModalities: <VrSensingModality>{modality},
        category: category,
        confidence: baseConfidence.clamp(0.0, 1.0),
        acousticReflectivity: acousticReflectivity,
        rfAttenuationDb: rfAttenuationDb,
      );
      _voxels[key] = created;
      return created;
    }

    final mergedModalities = <VrSensingModality>{
      ...existing.contributingModalities,
      modality,
    };
    final isNewModality =
        !existing.contributingModalities.contains(modality);
    final synergyBonus = isNewModality
        ? VrSceneConstants.multiModalSynergyBonus
        : VrSceneConstants.occupancyHitConfidenceDelta * 0.5;
    final updatedConfidence = (math.max(existing.confidence, baseConfidence) +
            synergyBonus)
        .clamp(0.0, 1.0);

    final blendedPos = (existing.position + worldPosition) * 0.5;
    final updated = VrSyntheticLidarPoint(
      voxelKey: key,
      position: blendedPos,
      normal: normal.normalized(),
      primaryModality: existing.primaryModality,
      contributingModalities: mergedModalities,
      category: category,
      confidence: updatedConfidence,
      acousticReflectivity: math.max(
        existing.acousticReflectivity,
        acousticReflectivity,
      ),
      rfAttenuationDb: math.max(existing.rfAttenuationDb, rfAttenuationDb),
    );
    _voxels[key] = updated;
    return updated;
  }

  String _voxelKeyFor(Vector3 p) {
    final ix = (p.x / voxelSizeMeters).round();
    final iy = (p.y / voxelSizeMeters).round();
    final iz = (p.z / voxelSizeMeters).round();
    return '$ix:$iy:$iz';
  }
}
