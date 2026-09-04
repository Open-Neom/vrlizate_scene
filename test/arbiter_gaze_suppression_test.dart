import 'package:flutter_test/flutter_test.dart';
import 'package:vrlizate_scene/vrlizate_scene.dart';

void main() {
  group('StereoSceneView & VrInputArbiter Integration', () {
    test('VrInputArbiter correctly suppresses gaze when remote phone is active', () {
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
    });

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
