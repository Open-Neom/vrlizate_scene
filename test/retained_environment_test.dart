import 'dart:ui' as ui;

import 'package:flutter_scene/scene.dart' as fs;
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;
import 'package:vrlizate/vrlizate.dart' as core;
import 'package:vrlizate_scene/vrlizate_scene.dart';

/// Records ambient and sky requests without a GPU.
class EnvironmentRecorder extends VrRetainedResourceFactory {
  @override
  fs.Scene? createScene() => null;
  /// Models the GPU factory: an install completes only once shaders are
  /// loaded, and `environmentReady` reports the last install's outcome.
  bool shadersReady = true;
  bool _installed = true;
  @override
  bool get environmentReady => _installed;
  int flatUpdates = 0;
  int hemisphereUpdates = 0;
  final List<VrRetainedSkyDome?> skies = [];
  bool acceptSky = true;
  vm.Vector3 sky = vm.Vector3.zero();
  vm.Vector3 ground = vm.Vector3.zero();

  @override
  fs.Geometry? createGeometry(
    core.Geometry geometry, {
    bool wireframe = false,
  }) => null;
  @override
  fs.Material? createMaterial({required bool unlit}) => null;
  @override
  void updateMaterial(fs.Material? target, core.VRMaterial source) {}
  @override
  Future<fs.Mesh?> createSurface(VrRetainedSurface surface) async => null;

  @override
  void setAmbient(fs.Scene? scene, vm.Vector3 radiance) {
    flatUpdates++;
    _installed = shadersReady;
    sky.setFrom(radiance);
    ground.setFrom(radiance);
  }

  @override
  void setHemisphereAmbient(
    fs.Scene? scene,
    vm.Vector3 sky,
    vm.Vector3 ground,
  ) {
    hemisphereUpdates++;
    _installed = shadersReady;
    this.sky.setFrom(sky);
    this.ground.setFrom(ground);
  }

  @override
  bool setSky(fs.Scene? scene, VrRetainedSkyDome? sky) {
    skies.add(sky);
    return acceptSky;
  }
}

/// Evaluates the diffuse SH exactly as flutter_scene's shader does.
vm.Vector3 evaluateSh(List<vm.Vector3> sh, vm.Vector3 n) {
  final basis = <double>[
    0.282095,
    0.488603 * n.y,
    0.488603 * n.z,
    0.488603 * n.x,
    1.092548 * n.x * n.y,
    1.092548 * n.y * n.z,
    0.315392 * (3.0 * n.z * n.z - 1.0),
    1.092548 * n.x * n.z,
    0.546274 * (n.x * n.x - n.y * n.y),
  ];
  final out = vm.Vector3.zero();
  for (var i = 0; i < sh.length; i++) {
    out.addScaled(sh[i], basis[i]);
  }
  return out;
}

void main() {
  group('hemisphere spherical harmonics', () {
    test('evaluate to the sky color upward and the ground color downward', () {
      final sky = vm.Vector3(0.30, 0.40, 0.60);
      final ground = vm.Vector3(0.12, 0.09, 0.06);
      final sh = VrRetainedGpuResources.hemisphereSphericalHarmonics(
        sky,
        ground,
      );
      expect(sh.length, fs.kDiffuseShCoefficientCount);
      final up = evaluateSh(sh, vm.Vector3(0, 1, 0));
      final down = evaluateSh(sh, vm.Vector3(0, -1, 0));
      final side = evaluateSh(sh, vm.Vector3(1, 0, 0));
      for (var i = 0; i < 3; i++) {
        expect(up[i], closeTo(sky[i], 1e-6));
        expect(down[i], closeTo(ground[i], 1e-6));
        // Horizontal normals receive the average: a linear blend in n.y.
        expect(side[i], closeTo((sky[i] + ground[i]) / 2, 1e-6));
      }
      // Only bands 0 and 1 (the Y term) are populated.
      for (var i = 2; i < sh.length; i++) {
        expect(sh[i].length2, 0);
      }
    });

    test('never go negative for a physically plausible pair', () {
      final sh = VrRetainedGpuResources.hemisphereSphericalHarmonics(
        vm.Vector3(0.5, 0.6, 0.9),
        vm.Vector3(0.05, 0.04, 0.03),
      );
      for (final y in [-1.0, -0.5, 0.0, 0.5, 1.0]) {
        final n = vm.Vector3(0.3, y, 0.2)..normalize();
        final e = evaluateSh(sh, n);
        expect(e.x, greaterThanOrEqualTo(0));
        expect(e.y, greaterThanOrEqualTo(0));
        expect(e.z, greaterThanOrEqualTo(0));
      }
    });

    test('collapse to the flat ambient when sky equals ground', () {
      final c = vm.Vector3(0.2, 0.2, 0.2);
      final sh = VrRetainedGpuResources.hemisphereSphericalHarmonics(c, c);
      expect(sh[1].length2, 0);
      expect(evaluateSh(sh, vm.Vector3(0, 1, 0)).x, closeTo(0.2, 1e-6));
      expect(evaluateSh(sh, vm.Vector3(0, -1, 0)).x, closeTo(0.2, 1e-6));
    });
  });

  group('retained adapter environment', () {
    test('flat ambient lights keep the existing setAmbient path', () {
      final source = core.Scene()
        ..add(
          core.Light.ambient(color: const ui.Color(0xFFFFFFFF), intensity: .3),
        );
      final resources = EnvironmentRecorder();
      final adapter = VrRetainedSceneAdapter(
        source: source,
        resources: resources,
      );
      adapter.sync();
      expect(resources.flatUpdates, 1);
      expect(resources.hemisphereUpdates, 0);
      expect(resources.sky.x, closeTo(.3, 1e-6));
      adapter.dispose();
    });

    test('an ambient groundColor switches to hemisphere ambient', () {
      final light = core.Light.ambient(
        color: const ui.Color(0xFFFFFFFF),
        groundColor: const ui.Color(0xFF000000),
        intensity: .4,
      );
      final source = core.Scene()..add(light);
      final resources = EnvironmentRecorder();
      final adapter = VrRetainedSceneAdapter(
        source: source,
        resources: resources,
      );
      adapter.sync();
      expect(resources.hemisphereUpdates, 1);
      expect(resources.flatUpdates, 0);
      expect(resources.sky.x, closeTo(.4, 1e-6));
      expect(resources.ground.x, closeTo(0, 1e-6));
      // Unchanged lights do not re-upload the environment.
      adapter.sync();
      expect(resources.hemisphereUpdates, 1);
      // Changing only the ground color is a real change.
      light.groundColor = const ui.Color(0xFFFFFFFF);
      adapter.sync();
      expect(resources.hemisphereUpdates, 2);
      expect(resources.ground.x, closeTo(.4, 1e-6));
      adapter.dispose();
    });

    test('flat and hemisphere ambient lights sum per hemisphere', () {
      final source = core.Scene()
        ..add(
          core.Light.ambient(color: const ui.Color(0xFFFFFFFF), intensity: .1),
        )
        ..add(
          core.Light.ambient(
            color: const ui.Color(0xFFFFFFFF),
            groundColor: const ui.Color(0xFF000000),
            intensity: .2,
          ),
        );
      final resources = EnvironmentRecorder();
      final adapter = VrRetainedSceneAdapter(
        source: source,
        resources: resources,
      );
      adapter.sync();
      expect(resources.hemisphereUpdates, 1);
      expect(resources.sky.x, closeTo(.3, 1e-6));
      // The flat light contributes to both hemispheres; the hemisphere light
      // contributes nothing below.
      expect(resources.ground.x, closeTo(.1, 1e-6));
      adapter.dispose();
    });

    test('sky dome is opt-in, derived from scene colors and retried', () {
      final source = core.Scene(backgroundColor: const ui.Color(0xFF243B5C));
      final resources = EnvironmentRecorder()..acceptSky = false;
      final adapter = VrRetainedSceneAdapter(
        source: source,
        resources: resources,
      );
      adapter.sync();
      adapter.sync();
      // No dome requested: the sky hook is never called.
      expect(resources.skies, isEmpty);

      source
        ..skyZenithColor = const ui.Color(0xFF0B1730)
        ..skyGroundColor = const ui.Color(0xFF1A1612);
      adapter.sync();
      expect(resources.skies.length, 1);
      final dome = resources.skies.last!;
      // Horizon is the scene background; all channels are linearized.
      expect(dome.horizon.x, lessThan(0x24 / 255));
      expect(dome.horizon.z, greaterThan(dome.horizon.x));
      expect(dome.zenith.z, greaterThan(dome.zenith.x));
      expect(dome.ground.x, greaterThan(dome.ground.z));
      // The factory refused (shaders not ready): the same dome is retried.
      adapter.sync();
      expect(resources.skies.length, 2);
      expect(resources.skies.last, dome);
      resources.acceptSky = true;
      adapter.sync();
      expect(resources.skies.length, 3);
      adapter.sync();
      expect(resources.skies.length, 3, reason: 'applied domes are retained');

      source
        ..skyZenithColor = null
        ..skyGroundColor = null;
      adapter.sync();
      expect(resources.skies.last, isNull);
      adapter.dispose();
    });

    test('a missing zenith or ground falls back to the horizon color', () {
      final source = core.Scene(backgroundColor: const ui.Color(0xFF808080))
        ..skyZenithColor = const ui.Color(0xFF000000);
      final resources = EnvironmentRecorder();
      final adapter = VrRetainedSceneAdapter(
        source: source,
        resources: resources,
      );
      adapter.sync();
      final dome = resources.skies.last!;
      expect(dome.zenith.length2, 0);
      expect(dome.ground, dome.horizon);
      adapter.dispose();
    });
  });

  group('specular environment scale', () {
    test('matches the studio to the ambient level and never mutes metals', () {
      // Studio mean ≈ 0.5: a bright meadow keeps most of it, a dusk temple
      // dims it, a cavern keeps a floor so metals still catch a highlight.
      final meadow = VrRetainedGpuResources.environmentSpecularScale(
        vm.Vector3(0.45, 0.55, 0.7),
        vm.Vector3(0.15, 0.18, 0.12),
        0.5,
      );
      final dusk = VrRetainedGpuResources.environmentSpecularScale(
        vm.Vector3(0.12, 0.16, 0.25),
        vm.Vector3(0.08, 0.06, 0.05),
        0.5,
      );
      final cavern = VrRetainedGpuResources.environmentSpecularScale(
        vm.Vector3(0.02, 0.03, 0.04),
        vm.Vector3(0.02, 0.02, 0.02),
        0.5,
      );
      expect(meadow, closeTo(0.72, 0.05));
      expect(dusk, inInclusiveRange(0.2, 0.35));
      expect(cavern, 0.12);
      expect(
        VrRetainedGpuResources.environmentSpecularScale(
          vm.Vector3(5, 5, 5),
          vm.Vector3(5, 5, 5),
          0.5,
        ),
        1.0,
        reason: 'never brighter than the studio itself',
      );
    });

    test('is safe for degenerate inputs', () {
      expect(
        VrRetainedGpuResources.environmentSpecularScale(
          vm.Vector3(double.nan, 0, 0),
          vm.Vector3.zero(),
          0.5,
        ),
        1.0,
      );
      expect(
        VrRetainedGpuResources.environmentSpecularScale(
          vm.Vector3(0.3, 0.3, 0.3),
          vm.Vector3(0.3, 0.3, 0.3),
          0,
        ),
        1.0,
      );
    });

    test('diffuse SH divided by the scale reproduces the ambient exactly', () {
      final sky = vm.Vector3(0.3, 0.35, 0.5);
      final ground = vm.Vector3(0.2, 0.15, 0.1);
      final k = VrRetainedGpuResources.environmentSpecularScale(
        sky,
        ground,
        0.5,
      );
      final sh = VrRetainedGpuResources.hemisphereSphericalHarmonics(
        sky,
        ground,
      ).map((c) => c / k).toList();
      // The shader multiplies the evaluated SH by environmentIntensity (= k).
      final up = evaluateSh(sh, vm.Vector3(0, 1, 0)) * k;
      final down = evaluateSh(sh, vm.Vector3(0, -1, 0)) * k;
      expect(up.x, closeTo(sky.x, 1e-6));
      expect(up.z, closeTo(sky.z, 1e-6));
      expect(down.x, closeTo(ground.x, 1e-6));
      expect(down.y, closeTo(ground.y, 1e-6));
    });

    test(
      'the adapter retries the ambient install until the factory is ready',
      () {
        final source = core.Scene()
          ..add(
            core.Light.ambient(
              color: const ui.Color(0xFFFFFFFF),
              intensity: .3,
            ),
          );
        final resources = EnvironmentRecorder()..shadersReady = false;
        final adapter = VrRetainedSceneAdapter(
          source: source,
          resources: resources,
        );
        adapter.sync();
        adapter.sync();
        expect(resources.flatUpdates, 2, reason: 'retried while not ready');
        resources.shadersReady = true;
        adapter.sync();
        adapter.sync();
        expect(resources.flatUpdates, 3, reason: 'settles once ready');
        adapter.dispose();
      },
    );
  });
}
