/// A stateless near-distance band with explicit entry and exit margins.
///
/// Evaluate with the shared center-eye distance and retain state in the caller.
/// This class neither measures distance nor schedules updates,
/// mounts nodes, or changes residency. Those policies remain with their owner.
///
/// With [includeBoundary], the near side includes equality. Set it to false
/// for authored LOD cutoffs where equality belongs to the farther level.
final class VrDistanceBand {
  VrDistanceBand({
    required this.distanceMeters,
    this.enterMarginMeters = 0,
    this.exitMarginMeters = 0,
    this.includeBoundary = true,
  }) {
    if (![
      distanceMeters,
      enterMarginMeters,
      exitMarginMeters,
    ].every((value) => value.isFinite && value >= 0)) {
      throw ArgumentError(
        'Distance and margins must be finite and nonnegative.',
      );
    }
  }

  final double distanceMeters;
  final double enterMarginMeters;
  final double exitMarginMeters;
  final bool includeBoundary;

  /// Whether [distanceMeters] belongs to the near side of this boundary.
  ///
  /// A null [wasInside] performs initial selection at the unmodified cutoff.
  /// True retains the near side through the exit margin; false requires entry
  /// past the entry margin. Positive infinity is accepted; callers that require
  /// finite distances may apply stricter validation.
  bool contains(double distanceMeters, {bool? wasInside}) {
    if (distanceMeters.isNaN || distanceMeters < 0) {
      throw ArgumentError.value(distanceMeters, 'distanceMeters');
    }
    final limit = switch (wasInside) {
      null => this.distanceMeters,
      true => this.distanceMeters + exitMarginMeters,
      false => this.distanceMeters - enterMarginMeters,
    };
    return includeBoundary ? distanceMeters <= limit : distanceMeters < limit;
  }
}
