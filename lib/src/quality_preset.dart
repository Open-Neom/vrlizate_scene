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

  /// Budget devices (Mali-G52, Unisoc, entry/mid 720p 90Hz panels): stability first.
  static const low = VrQualityPreset(
    tier: VrQualityTier.low,
    pixelRatioScale: 0.75,
    antiAliasing: AntiAliasingMode.none,
    shadowMapResolution: 512,
    bloomEnabled: false,
  );

  /// Mid-range devices: native resolution, light FXAA, modest shadows.
  static const medium = VrQualityPreset(
    tier: VrQualityTier.medium,
    pixelRatioScale: 0.9,
    antiAliasing: AntiAliasingMode.fxaa,
    shadowMapResolution: 1024,
    bloomEnabled: false,
  );

  /// Flagships (S25 Ultra, Snapdragon 8 Elite, high DPR ≥ 2.7): full fidelity with MSAA and bloom.
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

  /// Tier heuristic from display characteristics.
  ///
  /// Note: Budget phones (like Moto G20) often have 90Hz panels but low DPR (<=2.0 / 720p)
  /// and low-end GPUs (Mali-G52). Flagships (S25 Ultra) have >=90Hz with high DPR (>=2.75 / 1080p+).
  static VrQualityTier detectTier(BuildContext context) {
    final view = View.of(context);
    final refreshRate = view.display.refreshRate;
    final dpr = view.devicePixelRatio;

    // True flagships: High refresh rate AND high display density / resolution.
    if (refreshRate >= 90 && dpr >= 2.7) return VrQualityTier.high;
    // Mid-range: Good density at 60Hz or high refresh rate with medium density.
    if (dpr >= 2.5 || (refreshRate >= 90 && dpr >= 2.2)) {
      return VrQualityTier.medium;
    }
    // Budget tier (e.g. Moto G20 with 720p screen, DPR ~1.75-2.0).
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
