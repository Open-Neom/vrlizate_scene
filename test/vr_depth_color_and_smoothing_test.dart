import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;
import 'package:vrlizate_scene/vrlizate_scene.dart';

void main() {
  group('VrDepthColorPalette — SDK Depth Perception Coloring', () {
    test('maps near, optimal eMudra reach, mid, and far distances to distinct colors', () {
      final near = VrDepthColorPalette.colorForDistanceMeters(0.22);
      final reach = VrDepthColorPalette.colorForDistanceMeters(0.52);
      final mid = VrDepthColorPalette.colorForDistanceMeters(1.25);
      final far = VrDepthColorPalette.colorForDistanceMeters(2.90);

      expect(
        VrDepthColorPalette.zoneForDistanceMeters(0.22),
        VrDepthZone.nearContact,
      );
      expect(
        VrDepthColorPalette.zoneForDistanceMeters(0.52),
        VrDepthZone.activeReach,
      );
      expect(
        VrDepthColorPalette.zoneForDistanceMeters(1.25),
        VrDepthZone.midSpace,
      );
      expect(
        VrDepthColorPalette.zoneForDistanceMeters(2.90),
        VrDepthZone.farHorizon,
      );

      // Near is warm red-dominant; reach is emerald/cyan green-dominant; far is violet blue-dominant
      expect(near.r, greaterThan(0.85));
      expect(reach.g, greaterThan(0.80));
      expect(mid.b, greaterThan(0.85));
      expect(far.b, greaterThan(0.85));
      expect(far.r, greaterThan(0.35));

      // Stroke scale decreases smoothly with distance
      expect(
        VrDepthColorPalette.strokeScaleForDistanceMeters(0.25),
        greaterThan(VrDepthColorPalette.strokeScaleForDistanceMeters(2.20)),
      );
    });
  });

  group('VrMultiCameraSpaceMapper — Opt-In Bounding Boxes & Temporal Smoothing', () {
    test('hides object bounding boxes when showObjectBoundingBoxes is false', () {
      final mapper = VrMultiCameraSpaceMapper(
        showObjectBoundingBoxes: false,
        temporalSmoothingAlpha: 0.25,
      );

      mapper.upsertObject(
        VrDetectedSpatialObject.fromBoundingBox3D(
          id: 'box_1',
          label: 'Mesa',
          category: VrSpatialObjectCategory.table,
          centerWorld: vm.Vector3(0, 0.4, -1.2),
          extentsWorld: vm.Vector3(0.8, 0.6, 0.5),
        ),
      );

      // Anti-clutter: hidden while opt-in is false
      expect(mapper.allContourSegments, isEmpty);

      // Visible immediately when user opts in
      mapper.showObjectBoundingBoxes = true;
      expect(mapper.allContourSegments.length, 12);
    });

    test('applies exponential temporal smoothing on repeated upsertObject updates', () {
      final mapper = VrMultiCameraSpaceMapper(
        showObjectBoundingBoxes: true,
        temporalSmoothingAlpha: 0.25,
      );

      mapper.upsertObject(
        VrDetectedSpatialObject.fromBoundingBox3D(
          id: 'hand_box',
          label: 'Mano',
          category: VrSpatialObjectCategory.handController,
          centerWorld: vm.Vector3(0.0, 1.0, -0.50),
          extentsWorld: vm.Vector3(0.20, 0.12, 0.12),
        ),
        timestampMicros: 100000,
      );
      mapper.upsertObject(
        VrDetectedSpatialObject.fromBoundingBox3D(
          id: 'hand_box',
          label: 'Mano',
          category: VrSpatialObjectCategory.handController,
          centerWorld: vm.Vector3(0.40, 1.0, -0.90),
          extentsWorld: vm.Vector3(0.20, 0.12, 0.12),
        ),
        timestampMicros: 116000,
      );

      final smoothed = mapper.objects.single;
      // With alpha=0.25: 0.0 + 0.25*(0.40 - 0.0) = 0.10 (glides smoothly, no jump!)
      expect(smoothed.centerWorld.x, closeTo(0.10, 1e-4));
      expect(smoothed.centerWorld.z, closeTo(-0.60, 1e-4));

      // Stale pruning clears lingering ghost boxes
      mapper.pruneStaleObjects(nowMicros: 1200000, maxAgeMicros: 900000);
      expect(mapper.objects, isEmpty);
    });

    testWidgets('VrSpatialWireframePainter renders depth-colored gradients cleanly', (
      tester,
    ) async {
      final segments = <VrSpatialContourSegment>[
        VrSpatialContourSegment(
          startWorld: vm.Vector3(-0.15, 1.55, -0.28),
          endWorld: vm.Vector3(0.20, 1.55, -1.95),
          category: VrSpatialObjectCategory.floorBoundary,
        ),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 300,
              child: CustomPaint(
                painter: VrSpatialWireframePainter(
                  segments: segments,
                  viewerPosition: vm.Vector3(0, 1.60, 0),
                  viewerOrientation: vm.Quaternion.identity(),
                  colorByDepth: true,
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.byType(CustomPaint), findsWidgets);
    });
  });

  group('Frontal Headset 48° FoV & Active Lens Scissor (-36.2% GPU Pixels)', () {
    test('VrViewerProfile.frontalLowLatency eliminates >36% peripheral fragments while preserving center projection', () {
      final profile = VrViewerProfile.frontalLowLatency();
      expect(profile.hasActiveLensScissor, isTrue);
      expect(profile.estimatedGpuPixelSavingsFraction, closeTo(0.3616, 1e-3));

      final rig = StereoHeadRig();
      profile.applyTo(rig);

      const screenSize = Size(2400, 1080);
      final fullEyes = rig.buildStereoViews();
      final croppedEyes = VrFixedFoveation.cropStereoViewsToActiveLens(
        fullEyes,
        viewportSize: screenSize,
        widthFraction: profile.activeLensWidthFraction,
        heightFraction: profile.activeLensHeightFraction,
        centers: [
          Offset(0.5 + rig.stereoImageInset / 2, 0.5),
          Offset(0.5 - rig.stereoImageInset / 2, 0.5),
        ],
      );

      expect(croppedEyes.length, 2);
      // Left eye viewport width is 0.5 * 0.76 = 0.38 instead of 0.50
      expect(croppedEyes[0].viewport!.width, closeTo(0.38, 1e-4));
      expect(croppedEyes[0].viewport!.height, closeTo(0.84, 1e-4));

      // Verify projection invariance: a 3D point near convergence lands on the exact same physical screen pixel!
      final worldPoint = vm.Vector3(0.08, 1.62, -1.80);
      for (var i = 0; i < 2; i++) {
        final fullVp = fullEyes[i].viewport!;
        final fullPx = fullEyes[i].camera.worldToScreen(
          worldPoint,
          Size(screenSize.width * fullVp.width, screenSize.height * fullVp.height),
        )!;
        final fullScreenX = screenSize.width * fullVp.left + fullPx.dx;
        final fullScreenY = screenSize.height * fullVp.top + fullPx.dy;

        final cropVp = croppedEyes[i].viewport!;
        final cropPx = croppedEyes[i].camera.worldToScreen(
          worldPoint,
          Size(screenSize.width * cropVp.width, screenSize.height * cropVp.height),
        )!;
        final cropScreenX = screenSize.width * cropVp.left + cropPx.dx;
        final cropScreenY = screenSize.height * cropVp.top + cropPx.dy;

        expect(cropScreenX, closeTo(fullScreenX, 1e-2));
        expect(cropScreenY, closeTo(fullScreenY, 1e-2));
      }
    });
  });
}
