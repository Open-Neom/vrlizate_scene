import 'package:vector_math/vector_math.dart';

import '../../utils/constants/vr_scene_constants.dart';

/// Captures readings from the remaining physical hardware sensors present in
/// conventional smartphones to enrich 3D spatial capture:
/// 1. **Differential MEMS Barometer** (`visorPressureHpa`, `joystickPressureHpa`)
/// 2. **3-Axis Uncalibrated Magnetometer Anomaly** (`localMagneticMicroTesla`,
///    `earthReferenceMagneticMicroTesla`)
/// 3. **Camera Dual-Pixel PDAF Focus Distance** (`lensFocusDistanceDiopters`)
/// 4. **Ambient Light RGB / Color Temperature + IR Proximity** (`ambientLux`,
///    `colorTemperatureKelvin`, `irProximityCentimeters`)
/// 5. **Ultra-Wideband (UWB) Ranging** (`uwbDistanceMeters`, `uwbAzimuthRadians`)
/// 6. **IMU Heel-Strike Footstep Vibrometry** (`heelStrikeShockG`)
class VrEnvironmentalHardwareSample {
  const VrEnvironmentalHardwareSample({
    this.visorPressureHpa,
    this.joystickPressureHpa,
    this.localMagneticMicroTesla,
    this.earthReferenceMagneticMicroTesla,
    this.lensFocusDistanceDiopters,
    this.ambientLux,
    this.colorTemperatureKelvin,
    this.irProximityCentimeters,
    this.uwbDistanceMeters,
    this.uwbAzimuthRadians,
    this.heelStrikeShockG = 0.0,
  });

  /// Barometric pressure at the Visor Smartphone in hPa (e.g. `1013.20`).
  final double? visorPressureHpa;

  /// Barometric pressure at the Joystick Smartphone in hPa (e.g. `1013.26`).
  final double? joystickPressureHpa;

  /// Uncalibrated 3D magnetic field vector ($\mu\text{T}$) at the sensor.
  final Vector3? localMagneticMicroTesla;

  /// Baseline geomagnetic field vector ($\mu\text{T}$) of the room.
  final Vector3? earthReferenceMagneticMicroTesla;

  /// Camera ISP Dual-Pixel PDAF lens focus distance in diopters ($\text{m}^{-1}$).
  final double? lensFocusDistanceDiopters;

  /// Ambient illuminance in Lux from the RGB light sensor.
  final double? ambientLux;

  /// Correlated Color Temperature (CCT) in Kelvin (e.g. $5800\text{ K}$ daylight
  /// window vs. $2900\text{ K}$ indoor warm lamp).
  final double? colorTemperatureKelvin;

  /// Near-field Infrared (IR) proximity sensor distance in centimeters.
  final double? irProximityCentimeters;

  /// IEEE 802.15.4z Ultra-Wideband (UWB) Time-of-Flight distance in meters.
  final double? uwbDistanceMeters;

  /// Ultra-Wideband (UWB) Angle-of-Arrival horizontal azimuth in radians.
  final double? uwbAzimuthRadians;

  /// Peak vertical heel-strike shockwave acceleration in $g$ detected by the
  /// IMU pedometer/vibrometry pipeline.
  final double heelStrikeShockG;

  /// Drift-free vertical elevation difference $\Delta h = y_{\text{visor}} -
  /// y_{\text{joystick}}$ in meters computed from differential barometric
  /// pressure ($\Delta P = P_{\text{joystick}} - P_{\text{visor}}$).
  double? get barometricHeightDeltaMeters {
    final pV = visorPressureHpa;
    final pJ = joystickPressureHpa;
    if (pV == null || pJ == null) return null;
    return (pJ - pV) * VrSceneConstants.barometricMetersPerHpaAtRoomTemp;
  }

  /// Magnitude of the local ferromagnetic anomaly ($\|\mathbf{B}_{\text{local}}
  /// - \mathbf{B}_{\text{earth}}\|$ in $\mu\text{T}$).
  double get magneticAnomalyMagnitudeMicroTesla {
    final local = localMagneticMicroTesla;
    final earth = earthReferenceMagneticMicroTesla;
    if (local == null || earth == null) return 0.0;
    return (local - earth).length;
  }

  /// True when a strong ferromagnetic object (metal desk frame, steel stud,
  /// monitor, appliance) is distorting the local magnetic field.
  bool get hasFerromagneticObstacle =>
      magneticAnomalyMagnitudeMicroTesla >=
      VrSceneConstants.ferromagneticAnomalyThresholdMicroTesla;

  /// Metric depth in meters ($d = 1 / \text{diopters}$) derived directly from
  /// the camera's Dual-Pixel PDAF voice-coil lens position.
  double? get pdafFocusDepthMeters {
    final diopters = lensFocusDistanceDiopters;
    if (diopters == null || diopters < VrSceneConstants.minPdafFocusDiopters) {
      return null;
    }
    return (1.0 / diopters).clamp(
      VrSceneConstants.minPdafFocusDistanceMeters,
      VrSceneConstants.maxPdafFocusDistanceMeters,
    );
  }

  /// True when the Ambient RGB Light Sensor detects a natural daylight window
  /// ($\ge 350\text{ Lux}$ and $\ge 5200\text{ K}$).
  bool get detectsDaylightWindowDirection {
    final lux = ambientLux;
    final cct = colorTemperatureKelvin;
    if (lux == null || cct == null) return false;
    return lux >= VrSceneConstants.windowLightMinLux &&
        cct >= VrSceneConstants.daylightWindowColorTempKelvin;
  }
}
