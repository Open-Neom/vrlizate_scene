import '../constants/vr_scene_constants.dart';

/// Power and compute allocation profiles for the 10-modality Spatial Capture
/// pipeline across the **Visor Smartphone** and **Joystick Smartphone**.
enum VrSpatialCapturePowerMode {
  /// Minimal battery draw; runs only IMU, metadata-based PDAF/ALS, and low-rate
  /// ultrasonic ranging.
  ultraLowPower(VrSceneConstants.powerModeUltraLowId),

  /// Default balanced mode; dynamically scales camera and sonar tick rates
  /// based on user movement speed.
  balancedAdaptive(VrSceneConstants.powerModeBalancedAdaptiveId),

  /// Maximum room reconstruction density when entering a new physical space.
  highPrecisionScan(VrSceneConstants.powerModeHighPrecisionId),

  /// Flagship Two-Devices VR mode (e.g. **Galaxy S25 Visor + Moto Edge
  /// Joystick**): offloads $> 70\%$ of vision, sonar DSP, and RF trilateration
  /// to the Joystick Smartphone so the Visor Smartphone reserves its GPU/CPU
  /// for 90–120 FPS stereo PBR rendering.
  joystickOffloadedVisorPriority(VrSceneConstants.powerModeJoystickOffloadedId);

  const VrSpatialCapturePowerMode(this.id);

  final String id;
}
