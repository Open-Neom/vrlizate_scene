import 'dart:math' as math;

import '../../utils/constants/vr_scene_constants.dart';
import '../../utils/enums/vr_sensing_modality.dart';

/// Hardware sensor capability matrix for a **Visor Smartphone + Joystick
/// Smartphone** pair, with built-in reference presets for **Samsung Galaxy S25
/// (Visor) + Motorola Edge (Joystick)** and generic fallback devices.
class VrDeviceSensorPairProfile {
  const VrDeviceSensorPairProfile({
    required this.visorModelName,
    required this.joystickModelName,
    required this.visorForwardCameraFovDegrees,
    required this.joystickRearFloorCameraFovDegrees,
    required this.joystickFrontBodyCameraFovDegrees,
    required this.visorMicBaselineMeters,
    required this.joystickMicBaselineMeters,
    required this.joystickTouchSamplingHz,
    this.supportsDualPixelPdaf = true,
    this.supportsUltrasonic48kHz = true,
    this.supportsWifiRtt80211mc = true,
    this.supportsBle5Radar = true,
    this.supportsDifferentialBarometer = true,
    this.supports3AxisMagnetometer = true,
    this.supportsAmbientLightColorTemp = true,
    this.supportsUltraWideband = false,
    this.supportsImuFootstepVibrometry = true,
  });

  /// Reference flagship pair: **Samsung Galaxy S25 (Visor)** + **Motorola Edge
  /// (Joystick)**.
  ///
  /// - **Galaxy S25 Visor:** Snapdragon 8 Elite (3 nm), 120 Hz AMOLED, 50 MP
  ///   Dual-Pixel PDAF + 12 MP $120^\circ$ Ultra-Wide forward camera, Wi-Fi 7
  ///   (`802.11mc/az` RTT), BLE 5.4, MEMS Barometer, 3-axis Magnetometer, RGB
  ///   ALS, $48\text{ kHz}$ stereo mics ($b_{\text{mic}} = 14.7\text{ cm}$).
  /// - **Motorola Edge Joystick:** 144 Hz pOLED ($240\text{ Hz}$ touch
  ///   sampling for ultra-responsive Dual-Thumb Curtain & Wordsphere), 50 MP
  ///   All-Pixel PDAF + 13 MP $120^\circ$ Ultra-Wide rear camera (covering a
  ///   $3.6\text{ m}$ floor circle from waist height!), 32 MP front camera,
  ///   Dolby Atmos stereo speakers + $15.8\text{ cm}$ dual-mic baseline,
  ///   Wi-Fi 6E RTT, BLE 5.3.
  factory VrDeviceSensorPairProfile.s25VisorAndMotoEdgeJoystick() {
    return const VrDeviceSensorPairProfile(
      visorModelName: VrSceneConstants.referenceVisorS25ModelName,
      joystickModelName: VrSceneConstants.referenceJoystickMotoEdgeModelName,
      visorForwardCameraFovDegrees:
          VrSceneConstants.s25VisorUltraWideFovDegrees,
      joystickRearFloorCameraFovDegrees:
          VrSceneConstants.motoEdgeRearUltraWideFovDegrees,
      joystickFrontBodyCameraFovDegrees:
          VrSceneConstants.motoEdgeFrontSelfieFovDegrees,
      visorMicBaselineMeters: VrSceneConstants.s25MicBaselineMeters,
      joystickMicBaselineMeters: VrSceneConstants.motoEdgeMicBaselineMeters,
      joystickTouchSamplingHz: VrSceneConstants.motoEdgeTouchSamplingHz,
      supportsDualPixelPdaf: true,
      supportsUltrasonic48kHz: true,
      supportsWifiRtt80211mc: true,
      supportsBle5Radar: true,
      supportsDifferentialBarometer: true,
      supports3AxisMagnetometer: true,
      supportsAmbientLightColorTemp: true,
      supportsUltraWideband: false, // Base 6.2" S25 uses Ultrasonic + Wi-Fi 7 RTT
      supportsImuFootstepVibrometry: true,
    );
  }

  /// Universal baseline profile for any two conventional Android/iOS
  /// smartphones when specific hardware sensors (like Barometer or UWB) may not
  /// be present on both devices.
  factory VrDeviceSensorPairProfile.genericConventionalPair() {
    return const VrDeviceSensorPairProfile(
      visorModelName: VrSceneConstants.genericVisorModelName,
      joystickModelName: VrSceneConstants.genericJoystickModelName,
      visorForwardCameraFovDegrees: VrSceneConstants.genericRearCameraFovDegrees,
      joystickRearFloorCameraFovDegrees:
          VrSceneConstants.genericRearCameraFovDegrees,
      joystickFrontBodyCameraFovDegrees:
          VrSceneConstants.genericFrontCameraFovDegrees,
      visorMicBaselineMeters:
          VrSceneConstants.defaultSmartphoneMicBaselineMeters,
      joystickMicBaselineMeters:
          VrSceneConstants.defaultSmartphoneMicBaselineMeters,
      joystickTouchSamplingHz: VrSceneConstants.genericTouchSamplingHz,
      supportsDualPixelPdaf: true,
      supportsUltrasonic48kHz: true,
      supportsWifiRtt80211mc: false,
      supportsBle5Radar: true,
      supportsDifferentialBarometer: false,
      supports3AxisMagnetometer: true,
      supportsAmbientLightColorTemp: true,
      supportsUltraWideband: false,
      supportsImuFootstepVibrometry: true,
    );
  }

  final String visorModelName;
  final String joystickModelName;
  final double visorForwardCameraFovDegrees;
  final double joystickRearFloorCameraFovDegrees;
  final double joystickFrontBodyCameraFovDegrees;
  final double visorMicBaselineMeters;
  final double joystickMicBaselineMeters;
  final double joystickTouchSamplingHz;

  final bool supportsDualPixelPdaf;
  final bool supportsUltrasonic48kHz;
  final bool supportsWifiRtt80211mc;
  final bool supportsBle5Radar;
  final bool supportsDifferentialBarometer;
  final bool supports3AxisMagnetometer;
  final bool supportsAmbientLightColorTemp;
  final bool supportsUltraWideband;
  final bool supportsImuFootstepVibrometry;

  /// Diameter in meters of the physical floor circle visible to the Joystick's
  /// downward rear camera when held at [joystickHeightMeters] above the floor:
  /// $D = 2 \cdot h_{\text{joy}} \cdot \tan(\text{FoV} / 2)$.
  double floorCoverageDiameterMeters({double joystickHeightMeters = 1.05}) {
    final halfFovRad =
        (joystickRearFloorCameraFovDegrees.clamp(40.0, 140.0) * math.pi / 180.0) *
        0.5;
    return 2.0 * joystickHeightMeters * math.tan(halfFovRad);
  }

  /// Returns the set of [VrSensingModality] supported by this hardware pair.
  Set<VrSensingModality> get supportedModalities {
    return <VrSensingModality>{
      VrSensingModality.triCameraVision,
      if (supportsUltrasonic48kHz) VrSensingModality.acousticSonarEcho,
      VrSensingModality.wifiRfSensing,
      if (supportsBle5Radar) VrSensingModality.bluetoothBleRadar,
      if (supportsDifferentialBarometer) VrSensingModality.differentialBarometer,
      if (supports3AxisMagnetometer) VrSensingModality.magneticAnomalyField,
      if (supportsDualPixelPdaf) VrSensingModality.cameraPdafFocusDepth,
      if (supportsAmbientLightColorTemp)
        VrSensingModality.ambientLightAndIrProximity,
      if (supportsUltraWideband) VrSensingModality.ultraWidebandToF,
      if (supportsImuFootstepVibrometry)
        VrSensingModality.imuFootstepVibrometry,
    };
  }
}
