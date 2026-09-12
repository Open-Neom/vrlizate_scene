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
    double stereoImageInset = 0.10,
  }) : _stereoImageInset = _validateStereoImageInset(stereoImageInset),
       cameraRig = cameraRig ?? CameraRig(ipd: ipd) {
    final center = eyeCenter;
    if (center != null) this.cameraRig.position = center;
  }

  /// The underlying vrlizate camera rig (position, rotation, IPD, FOV).
  final CameraRig cameraRig;

  /// Distance in meters of the zero-parallax plane, before image-center inset.
  ///
  /// Both cameras remain parallel. An asymmetric projection aligns content at
  /// this depth without the vertical disparity introduced by toe-in cameras.
  /// Null, non-finite, or non-positive values disable the convergence shift.
  /// Actual viewing comfort also depends on the physical headset calibration.
  double? convergenceDistance;

  /// Horizontal optical correction that moves both eye images inward.
  ///
  /// This is independent from anatomical IPD. `0.10` moves each image center
  /// inward by 2.5% of the full display width, which helps long phones whose
  /// quarter-screen centers sit wider than the headset lenses. Valid range is
  /// 0 (no correction) through 0.35.
  double get stereoImageInset => _stereoImageInset;
  double _stereoImageInset;
  set stereoImageInset(double value) {
    _stereoImageInset = _validateStereoImageInset(value);
  }

  /// Interpupillary distance in meters.
  double get ipd => cameraRig.ipd;
  set ipd(double value) => cameraRig.ipd = value;

  @override
  void rotate(double dTheta, double dPhi) => cameraRig.rotate(dTheta, dPhi);

  @override
  void reset() => cameraRig.reset();

  /// Sets the absolute gaze orientation (yaw, pitch) in radians.
  @override
  void setOrientation(double yaw, double pitch) =>
      cameraRig.setOrientation(yaw, pitch);

  /// Sets the vertical elevation (pitch) directly in radians.
  @override
  void setPitch(double pitch) => cameraRig.setPitch(pitch);

  /// Recenters the horizontal head heading (Yaw = 0°).
  @override
  void recenter() => cameraRig.recenter();

  /// World-space midpoint between the eyes.
  vm.Vector3 get eyeCenter => cameraRig.position;
  set eyeCenter(vm.Vector3 value) => cameraRig.position = value;

  /// World-space head orientation quaternion.
  vm.Quaternion get orientation => cameraRig.headTransform.rotation;

  /// World-space gaze direction (−Z head axis, rotated).
  vm.Vector3 get forward => cameraRig.headTransform.forward;

  /// World-space local +X direction of the underlying vrlizate rig.
  ///
  /// This differs from [screenRight] because flutter_scene's view convention
  /// uses `up.cross(forward)` for its horizontal camera axis.
  vm.Vector3 get right => cameraRig.headTransform.right;

  /// World-space head-up direction.
  vm.Vector3 get up => cameraRig.headTransform.up;

  /// World direction that projects toward the right edge of an eye viewport.
  vm.Vector3 get screenRight => up.cross(forward)..normalize();

  /// Physical left/right eye position in the renderer's screen basis.
  ///
  /// Using the rig's local +X for the baseline would swap the stereo images
  /// relative to flutter_scene's view basis and invert perceived depth.
  vm.Vector3 eyePosition(StereoEye eye) =>
      eyeCenter + screenRight * _eyeOffset(eye);

  double _eyeOffset(StereoEye eye) =>
      (eye == StereoEye.left ? -1.0 : 1.0) * ipd / 2;

  double? get _finiteConvergenceDistance {
    final distance = convergenceDistance;
    return distance != null && distance.isFinite && distance > 0
        ? distance
        : null;
  }

  /// World point seen under both inset-adjusted reticles, when convergence is on.
  vm.Vector3? get convergencePoint {
    final distance = _finiteConvergenceDistance;
    return distance == null ? null : eyeCenter + forward * distance;
  }

  /// Gaze-ray angle per eye toward the convergence point, in radians.
  /// The cameras themselves remain parallel. Returns zero when disabled.
  double get convergenceAngleRadians {
    final dist = _finiteConvergenceDistance;
    if (dist == null) return 0.0;
    return atan2(ipd / 2, dist);
  }

  /// Computes the horizontal angular parallax in radians for a point at depth [distanceMeters].
  ///
  /// Positive value indicates uncrossed parallax (farther than convergence plane).
  /// Negative value indicates crossed parallax (closer than convergence plane).
  /// Zero indicates zero parallax (exactly on the convergence plane). This
  /// angular convention is the opposite sign of left-minus-right screen pixels.
  double parallaxAtDistance(double distanceMeters) {
    if (distanceMeters <= 0) return 0.0;
    final dist = _finiteConvergenceDistance;
    final convergenceAngle = dist == null ? 0.0 : atan2(ipd / 2, dist);
    return 2 * (convergenceAngle - atan2(ipd / 2, distanceMeters));
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
  /// Cameras always look parallel along [forward]. When convergence is enabled,
  /// an off-axis projection puts [convergencePoint] under the inset-adjusted
  /// reticle while preserving identical vertical projections for both eyes.
  PerspectiveCamera eyeCamera(StereoEye eye, {double? fovRadiansY}) {
    final pos = eyePosition(eye);
    final distance = _finiteConvergenceDistance;
    return _ShiftedPerspectiveCamera(
      position: pos,
      target: pos + forward,
      up: up,
      fovRadiansY: fovRadiansY ?? cameraRig.fovY,
      horizontalShift: eye == StereoEye.left
          ? _stereoImageInset
          : -_stereoImageInset,
      eyeOffsetOverConvergence: distance == null
          ? 0
          : _eyeOffset(eye) / distance,
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

  static double _validateStereoImageInset(double value) {
    if (!value.isFinite || value < 0 || value > 0.35) {
      throw ArgumentError.value(
        value,
        'stereoImageInset',
        'Must be finite and between 0 and 0.35.',
      );
    }
    return value;
  }
}

final class _ShiftedPerspectiveCamera extends PerspectiveCamera {
  _ShiftedPerspectiveCamera({
    required super.position,
    required super.target,
    required super.up,
    required super.fovRadiansY,
    required this.horizontalShift,
    required this.eyeOffsetOverConvergence,
  });

  final double horizontalShift;
  final double eyeOffsetOverConvergence;

  @override
  CameraProjection get projection => _ShiftedPerspectiveProjection(
    fovRadiansY: fovRadiansY,
    near: fovNear,
    far: fovFar,
    horizontalShift: horizontalShift,
    eyeOffsetOverConvergence: eyeOffsetOverConvergence,
  );
}

final class _ShiftedPerspectiveProjection extends CameraProjection {
  _ShiftedPerspectiveProjection({
    required this.fovRadiansY,
    required this.near,
    required this.far,
    required this.horizontalShift,
    required this.eyeOffsetOverConvergence,
  });

  final double fovRadiansY;
  final double near;
  final double far;
  final double horizontalShift;
  final double eyeOffsetOverConvergence;

  @override
  vm.Matrix4 getProjectionMatrix(double aspectRatio) {
    final matrix = PerspectiveProjection(
      fovRadiansY: fovRadiansY,
      near: near,
      far: far,
    ).getProjectionMatrix(aspectRatio);
    // flutter_scene uses a left-handed view: clip.w = view.z and
    // clip.x = P00 * view.x + P02 * view.z. At the convergence point,
    // view.x = -eyeOffset, so adding P00 * eyeOffset / distance cancels
    // baseline disparity. The independent inset remains in normalized space.
    matrix.storage[8] =
        horizontalShift + matrix.storage[0] * eyeOffsetOverConvergence;
    return matrix;
  }
}
