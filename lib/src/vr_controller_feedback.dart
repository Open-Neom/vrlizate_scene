import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Read-only telemetry for the controller shown inside an eye view.
///
/// This is not a measured controller position and does not generate VR input.
/// Axis values conventionally range from -1 to 1; pedals range from 0 to 1.
@immutable
class VrControllerFeedbackState {
  const VrControllerFeedbackState({
    this.connected = false,
    this.visible = true,
    this.btnA = false,
    this.btnB = false,
    this.btnX = false,
    this.btnY = false,
    this.btnL = false,
    this.btnR = false,
    this.grip = false,
    this.moveX = 0,
    this.moveY = 0,
    this.lookX = 0,
    this.lookY = 0,
    this.laserX = 0,
    this.laserY = 0,
    this.driving = false,
    this.steering = 0,
    this.throttle = 0,
    this.brake = 0,
    this.actions = const {},
  });

  final bool connected, visible, btnA, btnB, btnX, btnY, btnL, btnR, grip;
  final double moveX, moveY, lookX, lookY, laserX, laserY;
  final bool driving;
  final double steering, throttle, brake;

  /// What each button does in the active experience, keyed by the button's
  /// printed name (`A`, `B`, `X`, `Y`, `L`, `R`, `GRIP`). Drawn as a caption
  /// under the key so a viewer glancing down at the controller sees, for
  /// example, `X · Cambiar arma` instead of a bare letter. Values longer than
  /// [maxActionLength] are truncated when drawn. Static per experience: the
  /// label atlas is re-rasterized only when this map changes.
  final Map<String, String> actions;

  /// Longest caption the atlas can fit under a key without overlapping.
  static const int maxActionLength = 14;

  bool get shown => connected && visible;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VrControllerFeedbackState &&
          connected == other.connected &&
          visible == other.visible &&
          btnA == other.btnA &&
          btnB == other.btnB &&
          btnX == other.btnX &&
          btnY == other.btnY &&
          btnL == other.btnL &&
          btnR == other.btnR &&
          grip == other.grip &&
          moveX == other.moveX &&
          moveY == other.moveY &&
          lookX == other.lookX &&
          lookY == other.lookY &&
          laserX == other.laserX &&
          laserY == other.laserY &&
          driving == other.driving &&
          steering == other.steering &&
          throttle == other.throttle &&
          brake == other.brake &&
          mapEquals(actions, other.actions);

  @override
  int get hashCode => Object.hash(
    connected,
    visible,
    btnA,
    btnB,
    btnX,
    btnY,
    btnL,
    btnR,
    grip,
    moveX,
    moveY,
    lookX,
    lookY,
    laserX,
    laserY,
    driving,
    steering,
    throttle,
    brake,
    Object.hashAllUnordered(
      actions.entries.map((e) => Object.hash(e.key, e.value)),
    ),
  );
}

/// Supplies telemetry to every nested StereoSceneView without rebuilding the
/// app or rasterizing text for each input packet. The caller owns [state].
class VrControllerFeedbackScope extends InheritedWidget {
  const VrControllerFeedbackScope({
    super.key,
    required this.state,
    required super.child,
  });

  final ValueListenable<VrControllerFeedbackState> state;

  static VrControllerFeedbackScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<VrControllerFeedbackScope>();

  @override
  bool updateShouldNotify(VrControllerFeedbackScope oldWidget) =>
      !identical(state, oldWidget.state);
}
