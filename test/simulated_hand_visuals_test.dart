import 'dart:math';

import 'package:flutter/painting.dart';
import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;
import 'package:vrlizate_scene/src/simulated_hand_visuals.dart';

void main() {
  Mesh emptyMesh(vm.Vector3 size, PhysicallyBasedMaterial material) =>
      Mesh.primitives(primitives: const []);

  test('decorative hands cannot intercept a gaze ray', () {
    final root = Node();
    final hands = SimulatedHandVisuals(
      root,
      const Color(0xFF00E5FF),
      meshBuilder: emptyMesh,
    );
    hands.update(vm.Vector3.zero(), vm.Quaternion.identity(), 0);

    final ray = vm.Ray.originDirection(
      vm.Vector3.zero(),
      vm.Vector3(0.17, -0.22, -0.46).normalized(),
    );
    expect(root.children, hasLength(14));
    final pickCandidates = <Node>[];
    bool recordCandidate(Node node) {
      if (node != root) pickCandidates.add(node);
      return true;
    }

    expect(raycastNode(root, ray, where: recordCandidate), isNull);
    expect(pickCandidates, isEmpty);

    // Enabling a hand must make it a candidate in the same real raycast path.
    final palm = root.children.first;
    palm.raycastable = true;
    raycastNode(root, ray, where: recordCandidate);
    expect(pickCandidates, [palm]);
    hands.dispose();
    expect(root.children, isEmpty);
  });

  test('animation follows the viewer and reuses all node transforms', () {
    final root = Node();
    final hands = SimulatedHandVisuals(
      root,
      const Color(0xFF00E5FF),
      meshBuilder: emptyMesh,
    );
    final nodes = root.children.toList(growable: false);
    final transforms = nodes.map((node) => node.localTransform).toList();
    final eye = vm.Vector3(1, 1.6, 2);
    final orientation = vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), pi / 2);

    hands.update(eye, orientation, 0);
    final expectedPalm = orientation.rotated(vm.Vector3(0.17, -0.22, -0.46))
      ..add(eye);
    expect(nodes.first.position.distanceTo(expectedPalm), lessThan(1e-6));

    for (var frame = 1; frame <= 120; frame++) {
      hands.update(eye, orientation, frame / 60);
    }
    for (var index = 0; index < nodes.length; index++) {
      expect(nodes[index].localTransform, same(transforms[index]));
      expect(nodes[index].position.x.isFinite, isTrue);
    }
    expect(eye, vm.Vector3(1, 1.6, 2));
    hands.dispose();
  });
}
