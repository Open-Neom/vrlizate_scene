import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;
import 'package:vrlizate_scene/src/quality_preset.dart';
import 'package:vrlizate_scene/src/vr_directional_shadows.dart';

void main() {
  test('quality presets preserve the existing OpenWorld shadow values', () {
    for (final preset in [
      VrQualityPreset.low,
      VrQualityPreset.medium,
      VrQualityPreset.high,
      VrQualityPreset.ultra,
    ]) {
      final light = DirectionalLight(
        direction: vm.Vector3(1, -2, 3),
        color: vm.Vector3(.1, .2, .3),
        intensity: .7,
        castsShadow: true,
        cacheStaticShadows: false,
        shadowSoftness: .19,
        shadowFadeRange: 6,
      );
      VrDirectionalShadowSettings.forQuality(preset).applyTo(light);
      final low = preset.tier == VrQualityTier.low;
      expect(light.shadowMapResolution, preset.shadowMapResolution);
      expect(light.shadowCascadeCount, low ? 1 : 2);
      expect(light.shadowMaxDistance, low ? 24 : 45);
      expect(light.direction, vm.Vector3(1, -2, 3));
      expect(light.color, vm.Vector3(.1, .2, .3));
      expect(light.intensity, .7);
      expect(light.castsShadow, isTrue);
      expect(light.cacheStaticShadows, isFalse);
      expect(light.shadowSoftness, .19);
      expect(light.shadowFadeRange, 6);
    }
  });

  test('portable defaults preserve authored casting and resolution', () {
    for (final casts in [false, true]) {
      final light = DirectionalLight(
        castsShadow: casts,
        shadowMapResolution: 2048,
        shadowDepthBias: .03,
        shadowNormalBias: .04,
      );
      VrDirectionalShadowSettings.portableWorld.applyTo(light);
      expect(light.shadowCascadeCount, 2);
      expect(light.shadowMaxDistance, 65);
      expect(light.shadowSoftness, .14);
      expect(light.shadowFadeRange, 8);
      expect(light.castsShadow, casts);
      expect(light.shadowMapResolution, 2048);
      expect(light.shadowDepthBias, .03);
      expect(light.shadowNormalBias, .04);
    }
  });

  test('host quality coverage and cascade overrides remain explicit', () {
    for (final preset in [VrQualityPreset.low, VrQualityPreset.high]) {
      final light = DirectionalLight();
      VrDirectionalShadowSettings.forQuality(
        preset,
        lowCascadeCount: 2,
        cascadeCount: 3,
        lowMaxDistance: 18,
        maxDistance: 52,
      ).applyTo(light);
      final low = preset.tier == VrQualityTier.low;
      expect(light.shadowCascadeCount, low ? 2 : 3);
      expect(light.shadowMaxDistance, low ? 18 : 52);
      expect(light.castsShadow, isFalse);
    }
  });

  test('a partial override does not replace other light properties', () {
    final light = DirectionalLight(shadowCascadeCount: 3);
    const VrDirectionalShadowSettings(
      mapResolution: 256,
      castsShadow: true,
      cacheStaticShadows: false,
    ).applyTo(light);
    expect(light.shadowMapResolution, 256);
    expect(light.shadowCascadeCount, 3);
    expect(light.castsShadow, isTrue);
    expect(light.cacheStaticShadows, isFalse);
    const VrDirectionalShadowSettings().applyTo(light);
    expect(light.shadowMapResolution, 256);
    expect(light.shadowCascadeCount, 3);
    expect(light.castsShadow, isTrue);
    expect(light.cacheStaticShadows, isFalse);
  });

  test('invalid overrides fail before partially mutating the light', () {
    for (final settings in [
      const VrDirectionalShadowSettings(mapResolution: 0),
      const VrDirectionalShadowSettings(cascadeCount: 0),
      const VrDirectionalShadowSettings(cascadeCount: 5),
      const VrDirectionalShadowSettings(maxDistance: double.nan),
      const VrDirectionalShadowSettings(maxDistance: 0),
      const VrDirectionalShadowSettings(softness: -1),
      const VrDirectionalShadowSettings(fadeRange: double.infinity),
      const VrDirectionalShadowSettings(mapResolution: 256, fadeRange: -1),
    ]) {
      final light = DirectionalLight();
      expect(() => settings.applyTo(light), throwsArgumentError);
      expect(light.shadowMapResolution, 1024);
      expect(light.shadowCascadeCount, 4);
      expect(light.shadowMaxDistance, 150);
      expect(light.shadowSoftness, .08);
      expect(light.shadowFadeRange, 2);
    }
  });
}
