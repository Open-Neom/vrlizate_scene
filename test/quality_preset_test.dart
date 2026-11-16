import 'package:flutter_scene/scene.dart' show AntiAliasingMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:vrlizate_scene/vrlizate_scene.dart';

void main() {
  group('VrQualityPreset', () {
    test('tiers are ordered by cost', () {
      expect(
        VrQualityPreset.low.pixelRatioScale,
        lessThan(VrQualityPreset.medium.pixelRatioScale),
      );
      expect(
        VrQualityPreset.low.shadowMapResolution,
        lessThan(VrQualityPreset.high.shadowMapResolution),
      );
      expect(VrQualityPreset.high.bloomEnabled, isFalse);
      expect(VrQualityPreset.ultra.bloomEnabled, isTrue);
      expect(VrQualityPreset.medium.pixelRatioScale, 1.0);
      expect(VrQualityPreset.high.pixelRatioScale, 1.0);
      expect(VrQualityPreset.low.bloomEnabled, isFalse);
    });

    test('forTier returns the matching constant', () {
      expect(
        VrQualityPreset.forTier(VrQualityTier.low),
        same(VrQualityPreset.low),
      );
      expect(
        VrQualityPreset.forTier(VrQualityTier.high),
        same(VrQualityPreset.high),
      );
    });

    test('stepDown lowers one tier and bottoms out at low', () {
      expect(VrQualityPreset.ultra.stepDown, same(VrQualityPreset.high));
      expect(VrQualityPreset.high.stepDown, same(VrQualityPreset.medium));
      expect(VrQualityPreset.medium.stepDown, same(VrQualityPreset.low));
      expect(VrQualityPreset.low.stepDown, same(VrQualityPreset.low));
    });

    test('stepDown caps the next tier at the current custom budgets', () {
      const custom = VrQualityPreset(
        tier: VrQualityTier.high,
        pixelRatioScale: .75,
        antiAliasing: AntiAliasingMode.none,
        shadowMapResolution: 384,
        bloomEnabled: false,
      );
      final medium = custom.stepDown;
      expect(medium.tier, VrQualityTier.medium);
      expect(medium.pixelRatioScale, .75);
      expect(medium.shadowMapResolution, 384);
      expect(medium.antiAliasing, AntiAliasingMode.none);
      expect(medium.bloomEnabled, isFalse);

      final low = medium.stepDown;
      expect(low.tier, VrQualityTier.low);
      expect(low.pixelRatioScale, .6);
      expect(low.shadowMapResolution, 384);
      expect(low.stepDown, same(low));
    });

    test('stepDown reduces larger custom budgets and retains selected AA', () {
      const custom = VrQualityPreset(
        tier: VrQualityTier.ultra,
        pixelRatioScale: 1.3,
        antiAliasing: AntiAliasingMode.fxaa,
        shadowMapResolution: 4096,
        bloomEnabled: true,
      );

      final high = custom.stepDown;
      expect(high.tier, VrQualityTier.high);
      expect(high.pixelRatioScale, 1.0);
      expect(high.shadowMapResolution, 2048);
      expect(high.antiAliasing, AntiAliasingMode.fxaa);
      expect(high.bloomEnabled, isFalse);
      expect(high.stepDown.antiAliasing, AntiAliasingMode.fxaa);
      expect(high.stepDown.stepDown.antiAliasing, AntiAliasingMode.none);
    });

    test('custom low keeps its exact settings at the bottom tier', () {
      const custom = VrQualityPreset(
        tier: VrQualityTier.low,
        pixelRatioScale: .5,
        antiAliasing: AntiAliasingMode.none,
        shadowMapResolution: 256,
        bloomEnabled: false,
      );
      expect(custom.stepDown, same(custom));
    });

    test('high tier uses MSAA, medium MSAA-with-FXAA-fallback, low none', () {
      expect(VrQualityPreset.high.antiAliasing, AntiAliasingMode.msaa);
      // `auto` is MSAA where the backend supports it, FXAA elsewhere:
      // crisp edges and label text on the default tier without a hard
      // dependency on MSAA support.
      expect(VrQualityPreset.medium.antiAliasing, AntiAliasingMode.auto);
      expect(VrQualityPreset.low.antiAliasing, AntiAliasingMode.none);
    });
  });
}
