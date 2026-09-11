import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;
import 'package:vrlizate/vrlizate.dart'
    show
        CameraRig,
        GazePointer,
        HeadTracker,
        InertialTapDetector,
        VrInputArbiter,
        VrInputEvent,
        VrInputType;
import 'package:vrlizate_widgets/vrlizate_widgets.dart'
    show VrButton3D, VrTextLabel;

import 'quality_preset.dart';
import 'simulated_hand_visuals.dart';
import 'stereo_head_rig.dart';
import 'vr_look.dart';
import 'vr_world_navigation_scope.dart';
import 'vr_input_session_scope.dart';
import 'openxr/vr_openxr_swapchain_bridge.dart';

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
    this.stereoImageInset,
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
    this.gazeFilter,
    this.showReticle = true,
    this.quality,
    this.dynamicScaling = true,
    this.onQualityChanged,
    this.onTick,
    this.look,
    this.convergenceDistance = 1.8,
    this.arbiter,
    this.openXrBridge,
  });

  /// Optional OpenXR swapchain bridge for direct external GPU render-target presentation.
  ///
  /// When provided on standalone hardware (e.g. Meta Quest 3), the stereo scene
  /// render dispatch can bypass Flutter's Canvas and render directly to hardware swapchains.
  final VrOpenXrSwapchainBridge? openXrBridge;

  /// Optional input arbiter for unified multimodal priority & gaze suppression.
  ///
  /// When provided, dwell progress and auto-selection are cleanly suppressed
  /// while higher priority inputs (e.g. 2nd phone remote, touch) are actively interacting.
  final VrInputArbiter? arbiter;

  /// Zero-parallax distance in meters before optical image inset (default 1.8m).
  ///
  /// An off-axis projection keeps the cameras parallel and aligns the views
  /// at this depth. Null or non-positive values disable the convergence shift.
  /// Physical lens calibration remains necessary for viewing comfort.
  final double? convergenceDistance;

  /// Interpupillary distance in meters (defaults to 0.064m / 64mm).
  final double? ipd;

  /// Optical image-center correction. Positive values move both eye images
  /// inward without changing the virtual cameras' anatomical IPD.
  final double? stereoImageInset;

  /// Whether double-tapping on screen recenters the horizontal gaze heading.
  final bool doubleTapToRecenter;

  /// Whether looking straight up (~55° pitch) triggers hands-free recentering.
  final bool zenithRecenter;

  /// Whether physical tap on visor/temple triggers instant gaze select and double-tap recenters.
  final bool enableTempleTap;

  /// Whether to render decorative, head-relative holographic hands.
  ///
  /// This legacy option displays a simulated idle pose; it does not enable
  /// optical hand tracking or consume measured hand landmarks.
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

  /// Optional scene-node filter used by gaze raycasting.
  ///
  /// A world-space modal can restrict gaze to its own controls while open,
  /// preventing scenery from stealing the reticle without making the modal
  /// follow the user's head.
  final bool Function(Node node)? gazeFilter;

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
  late final StereoHeadRig _rig =
      widget.rig ??
      StereoHeadRig(
        ipd: widget.ipd ?? CameraRig.defaultIpd,
        convergenceDistance: widget.convergenceDistance,
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
  VrWorldNavigationScope? _worldNavigation;
  VrButton3D? _worldHomeButton;
  vm.Vector3? _worldHomeCenter;
  List<Node> _worldHomeNodes = const [];
  bool _worldHomeCreating = false;
  int _worldHomeGeneration = 0;

  static const String _worldHomeNodeName = '__vrlizate_system_home__';
  VrInputArbiter? _activeArbiter;

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
    if (widget.stereoImageInset != null) {
      _rig.stereoImageInset = widget.stereoImageInset!;
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
              _activateGazeNode(node);
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

    _gaze.onDwellProgress = (_, p) {
      if (_activeArbiter != null && _activeArbiter!.isGazeSuppressed) {
        if (_dwellProgress.value != 0) _dwellProgress.value = 0;
        return;
      }
      _dwellProgress.value = p;
    };
    _gaze.onGazeExit = (id) {
      _dwellProgress.value = 0;
      if (id == _worldHomeNodeName) {
        _worldHomeButton?.onHoverExit(id);
      } else if (widget.gazeEnabled) {
        widget.onGazeHoverChanged?.call(null);
      }
    };
    _gaze.onGazeSelect = (id) {
      if (_activeArbiter != null && _activeArbiter!.isGazeSuppressed) {
        _dwellProgress.value = 0;
        return;
      }
      _dwellProgress.value = 0;
      final node = _nodesByName[id];
      if (node != null) _activateGazeNode(node);
    };
    _gaze.onGazeEnter = (id) {
      final node = _nodesByName[id];
      if (id == _worldHomeNodeName) {
        _worldHomeButton?.onHoverEnter(id);
      } else if (widget.gazeEnabled) {
        widget.onGazeHoverChanged?.call(node);
      }
    };

    if (widget.enableHandTracking) {
      _handRig = SimulatedHandVisuals(widget.scene.root, widget.handGlowColor);
    }
  }

  SimulatedHandVisuals? _handRig;

  void _onArbiterEvent(VrInputEvent event) {
    if (!mounted) return;
    if ((event.type == VrInputType.select || event.type == VrInputType.trigger) &&
        event.active) {
      final currentId = _gaze.gazeTargetId;
      if (currentId != null) {
        final node = _nodesByName[currentId];
        if (node != null) {
          _activateGazeNode(node);
          if (widget.enableHaptics) HapticFeedback.selectionClick();
        }
      }
    }
  }

  void _updateActiveArbiter() {
    final nextArbiter =
        widget.arbiter ?? VrInputSessionScope.arbiterOf(context);
    if (nextArbiter != _activeArbiter) {
      _activeArbiter?.removeListener(_onArbiterEvent);
      _activeArbiter = nextArbiter;
      _activeArbiter?.addListener(_onArbiterEvent);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateActiveArbiter();
    final next = VrWorldNavigationScope.maybeOf(context);
    if (next?.onHome != _worldNavigation?.onHome ||
        next?.homeLabel != _worldNavigation?.homeLabel) {
      _removeWorldHome();
      _worldNavigation = next;
    }
  }

  @override
  void didUpdateWidget(covariant StereoSceneView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.arbiter != oldWidget.arbiter) {
      _updateActiveArbiter();
    }
    if (widget.quality != oldWidget.quality && widget.quality != null) {
      _applyPreset(widget.quality!);
    }
    if (widget.ipd != oldWidget.ipd && widget.ipd != null) {
      _rig.ipd = widget.ipd!;
    }
    if (widget.stereoImageInset != oldWidget.stereoImageInset &&
        widget.stereoImageInset != null) {
      _rig.stereoImageInset = widget.stereoImageInset!;
    }
    if (widget.convergenceDistance != oldWidget.convergenceDistance) {
      _rig.convergenceDistance = widget.convergenceDistance;
    }
    if (widget.look != oldWidget.look && widget.look != null) {
      widget.look!.applyToScene(
        widget.scene,
        _preset ?? VrQualityPreset.medium,
      );
    }
  }

  @override
  void dispose() {
    _activeArbiter?.removeListener(_onArbiterEvent);
    _activeArbiter = null;
    _removeWorldHome();
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
    if (t > 0.20 &&
        _worldNavigation != null &&
        _worldHomeButton == null &&
        !_worldHomeCreating) {
      _createWorldHome();
    }
    _worldHomeButton?.update(dt);
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

    final systemGazeEnabled = _worldNavigation != null;
    if (widget.gazeEnabled || systemGazeEnabled) {
      final homeCenter = _worldHomeCenter;
      var aimingAtHome = false;
      if (systemGazeEnabled && homeCenter != null) {
        final toHome = homeCenter - _rig.eyeCenter;
        if (toHome.length2 > 0.0001) {
          toHome.normalize();
          // Cheap angular broad phase: preserve one raycast per frame on
          // low-end devices, and only grant system priority near HOME.
          aimingAtHome = toHome.dot(_rig.forward) > 0.96;
        }
      }
      final systemHit = aimingAtHome
          ? widget.scene.raycast(
              _rig.gazeRay,
              where: (node) => node.name == _worldHomeNodeName,
            )
          : null;
      final hit =
          systemHit ??
          (widget.gazeEnabled
              ? widget.scene.raycast(
                  _rig.gazeRay,
                  where: (node) =>
                      node.name != _worldHomeNodeName &&
                      (widget.gazeFilter?.call(node) ?? true),
                )
              : null);
      final node = hit?.node;
      String? id;
      if (node != null && node.name.isNotEmpty) {
        id = node.name;
        _nodesByName[id] = node;
      }
      _gaze.update(
        dt,
        id,
        dwellEnabled: !(_activeArbiter?.isGazeSuppressed ?? false),
      );
    }
    widget.onTick?.call(elapsed, dt);
  }

  void _activateGazeNode(Node node) {
    if (node.name == _worldHomeNodeName) {
      _worldHomeButton?.onSelect(_worldHomeNodeName);
      return;
    }
    if (widget.gazeEnabled) widget.onGazeSelect?.call(node);
  }

  Future<void> _createWorldHome() async {
    final navigation = _worldNavigation;
    if (navigation == null || _worldHomeCreating || !mounted) return;
    _worldHomeCreating = true;
    final generation = ++_worldHomeGeneration;
    try {
      final button = VrButton3D(
        name: _worldHomeNodeName,
        label: 'Volver al Home',
        center: vm.Vector3.zero(),
        color: vm.Vector4(0.02, 0.70, 0.88, 1),
        width: 0.52,
        height: 0.18,
        onPressed: navigation.onHome,
      );
      final label = await VrTextLabel.create(
        navigation.homeLabel,
        center: vm.Vector3.zero(),
        height: 0.062,
        fontSize: 80,
        color: Colors.white,
        fontWeight: FontWeight.w800,
        maxWidthPx: 700,
        name: _worldHomeNodeName,
      );
      if (!mounted ||
          generation != _worldHomeGeneration ||
          _worldNavigation == null) {
        return;
      }

      final distance = _rig.convergenceDistance ?? 1.8;
      final center =
          _rig.eyeCenter +
          _rig.forward * distance +
          _rig.right * 0.62 +
          _rig.up * 0.42;
      final pose = _WorldLockedBasis.facing(
        eye: _rig.eyeCenter,
        center: center,
      );
      button.nodes.first.localTransform = pose.transformAt(0, 0, 0);
      label.node.localTransform = pose.transformAt(0, 0, 0.04)
        ..rotateX(pi / 2)
        ..scaleByVector3(vm.Vector3(-1, 1, 1));

      _worldHomeButton = button;
      _worldHomeCenter = center.clone();
      _worldHomeNodes = [...button.nodes, label.node];
      for (final node in _worldHomeNodes) {
        widget.scene.add(node);
      }
    } catch (error, stackTrace) {
      debugPrint('Could not create world HOME control: $error\n$stackTrace');
    } finally {
      _worldHomeCreating = false;
    }
  }

  void _removeWorldHome() {
    _worldHomeGeneration++;
    for (final node in _worldHomeNodes) {
      if (node.parent != null) widget.scene.remove(node);
    }
    _worldHomeNodes = const [];
    _worldHomeButton = null;
    _worldHomeCenter = null;
    _worldHomeCreating = false;
    _nodesByName.remove(_worldHomeNodeName);
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
    final preset = _preset ?? VrQualityPreset.resolve(context, widget.quality);
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

    final effectiveGaze = widget.gazeEnabled || _worldNavigation != null;
    if ((widget.showReticle && effectiveGaze) ||
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
                showReticle: widget.showReticle && effectiveGaze,
                stereoImageInset: _rig.stereoImageInset,
              ),
            ),
          ),
        ],
      );
    }

    return child;
  }
}

/// Immutable basis captured once for a system control in world space.
class _WorldLockedBasis {
  const _WorldLockedBasis({
    required this.center,
    required this.right,
    required this.up,
    required this.normal,
  });

  final vm.Vector3 center;
  final vm.Vector3 right;
  final vm.Vector3 up;
  final vm.Vector3 normal;

  factory _WorldLockedBasis.facing({
    required vm.Vector3 eye,
    required vm.Vector3 center,
  }) {
    final normal = eye - center;
    if (normal.length2 < 0.0001) normal.setValues(0, 0, 1);
    normal.normalize();
    final right = vm.Vector3(0, 1, 0).cross(normal);
    if (right.length2 < 0.0001) right.setValues(1, 0, 0);
    right.normalize();
    final up = normal.cross(right)..normalize();
    return _WorldLockedBasis(
      center: center.clone(),
      right: right,
      up: up,
      normal: normal,
    );
  }

  vm.Matrix4 transformAt(double x, double y, double z) {
    final origin = center + right * x + up * y + normal * z;
    return vm.Matrix4.identity()
      ..setColumn(0, vm.Vector4(right.x, right.y, right.z, 0))
      ..setColumn(1, vm.Vector4(up.x, up.y, up.z, 0))
      ..setColumn(2, vm.Vector4(normal.x, normal.y, normal.z, 0))
      ..setColumn(3, vm.Vector4(origin.x, origin.y, origin.z, 1));
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
    required this.stereoImageInset,
  }) : super(repaint: Listenable.merge([progress, zenithProgress]));

  final ValueNotifier<double> progress;
  final ValueNotifier<double> zenithProgress;
  final bool showDivider;
  final bool showReticle;
  final double stereoImageInset;

  void _drawReticle(
    Canvas canvas,
    Offset center,
    double p,
    Paint ring,
    Paint dot,
    Paint arc,
  ) {
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
      canvas.drawLine(Offset(dividerX, 0), Offset(dividerX, 16), tickPaint);
      canvas.drawLine(
        Offset(dividerX, size.height - 16),
        Offset(dividerX, size.height),
        tickPaint,
      );
    }

    // 2. Stereoscopic Gaze Reticles
    if (showReticle) {
      final insetPixels = size.width * 0.25 * stereoImageInset;
      final leftCenter = Offset(
        size.width * 0.25 + insetPixels,
        size.height * 0.5,
      );
      final rightCenter = Offset(
        size.width * 0.75 - insetPixels,
        size.height * 0.5,
      );
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
      final insetPixels = size.width * 0.25 * stereoImageInset;
      final leftZenith = Offset(
        size.width * 0.25 + insetPixels,
        size.height * 0.18,
      );
      final rightZenith = Offset(
        size.width * 0.75 - insetPixels,
        size.height * 0.18,
      );
      _drawZenithTarget(canvas, leftZenith, zp);
      _drawZenithTarget(canvas, rightZenith, zp);
    }
  }

  @override
  bool shouldRepaint(_ReticlePainter oldDelegate) => true;
}
