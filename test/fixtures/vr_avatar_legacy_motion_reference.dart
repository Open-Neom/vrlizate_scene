// Frozen pre-optimization CPU evaluator. Keep this oracle unchanged unless
// the authored animation itself intentionally changes. It validates that the
// prepared, shared frame preserves every instance matrix.
import 'dart:math' as math;

import 'package:vector_math/vector_math.dart' as vm;
import 'package:vrlizate_avatar/vrlizate_avatar.dart';
import 'package:vrlizate_scene/src/avatar/vr_avatar_plan.dart';

void evaluateLegacyAvatarPartTransform({
  required VrAvatarPart part,
  required vm.Matrix4 outTransform,
  required double time,
  required double heightMeters,
  bool animateIdle = true,
  VrAvatarPose? pose,
  vm.Matrix4? scratchDelta,
}) {
  if (part.motion == VrAvatarMotion.ground) {
    outTransform.setFrom(part.transform);
    return;
  }
  final delta = scratchDelta ?? vm.Matrix4.identity();
  delta.setIdentity();

  final idleScale = animateIdle ? 1.0 : 0.0;
  final sitOffset = (pose?.sit ?? 0.0).clamp(0.0, 1.0) * 0.14 * heightMeters;
  final breathY =
      (math.sin(time * 2.1) * .006 * heightMeters * idleScale) +
      (pose?.bob ?? 0.0) -
      sitOffset;
  final bodyPitch =
      (math.sin(time * 2.1) * .018 * idleScale) + (pose?.lean ?? 0.0);
  final bodyYaw =
      (math.sin(time * 1.05) * .022 * idleScale) + (pose?.turn ?? 0.0);
  final headYaw =
      (math.sin(time * 1.35) * .048 * idleScale) + (pose?.look ?? 0.0);
  final headPitch =
      (math.sin(time * 2.1 + .6) * .028 * idleScale) + (pose?.nod ?? 0.0);
  final headRoll =
      (math.cos(time * 1.35) * .022 * idleScale) + (pose?.tilt ?? 0.0);
  final armSwing = math.sin(time * 2.1) * .038 * idleScale;
  final leftFlex = armSwing + (pose?.leftArmFlexion ?? 0.0);
  final leftAbd = (armSwing * .5) + (pose?.leftArmAbduction ?? 0.0);
  final rightFlex = -armSwing + (pose?.rightArmFlexion ?? 0.0);
  final rightAbd = (armSwing * .5) + (pose?.rightArmAbduction ?? 0.0);
  final leftClavicleY = VrShoulderKinematics.clavicleRiseMeters(
    flexion: leftFlex,
    abduction: leftAbd,
    heightMeters: heightMeters,
  );
  final leftClavicleZ = VrShoulderKinematics.clavicleForwardMeters(
    flexion: leftFlex,
    abduction: leftAbd,
    heightMeters: heightMeters,
  );
  final rightClavicleY = VrShoulderKinematics.clavicleRiseMeters(
    flexion: rightFlex,
    abduction: rightAbd,
    heightMeters: heightMeters,
  );
  final rightClavicleZ = VrShoulderKinematics.clavicleForwardMeters(
    flexion: rightFlex,
    abduction: rightAbd,
    heightMeters: heightMeters,
  );
  final leftLegSwing = (pose?.leftLegSwing ?? 0.0).clamp(-1.05, 1.05);
  final rightLegSwing = (pose?.rightLegSwing ?? 0.0).clamp(-1.05, 1.05);
  final leftFootLift =
      math.max(0.0, math.sin(leftLegSwing)) * 0.022 * heightMeters;
  final rightFootLift =
      math.max(0.0, math.sin(rightLegSwing)) * 0.022 * heightMeters;
  final eyeScaleY = pose?.eyeScaleY ?? 1.0;
  final leftFeat = math.sin(time * 3.2) * .065 * idleScale;
  final rightFeat = math.sin(time * 3.2 + .9) * .065 * idleScale;
  final crownSway = math.sin(time * 2.6) * .055 * idleScale;
  final tailWag = math.sin(time * 2.8) * .085 * idleScale;
  final hoverY =
      (math.sin(time * 2.4) * .016 * heightMeters * idleScale) +
      (pose?.bob ?? 0.0);
  final hoverRoll =
      (math.cos(time * 1.6) * .032 * idleScale) + (pose?.tilt ?? 0.0);

  final p = part.pivot;
  switch (part.motion) {
    case VrAvatarMotion.ground:
      break;
    case VrAvatarMotion.body:
      delta
        ..translateByDouble(p.x, p.y + breathY, p.z, 1)
        ..rotateY(bodyYaw)
        ..rotateX(bodyPitch)
        ..translateByDouble(-p.x, -p.y, -p.z, 1);
    case VrAvatarMotion.head:
      delta
        ..translateByDouble(p.x, p.y + breathY, p.z, 1)
        ..rotateY(headYaw)
        ..rotateX(headPitch)
        ..rotateZ(headRoll)
        ..translateByDouble(-p.x, -p.y, -p.z, 1);
      if (eyeScaleY < 0.999 && part.id.startsWith('eye_')) {
        delta
          ..translateByDouble(p.x, p.y, p.z, 1)
          ..scaleByDouble(1.0, eyeScaleY, 1.0, 1.0)
          ..translateByDouble(-p.x, -p.y, -p.z, 1);
      }
    case VrAvatarMotion.leftArm:
      delta
        ..translateByDouble(
          p.x,
          p.y + breathY + leftClavicleY,
          p.z + leftClavicleZ,
          1,
        )
        ..rotateZ(-leftAbd)
        ..rotateX(-leftFlex)
        ..translateByDouble(-p.x, -p.y, -p.z, 1);
    case VrAvatarMotion.rightArm:
      delta
        ..translateByDouble(
          p.x,
          p.y + breathY + rightClavicleY,
          p.z + rightClavicleZ,
          1,
        )
        ..rotateZ(rightAbd)
        ..rotateX(-rightFlex)
        ..translateByDouble(-p.x, -p.y, -p.z, 1);
    case VrAvatarMotion.leftLeg:
      if (leftLegSwing.abs() < 1e-5) {
        outTransform.setFrom(part.transform);
        return;
      }
      delta
        ..translateByDouble(p.x, p.y + leftFootLift, p.z, 1)
        ..rotateX(-leftLegSwing)
        ..translateByDouble(-p.x, -p.y, -p.z, 1);
    case VrAvatarMotion.rightLeg:
      if (rightLegSwing.abs() < 1e-5) {
        outTransform.setFrom(part.transform);
        return;
      }
      delta
        ..translateByDouble(p.x, p.y + rightFootLift, p.z, 1)
        ..rotateX(-rightLegSwing)
        ..translateByDouble(-p.x, -p.y, -p.z, 1);
    case VrAvatarMotion.leftFeature:
      delta
        ..translateByDouble(p.x, p.y + breathY, p.z, 1)
        ..rotateY(headYaw)
        ..rotateZ(leftFeat)
        ..translateByDouble(-p.x, -p.y, -p.z, 1);
    case VrAvatarMotion.rightFeature:
      delta
        ..translateByDouble(p.x, p.y + breathY, p.z, 1)
        ..rotateY(headYaw)
        ..rotateZ(-rightFeat)
        ..translateByDouble(-p.x, -p.y, -p.z, 1);
    case VrAvatarMotion.crownFeature:
      delta
        ..translateByDouble(p.x, p.y + breathY, p.z, 1)
        ..rotateY(headYaw)
        ..rotateZ(crownSway)
        ..rotateX(headPitch * .6)
        ..translateByDouble(-p.x, -p.y, -p.z, 1);
    case VrAvatarMotion.tail:
      delta
        ..translateByDouble(p.x, p.y + breathY * .6, p.z, 1)
        ..rotateY(tailWag)
        ..rotateZ(tailWag * .45)
        ..translateByDouble(-p.x, -p.y, -p.z, 1);
    case VrAvatarMotion.hoverCore:
      delta
        ..translateByDouble(p.x, p.y + hoverY, p.z, 1)
        ..rotateY(bodyYaw * 1.2)
        ..rotateZ(hoverRoll)
        ..translateByDouble(-p.x, -p.y, -p.z, 1);
  }
  outTransform
    ..setFrom(delta)
    ..multiply(part.transform);
}
