import 'package:flutter/painting.dart';

/// Perceptual metric depth zone relative to the viewer's eyes or active camera.
enum VrDepthZone {
  /// `<= 0.35 m` — Immediate contact / physical desk or visor proximity alert.
  nearContact,

  /// `0.35 m – 0.75 m` — Optimal ergonomic hand & `eMudra` interaction zone.
  activeReach,

  /// `0.75 m – 1.50 m` — Mid-range personal space.
  midSpace,

  /// `> 1.50 m` — Far room / horizon background.
  farHorizon,
}

/// SDK-wide metric depth-to-color mapping for 3D spatial contours, skeletons,
/// and holographic hands across `.vrlz` and `.vrlw` experiences.
///
/// Shifts line and hand colors smoothly according to real metric distance (`m`)
/// so monocular and stereoscopic depth perception reinforce each other:
/// - `<= 0.20 m`: Coral Red (`#FF5252`) — immediate proximity warning
/// - `0.35 m`: Warm Amber (`#FFAB00`) — near boundary
/// - `0.52 m`: Bio-Emerald (`#00E676`) — sweet-spot `eMudra` reach
/// - `0.78 m`: Neon Cyan (`#00E5FF`) — comfortable arm extension
/// - `1.45 m`: Electric Azure (`#2979FF`) — mid-room boundary
/// - `>= 2.85 m`: Deep Cyber Violet (`#7C4DFF`) — far horizon
abstract final class VrDepthColorPalette {
  static const Color nearCoral = Color(0xFFFF5252);
  static const Color nearAmber = Color(0xFFFFAB00);
  static const Color reachEmerald = Color(0xFF00E676);
  static const Color reachCyan = Color(0xFF00E5FF);
  static const Color midAzure = Color(0xFF2979FF);
  static const Color farViolet = Color(0xFF7C4DFF);

  static const List<(double, Color)> _stops = <(double, Color)>[
    (0.18, nearCoral),
    (0.34, nearAmber),
    (0.52, reachEmerald),
    (0.78, reachCyan),
    (1.45, midAzure),
    (2.85, farViolet),
  ];

  /// Classifies a metric distance (`meters`) into its semantic [VrDepthZone].
  static VrDepthZone zoneForDistanceMeters(double distanceMeters) {
    final d = distanceMeters.isFinite ? distanceMeters : 1.0;
    if (d <= 0.35) return VrDepthZone.nearContact;
    if (d <= 0.75) return VrDepthZone.activeReach;
    if (d <= 1.50) return VrDepthZone.midSpace;
    return VrDepthZone.farHorizon;
  }

  /// Human-readable Spanish label for HUDs and camera inspectors.
  static String labelForDistanceMeters(double distanceMeters) {
    return switch (zoneForDistanceMeters(distanceMeters)) {
      VrDepthZone.nearContact => 'Cercano / Alerta',
      VrDepthZone.activeReach => 'Zona eMudra Óptima',
      VrDepthZone.midSpace => 'Espacio Medio',
      VrDepthZone.farHorizon => 'Fondo Profundo',
    };
  }

  /// Continuous piecewise-linear perceptual interpolation from metric distance
  /// (`meters`) to a vivid neon spatial [Color].
  static Color colorForDistanceMeters(
    double distanceMeters, {
    double alpha = 1.0,
  }) {
    final clampedAlpha = alpha.clamp(0.0, 1.0);
    if (!distanceMeters.isFinite) {
      return reachCyan.withValues(alpha: clampedAlpha);
    }
    final d = distanceMeters.clamp(_stops.first.$1, _stops.last.$1);
    for (var i = 0; i < _stops.length - 1; i++) {
      final (d0, c0) = _stops[i];
      final (d1, c1) = _stops[i + 1];
      if (d <= d1) {
        final t = ((d - d0) / (d1 - d0)).clamp(0.0, 1.0);
        return (Color.lerp(c0, c1, t) ?? c1).withValues(alpha: clampedAlpha);
      }
    }
    return _stops.last.$2.withValues(alpha: clampedAlpha);
  }

  /// Blends an object's semantic category [baseColor] with its metric depth
  /// color according to [depthBlend] (`0.0` = category only, `1.0` = pure depth).
  static Color blendWithCategory(
    Color baseColor,
    double distanceMeters, {
    double depthBlend = 0.85,
    double alpha = 1.0,
  }) {
    final depthColor = colorForDistanceMeters(distanceMeters, alpha: 1.0);
    final mixed =
        Color.lerp(baseColor, depthColor, depthBlend.clamp(0.0, 1.0)) ??
        depthColor;
    return mixed.withValues(alpha: alpha.clamp(0.0, 1.0));
  }

  /// Perspective stroke thickness multiplier (`1.30x` very close -> `0.74x` far)
  /// reinforcing depth ordering without visual clutter.
  static double strokeScaleForDistanceMeters(double distanceMeters) {
    if (!distanceMeters.isFinite) return 1.0;
    final normalized = ((distanceMeters - 0.20) / 2.40).clamp(0.0, 1.0);
    return 1.30 - 0.56 * normalized;
  }
}
