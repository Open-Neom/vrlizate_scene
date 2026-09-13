import 'package:flutter_scene/scene.dart';
import 'package:vrlizate/vrlizate.dart'
    show GazePointer, VrInputArbiter, VrInputSource, VrInputType;

import 'stereo_head_rig.dart';
import 'vr_viewer_profile.dart';

/// Defers configuration-driven gaze exits until the next input tick, outside
/// widget build. A disabled scene must not retain dwell or a grace target.
class VrSceneGazeLifecycle {
  bool _resetPending = false;

  void configurationChanged({
    required bool previousGazeEnabled,
    required bool gazeEnabled,
  }) {
    // Keep the reset even if the view is re-enabled before another frame.
    _resetPending |= previousGazeEnabled && !gazeEnabled;
  }

  void beforeTick(
    GazePointer gaze, {
    required bool gazeEnabled,
    required bool systemGazeEnabled,
  }) {
    final inactiveWithTarget =
        !gazeEnabled &&
        !systemGazeEnabled &&
        (gaze.gazeTargetId != null || gaze.dwellProgress != 0);
    if (!_resetPending && !inactiveWithTarget) return;
    _resetPending = false;
    gaze.update(0, null, dwellEnabled: false, allowGrace: false);
    gaze.resetAdaptation();
  }
}

/// Applies shared optics at dependency/configuration changes, never per tick.
/// Explicit per-view IPD/inset win; FOV/convergence belong to the shared profile.
class VrSceneViewerProfileBinding {
  ({double ipd, double fov, double inset, double? convergence})? _original;

  void apply(
    StereoHeadRig rig,
    VrViewerProfile? profile, {
    double? explicitIpd,
    double? explicitInset,
  }) {
    if (profile != null) {
      _original ??= (
        ipd: rig.ipd,
        fov: rig.cameraRig.fovY,
        inset: rig.stereoImageInset,
        convergence: rig.convergenceDistance,
      );
      profile.applyTo(rig);
    } else if (_original case final original?) {
      rig.ipd = original.ipd;
      rig.cameraRig.fovY = original.fov;
      rig.stereoImageInset = original.inset;
      rig.convergenceDistance = original.convergence;
      _original = null;
    }
    if (explicitIpd != null) rig.ipd = explicitIpd;
    if (explicitInset != null) rig.stereoImageInset = explicitInset;
  }
}

/// Separates the visible laser intersection from ownership of activation.
/// A retained simulation can own gameplay without losing stereo pointer depth.
class VrScenePointerResolver {
  double distance = 1.8;

  Node? resolve({
    required SceneRaycastHit? systemHit,
    required bool gazeEnabled,
    required bool pointerActive,
    required SceneRaycastHit? Function() pickSelectable,
    required SceneRaycastHit? Function() pickGeometry,
    double fallbackDistance = 1.8,
  }) {
    final activationHit = systemHit ?? (gazeEnabled ? pickSelectable() : null);
    final visualHit =
        activationHit ??
        (!gazeEnabled && pointerActive ? pickGeometry() : null);
    final hitDistance = visualHit?.distance;
    distance = hitDistance != null && hitDistance.isFinite && hitDistance > 0
        ? hitDistance
        : (fallbackDistance.isFinite && fallbackDistance > 0
              ? fallbackDistance
              : 1.8);
    // Geometry-only hits never take an action away from the simulation.
    return activationHit?.node;
  }
}

/// A physical tap produces exactly one primary event. A host fallback owns its
/// own dispatch (e.g. legacy gameplay); otherwise the shared arbiter resolves
/// HOME and ordinary scene controls, including priority suppression.
void dispatchVrSceneTempleTap({
  required Node? Function() pick,
  required void Function(Node) activate,
  VrInputArbiter? arbiter,
  void Function()? onUnhandled,
}) {
  final target = pick();
  if (target == null && onUnhandled != null) {
    onUnhandled();
    return;
  }
  if (arbiter != null) {
    final event = arbiter.acquire(
      type: VrInputType.select,
      source: VrInputSource.templeTap,
    );
    try {
      arbiter.submit(event);
    } finally {
      arbiter.release(event);
    }
  } else if (target != null) {
    activate(target);
  }
}
