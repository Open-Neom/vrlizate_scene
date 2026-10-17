import 'dart:math' as math;

import 'package:vector_math/vector_math.dart' as vm;

/// Procedural two-point limb orientation and first-person VR foot kinematics.
///
/// Adapted from Lemo-Opuscar `styles/backrooms/demo/figures.js` (MIT License).
abstract final class VrLimbKinematics {
  static final vm.Vector3 _upAxis = vm.Vector3(0, 1, 0);

  /// Computes a `Matrix4` transform that places, rotates, and scales a unit-height
  /// capsule/cylinder (total unscaled height `1 + 2 * baseRadius`, oriented along +Y)
  /// so it spans cleanly between 3D endpoints [start] and [end].
  ///
  /// Useful for VR controller arm/forearm capsules, tether beams, and IK limbs.
  static vm.Matrix4 capsuleTransformBetween(
    vm.Vector3 start,
    vm.Vector3 end, {
    required double baseRadius,
    double? currentRadius,
  }) {
    final r = math.max(1e-4, baseRadius);
    final r2 = currentRadius ?? r;
    final delta = end - start;
    final length = delta.length;
    final mid = start + delta * 0.5;
    final dir = length > 1e-6 ? (delta / length) : vm.Vector3(0, 1, 0);
    final rot = vm.Quaternion.fromTwoVectors(_upAxis, dir);
    final radialScale = r2 / r;
    final yScale = math.max(0.01, (length + r) / (1.0 + 2.0 * r));
    return vm.Matrix4.compose(
      mid,
      rot,
      vm.Vector3(radialScale, yScale, radialScale),
    );
  }
}

/// First-person foot/shoe pose for looking down in VR locomotion.
class VrFootTransform {
  const VrFootTransform({
    required this.position,
    required this.yawRadians,
    required this.pitchRadians,
  });

  final vm.Vector3 position;
  final double yawRadians;
  final double pitchRadians;

  vm.Matrix4 toMatrix4() {
    return vm.Matrix4.translation(position)
      ..rotateY(yawRadians)
      ..rotateX(pitchRadians);
  }
}

/// Evaluates left and right foot transforms from player position, heading yaw,
/// and stride phase (adapted from `makeLegs.pose` in `figures.js`).
abstract final class VrFirstPersonFeetRig {
  /// Returns `(leftFoot, rightFoot)` transforms for a VR walker at [bodyGroundPosition].
  ///
  /// - [yawRadians]: heading angle in the XZ plane (`0` faces `-Z`).
  /// - [phaseRadians]: continuous gait phase.
  /// - [amplitude]: `0..1` stride intensity (`0` = standing still, `1` = full walk).
  /// - [stanceOffset]: extra lateral foot separation in meters.
  static (VrFootTransform left, VrFootTransform right) evaluate({
    required vm.Vector3 bodyGroundPosition,
    required double yawRadians,
    required double phaseRadians,
    double amplitude = 1.0,
    double stanceOffset = 0.0,
  }) {
    final amp = amplitude.clamp(0.0, 1.5);
    final forward = vm.Vector3(
      -math.sin(yawRadians),
      0.0,
      -math.cos(yawRadians),
    );
    final right = vm.Vector3(
      math.cos(yawRadians),
      0.0,
      -math.sin(yawRadians),
    );

    VrFootTransform footForSide(int sideIndex) {
      final sideSign = sideIndex == 0 ? -1.0 : 1.0;
      final ph = phaseRadians + sideIndex * math.pi;
      final fwdOffset = math.sin(ph) * 0.26 * amp + 0.15;
      final liftY = math.max(0.0, math.cos(ph)) * 0.06 * amp;
      final lateral = sideSign * (0.11 + stanceOffset);
      final ankle = vm.Vector3(
        bodyGroundPosition.x + forward.x * fwdOffset + right.x * lateral,
        bodyGroundPosition.y + liftY,
        bodyGroundPosition.z + forward.z * fwdOffset + right.z * lateral,
      );
      final footYaw = yawRadians + math.pi - sideSign * 0.1;
      final toePitch = math.max(0.0, math.cos(ph)) * 0.2 * amp;
      return VrFootTransform(
        position: ankle,
        yawRadians: footYaw,
        pitchRadians: toePitch,
      );
    }

    return (footForSide(0), footForSide(1));
  }
}
