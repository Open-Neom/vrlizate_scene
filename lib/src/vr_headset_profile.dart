import 'dart:math' as math;

import 'stereo_head_rig.dart';
import 'vr_viewer_profile.dart';

/// Physical optics and geometric specifications of a VR headset/viewer.
class VrHeadsetProfile {
  final String id;
  final String name;
  final String vendor;
  final double ipdMeters;
  final double fovDegrees;
  final double focalLengthMm;
  final double lensDistortionK1;
  final double lensDistortionK2;
  final double chromaticAberrationRed;
  final double chromaticAberrationBlue;
  final double apertureRadius;
  final bool isPancakeOptics;
  final double convergenceDistanceMeters;
  final double stereoImageInset;
  final double activeLensWidthFraction;
  final double activeLensHeightFraction;

  const VrHeadsetProfile({
    required this.id,
    required this.name,
    required this.vendor,
    required this.ipdMeters,
    required this.fovDegrees,
    this.focalLengthMm = 42.0,
    this.lensDistortionK1 = 0.0,
    this.lensDistortionK2 = 0.0,
    this.chromaticAberrationRed = 0.0,
    this.chromaticAberrationBlue = 0.0,
    this.apertureRadius = 0.0,
    this.isPancakeOptics = false,
    this.convergenceDistanceMeters = 1.8,
    this.stereoImageInset = 0.10,
    this.activeLensWidthFraction = 1.0,
    this.activeLensHeightFraction = 1.0,
  });

  /// Google Cardboard v2 (42mm focal length, biconvex PMMA).
  static const googleCardboardV2 = VrHeadsetProfile(
    id: 'cardboard_v2',
    name: 'Google Cardboard v2',
    vendor: 'Google',
    ipdMeters: 0.064,
    fovDegrees: 96.0,
    focalLengthMm: 42.0,
    lensDistortionK1: 0.14,
    lensDistortionK2: 0.04,
    chromaticAberrationRed: -0.010,
    chromaticAberrationBlue: 0.014,
    convergenceDistanceMeters: 1.8,
    stereoImageInset: 0.10,
  );

  /// BoboVR Z6 (High-FOV wide biconvex lenses).
  static const boboVrZ6 = VrHeadsetProfile(
    id: 'bobovr_z6',
    name: 'BoboVR Z6',
    vendor: 'BoboVR',
    ipdMeters: 0.065,
    fovDegrees: 110.0,
    focalLengthMm: 38.0,
    lensDistortionK1: 0.18,
    lensDistortionK2: 0.06,
    chromaticAberrationRed: -0.012,
    chromaticAberrationBlue: 0.018,
    convergenceDistanceMeters: 2.0,
    stereoImageInset: 0.08,
  );

  /// VR Box 2.0 (Entry-level long-focal viewer).
  static const vrBox2 = VrHeadsetProfile(
    id: 'vr_box_2',
    name: 'VR Box 2.0',
    vendor: 'VR Box',
    ipdMeters: 0.062,
    fovDegrees: 85.0,
    focalLengthMm: 45.0,
    lensDistortionK1: 0.10,
    lensDistortionK2: 0.02,
    chromaticAberrationRed: -0.008,
    chromaticAberrationBlue: 0.011,
    convergenceDistanceMeters: 1.5,
    stereoImageInset: 0.12,
  );

  /// Google Daydream View (Fabric, 100° FOV).
  static const daydreamView = VrHeadsetProfile(
    id: 'daydream_view',
    name: 'Daydream View',
    vendor: 'Google',
    ipdMeters: 0.064,
    fovDegrees: 100.0,
    focalLengthMm: 40.0,
    lensDistortionK1: 0.16,
    lensDistortionK2: 0.05,
    chromaticAberrationRed: -0.011,
    chromaticAberrationBlue: 0.015,
    convergenceDistanceMeters: 1.8,
    stereoImageInset: 0.10,
  );

  /// Short-focal 35mm aspheric doublet shell (high OLED brightness, minimal CA).
  static const asphericShortFocal35 = VrHeadsetProfile(
    id: 'aspheric_35mm',
    name: 'Asférico Acromático 35mm',
    vendor: 'VRlizate Open Shell',
    ipdMeters: 0.064,
    fovDegrees: 98.0,
    focalLengthMm: 35.0,
    lensDistortionK1: 0.15,
    lensDistortionK2: 0.03,
    chromaticAberrationRed: -0.004,
    chromaticAberrationBlue: 0.006,
    convergenceDistanceMeters: 1.8,
    stereoImageInset: 0.09,
  );

  /// Folded polarization 22mm Pancake shell for OLED smartphones at 100% nits.
  ///
  /// Uses a circular `#000000` OLED aperture mask (`apertureRadius = 0.96`) to
  /// eliminate internal stray reflections across the half-mirror / QWP stack
  /// and reduce smartphone panel power draw by ~25%.
  static const vrlizatePancakeShell = VrHeadsetProfile(
    id: 'vrlizate_pancake_22mm',
    name: 'VRlizate Pancake 22mm (OLED)',
    vendor: 'VRlizate Optics',
    ipdMeters: 0.064,
    fovDegrees: 102.0,
    focalLengthMm: 22.0,
    lensDistortionK1: 0.22,
    lensDistortionK2: 0.07,
    chromaticAberrationRed: -0.006,
    chromaticAberrationBlue: 0.009,
    apertureRadius: 0.96,
    isPancakeOptics: true,
    convergenceDistanceMeters: 1.8,
    stereoImageInset: 0.08,
  );

  /// Frontal smartphone headset optimized for minimal latency & zero wasted
  /// peripheral fragments (`48°` real lens FoV + `0.76 × 0.84` Active Lens
  /// Scissor = `-36.2%` GPU shading + OLED `#000000` outer border).
  static const frontalLowLatency48 = VrHeadsetProfile(
    id: 'frontal_low_latency',
    name: 'Visor Frontal Baja Latencia (48° Active Scissor)',
    vendor: 'VRlizate Low-Latency',
    ipdMeters: 0.064,
    fovDegrees: 48.0,
    focalLengthMm: 42.0,
    convergenceDistanceMeters: 1.8,
    stereoImageInset: 0.12,
    activeLensWidthFraction: 0.76,
    activeLensHeightFraction: 0.84,
  );

  static const List<VrHeadsetProfile> builtInProfiles = [
    frontalLowLatency48,
    googleCardboardV2,
    boboVrZ6,
    vrBox2,
    daydreamView,
    asphericShortFocal35,
    vrlizatePancakeShell,
  ];

  static VrHeadsetProfile? byId(String id) {
    for (final profile in builtInProfiles) {
      if (profile.id == id) return profile;
    }
    return null;
  }

  /// Converts this physical headset spec into a runtime [VrViewerProfile]
  /// while optionally preserving the user's personal [ipdOverrideMeters].
  VrViewerProfile toViewerProfile({double? ipdOverrideMeters}) {
    final fovRad = (fovDegrees * math.pi / 180.0).clamp(
      VrViewerProfile.minFovYRadians,
      VrViewerProfile.maxFovYRadians,
    );
    return VrViewerProfile(
      ipdMeters: (ipdOverrideMeters ?? ipdMeters).clamp(
        VrViewerProfile.minIpdMeters,
        VrViewerProfile.maxIpdMeters,
      ),
      fovYRadians: fovRad,
      stereoImageInset: stereoImageInset.clamp(
        0.0,
        VrViewerProfile.maxStereoImageInset,
      ),
      convergenceDistanceMeters: convergenceDistanceMeters.clamp(
        VrViewerProfile.minConvergenceMeters,
        VrViewerProfile.maxConvergenceMeters,
      ),
      lensDistortionK1: lensDistortionK1.clamp(
        0.0,
        VrViewerProfile.maxLensDistortionK1,
      ),
      lensDistortionK2: lensDistortionK2.clamp(
        0.0,
        VrViewerProfile.maxLensDistortionK2,
      ),
      chromaticAberrationRed: chromaticAberrationRed.clamp(
        -VrViewerProfile.maxChromaticAberration,
        VrViewerProfile.maxChromaticAberration,
      ),
      chromaticAberrationBlue: chromaticAberrationBlue.clamp(
        -VrViewerProfile.maxChromaticAberration,
        VrViewerProfile.maxChromaticAberration,
      ),
      apertureRadius: apertureRadius.clamp(
        0.0,
        VrViewerProfile.maxApertureRadius,
      ),
      activeLensWidthFraction: activeLensWidthFraction.clamp(
        VrViewerProfile.minActiveLensFraction,
        1.0,
      ),
      activeLensHeightFraction: activeLensHeightFraction.clamp(
        VrViewerProfile.minActiveLensFraction,
        1.0,
      ),
      headsetPresetId: id,
    );
  }

  /// Applies optical interpupillary distance and calibration parameters to [rig].
  void applyToRig(StereoHeadRig rig) {
    rig.ipd = ipdMeters;
    rig.convergenceDistance = convergenceDistanceMeters;
    rig.stereoImageInset = stereoImageInset;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'vendor': vendor,
    'ipdMeters': ipdMeters,
    'fovDegrees': fovDegrees,
    'focalLengthMm': focalLengthMm,
    'lensDistortionK1': lensDistortionK1,
    'lensDistortionK2': lensDistortionK2,
    'chromaticAberrationRed': chromaticAberrationRed,
    'chromaticAberrationBlue': chromaticAberrationBlue,
    'apertureRadius': apertureRadius,
    'isPancakeOptics': isPancakeOptics,
    'convergenceDistanceMeters': convergenceDistanceMeters,
    'stereoImageInset': stereoImageInset,
  };

  factory VrHeadsetProfile.fromJson(Map<String, dynamic> json) =>
      VrHeadsetProfile(
        id: json['id'] as String? ?? 'custom',
        name: json['name'] as String? ?? 'Custom Headset',
        vendor: json['vendor'] as String? ?? 'Generic',
        ipdMeters: (json['ipdMeters'] as num?)?.toDouble() ?? 0.064,
        fovDegrees: (json['fovDegrees'] as num?)?.toDouble() ?? 96.0,
        focalLengthMm: (json['focalLengthMm'] as num?)?.toDouble() ?? 42.0,
        lensDistortionK1: (json['lensDistortionK1'] as num?)?.toDouble() ?? 0.0,
        lensDistortionK2: (json['lensDistortionK2'] as num?)?.toDouble() ?? 0.0,
        chromaticAberrationRed:
            (json['chromaticAberrationRed'] as num?)?.toDouble() ?? 0.0,
        chromaticAberrationBlue:
            (json['chromaticAberrationBlue'] as num?)?.toDouble() ?? 0.0,
        apertureRadius: (json['apertureRadius'] as num?)?.toDouble() ?? 0.0,
        isPancakeOptics: json['isPancakeOptics'] == true,
        convergenceDistanceMeters:
            (json['convergenceDistanceMeters'] as num?)?.toDouble() ?? 1.8,
        stereoImageInset:
            (json['stereoImageInset'] as num?)?.toDouble() ?? 0.10,
      );
}
