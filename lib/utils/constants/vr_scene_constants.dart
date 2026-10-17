/// Shared constants for `vrlizate_scene` stereo rendering, lighting presets,
/// and spatial scene transitions.
abstract final class VrSceneConstants {
  static const double defaultConvergenceDistanceMeters = 1.8;
  static const double defaultIpdMeters = 0.064;
  static const double defaultGazeDwellSeconds = 1.2;

  static const int defaultTransitionDurationMs = 450;
  static const double minTransitionProgress = 0.0;
  static const double maxTransitionProgress = 1.0;
  static const double smoothstepFactorA = 3.0;
  static const double smoothstepFactorB = 2.0;

  static const double defaultBaseFovDegrees = 90.0;
  static const double instantWarpDeltaDegrees = 0.0;
  static const double smoothFadeWarpDeltaDegrees = 6.0;
  static const double portalIrisWarpDeltaDegrees = 18.0;
  static const double zoomSlideWarpDeltaDegrees = 24.0;

  static const double minIrisAperture = 0.0;
  static const double maxIrisAperture = 1.0;

  static const String lightingDaylightId = 'daylight';
  static const String lightingNeonArcadeId = 'neon_arcade';
  static const String lightingWarmGalleryId = 'warm_gallery';
  static const String lightingDeepSpaceId = 'deep_space';
  static const String lightingSunsetId = 'sunset';

  static const int daylightAmbientArgb = 0xFFE8F4FF;
  static const int daylightDirectionalArgb = 0xFFFFF8E7;
  static const double daylightAmbientIntensity = 0.75;
  static const double daylightDirectionalIntensity = 1.20;

  static const int neonArcadeAmbientArgb = 0xFF1A103C;
  static const int neonArcadeDirectionalArgb = 0xFF00F0FF;
  static const double neonArcadeAmbientIntensity = 0.45;
  static const double neonArcadeDirectionalIntensity = 1.35;

  static const int warmGalleryAmbientArgb = 0xFFF5EBE1;
  static const int warmGalleryDirectionalArgb = 0xFFFFDFB8;
  static const double warmGalleryAmbientIntensity = 0.65;
  static const double warmGalleryDirectionalIntensity = 1.00;

  static const int deepSpaceAmbientArgb = 0xFF090C1C;
  static const int deepSpaceDirectionalArgb = 0xFF8AA8FF;
  static const double deepSpaceAmbientIntensity = 0.25;
  static const double deepSpaceDirectionalIntensity = 0.90;

  static const int sunsetAmbientArgb = 0xFF3E1F47;
  static const int sunsetDirectionalArgb = 0xFFFF7B54;
  static const double sunsetAmbientIntensity = 0.55;
  static const double sunsetDirectionalIntensity = 1.10;

  static const String transitionInstantId = 'instant';
  static const String transitionSmoothFadeId = 'smooth_fade';
  static const String transitionPortalIrisId = 'portal_iris';
  static const String transitionZoomSlideId = 'zoom_slide';
}
