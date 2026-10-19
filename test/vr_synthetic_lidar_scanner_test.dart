import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';
import 'package:vrlizate_scene/vrlizate_scene.dart';

void main() {
  group('VrSyntheticLidarScanner (Camera + Sonar + Wi-Fi + BLE)', () {
    test('acoustic sonar echo computes radial distance, TDOA azimuth, and wall patch', () {
      final scanner = VrSyntheticLidarScanner(voxelSizeMeters: 0.20);
      // 2.0 meters away -> roundTripSeconds = (2 * 2.0) / 343.0 = 0.0116618 s
      const echo = VrAcousticSonarEcho(
        roundTripSeconds: 4.0 / 343.0,
        dualMicPhaseDelaySeconds: 0.0,
        reflectionAmplitude: 0.90,
      );

      expect(echo.radialDistanceMeters, closeTo(2.0, 0.01));
      expect(echo.estimatedAzimuthRadians, closeTo(0.0, 0.001));

      final point = scanner.ingestAcousticSonarEcho(
        echo: echo,
        sensorPosition: Vector3(0.0, 1.6, 0.0),
        sensorForward: Vector3(0.0, 0.0, -1.0),
      );

      expect(point.position.z, closeTo(-2.0, 0.05));
      expect(point.primaryModality, VrSensingModality.acousticSonarEcho);
      expect(point.confidence, greaterThan(0.80));
      expect(scanner.reconstructedContours, isNotEmpty);
      expect(scanner.reconstructedObjects, hasLength(1));
    });

    test('dual-phone Wi-Fi RTT/RSSI and BLE radar triangulate anchors and shadowed walls', () {
      final scanner = VrSyntheticLidarScanner(voxelSizeMeters: 0.20);
      const wifiSample = VrRfRadioBeaconSample(
        beaconId: 'ap_living_room',
        label: 'Router Wi-Fi 6',
        modality: VrSensingModality.wifiRfSensing,
        visorRssiDbm: -58.0,
        joystickRssiDbm: -61.0,
        rttDistanceMeters: 3.2,
        estimatedWallAttenuationDb: 8.5, // >= 6 dB -> infers intervening wall!
      );

      expect(wifiSample.hasWallShadowing, isTrue);
      expect(wifiSample.estimateDistanceFromVisorMeters(), closeTo(3.1, 0.5));

      final point = scanner.ingestDualPhoneRfSample(
        sample: wifiSample,
        visorPosition: Vector3(0.0, 1.65, 0.0),
        visorForward: Vector3(0.0, 0.0, -1.0),
        joystickPosition: Vector3(0.0, 1.10, -0.25),
      );

      expect(point.primaryModality, VrSensingModality.wifiRfSensing);
      // Both the Wi-Fi anchor and the shadowed wall plane are reconstructed
      expect(scanner.reconstructedObjects.length, 2);
    });

    test('fusing Tri-Camera vision and Acoustic Sonar on same voxel boosts multi-modal confidence', () {
      final scanner = VrSyntheticLidarScanner(voxelSizeMeters: 0.25);
      const echo = VrAcousticSonarEcho(
        roundTripSeconds: 3.0 / 343.0, // 1.5 m
        reflectionAmplitude: 0.80,
      );

      final sonarPoint = scanner.ingestAcousticSonarEcho(
        echo: echo,
        sensorPosition: Vector3(0.0, 1.5, 0.0),
        sensorForward: Vector3(0.0, 0.0, -1.0),
      );

      final fusedPoint = scanner.ingestVisualDepthPoint(
        worldPosition: Vector3(0.0, 1.5, -1.5),
        normal: Vector3(0.0, 0.0, 1.0),
        category: VrSpatialObjectCategory.wall,
        confidence: 0.80,
      );

      expect(fusedPoint.voxelKey, sonarPoint.voxelKey);
      expect(fusedPoint.isMultiModalConfirmed, isTrue);
      expect(
        fusedPoint.contributingModalities,
        containsAll(<VrSensingModality>[
          VrSensingModality.acousticSonarEcho,
          VrSensingModality.triCameraVision,
        ]),
      );
      expect(fusedPoint.confidence, greaterThan(sonarPoint.confidence));

      final mapper = VrMultiCameraSpaceMapper();
      scanner.syncToSpaceMapper(mapper);
      expect(mapper.objects, isNotEmpty);
    });

    test('environmental hardware sensors (Barometer, Magnetometer, PDAF, ALS, UWB, IMU) enrich voxel cloud', () {
      final scanner = VrSyntheticLidarScanner(voxelSizeMeters: 0.25);
      final sample = VrEnvironmentalHardwareSample(
        visorPressureHpa: 1013.20,
        joystickPressureHpa: 1013.27, // +0.07 hPa -> ~0.59 m height delta
        localMagneticMicroTesla: Vector3(48.0, -15.0, 32.0),
        earthReferenceMagneticMicroTesla: Vector3(22.0, -12.0, 28.0),
        lensFocusDistanceDiopters: 1.25, // 1 / 1.25 = 0.80 m
        ambientLux: 620.0,
        colorTemperatureKelvin: 5800.0,
        uwbDistanceMeters: 0.58,
        heelStrikeShockG: 1.65,
      );

      expect(sample.barometricHeightDeltaMeters, closeTo(0.59, 0.05));
      expect(sample.hasFerromagneticObstacle, isTrue);
      expect(sample.pdafFocusDepthMeters, closeTo(0.80, 0.01));
      expect(sample.detectsDaylightWindowDirection, isTrue);

      final points = scanner.ingestEnvironmentalHardwareSample(
        sample: sample,
        sensorPosition: Vector3(0.0, 1.5, 0.0),
        sensorForward: Vector3(0.0, 0.0, -1.0),
      );

      expect(points.length, greaterThanOrEqualTo(4));
      // The voxel at 0.80m is confirmed by both PDAF focus and Magnetometer anomaly!
      final tablePoint = points.firstWhere(
        (p) => p.contributingModalities.contains(
          VrSensingModality.magneticAnomalyField,
        ),
      );
      expect(tablePoint.isMultiModalConfirmed, isTrue);
    });

    test('Galaxy S25 Visor + Moto Edge Joystick profile offloads CPU to Joystick and protects 90-120 FPS Visor budget', () {
      final profile = VrDeviceSensorPairProfile.s25VisorAndMotoEdgeJoystick();
      expect(profile.visorModelName, 'Samsung Galaxy S25');
      expect(profile.joystickModelName, 'Motorola Edge');
      // 120 deg Ultra-Wide rear camera on Moto Edge at 1.05m covers > 3.5m floor circle
      expect(profile.floorCoverageDiameterMeters(joystickHeightMeters: 1.05), greaterThan(3.5));

      final scheduler = VrSpatialCaptureScheduler(profile: profile);
      final budget = scheduler.evaluateResourceBudget(
        userSpeedMetersPerSec: 0.30,
        visorFrameTimeMs: 8.3,
      );

      expect(budget.isVisorFrameBudgetProtected, isTrue);
      expect(budget.visorCpuLoadPercent, lessThan(2.5));
      expect(budget.joystickCpuLoadPercent, greaterThan(budget.visorCpuLoadPercent));
      expect(
        scheduler.shouldSampleModality(
          modality: VrSensingModality.acousticSonarEcho,
          elapsedSeconds: 0.10,
        ),
        isTrue,
      );
      expect(
        scheduler.shouldSampleModality(
          modality: VrSensingModality.acousticSonarEcho,
          elapsedSeconds: 0.12,
        ),
        isFalse,
      );
    });
  });
}
