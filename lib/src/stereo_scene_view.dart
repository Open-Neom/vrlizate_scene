import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vrlizate/vrlizate.dart' show GazePointer, HeadTracker;

import 'stereo_head_rig.dart';

/// Stereoscopic VR view over a flutter_scene [Scene], driven by the
/// vrlizate input stack.
///
/// Renders [scene] as two half-screen eye views via [StereoHeadRig] and a
/// vrlizate `HeadTracker` (gyroscope), with touch-drag fallback. When
/// [gazeEnabled], a center-gaze raycast runs every frame through the
/// vrlizate `GazePointer` (adaptive dwell + grace period): dwell on a named
/// `Node` long enough and [onGazeSelect] fires — no joystick, no buttons.
///
/// Only nodes with a non-empty `Node.name` are gaze-interactive.
class StereoSceneView extends StatefulWidget {
  const StereoSceneView({
    super.key,
    required this.scene,
    this.rig,
    this.headTracker,
    this.touchFallback = true,
    this.gazeEnabled = true,
    this.gazeDwellSeconds = 2.0,
    this.onGazeSelect,
    this.onGazeHoverChanged,
    this.showReticle = true,
    this.onTick,
  });

  /// The flutter_scene scene to render in stereo.
  final Scene scene;

  /// External rig; when omitted an owned one is created (eye height 1.6 m).
  final StereoHeadRig? rig;

  /// External head tracker; when omitted an owned one is created and
  /// started/stopped with this widget's lifecycle.
  final HeadTracker? headTracker;

  /// Whether touch-drag rotates the view as a gyroscope fallback.
  final bool touchFallback;

  /// Whether center-gaze raycasting + dwell selection is active.
  final bool gazeEnabled;

  /// Base dwell time in seconds before a gaze selects its target.
  final double gazeDwellSeconds;

  /// Called when a named node is dwell-selected.
  final void Function(Node node)? onGazeSelect;

  /// Called when the gazed node changes (null when gaze leaves all nodes).
  final void Function(Node? node)? onGazeHoverChanged;

  /// Whether to draw the center reticle with dwell progress.
  final bool showReticle;

  /// Extra per-frame hook (elapsed, deltaSeconds).
  final void Function(Duration elapsed, double deltaSeconds)? onTick;

  @override
  State<StereoSceneView> createState() => _StereoSceneViewState();
}

class _StereoSceneViewState extends State<StereoSceneView> {
  late final StereoHeadRig _rig = widget.rig ??
      StereoHeadRig(); // default: eye at origin-ish, set by app if needed
  late final HeadTracker _headTracker =
      widget.headTracker ?? HeadTracker(target: _rig);
  late final GazePointer _gaze = GazePointer(
    cameraRig: _rig.cameraRig,
    dwellDuration: widget.gazeDwellSeconds,
  );

  final Map<String, Node> _nodesByName = {};
  final ValueNotifier<double> _dwellProgress = ValueNotifier(0);

  @override
  void initState() {
    super.initState();
    if (widget.rig == null) {
      _rig.eyeCenter.setValues(0, 1.6, 0);
    }
    _gaze.onDwellSelect = (id) {
      final node = _nodesByName[id];
      if (node != null) widget.onGazeSelect?.call(node);
    };
    _gaze.onGazeEnter = (id) =>
        widget.onGazeHoverChanged?.call(_nodesByName[id]);
    _gaze.onGazeExit = (_) => widget.onGazeHoverChanged?.call(null);
    _gaze.onDwellProgress = (_, progress) => _dwellProgress.value = progress;
    if (widget.headTracker == null) _headTracker.start();
  }

  @override
  void dispose() {
    if (widget.headTracker == null) _headTracker.stop();
    _dwellProgress.dispose();
    super.dispose();
  }

  void _tick(Duration elapsed, double dt) {
    if (widget.gazeEnabled) {
      final hit = widget.scene.raycast(_rig.gazeRay);
      final node = hit?.node;
      String? id;
      if (node != null && node.name.isNotEmpty) {
        id = node.name;
        _nodesByName[id] = node;
      }
      _gaze.update(dt, id);
    }
    widget.onTick?.call(elapsed, dt);
  }

  @override
  Widget build(BuildContext context) {
    Widget child = SceneView(
      widget.scene,
      viewsBuilder: (_) => _rig.buildStereoViews(),
      onTick: _tick,
    );

    if (widget.touchFallback) {
      child = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate: (d) =>
            _headTracker.applyTouchDelta(d.delta.dx, d.delta.dy),
        child: child,
      );
    }

    if (widget.showReticle && widget.gazeEnabled) {
      child = Stack(
        fit: StackFit.expand,
        children: [
          child,
          IgnorePointer(
            child: CustomPaint(
              painter: _ReticlePainter(progress: _dwellProgress),
            ),
          ),
        ],
      );
    }

    return child;
  }
}

/// Center-screen gaze reticle with a dwell-progress arc.
class _ReticlePainter extends CustomPainter {
  _ReticlePainter({required this.progress}) : super(repaint: progress);

  final ValueNotifier<double> progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final ring = Paint()
      ..color = Colors.white.withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final dot = Paint()..color = Colors.white.withValues(alpha: 0.9);
    final arc = Paint()
      ..color = Colors.cyanAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, 10, ring);
    canvas.drawCircle(center, 2, dot);
    final p = progress.value;
    if (p > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: 14),
        -3.141592653589793 / 2,
        p * 2 * 3.141592653589793,
        false,
        arc,
      );
    }
  }

  @override
  bool shouldRepaint(_ReticlePainter oldDelegate) => false;
}
