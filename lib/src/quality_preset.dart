import 'package:flutter/widgets.dart';
import 'package:flutter_scene/scene.dart' show AntiAliasingMode;

/// Device performance tier for VR rendering.
enum VrQualityTier { low, medium, high, ultra }

/// Quality settings for GPU VR rendering, applied by `StereoSceneView`.
///
/// Explicit quality choices, not a guarantee of frame rate or thermal safety.
/// Native resolution is the starting point for mid-range/flagship viewers;
/// validate the active stereo scene on the actual phone and lenses.
class VrQualityPreset {
  const VrQualityPreset({
    required this.tier,
    required this.pixelRatioScale,
    required this.antiAliasing,
    required this.shadowMapResolution,
    required this.bloomEnabled,
  });

  final VrQualityTier tier;

  /// Multiplier over the device pixel ratio (1.0 = native resolution, 1.15 = supersampling).
  final double pixelRatioScale;

  /// Scene anti-aliasing technique.
  final AntiAliasingMode antiAliasing;

  /// Shadow map size apps should use when creating shadow-casting lights.
  final int shadowMapResolution;

  /// Whether HDR bloom post-processing runs.
  final bool bloomEnabled;

  /// Budget devices (Mali-G52/G57, Unisoc, entry/mid panels): stability first.
  ///
  /// 0.6× native renders ~36% of the pixels of [medium]. Through Cardboard
  /// lenses the eye sees a magnified quarter-screen, so the loss is mostly in
  /// the blurred periphery; a measured raster time of 9–13× the 60 Hz budget
  /// on a Dimensity 720 (see docs/STABILIZATION_2026-09-12.md) showed 0.75×
  /// was not a stability floor. Dynamic scaling lands here after [medium].
  static const low = VrQualityPreset(
    tier: VrQualityTier.low,
    pixelRatioScale: 0.6,
    antiAliasing: AntiAliasingMode.none,
    shadowMapResolution: 512,
    bloomEnabled: false,
  );

  /// Mid-range devices: native resolution, MSAA where the backend has it
  /// (FXAA otherwise), modest shadows.
  ///
  /// [AntiAliasingMode.auto] resolves to 4× MSAA on Impeller's Metal/Vulkan
  /// backends, where flutter_scene allocates the multisample color target as
  /// `deviceTransient` — it lives in tile memory and never round-trips to
  /// RAM, so on mobile it costs coverage, not bandwidth. FXAA, by contrast,
  /// is a full-screen post pass that softens every high-contrast edge,
  /// label text included: exactly the definition a stereo lens magnifies
  /// the loss of. The 2026-09-12 profile put the raster cost in per-pixel
  /// shading, which MSAA does not multiply. Needs device validation on the
  /// Dimensity/Mali tier; revert to `fxaa` here if it regresses.
  static const medium = VrQualityPreset(
    tier: VrQualityTier.medium,
    pixelRatioScale: 1.0,
    antiAliasing: AntiAliasingMode.auto,
    shadowMapResolution: 1024,
    bloomEnabled: false,
  );

  /// High tier: native resolution with MSAA. Bloom is opt-in (ultra).
  static const high = VrQualityPreset(
    tier: VrQualityTier.high,
    pixelRatioScale: 1.0,
    antiAliasing: AntiAliasingMode.msaa,
    shadowMapResolution: 2048,
    bloomEnabled: false,
  );

  /// Ultra tier: razor-sharp 1.15x supersampling, MSAA and HDR bloom for maximum VR lens clarity.
  static const ultra = VrQualityPreset(
    tier: VrQualityTier.ultra,
    pixelRatioScale: 1.15,
    antiAliasing: AntiAliasingMode.msaa,
    shadowMapResolution: 2048,
    bloomEnabled: true,
  );

  static VrQualityPreset forTier(VrQualityTier tier) => switch (tier) {
    VrQualityTier.low => low,
    VrQualityTier.medium => medium,
    VrQualityTier.high => high,
    VrQualityTier.ultra => ultra,
  };

  /// Conservative initial tier until profiling or an explicit user choice.
  /// Display refresh rate/DPR do not measure GPU capability; a 120 Hz screen
  /// is not evidence that two VR views can be rendered at 120 FPS.
  static VrQualityTier detectTier(BuildContext context) {
    return VrQualityTier.medium;
  }

  /// Resolves [preset] or auto-detects from the display when null.
  static VrQualityPreset resolve(
    BuildContext context,
    VrQualityPreset? preset,
  ) => preset ?? forTier(detectTier(context));

  /// The next tier down, for dynamic frame-time-based downscaling.
  VrQualityPreset get stepDown => switch (tier) {
    VrQualityTier.ultra => high,
    VrQualityTier.high => medium,
    VrQualityTier.medium => low,
    VrQualityTier.low => low,
  };

  /// The next tier up, for dynamic resolution recovery when performance is stable.
  VrQualityPreset get stepUp => switch (tier) {
    VrQualityTier.low => medium,
    VrQualityTier.medium => high,
    VrQualityTier.high => ultra,
    VrQualityTier.ultra => ultra,
  };
}
