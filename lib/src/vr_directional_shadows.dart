import 'package:flutter_scene/scene.dart' show DirectionalLight;

import 'quality_preset.dart';

/// Explicit directional-shadow overrides, independent of light color and pose.
///
/// Null fields preserve the light's existing values. Shadow enablement and
/// static caching change only when explicitly supplied by the host. These
/// settings are rendering choices, not a guarantee of frame rate.
final class VrDirectionalShadowSettings {
  const VrDirectionalShadowSettings({
    this.mapResolution,
    this.cascadeCount,
    this.maxDistance,
    this.softness,
    this.fadeRange,
    this.castsShadow,
    this.cacheStaticShadows,
  });

  /// Mobile quality mapping used by the streamed OpenWorld demo.
  /// Other experiences can override the coverage and cascade counts.
  factory VrDirectionalShadowSettings.forQuality(
    VrQualityPreset preset, {
    int lowCascadeCount = 1,
    int cascadeCount = 2,
    double lowMaxDistance = 24,
    double maxDistance = 45,
  }) {
    final low = preset.tier == VrQualityTier.low;
    return VrDirectionalShadowSettings(
      mapResolution: preset.shadowMapResolution,
      cascadeCount: low ? lowCascadeCount : cascadeCount,
      maxDistance: low ? lowMaxDistance : maxDistance,
    );
  }

  /// Existing portable-world defaults. Resolution and casting remain owned by
  /// the host/light and authored environment, respectively.
  static const portableWorld = VrDirectionalShadowSettings(
    cascadeCount: 2,
    maxDistance: 65,
    softness: .14,
    fadeRange: 8,
  );

  final int? mapResolution, cascadeCount;
  final double? maxDistance, softness, fadeRange;
  final bool? castsShadow, cacheStaticShadows;

  /// Validates the whole request before changing any property on [light].
  void applyTo(DirectionalLight light) {
    final resolution = mapResolution;
    final cascades = cascadeCount;
    final distance = maxDistance;
    final soft = softness;
    final fade = fadeRange;
    if ((resolution != null && resolution < 1) ||
        (cascades != null && (cascades < 1 || cascades > 4)) ||
        (distance != null && (!distance.isFinite || distance <= 0)) ||
        (soft != null && (!soft.isFinite || soft < 0)) ||
        (fade != null && (!fade.isFinite || fade < 0))) {
      throw ArgumentError('Invalid directional shadow settings.');
    }
    if (resolution != null) light.shadowMapResolution = resolution;
    if (cascades != null) light.shadowCascadeCount = cascades;
    if (distance != null) light.shadowMaxDistance = distance;
    if (soft != null) light.shadowSoftness = soft;
    if (fade != null) light.shadowFadeRange = fade;
    if (castsShadow != null) light.castsShadow = castsShadow!;
    if (cacheStaticShadows != null) {
      light.cacheStaticShadows = cacheStaticShadows!;
    }
  }
}
