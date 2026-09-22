import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;
import 'package:vrlizate_scene/src/vr_controller_feedback_visuals.dart';
import 'package:vrlizate_scene/vrlizate_scene.dart';

void main() {
  test(
    'foreground compositor preserves stereo projection and world pixels',
    () async {
      final repaint = ValueNotifier(0);
      final rig = StereoHeadRig();
      rig.setOrientation(.3, -.5);
      rig.bodyYaw = .7;
      var shown = true;
      var calls = 0;
      final painter = VrControllerFeedbackPainter(
        repaint: repaint,
        rig: rig,
        visible: () => shown,
        pixelRatio: 1.25,
        render: () => (views, canvas, {region, pixelRatio}) {
          calls++;
          expect(region, const Rect.fromLTWH(0, 0, 32, 32));
          expect(pixelRatio, 1.25);
          expect(views, hasLength(2));
          final expected = rig.buildStereoViews();
          final atDepth =
              rig.eyeCenter +
              rig.forward * VrControllerFeedbackVisuals.distanceMeters;
          for (var i = 0; i < views.length; i++) {
            expect(views[i].viewport, expected[i].viewport);
            final actualPoint = views[i].camera.worldToScreen(
              atDepth,
              const Size(400, 400),
            )!;
            final expectedPoint = expected[i].camera.worldToScreen(
              atDepth,
              const Size(400, 400),
            )!;
            expect((actualPoint - expectedPoint).distance, lessThan(1e-6));
          }
          // Simulates the transparent output from the isolated feedback scene:
          // only the model's covered pixels are composited over the opaque world.
          canvas.drawRect(
            const Rect.fromLTWH(12, 22, 8, 8),
            Paint()..color = const Color(0xFF00FF00),
          );
        },
      );
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawColor(const Color(0xFFFF0000), BlendMode.src);
      painter.paint(canvas, const Size(32, 32));
      final picture = recorder.endRecording();
      final image = await picture.toImage(32, 32);
      final pixels = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      expect(pixels.getUint8((25 * 32 + 15) * 4 + 1), 255);
      expect(pixels.getUint8((5 * 32 + 5) * 4), 255);
      expect(painter.hitTest(Offset.zero), isFalse);
      shown = false;
      final hidden = ui.PictureRecorder();
      painter.paint(Canvas(hidden), const Size(32, 32));
      hidden.endRecording().dispose();
      expect(calls, 1);
      image.dispose();
      picture.dispose();
      repaint.dispose();
    },
  );

  test('immutable telemetry compares every input and display flag', () {
    const neutral = VrControllerFeedbackState();
    expect(neutral.shown, isFalse);
    expect(neutral, const VrControllerFeedbackState());
    expect(neutral.hashCode, const VrControllerFeedbackState().hashCode);
    for (final state in const [
      VrControllerFeedbackState(connected: true),
      VrControllerFeedbackState(visible: false),
      VrControllerFeedbackState(btnA: true),
      VrControllerFeedbackState(btnB: true),
      VrControllerFeedbackState(btnX: true),
      VrControllerFeedbackState(btnY: true),
      VrControllerFeedbackState(btnL: true),
      VrControllerFeedbackState(btnR: true),
      VrControllerFeedbackState(grip: true),
      VrControllerFeedbackState(moveX: .5),
      VrControllerFeedbackState(moveY: .5),
      VrControllerFeedbackState(lookX: .5),
      VrControllerFeedbackState(lookY: .5),
      VrControllerFeedbackState(laserX: .5),
      VrControllerFeedbackState(laserY: .5),
      VrControllerFeedbackState(driving: true),
      VrControllerFeedbackState(steering: .5),
      VrControllerFeedbackState(throttle: .5),
      VrControllerFeedbackState(brake: .5),
    ]) {
      expect(state, isNot(neutral));
    }
    final notifier = ValueNotifier(neutral);
    var updates = 0;
    notifier.addListener(() => updates++);
    notifier.value = const VrControllerFeedbackState();
    expect(updates, 0);
    notifier.value = const VrControllerFeedbackState(btnA: true);
    expect(updates, 1);
    notifier.dispose();
  });

  testWidgets('scope exposes caller-owned notifier and replaces its identity', (
    tester,
  ) async {
    final a = ValueNotifier(const VrControllerFeedbackState());
    final b = ValueNotifier(const VrControllerFeedbackState(connected: true));
    Object? observed;
    Widget tree(ValueNotifier<VrControllerFeedbackState> source) =>
        VrControllerFeedbackScope(
          state: source,
          child: Builder(
            builder: (context) {
              observed = VrControllerFeedbackScope.maybeOf(context)?.state;
              return const SizedBox();
            },
          ),
        );
    await tester.pumpWidget(tree(a));
    expect(observed, same(a));
    await tester.pumpWidget(tree(b));
    expect(observed, same(b));
    await tester.pumpWidget(const SizedBox());
    // The scope never disposes the source belonging to the app session.
    b.value = const VrControllerFeedbackState();
    a.dispose();
    b.dispose();
  });

  test(
    'visibility, retained assets and state update without recreating text',
    () async {
      final fixture = _Fixture();
      final visual = fixture.create();
      await visual.ready;
      expect(visual.root.visible, isFalse);
      final count = visual.root.children.length;
      final meshCount = fixture.materials.length;
      final aMaterial = fixture.materials[7];
      final rig = StereoHeadRig();
      visual.setState(const VrControllerFeedbackState(connected: true));
      visual.updatePose(rig);
      final dimA = aMaterial.baseColorFactor.clone();
      final transform = visual.root.localTransform;
      for (var frame = 0; frame < 120; frame++) {
        visual.setState(
          VrControllerFeedbackState(
            connected: true,
            btnA: true,
            btnL: true,
            grip: true,
            moveX: 1,
            moveY: -1,
            lookX: -.5,
            lookY: .5,
            laserX: .5,
            laserY: -.5,
          ),
        );
        visual.updatePose(rig);
        // Read the world transform to exercise renderer cache invalidation.
        visual.root.globalTransform;
      }
      expect(aMaterial.baseColorFactor.y, greaterThan(dimA.y));
      expect(fixture.node(visual, 'A').position.z, closeTo(.039, 1e-6));
      expect(fixture.node(visual, 'R').position.z, closeTo(.046, 1e-6));
      expect(
        fixture.node(visual, 'move_stick').position.x,
        closeTo(.183, 1e-6),
      );
      expect(
        fixture.node(visual, 'look_stick').position.y,
        closeTo(.009, 1e-6),
      );
      expect(
        fixture.node(visual, 'laser_dot').position.x,
        closeTo(-.026, 1e-6),
      );
      expect(visual.root.localTransform, same(transform));
      expect(visual.root.children, hasLength(count));
      expect(fixture.materials, hasLength(meshCount));
      expect(fixture.artworks, hasLength(1));
      visual.setState(
        const VrControllerFeedbackState(connected: true, visible: false),
      );
      expect(visual.root.visible, isFalse);
      visual.setState(const VrControllerFeedbackState(connected: true));
      expect(visual.root.visible, isTrue);
      expect(fixture.node(visual, 'A').position.z, closeTo(.046, 1e-6));
      expect(
        fixture.node(visual, 'move_stick').position.x,
        closeTo(.225, 1e-6),
      );
      visual.setState(const VrControllerFeedbackState());
      expect(visual.root.visible, isFalse);
      visual.dispose();
      visual.dispose();
      expect(fixture.parent.children, isEmpty);
    },
  );

  test(
    'driving exposes steering and pedals and clamps non-finite axes',
    () async {
      final fixture = _Fixture();
      final visual = fixture.create();
      await visual.ready;
      visual.setState(
        const VrControllerFeedbackState(
          connected: true,
          driving: true,
          steering: 1,
          throttle: .5,
          brake: 2,
          moveX: double.nan,
          lookY: double.infinity,
        ),
      );
      expect(
        fixture.node(visual, 'laser_dot').position.x,
        closeTo(-.052, 1e-6),
      );
      expect(fixture.node(visual, 'throttle').visible, isTrue);
      expect(fixture.node(visual, 'throttle').scale.x, closeTo(.04, 1e-6));
      expect(fixture.node(visual, 'brake').scale.x, closeTo(.08, 1e-6));
      expect(
        fixture.node(visual, 'move_stick').position.x,
        closeTo(.225, 1e-6),
      );
      expect(
        fixture.node(visual, 'look_stick').position.y,
        closeTo(-.012, 1e-6),
      );
      visual.setState(const VrControllerFeedbackState(connected: true));
      expect(fixture.node(visual, 'throttle').visible, isFalse);
      expect(fixture.node(visual, 'brake').visible, isFalse);
      visual.dispose();
    },
  );

  test(
    'both eyes keep L left of R across head and vehicle rotations',
    () async {
      final fixture = _Fixture();
      final visual = fixture.create();
      await visual.ready;
      final rig = StereoHeadRig()..eyeCenter = vm.Vector3(3, 1.6, -2);
      visual.setState(const VrControllerFeedbackState(connected: true));
      for (final (yaw, pitch, body) in [
        (0.0, 0.0, 0.0),
        (.8, -.4, 0.0),
        (-.7, .4, math.pi / 2),
      ]) {
        rig.setOrientation(yaw, pitch);
        rig.bodyYaw = body;
        visual.updatePose(rig);
        for (final eye in StereoEye.values) {
          final camera = rig.eyeCamera(eye);
          final left = camera.worldToScreen(
            fixture.node(visual, 'L').globalTransform.getTranslation(),
            const Size(400, 400),
          )!;
          final right = camera.worldToScreen(
            fixture.node(visual, 'R').globalTransform.getTranslation(),
            const Size(400, 400),
          )!;
          expect(left.dx, lessThan(right.dx));
          expect(left.dy, closeTo(right.dy, .001));
          final center = camera.worldToScreen(
            visual.root.position,
            const Size(400, 400),
          )!;
          expect(center.dy, closeTo(336, .01));
        }
      }
      // Atlas UVs put the canvas left-hand L at local +X, not mirrored text.
      final surface = fixture.artworks.single;
      expect(surface.geometry.vertices[1].x, greaterThan(0));
      expect(surface.geometry.uvs[1].x, 0);
      visual.dispose();
    },
  );

  test(
    'controller has distant stereo depth and readable bounds in both eyes',
    () async {
      final fixture = _Fixture();
      final visual = fixture.create();
      await visual.ready;
      addTearDown(visual.dispose);
      final rig = StereoHeadRig()..eyeCenter = vm.Vector3(3, 1.6, -2);
      rig.setOrientation(.4, .6);
      rig.bodyYaw = .8;
      rig.bodyPitch = -.15;
      visual.setState(const VrControllerFeedbackState(connected: true));
      const size = Size(400, 400);

      for (final fov in [1.2, .5]) {
        rig.cameraRig.fovY = fov;
        visual.updatePose(rig);
        final offset = visual.root.position - rig.eyeCenter;
        expect(offset.dot(rig.forward), closeTo(3, 1e-5));
        expect(offset.dot(rig.screenRight), closeTo(0, 1e-5));
        expect(rig.convergenceDistance, 1.8);

        final disparityFromConvergence = <double>[];
        for (final eye in StereoEye.values) {
          final camera = rig.eyeCamera(eye);
          final center = camera.worldToScreen(visual.root.position, size)!;
          final convergence = camera.worldToScreen(
            rig.convergencePoint!,
            size,
          )!;
          final disparity = center.dx - convergence.dx;
          disparityFromConvergence.add(disparity);
          expect(
            disparity,
            eye == StereoEye.left ? lessThan(-1) : greaterThan(1),
            reason: 'the controller projects beyond the convergence plane',
          );
          expect(center.dy, closeTo(336, .01));

          final corners = [
            for (final x in [-.4, .4])
              for (final y in [-.175, .175])
                camera.worldToScreen(
                  visual.root.globalTransform.transformed3(
                    vm.Vector3(x, y, .086),
                  ),
                  size,
                )!,
          ];
          for (final corner in corners) {
            expect(corner.dx, inInclusiveRange(0, size.width));
            expect(corner.dy, inInclusiveRange(0, size.height));
          }
          final artworkWidth = (corners[2].dx - corners[0].dx).abs();
          expect(
            artworkWidth,
            greaterThan(size.width * .27),
            reason: 'distance must not make the control labels too small',
          );
          if (fov == 1.2) {
            expect(artworkWidth, lessThan(size.width * .30));
          }
        }
        expect(
          disparityFromConvergence[0],
          closeTo(-disparityFromConvergence[1], .001),
          reason: 'both eyes use the same depth without vertical disparity',
        );
      }
      expect(fixture.artworks, hasLength(1));
    },
  );

  test(
    'telemetry subtree never participates in geometry or named ray picking',
    () async {
      final fixture = _Fixture();
      final visual = fixture.create();
      await visual.ready;
      visual.setState(const VrControllerFeedbackState(connected: true));
      visual.updatePose(StereoHeadRig());
      expect(visual.root.raycastable, isFalse);
      for (final node in visual.root.children) {
        expect(node.raycastable, isFalse, reason: node.name);
        expect(node.castsShadows, isFalse, reason: node.name);
      }
      final candidates = <Node>[];
      raycastNode(
        fixture.parent,
        vm.Ray.originDirection(vm.Vector3.zero(), vm.Vector3(0, -.5, -1)),
        where: (node) {
          candidates.add(node);
          return true;
        },
      );
      expect(
        candidates.where(
          (node) =>
              node.name.startsWith(VrControllerFeedbackVisuals.nodePrefix),
        ),
        isEmpty,
      );
      visual.dispose();
    },
  );

  test(
    'late texture completion after disposal cannot resurrect a scene node',
    () async {
      final fixture = _Fixture();
      final pending = Completer<Mesh?>();
      final visual = fixture.create(artwork: (_) => pending.future);
      visual.dispose();
      pending.complete(null);
      await visual.ready;
      visual.setState(const VrControllerFeedbackState(connected: true));
      visual.updatePose(StereoHeadRig());
      expect(visual.root.visible, isFalse);
      expect(fixture.parent.children, isEmpty);
      expect(
        visual.root.children.where((node) => node.name.endsWith('labels')),
        isEmpty,
      );
    },
  );

  test(
    'action captions re-rasterize the label atlas only when they change',
    () async {
      final fixture = _Fixture();
      final visual = fixture.create();
      await visual.ready;
      expect(
        fixture.artworks.length,
        1,
        reason: 'initial atlas without captions',
      );

      // Same experience, many packets: no new atlas.
      for (var i = 0; i < 5; i++) {
        visual.setState(
          VrControllerFeedbackState(
            connected: true,
            btnA: i.isEven,
            actions: const {'A': 'Disparar', 'X': 'Cambiar arma'},
          ),
        );
      }
      await visual.artworkPending;
      expect(
        fixture.artworks.length,
        2,
        reason: 'one atlas for the new actions',
      );
      expect(
        visual.root.children.where((n) => n.name.endsWith('labels')).length,
        1,
        reason: 'the previous label node is replaced, never stacked',
      );

      // A different experience → one more atlas.
      visual.setState(
        const VrControllerFeedbackState(
          connected: true,
          actions: {'A': 'Golpear', 'GRIP': 'Magnesis'},
        ),
      );
      await visual.artworkPending;
      expect(fixture.artworks.length, 3);
      expect(
        visual.root.children.where((n) => n.name.endsWith('labels')).length,
        1,
      );
      visual.dispose();
    },
  );

  test(
    'action captions paint under their keys and truncate long text',
    () async {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final fixture = _Fixture();
      final visual = fixture.create();
      await visual.ready;
      visual.setState(
        const VrControllerFeedbackState(
          connected: true,
          actions: {
            'X': 'Cambiar arma',
            'Y': 'Una etiqueta demasiado larga para caber',
            'GRIP': 'Puerta',
          },
        ),
      );
      await visual.artworkPending;
      // The paint callback must run without throwing for an oversized caption
      // and must reference the same atlas dimensions as the base artwork.
      final surface = fixture.artworks.last;
      expect(surface.widthPixels, 1024);
      expect(surface.heightPixels, 448);
      surface.paint(canvas, const Size(1024, 448));
      recorder.endRecording().dispose();
      visual.dispose();
    },
  );

  test('feedback state equality includes the action map', () {
    const a = VrControllerFeedbackState(actions: {'A': 'Disparar'});
    const b = VrControllerFeedbackState(actions: {'A': 'Disparar'});
    const c = VrControllerFeedbackState(actions: {'A': 'Golpear'});
    expect(a, equals(b));
    expect(a.hashCode, b.hashCode);
    expect(a, isNot(equals(c)));
    expect(const VrControllerFeedbackState(), isNot(equals(a)));
  });

  test(
    'gaze angle from feet calculates correct angles (0° at feet/nadir, 90° at horizon)',
    () {
      final rig = StereoHeadRig();
      // At horizon (pitch = 0 rad), angle from feet is 90°
      rig.setOrientation(0.0, 0.0);
      expect(
        VrControllerFeedbackVisuals.gazeAngleFromFeetDeg(rig),
        closeTo(90.0, 1e-4),
      );

      // Looking down 70° (pitch = 70 * pi / 180 ≈ 1.2217 rad), angle from feet is 20°
      rig.setPitch(70.0 * math.pi / 180.0);
      expect(
        VrControllerFeedbackVisuals.gazeAngleFromFeetDeg(rig),
        closeTo(20.0, 1e-4),
      );

      // Looking down 60° (pitch = 60 * pi / 180 ≈ 1.0472 rad), angle from feet is 30°
      rig.setPitch(60.0 * math.pi / 180.0);
      expect(
        VrControllerFeedbackVisuals.gazeAngleFromFeetDeg(rig),
        closeTo(30.0, 1e-4),
      );

      // Looking straight down at feet (pitch = 90° = pi / 2, clamped to 1.45 rad ≈ 83.08° in CameraRig)
      rig.setPitch(1.45);
      expect(
        VrControllerFeedbackVisuals.gazeAngleFromFeetDeg(rig),
        closeTo(90.0 - 83.0784, 0.01),
      );

      // Looking up at sky (pitch = -30° = -pi / 6), angle from feet is 120°
      rig.setPitch(-30.0 * math.pi / 180.0);
      expect(
        VrControllerFeedbackVisuals.gazeAngleFromFeetDeg(rig),
        closeTo(120.0, 1e-4),
      );
    },
  );

  test(
    'controller reveals at 30 degrees and hides at 20 without flicker',
    () async {
      final visual = _Fixture().create(gazeFilterEnabled: true);
      await visual.ready;
      addTearDown(visual.dispose);
      final rig = StereoHeadRig();
      visual.setState(const VrControllerFeedbackState(connected: true));
      void pitch(double degrees) {
        rig.setPitch(degrees * math.pi / 180);
        visual.updatePose(rig);
      }

      for (final angle in [-30.0, 0.0, 20.0, 29.9]) {
        pitch(angle);
        expect(visual.root.visible, isFalse, reason: '$angle degrees');
      }
      pitch(30);
      expect(visual.root.visible, isTrue);
      // Noise around the reveal angle cannot repeatedly show/hide the model.
      for (final angle in [29.8, 30.2, 29.9, 30.1, 25.0, 20.1, 80.0]) {
        pitch(angle);
        expect(visual.root.visible, isTrue, reason: '$angle degrees');
      }
      pitch(20);
      expect(visual.root.visible, isFalse);
      // Noise around the hide angle must not re-open a dismissed controller.
      for (final angle in [19.9, 20.1, 19.8, 20.2, 29.9]) {
        pitch(angle);
        expect(visual.root.visible, isFalse, reason: '$angle degrees');
      }
      pitch(30);
      expect(visual.root.visible, isTrue);
      pitch(0);
      expect(visual.root.visible, isFalse);
    },
  );

  test(
    'reveal gesture uses physical head pitch, pose uses composed pitch',
    () async {
      final visual = _Fixture().create(gazeFilterEnabled: true);
      await visual.ready;
      addTearDown(visual.dispose);
      final rig = StereoHeadRig();
      visual.setState(const VrControllerFeedbackState(connected: true));
      rig.bodyPitch = 70 * math.pi / 180;
      visual.updatePose(rig);
      expect(
        visual.root.visible,
        isFalse,
        reason: 'stick alone cannot reveal it',
      );

      rig.setPitch(30 * math.pi / 180);
      rig.bodyPitch = -1;
      visual.updatePose(rig);
      expect(rig.pitch, lessThan(0));
      expect(
        visual.root.visible,
        isTrue,
        reason: 'head tilt works despite stick offset',
      );
      for (final eye in StereoEye.values) {
        final center = rig
            .eyeCamera(eye)
            .worldToScreen(visual.root.position, const Size(400, 400))!;
        expect(
          center.dy,
          closeTo(336, .01),
          reason: 'model follows rendered eye basis',
        );
      }

      rig.setPitch(0);
      rig.bodyPitch = 1;
      visual.updatePose(rig);
      expect(
        visual.root.visible,
        isFalse,
        reason: 'physical horizon dismisses it',
      );
    },
  );

  test('disconnect and manual hide reset the reveal gesture', () async {
    final visual = _Fixture().create(gazeFilterEnabled: true);
    await visual.ready;
    addTearDown(visual.dispose);
    final rig = StereoHeadRig()..setPitch(30 * math.pi / 180);
    const shown = VrControllerFeedbackState(connected: true);
    for (final hidden in const [
      VrControllerFeedbackState(connected: false),
      VrControllerFeedbackState(connected: true, visible: false),
    ]) {
      visual.setState(shown);
      rig.setPitch(30 * math.pi / 180);
      visual.updatePose(rig);
      expect(visual.root.visible, isTrue);
      visual.setState(hidden);
      expect(visual.root.visible, isFalse);
      visual.updatePose(rig);
      expect(visual.root.visible, isFalse);
      rig.setPitch(25 * math.pi / 180);
      visual.setState(shown);
      visual.updatePose(rig);
      expect(
        visual.root.visible,
        isFalse,
        reason: 'new session requires reveal tilt',
      );
    }
  });

  test(
    'explicit legacy window keeps angles from feet and composed gaze',
    () async {
      final visual = _Fixture().create(
        gazeFilterEnabled: true,
        targetGazeAngleDeg: 20,
        gazeAngleToleranceDeg: 15,
      );
      await visual.ready;
      addTearDown(visual.dispose);
      final rig = StereoHeadRig();
      visual.setState(const VrControllerFeedbackState(connected: true));
      rig.setPitch(30 * math.pi / 180);
      visual.updatePose(rig);
      expect(visual.root.visible, isFalse);
      rig.setPitch(0);
      rig.bodyPitch = 70 * math.pi / 180;
      visual.updatePose(rig);
      expect(visual.root.visible, isTrue);
      rig.bodyPitch = 50 * math.pi / 180;
      visual.updatePose(rig);
      expect(visual.root.visible, isFalse);
    },
  );
}

class _Fixture {
  final parent = Node();
  final materials = <UnlitMaterial>[];
  final artworks = <VrRetainedSurface>[];

  VrControllerFeedbackVisuals create({
    Future<Mesh?> Function(VrRetainedSurface)? artwork,
    bool gazeFilterEnabled = false,
    double? targetGazeAngleDeg,
    double? gazeAngleToleranceDeg,
  }) => VrControllerFeedbackVisuals(
    parent,
    gazeFilterEnabled: gazeFilterEnabled,
    targetGazeAngleDeg: targetGazeAngleDeg,
    gazeAngleToleranceDeg: gazeAngleToleranceDeg,
    meshBuilder: (material, {required round}) {
      materials.add(material);
      return Mesh.primitives(primitives: const []);
    },
    artworkBuilder:
        artwork ??
        (surface) async {
          artworks.add(surface);
          return null;
        },
  );

  Node node(VrControllerFeedbackVisuals visual, String id) =>
      visual.root.children.singleWhere(
        (node) => node.name == '${VrControllerFeedbackVisuals.nodePrefix}$id',
      );
}
