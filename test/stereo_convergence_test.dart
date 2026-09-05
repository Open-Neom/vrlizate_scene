import 'dart:math';
import 'dart:ui' show Offset, Size;

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

    test(
      'image inset moves projected eye images toward the display center',
      () {
        final rig = StereoHeadRig(
          eyeCenter: vm.Vector3(0, 1.6, 0),
          stereoImageInset: 0.10,
        );
        final point = rig.convergencePoint!;
        const eyeViewport = Size(100, 100);

        final left = rig
            .eyeCamera(StereoEye.left)
            .worldToScreen(point, eyeViewport);
        final right = rig
            .eyeCamera(StereoEye.right)
            .worldToScreen(point, eyeViewport);

        expect(left, isNotNull);
        expect(right, isNotNull);
        expect(left!.dx, closeTo(55, 1e-5));
        expect(right!.dx, closeTo(45, 1e-5));
      },
    );

    test('eye cameras stay parallel when convergenceDistance is finite', () {
      final rig = StereoHeadRig(
        eyeCenter: vm.Vector3(0, 1.6, 0),
        ipd: 0.064,
        convergenceDistance: 2.0,
      );

      final leftCam = rig.eyeCamera(StereoEye.left);
      final rightCam = rig.eyeCamera(StereoEye.right);

      expect(leftCam.forward.distanceTo(rig.forward), lessThan(1e-6));
      expect(rightCam.forward.distanceTo(rig.forward), lessThan(1e-6));
      expect(leftCam.forward.distanceTo(rightCam.forward), lessThan(1e-6));
    });

    test(
      'convergenceAngleRadians matches arctan((ipd/2) / convergenceDistance)',
      () {
        final rig = StereoHeadRig(ipd: 0.064, convergenceDistance: 1.5);

        final expectedAngle = atan2(0.032, 1.5);
        expect(rig.convergenceAngleRadians, closeTo(expectedAngle, 1e-6));
      },
    );

    test(
      'parallaxAtDistance demonstrates zero, crossed, and uncrossed parallax',
      () {
        final rig = StereoHeadRig(ipd: 0.064, convergenceDistance: 1.5);

        // Zero parallax on the convergence plane (1.5m)
        expect(rig.parallaxAtDistance(1.5), closeTo(0.0, 1e-6));

        // Crossed parallax (closer than 1.5m -> negative)
        expect(rig.parallaxAtDistance(0.8), lessThan(0.0));

        // Uncrossed parallax (farther than 1.5m -> positive)
        expect(rig.parallaxAtDistance(3.0), greaterThan(0.0));
      },
    );

    test(
      'left and right gaze rays intersect exactly at the convergence point',
      () {
        final rig = StereoHeadRig(
          eyeCenter: vm.Vector3(0, 1.6, 0),
          ipd: 0.064,
          convergenceDistance: 2.0,
        );

        final leftRay = rig.leftGazeRay;
        final rightRay = rig.rightGazeRay;

        // Renderer screen-right is world -X for an identity head pose.
        expect(leftRay.origin.x, closeTo(0.032, 1e-6));
        expect(leftRay.origin.y, closeTo(1.6, 1e-6));

        expect(rightRay.origin.x, closeTo(-0.032, 1e-6));
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
      },
    );

    test(
      'null convergenceDistance preserves parallel camera configuration (infinity focus)',
      () {
        final rig = StereoHeadRig(
          eyeCenter: vm.Vector3(0, 1.6, 0),
          ipd: 0.064,
          convergenceDistance: null,
        );

        expect(rig.convergencePoint, isNull);
        expect(rig.convergenceAngleRadians, 0.0);
        expect(rig.parallaxAtDistance(0.8), lessThan(0));

        final leftCam = rig.eyeCamera(StereoEye.left);
        final rightCam = rig.eyeCamera(StereoEye.right);

        // Left camera points strictly along forward (-Z): target is pos + forward
        expect(leftCam.target.x, closeTo(0.032, 1e-6));
        expect(leftCam.target.z, closeTo(-1.0, 1e-6));

        // Right camera points strictly along forward (-Z): target is pos + forward
        expect(rightCam.target.x, closeTo(-0.032, 1e-6));
        expect(rightCam.target.z, closeTo(-1.0, 1e-6));
      },
    );

    test(
      'projected near/far disparity has physical crossed/uncrossed signs',
      () {
        final rig = StereoHeadRig(eyeCenter: vm.Vector3(0, 1.6, 0));
        for (final size in const [Size(1200, 1080), Size(1000, 800)]) {
          for (final fov in [0.9, 1.2]) {
            final left = rig.eyeCamera(StereoEye.left, fovRadiansY: fov);
            final right = rig.eyeCamera(StereoEye.right, fovRadiansY: fov);
            final insetDisparity = size.width * rig.stereoImageInset;
            double disparity(double depth) {
              final point = rig.eyeCenter + rig.forward * depth;
              return left.worldToScreen(point, size)!.dx -
                  right.worldToScreen(point, size)!.dx -
                  insetDisparity;
            }

            // A near object appears to the RIGHT in the left image (crossed).
            expect(disparity(0.8), greaterThan(0));
            expect(disparity(1.8), closeTo(0, 1e-4));
            expect(disparity(3), lessThan(0));
          }
        }
      },
    );

    test(
      'off-axis panel corners have no vertical disparity at rotated poses',
      () {
        const size = Size(1200, 1080);
        final rig = StereoHeadRig(eyeCenter: vm.Vector3(2, 1.6, -3));
        for (final rotation in [
          vm.Quaternion.identity(),
          vm.Quaternion.euler(0.7, 0.3, 0.2),
        ]) {
          rig.cameraRig.rotation = rotation;
          final left = rig.eyeCamera(StereoEye.left);
          final right = rig.eyeCamera(StereoEye.right);
          for (final depth in [0.8, 1.8, 3.0]) {
            for (final x in [-0.7, 0.0, 0.7]) {
              for (final y in [-0.45, 0.0, 0.45]) {
                final point =
                    rig.eyeCenter +
                    rig.forward * depth +
                    rig.screenRight * x +
                    rig.up * y;
                final l = left.worldToScreen(point, size)!;
                final r = right.worldToScreen(point, size)!;
                expect(l.dy, closeTo(r.dy, 1e-3));
                final disparity =
                    l.dx - r.dx - size.width * rig.stereoImageInset;
                if (depth == 1.8) {
                  expect(disparity, closeTo(0, 1e-3));
                } else if (depth < 1.8) {
                  expect(disparity, greaterThan(0));
                } else {
                  expect(disparity, lessThan(0));
                }
              }
            }
          }
        }
      },
    );

    test('rays through inset-adjusted reticles agree with eye gaze rays', () {
      final rig = StereoHeadRig(eyeCenter: vm.Vector3(2, 1.6, -3));
      rig.cameraRig.rotation = vm.Quaternion.euler(0.7, 0.3, 0.2);
      const size = Size(1200, 1080);
      for (final eye in StereoEye.values) {
        final inset = eye == StereoEye.left
            ? rig.stereoImageInset
            : -rig.stereoImageInset;
        final ray = rig
            .eyeCamera(eye)
            .screenPointToRay(
              Offset(size.width * (1 + inset) / 2, size.height / 2),
              size,
            );
        expect(
          ray.direction.normalized().distanceTo(rig.eyeGazeRay(eye).direction),
          lessThan(1e-4),
        );
      }
    });

    test(
      'zero IPD removes depth disparity and non-finite convergence is disabled',
      () {
        const size = Size(1200, 1080);
        final rig = StereoHeadRig(ipd: 0, stereoImageInset: 0);
        final point = vm.Vector3(0.2, 0.1, -0.8);
        expect(
          rig.eyeCamera(StereoEye.left).worldToScreen(point, size),
          rig.eyeCamera(StereoEye.right).worldToScreen(point, size),
        );
        for (final distance in [double.infinity, double.nan, 0.0, -1.0]) {
          rig.convergenceDistance = distance;
          expect(rig.convergencePoint, isNull);
          expect(rig.convergenceAngleRadians, 0);
          expect(
            rig
                .eyeCamera(StereoEye.left)
                .worldToScreen(point, size)!
                .dx
                .isFinite,
            isTrue,
          );
        }
      },
    );
  });
}
