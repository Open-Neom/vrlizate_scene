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
    this.cpuCores,
    this.totalRamMb,
    this.isLowRamDevice,
    this.socManufacturer,
    this.socModel,
    this.mediaPerformanceClass,
    this.hasHardwareGyroscope,
    this.hasGameRotationVector,
    this.minGyroDelayUs,
    this.hasVibrator,
    this.hasLinearHaptics,
    this.hasConcurrentCameras,
    this.supportsWifi5Ghz,
    this.supportsWifi6Ghz,
    this.supportsWifiP2p,
    this.supportsWifiAware,
    this.supportsStaApConcurrency,
    this.wifiConnected,
    this.cellularConnected,
    this.wifiFrequencyMhz,
    this.audioOutputKind,
    this.thermalStatus,
  });

  final String manufacturer;
  final String model;
  final int? androidSdk;
  final VrDisplayMode? activeMode;
  final List<VrDisplayMode> supportedModes;
  final int? cpuCores;
  final int? totalRamMb;
  final bool? isLowRamDevice;
  final String? socManufacturer;
  final String? socModel;
  final int? mediaPerformanceClass;
  final bool? hasHardwareGyroscope;
  final bool? hasGameRotationVector;
  final int? minGyroDelayUs;
  final bool? hasVibrator;
  final bool? hasLinearHaptics;
  final bool? hasConcurrentCameras;
  final bool? supportsWifi5Ghz;
  final bool? supportsWifi6Ghz;
  final bool? supportsWifiP2p;
  final bool? supportsWifiAware;
  final bool? supportsStaApConcurrency;
  final bool? wifiConnected;
  final bool? cellularConnected;
  final int? wifiFrequencyMhz;
  final String? audioOutputKind;
  final int? thermalStatus;

  double? get maxSupportedRefreshHz {
    double? best = activeMode?.refreshRateHz;
    for (final mode in supportedModes) {
      if (best == null || mode.refreshRateHz > best) {
        best = mode.refreshRateHz;
      }
    }
    return best;
  }

  bool get isOn5GhzOr6GhzWifi =>
      wifiConnected == true && (wifiFrequencyMhz ?? 0) >= 4900;

  bool get isOn24GhzWifi =>
      wifiConnected == true &&
      (wifiFrequencyMhz ?? 0) >= 2400 &&
      (wifiFrequencyMhz ?? 0) < 2500;

  VrDeviceCapabilities copyWithRuntimeEnvironment(Object? raw) {
    if (raw is! Map) return this;
    return VrDeviceCapabilities(
      manufacturer: manufacturer,
      model: model,
      androidSdk: androidSdk,
      activeMode: VrDisplayMode.fromPlatform(raw['activeMode']) ?? activeMode,
      supportedModes: supportedModes,
      cpuCores: cpuCores,
      totalRamMb: totalRamMb,
      isLowRamDevice: isLowRamDevice,
      socManufacturer: socManufacturer,
      socModel: socModel,
      mediaPerformanceClass: mediaPerformanceClass,
      hasHardwareGyroscope: hasHardwareGyroscope,
      hasGameRotationVector: hasGameRotationVector,
      minGyroDelayUs: minGyroDelayUs,
      hasVibrator: hasVibrator,
      hasLinearHaptics: hasLinearHaptics,
      hasConcurrentCameras: hasConcurrentCameras,
      supportsWifi5Ghz: supportsWifi5Ghz,
      supportsWifi6Ghz: supportsWifi6Ghz,
      supportsWifiP2p: supportsWifiP2p,
      supportsWifiAware: supportsWifiAware,
      supportsStaApConcurrency: supportsStaApConcurrency,
      wifiConnected: _optionalBool(raw['wifiConnected']) ?? wifiConnected,
      cellularConnected:
          _optionalBool(raw['cellularConnected']) ?? cellularConnected,
      wifiFrequencyMhz: raw.containsKey('wifiFrequencyMhz')
          ? _positiveInt(raw['wifiFrequencyMhz'])
          : wifiFrequencyMhz,
      audioOutputKind:
          _optionalLabel(raw['audioOutputKind']) ?? audioOutputKind,
      thermalStatus:
          _nonNegativeInt(raw['thermalStatus']) ?? thermalStatus,
    );
  }

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
      cpuCores: _positiveInt(raw['cpuCores']),
      totalRamMb: _positiveInt(raw['totalRamMb']),
      isLowRamDevice: _optionalBool(raw['isLowRamDevice']),
      socManufacturer: _optionalLabel(raw['socManufacturer']),
      socModel: _optionalLabel(raw['socModel']),
      mediaPerformanceClass: _nonNegativeInt(raw['mediaPerformanceClass']),
      hasHardwareGyroscope: _optionalBool(raw['hasHardwareGyroscope']),
      hasGameRotationVector: _optionalBool(raw['hasGameRotationVector']),
      minGyroDelayUs: _nonNegativeInt(raw['minGyroDelayUs']),
      hasVibrator: _optionalBool(raw['hasVibrator']),
      hasLinearHaptics: _optionalBool(raw['hasLinearHaptics']),
      hasConcurrentCameras: _optionalBool(raw['hasConcurrentCameras']),
      supportsWifi5Ghz: _optionalBool(raw['supportsWifi5Ghz']),
      supportsWifi6Ghz: _optionalBool(raw['supportsWifi6Ghz']),
      supportsWifiP2p: _optionalBool(raw['supportsWifiP2p']),
      supportsWifiAware: _optionalBool(raw['supportsWifiAware']),
      supportsStaApConcurrency: _optionalBool(raw['supportsStaApConcurrency']),
      wifiConnected: _optionalBool(raw['wifiConnected']),
      cellularConnected: _optionalBool(raw['cellularConnected']),
      wifiFrequencyMhz: _positiveInt(raw['wifiFrequencyMhz']),
      audioOutputKind: _optionalLabel(raw['audioOutputKind']),
      thermalStatus: _nonNegativeInt(raw['thermalStatus']),
    );
  }

  Map<String, Object?> toJson() => {
    'manufacturer': manufacturer,
    'model': model,
    'androidSdk': androidSdk,
    'activeMode': activeMode?.toJson(),
    if (cpuCores != null) 'cpuCores': cpuCores,
    if (totalRamMb != null) 'totalRamMb': totalRamMb,
    if (isLowRamDevice != null) 'isLowRamDevice': isLowRamDevice,
    if (socManufacturer != null) 'socManufacturer': socManufacturer,
    if (socModel != null) 'socModel': socModel,
    if (mediaPerformanceClass != null)
      'mediaPerformanceClass': mediaPerformanceClass,
    if (hasHardwareGyroscope != null)
      'hasHardwareGyroscope': hasHardwareGyroscope,
    if (hasGameRotationVector != null)
      'hasGameRotationVector': hasGameRotationVector,
    if (minGyroDelayUs != null) 'minGyroDelayUs': minGyroDelayUs,
    if (hasVibrator != null) 'hasVibrator': hasVibrator,
    if (hasLinearHaptics != null) 'hasLinearHaptics': hasLinearHaptics,
    if (hasConcurrentCameras != null)
      'hasConcurrentCameras': hasConcurrentCameras,
    if (supportsWifi5Ghz != null) 'supportsWifi5Ghz': supportsWifi5Ghz,
    if (supportsWifi6Ghz != null) 'supportsWifi6Ghz': supportsWifi6Ghz,
    if (supportsWifiP2p != null) 'supportsWifiP2p': supportsWifiP2p,
    if (supportsWifiAware != null) 'supportsWifiAware': supportsWifiAware,
    if (supportsStaApConcurrency != null)
      'supportsStaApConcurrency': supportsStaApConcurrency,
    if (wifiConnected != null) 'wifiConnected': wifiConnected,
    if (cellularConnected != null) 'cellularConnected': cellularConnected,
    if (wifiFrequencyMhz != null) 'wifiFrequencyMhz': wifiFrequencyMhz,
    if (audioOutputKind != null) 'audioOutputKind': audioOutputKind,
    if (thermalStatus != null) 'thermalStatus': thermalStatus,
    'supportedModes': [for (final mode in supportedModes) mode.toJson()],
  };

  /// Compact summary safe for post-authentication Visor <-> Joystick exchange.
  Map<String, Object?> toPeerSummary() {
    final feature = VrPopularDeviceCatalog.resolve(this);
    return {
      'maker': manufacturer,
      'model': model,
      'cls': feature.deviceClass.name,
      if (totalRamMb != null) 'ramMb': totalRamMb,
      if (mediaPerformanceClass != null && mediaPerformanceClass! > 0)
        'mpc': mediaPerformanceClass,
      if (hasHardwareGyroscope != null) 'gyro': hasHardwareGyroscope,
      if (hasLinearHaptics != null) 'haptics': hasLinearHaptics,
      if (hasConcurrentCameras != null) 'cam3': hasConcurrentCameras,
      if (supportsWifi5Ghz != null) 'wifi5': supportsWifi5Ghz,
      if (supportsStaApConcurrency != null) 'staAp': supportsStaApConcurrency,
      if (wifiConnected != null) 'wifiOn': wifiConnected,
      if (wifiFrequencyMhz != null) 'freqMhz': wifiFrequencyMhz,
      if (audioOutputKind != null) 'audio': audioOutputKind,
      if (maxSupportedRefreshHz != null)
        'maxHz': maxSupportedRefreshHz!.round(),
    };
  }
}

/// Broad hardware capability tier used to gate optional background processes,
/// sensors, and link upgrade rates without claiming measured scene FPS.
enum VrDeviceClass { entry, mid, flagship }

/// Capability-gated feature budget resolved from hardware probes and popular
/// smartphone product lines.
///
/// Unlike [VrDevicePerformanceProfile], which is restricted to explicitly
/// benchmarked SKUs, [VrDeviceFeatureProfile] identifies which sensors, radio
/// upgrades, and controller polling rates a phone can actually execute without
/// wasting CPU/battery on unsupported hardware.
@immutable
class VrDeviceFeatureProfile {
  const VrDeviceFeatureProfile({
    required this.deviceClass,
    required this.popularLineId,
    required this.popularLineLabel,
    required this.recommendedVisorTier,
    required this.isExplicitOrHardwareClassified,
    required this.supportsMotionControls,
    required this.supportsLinearHaptics,
    required this.supportsConcurrentCameras,
    required this.supportsPro120HzController,
    required this.supports5GhzFastLink,
    required this.supportsStaApHotspot,
    required this.preferControllerRoleWarning,
  });

  final VrDeviceClass deviceClass;
  final String popularLineId;
  final String popularLineLabel;
  final VrQualityTier recommendedVisorTier;

  /// True when matched by a popular line rule or hardware probe (RAM/SoC/MPC).
  /// False when capabilities only contain bare display/model strings without
  /// hardware tier telemetry.
  final bool isExplicitOrHardwareClassified;
  final bool supportsMotionControls;
  final bool supportsLinearHaptics;
  final bool supportsConcurrentCameras;
  final bool supportsPro120HzController;
  final bool supports5GhzFastLink;
  final bool supportsStaApHotspot;
  final bool preferControllerRoleWarning;

  int get targetControllerHz => supportsPro120HzController ? 120 : 60;
}

/// Resolves [VrDeviceFeatureProfile] across popular smartphone lines
/// (Samsung Galaxy S/Z/A/M, Motorola Edge/Moto G/E, Xiaomi/Redmi/POCO,
/// Google Pixel, Apple iPhone) with hardware-first fallback.
abstract final class VrPopularDeviceCatalog {
  static VrDeviceFeatureProfile resolve(VrDeviceCapabilities? capabilities) {
    if (capabilities == null) {
      return const VrDeviceFeatureProfile(
        deviceClass: VrDeviceClass.mid,
        popularLineId: 'default_unknown',
        popularLineLabel: 'Standard Smartphone',
        recommendedVisorTier: VrQualityTier.medium,
        isExplicitOrHardwareClassified: false,
        supportsMotionControls: true,
        supportsLinearHaptics: false,
        supportsConcurrentCameras: false,
        supportsPro120HzController: false,
        supports5GhzFastLink: true,
        supportsStaApHotspot: false,
        preferControllerRoleWarning: false,
      );
    }

    final lineMatch = _matchPopularLine(
      manufacturer: capabilities.manufacturer,
      model: capabilities.model,
    );

    final ramMb = capabilities.totalRamMb;
    final lowRam =
        capabilities.isLowRamDevice == true || (ramMb != null && ramMb <= 4200);
    final mpc = capabilities.mediaPerformanceClass ?? 0;
    final socFlagship = _isFlagshipSoc(capabilities.socModel);

    final VrDeviceClass resolvedClass;
    final VrQualityTier resolvedTier;
    final String lineId;
    final String lineLabel;
    final bool classified;

    if (lowRam) {
      resolvedClass = VrDeviceClass.entry;
      resolvedTier = VrQualityTier.low;
      lineId = lineMatch?.id ?? 'hardware_low_ram_entry';
      lineLabel = lineMatch?.label ?? 'Entry Smartphone (<= 4 GB RAM)';
      classified = true;
    } else if (lineMatch != null) {
      resolvedClass = lineMatch.deviceClass;
      resolvedTier = lineMatch.visorTier;
      lineId = lineMatch.id;
      lineLabel = lineMatch.label;
      classified = true;
    } else if (mpc >= 33 || socFlagship || (ramMb != null && ramMb >= 10500)) {
      resolvedClass = VrDeviceClass.flagship;
      resolvedTier = VrQualityTier.medium;
      lineId = 'hardware_flagship';
      lineLabel = 'Flagship Hardware Class';
      classified = true;
    } else if (ramMb != null && ramMb <= 6400) {
      resolvedClass = VrDeviceClass.mid;
      resolvedTier = VrQualityTier.low;
      lineId = 'hardware_mid_compact';
      lineLabel = 'Mid-Range Smartphone (6 GB RAM)';
      classified = true;
    } else if (ramMb != null || mpc > 0 || capabilities.socModel != null) {
      resolvedClass = VrDeviceClass.mid;
      resolvedTier = VrQualityTier.medium;
      lineId = 'hardware_mid';
      lineLabel = 'Mid-Range Smartphone';
      classified = true;
    } else {
      resolvedClass = VrDeviceClass.mid;
      resolvedTier = VrQualityTier.medium;
      lineId = 'unlisted_default';
      lineLabel = capabilities.model;
      classified = false;
    }

    final hasGyro = capabilities.hasHardwareGyroscope ?? true;
    final maxHz = capabilities.maxSupportedRefreshHz ?? 60.0;
    final supportsPro120 =
        resolvedClass == VrDeviceClass.flagship && maxHz >= 115.0;

    return VrDeviceFeatureProfile(
      deviceClass: resolvedClass,
      popularLineId: lineId,
      popularLineLabel: lineLabel,
      recommendedVisorTier: resolvedTier,
      isExplicitOrHardwareClassified: classified,
      supportsMotionControls: hasGyro,
      supportsLinearHaptics:
          capabilities.hasLinearHaptics ??
          (resolvedClass == VrDeviceClass.flagship &&
              (capabilities.hasVibrator ?? true)),
      supportsConcurrentCameras: capabilities.hasConcurrentCameras ?? false,
      supportsPro120HzController: supportsPro120,
      supports5GhzFastLink: capabilities.supportsWifi5Ghz ?? true,
      supportsStaApHotspot: capabilities.supportsStaApConcurrency ?? false,
      preferControllerRoleWarning:
          resolvedClass == VrDeviceClass.entry || !hasGyro,
    );
  }

  static bool _isFlagshipSoc(String? rawSoc) {
    if (rawSoc == null || rawSoc.isEmpty) return false;
    final soc = rawSoc.trim().toUpperCase();
    return soc.startsWith('SM84') ||
        soc.startsWith('SM85') ||
        soc.startsWith('SM86') ||
        soc.startsWith('SM87') ||
        soc.startsWith('S5E99') ||
        soc.contains('TENSOR G3') ||
        soc.contains('TENSOR G4') ||
        soc.startsWith('MT698') ||
        soc.startsWith('MT699');
  }

  static _PopularLineRule? _matchPopularLine({
    required String manufacturer,
    required String model,
  }) {
    final maker = VrDevicePerformanceCatalog._normalize(manufacturer);
    final rawName = VrDevicePerformanceCatalog._normalize(
      model,
    ).replaceFirst(VrDevicePerformanceCatalog._dualSimSuffix, '').trim();

    if (maker == 'samsung') {
      if (_matchesAnyPrefix(rawName, const [
            'sm-s90',
            'sm-s91',
            'sm-s92',
            'sm-s93',
            'sm-f9',
            'sm-f7',
          ]) ||
          _containsAny(rawName, const [
            'galaxy s22',
            'galaxy s23',
            'galaxy s24',
            'galaxy s25',
            'galaxy z fold',
            'galaxy z flip',
          ])) {
        if (rawName.contains('fe')) {
          return const _PopularLineRule(
            id: 'samsung_galaxy_s_fe',
            label: 'Samsung Galaxy S FE Series',
            deviceClass: VrDeviceClass.mid,
            visorTier: VrQualityTier.medium,
          );
        }
        return const _PopularLineRule(
          id: 'samsung_galaxy_s_flagship',
          label: 'Samsung Galaxy S / Z Flagship',
          deviceClass: VrDeviceClass.flagship,
          visorTier: VrQualityTier.medium,
        );
      }
      if (_matchesAnyPrefix(rawName, const [
            'sm-s711',
            'sm-s721',
            'sm-g990',
            'sm-a546',
            'sm-a556',
            'sm-a566',
          ]) ||
          _containsAny(rawName, const [
            'galaxy a54',
            'galaxy a55',
            'galaxy a56',
          ])) {
        return const _PopularLineRule(
          id: 'samsung_galaxy_a5x_fe',
          label: 'Samsung Galaxy A5x / FE Series',
          deviceClass: VrDeviceClass.mid,
          visorTier: VrQualityTier.medium,
        );
      }
      if (_matchesAnyPrefix(rawName, const [
            'sm-a346',
            'sm-a356',
            'sm-a366',
            'sm-a256',
            'sm-m346',
            'sm-m356',
            'sm-m546',
          ]) ||
          _containsAny(rawName, const [
            'galaxy a34',
            'galaxy a35',
            'galaxy a36',
            'galaxy a25',
            'galaxy m34',
            'galaxy m35',
            'galaxy m54',
          ])) {
        return const _PopularLineRule(
          id: 'samsung_galaxy_a3x_mid',
          label: 'Samsung Galaxy A3x / M3x Series',
          deviceClass: VrDeviceClass.mid,
          visorTier: VrQualityTier.low,
        );
      }
      if (_matchesAnyPrefix(rawName, const [
            'sm-a04',
            'sm-a05',
            'sm-a06',
            'sm-a14',
            'sm-a15',
            'sm-a16',
            'sm-m14',
            'sm-m15',
          ]) ||
          _containsAny(rawName, const [
            'galaxy a04',
            'galaxy a05',
            'galaxy a06',
            'galaxy a14',
            'galaxy a15',
            'galaxy a16',
          ])) {
        return const _PopularLineRule(
          id: 'samsung_galaxy_a0x_a1x_entry',
          label: 'Samsung Galaxy A0x / A1x Series',
          deviceClass: VrDeviceClass.entry,
          visorTier: VrQualityTier.low,
        );
      }
    }

    if (maker == 'motorola') {
      if (_containsAny(rawName, const [
        'edge 30 pro',
        'edge 30 ultra',
        'edge 40 pro',
        'edge 50 pro',
        'edge 50 ultra',
        'razr 40 ultra',
        'razr 50 ultra',
        'thinkphone',
        'moto g200',
      ])) {
        return const _PopularLineRule(
          id: 'motorola_edge_flagship',
          label: 'Motorola Edge Pro / Ultra Series',
          deviceClass: VrDeviceClass.flagship,
          visorTier: VrQualityTier.medium,
        );
      }
      if (_containsAny(rawName, const [
        'edge 20',
        'edge 30',
        'edge 40',
        'edge 50',
        'moto g54',
        'moto g73',
        'moto g84',
        'moto g85',
        'moto g stylus 5g',
      ])) {
        final isUpperEdge = _containsAny(rawName, const [
          'edge 30 fusion',
          'edge 40',
          'edge 50',
        ]);
        return _PopularLineRule(
          id: 'motorola_edge_mid',
          label: 'Motorola Edge / Moto G5x-G8x Series',
          deviceClass: VrDeviceClass.mid,
          visorTier: isUpperEdge ? VrQualityTier.medium : VrQualityTier.low,
        );
      }
      if (rawName.startsWith('moto e') ||
          _containsAny(rawName, const [
            'moto g04',
            'moto g13',
            'moto g14',
            'moto g20',
            'moto g(20)',
            'moto g22',
            'moto g23',
            'moto g24',
            'moto g32',
            'moto g34',
          ])) {
        return const _PopularLineRule(
          id: 'motorola_moto_g_e_entry',
          label: 'Motorola Moto E / G Entry Series',
          deviceClass: VrDeviceClass.entry,
          visorTier: VrQualityTier.low,
        );
      }
    }

    if (maker == 'xiaomi' || maker == 'redmi' || maker == 'poco') {
      if (_containsAny(rawName, const [
        'redmi a1',
        'redmi a2',
        'redmi a3',
        'redmi 10c',
        'redmi 12c',
        'redmi 13c',
        'redmi 14c',
        'poco c40',
        'poco c55',
        'poco c65',
      ]) ||
          rawName == 'redmi 12') {
        return const _PopularLineRule(
          id: 'xiaomi_redmi_entry',
          label: 'Xiaomi Redmi A / C Entry Series',
          deviceClass: VrDeviceClass.entry,
          visorTier: VrQualityTier.low,
        );
      }
      if (_containsAny(rawName, const [
            'xiaomi 13',
            'xiaomi 14',
            'xiaomi 15',
            'poco f5',
            'poco f6',
            'redmi k60',
            'redmi k70',
          ]) &&
          !rawName.contains('lite')) {
        return const _PopularLineRule(
          id: 'xiaomi_poco_f_flagship',
          label: 'Xiaomi Flagship / POCO F Series',
          deviceClass: VrDeviceClass.flagship,
          visorTier: VrQualityTier.medium,
        );
      }
      if (_containsAny(rawName, const [
        'redmi note 11',
        'redmi note 12',
        'redmi note 13',
        'redmi note 14',
        'poco x5',
        'poco x6',
        'poco m6 pro',
        'xiaomi 12 lite',
        'xiaomi 13 lite',
      ])) {
        final isUpper = _containsAny(rawName, const ['x6 pro', 'pro+']);
        return _PopularLineRule(
          id: 'xiaomi_redmi_note_poco_x_mid',
          label: 'Redmi Note / POCO X Series',
          deviceClass: VrDeviceClass.mid,
          visorTier: isUpper ? VrQualityTier.medium : VrQualityTier.low,
        );
      }
    }

    if (maker == 'google') {
      if (_containsAny(rawName, const [
        'pixel 7 pro',
        'pixel 8',
        'pixel 9',
      ]) &&
          !rawName.endsWith('a')) {
        return const _PopularLineRule(
          id: 'google_pixel_flagship',
          label: 'Google Pixel Flagship',
          deviceClass: VrDeviceClass.flagship,
          visorTier: VrQualityTier.medium,
        );
      }
      if (rawName.contains('pixel')) {
        return const _PopularLineRule(
          id: 'google_pixel_a_mid',
          label: 'Google Pixel A Series',
          deviceClass: VrDeviceClass.mid,
          visorTier: VrQualityTier.medium,
        );
      }
    }

    if (maker == 'apple') {
      if (_containsAny(rawName, const [
        'iphone 14 pro',
        'iphone 15',
        'iphone 16',
        'iphone15,',
        'iphone16,',
        'iphone17,',
      ])) {
        return const _PopularLineRule(
          id: 'apple_iphone_flagship',
          label: 'Apple iPhone Pro / Modern Series',
          deviceClass: VrDeviceClass.flagship,
          visorTier: VrQualityTier.high,
        );
      }
      if (rawName.contains('iphone')) {
        return const _PopularLineRule(
          id: 'apple_iphone_mid',
          label: 'Apple iPhone Standard Series',
          deviceClass: VrDeviceClass.mid,
          visorTier: VrQualityTier.medium,
        );
      }
    }

    return null;
  }

  static bool _matchesAnyPrefix(String value, List<String> prefixes) {
    for (final prefix in prefixes) {
      if (value.startsWith(prefix)) return true;
    }
    return false;
  }

  static bool _containsAny(String value, List<String> needles) {
    for (final needle in needles) {
      if (value.contains(needle)) return true;
    }
    return false;
  }
}

@immutable
class _PopularLineRule {
  const _PopularLineRule({
    required this.id,
    required this.label,
    required this.deviceClass,
    required this.visorTier,
  });

  final String id;
  final String label;
  final VrDeviceClass deviceClass;
  final VrQualityTier visorTier;
}

int? _positiveInt(Object? raw) => raw is int && raw > 0 ? raw : null;

int? _nonNegativeInt(Object? raw) => raw is int && raw >= 0 ? raw : null;

bool? _optionalBool(Object? raw) => raw is bool ? raw : null;

String? _optionalLabel(Object? raw) {
  final cleaned = _deviceLabel(raw);
  return cleaned.isEmpty ? null : cleaned;
}

String _deviceLabel(Object? raw) {
  if (raw is! String || raw.length > 160) return '';
  return raw.replaceAll(RegExp(r'[\x00-\x1F\x7F]'), ' ').trim();
}
