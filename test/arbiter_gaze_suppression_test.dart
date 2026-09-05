import 'package:flutter_test/flutter_test.dart';
import 'package:vrlizate/vrlizate.dart' show CameraRig, GazePointer;
import 'package:vrlizate_scene/vrlizate_scene.dart';

void main() {
  group('StereoSceneView & VrInputArbiter Integration', () {
    test('suppressed dwell restarts on the same target after hysteresis', () {
      var nowUs = 1000000;
      var selections = 0;
      var enters = 0;
      var exits = 0;
      final arbiter = VrInputArbiter(clock: () => nowUs);
      final pointer = GazePointer(
        cameraRig: CameraRig(),
        dwellDuration: 0.8,
        adaptiveDwell: false,
        enableHaptics: false,
        onDwellSelect: (_) => selections++,
        onGazeEnter: (_) => enters++,
        onGazeExit: (_) => exits++,
      );
      void tick(double dt, {bool controllerActive = false}) {
        nowUs += (dt * 1000000).round();
        if (controllerActive) {
          final event = arbiter.acquire(
            type: VrInputType.navigate,
            source: VrInputSource.remotePhone,
            active: true,
          );
          arbiter.submit(event);
          arbiter.release(event);
        }
        pointer.update(
          dt,
          'enter_demo',
          dwellEnabled: !arbiter.isGazeSuppressed,
        );
      }

      tick(0);
      tick(0.5);
      expect(pointer.dwellProgress, greaterThan(0));
      for (var frame = 0; frame < 120; frame++) {
        tick(1 / 60, controllerActive: true);
      }
      expect(selections, 0);
      expect(pointer.dwellProgress, 0);
      tick(0.399);
      expect(arbiter.isGazeSuppressed, isTrue);
      expect(pointer.dwellProgress, 0);
      tick(0.002);
      expect(arbiter.isGazeSuppressed, isFalse);
      tick(0.4);
      expect(selections, 0, reason: 'Old dwell progress must not survive.');
      tick(0.4);
      expect(selections, 1);
      tick(1);
      expect(selections, 1, reason: 'Select only once until the gaze changes.');
      expect(enters, 1, reason: 'Suppression must preserve hover.');
      expect(exits, 0);
      expect(arbiter.pool.inUseCount, 0);
      arbiter.dispose();
    });

    test(
      'VrInputArbiter correctly suppresses gaze when remote phone is active',
      () {
        var fakeTimeUs = 1000000;
        final arbiter = VrInputArbiter(
          clock: () => fakeTimeUs,
          suppressionWindow: const Duration(milliseconds: 400),
        );

        // Initially, no high priority inputs: gaze is NOT suppressed
        expect(arbiter.isGazeSuppressed, isFalse);

        // Remote phone emits an active trigger event
        final event = arbiter.acquire(
          type: VrInputType.trigger,
          source: VrInputSource.remotePhone,
          active: true,
        );
        expect(arbiter.submit(event), isTrue);
        arbiter.release(event);

        // Gaze must now be suppressed!
        expect(arbiter.isGazeSuppressed, isTrue);

        // Advance clock by 200ms (within the 400ms suppression window)
        fakeTimeUs += 200000;
        expect(arbiter.isGazeSuppressed, isTrue);

        // Advance clock by another 250ms (total 450ms > 400ms window)
        fakeTimeUs += 250000;
        expect(arbiter.isGazeSuppressed, isFalse);

        arbiter.dispose();
      },
    );

    test('Inactive remote stick deflection does not keep gaze suppressed', () {
      var fakeTimeUs = 1000000;
      final arbiter = VrInputArbiter(
        clock: () => fakeTimeUs,
        suppressionWindow: const Duration(milliseconds: 300),
      );

      // Controller centered / inactive
      final event = arbiter.acquire(
        type: VrInputType.navigate,
        source: VrInputSource.remotePhone,
        active: false,
      );
      arbiter.submit(event);
      arbiter.release(event);

      expect(arbiter.isGazeSuppressed, isFalse);

      arbiter.dispose();
    });
  });
}
