import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Sustained pressure in Flutter's build/raster stages, not GPU completion or
/// display presentation. The stages are pipelined, so each is compared with the
/// budget independently; their durations must not be added together.
class VrFrameQualityPolicy {
  VrFrameQualityPolicy({
    double targetRefreshRateHz = 60,
    this.warmupFrames = 30,
    this.windowFrames = 45,
    this.requiredSlowWindows = 2,
    this.slowFrameFraction = 0.2,
  }) : _targetRefreshRateHz = _validateRate(targetRefreshRateHz) {
    if (warmupFrames < 0 || windowFrames < 1 || requiredSlowWindows < 1) {
      throw ArgumentError(
        'Frame counts must be positive (warmup may be zero).',
      );
    }
    if (!slowFrameFraction.isFinite ||
        slowFrameFraction <= 0 ||
        slowFrameFraction > 1) {
      throw ArgumentError.value(slowFrameFraction, 'slowFrameFraction');
    }
  }

  final int warmupFrames;
  final int windowFrames;
  final int requiredSlowWindows;
  final double slowFrameFraction;
  double _targetRefreshRateHz;
  int _warmupSamples = 0;
  int _samples = 0;
  int _slowSamples = 0;
  int _slowWindows = 0;

  double get targetRefreshRateHz => _targetRefreshRateHz;
  double get frameBudgetMicroseconds => 1000000 / _targetRefreshRateHz;

  set targetRefreshRateHz(double value) {
    value = _validateRate(value);
    if (_targetRefreshRateHz == value) return;
    _targetRefreshRateHz = value;
    reset();
  }

  static double _validateRate(double value) {
    if (!value.isFinite || value <= 0) {
      throw ArgumentError.value(value, 'targetRefreshRateHz');
    }
    return value;
  }

  /// Starts a fresh warmup after visibility, scene, refresh-rate or quality
  /// changes. Delayed timing batches and allocation/shader warmup should not
  /// immediately reduce the newly active scene's quality.
  void reset() {
    _warmupSamples = 0;
    _samples = 0;
    _slowSamples = 0;
    _slowWindows = 0;
  }

  /// True once sustained overload warrants one quality step down. Long frames
  /// are retained, including raster durations above 50 ms; invalid negative
  /// durations are the only discarded samples.
  bool record({
    required int buildMicroseconds,
    required int rasterMicroseconds,
  }) {
    if (buildMicroseconds < 0 || rasterMicroseconds < 0) return false;
    if (_warmupSamples < warmupFrames) {
      _warmupSamples++;
      return false;
    }
    _samples++;
    if (buildMicroseconds > frameBudgetMicroseconds ||
        rasterMicroseconds > frameBudgetMicroseconds) {
      _slowSamples++;
    }
    if (_samples < windowFrames) return false;
    final slow = _slowSamples / _samples >= slowFrameFraction;
    _slowWindows = slow ? _slowWindows + 1 : 0;
    _samples = 0;
    _slowSamples = 0;
    if (_slowWindows < requiredSlowWindows) return false;
    reset();
    return true;
  }
}

/// Owns one engine timing subscription while its scene is active and the app
/// resumed. Call [setActive] with TickerMode/scene visibility and [dispose] when
/// the scene leaves the tree. There is no timer or per-frame allocation here.
class VrFrameQualityMonitor with WidgetsBindingObserver {
  VrFrameQualityMonitor({
    required this.policy,
    required this.onPressure,
    WidgetsBinding? binding,
  }) : _binding = binding ?? WidgetsBinding.instance {
    _binding.addObserver(this);
  }

  final VrFrameQualityPolicy policy;
  final VoidCallback onPressure;
  final WidgetsBinding _binding;
  bool _active = false;
  bool _listening = false;
  bool _disposed = false;
  AppLifecycleState? _lifecycle;
  late final TimingsCallback _callback = _recordTimings;

  bool get isListening => _listening;

  void setActive(bool active) {
    if (_disposed) return;
    _active = active;
    _syncSubscription();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycle = state;
    _syncSubscription();
  }

  void _syncSubscription() {
    final state = _lifecycle ?? _binding.lifecycleState;
    final listen =
        _active && (state == null || state == AppLifecycleState.resumed);
    if (listen == _listening) return;
    _listening = listen;
    policy.reset();
    if (listen) {
      _binding.addTimingsCallback(_callback);
    } else {
      _binding.removeTimingsCallback(_callback);
    }
  }

  void _recordTimings(List<FrameTiming> timings) {
    if (!_listening || _disposed) return;
    for (final timing in timings) {
      if (policy.record(
        buildMicroseconds: timing.buildDuration.inMicroseconds,
        rasterMicroseconds: timing.rasterDuration.inMicroseconds,
      )) {
        onPressure();
        // A batch describes the previous quality. Never take multiple steps
        // from that batch before a newly rendered tier can be measured.
        return;
      }
    }
  }

  void dispose() {
    if (_disposed) return;
    setActive(false);
    _disposed = true;
    _binding.removeObserver(this);
  }
}
