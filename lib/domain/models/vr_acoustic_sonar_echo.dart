import 'dart:math' as math;

import '../../utils/constants/vr_scene_constants.dart';

/// Represents a specular or diffuse acoustic/ultrasonic echo captured by a
/// conventional smartphone's speaker and dual microphones.
class VrAcousticSonarEcho {
  const VrAcousticSonarEcho({
    required this.roundTripSeconds,
    this.carrierFrequencyHz = VrSceneConstants.defaultUltrasonicSonarCarrierHz,
    this.dualMicPhaseDelaySeconds = 0.0,
    this.micBaselineMeters =
        VrSceneConstants.defaultSmartphoneMicBaselineMeters,
    this.reflectionAmplitude = 0.75,
    this.isBistatic = false,
    this.bistaticDirectDistanceMeters = 0.0,
  });

  /// Measured round-trip time of flight ($\tau$) in seconds for monostatic
  /// echoes, or total propagation time from emitter phone $\to$ reflector
  /// $\to$ receiver phone for bistatic echoes.
  final double roundTripSeconds;

  /// Center acoustic frequency in Hz (e.g., $20\text{ kHz}$ ultrasonic FMCW
  /// chirp or $6\text{–}12\text{ kHz}$ broadband room impulse).
  final double carrierFrequencyHz;

  /// Time Difference of Arrival ($\Delta \tau_{\text{mic}}$) between the
  /// smartphone's bottom primary microphone and top earpiece microphone.
  final double dualMicPhaseDelaySeconds;

  /// Physical separation between the two microphones on the smartphone
  /// (typically $14.5\text{ cm}$).
  final double micBaselineMeters;

  /// Normalized peak amplitude (`0.0 .. 1.0`), indicating surface hardness
  /// (e.g. $> 0.75$ for glass, concrete, or wood; $< 0.45$ for curtains/sofa).
  final double reflectionAmplitude;

  /// Whether the acoustic pulse was emitted by one smartphone (Visor) and
  /// received by the second smartphone (Joystick) after reflecting off a
  /// surface.
  final bool isBistatic;

  /// Direct line-of-sight distance $d_{VJ}$ between Visor and Joystick when
  /// [isBistatic] is true.
  final double bistaticDirectDistanceMeters;

  /// Radial distance in meters from the sensing midpoint to the reflecting
  /// surface ($r = \frac{c \cdot \tau}{2}$), clamped to valid room range.
  double get radialDistanceMeters {
    final raw =
        (VrSceneConstants.speedOfSoundMetersPerSec * roundTripSeconds) * 0.5;
    if (isBistatic && bistaticDirectDistanceMeters > 0.0) {
      final halfBaseline = bistaticDirectDistanceMeters * 0.5;
      if (raw > halfBaseline) {
        return math
            .sqrt(raw * raw - halfBaseline * halfBaseline)
            .clamp(
              VrSceneConstants.minSonarEchoDistanceMeters,
              VrSceneConstants.maxSonarEchoDistanceMeters,
            );
      }
    }
    return raw.clamp(
      VrSceneConstants.minSonarEchoDistanceMeters,
      VrSceneConstants.maxSonarEchoDistanceMeters,
    );
  }

  /// Horizontal azimuth angle in radians ($\theta \in [-\frac{\pi}{2},
  /// \frac{\pi}{2}]$) derived from the dual-microphone TDOA
  /// $\theta = \arcsin\left(\frac{c \cdot \Delta \tau_{\text{mic}}}{b_{\text{mic}}}\right)$.
  double get estimatedAzimuthRadians {
    if (micBaselineMeters <= 0.0) return 0.0;
    final pathDiff =
        VrSceneConstants.speedOfSoundMetersPerSec * dualMicPhaseDelaySeconds;
    final sinTheta = (pathDiff / micBaselineMeters).clamp(-1.0, 1.0);
    return math.asin(sinTheta);
  }
}
