import 'package:flutter/widgets.dart';

/// Supplies renderer-independent system navigation to nested VR scenes.
///
/// [StereoSceneView] turns this intent into one real 3D HOME control. The
/// control is placed once when the scene starts and is rendered by both eyes;
/// it is never attached to the viewport or moved with the head afterward.
class VrWorldNavigationScope extends InheritedWidget {
  const VrWorldNavigationScope({
    super.key,
    required this.onHome,
    this.homeLabel = '↖  HOME',
    required super.child,
  });

  final VoidCallback onHome;
  final String homeLabel;

  static VrWorldNavigationScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<VrWorldNavigationScope>();

  @override
  bool updateShouldNotify(VrWorldNavigationScope oldWidget) =>
      onHome != oldWidget.onHome || homeLabel != oldWidget.homeLabel;
}
