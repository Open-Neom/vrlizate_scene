import 'dart:async';

import 'quality_preset.dart';

/// Performance event emitted when the thermal governor adjusts rendering settings.
class VrThermalEvent {
  final VrQualityPreset previousPreset;
  final VrQualityPreset newPreset;
  final double currentFps;
  final String reason;
  final DateTime timestamp;

  VrThermalEvent({
    required this.previousPreset,
    required this.newPreset,
    required this.currentFps,
    required this.reason,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  @override
  String toString() =>
      'VrThermalEvent(${previousPreset.tier} -> ${newPreset.tier} at ${currentFps.toStringAsFixed(1)} FPS: $reason)';
}

/// Adaptive thermal and frame-rate governor for mobile VR rendering.
///
/// Continuously monitors frame time and rolling FPS to prevent thermal throttling
/// and battery drain on mobile SoCs by dynamically scaling down quality tiers.
class VrThermalGovernor {
  VrQualityPreset _currentPreset;
  final double targetFps;
  final double stepDownThresholdFps;
  final double stepUpThresholdFps;

  final List<double> _frameTimes = [];
  static const int _sampleWindowSize = 60;

  double _secondsSinceLastCheck = 0.0;
  static const double _evaluationIntervalSeconds = 3.0;

  int _consecutiveLowCycles = 0;
  double _stableHighTimeSeconds = 0.0;
  static const double _stableCooldownRequiredSeconds = 25.0;

  final StreamController<VrThermalEvent> _eventController =
      StreamController<VrThermalEvent>.broadcast();

  VrThermalGovernor({
    VrQualityPreset initialPreset = VrQualityPreset.high,
    this.targetFps = 60.0,
    double? stepDownThresholdFps,
    double? stepUpThresholdFps,
  })  : _currentPreset = initialPreset,
        stepDownThresholdFps = stepDownThresholdFps ?? 54.0,
        stepUpThresholdFps = stepUpThresholdFps ?? 58.5;

  VrQualityPreset get currentPreset => _currentPreset;
  set currentPreset(VrQualityPreset preset) => _currentPreset = preset;

  Stream<VrThermalEvent> get onThermalEvent => _eventController.stream;

  /// Returns current rolling average FPS calculated from the sample window.
  double get currentFps {
    if (_frameTimes.isEmpty) return targetFps;
    final total = _frameTimes.reduce((a, b) => a + b);
    final avgDelta = total / _frameTimes.length;
    if (avgDelta <= 0.0) return targetFps;
    return 1.0 / avgDelta;
  }

  /// Records a newly completed frame delta time (in seconds) and evaluates governor policy.
  ///
  /// Returns the newly determined [VrQualityPreset] (or unchanged if stable).
  VrQualityPreset recordFrame(double frameDtSeconds) {
    if (frameDtSeconds > 0.0 && frameDtSeconds < 0.5) {
      _frameTimes.add(frameDtSeconds);
      if (_frameTimes.length > _sampleWindowSize) {
        _frameTimes.removeAt(0);
      }
    }

    _secondsSinceLastCheck += frameDtSeconds;

    if (_secondsSinceLastCheck >= _evaluationIntervalSeconds) {
      _secondsSinceLastCheck = 0.0;
      final fps = currentFps;

      // 1. Check for thermal degradation / dropped frames
      if (fps < stepDownThresholdFps) {
        _consecutiveLowCycles++;
        _stableHighTimeSeconds = 0.0;

        // If low for 2 consecutive 3-second evaluation cycles, step down
        if (_consecutiveLowCycles >= 2) {
          _consecutiveLowCycles = 0;
          final prev = _currentPreset;
          final next = prev.stepDown;

          if (prev != next) {
            _currentPreset = next;
            final event = VrThermalEvent(
              previousPreset: prev,
              newPreset: next,
              currentFps: fps,
              reason: 'Prevención de sobrecalentamiento por baja de FPS prolongada',
            );
            _eventController.add(event);
          }
        }
      } else if (fps >= stepUpThresholdFps) {
        // 2. High stable performance cooldown
        _consecutiveLowCycles = 0;
        _stableHighTimeSeconds += _evaluationIntervalSeconds;

        if (_stableHighTimeSeconds >= _stableCooldownRequiredSeconds) {
          _stableHighTimeSeconds = 0.0;
          final prev = _currentPreset;
          final next = prev.stepUp;

          if (prev != next) {
            _currentPreset = next;
            final event = VrThermalEvent(
              previousPreset: prev,
              newPreset: next,
              currentFps: fps,
              reason: 'Recuperación térmica y estabilidad de tasa de refresco',
            );
            _eventController.add(event);
          }
        }
      } else {
        // Nominal steady state (neutral FPS band)
        _consecutiveLowCycles = 0;
        _stableHighTimeSeconds = 0.0;
      }
    }

    return _currentPreset;
  }

  void dispose() {
    _eventController.close();
  }
}
