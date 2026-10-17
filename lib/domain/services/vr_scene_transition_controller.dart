import '../../utils/constants/vr_scene_constants.dart';
import '../../utils/enums/vr_scene_transition_style.dart';

/// Manages smooth transition progress (`0.0..1.0`), fade opacity, and FOV warp
/// when entering or exiting spatial apps and portals.
class VrSceneTransitionController {
  VrSceneTransitionController({
    this.style = VrSceneTransitionStyle.smoothFade,
    this.durationMs = VrSceneConstants.defaultTransitionDurationMs,
    this.baseFovDegrees = VrSceneConstants.defaultBaseFovDegrees,
  }) : assert(durationMs >= 0),
       assert(baseFovDegrees > 0);

  VrSceneTransitionStyle style;
  final int durationMs;
  final double baseFovDegrees;

  double _progress = VrSceneConstants.minTransitionProgress;
  bool _isTransitioning = false;
  bool _isEntering = true;
  String? _targetId;

  /// Normalized transition progress in the range `0.0..1.0`.
  double get progress => _progress;

  /// Whether a transition is currently in progress.
  bool get isTransitioning => _isTransitioning;

  /// True when entering an app or portal; false when exiting back to lobby/scene.
  bool get isEntering => _isEntering;

  /// Identifier of the portal or app being transitioned into/out of, if any.
  String? get targetId => _targetId;

  /// Smoothly eased fade opacity (`0.0..1.0`) derived from [progress].
  double get fadeOpacity {
    final t = _progress.clamp(
      VrSceneConstants.minTransitionProgress,
      VrSceneConstants.maxTransitionProgress,
    );
    return t *
        t *
        (VrSceneConstants.smoothstepFactorA -
            VrSceneConstants.smoothstepFactorB * t);
  }

  /// Signed field-of-view warp delta in degrees based on [style] and direction.
  ///
  /// Entering narrows/pulls the FOV forward (negative delta for zoom-in effect),
  /// while exiting expands back toward the base FOV.
  double get fovWarpDegrees {
    if (style.isImmediate) {
      return VrSceneConstants.instantWarpDeltaDegrees;
    }
    final directionSign = _isEntering ? -1.0 : 1.0;
    return directionSign * style.fovWarpDeltaDegrees * fadeOpacity;
  }

  /// Effective camera field-of-view in degrees including the transition warp.
  double get effectiveFovDegrees => baseFovDegrees + fovWarpDegrees;

  /// Normalized portal iris aperture (`0.0..1.0`), closing as [fadeOpacity] rises
  /// when using [VrSceneTransitionStyle.portalIris].
  double get irisAperture {
    if (style != VrSceneTransitionStyle.portalIris) {
      return VrSceneConstants.maxIrisAperture;
    }
    return (VrSceneConstants.maxIrisAperture - fadeOpacity).clamp(
      VrSceneConstants.minIrisAperture,
      VrSceneConstants.maxIrisAperture,
    );
  }

  /// Starts an entry transition toward [targetId].
  void beginEnter({String? targetId, VrSceneTransitionStyle? style}) {
    if (style != null) {
      this.style = style;
    }
    _targetId = targetId;
    _isEntering = true;
    if (this.style.isImmediate || durationMs == 0) {
      _progress = VrSceneConstants.maxTransitionProgress;
      _isTransitioning = false;
      return;
    }
    _progress = VrSceneConstants.minTransitionProgress;
    _isTransitioning = true;
  }

  /// Starts an exit transition away from [targetId].
  void beginExit({String? targetId, VrSceneTransitionStyle? style}) {
    if (style != null) {
      this.style = style;
    }
    _targetId = targetId ?? _targetId;
    _isEntering = false;
    if (this.style.isImmediate || durationMs == 0) {
      _progress = VrSceneConstants.maxTransitionProgress;
      _isTransitioning = false;
      return;
    }
    _progress = VrSceneConstants.minTransitionProgress;
    _isTransitioning = true;
  }

  /// Advances transition progress by [deltaMs] milliseconds.
  void advanceMs(int deltaMs) {
    if (!_isTransitioning || deltaMs <= 0) {
      return;
    }
    if (style.isImmediate || durationMs <= 0) {
      _progress = VrSceneConstants.maxTransitionProgress;
      _isTransitioning = false;
      return;
    }
    final step = deltaMs / durationMs;
    setProgress(_progress + step);
  }

  /// Advances transition progress by [delta].
  void update(Duration delta) => advanceMs(delta.inMilliseconds);

  /// Explicitly sets [progress] clamped to `0.0..1.0`.
  void setProgress(double value) {
    _progress = value.clamp(
      VrSceneConstants.minTransitionProgress,
      VrSceneConstants.maxTransitionProgress,
    );
    if (_progress >= VrSceneConstants.maxTransitionProgress) {
      _isTransitioning = false;
    }
  }

  /// Resets the controller to its idle `0.0` state.
  void reset() {
    _progress = VrSceneConstants.minTransitionProgress;
    _isTransitioning = false;
    _isEntering = true;
    _targetId = null;
  }
}
