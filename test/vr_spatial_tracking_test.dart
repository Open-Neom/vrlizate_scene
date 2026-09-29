import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;
import 'package:vrlizate_scene/vrlizate_scene.dart';

class _Source implements VrSpatialPoseSource {
  final stream = StreamController<VrSpatialPose>.broadcast(sync: true);
  int starts = 0;
  int stops = 0;
  Completer<void>? startGate;
  bool failStart = false;
  @override
  Stream<VrSpatialPose> get poses => stream.stream;
  @override
  Future<void> start() async {
    starts++;
    if (failStart) throw StateError('Native session unavailable');
    await startGate?.future;
  }

  @override
  Future<void> stop() async => stops++;
}

VrSpatialPose _pose(int timestamp, {vm.Vector3? position, vm.Quaternion? q}) =>
    VrSpatialPose.tracking(
      position: position ?? vm.Vector3.zero(),
      orientation: q ?? vm.Quaternion.identity(),
      timestampNanos: timestamp,
    );

void _nearVector(
  vm.Vector3 actual,
  vm.Vector3 expected, [
  double epsilon = 1e-6,
]) {
  expect(actual.x, closeTo(expected.x, epsilon));
  expect(actual.y, closeTo(expected.y, epsilon));
  expect(actual.z, closeTo(expected.z, epsilon));
}

vm.Vector3 _activeRotate(vm.Quaternion q, vm.Vector3 v) =>
    vm.Quaternion(-q.x, -q.y, -q.z, q.w).rotated(v);

void main() {
  late _Source source;
  late StereoHeadRig rig;
  late VrSpatialTrackingController controller;
  late Duration now;

  setUp(() {
    source = _Source();
    rig = StereoHeadRig(eyeCenter: vm.Vector3(3, 1.6, 7));
    now = Duration.zero;
    controller = VrSpatialTrackingController(
      rig: rig,
      source: source,
      now: () => now,
      recoveryBlend: Duration.zero,
    );
  });

  tearDown(() async {
    await controller.detach();
    await source.stream.close();
  });

  test('pose validates finite tracking and preserves input ownership', () {
    final p = vm.Vector3(1, 2, 3);
    final q = vm.Quaternion.identity();
    final pose = VrSpatialPose.tracking(
      position: p,
      orientation: q,
      timestampNanos: 1,
    );
    p.setZero();
    q.setValues(1, 0, 0, 0);
    pose.position!.setZero();
    _nearVector(pose.position!, vm.Vector3(1, 2, 3));
    expect(pose.orientation!.w, 1);
    expect(
      () => _pose(1, position: vm.Vector3(double.nan, 0, 0)),
      throwsArgumentError,
    );
    expect(() => _pose(0), throwsArgumentError);
    expect(
      VrSpatialPose.unavailable(
        state: VrSpatialTrackingState.paused,
        timestampNanos: 0,
      ).position,
      isNull,
    );
  });

  test('leases start once and release without resetting the viewer', () async {
    await controller.attach();
    await controller.attach();
    source.stream.add(_pose(1));
    source.stream.add(_pose(2, position: vm.Vector3(1, 0, 0)));
    final before = rig.eyeCenter.clone();
    await controller.detach();
    await controller.detach();
    expect(source.starts, 1);
    expect(source.stops, 1);
    _nearVector(rig.eyeCenter, before);
    _nearVector(rig.physicalTranslation, vm.Vector3.zero());
    source.stream.add(_pose(3, position: vm.Vector3(100, 0, 0)));
    _nearVector(rig.eyeCenter, before);
  });

  test(
    'detach releases camera intent while native startup is pending',
    () async {
      source.startGate = Completer<void>();
      final starting = controller.attach();
      expect(source.starts, 1);
      final stopping = controller.detach();
      expect(source.stops, 1);
      expect(controller.isAttached, isFalse);
      source.startGate!.complete();
      await starting;
      await stopping;
    },
  );

  test(
    'failed native startup is handled and its lease remains balanced',
    () async {
      source.failStart = true;
      await controller.attach();
      expect(controller.isTracking, isFalse);
      await controller.detach();
      expect(source.starts, 1);
      expect(source.stops, 1);
    },
  );

  test(
    'source stream errors switch to IMU without moving the viewer',
    () async {
      await controller.attach();
      source.stream.add(_pose(1));
      final before = rig.eyeCenter.clone();
      source.stream.addError(StateError('Camera closed'));
      expect(controller.isTracking, isFalse);
      _nearVector(rig.eyeCenter, before);
    },
  );

  test(
    'ARCore active quaternion preserves yaw sign and physical roll',
    () async {
      await controller.attach();
      source.stream.add(_pose(1));
      source.stream.add(
        _pose(2, q: vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), math.pi / 2)),
      );
      _nearVector(rig.forward, vm.Vector3(1, 0, 0));
      source.stream.add(
        _pose(3, q: vm.Quaternion.axisAngle(vm.Vector3(0, 0, 1), math.pi / 2)),
      );
      _nearVector(rig.forward, vm.Vector3(0, 0, -1));
      _nearVector(rig.up, vm.Vector3(1, 0, 0));
    },
  );

  test(
    'absolute displacement and joystick changes do not accumulate twice',
    () async {
      await controller.attach();
      source.stream.add(_pose(1, position: vm.Vector3(100, 4, 100)));
      _nearVector(rig.eyeCenter, vm.Vector3(3, 1.6, 7));
      source.stream.add(_pose(2, position: vm.Vector3(101, 4, 100)));
      _nearVector(rig.eyeCenter, vm.Vector3(2, 1.6, 7));
      _nearVector(rig.locomotionOrigin, vm.Vector3(3, 1.6, 7));
      rig.eyeCenter = vm.Vector3(10, 2, 20);
      for (var i = 3; i < 100; i++) {
        source.stream.add(_pose(i, position: vm.Vector3(101, 4, 100)));
      }
      _nearVector(rig.eyeCenter, vm.Vector3(10, 2, 20));
      _nearVector(rig.locomotionOrigin, vm.Vector3(11, 2, 20));
      rig.eyeCenter.add(vm.Vector3(0, 0, 2));
      source.stream.add(_pose(100, position: vm.Vector3(101, 4, 100)));
      _nearVector(rig.eyeCenter, vm.Vector3(10, 2, 22));
    },
  );

  test('camera-to-eye lever arm rotates once in the camera basis', () async {
    controller = VrSpatialTrackingController(
      rig: rig,
      source: source,
      cameraToEyeTranslation: vm.Vector3(.1, 0, 0),
      recoveryBlend: Duration.zero,
      now: () => now,
    );
    await controller.attach();
    source.stream.add(_pose(1));
    final origin = rig.eyeCenter.clone();
    source.stream.add(
      _pose(2, q: vm.Quaternion.axisAngle(vm.Vector3(0, 0, 1), math.pi / 2)),
    );
    _nearVector(rig.eyeCenter, origin + vm.Vector3(.1, .1, 0));
  });

  test(
    'physical right motion shifts a static object left on the real projection',
    () async {
      await controller.attach();
      source.stream.add(_pose(1));
      const viewport = Size(1000, 900);
      final object = rig.eyeCenter + vm.Vector3(0, 0, -3);
      final before = rig
          .eyeCamera(StereoEye.left)
          .worldToScreen(object, viewport)!;
      source.stream.add(_pose(2, position: vm.Vector3(.1, 0, 0)));
      final after = rig
          .eyeCamera(StereoEye.left)
          .worldToScreen(object, viewport)!;
      expect(after.dx, lessThan(before.dx));
      expect(rig.physicalTranslation.dot(vm.Vector3(-1, 0, 0)), greaterThan(0));
    },
  );

  test(
    'physical right yaw shifts a static object left on the real projection',
    () async {
      await controller.attach();
      source.stream.add(_pose(1));
      const viewport = Size(1000, 900);
      final object = rig.eyeCenter + vm.Vector3(0, 0, -3);
      final before = rig
          .eyeCamera(StereoEye.left)
          .worldToScreen(object, viewport)!;
      // Standard active ARCore rotation: -Y rotates -Z toward physical +X.
      source.stream.add(
        _pose(2, q: vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), -.1)),
      );
      final after = rig
          .eyeCamera(StereoEye.left)
          .worldToScreen(object, viewport)!;
      expect(after.dx, lessThan(before.dx));
    },
  );

  test(
    'virtual turn rotates future physical motion without orbiting old position',
    () async {
      await controller.attach();
      source.stream.add(_pose(1));
      source.stream.add(_pose(2, position: vm.Vector3(0, 0, -1)));
      final before = rig.eyeCenter.clone();
      rig.rotate(math.pi / 2, 0);
      controller.tick();
      _nearVector(rig.eyeCenter, before);
      final heading = rig.forward.clone();
      source.stream.add(_pose(3, position: vm.Vector3(0, 0, -2)));
      _nearVector(rig.eyeCenter - before, heading);
      // Repeated absolute pose cannot apply the turn/displacement twice.
      source.stream.add(_pose(4, position: vm.Vector3(0, 0, -2)));
      _nearVector(rig.eyeCenter - before, heading);
    },
  );

  test(
    'live IMU never adds to VIO and fallback starts without a jump',
    () async {
      await controller.attach();
      source.stream.add(_pose(1));
      source.stream.add(
        _pose(2, q: vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), -.2)),
      );
      controller.rotate(.5, 0);
      expect(rig.yaw, closeTo(-.2, 1e-6));
      final before = rig.forward.clone();
      source.stream.add(
        VrSpatialPose.unavailable(
          state: VrSpatialTrackingState.paused,
          timestampNanos: 3,
          reason: 'INSUFFICIENT_FEATURES',
        ),
      );
      expect(controller.isTracking, isFalse);
      _nearVector(rig.forward, before);
      controller.rotate(.1, 0);
      expect(rig.yaw, closeTo(-.1, 1e-6));
    },
  );

  test(
    'recovery rebases a reset source origin without teleportation',
    () async {
      await controller.attach();
      source.stream.add(_pose(1));
      source.stream.add(_pose(2, position: vm.Vector3(1, 0, 0)));
      now = const Duration(seconds: 1);
      controller.tick();
      expect(controller.isTracking, isFalse);
      controller.rotate(.2, 0);
      final before = rig.eyeCenter.clone();
      source.stream.add(
        _pose(
          3,
          position: vm.Vector3(80, 30, -20),
          q: vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), -1.2),
        ),
      );
      expect(controller.isTracking, isTrue);
      _nearVector(rig.eyeCenter, before);
      expect(rig.yaw, closeTo(.2, 1e-6));
      source.stream.add(
        _pose(
          4,
          position: vm.Vector3(81, 30, -20),
          q: vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), -1.2),
        ),
      );
      expect((rig.eyeCenter - before).length, closeTo(1, 1e-6));
    },
  );

  test('out-of-order timestamps cannot move pose or keep it fresh', () async {
    await controller.attach();
    source.stream.add(_pose(10));
    source.stream.add(_pose(20, position: vm.Vector3(1, 0, 0)));
    final before = rig.eyeCenter.clone();
    now = const Duration(milliseconds: 600);
    source.stream.add(_pose(20, position: vm.Vector3(100, 0, 0)));
    source.stream.add(_pose(19, position: vm.Vector3(200, 0, 0)));
    controller.tick();
    expect(controller.isTracking, isFalse);
    _nearVector(rig.eyeCenter, before);
  });

  test(
    'paused state applies even when the camera timestamp is unchanged',
    () async {
      await controller.attach();
      source.stream.add(_pose(10));
      expect(controller.isTracking, isTrue);
      source.stream.add(
        VrSpatialPose.unavailable(
          state: VrSpatialTrackingState.paused,
          timestampNanos: 10,
        ),
      );
      expect(controller.isTracking, isFalse);
      source.stream.add(_pose(10));
      expect(controller.isTracking, isFalse);
      source.stream.add(_pose(11));
      expect(controller.isTracking, isTrue);
    },
  );

  test(
    'direct rig recenter updates source origin and preserves locomotion',
    () async {
      await controller.attach();
      source.stream.add(_pose(1));
      final q = vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), -.6);
      source.stream.add(_pose(2, position: vm.Vector3(1, 0, 0), q: q));
      rig.bodyYaw = .2;
      final before = rig.eyeCenter.clone();
      rig.recenter();
      expect(rig.cameraRig.yaw, closeTo(0, 1e-6));
      expect(rig.bodyYaw, .2);
      source.stream.add(_pose(3, position: vm.Vector3(1, 0, 0), q: q));
      _nearVector(rig.eyeCenter, before);
      expect(rig.yaw, closeTo(.2, 1e-6));
    },
  );

  test(
    'virtual yaw and pitch compose with physical roll exactly once',
    () async {
      await controller.attach();
      source.stream.add(_pose(1));
      final roll = vm.Quaternion.axisAngle(vm.Vector3(0, 0, 1), .3);
      source.stream.add(_pose(2, q: roll));
      rig.rotate(.4, 0);
      rig.bodyPitch = .2;
      source.stream.add(_pose(3, q: roll));
      final expected =
          vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), -.4) *
          vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), -.2) *
          vm.Quaternion(-roll.x, -roll.y, -roll.z, roll.w);
      _nearVector(rig.forward, _activeRotate(expected, vm.Vector3(0, 0, -1)));
      _nearVector(rig.up, _activeRotate(expected, vm.Vector3(0, 1, 0)));
    },
  );

  test(
    'recovery boundary preserves view then restores gravity alignment',
    () async {
      controller = VrSpatialTrackingController(
        rig: rig,
        source: source,
        now: () => now,
      );
      await controller.attach();
      final before = rig.up.clone();
      final roll = vm.Quaternion.axisAngle(vm.Vector3(0, 0, 1), .25);
      source.stream.add(_pose(1, q: roll));
      _nearVector(rig.up, before);
      now = const Duration(milliseconds: 250);
      controller.tick();
      _nearVector(
        rig.up,
        _activeRotate(
          vm.Quaternion(roll.x, -roll.y, -roll.z, roll.w),
          vm.Vector3(0, 1, 0),
        ),
      );
    },
  );

  test(
    'spatial composition cache invalidates when only roll changes',
    () async {
      await controller.attach();
      source.stream.add(_pose(1));
      rig.bodyYaw = .3;
      rig.bodyPitch = .2;
      final before = rig.up.clone();
      final yawBefore = rig.cameraRig.yaw;
      final pitchBefore = rig.cameraRig.pitch;
      final roll = vm.Quaternion.axisAngle(vm.Vector3(0, 0, 1), .4);
      source.stream.add(_pose(2, q: roll));
      expect(rig.cameraRig.yaw, closeTo(yawBefore, 1e-6));
      expect(rig.cameraRig.pitch, closeTo(pitchBefore, 1e-6));
      expect(rig.up.distanceTo(before), greaterThan(.01));
      final expected =
          vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), -.3) *
          vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), -.2) *
          vm.Quaternion(roll.x, -roll.y, -roll.z, roll.w);
      _nearVector(rig.up, _activeRotate(expected, vm.Vector3(0, 1, 0)));
    },
  );

  test(
    'spatial orientation callers cannot mutate cache or physical pose',
    () async {
      await controller.attach();
      source.stream.add(_pose(1));
      source.stream.add(
        _pose(2, q: vm.Quaternion.axisAngle(vm.Vector3(0, 0, 1), .3)),
      );
      for (final bodyYaw in [0.0, .4]) {
        rig.bodyYaw = bodyYaw;
        final expected = rig.orientation;
        rig.orientation.setValues(0, 0, 0, 0);
        expect(rig.orientation.storage, orderedEquals(expected.storage));
        expect(rig.cameraRig.rotation.length, closeTo(1, 1e-6));
      }
    },
  );
}
