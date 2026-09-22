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

FrameTiming _timing({int build = 1000, int raster = 40000}) => FrameTiming(
  vsyncStart: 0,
  buildStart: 10,
  buildFinish: 10 + build,
  rasterStart: 11 + build,
  rasterFinish: 11 + build + raster,
  rasterFinishWallTime: 11 + build + raster,
);

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
}
