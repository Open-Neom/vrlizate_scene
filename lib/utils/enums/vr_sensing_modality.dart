import '../constants/vr_scene_constants.dart';

/// Sensor modalities available on conventional smartphones that are fused by
/// `VrSyntheticLidarScanner` to reconstruct a 3D room model comparable to
/// hardware LiDAR.
enum VrSensingModality {
  /// Optical edges, floor plane, and bounding boxes from the 3 smartphone
  /// cameras (`visor_front`, `joystick_rear`, `joystick_front`).
  triCameraVision(VrSceneConstants.modalityTriCameraVisionId),

  /// Multi-frequency acoustic & ultrasonic sonar echoes ($4\text{–}22\text{ kHz}$
  /// FMCW monostatic self-echoes + bistatic Visor/Joystick reflections +
  /// dual-microphone TDOA azimuth). Works on glass, mirrors, white walls, and
  /// in total darkness.
  acousticSonarEcho(VrSceneConstants.modalityAcousticSonarEchoId),

  /// IEEE 802.11mc/az Wi-Fi Fine Timing Measurement (RTT) and dual-smartphone
  /// RSSI differential shadowing/multipath across room walls (`2.4/5/6 GHz`).
  wifiRfSensing(VrSceneConstants.modalityWifiRfSensingId),

  /// Dual-smartphone differential BLE 5.x/6.0 RSSI, AoA, and Channel Sounding
  /// trilateration of surrounding fixed/peer devices.
  bluetoothBleRadar(VrSceneConstants.modalityBluetoothBleRadarId),

  /// Differential MEMS barometric pressure ($\Delta P = P_{\text{joy}} -
  /// P_{\text{visor}}$) canceling weather/HVAC drift to measure vertical
  /// height deltas ($\sim 8.43\text{ m/hPa}$).
  differentialBarometer(VrSceneConstants.modalityDifferentialBarometerId),

  /// 3-axis uncalibrated magnetometer anomaly ($\Delta \mathbf{B}$ in
  /// $\mu\text{T}$) detecting nearby ferromagnetic furniture, steel wall studs,
  /// monitors, and indoor geomagnetic room fingerprints.
  magneticAnomalyField(VrSceneConstants.modalityMagneticAnomalyFieldId),

  /// Camera ISP Dual-Pixel Phase-Detection Autofocus (PDAF) lens focus
  /// distance in diopters ($d = 1/\text{diopters}$) + active torch/screen
  /// inverse-square photometry.
  cameraPdafFocusDepth(VrSceneConstants.modalityCameraPdafFocusDepthId),

  /// Ambient RGB light sensor (Lux + Correlated Color Temperature in Kelvin)
  /// and near-field Infrared (IR) proximity photodiode ($850\text{–}940\text{ nm}$).
  ambientLightAndIrProximity(
    VrSceneConstants.modalityAmbientLightAndIrProximityId,
  ),

  /// IEEE 802.15.4z Ultra-Wideband (UWB) nanosecond radio Time-of-Flight and
  /// 3D Angle of Arrival between smartphones.
  ultraWidebandToF(VrSceneConstants.modalityUltraWidebandToFId),

  /// High-rate IMU heel-strike shockwave vibrometry + floor contact clamping
  /// (`y = 0`).
  imuFootstepVibrometry(VrSceneConstants.modalityImuFootstepVibrometryId);

  const VrSensingModality(this.id);

  final String id;
}
