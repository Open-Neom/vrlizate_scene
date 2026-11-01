import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import 'vr_viewer_profile.dart';

/// Deterministic CPU reference of `shaders/vr_lens_warp.frag` for optical
/// verification, gaze-to-lens calibration checks, and unit tests.
class VrLensWarpSample {
  const VrLensWarpSample({
    required this.redScreenUv,
    required this.greenScreenUv,
    required this.blueScreenUv,
    required this.redEyeUv,
    required this.greenEyeUv,
    required this.blueEyeUv,
    required this.apertureMask,
    required this.greenBorderMask,
  });

  final Offset redScreenUv;
  final Offset greenScreenUv;
  final Offset blueScreenUv;
  final Offset redEyeUv;
  final Offset greenEyeUv;
  final Offset blueEyeUv;

  /// `1.0` inside the optical cone, `0.0` in the `#000000` OLED Pancake mask.
  final double apertureMask;

  /// `1.0` inside the warped eye viewport, `0.0` outside `[0..1]` eye borders.
  final double greenBorderMask;
}

abstract final class VrLensWarpMath {
  static double _smoothstep(double edge0, double edge1, double x) {
    if (edge1 <= edge0) return x < edge0 ? 0.0 : 1.0;
    final t = ((x - edge0) / (edge1 - edge0)).clamp(0.0, 1.0);
    return t * t * (3.0 - 2.0 * t);
  }

  static double _eyeBorderMask(Offset eyeUv) {
    final dx = math.min(eyeUv.dx, 1.0 - eyeUv.dx);
    final dy = math.min(eyeUv.dy, 1.0 - eyeUv.dy);
    return _smoothstep(-0.002, 0.008, math.min(dx, dy));
  }

  static Offset _eyeToScreenUv(Offset eyeUv, bool isLeft) {
    final cx = eyeUv.dx.clamp(0.001, 0.999);
    final cy = eyeUv.dy.clamp(0.001, 0.999);
    final fullX = isLeft ? (cx * 0.5) : (0.5 + cx * 0.5);
    return Offset(fullX.clamp(0.0005, 0.9995), cy.clamp(0.0005, 0.9995));
  }

  /// Evaluates the exact barrel + RGB chromatic dispersion + Pancake OLED mask
  /// mapping for a normalized full-screen coordinate [screenUv] (`[0..1]^2`).
  static VrLensWarpSample evaluate({
    required Offset screenUv,
    required Size viewportSize,
    required VrViewerProfile profile,
    double? stereoImageInsetOverride,
  }) {
    final safeW = math.max(viewportSize.width, 1.0);
    final safeH = math.max(viewportSize.height, 1.0);
    final isLeft = screenUv.dx < 0.5;
    final eyeUv = Offset(
      isLeft ? (screenUv.dx * 2.0) : ((screenUv.dx - 0.5) * 2.0),
      screenUv.dy,
    );

    final inset = stereoImageInsetOverride ?? profile.stereoImageInset;
    final centerShift = inset * 0.5;
    final lensCenter = Offset(
      isLeft ? (0.5 + centerShift) : (0.5 - centerShift),
      0.5,
    );
    final delta = (eyeUv - lensCenter) * 2.0;

    final eyeAspect = (safeW * 0.5) / safeH;
    final pMetric = eyeAspect >= 1.0
        ? Offset(delta.dx * eyeAspect, delta.dy)
        : Offset(delta.dx, delta.dy / math.max(eyeAspect, 0.001));

    final r2 = pMetric.dx * pMetric.dx + pMetric.dy * pMetric.dy;
    final r4 = r2 * r2;
    final k1 = profile.lensDistortionK1;
    final k2 = profile.lensDistortionK2;
    final caR = profile.chromaticAberrationRed;
    final caB = profile.chromaticAberrationBlue;

    final invZoom = 1.0 / math.max(1.0 + k1 * 0.55 + k2 * 0.30, 0.25);
    final baseWarp = (1.0 + k1 * r2 + k2 * r4) * invZoom;

    final uvG = lensCenter + (delta * baseWarp) * 0.5;
    final uvR = lensCenter + (delta * (baseWarp * (1.0 + caR * r2))) * 0.5;
    final uvB = lensCenter + (delta * (baseWarp * (1.0 + caB * r2))) * 0.5;

    var apertureMask = 1.0;
    if (profile.apertureRadius > 0.0) {
      final r = math.sqrt(r2);
      apertureMask =
          1.0 -
          _smoothstep(
            math.max(0.0, profile.apertureRadius - 0.03),
            profile.apertureRadius,
            r,
          );
    }

    return VrLensWarpSample(
      redScreenUv: _eyeToScreenUv(uvR, isLeft),
      greenScreenUv: _eyeToScreenUv(uvG, isLeft),
      blueScreenUv: _eyeToScreenUv(uvB, isLeft),
      redEyeUv: uvR,
      greenEyeUv: uvG,
      blueEyeUv: uvB,
      apertureMask: apertureMask,
      greenBorderMask: _eyeBorderMask(uvG),
    );
  }
}

/// Impeller GPU post-process filter applying Brown-Conrady barrel warp,
/// per-channel RGB lateral chromatic aberration compensation, and circular
/// `#000000` OLED Pancake aperture masking over dual-eye stereo views.
///
/// Preserves a constant widget/element depth via `ImageFiltered(enabled: ...)`
/// so toggling lens distortion never recreates the child `SceneView`.
class VrLensWarpPostProcess extends StatefulWidget {
  const VrLensWarpPostProcess({
    super.key,
    required this.enabled,
    required this.profile,
    this.stereoImageInsetOverride,
    required this.child,
  });

  final bool enabled;
  final VrViewerProfile? profile;
  final double? stereoImageInsetOverride;
  final Widget child;

  @override
  State<VrLensWarpPostProcess> createState() => _VrLensWarpPostProcessState();
}

class _VrLensWarpPostProcessState extends State<VrLensWarpPostProcess> {
  static Future<ui.FragmentProgram?>? _programFuture;
  static final ui.ImageFilter _inertFilter = ui.ImageFilter.blur();

  ui.FragmentProgram? _program;
  ui.FragmentShader? _shader;

  bool get _wantsShader {
    final p = widget.profile;
    return widget.enabled && p != null && p.hasLensWarp;
  }

  @override
  void initState() {
    super.initState();
    if (_wantsShader) _ensureProgramLoaded();
  }

  @override
  void didUpdateWidget(covariant VrLensWarpPostProcess oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_wantsShader && _program == null) {
      _ensureProgramLoaded();
    }
  }

  void _ensureProgramLoaded() {
    if (!ui.ImageFilter.isShaderFilterSupported) return;
    _programFuture ??= _loadFragmentProgram();
    unawaited(
      _programFuture!.then((program) {
        if (!mounted || program == null) return;
        setState(() {
          _program = program;
          _shader ??= program.fragmentShader();
        });
      }),
    );
  }

  static Future<ui.FragmentProgram?> _loadFragmentProgram() async {
    try {
      return await ui.FragmentProgram.fromAsset(
        'packages/vrlizate_scene/shaders/vr_lens_warp.frag',
      );
    } catch (_) {
      try {
        return await ui.FragmentProgram.fromAsset('shaders/vr_lens_warp.frag');
      } catch (_) {
        return null;
      }
    }
  }

  @override
  void dispose() {
    _shader?.dispose();
    _shader = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.profile;
    final canFilter =
        _wantsShader &&
        ui.ImageFilter.isShaderFilterSupported &&
        _shader != null &&
        profile != null;

    ui.ImageFilter filter = _inertFilter;
    if (canFilter) {
      final shader = _shader!;
      final inset = widget.stereoImageInsetOverride ?? profile.stereoImageInset;
      // Floats 0 and 1 are reserved for `uniform vec2 u_size` by Impeller.
      shader.setFloat(2, inset);
      shader.setFloat(3, profile.lensDistortionK1);
      shader.setFloat(4, profile.lensDistortionK2);
      shader.setFloat(5, profile.chromaticAberrationRed);
      shader.setFloat(6, profile.chromaticAberrationBlue);
      shader.setFloat(7, profile.apertureRadius);
      filter = ui.ImageFilter.shader(shader);
    }

    return ImageFiltered(
      enabled: canFilter,
      imageFilter: filter,
      child: widget.child,
    );
  }
}
