import 'dart:math' as math;

import 'package:vector_math/vector_math.dart' as vm;
import 'package:vrlizate_avatar/vrlizate_avatar.dart';

import 'vr_avatar_plan.dart';

/// Internal retained animation state shared by all parts of one avatar update.
///
/// [prepare] evaluates pose, waves and shoulder kinematics once. [transformPart]
/// only applies those values at each authored pivot, without recalculating them
/// for every face, eye, limb and cosmetic. Reuse this object between frames.
final class VrAvatarMotionFrame {
  late double _breathY;
  late double _bodyPitch;
  late double _bodyYaw;
  late double _headYaw;
  late double _headPitch;
  late double _headRoll;
  late double _leftFlex;
  late double _leftAbd;
  late double _rightFlex;
  late double _rightAbd;
  late double _leftClavicleY;
  late double _leftClavicleZ;
  late double _rightClavicleY;
  late double _rightClavicleZ;
  late double _eyeScaleY;
  late double _leftFeat;
  late double _rightFeat;
  late double _crownSway;
  late double _tailWag;
  late double _hoverY;
  late double _hoverRoll;

  void prepare({
    required double time,
    required double heightMeters,
    bool animateIdle = true,
    VrAvatarPose? pose,
  }) {
    final idleScale = animateIdle ? 1.0 : 0.0;
    final breathWave = math.sin(time * 2.1);
    final sitOffset = (pose?.sit ?? 0.0).clamp(0.0, 1.0) * 0.14 * heightMeters;
    _breathY =
        (breathWave * .006 * heightMeters * idleScale) +
        (pose?.bob ?? 0.0) -
        sitOffset;
    _bodyPitch = (breathWave * .018 * idleScale) + (pose?.lean ?? 0.0);
    _bodyYaw = (math.sin(time * 1.05) * .022 * idleScale) + (pose?.turn ?? 0.0);
    _headYaw = (math.sin(time * 1.35) * .048 * idleScale) + (pose?.look ?? 0.0);
    _headPitch =
        (math.sin(time * 2.1 + .6) * .028 * idleScale) + (pose?.nod ?? 0.0);
    _headRoll =
        (math.cos(time * 1.35) * .022 * idleScale) + (pose?.tilt ?? 0.0);
    final armSwing = breathWave * .038 * idleScale;
    _leftFlex = armSwing + (pose?.leftArmFlexion ?? 0.0);
    _leftAbd = (armSwing * .5) + (pose?.leftArmAbduction ?? 0.0);
    _rightFlex = -armSwing + (pose?.rightArmFlexion ?? 0.0);
    _rightAbd = (armSwing * .5) + (pose?.rightArmAbduction ?? 0.0);
    _leftClavicleY = VrShoulderKinematics.clavicleRiseMeters(
      flexion: _leftFlex,
      abduction: _leftAbd,
      heightMeters: heightMeters,
    );
    _leftClavicleZ = VrShoulderKinematics.clavicleForwardMeters(
      flexion: _leftFlex,
      abduction: _leftAbd,
      heightMeters: heightMeters,
    );
    _rightClavicleY = VrShoulderKinematics.clavicleRiseMeters(
      flexion: _rightFlex,
      abduction: _rightAbd,
      heightMeters: heightMeters,
    );
    _rightClavicleZ = VrShoulderKinematics.clavicleForwardMeters(
      flexion: _rightFlex,
      abduction: _rightAbd,
      heightMeters: heightMeters,
    );
    _eyeScaleY = pose?.eyeScaleY ?? 1.0;
    _leftFeat = math.sin(time * 3.2) * .065 * idleScale;
    _rightFeat = math.sin(time * 3.2 + .9) * .065 * idleScale;
    _crownSway = math.sin(time * 2.6) * .055 * idleScale;
    _tailWag = math.sin(time * 2.8) * .085 * idleScale;
    _hoverY =
        (math.sin(time * 2.4) * .016 * heightMeters * idleScale) +
        (pose?.bob ?? 0.0);
    _hoverRoll =
        (math.cos(time * 1.6) * .032 * idleScale) + (pose?.tilt ?? 0.0);
  }

  void transformPart({
    required VrAvatarPart part,
    required vm.Matrix4 outTransform,
    vm.Matrix4? scratchDelta,
  }) {
    if (part.motion == VrAvatarMotion.ground) {
      outTransform.setFrom(part.transform);
      return;
    }
    final delta = scratchDelta ?? vm.Matrix4.identity();
    delta.setIdentity();

    final p = part.pivot;
    switch (part.motion) {
      case VrAvatarMotion.ground:
        break;
      case VrAvatarMotion.body:
        delta
          ..translateByDouble(p.x, p.y + _breathY, p.z, 1)
          ..rotateY(_bodyYaw)
          ..rotateX(_bodyPitch)
          ..translateByDouble(-p.x, -p.y, -p.z, 1);
      case VrAvatarMotion.head:
        delta
          ..translateByDouble(p.x, p.y + _breathY, p.z, 1)
          ..rotateY(_headYaw)
          ..rotateX(_headPitch)
          ..rotateZ(_headRoll)
          ..translateByDouble(-p.x, -p.y, -p.z, 1);
        if (_eyeScaleY < 0.999 && part.id.startsWith('eye_')) {
          delta
            ..translateByDouble(p.x, p.y, p.z, 1)
            ..scaleByDouble(1.0, _eyeScaleY, 1.0, 1.0)
            ..translateByDouble(-p.x, -p.y, -p.z, 1);
        }
      case VrAvatarMotion.leftArm:
        delta
          ..translateByDouble(
            p.x,
            p.y + _breathY + _leftClavicleY,
            p.z + _leftClavicleZ,
            1,
          )
          ..rotateZ(-_leftAbd)
          ..rotateX(-_leftFlex)
          ..translateByDouble(-p.x, -p.y, -p.z, 1);
      case VrAvatarMotion.rightArm:
        delta
          ..translateByDouble(
            p.x,
            p.y + _breathY + _rightClavicleY,
            p.z + _rightClavicleZ,
            1,
          )
          ..rotateZ(_rightAbd)
          ..rotateX(-_rightFlex)
          ..translateByDouble(-p.x, -p.y, -p.z, 1);
      case VrAvatarMotion.leftFeature:
        delta
          ..translateByDouble(p.x, p.y + _breathY, p.z, 1)
          ..rotateY(_headYaw)
          ..rotateZ(_leftFeat)
          ..translateByDouble(-p.x, -p.y, -p.z, 1);
      case VrAvatarMotion.rightFeature:
        delta
          ..translateByDouble(p.x, p.y + _breathY, p.z, 1)
          ..rotateY(_headYaw)
          ..rotateZ(-_rightFeat)
          ..translateByDouble(-p.x, -p.y, -p.z, 1);
      case VrAvatarMotion.crownFeature:
        delta
          ..translateByDouble(p.x, p.y + _breathY, p.z, 1)
          ..rotateY(_headYaw)
          ..rotateZ(_crownSway)
          ..rotateX(_headPitch * .6)
          ..translateByDouble(-p.x, -p.y, -p.z, 1);
      case VrAvatarMotion.tail:
        delta
          ..translateByDouble(p.x, p.y + _breathY * .6, p.z, 1)
          ..rotateY(_tailWag)
          ..rotateZ(_tailWag * .45)
          ..translateByDouble(-p.x, -p.y, -p.z, 1);
      case VrAvatarMotion.hoverCore:
        delta
          ..translateByDouble(p.x, p.y + _hoverY, p.z, 1)
          ..rotateY(_bodyYaw * 1.2)
          ..rotateZ(_hoverRoll)
          ..translateByDouble(-p.x, -p.y, -p.z, 1);
    }
    outTransform
      ..setFrom(delta)
      ..multiply(part.transform);
  }
}
