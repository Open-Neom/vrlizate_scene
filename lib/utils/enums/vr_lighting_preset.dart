import '../constants/vr_scene_constants.dart';

/// Curated lighting presets for stereoscopic 3D VR scenes.
enum VrLightingPreset {
  daylight,
  neonArcade,
  warmGallery,
  deepSpace,
  sunset;

  /// Stable identifier for serialization and configuration.
  String get id => switch (this) {
    VrLightingPreset.daylight => VrSceneConstants.lightingDaylightId,
    VrLightingPreset.neonArcade => VrSceneConstants.lightingNeonArcadeId,
    VrLightingPreset.warmGallery => VrSceneConstants.lightingWarmGalleryId,
    VrLightingPreset.deepSpace => VrSceneConstants.lightingDeepSpaceId,
    VrLightingPreset.sunset => VrSceneConstants.lightingSunsetId,
  };

  /// Ambient fill color in 32-bit ARGB format.
  int get ambientColorArgb => switch (this) {
    VrLightingPreset.daylight => VrSceneConstants.daylightAmbientArgb,
    VrLightingPreset.neonArcade => VrSceneConstants.neonArcadeAmbientArgb,
    VrLightingPreset.warmGallery => VrSceneConstants.warmGalleryAmbientArgb,
    VrLightingPreset.deepSpace => VrSceneConstants.deepSpaceAmbientArgb,
    VrLightingPreset.sunset => VrSceneConstants.sunsetAmbientArgb,
  };

  /// Key directional light color in 32-bit ARGB format.
  int get directionalColorArgb => switch (this) {
    VrLightingPreset.daylight => VrSceneConstants.daylightDirectionalArgb,
    VrLightingPreset.neonArcade => VrSceneConstants.neonArcadeDirectionalArgb,
    VrLightingPreset.warmGallery => VrSceneConstants.warmGalleryDirectionalArgb,
    VrLightingPreset.deepSpace => VrSceneConstants.deepSpaceDirectionalArgb,
    VrLightingPreset.sunset => VrSceneConstants.sunsetDirectionalArgb,
  };

  /// Relative ambient light intensity.
  double get ambientIntensity => switch (this) {
    VrLightingPreset.daylight => VrSceneConstants.daylightAmbientIntensity,
    VrLightingPreset.neonArcade => VrSceneConstants.neonArcadeAmbientIntensity,
    VrLightingPreset.warmGallery =>
      VrSceneConstants.warmGalleryAmbientIntensity,
    VrLightingPreset.deepSpace => VrSceneConstants.deepSpaceAmbientIntensity,
    VrLightingPreset.sunset => VrSceneConstants.sunsetAmbientIntensity,
  };

  /// Relative key directional light intensity.
  double get directionalIntensity => switch (this) {
    VrLightingPreset.daylight => VrSceneConstants.daylightDirectionalIntensity,
    VrLightingPreset.neonArcade =>
      VrSceneConstants.neonArcadeDirectionalIntensity,
    VrLightingPreset.warmGallery =>
      VrSceneConstants.warmGalleryDirectionalIntensity,
    VrLightingPreset.deepSpace =>
      VrSceneConstants.deepSpaceDirectionalIntensity,
    VrLightingPreset.sunset => VrSceneConstants.sunsetDirectionalIntensity,
  };

  /// Resolves a [VrLightingPreset] by its [id], defaulting to [daylight].
  static VrLightingPreset fromId(String id) {
    for (final preset in VrLightingPreset.values) {
      if (preset.id == id || preset.name == id) {
        return preset;
      }
    }
    return VrLightingPreset.daylight;
  }
}
