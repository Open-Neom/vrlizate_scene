import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;
import 'package:vrlizate_scene/src/vr_scene_input_controller.dart';
import 'package:vrlizate_scene/vrlizate_scene.dart';

void main() {
  test('jump elevation composes with tracked movement and both eye views', () {
    final rig = StereoHeadRig(eyeCenter: vm.Vector3(2, 1.6, 3));
    final trackedOffset = vm.Vector3(.2, .15, -.3);
    rig.applySpatialPose(
      translationOffset: trackedOffset,
      rotation: vm.Quaternion.identity(),
    );
    rig.locomotionVerticalOffset = .32;
    expect(rig.centerCamera().position.y, closeTo(2.07, 1e-6));
    for (final eye in StereoEye.values) {
      expect(rig.eyeCamera(eye).position.y, closeTo(2.07, 1e-6));
    }

    final nextTrackedOffset = vm.Vector3(.25, -.1, -.35);
    for (var sample = 0; sample < 3; sample++) {
      rig.applySpatialPose(
        translationOffset: nextTrackedOffset,
        rotation: vm.Quaternion.identity(),
      );
    }
    expect(rig.eyeCenter.y, closeTo(1.82, 1e-6));
    rig.locomotionVerticalOffset = 0;
    expect(rig.eyeCenter.x, closeTo(2.25, 1e-6));
    expect(rig.eyeCenter.y, closeTo(1.50, 1e-6));
    expect(rig.eyeCenter.z, closeTo(2.65, 1e-6));
  });

  test('repeated elevation cycles preserve the Float32 standing height', () {
    final rig = StereoHeadRig(eyeCenter: vm.Vector3(0, 1.63, 0));
    final standingHeight = rig.eyeCenter.y;
    for (var jump = 0; jump < 100; jump++) {
      for (var step = 1; step <= 33; step++) {
        final t = step / 33;
        rig.locomotionVerticalOffset = .32 * 4 * t * (1 - t);
      }
    }
    expect(rig.eyeCenter.y, standingHeight);
    expect(rig.locomotionVerticalOffset, 0);
  });

  test('reset clears pending elevation before a new world pose', () {
    final rig = StereoHeadRig(eyeCenter: vm.Vector3(0, 1.6, 0))
      ..locomotionVerticalOffset = .32;
    rig.reset();
    rig.eyeCenter = vm.Vector3(0, 1.8, 0);
    rig.locomotionVerticalOffset = 0;
    expect(rig.eyeCenter.y, closeTo(1.8, 1e-6));
    expect(
      () => rig.locomotionVerticalOffset = double.nan,
      throwsArgumentError,
    );
  });

  test('sprint changes stick displacement while preserving tracked height', () {
    final rig = StereoHeadRig(eyeCenter: vm.Vector3(0, 1.6, 0));
    final input = VrSceneInputController(
      rig: rig,
      pick: (_) => null,
      activate: (_) {},
      recenter: () {},
    );
    input.handleEvent(
      VrInputEvent(
        type: VrInputType.navigate,
        source: VrInputSource.touch,
        data: {'stickY': 1.0, 'edgeTurnEnabled': false},
      ),
    );
    input.update(.1);
    expect(rig.eyeCenter.z, closeTo(-.3, 1e-6));

    rig.locomotionVerticalOffset = .32;
    rig.locomotionSpeed = 4.5;
    input.update(.1);
    expect(rig.eyeCenter.z, closeTo(-.75, 1e-6));
    expect(rig.eyeCenter.y, closeTo(1.92, 1e-6));

    rig.locomotionSpeed = 3;
    rig.locomotionVerticalOffset = 0;
    input.update(.1);
    expect(rig.eyeCenter.z, closeTo(-1.05, 1e-6));
    expect(rig.eyeCenter.y, closeTo(1.6, 1e-6));
  });
}
