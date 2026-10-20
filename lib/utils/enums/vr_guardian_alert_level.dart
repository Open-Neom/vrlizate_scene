import '../constants/vr_scene_constants.dart';

/// Physical safety alert level evaluated by `VrPhysicalGuardianService` as the
/// user moves inside their real-world room.
enum VrGuardianAlertLevel {
  /// User is at a safe distance (`>= 0.95 m`) from all physical walls and
  /// furniture.
  clear(VrSceneConstants.guardianAlertClearId),

  /// User is approaching a physical obstacle (`< 0.95 m`); AI wireframe
  /// contours and gradual camera passthrough are blended in.
  approachingObstacle(VrSceneConstants.guardianAlertApproachingId),

  /// User has breached the critical safety margin (`<= 0.42 m`); full `100%`
  /// camera passthrough is enforced immediately to prevent physical collision.
  criticalBoundaryBreach(VrSceneConstants.guardianAlertCriticalBreachId);

  const VrGuardianAlertLevel(this.id);

  final String id;

  /// True when an obstacle alert is active (`approachingObstacle` or
  /// `criticalBoundaryBreach`).
  bool get isAlertActive => this != VrGuardianAlertLevel.clear;
}
