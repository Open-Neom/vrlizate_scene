import 'package:flutter_test/flutter_test.dart';
import 'package:vrlizate_scene/vrlizate_scene.dart';

void main() {
  group('VrZenithRecenterDetector', () {
    test('fires once after holding the gaze above the zenith threshold', () {
      final detector = VrZenithRecenterDetector();
      var fired = 0;
      // Looking 60° up: negative pitch in CameraRig's convention.
      const lookingUp = -1.05;
      for (var i = 0; i < 60; i++) {
        if (detector.update(lookingUp, 1 / 60)) fired++;
      }
      expect(fired, 1);
      expect(detector.triggered, isTrue);
      expect(detector.progress, 1.0);
      // Holding longer does not fire again.
      for (var i = 0; i < 60; i++) {
        if (detector.update(lookingUp, 1 / 60)) fired++;
      }
      expect(fired, 1);
    });

    test('never fires while looking down, where the controller window is', () {
      final detector = VrZenithRecenterDetector();
      // 55°–85° below the horizon is the virtual controller's visibility band
      // (20° ± 15° from the feet). The old check fired on this whole band.
      for (final degrees in [55.0, 60.0, 70.0, 83.0]) {
        detector.reset();
        final pitch = degrees * 3.141592653589793 / 180;
        var fired = false;
        for (var i = 0; i < 120; i++) {
          fired |= detector.update(pitch, 1 / 60);
        }
        expect(fired, isFalse, reason: 'looking $degrees° down');
        expect(detector.progress, 0);
      }
    });

    test('dropping the gaze resets progress and re-arms', () {
      final detector = VrZenithRecenterDetector(holdSeconds: 0.5);
      for (var i = 0; i < 15; i++) {
        detector.update(-1.2, 1 / 60);
      }
      expect(detector.progress, closeTo(0.5, 1e-9));
      expect(detector.update(0.0, 1 / 60), isFalse);
      expect(detector.progress, 0);
      var fired = false;
      for (var i = 0; i < 31; i++) {
        fired |= detector.update(-1.2, 1 / 60);
      }
      expect(fired, isTrue);
    });

    test('a paused frame cannot complete the hold in one tick', () {
      final detector = VrZenithRecenterDetector(holdSeconds: 0.8);
      expect(detector.update(-1.2, 5.0), isTrue);
      // Clamped to holdSeconds, so exactly one hold, not several.
      expect(detector.progress, 1.0);
    });

    test('ignores non-finite input', () {
      final detector = VrZenithRecenterDetector();
      expect(detector.update(double.nan, 1 / 60), isFalse);
      expect(detector.update(-1.2, double.infinity), isFalse);
      expect(detector.progress, 0);
    });
  });
}
