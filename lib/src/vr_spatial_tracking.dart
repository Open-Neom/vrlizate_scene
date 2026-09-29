import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:vector_math/vector_math.dart' as vm;
import 'package:vrlizate/vrlizate.dart' show CameraRig, RotationTarget;

import 'stereo_head_rig.dart';

enum VrSpatialTrackingState { tracking, paused, stopped }

/// A camera pose in the source's gravity-aligned, meter-scale world.
///
/// [orientation] uses the conventional active RH/OpenGL XYZW convention
/// (ARCore DisplayOrientedPose), NOT vector_math's inverse `rotated` convention.
/// The camera's local forward is -Z, right +X and up +Y. Unavailable poses carry
/// no fabricated position/orientation. Vectors are defensively copied.
class VrSpatialPose {
  VrSpatialPose({
    vm.Vector3? position,
    vm.Quaternion? orientation,
    required this.timestampNanos,
    required this.state,
    this.reason,
  }) : _position = position?.clone(),
       _orientation = orientation?.clone() {
    if (timestampNanos < 0) {
      throw ArgumentError.value(timestampNanos, 'timestampNanos');
    }
    if (state == VrSpatialTrackingState.tracking) {
      if (_position == null ||
          !_position.x.isFinite ||
          !_position.y.isFinite ||
          !_position.z.isFinite ||
          _orientation == null ||
          !_orientation.length2.isFinite ||
          _orientation.length2 < 1e-12 ||
          timestampNanos == 0) {
        throw ArgumentError('Tracking requires a finite pose and timestamp.');
      }
      _orientation.normalize();
    }
  }

  VrSpatialPose.tracking({
    required vm.Vector3 position,
    required vm.Quaternion orientation,
    required int timestampNanos,
  }) : this(
         position: position,
         orientation: orientation,
         timestampNanos: timestampNanos,
         state: VrSpatialTrackingState.tracking,
       );

  VrSpatialPose.unavailable({
    required VrSpatialTrackingState state,
    required int timestampNanos,
    String? reason,
  }) : this(timestampNanos: timestampNanos, state: state, reason: reason);

  final vm.Vector3? _position;
  final vm.Quaternion? _orientation;
  vm.Vector3? get position => _position?.clone();
  vm.Quaternion? get orientation => _orientation?.clone();
  final int timestampNanos;
  final VrSpatialTrackingState state;
  final String? reason;
}

/// App-owned, shared source. start/stop acquire/release reference-counted leases.
/// Implementations must serialize native lifecycle changes and balance leases
/// even when startup fails. No scene owns or disposes the native source object.
abstract interface class VrSpatialPoseSource {
  Stream<VrSpatialPose> get poses;
  Future<void> start();
  Future<void> stop();
}

/// Explicit opt-in. The source is leased only by an active, resumed scene.
///
/// Calibration maps eye-center coordinates into the source camera coordinates.
/// Zero translation / identity rotation means **uncalibrated**, not a measured
/// camera-to-eye transform. A physical viewer needs a measured mount profile.
class VrSpatialTrackingScope extends InheritedWidget {
  VrSpatialTrackingScope({
    super.key,
    required this.source,
    required super.child,
    this.enabled = true,
    vm.Vector3? cameraToEyeTranslation,
    vm.Quaternion? cameraToEyeRotation,
  }) : cameraToEyeTranslation =
           cameraToEyeTranslation?.clone() ?? vm.Vector3.zero(),
       cameraToEyeRotation =
           cameraToEyeRotation?.clone() ?? vm.Quaternion.identity();

  final VrSpatialPoseSource source;
  final bool enabled;
  final vm.Vector3 cameraToEyeTranslation;
  final vm.Quaternion cameraToEyeRotation;

  static VrSpatialTrackingScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<VrSpatialTrackingScope>();

  @override
  bool updateShouldNotify(VrSpatialTrackingScope oldWidget) =>
      source != oldWidget.source ||
      enabled != oldWidget.enabled ||
      cameraToEyeTranslation != oldWidget.cameraToEyeTranslation ||
      cameraToEyeRotation != oldWidget.cameraToEyeRotation;
}

/// Bridges measured camera poses and an independently running IMU fallback.
///
/// Send HeadTracker input to this RotationTarget, never directly to the rig
/// while attached. Tracking uses one orientation authority. Loss freezes
/// physical translation; IMU continues from the last rendered orientation.
/// Recovery rebases translation and heading, so a reset source origin cannot
/// teleport the viewer. Gravity alignment is restored over [recoveryBlend].
class VrSpatialTrackingController implements RotationTarget {
  VrSpatialTrackingController({
    required this.rig,
    required this.source,
    vm.Vector3? cameraToEyeTranslation,
    vm.Quaternion? cameraToEyeRotation,
    this.staleAfter = const Duration(milliseconds: 500),
    this.recoveryBlend = const Duration(milliseconds: 250),
    Duration Function()? now,
  }) : cameraToEyeTranslation =
           cameraToEyeTranslation?.clone() ?? vm.Vector3.zero(),
       cameraToEyeRotation =
           cameraToEyeRotation?.clone() ?? vm.Quaternion.identity(),
       _now = now ?? (Stopwatch()..start()).elapsedGetter {
    if (staleAfter <= Duration.zero || recoveryBlend < Duration.zero) {
      throw ArgumentError('Invalid spatial tracking timing.');
    }
    if (!this.cameraToEyeTranslation.x.isFinite ||
        !this.cameraToEyeTranslation.y.isFinite ||
        !this.cameraToEyeTranslation.z.isFinite ||
        !this.cameraToEyeRotation.length2.isFinite ||
        this.cameraToEyeRotation.length2 < 1e-12) {
      throw ArgumentError('Invalid camera-to-eye calibration.');
    }
    this.cameraToEyeRotation.normalize();
    _fallback.rotation = rig.cameraRig.rotation.clone();
  }

  final StereoHeadRig rig;
  final VrSpatialPoseSource source;
  final vm.Vector3 cameraToEyeTranslation;
  final vm.Quaternion cameraToEyeRotation;
  final Duration staleAfter;
  final Duration recoveryBlend;
  final Duration Function() _now;
  final CameraRig _fallback = CameraRig();
  final vm.Vector3 _anchorPosition = vm.Vector3.zero();
  final vm.Vector3 _anchorOffset = vm.Vector3.zero();
  vm.Quaternion _trackingToWorld = vm.Quaternion.identity();
  vm.Quaternion _translationToWorld = vm.Quaternion.identity();
  double _translationBodyYaw = 0;
  vm.Quaternion _fallbackToWorld = vm.Quaternion.identity();
  vm.Quaternion _recoveryCorrection = vm.Quaternion.identity();
  StreamSubscription<VrSpatialPose>? _subscription;
  Timer? _staleTimer;
  Future<void>? _startFuture;
  VrSpatialPose? _lastPose;
  VrSpatialPose? _lastPublishedPose;
  Duration? _lastArrival;
  Duration _correctionStart = Duration.zero;
  Duration _lastLog = Duration.zero;
  int _lastTimestampNanos = -1;
  bool _attached = false;
  bool _tracking = false;
  String? _lastLossReason;

  bool get isAttached => _attached;
  bool get isTracking => _tracking;

  Future<void> attach() async {
    if (_attached) return;
    _attached = true;
    _lastTimestampNanos = -1;
    _fallback.rotation = rig.cameraRig.rotation.clone();
    _fallbackToWorld = vm.Quaternion.identity();
    rig.attachSpatialOwner(this, recenter);
    _log('starting');
    try {
      _subscription = source.poses.listen(
        acceptPose,
        onError: (Object error, StackTrace stack) =>
            _loseTracking('source_error'),
        onDone: () => _loseTracking('source_closed'),
      );
      _staleTimer = Timer.periodic(
        const Duration(milliseconds: 100),
        (_) => tick(),
      );
      // Also catch synchronous implementations; widget callers deliberately
      // do not await startup while their route transition is rendering.
      _startFuture = Future<void>.sync(source.start);
      await _startFuture;
    } catch (error) {
      _loseTracking('start_failed');
      if (kDebugMode) debugPrint('Spatial tracking start failed: $error');
    }
  }

  Future<void> detach() async {
    if (!_attached) return;
    _loseTracking('detached');
    _attached = false;
    _staleTimer?.cancel();
    _staleTimer = null;
    final subscription = _subscription;
    _subscription = null;
    rig.detachSpatialOwner(this);
    // Release intent before any await. The app-owned source serializes native
    // transitions; waiting here could leave camera intent alive on a QR route.
    final stopping = _startFuture == null
        ? Future<void>.value()
        : Future<void>.sync(source.stop).catchError((Object error) {
            if (kDebugMode) debugPrint('Spatial tracking stop failed: $error');
          });
    _startFuture = null;
    try {
      await subscription?.cancel();
    } catch (error) {
      if (kDebugMode) debugPrint('Spatial pose stream cancel failed: $error');
    }
    await stopping;
  }

  /// Public for deterministic native-bridge tests. Older/duplicate source
  /// timestamps cannot rewind pose or refresh the stale-data deadline.
  void acceptPose(VrSpatialPose pose) {
    if (!_attached || pose.timestampNanos < _lastTimestampNanos) return;
    if (pose.state != VrSpatialTrackingState.tracking) {
      // ARCore can change state without producing a newer image timestamp.
      // Such a pause must take effect immediately instead of waiting for stale.
      _lastTimestampNanos = pose.timestampNanos;
      _loseTracking(pose.reason ?? pose.state.name);
      return;
    }
    if (pose.timestampNanos == _lastTimestampNanos) return;
    _lastTimestampNanos = pose.timestampNanos;
    _lastArrival = _now();
    _lastPose = pose;
    if (!_tracking) {
      _anchor(pose);
      _tracking = true;
      _lastLossReason = null;
      _log('tracking');
    }
    _publishTracking(pose);
  }

  void tick() {
    if (!_attached) return;
    final now = _now();
    if (_tracking && _lastArrival != null && now - _lastArrival! > staleAfter) {
      _loseTracking('stale');
    }
    if (_tracking && _lastPose != null) _publishTracking(_lastPose!);
    if (now - _lastLog >= const Duration(seconds: 2)) {
      _lastLog = now;
      _log(_tracking ? 'tracking_pose' : 'imu_pose');
    }
  }

  vm.Quaternion _eyeOrientation(VrSpatialPose pose) {
    final q = (pose._orientation! * cameraToEyeRotation)..normalize();
    // flutter_scene's screen-right is up.cross(forward), i.e. -X at rest.
    // Reflect BOTH camera/world bases through M=diag(-1,1,1): R'=M R M.
    // Conjugation for vector_math alone would mirror physical head movement.
    return vm.Quaternion(q.x, -q.y, -q.z, q.w);
  }

  vm.Vector3 _eyePosition(VrSpatialPose pose) {
    final p =
        pose._position! +
        _activeRotate(pose._orientation!, cameraToEyeTranslation);
    return vm.Vector3(-p.x, p.y, p.z);
  }

  void _anchor(VrSpatialPose pose) {
    final eyeOrientation = _eyeOrientation(pose);
    final heading = rig.cameraRig.yaw;
    _trackingToWorld = _headingRotation(heading - _heading(eyeOrientation));
    _translationBodyYaw = rig.bodyYaw;
    _translationToWorld =
        _headingRotation(_translationBodyYaw) * _trackingToWorld;
    _anchorPosition.setFrom(_eyePosition(pose));
    _anchorOffset.setFrom(rig.physicalTranslation);
    final target = _trackingToWorld * eyeOrientation;
    // Preserve the rendered view at the boundary, then remove only this
    // transient correction. The world origin itself remains gravity-aligned.
    _recoveryCorrection = (_inverse(rig.cameraRig.rotation) * _inverse(target))
      ..normalize();
    _correctionStart = _now();
    _lastPublishedPose = pose;
  }

  void _publishTracking(VrSpatialPose pose) {
    if (rig.bodyYaw != _translationBodyYaw) {
      // Turning virtual locomotion changes future physical displacement axes,
      // not the already accumulated position. Anchor before rotating the frame
      // to avoid orbiting the HMD around an old tracking origin.
      _anchorPosition.setFrom(_eyePosition(_lastPublishedPose ?? pose));
      _anchorOffset.setFrom(rig.physicalTranslation);
      _translationBodyYaw = rig.bodyYaw;
      _translationToWorld =
          _headingRotation(_translationBodyYaw) * _trackingToWorld;
    }
    final delta = _eyePosition(pose) - _anchorPosition;
    final offset = _anchorOffset + _activeRotate(_translationToWorld, delta);
    var orientation = _trackingToWorld * _eyeOrientation(pose);
    final blend = recoveryBlend.inMicroseconds == 0
        ? 1.0
        : ((_now() - _correctionStart).inMicroseconds /
                  recoveryBlend.inMicroseconds)
              .clamp(0.0, 1.0);
    if (blend < 1) {
      final correction = _slerp(
        _recoveryCorrection,
        vm.Quaternion.identity(),
        blend,
      );
      orientation = correction * orientation;
    }
    rig.applySpatialPose(
      translationOffset: offset,
      rotation: _inverse(orientation),
    );
    _lastPublishedPose = pose;
  }

  void _loseTracking(String reason) {
    if (!_tracking) {
      if (_lastLossReason != reason) _log('imu_fallback:$reason');
      _lastLossReason = reason;
      return;
    }
    _tracking = false;
    _lastLossReason = reason;
    _fallbackToWorld = (_inverse(rig.cameraRig.rotation) * _fallback.rotation)
      ..normalize();
    _log('imu_fallback:$reason');
  }

  void _publishFallback() {
    if (!_attached || _tracking) return;
    final active = _fallbackToWorld * _inverse(_fallback.rotation);
    rig.applySpatialPose(
      translationOffset: rig.physicalTranslation,
      rotation: _inverse(active),
    );
  }

  @override
  void rotate(double dTheta, double dPhi) {
    _fallback.rotate(dTheta, dPhi);
    _publishFallback();
  }

  @override
  void setPitch(double pitch) {
    _fallback.setPitch(pitch);
    _publishFallback();
  }

  @override
  void setOrientation(double yaw, double pitch) {
    _fallback.setOrientation(yaw, pitch);
    _publishFallback();
  }

  /// Zero physical heading without moving the viewer or resetting locomotion.
  @override
  void recenter() {
    final active = _inverse(rig.cameraRig.rotation);
    final recentered = _headingRotation(-rig.cameraRig.yaw) * active;
    rig.applySpatialPose(
      translationOffset: rig.physicalTranslation,
      rotation: _inverse(recentered),
    );
    _fallback.recenter();
    _fallbackToWorld = (recentered * _fallback.rotation)..normalize();
    if (_tracking && _lastPose != null) _anchor(_lastPose!);
  }

  @override
  void reset() => recenter();

  void _log(String mode) {
    if (!const bool.fromEnvironment('VRLIZATE_SPATIAL_LOG')) return;
    debugPrint(
      'VRLIZATE_SPATIAL $mode eye=${rig.eyeCenter} '
      'physical=${rig.physicalTranslation} origin=${rig.locomotionOrigin} '
      'yaw=${rig.yaw} pitch=${rig.pitch}',
    );
  }
}

vm.Quaternion _inverse(vm.Quaternion q) =>
    vm.Quaternion(-q.x, -q.y, -q.z, q.w)..normalize();

/// vector_math.rotate evaluates conjugate(q) * v * q: invert first for ARCore.
vm.Vector3 _activeRotate(vm.Quaternion q, vm.Vector3 v) =>
    _inverse(q).rotated(v);

double _heading(vm.Quaternion active) {
  final forward = _activeRotate(active, vm.Vector3(0, 0, -1));
  return math.atan2(forward.x, -forward.z);
}

vm.Quaternion _headingRotation(double heading) =>
    vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), -heading);

vm.Quaternion _slerp(vm.Quaternion from, vm.Quaternion to, double t) {
  var dot = from.x * to.x + from.y * to.y + from.z * to.z + from.w * to.w;
  final sign = dot < 0 ? -1.0 : 1.0;
  dot = dot.abs().clamp(0.0, 1.0);
  final angle = math.acos(dot);
  final sine = math.sin(angle);
  final a = sine.abs() < 1e-6 ? 1 - t : math.sin((1 - t) * angle) / sine;
  final b = (sine.abs() < 1e-6 ? t : math.sin(t * angle) / sine) * sign;
  return vm.Quaternion(
    from.x * a + to.x * b,
    from.y * a + to.y * b,
    from.z * a + to.z * b,
    from.w * a + to.w * b,
  )..normalize();
}

extension on Stopwatch {
  Duration Function() get elapsedGetter =>
      () => elapsed;
}
