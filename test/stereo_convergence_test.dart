import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;
import 'package:vrlizate_scene/vrlizate_scene.dart';

void main() {
  group('Stereo Optical Convergence', () {
    test('default convergence distance is 1.8m (comfort distance)', () {
      final rig = StereoHeadRig(eyeCenter: vm.Vector3(0, 1.6, 0), ipd: 0.064);
      expect(rig.convergenceDistance, closeTo(1.8, 1e-6));
      expect(rig.convergencePoint, isNotNull);
      // Gaze forward is (0, 0, -1), so convergence point is (0, 1.6, -1.8)
      expect(rig.convergencePoint!.x, closeTo(0.0, 1e-6));
      expect(rig.convergencePoint!.y, closeTo(1.6, 1e-6));
      expect(rig.convergencePoint!.z, closeTo(-1.8, 1e-6));
    });

    test('eyeCamera targets convergence point when convergenceDistance is finite', () {
      final rig = StereoHeadRig(
        eyeCenter: vm.Vector3(0, 1.6, 0),
        ipd: 0.064,
        convergenceDistance: 2.0,
      );

      final leftCam = rig.eyeCamera(StereoEye.left);
      final rightCam = rig.eyeCamera(StereoEye.right);

      final expectedConvergence = vm.Vector3(0, 1.6, -2.0);

      expect(leftCam.target.x, closeTo(expectedConvergence.x, 1e-6));
      expect(leftCam.target.y, closeTo(expectedConvergence.y, 1e-6));
      expect(leftCam.target.z, closeTo(expectedConvergence.z, 1e-6));

      expect(rightCam.target.x, closeTo(expectedConvergence.x, 1e-6));
      expect(rightCam.target.y, closeTo(expectedConvergence.y, 1e-6));
      expect(rightCam.target.z, closeTo(expectedConvergence.z, 1e-6));
    });

    test('convergenceAngleRadians matches arctan((ipd/2) / convergenceDistance)', () {
      final rig = StereoHeadRig(
        ipd: 0.064,
        convergenceDistance: 1.5,
      );

      final expectedAngle = atan2(0.032, 1.5);
      expect(rig.convergenceAngleRadians, closeTo(expectedAngle, 1e-6));
    });

    test('parallaxAtDistance demonstrates zero, crossed, and uncrossed parallax', () {
      final rig = StereoHeadRig(
        ipd: 0.064,
        convergenceDistance: 1.5,
      );

      // Zero parallax on the convergence plane (1.5m)
      expect(rig.parallaxAtDistance(1.5), closeTo(0.0, 1e-6));

      // Crossed parallax (closer than 1.5m -> negative)
      expect(rig.parallaxAtDistance(0.8), lessThan(0.0));

      // Uncrossed parallax (farther than 1.5m -> positive)
      expect(rig.parallaxAtDistance(3.0), greaterThan(0.0));
    });

    test('left and right gaze rays intersect exactly at the convergence point', () {
      final rig = StereoHeadRig(
        eyeCenter: vm.Vector3(0, 1.6, 0),
        ipd: 0.064,
        convergenceDistance: 2.0,
      );

      final leftRay = rig.leftGazeRay;
      final rightRay = rig.rightGazeRay;

      // Left ray origin is (-0.032, 1.6, 0)
      expect(leftRay.origin.x, closeTo(-0.032, 1e-6));
      expect(leftRay.origin.y, closeTo(1.6, 1e-6));

      // Right ray origin is (+0.032, 1.6, 0)
      expect(rightRay.origin.x, closeTo(0.032, 1e-6));
      expect(rightRay.origin.y, closeTo(1.6, 1e-6));

      final convPoint = rig.convergencePoint!;
      final distLeft = (convPoint - leftRay.origin).length;
      final distRight = (convPoint - rightRay.origin).length;

      final hitLeft = leftRay.origin + leftRay.direction * distLeft;
      final hitRight = rightRay.origin + rightRay.direction * distRight;

      expect(hitLeft.x, closeTo(convPoint.x, 1e-5));
      expect(hitLeft.y, closeTo(convPoint.y, 1e-5));
      expect(hitLeft.z, closeTo(convPoint.z, 1e-5));

      expect(hitRight.x, closeTo(convPoint.x, 1e-5));
      expect(hitRight.y, closeTo(convPoint.y, 1e-5));
      expect(hitRight.z, closeTo(convPoint.z, 1e-5));
    });

    test('null convergenceDistance preserves parallel camera configuration (infinity focus)', () {
      final rig = StereoHeadRig(
        eyeCenter: vm.Vector3(0, 1.6, 0),
        ipd: 0.064,
        convergenceDistance: null,
      );

      expect(rig.convergencePoint, isNull);
      expect(rig.convergenceAngleRadians, 0.0);

      final leftCam = rig.eyeCamera(StereoEye.left);
      final rightCam = rig.eyeCamera(StereoEye.right);

      // Left camera points strictly along forward (-Z): target is pos + forward
      expect(leftCam.target.x, closeTo(-0.032, 1e-6));
      expect(leftCam.target.z, closeTo(-1.0, 1e-6));

      // Right camera points strictly along forward (-Z): target is pos + forward
      expect(rightCam.target.x, closeTo(0.032, 1e-6));
      expect(rightCam.target.z, closeTo(-1.0, 1e-6));
    });
  });
}
