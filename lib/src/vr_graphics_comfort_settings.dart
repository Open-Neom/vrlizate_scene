import 'package:flutter/foundation.dart';

import 'quality_preset.dart';
import 'vr_sgsr_upscale_post_process.dart';

/// Spatial upscaling mode backed by Qualcomm Snapdragon Game Super Resolution 1
/// (`SGSR 1`, `BSD-3-Clause`).
enum VrSgsrMode {
  /// Automatically enables `0.82×` SGSR in stereo VR on low/medium tiers while
  /// keeping 1D mono and high/ultra presets at native `1.0×` clarity.
  auto('Auto'),

  /// Native `1.0×` rendering with no spatial upscaling pass.
  off('Off 1.0×'),

  /// High-clarity spatial reconstruction (`0.82×`, ~`33%` fewer shaded pixels).
  quality('Calidad 0.82×'),

  /// Balanced mobile VR boost (`0.75×`, ~`44%` fewer shaded pixels).
  balanced('Equil. 0.75×'),

  /// High-FPS / battery & thermal boost (`0.67×`, ~`55%` fewer shaded pixels).
  performance('Turbo 0.67×');

  const VrSgsrMode(this.shortLabelEs);
  final String shortLabelEs;
}

/// Horizontal turning style supported across 1D handheld, 2D Joystick, and 3D
/// Faro sessions (matching Meta Quest / VRChat / Steam Deck comfort norms).
enum VrTurnMode {
  smooth('Suave', 0),
  snap30('Snap 30°', 30),
  snap45('Snap 45°', 45);

  const VrTurnMode(this.shortLabelEs, this.snapDegrees);
  final String shortLabelEs;
  final int snapDegrees;

  bool get isSnap => snapDegrees > 0;
}

/// Compact real-time render telemetry published at ~2 Hz when the user enables
/// the optional performance HUD (`showPerformanceHud`).
@immutable
class VrLiveFrameMetrics {
  const VrLiveFrameMetrics({
    required this.fps,
    required this.frameMs,
    required this.tier,
    required this.sgsrScale,
    required this.isStereo,
  });

  static const initial = VrLiveFrameMetrics(
    fps: 60.0,
    frameMs: 16.7,
    tier: VrQualityTier.medium,
    sgsrScale: 1.0,
    isStereo: false,
  );

  final double fps;
  final double frameMs;
  final VrQualityTier tier;
  final double sgsrScale;
  final bool isStereo;

  String get compactLabel {
    final tierLabel = switch (tier) {
      VrQualityTier.low => 'BAJA',
      VrQualityTier.medium => 'MEDIA',
      VrQualityTier.high => 'ALTA',
      VrQualityTier.ultra => 'ULTRA 1.15×',
    };
    final scaleTag = sgsrScale < 0.999
        ? 'SGSR ${sgsrScale.toStringAsFixed(2)}×'
        : 'NATIVO';
    final viewTag = isStereo ? 'VR' : '1D';
    return '${fps.round()} FPS · ${frameMs.toStringAsFixed(1)} ms · $tierLabel · $scaleTag · $viewTag';
  }
}

/// Shared, zero-dependency graphics resolution, FPS upscaling, and locomotion
/// comfort settings synchronized across `StereoSceneView`, `VirtualHomeScene`,
/// Famous Malls, Open Source Arcade, and Settings UI (`1D`, `2D`, `3D`).
class VrGraphicsComfortSettings extends ChangeNotifier {
  VrGraphicsComfortSettings({
    VrQualityTier? qualityOverride,
    VrSgsrMode sgsrMode = VrSgsrMode.auto,
    VrTurnMode turnMode = VrTurnMode.smooth,
    bool comfortVignetteEnabled = true,
    bool handheldGyroAimEnabled = false,
    bool showPerformanceHud = false,
    bool crispHandheldBoost = true,
  }) : _qualityOverride = qualityOverride,
       _sgsrMode = sgsrMode,
       _turnMode = turnMode,
       _comfortVignetteEnabled = comfortVignetteEnabled,
       _handheldGyroAimEnabled = handheldGyroAimEnabled,
       _showPerformanceHud = showPerformanceHud,
       _crispHandheldBoost = crispHandheldBoost;

  /// Process-wide singleton observed by `StereoSceneView` and Settings.
  static final VrGraphicsComfortSettings instance = VrGraphicsComfortSettings();

  VrQualityTier? _qualityOverride;
  VrSgsrMode _sgsrMode;
  VrTurnMode _turnMode;
  bool _comfortVignetteEnabled;
  bool _handheldGyroAimEnabled;
  bool _showPerformanceHud;
  bool _crispHandheldBoost;

  /// Updated at ~2 Hz exclusively while [showPerformanceHud] is enabled.
  final ValueNotifier<VrLiveFrameMetrics> telemetry =
      ValueNotifier<VrLiveFrameMetrics>(VrLiveFrameMetrics.initial);

  VrQualityTier? get qualityOverride => _qualityOverride;
  VrSgsrMode get sgsrMode => _sgsrMode;
  VrTurnMode get turnMode => _turnMode;
  bool get comfortVignetteEnabled => _comfortVignetteEnabled;
  bool get handheldGyroAimEnabled => _handheldGyroAimEnabled;
  bool get showPerformanceHud => _showPerformanceHud;
  bool get crispHandheldBoost => _crispHandheldBoost;

  set qualityOverride(VrQualityTier? value) {
    if (_qualityOverride == value) return;
    _qualityOverride = value;
    notifyListeners();
  }

  set sgsrMode(VrSgsrMode value) {
    if (_sgsrMode == value) return;
    _sgsrMode = value;
    notifyListeners();
  }

  set turnMode(VrTurnMode value) {
    if (_turnMode == value) return;
    _turnMode = value;
    notifyListeners();
  }

  set comfortVignetteEnabled(bool value) {
    if (_comfortVignetteEnabled == value) return;
    _comfortVignetteEnabled = value;
    notifyListeners();
  }

  set handheldGyroAimEnabled(bool value) {
    if (_handheldGyroAimEnabled == value) return;
    _handheldGyroAimEnabled = value;
    notifyListeners();
  }

  set showPerformanceHud(bool value) {
    if (_showPerformanceHud == value) return;
    _showPerformanceHud = value;
    notifyListeners();
  }

  set crispHandheldBoost(bool value) {
    if (_crispHandheldBoost == value) return;
    _crispHandheldBoost = value;
    notifyListeners();
  }

  /// Applies multiple fields in a single notification (e.g. restoring persisted
  /// user preferences at startup).
  void apply({
    VrQualityTier? qualityOverride,
    bool clearQualityOverride = false,
    VrSgsrMode? sgsrMode,
    VrTurnMode? turnMode,
    bool? comfortVignetteEnabled,
    bool? handheldGyroAimEnabled,
    bool? showPerformanceHud,
    bool? crispHandheldBoost,
  }) {
    var changed = false;
    if (clearQualityOverride && _qualityOverride != null) {
      _qualityOverride = null;
      changed = true;
    } else if (!clearQualityOverride &&
        qualityOverride != null &&
        _qualityOverride != qualityOverride) {
      _qualityOverride = qualityOverride;
      changed = true;
    }
    if (sgsrMode != null && _sgsrMode != sgsrMode) {
      _sgsrMode = sgsrMode;
      changed = true;
    }
    if (turnMode != null && _turnMode != turnMode) {
      _turnMode = turnMode;
      changed = true;
    }
    if (comfortVignetteEnabled != null &&
        _comfortVignetteEnabled != comfortVignetteEnabled) {
      _comfortVignetteEnabled = comfortVignetteEnabled;
      changed = true;
    }
    if (handheldGyroAimEnabled != null &&
        _handheldGyroAimEnabled != handheldGyroAimEnabled) {
      _handheldGyroAimEnabled = handheldGyroAimEnabled;
      changed = true;
    }
    if (showPerformanceHud != null &&
        _showPerformanceHud != showPerformanceHud) {
      _showPerformanceHud = showPerformanceHud;
      changed = true;
    }
    if (crispHandheldBoost != null &&
        _crispHandheldBoost != crispHandheldBoost) {
      _crispHandheldBoost = crispHandheldBoost;
      changed = true;
    }
    if (changed) notifyListeners();
  }

  /// Resolves the effective [VrQualityPreset] combining explicit user overrides
  /// and 1D single-camera headroom boost (rendering 1 eye instead of 2 cuts
  /// geometry draw calls in half, safely allowing sharper native resolution).
  VrQualityPreset resolvePreset(
    VrQualityPreset basePreset, {
    required bool isHandheldMono,
  }) {
    if (_qualityOverride != null) {
      return VrQualityPreset.forTier(_qualityOverride!);
    }
    if (isHandheldMono &&
        _crispHandheldBoost &&
        basePreset.tier == VrQualityTier.low) {
      return VrQualityPreset.medium;
    }
    return basePreset;
  }

  /// Resolves the active Qualcomm `SGSR 1` spatial upscaling configuration.
  VrSgsrUpscaleConfig resolveSgsrConfig(
    VrQualityPreset activePreset, {
    required bool isStereo,
  }) => switch (_sgsrMode) {
    VrSgsrMode.off => VrSgsrUpscaleConfig.disabled,
    VrSgsrMode.quality => VrSgsrUpscaleConfig.mobileQuality,
    VrSgsrMode.balanced => VrSgsrUpscaleConfig.mobileBalanced,
    VrSgsrMode.performance => VrSgsrUpscaleConfig.mobilePerformance,
    VrSgsrMode.auto =>
      (isStereo && activePreset.tier.index <= VrQualityTier.medium.index)
          ? VrSgsrUpscaleConfig.mobileQuality
          : VrSgsrUpscaleConfig.disabled,
  };

  /// Computes target peripheral anti-nausea comfort vignette strength (`0..0.38`)
  /// from instantaneous angular turn rate (`rad/s`) and linear speed (`m/s`),
  /// mirroring Meta Quest / VRChat comfort tunnels. Returns `0` when stationary,
  /// disabled, or in flat 1D handheld mode.
  double computeComfortVignetteTarget({
    required double yawRateRadPerSec,
    required double linearSpeedMetersPerSec,
    required bool isStereo,
  }) {
    if (!isStereo || !_comfortVignetteEnabled) return 0.0;
    final turnFactor = ((yawRateRadPerSec.abs() - 0.75) / 1.45).clamp(0.0, 1.0);
    final speedFactor = ((linearSpeedMetersPerSec - 2.8) / 2.6).clamp(0.0, 1.0);
    final peak = turnFactor > speedFactor ? turnFactor : speedFactor;
    return peak * 0.38;
  }

  void publishTelemetry(VrLiveFrameMetrics metrics) {
    telemetry.value = metrics;
  }

  void resetToDefaults() {
    apply(
      clearQualityOverride: true,
      sgsrMode: VrSgsrMode.auto,
      turnMode: VrTurnMode.smooth,
      comfortVignetteEnabled: true,
      handheldGyroAimEnabled: false,
      showPerformanceHud: false,
      crispHandheldBoost: true,
    );
  }
}
