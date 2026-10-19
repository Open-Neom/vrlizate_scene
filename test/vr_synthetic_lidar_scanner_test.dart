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
  });
}
