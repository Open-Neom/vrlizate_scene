import 'dart:async';
import 'dart:developer' show Timeline;
import 'dart:ui' show FramePhase;

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
    if (!warmupFrames.isFinite ||
        !windowFrames.isFinite ||
        !requiredSlowWindows.isFinite ||
        warmupFrames < 0 ||
        windowFrames < 1 ||
        requiredSlowWindows < 1) {
      throw ArgumentError(
        'Frame counts must be finite and positive (warmup may be zero).',
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
    if (!buildMicroseconds.isFinite ||
        !rasterMicroseconds.isFinite ||
        buildMicroseconds < 0 ||
        rasterMicroseconds < 0) {
      return false;
    }
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
/// the scene leaves the tree. An optional thermal reader is polled only while
/// that subscription is active.
class VrFrameQualityMonitor with WidgetsBindingObserver {
  VrFrameQualityMonitor({
    required this.policy,
    required this.onPressure,
    Future<int?> Function()? readThermalStatus,
    this.onRecovery,
    WidgetsBinding? binding,
    int Function()? clockMicroseconds,
  }) : _binding = binding ?? WidgetsBinding.instance,
       _readThermalStatus = readThermalStatus,
       _clockMicroseconds = clockMicroseconds {
    _binding.addObserver(this);
  }

  final VrFrameQualityPolicy policy;
  final VoidCallback onPressure;
  final VoidCallback? onRecovery;
  final WidgetsBinding _binding;
  final int Function()? _clockMicroseconds;
  bool _active = false;
  bool _listening = false;
  bool _disposed = false;
  AppLifecycleState? _lifecycle;
  late final TimingsCallback _callback = _recordTimings;

  static const _thermalPollInterval = 10 * Duration.microsecondsPerSecond;
  static const _coolReadingMaxGap = 15 * Duration.microsecondsPerSecond;
  static const _coolPeriod = 30 * Duration.microsecondsPerSecond;
  static const _frameTimingMaxAge = 3 * Duration.microsecondsPerSecond;

  Future<int?> Function()? _readThermalStatus;
  Timer? _thermalPollTimer;
  bool _thermalPollInFlight = false;
  int _thermalGeneration = 0;
  int? _lastPollStart;
  int? _coolSince;
  int? _lastCoolReading;
  int? _lastFrameTiming;
  int? _recoveryFramesStart;
  int _healthyFrames = 0;

  bool get isListening => _listening;

  // Flutter's native engine uses the Dart timeline clock for frame phases.
  int _nowMicroseconds() => _clockMicroseconds?.call() ?? Timeline.now;

  /// Changes the source of fresh Android-style thermal severity samples.
  /// Status 0 can support recovery, 3 or higher requests a reduction, and
  /// other or unavailable readings leave the frame-based policy in control.
  void setThermalStatusReader(Future<int?> Function()? reader) {
    if (_disposed || _readThermalStatus == reader) return;
    _readThermalStatus = reader;
    resetThermalEvidence();
    _cancelThermalPollTimer();
    _scheduleThermalPoll();
  }

  /// Clears recovery evidence for a scene, quality, or refresh-rate change.
  /// An outstanding result becomes obsolete, but retains its polling slot
  /// until completion and still counts toward the minimum poll interval.
  void resetThermalEvidence() {
    _thermalGeneration++;
    _coolSince = null;
    _lastCoolReading = null;
    _lastFrameTiming = null;
    _recoveryFramesStart =
        _listening && _readThermalStatus != null && onRecovery != null
        ? _nowMicroseconds()
        : null;
    _healthyFrames = 0;
  }

  /// Resolves the scene's route and ticker visibility together. Non-opaque
  /// routes (dialogs, sheets) can leave the underlying route's ticker enabled;
  /// their timing pressure must not degrade the covered scene's quality.
  /// Call from didChangeDependencies so route changes refresh the subscription.
  void setActiveForContext(BuildContext context, {required bool enabled}) {
    setActive(
      enabled &&
          TickerMode.valuesOf(context).enabled &&
          (ModalRoute.isCurrentOf(context) ?? true),
    );
  }

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
    resetThermalEvidence();
    if (listen) {
      _binding.addTimingsCallback(_callback);
      _scheduleThermalPoll();
    } else {
      _binding.removeTimingsCallback(_callback);
      _cancelThermalPollTimer();
    }
  }

  void _cancelThermalPollTimer() {
    _thermalPollTimer?.cancel();
    _thermalPollTimer = null;
  }

  void _scheduleThermalPoll() {
    if (!_listening ||
        _disposed ||
        _readThermalStatus == null ||
        _thermalPollInFlight ||
        _thermalPollTimer != null) {
      return;
    }
    final lastStart = _lastPollStart;
    final remaining = lastStart == null
        ? 0
        : lastStart + _thermalPollInterval - _nowMicroseconds();
    _thermalPollTimer = Timer(
      remaining > 0 ? Duration(microseconds: remaining) : Duration.zero,
      () => unawaited(_pollThermalStatus()),
    );
  }

  Future<void> _pollThermalStatus() async {
    _thermalPollTimer = null;
    final reader = _readThermalStatus;
    if (!_listening || _disposed || reader == null || _thermalPollInFlight)
      return;
    final generation = _thermalGeneration;
    final startedAt = _nowMicroseconds();
    _lastPollStart = startedAt;
    _thermalPollInFlight = true;
    try {
      int? status;
      try {
        status = await reader();
      } catch (_) {
        // A failing or unavailable platform source supplies no cool evidence.
      }
      if (!_listening || _disposed || generation != _thermalGeneration) return;
      final now = _nowMicroseconds();
      if (now - startedAt > _thermalPollInterval ||
          (status != null && (status < 0 || status > 6))) {
        status = null;
      }
      _applyThermalStatus(status, now);
    } finally {
      _thermalPollInFlight = false;
      _scheduleThermalPoll();
    }
  }

  void _applyThermalStatus(int? status, int now) {
    if (status != 0) {
      _coolSince = null;
      _lastCoolReading = null;
      if (status != null && status >= 3) {
        resetThermalEvidence();
        policy.reset();
        onPressure();
      }
      return;
    }
    final recover = onRecovery;
    if (recover == null) return;
    final lastCool = _lastCoolReading;
    if (lastCool == null || now - lastCool > _coolReadingMaxGap) {
      _coolSince = now;
    }
    _lastCoolReading = now;
    final lastFrame = _lastFrameTiming;
    if (now - _coolSince! >= _coolPeriod &&
        lastFrame != null &&
        now - lastFrame <= _frameTimingMaxAge &&
        _healthyFrames >= policy.windowFrames) {
      resetThermalEvidence();
      policy.reset();
      recover();
    }
  }

  void _recordTimings(List<FrameTiming> timings) {
    if (!_listening || _disposed) return;
    final recoveryStart = _recoveryFramesStart;
    final trackRecovery = recoveryStart != null;
    final now = trackRecovery ? _nowMicroseconds() : 0;
    final lastFrame = _lastFrameTiming;
    if (trackRecovery &&
        (lastFrame == null || now - lastFrame > _frameTimingMaxAge)) {
      _healthyFrames = 0;
    }
    final recoveryBudget = trackRecovery
        ? policy.frameBudgetMicroseconds * .7
        : 0.0;
    for (final timing in timings) {
      final build = timing.buildDuration.inMicroseconds;
      final raster = timing.rasterDuration.inMicroseconds;
      if (recoveryStart != null) {
        _recordRecoveryFrame(
          timing,
          build: build,
          raster: raster,
          budget: recoveryBudget,
          now: now,
          recoveryStart: recoveryStart,
        );
      }
      if (policy.record(buildMicroseconds: build, rasterMicroseconds: raster)) {
        resetThermalEvidence();
        onPressure();
        // A batch describes the previous quality. Never take multiple steps
        // from that batch before a newly rendered tier can be measured.
        return;
      }
    }
  }

  void _recordRecoveryFrame(
    FrameTiming timing, {
    required int build,
    required int raster,
    required double budget,
    required int now,
    required int recoveryStart,
  }) {
    final buildStart = timing.timestampInMicroseconds(FramePhase.buildStart);
    final rasterFinish = timing.timestampInMicroseconds(
      FramePhase.rasterFinish,
    );
    final previous = _lastFrameTiming;
    // Engine batches may arrive after a transition or in a later frame window.
    if (buildStart <= 0 ||
        buildStart < recoveryStart ||
        rasterFinish < buildStart ||
        rasterFinish > now ||
        now - rasterFinish > _frameTimingMaxAge ||
        (previous != null && rasterFinish <= previous)) {
      return;
    }

    if (previous != null && rasterFinish - previous > _frameTimingMaxAge) {
      _healthyFrames = 0;
    }
    _lastFrameTiming = rasterFinish;
    if (build >= 0 && raster >= 0 && build < budget && raster < budget) {
      if (_healthyFrames < policy.windowFrames) _healthyFrames++;
    } else {
      _healthyFrames = 0;
    }
  }

  void dispose() {
    if (_disposed) return;
    setActive(false);
    _disposed = true;
    _binding.removeObserver(this);
  }
}
