import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'quality_preset.dart';

/// A shared visual "look" for vrlizate_scene GPU demos.
///
/// One value object upgrades every demo at once: tone mapping, exposure,
/// color grading, HDR bloom, vignette (doubles as a VR comfort aid),
/// exponential fog and ambient occlusion — all scaled by the active
/// [VrQualityPreset] so budget phones keep a stable frame rate:
///
/// - Bloom only runs when the preset allows it (`preset.bloomEnabled`).
/// - Ambient occlusion only runs on the high tier, at half resolution.
/// - Fog, tone mapping, grading and vignette are cheap and run everywhere.
///
/// Usage:
/// ```dart
/// StereoSceneView(scene: scene, look: VrLook.cinematic, ...);
/// // or directly:
/// VrLook.night.applyToScene(scene, VrQualityPreset.medium);
/// ```
class VrLook {
  const VrLook({
    this.toneMapping = ToneMappingMode.agx,
    this.exposure = 1.0,
    this.saturation = 1.0,
    this.contrast = 1.0,
    this.bloomIntensity = 0.2,
    this.bloomThreshold = 1.0,
    this.vignetteIntensity = 0.0,
    this.fogColor,
    this.fogVisibilityMeters = 0.0,
    this.ambientOcclusion = false,
  });

  /// Tone mapping operator. AgX preserves bright hues better than the
  /// engine default (PBR Neutral) on emissive-heavy VR scenes.
  final ToneMappingMode toneMapping;

  /// Linear exposure multiplier (1.0 = unchanged).
  final double exposure;

  /// Color grading saturation (1.0 = unchanged).
  final double saturation;

  /// Color grading contrast (1.0 = unchanged).
  final double contrast;

  /// HDR bloom intensity (0 = off). Gated by `preset.bloomEnabled`.
  final double bloomIntensity;

  /// Luminance threshold above which bloom picks up highlights.
  final double bloomThreshold;

  /// Vignette strength (0 = off). A mild vignette also reduces peripheral
  /// motion sickness in VR.
  final double vignetteIntensity;

  /// Fog color (linear, not sRGB). Null disables fog.
  final vm.Vector3? fogColor;

  /// Distance in meters at which geometry fades to a low-contrast haze
  /// (Koschmieder visibility). 0 disables fog.
  final double fogVisibilityMeters;

  /// Whether to run ambient occlusion (high tier only, half resolution).
  final bool ambientOcclusion;

  /// Clean default: AgX + gentle bloom. Safe for every GPU demo.
  static const standard = VrLook(bloomIntensity: 0.15);

  /// Booth/showpiece: richer contrast, visible bloom, mild vignette and AO.
  static const cinematic = VrLook(
    exposure: 1.05,
    saturation: 1.06,
    contrast: 1.08,
    bloomIntensity: 0.3,
    bloomThreshold: 0.9,
    vignetteIntensity: 0.22,
    ambientOcclusion: true,
  );

  /// Dark scenes (space, night worlds): lower exposure, cool haze.
  static final night = VrLook(
    exposure: 0.85,
    contrast: 1.05,
    bloomIntensity: 0.4,
    bloomThreshold: 0.8,
    vignetteIntensity: 0.25,
    fogColor: vm.Vector3(0.02, 0.03, 0.07),
    fogVisibilityMeters: 80,
  );

  /// High-voltage cyber/neon aesthetic: deep pitch blacks, radiant cyan/magenta bloom, high contrast.
  static const cyberpunk = VrLook(
    exposure: 1.12,
    saturation: 1.25,
    contrast: 1.18,
    bloomIntensity: 0.48,
    bloomThreshold: 0.75,
    vignetteIntensity: 0.28,
    ambientOcclusion: true,
  );

  /// Deep space & nebula aesthetic: cosmic atmosphere, high starlight exposure and gentle cosmic fog.
  static final stellar = VrLook(
    exposure: 0.95,
    saturation: 1.15,
    contrast: 1.12,
    bloomIntensity: 0.42,
    bloomThreshold: 0.82,
    vignetteIntensity: 0.20,
    fogColor: vm.Vector3(0.01, 0.02, 0.05),
    fogVisibilityMeters: 120,
    ambientOcclusion: true,
  );

  /// Writes this look into a live [EnvironmentSettings] snapshot, scaled by
  /// [preset]. Pure and allocation-free — safe to call on tier changes.
  void applyTo(EnvironmentSettings s, VrQualityPreset preset) {
    s.toneMapping = toneMapping;
    s.exposure = exposure;

    final grading = saturation != 1.0 || contrast != 1.0;
    s.colorGradingEnabled = grading;
    if (grading) {
      s.saturation = saturation;
      s.contrast = contrast;
    }

    final bloom = preset.bloomEnabled && bloomIntensity > 0.0;
    s.bloomEnabled = bloom;
    if (bloom) {
      s.bloomIntensity = bloomIntensity;
      s.bloomThreshold = bloomThreshold;
    }

    final vignette = vignetteIntensity > 0.0;
    s.vignetteEnabled = vignette;
    if (vignette) s.vignetteIntensity = vignetteIntensity;

    final fog = fogColor != null && fogVisibilityMeters > 0.0;
    s.fogEnabled = fog;
    if (fog) {
      s.fogMode = FogMode.exponential;
      s.fogColor = fogColor!;
      s.fogDensity = Fog.visibilityDensity(fogVisibilityMeters);
    }

    final ao = ambientOcclusion && preset.tier == VrQualityTier.high;
    s.ambientOcclusionEnabled = ao;
    if (ao) {
      s.ambientOcclusionIntensity = 0.6;
      s.ambientOcclusionHalfResolution = true;
    }
  }

  /// Snapshots the scene look, applies this look scaled by [preset], and
  /// writes it back (see [Scene.environmentSettings]).
  void applyToScene(Scene scene, VrQualityPreset preset) {
    final s = scene.environmentSettings;
    applyTo(s, preset);
    scene.environmentSettings = s;
  }
}
