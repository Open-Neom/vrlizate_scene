import 'package:flutter_test/flutter_test.dart';
import 'package:vrlizate_scene/vrlizate_scene.dart';

void main() {
  group('VrGraphicsComfortSettings', () {
    test('resolves 1D handheld sharpness boost and explicit tier overrides', () {
      final settings = VrGraphicsComfortSettings();

      // In 1D single-camera mode, low tier promotes safely to medium (50% fewer draw calls).
      expect(
        settings.resolvePreset(VrQualityPreset.low, isHandheldMono: true),
        VrQualityPreset.medium,
      );
      // In stereo VR, low tier stays conservative to protect 60-90 Hz frame times.
      expect(
        settings.resolvePreset(VrQualityPreset.low, isHandheldMono: false),
        VrQualityPreset.low,
      );

      // Explicit user override (e.g. Ultra 1.15x SSAA) wins in both modes.
      settings.qualityOverride = VrQualityTier.ultra;
      expect(
        settings.resolvePreset(VrQualityPreset.low, isHandheldMono: false),
        VrQualityPreset.ultra,
      );
      expect(
        settings.resolvePreset(VrQualityPreset.medium, isHandheldMono: true),
        VrQualityPreset.ultra,
      );
    });

    test('resolves Qualcomm SGSR 1 auto and manual spatial upscaling modes', () {
      final settings = VrGraphicsComfortSettings();

      // Auto SGSR: activates mobileQuality (0.82x) in stereo VR on low/medium,
      // keeps 1D mono and high/ultra at native 1.0x clarity.
      expect(
        settings.resolveSgsrConfig(VrQualityPreset.medium, isStereo: true),
        VrSgsrUpscaleConfig.mobileQuality,
      );
      expect(
        settings.resolveSgsrConfig(VrQualityPreset.medium, isStereo: false),
        VrSgsrUpscaleConfig.disabled,
      );
      expect(
        settings.resolveSgsrConfig(VrQualityPreset.ultra, isStereo: true),
        VrSgsrUpscaleConfig.disabled,
      );

      settings.sgsrMode = VrSgsrMode.balanced;
      expect(
        settings.resolveSgsrConfig(VrQualityPreset.high, isStereo: false),
        VrSgsrUpscaleConfig.mobileBalanced,
      );
      settings.sgsrMode = VrSgsrMode.performance;
      expect(
        settings.resolveSgsrConfig(VrQualityPreset.high, isStereo: true),
        VrSgsrUpscaleConfig.mobilePerformance,
      );
      settings.sgsrMode = VrSgsrMode.off;
      expect(
        settings.resolveSgsrConfig(VrQualityPreset.low, isStereo: true),
        VrSgsrUpscaleConfig.disabled,
      );
    });

    test('computes anti-nausea stereo comfort vignette only during rapid VR motion', () {
      final settings = VrGraphicsComfortSettings();

      // Idle or gentle motion -> 0.0 (100% open FOV).
      expect(
        settings.computeComfortVignetteTarget(
          yawRateRadPerSec: 0.2,
          linearSpeedMetersPerSec: 1.4,
          isStereo: true,
        ),
        0.0,
      );

      // Fast yaw turn in stereo VR -> progressive peripheral vignette up to 0.38.
      final fastTurn = settings.computeComfortVignetteTarget(
        yawRateRadPerSec: 2.4,
        linearSpeedMetersPerSec: 0.0,
        isStereo: true,
      );
      expect(fastTurn, closeTo(0.38, 1e-6));

      // 1D handheld flat screen -> never vignettes.
      expect(
        settings.computeComfortVignetteTarget(
          yawRateRadPerSec: 2.4,
          linearSpeedMetersPerSec: 5.5,
          isStereo: false,
        ),
        0.0,
      );

      // Disabled by user -> always 0.0.
      settings.comfortVignetteEnabled = false;
      expect(
        settings.computeComfortVignetteTarget(
          yawRateRadPerSec: 3.0,
          linearSpeedMetersPerSec: 6.0,
          isStereo: true,
        ),
        0.0,
      );
    });

    test('formats compact live frame telemetry cleanly', () {
      const m = VrLiveFrameMetrics(
        fps: 89.6,
        frameMs: 11.16,
        tier: VrQualityTier.high,
        sgsrScale: 0.75,
        isStereo: true,
      );
      expect(m.compactLabel, '90 FPS · 11.2 ms · ALTA · SGSR 0.75× · VR');
    });
  });
}
