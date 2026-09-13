import 'package:flutter_test/flutter_test.dart';
import 'package:vrlizate/vrlizate.dart' show CameraRig, GazePointer;
import 'package:vrlizate_scene/src/vr_scene_pointer_interaction.dart';

void main() {
  test(
    'disabling gaze clears hover and near-complete dwell on the next tick',
    () {
      final lifecycle = VrSceneGazeLifecycle();
      final exits = <String>[];
      var selections = 0;
      final gaze = GazePointer(
        cameraRig: CameraRig(),
        dwellDuration: 1.4,
        adaptiveDwell: false,
        enableHaptics: false,
        onGazeExit: exits.add,
        onDwellSelect: (_) => selections++,
      );
      gaze.update(0, 'demo');
      gaze.update(1.3, 'demo');
      expect(gaze.dwellProgress, greaterThan(.9));
      lifecycle.configurationChanged(
        previousGazeEnabled: true,
        gazeEnabled: false,
      );
      expect(exits, isEmpty, reason: 'No parent callback during widget build.');
      lifecycle.beforeTick(gaze, gazeEnabled: false, systemGazeEnabled: false);
      expect(gaze.gazeTargetId, isNull);
      expect(gaze.dwellProgress, 0);
      expect(exits, ['demo']);
      lifecycle.beforeTick(gaze, gazeEnabled: false, systemGazeEnabled: false);
      expect(exits, [
        'demo',
      ], reason: 'No repeated hover exits while disabled.');

      lifecycle.configurationChanged(
        previousGazeEnabled: false,
        gazeEnabled: true,
      );
      lifecycle.beforeTick(gaze, gazeEnabled: true, systemGazeEnabled: false);
      gaze.update(0, 'demo');
      gaze.update(.2, 'demo');
      expect(
        selections,
        0,
        reason: '1.3 seconds from before hiding must not resume.',
      );
      expect(gaze.dwellProgress, closeTo(.2 / 1.4, 1e-9));
      gaze.update(1.21, 'demo');
      expect(selections, 1);
    },
  );

  test('disabling clears grace even with system HOME still enabled', () {
    final lifecycle = VrSceneGazeLifecycle();
    var selections = 0;
    final gaze = GazePointer(
      cameraRig: CameraRig(),
      dwellDuration: 1.4,
      adaptiveDwell: false,
      enableHaptics: false,
      onDwellSelect: (_) => selections++,
    );
    gaze.update(0, 'demo');
    gaze.update(1.3, 'demo');
    gaze.update(.05, null);
    expect(gaze.gazeTargetId, 'demo', reason: 'Original grace is active.');
    lifecycle.configurationChanged(
      previousGazeEnabled: true,
      gazeEnabled: false,
    );
    lifecycle.beforeTick(gaze, gazeEnabled: false, systemGazeEnabled: true);
    expect(gaze.gazeTargetId, isNull);
    expect(gaze.dwellProgress, 0);
    // Returning immediately to the same id must not restore saved grace time.
    lifecycle.configurationChanged(
      previousGazeEnabled: false,
      gazeEnabled: true,
    );
    lifecycle.beforeTick(gaze, gazeEnabled: true, systemGazeEnabled: true);
    gaze.update(0, 'demo');
    gaze.update(.2, 'demo');
    expect(selections, 0);
    expect(gaze.dwellProgress, closeTo(.2 / 1.4, 1e-9));
    gaze.update(0, 'HOME');
    gaze.update(.2, 'HOME');
    expect(
      gaze.dwellProgress,
      greaterThan(0),
      reason: 'System dwell still works.',
    );
  });

  test('off/on before the next tick still discards the interrupted dwell', () {
    final lifecycle = VrSceneGazeLifecycle();
    final gaze = GazePointer(
      cameraRig: CameraRig(),
      dwellDuration: 1.4,
      enableHaptics: false,
    );
    gaze.update(0, 'demo');
    gaze.update(1.3, 'demo');
    lifecycle.configurationChanged(
      previousGazeEnabled: true,
      gazeEnabled: false,
    );
    lifecycle.configurationChanged(
      previousGazeEnabled: false,
      gazeEnabled: true,
    );
    lifecycle.beforeTick(gaze, gazeEnabled: true, systemGazeEnabled: false);
    expect(gaze.gazeTargetId, isNull);
    expect(gaze.dwellProgress, 0);
    gaze.update(0, 'demo');
    gaze.update(.1, 'demo');
    expect(gaze.dwellProgress, closeTo(.1 / 1.4, 1e-9));
  });
}
