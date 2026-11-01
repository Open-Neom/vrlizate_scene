import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;
import 'package:vrlizate_scene/vrlizate_scene.dart';

bool _isInsideAllPlanes(List<vm.Plane> planes, vm.Vector3 point) {
  for (final p in planes) {
    if (p.normal.dot(point) + p.constant < 0.0) {
      return false;
    }
  }
  return true;
}

void main() {
  group('VrPredictiveMotionCuller', () {
    test(
      'shifts optical centers ahead into gaze turn direction and contracts scissor during saccades',
      () {
        final rig = StereoHeadRig();
        final culler = VrPredictiveMotionCuller();

        culler.update(
          forward: rig.forward,
          screenRight: rig.screenRight,
          up: rig.up,
          eyeCenter: rig.eyeCenter,
          dtSeconds: 1 / 60,
          fovRadiansY: rig.cameraRig.fovY,
        );
        expect(culler.state.opticalCenterLeadOffset, ui.Offset.zero);
        expect(culler.state.saccadicScissorScale, 1.0);

        for (var i = 0; i < 6; i++) {
          rig.rotate(-0.04, 0.0); // 2.4 rad/s rightward (+screenRight)
          culler.update(
            forward: rig.forward,
            screenRight: rig.screenRight,
            up: rig.up,
            eyeCenter: rig.eyeCenter,
            dtSeconds: 1 / 60,
            fovRadiansY: rig.cameraRig.fovY,
          );
        }

        final sweepState = culler.state;
        expect(sweepState.screenAngularVelXRadPerSec, greaterThan(1.5));
        expect(sweepState.opticalCenterLeadOffset.dx, greaterThan(0.02));
        expect(sweepState.isSaccadicSweep, isTrue);
        expect(sweepState.saccadicScissorScale, lessThan(0.96));
        expect(sweepState.dynamicFarCullMeters, isNotNull);

        final shifted = culler.shiftOpticalCenters(const [
          ui.Offset(0.55, 0.50),
          ui.Offset(0.45, 0.50),
        ]);
        expect(shifted[0].dx, greaterThan(0.55));
        expect(shifted[1].dx, greaterThan(0.45));

        for (var i = 0; i < 24; i++) {
          culler.update(
            forward: rig.forward,
            screenRight: rig.screenRight,
            up: rig.up,
            eyeCenter: rig.eyeCenter,
            dtSeconds: 1 / 60,
            fovRadiansY: rig.cameraRig.fovY,
          );
        }
        expect(culler.state.saccadicScissorScale, greaterThan(0.99));
        expect(culler.state.dynamicFarCullMeters, isNull);
      },
    );

    test(
      'buildPredictiveEyeCullingPlanes keeps in-cone geometry and culls trailing/far geometry',
      () {
        final rig = StereoHeadRig();
        final eyePos = rig.eyePosition(StereoEye.left);
        final planes = VrPredictiveMotionCuller.buildPredictiveEyeCullingPlanes(
          eyePosition: eyePos,
          forward: rig.forward,
          screenRight: rig.screenRight,
          up: rig.up,
          fovRadiansY: math.pi / 3,
          fullEyeAspectRatio: 1.0,
          normalizedCropRect: const ui.Rect.fromLTRB(0.22, 0.10, 0.94, 0.90),
          dynamicFarCullMeters: 50.0,
        );

        expect(planes.length, 5);

        final centerAhead = eyePos + rig.forward * 5.0;
        expect(_isInsideAllPlanes(planes, centerAhead), isTrue);

        final trailingLeft =
            eyePos + rig.forward * 5.0 - rig.screenRight * 6.0;
        expect(_isInsideAllPlanes(planes, trailingLeft), isFalse);

        final beyondSaccadicFar = eyePos + rig.forward * 80.0;
        expect(_isInsideAllPlanes(planes, beyondSaccadicFar), isFalse);
      },
    );

    test(
      'cropStereoViewsToActiveLens attaches predictive cullingPlanes to stereo RenderViews',
      () {
        final rig = StereoHeadRig();
        final rawEyes = rig.buildStereoViews();
        final cropped = VrFixedFoveation.cropStereoViewsToActiveLens(
          rawEyes,
          viewportSize: const ui.Size(2400, 1080),
          widthFraction: 0.76,
          heightFraction: 0.84,
          cullingPlanesBuilder: (eyeIndex, cropRect, aspect) =>
              VrPredictiveMotionCuller.buildPredictiveEyeCullingPlanes(
                eyePosition: rig.eyePosition(
                  eyeIndex == 0 ? StereoEye.left : StereoEye.right,
                ),
                forward: rig.forward,
                screenRight: rig.screenRight,
                up: rig.up,
                fovRadiansY: rig.cameraRig.fovY,
                fullEyeAspectRatio: aspect,
                normalizedCropRect: cropRect,
                dynamicFarCullMeters: 60.0,
              ),
        );

        expect(cropped.length, 2);
        expect(cropped[0].cullingPlanes.length, 5);
        expect(cropped[1].cullingPlanes.length, 5);
      },
    );
  });
}
