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

/// A display mode reported by Android, never an application FPS measurement.
@immutable
class VrDisplayMode {
  const VrDisplayMode({
    required this.widthPixels,
    required this.heightPixels,
    required this.refreshRateHz,
  });

  final int widthPixels;
  final int heightPixels;
  final double refreshRateHz;

  static VrDisplayMode? fromPlatform(Object? raw) {
    if (raw is! Map) return null;
    final width = _positiveInt(raw['widthPixels']);
    final height = _positiveInt(raw['heightPixels']);
    final hz = raw['refreshRateHz'];
    if (width == null ||
        height == null ||
        hz is! num ||
        !hz.isFinite ||
        hz <= 0) {
      return null;
    }
    return VrDisplayMode(
      widthPixels: width,
      heightPixels: height,
      refreshRateHz: hz.toDouble(),
    );
  }

  Map<String, Object> toJson() => {
    'widthPixels': widthPixels,
    'heightPixels': heightPixels,
    'refreshRateHz': refreshRateHz,
  };
}

/// Read-only startup snapshot, without serial number or inferred GPU capability.
/// The OS can change its active refresh rate after this snapshot is taken.
@immutable
class VrDeviceCapabilities {
  const VrDeviceCapabilities({
    required this.manufacturer,
    required this.model,
    required this.androidSdk,
    required this.activeMode,
    required this.supportedModes,
  });

  final String manufacturer;
  final String model;
  final int? androidSdk;
  final VrDisplayMode? activeMode;
  final List<VrDisplayMode> supportedModes;

  static VrDeviceCapabilities? fromPlatform(Object? raw) {
    if (raw is! Map) return null;
    final manufacturer = _deviceLabel(raw['manufacturer']);
    final model = _deviceLabel(raw['model']);
    if (manufacturer.isEmpty || model.isEmpty) return null;
    final modes = raw['supportedModes'];
    return VrDeviceCapabilities(
      manufacturer: manufacturer,
      model: model,
      androidSdk: _positiveInt(raw['androidSdk']),
      activeMode: VrDisplayMode.fromPlatform(raw['activeMode']),
      supportedModes: List.unmodifiable(
        modes is List
            ? modes.map(VrDisplayMode.fromPlatform).whereType<VrDisplayMode>()
            : const <VrDisplayMode>[],
      ),
    );
  }

  Map<String, Object?> toJson() => {
    'manufacturer': manufacturer,
    'model': model,
    'androidSdk': androidSdk,
    'activeMode': activeMode?.toJson(),
    'supportedModes': [for (final mode in supportedModes) mode.toJson()],
  };
}

int? _positiveInt(Object? raw) => raw is int && raw > 0 ? raw : null;

String _deviceLabel(Object? raw) {
  if (raw is! String || raw.length > 160) return '';
  return raw.replaceAll(RegExp(r'[\x00-\x1F\x7F]'), ' ').trim();
}
