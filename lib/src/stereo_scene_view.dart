import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;
import 'package:vrlizate/vrlizate.dart'
    show CameraRig, GazePointer, HeadTracker, InertialTapDetector;

import 'quality_preset.dart';
import 'stereo_head_rig.dart';
import 'vr_look.dart';

/// Stereoscopic VR view over a flutter_scene [Scene], driven by the
/// vrlizate input stack.
///
/// Renders [scene] as two half-screen eye views via [StereoHeadRig] and a
/// vrlizate `HeadTracker` (gyroscope), with touch-drag fallback. When
/// [gazeEnabled], a center-gaze raycast runs every frame through the
/// vrlizate `GazePointer` (adaptive dwell + grace period): dwell on a named
/// `Node` long enough and [onGazeSelect] fires — no joystick, no buttons.
///
/// Only nodes with a non-empty `Node.name` are gaze-interactive.
class StereoSceneView extends StatefulWidget {
  const StereoSceneView({
    super.key,
    required this.scene,
    this.rig,
    this.headTracker,
    this.ipd,
    this.touchFallback = true,
    this.doubleTapToRecenter = true,
    this.zenithRecenter = true,
    this.showAlignmentDivider = true,
    this.enableTempleTap = true,
    this.enableHandTracking = true,
    this.handGlowColor = const Color(0xFF00E5FF),
    this.gazeEnabled = true,
    this.enableHaptics = true,
    this.gazeDwellSeconds = 2.0,
    this.onGazeSelect,
    this.onGazeHoverChanged,
    this.showReticle = true,
    this.quality,
    this.dynamicScaling = true,
    this.onQualityChanged,
    this.onTick,
    this.look,
  });

  /// Interpupillary distance in meters (defaults to 0.064m / 64mm).
  final double? ipd;

  /// Whether double-tapping on screen recenters the horizontal gaze heading.
  final bool doubleTapToRecenter;

  /// Whether looking straight up (~55° pitch) triggers hands-free recentering.
  final bool zenithRecenter;

  /// Whether physical tap on visor/temple triggers instant gaze select and double-tap recenters.
  final bool enableTempleTap;

  /// Whether to render and track 3D holographic hands in the stereoscopic scene.
  final bool enableHandTracking;

  /// Color accent for the 3D holographic hands glowing energy joints.
  final Color handGlowColor;

  /// Whether to render a central physical alignment divider and notch ticks.
  final bool showAlignmentDivider;

  /// Whether tactile haptic feedback is enabled for gaze dwell and interactions.
  final bool enableHaptics;

  /// The flutter_scene scene to render in stereo.
  final Scene scene;

  /// External rig; when omitted an owned one is created (eye height 1.6 m).
  final StereoHeadRig? rig;

  /// External head tracker; when omitted an owned one is created and
  /// started/stopped with this widget's lifecycle.
  final HeadTracker? headTracker;

  /// Whether touch-drag rotates the view as a gyroscope fallback.
  final bool touchFallback;

  /// Whether center-gaze raycasting + dwell selection is active.
  final bool gazeEnabled;

  /// Base dwell time in seconds before a gaze selects its target.
  final double gazeDwellSeconds;

  /// Called when a named node is dwell-selected.
  final void Function(Node node)? onGazeSelect;

  /// Called when the gazed node changes (null when gaze leaves all nodes).
  final void Function(Node? node)? onGazeHoverChanged;

  /// Whether to draw the center reticle with dwell progress.
  final bool showReticle;

  /// Quality preset; when null it is auto-detected from the display
  /// (refresh rate + pixel density). See [VrQualityPreset].
  final VrQualityPreset? quality;

  /// When true, frame times are monitored and quality steps down one tier
  /// if the rolling average stays above the frame budget.
  final bool dynamicScaling;

  /// Called whenever the effective quality tier changes (auto-detection or
  /// dynamic downscaling).
  final void Function(VrQualityPreset preset)? onQualityChanged;

  /// Extra per-frame hook (elapsed, deltaSeconds).
  final void Function(Duration elapsed, double deltaSeconds)? onTick;

  /// Optional shared visual look (tone mapping, bloom, vignette, fog, AO).
  /// Re-applied whenever the effective quality preset changes, so expensive
  /// features (bloom, AO) stay in sync with dynamic downscaling.
  final VrLook? look;

  @override
  State<StereoSceneView> createState() => _StereoSceneViewState();
}

class _StereoSceneViewState extends State<StereoSceneView> {
  late final StereoHeadRig _rig = widget.rig ??
      StereoHeadRig(
        ipd: widget.ipd ?? CameraRig.defaultIpd,
      );
  late final HeadTracker _headTracker =
      widget.headTracker ?? HeadTracker(target: _rig);
  late final GazePointer _gaze = GazePointer(
    cameraRig: _rig.cameraRig,
    dwellDuration: widget.gazeDwellSeconds,
    enableHaptics: widget.enableHaptics,
  );

  final Map<String, Node> _nodesByName = {};
  final ValueNotifier<double> _dwellProgress = ValueNotifier(0);
  final ValueNotifier<double> _zenithProgress = ValueNotifier(0);
  double _zenithTimer = 0;
  bool _zenithTriggered = false;

  InertialTapDetector? _tapDetector;
  VrQualityPreset? _preset;

  /// The quality preset currently in effect.
  VrQualityPreset? get effectivePreset => _preset;

  // Dynamic frame-time scaling state.
  double _frameTimeSum = 0;
  int _frameTimeCount = 0;
  static const int _warmupFrames = 30; // 0.5s warmup
  static const int _windowFrames = 45; // ~0.75s evaluation window
  static const double _frameBudgetSeconds = 0.018; // ~55 FPS budget

  void _applyPreset(VrQualityPreset preset) {
    _preset = preset;
    widget.scene.antiAliasingMode = preset.antiAliasing;
    widget.scene.postProcess.bloom.enabled = preset.bloomEnabled;
    widget.look?.applyToScene(widget.scene, preset);
    widget.onQualityChanged?.call(preset);
  }

  @override
  void initState() {
    super.initState();
    if (widget.rig == null) {
      _rig.eyeCenter.setValues(0, 1.6, 0);
    }
    if (widget.ipd != null) {
      _rig.ipd = widget.ipd!;
    }
    _headTracker.start();

    // Zero-latency temple/visor tap trigger
    if (widget.enableTempleTap) {
      _tapDetector = InertialTapDetector(
        onSingleTap: () {
          final currentId = _gaze.gazeTargetId;
          if (currentId != null) {
            final node = _nodesByName[currentId];
            if (node != null) {
              widget.onGazeSelect?.call(node);
              if (widget.enableHaptics) HapticFeedback.selectionClick();
            }
          }
        },
        onDoubleTap: () {
          _headTracker.recenter();
          _rig.recenter();
          if (widget.enableHaptics) HapticFeedback.mediumImpact();
        },
      )..start();
    }

    _gaze.onDwellProgress = (_, p) => _dwellProgress.value = p;
    _gaze.onGazeExit = (_) => _dwellProgress.value = 0;
    _gaze.onGazeSelect = (id) {
      _dwellProgress.value = 0;
      final node = _nodesByName[id];
      if (node != null) widget.onGazeSelect?.call(node);
    };
    _gaze.onGazeEnter = (id) {
      final node = _nodesByName[id];
      widget.onGazeHoverChanged?.call(node);
    };

    if (widget.enableHandTracking) {
      _handRig = _HolographicHandRig(widget.scene, widget.handGlowColor);
    }
  }

  _HolographicHandRig? _handRig;

  @override
  void dispose() {
    _handRig?.dispose();
    _tapDetector?.dispose();
    if (widget.headTracker == null) _headTracker.stop();
    _dwellProgress.dispose();
    _zenithProgress.dispose();
    super.dispose();
  }

  void _tick(Duration elapsed, double dt) {
    _monitorFrameTime(dt);

    final t = elapsed.inMicroseconds / 1000000.0;
    if (_handRig != null) {
      _handRig!.update(_rig.eyeCenter, _rig.cameraRig.rotation, t);
    }

    // Hands-free zenith recenter (looking up > 55°).
    if (widget.zenithRecenter) {
      if (_rig.cameraRig.pitch > 0.95) {
        _zenithTimer += dt;
        _zenithProgress.value = (_zenithTimer / 0.8).clamp(0.0, 1.0);
        if (_zenithTimer >= 0.8 && !_zenithTriggered) {
          _zenithTriggered = true;
          _headTracker.recenter();
          _rig.recenter();
          if (widget.enableHaptics) {
            HapticFeedback.mediumImpact();
          }
        }
      } else {
        _zenithTimer = 0;
        _zenithTriggered = false;
        if (_zenithProgress.value != 0) _zenithProgress.value = 0;
      }
    }

    if (widget.gazeEnabled) {
      final hit = widget.scene.raycast(_rig.gazeRay);
      final node = hit?.node;
      String? id;
      if (node != null && node.name.isNotEmpty) {
        id = node.name;
        _nodesByName[id] = node;
      }
      _gaze.update(dt, id);
    }
    widget.onTick?.call(elapsed, dt);
  }

  /// Rolling frame-time monitor: after a warmup, if the average frame time
  /// over a window exceeds the budget, quality steps down one tier.
  void _monitorFrameTime(double dt) {
    if (!widget.dynamicScaling || _preset == null) return;
    if (_preset!.tier == VrQualityTier.low) return;
    _frameTimeCount++;
    if (_frameTimeCount <= _warmupFrames) return;
    _frameTimeSum += dt;
    final windowCount = _frameTimeCount - _warmupFrames;
    if (windowCount < _windowFrames) return;
    final avg = _frameTimeSum / windowCount;
    _frameTimeSum = 0;
    _frameTimeCount = _warmupFrames;
    if (avg > _frameBudgetSeconds) {
      setState(() => _applyPreset(_preset!.stepDown));
    }
  }

  @override
  Widget build(BuildContext context) {
    final preset =
        _preset ?? VrQualityPreset.resolve(context, widget.quality);
    if (_preset == null) _applyPreset(preset);
    final dpr = MediaQuery.devicePixelRatioOf(context);

    Widget child = SceneView(
      widget.scene,
      viewsBuilder: (_) => _rig.buildStereoViews(),
      pixelRatio: dpr * preset.pixelRatioScale,
      onTick: _tick,
    );

    if (widget.touchFallback || widget.doubleTapToRecenter) {
      child = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate: widget.touchFallback
            ? (d) => _headTracker.applyTouchDelta(d.delta.dx, d.delta.dy)
            : null,
        onDoubleTap: widget.doubleTapToRecenter
            ? () {
                _headTracker.recenter();
                _rig.recenter();
                if (widget.enableHaptics) {
                  HapticFeedback.mediumImpact();
                }
              }
            : null,
        child: child,
      );
    }

    if ((widget.showReticle && widget.gazeEnabled) ||
        widget.showAlignmentDivider ||
        widget.zenithRecenter) {
      child = Stack(
        fit: StackFit.expand,
        children: [
          child,
          IgnorePointer(
            child: CustomPaint(
              painter: _ReticlePainter(
                progress: _dwellProgress,
                zenithProgress: _zenithProgress,
                showDivider: widget.showAlignmentDivider,
                showReticle: widget.showReticle && widget.gazeEnabled,
              ),
            ),
          ),
        ],
      );
    }

    return child;
  }
}

/// Center gaze reticles for both stereoscopic eyes with a dwell-progress arc,
/// physical alignment divider, and zenith calibration target.
class _ReticlePainter extends CustomPainter {
  _ReticlePainter({
    required this.progress,
    required this.zenithProgress,
    this.showDivider = true,
    this.showReticle = true,
  }) : super(repaint: Listenable.merge([progress, zenithProgress]));

  final ValueNotifier<double> progress;
  final ValueNotifier<double> zenithProgress;
  final bool showDivider;
  final bool showReticle;

  void _drawReticle(Canvas canvas, Offset center, double p, Paint ring, Paint dot, Paint arc) {
    canvas.drawCircle(center, 9, ring);
    canvas.drawCircle(center, 2.5, dot);
    if (p > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: 13),
        -3.141592653589793 / 2,
        p * 2 * 3.141592653589793,
        false,
        arc,
      );
    }
  }

  void _drawZenithTarget(Canvas canvas, Offset center, double p) {
    final ring = Paint()
      ..color = Colors.cyanAccent.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final dot = Paint()..color = Colors.cyanAccent;
    final arc = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, 16, ring);
    canvas.drawCircle(center, 3, dot);
    if (p > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: 21),
        -3.141592653589793 / 2,
        p * 2 * 3.141592653589793,
        false,
        arc,
      );
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Central Physical Alignment Divider
    if (showDivider) {
      final dividerX = size.width * 0.5;
      final dividerPaint = Paint()
        ..color = Colors.black
        ..strokeWidth = 3;
      canvas.drawLine(
        Offset(dividerX, 0),
        Offset(dividerX, size.height),
        dividerPaint,
      );

      // Alignment Notch Ticks (top & bottom)
      final tickPaint = Paint()
        ..color = const Color(0xFF00E5FF).withValues(alpha: 0.4)
        ..strokeWidth = 2;
      canvas.drawLine(
        Offset(dividerX, 0),
        Offset(dividerX, 16),
        tickPaint,
      );
      canvas.drawLine(
        Offset(dividerX, size.height - 16),
        Offset(dividerX, size.height),
        tickPaint,
      );
    }

    // 2. Stereoscopic Gaze Reticles
    if (showReticle) {
      final leftCenter = Offset(size.width * 0.25, size.height * 0.5);
      final rightCenter = Offset(size.width * 0.75, size.height * 0.5);
      final ring = Paint()
        ..color = Colors.white.withValues(alpha: 0.7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      final dot = Paint()..color = Colors.white.withValues(alpha: 0.95);
      final arc = Paint()
        ..color = Colors.cyanAccent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round;

      final p = progress.value;
      _drawReticle(canvas, leftCenter, p, ring, dot, arc);
      _drawReticle(canvas, rightCenter, p, ring, dot, arc);
    }

    // 3. Hands-Free Zenith Recenter Target (when looking straight up)
    final zp = zenithProgress.value;
    if (zp > 0) {
      final leftZenith = Offset(size.width * 0.25, size.height * 0.18);
      final rightZenith = Offset(size.width * 0.75, size.height * 0.18);
      _drawZenithTarget(canvas, leftZenith, zp);
      _drawZenithTarget(canvas, rightZenith, zp);
    }
  }

  @override
  bool shouldRepaint(_ReticlePainter oldDelegate) => true;
}

/// Lightweight 3D dual holographic hands rig rendered inside a stereoscopic [Scene].
class _HolographicHandRig {
  final Scene scene;
  final Color glowColor;

  Node? rightPalmNode;
  final List<Node> rightFingerNodes = [];
  Node? rightTipNode;

  Node? leftPalmNode;
  final List<Node> leftFingerNodes = [];
  Node? leftTipNode;

  _HolographicHandRig(this.scene, this.glowColor) {
    final col = vm.Vector4(
      glowColor.r,
      glowColor.g,
      glowColor.b,
      0.85,
    );
    final emissive = vm.Vector4(
      glowColor.r,
      glowColor.g,
      glowColor.b,
      1.0,
    );

    final handMat = PhysicallyBasedMaterial()
      ..baseColorFactor = col
      ..emissiveFactor = emissive
      ..roughnessFactor = 0.15;

    final tipMat = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(1, 1, 1, 1)
      ..emissiveFactor = vm.Vector4(col.x, col.y, col.z, 1.0)
      ..roughnessFactor = 0.0;

    // 1. Right Hand
    rightPalmNode = Node(
      name: 'holo_palm_r',
      mesh: Mesh(CuboidGeometry(vm.Vector3(0.065, 0.018, 0.065)), handMat),
    );
    scene.add(rightPalmNode!);

    for (int i = 0; i < 5; i++) {
      final f = Node(
        name: 'holo_finger_r_$i',
        mesh: Mesh(CuboidGeometry(vm.Vector3(0.012, 0.012, 0.035)), handMat),
      );
      rightFingerNodes.add(f);
      scene.add(f);
    }

    rightTipNode = Node(
      name: 'holo_tip_r',
      mesh: Mesh(CuboidGeometry(vm.Vector3(0.024, 0.024, 0.024)), tipMat),
    );
    scene.add(rightTipNode!);

    // 2. Left Hand
    leftPalmNode = Node(
      name: 'holo_palm_l',
      mesh: Mesh(CuboidGeometry(vm.Vector3(0.065, 0.018, 0.065)), handMat),
    );
    scene.add(leftPalmNode!);

    for (int i = 0; i < 5; i++) {
      final f = Node(
        name: 'holo_finger_l_$i',
        mesh: Mesh(CuboidGeometry(vm.Vector3(0.012, 0.012, 0.035)), handMat),
      );
      leftFingerNodes.add(f);
      scene.add(f);
    }

    leftTipNode = Node(
      name: 'holo_tip_l',
      mesh: Mesh(CuboidGeometry(vm.Vector3(0.024, 0.024, 0.024)), tipMat),
    );
    scene.add(leftTipNode!);
  }

  void update(vm.Vector3 eyePos, vm.Quaternion orientation, double t) {
    final hoverY = sin(t * 2.2) * 0.008;

    // 1. Right Hand position (~17cm right, 22cm down, 46cm forward)
    final localRightHand = vm.Vector3(0.17, -0.22 + hoverY, -0.46);
    final worldRightHand = eyePos + orientation.rotate(localRightHand);

    if (rightPalmNode != null) {
      rightPalmNode!.localTransform = vm.Matrix4.translation(worldRightHand);
    }

    final rightOffsets = [
      vm.Vector3(-0.028, 0.004, -0.032), // Thumb
      vm.Vector3(-0.012, 0.007, -0.048), // Index
      vm.Vector3(0.004, 0.007, -0.052),  // Middle
      vm.Vector3(0.018, 0.005, -0.044),  // Ring
      vm.Vector3(0.032, 0.003, -0.036),  // Pinky
    ];

    for (int i = 0; i < rightFingerNodes.length; i++) {
      final flex = sin(t * 1.8 + i) * 0.003;
      final off = orientation.rotate(rightOffsets[i] + vm.Vector3(0, flex, 0));
      rightFingerNodes[i].localTransform = vm.Matrix4.translation(worldRightHand + off);
    }

    final rightTipOff = orientation.rotate(vm.Vector3(-0.012, 0.007, -0.048));
    if (rightTipNode != null) {
      rightTipNode!.localTransform = vm.Matrix4.translation(worldRightHand + rightTipOff);
    }

    // 2. Left Hand position (~17cm left, 22cm down, 46cm forward)
    final localLeftHand = vm.Vector3(-0.17, -0.22 + hoverY, -0.46);
    final worldLeftHand = eyePos + orientation.rotate(localLeftHand);

    if (leftPalmNode != null) {
      leftPalmNode!.localTransform = vm.Matrix4.translation(worldLeftHand);
    }

    final leftOffsets = [
      vm.Vector3(0.028, 0.004, -0.032),  // Thumb
      vm.Vector3(0.012, 0.007, -0.048),  // Index
      vm.Vector3(-0.004, 0.007, -0.052), // Middle
      vm.Vector3(-0.018, 0.005, -0.044), // Ring
      vm.Vector3(-0.032, 0.003, -0.036), // Pinky
    ];

    for (int i = 0; i < leftFingerNodes.length; i++) {
      final flex = sin(t * 1.8 + i + 1.5) * 0.003;
      final off = orientation.rotate(leftOffsets[i] + vm.Vector3(0, flex, 0));
      leftFingerNodes[i].localTransform = vm.Matrix4.translation(worldLeftHand + off);
    }

    final leftTipOff = orientation.rotate(vm.Vector3(0.012, 0.007, -0.048));
    if (leftTipNode != null) {
      leftTipNode!.localTransform = vm.Matrix4.translation(worldLeftHand + leftTipOff);
    }
  }

  void dispose() {
    if (rightPalmNode != null) scene.remove(rightPalmNode!);
    for (final f in rightFingerNodes) {
      scene.remove(f);
    }
    if (rightTipNode != null) scene.remove(rightTipNode!);

    if (leftPalmNode != null) scene.remove(leftPalmNode!);
    for (final f in leftFingerNodes) {
      scene.remove(f);
    }
    if (leftTipNode != null) scene.remove(leftTipNode!);
  }
}

