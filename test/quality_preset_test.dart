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
      expect(VrQualityPreset.high.stepDown.tier, VrQualityTier.medium);
      expect(VrQualityPreset.medium.stepDown.tier, VrQualityTier.low);
      expect(VrQualityPreset.low.stepDown.tier, VrQualityTier.low);
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
