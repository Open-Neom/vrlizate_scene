import 'package:flutter/widgets.dart';

import 'quality_preset.dart';

/// A starting quality suggestion for an explicitly identified phone model.
///
/// This is neither a user/optical profile nor a benchmark result. A measured
/// frame rate belongs to a particular scene, renderer/backend, resolution,
/// quality and test conditions; it cannot be inferred from the model name or
/// [displayMaxHz]. The active display mode can also be below that maximum.
/// Runtime quality monitoring remains responsible for adapting the scene.
@immutable
class VrDevicePerformanceProfile {
  const VrDevicePerformanceProfile({
    required this.id,
    required this.label,
    required this.initialTier,
    this.displayMaxHz,
  });

  final String id;
  final String label;
  final VrQualityTier initialTier;

  /// Catalogued maximum panel refresh, not current refresh or achievable FPS.
  /// Null means the catalog does not establish a maximum.
  final double? displayMaxHz;
}

/// Small reference catalog with exact, explicit model aliases.
///
/// Unknown phones stay unknown: product-family prefixes and processor names
/// do not qualify another model for these suggestions. Neither profile enables
/// foveation automatically or promises a frame-rate target.
abstract final class VrDevicePerformanceCatalog {
  /// The tested Motorola is an Edge 20 Lite, not a Moto G20.
  static const motorolaEdge20Lite = VrDevicePerformanceProfile(
    id: 'motorola_edge_20_lite',
    label: 'Motorola Edge 20 Lite',
    initialTier: VrQualityTier.low,
    displayMaxHz: 90,
  );

  /// Ultra SKU aliases share a startup suggestion, not benchmark evidence.
  /// Results measured on one SKU must retain that exact SKU in their record.
  static const samsungGalaxyS25Ultra = VrDevicePerformanceProfile(
    id: 'samsung_galaxy_s25_ultra',
    label: 'Samsung Galaxy S25 Ultra',
    initialTier: VrQualityTier.medium,
    displayMaxHz: 120,
  );

  static const profiles = [motorolaEdge20Lite, samsungGalaxyS25Ultra];

  /// Finds a model after case/whitespace normalization and an optional Samsung
  /// dual-SIM `/DS` suffix. No partial-name or device-family matching is used.
  static VrDevicePerformanceProfile? match({
    required String manufacturer,
    required String model,
  }) {
    final maker = _normalize(manufacturer);
    final name = _normalize(model);
    if (maker == 'motorola' && name == 'motorola edge 20 lite') {
      return motorolaEdge20Lite;
    }
    if (maker != 'samsung') return null;
    final samsungModel = name.replaceFirst(_dualSimSuffix, '').trim();
    return switch (samsungModel) {
      'sm-s938b' ||
      'sm-s938u' ||
      'sm-s938u1' ||
      'sm-s938w' ||
      'sm-s938n' ||
      'sm-s9380' => samsungGalaxyS25Ultra,
      _ => null,
    };
  }

  static final _whitespace = RegExp(r'\s+');
  static final _dualSimSuffix = RegExp(r'\s*/\s*ds$');

  static String _normalize(String value) =>
      value.trim().toLowerCase().replaceAll(_whitespace, ' ');
}

/// Host-provided startup suggestion shared by scene views in the subtree.
///
/// Hosts resolve device identity once and may supply null for unknown devices.
/// A scene consumes this as an initial seed, not a command to reset its current
/// adaptive quality on rebuild. It does not configure display refresh, change
/// the quality monitor's target, persist preferences, or switch rendering modes.
class VrDevicePerformanceScope extends InheritedWidget {
  const VrDevicePerformanceScope({
    super.key,
    required this.profile,
    required super.child,
  });

  final VrDevicePerformanceProfile? profile;

  static VrDevicePerformanceProfile? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<VrDevicePerformanceScope>()
      ?.profile;

  /// Resolves the initial quality without overwriting any established preset.
  /// Call only when the consumer has no current adaptive quality of its own.
  static VrQualityPreset initialPresetOf(
    BuildContext context, {
    VrQualityPreset? explicitQuality,
  }) {
    if (explicitQuality != null) return explicitQuality;
    final profile = maybeOf(context);
    return profile == null
        ? VrQualityPreset.resolve(context, null)
        : VrQualityPreset.forTier(profile.initialTier);
  }

  @override
  bool updateShouldNotify(VrDevicePerformanceScope oldWidget) =>
      profile != oldWidget.profile;
}
