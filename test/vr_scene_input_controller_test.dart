import 'dart:ui' show Size;

import 'package:flutter_scene/scene.dart' show Node;
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;
import 'package:vrlizate_scene/src/vr_scene_input_controller.dart';
import 'package:vrlizate_scene/vrlizate_scene.dart';

void main() {
  test('one consumed action reaches only one scene; aliases do not select', () {
    final arbiter = VrInputArbiter();
    final node = Node(name: 'action');
    var first = 0;
    var second = 0;
    VrSceneInputController controller(void Function(Node) activate) =>
        VrSceneInputController(
          rig: StereoHeadRig(),
          pick: (_) => node,
          activate: activate,
          recenter: () {},
        );
    final a = controller((_) => first++);
    final b = controller((_) => second++);
    arbiter.addListener(a.handleEvent);
    arbiter.addListener(b.handleEvent);
    arbiter.emit(type: VrInputType.buttonA, source: VrInputSource.remotePhone);
    arbiter.emit(type: VrInputType.buttonR, source: VrInputSource.remotePhone);
    arbiter.emit(type: VrInputType.select, source: VrInputSource.remotePhone);
    expect(first, 1);
    expect(second, 0);
    arbiter.pool.assertNoLeaks();
    arbiter.dispose();
  });

  test(
    'HOME wins before gameplay; normal controls remain consumable by demo',
    () {
      final arbiter = VrInputArbiter();
      final home = Node(name: 'HOME');
      final button = Node(name: 'button');
      var current = home;
      var homeActions = 0;
      var sceneActions = 0;
      var gameplayActions = 0;
      final input = VrSceneInputController(
        rig: StereoHeadRig(),
        pick: (_) => current,
        isSystemNode: (node) => node == home,
        activate: (node) => node == home ? homeActions++ : sceneActions++,
        recenter: () {},
      );
      // Match the actual parent-demo then nested-scene registration order.
      arbiter.addListener((event) {
        if (!event.handled && event.type == VrInputType.select) {
          gameplayActions++;
          event.consume();
        }
      });
      arbiter.addListener(input.handleSystemEvent, first: true);
      arbiter.addListener(input.handleEvent);
      arbiter.emit(type: VrInputType.select, source: VrInputSource.remotePhone);
      expect(homeActions, 1);
      expect(gameplayActions, 0);
      current = button;
      arbiter.emit(type: VrInputType.select, source: VrInputSource.remotePhone);
      expect(gameplayActions, 1);
      expect(sceneActions, 0);
      arbiter.dispose();
    },
  );

  test('laser trigger is edge-triggered; X/Y/L2 do not activate', () {
    final arbiter = VrInputArbiter();
    var selected = 0;
    final input = VrSceneInputController(
      rig: StereoHeadRig(),
      pick: (_) => Node(name: 'target'),
      activate: (_) => selected++,
      recenter: () {},
    );
    arbiter.addListener(input.handleEvent);
    final driver = VrGamepadDriver();
    arbiter.attachDriver(driver);
    driver.updateButton(VrGamepadButton.x, true);
    driver.updateButton(VrGamepadButton.y, true);
    driver.updateTrigger(VrGamepadButton.l2, 1);
    expect(selected, 0);
    driver.updateTrigger(VrGamepadButton.r2, .5);
    driver.updateTrigger(VrGamepadButton.r2, 1);
    expect(selected, 1);
    driver.updateTrigger(VrGamepadButton.r2, 0);
    driver.updateTrigger(VrGamepadButton.r2, 1);
    expect(selected, 2);
    arbiter.dispose();
  });

  test('fresh remote pose selects its ray rather than cached head gaze', () {
    final left = Node(name: 'left');
    final front = Node(name: 'front');
    Node? selected;
    final arbiter = VrInputArbiter();
    final input = VrSceneInputController(
      rig: StereoHeadRig(),
      pick: (ray) => ray.direction.x < -.5 ? left : front,
      activate: (node) => selected = node,
      recenter: () {},
    );
    arbiter.addListener(input.handleEvent);
    final direction = vm.Vector3(-1, 0, -1);
    arbiter.emit(
      type: VrInputType.pointerMove,
      source: VrInputSource.remotePhone,
      data: {'forward': direction},
    );
    direction.setValues(0, 0, -1); // The driver payload is reusable/borrowed.
    arbiter.emit(type: VrInputType.select, source: VrInputSource.remotePhone);
    expect(selected, same(left));
    expect(input.ray.origin, input.rig.eyeCenter);
    input.update(.51);
    expect(input.pointerActive, isFalse);
    arbiter.emit(type: VrInputType.select, source: VrInputSource.remotePhone);
    expect(selected, same(front));
    arbiter.pool.assertNoLeaks();
    arbiter.dispose();
  });

  test('misses and already handled actions do not activate or consume', () {
    final input = VrSceneInputController(
      rig: StereoHeadRig(),
      pick: (_) => null,
      activate: (_) => fail('unexpected activation'),
      recenter: () {},
    );
    final miss = VrInputEvent(
      type: VrInputType.select,
      source: VrInputSource.touch,
    );
    input.handleEvent(miss);
    expect(miss.handled, isFalse);
    final handled = VrInputEvent(
      type: VrInputType.select,
      source: VrInputSource.touch,
      data: {'handled': true},
    );
    input.handleEvent(handled);
    expect(handled.handled, isTrue);
  });

  test('remote packet rates do not change movement distance', () {
    double travel(int packetsPerSecond) {
      final arbiter = VrInputArbiter();
      final input = VrSceneInputController(
        rig: StereoHeadRig(),
        pick: (_) => null,
        activate: (_) {},
        recenter: () {},
      );
      arbiter.addListener(input.handleEvent);
      for (var frame = 0; frame < 120; frame++) {
        if (frame % (120 ~/ packetsPerSecond) == 0) {
          arbiter.emit(
            type: VrInputType.navigate,
            source: VrInputSource.remotePhone,
            data: {'y': 1.0},
          );
        }
        input.update(1 / 120);
      }
      final distance = input.rig.eyeCenter.length;
      expect(input.rig.eyeCenter.z, lessThan(0));
      arbiter.dispose();
      return distance;
    }

    expect(travel(20), closeTo(3, .0001));
    expect(travel(60), closeTo(3, .0001));
    expect(travel(120), closeTo(3, .0001));
  });

  test(
    'right strafe projects right; right stick turns without translation',
    () {
      final rig = StereoHeadRig();
      final camera = rig.eyeCamera(StereoEye.left);
      final before = camera.worldToScreen(
        vm.Vector3(0, 0, -1.8),
        const Size(1000, 1000),
      )!;
      final input = VrSceneInputController(
        rig: rig,
        pick: (_) => null,
        activate: (_) {},
        recenter: () {},
      );
      input.handleEvent(
        VrInputEvent(
          type: VrInputType.navigate,
          source: VrInputSource.gamepad,
          data: {'stick': VrGamepadStick.left, 'x': 1},
        ),
      );
      input.update(.1);
      final after = camera.worldToScreen(
        vm.Vector3(rig.eyeCenter.x, 0, -1.8),
        const Size(1000, 1000),
      )!;
      expect(after.dx, greaterThan(before.dx));
      input.reset();
      final position = rig.eyeCenter.clone();
      input.handleEvent(
        VrInputEvent(
          type: VrInputType.navigate,
          source: VrInputSource.gamepad,
          data: {'stick': VrGamepadStick.right, 'x': 1, 'y': 1},
        ),
      );
      input.update(.1);
      expect(rig.eyeCenter, position);
      expect(rig.forward.dot(rig.screenRight), closeTo(0, .0001));
      expect(rig.cameraRig.yaw, lessThan(0));
      expect(rig.cameraRig.pitch, lessThan(0));
    },
  );

  test('recenter clears remote state and preserves world position', () {
    final rig = StereoHeadRig(eyeCenter: vm.Vector3(1, 2, 3))..rotate(1, 0);
    var recentered = 0;
    final input = VrSceneInputController(
      rig: rig,
      pick: (_) => null,
      activate: (_) {},
      recenter: () {
        recentered++;
        rig.recenter();
      },
    );
    input.handleEvent(
      VrInputEvent(
        type: VrInputType.pointerMove,
        source: VrInputSource.remotePhone,
        data: {'forward': vm.Vector3(1, 0, 0)},
      ),
    );
    final event = VrInputEvent(
      type: VrInputType.recenter,
      source: VrInputSource.remotePhone,
    );
    input.handleSystemEvent(event);
    input.handleEvent(event);
    expect(recentered, 1);
    expect(event.handled, isTrue);
    expect(input.pointerActive, isFalse);
    expect(rig.eyeCenter, vm.Vector3(1, 2, 3));
    expect(rig.cameraRig.yaw, 0);
  });
}
