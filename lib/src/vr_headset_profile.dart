import 'stereo_head_rig.dart';

/// Physical optics and geometric specifications of a VR headset/viewer.
class VrHeadsetProfile {
  final String id;
  final String name;
  final String vendor;
  final double ipdMeters;
  final double fovDegrees;
  final double lensDistortionK1;
  final double lensDistortionK2;
  final double convergenceDistanceMeters;
  final double stereoImageInset;

  const VrHeadsetProfile({
    required this.id,
    required this.name,
    required this.vendor,
    required this.ipdMeters,
    required this.fovDegrees,
    this.lensDistortionK1 = 0.0,
    this.lensDistortionK2 = 0.0,
    this.convergenceDistanceMeters = 1.8,
    this.stereoImageInset = 0.10,
  });

  /// Google Cardboard v2 (42mm focal length, capacitive button).
  static const googleCardboardV2 = VrHeadsetProfile(
    id: 'cardboard_v2',
    name: 'Google Cardboard v2',
    vendor: 'Google',
    ipdMeters: 0.064,
    fovDegrees: 96.0,
    lensDistortionK1: 0.14,
    lensDistortionK2: 0.04,
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
    lensDistortionK1: 0.18,
    lensDistortionK2: 0.06,
    convergenceDistanceMeters: 2.0,
    stereoImageInset: 0.08,
  );

  /// VR Box 2.0 (Entry-level viewer).
  static const vrBox2 = VrHeadsetProfile(
    id: 'vr_box_2',
    name: 'VR Box 2.0',
    vendor: 'VR Box',
    ipdMeters: 0.062,
    fovDegrees: 85.0,
    lensDistortionK1: 0.10,
    lensDistortionK2: 0.02,
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
    lensDistortionK1: 0.16,
    lensDistortionK2: 0.05,
    convergenceDistanceMeters: 1.8,
    stereoImageInset: 0.10,
  );

  static const List<VrHeadsetProfile> builtInProfiles = [
    googleCardboardV2,
    boboVrZ6,
    vrBox2,
    daydreamView,
  ];

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
    'lensDistortionK1': lensDistortionK1,
    'lensDistortionK2': lensDistortionK2,
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
        lensDistortionK1: (json['lensDistortionK1'] as num?)?.toDouble() ?? 0.0,
        lensDistortionK2: (json['lensDistortionK2'] as num?)?.toDouble() ?? 0.0,
        convergenceDistanceMeters:
            (json['convergenceDistanceMeters'] as num?)?.toDouble() ?? 1.8,
        stereoImageInset:
            (json['stereoImageInset'] as num?)?.toDouble() ?? 0.10,
      );
}
