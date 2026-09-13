import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;
import 'package:vrlizate/vrlizate.dart'
    show VrInputArbiter, VrInputSource, VrInputType;
import 'package:vrlizate_scene/src/vr_scene_pointer_interaction.dart';
import 'package:vrlizate_scene/src/vr_scene_input_controller.dart';
import 'package:vrlizate_scene/vrlizate_scene.dart'
    show StereoHeadRig, VrViewerProfile;

SceneRaycastHit hit(Node node, double distance) => SceneRaycastHit(
  node: node,
  distance: distance,
  worldPoint: vm.Vector3(0, 0, -distance),
  worldNormal: vm.Vector3(0, 0, 1),
  uv: null,
  barycentrics: vm.Vector3(1, 0, 0),
  triangleIndex: 0,
  primitiveIndex: 0,
);

void main() {
  test(
    'legacy gameplay keeps activation while pointer gets actual surface depth',
    () {
      final resolver = VrScenePointerResolver();
      final geometry = Node(name: 'game_target');
      var depth = 5.0;
      var selections = 0;
      var geometryQueries = 0;
      Node? resolve({SceneRaycastHit? system, bool active = true}) =>
          resolver.resolve(
            systemHit: system,
            gazeEnabled: false,
            pointerActive: active,
            pickSelectable: () {
              selections++;
              return hit(geometry, 2);
            },
            pickGeometry: () {
              geometryQueries++;
              return hit(geometry, depth);
            },
          );
      expect(resolve(), isNull);
      expect(resolver.distance, 5);
      depth = .8;
      expect(resolve(), isNull);
      expect(resolver.distance, .8);
      expect(selections, 0);
      final home = Node(name: 'HOME');
      expect(resolve(system: hit(home, 1.5)), same(home));
      expect(resolver.distance, 1.5);
      expect(geometryQueries, 2);
      expect(resolve(active: false), isNull);
      expect(resolver.distance, 1.8);
      expect(geometryQueries, 2);
    },
  );

  test('native selection and pointer depth share the actionable hit', () {
    final resolver = VrScenePointerResolver();
    final button = Node(name: 'button');
    expect(
      resolver.resolve(
        systemHit: null,
        gazeEnabled: true,
        pointerActive: true,
        pickSelectable: () => hit(button, 3),
        pickGeometry: () => throw StateError('extra raycast'),
      ),
      same(button),
    );
    expect(resolver.distance, 3);
  });

  test(
    'temple fallback submits one canonical event and HOME never falls through',
    () {
      final arbiter = VrInputArbiter();
      Node? target;
      var homeActions = 0;
      var gameActions = 0;
      var eventCount = 0;
      final input = VrSceneInputController(
        rig: StereoHeadRig(),
        pick: (_) => target,
        isSystemNode: (_) => true,
        activate: (_) => homeActions++,
        recenter: () {},
      );
      arbiter.addListener(input.handleSystemEvent, first: true);
      arbiter.addListener((event) {
        if (event.type == VrInputType.select) {
          eventCount++;
          expect(event.source, VrInputSource.templeTap);
          if (!event.handled) gameActions++;
        }
      });
      void dispatch() => dispatchVrSceneTempleTap(
        pick: () => target,
        arbiter: arbiter,
        activate: (_) => fail('bypassed arbiter'),
        onUnhandled: () => arbiter.emit(
          type: VrInputType.select,
          source: VrInputSource.templeTap,
        ),
      );
      dispatch();
      expect(eventCount, 1);
      expect(gameActions, 1);
      target = Node(name: 'HOME');
      dispatch();
      expect(eventCount, 2);
      expect(gameActions, 1);
      expect(homeActions, 1);
      arbiter.pool.assertNoLeaks();
      arbiter.dispose();
    },
  );

  test(
    'temple honors higher-priority control and supports standalone scenes',
    () {
      final arbiter = VrInputArbiter();
      var activations = 0;
      final node = Node(name: 'target');
      arbiter.addListener((_) => activations++);
      arbiter.markActive(VrInputSource.remotePhone);
      dispatchVrSceneTempleTap(
        pick: () => node,
        arbiter: arbiter,
        activate: (_) => activations++,
      );
      expect(activations, 0);
      dispatchVrSceneTempleTap(
        pick: () => node,
        activate: (_) => activations++,
      );
      expect(activations, 1);
      arbiter.pool.assertNoLeaks();
      arbiter.dispose();
    },
  );

  test(
    'profile applies projection, preserves pose and respects explicit overrides',
    () {
      final rig = StereoHeadRig()..eyeCenter = vm.Vector3(2, 1.5, -4);
      final originalFov = rig.cameraRig.fovY;
      final originalInset = rig.stereoImageInset;
      final binding = VrSceneViewerProfileBinding();
      final profile = VrViewerProfile(
        ipdMeters: .060,
        fovYRadians: 1.2,
        stereoImageInset: .2,
        convergenceDistanceMeters: 2.5,
      );
      binding.apply(rig, profile, explicitIpd: .067, explicitInset: .12);
      expect(rig.ipd, .067);
      expect(rig.stereoImageInset, .12);
      expect(rig.cameraRig.fovY, 1.2);
      expect(rig.convergenceDistance, 2.5);
      expect(rig.eyeCenter, vm.Vector3(2, 1.5, -4));
      binding.apply(rig, profile);
      expect(rig.ipd, .060);
      expect(rig.stereoImageInset, .2);
      binding.apply(rig, null);
      expect(rig.cameraRig.fovY, originalFov);
      expect(rig.stereoImageInset, originalInset);
    },
  );
}
