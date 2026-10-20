import 'package:vector_math/vector_math.dart';

import '../../utils/enums/vr_guardian_alert_level.dart';

/// Snapshot of physical obstacle proximity, automatic passthrough floor mix,
/// and anti-nausea locomotion comfort vignette evaluated by
/// `VrPhysicalGuardianService`.
class VrGuardianProximityState {
  const VrGuardianProximityState({
    required this.alertLevel,
    required this.nearestObstacleDistanceMeters,
    required this.nearestObstacleId,
    required this.obstacleDirectionWorld,
    required this.recommendedPassthroughFloorMix,
    required this.comfortVignetteIntensity,
    required this.statusMessage,
  });

  /// Current physical boundary alert state (`clear`, `approachingObstacle`,
  /// `criticalBoundaryBreach`).
  final VrGuardianAlertLevel alertLevel;

  /// Horizontal ground-plane distance in meters to the closest physical
  /// obstacle or wall (`double.infinity` when no obstacles are present).
  final double nearestObstacleDistanceMeters;

  /// Identifier of the nearest physical obstacle, or `null` when none exist.
  final String? nearestObstacleId;

  /// Unit horizontal direction vector in world space pointing from the viewer
  /// toward the nearest obstacle (`Vector3.zero()` when clear/none).
  final Vector3 obstacleDirectionWorld;

  /// Minimum passthrough mix (`0.0 .. 1.0`) automatically enforced by the
  /// Guardian so the real-world room fades into view before collision.
  final double recommendedPassthroughFloorMix;

  /// Peripheral comfort vignette intensity (`0.0 .. 0.40`) driven by linear and
  /// angular locomotion speed to prevent motion sickness.
  final double comfortVignetteIntensity;

  /// Localized human-readable safety status message.
  final String statusMessage;

  /// True when the Guardian is actively blending in real-world passthrough.
  bool get isPassthroughTriggered => recommendedPassthroughFloorMix > 0.0;

  /// True when the viewer is within the critical collision threshold.
  bool get isCritical =>
      alertLevel == VrGuardianAlertLevel.criticalBoundaryBreach;
}
