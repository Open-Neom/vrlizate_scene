import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vrlizate_scene/src/vr_frame_quality.dart';

class _TimingBinding extends AutomatedTestWidgetsFlutterBinding {
  final callbacks = <TimingsCallback>{};

  @override
  void addTimingsCallback(TimingsCallback callback) {
    super.addTimingsCallback(callback);
    callbacks.add(callback);
  }

  @override
  void removeTimingsCallback(TimingsCallback callback) {
    callbacks.remove(callback);
    super.removeTimingsCallback(callback);
  }

  void report(List<FrameTiming> timings) {
    for (final callback in List<TimingsCallback>.of(callbacks)) {
      callback(timings);
    }
  }
}

FrameTiming _timing({
  int build = 1000,
  int raster = 40000,
  int rasterWait = 1,
  int? finish,
}) {
  final rasterFinish = finish ?? 10 + build + rasterWait + raster;
  final rasterStart = rasterFinish - raster;
  final buildFinish = rasterStart - rasterWait;
  final buildStart = buildFinish - build;
  return FrameTiming(
    vsyncStart: buildStart - 10,
    buildStart: buildStart,
    buildFinish: buildFinish,
    rasterStart: rasterStart,
    rasterFinish: rasterFinish,
    rasterFinishWallTime: rasterFinish,
  );
}

bool _record(
  VrFrameQualityPolicy policy, {
  int build = 1000,
  int raster = 1000,
}) => policy.record(buildMicroseconds: build, rasterMicroseconds: raster);

void main() {
  final binding = _TimingBinding();

  for (final hz in [60.0, 90.0, 120.0]) {
    test('$hz Hz compares both pipeline stages with the matching budget', () {
      final policy = VrFrameQualityPolicy(
        targetRefreshRateHz: hz,
        warmupFrames: 0,
        windowFrames: 2,
        requiredSlowWindows: 1,
      );
      expect(policy.frameBudgetMicroseconds, closeTo(1000000 / hz, 0.001));
      final below = (policy.frameBudgetMicroseconds * 0.75).floor();
      // Adding these times would incorrectly classify both fast stages as slow.
      expect(_record(policy, build: below, raster: below), isFalse);
      expect(_record(policy, build: below, raster: below), isFalse);
      final above = (policy.frameBudgetMicroseconds * 1.25).ceil();
      expect(_record(policy, raster: above), isFalse);
      expect(_record(policy, raster: above), isTrue);
      expect(_record(policy, build: above), isFalse);
      expect(_record(policy, build: above), isTrue);
    });
  }

  test('120 Hz catches 12 ms raster that fits the 60 Hz budget', () {
    final policy = VrFrameQualityPolicy(
      warmupFrames: 0,
      windowFrames: 1,
      requiredSlowWindows: 1,
    );
    expect(_record(policy, raster: 12000), isFalse);
    policy.targetRefreshRateHz = 120;
    expect(_record(policy, raster: 12000), isTrue);
  });

  test('warmup and consecutive slow windows prevent transient degradation', () {
    final policy = VrFrameQualityPolicy(warmupFrames: 2, windowFrames: 2);
    expect(_record(policy, raster: 80000), isFalse);
    expect(_record(policy, raster: 80000), isFalse);
    expect(_record(policy, raster: 80000), isFalse);
    expect(_record(policy, raster: 80000), isFalse); // first slow window
    expect(_record(policy), isFalse);
    expect(_record(policy), isFalse); // healthy window resets pressure
    expect(_record(policy, raster: 80000), isFalse);
    expect(_record(policy, raster: 80000), isFalse);
    expect(_record(policy, raster: 80000), isFalse);
    expect(_record(policy, raster: 80000), isTrue);
    // Frames above 50 ms counted and caused pressure, not filtered out.
    expect(_record(policy, raster: 80000), isFalse); // new tier warmup
  });

  test('rate changes/reset discard old pressure and require fresh warmup', () {
    final policy = VrFrameQualityPolicy(warmupFrames: 1, windowFrames: 1);
    _record(policy, raster: 80000); // warmup
    _record(policy, raster: 80000); // first window
    policy.targetRefreshRateHz = 90;
    expect(_record(policy, raster: 80000), isFalse);
    expect(_record(policy, raster: 80000), isFalse);
    expect(_record(policy, raster: 80000), isTrue);
    policy.reset();
    expect(_record(policy, raster: 80000), isFalse);
  });

  test(
    'invalid input is rejected without discarding legitimate long frames',
    () {
      for (final rate in [0.0, -1.0, double.infinity, double.nan]) {
        expect(
          () => VrFrameQualityPolicy(targetRefreshRateHz: rate),
          throwsArgumentError,
        );
      }
      final policy = VrFrameQualityPolicy(warmupFrames: 0, windowFrames: 1);
      expect(_record(policy, raster: -1), isFalse);
      expect(_record(policy, raster: 500000), isFalse);
      expect(_record(policy, raster: 500000), isTrue);
    },
  );

  testWidgets(
    'subscribes only while active/resumed and disposes exactly once',
    (tester) async {
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final baseline = binding.callbacks.length;
      var pressure = 0;
      final monitor = VrFrameQualityMonitor(
        policy: VrFrameQualityPolicy(warmupFrames: 0, windowFrames: 1),
        binding: binding,
        onPressure: () => pressure++,
      );
      expect(monitor.isListening, isFalse);
      monitor.setActive(true);
      monitor.setActive(true);
      expect(binding.callbacks.length, baseline + 1);
      binding.report([_timing()]); // first slow window
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      expect(monitor.isListening, isFalse);
      expect(binding.callbacks.length, baseline);
      binding.report([_timing()]);
      expect(pressure, 0);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect(binding.callbacks.length, baseline + 1);
      binding.report([_timing()]);
      expect(pressure, 0); // reset on resume
      binding.report([_timing()]);
      expect(pressure, 1);
      monitor.setActive(false); // TickerMode/covered scene
      expect(binding.callbacks.length, baseline);
      binding.report([_timing(), _timing()]);
      expect(pressure, 1);
      monitor.setActive(true);
      monitor.dispose();
      monitor.dispose();
      monitor.setActive(true);
      expect(binding.callbacks.length, baseline);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect(binding.callbacks.length, baseline);
    },
  );

  testWidgets('one engine batch cannot reduce multiple quality tiers', (
    tester,
  ) async {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    var pressure = 0;
    final monitor = VrFrameQualityMonitor(
      policy: VrFrameQualityPolicy(
        warmupFrames: 0,
        windowFrames: 1,
        requiredSlowWindows: 1,
      ),
      binding: binding,
      onPressure: () => pressure++,
    )..setActive(true);
    addTearDown(monitor.dispose);
    binding.report(List.generate(120, (_) => _timing()));
    expect(pressure, 1);
    binding.report([_timing()]);
    expect(pressure, 2);
  });

  testWidgets('severe readings reduce at most once per poll', (tester) async {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    var status = 3;
    var reads = 0;
    var pressure = 0;
    late final VrFrameQualityMonitor monitor;
    monitor = VrFrameQualityMonitor(
      policy: VrFrameQualityPolicy(),
      binding: binding,
      clockMicroseconds: () => binding.clock.now().microsecondsSinceEpoch,
      readThermalStatus: () async {
        reads++;
        return status;
      },
      onPressure: () {
        pressure++;
        // Applying a new tier invalidates evidence in StereoSceneView.
        monitor.resetThermalEvidence();
      },
    );
    addTearDown(monitor.dispose);
    monitor.setActive(true);
    await tester.pump(Duration.zero);
    expect(reads, 1);
    expect(pressure, 1);

    monitor.setActive(false);
    monitor.setActive(true);
    await tester.pump(const Duration(seconds: 9));
    expect(reads, 1);
    await tester.pump(const Duration(seconds: 1));
    expect(reads, 2);
    expect(pressure, 2);

    status = 7;
    await tester.pump(const Duration(seconds: 10));
    expect(reads, 3);
    expect(pressure, 2, reason: 'Out-of-range status is unavailable');

    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump(const Duration(seconds: 20));
    expect(reads, 3);
    monitor.dispose();
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  testWidgets('obsolete reads cannot affect a replacement source', (
    tester,
  ) async {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final oldReading = Completer<int?>();
    var reads = 0;
    var pressure = 0;
    final monitor = VrFrameQualityMonitor(
      policy: VrFrameQualityPolicy(),
      binding: binding,
      clockMicroseconds: () => binding.clock.now().microsecondsSinceEpoch,
      readThermalStatus: () => oldReading.future,
      onPressure: () => pressure++,
    )..setActive(true);
    addTearDown(monitor.dispose);
    await tester.pump(Duration.zero);

    monitor.setActive(false);
    monitor.setThermalStatusReader(() async {
      reads++;
      return 3;
    });
    monitor.setActive(true);
    await tester.pump(const Duration(seconds: 20));
    expect(reads, 0, reason: 'The prior read still owns its slot');
    oldReading.complete(3);
    await tester.pump();
    await tester.pump(Duration.zero);
    expect(reads, 1);
    expect(pressure, 1, reason: 'Only the replacement read may reduce quality');
    monitor.dispose();
  });

  testWidgets('recovery needs fresh cool polls and current 120 Hz headroom', (
    tester,
  ) async {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    int? status = 0;
    var recoveries = 0;
    int clock() => binding.clock.now().microsecondsSinceEpoch;
    void reportFrames({int raster = 5000, int rasterWait = 1}) {
      final now = clock();
      binding.report([
        _timing(
          build: 5000,
          raster: raster,
          rasterWait: rasterWait,
          finish: now - 12000,
        ),
        _timing(raster: raster, rasterWait: rasterWait, finish: now),
      ]);
    }

    final monitor = VrFrameQualityMonitor(
      policy: VrFrameQualityPolicy(targetRefreshRateHz: 120, windowFrames: 2),
      binding: binding,
      clockMicroseconds: clock,
      readThermalStatus: () async => status,
      onPressure: () => fail('The workload stays below the frame budget'),
      onRecovery: () => recoveries++,
    )..setActive(true);
    addTearDown(monitor.dispose);
    await tester.pump(Duration.zero); // cool at t=0

    await tester.pump(const Duration(seconds: 10));
    status = null;
    await tester.pump(const Duration(seconds: 10)); // unknown at t=20
    status = 0;
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(seconds: 10)); // cool at t=30–50
    }
    // A frame that would have ample 60 Hz headroom is too close to the 120 Hz
    // budget. Build and raster are assessed independently for recovery too.
    await tester.pump(const Duration(seconds: 9));
    reportFrames(raster: 7000);
    await tester.pump(const Duration(seconds: 1));
    expect(recoveries, 0);

    reportFrames();
    await tester.pump(const Duration(seconds: 10));
    expect(recoveries, 0, reason: 'The healthy workload is stale');

    await tester.pump(const Duration(seconds: 9));
    reportFrames();
    await tester.pump(const Duration(seconds: 1));
    expect(recoveries, 1);

    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(seconds: 9));
      reportFrames();
      await tester.pump(const Duration(seconds: 1));
    }
    expect(recoveries, 1, reason: 'A new tier needs its own cool interval');

    await tester.pump(const Duration(seconds: 9));
    // These frames finished recently but began before t=80, when the prior
    // tier was active. Their individual stages have ample margin.
    reportFrames(rasterWait: const Duration(seconds: 40).inMicroseconds);
    await tester.pump(const Duration(seconds: 1));
    expect(
      recoveries,
      1,
      reason: 'Frames begun before recovery cannot qualify',
    );

    await tester.pump(const Duration(seconds: 9));
    reportFrames();
    await tester.pump(const Duration(seconds: 1));
    expect(recoveries, 2);
    monitor.dispose();
  });

  testWidgets(
    'non-opaque route pauses pressure despite an enabled scene ticker',
    (tester) async {
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final baseline = binding.callbacks.length;
      var pressure = 0;
      final monitor = VrFrameQualityMonitor(
        policy: VrFrameQualityPolicy(
          warmupFrames: 1,
          windowFrames: 1,
          requiredSlowWindows: 2,
        ),
        binding: binding,
        onPressure: () => pressure++,
      );
      addTearDown(monitor.dispose);
      final navigator = GlobalKey<NavigatorState>();
      final probe = GlobalKey<_QualityProbeState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          home: _QualityProbe(key: probe, monitor: monitor),
        ),
      );
      expect(monitor.isListening, isTrue);
      expect(binding.callbacks.length, baseline + 1);
      binding.report([_timing(), _timing()]); // warmup + one slow window
      expect(pressure, 0);

      navigator.currentState!.push<void>(
        PageRouteBuilder<void>(
          opaque: false,
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          pageBuilder: (_, _, _) => const SizedBox.shrink(),
        ),
      );
      await tester.pumpAndSettle();
      expect(probe.currentState!.tickerEnabled, isTrue);
      expect(monitor.isListening, isFalse);
      expect(binding.callbacks.length, baseline);
      binding.report(List.generate(120, (_) => _timing()));
      expect(pressure, 0);

      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(monitor.isListening, isTrue);
      expect(binding.callbacks.length, baseline + 1);
      binding.report([_timing()]); // fresh warmup
      expect(pressure, 0);
      binding.report([_timing()]); // fresh first slow window
      expect(pressure, 0);
      binding.report([_timing()]);
      expect(pressure, 1);

      await tester.pumpWidget(const SizedBox.shrink());
      monitor.dispose();
      expect(binding.callbacks.length, baseline);
    },
  );
}

class _QualityProbe extends StatefulWidget {
  const _QualityProbe({super.key, required this.monitor});
  final VrFrameQualityMonitor monitor;

  @override
  State<_QualityProbe> createState() => _QualityProbeState();
}

class _QualityProbeState extends State<_QualityProbe> {
  bool tickerEnabled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    tickerEnabled = TickerMode.valuesOf(context).enabled;
    widget.monitor.setActiveForContext(context, enabled: true);
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
