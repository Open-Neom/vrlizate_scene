import 'dart:ui' show Offset, Rect, Size;

import 'package:flutter_scene/scene.dart'
    show Camera, PerspectiveProjection, RenderTexture, RenderView;
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;
import 'package:vrlizate_scene/vrlizate_scene.dart';

void main() {
  group('VrFixedFoveation', () {
    const foveation = VrFixedFoveation();
    const viewportSize = Size(2400, 1080);

    test('defaults reduce color pixels while retaining native center', () {
      expect(foveation.centerFraction, 0.6);
      expect(foveation.peripheralScale, 0.6);
      expect(foveation.estimatedColorPixelRatio, closeTo(0.72, 1e-12));
      expect(
        const VrFixedFoveation(
          centerFraction: 0.5,
          peripheralScale: 0.5,
        ).estimatedColorPixelRatio,
        closeTo(0.5, 1e-12),
      );
    });

    test('each eye has a low resolution background and native crop', () {
      final eyes = StereoHeadRig().buildStereoViews();
      final views = foveation.buildViews(eyes, viewportSize: viewportSize);
      expect(views, hasLength(4));
      final backgrounds = <RenderView>[];
      final centers = <RenderView>[];
      for (final eye in eyes) {
        final pair = _viewsForEye(views, eye);
        expect(pair, hasLength(2));
        final background = pair.singleWhere((v) => v.viewport == eye.viewport);
        final center = pair.singleWhere((v) => v.viewport != eye.viewport);
        backgrounds.add(background);
        centers.add(center);
        expect(background.renderScale, 0.6);
        expect(center.renderScale, 1.0);
        expect(
          center.viewport!.width / eye.viewport!.width,
          closeTo(0.6, 1e-9),
        );
        expect(
          center.viewport!.height / eye.viewport!.height,
          closeTo(0.6, 1e-9),
        );
        expect(eye.viewport!.contains(center.viewport!.topLeft), isTrue);
        expect(eye.viewport!.contains(center.viewport!.bottomRight), isTrue);
        expect(background.target, isNull);
        expect(center.target, isNull);
      }
      for (final center in centers) {
        for (final background in backgrounds) {
          expect(center.order, greaterThan(background.order));
        }
      }
    });

    test(
      'both eyes preserve screen position across optics, pose and aspect',
      () {
        final rig = StereoHeadRig(eyeCenter: vm.Vector3(2, 1.6, -4), ipd: 0.07);
        for (final size in [
          const Size(2400, 1080),
          const Size(1365, 721),
          const Size(800, 1200),
        ]) {
          for (final inset in [0.0, 0.1, 0.3]) {
            rig.stereoImageInset = inset;
            for (final convergence in <double?>[null, 1.8, 5.0]) {
              rig.convergenceDistance = convergence;
              for (final yaw in [0.0, 0.7]) {
                rig.setOrientation(yaw, -0.23);
                rig.bodyYaw = -yaw / 2;
                rig.bodyPitch = 0.08;
                final eyes = rig.buildStereoViews(fovRadiansY: 1.1);
                final views = foveation.buildViews(eyes, viewportSize: size);
                for (final eye in eyes) {
                  final area = _viewArea(eye, size);
                  for (final uv in [
                    const Offset(0.2, 0.25),
                    const Offset(0.5, 0.5),
                    const Offset(0.7, 0.75),
                  ]) {
                    final local = Offset(
                      uv.dx * area.width,
                      uv.dy * area.height,
                    );
                    final ray = eye.camera.screenPointToRay(local, area.size);
                    for (final distance in [0.5, 2.0, 30.0]) {
                      final world =
                          ray.origin + ray.direction.normalized() * distance;
                      final expected = _screenPosition(eye, world, size);
                      for (final view in _viewsForEye(views, eye)) {
                        _expectOffsetClose(
                          _screenPosition(view, world, size),
                          expected,
                        );
                      }
                    }
                  }
                }
              }
            }
          }
        }
      },
    );

    test(
      'rounded render targets do not shift the center relative to periphery',
      () {
        const size = Size(933.25, 411.75);
        final rig = StereoHeadRig(stereoImageInset: 0.17)
          ..setOrientation(0.4, 0.2);
        final eyes = rig.buildStereoViews();
        final views = foveation.buildViews(eyes, viewportSize: size);
        final world = rig.eyeCenter + rig.forward * 3 + rig.screenRight * 0.1;
        for (final eye in eyes) {
          final expected = _screenPosition(eye, world, size);
          for (final view in _viewsForEye(views, eye)) {
            for (final pixelRatio in [1.0, 1.575, 2.625, 3.0]) {
              _expectOffsetClose(
                _screenPosition(view, world, size, pixelRatio: pixelRatio),
                expected,
              );
            }
          }
        }
      },
    );

    test('optical centers shift the crop without changing its projection', () {
      final rig = StereoHeadRig(stereoImageInset: 0.2);
      final eyes = rig.buildStereoViews();
      const centers = [Offset(0.6, 0.5), Offset(0.4, 0.5)];
      final views = foveation.buildViews(
        eyes,
        viewportSize: viewportSize,
        centers: centers,
      );
      for (var i = 0; i < eyes.length; i++) {
        final eye = eyes[i];
        final center = _viewsForEye(
          views,
          eye,
        ).singleWhere((view) => view.viewport != eye.viewport);
        final expectedCenter = Offset(
          eye.viewport!.left + eye.viewport!.width * centers[i].dx,
          eye.viewport!.top + eye.viewport!.height * centers[i].dy,
        );
        _expectOffsetClose(center.viewport!.center, expectedCenter);
        _expectOffsetClose(
          _screenPosition(center, rig.convergencePoint!, viewportSize),
          _screenPosition(eye, rig.convergencePoint!, viewportSize),
        );
      }
    });

    test('extreme crop centers stay within their own eye', () {
      final eyes = StereoHeadRig().buildStereoViews();
      final views = foveation.buildViews(
        eyes,
        viewportSize: viewportSize,
        centers: const [Offset.zero, Offset(1, 1)],
      );
      for (final eye in eyes) {
        final center = _viewsForEye(
          views,
          eye,
        ).singleWhere((view) => view.viewport != eye.viewport);
        expect(center.viewport!.left, greaterThanOrEqualTo(eye.viewport!.left));
        expect(center.viewport!.top, greaterThanOrEqualTo(eye.viewport!.top));
        expect(center.viewport!.right, lessThanOrEqualTo(eye.viewport!.right));
        expect(
          center.viewport!.bottom,
          lessThanOrEqualTo(eye.viewport!.bottom),
        );
      }
    });

    test('peripheral density composes with inherited and per-eye scales', () {
      final eyes = StereoHeadRig().buildStereoViews();
      eyes[1].renderScale = 0.9;
      final views = foveation.buildViews(
        eyes,
        viewportSize: viewportSize,
        inheritedRenderScale: 0.8,
      );
      for (var i = 0; i < eyes.length; i++) {
        final eye = eyes[i];
        final scale = i == 0 ? 0.8 : 0.9;
        final pair = _viewsForEye(views, eye);
        expect(
          pair.singleWhere((view) => view.viewport == eye.viewport).renderScale,
          closeTo(scale * 0.6, 1e-12),
        );
        expect(
          pair.singleWhere((view) => view.viewport != eye.viewport).renderScale,
          scale,
        );
      }
      expect(eyes[0].renderScale, isNull);
      expect(eyes[1].renderScale, 0.9);
    });

    test(
      'cropped projection retains full-eye shadow metadata and camera pose',
      () {
        final rig = StereoHeadRig()..setOrientation(0.6, -0.3);
        final eyes = rig.buildStereoViews(fovRadiansY: 1.2);
        final views = foveation.buildViews(eyes, viewportSize: viewportSize);
        for (final eye in eyes) {
          final baseProjection = eye.camera.projection as PerspectiveProjection;
          for (final view in _viewsForEye(views, eye)) {
            expect(view.camera.projection, isA<PerspectiveProjection>());
            final projection = view.camera.projection as PerspectiveProjection;
            expect(projection.fovRadiansY, baseProjection.fovRadiansY);
            expect(projection.near, baseProjection.near);
            expect(projection.far, baseProjection.far);
            expect(
              view.camera.position.distanceTo(eye.camera.position),
              lessThan(1e-9),
            );
            expect(
              view.camera.forward.distanceTo(eye.camera.forward),
              lessThan(1e-9),
            );
            expect(view.camera.up.distanceTo(eye.camera.up), lessThan(1e-9));
            expect(
              view.camera.getViewMatrix().storage,
              orderedEquals(eye.camera.getViewMatrix().storage),
            );
          }
        }
      },
    );

    test('rays through a cropped pixel coincide with the original eye ray', () {
      final rig = StereoHeadRig(stereoImageInset: 0.2, convergenceDistance: 3.0)
        ..setOrientation(-0.7, 0.3);
      final eyes = rig.buildStereoViews();
      final views = foveation.buildViews(eyes, viewportSize: viewportSize);
      for (final eye in eyes) {
        final originalArea = _viewArea(eye, viewportSize);
        final center = _viewsForEye(
          views,
          eye,
        ).singleWhere((view) => view.viewport != eye.viewport);
        final centerArea = _viewArea(center, viewportSize);
        for (final uv in [
          const Offset(0.1, 0.2),
          const Offset(0.5, 0.5),
          const Offset(0.9, 0.8),
        ]) {
          final local = Offset(
            uv.dx * centerArea.width,
            uv.dy * centerArea.height,
          );
          final originalLocal =
              local + centerArea.topLeft - originalArea.topLeft;
          final expected = eye.camera.screenPointToRay(
            originalLocal,
            originalArea.size,
          );
          final actual = center.camera.screenPointToRay(local, centerArea.size);
          expect(actual.origin.distanceTo(expected.origin), lessThan(1e-6));
          expect(
            actual.direction.normalized().distanceTo(
              expected.direction.normalized(),
            ),
            lessThan(1e-6),
          );
        }
      }
    });

    test(
      'building foveated views does not mutate the supplied stereo views',
      () {
        final eyes = StereoHeadRig().buildStereoViews();
        final cameras = eyes.map((view) => view.camera).toList();
        final viewports = eyes.map((view) => view.viewport).toList();
        final matrices = eyes
            .map(
              (view) =>
                  view.camera.getViewTransform(const Size(1200, 1080)).clone(),
            )
            .toList();
        eyes[0].layerMask = 5;
        eyes[1].layerMask = 9;
        final views = foveation.buildViews(eyes, viewportSize: viewportSize);
        expect(eyes, hasLength(2));
        for (var i = 0; i < eyes.length; i++) {
          expect(eyes[i].camera, same(cameras[i]));
          expect(eyes[i].viewport, viewports[i]);
          expect(eyes[i].renderScale, isNull);
          expect(eyes[i].order, 0);
          expect(
            eyes[i].camera.getViewTransform(const Size(1200, 1080)).storage,
            orderedEquals(matrices[i].storage),
          );
          for (final view in _viewsForEye(views, eyes[i])) {
            expect(view, isNot(same(eyes[i])));
            expect(view.layerMask, eyes[i].layerMask);
          }
        }
      },
    );

    test('rejects invalid center fractions at runtime', () {
      for (final value in [0.0, -0.1, 1.1, double.nan, double.infinity]) {
        expect(
          () => VrFixedFoveation(centerFraction: value).buildViews(
            StereoHeadRig().buildStereoViews(),
            viewportSize: viewportSize,
          ),
          throwsArgumentError,
          reason: 'centerFraction=$value',
        );
      }
    });

    test('rejects invalid peripheral scales at runtime', () {
      for (final value in [0.0, -0.1, 1.1, double.nan, double.infinity]) {
        expect(
          () => VrFixedFoveation(peripheralScale: value).buildViews(
            StereoHeadRig().buildStereoViews(),
            viewportSize: viewportSize,
          ),
          throwsArgumentError,
          reason: 'peripheralScale=$value',
        );
      }
    });

    test('rejects texture-target views without touching GPU resources', () {
      final eyes = StereoHeadRig().buildStereoViews();
      eyes[0].target = _UnusedRenderTexture();
      expect(
        () => foveation.buildViews(eyes, viewportSize: viewportSize),
        throwsArgumentError,
      );
    });

    test('rejects malformed center lists and non-finite centers', () {
      for (final centers in <List<Offset>>[
        [],
        [Offset.zero],
        [const Offset(double.nan, 0.5), const Offset(0.5, 0.5)],
        [const Offset(0.5, double.infinity), const Offset(0.5, 0.5)],
        [const Offset(-0.1, 0.5), const Offset(0.5, 0.5)],
        [const Offset(0.5, 0.5), const Offset(1.1, 0.5)],
      ]) {
        expect(
          () => foveation.buildViews(
            StereoHeadRig().buildStereoViews(),
            viewportSize: viewportSize,
            centers: centers,
          ),
          throwsArgumentError,
        );
      }
    });

    test('rejects zero, negative and non-finite viewport dimensions', () {
      for (final size in [
        Size.zero,
        const Size(-1, 1080),
        const Size(1920, -1),
        const Size(double.infinity, 1080),
        const Size(1920, double.infinity),
        const Size(double.nan, 1080),
        const Size(1920, double.nan),
      ]) {
        expect(
          () => foveation.buildViews(
            StereoHeadRig().buildStereoViews(),
            viewportSize: size,
          ),
          throwsArgumentError,
          reason: 'viewportSize=$size',
        );
      }
    });
  });
}

List<RenderView> _viewsForEye(List<RenderView> views, RenderView eye) => [
  for (final view in views)
    if (view.camera.position.distanceTo(eye.camera.position) < 1e-9) view,
];

Rect _viewArea(RenderView view, Size size) {
  final viewport = view.viewport ?? const Rect.fromLTWH(0, 0, 1, 1);
  return Rect.fromLTWH(
    viewport.left * size.width,
    viewport.top * size.height,
    viewport.width * size.width,
    viewport.height * size.height,
  );
}

Offset _screenPosition(
  RenderView view,
  vm.Vector3 world,
  Size size, {
  double? pixelRatio,
}) {
  final area = _viewArea(view, size);
  final Camera camera = view.camera;
  if (pixelRatio == null) {
    return camera.worldToScreen(world, area.size)! + area.topLeft;
  }
  // Match flutter_scene's real ceil-rounded physical render-target dimensions.
  final scale = pixelRatio * (view.renderScale ?? 1.0);
  final rasterSize = Size(
    (area.width * scale).ceilToDouble(),
    (area.height * scale).ceilToDouble(),
  );
  final pixel = camera.worldToScreen(world, rasterSize)!;
  return Offset(
    area.left + pixel.dx * area.width / rasterSize.width,
    area.top + pixel.dy * area.height / rasterSize.height,
  );
}

void _expectOffsetClose(Offset actual, Offset expected) {
  // Matrix storage/arithmetic can round at float precision. A thousandth of
  // a logical pixel admits that roundoff while catching visible misalignment.
  expect(actual.dx, closeTo(expected.dx, 1e-3));
  expect(actual.dy, closeTo(expected.dy, 1e-3));
}

// Validating screen-only views must reject the target before accessing it.
// This fake avoids allocating any native/GPU render textures in a unit test.
class _UnusedRenderTexture implements RenderTexture {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError(
    'Texture resources must not be accessed during validation',
  );
}
