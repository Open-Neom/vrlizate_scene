import 'package:vector_math/vector_math.dart';

import '../../utils/enums/vr_sensing_modality.dart';
import '../../utils/enums/vr_spatial_object_category.dart';

/// A 3D occupied voxel / surface point reconstructed by
/// `VrSyntheticLidarScanner` from fused Camera, Acoustic Sonar, Wi-Fi, and
/// Bluetooth observations.
class VrSyntheticLidarPoint {
  const VrSyntheticLidarPoint({
    required this.voxelKey,
    required this.position,
    required this.normal,
    required this.primaryModality,
    required this.contributingModalities,
    required this.category,
    required this.confidence,
    this.acousticReflectivity = 0.0,
    this.rfAttenuationDb = 0.0,
  });

  /// Discrete 3D grid index key (`"ix:iy:iz"`).
  final String voxelKey;

  /// 3D world position in meters.
  final Vector3 position;

  /// Estimated unit surface normal pointing toward the viewer.
  final Vector3 normal;

  /// Primary sensor modality that first anchored or dominates this point.
  final VrSensingModality primaryModality;

  /// Set of all sensor modalities that have confirmed this 3D voxel.
  final Set<VrSensingModality> contributingModalities;

  /// Semantic category inferred for the surface/object.
  final VrSpatialObjectCategory category;

  /// Occupancy probability (`0.0 .. 1.0`).
  final double confidence;

  /// Acoustic specular reflectivity (`0.0 .. 1.0`) when observed by sonar.
  final double acousticReflectivity;

  /// RF attenuation in dB when observed by Wi-Fi/BLE shadowing.
  final double rfAttenuationDb;

  /// True when confirmed by 2 or more independent physical modalities
  /// (e.g., Camera + Sonar, or Sonar + Wi-Fi).
  bool get isMultiModalConfirmed => contributingModalities.length >= 2;
}
