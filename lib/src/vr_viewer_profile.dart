import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'stereo_head_rig.dart';

/// User/viewer optical alignment and optional barrel / RGB chromatic aberration
/// lens pre-distortion parameters, independent from hardware quality presets.
///
/// Settings belong to user + physical viewer shell (including biconvex,
/// short-focal aspheric, and folded 22mm Pancake optics).
@immutable
class VrViewerProfile {
  VrViewerProfile({
    this.ipdMeters = 0.064,
    this.fovYRadians = math.pi / 3,
    this.stereoImageInset = 0.10,
    this.convergenceDistanceMeters = 1.8,
    this.lensDistortionK1 = 0.0,
    this.lensDistortionK2 = 0.0,
    this.chromaticAberrationRed = 0.0,
    this.chromaticAberrationBlue = 0.0,
    this.apertureRadius = 0.0,
    this.activeLensWidthFraction = 1.0,
    this.activeLensHeightFraction = 1.0,
    this.headsetPresetId = 'none',
  }) {
    _range(ipdMeters, 'ipdMeters', minIpdMeters, maxIpdMeters);
    _range(fovYRadians, 'fovYRadians', minFovYRadians, maxFovYRadians);
    _range(stereoImageInset, 'stereoImageInset', 0, maxStereoImageInset);
    final convergence = convergenceDistanceMeters;
    if (convergence != null) {
      _range(
        convergence,
        'convergenceDistanceMeters',
        minConvergenceMeters,
        maxConvergenceMeters,
      );
    }
    _range(lensDistortionK1, 'lensDistortionK1', 0, maxLensDistortionK1);
    _range(lensDistortionK2, 'lensDistortionK2', 0, maxLensDistortionK2);
    _range(
      chromaticAberrationRed,
      'chromaticAberrationRed',
      -maxChromaticAberration,
      maxChromaticAberration,
    );
    _range(
      chromaticAberrationBlue,
      'chromaticAberrationBlue',
      -maxChromaticAberration,
      maxChromaticAberration,
    );
    _range(apertureRadius, 'apertureRadius', 0, maxApertureRadius);
    _range(
      activeLensWidthFraction,
      'activeLensWidthFraction',
      minActiveLensFraction,
      1.0,
    );
    _range(
      activeLensHeightFraction,
      'activeLensHeightFraction',
      minActiveLensFraction,
      1.0,
    );
  }

  /// Low-latency profile matched to real frontal smartphone headset optics
  /// (`48°` effective cone + `0.76 × 0.84` Active Lens Scissor = `-36.2%` GPU
  /// pixels shaded and OLED `#000000` outer border).
  factory VrViewerProfile.frontalLowLatency({
    double ipdMeters = 0.064,
    double fovYDegrees = 48.0,
    double stereoImageInset = 0.12,
    double? convergenceDistanceMeters = 1.8,
    double activeLensWidthFraction = 0.76,
    double activeLensHeightFraction = 0.84,
  }) => VrViewerProfile(
    ipdMeters: ipdMeters,
    fovYRadians: (fovYDegrees * math.pi / 180.0).clamp(
      minFovYRadians,
      maxFovYRadians,
    ),
    stereoImageInset: stereoImageInset,
    convergenceDistanceMeters: convergenceDistanceMeters,
    activeLensWidthFraction: activeLensWidthFraction,
    activeLensHeightFraction: activeLensHeightFraction,
    headsetPresetId: 'frontal_low_latency',
  );

  // Match CameraRig's physical IPD bounds: applying never silently clamps.
  static const double minIpdMeters = 0.050, maxIpdMeters = 0.080;
  static const double minFovYRadians = math.pi / 6;
  static const double maxFovYRadians = math.pi * 2 / 3;
  static const double maxStereoImageInset = 0.35;
  static const double minConvergenceMeters = 0.5, maxConvergenceMeters = 20;
  static const double maxLensDistortionK1 = 0.50;
  static const double maxLensDistortionK2 = 0.35;
  static const double maxChromaticAberration = 0.08;
  static const double maxApertureRadius = 1.25;
  static const double minActiveLensFraction = 0.45;
  static const Object _unchanged = Object();

  final double ipdMeters;
  final double fovYRadians;
  final double stereoImageInset;

  /// Zero-parallax distance; null keeps both eye projections parallel without
  /// the convergence shift (the independent image inset still applies).
  final double? convergenceDistanceMeters;

  /// Radial Brown-Conrady barrel pre-distortion terms (`0.0` = planar).
  final double lensDistortionK1;
  final double lensDistortionK2;

  /// Per-channel RGB lateral chromatic dispersion compensation (`0.0` = off).
  final double chromaticAberrationRed;
  final double chromaticAberrationBlue;

  /// Circular `#000000` OLED aperture mask radius (`0.0` = full half-screen,
  /// `~0.96` = Pancake folded-optics stray-light & power-saving aperture).
  final double apertureRadius;

  /// Early GPU viewport scissor width/height fraction within each half-eye
  /// (`1.0` = full half-screen, `0.76 × 0.84` skips occluded plastic margins).
  final double activeLensWidthFraction;
  final double activeLensHeightFraction;

  /// Identifier of the selected optical preset (`'none'` when planar/manual).
  final String headsetPresetId;

  /// True when early projection-matched viewport cropping eliminates wasted
  /// peripheral fragments outside the frontal headset's real lens aperture.
  bool get hasActiveLensScissor =>
      activeLensWidthFraction < 0.999 || activeLensHeightFraction < 0.999;

  /// Fraction of stereo color-target pixels eliminated before shading (`0..1`).
  double get estimatedGpuPixelSavingsFraction =>
      (1.0 - activeLensWidthFraction * activeLensHeightFraction).clamp(
        0.0,
        1.0,
      );

  /// True when GPU barrel warp, RGB chromatic shift, or Pancake circular
  /// masking should be applied to the stereo eye pass.
  bool get hasLensWarp =>
      lensDistortionK1 > 1e-5 ||
      lensDistortionK2 > 1e-5 ||
      chromaticAberrationRed.abs() > 1e-5 ||
      chromaticAberrationBlue.abs() > 1e-5 ||
      apertureRadius > 1e-5;

  VrViewerProfile copyWith({
    double? ipdMeters,
    double? fovYRadians,
    double? stereoImageInset,
    Object? convergenceDistanceMeters = _unchanged,
    double? lensDistortionK1,
    double? lensDistortionK2,
    double? chromaticAberrationRed,
    double? chromaticAberrationBlue,
    double? apertureRadius,
    double? activeLensWidthFraction,
    double? activeLensHeightFraction,
    String? headsetPresetId,
  }) {
    final convergence = identical(convergenceDistanceMeters, _unchanged)
        ? this.convergenceDistanceMeters
        : convergenceDistanceMeters;
    if (convergence != null && convergence is! num) {
      throw ArgumentError.value(
        convergence,
        'convergenceDistanceMeters',
        'Must be a finite number of meters or null.',
      );
    }
    return VrViewerProfile(
      ipdMeters: ipdMeters ?? this.ipdMeters,
      fovYRadians: fovYRadians ?? this.fovYRadians,
      stereoImageInset: stereoImageInset ?? this.stereoImageInset,
      convergenceDistanceMeters: (convergence as num?)?.toDouble(),
      lensDistortionK1: lensDistortionK1 ?? this.lensDistortionK1,
      lensDistortionK2: lensDistortionK2 ?? this.lensDistortionK2,
      chromaticAberrationRed:
          chromaticAberrationRed ?? this.chromaticAberrationRed,
      chromaticAberrationBlue:
          chromaticAberrationBlue ?? this.chromaticAberrationBlue,
      apertureRadius: apertureRadius ?? this.apertureRadius,
      activeLensWidthFraction:
          activeLensWidthFraction ?? this.activeLensWidthFraction,
      activeLensHeightFraction:
          activeLensHeightFraction ?? this.activeLensHeightFraction,
      headsetPresetId: headsetPresetId ?? this.headsetPresetId,
    );
  }

  /// Apply projection only; preserve head pose, eye height and world anchors.
  void applyTo(StereoHeadRig rig) {
    rig.ipd = ipdMeters;
    rig.cameraRig.fovY = fovYRadians;
    rig.stereoImageInset = stereoImageInset;
    rig.convergenceDistance = convergenceDistanceMeters;
  }

  Map<String, dynamic> toJson() => {
    'schemaVersion': 1,
    'ipdMeters': ipdMeters,
    'fovYRadians': fovYRadians,
    'stereoImageInset': stereoImageInset,
    'convergenceDistanceMeters': convergenceDistanceMeters,
    if (lensDistortionK1 != 0.0) 'lensDistortionK1': lensDistortionK1,
    if (lensDistortionK2 != 0.0) 'lensDistortionK2': lensDistortionK2,
    if (chromaticAberrationRed != 0.0)
      'chromaticAberrationRed': chromaticAberrationRed,
    if (chromaticAberrationBlue != 0.0)
      'chromaticAberrationBlue': chromaticAberrationBlue,
    if (apertureRadius != 0.0) 'apertureRadius': apertureRadius,
    if (activeLensWidthFraction != 1.0)
      'activeLensWidthFraction': activeLensWidthFraction,
    if (activeLensHeightFraction != 1.0)
      'activeLensHeightFraction': activeLensHeightFraction,
    if (headsetPresetId != 'none') 'headsetPresetId': headsetPresetId,
  };

  factory VrViewerProfile.fromJson(Map<String, dynamic> json) {
    if (json['schemaVersion'] != 1) {
      throw const FormatException('Unsupported viewer profile schemaVersion.');
    }
    double readNumber(String key) {
      final value = json[key];
      if (value is! num || !value.isFinite) {
        throw FormatException('Viewer profile $key must be a finite number.');
      }
      return value.toDouble();
    }

    double readOptionalNumber(String key, double fallback) {
      if (!json.containsKey(key) || json[key] == null) return fallback;
      return readNumber(key);
    }

    if (!json.containsKey('convergenceDistanceMeters')) {
      throw const FormatException(
        'Viewer profile missing convergenceDistanceMeters.',
      );
    }
    final presetRaw = json['headsetPresetId'];
    if (presetRaw != null && presetRaw is! String) {
      throw const FormatException(
        'Viewer profile headsetPresetId must be a string.',
      );
    }
    try {
      return VrViewerProfile(
        ipdMeters: readNumber('ipdMeters'),
        fovYRadians: readNumber('fovYRadians'),
        stereoImageInset: readNumber('stereoImageInset'),
        convergenceDistanceMeters: json['convergenceDistanceMeters'] == null
            ? null
            : readNumber('convergenceDistanceMeters'),
        lensDistortionK1: readOptionalNumber('lensDistortionK1', 0.0),
        lensDistortionK2: readOptionalNumber('lensDistortionK2', 0.0),
        chromaticAberrationRed: readOptionalNumber(
          'chromaticAberrationRed',
          0.0,
        ),
        chromaticAberrationBlue: readOptionalNumber(
          'chromaticAberrationBlue',
          0.0,
        ),
        apertureRadius: readOptionalNumber('apertureRadius', 0.0),
        activeLensWidthFraction: readOptionalNumber(
          'activeLensWidthFraction',
          1.0,
        ),
        activeLensHeightFraction: readOptionalNumber(
          'activeLensHeightFraction',
          1.0,
        ),
        headsetPresetId: (presetRaw as String?) ?? 'none',
      );
    } on ArgumentError catch (error) {
      throw FormatException(
        'Invalid viewer profile ${error.name}: ${error.message}',
      );
    }
  }

  static void _range(double value, String name, double min, double max) {
    if (!value.isFinite || value < min || value > max) {
      throw ArgumentError.value(
        value,
        name,
        'Must be finite within $min–$max.',
      );
    }
  }

  @override
  bool operator ==(Object other) =>
      other is VrViewerProfile &&
      other.ipdMeters == ipdMeters &&
      other.fovYRadians == fovYRadians &&
      other.stereoImageInset == stereoImageInset &&
      other.convergenceDistanceMeters == convergenceDistanceMeters &&
      other.lensDistortionK1 == lensDistortionK1 &&
      other.lensDistortionK2 == lensDistortionK2 &&
      other.chromaticAberrationRed == chromaticAberrationRed &&
      other.chromaticAberrationBlue == chromaticAberrationBlue &&
      other.apertureRadius == apertureRadius &&
      other.activeLensWidthFraction == activeLensWidthFraction &&
      other.activeLensHeightFraction == activeLensHeightFraction &&
      other.headsetPresetId == headsetPresetId;

  @override
  int get hashCode => Object.hash(
    ipdMeters,
    fovYRadians,
    stereoImageInset,
    convergenceDistanceMeters,
    lensDistortionK1,
    lensDistortionK2,
    chromaticAberrationRed,
    chromaticAberrationBlue,
    apertureRadius,
    activeLensWidthFraction,
    activeLensHeightFraction,
    headsetPresetId,
  );
}

/// Host-owned shared calibration. The application persists [onChanged]; this
/// renderer package has no storage dependency or device-name heuristics.
class VrViewerProfileScope extends InheritedWidget {
  const VrViewerProfileScope({
    super.key,
    required this.profile,
    required this.onChanged,
    required super.child,
  });

  final VrViewerProfile profile;
  final ValueChanged<VrViewerProfile> onChanged;

  static VrViewerProfileScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<VrViewerProfileScope>();

  @override
  bool updateShouldNotify(VrViewerProfileScope oldWidget) =>
      profile != oldWidget.profile || onChanged != oldWidget.onChanged;
}
