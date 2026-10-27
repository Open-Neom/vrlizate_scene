import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;
import 'package:vrlizate_scene/src/vr_scene_input_controller.dart';
import 'package:vrlizate_scene/vrlizate_scene.dart';

VrInputEvent _axes(
  double x,
  double y, {
  VrInputSource source = VrInputSource.remotePhone,
  Object? stick,
  bool active = true,
}) => VrInputEvent(
  type: VrInputType.navigate,
  source: source,
  active: active,
  data: {
    if (stick != null) 'stick': stick,
    'x': x,
    'y': y,
    if (source == VrInputSource.remotePhone) ...{
      'stickX': x,
      'stickY': y,
      'moveAtEdge': true,
      'lookX': .8,
      'lookY': .7,
    },
  },
);

void main() {
  test(
    'scene modal blocks motion, retains laser/head pose, and requires held-stick release',
    () {
      final rig = StereoHeadRig(eyeCenter: vm.Vector3(0, 1.6, 0));
      final scene = VrSceneInputController(
        rig: rig,
        pick: (_) => null,
        activate: (_) {},
        recenter: () {},
      );
      void dispatch(VrInputEvent event, {bool consumed = true}) {
        scene.handleSystemEvent(event);
        if (consumed) event.consume();
        scene.handleEvent(event);
        scene.update(.1);
      }

      scene.locomotionEnabled = scene.lookInputEnabled = false;
      dispatch(_axes(1, 1));
      expect(rig.eyeCenter, vm.Vector3(0, 1.6, 0));
      expect(rig.yaw, 0);
      expect(rig.pitch, 0);
      rig.rotate(.4, .1);
      dispatch(
        VrInputEvent(
          type: VrInputType.pointerMove,
          source: VrInputSource.remotePhone,
          data: {'relativeToHead': true, 'laserX': .3, 'laserY': .1},
        ),
      );
      expect(scene.pointerActive, isTrue);
      expect(rig.yaw, closeTo(.4, 1e-8));
      final position = rig.eyeCenter.clone(), yaw = rig.yaw, pitch = rig.pitch;
      scene.locomotionEnabled = scene.lookInputEnabled = true;
      for (var i = 0; i < 5; i++) dispatch(_axes(1, 1), consumed: false);
      expect(rig.eyeCenter, position);
      expect(rig.yaw, yaw);
      expect(rig.pitch, pitch);
      dispatch(_axes(0, 0, active: false), consumed: false);
      dispatch(_axes(1, 1), consumed: false);
      expect(rig.eyeCenter, isNot(position));
      expect(rig.yaw, isNot(yaw));
      expect(rig.pitch, isNot(pitch));
    },
  );

  test(
    'centered modal close accepts next push and sticks re-arm independently',
    () {
      final rig = StereoHeadRig(eyeCenter: vm.Vector3(0, 1.6, 0));
      final scene = VrSceneInputController(
        rig: rig,
        pick: (_) => null,
        activate: (_) {},
        recenter: () {},
      );
      void dispatch(VrInputEvent event) {
        scene.handleSystemEvent(event);
        scene.handleEvent(event);
        scene.update(.1);
      }

      scene.locomotionEnabled = scene.lookInputEnabled = false;
      dispatch(
        _axes(1, 0, source: VrInputSource.gamepad, stick: VrGamepadStick.left),
      );
      dispatch(
        _axes(1, 0, source: VrInputSource.gamepad, stick: VrGamepadStick.right),
      );
      scene.locomotionEnabled = scene.lookInputEnabled = true;
      dispatch(
        _axes(
          0,
          0,
          source: VrInputSource.gamepad,
          stick: VrGamepadStick.right,
          active: false,
        ),
      );
      dispatch(
        _axes(1, 0, source: VrInputSource.gamepad, stick: VrGamepadStick.left),
      );
      expect(rig.eyeCenter, vm.Vector3(0, 1.6, 0));
      dispatch(
        _axes(1, 0, source: VrInputSource.gamepad, stick: VrGamepadStick.right),
      );
      expect(rig.yaw, isNot(0));
      dispatch(
        _axes(
          0,
          0,
          source: VrInputSource.gamepad,
          stick: VrGamepadStick.left,
          active: false,
        ),
      );
      scene.locomotionEnabled = false;
      scene.locomotionEnabled = true;
      dispatch(
        _axes(1, 0, source: VrInputSource.gamepad, stick: VrGamepadStick.left),
      );
      expect(rig.eyeCenter, isNot(vm.Vector3(0, 1.6, 0)));
    },
  );
}
