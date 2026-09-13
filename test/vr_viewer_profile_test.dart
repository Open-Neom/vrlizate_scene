import 'dart:convert';
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;
import 'package:vrlizate_scene/vrlizate_scene.dart';

void main() {
  test('JSON round-trip, equality and independent copy', () {
    final profile = VrViewerProfile(
      ipdMeters: 0.062,
      fovYRadians: 1.2,
      stereoImageInset: 0.18,
      convergenceDistanceMeters: 2.5,
    );
    expect(
      VrViewerProfile.fromJson(jsonDecode(jsonEncode(profile.toJson()))),
      profile,
    );
    final changed = profile.copyWith(ipdMeters: 0.065);
    expect(changed.ipdMeters, 0.065);
    expect(changed.fovYRadians, 1.2);
    expect(profile.ipdMeters, 0.062);
    expect(profile.copyWith().hashCode, profile.hashCode);
  });

  test('copy and JSON preserve an explicitly disabled convergence shift', () {
    final profile = VrViewerProfile().copyWith(convergenceDistanceMeters: null);
    expect(profile.convergenceDistanceMeters, isNull);
    expect(
      profile.copyWith(stereoImageInset: 0.2).convergenceDistanceMeters,
      isNull,
    );
    expect(VrViewerProfile.fromJson(profile.toJson()), profile);
    expect(
      profile.copyWith(convergenceDistanceMeters: 2).convergenceDistanceMeters,
      2,
    );
  });

  test('invalid values fail at runtime, never silently clamp', () {
    for (final ipd in [double.nan, double.infinity, 0.049, 0.081]) {
      expect(() => VrViewerProfile(ipdMeters: ipd), throwsArgumentError);
    }
    for (final fov in [double.nan, 0.4, pi]) {
      expect(() => VrViewerProfile(fovYRadians: fov), throwsArgumentError);
    }
    for (final inset in [double.nan, -0.01, 0.351]) {
      expect(
        () => VrViewerProfile(stereoImageInset: inset),
        throwsArgumentError,
      );
    }
    for (final distance in <double>[double.infinity, 0, 0.49, 21]) {
      expect(
        () => VrViewerProfile(convergenceDistanceMeters: distance),
        throwsArgumentError,
      );
    }
    expect(
      () => VrViewerProfile().copyWith(convergenceDistanceMeters: '2'),
      throwsArgumentError,
    );
  });

  test('malformed or unsupported JSON fails descriptively', () {
    expect(() => VrViewerProfile.fromJson({}), throwsFormatException);
    final json = VrViewerProfile().toJson();
    for (final key in [
      'ipdMeters',
      'fovYRadians',
      'stereoImageInset',
      'convergenceDistanceMeters',
    ]) {
      expect(
        () => VrViewerProfile.fromJson(Map.of(json)..remove(key)),
        throwsFormatException,
      );
      expect(
        () => VrViewerProfile.fromJson({...json, key: 'invalid'}),
        throwsFormatException,
      );
    }
    expect(
      () => VrViewerProfile.fromJson({...json, 'schemaVersion': 2}),
      throwsFormatException,
    );
    expect(
      () => VrViewerProfile.fromJson({...json, 'ipdMeters': 0.1}),
      throwsFormatException,
    );
  });

  test(
    'apply exact calibration to both eyes without moving the world pose',
    () {
      final rig = StereoHeadRig(eyeCenter: vm.Vector3(2, 1.6, 4));
      rig.setOrientation(0.6, -0.2);
      final position = rig.eyeCenter.clone();
      final orientation = rig.orientation.clone();
      for (final ipd in [0.050, 0.064, 0.080]) {
        final profile = VrViewerProfile(
          ipdMeters: ipd,
          fovYRadians: 1.4,
          stereoImageInset: 0.25,
          convergenceDistanceMeters: 3,
        );
        profile.applyTo(rig);
        expect(rig.ipd, ipd);
        expect(rig.cameraRig.fovY, 1.4);
        expect(rig.stereoImageInset, 0.25);
        expect(rig.convergenceDistance, 3);
        expect(rig.eyeCenter, position);
        expect(rig.orientation, orientation);
        expect(
          (rig.eyePosition(StereoEye.left) - rig.eyePosition(StereoEye.right))
              .length,
          closeTo(ipd, 1e-6),
        );
      }
      VrViewerProfile(convergenceDistanceMeters: null).applyTo(rig);
      expect(rig.convergencePoint, isNull);
    },
  );

  testWidgets('scope notifies consumers and forwards edits to the host', (
    tester,
  ) async {
    final current = ValueNotifier(VrViewerProfile());
    addTearDown(current.dispose);
    VrViewerProfileScope? scope;
    var builds = 0;
    await tester.pumpWidget(
      ValueListenableBuilder<VrViewerProfile>(
        valueListenable: current,
        builder: (_, profile, _) => VrViewerProfileScope(
          profile: profile,
          onChanged: (value) => current.value = value,
          child: Builder(
            builder: (context) {
              builds++;
              scope = VrViewerProfileScope.maybeOf(context);
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    expect(scope!.profile, current.value);
    scope!.onChanged(scope!.profile.copyWith(stereoImageInset: 0.24));
    await tester.pump();
    expect(scope!.profile.stereoImageInset, 0.24);
    expect(builds, 2);
  });
}
