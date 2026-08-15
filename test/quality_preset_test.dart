import 'package:flutter_scene/scene.dart' show AntiAliasingMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:vrlizate_scene/vrlizate_scene.dart';

void main() {
  group('VrQualityPreset', () {
    test('tiers are ordered by cost', () {
      expect(VrQualityPreset.low.pixelRatioScale,
          lessThan(VrQualityPreset.medium.pixelRatioScale));
      expect(VrQualityPreset.low.shadowMapResolution,
          lessThan(VrQualityPreset.high.shadowMapResolution));
      expect(VrQualityPreset.high.bloomEnabled, isTrue);
      expect(VrQualityPreset.low.bloomEnabled, isFalse);
    });

    test('forTier returns the matching constant', () {
      expect(VrQualityPreset.forTier(VrQualityTier.low),
          same(VrQualityPreset.low));
      expect(VrQualityPreset.forTier(VrQualityTier.high),
          same(VrQualityPreset.high));
    });

    test('stepDown lowers one tier and bottoms out at low', () {
      expect(VrQualityPreset.high.stepDown.tier, VrQualityTier.medium);
      expect(VrQualityPreset.medium.stepDown.tier, VrQualityTier.low);
      expect(VrQualityPreset.low.stepDown.tier, VrQualityTier.low);
    });

    test('high tier uses MSAA, lower tiers use FXAA', () {
      expect(VrQualityPreset.high.antiAliasing, AntiAliasingMode.msaa);
      expect(VrQualityPreset.medium.antiAliasing, AntiAliasingMode.fxaa);
      expect(VrQualityPreset.low.antiAliasing, AntiAliasingMode.fxaa);
    });
  });
}
