import 'dart:ui' show Size;

import 'package:flutter_scene/scene.dart' show PerspectiveProjection;
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;
import 'package:vrlizate_scene/src/vr_controller_feedback_visuals.dart';
import 'package:vrlizate_scene/vrlizate_scene.dart';

void main() {
  group('stereo eye projection', () {
    test('is a PerspectiveProjection so perspective-only passes stay on', () {
      // flutter_scene fits shadow cascades, god rays, depth of field and AO
      // only for `camera.projection is PerspectiveProjection`. A stereo eye
      // with convergence must not silently opt out of all of them.
      final rig = StereoHeadRig(
        eyeCenter: vm.Vector3(0, 1.6, 0),
        convergenceDistance: 1.8,
        stereoImageInset: 0.10,
      );
      for (final eye in StereoEye.values) {
        final projection = rig.eyeCamera(eye).projection;
        expect(projection, isA<PerspectiveProjection>());
        final perspective = projection as PerspectiveProjection;
        expect(perspective.fovRadiansY, rig.cameraRig.fovY);
        expect(perspective.near, greaterThan(0));
        expect(perspective.far, greaterThan(perspective.near));
      }
    });

    test('keeps the convergence shift after the base-class change', () {
      final rig = StereoHeadRig(
        eyeCenter: vm.Vector3(0, 1.6, 0),
        ipd: 0.064,
        convergenceDistance: 1.8,
        stereoImageInset: 0,
      );
      const eyeViewport = Size(200, 100);
      final point = rig.convergencePoint!;
      final left = rig
          .eyeCamera(StereoEye.left)
          .worldToScreen(point, eyeViewport);
      final right = rig
          .eyeCamera(StereoEye.right)
          .worldToScreen(point, eyeViewport);
      // Zero disparity at the convergence plane, in both eyes.
      expect(left!.dx, closeTo(100, 1e-4));
      expect(right!.dx, closeTo(100, 1e-4));
      // Only the horizontal term differs from the plain perspective matrix.
      final plain = PerspectiveProjection(
        fovRadiansY: rig.cameraRig.fovY,
        near:
            (rig.eyeCamera(StereoEye.left).projection as PerspectiveProjection)
                .near,
        far: (rig.eyeCamera(StereoEye.left).projection as PerspectiveProjection)
            .far,
      ).getProjectionMatrix(2.0);
      final shifted = rig
          .eyeCamera(StereoEye.left)
          .projection
          .getProjectionMatrix(2.0);
      for (var i = 0; i < 16; i++) {
        if (i == 8) continue;
        expect(shifted.storage[i], closeTo(plain.storage[i], 1e-9));
      }
      expect(shifted.storage[8], isNot(closeTo(plain.storage[8], 1e-9)));
    });
  });

  group('composed rig pitch', () {
    test('adds bodyPitch to the tracked head pitch within the clamp', () {
      final rig = StereoHeadRig();
      expect(rig.pitch, 0);
      rig.setPitch(0.4);
      expect(rig.pitch, closeTo(0.4, 1e-9));
      rig.bodyPitch = -0.6;
      expect(rig.pitch, closeTo(-0.2, 1e-9));
      expect(rig.forward.y, greaterThan(0), reason: 'net gaze is upward');
      rig.bodyPitch = 2.0;
      expect(rig.pitch, 1.45);
      expect(rig.right.y, closeTo(0, 1e-6), reason: 'horizon stays level');
    });

    test('bodyPitch alone bends the eye cameras and gaze ray', () {
      final rig = StereoHeadRig(eyeCenter: vm.Vector3(0, 1.6, 0));
      final level = rig.gazeRay.direction.clone();
      rig.bodyPitch = 0.5; // look down
      final down = rig.gazeRay.direction;
      expect(level.y, closeTo(0, 1e-9));
      expect(down.y, lessThan(-0.4));
      expect(rig.eyeCamera(StereoEye.left).forward.y, lessThan(-0.4));
      // Body yaw and pitch compose without roll.
      rig.bodyYaw = 1.1;
      expect(rig.right.y, closeTo(0, 1e-6));
      expect(rig.up.dot(rig.forward), closeTo(0, 1e-6));
    });

    test('controller feedback window follows the composed pitch', () {
      final rig = StereoHeadRig();
      // Head level, stick pushes the view 70° down: the controller (20° from
      // the feet) must show even though the tracked head pitch is zero.
      rig.bodyPitch = 70 * 3.141592653589793 / 180;
      expect(
        VrControllerFeedbackVisuals.gazeAngleFromFeetDeg(rig),
        closeTo(20, 1e-6),
      );
      expect(VrControllerFeedbackVisuals.isGazeTowardsController(rig), isTrue);
    });
  });
}
