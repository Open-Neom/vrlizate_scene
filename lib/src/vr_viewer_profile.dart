import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'stereo_head_rig.dart';

/// User/viewer optical alignment, independent from hardware quality presets.
///
/// These values change stereo projection, not lens-distortion correction.
/// They are not a manufacturer-certified profile or a guarantee of fusion.
@immutable
class VrViewerProfile {
  VrViewerProfile({
    this.ipdMeters = 0.064,
    this.fovYRadians = math.pi / 3,
    this.stereoImageInset = 0.10,
    this.convergenceDistanceMeters = 1.8,
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
  }

  // Match CameraRig's physical IPD bounds: applying never silently clamps.
  static const double minIpdMeters = 0.050, maxIpdMeters = 0.080;
  static const double minFovYRadians = math.pi / 6;
  static const double maxFovYRadians = math.pi * 2 / 3;
  static const double maxStereoImageInset = 0.35;
  static const double minConvergenceMeters = 0.5, maxConvergenceMeters = 20;
  static const Object _unchanged = Object();

  final double ipdMeters;
  final double fovYRadians;
  final double stereoImageInset;

  /// Zero-parallax distance; null keeps both eye projections parallel without
  /// the convergence shift (the independent image inset still applies).
  final double? convergenceDistanceMeters;

  VrViewerProfile copyWith({
    double? ipdMeters,
    double? fovYRadians,
    double? stereoImageInset,
    Object? convergenceDistanceMeters = _unchanged,
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

    if (!json.containsKey('convergenceDistanceMeters')) {
      throw const FormatException(
        'Viewer profile missing convergenceDistanceMeters.',
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
      other.convergenceDistanceMeters == convergenceDistanceMeters;

  @override
  int get hashCode => Object.hash(
    ipdMeters,
    fovYRadians,
    stereoImageInset,
    convergenceDistanceMeters,
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
