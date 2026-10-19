/// Shared constants for `vrlizate_scene` stereo rendering, lighting presets,
/// and spatial scene transitions.
abstract final class VrSceneConstants {
  static const double defaultConvergenceDistanceMeters = 1.8;
  static const double defaultIpdMeters = 0.064;
  static const double defaultGazeDwellSeconds = 2.6;
  static const double defaultGazeActivationDelaySeconds = 0.35;
  static const double defaultButtonBDragHoldSeconds = 0.85;

  static const int defaultTransitionDurationMs = 450;
  static const double minTransitionProgress = 0.0;
  static const double maxTransitionProgress = 1.0;
  static const double smoothstepFactorA = 3.0;
  static const double smoothstepFactorB = 2.0;

  static const double defaultBaseFovDegrees = 90.0;
  static const double instantWarpDeltaDegrees = 0.0;
  static const double smoothFadeWarpDeltaDegrees = 6.0;
  static const double portalIrisWarpDeltaDegrees = 18.0;
  static const double zoomSlideWarpDeltaDegrees = 24.0;

  static const double minIrisAperture = 0.0;
  static const double maxIrisAperture = 1.0;

  static const String lightingDaylightId = 'daylight';
  static const String lightingNeonArcadeId = 'neon_arcade';
  static const String lightingWarmGalleryId = 'warm_gallery';
  static const String lightingDeepSpaceId = 'deep_space';
  static const String lightingSunsetId = 'sunset';

  static const int daylightAmbientArgb = 0xFFE8F4FF;
  static const int daylightDirectionalArgb = 0xFFFFF8E7;
  static const double daylightAmbientIntensity = 0.75;
  static const double daylightDirectionalIntensity = 1.20;

  static const int neonArcadeAmbientArgb = 0xFF1A103C;
  static const int neonArcadeDirectionalArgb = 0xFF00F0FF;
  static const double neonArcadeAmbientIntensity = 0.45;
  static const double neonArcadeDirectionalIntensity = 1.35;

  static const int warmGalleryAmbientArgb = 0xFFF5EBE1;
  static const int warmGalleryDirectionalArgb = 0xFFFFDFB8;
  static const double warmGalleryAmbientIntensity = 0.65;
  static const double warmGalleryDirectionalIntensity = 1.00;

  static const int deepSpaceAmbientArgb = 0xFF090C1C;
  static const int deepSpaceDirectionalArgb = 0xFF8AA8FF;
  static const double deepSpaceAmbientIntensity = 0.25;
  static const double deepSpaceDirectionalIntensity = 0.90;

  static const int sunsetAmbientArgb = 0xFF3E1F47;
  static const int sunsetDirectionalArgb = 0xFFFF7B54;
  static const double sunsetAmbientIntensity = 0.55;
  static const double sunsetDirectionalIntensity = 1.10;

  static const String transitionInstantId = 'instant';
  static const String transitionSmoothFadeId = 'smooth_fade';
  static const String transitionPortalIrisId = 'portal_iris';
  static const String transitionZoomSlideId = 'zoom_slide';

  // Passthrough & Multi-Camera AI Wireframe Space Mapping constants
  static const String cameraSourceVisorFront = 'visor_front';
  static const String cameraSourceJoystickRear = 'joystick_rear';
  static const String cameraSourceJoystickFront = 'joystick_front';

  static const double defaultSafetyProximityRadiusMeters = 1.15;
  static const double criticalSafetyProximityRadiusMeters = 0.55;
  static const double glanceDownPitchThresholdRadians = -0.48; // ~ -27.5 deg
  static const double fullGlanceDownPitchRadians = -0.85; // ~ -48.7 deg
  static const double defaultContourStrokeWidth = 2.2;

  static const int contourColorFloorBoundaryArgb = 0xFF00F5D4;
  static const int contourColorWallArgb = 0xFF3A86FF;
  static const int contourColorFurnitureArgb = 0xFFFFBE0B;
  static const int contourColorPersonPetArgb = 0xFFFF006E;
  static const int contourColorObstacleAlertArgb = 0xFFFF3B30;
  static const int contourColorHandControllerArgb = 0xFF8338EC;

  // Synthetic LiDAR (Acoustic Sonar + Wi-Fi RTT/RSSI + BLE Radar + Voxel Grid)
  static const String modalityTriCameraVisionId = 'tri_camera_vision';
  static const String modalityAcousticSonarEchoId = 'acoustic_sonar_echo';
  static const String modalityWifiRfSensingId = 'wifi_rf_sensing';
  static const String modalityBluetoothBleRadarId = 'bluetooth_ble_radar';
  static const String modalityDifferentialBarometerId =
      'differential_barometer';
  static const String modalityMagneticAnomalyFieldId =
      'magnetic_anomaly_field';
  static const String modalityCameraPdafFocusDepthId =
      'camera_pdaf_focus_depth';
  static const String modalityAmbientLightAndIrProximityId =
      'ambient_light_ir_proximity';
  static const String modalityUltraWidebandToFId = 'ultra_wideband_tof';
  static const String modalityImuFootstepVibrometryId =
      'imu_footstep_vibrometry';

  static const double barometricMetersPerHpaAtRoomTemp = 8.43;
  static const double ferromagneticAnomalyThresholdMicroTesla = 18.0;
  static const double minPdafFocusDiopters = 0.15;
  static const double maxPdafFocusDistanceMeters = 6.50;
  static const double daylightWindowColorTempKelvin = 5200.0;
  static const double windowLightMinLux = 350.0;

  static const double speedOfSoundMetersPerSec = 343.0;
  static const double defaultSmartphoneMicBaselineMeters = 0.145;
  static const double defaultUltrasonicSonarCarrierHz = 20000.0;
  static const double minSonarEchoDistanceMeters = 0.20;
  static const double maxSonarEchoDistanceMeters = 8.00;
  static const double sonarPatchHalfWidthMeters = 0.28;

  static const double defaultRfTxPowerAtOneMeterDbm = -45.0;
  static const double defaultIndoorPathLossExponent = 2.2;
  static const double minRfDistanceMeters = 0.30;
  static const double maxRfDistanceMeters = 15.0;
  static const double rttFusionWeight = 0.80;
  static const double rssiFusionWeight = 0.20;
  static const double rfWallShadowingThresholdDb = 6.0;
  static const double rfBeaconBoundingSizeMeters = 0.36;

  static const double defaultLidarVoxelSizeMeters = 0.15;
  static const double occupancyHitConfidenceDelta = 0.35;
  static const double multiModalSynergyBonus = 0.20;
  static const double minOccupiedVoxelConfidence = 0.50;
  static const String syntheticSonarWallPrefix = 'sonar_surface_';
  static const String syntheticRfAnchorPrefix = 'rf_anchor_';
  static const String syntheticRfWallShadowPrefix = 'rf_wall_shadow_';

  // Reference Two-Devices VR Pair: Samsung Galaxy S25 Visor + Motorola Edge Joystick
  static const String referenceVisorS25ModelName = 'Samsung Galaxy S25';
  static const String referenceJoystickMotoEdgeModelName = 'Motorola Edge';
  static const String genericVisorModelName = 'Generic Smartphone Visor';
  static const String genericJoystickModelName = 'Generic Smartphone Joystick';

  static const double s25VisorUltraWideFovDegrees = 120.0;
  static const double motoEdgeRearUltraWideFovDegrees = 120.0;
  static const double motoEdgeFrontSelfieFovDegrees = 84.0;
  static const double genericRearCameraFovDegrees = 78.0;
  static const double genericFrontCameraFovDegrees = 74.0;

  static const double s25MicBaselineMeters = 0.147;
  static const double motoEdgeMicBaselineMeters = 0.158;
  static const double motoEdgeTouchSamplingHz = 240.0;
  static const double genericTouchSamplingHz = 120.0;

  // Spatial Capture Power Modes & Adaptive Multi-Rate Duty-Cycling
  static const String powerModeUltraLowId = 'ultra_low_power';
  static const String powerModeBalancedAdaptiveId = 'balanced_adaptive';
  static const String powerModeHighPrecisionId = 'high_precision_scan';
  static const String powerModeJoystickOffloadedId =
      'joystick_offloaded_visor_priority';

  static const double defaultTargetFrameBudgetMs = 11.1; // 90 FPS stereo budget
  static const double visorThermalThrottleFrameMs = 15.2;
}


