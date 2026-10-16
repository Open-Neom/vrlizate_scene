import 'dart:ui' as ui;

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// Experimental fixed spatial foveation using ordinary Flutter Scene views.
///
/// Every frame draws a low-resolution full eye and a cropped sharp center.
/// Pass all returned views to ONE SceneView/renderViews call: simulation,
/// tracking and both resolution zones then use the same frame. This is not
/// hardware VRS, temporal reuse, an eye tracker or a post-process blur.
///
/// The default color-target area is 0.6² + 0.6² = 72% of uniform rendering.
/// Geometry, shadows and compositing have additional per-view costs; fewer
/// color pixels do not guarantee a faster frame or lower power consumption.
///
/// Cropped passes must not use viewport-local effects such as vignette,
/// lens distortion, bloom, AO, SSR or depth of field. Those effects need a
/// crop-aware compositor. The initial trial uses plain tonemapping/fog and
/// offers an immediate uniform-rendering comparison.
class VrFixedFoveation {
  const VrFixedFoveation({
    this.centerFraction = 0.6,
    this.peripheralScale = 0.6,
  });

  /// Fraction of each eye's width AND height retaining its original density.
  /// Keeping the same fraction on both axes preserves the full-eye aspect.
  final double centerFraction;

  /// Linear render scale of the full-eye background, relative to its current
  /// quality preset. 0.6 draws 36% of the uniform eye's color-target pixels.
  final double peripheralScale;

  /// Nominal color-pixel ratio, including overlap underneath the sharp center.
  /// Excludes integer target rounding, MSAA samples and every other pass.
  double get estimatedColorPixelRatio =>
      peripheralScale * peripheralScale + centerFraction * centerFraction;

  /// Builds background views followed by sharp, projection-matched crops.
  ///
  /// [viewportSize] is the complete logical SceneView size. Locking projection
  /// to that size prevents target-resolution rounding from shifting the two
  /// images. [centers] are normalized within each eye (default 0.5, 0.5);
  /// StereoSceneView supplies its inset-adjusted optical centers.
  /// Input views and cameras are never mutated. Texture-target views are not
  /// supported. A square normalized crop keeps the perspective metadata used
  /// by the renderer's shadow fitting consistent with the full-eye pass.
  List<RenderView> buildViews(
    List<RenderView> eyes, {
    required ui.Size viewportSize,
    List<ui.Offset>? centers,
    double inheritedRenderScale = 1,
  }) {
    _unitScale(centerFraction, 'centerFraction');
    _unitScale(peripheralScale, 'peripheralScale');
    if (!viewportSize.width.isFinite ||
        !viewportSize.height.isFinite ||
        viewportSize.isEmpty) {
      throw ArgumentError.value(viewportSize, 'viewportSize');
    }
    if (!inheritedRenderScale.isFinite || inheritedRenderScale <= 0) {
      throw ArgumentError.value(inheritedRenderScale, 'inheritedRenderScale');
    }
    if (centers != null && centers.length != eyes.length) {
      throw ArgumentError('centers must match the number of eye views');
    }
    final backgrounds = <RenderView>[];
    final sharp = <RenderView>[];
    for (var i = 0; i < eyes.length; i++) {
      final eye = eyes[i];
      if (eye.target != null) {
        throw ArgumentError('Fixed foveation requires screen-target views');
      }
      final viewport = eye.viewport ?? const ui.Rect.fromLTWH(0, 0, 1, 1);
      if (!_validViewport(viewport)) {
        throw ArgumentError.value(viewport, 'eye.viewport');
      }
      final perspective = eye.camera.projection;
      if (perspective is! PerspectiveProjection) {
        throw ArgumentError('Fixed foveation requires perspective cameras');
      }
      final center = centers?[i] ?? const ui.Offset(0.5, 0.5);
      if (!center.dx.isFinite ||
          !center.dy.isFinite ||
          center.dx < 0 ||
          center.dx > 1 ||
          center.dy < 0 ||
          center.dy > 1) {
        throw ArgumentError.value(center, 'centers');
      }
      final half = centerFraction / 2;
      final crop = ui.Rect.fromLTWH(
        (center.dx - half).clamp(0.0, 1 - centerFraction),
        (center.dy - half).clamp(0.0, 1 - centerFraction),
        centerFraction,
        centerFraction,
      );
      final aspect =
          viewportSize.width *
          viewport.width /
          (viewportSize.height * viewport.height);
      final scale = eye.renderScale ?? inheritedRenderScale;
      if (!scale.isFinite || scale <= 0) {
        throw ArgumentError.value(scale, 'eye.renderScale');
      }
      RenderView makeView(
        ui.Rect cameraCrop,
        ui.Rect area,
        double scale,
        int order,
      ) => RenderView(
        camera: _CroppedEyeCamera(eye.camera, perspective, aspect, cameraCrop),
        viewport: area,
        renderScale: scale,
        order: order,
        filterQuality: ui.FilterQuality.low,
        antiAliasingMode: eye.antiAliasingMode,
        layerMask: eye.layerMask,
        cullingPlanes: List.of(eye.cullingPlanes),
      );
      backgrounds.add(
        makeView(
          const ui.Rect.fromLTWH(0, 0, 1, 1),
          viewport,
          scale * peripheralScale,
          i,
        ),
      );
      sharp.add(
        makeView(
          crop,
          ui.Rect.fromLTWH(
            viewport.left + viewport.width * crop.left,
            viewport.top + viewport.height * crop.top,
            viewport.width * crop.width,
            viewport.height * crop.height,
          ),
          scale,
          eyes.length + i,
        ),
      );
    }
    return [...backgrounds, ...sharp];
  }

  static void _unitScale(double value, String name) {
    if (!value.isFinite || value <= 0 || value > 1) {
      throw ArgumentError.value(value, name, 'Must be finite and in (0, 1]');
    }
  }

  static bool _validViewport(ui.Rect rect) =>
      rect.left.isFinite &&
      rect.top.isFinite &&
      rect.right.isFinite &&
      rect.bottom.isFinite &&
      !rect.isEmpty &&
      rect.left >= 0 &&
      rect.top >= 0 &&
      rect.right <= 1 &&
      rect.bottom <= 1;
}

final class _CroppedEyeCamera extends Camera {
  _CroppedEyeCamera(
    this.source,
    PerspectiveProjection perspective,
    double aspect,
    ui.Rect crop,
  ) : projection = _CroppedEyeProjection(perspective, aspect, crop);

  final Camera source;
  @override
  final CameraProjection projection;
  @override
  vm.Vector3 get position => source.position;
  @override
  vm.Vector3 get forward => source.forward;
  @override
  vm.Vector3 get up => source.up;
  @override
  vm.Matrix4 getViewMatrix() => source.getViewMatrix();
}

final class _CroppedEyeProjection extends PerspectiveProjection {
  _CroppedEyeProjection(this.source, this.fullEyeAspect, this.crop)
    : super(
        fovRadiansY: source.fovRadiansY,
        near: source.near,
        far: source.far,
      );

  final PerspectiveProjection source;
  final double fullEyeAspect;
  final ui.Rect crop;

  @override
  vm.Matrix4 getProjectionMatrix(double aspectRatio, {vm.Vector2? jitter}) {
    // Crop in clip space AFTER the complete off-axis stereo projection. This
    // preserves IPD, convergence, optical inset and vertical disparity.
    final transform = vm.Matrix4.identity()
      ..setEntry(0, 0, 1 / crop.width)
      ..setEntry(1, 1, 1 / crop.height)
      ..setEntry(0, 3, (1 - 2 * crop.center.dx) / crop.width)
      ..setEntry(1, 3, (2 * crop.center.dy - 1) / crop.height);
    return transform *
        source.getProjectionMatrix(fullEyeAspect, jitter: jitter);
  }
}
