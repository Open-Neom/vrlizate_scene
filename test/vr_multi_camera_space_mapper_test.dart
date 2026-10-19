import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;
import 'package:vrlizate_scene/vrlizate_scene.dart';

void main() {
  group('VrMultiCameraSpaceMapper & AI Wireframe Passthrough', () {
    test('projects 2D camera contours from Visor and Joystick onto 3D floor map', () {
      final mapper = VrMultiCameraSpaceMapper(
        mode: VrPassthroughMode.multiCameraHybridSpace,
      );

      // Project a floor boundary edge from the Joystick Rear Camera at height 1.1 m
      final joyRearOrientation = vm.Quaternion.axisAngle(
        vm.Vector3(1.0, 0.0, 0.0),
        -1.05,
      );
      final floorSegment = mapper.projectImageContourToWorld(
        uvStart: vm.Vector2(0.25, 0.5),
        uvEnd: vm.Vector2(0.75, 0.5),
        cameraPosition: vm.Vector3(0.0, 1.1, -0.35),
        cameraOrientation: joyRearOrientation,
        floorY: 0.0,
        category: VrSpatialObjectCategory.floorBoundary,
      );

      expect(floorSegment.startWorld.y, closeTo(0.0, 1e-4));
      expect(floorSegment.endWorld.y, closeTo(0.0, 1e-4));
      expect(floorSegment.lengthMeters, greaterThan(0.25));

      // Add a 3D AI-identified table ahead of the Visor camera
      final table = VrDetectedSpatialObject.fromBoundingBox3D(
        id: 'table_1',
        label: 'Mesa de centro',
        category: VrSpatialObjectCategory.table,
        centerWorld: vm.Vector3(0.0, 0.45, -1.20),
        extentsWorld: vm.Vector3(0.90, 0.75, 0.60),
        sourceCameraId: VrSceneConstants.cameraSourceVisorFront,
      );
      mapper.upsertObject(table);

      expect(table.contourSegments.length, 12);
      expect(mapper.allContourSegments.length, 13);

      // Far from table & looking straight ahead -> subtle wireframe only
      final farVis = mapper.evaluateVisibility(
        viewerPosition: vm.Vector3(0.0, 1.65, 1.0),
        headPitchRadians: 0.0,
      );
      expect(farVis.wireframeOpacity, closeTo(0.20, 0.01));
      expect(farVis.cameraFeedOpacity, closeTo(0.0, 0.01));

      // Stepping close to the table (< 1.15 m) -> proximity alert boosts wireframe & passthrough
      final nearVis = mapper.evaluateVisibility(
        viewerPosition: vm.Vector3(0.0, 1.65, -0.25),
        headPitchRadians: 0.0,
      );
      expect(nearVis.wireframeOpacity, greaterThan(0.75));
      expect(nearVis.cameraFeedOpacity, greaterThan(0.20));

      // Glancing down at the floor (pitch = -0.80 rad) -> floor passthrough blends in
      final glanceVis = mapper.evaluateVisibility(
        viewerPosition: vm.Vector3(0.0, 1.65, 2.0),
        headPitchRadians: -0.80,
      );
      expect(glanceVis.cameraFeedOpacity, greaterThan(0.60));
    });

    testWidgets('VrSpatialPassthroughOverlay renders stereoscopic AI wireframe contours', (
      tester,
    ) async {
      final mapper = VrMultiCameraSpaceMapper(
        mode: VrPassthroughMode.aiWireframeContours,
      );
      mapper.upsertObject(
        VrDetectedSpatialObject.fromBoundingBox3D(
          id: 'chair_1',
          label: 'Silla',
          category: VrSpatialObjectCategory.chair,
          centerWorld: vm.Vector3(0.0, 0.5, -1.8),
          extentsWorld: vm.Vector3(0.5, 0.9, 0.5),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 400,
              child: VrSpatialPassthroughOverlay(
                mapper: mapper,
                viewerPosition: vm.Vector3(0.0, 1.65, 0.0),
                viewerOrientation: vm.Quaternion.identity(),
              ),
            ),
          ),
        ),
      );

      expect(find.byType(VrSpatialPassthroughOverlay), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets);
    });
  });
}
