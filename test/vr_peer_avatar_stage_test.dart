import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;
import 'package:vrlizate_avatar/vrlizate_avatar.dart';
import 'package:vrlizate_scene/vrlizate_scene.dart';

void main() {
  group('VrPeerAvatarStage (shared multiplayer user & NPC crowd stage)', () {
    test('smoothly dead-reckons 10-15 Hz snapshots at 60 Hz and drops out-of-order packets', () {
      final stage = VrPeerAvatarStage(maxPeers: 16);
      final appearance = VrAvatarAppearance(species: VrAvatarSpecies.human);

      expect(
        stage.upsertPeer(
          VrPeerAvatarSnapshot(
            peerId: 'user_alpha',
            appearance: appearance,
            x: 0.0,
            z: -4.0,
            yaw: math.pi - 0.1,
            vx: 2.0,
            vz: 0.0,
            sequence: 10,
          ),
        ),
        isTrue,
      );

      // Advance four 60 Hz frames without a new network packet -> dead-reckons smoothly +X!
      for (var f = 0; f < 4; f++) {
        stage.tick(1 / 60);
      }
      final pos = stage.interpolatedPosition('user_alpha')!;
      expect(pos.x, greaterThan(0.03));

      // Out-of-order stale packet (seq 9 < 10) is rejected
      expect(
        stage.upsertPeer(
          VrPeerAvatarSnapshot(
            peerId: 'user_alpha',
            appearance: appearance,
            x: -99.0,
            z: -4.0,
            yaw: 0.0,
            sequence: 9,
          ),
        ),
        isFalse,
      );
      expect(stage.interpolatedPosition('user_alpha')!.x, greaterThan(0.03));

      // Newer packet across -pi/+pi boundary interpolates shortest angle cleanly
      expect(
        stage.upsertPeer(
          VrPeerAvatarSnapshot(
            peerId: 'user_alpha',
            appearance: appearance,
            x: 0.5,
            z: -4.0,
            yaw: -math.pi + 0.1,
            sequence: 11,
          ),
        ),
        isTrue,
      );
      stage.tick(1 / 60);
      expect(stage.interpolatedYaw('user_alpha')!.abs(), greaterThan(2.5));

      expect(stage.removePeer('user_alpha'), isTrue);
      expect(stage.peerCount, 0);
      stage.dispose();
    });

    test('culls peers behind stereo FOV and caps close limb articulation budget', () {
      final stage = VrPeerAvatarStage(
        maxPeers: 16,
        maxVisibleDistance: 25.0,
        articulateDistance: 10.0,
        maxArticulatedPeers: 2,
      );
      final appearance = VrAvatarAppearance(species: VrAvatarSpecies.robot);

      // 3 close peers in front (-Z), 1 peer behind (+Z), 1 peer too far (-40 m)
      for (var i = 0; i < 3; i++) {
        stage.upsertPeer(
          VrPeerAvatarSnapshot(
            peerId: 'front_$i',
            appearance: appearance,
            x: i * 1.0,
            z: -5.0,
            yaw: 0.0,
          ),
        );
      }
      stage.upsertPeer(
        VrPeerAvatarSnapshot(
          peerId: 'behind_viewer',
          appearance: appearance,
          x: 0.0,
          z: 8.0,
          yaw: 0.0,
        ),
      );
      stage.upsertPeer(
        VrPeerAvatarSnapshot(
          peerId: 'far_away',
          appearance: appearance,
          x: 0.0,
          z: -40.0,
          yaw: 0.0,
        ),
      );

      stage.tick(
        1 / 60,
        eyePosition: vm.Vector3(0, 1.6, 0),
        viewerForward: vm.Vector3(0, 0, -1),
      );

      expect(stage.peerCount, 5);
      expect(stage.visiblePeerCount, 3); // behind & >25 m culled!
      expect(stage.articulatedPeerCount, 2); // capped at maxArticulatedPeers=2!
      stage.dispose();
    });

    test('enables per-instance vertex colors and prioritizes closest peers for articulation', () {
      expect(VrPeerAvatarStage.sharedMaterialVertexColorWeight, 1.0);
      final stage = VrPeerAvatarStage(
        maxPeers: 16,
        maxVisibleDistance: 25.0,
        articulateDistance: 14.0,
        maxArticulatedPeers: 2,
      );
      final appearance = VrAvatarAppearance(
        species: VrAvatarSpecies.human,
        bodyColorArgb: 0xFF2E86DE,
        accentColorArgb: 0xFF7EF0DD,
      );

      // Register far peers FIRST so array order would starve the close peer
      // if nearest-first prioritization regressed.
      stage.upsertPeer(
        VrPeerAvatarSnapshot(
          peerId: 'far_1',
          appearance: appearance,
          x: 0.0,
          z: -11.0,
          yaw: 0.0,
        ),
      );
      stage.upsertPeer(
        VrPeerAvatarSnapshot(
          peerId: 'far_2',
          appearance: appearance,
          x: 1.0,
          z: -10.5,
          yaw: 0.0,
        ),
      );
      stage.upsertPeer(
        VrPeerAvatarSnapshot(
          peerId: 'closest_hero',
          appearance: appearance,
          x: 0.0,
          z: -2.0,
          yaw: 0.0,
          pose: VrAvatarPose.walk(1.1, amplitude: 0.65),
        ),
      );

      stage.tick(
        1 / 60,
        eyePosition: vm.Vector3(0, 1.6, 0),
        viewerForward: vm.Vector3(0, 0, -1),
      );

      expect(stage.articulatedPeerCount, 2);
      expect(stage.isPeerArticulated('closest_hero'), isTrue);
      expect(stage.isPeerArticulated('far_2'), isTrue);
      expect(stage.isPeerArticulated('far_1'), isFalse);

      // Verify leg parts articulate during walk poses and remain planted at rest.
      final plan = VrAvatarPlan.build(appearance);
      final leftLeg = plan.parts.singleWhere((p) => p.id == 'left_leg');
      expect(leftLeg.motion, VrAvatarMotion.leftLeg);
      final restOut = vm.Matrix4.identity();
      final walkOut = vm.Matrix4.identity();
      VrAvatarNode.evaluatePartTransform(
        part: leftLeg,
        outTransform: restOut,
        time: 0.5,
        heightMeters: appearance.heightMeters,
        pose: VrAvatarPose.neutral,
      );
      VrAvatarNode.evaluatePartTransform(
        part: leftLeg,
        outTransform: walkOut,
        time: 0.5,
        heightMeters: appearance.heightMeters,
        pose: VrAvatarPose.walk(1.2, amplitude: 0.65),
      );
      expect(restOut.storage, orderedEquals(leftLeg.transform.storage));
      expect(walkOut.storage, isNot(orderedEquals(leftLeg.transform.storage)));
      stage.dispose();
    });

    test(
      'social Look-At Head IK tracks elevated players smoothly, respects anatomical cone, supports explicit gaze targets, and auto-walks moving remote peers',
      () {
        final stage = VrPeerAvatarStage(maxPeers: 8);
        final appearance = VrAvatarAppearance(
          species: VrAvatarSpecies.human,
          heightMeters: 1.72,
        );

        // Avatar at origin facing +Z (yaw = 0).
        stage.upsertPeer(
          VrPeerAvatarSnapshot(
            peerId: 'greeter',
            appearance: appearance,
            x: 0.0,
            y: 0.0,
            z: 0.0,
            yaw: 0.0,
          ),
        );
        // Remote multiplayer runner with pose == null and vx = 1.6 m/s.
        stage.upsertPeer(
          VrPeerAvatarSnapshot(
            peerId: 'remote_runner',
            appearance: appearance,
            x: -1.5,
            y: 0.0,
            z: 3.0,
            yaw: math.pi / 2,
            vx: 1.6,
            vz: 0.0,
          ),
        );

        // Player stands ahead-left on an elevated terrace (+2.0, 2.55, +4.0).
        final elevatedViewer = vm.Vector3(2.0, 2.55, 4.0);
        for (var f = 0; f < 30; f++) {
          stage.tick(
            1 / 30,
            eyePosition: elevatedViewer,
            viewerForward: vm.Vector3(-0.4, -0.2, -0.9)..normalize(),
          );
        }

        final lookYaw = stage.peerLookAtYaw('greeter')!;
        final lookPitch = stage.peerLookAtPitch('greeter')!;
        expect(lookYaw, greaterThan(0.25));
        expect(lookYaw, lessThanOrEqualTo(VrPeerAvatarStage.maxLookAtYawRadians));
        // Negative pitch tilts local +Z head upward toward elevated Belvedere!
        expect(lookPitch, lessThan(-0.12));
        expect(
          lookPitch,
          greaterThanOrEqualTo(-VrPeerAvatarStage.maxLookAtUpPitchRadians),
        );

        // Remote runner automatically synthesizes velocity-driven bipedal stride.
        expect(stage.peerSmoothedSpeed('remote_runner')!, greaterThan(1.0));
        expect(stage.peerWalkPhase('remote_runner')!, greaterThan(1.5));

        // Moving player BEHIND the greeter relaxes gaze back to 0 (no owl-neck).
        final behindViewer = vm.Vector3(0.0, 1.6, -3.0);
        for (var f = 0; f < 45; f++) {
          stage.tick(
            1 / 30,
            eyePosition: behindViewer,
            viewerForward: vm.Vector3(0.0, 0.0, 1.0),
          );
        }
        expect(stage.peerLookAtYaw('greeter')!.abs(), lessThan(0.04));
        expect(stage.peerLookAtPitch('greeter')!.abs(), lessThan(0.04));

        // Explicit partner lookAtTarget (ahead-right) overrides viewer eye.
        stage.updatePeerMotion(
          'greeter',
          x: 0.0,
          z: 0.0,
          yaw: 0.0,
          lookAtTarget: vm.Vector3(-1.8, 1.15, 2.6),
        );
        for (var f = 0; f < 30; f++) {
          stage.tick(
            1 / 30,
            eyePosition: behindViewer,
            viewerForward: vm.Vector3(0.0, 0.0, 1.0),
          );
        }
        expect(stage.peerLookAtYaw('greeter')!, lessThan(-0.25));
        // Seated target below avatar eye height tilts head slightly downward (+pitch).
        expect(stage.peerLookAtPitch('greeter')!, greaterThan(0.04));
        stage.dispose();
      },
    );
  });
}
