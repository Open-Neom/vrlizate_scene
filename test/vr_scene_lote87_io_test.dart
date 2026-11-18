import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;
import 'package:vrlizate_scene/src/assets/vr_glb_template_cache.dart';
import 'package:vrlizate_scene/src/quality_preset.dart';
import 'package:vrlizate_scene/src/vr_look.dart';

void main() {
  group('Lote 87 vrlizate_scene VM/GPU Hardening', () {
    test(
      'VrGlbTemplateCache rejects leading/trailing spaces, dot/empty segments, and percent-encoded traversal',
      () async {
        var calls = 0;
        final cache = VrGlbTemplateCache(
          loader: (_, {maxTextureSize}) async {
            calls++;
            return Node();
          },
        );
        addTearDown(cache.dispose);

        await expectLater(
          cache.instantiate(' assets/avatar.glb'),
          throwsArgumentError,
        );
        await expectLater(
          cache.instantiate('assets/avatar.glb '),
          throwsArgumentError,
        );
        await expectLater(
          cache.instantiate('assets/./avatar.glb'),
          throwsArgumentError,
        );
        await expectLater(
          cache.instantiate('assets//avatar.glb'),
          throwsArgumentError,
        );
        await expectLater(
          cache.instantiate('assets/%2e%2e/secret.glb'),
          throwsArgumentError,
        );
        await expectLater(
          cache.instantiate('assets%2favatar.glb'),
          throwsArgumentError,
        );
        await expectLater(
          cache.instantiate('assets%5cavatar.glb'),
          throwsArgumentError,
        );
        expect(calls, 0);
      },
    );

    test(
      'VrLook.applyTo sanitizes NaN/Infinity/negative exposure, grading, bloom, vignette, and fog',
      () {
        final s = EnvironmentSettings();
        final poisoned = VrLook(
          exposure: double.nan,
          saturation: double.infinity,
          contrast: -2.0,
          bloomIntensity: double.nan,
          bloomThreshold: double.negativeInfinity,
          vignetteIntensity: double.infinity,
          fogColor: vm.Vector3(double.nan, 0.1, 0.2),
          fogVisibilityMeters: double.infinity,
        );

        poisoned.applyTo(s, VrQualityPreset.ultra);
        expect(s.exposure, 1.0);
        expect(s.colorGradingEnabled, isFalse);
        expect(s.bloomEnabled, isFalse);
        expect(s.vignetteEnabled, isFalse);
        expect(s.fogEnabled, isFalse);
      },
    );
  });
}
