import '../constants/vr_scene_constants.dart';

/// Visual transition styles used when entering or exiting VR apps and portals.
enum VrSceneTransitionStyle {
  instant,
  smoothFade,
  portalIris,
  zoomSlide;

  /// Stable identifier for serialization and configuration.
  String get id => switch (this) {
    VrSceneTransitionStyle.instant => VrSceneConstants.transitionInstantId,
    VrSceneTransitionStyle.smoothFade =>
      VrSceneConstants.transitionSmoothFadeId,
    VrSceneTransitionStyle.portalIris =>
      VrSceneConstants.transitionPortalIrisId,
    VrSceneTransitionStyle.zoomSlide => VrSceneConstants.transitionZoomSlideId,
  };

  /// Peak field-of-view warp delta in degrees during transition.
  double get fovWarpDeltaDegrees => switch (this) {
    VrSceneTransitionStyle.instant => VrSceneConstants.instantWarpDeltaDegrees,
    VrSceneTransitionStyle.smoothFade =>
      VrSceneConstants.smoothFadeWarpDeltaDegrees,
    VrSceneTransitionStyle.portalIris =>
      VrSceneConstants.portalIrisWarpDeltaDegrees,
    VrSceneTransitionStyle.zoomSlide =>
      VrSceneConstants.zoomSlideWarpDeltaDegrees,
  };

  /// Whether this style completes immediately without interpolation.
  bool get isImmediate => this == VrSceneTransitionStyle.instant;

  /// Resolves a [VrSceneTransitionStyle] by its [id], defaulting to [smoothFade].
  static VrSceneTransitionStyle fromId(String id) {
    for (final style in VrSceneTransitionStyle.values) {
      if (style.id == id || style.name == id) {
        return style;
      }
    }
    return VrSceneTransitionStyle.smoothFade;
  }
}
