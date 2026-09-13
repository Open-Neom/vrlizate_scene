import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;
import 'package:vrlizate/vrlizate.dart' show CameraRig;
import 'package:vrlizate_scene/vrlizate_scene.dart';
import 'package:vrlizate_scene/src/vr_scene_input_controller.dart';

void main() {
  test('vehicle heading composes with head pose and survives recenter', () {
    final rig = StereoHeadRig()..bodyYaw = .7;
    rig.setOrientation(.3, -.2);
    final expected = CameraRig()..setOrientation(1, -.2);
    expect(rig.forward.x, closeTo(expected.headTransform.forward.x, 1e-6));
    expect(rig.forward.y, closeTo(expected.headTransform.forward.y, 1e-6));
    rig.recenter();
    expect(rig.bodyYaw, .7);
    expect(rig.cameraRig.yaw, 0);
    expect(rig.right.y, closeTo(0, 1e-6));
  });

  test('seated/grid modes block walking without blocking pointing', () {
    final rig = StereoHeadRig();
    final input = VrSceneInputController(
      rig: rig,
      pick: (_) => null,
      activate: (_) {},
      recenter: () {},
      locomotionEnabled: false,
      lookInputEnabled: false,
    );
    input.handleEvent(
      VrInputEvent(
        type: VrInputType.navigate,
        source: VrInputSource.remotePhone,
        data: {'x': 1.0, 'y': 1.0, 'lookX': 1.0},
      ),
    );
    input.update(.1);
    expect(rig.eyeCenter, vm.Vector3.zero());
    expect(rig.cameraRig.yaw, 0);
    input.handleEvent(
      VrInputEvent(
        type: VrInputType.pointerMove,
        source: VrInputSource.remotePhone,
        data: {'forward': vm.Vector3(-1, 0, -1)},
      ),
    );
    expect(input.ray.direction.x, lessThan(0));
  });
}
