import 'dart:math' as math;

import 'package:flutter_scene/scene.dart' as fs;
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;
import 'package:vrlizate_avatar/vrlizate_avatar.dart';
import 'package:vrlizate_scene/vrlizate_scene.dart';

void main() {
  group('VrLimbKinematics & VrFirstPersonFeetRig', () {
    test('capsuleTransformBetween centers and aligns capsule between endpoints', () {
      final a = vm.Vector3(0, 1, 0);
      final b = vm.Vector3(0, 1, -2);
      final m = VrLimbKinematics.capsuleTransformBetween(
        a,
        b,
        baseRadius: 0.05,
      );
      final pos = m.getTranslation();
      expect(pos.x, closeTo(0.0, 1e-6));
      expect(pos.y, closeTo(1.0, 1e-6));
      expect(pos.z, closeTo(-1.0, 1e-6));
    });

    test('VrFirstPersonFeetRig computes alternating left and right stride', () {
      final (left, right) = VrFirstPersonFeetRig.evaluate(
        bodyGroundPosition: vm.Vector3(0, 0, 0),
        yawRadians: 0.0,
        phaseRadians: math.pi / 2,
        amplitude: 1.0,
      );
      expect(left.position.x, lessThan(0));
      expect(right.position.x, greaterThan(0));
      expect(left.position.z, isNot(closeTo(right.position.z, 1e-3)));
    });
  });

  group('VrExplodedSceneRig & VrGrowthSchedule', () {
    test('explodes parts radially, scans vertically, and resets cleanly', () {
      final root = fs.Node(name: 'keyboard');
      final cap = fs.Node(
        name: 'keycap',
        localTransform: vm.Matrix4.translationValues(0, 0.5, 0),
      );
      final pcb = fs.Node(
        name: 'pcb',
        localTransform: vm.Matrix4.translationValues(0, 0.0, 0),
      );
      root..add(cap)..add(pcb);

      final rig = VrExplodedSceneRig(
        root: root,
        parts: [
          VrExplodablePart(
            id: 'keycap',
            node: cap,
            explodeVector: vm.Vector3(0, 0.4, 0),
          ),
          VrExplodablePart(
            id: 'pcb',
            node: pcb,
            explodeVector: vm.Vector3(0, -0.2, 0),
          ),
        ],
      );

      rig.setGlobalExplode(1.0);
      expect(cap.localTransform.getTranslation().y, closeTo(0.9, 1e-6));
      expect(pcb.localTransform.getTranslation().y, closeTo(-0.2, 1e-6));

      rig.applyVerticalScan(0.2, bandMeters: 0.05);
      expect(pcb.visible, isTrue);
      expect(cap.visible, isFalse);

      rig.reset();
      expect(cap.visible, isTrue);
      expect(cap.localTransform.getTranslation().y, closeTo(0.5, 1e-6));
    });

    test('VrGrowthSchedule animates staggered tile pop-in', () {
      final tileA = fs.Node(
        name: 'tileA',
        localTransform: vm.Matrix4.translationValues(0, 1.0, 0),
      );
      final tileB = fs.Node(
        name: 'tileB',
        localTransform: vm.Matrix4.translationValues(2, 1.0, 0),
      );
      final schedule = VrGrowthSchedule([
        VrGrowthItem(id: 'a', node: tileA, startTime: 0.0, duration: 0.5),
        VrGrowthItem(id: 'b', node: tileB, startTime: 1.0, duration: 0.5),
      ]);

      schedule.evaluate(0.25);
      expect(tileA.visible, isTrue);
      expect(tileB.visible, isFalse);

      schedule.evaluate(2.0);
      expect(tileA.visible, isTrue);
      expect(tileB.visible, isTrue);
      expect(tileB.localTransform.getTranslation().y, closeTo(1.0, 1e-6));
    });
  });

  group('VrAvatarNode procedural pose', () {
    test('evaluatePartTransform applies seated, walk, and wave poses with clavicle lift', () {
      final appearance = VrAvatarAppearance();
      final plan = VrAvatarPlan.build(appearance);
      final torso = plan.parts.firstWhere((p) => p.id == 'torso');
      final rightHand = plan.parts.firstWhere((p) => p.id == 'right_hand');
      final groundShadow = plan.parts.firstWhere((p) => p.id == 'ground_shadow');

      final standingOut = vm.Matrix4.identity();
      final seatedOut = vm.Matrix4.identity();
      VrAvatarNode.evaluatePartTransform(
        part: torso,
        outTransform: standingOut,
        time: 0.0,
        heightMeters: appearance.heightMeters,
        animateIdle: false,
        pose: VrAvatarPose.neutral,
      );
      VrAvatarNode.evaluatePartTransform(
        part: torso,
        outTransform: seatedOut,
        time: 0.0,
        heightMeters: appearance.heightMeters,
        animateIdle: false,
        pose: VrAvatarPose.seated(sit: 1.0, blink: 1.0),
      );
      expect(
        seatedOut.getTranslation().y,
        lessThan(standingOut.getTranslation().y - 0.1),
      );

      // Ground shadow remains anchored at y = base even when seated
      final shadowOut = vm.Matrix4.identity();
      VrAvatarNode.evaluatePartTransform(
        part: groundShadow,
        outTransform: shadowOut,
        time: 0.0,
        heightMeters: appearance.heightMeters,
        animateIdle: false,
        pose: VrAvatarPose.seated(sit: 1.0),
      );
      expect(
        shadowOut.getTranslation().y,
        closeTo(groundShadow.transform.getTranslation().y, 1e-6),
      );

      // Wave pose raises the right hand above its neutral height
      final neutralHand = vm.Matrix4.identity();
      final wavingHand = vm.Matrix4.identity();
      VrAvatarNode.evaluatePartTransform(
        part: rightHand,
        outTransform: neutralHand,
        time: 0.0,
        heightMeters: appearance.heightMeters,
        animateIdle: false,
        pose: VrAvatarPose.neutral,
      );
      VrAvatarNode.evaluatePartTransform(
        part: rightHand,
        outTransform: wavingHand,
        time: 0.0,
        heightMeters: appearance.heightMeters,
        animateIdle: false,
        pose: VrAvatarPose.wave(0.25),
      );
      expect(
        wavingHand.getTranslation().y,
        greaterThan(neutralHand.getTranslation().y),
      );
    });
  });
}
