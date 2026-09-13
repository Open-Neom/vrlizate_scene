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
          final atDepth = rig.eyeCenter + rig.forward * 1.8;
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
    'gaze angle from feet calculates correct angles (0° at feet/nadir, 90° at horizon)',
    () {
      final rig = StereoHeadRig();
      // At horizon (pitch = 0 rad), angle from feet is 90°
      rig.setOrientation(0.0, 0.0);
      expect(VrControllerFeedbackVisuals.gazeAngleFromFeetDeg(rig), closeTo(90.0, 1e-4));

      // Looking down 70° (pitch = 70 * pi / 180 ≈ 1.2217 rad), angle from feet is 20°
      rig.setPitch(70.0 * math.pi / 180.0);
      expect(VrControllerFeedbackVisuals.gazeAngleFromFeetDeg(rig), closeTo(20.0, 1e-4));

      // Looking down 60° (pitch = 60 * pi / 180 ≈ 1.0472 rad), angle from feet is 30°
      rig.setPitch(60.0 * math.pi / 180.0);
      expect(VrControllerFeedbackVisuals.gazeAngleFromFeetDeg(rig), closeTo(30.0, 1e-4));

      // Looking straight down at feet (pitch = 90° = pi / 2, clamped to 1.45 rad ≈ 83.08° in CameraRig)
      rig.setPitch(1.45);
      expect(VrControllerFeedbackVisuals.gazeAngleFromFeetDeg(rig), closeTo(90.0 - 83.0784, 0.01));

      // Looking up at sky (pitch = -30° = -pi / 6), angle from feet is 120°
      rig.setPitch(-30.0 * math.pi / 180.0);
      expect(VrControllerFeedbackVisuals.gazeAngleFromFeetDeg(rig), closeTo(120.0, 1e-4));
    },
  );

  test(
    'virtual controller is only visible when looking down around 20° from feet',
    () async {
      final fixture = _Fixture();
      // Default: gazeFilterEnabled is true
      final visual = fixture.create(gazeFilterEnabled: true);
      await visual.ready;

      final rig = StereoHeadRig();
      visual.setState(const VrControllerFeedbackState(connected: true));

      // 1. Looking at horizon (pitch = 0.0, 90° from feet) -> MUST BE HIDDEN
      rig.setOrientation(0.0, 0.0);
      visual.updatePose(rig);
      expect(visual.root.visible, isFalse, reason: 'Must be hidden at horizon (90° from feet)');

      // 2. Looking up at sky (pitch = -30°, 120° from feet) -> MUST BE HIDDEN
      rig.setPitch(-30.0 * math.pi / 180.0);
      visual.updatePose(rig);
      expect(visual.root.visible, isFalse, reason: 'Must be hidden looking up');

      // 3. Looking slightly down (pitch = 30°, 60° from feet) -> MUST BE HIDDEN
      rig.setPitch(30.0 * math.pi / 180.0);
      visual.updatePose(rig);
      expect(visual.root.visible, isFalse, reason: 'Must be hidden looking slightly down (60° from feet)');

      // 4. Looking down at ~20° from feet (pitch = 70° = 1.2217 rad) -> MUST BE VISIBLE!
      rig.setPitch(70.0 * math.pi / 180.0);
      visual.updatePose(rig);
      expect(visual.root.visible, isTrue, reason: 'Must be visible at 20° from feet');

      // 5. Looking down at 30° from feet (pitch = 60°, within 20° ± 15°) -> VISIBLE
      rig.setPitch(60.0 * math.pi / 180.0);
      visual.updatePose(rig);
      expect(visual.root.visible, isTrue, reason: 'Must be visible at 30° from feet (within tolerance)');

      // 6. Looking down at 10° from feet (pitch = 80°, within 20° ± 15°) -> VISIBLE
      rig.setPitch(80.0 * math.pi / 180.0);
      visual.updatePose(rig);
      expect(visual.root.visible, isTrue, reason: 'Must be visible at 10° from feet (within tolerance)');

      // 7. Looking down at 40° from feet (pitch = 50°, outside 20° ± 15°) -> HIDDEN
      rig.setPitch(50.0 * math.pi / 180.0);
      visual.updatePose(rig);
      expect(visual.root.visible, isFalse, reason: 'Must be hidden at 40° from feet (outside tolerance)');

      // 8. Returning gaze to horizon -> HIDES IMMEDIATELY
      rig.setPitch(0.0);
      visual.updatePose(rig);
      expect(visual.root.visible, isFalse, reason: 'Must hide when looking back up at horizon');

      // 9. When disconnected, stays hidden even at 20° gaze
      visual.setState(const VrControllerFeedbackState(connected: false));
      rig.setPitch(70.0 * math.pi / 180.0);
      visual.updatePose(rig);
      expect(visual.root.visible, isFalse, reason: 'Must not show if disconnected');

      // 10. When visible flag is false, stays hidden even at 20° gaze
      visual.setState(const VrControllerFeedbackState(connected: true, visible: false));
      visual.updatePose(rig);
      expect(visual.root.visible, isFalse, reason: 'Must not show if visible is false');

      visual.dispose();
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
  }) => VrControllerFeedbackVisuals(
    parent,
    gazeFilterEnabled: gazeFilterEnabled,
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
