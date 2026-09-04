import 'dart:math';
import 'dart:ui' show Rect;

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;
import 'package:vrlizate/vrlizate.dart' show CameraRig, RotationTarget;

/// Which eye a stereo view renders.
enum StereoEye { left, right }

/// Head-tracked stereo rig bridging the vrlizate input stack with
/// flutter_scene rendering.
///
/// Wraps a vrlizate [CameraRig] (itself the `RotationTarget` consumed by
/// `HeadTracker`) and converts its orientation into per-eye flutter_scene
/// [PerspectiveCamera]s, plus a center [gazeRay] for gaze interaction.
///
/// Both packages share `vector_math` types, so poses flow through without
/// conversion.
class StereoHeadRig implements RotationTarget {
  StereoHeadRig({
    CameraRig? cameraRig,
    vm.Vector3? eyeCenter,
    double ipd = 0.064,
    this.convergenceDistance = 1.8,
  }) : cameraRig = cameraRig ?? CameraRig(ipd: ipd) {
    final center = eyeCenter;
    if (center != null) this.cameraRig.position = center;
  }

  /// The underlying vrlizate camera rig (position, rotation, IPD, FOV).
  final CameraRig cameraRig;

  /// Distance in meters at which the left and right optical stereo axes converge.
  ///
  /// Setting a finite distance (e.g. 1.5m to 2.0m) eliminates diplopia (double vision)
  /// for interactive UI elements and content placed at comfortable reaching distance.
  /// If set to null or <= 0, cameras remain parallel (infinity focus).
  double? convergenceDistance;

  /// Interpupillary distance in meters.
  double get ipd => cameraRig.ipd;
  set ipd(double value) => cameraRig.ipd = value;

  @override
  void rotate(double dTheta, double dPhi) => cameraRig.rotate(dTheta, dPhi);

  @override
  void reset() => cameraRig.reset();

  /// Recenters the horizontal head heading (Yaw = 0°).
  void recenter() => cameraRig.recenter();

  /// World-space midpoint between the eyes.
  vm.Vector3 get eyeCenter => cameraRig.position;
  set eyeCenter(vm.Vector3 value) => cameraRig.position = value;

  /// World-space head orientation quaternion.
  vm.Quaternion get orientation => cameraRig.headTransform.rotation;

  /// World-space gaze direction (−Z head axis, rotated).
  vm.Vector3 get forward => cameraRig.headTransform.forward;

  /// World-space head-right direction.
  vm.Vector3 get right => cameraRig.headTransform.right;

  /// World-space head-up direction.
  vm.Vector3 get up => cameraRig.headTransform.up;

  /// World-space position of [eye].
  vm.Vector3 eyePosition(StereoEye eye) =>
      eyeCenter + right * ((eye == StereoEye.left ? -1.0 : 1.0) * ipd / 2);

  /// Point in world space where the left and right gaze axes converge.
  /// If [convergenceDistance] is finite and positive, it is [eyeCenter] + [forward] * [convergenceDistance].
  vm.Vector3? get convergencePoint =>
      (convergenceDistance != null && convergenceDistance! > 0)
          ? eyeCenter + forward * convergenceDistance!
          : null;

  /// The toe-in convergence angle in radians for each eye toward the convergence point.
  /// Returns 0.0 if convergence is disabled.
  double get convergenceAngleRadians {
    final dist = convergenceDistance;
    if (dist == null || dist <= 0) return 0.0;
    return atan2(ipd / 2, dist);
  }

  /// Computes the horizontal angular parallax in radians for a point at depth [distanceMeters].
  ///
  /// Positive value indicates uncrossed parallax (farther than convergence plane).
  /// Negative value indicates crossed parallax (closer than convergence plane).
  /// Zero indicates zero parallax (exactly on the convergence plane).
  double parallaxAtDistance(double distanceMeters) {
    if (distanceMeters <= 0) return 0.0;
    final dist = convergenceDistance;
    if (dist == null || dist <= 0) {
      return atan2(ipd, distanceMeters);
    }
    return atan2(ipd, dist) - atan2(ipd, distanceMeters);
  }

  /// Gaze ray from the eye midpoint along [forward], for center-screen
  /// gaze raycasting against a flutter_scene `Scene`.
  vm.Ray get gazeRay => vm.Ray()
    ..origin.setFrom(eyeCenter)
    ..direction.setFrom(forward);

  /// Gaze ray for the specified [eye] converging toward [convergencePoint]
  /// (or parallel along [forward] if convergence is disabled).
  vm.Ray eyeGazeRay(StereoEye eye) {
    final pos = eyePosition(eye);
    final target = convergencePoint ?? (pos + forward);
    final dir = (target - pos).normalized();
    return vm.Ray()
      ..origin.setFrom(pos)
      ..direction.setFrom(dir);
  }

  /// Convenience getter for the left eye gaze ray.
  vm.Ray get leftGazeRay => eyeGazeRay(StereoEye.left);

  /// Convenience getter for the right eye gaze ray.
  vm.Ray get rightGazeRay => eyeGazeRay(StereoEye.right);

  /// Builds the flutter_scene [PerspectiveCamera] for [eye].
  ///
  /// If [convergenceDistance] is set, the camera looks at [convergencePoint],
  /// creating a stereoscopic convergence plane at that depth. Otherwise,
  /// it looks parallel along [forward].
  PerspectiveCamera eyeCamera(StereoEye eye, {double? fovRadiansY}) {
    final pos = eyePosition(eye);
    final target = convergencePoint ?? (pos + forward);
    return PerspectiveCamera(
      position: pos,
      target: target,
      up: up,
      fovRadiansY: fovRadiansY ?? cameraRig.fovY,
    );
  }

  /// The pair of half-screen [RenderView]s (left | right) for
  /// `SceneView.viewsBuilder`.
  List<RenderView> buildStereoViews({double? fovRadiansY}) {
    return [
      RenderView(
        camera: eyeCamera(StereoEye.left, fovRadiansY: fovRadiansY),
        viewport: const Rect.fromLTWH(0, 0, 0.5, 1),
      ),
      RenderView(
        camera: eyeCamera(StereoEye.right, fovRadiansY: fovRadiansY),
        viewport: const Rect.fromLTWH(0.5, 0, 0.5, 1),
      ),
    ];
  }

  /// Default vertical FOV for Cardboard-class viewers (60°).
  static double get defaultFovY => 60 * pi / 180;
}
