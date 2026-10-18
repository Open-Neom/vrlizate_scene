import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:vector_math/vector_math.dart' as vm;
import 'package:vrlizate/vrlizate.dart' show VREngine, VrInputArbiter;

import 'quality_preset.dart';
import 'retained_desktop_input.dart';
import 'retained_scene_adapter.dart';
import 'stereo_head_rig.dart';
import 'stereo_scene_view.dart';
import 'vr_input_session_scope.dart';

/// Runs existing game rules against a retained GPU scene, never a screenshot
/// of the legacy renderer. StereoSceneView exclusively owns tracking and time.
class RetainedDemoSceneView extends StatefulWidget {
  const RetainedDemoSceneView({
    super.key,
    required this.engine,
    required this.onPrimary,
    this.onTempleTap,
  });

  final VREngine engine;
  final VoidCallback onPrimary;
  final VoidCallback? onTempleTap;

  @override
  State<RetainedDemoSceneView> createState() => _RetainedDemoSceneViewState();
}

class _RetainedDemoSceneViewState extends State<RetainedDemoSceneView>
    with WidgetsBindingObserver {
  final RetainedDesktopInput _desktopInput = RetainedDesktopInput();
  VrInputArbiter? _desktopArbiter;
  bool _foreground = true;
  bool get _isDesktop => switch (defaultTargetPlatform) {
    TargetPlatform.macOS ||
    TargetPlatform.windows ||
    TargetPlatform.linux => true,
    _ => false,
  };
  late final StereoHeadRig _rig = StereoHeadRig(
    cameraRig: widget.engine.cameraRig,
  );
  // Legacy worlds get a dome from their background color when they define
  // no sky, and their first directional light casts shadows at the quality
  // preset's resolution (see onQualityChanged below).
  late final VrRetainedSceneAdapter _adapter = VrRetainedSceneAdapter(
    source: widget.engine.scene,
  )..defaultSkyDome = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.engine.useExternalFrameDriver();
    _adapter.sync();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = _isDesktop ? VrInputSessionScope.arbiterOf(context) : null;
    if (!identical(next, _desktopArbiter)) {
      _desktopArbiter?.detachDriver(_desktopInput);
      _desktopArbiter = next;
      next?.attachDriver(_desktopInput);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) _desktopInput.releaseAll();
  }

  void _copyRay(vm.Ray ray) {
    widget.engine.setExternalInteractionRay(ray);
    // A system HOME target owns dwell; do not activate a game object behind it.
    widget.engine.externalDwellSuppressed =
        _adapter.scene.raycast(
          ray,
          where: (node) => node.name == '__vrlizate_system_home__',
        ) !=
        null;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _desktopArbiter?.detachDriver(_desktopInput);
    widget.engine.setExternalInteractionRay(null);
    widget.engine.externalDwellSuppressed = false;
    _adapter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final child = GestureDetector(
      onTap: widget.onPrimary,
      child: StereoSceneView(
        scene: _adapter.scene,
        rig: _rig,
        enableHandTracking: false,
        // Source game rules own their dwell/selection, while the GPU view owns
        // system HOME and publishes the same ray before input dispatch.
        gazeEnabled: false,
        onUnhandledTempleTap: widget.onTempleTap ?? widget.onPrimary,
        onInteractionRay: _copyRay,
        onQualityChanged: (preset) {
          _adapter.shadowMapResolution = preset.tier == VrQualityTier.low
              ? null
              : preset.shadowMapResolution;
        },
        onTick: (elapsed, dt) {
          widget.engine.step(dt, integrateInput: false);
          _adapter.sync(elapsedSeconds: elapsed.inMicroseconds / 1000000);
        },
      ),
    );
    if (!_isDesktop) return child;
    return Focus(
      autofocus: true,
      onFocusChange: (focused) {
        if (!focused) _desktopInput.releaseAll();
      },
      onKeyEvent: (_, event) =>
          _foreground && _desktopInput.handleKeyEvent(event)
          ? KeyEventResult.handled
          : KeyEventResult.ignored,
      child: child,
    );
  }
}
