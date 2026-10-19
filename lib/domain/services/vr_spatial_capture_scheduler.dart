import '../../utils/constants/vr_scene_constants.dart';
import '../../utils/enums/vr_sensing_modality.dart';
import '../../utils/enums/vr_spatial_capture_power_mode.dart';
import '../models/vr_device_sensor_pair_profile.dart';
import '../models/vr_spatial_capture_resource_snapshot.dart';

/// Schedules multi-rate sensor duty-cycling and asymmetric workload offloading
/// between the **Visor Smartphone** (e.g. Samsung Galaxy S25) and the
/// **Joystick Smartphone** (e.g. Motorola Edge) so that 10-modality Spatial
/// Capture runs with near-zero impact on stereo rendering FPS.
class VrSpatialCaptureScheduler {
  VrSpatialCaptureScheduler({
    VrDeviceSensorPairProfile? profile,
    this.powerMode = VrSpatialCapturePowerMode.joystickOffloadedVisorPriority,
  }) : profile =
           profile ?? VrDeviceSensorPairProfile.s25VisorAndMotoEdgeJoystick();

  final VrDeviceSensorPairProfile profile;
  VrSpatialCapturePowerMode powerMode;

  final Map<VrSensingModality, double> _lastSampleTimestampSec =
      <VrSensingModality, double>{};

  /// Computes the adaptive sampling rates, CPU/GPU load distribution, and
  /// power budget for the current frame given [userSpeedMetersPerSec] and
  /// [visorFrameTimeMs].
  VrSpatialCaptureResourceSnapshot evaluateResourceBudget({
    double userSpeedMetersPerSec = 0.25,
    double visorFrameTimeMs = 8.3,
    double joystickHeightMeters = 1.05,
  }) {
    final isMoving = userSpeedMetersPerSec > 0.12;
    final visorUnderThermalOrFrameLoad =
        visorFrameTimeMs > VrSceneConstants.visorThermalThrottleFrameMs;

    final supported = profile.supportedModalities;
    final rates = <VrSensingModality, double>{};

    for (final modality in supported) {
      rates[modality] = _targetRateHzFor(
        modality: modality,
        isMoving: isMoving,
        visorUnderLoad: visorUnderThermalOrFrameLoad,
      );
    }

    // Compute asymmetric CPU/GPU/mW split between Visor (S25) and Joystick (Moto Edge)
    final offloadToJoystick =
        powerMode == VrSpatialCapturePowerMode.joystickOffloadedVisorPriority ||
        visorUnderThermalOrFrameLoad;

    final visionRate = rates[VrSensingModality.triCameraVision] ?? 0.0;
    final sonarRate = rates[VrSensingModality.acousticSonarEcho] ?? 0.0;
    final rfRate = rates[VrSensingModality.wifiRfSensing] ?? 0.0;

    // On S25 + Moto Edge with joystickOffloadedVisorPriority:
    // - 2 of the 3 cameras (rear floor + front torso) and Ultrasonic/RF DSP run
    //   100% on the Moto Edge Joystick!
    // - PDAF, ALS, Barometer, Magnetometer, and IMU run on hardware sensor hubs
    //   (< 0.4% CPU combined).
    final visorCpu = offloadToJoystick
        ? (0.35 + visionRate * 0.11 + sonarRate * 0.03)
        : (0.60 + visionRate * 0.28 + sonarRate * 0.12 + rfRate * 0.15);

    final joystickCpu = offloadToJoystick
        ? (0.55 + visionRate * 0.34 + sonarRate * 0.15 + rfRate * 0.18)
        : (0.45 + visionRate * 0.20 + sonarRate * 0.10 + rfRate * 0.10);

    final visorMw = offloadToJoystick
        ? (32.0 + visionRate * 6.5 + sonarRate * 1.8)
        : (65.0 + visionRate * 14.0 + sonarRate * 5.0 + rfRate * 8.0);

    final joystickMw = offloadToJoystick
        ? (48.0 + visionRate * 11.5 + sonarRate * 4.5 + rfRate * 6.0)
        : (40.0 + visionRate * 8.0 + sonarRate * 3.5 + rfRate * 4.0);

    return VrSpatialCaptureResourceSnapshot(
      powerMode: powerMode,
      visorCpuLoadPercent: visorCpu.clamp(0.4, 15.0),
      joystickCpuLoadPercent: joystickCpu.clamp(0.5, 22.0),
      visorGpuOverheadPercent: 0.40,
      estimatedExtraPowerMilliwattsVisor: visorMw,
      estimatedExtraPowerMilliwattsJoystick: joystickMw,
      activeModalities: supported,
      modalityTickRatesHz: Map<VrSensingModality, double>.unmodifiable(rates),
      floorCoverageDiameterMeters: profile.floorCoverageDiameterMeters(
        joystickHeightMeters: joystickHeightMeters,
      ),
      isVisorFrameBudgetProtected:
          offloadToJoystick && visorCpu < 3.5,
    );
  }

  /// Returns `true` when [modality] is due to sample at [elapsedSeconds] under
  /// the staggered multi-rate schedule, preventing multiple heavy sensors from
  /// firing on the same frame.
  bool shouldSampleModality({
    required VrSensingModality modality,
    required double elapsedSeconds,
    double userSpeedMetersPerSec = 0.25,
    double visorFrameTimeMs = 8.3,
  }) {
    if (!profile.supportedModalities.contains(modality)) return false;
    final rateHz = _targetRateHzFor(
      modality: modality,
      isMoving: userSpeedMetersPerSec > 0.12,
      visorUnderLoad:
          visorFrameTimeMs > VrSceneConstants.visorThermalThrottleFrameMs,
    );
    if (rateHz <= 0.0) return false;
    final intervalSec = 1.0 / rateHz;
    final lastSec = _lastSampleTimestampSec[modality];
    if (lastSec == null || (elapsedSeconds - lastSec) >= intervalSec) {
      _lastSampleTimestampSec[modality] = elapsedSeconds;
      return true;
    }
    return false;
  }

  double _targetRateHzFor({
    required VrSensingModality modality,
    required bool isMoving,
    required bool visorUnderLoad,
  }) {
    final scale = switch (powerMode) {
      VrSpatialCapturePowerMode.ultraLowPower => 0.4,
      VrSpatialCapturePowerMode.balancedAdaptive => isMoving ? 1.0 : 0.5,
      VrSpatialCapturePowerMode.highPrecisionScan => 1.5,
      VrSpatialCapturePowerMode.joystickOffloadedVisorPriority =>
        isMoving ? 1.0 : 0.5,
    };

    return switch (modality) {
      VrSensingModality.imuFootstepVibrometry => 100.0,
      VrSensingModality.differentialBarometer => 25.0,
      VrSensingModality.cameraPdafFocusDepth => 30.0 * scale,
      VrSensingModality.triCameraVision =>
        (visorUnderLoad ? 8.0 : 12.0) * scale,
      VrSensingModality.acousticSonarEcho => 12.0 * scale,
      VrSensingModality.ultraWidebandToF => 20.0 * scale,
      VrSensingModality.magneticAnomalyField => 10.0 * scale,
      VrSensingModality.ambientLightAndIrProximity => 5.0 * scale,
      VrSensingModality.bluetoothBleRadar => (isMoving ? 2.0 : 0.25) * scale,
      VrSensingModality.wifiRfSensing => (isMoving ? 1.0 : 0.10) * scale,
    };
  }
}
