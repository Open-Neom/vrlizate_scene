import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vrlizate/vrlizate.dart' show CameraRig, GazePointer;
import 'package:vrlizate_scene/src/vr_scene_home_control_lifecycle.dart';
import 'package:vrlizate_scene/src/vr_scene_pointer_interaction.dart';

void main() {
  test('unchanged enabled configuration preserves the pending label', () {
    final lifecycle = VrSceneHomeControlLifecycle();
    final attempt = lifecycle.begin()!;
    lifecycle.setEnabled(true);
    expect(lifecycle.accepts(attempt), isTrue);
    expect(lifecycle.begin(), isNull);
  });

  test(
    'disabled controls allocate no attempt and enabled creation is singular',
    () {
      final lifecycle = VrSceneHomeControlLifecycle(enabled: false);
      expect(lifecycle.begin(), isNull);
      expect(lifecycle.creating, isFalse);
      lifecycle.setEnabled(true);
      final attempt = lifecycle.begin()!;
      expect(lifecycle.begin(), isNull);
      expect(lifecycle.accepts(attempt), isTrue);
      lifecycle.finish(attempt);
      expect(lifecycle.creating, isFalse);
    },
  );

  test(
    'false then true cannot attach an old label or finish the new load',
    () async {
      final lifecycle = VrSceneHomeControlLifecycle();
      final oldLabel = Completer<void>();
      final newLabel = Completer<void>();
      var attached = 0;
      Future<void> create(Completer<void> label) async {
        final attempt = lifecycle.begin();
        if (attempt == null) return;
        try {
          await label.future;
          if (lifecycle.accepts(attempt)) attached++;
        } finally {
          lifecycle.finish(attempt);
        }
      }

      final oldCreation = create(oldLabel);
      lifecycle.setEnabled(false);
      expect(lifecycle.begin(), isNull);
      lifecycle.setEnabled(true);
      final newCreation = create(newLabel);
      oldLabel.complete();
      await oldCreation;
      expect(attached, 0);
      expect(lifecycle.creating, isTrue);
      expect(
        lifecycle.begin(),
        isNull,
        reason: 'An old finally must not permit a duplicate current creation.',
      );
      newLabel.complete();
      await newCreation;
      expect(attached, 1);
      expect(lifecycle.creating, isFalse);
    },
  );

  test('scene/scope replacement or disposal invalidates pending creation', () {
    final lifecycle = VrSceneHomeControlLifecycle();
    final previous = lifecycle.begin()!;
    lifecycle.invalidate();
    expect(lifecycle.accepts(previous), isFalse);
    final replacement = lifecycle.begin()!;
    lifecycle.finish(previous);
    expect(lifecycle.accepts(replacement), isTrue);
    lifecycle.invalidate();
    expect(lifecycle.accepts(replacement), isFalse);
    expect(lifecycle.creating, isFalse);
  });

  test(
    'removed HOME resets its dwell on the next tick, outside widget build',
    () {
      final lifecycle = VrSceneGazeLifecycle();
      var exits = 0;
      var selected = 0;
      final gaze = GazePointer(
        cameraRig: CameraRig(),
        adaptiveDwell: false,
        dwellDuration: 1,
        enableHaptics: false,
        onGazeExit: (_) => exits++,
        onDwellSelect: (_) => selected++,
      );
      gaze.update(0, 'HOME');
      gaze.update(.9, 'HOME');
      lifecycle.invalidateTarget();
      expect(exits, 0);
      lifecycle.beforeTick(gaze, gazeEnabled: true, systemGazeEnabled: true);
      expect(exits, 1);
      expect(gaze.gazeTargetId, isNull);
      gaze.update(.2, 'HOME');
      expect(selected, 0);
    },
  );
}
