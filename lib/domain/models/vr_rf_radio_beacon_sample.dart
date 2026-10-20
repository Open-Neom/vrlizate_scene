import 'dart:math' as math;

import '../../utils/constants/vr_scene_constants.dart';
import '../../utils/enums/vr_sensing_modality.dart';

/// Represents a Wi-Fi (`802.11mc` RTT / RSSI) or Bluetooth (`BLE 5.x/6.0`)
/// radio signal sampled simultaneously by both the **Visor Smartphone** and
/// the **Joystick Smartphone**.
class VrRfRadioBeaconSample {
  const VrRfRadioBeaconSample({
    required this.beaconId,
    required this.label,
    required this.modality,
    required this.visorRssiDbm,
    required this.joystickRssiDbm,
    this.frequencyMhz = VrSceneConstants.defaultWifi5GhzFrequencyMhz,
    this.txPowerAtOneMeterDbm = VrSceneConstants.defaultRfTxPowerAtOneMeterDbm,
    this.pathLossExponent = VrSceneConstants.defaultIndoorPathLossExponent,
    this.rttDistanceMeters,
    this.aoaAzimuthRadians,
    this.estimatedWallAttenuationDb = 0.0,
  });

  /// Unique radio identifier (Wi-Fi BSSID or BLE MAC / device UUID).
  final String beaconId;

  /// Human-readable or semantic label (e.g. router, smart TV, PC, speaker).
  final String label;

  /// Whether captured via Wi-Fi (`wifiRfSensing`) or BLE (`bluetoothBleRadar`).
  final VrSensingModality modality;

  /// RSSI measured at the Visor Smartphone in dBm (e.g. `-52.0`).
  final double visorRssiDbm;

  /// RSSI measured simultaneously at the Joystick Smartphone in dBm.
  final double joystickRssiDbm;

  /// Carrier frequency in MHz (e.g. `2412`, `5180`, `2402`).
  final int frequencyMhz;

  /// Reference received power at $1\text{ m}$ in dBm.
  final double txPowerAtOneMeterDbm;

  /// Log-distance path-loss exponent $n$ (typically $2.0\text{–}2.5$ LOS,
  /// $2.7\text{–}3.5$ obstructed).
  final double pathLossExponent;

  /// Optional IEEE 802.11mc/az Fine Timing Measurement (Wi-Fi RTT) or BLE 6.0
  /// Channel Sounding distance in meters.
  final double? rttDistanceMeters;

  /// Optional Angle of Arrival (AoA) or synthetic aperture azimuth in radians
  /// relative to the Visor forward vector.
  final double? aoaAzimuthRadians;

  /// Excess attenuation in dB caused by an intervening wall or heavy obstacle
  /// along the propagation path.
  final double estimatedWallAttenuationDb;

  /// Estimated distance in meters from the **Visor Smartphone** to the radio
  /// source, fusing hardware RTT (if available) with the log-distance path-loss
  /// model.
  double estimateDistanceFromVisorMeters() {
    final rssiDist = _rssiToMeters(visorRssiDbm);
    final rtt = rttDistanceMeters;
    if (rtt != null && rtt > 0.0) {
      return (rtt * VrSceneConstants.rttFusionWeight +
              rssiDist * VrSceneConstants.rssiFusionWeight)
          .clamp(
            VrSceneConstants.minRfDistanceMeters,
            VrSceneConstants.maxRfDistanceMeters,
          );
    }
    return rssiDist;
  }

  /// Estimated distance in meters from the **Joystick Smartphone** to the
  /// radio source via the log-distance path-loss model.
  double estimateDistanceFromJoystickMeters() => _rssiToMeters(joystickRssiDbm);

  /// Whether the signal exhibits non-line-of-sight wall/obstacle shadowing
  /// ($\ge 6\text{ dB}$ excess loss).
  bool get hasWallShadowing =>
      estimatedWallAttenuationDb >= VrSceneConstants.rfWallShadowingThresholdDb;

  double _rssiToMeters(double rssiDbm) {
    final safeExponent = math.max(
      VrSceneConstants.minPathLossExponent,
      pathLossExponent,
    );
    final effectiveLossDb =
        txPowerAtOneMeterDbm - rssiDbm - estimatedWallAttenuationDb;
    final rawMeters =
        math.pow(10.0, effectiveLossDb / (10.0 * safeExponent)).toDouble();
    return rawMeters.clamp(
      VrSceneConstants.minRfDistanceMeters,
      VrSceneConstants.maxRfDistanceMeters,
    );
  }
}
