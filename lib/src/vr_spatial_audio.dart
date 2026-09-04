import 'dart:math';
import 'package:vector_math/vector_math.dart' as vm;

/// Evaluates real-time 3D spatial positional audio metrics (Gain & Stereo Panning).
///
/// Implements standard inverse-square law attenuation with rolloff and head-relative
/// horizontal azimuth panning (-1.0 = 100% Left Ear, +1.0 = 100% Right Ear).
class VrSpatialAudioEvaluator {
  /// Evaluates spatial volume gain and stereo panning for an audio source in 3D space.
  ///
  /// - [source]: 3D world position of the sound emitter.
  /// - [listener]: 3D world position of the user's head / camera rig.
  /// - [listenerYaw]: horizontal head rotation in radians.
  /// - [minDistance]: distance within which sound is at full volume (gain = 1.0).
  /// - [maxDistance]: distance beyond which sound is completely inaudible (gain = 0.0).
  /// - [rolloff]: attenuation factor (1.0 = natural real-world inverse distance).
  ///
  /// Returns a record `(double gain, double pan)`:
  /// - `gain`: amplitude multiplier in range `[0.0, 1.0]`.
  /// - `pan`: stereo balance in range `[-1.0, 1.0]`.
  static (double gain, double pan) evaluate({
    required vm.Vector3 source,
    required vm.Vector3 listener,
    required double listenerYaw,
    double minDistance = 1.0,
    double maxDistance = 25.0,
    double rolloff = 1.0,
  }) {
    // 1. Distance Calculation & Attenuation Gain
    final diff = source - listener;
    final distance = diff.length;

    if (distance >= maxDistance) {
      return (0.0, 0.0);
    }

    final clampedDist = max(distance, minDistance);
    final distanceGain = minDistance / (minDistance + rolloff * (clampedDist - minDistance));
    final windowFalloff = (1.0 - (distance / maxDistance)).clamp(0.0, 1.0);
    final gain = (distanceGain * windowFalloff).clamp(0.0, 1.0);

    // 2. Relative Azimuth Angle & Stereo Panning
    // Rotate relative offset by negative head yaw to express in listener's local frame
    final cosYaw = cos(-listenerYaw);
    final sinYaw = sin(-listenerYaw);

    // Horizontal plane (X = right, Z = forward/back where -Z is front)
    final localX = diff.x * cosYaw - diff.z * sinYaw;
    final localZ = diff.x * sinYaw + diff.z * cosYaw;

    final horizontalDist = sqrt(localX * localX + localZ * localZ);
    if (horizontalDist < 1e-4) {
      return (gain, 0.0);
    }

    // Azimuth angle: 0 rad = straight ahead, +pi/2 = right, -pi/2 = left
    final azimuth = atan2(localX, -localZ);
    final pan = sin(azimuth).clamp(-1.0, 1.0);

    return (gain, pan);
  }
}
