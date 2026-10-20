import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

import '../../utils/constants/vr_scene_constants.dart';

/// Represents a 3D expanding echolocation sonar wave (`0% -> 100% -> 0%`)
/// triggered by a dual-thumb center double-tap on the Smartphone Joystick.
///
/// As the spherical wave expands from [origin] up to [maxRadiusMeters],
/// 3D AI wireframe contour segments inside the wavefront band are illuminated.
class VrSpatialSonarPulse {
  VrSpatialSonarPulse({
    required Vector3 origin,
    this.durationSeconds = VrSceneConstants.defaultSonarPulseDurationSeconds,
    this.maxRadiusMeters = VrSceneConstants.defaultSonarPulseMaxRadiusMeters,
    this.wavefrontBandWidthMeters =
        VrSceneConstants.defaultSonarPulseBandWidthMeters,
  }) : origin = origin.clone();

  final Vector3 origin;
  final double durationSeconds;
  final double maxRadiusMeters;
  final double wavefrontBandWidthMeters;

  double _elapsedSeconds = 0.0;

  /// Normalized progress (`0.0 .. 1.0`) of the sonar wave.
  double get progress =>
      (_elapsedSeconds /
              math.max(
                VrSceneConstants.minSonarPulseDurationSeconds,
                durationSeconds,
              ))
          .clamp(0.0, 1.0);

  /// Whether the sonar wave is still expanding.
  bool get isActive => _elapsedSeconds < durationSeconds;

  /// Current wavefront radius in meters (`0.0 .. maxRadiusMeters`).
  double get currentRadiusMeters => progress * maxRadiusMeters;

  /// Global envelope (`0.0 -> 1.0 -> 0.0`) following $\sin(\pi \cdot p)$.
  double get envelopeOpacity =>
      isActive ? math.sin(math.pi * progress).clamp(0.0, 1.0) : 0.0;

  /// Advances the sonar wave by [dtSeconds].
  void advance(double dtSeconds) {
    if (dtSeconds > 0.0) {
      _elapsedSeconds += dtSeconds;
    }
  }

  /// Computes the local illumination intensity (`0.0 .. 1.0`) at a 3D point
  /// [worldPoint] as the sonar wavefront passes over it.
  double intensityAtPoint(Vector3 worldPoint) {
    if (!isActive) return 0.0;
    final dist = (worldPoint - origin).length;
    final radialDelta = (dist - currentRadiusMeters).abs();
    if (radialDelta > wavefrontBandWidthMeters) return 0.0;
    final bandFactor =
        1.0 -
        (radialDelta /
            math.max(
              VrSceneConstants.minSonarPulseBandWidthMeters,
              wavefrontBandWidthMeters,
            ));
    return (bandFactor * envelopeOpacity).clamp(0.0, 1.0);
  }
}
