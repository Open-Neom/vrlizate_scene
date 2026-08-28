import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vrlizate_scene/vrlizate_scene.dart';

void main() {
  group('VrLook', () {
    test('standard applies AgX tone mapping and gentle bloom', () {
      final s = EnvironmentSettings();
      VrLook.standard.applyTo(s, VrQualityPreset.high);

      expect(s.toneMapping, ToneMappingMode.agx);
      expect(s.exposure, 1.0);
      expect(s.bloomEnabled, isTrue);
      expect(s.bloomIntensity, 0.15);
      // Off by default: vignette, fog, AO, grading.
      expect(s.vignetteEnabled, isFalse);
      expect(s.fogEnabled, isFalse);
      expect(s.ambientOcclusionEnabled, isFalse);
      expect(s.colorGradingEnabled, isFalse);
    });

    test('bloom is gated by the quality preset', () {
      final s = EnvironmentSettings();
      VrLook.standard.applyTo(s, VrQualityPreset.low); // bloomEnabled: false
      expect(s.bloomEnabled, isFalse);

      VrLook.standard.applyTo(s, VrQualityPreset.high);
      expect(s.bloomEnabled, isTrue);
    });

    test('ambient occlusion only runs on the high tier', () {
      final s = EnvironmentSettings();
      VrLook.cinematic.applyTo(s, VrQualityPreset.medium);
      expect(s.ambientOcclusionEnabled, isFalse);

      VrLook.cinematic.applyTo(s, VrQualityPreset.high);
      expect(s.ambientOcclusionEnabled, isTrue);
      expect(s.ambientOcclusionHalfResolution, isTrue);
    });

    test('cinematic enables grading, vignette and stronger bloom', () {
      final s = EnvironmentSettings();
      VrLook.cinematic.applyTo(s, VrQualityPreset.high);

      expect(s.colorGradingEnabled, isTrue);
      expect(s.contrast, 1.08);
      expect(s.saturation, 1.06);
      expect(s.vignetteEnabled, isTrue);
      expect(s.vignetteIntensity, 0.22);
      expect(s.bloomIntensity, greaterThan(VrLook.standard.bloomIntensity));
    });

    test('night enables exponential fog with visibility-derived density', () {
      final s = EnvironmentSettings();
      VrLook.night.applyTo(s, VrQualityPreset.medium);

      expect(s.fogEnabled, isTrue);
      expect(s.fogMode, FogMode.exponential);
      expect(s.fogDensity, closeTo(Fog.visibilityDensity(80), 1e-9));
      expect(s.exposure, lessThan(1.0));
    });

    test('a look with no fog leaves fog disabled', () {
      final s = EnvironmentSettings();
      VrLook.cinematic.applyTo(s, VrQualityPreset.high);
      expect(s.fogEnabled, isFalse);
    });
  });
}
