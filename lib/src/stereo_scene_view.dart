import 'dart:math';

import 'package:flutter/foundation.dart';
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
        VrSensorCapabilities,
        VrInputArbiter,
        VrInputEvent;
import 'package:vrlizate_widgets/vrlizate_widgets.dart'
    show VrButton3D, VrTextLabel;

import 'quality_preset.dart';
import 'vr_gpu_resource_gate.dart';
import 'simulated_hand_visuals.dart';
import 'stereo_head_rig.dart';
import 'vr_look.dart';
import 'vr_world_navigation_scope.dart';
import 'vr_input_session_scope.dart';
import 'vr_controller_feedback.dart';
import 'vr_controller_feedback_visuals.dart';
import 'vr_scene_input_controller.dart';
import 'vr_scene_pointer_interaction.dart';
import 'vr_viewer_profile.dart';
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
    this.onInteractionRay,
    this.locomotionEnabled = true,
    this.lookInputEnabled = true,
    this.onUnhandledTempleTap,
  });

  /// Reserved experimental OpenXR integration hook; currently unused.
  ///
  /// Supplying this does not bypass Canvas or activate native XR rendering.
  /// This widget still uses the ordinary flutter_scene stereo render path.
  final VrOpenXrSwapchainBridge? openXrBridge;

  /// Current controller ray (or head gaze), before demo listeners and per tick.
  /// The ray is reused: copy its vectors if retaining it for drag/input logic.
  final void Function(vm.Ray ray)? onInteractionRay;

  /// Disable for grid puzzles, seated experiences and vehicle-owned motion.
  final bool locomotionEnabled;

  /// Whether the look stick rotates the view; head tracking is unaffected.
  final bool lookInputEnabled;

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
  /// A shared [VrViewerProfileScope] overrides this value and the rig's FOV.
  final double? convergenceDistance;

  /// Interpupillary distance in meters (defaults to 0.064m / 64mm).
  /// An explicit value overrides the shared viewer profile's IPD.
  final double? ipd;

  /// Optical image-center correction. Positive values move both eye images
  /// inward without changing the virtual cameras' anatomical IPD.
  /// An explicit value overrides the shared viewer profile's inset.
  final double? stereoImageInset;

  /// Whether double-tapping on screen recenters the horizontal gaze heading.
  final bool doubleTapToRecenter;

  /// Whether looking straight up (~55° pitch) triggers hands-free recentering.
  final bool zenithRecenter;

  /// Whether physical tap on visor/temple triggers instant gaze select and double-tap recenters.
  final bool enableTempleTap;

  /// Called for a visor tap when this view has no actionable target. Retained
  /// game hosts can dispatch their primary action through the shared arbiter.
  /// The current interaction ray is published before this callback.
  final VoidCallback? onUnhandledTempleTap;

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
  State<StereoSceneView> createState() => _StereoSceneResourceGateState();
}

class _StereoSceneResourceGateState extends State<StereoSceneView> {
  @override
  Widget build(BuildContext context) => VrGpuResourceGate(
    onBack: VrWorldNavigationScope.maybeOf(context)?.onHome,
    builder: (_) => _ReadyStereoSceneView(configuration: widget),
  );
}

/// Do not start scene rendering, sensors or input listeners while resource
/// initialization has failed. Their existing lifecycle begins only on success.
class _ReadyStereoSceneView extends StatefulWidget {
  const _ReadyStereoSceneView({required this.configuration});
  final StereoSceneView configuration;

  @override
  State<_ReadyStereoSceneView> createState() => _StereoSceneViewState();
}

class _StereoSceneViewState extends State<_ReadyStereoSceneView> {
  StereoSceneView get view => widget.configuration;
  late final StereoHeadRig _rig =
      view.rig ??
      StereoHeadRig(
        ipd: view.ipd ?? CameraRig.defaultIpd,
        convergenceDistance: view.convergenceDistance,
      );
  late final HeadTracker _headTracker =
      view.headTracker ?? HeadTracker(target: _rig);
  late final GazePointer _gaze = GazePointer(
    cameraRig: _rig.cameraRig,
    dwellDuration: view.gazeDwellSeconds,
    enableHaptics: view.enableHaptics,
  );

  final Map<String, Node> _nodesByName = {};
  final _gazeLifecycle = VrSceneGazeLifecycle();
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
  late final VrSceneInputController _input = VrSceneInputController(
    rig: _rig,
    locomotionEnabled: view.locomotionEnabled,
    lookInputEnabled: view.lookInputEnabled,
    pick: _pickInputNode,
    activate: (node) {
      _activateGazeNode(node);
      if (view.enableHaptics) HapticFeedback.selectionClick();
    },
    recenter: () {
      _headTracker.recenter();
      _rig.recenter();
    },
    isSystemNode: (node) => node.name == _worldHomeNodeName,
  );
  final _PointerRepaint _pointerRepaint = _PointerRepaint();
  final vm.Vector3 _pointerPosition = vm.Vector3.zero();
  double _pointerDistance = 1.8;
  final VrScenePointerResolver _pointerResolver = VrScenePointerResolver();
  final VrSceneViewerProfileBinding _profileBinding =
      VrSceneViewerProfileBinding();
  VrViewerProfile? _viewerProfile;
  ValueListenable<VrControllerFeedbackState>? _feedbackSource;
  VrControllerFeedbackVisuals? _feedbackVisuals;
  Scene? _feedbackScene;
  final _PointerRepaint _feedbackRepaint = _PointerRepaint();
  bool _feedbackCreationFailed = false;

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
    view.scene.antiAliasingMode = preset.antiAliasing;
    view.scene.postProcess.bloom.enabled = preset.bloomEnabled;
    view.look?.applyToScene(view.scene, preset);
    view.onQualityChanged?.call(preset);
  }

  @override
  void initState() {
    super.initState();
    if (view.rig == null) {
      _rig.eyeCenter.setValues(0, 1.6, 0);
    }
    if (view.ipd != null) {
      _rig.ipd = view.ipd!;
    }
    if (view.stereoImageInset != null) {
      _rig.stereoImageInset = view.stereoImageInset!;
    }
    // Native desktop has no sensors_plus motion backend. Keep the tracker for
    // touch/recenter and preserve explicitly supplied custom sensor streams.
    if (_headTracker.canStart) _headTracker.start();

    // Zero-latency temple/visor tap trigger
    if (view.enableTempleTap && VrSensorCapabilities.supportsDeviceMotion) {
      _tapDetector = InertialTapDetector(
        onSingleTap: _handleTempleTap,
        onDoubleTap: () {
          _headTracker.recenter();
          _rig.recenter();
          if (view.enableHaptics) HapticFeedback.mediumImpact();
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
      } else {
        // Clear a prior app hover even when gaze was just disabled. This runs
        // from the input tick, never synchronously in didUpdateWidget.
        view.onGazeHoverChanged?.call(null);
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
      } else if (view.gazeEnabled) {
        view.onGazeHoverChanged?.call(node);
      }
    };

    if (view.enableHandTracking) {
      _handRig = SimulatedHandVisuals(view.scene.root, view.handGlowColor);
    }
  }

  SimulatedHandVisuals? _handRig;

  void _onArbiterEvent(VrInputEvent event) {
    if (!mounted) return;
    _input.handleEvent(event);
  }

  void _onSystemInputEvent(VrInputEvent event) {
    if (!mounted) return;
    _input.handleSystemEvent(event);
    view.onInteractionRay?.call(_input.ray);
  }

  void _updateActiveArbiter() {
    final nextArbiter = view.arbiter ?? VrInputSessionScope.arbiterOf(context);
    if (nextArbiter != _activeArbiter) {
      _activeArbiter?.removeListener(_onArbiterEvent);
      _activeArbiter?.removeListener(_onSystemInputEvent);
      _input.reset();
      _activeArbiter = nextArbiter;
      _activeArbiter?.addListener(_onSystemInputEvent, first: true);
      _activeArbiter?.addListener(_onArbiterEvent);
    }
  }

  void _updateFeedbackSource() {
    final next = VrControllerFeedbackScope.maybeOf(context)?.state;
    if (identical(next, _feedbackSource)) return;
    _feedbackSource?.removeListener(_onFeedbackChanged);
    _feedbackSource = next;
    _feedbackCreationFailed = false;
    if (next == null) {
      _feedbackVisuals?.dispose();
      _feedbackVisuals = null;
      _feedbackScene = null;
      _feedbackRepaint.markDirty();
      return;
    }
    next.addListener(_onFeedbackChanged);
    _onFeedbackChanged();
  }

  void _onFeedbackChanged() {
    if (!mounted) return;
    final feedback = _feedbackSource?.value;
    if (feedback == null) return;
    // Do not allocate GPU assets for views that never use a remote controller.
    if (_feedbackVisuals == null &&
        feedback.shown &&
        !_feedbackCreationFailed) {
      try {
        // An independent GPU scene owns independent color/depth targets.
        // Its alpha-transparent output is composed after the world. Merely
        // disabling picking on a world node cannot prevent floor occlusion.
        final overlay = Scene()
          ..skybox = null
          ..environment = EnvironmentMap.empty()
          ..toneMapping = ToneMappingMode.linear
          ..antiAliasingMode = AntiAliasingMode.none;
        final visuals = VrControllerFeedbackVisuals(overlay.root);
        _feedbackScene = overlay;
        _feedbackVisuals = visuals;
        visuals.ready.catchError((Object error, StackTrace stack) {
          if (mounted && identical(_feedbackVisuals, visuals)) {
            debugPrint(
              'Controller feedback labels unavailable: $error\n$stack',
            );
          }
        });
      } catch (error, stack) {
        _feedbackCreationFailed = true;
        debugPrint('Controller feedback unavailable: $error\n$stack');
        return;
      }
    }
    _feedbackVisuals?.setState(feedback);
    _feedbackVisuals?.updatePose(_rig);
    _feedbackRepaint.markDirty();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateActiveArbiter();
    _updateFeedbackSource();
    final profile = VrViewerProfileScope.maybeOf(context)?.profile;
    if (profile != _viewerProfile) {
      _viewerProfile = profile;
      _applyViewerProfile();
    }
    final next = VrWorldNavigationScope.maybeOf(context);
    if (next?.onHome != _worldNavigation?.onHome ||
        next?.homeLabel != _worldNavigation?.homeLabel) {
      _removeWorldHome();
      _worldNavigation = next;
    }
  }

  void _applyViewerProfile() => _profileBinding.apply(
    _rig,
    _viewerProfile,
    explicitIpd: view.ipd,
    explicitInset: view.stereoImageInset,
  );

  @override
  void didUpdateWidget(covariant _ReadyStereoSceneView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final previous = oldWidget.configuration;
    if (!identical(previous.scene, view.scene)) {
      _feedbackVisuals?.dispose();
      _feedbackVisuals = null;
      _feedbackScene = null;
      _feedbackCreationFailed = false;
      _onFeedbackChanged();
    }
    _gazeLifecycle.configurationChanged(
      previousGazeEnabled: previous.gazeEnabled,
      gazeEnabled: view.gazeEnabled,
    );
    _input.locomotionEnabled = view.locomotionEnabled;
    _input.lookInputEnabled = view.lookInputEnabled;
    if (view.arbiter != previous.arbiter) {
      _updateActiveArbiter();
    }
    if (view.quality != previous.quality && view.quality != null) {
      _applyPreset(view.quality!);
    }
    if (view.ipd != previous.ipd && view.ipd != null) {
      _rig.ipd = view.ipd!;
    }
    if (view.stereoImageInset != previous.stereoImageInset &&
        view.stereoImageInset != null) {
      _rig.stereoImageInset = view.stereoImageInset!;
    }
    if (_viewerProfile == null &&
        view.convergenceDistance != previous.convergenceDistance) {
      _rig.convergenceDistance = view.convergenceDistance;
    }
    if (view.ipd != previous.ipd ||
        view.stereoImageInset != previous.stereoImageInset) {
      _applyViewerProfile();
    }
    if (view.look != previous.look && view.look != null) {
      view.look!.applyToScene(view.scene, _preset ?? VrQualityPreset.medium);
    }
  }

  @override
  void dispose() {
    _feedbackSource?.removeListener(_onFeedbackChanged);
    _feedbackSource = null;
    _feedbackVisuals?.dispose();
    _feedbackVisuals = null;
    _feedbackScene = null;
    _feedbackRepaint.dispose();
    _activeArbiter?.removeListener(_onArbiterEvent);
    _activeArbiter?.removeListener(_onSystemInputEvent);
    _activeArbiter = null;
    _input.reset();
    _removeWorldHome();
    _handRig?.dispose();
    _tapDetector?.dispose();
    if (view.headTracker == null) _headTracker.stop();
    _dwellProgress.dispose();
    _zenithProgress.dispose();
    _pointerRepaint.dispose();
    super.dispose();
  }

  void _tick(Duration elapsed, double dt) {
    final systemGazeEnabled = _worldNavigation != null;
    _gazeLifecycle.beforeTick(
      _gaze,
      gazeEnabled: view.gazeEnabled,
      systemGazeEnabled: systemGazeEnabled,
    );
    final hadPointer = _input.pointerActive;
    _input.update(dt);
    view.onInteractionRay?.call(_input.ray);
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
    if (view.zenithRecenter) {
      if (_rig.cameraRig.pitch > 0.95) {
        _zenithTimer += dt;
        _zenithProgress.value = (_zenithTimer / 0.8).clamp(0.0, 1.0);
        if (_zenithTimer >= 0.8 && !_zenithTriggered) {
          _zenithTriggered = true;
          _headTracker.recenter();
          _rig.recenter();
          if (view.enableHaptics) {
            HapticFeedback.mediumImpact();
          }
        }
      } else {
        _zenithTimer = 0;
        _zenithTriggered = false;
        if (_zenithProgress.value != 0) _zenithProgress.value = 0;
      }
    }

    if (view.gazeEnabled || systemGazeEnabled) {
      final ray = _input.ray;
      final node = _pickInputNode(ray);
      if (_input.pointerActive) {
        _pointerPosition.setFrom(ray.direction);
        _pointerPosition.scale(_pointerDistance);
        _pointerPosition.add(ray.origin);
      }
      String? id;
      if (node != null && node.name.isNotEmpty) {
        id = node.name;
        _nodesByName[id] = node;
      }
      _gaze.update(
        dt,
        id,
        dwellEnabled:
            !_input.pointerActive &&
            !(_activeArbiter?.isGazeSuppressed ?? false),
      );
    }
    if (_input.pointerActive || hadPointer) _pointerRepaint.markDirty();
    view.onTick?.call(elapsed, dt);
    // Vehicle demos may update bodyYaw and eye position in their onTick.
    final hadFeedback = _feedbackVisuals?.root.visible ?? false;
    _feedbackVisuals?.updatePose(_rig);
    final hasFeedback = _feedbackVisuals?.root.visible ?? false;
    if (hadFeedback || hasFeedback) {
      _feedbackRepaint.markDirty();
    }
  }

  void _handleTempleTap() {
    if (!mounted) return;
    view.onInteractionRay?.call(_input.ray);
    dispatchVrSceneTempleTap(
      pick: () => _pickInputNode(_input.ray),
      arbiter: _activeArbiter,
      onUnhandled: view.onUnhandledTempleTap,
      activate: (node) {
        _activateGazeNode(node);
        if (view.enableHaptics) HapticFeedback.selectionClick();
      },
    );
  }

  Node? _pickInputNode(vm.Ray ray) {
    final homeCenter = _worldHomeCenter;
    var aimingAtHome = false;
    if (_worldNavigation != null && homeCenter != null) {
      final toHome = homeCenter - ray.origin;
      if (toHome.length2 > 0.0001) {
        toHome.normalize();
        aimingAtHome = toHome.dot(ray.direction) > 0.96;
      }
    }
    final systemHit = aimingAtHome
        ? view.scene.raycast(
            ray,
            where: (node) => node.name == _worldHomeNodeName,
          )
        : null;
    final target = _pointerResolver.resolve(
      systemHit: systemHit,
      gazeEnabled: view.gazeEnabled,
      pointerActive: _input.pointerActive,
      fallbackDistance: _rig.convergenceDistance ?? 1.8,
      pickSelectable: () => view.scene.raycast(
        ray,
        where: (node) =>
            node.name.isNotEmpty &&
            !node.name.startsWith(VrControllerFeedbackVisuals.nodePrefix) &&
            node.name != _worldHomeNodeName &&
            (view.gazeFilter?.call(node) ?? true),
      ),
      pickGeometry: () => view.scene.raycast(
        ray,
        where: (node) =>
            !node.name.startsWith(VrControllerFeedbackVisuals.nodePrefix) &&
            node.name != _worldHomeNodeName &&
            (view.gazeFilter?.call(node) ?? true),
      ),
    );
    _pointerDistance = _pointerResolver.distance;
    return target;
  }

  void _activateGazeNode(Node node) {
    if (node.name == _worldHomeNodeName) {
      _worldHomeButton?.onSelect(_worldHomeNodeName);
      return;
    }
    if (view.gazeEnabled) view.onGazeSelect?.call(node);
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
        view.scene.add(node);
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
      if (node.parent != null) view.scene.remove(node);
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
    if (!view.dynamicScaling || _preset == null) return;
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
    final preset = _preset ?? VrQualityPreset.resolve(context, view.quality);
    if (_preset == null) _applyPreset(preset);
    final dpr = MediaQuery.devicePixelRatioOf(context);

    Widget child = SceneView(
      view.scene,
      viewsBuilder: (_) => _rig.buildStereoViews(),
      pixelRatio: dpr * preset.pixelRatioScale,
      onTick: _tick,
    );

    if (view.touchFallback || view.doubleTapToRecenter) {
      child = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate: view.touchFallback
            ? (d) => _headTracker.applyTouchDelta(d.delta.dx, d.delta.dy)
            : null,
        onDoubleTap: view.doubleTapToRecenter
            ? () {
                _headTracker.recenter();
                _rig.recenter();
                if (view.enableHaptics) {
                  HapticFeedback.mediumImpact();
                }
              }
            : null,
        child: child,
      );
    }

    child = Stack(
      fit: StackFit.expand,
      children: [
        child,
        IgnorePointer(
          child: CustomPaint(
            willChange: true,
            painter: VrControllerFeedbackPainter(
              repaint: _feedbackRepaint,
              rig: _rig,
              render: () => _feedbackScene?.renderViews,
              visible: () => _feedbackVisuals?.root.visible ?? false,
              // This small unlit model does not need the main scene's full
              // high-DPI resolve buffers or MSAA on memory-limited phones.
              pixelRatio: min(dpr * preset.pixelRatioScale, 1.5),
            ),
          ),
        ),
      ],
    );

    final effectiveGaze = view.gazeEnabled || _worldNavigation != null;
    if ((view.showReticle && effectiveGaze) ||
        view.showAlignmentDivider ||
        view.zenithRecenter) {
      child = Stack(
        fit: StackFit.expand,
        children: [
          child,
          IgnorePointer(
            child: CustomPaint(
              painter: _ReticlePainter(
                progress: _dwellProgress,
                zenithProgress: _zenithProgress,
                showDivider: view.showAlignmentDivider,
                showReticle: view.showReticle && effectiveGaze,
                stereoImageInset: _rig.stereoImageInset,
                pointerRepaint: _pointerRepaint,
                pointerPosition: () =>
                    _input.pointerActive ? _pointerPosition : null,
                rig: _rig,
              ),
            ),
          ),
        ],
      );
    }

    return child;
  }
}

class _PointerRepaint extends ChangeNotifier {
  void markDirty() => notifyListeners();
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
    required Listenable pointerRepaint,
    required this.pointerPosition,
    required this.rig,
  }) : super(
         repaint: Listenable.merge([progress, zenithProgress, pointerRepaint]),
       );

  final ValueNotifier<double> progress;
  final ValueNotifier<double> zenithProgress;
  final bool showDivider;
  final bool showReticle;
  final double stereoImageInset;
  final vm.Vector3? Function() pointerPosition;
  final StereoHeadRig rig;

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
      var leftCenter = Offset(
        size.width * 0.25 + insetPixels,
        size.height * 0.5,
      );
      var rightCenter = Offset(
        size.width * 0.75 - insetPixels,
        size.height * 0.5,
      );
      final pointer = pointerPosition();
      if (pointer != null) {
        final eyeSize = Size(size.width / 2, size.height);
        final left = rig
            .eyeCamera(StereoEye.left)
            .worldToScreen(pointer, eyeSize);
        final right = rig
            .eyeCamera(StereoEye.right)
            .worldToScreen(pointer, eyeSize);
        if (left == null || right == null) return;
        leftCenter = left;
        rightCenter = right + Offset(size.width / 2, 0);
      }
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
