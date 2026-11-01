import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:vector_math/vector_math.dart' as vm;

/// Snapshot of predictive gaze velocity, asymmetric scissor shift, saccadic
/// peripheral compression, and BVH culling parameters for a single VR frame.
class VrPredictiveCullState {
  const VrPredictiveCullState({
    required this.screenAngularVelXRadPerSec,
    required this.screenAngularVelYRadPerSec,
    required this.angularSpeedRadPerSec,
    required this.linearSpeedMetersPerSec,
    required this.opticalCenterLeadOffset,
    required this.saccadicScissorScale,
    this.dynamicFarCullMeters,
  });

  static const VrPredictiveCullState idle = VrPredictiveCullState(
    screenAngularVelXRadPerSec: 0.0,
    screenAngularVelYRadPerSec: 0.0,
    angularSpeedRadPerSec: 0.0,
    linearSpeedMetersPerSec: 0.0,
    opticalCenterLeadOffset: ui.Offset.zero,
    saccadicScissorScale: 1.0,
  );

  /// Horizontal angular velocity projected onto `+screenRight` (`rad/s`).
  /// Positive means the user is turning toward the right edge of the viewport.
  final double screenAngularVelXRadPerSec;

  /// Vertical angular velocity projected onto `+screenDown` (`rad/s`).
  /// Positive means the user is pitching downward toward the bottom edge.
  final double screenAngularVelYRadPerSec;

  /// Total 2D gaze angular speed $\sqrt{\omega_x^2 + \omega_y^2}$ (`rad/s`).
  final double angularSpeedRadPerSec;

  /// 3D linear locomotion speed of `eyeCenter` (`m/s`).
  final double linearSpeedMetersPerSec;

  /// Normalized viewport offset (`dx, dy` in `[-maxLeadShift .. +maxLeadShift]`)
  /// shifting each eye's active scissor / foveated sweet-spot **ahead** into
  /// the predicted direction of motion while dropping trailing-edge pixels.
  final ui.Offset opticalCenterLeadOffset;

  /// Multiplicative width/height scale (`[minSaccadicScale .. 1.0]`) applied
  /// during fast saccadic head/stick turns (`> saccadeThresholdRadPerSec`),
  /// exploiting human saccadic masking to shed unseen peripheral GPU pixels.
  final double saccadicScissorScale;

  /// Optional world-space far culling distance (`meters`) active during fast
  /// rotational sweeps (`null` when stationary or moving slowly so full scene
  /// horizon remains visible).
  final double? dynamicFarCullMeters;

  bool get isSaccadicSweep => saccadicScissorScale < 0.995;

  /// Additional GPU fragment savings fraction (`0.0 .. 0.36`) contributed by
  /// saccadic peripheral compression alone, on top of static lens scissor.
  double get additionalSaccadicPixelSavings =>
      (1.0 - saccadicScissorScale * saccadicScissorScale).clamp(0.0, 0.50);
}

/// Velocity-directed predictive rendering & BVH culling controller for
/// `StereoSceneView`.
///
/// Combines three physiological and geometric VR optimizations:
/// 1. **Gaze-Lead Asymmetric Crop Shift (`22 ms` lookahead):** shifts the
///    rendered lens/foveation window toward incoming geometry along the gaze
///    velocity vector and stops shading the trailing edge leaving the lens.
/// 2. **Saccadic Masking Compression (`> 43°/s`):** smoothly contracts
///    peripheral viewport dimensions during rapid head/thumbstick turns when
///    peripheral retinal acuity is physiologically suppressed, restoring `1.0`
///    smoothly on fixation.
/// 3. **World-Space Predictive BVH `cullingPlanes`:** builds inward-facing
///    `vm.Plane` half-spaces (`normal.dot(x) + constant >= 0`) matched to the
///    active cropped cone + trailing-edge velocity cull + saccadic far plane so
///    `flutter_scene`'s CPU Morton-BVH skips invisible 3D subtrees before draw
///    submission.
class VrPredictiveMotionCuller {
  VrPredictiveMotionCuller({
    this.lookaheadSeconds = 0.022,
    this.maxLeadViewportShift = 0.065,
    this.saccadeThresholdRadPerSec = 0.75,
    this.fullSaccadeRadPerSec = 2.60,
    this.minSaccadicScissorScale = 0.86,
    this.saccadeFarCullStartRadPerSec = 1.35,
    this.minDynamicFarCullMeters = 42.0,
    this.maxDynamicFarCullMeters = 140.0,
  });

  final double lookaheadSeconds;
  final double maxLeadViewportShift;
  final double saccadeThresholdRadPerSec;
  final double fullSaccadeRadPerSec;
  final double minSaccadicScissorScale;
  final double saccadeFarCullStartRadPerSec;
  final double minDynamicFarCullMeters;
  final double maxDynamicFarCullMeters;

  final vm.Vector3 _prevForward = vm.Vector3(0, 0, -1);
  final vm.Vector3 _prevEyeCenter = vm.Vector3.zero();
  bool _initialized = false;

  double _smoothVelX = 0.0;
  double _smoothVelY = 0.0;
  double _smoothLinearSpeed = 0.0;
  double _smoothSaccadicScale = 1.0;

  VrPredictiveCullState _state = VrPredictiveCullState.idle;
  VrPredictiveCullState get state => _state;

  void reset() {
    _initialized = false;
    _smoothVelX = 0.0;
    _smoothVelY = 0.0;
    _smoothLinearSpeed = 0.0;
    _smoothSaccadicScale = 1.0;
    _state = VrPredictiveCullState.idle;
  }

  /// Updates the motion predictor from the rig's current orthonormal basis.
  VrPredictiveCullState update({
    required vm.Vector3 forward,
    required vm.Vector3 screenRight,
    required vm.Vector3 up,
    required vm.Vector3 eyeCenter,
    required double dtSeconds,
    double fovRadiansY = 1.04719755,
  }) {
    if (!dtSeconds.isFinite || dtSeconds <= 1e-5 || dtSeconds > 0.25) {
      _prevForward.setFrom(forward);
      _prevEyeCenter.setFrom(eyeCenter);
      _initialized = true;
      return _state;
    }
    if (!_initialized) {
      _prevForward.setFrom(forward);
      _prevEyeCenter.setFrom(eyeCenter);
      _initialized = true;
      return _state;
    }

    final dfx = forward.x - _prevForward.x;
    final dfy = forward.y - _prevForward.y;
    final dfz = forward.z - _prevForward.z;
    _prevForward.setFrom(forward);

    final dpx = eyeCenter.x - _prevEyeCenter.x;
    final dpy = eyeCenter.y - _prevEyeCenter.y;
    final dpz = eyeCenter.z - _prevEyeCenter.z;
    _prevEyeCenter.setFrom(eyeCenter);

    // Project delta-forward onto screenRight (+dx) and -up (+dy, top-left origin).
    final rawVelX =
        ((dfx * screenRight.x + dfy * screenRight.y + dfz * screenRight.z) /
                dtSeconds)
            .clamp(-12.0, 12.0);
    final rawVelY =
        (-(dfx * up.x + dfy * up.y + dfz * up.z) / dtSeconds).clamp(
          -12.0,
          12.0,
        );
    final rawLinSpeed =
        (math.sqrt(dpx * dpx + dpy * dpy + dpz * dpz) / dtSeconds).clamp(
          0.0,
          30.0,
        );

    // Fast 28 ms time-constant EMA rejects single-sample IMU spikes while
    // reacting within 1-2 frames to genuine head/stick turns.
    final alpha = (1.0 - math.exp(-dtSeconds / 0.028)).clamp(0.08, 0.85);
    _smoothVelX += (rawVelX - _smoothVelX) * alpha;
    _smoothVelY += (rawVelY - _smoothVelY) * alpha;
    _smoothLinearSpeed += (rawLinSpeed - _smoothLinearSpeed) * alpha;

    final omega = math.sqrt(
      _smoothVelX * _smoothVelX + _smoothVelY * _smoothVelY,
    );

    final safeFov = fovRadiansY.isFinite && fovRadiansY > 0.2
        ? fovRadiansY
        : 1.04719755;
    final leadShiftX = ((_smoothVelX * lookaheadSeconds) / safeFov).clamp(
      -maxLeadViewportShift,
      maxLeadViewportShift,
    );
    final leadShiftY = ((_smoothVelY * lookaheadSeconds) / safeFov).clamp(
      -maxLeadViewportShift,
      maxLeadViewportShift,
    );

    // Saccadic peripheral compression: fast contraction on sweep, gentle
    // restoration on fixation so peripheral return is visually imperceptible.
    final saccadeT =
        ((omega - saccadeThresholdRadPerSec) /
                math.max(0.1, fullSaccadeRadPerSec - saccadeThresholdRadPerSec))
            .clamp(0.0, 1.0);
    final targetScale =
        1.0 - (1.0 - minSaccadicScissorScale) * (saccadeT * saccadeT);
    final scaleAlpha = targetScale < _smoothSaccadicScale ? 0.42 : 0.18;
    _smoothSaccadicScale += (targetScale - _smoothSaccadicScale) * scaleAlpha;

    double? dynamicFar;
    if (omega > saccadeFarCullStartRadPerSec) {
      final farT =
          ((omega - saccadeFarCullStartRadPerSec) /
                  math.max(
                    0.2,
                    fullSaccadeRadPerSec + 0.8 - saccadeFarCullStartRadPerSec,
                  ))
              .clamp(0.0, 1.0);
      dynamicFar =
          maxDynamicFarCullMeters -
          (maxDynamicFarCullMeters - minDynamicFarCullMeters) * farT;
    }

    _state = VrPredictiveCullState(
      screenAngularVelXRadPerSec: _smoothVelX,
      screenAngularVelYRadPerSec: _smoothVelY,
      angularSpeedRadPerSec: omega,
      linearSpeedMetersPerSec: _smoothLinearSpeed,
      opticalCenterLeadOffset: ui.Offset(
        omega < 0.08 ? 0.0 : leadShiftX,
        omega < 0.08 ? 0.0 : leadShiftY,
      ),
      saccadicScissorScale: _smoothSaccadicScale.clamp(
        minSaccadicScissorScale,
        1.0,
      ),
      dynamicFarCullMeters: dynamicFar,
    );
    return _state;
  }

  /// Applies predictive gaze-lead shift to stereo optical centers `[left, right]`.
  List<ui.Offset> shiftOpticalCenters(List<ui.Offset> baseCenters) {
    final lead = _state.opticalCenterLeadOffset;
    if (lead == ui.Offset.zero) return baseCenters;
    return [
      for (final c in baseCenters)
        ui.Offset(
          (c.dx + lead.dx).clamp(0.12, 0.88),
          (c.dy + lead.dy).clamp(0.12, 0.88),
        ),
    ];
  }

  /// Builds inward-facing world-space `vm.Plane`s (`normal.dot(p) + constant >= 0`)
  /// matching `flutter_scene`'s `Bvh.query` convention so bounded 3D objects
  /// outside the active cropped lens cone (or behind the trailing saccadic
  /// edge / beyond dynamic saccadic far depth) are skipped on the CPU BVH
  /// before GPU command encoding.
  static List<vm.Plane> buildPredictiveEyeCullingPlanes({
    required vm.Vector3 eyePosition,
    required vm.Vector3 forward,
    required vm.Vector3 screenRight,
    required vm.Vector3 up,
    required double fovRadiansY,
    required double fullEyeAspectRatio,
    required ui.Rect normalizedCropRect,
    double horizontalClipShift = 0.0,
    double safetyMarginRadians = 0.085,
    double? dynamicFarCullMeters,
  }) {
    if (fovRadiansY <= 0.05 ||
        !fovRadiansY.isFinite ||
        fullEyeAspectRatio <= 0.05 ||
        !fullEyeAspectRatio.isFinite) {
      return const [];
    }
    final planes = <vm.Plane>[];
    final tanHalfY = math.tan(fovRadiansY * 0.5);
    final tanHalfX = tanHalfY * fullEyeAspectRatio;
    final guardX = math.tan(safetyMarginRadians) + horizontalClipShift.abs();
    final guardY = math.tan(safetyMarginRadians);

    // Map normalized crop [0..1] (top-left origin) into tangent bounds:
    // u=0 -> -tanHalfX, u=1 -> +tanHalfX; v=0 -> +tanHalfY (top), v=1 -> -tanHalfY (bottom).
    final leftClip = normalizedCropRect.left * 2.0 - 1.0;
    final rightClip = normalizedCropRect.right * 2.0 - 1.0;
    final topClip = 1.0 - normalizedCropRect.top * 2.0;
    final bottomClip = 1.0 - normalizedCropRect.bottom * 2.0;

    final tauLeft = leftClip * tanHalfX - guardX;
    final tauRight = rightClip * tanHalfX + guardX;
    final tauBottom = bottomClip * tanHalfY - guardY;
    final tauTop = topClip * tanHalfY + guardY;

    vm.Plane makeConePlane(vm.Vector3 rawNormal) {
      final n = rawNormal.normalized();
      return vm.Plane.components(n.x, n.y, n.z, -n.dot(eyePosition));
    }

    // Only emit side planes when tighter than the uncropped eye frustum,
    // avoiding duplicate plane tests when full 1.0 x 1.0 viewport is active.
    if (normalizedCropRect.left > 0.01) {
      planes.add(makeConePlane(screenRight - forward * tauLeft));
    }
    if (normalizedCropRect.right < 0.99) {
      planes.add(makeConePlane(-screenRight + forward * tauRight));
    }
    if (normalizedCropRect.bottom < 0.99) {
      planes.add(makeConePlane(up - forward * tauBottom));
    }
    if (normalizedCropRect.top > 0.01) {
      planes.add(makeConePlane(-up + forward * tauTop));
    }

    if (dynamicFarCullMeters != null &&
        dynamicFarCullMeters.isFinite &&
        dynamicFarCullMeters > 4.0) {
      final f = forward.normalized();
      planes.add(
        vm.Plane.components(
          -f.x,
          -f.y,
          -f.z,
          f.dot(eyePosition) + dynamicFarCullMeters,
        ),
      );
    }
    return planes;
  }
}
