import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vrlizate_scene/vrlizate_scene.dart';

class _StatefulProbe extends StatefulWidget {
  const _StatefulProbe({super.key});

  @override
  State<_StatefulProbe> createState() => _StatefulProbeState();
}

class _StatefulProbeState extends State<_StatefulProbe> {
  static int initCount = 0;

  @override
  void initState() {
    super.initState();
    initCount++;
  }

  @override
  Widget build(BuildContext context) => const SizedBox(width: 200, height: 100);
}

void main() {
  test('Pancake 22mm and Aspheric 35mm headset profiles round-trip cleanly', () {
    final pancake = VrHeadsetProfile.vrlizatePancakeShell;
    expect(pancake.isPancakeOptics, isTrue);
    expect(pancake.focalLengthMm, 22.0);
    expect(pancake.apertureRadius, closeTo(0.96, 1e-6));
    expect(VrHeadsetProfile.byId('vrlizate_pancake_22mm')?.name, pancake.name);
    expect(VrHeadsetProfile.byId('aspheric_35mm')?.focalLengthMm, 35.0);

    final viewer = pancake.toViewerProfile(ipdOverrideMeters: 0.0665);
    expect(viewer.ipdMeters, closeTo(0.0665, 1e-6));
    expect(viewer.hasLensWarp, isTrue);
    expect(viewer.headsetPresetId, 'vrlizate_pancake_22mm');
    expect(viewer.apertureRadius, closeTo(0.96, 1e-6));

    final decoded = VrViewerProfile.fromJson(
      jsonDecode(jsonEncode(viewer.toJson())) as Map<String, dynamic>,
    );
    expect(decoded, viewer);
    expect(decoded.hashCode, viewer.hashCode);

    // Legacy v1 JSON without optical keys remains 100% compatible.
    final legacy = VrViewerProfile.fromJson(const {
      'schemaVersion': 1,
      'ipdMeters': 0.063,
      'fovYRadians': 1.05,
      'stereoImageInset': 0.10,
      'convergenceDistanceMeters': 1.8,
    });
    expect(legacy.hasLensWarp, isFalse);
    expect(legacy.headsetPresetId, 'none');
  });

  test(
    'VrLensWarpMath applies barrel warp, RGB chromatic shift, eye isolation, and Pancake OLED mask',
    () {
      const viewport = Size(2400, 1080);
      final profile = VrHeadsetProfile.vrlizatePancakeShell.toViewerProfile();
      final leftCenterEyeX = 0.5 + profile.stereoImageInset * 0.5;
      final leftCenterScreenUv = Offset(leftCenterEyeX * 0.5, 0.5);

      // 1. Optical axis stays invariant with full brightness.
      final centerSample = VrLensWarpMath.evaluate(
        screenUv: leftCenterScreenUv,
        viewportSize: viewport,
        profile: profile,
      );
      expect(centerSample.greenEyeUv.dx, closeTo(leftCenterEyeX, 1e-6));
      expect(centerSample.greenEyeUv.dy, closeTo(0.5, 1e-6));
      expect(centerSample.apertureMask, closeTo(1.0, 1e-6));

      // 2. Periphery exhibits radial barrel pull and RGB dispersion separation.
      final edgeSample = VrLensWarpMath.evaluate(
        screenUv: Offset(leftCenterScreenUv.dx, 0.06),
        viewportSize: viewport,
        profile: profile,
      );
      final rawDist = (0.06 - 0.5).abs();
      final warpedDistG = (edgeSample.greenEyeUv.dy - 0.5).abs();
      final warpedDistR = (edgeSample.redEyeUv.dy - 0.5).abs();
      final warpedDistB = (edgeSample.blueEyeUv.dy - 0.5).abs();
      expect(warpedDistG, greaterThan(rawDist));
      expect(warpedDistB, greaterThan(warpedDistG));
      expect(warpedDistG, greaterThan(warpedDistR));

      // 3. Cross-eye seam isolation: left eye never samples >= 0.5, right eye never <= 0.5.
      final nearSeamLeft = VrLensWarpMath.evaluate(
        screenUv: const Offset(0.499, 0.05),
        viewportSize: viewport,
        profile: profile,
      );
      expect(nearSeamLeft.redScreenUv.dx, lessThan(0.5));
      expect(nearSeamLeft.greenScreenUv.dx, lessThan(0.5));
      expect(nearSeamLeft.blueScreenUv.dx, lessThan(0.5));

      final nearSeamRight = VrLensWarpMath.evaluate(
        screenUv: const Offset(0.501, 0.05),
        viewportSize: viewport,
        profile: profile,
      );
      expect(nearSeamRight.redScreenUv.dx, greaterThan(0.5));
      expect(nearSeamRight.greenScreenUv.dx, greaterThan(0.5));
      expect(nearSeamRight.blueScreenUv.dx, greaterThan(0.5));

      // 4. Far corner falls outside the circular 0.96 Pancake cone -> pure #000000 OLED mask.
      final cornerSample = VrLensWarpMath.evaluate(
        screenUv: const Offset(0.01, 0.01),
        viewportSize: viewport,
        profile: profile,
      );
      expect(cornerSample.apertureMask, closeTo(0.0, 1e-6));
    },
  );

  testWidgets(
    'VrLensWarpPostProcess keeps child element state intact across preset toggles',
    (tester) async {
      _StatefulProbeState.initCount = 0;
      final profileNotifier = ValueNotifier<VrViewerProfile>(VrViewerProfile());
      addTearDown(profileNotifier.dispose);

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: ValueListenableBuilder<VrViewerProfile>(
            valueListenable: profileNotifier,
            builder: (_, profile, _) => VrLensWarpPostProcess(
              enabled: true,
              profile: profile,
              child: const _StatefulProbe(key: ValueKey('probe')),
            ),
          ),
        ),
      );
      expect(_StatefulProbeState.initCount, 1);

      profileNotifier.value =
          VrHeadsetProfile.vrlizatePancakeShell.toViewerProfile();
      await tester.pump();
      expect(_StatefulProbeState.initCount, 1);

      profileNotifier.value = VrViewerProfile();
      await tester.pump();
      expect(_StatefulProbeState.initCount, 1);
    },
  );
}
