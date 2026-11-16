import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;
import 'package:vrlizate_scene/vrlizate_scene.dart';

import 'support/predictive_cull_before.dart';

void main() {
  test('stereo pose/crop replay retains every plane bit and input vector', () {
    final rig = StereoHeadRig();
    for (var pose = 0; pose < 36; pose++) {
      rig.rotate(.071, (pose.isEven ? 1 : -1) * .033);
      for (final crop in [
        const ui.Rect.fromLTRB(0, 0, 1, 1),
        const ui.Rect.fromLTRB(.2, 0, 1, 1),
        const ui.Rect.fromLTRB(.2, 0, .8, 1),
        const ui.Rect.fromLTRB(.2, .1, .8, .9),
      ]) {
        for (final far in <double?>[null, 4, 42, 140]) {
          for (final eye in StereoEye.values) {
            _replay(
              eye: rig.eyePosition(eye),
              forward: rig.forward,
              right: rig.screenRight,
              up: rig.up,
              crop: crop,
              far: far,
              fov: rig.cameraRig.fovY,
              aspect: pose.isEven ? 1 : 1.4,
            );
          }
        }
      }
    }
  });

  test('crop and far-plane boundary inequalities remain exact', () {
    for (final epsilon in [-1e-12, 0.0, 1e-12]) {
      for (final far in <double?>[null, 4 - 1e-12, 4, 4 + 1e-12]) {
        _replay(
          crop: ui.Rect.fromLTRB(
            .01 + epsilon,
            .01 + epsilon,
            .99 - epsilon,
            .99 - epsilon,
          ),
          far: far,
        );
      }
    }
  });

  test('invalid FOV and aspect preserve early-return behavior', () {
    for (final invalid in [
      double.nan,
      double.infinity,
      -double.infinity,
      -.1,
      0.0,
      .05,
    ]) {
      _replay(fov: invalid);
      _replay(aspect: invalid);
    }
  });

  test('stereo inset, safety margins and nonfinite far retain plane bits', () {
    for (final shift in [-.08, -0.0, 0.0, .08]) {
      for (final margin in [
        .085,
        .1,
        .2,
        0.0,
        -0.0,
        -.1,
        math.pi / 2 - 1e-12,
        math.pi / 2 + 1e-12,
        double.nan,
        double.infinity,
        -double.infinity,
      ]) {
        for (final far in <double?>[
          null,
          42,
          double.nan,
          double.infinity,
          -double.infinity,
        ]) {
          _replay(shift: shift, margin: margin, far: far);
        }
      }
    }
  });

  test('zero, signed zero and nonfinite bases are not mutated', () {
    for (final value in [
      0.0,
      -0.0,
      double.nan,
      double.infinity,
      -double.infinity,
      1e30,
    ]) {
      _replay(forward: vm.Vector3(value, 0, -1));
      _replay(right: vm.Vector3(1, value, 0));
      _replay(up: vm.Vector3(0, 1, value));
      _replay(eye: vm.Vector3(value, -0.0, 0));
    }
    _replay(
      forward: vm.Vector3.zero(),
      right: vm.Vector3.zero(),
      up: vm.Vector3.zero(),
    );
  });

  test('vector subtype operators may return an external base-vector alias', () {
    for (final role in ['forward', 'right', 'up']) {
      for (final spoofType in [false, true]) {
        final alias = vm.Vector3(2, 3, 4);
        final before = _vectorBits(alias);
        final custom = _AliasedVector(alias, spoofType: spoofType);
        _replay(
          forward: role == 'forward' ? custom : null,
          right: role == 'right' ? custom : null,
          up: role == 'up' ? custom : null,
        );
        expect(_vectorBits(alias), before, reason: 'Caller-owned $role alias.');
      }
    }
  });
}

void _replay({
  vm.Vector3? eye,
  vm.Vector3? forward,
  vm.Vector3? right,
  vm.Vector3? up,
  ui.Rect crop = const ui.Rect.fromLTRB(.2, .1, .8, .9),
  double fov = math.pi / 3,
  double aspect = 1,
  double? far = 50,
  double shift = 0,
  double margin = .085,
}) {
  eye ??= vm.Vector3(3, 1.6, -8);
  forward ??= vm.Vector3(0, 0, -1);
  right ??= vm.Vector3(1, 0, 0);
  up ??= vm.Vector3(0, 1, 0);
  final vectors = [eye, forward, right, up];
  final before = [for (final v in vectors) _vectorBits(v)];
  final old = buildBeforePredictivePlanes(
    eyePosition: eye,
    forward: forward,
    screenRight: right,
    up: up,
    fovRadiansY: fov,
    fullEyeAspectRatio: aspect,
    normalizedCropRect: crop,
    dynamicFarCullMeters: far,
    horizontalClipShift: shift,
    safetyMarginRadians: margin,
  );
  final actual = VrPredictiveMotionCuller.buildPredictiveEyeCullingPlanes(
    eyePosition: eye,
    forward: forward,
    screenRight: right,
    up: up,
    fovRadiansY: fov,
    fullEyeAspectRatio: aspect,
    normalizedCropRect: crop,
    dynamicFarCullMeters: far,
    horizontalClipShift: shift,
    safetyMarginRadians: margin,
  );
  expect(_planeBits(actual), _planeBits(old));
  for (var i = 0; i < vectors.length; i++) {
    expect(_vectorBits(vectors[i]), before[i]);
  }
}

List<int> _planeBits(List<vm.Plane> planes) {
  final bytes = ByteData(planes.length * 32);
  for (var i = 0; i < planes.length; i++) {
    final p = planes[i];
    for (final entry in [
      p.normal.x,
      p.normal.y,
      p.normal.z,
      p.constant,
    ].indexed) {
      bytes.setFloat64(i * 32 + entry.$1 * 8, entry.$2, Endian.little);
    }
  }
  return bytes.buffer.asUint8List();
}

List<int> _vectorBits(vm.Vector3 v) => Uint8List.fromList(
  v.storage.buffer.asUint8List(
    v.storage.offsetInBytes,
    v.storage.lengthInBytes,
  ),
);

final class _AliasedVector extends vm.Vector3 {
  _AliasedVector(this.alias, {required this.spoofType}) : super.zero() {
    setValues(1, .5, -.25);
  }
  final vm.Vector3 alias;
  final bool spoofType;
  @override
  Type get runtimeType => spoofType ? vm.Vector3 : super.runtimeType;
  @override
  vm.Vector3 operator -(vm.Vector3 other) => alias;
  @override
  vm.Vector3 operator -() => alias;
  @override
  vm.Vector3 operator +(vm.Vector3 other) => alias;
  @override
  vm.Vector3 operator *(double scale) => alias;
}
