/// Hands-free recenter trigger: hold the gaze above the zenith threshold.
///
/// Pitch follows the `CameraRig` convention — **positive looks down** — so the
/// zenith is the *negative* side. Looking down (where the downward-gaze
/// controller feedback lives) never arms the trigger. Pure and allocation
/// free; the stereo view feeds it the composed rig pitch every tick.
class VrZenithRecenterDetector {
  VrZenithRecenterDetector({
    this.thresholdRadians = 0.95,
    this.holdSeconds = 0.8,
  }) : assert(thresholdRadians > 0),
       assert(holdSeconds > 0);

  /// How far above the horizon (in radians, ~55° by default) counts as zenith.
  final double thresholdRadians;

  /// How long the gaze must stay there before recentering fires.
  final double holdSeconds;

  double _timer = 0;
  bool _triggered = false;

  /// 0..1 fraction of [holdSeconds] accumulated while looking up.
  double get progress => (_timer / holdSeconds).clamp(0.0, 1.0);

  /// Whether the current hold already fired (until the gaze drops).
  bool get triggered => _triggered;

  /// Advances by [dt] with the composed [pitch]. Returns true exactly once
  /// per hold, on the tick the hold completes.
  bool update(double pitch, double dt) {
    if (!pitch.isFinite || !dt.isFinite) return false;
    if (pitch < -thresholdRadians) {
      _timer += dt.clamp(0.0, holdSeconds);
      if (_timer >= holdSeconds && !_triggered) {
        _triggered = true;
        return true;
      }
      return false;
    }
    reset();
    return false;
  }

  void reset() {
    _timer = 0;
    _triggered = false;
  }
}
