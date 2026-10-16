import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vrlizate_scene/src/vr_stereo_scene_layers.dart';

void main() {
  testWidgets(
    'fullscreen and independent overlay changes retain the viewport',
    (tester) async {
      var mounts = 0;
      var disposals = 0;
      Widget host({required bool feedback, required bool reticle}) =>
          Directionality(
            textDirection: TextDirection.ltr,
            child: VrStereoSceneLayers(
              scene: GestureDetector(
                // A fresh unkeyed viewport widget on every host rebuild mirrors
                // StereoSceneView.build; its State must nevertheless survive.
                child: _ViewportProbe(
                  onMount: () => mounts++,
                  onDispose: () => disposals++,
                ),
              ),
              controllerFeedback: feedback ? const Text('feedback') : null,
              reticle: reticle ? const Text('reticle') : null,
            ),
          );

      await tester.pumpWidget(host(feedback: true, reticle: true));
      final viewportState = tester.state(find.byType(_ViewportProbe));
      for (final overlays in [
        (false, false),
        (true, false),
        (false, true),
        (true, true),
        (false, false),
        (true, true),
      ]) {
        await tester.pumpWidget(
          host(feedback: overlays.$1, reticle: overlays.$2),
        );
        expect(tester.state(find.byType(_ViewportProbe)), same(viewportState));
        expect(mounts, 1);
        expect(disposals, 0);
        expect(
          find.text('feedback'),
          overlays.$1 ? findsOneWidget : findsNothing,
        );
        expect(
          find.text('reticle'),
          overlays.$2 ? findsOneWidget : findsNothing,
        );
      }
      await tester.pumpWidget(const SizedBox.shrink());
      expect(disposals, 1);
    },
  );
}

class _ViewportProbe extends StatefulWidget {
  const _ViewportProbe({required this.onMount, required this.onDispose});
  final VoidCallback onMount, onDispose;

  @override
  State<_ViewportProbe> createState() => _ViewportProbeState();
}

class _ViewportProbeState extends State<_ViewportProbe> {
  @override
  void initState() {
    super.initState();
    widget.onMount();
  }

  @override
  void dispose() {
    widget.onDispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}
