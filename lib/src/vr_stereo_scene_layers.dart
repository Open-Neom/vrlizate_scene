import 'package:flutter/widgets.dart';

/// Keeps the viewport at one stable element-tree position when overlays change.
/// Reparenting a SceneView can recreate captured widgets/native video players.
class VrStereoSceneLayers extends StatelessWidget {
  const VrStereoSceneLayers({
    super.key,
    required this.scene,
    this.controllerFeedback,
    this.reticle,
  });

  final Widget scene;
  final Widget? controllerFeedback, reticle;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      scene,
      if (controllerFeedback case final overlay?) overlay,
      if (reticle case final overlay?) overlay,
    ],
  );
}
