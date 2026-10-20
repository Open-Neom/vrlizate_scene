import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

import '../../utils/constants/vr_scene_constants.dart';
import '../../utils/constants/vr_scene_translation_constants.dart';
import '../../utils/enums/vr_guardian_alert_level.dart';
import '../../utils/enums/vr_spatial_object_category.dart';
import '../models/vr_detected_spatial_object.dart';
import '../models/vr_guardian_proximity_state.dart';
import 'vr_multi_camera_space_mapper.dart';

/// Evaluates real-time physical obstacle proximity and locomotion velocity to:
/// 1. **Auto-Trigger Passthrough Before Collision:** When the user approaches a
///    physical wall, table, chair, or obstacle (`< 0.95 m`), smoothly ramps
///    `recommendedPassthroughFloorMix` from `0.0` up to `1.0` at the critical
///    boundary (`<= 0.42 m`).
/// 2. **Comfort Motion Shield:** Computes a peripheral comfort vignette
///    (`0.0 .. 0.40`) during fast linear or angular locomotion to prevent
///    vestibular motion sickness.
class VrPhysicalGuardianService {
  const VrPhysicalGuardianService({
    this.warningDistanceMeters = VrSceneConstants.guardianWarningDistanceMeters,
    this.criticalDistanceMeters =
        VrSceneConstants.guardianCriticalDistanceMeters,
    this.maxComfortVignetteIntensity =
        VrSceneConstants.guardianMaxComfortVignetteIntensity,
    this.linearSpeedVignetteThresholdMetersPerSec =
        VrSceneConstants.guardianLinearSpeedVignetteThreshold,
    this.linearSpeedMaxVignetteMetersPerSec =
        VrSceneConstants.guardianLinearSpeedMaxVignette,
    this.angularSpeedVignetteThresholdRadPerSec =
        VrSceneConstants.guardianAngularSpeedVignetteThreshold,
    this.angularSpeedMaxVignetteRadPerSec =
        VrSceneConstants.guardianAngularSpeedMaxVignette,
  }) : assert(warningDistanceMeters > criticalDistanceMeters),
       assert(criticalDistanceMeters > 0.0);

  final double warningDistanceMeters;
  final double criticalDistanceMeters;
  final double maxComfortVignetteIntensity;
  final double linearSpeedVignetteThresholdMetersPerSec;
  final double linearSpeedMaxVignetteMetersPerSec;
  final double angularSpeedVignetteThresholdRadPerSec;
  final double angularSpeedMaxVignetteRadPerSec;

  /// Evaluates [viewerPosition], [locomotionSpeedMetersPerSec], and
  /// [angularSpeedRadiansPerSec] against [detectedObjects].
  ///
  /// Ignores user body/controller categories (`handController`, `floorBoundary`,
  /// `doorway`) and checks physical collision hazards (`wall`, `table`, `chair`,
  /// `obstacle`, `person`, `pet`).
  VrGuardianProximityState evaluate({
    required Vector3 viewerPosition,
    required List<VrDetectedSpatialObject> detectedObjects,
    double locomotionSpeedMetersPerSec = 0.0,
    double angularSpeedRadiansPerSec = 0.0,
  }) {
    var nearestDistance = double.infinity;
    VrDetectedSpatialObject? nearestObject;

    for (final obj in detectedObjects) {
      if (!_isPhysicalCollisionHazard(obj.category)) {
        continue;
      }
      final dist = obj.horizontalDistanceToViewerMeters(viewerPosition);
      if (dist < nearestDistance) {
        nearestDistance = dist;
        nearestObject = obj;
      }
    }

    var obstacleDirection = Vector3.zero();
    if (nearestObject != null) {
      final deltaHoriz = Vector3(
        nearestObject.centerWorld.x - viewerPosition.x,
        0.0,
        nearestObject.centerWorld.z - viewerPosition.z,
      );
      if (deltaHoriz.length2 > 1e-6) {
        obstacleDirection = deltaHoriz.normalized();
      }
    }

    final VrGuardianAlertLevel alertLevel;
    final double passthroughFloorMix;
    final String statusMessage;

    if (nearestDistance <= criticalDistanceMeters) {
      alertLevel = VrGuardianAlertLevel.criticalBoundaryBreach;
      passthroughFloorMix = 1.0;
      statusMessage = VrSceneTranslationConstants.guardianStatusCriticalBreach;
    } else if (nearestDistance < warningDistanceMeters) {
      alertLevel = VrGuardianAlertLevel.approachingObstacle;
      final span = math.max(
        1e-4,
        warningDistanceMeters - criticalDistanceMeters,
      );
      passthroughFloorMix =
          ((warningDistanceMeters - nearestDistance) / span).clamp(0.0, 1.0);
      statusMessage = VrSceneTranslationConstants.guardianStatusApproaching;
    } else {
      alertLevel = VrGuardianAlertLevel.clear;
      passthroughFloorMix = 0.0;
      statusMessage = VrSceneTranslationConstants.guardianStatusClear;
    }

    final comfortVignette = _computeComfortVignette(
      linearSpeedMetersPerSec: locomotionSpeedMetersPerSec,
      angularSpeedRadiansPerSec: angularSpeedRadiansPerSec,
    );

    return VrGuardianProximityState(
      alertLevel: alertLevel,
      nearestObstacleDistanceMeters: nearestDistance,
      nearestObstacleId: nearestObject?.id,
      obstacleDirectionWorld: obstacleDirection,
      recommendedPassthroughFloorMix: passthroughFloorMix,
      comfortVignetteIntensity: comfortVignette,
      statusMessage: statusMessage,
    );
  }

  /// Evaluates the Guardian state directly against [spaceMapper] and optionally
  /// enforces the minimum `recommendedPassthroughFloorMix` on [spaceMapper].
  VrGuardianProximityState evaluateSpaceMapper({
    required Vector3 viewerPosition,
    required VrMultiCameraSpaceMapper spaceMapper,
    double locomotionSpeedMetersPerSec = 0.0,
    double angularSpeedRadiansPerSec = 0.0,
    bool autoApplyPassthroughFloor = true,
  }) {
    final state = evaluate(
      viewerPosition: viewerPosition,
      detectedObjects: spaceMapper.objects,
      locomotionSpeedMetersPerSec: locomotionSpeedMetersPerSec,
      angularSpeedRadiansPerSec: angularSpeedRadiansPerSec,
    );
    if (autoApplyPassthroughFloor && state.recommendedPassthroughFloorMix > 0) {
      spaceMapper.applyControllerPassthroughMix(
        math.max(
          spaceMapper.controllerPassthroughMix,
          state.recommendedPassthroughFloorMix,
        ),
      );
    }
    return state;
  }

  double _computeComfortVignette({
    required double linearSpeedMetersPerSec,
    required double angularSpeedRadiansPerSec,
  }) {
    final absLinear = linearSpeedMetersPerSec.abs();
    final absAngular = angularSpeedRadiansPerSec.abs();

    var linearFactor = 0.0;
    if (absLinear > linearSpeedVignetteThresholdMetersPerSec) {
      final span = math.max(
        1e-4,
        linearSpeedMaxVignetteMetersPerSec -
            linearSpeedVignetteThresholdMetersPerSec,
      );
      linearFactor =
          ((absLinear - linearSpeedVignetteThresholdMetersPerSec) / span)
              .clamp(0.0, 1.0);
    }

    var angularFactor = 0.0;
    if (absAngular > angularSpeedVignetteThresholdRadPerSec) {
      final span = math.max(
        1e-4,
        angularSpeedMaxVignetteRadPerSec -
            angularSpeedVignetteThresholdRadPerSec,
      );
      angularFactor =
          ((absAngular - angularSpeedVignetteThresholdRadPerSec) / span)
              .clamp(0.0, 1.0);
    }

    final combined = math.max(linearFactor, angularFactor);
    return (combined * maxComfortVignetteIntensity).clamp(
      0.0,
      maxComfortVignetteIntensity,
    );
  }

  static bool _isPhysicalCollisionHazard(VrSpatialObjectCategory category) {
    return switch (category) {
      VrSpatialObjectCategory.wall ||
      VrSpatialObjectCategory.table ||
      VrSpatialObjectCategory.chair ||
      VrSpatialObjectCategory.obstacle ||
      VrSpatialObjectCategory.person ||
      VrSpatialObjectCategory.pet => true,
      VrSpatialObjectCategory.floorBoundary ||
      VrSpatialObjectCategory.doorway ||
      VrSpatialObjectCategory.handController => false,
    };
  }
}
