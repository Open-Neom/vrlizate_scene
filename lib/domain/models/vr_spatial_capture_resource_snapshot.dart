import '../../utils/enums/vr_sensing_modality.dart';
import '../../utils/enums/vr_spatial_capture_power_mode.dart';

/// Telemetry snapshot of CPU, GPU, and battery power consumption across the
/// **Visor Smartphone** and **Joystick Smartphone** for the Spatial Capture
/// pipeline.
class VrSpatialCaptureResourceSnapshot {
  const VrSpatialCaptureResourceSnapshot({
    required this.powerMode,
    required this.visorCpuLoadPercent,
    required this.joystickCpuLoadPercent,
    required this.visorGpuOverheadPercent,
    required this.estimatedExtraPowerMilliwattsVisor,
    required this.estimatedExtraPowerMilliwattsJoystick,
    required this.activeModalities,
    required this.modalityTickRatesHz,
    required this.floorCoverageDiameterMeters,
    required this.isVisorFrameBudgetProtected,
  });

  final VrSpatialCapturePowerMode powerMode;

  /// Percentage of total CPU capacity consumed by Spatial Capture on the Visor
  /// Smartphone (kept below $2.5\%$ in `joystickOffloadedVisorPriority` mode).
  final double visorCpuLoadPercent;

  /// Percentage of total CPU/NPU capacity consumed on the Joystick Smartphone
  /// (which handles the heavy floor/torso vision and ultrasonic DSP while its
  /// 3D GPU is idle).
  final double joystickCpuLoadPercent;

  /// Extra GPU overhead on the Visor Smartphone (only stereoscopic wireframe
  /// line projection, typically $< 0.5\%$).
  final double visorGpuOverheadPercent;

  /// Estimated extra power draw in milliwatts on the Visor Smartphone.
  final double estimatedExtraPowerMilliwattsVisor;

  /// Estimated extra power draw in milliwatts on the Joystick Smartphone.
  final double estimatedExtraPowerMilliwattsJoystick;

  /// Currently active sensing modalities.
  final Set<VrSensingModality> activeModalities;

  /// Assigned sampling frequency in Hz per modality.
  final Map<VrSensingModality, double> modalityTickRatesHz;

  /// Diameter in meters of the floor area covered by the Joystick rear camera.
  final double floorCoverageDiameterMeters;

  /// True when the Visor's stereo frame budget ($90\text{–}120\text{ FPS}$) is
  /// protected from sensor-processing stalls.
  final bool isVisorFrameBudgetProtected;
}
