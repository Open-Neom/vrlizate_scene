import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' show FramePhase;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/scheduler.dart';

/// Bounded frame-stage samples. Recording reuses the two allocated arrays;
/// sorting and summary allocation happen only when [snapshot] is requested.
class VrFrameMetricsWindow {
  VrFrameMetricsWindow({this.targetRefreshRateHz = 60, this.capacity = 2400})
    : _buildUs = Int64List(_validCapacity(capacity)),
      _rasterUs = Int64List(_validCapacity(capacity)) {
    if (!targetRefreshRateHz.isFinite || targetRefreshRateHz <= 0) {
      throw ArgumentError.value(targetRefreshRateHz, 'targetRefreshRateHz');
    }
  }

  final double targetRefreshRateHz;
  final int capacity;
  final Int64List _buildUs;
  final Int64List _rasterUs;
  int _next = 0;
  int _count = 0;
  int _received = 0;

  static int _validCapacity(int value) {
    if (value < 1) throw ArgumentError.value(value, 'capacity');
    return value;
  }

  /// Number of samples retained in the ring (at most [capacity]).
  int get sampleCount => _count;

  void record({
    required int buildMicroseconds,
    required int rasterMicroseconds,
  }) {
    if (buildMicroseconds < 0 || rasterMicroseconds < 0) return;
    _buildUs[_next] = buildMicroseconds;
    _rasterUs[_next] = rasterMicroseconds;
    _next = (_next + 1) % capacity;
    if (_count < capacity) _count++;
    _received++;
  }

  void clear() {
    _next = 0;
    _count = 0;
    _received = 0;
  }

  VrFrameMetricsSnapshot? snapshot() {
    if (_count == 0) return null;
    final build = List<int>.generate(_count, (index) => _buildUs[index]);
    final raster = List<int>.generate(_count, (index) => _rasterUs[index]);
    final budgetUs = 1000000 / targetRefreshRateHz;
    var buildOverBudget = 0;
    var rasterOverBudget = 0;
    var eitherOverBudget = 0;
    for (var index = 0; index < _count; index++) {
      final slowBuild = build[index] > budgetUs;
      final slowRaster = raster[index] > budgetUs;
      if (slowBuild) buildOverBudget++;
      if (slowRaster) rasterOverBudget++;
      if (slowBuild || slowRaster) eitherOverBudget++;
    }
    build.sort();
    raster.sort();
    double percentileMs(List<int> sorted, double percentile) =>
        sorted[(sorted.length * percentile).ceil() - 1] / 1000;
    return VrFrameMetricsSnapshot(
      sampleCount: _count,
      receivedFrames: _received,
      targetRefreshRateHz: targetRefreshRateHz,
      buildP50Ms: percentileMs(build, 0.50),
      buildP95Ms: percentileMs(build, 0.95),
      rasterP50Ms: percentileMs(raster, 0.50),
      rasterP95Ms: percentileMs(raster, 0.95),
      buildOverBudgetFrames: buildOverBudget,
      rasterOverBudgetFrames: rasterOverBudget,
      eitherStageOverBudgetFrames: eitherOverBudget,
    );
  }
}

/// CPU-side Flutter timings, not GPU completion or display presentation times.
/// Percentiles use the nearest-rank method over retained samples.
class VrFrameMetricsSnapshot {
  const VrFrameMetricsSnapshot({
    required this.sampleCount,
    required this.receivedFrames,
    required this.targetRefreshRateHz,
    required this.buildP50Ms,
    required this.buildP95Ms,
    required this.rasterP50Ms,
    required this.rasterP95Ms,
    required this.buildOverBudgetFrames,
    required this.rasterOverBudgetFrames,
    required this.eitherStageOverBudgetFrames,
  });

  final int sampleCount;
  final int receivedFrames;
  final double targetRefreshRateHz;
  final double buildP50Ms;
  final double buildP95Ms;
  final double rasterP50Ms;
  final double rasterP95Ms;
  final int buildOverBudgetFrames;
  final int rasterOverBudgetFrames;

  /// Counts each retained frame once if build OR raster exceeds the target.
  /// Stages run in a pipeline, so their durations are not added together.
  /// This is not a count of frames actually dropped by the display.
  final int eitherStageOverBudgetFrames;

  double get frameBudgetMs => 1000 / targetRefreshRateHz;

  String toLogLine() =>
      '[VR_PERF] target_hz=${targetRefreshRateHz.toStringAsFixed(1)} '
      'budget_ms=${frameBudgetMs.toStringAsFixed(2)} '
      'retained=$sampleCount received=$receivedFrames '
      'ui_p50_ms=${buildP50Ms.toStringAsFixed(2)} '
      'ui_p95_ms=${buildP95Ms.toStringAsFixed(2)} '
      'raster_p50_ms=${rasterP50Ms.toStringAsFixed(2)} '
      'raster_p95_ms=${rasterP95Ms.toStringAsFixed(2)} '
      'ui_over=$buildOverBudgetFrames raster_over=$rasterOverBudgetFrames '
      'either_stage_over=$eitherStageOverBudgetFrames '
      '(Flutter thread timings; not GPU completion or dropped frames)';
}

/// Opt-in profiler. Call [start] only when profiling has been requested.
///
/// Uses engine [FrameTiming] reports, not animation tick deltas. Supply the
/// intended display/render refresh rate; the explicit default is 60 Hz.
/// Reports contain only aggregate timings and do not include session/user data.
class VrFrameMetrics {
  VrFrameMetrics({
    double targetRefreshRateHz = 60,
    int capacity = 2400,
    this.reportInterval = const Duration(seconds: 10),
    void Function(String message)? logger,
    SchedulerBinding? binding,
  }) : _window = VrFrameMetricsWindow(
         targetRefreshRateHz: targetRefreshRateHz,
         capacity: capacity,
       ),
       _logger = logger ?? _defaultLogger,
       _binding = binding {
    if (reportInterval <= Duration.zero) {
      throw ArgumentError.value(reportInterval, 'reportInterval');
    }
  }

  final Duration reportInterval;
  final VrFrameMetricsWindow _window;
  final void Function(String message) _logger;
  final SchedulerBinding? _binding;
  SchedulerBinding? _activeBinding;
  Timer? _reportTimer;
  late final TimingsCallback _callback = _recordTimings;

  bool get isRunning => _activeBinding != null;

  static void _defaultLogger(String message) => debugPrint(message);

  void start() {
    if (isRunning) return;
    _window.clear();
    _activeBinding = _binding ?? SchedulerBinding.instance;
    _activeBinding!.addTimingsCallback(_callback);
    _reportTimer = Timer.periodic(reportInterval, (_) => _report());
  }

  void _recordTimings(List<FrameTiming> timings) {
    if (!isRunning) return;
    for (var index = 0; index < timings.length; index++) {
      final timing = timings[index];
      _window.record(
        buildMicroseconds:
            timing.timestampInMicroseconds(FramePhase.buildFinish) -
            timing.timestampInMicroseconds(FramePhase.buildStart),
        rasterMicroseconds:
            timing.timestampInMicroseconds(FramePhase.rasterFinish) -
            timing.timestampInMicroseconds(FramePhase.rasterStart),
      );
    }
  }

  void _report() {
    final summary = _window.snapshot();
    if (summary == null) return;
    _window.clear();
    _logger(summary.toLogLine());
  }

  void stop({bool reportFinal = true}) {
    if (!isRunning) return;
    _activeBinding!.removeTimingsCallback(_callback);
    _activeBinding = null;
    _reportTimer?.cancel();
    _reportTimer = null;
    if (reportFinal) _report();
    _window.clear();
  }
}
