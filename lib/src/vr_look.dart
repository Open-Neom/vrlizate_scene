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
    this.barrelDistortionK1 = 0.0,
    this.barrelDistortionK2 = 0.0,
    this.chromaticAberrationOffset = 0.0,
  });

  /// Tone mapping operator. AgX preserves bright hues better than the
  /// engine default (PBR Neutral) on emissive-heavy VR scenes.
  final ToneMappingMode toneMapping;

  /// Radial lens distortion coefficient k1 (Brown-Conrady model).
  /// Counteracts pincushion distortion of VR lenses. 0 = disabled.
  final double barrelDistortionK1;

  /// Radial lens distortion coefficient k2. 0 = disabled.
  final double barrelDistortionK2;

  /// Lateral chromatic aberration offset factor across lens edges. 0 = disabled.
  final double chromaticAberrationOffset;

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

  /// Creates a simple opaque PBR material from already-linear RGB channels.
  ///
  /// Authored sRGB palettes must convert before calling this method. An omitted
  /// [emission] preserves the renderer's default emissive factor; otherwise its
  /// RGB channels are the supplied color multiplied by that strength.
  static PhysicallyBasedMaterial material(
    double r,
    double g,
    double b, {
    double roughness = 0.8,
    double metallic = 0,
    double? emission,
  }) {
    final material = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(r, g, b, 1)
      ..roughnessFactor = roughness
      ..metallicFactor = metallic
      ..vertexColorWeight = 0;
    if (emission != null) {
      material.emissiveFactor = vm.Vector4(
        r * emission,
        g * emission,
        b * emission,
        0,
      );
    }
    return material;
  }

  /// Writes this look into a live [EnvironmentSettings] snapshot, scaled by
  /// [preset]. Pure and allocation-free — safe to call on tier changes.
  void applyTo(EnvironmentSettings s, VrQualityPreset preset) {
    s.toneMapping = toneMapping;
    if (toneMapping == ToneMappingMode.agx) {
      s.agxContrast = 1.26;
    }
    s.exposure = (exposure.isFinite && exposure >= 0.0) ? exposure : 1.0;

    final safeSat =
        (saturation.isFinite && saturation >= 0.0) ? saturation : 1.0;
    final safeCon = (contrast.isFinite && contrast >= 0.0) ? contrast : 1.0;
    final grading = safeSat != 1.0 || safeCon != 1.0;
    s.colorGradingEnabled = grading;
    if (grading) {
      s.saturation = safeSat;
      s.contrast = safeCon;
    }

    final safeBloom =
        (bloomIntensity.isFinite && bloomIntensity > 0.0) ? bloomIntensity : 0.0;
    final safeBloomThresh =
        (bloomThreshold.isFinite && bloomThreshold >= 0.0)
            ? bloomThreshold
            : 1.0;
    final bloom = preset.bloomEnabled && safeBloom > 0.0;
    s.bloomEnabled = bloom;
    if (bloom) {
      s.bloomIntensity = safeBloom;
      s.bloomThreshold = safeBloomThresh;
      s.bloomScatter = 0.72;
    }

    final safeVignette =
        (vignetteIntensity.isFinite && vignetteIntensity > 0.0)
            ? vignetteIntensity.clamp(0.0, 1.0)
            : 0.0;
    final vignette = safeVignette > 0.0;
    s.vignetteEnabled = vignette;
    if (vignette) s.vignetteIntensity = safeVignette;

    final validFogColor =
        fogColor != null &&
        fogColor!.x.isFinite &&
        fogColor!.y.isFinite &&
        fogColor!.z.isFinite;
    final fog =
        validFogColor &&
        fogVisibilityMeters.isFinite &&
        fogVisibilityMeters > 0.0;
    s.fogEnabled = fog;
    if (fog) {
      s.fogMode = FogMode.exponential;
      s.fogColor = fogColor!;
      s.fogDensity = Fog.visibilityDensity(fogVisibilityMeters);
      s.fogSkyColorInfluence = 0.28;
      s.fogSunInScatter = 0.22;
    } else {
      s.fogSkyColorInfluence = 0.0;
      s.fogSunInScatter = 0.0;
    }

    final ao =
        ambientOcclusion && preset.tier.index >= VrQualityTier.high.index;
    s.ambientOcclusionEnabled = ao;
    if (ao) {
      final ultra = preset.tier == VrQualityTier.ultra;
      s.ambientOcclusionMethod = AmbientOcclusionMethod.groundTruth;
      s.ambientOcclusionIntensity = 0.82;
      s.ambientOcclusionRadius = 0.40;
      s.ambientOcclusionMultiBounce = 0.65;
      s.ambientOcclusionDirectLightAffect = 0.18;
      s.ambientOcclusionHalfResolution = true;
      s.ambientOcclusionBentNormals = ultra;
      s.ambientOcclusionSpecularMode = ultra
          ? SpecularAmbientOcclusionMode.bentCone
          : SpecularAmbientOcclusionMode.simple;
    } else {
      s.ambientOcclusionBentNormals = false;
      s.ambientOcclusionSpecularMode = SpecularAmbientOcclusionMode.none;
    }
  }

  /// Snapshots the scene look, applies this look scaled by [preset], and
  /// writes it back (see [Scene.environmentSettings]).
  void applyToScene(Scene scene, VrQualityPreset preset) {
    final s = scene.environmentSettings;
    applyTo(s, preset);
    scene.environmentSettings = s;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VrLook &&
          other.toneMapping == toneMapping &&
          other.exposure == exposure &&
          other.saturation == saturation &&
          other.contrast == contrast &&
          other.bloomIntensity == bloomIntensity &&
          other.bloomThreshold == bloomThreshold &&
          other.vignetteIntensity == vignetteIntensity &&
          other.fogColor == fogColor &&
          other.fogVisibilityMeters == fogVisibilityMeters &&
          other.ambientOcclusion == ambientOcclusion &&
          other.barrelDistortionK1 == barrelDistortionK1 &&
          other.barrelDistortionK2 == barrelDistortionK2 &&
          other.chromaticAberrationOffset == chromaticAberrationOffset;

  @override
  int get hashCode => Object.hash(
    toneMapping,
    exposure,
    saturation,
    contrast,
    bloomIntensity,
    bloomThreshold,
    vignetteIntensity,
    fogColor,
    fogVisibilityMeters,
    ambientOcclusion,
    barrelDistortionK1,
    barrelDistortionK2,
    chromaticAberrationOffset,
  );
}
