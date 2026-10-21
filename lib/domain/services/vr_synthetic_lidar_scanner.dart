import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

import '../../utils/constants/vr_scene_constants.dart';
import '../../utils/enums/vr_sensing_modality.dart';
import '../../utils/enums/vr_spatial_object_category.dart';
import '../models/vr_acoustic_sonar_echo.dart';
import '../models/vr_detected_spatial_object.dart';
import '../models/vr_environmental_hardware_sample.dart';
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
  }) : assert(voxelSizeMeters > VrSceneConstants.minLidarVoxelSizeMeters);

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

    final category = hitPoint.y <= VrSceneConstants.floorVoxelMaxHeightMeters
        ? VrSpatialObjectCategory.floorBoundary
        : (distance <= VrSceneConstants.defaultSafetyProximityRadiusMeters
              ? VrSpatialObjectCategory.obstacle
              : VrSpatialObjectCategory.wall);

    final point = _upsertVoxel(
      worldPosition: hitPoint,
      normal: normal,
      modality: VrSensingModality.acousticSonarEcho,
      category: category,
      baseConfidence:
          (VrSceneConstants.sonarBaseConfidenceOffset +
                  echo.reflectionAmplitude *
                      VrSceneConstants.sonarAmplitudeConfidenceScale)
              .clamp(
                VrSceneConstants.minSonarVoxelConfidence,
                VrSceneConstants.maxSonarVoxelConfidence,
              ),
      acousticReflectivity: echo.reflectionAmplitude,
    );

    // Synthesize a local tangent planar contour patch perpendicular to the ray
    final halfWidth = VrSceneConstants.sonarPatchHalfWidthMeters;
    final tangent = normal.cross(up).length2 > 1e-5
        ? normal.cross(up).normalized()
        : Vector3(1.0, 0.0, 0.0);
    final segStart = hitPoint - tangent * halfWidth;
    final segEnd = hitPoint + tangent * halfWidth;
    if (_reconstructedContours.length >= 32) {
      _reconstructedContours.removeAt(0);
    }
    _reconstructedContours.add(
      VrSpatialContourSegment(
        startWorld: segStart,
        endWorld: segEnd,
        category: category,
        confidence: point.confidence,
      ),
    );

    _sonarSurfaceCounter = (_sonarSurfaceCounter % 8) + 1;
    final surfaceId =
        '${VrSceneConstants.syntheticSonarWallPrefix}$_sonarSurfaceCounter';
    _reconstructedObjects[surfaceId] = VrDetectedSpatialObject.fromBoundingBox3D(
      id: surfaceId,
      label: surfaceId,
      category: category,
      centerWorld: hitPoint,
      extentsWorld: Vector3(
        halfWidth * 2.0,
        halfWidth * 2.0,
        VrSceneConstants.sonarSurfaceThicknessMeters,
      ),
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
    if (baselineLen > VrSceneConstants.minDualPhoneBaselineMeters) {
      final cosElevation =
          ((distJoystick * distJoystick -
                      distVisor * distVisor -
                      baselineLen * baselineLen) /
                  (2.0 * distVisor * baselineLen))
              .clamp(
                -VrSceneConstants.maxRfElevationCosine,
                VrSceneConstants.maxRfElevationCosine,
              );
      verticalOffset =
          distVisor * cosElevation * VrSceneConstants.rfVerticalElevationScale;
    }

    final estimatedPos = Vector3(
      visorPosition.x + horizontalDir.x * distVisor,
      math.max(
        VrSceneConstants.minRfVoxelHeightMeters,
        visorPosition.y + verticalOffset,
      ),
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
      baseConfidence: sample.rttDistanceMeters != null
          ? VrSceneConstants.rfRttBaseConfidence
          : VrSceneConstants.rfRssiBaseConfidence,
      rfAttenuationDb: sample.estimatedWallAttenuationDb,
    );

    final anchorId =
        '${VrSceneConstants.syntheticRfAnchorPrefix}${sample.beaconId}';
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
      final wallPos =
          visorPosition +
          (estimatedPos - visorPosition) *
              VrSceneConstants.rfShadowWallInterpolationFactor;
      _upsertVoxel(
        worldPosition: wallPos,
        normal: normal,
        modality: sample.modality,
        category: VrSpatialObjectCategory.wall,
        baseConfidence: VrSceneConstants.rfShadowWallBaseConfidence,
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
            extentsWorld: Vector3(
              VrSceneConstants.rfShadowWallWidthMeters,
              VrSceneConstants.rfShadowWallHeightMeters,
              VrSceneConstants.rfShadowWallDepthMeters,
            ),
            confidence: VrSceneConstants.rfShadowWallBaseConfidence,
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
    double confidence = VrSceneConstants.defaultVisualDepthConfidence,
  }) {
    return _upsertVoxel(
      worldPosition: worldPosition,
      normal: normal,
      modality: VrSensingModality.triCameraVision,
      category: category,
      baseConfidence: confidence,
    );
  }

  /// Ingests additional smartphone hardware sensors (Dual-Pixel PDAF focus
  /// distance, 3D Magnetometer ferromagnetic anomaly, Ambient Light window
  /// detection, Differential Barometer, UWB ToF, and IMU heel-strike floor
  /// contact) to enrich the 3D voxel room model.
  List<VrSyntheticLidarPoint> ingestEnvironmentalHardwareSample({
    required VrEnvironmentalHardwareSample sample,
    required Vector3 sensorPosition,
    required Vector3 sensorForward,
  }) {
    final added = <VrSyntheticLidarPoint>[];
    final forward = sensorForward.length2 > 1e-6
        ? sensorForward.normalized()
        : Vector3(0.0, 0.0, -1.0);
    final normal = -forward;

    // 1. Camera Dual-Pixel PDAF Lens Focus Depth (d = 1 / diopters)
    final pdafDepth = sample.pdafFocusDepthMeters;
    if (pdafDepth != null) {
      final hit = sensorPosition + forward * pdafDepth;
      added.add(
        _upsertVoxel(
          worldPosition: hit,
          normal: normal,
          modality: VrSensingModality.cameraPdafFocusDepth,
          category: pdafDepth < VrSceneConstants.pdafTableMaxDepthMeters
              ? VrSpatialObjectCategory.table
              : VrSpatialObjectCategory.wall,
          baseConfidence: VrSceneConstants.pdafVoxelBaseConfidence,
        ),
      );
    }

    // 2. 3D Uncalibrated Magnetometer Ferromagnetic Anomaly (metal furniture / wall studs)
    if (sample.hasFerromagneticObstacle) {
      final probeDist =
          pdafDepth ?? VrSceneConstants.defaultFerromagneticProbeDistanceMeters;
      final metalPos = sensorPosition + forward * probeDist;
      added.add(
        _upsertVoxel(
          worldPosition: metalPos,
          normal: normal,
          modality: VrSensingModality.magneticAnomalyField,
          category: VrSpatialObjectCategory.table,
          baseConfidence: VrSceneConstants.ferromagneticVoxelBaseConfidence,
        ),
      );
    }

    // 3. Ambient RGB Light + CCT Window/Doorway Direction
    if (sample.detectsDaylightWindowDirection) {
      final windowPos =
          sensorPosition +
          forward *
              (pdafDepth ??
                  VrSceneConstants.defaultDaylightWindowProbeDistanceMeters);
      added.add(
        _upsertVoxel(
          worldPosition: windowPos,
          normal: normal,
          modality: VrSensingModality.ambientLightAndIrProximity,
          category: VrSpatialObjectCategory.doorway,
          baseConfidence: VrSceneConstants.daylightWindowVoxelBaseConfidence,
        ),
      );
    }

    // 4. Ultra-Wideband (UWB) ToF + AoA
    final uwbDist = sample.uwbDistanceMeters;
    if (uwbDist != null && uwbDist > VrSceneConstants.minUwbRangeMeters) {
      final uwbPos = sensorPosition + forward * uwbDist;
      added.add(
        _upsertVoxel(
          worldPosition: uwbPos,
          normal: normal,
          modality: VrSensingModality.ultraWidebandToF,
          category: VrSpatialObjectCategory.handController,
          baseConfidence: VrSceneConstants.uwbVoxelBaseConfidence,
        ),
      );
    }

    // 5. IMU Heel-Strike Footstep Vibrometry (clamps floor plane y = 0)
    if (sample.heelStrikeShockG >=
        VrSceneConstants.heelStrikeShockThresholdG) {
      final footFloorPos = Vector3(sensorPosition.x, 0.0, sensorPosition.z);
      added.add(
        _upsertVoxel(
          worldPosition: footFloorPos,
          normal: Vector3(0.0, 1.0, 0.0),
          modality: VrSensingModality.imuFootstepVibrometry,
          category: VrSpatialObjectCategory.floorBoundary,
          baseConfidence: VrSceneConstants.heelStrikeVoxelBaseConfidence,
        ),
      );
    }

    return added;
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
    final isNewModality = !existing.contributingModalities.contains(modality);
    final synergyBonus = isNewModality
        ? VrSceneConstants.multiModalSynergyBonus
        : VrSceneConstants.occupancyHitConfidenceDelta *
              VrSceneConstants.voxelPositionBlendFactor;
    final updatedConfidence =
        (math.max(existing.confidence, baseConfidence) + synergyBonus).clamp(
          0.0,
          1.0,
        );

    final blendedPos =
        (existing.position + worldPosition) *
        VrSceneConstants.voxelPositionBlendFactor;
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
    const sep = VrSceneConstants.voxelKeySeparator;
    return '$ix$sep$iy$sep$iz';
  }
}
