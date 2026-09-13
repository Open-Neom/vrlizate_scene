import 'package:flutter_scene/scene.dart' show Node;
import 'package:vector_math/vector_math.dart' as vm;
import 'package:vrlizate/vrlizate.dart'
    show
        VrGamepadButton,
        VrInputEvent,
        VrInputSource,
        VrInputType,
        VrSpatialInputState;

import 'stereo_head_rig.dart';

/// CPU-only input integration shared by the widget and its regression tests.
/// Pick callbacks must restrict hits to the currently interactive scene/modal.
class VrSceneInputController {
  final StereoHeadRig rig;
  final Node? Function(vm.Ray ray) pick;
  final void Function(Node node) activate;
  final void Function() recenter;
  final bool Function(Node node)? isSystemNode;
  final VrSpatialInputState state;
  bool locomotionEnabled;
  bool lookInputEnabled;
  final vm.Ray _ray = vm.Ray();
  final vm.Vector3 _movement = vm.Vector3.zero();
  final List<bool> _triggerHeld = List.filled(
    VrInputSource.values.length,
    false,
  );

  VrSceneInputController({
    required this.rig,
    required this.pick,
    required this.activate,
    required this.recenter,
    this.isSystemNode,
    this.locomotionEnabled = true,
    this.lookInputEnabled = true,
    VrSpatialInputState? state,
  }) : state = state ?? VrSpatialInputState();

  bool get pointerActive => state.pointerActive;

  /// Borrowed ray, updated using the current viewer pose on every access.
  vm.Ray get ray {
    state.writeRay(
      _ray,
      origin: rig.eyeCenter,
      forward: rig.forward,
      screenRight: rig.screenRight,
      up: rig.up,
    );
    return _ray;
  }

  /// Early listener: reserve system HOME/recenter before gameplay consumes an
  /// action. Normal controls remain for the late [handleEvent] listener.
  void handleSystemEvent(VrInputEvent event) {
    if (event.handled) return;
    state.handleEvent(event);
    if (event.type == VrInputType.recenter && event.active) {
      reset();
      event.consume();
      recenter();
      return;
    }
    final triggerDown =
        _isPrimaryTrigger(event) &&
        event.active &&
        !_triggerHeld[event.source.index];
    if (!(event.type == VrInputType.select && event.active) && !triggerDown) {
      return;
    }
    final node = pick(ray);
    if (node == null || !(isSystemNode?.call(node) ?? false)) return;
    if (triggerDown) _triggerHeld[event.source.index] = true;
    event.consume();
    activate(node);
  }

  bool _isPrimaryTrigger(VrInputEvent event) {
    if (event.type != VrInputType.trigger) return false;
    final button = event.data?['button'];
    return button == null || button == VrGamepadButton.r2 || button == 'r2';
  }

  void handleEvent(VrInputEvent event) {
    var triggerDown = false;
    if (event.type == VrInputType.trigger) {
      // X/Y/L2 are secondary actions, not aliases for the primary trigger.
      if (!_isPrimaryTrigger(event)) return;
      triggerDown = event.active && !_triggerHeld[event.source.index];
      _triggerHeld[event.source.index] = event.active;
    }
    if (event.handled) return;
    state.handleEvent(event);
    if (event.type == VrInputType.recenter && event.active) {
      reset();
      event.consume();
      recenter();
      return;
    }
    if (!(event.type == VrInputType.select && event.active) && !triggerDown) {
      return;
    }
    // Resolve now, not from last frame's gaze ID. The controller may have
    // changed pose or a modal may have opened since the last rendered frame.
    final node = pick(ray);
    if (node == null) return;
    event.consume();
    activate(node);
  }

  void update(double dt) {
    state.update(dt);
    if (!dt.isFinite || dt <= 0) return;
    // Avoid a large teleport after a paused/resumed frame.
    final step = dt.clamp(0.0, 0.1);
    if (lookInputEnabled && (state.lookX != 0 || state.lookY != 0)) {
      rig.rotate(-state.lookX * 1.8 * step, -state.lookY * 1.5 * step);
    }
    if (!locomotionEnabled || (state.moveX == 0 && state.moveY == 0)) return;
    state.writeMovement(
      _movement,
      forward: rig.forward,
      screenRight: rig.screenRight,
      dt: step,
    );
    rig.eyeCenter.add(_movement);
  }

  void reset() {
    state.reset();
    _triggerHeld.fillRange(0, _triggerHeld.length, false);
  }
}
