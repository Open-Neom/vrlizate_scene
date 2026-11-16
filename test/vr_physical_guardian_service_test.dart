import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';
import 'package:vrlizate_scene/vrlizate_scene.dart';

void main() {
  group('VrPhysicalGuardianService (Auto-Passthrough & Comfort Motion Shield)', () {
    const guardian = VrPhysicalGuardianService();

    final physicalWall = VrDetectedSpatialObject.fromBoundingBox3D(
      id: 'wall_north',
      label: 'Pared Norte',
      category: VrSpatialObjectCategory.wall,
      centerWorld: Vector3(0.0, 1.4, -2.0),
      extentsWorld: Vector3(3.0, 2.8, 0.20), // South face at z = -1.90
    );

    final coffeeTable = VrDetectedSpatialObject.fromBoundingBox3D(
      id: 'table_center',
      label: 'Mesa de centro',
      category: VrSpatialObjectCategory.table,
      centerWorld: Vector3(1.5, 0.45, 0.0),
      extentsWorld: Vector3(0.80, 0.50, 0.80),
    );

    final userHandController = VrDetectedSpatialObject.fromBoundingBox3D(
      id: 'joystick_hand',
      label: 'Controlador Joystick',
      category: VrSpatialObjectCategory.handController,
      centerWorld: Vector3(0.0, 1.1, -0.25),
      extentsWorld: Vector3(0.16, 0.08, 0.08),
    );

    test('remains clear with 0% auto-passthrough when far from obstacles and ignores hand controllers', () {
      // Viewer at origin: handController is 0.21m away, but wall is 1.90m away and table is 1.10m away
      final state = guardian.evaluate(
        viewerPosition: Vector3(0.0, 1.65, 0.0),
        detectedObjects: <VrDetectedSpatialObject>[
          physicalWall,
          coffeeTable,
          userHandController,
        ],
      );

      expect(state.alertLevel, VrGuardianAlertLevel.clear);
      expect(state.alertLevel.isAlertActive, isFalse);
      expect(state.nearestObstacleId, 'table_center');
      expect(state.nearestObstacleDistanceMeters, closeTo(1.10, 0.01));
      expect(state.recommendedPassthroughFloorMix, 0.0);
      expect(state.isPassthroughTriggered, isFalse);
      expect(state.comfortVignetteIntensity, 0.0);
      expect(state.statusMessage, VrSceneTranslationConstants.guardianStatusClear);
    });

    test('smoothly ramps auto-passthrough from 0.0 to 1.0 when approaching obstacle (< 0.95 m)', () {
      // Wall south face is at z = -1.90.
      // Viewer at z = -1.20 -> distance to wall face is 0.70 m (< 0.95 m warning, > 0.42 m critical)
      final approaching = guardian.evaluate(
        viewerPosition: Vector3(0.0, 1.65, -1.20),
        detectedObjects: <VrDetectedSpatialObject>[physicalWall],
      );

      expect(approaching.alertLevel, VrGuardianAlertLevel.approachingObstacle);
      expect(approaching.alertLevel.isAlertActive, isTrue);
      expect(approaching.nearestObstacleId, 'wall_north');
      expect(approaching.nearestObstacleDistanceMeters, closeTo(0.70, 0.01));
      expect(approaching.recommendedPassthroughFloorMix, greaterThan(0.40));
      expect(approaching.recommendedPassthroughFloorMix, lessThan(0.60));
      expect(approaching.obstacleDirectionWorld.z, closeTo(-1.0, 0.01));
      expect(
        approaching.statusMessage,
        VrSceneTranslationConstants.guardianStatusApproaching,
      );
    });

    test('triggers criticalBoundaryBreach, keeps manual controllerPassthroughMix separate, and restores mix when cleared', () {
      final mapper = VrMultiCameraSpaceMapper(
        mode: VrPassthroughMode.multiCameraHybridSpace,
        controllerPassthroughMix: 0.20,
      );
      mapper.upsertObject(physicalWall);

      // Viewer at z = -1.55 -> 0.35 m from wall face (<= 0.42 m critical)
      final breach = guardian.evaluateSpaceMapper(
        viewerPosition: Vector3(0.0, 1.65, -1.55),
        spaceMapper: mapper,
      );

      expect(breach.alertLevel, VrGuardianAlertLevel.criticalBoundaryBreach);
      expect(breach.isCritical, isTrue);
      expect(breach.recommendedPassthroughFloorMix, 1.0);
      // Temporary Guardian floor rises to 1.0 while manual mix stays 0.20!
      expect(mapper.guardianPassthroughFloorMix, 1.0);
      expect(mapper.controllerPassthroughMix, closeTo(0.20, 1e-4));
      expect(mapper.effectivePassthroughMix, 1.0);
      expect(
        mapper
            .evaluateVisibility(
              viewerPosition: Vector3(0.0, 1.65, -1.55),
              headPitchRadians: 0.0,
            )
            .cameraFeedOpacity,
        1.0,
      );
      expect(
        breach.statusMessage,
        VrSceneTranslationConstants.guardianStatusCriticalBreach,
      );

      // Once obstacle clears, temporary floor drops to 0.0 and manual 0.20 mix is restored.
      mapper.removeObject('wall_north');
      final cleared = guardian.evaluateSpaceMapper(
        viewerPosition: Vector3(0.0, 1.65, -1.55),
        spaceMapper: mapper,
      );
      expect(cleared.alertLevel, VrGuardianAlertLevel.clear);
      expect(mapper.guardianPassthroughFloorMix, 0.0);
      expect(mapper.controllerPassthroughMix, closeTo(0.20, 1e-4));
      expect(mapper.effectivePassthroughMix, closeTo(0.20, 1e-4));
    });

    test('ignores zero-confidence detections, respects VrPassthroughMode.off unless opted in, and prunes stale obstacles (A06)', () {
      final mapper = VrMultiCameraSpaceMapper(mode: VrPassthroughMode.off);

      // 1. Zero-confidence obstacle never triggers Guardian alert or passthrough
      mapper.upsertObject(
        VrDetectedSpatialObject.fromBoundingBox3D(
          id: 'uncertain',
          label: 'uncertain',
          category: VrSpatialObjectCategory.wall,
          centerWorld: Vector3(0.0, 1.6, -0.2),
          extentsWorld: Vector3.all(0.1),
          confidence: 0.0,
        ),
      );
      final zeroConf = guardian.evaluateSpaceMapper(
        viewerPosition: Vector3.zero(),
        spaceMapper: mapper,
      );
      expect(zeroConf.alertLevel, VrGuardianAlertLevel.clear);
      expect(
        mapper
            .evaluateVisibility(
              viewerPosition: Vector3.zero(),
              headPitchRadians: 0.0,
            )
            .cameraFeedOpacity,
        0.0,
      );

      // 2. High-confidence obstacle in mode=off raises alertLevel, but keeps cameraFeedOpacity=0
      //    unless allowGuardianPassthroughWhenOff or allowOverrideOffMode is explicitly enabled.
      mapper.clear();
      mapper.upsertObject(
        physicalWall,
        timestampMicros: 100000,
      );
      final offModeBreach = guardian.evaluateSpaceMapper(
        viewerPosition: Vector3(0.0, 1.65, -1.55),
        spaceMapper: mapper,
      );
      expect(
        offModeBreach.alertLevel,
        VrGuardianAlertLevel.criticalBoundaryBreach,
      );
      expect(mapper.controllerPassthroughMix, 0.0);
      expect(mapper.guardianPassthroughFloorMix, 0.0);
      expect(
        mapper
            .evaluateVisibility(
              viewerPosition: Vector3(0.0, 1.65, -1.55),
              headPitchRadians: 0.0,
            )
            .cameraFeedOpacity,
        0.0,
      );

      // Opt-in override in mode=off turns on temporary passthrough floor AND effective cameraFeedOpacity=1.0
      // without mutating manual controllerPassthroughMix or persistent allowGuardianPassthroughWhenOff.
      final optInBreach = guardian.evaluateSpaceMapper(
        viewerPosition: Vector3(0.0, 1.65, -1.55),
        spaceMapper: mapper,
        allowOverrideOffMode: true,
        nowMicros: 500000,
      );
      expect(optInBreach.isCritical, isTrue);
      expect(mapper.guardianPassthroughFloorMix, 1.0);
      expect(mapper.effectivePassthroughMix, 1.0);
      expect(mapper.controllerPassthroughMix, 0.0);
      expect(mapper.allowGuardianPassthroughWhenOff, isFalse);
      expect(
        mapper
            .evaluateVisibility(
              viewerPosition: Vector3(0.0, 1.65, -1.55),
              headPitchRadians: 0.0,
            )
            .cameraFeedOpacity,
        1.0,
      );

      // Next evaluate without allowOverrideOffMode immediately restores floor=0 and cameraFeedOpacity=0
      // without leaving any permanent opt-in enabled.
      final nextWithoutFlag = guardian.evaluateSpaceMapper(
        viewerPosition: Vector3(0.0, 1.65, -1.55),
        spaceMapper: mapper,
        nowMicros: 600000,
      );
      expect(nextWithoutFlag.isCritical, isTrue);
      expect(mapper.guardianPassthroughFloorMix, 0.0);
      expect(mapper.effectivePassthroughMix, 0.0);
      expect(mapper.controllerPassthroughMix, 0.0);
      expect(mapper.allowGuardianPassthroughWhenOff, isFalse);
      expect(
        mapper
            .evaluateVisibility(
              viewerPosition: Vector3(0.0, 1.65, -1.55),
              headPitchRadians: 0.0,
            )
            .cameraFeedOpacity,
        0.0,
      );

      // Re-enable per-call opt-in, then let stale obstacle (> 900 ms after timestampMicros: 100000) expire automatically.
      guardian.evaluateSpaceMapper(
        viewerPosition: Vector3(0.0, 1.65, -1.55),
        spaceMapper: mapper,
        allowOverrideOffMode: true,
        nowMicros: 700000,
      );
      expect(mapper.effectivePassthroughMix, 1.0);

      final expired = guardian.evaluateSpaceMapper(
        viewerPosition: Vector3(0.0, 1.65, -1.55),
        spaceMapper: mapper,
        allowOverrideOffMode: true,
        nowMicros: 1500000,
      );
      expect(expired.alertLevel, VrGuardianAlertLevel.clear);
      expect(mapper.guardianPassthroughFloorMix, 0.0);
      expect(mapper.effectivePassthroughMix, 0.0);
      expect(
        mapper
            .evaluateVisibility(
              viewerPosition: Vector3(0.0, 1.65, -1.55),
              headPitchRadians: 0.0,
            )
            .cameraFeedOpacity,
        0.0,
      );
      expect(mapper.objects, isEmpty);
    });

    test('computes comfort vignette intensity (0.0 .. 0.40) during fast linear or angular locomotion', () {
      final slowState = guardian.evaluate(
        viewerPosition: Vector3.zero(),
        detectedObjects: const <VrDetectedSpatialObject>[],
        locomotionSpeedMetersPerSec: 0.40,
        angularSpeedRadiansPerSec: 0.25,
      );
      expect(slowState.comfortVignetteIntensity, 0.0);

      final fastTurnState = guardian.evaluate(
        viewerPosition: Vector3.zero(),
        detectedObjects: const <VrDetectedSpatialObject>[],
        locomotionSpeedMetersPerSec: 1.80,
        angularSpeedRadiansPerSec: 2.50,
      );
      expect(
        fastTurnState.comfortVignetteIntensity,
        closeTo(VrSceneConstants.guardianMaxComfortVignetteIntensity, 0.01),
      );
    });
  });
}
