import 'package:flutter_test/flutter_test.dart';
import 'package:vrlizate_scene/src/quality_preset.dart';
import 'package:vrlizate_scene/src/vr_frame_quality.dart';
import 'package:vrlizate_scene/src/vr_thermal_governor.dart';

void main() {
  group('Lote 87 vrlizate_scene Web-Safe Hardening', () {
    test(
      'VrThermalGovernor ignores NaN/Infinity/non-positive dt without poisoning _secondsSinceLastCheck and dispose is idempotent',
      () async {
        final gov = VrThermalGovernor(
          initialPreset: VrQualityPreset.high,
          targetFps: double.nan,
          stepDownThresholdFps: double.infinity,
          stepUpThresholdFps: -10.0,
        );
        expect(gov.targetFps, 60.0);
        expect(gov.stepDownThresholdFps, 54.0);
        expect(gov.stepUpThresholdFps, 58.5);

        // Inject NaN and Infinity deltas: previously poisoned _secondsSinceLastCheck forever!
        gov.recordFrame(double.nan);
        gov.recordFrame(double.infinity);
        gov.recordFrame(double.negativeInfinity);
        gov.recordFrame(0.0);
        gov.recordFrame(-0.016);

        // Now record sustained 30 FPS (0.0333s) over > 6s (2 evaluation windows of 3s)
        for (var i = 0; i < 200; i++) {
          gov.recordFrame(1.0 / 30.0);
        }
        expect(gov.currentPreset, VrQualityPreset.medium);

        // Idempotent dispose + safe recordFrame after dispose
        gov.dispose();
        gov.dispose();
        final afterDispose = gov.recordFrame(1.0 / 25.0);
        expect(afterDispose, isA<VrQualityPreset>());
      },
    );

    test(
      'VrFrameQualityPolicy rejects non-finite JS counts and clamps non-finite FrameTiming values',
      () {
        if (identical(0, 0.0)) {
          final jsInf = (double.infinity as dynamic) as int;
          expect(
            () => VrFrameQualityPolicy(warmupFrames: jsInf),
            throwsArgumentError,
          );
          final pJs = VrFrameQualityPolicy(
            warmupFrames: 0,
            windowFrames: 1,
            requiredSlowWindows: 1,
          );
          expect(
            pJs.record(buildMicroseconds: jsInf, rasterMicroseconds: jsInf),
            isFalse,
          );
        }
        final policy = VrFrameQualityPolicy(
          warmupFrames: 0,
          windowFrames: 2,
          requiredSlowWindows: 1,
        );
        expect(
          policy.record(buildMicroseconds: 5000, rasterMicroseconds: 5000),
          isFalse,
        );
      },
    );
  });
}
