import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

/// Configuration for single-pass Qualcomm Snapdragon Game Super Resolution 1
/// (`SGSR 1`, `BSD-3-Clause`) spatial upscaling over `StereoSceneView`.
///
/// Renders the 3D scene at [internalRenderScale] (e.g. `0.75x`, cutting ~`43.8%`
/// of 3D fragment/PBR/shadow work) and reconstructs native-DPR edges in one
/// pass while keeping HUD reticles and controller feedback at `1.0x` native DPR.
@immutable
class VrSgsrUpscaleConfig {
  const VrSgsrUpscaleConfig({
    this.enabled = true,
    this.internalRenderScale = 0.75,
    this.edgeSharpness = 2.0,
    this.edgeThreshold = 8.0 / 255.0,
  }) : assert(
         internalRenderScale >= 0.50 && internalRenderScale <= 1.0,
         'internalRenderScale must lie within [0.50 .. 1.0].',
       ),
       assert(
         edgeSharpness >= 0.5 && edgeSharpness <= 4.0,
         'edgeSharpness must lie within [0.5 .. 4.0].',
       ),
       assert(
         edgeThreshold >= 1.0 / 255.0 && edgeThreshold <= 64.0 / 255.0,
         'edgeThreshold must lie within [1/255 .. 64/255].',
       );

  /// Pass-through (native `1.0x` 3D rendering, shader filter disabled).
  static const disabled = VrSgsrUpscaleConfig(
    enabled: false,
    internalRenderScale: 1.0,
  );

  /// High-clarity preset (`0.82x` linear -> ~`32.8%` fewer shaded 3D pixels).
  static const mobileQuality = VrSgsrUpscaleConfig(
    internalRenderScale: 0.82,
    edgeSharpness: 2.0,
  );

  /// Default mobile VR balance (`0.75x` linear -> `43.75%` fewer shaded pixels).
  static const mobileBalanced = VrSgsrUpscaleConfig(
    internalRenderScale: 0.75,
    edgeSharpness: 2.0,
  );

  /// Thermal / high-Hz battery saver (`0.67x` linear -> ~`55.1%` fewer pixels).
  static const mobilePerformance = VrSgsrUpscaleConfig(
    internalRenderScale: 0.67,
    edgeSharpness: 2.15,
  );

  final bool enabled;
  final double internalRenderScale;
  final double edgeSharpness;
  final double edgeThreshold;

  bool get isActive => enabled && internalRenderScale < 0.999;

  /// Relative 2D shaded pixel count (`1.0` when inactive, `scale^2` when active).
  double get shadedPixelFraction =>
      isActive ? internalRenderScale * internalRenderScale : 1.0;

  /// Fraction of 3D fragment shading work saved (`0.4375` at `0.75x`).
  double get estimatedShadedPixelSavings => 1.0 - shadedPixelFraction;

  VrSgsrUpscaleConfig copyWith({
    bool? enabled,
    double? internalRenderScale,
    double? edgeSharpness,
    double? edgeThreshold,
  }) => VrSgsrUpscaleConfig(
    enabled: enabled ?? this.enabled,
    internalRenderScale: internalRenderScale ?? this.internalRenderScale,
    edgeSharpness: edgeSharpness ?? this.edgeSharpness,
    edgeThreshold: edgeThreshold ?? this.edgeThreshold,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VrSgsrUpscaleConfig &&
          other.enabled == enabled &&
          other.internalRenderScale == internalRenderScale &&
          other.edgeSharpness == edgeSharpness &&
          other.edgeThreshold == edgeThreshold;

  @override
  int get hashCode => Object.hash(
    enabled,
    internalRenderScale,
    edgeSharpness,
    edgeThreshold,
  );
}

/// Linear RGB triplet (supports extended HDR values `> 1.0`) returned by
/// [VrSgsrUpscaleMath] during deterministic CPU verification.
@immutable
class VrSgsrRgbSample {
  const VrSgsrRgbSample(
    this.r,
    this.g,
    this.b, {
    this.edgeTriggered = false,
    this.deltaY = 0.0,
    this.edgeDirection = Offset.zero,
  });

  final double r;
  final double g;
  final double b;
  final bool edgeTriggered;
  final double deltaY;
  final Offset edgeDirection;

  double get luma => 0.299 * r + 0.587 * g + 0.114 * b;
}

/// Deterministic CPU reference of `shaders/vr_sgsr1_upscale.frag`
/// (`BSD-3-Clause`, Qualcomm SGSR v1 `UseEdgeDirection` + HDR preservation).
abstract final class VrSgsrUpscaleMath {
  static double fastLanczos2(double x) {
    var wA = x - 4.0;
    final wB = x * wA - wA;
    wA *= wA;
    return wB * wA;
  }

  static Offset edgeDirection({
    required double leftY,
    required double leftZ,
    required double rightX,
    required double rightW,
  }) {
    final rxLz = rightX - leftZ;
    final rwLy = rightW - leftY;
    final dx = rxLz + rwLy;
    final dy = rxLz - rwLy;
    final lenInv =
        1.0 / math.sqrt((dx * dx + 3.075740e-05) + (dy * dy));
    return Offset(dx * lenInv, dy * lenInv);
  }

  static Offset eyeToScreenUv(
    Offset eyeUv, {
    required bool isLeft,
    required bool stereoSplit,
  }) {
    final cx = eyeUv.dx.clamp(0.0005, 0.9995);
    final cy = eyeUv.dy.clamp(0.0005, 0.9995);
    if (!stereoSplit) return Offset(cx, cy);
    final fullX = isLeft ? (cx * 0.5) : (0.5 + cx * 0.5);
    return Offset(fullX.clamp(0.0005, 0.9995), cy);
  }

  static (double w, double wc) _weightY(
    double dx,
    double dy,
    double c,
    double std,
    Offset dir,
  ) {
    final edgeDis = (dx * dir.dy) + (dy * dir.dx);
    final x =
        ((dx * dx) + (dy * dy)) +
        (edgeDis * edgeDis * (((c * c * std).clamp(0.0, 1.0) * 0.7) - 1.0));
    final w = fastLanczos2(x);
    return (w, w * c);
  }

  /// Evaluates the exact 12-tap SGSR v1 kernel at normalized full-viewport
  /// coordinate [screenUv] (`[0..1]^2`).
  ///
  /// [sampleFullScreen] receives clamped full-screen UVs so tests can verify
  /// both spatial sharpening and strict `x = 0.5` left/right eye isolation.
  static VrSgsrRgbSample evaluate({
    required Offset screenUv,
    required Size outputViewportSize,
    required double effectiveRenderScale,
    required (double r, double g, double b) Function(Offset fullScreenUv)
    sampleFullScreen,
    bool stereoSplit = true,
    double edgeSharpness = 2.0,
    double edgeThreshold = 8.0 / 255.0,
  }) {
    final safeW = math.max(outputViewportSize.width, 2.0);
    final safeH = math.max(outputViewportSize.height, 2.0);
    final isLeft = stereoSplit && screenUv.dx < 0.5;
    final eyeUv = stereoSplit
        ? Offset(
            isLeft ? (screenUv.dx * 2.0) : ((screenUv.dx - 0.5) * 2.0),
            screenUv.dy,
          )
        : screenUv;

    final baseRgb = sampleFullScreen(
      eyeToScreenUv(eyeUv, isLeft: isLeft, stereoSplit: stereoSplit),
    );
    final scale = effectiveRenderScale.clamp(0.25, 1.0);
    if (scale >= 0.999) {
      return VrSgsrRgbSample(baseRgb.$1, baseRgb.$2, baseRgb.$3);
    }

    final eyeOutW = stereoSplit ? safeW * 0.5 : safeW;
    final eyeInW = math.max((eyeOutW * scale).floorToDouble(), 2.0);
    final eyeInH = math.max((safeH * scale).floorToDouble(), 2.0);

    final imgX = eyeUv.dx * eyeInW - 0.5;
    final imgY = eyeUv.dy * eyeInH - 0.5;
    final baseX = imgX.floorToDouble();
    final baseY = imgY.floorToDouble();
    final plX = imgX - baseX;
    final plY = imgY - baseY;

    double luma((double, double, double) c) =>
        0.299 * c.$1 + 0.587 * c.$2 + 0.114 * c.$3;

    double tap(double ox, double oy) {
      final tx = (baseX + ox + 0.5).clamp(0.5, eyeInW - 0.5);
      final ty = (baseY + oy + 0.5).clamp(0.5, eyeInH - 0.5);
      final uv = eyeToScreenUv(
        Offset(tx / eyeInW, ty / eyeInH),
        isLeft: isLeft,
        stereoSplit: stereoSplit,
      );
      return luma(sampleFullScreen(uv));
    }

    final cLuma = luma(baseRgb);
    final leftZ = tap(0.0, 0.0);
    final leftY = tap(0.0, 1.0);
    final rightW = tap(1.0, 0.0);
    final edgeVote =
        (leftZ - leftY).abs() +
        (leftZ - rightW).abs() +
        (cLuma - leftY).abs() +
        (cLuma - leftZ).abs();

    if (edgeVote <= edgeThreshold) {
      return VrSgsrRgbSample(baseRgb.$1, baseRgb.$2, baseRgb.$3);
    }

    final rawLx = tap(-1.0, 1.0);
    final rawLy = leftY;
    final rawLz = leftZ;
    final rawLw = tap(-1.0, 0.0);

    final rawRx = tap(1.0, 1.0);
    final rawRy = tap(2.0, 1.0);
    final rawRz = tap(2.0, 0.0);
    final rawRw = rightW;

    final rawUx = tap(0.0, -1.0);
    final rawUy = tap(1.0, -1.0);
    final rawUz = tap(1.0, 2.0);
    final rawUw = tap(0.0, 2.0);

    final mean = (rawLy + rawLz + rawRx + rawRw) * 0.25;
    final lx = rawLx - mean;
    final ly = rawLy - mean;
    final lz = rawLz - mean;
    final lw = rawLw - mean;
    final rx = rawRx - mean;
    final ry = rawRy - mean;
    final rz = rawRz - mean;
    final rw = rawRw - mean;
    final ux = rawUx - mean;
    final uy = rawUy - mean;
    final uz = rawUz - mean;
    final uw = rawUw - mean;
    final centerDelta = cLuma - mean;

    final sum =
        lx.abs() +
        ly.abs() +
        lz.abs() +
        lw.abs() +
        rx.abs() +
        ry.abs() +
        rz.abs() +
        rw.abs() +
        ux.abs() +
        uy.abs() +
        uz.abs() +
        uw.abs();
    final sumMean = 1.014185e+01 / math.max(sum, 1.0e-5);
    final std = sumMean * sumMean;
    final dir = edgeDirection(
      leftY: ly,
      leftZ: lz,
      rightX: rx,
      rightW: rw,
    );

    var accW = 0.0;
    var accWC = 0.0;
    void addTap(double dx, double dy, double c) {
      final (w, wc) = _weightY(dx, dy, c, std, dir);
      accW += w;
      accWC += wc;
    }

    addTap(plX, plY + 1.0, ux);
    addTap(plX - 1.0, plY + 1.0, uy);
    addTap(plX - 1.0, plY - 2.0, uz);
    addTap(plX, plY - 2.0, uw);
    addTap(plX + 1.0, plY - 1.0, lx);
    addTap(plX, plY - 1.0, ly);
    addTap(plX, plY, lz);
    addTap(plX + 1.0, plY, lw);
    addTap(plX - 1.0, plY - 1.0, rx);
    addTap(plX - 2.0, plY - 1.0, ry);
    addTap(plX - 2.0, plY, rz);
    addTap(plX - 1.0, plY, rw);

    final denom = accW.abs() > 1.0e-5 ? accW : (accW < 0.0 ? -1.0e-5 : 1.0e-5);
    final finalY = accWC / denom;
    final maxY = math.max(math.max(ly, lz), math.max(rx, rw));
    final minY = math.min(math.min(ly, lz), math.min(rx, rw));
    var deltaY = (edgeSharpness * finalY).clamp(minY, maxY) - centerDelta;
    final maxSwing = (23.0 / 255.0) * math.max(1.0, cLuma);
    deltaY = deltaY.clamp(-maxSwing, maxSwing);

    return VrSgsrRgbSample(
      math.max(baseRgb.$1 + deltaY, 0.0),
      math.max(baseRgb.$2 + deltaY, 0.0),
      math.max(baseRgb.$3 + deltaY, 0.0),
      edgeTriggered: true,
      deltaY: deltaY,
      edgeDirection: dir,
    );
  }
}

/// Impeller GPU post-process filter applying Qualcomm SGSR 1 (`BSD-3-Clause`)
/// single-pass edge-directed spatial upscaling to the 3D scene layer before
/// HUD reticles, controller feedback, and optical lens distortion.
///
/// Always renders an `ImageFiltered(enabled: ...)` wrapper so toggling SGSR or
/// adapting render scale never unmounts the child `SceneView`.
class VrSgsrUpscalePostProcess extends StatefulWidget {
  const VrSgsrUpscalePostProcess({
    super.key,
    required this.config,
    required this.effectiveRenderScale,
    required this.stereoSplit,
    this.onShaderReadyChanged,
    required this.child,
  });

  final VrSgsrUpscaleConfig? config;

  /// Total internal render scale relative to the output layer (`preset * sgsr`).
  final double effectiveRenderScale;
  final bool stereoSplit;
  final ValueChanged<bool>? onShaderReadyChanged;
  final Widget child;

  @override
  State<VrSgsrUpscalePostProcess> createState() =>
      _VrSgsrUpscalePostProcessState();
}

class _VrSgsrUpscalePostProcessState extends State<VrSgsrUpscalePostProcess> {
  static Future<ui.FragmentProgram?>? _programFuture;
  static ui.FragmentProgram? _cachedProgram;
  static final ui.ImageFilter _inertFilter = ui.ImageFilter.blur();

  ui.FragmentProgram? _program;
  ui.FragmentShader? _shader;
  bool _reportedReady = false;

  bool get _wantsShader => widget.config?.isActive ?? false;

  @override
  void initState() {
    super.initState();
    if (_wantsShader) _ensureProgramLoaded(fromLifecycle: true);
  }

  @override
  void didUpdateWidget(covariant VrSgsrUpscalePostProcess oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_wantsShader && _program == null) {
      _ensureProgramLoaded(fromLifecycle: true);
    } else {
      _notifyReadyIfNeeded(deferToPostFrame: true);
    }
  }

  void _notifyReadyIfNeeded({bool deferToPostFrame = false}) {
    final ready =
        _shader != null && ui.ImageFilter.isShaderFilterSupported;
    if (ready == _reportedReady) return;
    _reportedReady = ready;
    final cb = widget.onShaderReadyChanged;
    if (cb == null) return;
    if (deferToPostFrame) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) cb(_reportedReady);
      });
    } else {
      cb(ready);
    }
  }

  void _ensureProgramLoaded({bool fromLifecycle = false}) {
    if (!ui.ImageFilter.isShaderFilterSupported) return;
    final cached = _cachedProgram;
    if (cached != null) {
      _program = cached;
      _shader ??= cached.fragmentShader();
      _notifyReadyIfNeeded(deferToPostFrame: fromLifecycle);
      return;
    }
    _programFuture ??= _loadFragmentProgram();
    unawaited(
      _programFuture!.then((program) {
        if (program != null) _cachedProgram = program;
        if (!mounted || program == null) return;
        setState(() {
          _program = program;
          _shader ??= program.fragmentShader();
        });
        _notifyReadyIfNeeded();
      }),
    );
  }

  static Future<ui.FragmentProgram?> _loadFragmentProgram() async {
    try {
      return await ui.FragmentProgram.fromAsset(
        'packages/vrlizate_scene/shaders/vr_sgsr1_upscale.frag',
      );
    } catch (_) {
      try {
        return await ui.FragmentProgram.fromAsset(
          'shaders/vr_sgsr1_upscale.frag',
        );
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
    final cfg = widget.config;
    final canFilter =
        cfg != null &&
        cfg.isActive &&
        widget.effectiveRenderScale < 0.999 &&
        ui.ImageFilter.isShaderFilterSupported &&
        _shader != null;

    ui.ImageFilter filter = _inertFilter;
    if (canFilter) {
      final shader = _shader!;
      // Floats 0 and 1 are reserved for `uniform vec2 u_size` by Impeller.
      shader.setFloat(2, widget.effectiveRenderScale.clamp(0.25, 1.0));
      shader.setFloat(3, cfg.edgeSharpness);
      shader.setFloat(4, cfg.edgeThreshold);
      shader.setFloat(5, widget.stereoSplit ? 1.0 : 0.0);
      filter = ui.ImageFilter.shader(shader);
    }

    return ImageFiltered(
      enabled: canFilter,
      imageFilter: filter,
      child: widget.child,
    );
  }
}
