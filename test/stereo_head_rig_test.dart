import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;
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
  });
}
