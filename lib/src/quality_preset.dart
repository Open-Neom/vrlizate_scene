import 'package:flutter/widgets.dart';
import 'package:flutter_scene/scene.dart' show AntiAliasingMode;

/// Device performance tier for VR rendering.
enum VrQualityTier { low, medium, high }

/// Quality settings for GPU VR rendering, applied by `StereoSceneView`.
///
/// Presets scale resolution, anti-aliasing, shadow resolution and bloom so
/// the same scene runs at a stable frame rate on a budget phone (Moto G20
/// class) and at full fidelity on a modern flagship.
class VrQualityPreset {
  const VrQualityPreset({
    required this.tier,
    required this.pixelRatioScale,
    required this.antiAliasing,
    required this.shadowMapResolution,
    required this.bloomEnabled,
  });

  final VrQualityTier tier;

  /// Multiplier over the device pixel ratio (1.0 = native resolution).
  final double pixelRatioScale;

  /// Scene anti-aliasing technique.
  final AntiAliasingMode antiAliasing;

  /// Shadow map size apps should use when creating shadow-casting lights.
  final int shadowMapResolution;

  /// Whether HDR bloom post-processing runs.
  final bool bloomEnabled;

  /// Budget devices (≤60 Hz panels, low-tier GPUs): stability first.
  static const low = VrQualityPreset(
    tier: VrQualityTier.low,
    pixelRatioScale: 0.75,
    antiAliasing: AntiAliasingMode.fxaa,
    shadowMapResolution: 512,
    bloomEnabled: false,
  );

  /// Mid-range devices: native resolution, cheap AA, modest shadows.
  static const medium = VrQualityPreset(
    tier: VrQualityTier.medium,
    pixelRatioScale: 1.0,
    antiAliasing: AntiAliasingMode.fxaa,
    shadowMapResolution: 1024,
    bloomEnabled: false,
  );

  /// Flagships (≥90 Hz panels): full fidelity with MSAA and bloom.
  static const high = VrQualityPreset(
    tier: VrQualityTier.high,
    pixelRatioScale: 1.0,
    antiAliasing: AntiAliasingMode.msaa,
    shadowMapResolution: 2048,
    bloomEnabled: true,
  );

  static VrQualityPreset forTier(VrQualityTier tier) => switch (tier) {
        VrQualityTier.low => low,
        VrQualityTier.medium => medium,
        VrQualityTier.high => high,
      };

  /// Static tier heuristic from display characteristics — no plugins.
  ///
  /// High refresh rate panels (≥90 Hz) correlate strongly with flagship
  /// SoCs; a high device pixel ratio adds supporting signal. Anything at
  /// 60 Hz with a modest DPR is treated as low tier.
  static VrQualityTier detectTier(BuildContext context) {
    final view = View.of(context);
    final refreshRate = view.display.refreshRate;
    final dpr = view.devicePixelRatio;
    if (refreshRate >= 90) return VrQualityTier.high;
    if (refreshRate >= 60 && dpr >= 3.0) return VrQualityTier.medium;
    return VrQualityTier.low;
  }

  /// Resolves [preset] or auto-detects from the display when null.
  static VrQualityPreset resolve(BuildContext context, VrQualityPreset? preset) =>
      preset ?? forTier(detectTier(context));

  /// The next tier down, for dynamic frame-time-based downscaling.
  VrQualityPreset get stepDown => switch (tier) {
        VrQualityTier.high => medium,
        VrQualityTier.medium => low,
        VrQualityTier.low => low,
      };
}
