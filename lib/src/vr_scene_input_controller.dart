import 'package:flutter_scene/scene.dart' show Node;
import 'package:vector_math/vector_math.dart' as vm;
import 'package:vrlizate/vrlizate.dart'
    show
        VrGamepadButton,
        VrGamepadStick,
        VrInputEvent,
        VrInputSource,
        VrInputType,
        VrSpatialInputState,
        VrStickEdgeTurn;

import 'stereo_head_rig.dart';
import 'vr_stick_look.dart';

/// CPU-only input integration shared by the widget and its regression tests.
/// Pick callbacks must restrict hits to the currently interactive scene/modal.
class VrSceneInputController {
  final StereoHeadRig rig;
  final Node? Function(vm.Ray ray) pick;
  final void Function(Node node) activate;
  final void Function() recenter;
  final bool Function(Node node)? isSystemNode;
  final VrSpatialInputState state;
  bool _locomotionEnabled, _lookInputEnabled;
  bool _movementNeedsNeutral = false, _lookNeedsNeutral = false;
  bool _movementWasActive = false, _lookWasActive = false;
  VrInputSource? _movementSource, _lookSource;

  bool get locomotionEnabled => _locomotionEnabled;
  set locomotionEnabled(bool enabled) {
    if (enabled == _locomotionEnabled) return;
    _locomotionEnabled = enabled;
    _movementNeedsNeutral = enabled && _movementWasActive;
    state.moveX = state.moveY = 0;
    _edgeTurn.reset();
  }

  bool get lookInputEnabled => _lookInputEnabled;
  set lookInputEnabled(bool enabled) {
    if (enabled == _lookInputEnabled) return;
    _lookInputEnabled = enabled;
    _lookNeedsNeutral = enabled && _lookWasActive;
    state.lookX = state.lookY = 0;
  }

  bool edgeTurnEnabled;
  final VrStickEdgeTurn _edgeTurn = VrStickEdgeTurn();
  final vm.Ray _ray = vm.Ray();
  final vm.Vector3 _movement = vm.Vector3.zero();
  final List<bool> _triggerHeld = List.filled(
    VrInputSource.values.length,
    false,
  );
  bool _buttonBHeld = false;

  VrSceneInputController({
    required this.rig,
    required this.pick,
    required this.activate,
    required this.recenter,
    this.isSystemNode,
    bool locomotionEnabled = true,
    bool lookInputEnabled = true,
    this.edgeTurnEnabled = true,
    VrSpatialInputState? state,
  }) : state = state ?? VrSpatialInputState(),
       _locomotionEnabled = locomotionEnabled,
       _lookInputEnabled = lookInputEnabled;

  bool get pointerActive => state.pointerActive;

  /// Whether Button B (or secondary back/cancel hold) is currently held down,
  /// enabling deliberate gaze+Button B dragging of 3D panels and widgets.
  bool get buttonBHeld => _buttonBHeld;

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
    _updateButtonBState(event);
    if (event.handled) return;
    state.handleEvent(event);
    _gateNavigation(event);
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

  void _updateButtonBState(VrInputEvent event) {
    final button = event.data?['button'];
    final isB =
        event.type == VrInputType.back ||
        button == VrGamepadButton.b ||
        button == 'b';
    if (isB) {
      _buttonBHeld = event.active;
    }
  }

  void handleEvent(VrInputEvent event) {
    _updateButtonBState(event);
    var triggerDown = false;
    if (event.type == VrInputType.trigger) {
      // X/Y/L2 are secondary actions, not aliases for the primary trigger.
      if (!_isPrimaryTrigger(event)) return;
      triggerDown = event.active && !_triggerHeld[event.source.index];
      _triggerHeld[event.source.index] = event.active;
    }
    if (event.handled) return;
    state.handleEvent(event);
    _gateNavigation(event);
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

  /// Modal axes cannot replay as movement after closing. Keep pointer/head
  /// tracking intact, and re-arm each stick only after its own neutral sample.
  void _gateNavigation(VrInputEvent event) {
    if (event.type != VrInputType.navigate) return;
    final stick = event.data?['stick'];
    if (stick != VrGamepadStick.right && stick != 'right') {
      if (event.active || _movementSource == event.source) {
        _movementWasActive = state.moveX != 0 || state.moveY != 0;
        _movementSource = event.active ? event.source : null;
      }
      if (_movementNeedsNeutral && !_movementWasActive) {
        _movementNeedsNeutral = false;
      }
      if (!_locomotionEnabled || _movementNeedsNeutral) {
        state.moveX = state.moveY = 0;
      }
    }
    if (stick != VrGamepadStick.left && stick != 'left') {
      if (event.active || _lookSource == event.source) {
        _lookWasActive = state.lookX != 0 || state.lookY != 0;
        _lookSource = event.active ? event.source : null;
      }
      if (_lookNeedsNeutral && !_lookWasActive) {
        _lookNeedsNeutral = false;
      }
      if (!_lookInputEnabled || _lookNeedsNeutral) {
        state.lookX = state.lookY = 0;
      }
    }
  }

  void update(double dt) {
    state.update(dt);
    if (!dt.isFinite || dt < 0) {
      reset();
      return;
    }
    if (dt == 0) return;
    // Avoid a large teleport after a paused/resumed frame.
    final step = dt.clamp(0.0, 0.1);
    if (lookInputEnabled && (state.lookX != 0 || state.lookY != 0)) {
      // Yaw is relative in the tracker, so the head rig keeps it. Pitch is
      // absolute (gravity-referenced) there and would erase a stick delta on
      // the next sample; accumulate it as a composed body offset instead.
      rig.rotate(-state.lookX * 1.8 * step, 0);
      rig.bodyPitch =
          (rig.bodyPitch + VrStickLook.pitchDelta(state.lookY, step)).clamp(
            -1.45,
            1.45,
          );
    }
    final movement = _edgeTurn.update(
      stickX: state.moveX,
      stickY: state.moveY,
      atEdge: state.moveAtEdge,
      heading: rig.bodyYaw,
      dt: step,
      enabled: locomotionEnabled && edgeTurnEnabled && state.edgeTurnEnabled,
      // Elevation remains independent of the left stick's target heading.
      // A physical gamepad's right yaw still overrides the assisted turn.
      manualLook: lookInputEnabled && state.lookX.abs() > .015,
    );
    if (!locomotionEnabled) return;
    rig.bodyYaw += movement.yawDelta;
    if (state.moveX == 0 && state.moveY == 0) return;
    state.writeMovement(
      _movement,
      forward: rig.forward,
      screenRight: rig.screenRight,
      dt: step,
      movementX: movement.movementX,
      movementY: movement.movementY,
    );
    rig.eyeCenter.add(_movement);
  }

  void reset() {
    state.reset();
    _edgeTurn.reset();
    _triggerHeld.fillRange(0, _triggerHeld.length, false);
    _buttonBHeld = false;
    _movementNeedsNeutral = _lookNeedsNeutral = false;
    _movementWasActive = _lookWasActive = false;
    _movementSource = _lookSource = null;
  }
}
