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
  bluetoothBleRadar(VrSceneConstants.modalityBluetoothBleRadarId);

  const VrSensingModality(this.id);

  final String id;
}
