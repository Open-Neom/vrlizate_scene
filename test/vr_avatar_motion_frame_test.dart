import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;
import 'package:vrlizate_avatar/vrlizate_avatar.dart';
import 'package:vrlizate_scene/src/avatar/vr_avatar_motion_frame.dart';
import 'package:vrlizate_scene/src/avatar/vr_avatar_node.dart';

import 'fixtures/vr_avatar_legacy_motion_reference.dart';

void main() {
  for (final species in VrAvatarSpecies.values) {
    test('shared motion frame preserves every $species part transform', () {
      final frame = VrAvatarMotionFrame();
      final scratch = vm.Matrix4.identity();
      final actual = vm.Matrix4.identity();
      final reference = vm.Matrix4.identity();
      final poses = <VrAvatarPose?>[
        null,
        VrAvatarPose.neutral,
        VrAvatarPose.seated(sit: .8, look: -.4, blink: 1),
        VrAvatarPose.wave(.7),
        VrAvatarPose.wave(2.3, leftHand: true, blink: .5),
        VrAvatarPose.walk(1.2, amplitude: .7),
        const VrAvatarPose(
          sit: 2,
          lean: -.3,
          turn: .6,
          bob: -.04,
          nod: .35,
          look: -.7,
          tilt: .2,
          leftArmFlexion: -.9,
          leftArmAbduction: .8,
          rightArmFlexion: 1.7,
          rightArmAbduction: 1.3,
          blink: -1,
        ),
      ];
      final appearances = [
        VrAvatarAppearance(species: species),
        VrAvatarAppearance(
          species: species,
          heightMeters: VrAvatarAppearance.minHeightMeters,
          headScale: VrAvatarAppearance.minHeadScale,
          featureScale: VrAvatarAppearance.minFeatureScale,
          cosmeticId: VrAvatarCosmeticCatalog.aurora,
        ),
        VrAvatarAppearance(
          species: species,
          heightMeters: VrAvatarAppearance.maxHeightMeters,
          headScale: VrAvatarAppearance.maxHeadScale,
          featureScale: VrAvatarAppearance.maxFeatureScale,
          pattern: VrAvatarPattern.values.last,
          cosmeticId: VrAvatarCosmeticCatalog.neon,
        ),
      ];
      for (final appearance in appearances) {
        final plan = VrAvatarPlan.build(appearance);
        final authored = [
          for (final part in plan.parts)
            List<double>.of(part.transform.storage),
        ];
        for (final time in [0.0, .125, 1.1, math.pi * 20 - .001]) {
          for (final pose in poses) {
            for (final animateIdle in [true, false]) {
              frame.prepare(
                time: time,
                heightMeters: appearance.heightMeters,
                pose: pose,
                animateIdle: animateIdle,
              );
              for (final part in plan.parts) {
                evaluateLegacyAvatarPartTransform(
                  part: part,
                  outTransform: reference,
                  time: time,
                  heightMeters: appearance.heightMeters,
                  pose: pose,
                  animateIdle: animateIdle,
                );
                frame.transformPart(
                  part: part,
                  outTransform: actual,
                  scratchDelta: scratch,
                );
                for (var i = 0; i < 16; i++) {
                  if (!actual.storage[i].isFinite ||
                      (actual.storage[i] - reference.storage[i]).abs() >
                          1e-12) {
                    fail(
                      '${part.id} at $time s, idle=$animateIdle, '
                      'height=${appearance.heightMeters}: component $i '
                      '${actual.storage[i]} != ${reference.storage[i]}',
                    );
                  }
                }
              }
            }
          }
        }
        // Reusing the frame/scratch must never mutate authored rest transforms.
        for (var i = 0; i < plan.parts.length; i++) {
          expect(plan.parts[i].transform.storage, orderedEquals(authored[i]));
        }
      }
    });
  }

  test(
    'parts reuse prepared pose and independent avatars keep their own frame',
    () {
      final pose = _CountingPose();
      final a = VrAvatarMotionFrame()
        ..prepare(time: .7, heightMeters: 1.7, pose: pose);
      final readsAfterPrepare = pose.reads;
      expect(readsAfterPrepare, greaterThan(0));
      final plan = VrAvatarPlan.build(VrAvatarAppearance());
      final scratch = vm.Matrix4.identity();
      final first = <List<double>>[];
      final actual = vm.Matrix4.identity();
      for (final part in plan.parts) {
        a.transformPart(
          part: part,
          outTransform: actual,
          scratchDelta: scratch,
        );
        first.add(List<double>.of(actual.storage));
      }
      final b = VrAvatarMotionFrame()
        ..prepare(time: 9, heightMeters: 2.2, pose: VrAvatarPose.seated());
      for (var i = 0; i < plan.parts.length; i++) {
        b.transformPart(
          part: plan.parts[i],
          outTransform: actual,
          scratchDelta: scratch,
        );
        a.transformPart(
          part: plan.parts[i],
          outTransform: actual,
          scratchDelta: scratch,
        );
        expect(actual.storage, orderedEquals(first[i]));
      }
      expect(pose.reads, readsAfterPrepare);
      final legacyPose = _CountingPose();
      for (final part in plan.parts) {
        evaluateLegacyAvatarPartTransform(
          part: part,
          outTransform: actual,
          time: .7,
          heightMeters: 1.7,
          pose: legacyPose,
          scratchDelta: scratch,
        );
      }
      final animatedParts = plan.parts
          .where((part) => part.motion != VrAvatarMotion.ground)
          .length;
      expect(readsAfterPrepare, 3);
      expect(legacyPose.reads, 3 * animatedParts);
      expect(animatedParts, greaterThan(1));
      // Deterministic CPU-work accounting; this is not a frame-rate benchmark.
      print(
        'Avatar motion preparation: $animatedParts per-part evaluations → 1 shared frame.',
      );
    },
  );

  test(
    'public single-part evaluator remains equivalent with reused scratch',
    () {
      final plan = VrAvatarPlan.build(VrAvatarAppearance());
      final actual = vm.Matrix4.identity();
      final expected = vm.Matrix4.identity();
      final scratch = vm.Matrix4.identity();
      final pose = VrAvatarPose.wave(.4, blink: 1);
      for (final part in plan.parts) {
        evaluateLegacyAvatarPartTransform(
          part: part,
          outTransform: expected,
          time: 3.2,
          heightMeters: 1.7,
          pose: pose,
        );
        VrAvatarNode.evaluatePartTransform(
          part: part,
          outTransform: actual,
          time: 3.2,
          heightMeters: 1.7,
          pose: pose,
          scratchDelta: scratch,
        );
        expect(actual.storage, orderedEquals(expected.storage));
      }
    },
  );
}

class _CountingPose extends VrAvatarPose {
  int reads = 0;

  @override
  double get bob {
    reads++;
    return .02;
  }

  @override
  double get eyeScaleY {
    reads++;
    return .65;
  }
}
