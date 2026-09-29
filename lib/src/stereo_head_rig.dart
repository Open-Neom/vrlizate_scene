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

  final vm.Vector3 _physicalTranslation = vm.Vector3.zero();
  Object? _spatialOwner;
  void Function()? _spatialRecenter;
  bool _preserveSpatialRoll = false;

  /// Measured displacement relative to the current tracking origin. Never
  /// derived from joystick input or an accelerometer double integration.
  vm.Vector3 get physicalTranslation => _physicalTranslation.clone();

  /// Virtual locomotion anchor, separate from measured physical displacement.
  /// eyeCenter remains mutable for existing vehicle/joystick integrations.
  vm.Vector3 get locomotionOrigin => cameraRig.position - _physicalTranslation;

  /// Internal ownership boundary used by the optional spatial controller.
  /// A replaced controller cannot clear a newer controller's recenter hook.
  void attachSpatialOwner(Object owner, void Function() recenter) {
    _spatialOwner = owner;
    _spatialRecenter = recenter;
  }

  void detachSpatialOwner(Object owner) {
    if (!identical(owner, _spatialOwner)) return;
    _spatialOwner = null;
    _spatialRecenter = null;
    // Bake the last measured displacement into the virtual anchor. Releasing
    // tracking must not snap the camera back to its pre-tracking position.
    _physicalTranslation.setZero();
  }

  /// Apply one measured pose. [rotation] uses the existing inverse vector_math
  /// rig convention; the spatial bridge converts conventional ARCore XYZW.
  /// Repeated absolute samples do not repeatedly add their displacement.
  void applySpatialPose({
    required vm.Vector3 translationOffset,
    required vm.Quaternion rotation,
  }) {
    cameraRig.position.add(translationOffset - _physicalTranslation);
    _physicalTranslation.setFrom(translationOffset);
    cameraRig.rotation = rotation;
    _preserveSpatialRoll = true;
  }

  /// Vehicle/platform heading independent of the viewer's local head pose.
  /// Recentring the head must not rotate the car or reset its world heading.
  double bodyYaw = 0;

  /// Manual vertical look offset in radians, composed with the tracked head
  /// pitch (positive looks down, like [CameraRig.pitch]).
  ///
  /// The head tracker writes an *absolute* gravity-referenced pitch into the
  /// camera rig on every sensor sample, so a look-stick delta written there
  /// is erased within one sample. Stick input accumulates here instead and is
  /// composed at read time; [recenter] leaves it untouched, exactly like
  /// [bodyYaw]. The composed [pitch] stays within the rig's ±83° clamp.
  double bodyPitch = 0;

  /// Composed vertical look angle: tracked head pitch plus [bodyPitch],
  /// clamped like [CameraRig.pitch]. Positive looks down.
  double get pitch => (cameraRig.pitch + bodyPitch).clamp(-1.45, 1.45);

  /// Composed horizontal heading: tracked head yaw plus [bodyYaw].
  double get yaw => cameraRig.yaw + bodyYaw;

  bool get _hasBodyOffset => bodyYaw != 0 || bodyPitch != 0;

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
  void rotate(double dTheta, double dPhi) {
    if (_spatialOwner != null) {
      // With absolute VIO, manual look belongs to virtual locomotion. The
      // tracker uses its proxy target and never enters this branch.
      bodyYaw += dTheta;
      bodyPitch = (bodyPitch + dPhi).clamp(-1.45, 1.45);
    } else {
      cameraRig.rotate(dTheta, dPhi);
    }
  }

  @override
  void reset() {
    cameraRig.reset();
    _physicalTranslation.setZero();
    _spatialRecenter?.call();
  }

  /// Sets the absolute gaze orientation (yaw, pitch) in radians.
  @override
  void setOrientation(double yaw, double pitch) =>
      cameraRig.setOrientation(yaw, pitch);

  /// Sets the vertical elevation (pitch) directly in radians.
  @override
  void setPitch(double pitch) => cameraRig.setPitch(pitch);

  /// Recenters the horizontal head heading (Yaw = 0°).
  @override
  void recenter() {
    final spatialRecenter = _spatialRecenter;
    if (spatialRecenter != null) {
      spatialRecenter();
    } else {
      cameraRig.recenter();
    }
  }

  /// World-space midpoint between the eyes, including physical translation.
  /// Assigning/mutating it changes the virtual anchor while retaining the
  /// current physical offset; the next identical pose therefore cannot drift.
  vm.Vector3 get eyeCenter => cameraRig.position;
  set eyeCenter(vm.Vector3 value) => cameraRig.position = value;

  /// World-space head orientation quaternion, including [bodyYaw] and
  /// [bodyPitch]. Legacy input keeps its level horizon; an optional spatial
  /// pose retains measured physical roll when composing virtual look.
  vm.Quaternion get orientation {
    if (!_hasBodyOffset) {
      return _preserveSpatialRoll
          ? cameraRig.headTransform.rotation.clone()
          : cameraRig.headTransform.rotation;
    }
    if (_preserveSpatialRoll) {
      // Extract the roll residual from the physical quaternion, then retain
      // it while composing virtual yaw/pitch once. The old yaw/pitch-only
      // branch remains unchanged for scenes which never opt into VIO.
      final physical = cameraRig.rotation;
      if (_spatialBodyOrientation == null ||
          _spatialHeadX != physical.x ||
          _spatialHeadY != physical.y ||
          _spatialHeadZ != physical.z ||
          _spatialHeadW != physical.w ||
          _spatialBodyYaw != bodyYaw ||
          _spatialBodyPitch != bodyPitch) {
        final headYaw = vm.Quaternion.axisAngle(
          vm.Vector3(0, 1, 0),
          cameraRig.yaw,
        );
        final headPitch = vm.Quaternion.axisAngle(
          vm.Vector3(1, 0, 0),
          cameraRig.pitch,
        );
        final base = (headPitch * headYaw)..normalize();
        final inverseBase = vm.Quaternion(-base.x, -base.y, -base.z, base.w);
        final virtualYaw = vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), yaw);
        final virtualPitch = vm.Quaternion.axisAngle(
          vm.Vector3(1, 0, 0),
          pitch,
        );
        _spatialBodyOrientation =
            (physical * inverseBase * virtualPitch * virtualYaw)..normalize();
        _spatialHeadX = physical.x;
        _spatialHeadY = physical.y;
        _spatialHeadZ = physical.z;
        _spatialHeadW = physical.w;
        _spatialBodyYaw = bodyYaw;
        _spatialBodyPitch = bodyPitch;
      }
      return _spatialBodyOrientation!.clone();
    }
    final currentYaw = yaw;
    final currentPitch = pitch;
    if (_bodyOrientation == null ||
        _bodyOrientationYaw != currentYaw ||
        _bodyOrientationPitch != currentPitch) {
      final yawQ = vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), currentYaw);
      final pitchQ = vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), currentPitch);
      _bodyOrientation = (pitchQ * yawQ)..normalize();
      _bodyOrientationYaw = currentYaw;
      _bodyOrientationPitch = currentPitch;
    }
    // Both eyes and input rays read the same pose repeatedly in one frame.
    // Return owned storage so caller mutations cannot corrupt the cached pose.
    return _bodyOrientation!.clone();
  }

  vm.Quaternion? _bodyOrientation;
  double? _bodyOrientationYaw;
  double? _bodyOrientationPitch;
  vm.Quaternion? _spatialBodyOrientation;
  double? _spatialHeadX, _spatialHeadY, _spatialHeadZ, _spatialHeadW;
  double? _spatialBodyYaw, _spatialBodyPitch;

  /// World-space gaze direction (−Z head axis, rotated).
  vm.Vector3 get forward => !_hasBodyOffset
      ? cameraRig.headTransform.forward
      : orientation.rotated(vm.Vector3(0, 0, -1));

  /// World-space local +X direction of the underlying vrlizate rig.
  ///
  /// This differs from [screenRight] because flutter_scene's view convention
  /// uses `up.cross(forward)` for its horizontal camera axis.
  vm.Vector3 get right => !_hasBodyOffset
      ? cameraRig.headTransform.right
      : orientation.rotated(vm.Vector3(1, 0, 0));

  /// World-space head-up direction.
  vm.Vector3 get up => !_hasBodyOffset
      ? cameraRig.headTransform.up
      : orientation.rotated(vm.Vector3(0, 1, 0));

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

/// A pinhole perspective with a horizontal clip-space shift for stereo.
///
/// It *is* a [PerspectiveProjection] so flutter_scene keeps its
/// perspective-only features — cascaded shadow fitting (which reads only
/// `fovRadiansY`, `near` and the camera forward), god rays, depth of field and
/// ambient occlusion — active in stereo instead of silently disabling them.
/// Screen-space effects that reconstruct positions from depth assume a
/// symmetric frustum and therefore see a uniform lateral offset of
/// `shift × tan(fovX/2) × depth`; it is the same for neighboring samples, so
/// relative effects such as AO are unaffected in practice.
final class _ShiftedPerspectiveProjection extends PerspectiveProjection {
  _ShiftedPerspectiveProjection({
    required super.fovRadiansY,
    required super.near,
    required super.far,
    required this.horizontalShift,
    required this.eyeOffsetOverConvergence,
  });

  final double horizontalShift;
  final double eyeOffsetOverConvergence;

  @override
  vm.Matrix4 getProjectionMatrix(double aspectRatio) {
    final matrix = super.getProjectionMatrix(aspectRatio);
    // flutter_scene uses a left-handed view: clip.w = view.z and
    // clip.x = P00 * view.x + P02 * view.z. At the convergence point,
    // view.x = -eyeOffset, so adding P00 * eyeOffset / distance cancels
    // baseline disparity. The independent inset remains in normalized space.
    matrix.storage[8] =
        horizontalShift + matrix.storage[0] * eyeOffsetOverConvergence;
    return matrix;
  }
}
