/// Shared vertical look response for Home and rendered scenes.
/// This applies only to a look stick, never to physical headset pitch or aim.
abstract final class VrStickLook {
  /// Deliberate vertical travel is required even during horizontal movement.
  static const verticalDeadZone = 0.30;

  /// Full travel turns about 52 degrees per second; the response above the
  /// dead zone ramps continuously from zero instead of jumping at its edge.
  static const maxPitchRadiansPerSecond = 0.9;

  /// Stick +Y is up; the rig's positive pitch is down. Clamp long frames to
  /// prevent a large camera jump after suspension, matching scene integration.
  static double pitchDelta(double axis, double dt) {
    if (!axis.isFinite || !dt.isFinite || dt <= 0) return 0;
    final magnitude = axis.abs().clamp(0.0, 1.0);
    if (magnitude <= verticalDeadZone) return 0;
    final response = (magnitude - verticalDeadZone) / (1 - verticalDeadZone);
    return -axis.sign *
        response *
        maxPitchRadiansPerSecond *
        dt.clamp(0.0, 0.1);
  }
}
