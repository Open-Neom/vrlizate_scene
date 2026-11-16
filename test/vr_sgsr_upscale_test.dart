import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vrlizate_scene/vrlizate_scene.dart';

class _StatefulSceneProbe extends StatefulWidget {
  const _StatefulSceneProbe({super.key});

  @override
  State<_StatefulSceneProbe> createState() => _StatefulSceneProbeState();
}

class _StatefulSceneProbeState extends State<_StatefulSceneProbe> {
  static int initCount = 0;

  @override
  void initState() {
    super.initState();
    initCount++;
  }

  @override
  Widget build(BuildContext context) => const SizedBox(width: 240, height: 120);
}

void main() {
  test('VrSgsrUpscaleConfig presets compute exact pixel savings', () {
    expect(VrSgsrUpscaleConfig.disabled.isActive, isFalse);
    expect(VrSgsrUpscaleConfig.disabled.estimatedShadedPixelSavings, 0.0);

    expect(VrSgsrUpscaleConfig.mobileBalanced.isActive, isTrue);
    expect(
      VrSgsrUpscaleConfig.mobileBalanced.shadedPixelFraction,
      closeTo(0.5625, 1e-6),
    );
    expect(
      VrSgsrUpscaleConfig.mobileBalanced.estimatedShadedPixelSavings,
      closeTo(0.4375, 1e-6),
    );
    expect(
      VrSgsrUpscaleConfig.mobilePerformance.estimatedShadedPixelSavings,
      greaterThan(0.54),
    );
  });

  test(
    'VrSgsrUpscaleMath early-exits flat regions, sharpens step edges without overshoot, and isolates stereo eyes',
    () {
      const viewport = Size(2400, 1080);

      // 1. Uniform surface -> early exit, zero deltaY.
      final flat = VrSgsrUpscaleMath.evaluate(
        screenUv: const Offset(0.25, 0.50),
        outputViewportSize: viewport,
        effectiveRenderScale: 0.75,
        sampleFullScreen: (_) => (0.42, 0.50, 0.58),
      );
      expect(flat.edgeTriggered, isFalse);
      expect(flat.deltaY, 0.0);
      expect(flat.r, closeTo(0.42, 1e-6));

      // 2. Softened bilinear step edge -> SGSR1 triggers and stays bounded (no ringing).
      // Simulate a vertical step at eye X = 0.50 blurred over ~2 input texels.
      (double, double, double) blurredStep(Offset fullUv) {
        final eyeX = fullUv.dx < 0.5 ? fullUv.dx * 2.0 : (fullUv.dx - 0.5) * 2.0;
        final t = ((eyeX - 0.497) / 0.006).clamp(0.0, 1.0);
        final v = 0.10 + 0.80 * t;
        return (v, v, v);
      }

      final highSide = VrSgsrUpscaleMath.evaluate(
        screenUv: const Offset(0.2508, 0.50), // eyeX = 0.5016 (bright side of edge)
        outputViewportSize: viewport,
        effectiveRenderScale: 0.75,
        sampleFullScreen: blurredStep,
      );
      expect(highSide.edgeTriggered, isTrue);
      // Anti-ringing guarantee: luminance never overshoots the 0.90 bright plateau
      // or drops below the 0.10 dark plateau.
      expect(highSide.luma, lessThanOrEqualTo(0.90 + 1e-5));
      expect(highSide.luma, greaterThanOrEqualTo(0.10 - 1e-5));
      expect(highSide.edgeDirection.dx.abs(), greaterThan(0.9));

      // 3. Stereo seam isolation: left eye near x = 0.499 never samples right eye (>= 0.5).
      final sampledUvs = <Offset>[];
      VrSgsrUpscaleMath.evaluate(
        screenUv: const Offset(0.4995, 0.50),
        outputViewportSize: viewport,
        effectiveRenderScale: 0.75,
        stereoSplit: true,
        sampleFullScreen: (uv) {
          sampledUvs.add(uv);
          return uv.dx < 0.5 ? (0.15, 0.15, 0.15) : (5.0, 5.0, 5.0);
        },
      );
      expect(sampledUvs, isNotEmpty);
      for (final uv in sampledUvs) {
        expect(uv.dx, lessThan(0.5));
      }

      sampledUvs.clear();
      VrSgsrUpscaleMath.evaluate(
        screenUv: const Offset(0.5005, 0.50),
        outputViewportSize: viewport,
        effectiveRenderScale: 0.75,
        stereoSplit: true,
        sampleFullScreen: (uv) {
          sampledUvs.add(uv);
          return uv.dx < 0.5 ? (5.0, 5.0, 5.0) : (0.20, 0.20, 0.20);
        },
      );
      expect(sampledUvs, isNotEmpty);
      for (final uv in sampledUvs) {
        expect(uv.dx, greaterThan(0.5));
      }

      // 4. HDR highlights > 1.0 are preserved without SDR 1.0 top-clipping.
      final hdr = VrSgsrUpscaleMath.evaluate(
        screenUv: const Offset(0.2501, 0.50),
        outputViewportSize: viewport,
        effectiveRenderScale: 0.75,
        sampleFullScreen: (uv) {
          final eyeX = uv.dx * 2.0;
          final t = ((eyeX - 0.4994) / 0.0012).clamp(0.0, 1.0);
          final v = 0.2 + 2.2 * t;
          return (v, v, v);
        },
      );
      expect(hdr.edgeTriggered, isTrue);
      expect(hdr.r, greaterThan(1.5));
    },
  );

  testWidgets(
    'VrSgsrUpscalePostProcess preserves child element state across config changes',
    (tester) async {
      _StatefulSceneProbeState.initCount = 0;
      final cfgNotifier = ValueNotifier<VrSgsrUpscaleConfig?>(
        VrSgsrUpscaleConfig.disabled,
      );
      addTearDown(cfgNotifier.dispose);

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: ValueListenableBuilder<VrSgsrUpscaleConfig?>(
            valueListenable: cfgNotifier,
            builder: (_, cfg, _) => VrSgsrUpscalePostProcess(
              config: cfg,
              effectiveRenderScale: cfg?.internalRenderScale ?? 1.0,
              stereoSplit: true,
              child: const _StatefulSceneProbe(key: ValueKey('sgsr_probe')),
            ),
          ),
        ),
      );
      expect(_StatefulSceneProbeState.initCount, 1);

      cfgNotifier.value = VrSgsrUpscaleConfig.mobileBalanced;
      await tester.pump();
      expect(_StatefulSceneProbeState.initCount, 1);

      cfgNotifier.value = VrSgsrUpscaleConfig.mobilePerformance;
      await tester.pump();
      expect(_StatefulSceneProbeState.initCount, 1);

      cfgNotifier.value = null;
      await tester.pump();
      expect(_StatefulSceneProbeState.initCount, 1);
    },
  );
}
