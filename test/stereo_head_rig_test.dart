import 'dart:ui' show Rect, Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_scene/scene.dart' show PerspectiveCamera;
import 'package:vector_math/vector_math.dart' as vm;
import 'package:vrlizate/vrlizate.dart' show CameraRig;
import 'package:vrlizate_scene/vrlizate_scene.dart';

void main() {
  group('StereoHeadRig', () {
    test('eyes are separated by the configured IPD', () {
      final rig = StereoHeadRig(eyeCenter: vm.Vector3(0, 1.6, 0), ipd: 0.064);
      final left = rig.eyePosition(StereoEye.left);
      final right = rig.eyePosition(StereoEye.right);
      expect((right - left).length, closeTo(0.064, 1e-6));
      expect((left + right) / 2, vm.Vector3(0, 1.6, 0));
      expect((right - left).dot(rig.screenRight), closeTo(0.064, 1e-6));
    });

    test('gaze ray starts at eye center and points forward', () {
      final rig = StereoHeadRig(eyeCenter: vm.Vector3(1, 2, 3));
      final ray = rig.gazeRay;
      expect(ray.origin, vm.Vector3(1, 2, 3));
      expect(ray.direction, vm.Vector3(0, 0, -1));
    });

    test('rotate() turns the gaze direction', () {
      final rig = StereoHeadRig();
      final before = rig.forward.clone();
      rig.rotate(0.5, 0);
      expect(rig.forward.distanceTo(before), greaterThan(0.01));
      rig.reset();
      expect(rig.forward.distanceTo(vm.Vector3(0, 0, -1)), lessThan(1e-6));
    });

    test('buildStereoViews produces left/right half-screen viewports', () {
      final rig = StereoHeadRig();
      final views = rig.buildStereoViews();
      expect(views, hasLength(2));
      expect(views[0].viewport, const Rect.fromLTWH(0, 0, 0.5, 1));
      expect(views[1].viewport, const Rect.fromLTWH(0.5, 0, 0.5, 1));
    });

    test('stereo pair matches individual eyes across poses and optics', () {
      final rig = StereoHeadRig(eyeCenter: vm.Vector3(2, 1.6, -4));
      const size = Size(1000, 900);
      for (final body in [0.0, 0.6]) {
        rig.bodyYaw = body;
        rig.bodyPitch = -body / 2;
        for (final pitch in [-1.4, 0.0, 1.4]) {
          rig.setOrientation(0.8, pitch);
          for (final convergence in [null, 0.0, 1.8, 4.0]) {
            rig.convergenceDistance = convergence;
            for (final inset in [0.0, 0.1, 0.3]) {
              rig.stereoImageInset = inset;
              rig.ipd = 0.07;
              final pair = rig.buildStereoViews(fovRadiansY: 1.1);
              for (final eye in StereoEye.values) {
                final expected = rig.eyeCamera(eye, fovRadiansY: 1.1);
                final actual = pair[eye.index].camera;
                expect(
                  actual.position.distanceTo(expected.position),
                  lessThan(1e-9),
                );
                expect(
                  actual.forward.distanceTo(expected.forward),
                  lessThan(1e-9),
                );
                expect(actual.up.distanceTo(expected.up), lessThan(1e-9));
                expect(
                  actual.getViewTransform(size).storage,
                  orderedEquals(expected.getViewTransform(size).storage),
                );
              }
            }
          }
        }
      }
    });

    test(
      'composed pose follows body, tracked head and clamped pitch changes',
      () {
        final rig = StereoHeadRig()..bodyYaw = 0.6;
        void checkPose() {
          final expected = CameraRig()..setOrientation(rig.yaw, rig.pitch);
          expect(
            rig.orientation.storage,
            orderedEquals(expected.rotation.storage),
          );
        }

        checkPose();
        rig.bodyYaw = -0.4;
        checkPose();
        rig.cameraRig.setOrientation(0.8, 1.4);
        rig.bodyPitch = 0.5;
        expect(rig.pitch, 1.45);
        checkPose();
        rig.cameraRig.rotation = vm.Quaternion.euler(-0.5, 0.4, 0);
        checkPose();
        rig.bodyYaw = rig.bodyPitch = 0;
        expect(rig.orientation, same(rig.cameraRig.headTransform.rotation));
        rig.cameraRig.setOrientation(-0.7, -1.4);
        rig.bodyPitch = -0.5;
        expect(rig.pitch, -1.45);
        checkPose();
        rig.recenter();
        checkPose();
        rig.reset();
        checkPose();
      },
    );

    test(
      'returned composed quaternions cannot mutate subsequent camera poses',
      () {
        final rig = StereoHeadRig()..bodyYaw = 0.6;
        final original = rig.orientation;
        final copy = original.clone();
        original.setValues(0, 0, 0, 0);
        expect(rig.orientation.storage, orderedEquals(copy.storage));
        expect(rig.orientation, isNot(same(original)));
        expect(rig.eyeCamera(StereoEye.left).forward.length, closeTo(1, 1e-6));
      },
    );

    test('stereo views preserve overridden eye cameras', () {
      final rig = _CustomCameraRig();
      final views = rig.buildStereoViews(fovRadiansY: 0.9);
      expect(rig.requestedEyes, [StereoEye.left, StereoEye.right]);
      expect(views[0].camera.position.x, closeTo(10.032, 1e-5));
      expect(views[1].camera.position.x, closeTo(9.968, 1e-5));
      for (final view in views) {
        expect((view.camera as PerspectiveCamera).fovRadiansY, 0.9);
      }
    });

    test('eye cameras preserve overridden eye positions', () {
      final rig = _CustomEyePositionRig()..bodyYaw = 0.3;
      final views = rig.buildStereoViews();
      expect(views[0].camera.position, vm.Vector3(2, 3, 4));
      expect(views[1].camera.position, vm.Vector3(5, 6, 7));
    });

    test(
      'camera snapshots remain independent of each other and later poses',
      () {
        final rig = StereoHeadRig()..bodyYaw = 0.4;
        final oldPair = rig.buildStereoViews();
        final oldLeftPosition = oldPair[0].camera.position.clone();
        final oldRightUp = oldPair[1].camera.up.clone();
        oldPair[0].camera.up.setZero();
        expect(oldPair[1].camera.up, oldRightUp);
        rig.eyeCenter.setValues(2, 3, 4);
        rig.bodyYaw = 1.2;
        rig.bodyPitch = -0.3;
        final newPair = rig.buildStereoViews();
        expect(oldPair[0].camera.position, oldLeftPosition);
        expect(oldPair[1].camera.up, oldRightUp);
        expect(newPair[0].camera.up.length, closeTo(1, 1e-6));
        expect(
          newPair[0].camera.position.distanceTo(oldLeftPosition),
          greaterThan(1),
        );
      },
    );
  });
}

class _CustomCameraRig extends StereoHeadRig {
  final requestedEyes = <StereoEye>[];

  @override
  PerspectiveCamera eyeCamera(StereoEye eye, {double? fovRadiansY}) {
    requestedEyes.add(eye);
    final camera = super.eyeCamera(eye, fovRadiansY: fovRadiansY);
    camera.position.x += 10;
    camera.target.x += 10;
    return camera;
  }
}

class _CustomEyePositionRig extends StereoHeadRig {
  @override
  vm.Vector3 eyePosition(StereoEye eye) =>
      eye == StereoEye.left ? vm.Vector3(2, 3, 4) : vm.Vector3(5, 6, 7);
}
