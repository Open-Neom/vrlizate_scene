import 'package:flutter_test/flutter_test.dart';
import 'package:vrlizate_scene/vrlizate_scene.dart';

void main() {
  group('VrLightingPreset', () {
    test('exposes distinct lighting parameters and resolves by id', () {
      for (final preset in VrLightingPreset.values) {
        expect(preset.id, isNotEmpty);
        expect(preset.ambientIntensity, greaterThan(0.0));
        expect(preset.directionalIntensity, greaterThan(0.0));
        expect(VrLightingPreset.fromId(preset.id), preset);
        expect(VrLightingPreset.fromId(preset.name), preset);
      }

      expect(
        VrLightingPreset.neonArcade.directionalColorArgb,
        VrSceneConstants.neonArcadeDirectionalArgb,
      );
      expect(
        VrLightingPreset.fromId('unknown_preset'),
        VrLightingPreset.daylight,
      );
    });
  });

  group('VrSceneTransitionStyle & VrSceneTransitionController', () {
    test('instant transition completes immediately with zero FOV warp', () {
      final controller = VrSceneTransitionController(
        style: VrSceneTransitionStyle.instant,
      );

      controller.beginEnter(targetId: 'portal_arcade');
      expect(controller.progress, 1.0);
      expect(controller.isTransitioning, isFalse);
      expect(controller.fadeOpacity, 1.0);
      expect(controller.fovWarpDegrees, 0.0);
      expect(controller.effectiveFovDegrees, VrSceneConstants.defaultBaseFovDegrees);
    });

    test('smoothFade and portalIris interpolate progress, opacity, and FOV warp', () {
      final controller = VrSceneTransitionController(
        style: VrSceneTransitionStyle.portalIris,
        durationMs: 400,
        baseFovDegrees: 90.0,
      );

      controller.beginEnter(targetId: 'gallery_room');
      expect(controller.isTransitioning, isTrue);
      expect(controller.isEntering, isTrue);
      expect(controller.targetId, 'gallery_room');
      expect(controller.progress, 0.0);
      expect(controller.irisAperture, 1.0);

      controller.advanceMs(200);
      expect(controller.progress, closeTo(0.5, 1e-6));
      expect(controller.fadeOpacity, closeTo(0.5, 1e-6));
      expect(controller.fovWarpDegrees, closeTo(-9.0, 1e-6));
      expect(controller.effectiveFovDegrees, closeTo(81.0, 1e-6));
      expect(controller.irisAperture, closeTo(0.5, 1e-6));

      controller.advanceMs(200);
      expect(controller.progress, 1.0);
      expect(controller.isTransitioning, isFalse);
      expect(controller.fadeOpacity, 1.0);
      expect(controller.irisAperture, 0.0);

      controller.beginExit(style: VrSceneTransitionStyle.zoomSlide);
      expect(controller.isEntering, isFalse);
      expect(controller.isTransitioning, isTrue);
      controller.update(const Duration(milliseconds: 200));
      expect(controller.fovWarpDegrees, greaterThan(0.0));

      controller.reset();
      expect(controller.progress, 0.0);
      expect(controller.isTransitioning, isFalse);
      expect(controller.targetId, isNull);
    });
  });
}
