import 'package:flutter/widgets.dart';
import 'package:vrlizate/vrlizate.dart' show VrInputArbiter;

/// Supplies a shared [VrInputArbiter] session to nested VR scenes and widgets.
///
/// When present, [StereoSceneView] attaches its instant trigger/select activations
/// and respects gaze suppression from this arbiter. Demos can also query it to
/// subscribe to physical buttons (A, B, Trigger) and navigation events (Stick/D-pad).
class VrInputSessionScope extends InheritedWidget {
  const VrInputSessionScope({
    super.key,
    required this.arbiter,
    required super.child,
  });

  final VrInputArbiter arbiter;

  static VrInputSessionScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<VrInputSessionScope>();

  static VrInputArbiter? arbiterOf(BuildContext context) =>
      maybeOf(context)?.arbiter;

  @override
  bool updateShouldNotify(VrInputSessionScope oldWidget) =>
      arbiter != oldWidget.arbiter;
}
