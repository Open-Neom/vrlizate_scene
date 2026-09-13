import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/rendering.dart' show CustomPainter;
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'retained_scene_adapter.dart';
import 'stereo_head_rig.dart';
import 'vr_controller_feedback.dart';

/// CPU-testable resource boundary; production uses retained unit GPU meshes.
typedef VrControllerFeedbackMeshBuilder =
    Mesh? Function(UnlitMaterial material, {required bool round});

/// Decorative 3D input feedback, not measured controller tracking or a menu.
///
/// Owns one subtree, two shared primitive geometries and one static label
/// texture. Packets only change material factors and local transforms. All
/// descendants are excluded from picking and shadows. The caller owns parent.
class VrControllerFeedbackVisuals {
  VrControllerFeedbackVisuals(
    this.parent, {
    VrControllerFeedbackMeshBuilder? meshBuilder,
    Future<Mesh?> Function(VrRetainedSurface surface)? artworkBuilder,
    this.gazeFilterEnabled = true,
    this.targetGazeAngleDeg = targetGazeAngleFromFeetDeg,
    this.gazeAngleToleranceDeg = defaultGazeAngleToleranceDeg,
  }) {
    final createMesh = meshBuilder ?? _gpuMesh;
    Node part(
      String id,
      vm.Vector3 size,
      double x,
      double y,
      double z,
      UnlitMaterial material, {
      bool round = false,
    }) {
      final node =
          _nonInteractive(
              Node(
                name: '$nodePrefix$id',
                mesh: createMesh(material, round: round),
              ),
            )
            ..position = vm.Vector3(x, y, z)
            ..scale = size;
      root.add(node);
      return node;
    }

    part(
      'body',
      vm.Vector3(.8, .34, .035),
      0,
      0,
      0,
      _material(const Color(0xFF142436)),
    );
    part(
      'screen',
      vm.Vector3(.76, .30, .009),
      0,
      0,
      .023,
      _material(const Color(0xFF080F1C)),
    );
    for (var i = 0; i < _buttons.length; i++) {
      final spec = _buttons[i];
      final material = _material(spec.$4);
      final node = part(
        spec.$1,
        vm.Vector3(.095, .060, .025),
        spec.$2,
        spec.$3,
        .046,
        material,
      );
      _keys.add(_FeedbackKey(node, material, spec.$4));
    }
    final dark = _material(const Color(0xFF273C52));
    final cyan = _material(const Color(0xFF00D7EF));
    final orange = _material(const Color(0xFFFF9700));
    for (final x in [.225, -.225]) {
      part(
        'stick_base',
        vm.Vector3(.17, .17, .023),
        x,
        -.012,
        .04,
        dark,
        round: true,
      );
    }
    _moveStick = part(
      'move_stick',
      vm.Vector3(.082, .082, .042),
      .225,
      -.012,
      .065,
      cyan,
      round: true,
    );
    _lookStick = part(
      'look_stick',
      vm.Vector3(.082, .082, .042),
      -.225,
      -.012,
      .065,
      orange,
      round: true,
    );
    part('laser_pad', vm.Vector3(.13, .095, .008), 0, -.015, .035, dark);
    _laserDot = part(
      'laser_dot',
      vm.Vector3(.018, .018, .016),
      0,
      -.015,
      .055,
      cyan,
      round: true,
    );
    final gripMaterial = _material(const Color(0xFF16DCA0));
    _grip = _FeedbackKey(
      part('grip', vm.Vector3(.09, .028, .012), 0, .093, .044, gripMaterial),
      gripMaterial,
      const Color(0xFF16DCA0),
    );
    _throttle = part(
      'throttle',
      vm.Vector3(.001, .014, .012),
      -.015,
      -.094,
      .048,
      orange,
    );
    _brake = part(
      'brake',
      vm.Vector3(.001, .014, .012),
      .015,
      -.094,
      .048,
      _material(const Color(0xFFF45364)),
    );
    parent.add(root);
    setState(const VrControllerFeedbackState());
    ready = _loadArtwork(
      artworkBuilder ?? const VrRetainedGpuResources().createSurface,
    );
  }

  static const nodePrefix = '__vrlizate_controller_feedback_';
  static const distanceMeters = 1.8;
  static const screenAlignmentY = .68;

  /// Target downward gaze angle in degrees where the virtual controller is displayed,
  /// considering 0° as looking straight down at feet and 90° as looking at the horizon.
  static const double targetGazeAngleFromFeetDeg = 20.0;

  /// Angular tolerance window around [targetGazeAngleFromFeetDeg] (±15°).
  static const double defaultGazeAngleToleranceDeg = 15.0;

  /// Converts camera rig pitch to degrees from feet (0° = feet/nadir, 90° = horizon).
  /// In CameraRig, positive pitch angles look down.
  static double gazeAngleFromFeetDeg(StereoHeadRig rig) {
    final pitchDeg = rig.cameraRig.pitch * 180.0 / math.pi;
    return 90.0 - pitchDeg;
  }

  /// Returns true if the viewer's gaze is directed towards the virtual controller
  /// (at around 20° looking down, where 0° is looking at feet).
  static bool isGazeTowardsController(
    StereoHeadRig rig, {
    double targetAngleDeg = targetGazeAngleFromFeetDeg,
    double toleranceDeg = defaultGazeAngleToleranceDeg,
  }) {
    final angle = gazeAngleFromFeetDeg(rig);
    return (angle - targetAngleDeg).abs() <= toleranceDeg;
  }

  final bool gazeFilterEnabled;
  final double targetGazeAngleDeg;
  final double gazeAngleToleranceDeg;

  // Local +X projects LEFT in flutter_scene; the atlas has the same UV basis
  // as VrRetainedSurface. Use the rig's real screen basis, including body yaw.
  static const _buttons = [
    ('L', .285, .112, Color(0xFF13B4DD)),
    ('R', -.285, .112, Color(0xFFFF9200)),
    ('Y', .347, -.008, Color(0xFFFFCF31)),
    ('B', -.347, -.008, Color(0xFFFF4564)),
    ('X', .285, -.117, Color(0xFF3784FF)),
    ('A', -.285, -.117, Color(0xFF19DF92)),
  ];

  final Node parent;
  final Node root = _nonInteractive(Node(name: '${nodePrefix}root'))
    ..visible = false;
  late final Future<void> ready;
  final List<_FeedbackKey> _keys = [];
  late final _FeedbackKey _grip;
  late final Node _moveStick, _lookStick, _laserDot, _throttle, _brake;
  final vm.Vector3 _scratch = vm.Vector3.zero();
  final vm.Matrix4 _pose = vm.Matrix4.identity();
  Geometry? _box, _sphere;
  VrControllerFeedbackState? _state;
  bool _disposed = false;

  Mesh _gpuMesh(UnlitMaterial material, {required bool round}) => Mesh(
    round
        ? (_sphere ??= SphereGeometry(radius: .5, segments: 16, rings: 8))
        : (_box ??= CuboidGeometry(vm.Vector3.all(1))),
    material,
  );

  static Node _nonInteractive(Node node) => node
    ..raycastable = false
    ..castsShadows = false;

  static UnlitMaterial _material(Color color) => UnlitMaterial()
    ..vertexColorWeight = 0
    ..baseColorFactor.setValues(color.r, color.g, color.b, 1);

  Future<void> _loadArtwork(
    Future<Mesh?> Function(VrRetainedSurface) create,
  ) async {
    final mesh = await create(
      const VrRetainedSurface(
        widthPixels: 1024,
        heightPixels: 448,
        worldWidth: .8,
        worldHeight: .35,
        paint: _paintArtwork,
      ),
    );
    if (_disposed) return;
    root.add(
      _nonInteractive(Node(name: '${nodePrefix}labels', mesh: mesh))
        ..position = vm.Vector3(0, 0, .086),
    );
  }

  static void _paintArtwork(Canvas canvas, Size size) {
    void label(
      String text,
      double x,
      double y,
      double fontSize, {
      Color color = const Color(0xFFFFFFFF),
    }) {
      final painter = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            fontSize: fontSize,
            color: color,
            fontWeight: FontWeight.w800,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(
        canvas,
        Offset(
          (.5 - x / .8) * size.width - painter.width / 2,
          (.5 - y / .35) * size.height - painter.height / 2,
        ),
      );
      painter.dispose();
    }

    for (final key in _buttons) {
      label(key.$1, key.$2, key.$3, 46);
    }
    label('GRIP', 0, .093, 20);
    label('MANDO', 0, .143, 18, color: const Color(0xFF72BBDB));
    label('FRENO', .055, -.131, 13);
    label('GAS', -.055, -.131, 13);
  }

  static double _axis(double value) =>
      value.isFinite ? value.clamp(-1.0, 1.0) : 0;
  static double _pedal(double value) =>
      value.isFinite ? value.clamp(0.0, 1.0) : 0;

  void setState(VrControllerFeedbackState state) {
    if (_disposed || state == _state) return;
    _state = state;
    if (!state.shown) {
      root.visible = false;
      return;
    }
    if (!gazeFilterEnabled) {
      root.visible = true;
    }
    _keys[0].pressed = state.btnL;
    _keys[1].pressed = state.btnR;
    _keys[2].pressed = state.btnY;
    _keys[3].pressed = state.btnB;
    _keys[4].pressed = state.btnX;
    _keys[5].pressed = state.btnA;
    _grip.pressed = state.grip;
    _move(
      _moveStick,
      .225 - _axis(state.moveX) * .042,
      -.012 + _axis(state.moveY) * .042,
    );
    _move(
      _lookStick,
      -.225 - _axis(state.lookX) * .042,
      -.012 + _axis(state.lookY) * .042,
    );
    _move(
      _laserDot,
      -_axis(state.driving ? state.steering : state.laserX) * .052,
      -.015 + (state.driving ? 0 : _axis(state.laserY) * .032),
    );
    _throttle.visible = _brake.visible = state.driving;
    _bar(_throttle, _pedal(state.throttle), -1);
    _bar(_brake, _pedal(state.brake), 1);
  }

  void _move(Node node, double x, double y) {
    _scratch.setValues(x, y, node == _laserDot ? .055 : .065);
    node.position = _scratch;
  }

  void _bar(Node node, double value, double side) {
    final width = math.max(.001, .08 * value);
    _scratch.setValues(width, .014, .012);
    node.scale = _scratch;
    _scratch.setValues(side * (.015 + width / 2), -.094, .048);
    node.position = _scratch;
  }

  /// Pose follows the actual rendered eye basis, not sensor quaternion alone.
  /// Narrow optical FOVs scale the model down to keep it inside both eye views.
  void updatePose(StereoHeadRig rig) {
    if (_disposed) return;
    final isConnected = _state?.shown ?? false;
    if (!isConnected) {
      root.visible = false;
      return;
    }
    if (gazeFilterEnabled) {
      final isLooking = isGazeTowardsController(
        rig,
        targetAngleDeg: targetGazeAngleDeg,
        toleranceDeg: gazeAngleToleranceDeg,
      );
      root.visible = isLooking;
      if (!isLooking) return;
    } else {
      root.visible = true;
    }
    final forward = rig.forward;
    final right = rig.screenRight;
    final up = rig.up;
    final halfHeight = distanceMeters * math.tan(rig.cameraRig.fovY / 2);
    final scale = math.min(1.0, halfHeight * .30 / .17);
    _scratch.setFrom(rig.eyeCenter);
    _scratch.addScaled(forward, distanceMeters);
    _scratch.addScaled(up, -halfHeight * screenAlignmentY);
    _pose.setIdentity();
    for (var i = 0; i < 3; i++) {
      _pose.setEntry(i, 0, -right[i] * scale);
      _pose.setEntry(i, 1, up[i] * scale);
      _pose.setEntry(i, 2, -forward[i] * scale);
      _pose.setEntry(i, 3, _scratch[i]);
    }
    // Assignment dirties world matrices; never mutate a live node matrix
    // without marking it dirty. Retain the same storage across all frames.
    root.localTransform = _pose;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    root.visible = false;
    parent.remove(root);
  }
}

class _FeedbackKey {
  _FeedbackKey(this.node, this.material, this.color);
  final Node node;
  final UnlitMaterial material;
  final Color color;
  bool? _pressed;
  set pressed(bool value) {
    if (_pressed == value) return;
    _pressed = value;
    final strength = value ? 1.0 : .25;
    material.baseColorFactor.setValues(
      color.r * strength,
      color.g * strength,
      color.b * strength,
      1,
    );
    node.mutateLocalTransform(
      (matrix) => matrix.setEntry(2, 3, value ? .039 : .046),
    );
  }
}

/// Paint-only stereo compositor for a dedicated, transparent feedback scene.
///
/// The scene supplied by [render] must contain only feedback, not the world.
/// flutter_scene gives each Scene/render view its own depth target; composing
/// this after the world preserves 1.8m stereo disparity while preventing the
/// floor/cockpit from occluding telemetry. No second clock or hit targets.
typedef VrControllerFeedbackRender =
    void Function(
      List<RenderView> views,
      Canvas canvas, {
      Rect? region,
      double? pixelRatio,
    });

class VrControllerFeedbackPainter extends CustomPainter {
  VrControllerFeedbackPainter({
    required Listenable repaint,
    required this.rig,
    required this.render,
    required this.visible,
    required this.pixelRatio,
  }) : super(repaint: repaint);

  final StereoHeadRig rig;
  final VrControllerFeedbackRender? Function() render;
  final bool Function() visible;
  final double pixelRatio;

  @override
  void paint(Canvas canvas, Size size) {
    if (!visible() || size.isEmpty) return;
    render()?.call(
      rig.buildStereoViews(),
      canvas,
      region: Offset.zero & size,
      pixelRatio: pixelRatio,
    );
  }

  @override
  bool? hitTest(Offset position) => false;

  @override
  bool shouldRepaint(VrControllerFeedbackPainter oldDelegate) =>
      oldDelegate.rig != rig ||
      oldDelegate.pixelRatio != pixelRatio ||
      oldDelegate.render != render ||
      oldDelegate.visible != visible;
}
