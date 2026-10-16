import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:vrlizate_scene/src/vr_scene_input_controller.dart';
import 'package:vrlizate_scene/vrlizate_scene.dart';

VrSceneInputController controller() => VrSceneInputController(
  rig: StereoHeadRig(),
  pick: (_) => null,
  activate: (_) {},
  recenter: () {},
);

void move(
  VrSceneInputController input,
  double x,
  double y, {
  bool? atEdge,
  bool enabled = true,
  VrInputSource source = VrInputSource.gamepad,
}) => input.handleEvent(
  VrInputEvent(
    type: VrInputType.navigate,
    source: source,
    data: {
      'stick': VrGamepadStick.left,
      'x': x,
      'y': y,
      'moveAtEdge': atEdge,
      'edgeTurnEnabled': enabled,
    },
    active: x != 0 || y != 0,
  ),
);

void frames(VrSceneInputController input, int count, [int hz = 60]) {
  for (var i = 0; i < count; i++) {
    input.update(1 / hz);
  }
}

void main() {
  test('rear rim takes backward steps then completes a single half turn', () {
    final input = controller();
    move(input, 0, -.5, atEdge: true);
    frames(input, 30);
    expect(input.rig.bodyYaw, 0);
    expect(input.rig.eyeCenter.z, closeTo(.75, 1e-5));
    frames(input, 240);
    expect(input.rig.bodyYaw, closeTo(-math.pi, .002));
    expect(input.rig.forward.z, closeTo(1, 1e-5));
    expect(input.rig.eyeCenter.x, closeTo(0, 1e-5));
    expect(input.rig.eyeCenter.z, closeTo(6.75, 1e-4));
    frames(input, 180);
    expect(input.rig.bodyYaw, closeTo(-math.pi, .002));
    expect(input.rig.eyeCenter.z, greaterThan(6.75));
  });

  test('right and left rim finish facing their original travel direction', () {
    for (final x in [-1.0, 1.0]) {
      final input = controller();
      final travel = input.rig.screenRight * x;
      move(input, x, 0);
      frames(input, 240);
      expect(input.rig.bodyYaw, closeTo(-x * math.pi / 2, .002));
      expect(input.rig.forward.dot(travel), closeTo(1, 1e-5));
      expect(input.rig.eyeCenter.z, closeTo(0, 1e-5));
    }
  });

  test('partial stick and digital movement preserve strafing', () {
    for (final digital in [false, true]) {
      final input = controller();
      move(input, digital ? 1 : .5, 0, enabled: !digital);
      frames(input, 240);
      expect(input.rig.bodyYaw, 0);
      expect(input.rig.eyeCenter.x.abs(), greaterThan(5));
    }
  });

  test('physical head tracking stays free throughout the body turn', () {
    final input = controller();
    move(input, 0, -1);
    for (var i = 0; i < 300; i++) {
      input.rig.cameraRig.rotate(.4 - input.rig.cameraRig.yaw, 0);
      input.update(1 / 60);
    }
    expect(input.rig.cameraRig.yaw, closeTo(.4, 1e-9));
    expect(input.rig.bodyYaw, closeTo(-math.pi, .002));
    expect(input.rig.yaw, closeTo(-math.pi + .4, .002));
  });

  test('manual look cancels assist until the left stick is released', () {
    final input = controller();
    move(input, 0, -1);
    frames(input, 60);
    expect(input.rig.bodyYaw, lessThan(0));
    input.handleEvent(
      VrInputEvent(
        type: VrInputType.navigate,
        source: VrInputSource.gamepad,
        data: {'stick': VrGamepadStick.right, 'x': .5, 'y': 0},
      ),
    );
    frames(input, 1);
    final stopped = input.rig.bodyYaw;
    input.handleEvent(
      VrInputEvent(
        type: VrInputType.navigate,
        source: VrInputSource.gamepad,
        data: {'stick': VrGamepadStick.right},
        active: false,
      ),
    );
    frames(input, 180);
    expect(input.rig.bodyYaw, stopped);
    move(input, 0, 0);
    frames(input, 1);
    move(input, 0, -1);
    frames(input, 90);
    expect(input.rig.bodyYaw, lessThan(stopped));
  });

  test('remote timeout and disabled seated locomotion cannot keep turning', () {
    final input = controller();
    move(input, 0, -1, atEdge: true, source: VrInputSource.remotePhone);
    frames(input, 240);
    expect(input.rig.bodyYaw, 0);
    input.locomotionEnabled = false;
    move(input, 0, -1);
    final position = input.rig.eyeCenter.clone();
    frames(input, 240);
    expect(input.rig.bodyYaw, 0);
    expect(input.rig.eyeCenter, position);
  });

  test('30, 60 and 120Hz finish at the same heading and travel distance', () {
    for (final hz in [30, 60, 120]) {
      final input = controller();
      move(input, 0, -1);
      frames(input, hz * 5, hz);
      expect(input.rig.bodyYaw, closeTo(-math.pi, .002));
      expect(input.rig.eyeCenter.z, closeTo(15, .0002));
    }
  });
}
