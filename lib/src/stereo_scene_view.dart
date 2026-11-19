import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show DeviceOrientation, HapticFeedback, SystemChrome, SystemUiMode;
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;
import 'package:vrlizate/vrlizate.dart'
    show
        CameraRig,
        GazePointer,
        HeadTracker,
        RotationTarget,
        InertialTapDetector,
        VrSensorCapabilities,
        VrInputArbiter,
        VrInputEvent,
        VrInputSource,
        VrInputType;
import 'package:vrlizate_widgets/vrlizate_widgets.dart'
    show VrButton3D, VrTextLabel;

import 'pbr_texture_library.dart';
import 'quality_preset.dart';
import 'vr_ktx2_texture.dart';
import 'vr_device_performance.dart';
import 'vr_fixed_foveation.dart';
import 'vr_frame_quality.dart';
import 'vr_gpu_resource_gate.dart';
import 'simulated_hand_visuals.dart';
import 'stereo_head_rig.dart';
import 'vr_spatial_tracking.dart';
import 'vr_look.dart';
import 'vr_world_navigation_scope.dart';
import 'vr_input_session_scope.dart';
import 'vr_controller_feedback.dart';
import 'vr_controller_feedback_visuals.dart';
import 'vr_scene_input_controller.dart';
import 'vr_scene_home_control_lifecycle.dart';
import 'vr_stereo_scene_layers.dart';
import 'vr_lens_warp_post_process.dart';
import 'vr_sgsr_upscale_post_process.dart';
import 'vr_graphics_comfort_settings.dart';
import 'stereo_hud_overlay.dart';
import 'vr_predictive_motion_culler.dart';
import 'vr_scene_pointer_interaction.dart';
import 'vr_viewer_profile.dart';
import 'vr_zenith_recenter.dart';
import '../utils/constants/vr_scene_constants.dart';
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
  /// Optional host hook fired whenever dynamic scaling steps down visual
  /// quality (or remains under pressure at [VrQualityTier.low]), allowing
  /// background co-processors (such as on-device AI weights) to evict RAM.
  static void Function(VrQualityPreset nextPreset)? onGlobalQualityStepDown;

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
    this.templeDoubleTapToRecenter = vrSceneDefaultTempleDoubleTapToRecenter,
    this.enableHandTracking = true,
    this.handGlowColor = const Color(0xFF00E5FF),
    this.gazeEnabled = true,
    this.enableHaptics = true,
    this.gazeDwellSeconds = VrSceneConstants.defaultGazeDwellSeconds,
    this.onGazeSelect,
    this.onGazeHoverChanged,
    this.gazeFilter,
    this.showReticle = true,
    this.showHomeControl = true,
    this.showControllerFeedback = true,
    this.quality,
    this.fixedFoveation,
    this.sgsrUpscale,
    this.dynamicScaling = true,
    this.targetRefreshRateHz,
    this.readThermalStatus,
    this.qualityContext,
    this.onQualityChanged,
    this.onTick,
    this.look,
    this.convergenceDistance = 1.8,
    this.arbiter,
    this.openXrBridge,
    this.onInteractionRay,
    this.locomotionEnabled = true,
    this.lookInputEnabled = true,
    this.edgeTurnEnabled = true,
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

  /// Face a sustained left-stick rim direction during smooth locomotion.
  /// Disable for experiences that assign their own meaning to the left stick.
  final bool edgeTurnEnabled;

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

  /// Whether looking straight up (more than ~55° above the horizon for 0.8 s)
  /// triggers hands-free recentering. Looking down never triggers it, so the
  /// downward-gaze controller feedback window is unaffected.
  final bool zenithRecenter;

  /// Whether a physical tap on the visor/temple triggers gaze selection.
  final bool enableTempleTap;

  /// Explicit opt-in for inertial double-tap recentering. Turning the head can
  /// produce acceleration peaks; those must not reset heading by default.
  /// Does not affect screen double taps or explicit controller commands.
  final bool templeDoubleTapToRecenter;

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
  ///
  /// Providing a custom tracker opts out of [VrSpatialTrackingScope]: its
  /// target ownership is external and must not compete with absolute VIO.
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

  /// Whether to add the renderer's floating, world-locked HOME button.
  /// Disable when the experience supplies its own in-world HOME action.
  /// Resource-loading/failure recovery still exposes the navigation back action.
  final bool showHomeControl;

  /// Whether to allocate and draw the controller's 3D status overlay.
  /// Input drivers, controller events and pointer interaction remain active.
  final bool showControllerFeedback;

  /// Quality preset; when null a conservative preset is selected.
  final VrQualityPreset? quality;

  /// Opt-in spatial foveation experiment: sharp center, lower-resolution
  /// periphery, both rendered in the SAME frame. Null keeps two uniform eyes.
  /// Uses four views and can cost more on geometry/shadow-bound scenes.
  /// See [VrFixedFoveation] for restrictions on screen-space effects.
  final VrFixedFoveation? fixedFoveation;

  /// Optional single-pass Qualcomm SGSR 1 (`BSD-3-Clause`) spatial upscaler.
  ///
  /// When active and supported by the Impeller shader backend, renders the 3D
  /// scene at `sgsrUpscale.internalRenderScale` (e.g. `0.75x`, cutting ~`43.8%`
  /// of shaded 3D fragments) and reconstructs edges to native DPR while keeping
  /// gaze reticles and controller overlays at crisp `1.0x` native resolution.
  final VrSgsrUpscaleConfig? sgsrUpscale;

  /// When true, sustained build/raster overruns reduce quality one tier.
  /// Monitoring pauses with the app lifecycle, disabled TickerMode, or a
  /// covering route (including non-opaque dialogs).
  final bool dynamicScaling;

  /// Intended render cadence for adaptive quality. Null uses the current
  /// display refresh rate (60 Hz only when the engine reports no valid rate).
  /// Set this when the app intentionally renders below the display cadence.
  /// This does not change the display mode or request an OS refresh rate.
  final double? targetRefreshRateHz;

  /// Optional fresh thermal severity reader using the Android 0–6 scale.
  /// Return null when no current reading is available. With adaptive quality
  /// enabled, thermal pressure can reduce quality, and cooling plus sustained
  /// frame headroom can restore it up to the requested preset.
  final Future<int?> Function()? readThermalStatus;

  /// Change this value when replacing content within a retained [scene].
  /// The new workload starts with fresh frame and thermal evidence.
  final Object? qualityContext;

  /// Called when the effective preset changes or is applied to a new scene.
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

/// A stable HeadTracker target, so changing scopes never starts a second IMU
/// backend. Spatial tracking observes the IMU for fallback without adding it to
/// a currently measured camera orientation.
class _SpatialRotationTarget implements RotationTarget {
  _SpatialRotationTarget(this.rig);
  final StereoHeadRig rig;
  VrSpatialTrackingController? spatial;
  RotationTarget get target => spatial ?? rig;
  @override
  void rotate(double yaw, double pitch) => target.rotate(yaw, pitch);
  @override
  void setOrientation(double yaw, double pitch) =>
      target.setOrientation(yaw, pitch);
  @override
  void setPitch(double pitch) => target.setPitch(pitch);
  @override
  void recenter() => target.recenter();
  @override
  void reset() => target.reset();
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

class _StereoSceneViewState extends State<_ReadyStereoSceneView>
    with WidgetsBindingObserver {
  StereoSceneView get view => widget.configuration;
  late final StereoHeadRig _rig =
      view.rig ??
      StereoHeadRig(
        ipd: view.ipd ?? CameraRig.defaultIpd,
        convergenceDistance: view.convergenceDistance,
      );
  late final HeadTracker _headTracker =
      view.headTracker ?? HeadTracker(target: _rotationTarget);
  late final _SpatialRotationTarget _rotationTarget = _SpatialRotationTarget(
    _rig,
  );
  VrSpatialTrackingController? _spatial;
  VrSpatialTrackingScope? _spatialScope;
  VrSceneRigSpatialBridge? _spatialBridge;
  final _spatialEyeCenter = vm.Vector3.zero();
  VrSceneHandPoseBridge? _handBridge;
  bool _beaconHandPointingWasActive = false;
  bool _beaconHandPinchWasDown = false;
  final Map<String, dynamic> _beaconHandPointerPayload = <String, dynamic>{};
  bool _ownedHeadTrackerStarted = false;
  bool _appResumed =
      WidgetsBinding.instance.lifecycleState == null ||
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
  late final GazePointer _gaze = GazePointer(
    cameraRig: _rig.cameraRig,
    dwellDuration: view.gazeDwellSeconds,
    enableHaptics: view.enableHaptics,
  );

  final Map<String, Node> _nodesByName = {};
  final _gazeLifecycle = VrSceneGazeLifecycle();
  bool _sgsrShaderReady = false;

  void _onSgsrShaderReadyChanged(bool ready) {
    if (_sgsrShaderReady == ready || !mounted) return;
    setState(() => _sgsrShaderReady = ready);
  }
  final ValueNotifier<double> _dwellProgress = ValueNotifier(0);
  final ValueNotifier<double> _zenithProgress = ValueNotifier(0);
  final ValueNotifier<double> _comfortVignetteAlpha = ValueNotifier(0);
  double _lastMotionYaw = 0.0;
  final vm.Vector3 _lastMotionEye = vm.Vector3.zero();
  bool _hasMotionSample = false;
  int _perfFrameCount = 0;
  double _perfAccumSec = 0.0;
  final VrZenithRecenterDetector _zenith = VrZenithRecenterDetector();

  InertialTapDetector? _tapDetector;
  VrQualityPreset? _preset;
  VrQualityPreset? _requestedPreset;
  VrWorldNavigationScope? _worldNavigation;
  bool get _systemGazeEnabled =>
      view.showHomeControl && _worldNavigation != null;
  VrButton3D? _worldHomeButton;
  vm.Vector3? _worldHomeCenter;
  List<Node> _worldHomeNodes = const [];
  late final _worldHomeLifecycle = VrSceneHomeControlLifecycle(
    enabled: view.showHomeControl,
  );

  static const String _worldHomeNodeName = '__vrlizate_system_home__';
  VrInputArbiter? _activeArbiter;
  late final VrSceneInputController _input = VrSceneInputController(
    rig: _rig,
    locomotionEnabled: view.locomotionEnabled,
    lookInputEnabled: view.lookInputEnabled,
    edgeTurnEnabled: view.edgeTurnEnabled,
    pick: _pickInputNode,
    activate: (node) {
      _activateGazeNode(node);
      if (view.enableHaptics) HapticFeedback.selectionClick();
    },
    recenter: _recenter,
    isSystemNode: (node) => node.name == _worldHomeNodeName,
  );
  final _PointerRepaint _pointerRepaint = _PointerRepaint();
  final vm.Vector3 _pointerPosition = vm.Vector3.zero();
  double _pointerDistance = 1.8;
  final VrScenePointerResolver _pointerResolver = VrScenePointerResolver();
  final vm.Vector3 _lastGeometryRayOrigin = vm.Vector3.zero();
  final vm.Vector3 _lastGeometryRayDir = vm.Vector3(0, 0, -1);
  SceneRaycastHit? _cachedGeometryHit;
  bool _hasGeometryRayCache = false;
  int _geometryPickAgeFrames = 0;
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

  final _qualityPolicy = VrFrameQualityPolicy();
  final _predictiveCuller = VrPredictiveMotionCuller();
  late final _qualityMonitor = VrFrameQualityMonitor(
    policy: _qualityPolicy,
    onPressure: _reduceQuality,
    onRecovery: _recoverQuality,
  );
  late final vm.Vector3? Function() _readPointerPosition = () =>
      _input.pointerActive ? _pointerPosition : null;
  late final bool Function() _readGazeSuppressed = () =>
      _activeArbiter?.isGazeSuppressed ?? false;
  bool _lastGazeSuppressed = false;

  void _applyPreset(VrQualityPreset preset) {
    _preset = preset;
    PbrTextureLibrary.defaultQualityTier = preset.tier;
    _qualityPolicy.reset();
    _qualityMonitor.resetThermalEvidence();
    view.scene.antiAliasingMode = preset.antiAliasing;
    view.scene.postProcess.bloom.enabled = preset.bloomEnabled;
    view.look?.applyToScene(view.scene, preset);
    view.onQualityChanged?.call(preset);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
    // Preserve custom tracker ownership. Owned trackers are gated by route,
    // TickerMode and lifecycle in didChangeDependencies below.
    if (view.headTracker != null && _headTracker.canStart) _headTracker.start();

    _syncTempleTapDetector();

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
    vrHandheldConsoleMode.addListener(_onDisplayModeChanged);
    VrGraphicsComfortSettings.instance.addListener(_onGraphicsSettingsChanged);
    _enforceImmersiveLandscape();
  }

  void _enforceImmersiveLandscape() {
    if (kIsWeb) return;
    if (defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS) {
      return;
    }
    if (WidgetsBinding.instance.runtimeType.toString().contains('Test')) {
      return;
    }
    unawaited(
      SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]),
    );
    unawaited(
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky),
    );
  }

  void _onDisplayModeChanged() {
    if (!mounted) return;
    _enforceImmersiveLandscape();
    _syncSpatialTracking();
    final base = _requestedPreset ?? _preset;
    if (base != null) {
      final resolved = VrGraphicsComfortSettings.instance.resolvePreset(
        base,
        isHandheldMono: vrHandheldConsoleMode.value,
      );
      if (resolved != _preset) _applyPreset(resolved);
    }
    setState(() {});
  }

  void _onGraphicsSettingsChanged() {
    if (!mounted) return;
    final settings = VrGraphicsComfortSettings.instance;
    if (!settings.comfortVignetteEnabled && _comfortVignetteAlpha.value != 0) {
      _comfortVignetteAlpha.value = 0.0;
    }
    final base = _requestedPreset ?? _preset;
    if (base != null) {
      final resolved = settings.resolvePreset(
        base,
        isHandheldMono: vrHandheldConsoleMode.value,
      );
      if (resolved != _preset) {
        _applyPreset(resolved);
      }
    }
    _syncSpatialTracking();
    setState(() {});
  }

  SimulatedHandVisuals? _handRig;

  void _onArbiterEvent(VrInputEvent event) {
    if (!mounted || !_sceneActive) return;
    _input.handleEvent(event);
  }

  void _onSystemInputEvent(VrInputEvent event) {
    if (!mounted || !_sceneActive) return;
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
    final next = view.showControllerFeedback
        ? VrControllerFeedbackScope.maybeOf(context)?.state
        : null;
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
    if (!mounted || !view.showControllerFeedback) return;
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
    _syncSpatialTracking();
    _syncQualityMonitoring();
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
    final sceneChanged = !identical(previous.scene, view.scene);
    if (sceneChanged || previous.qualityContext != view.qualityContext) {
      _qualityPolicy.reset();
      _qualityMonitor.resetThermalEvidence();
    }
    if (previous.enableTempleTap != view.enableTempleTap ||
        previous.templeDoubleTapToRecenter != view.templeDoubleTapToRecenter) {
      _syncTempleTapDetector();
    }
    if (previous.showHomeControl != view.showHomeControl || sceneChanged) {
      _worldHomeLifecycle.setEnabled(view.showHomeControl);
      _removeWorldHome();
    }
    if (sceneChanged) {
      _hasGeometryRayCache = false;
      _cachedGeometryHit = null;
      _handRig?.dispose();
      _handRig = (view.enableHandTracking || _handBridge != null)
          ? SimulatedHandVisuals(
              view.scene.root,
              view.handGlowColor,
              hideWhenUntracked: !view.enableHandTracking,
            )
          : null;
      _feedbackVisuals?.dispose();
      _feedbackVisuals = null;
      _feedbackScene = null;
      _feedbackCreationFailed = false;
      _onFeedbackChanged();
    }
    if (previous.showControllerFeedback != view.showControllerFeedback) {
      _updateFeedbackSource();
    }
    _gazeLifecycle.configurationChanged(
      previousGazeEnabled: previous.gazeEnabled,
      gazeEnabled: view.gazeEnabled,
    );
    _input.locomotionEnabled = view.locomotionEnabled;
    _input.lookInputEnabled = view.lookInputEnabled;
    _input.edgeTurnEnabled = view.edgeTurnEnabled;
    if (view.arbiter != previous.arbiter) {
      _updateActiveArbiter();
    }
    if (view.quality != previous.quality) {
      final requested = VrDevicePerformanceScope.initialPresetOf(
        context,
        explicitQuality: view.quality,
      );
      _requestedPreset = requested;
      _applyPreset(requested);
    } else if (sceneChanged && _preset != null) {
      _applyPreset(_preset!);
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
    _syncQualityMonitoring();
    _syncSpatialTracking();
  }

  void _recenter() {
    _input.reset();
    _predictiveCuller.reset();
    _headTracker.recenter();
    // Owned trackers reach the rig through the proxy, exactly once. An
    // external tracker may have an unrelated target and retains legacy use.
    if (view.headTracker != null) _rig.recenter();
  }

  void _syncTempleTapDetector() {
    // Dispose first so a deferred tap from a former opt-in cannot recenter
    // after the option is disabled or the selection callback is replaced.
    _tapDetector?.dispose();
    _tapDetector = null;
    if (!view.enableTempleTap || !VrSensorCapabilities.supportsDeviceMotion)
      return;
    final detector = InertialTapDetector();
    configureVrSceneTempleTapCallbacks(
      detector,
      doubleTapToRecenter: view.templeDoubleTapToRecenter,
      select: _handleTempleTap,
      recenter: () {
        if (!mounted || !_sceneActive) return;
        _recenter();
        if (view.enableHaptics) HapticFeedback.mediumImpact();
      },
    );
    _tapDetector = detector..start();
  }

  bool _sceneActive = false;

  void _syncSpatialTracking() {
    final scope = VrSpatialTrackingScope.maybeOf(context);
    _spatialBridge = scope?.source is VrSceneRigSpatialBridge
        ? scope!.source as VrSceneRigSpatialBridge
        : null;
    _handBridge = scope?.source is VrSceneHandPoseBridge
        ? scope!.source as VrSceneHandPoseBridge
        : null;
    if (_handBridge != null && _handRig == null) {
      _handRig = SimulatedHandVisuals(
        view.scene.root,
        view.handGlowColor,
        hideWhenUntracked: !view.enableHandTracking,
      );
    } else if (_handRig != null) {
      _handRig!.hideWhenUntracked = !view.enableHandTracking;
    }
    final sceneActive =
        _appResumed &&
        TickerMode.valuesOf(context).enabled &&
        (ModalRoute.isCurrentOf(context) ?? true);
    if (!sceneActive) _input.reset();
    if (sceneActive && !_sceneActive) {
      _enforceImmersiveLandscape();
    }
    _sceneActive = sceneActive;
    if (view.headTracker == null) {
      final allowGyroInHandheld =
          VrGraphicsComfortSettings.instance.handheldGyroAimEnabled;
      final shouldTrackHead =
          sceneActive && (!vrHandheldConsoleMode.value || allowGyroInHandheld);
      if (shouldTrackHead &&
          !_ownedHeadTrackerStarted &&
          _headTracker.canStart) {
        _headTracker.start();
        _ownedHeadTrackerStarted = true;
      } else if (!shouldTrackHead && _ownedHeadTrackerStarted) {
        _headTracker.stop();
        _ownedHeadTrackerStarted = false;
      }
      if (vrHandheldConsoleMode.value && !allowGyroInHandheld) {
        _rig.setPitch(0.0);
      }
    }
    final active =
        scope != null &&
        scope.enabled &&
        view.headTracker == null &&
        sceneActive &&
        !vrHandheldConsoleMode.value;
    final previous = _spatialScope;
    if (active &&
        _spatial != null &&
        identical(previous?.source, scope.source) &&
        previous?.cameraToEyeTranslation == scope.cameraToEyeTranslation &&
        previous?.cameraToEyeRotation == scope.cameraToEyeRotation) {
      return;
    }
    _rotationTarget.spatial = null;
    final old = _spatial;
    _spatial = null;
    _spatialScope = null;
    if (old != null) unawaited(old.detach());
    if (!active) return;
    final controller = VrSpatialTrackingController(
      rig: _rig,
      source: scope.source,
      cameraToEyeTranslation: scope.cameraToEyeTranslation,
      cameraToEyeRotation: scope.cameraToEyeRotation,
    );
    _spatial = controller;
    _spatialScope = scope;
    _rotationTarget.spatial = controller;
    unawaited(controller.attach());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appResumed = state == AppLifecycleState.resumed;
    if (mounted) _syncSpatialTracking();
  }

  @override
  void dispose() {
    vrHandheldConsoleMode.removeListener(_onDisplayModeChanged);
    VrGraphicsComfortSettings.instance.removeListener(
      _onGraphicsSettingsChanged,
    );
    WidgetsBinding.instance.removeObserver(this);
    _rotationTarget.spatial = null;
    final spatial = _spatial;
    _spatial = null;
    if (spatial != null) unawaited(spatial.detach());
    _qualityMonitor.dispose();
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
    _comfortVignetteAlpha.dispose();
    _pointerRepaint.dispose();
    super.dispose();
  }

  void _tick(Duration elapsed, double dt) {
    if (!_sceneActive) return;
    _spatial?.tick();
    final systemGazeEnabled = _systemGazeEnabled;
    _gazeLifecycle.beforeTick(
      _gaze,
      gazeEnabled: view.gazeEnabled,
      systemGazeEnabled: systemGazeEnabled,
    );
    final hadPointer = _input.pointerActive;
    _input.update(dt);
    final spatialBridge = _spatialBridge;
    if (spatialBridge != null) {
      final nativeVioActive = _spatial?.isTracking ?? false;
      final verticalOffset = _rig.locomotionVerticalOffset;
      final trackedEyeCenter = verticalOffset == 0
          ? _rig.eyeCenter
          : (_spatialEyeCenter
              ..setFrom(_rig.eyeCenter)
              ..y -= verticalOffset);
      final physicalDelta = spatialBridge.syncRigPoseAndSampleLocomotion(
        rigEyeCenter: trackedEyeCenter,
        rigYaw: _rig.yaw,
        rigBodyYaw: _rig.bodyYaw,
        rigPitch: _rig.pitch,
        dtSeconds: dt,
        nativeVioTracking: nativeVioActive,
      );
      if (!nativeVioActive && physicalDelta.length2 > 1e-9) {
        _rig.eyeCenter.x += physicalDelta.x;
        _rig.eyeCenter.z += physicalDelta.z;
        if (physicalDelta.y.abs() > 1e-4) {
          final trackedHeight = trackedEyeCenter.y + physicalDelta.y;
          _rig.eyeCenter.y = trackedHeight.clamp(0.85, 2.15) + verticalOffset;
        }
      }
    }
    view.onInteractionRay?.call(_input.ray);

    final t = elapsed.inMicroseconds / 1000000.0;
    if (t > 0.20 &&
        systemGazeEnabled &&
        _worldHomeButton == null &&
        !_worldHomeLifecycle.creating) {
      _createWorldHome();
    }
    _worldHomeButton?.update(dt);
    final trackedHands = _handBridge?.sampleTrackedHands();
    if (_handRig != null) {
      _handRig!.update(
        _rig.eyeCenter,
        _rig.cameraRig.rotation,
        t,
        trackedHands: trackedHands,
      );
    }
    _syncTrackedHandInteraction(trackedHands);

    // Hands-free zenith recenter (looking up > 55°). CameraRig pitch is
    // positive *downward* — the same convention the controller feedback's
    // 20°-from-feet window relies on — so the detector arms on the negative
    // side; the previous positive-side test fired while looking down at
    // that controller.
    if (view.zenithRecenter) {
      if (_zenith.update(_rig.pitch, dt)) {
        _recenter();
        if (view.enableHaptics) {
          HapticFeedback.mediumImpact();
        }
      }
      final progress = _zenith.progress;
      if (_zenithProgress.value != progress) _zenithProgress.value = progress;
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
      final gazeSuppressed = _activeArbiter?.isGazeSuppressed ?? false;
      if (gazeSuppressed != _lastGazeSuppressed) {
        _lastGazeSuppressed = gazeSuppressed;
        _pointerRepaint.markDirty();
      }
      if (gazeSuppressed && _dwellProgress.value != 0.0) {
        _dwellProgress.value = 0.0;
      }
      _gaze.update(
        dt,
        id,
        dwellEnabled: !_input.pointerActive && !gazeSuppressed,
      );
    }
    if (_input.pointerActive || hadPointer) _pointerRepaint.markDirty();
    view.onTick?.call(elapsed, dt);
    _predictiveCuller.update(
      forward: _rig.forward,
      screenRight: _rig.screenRight,
      up: _rig.up,
      eyeCenter: _rig.eyeCenter,
      dtSeconds: dt,
      fovRadiansY: _rig.cameraRig.fovY,
    );
    // Vehicle demos may update bodyYaw and eye position in their onTick.
    final hadFeedback = _feedbackVisuals?.root.visible ?? false;
    _feedbackVisuals?.updatePose(_rig);
    final hasFeedback = _feedbackVisuals?.root.visible ?? false;
    if (hadFeedback || hasFeedback) {
      _feedbackRepaint.markDirty();
    }

    // Dynamic anti-nausea peripheral comfort vignette (stereo VR only) &
    // optional 2 Hz live FPS telemetry when enabled in Settings.
    final gfxSettings = VrGraphicsComfortSettings.instance;
    final isStereo = !vrHandheldConsoleMode.value;
    if (dt > 1e-4 && dt.isFinite) {
      if (!_hasMotionSample) {
        _lastMotionYaw = _rig.yaw;
        _lastMotionEye.setFrom(_rig.eyeCenter);
        _hasMotionSample = true;
      } else {
        var dyaw = (_rig.yaw - _lastMotionYaw) % (2 * pi);
        if (dyaw > pi) dyaw -= 2 * pi;
        if (dyaw < -pi) dyaw += 2 * pi;
        final yawRate = dyaw.abs() / dt;
        final dx = _rig.eyeCenter.x - _lastMotionEye.x;
        final dz = _rig.eyeCenter.z - _lastMotionEye.z;
        final linSpeed = sqrt(dx * dx + dz * dz) / dt;
        _lastMotionYaw = _rig.yaw;
        _lastMotionEye.setFrom(_rig.eyeCenter);

        final targetAlpha = gfxSettings.computeComfortVignetteTarget(
          yawRateRadPerSec: yawRate,
          linearSpeedMetersPerSec: linSpeed,
          isStereo: isStereo,
        );
        final rate = targetAlpha > _comfortVignetteAlpha.value ? 10.0 : 5.5;
        final nextAlpha =
            _comfortVignetteAlpha.value +
            (targetAlpha - _comfortVignetteAlpha.value) *
                (1.0 - exp(-rate * dt));
        final snapped = nextAlpha < 0.008 ? 0.0 : nextAlpha;
        if ((snapped - _comfortVignetteAlpha.value).abs() > 0.004 ||
            (snapped == 0.0 && _comfortVignetteAlpha.value != 0.0)) {
          _comfortVignetteAlpha.value = snapped;
        }
      }

      if (gfxSettings.showPerformanceHud) {
        _perfFrameCount++;
        _perfAccumSec += dt;
        if (_perfAccumSec >= 0.5) {
          final fps = (_perfFrameCount / _perfAccumSec).clamp(1.0, 240.0);
          final frameMs = 1000.0 / fps;
          final activePreset = _preset ?? VrQualityPreset.medium;
          final sgsrCfg =
              view.sgsrUpscale ??
              gfxSettings.resolveSgsrConfig(activePreset, isStereo: isStereo);
          final effScale = (sgsrCfg.isActive && _sgsrShaderReady)
              ? sgsrCfg.internalRenderScale
              : 1.0;
          final texStats = VrKtx2TextureLoader.stats.value;
          final texTag = texStats.ktx2UploadedCount > 0
              ? texStats.hardwareFormatLabel
              : null;
          gfxSettings.publishTelemetry(
            VrLiveFrameMetrics(
              fps: fps,
              frameMs: frameMs,
              tier: activePreset.tier,
              sgsrScale: effScale,
              isStereo: isStereo,
              textureFormatTag: texTag,
            ),
          );
          _perfFrameCount = 0;
          _perfAccumSec = 0.0;
        }
      }
    }
  }

  void _syncTrackedHandInteraction(VrTrackedHandsSnapshot? trackedHands) {
    final pointing = trackedHands?.activePointingHand;
    // Never override an active higher-priority smartphone laser controller.
    final remotePhoneOwnsPointer =
        _input.pointerActive && !_beaconHandPointingWasActive;
    if (pointing == null || remotePhoneOwnsPointer) {
      if (_beaconHandPointingWasActive) {
        _beaconHandPointingWasActive = false;
        _beaconHandPinchWasDown = false;
        if (_activeArbiter != null) {
          _activeArbiter!.emit(
            type: VrInputType.pointerMove,
            source: VrInputSource.externalPeripheral,
            active: false,
          );
        } else {
          _input.state.handleEvent(
            VrInputEvent(
              type: VrInputType.pointerMove,
              source: VrInputSource.externalPeripheral,
              active: false,
            ),
          );
        }
      }
      return;
    }

    final rel = pointing.headRelativeMeters;
    final forwardDepth = (-rel.z).clamp(0.20, 1.25);
    _beaconHandPointerPayload['laserX'] = (rel.x / forwardDepth).clamp(
      -0.95,
      0.95,
    );
    _beaconHandPointerPayload['laserY'] = ((rel.y + 0.06) / forwardDepth).clamp(
      -0.95,
      0.95,
    );
    _beaconHandPointerPayload['relativeToHead'] = true;
    _beaconHandPointingWasActive = true;

    if (_activeArbiter != null) {
      _activeArbiter!.emit(
        type: VrInputType.pointerMove,
        source: VrInputSource.externalPeripheral,
        data: _beaconHandPointerPayload,
        active: true,
      );
    } else {
      _input.state.handleEvent(
        VrInputEvent(
          type: VrInputType.pointerMove,
          source: VrInputSource.externalPeripheral,
          data: _beaconHandPointerPayload,
          active: true,
        ),
      );
    }

    final pinching = pointing.isPinching;
    if (pinching && !_beaconHandPinchWasDown) {
      if (_activeArbiter != null) {
        _activeArbiter!.emit(
          type: VrInputType.select,
          source: VrInputSource.externalPeripheral,
        );
      } else {
        final node = _pickInputNode(_input.ray);
        if (node != null) {
          _activateGazeNode(node);
          if (view.enableHaptics) HapticFeedback.selectionClick();
        }
      }
    }
    _beaconHandPinchWasDown = pinching;
  }

  void _handleTempleTap() {
    if (!mounted || !_sceneActive) return;
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
    if (view.showHomeControl &&
        _worldNavigation != null &&
        homeCenter != null) {
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
      pickGeometry: () {
        if (_hasGeometryRayCache && _geometryPickAgeFrames < 3) {
          final dx = ray.origin.x - _lastGeometryRayOrigin.x;
          final dy = ray.origin.y - _lastGeometryRayOrigin.y;
          final dz = ray.origin.z - _lastGeometryRayOrigin.z;
          final originMoved2 = dx * dx + dy * dy + dz * dz;
          final dirCos = ray.direction.dot(_lastGeometryRayDir);
          if (originMoved2 <= 4e-6 && (1.0 - dirCos) <= 3.5e-6) {
            _geometryPickAgeFrames++;
            return _cachedGeometryHit;
          }
        }
        _lastGeometryRayOrigin.setFrom(ray.origin);
        _lastGeometryRayDir.setFrom(ray.direction);
        _geometryPickAgeFrames = 0;
        _hasGeometryRayCache = true;
        return _cachedGeometryHit = view.scene.raycast(
          ray,
          where: (node) =>
              !node.name.startsWith(VrControllerFeedbackVisuals.nodePrefix) &&
              node.name != _worldHomeNodeName &&
              (view.gazeFilter?.call(node) ?? true),
        );
      },
    );
    _pointerDistance = _pointerResolver.distance;
    return target;
  }

  void _activateGazeNode(Node node) {
    if (node.name == _worldHomeNodeName) {
      if (view.showHomeControl) {
        _worldHomeButton?.onSelect(_worldHomeNodeName);
      }
      return;
    }
    if (view.gazeEnabled) view.onGazeSelect?.call(node);
  }

  Future<void> _createWorldHome() async {
    final navigation = _worldNavigation;
    if (!view.showHomeControl || navigation == null || !mounted) return;
    final generation = _worldHomeLifecycle.begin();
    if (generation == null) return;
    final scene = view.scene;
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
          !view.showHomeControl ||
          !_worldHomeLifecycle.accepts(generation) ||
          !identical(scene, view.scene) ||
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
        scene.add(node);
      }
    } catch (error, stackTrace) {
      debugPrint('Could not create world HOME control: $error\n$stackTrace');
    } finally {
      _worldHomeLifecycle.finish(generation);
    }
  }

  void _removeWorldHome() {
    _worldHomeLifecycle.invalidate();
    if (_gaze.gazeTargetId == _worldHomeNodeName) {
      _gazeLifecycle.invalidateTarget();
    }
    for (final node in _worldHomeNodes) {
      // The configuration may already point at a replacement scene.
      node.parent?.remove(node);
    }
    _worldHomeNodes = const [];
    _worldHomeButton = null;
    _worldHomeCenter = null;
    _nodesByName.remove(_worldHomeNodeName);
  }

  @override
  void didChangeMetrics() {
    if (mounted) _syncQualityMonitoring();
  }

  void _syncQualityMonitoring() {
    final displayHz = View.of(context).display.refreshRate;
    final target =
        view.targetRefreshRateHz ??
        (displayHz.isFinite && displayHz > 0 ? displayHz : 60.0);
    if (_qualityPolicy.targetRefreshRateHz != target) {
      _qualityMonitor.resetThermalEvidence();
    }
    _qualityPolicy.targetRefreshRateHz = target;
    _qualityMonitor.setThermalStatusReader(view.readThermalStatus);
    _qualityMonitor.setActiveForContext(context, enabled: view.dynamicScaling);
  }

  void _reduceQuality() {
    final preset = _preset;
    if (!mounted || !view.dynamicScaling || preset == null) return;
    if (preset.tier == VrQualityTier.low) {
      StereoSceneView.onGlobalQualityStepDown?.call(preset);
      return;
    }
    final next = preset.stepDown;
    setState(() => _applyPreset(next));
    StereoSceneView.onGlobalQualityStepDown?.call(next);
  }

  void _recoverQuality() {
    final current = _preset;
    final requested = _requestedPreset;
    if (!mounted ||
        !view.dynamicScaling ||
        current == null ||
        requested == null ||
        current.tier.index >= requested.tier.index) {
      return;
    }
    final nextTier = current.tier.index + 1;
    // Descending from the ceiling preserves every custom budget. Returning
    // to the requested tier restores the exact object supplied by the host.
    var next = requested;
    while (next.tier.index > nextTier) {
      next = next.stepDown;
    }
    setState(() => _applyPreset(next));
  }

  @override
  Widget build(BuildContext context) {
    // The device catalog seeds a new scene only. Rebuilds retain any quality
    // reduction already selected by the frame monitor or an explicit override.
    final isHandheldMono = vrHandheldConsoleMode.value;
    final gfxSettings = VrGraphicsComfortSettings.instance;
    if (_preset == null) {
      final seeded = VrDevicePerformanceScope.initialPresetOf(
        context,
        explicitQuality: view.quality,
      );
      _requestedPreset = seeded;
      _applyPreset(
        gfxSettings.resolvePreset(seeded, isHandheldMono: isHandheldMono),
      );
    }
    final preset = _preset!;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final sgsrConfig =
        view.sgsrUpscale ??
        gfxSettings.resolveSgsrConfig(preset, isStereo: !isHandheldMono);
    final activeSgsrScale =
        (sgsrConfig.isActive && _sgsrShaderReady)
        ? sgsrConfig.internalRenderScale
        : 1.0;

    // Keep one stable SceneView and ticker even when the experiment is toggled.
    final scene = LayoutBuilder(
      builder: (context, constraints) => SceneView(
        view.scene,
        viewsBuilder: (_) {
          if (isHandheldMono) {
            return _rig.buildMonoViews();
          }
          final eyes = _rig.buildStereoViews();
          if (constraints.biggest.isEmpty) return eyes;
          final baseOpticalCenters = [
            Offset(0.5 + _rig.stereoImageInset / 2, 0.5),
            Offset(0.5 - _rig.stereoImageInset / 2, 0.5),
          ];
          final cullState = _predictiveCuller.state;
          final opticalCenters = _predictiveCuller.shiftOpticalCenters(
            baseOpticalCenters,
          );
          final foveation = view.fixedFoveation;
          if (foveation != null) {
            return foveation.buildViews(
              eyes,
              viewportSize: constraints.biggest,
              inheritedRenderScale: view.scene.renderScale,
              centers: opticalCenters,
            );
          }
          final profile = _viewerProfile;
          final baseW = profile?.activeLensWidthFraction ?? 1.0;
          final baseH = profile?.activeLensHeightFraction ?? 1.0;
          final effW = (baseW * cullState.saccadicScissorScale).clamp(
            0.45,
            1.0,
          );
          final effH = (baseH * cullState.saccadicScissorScale).clamp(
            0.45,
            1.0,
          );
          if (effW < 0.999 ||
              effH < 0.999 ||
              cullState.dynamicFarCullMeters != null) {
            final conv = _rig.convergenceDistance;
            final convClipShift =
                (conv != null && conv.isFinite && conv > 0.05)
                ? (_rig.ipd * 0.5 / conv)
                : 0.0;
            return VrFixedFoveation.cropStereoViewsToActiveLens(
              eyes,
              viewportSize: constraints.biggest,
              widthFraction: effW,
              heightFraction: effH,
              inheritedRenderScale: view.scene.renderScale,
              centers: opticalCenters,
              cullingPlanesBuilder: (eyeIndex, cropRect, fullEyeAspect) =>
                  VrPredictiveMotionCuller.buildPredictiveEyeCullingPlanes(
                    eyePosition: _rig.eyePosition(
                      eyeIndex == 0 ? StereoEye.left : StereoEye.right,
                    ),
                    forward: _rig.forward,
                    screenRight: _rig.screenRight,
                    up: _rig.up,
                    fovRadiansY: _rig.cameraRig.fovY,
                    fullEyeAspectRatio: fullEyeAspect,
                    normalizedCropRect: cropRect,
                    horizontalClipShift: _rig.stereoImageInset + convClipShift,
                    dynamicFarCullMeters: cullState.dynamicFarCullMeters,
                  ),
            );
          }
          return eyes;
        },
        pixelRatio: dpr * preset.pixelRatioScale * activeSgsrScale,
        onTick: _tick,
      ),
    );

    final effectiveGaze = view.gazeEnabled || _systemGazeEnabled;
    final baseStereoTree = VrLensWarpPostProcess(
      enabled: !isHandheldMono,
      profile: _viewerProfile,
      stereoImageInsetOverride: view.stereoImageInset,
      child: VrStereoSceneLayers(
        // Keep this wrapper even when both gestures are disabled. The viewport
        // and its captured native children must survive presentation changes.
        scene: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanUpdate: view.touchFallback
              ? (d) => _headTracker.applyTouchDelta(d.delta.dx, d.delta.dy)
              : null,
          onDoubleTap: view.doubleTapToRecenter
              ? () {
                  _recenter();
                  if (view.enableHaptics) {
                    HapticFeedback.mediumImpact();
                  }
                }
              : null,
          child: VrSgsrUpscalePostProcess(
            config: sgsrConfig,
            effectiveRenderScale: preset.pixelRatioScale * activeSgsrScale,
            stereoSplit: !isHandheldMono,
            onShaderReadyChanged: _onSgsrShaderReadyChanged,
            child: scene,
          ),
        ),
        controllerFeedback: view.showControllerFeedback && !isHandheldMono
            ? IgnorePointer(
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
              )
            : null,
        reticle:
            (view.showReticle && effectiveGaze) ||
                (view.showAlignmentDivider && !isHandheldMono) ||
                view.zenithRecenter
            ? RepaintBoundary(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _ReticlePainter(
                      progress: _dwellProgress,
                      zenithProgress: _zenithProgress,
                      showDivider: view.showAlignmentDivider && !isHandheldMono,
                      showReticle: view.showReticle && effectiveGaze,
                      mono: isHandheldMono,
                      stereoImageInset: _rig.stereoImageInset,
                      pointerRepaint: _pointerRepaint,
                      pointerPosition: _readPointerPosition,
                      isGazeSuppressed: _readGazeSuppressed,
                      rig: _rig,
                    ),
                  ),
                ),
              )
            : null,
      ),
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        baseStereoTree,
        if (!isHandheldMono && gfxSettings.comfortVignetteEnabled)
          IgnorePointer(
            child: ValueListenableBuilder<double>(
              valueListenable: _comfortVignetteAlpha,
              builder: (context, alpha, _) {
                if (alpha <= 0.01) return const SizedBox.shrink();
                return StereoHudOverlay(
                  alignment: Alignment.center,
                  padding: EdgeInsets.zero,
                  child: SizedBox.expand(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          radius: 0.88,
                          stops: const [0.46, 0.78, 1.0],
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: alpha * 0.55),
                            Colors.black.withValues(alpha: alpha),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        if (gfxSettings.showPerformanceHud)
          IgnorePointer(
            child: StereoHudOverlay(
              alignment: Alignment.topCenter,
              padding: const EdgeInsets.only(top: 10),
              child: ValueListenableBuilder<VrLiveFrameMetrics>(
                valueListenable: gfxSettings.telemetry,
                builder: (context, metrics, _) {
                  final healthy = metrics.fps >= 52.0;
                  final accent = healthy
                      ? const Color(0xFF34D399)
                      : const Color(0xFFFBBF24);
                  return Container(
                    key: const ValueKey('vr_live_perf_hud_chip'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xCC060D1D),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: accent.withValues(alpha: 0.65)),
                    ),
                    child: Text(
                      metrics.compactLabel,
                      style: TextStyle(
                        color: accent,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.3,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
      ],
    );
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
    this.mono = false,
    required this.stereoImageInset,
    required Listenable pointerRepaint,
    required this.pointerPosition,
    required this.isGazeSuppressed,
    required this.rig,
  }) : super(
         repaint: Listenable.merge([progress, zenithProgress, pointerRepaint]),
       );

  final ValueNotifier<double> progress;
  final ValueNotifier<double> zenithProgress;
  final bool showDivider;
  final bool showReticle;
  final bool mono;
  final double stereoImageInset;
  final vm.Vector3? Function() pointerPosition;
  final bool Function() isGazeSuppressed;
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
    if (showDivider && !mono) {
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

    // 2. Stereoscopic or Mono Gaze Reticles
    final pointer = pointerPosition();
    final pointing = pointer != null;
    if (showReticle && (pointing || !isGazeSuppressed())) {
      final ring = Paint()
        ..color = (pointing ? Colors.cyanAccent : Colors.white).withValues(
          alpha: 0.75,
        )
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      final dot = Paint()
        ..color = (pointing ? Colors.cyanAccent : Colors.white).withValues(
          alpha: 0.95,
        );
      final arc = Paint()
        ..color = Colors.cyanAccent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round;
      final p = progress.value;

      if (mono) {
        var center = Offset(size.width * 0.5, size.height * 0.5);
        if (pointer != null) {
          final projected = rig.centerCamera().worldToScreen(pointer, size);
          if (projected == null) return;
          center = projected;
        }
        _drawReticle(canvas, center, p, ring, dot, arc);
      } else {
        final insetPixels = size.width * 0.25 * stereoImageInset;
        var leftCenter = Offset(
          size.width * 0.25 + insetPixels,
          size.height * 0.5,
        );
        var rightCenter = Offset(
          size.width * 0.75 - insetPixels,
          size.height * 0.5,
        );
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
        _drawReticle(canvas, leftCenter, p, ring, dot, arc);
        _drawReticle(canvas, rightCenter, p, ring, dot, arc);
      }
    }

    // 3. Hands-Free Zenith Recenter Target (when looking straight up)
    final zp = zenithProgress.value;
    if (zp > 0) {
      if (mono) {
        _drawZenithTarget(
          canvas,
          Offset(size.width * 0.5, size.height * 0.18),
          zp,
        );
      } else {
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
  }

  @override
  bool shouldRepaint(_ReticlePainter oldDelegate) =>
      progress != oldDelegate.progress ||
      zenithProgress != oldDelegate.zenithProgress ||
      showDivider != oldDelegate.showDivider ||
      showReticle != oldDelegate.showReticle ||
      mono != oldDelegate.mono ||
      stereoImageInset != oldDelegate.stereoImageInset ||
      pointerPosition != oldDelegate.pointerPosition ||
      isGazeSuppressed != oldDelegate.isGazeSuppressed ||
      rig != oldDelegate.rig;
}
