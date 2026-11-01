import 'dart:math';

import 'package:flutter/painting.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import '../domain/services/vr_depth_color_palette.dart';
import 'vr_spatial_tracking.dart';

/// Holographic 3D hands anchored relative to the viewer.
///
/// Supports both decorative idle animation (for demos with `enableHandTracking`
/// on) and real-time measured 3D poses supplied through [VrSceneHandPoseBridge]
/// (e.g. from VRlizate Desktop Estación Faro, Visor Ultra-Wide camera, or
/// Joystick camera). When [colorByDepth] is enabled (SDK default), each hand's
/// joints and palm dynamically shift color according to real metric distance
/// (`meters`) from the viewer across all `.vrlz` and `.vrlw` experiences.
class SimulatedHandVisuals {
  SimulatedHandVisuals(
    this.parent,
    this.glowColor, {
    this.hideWhenUntracked = false,
    this.colorByDepth = true,
    this.positionSmoothingAlpha = 0.36,
    Mesh Function(vm.Vector3 size, PhysicallyBasedMaterial material)?
    meshBuilder,
  }) {
    final createMesh = meshBuilder ?? _boxMesh;
    for (var side = 0; side < 2; side++) {
      final sideName = side == 0 ? 'r' : 'l';
      final handMat = PhysicallyBasedMaterial()
        ..alphaMode = AlphaMode.blend
        ..baseColorFactor = vm.Vector4(
          glowColor.r,
          glowColor.g,
          glowColor.b,
          0.66,
        )
        ..emissiveFactor = vm.Vector4(
          glowColor.r * 0.75,
          glowColor.g * 0.75,
          glowColor.b * 0.75,
          1,
        )
        ..roughnessFactor = 0.22;
      final tipMat = PhysicallyBasedMaterial()
        ..alphaMode = AlphaMode.blend
        ..baseColorFactor = vm.Vector4(1, 1, 1, 0.80)
        ..emissiveFactor = vm.Vector4(glowColor.r, glowColor.g, glowColor.b, 1)
        ..roughnessFactor = 0;
      _handMaterials.add(handMat);
      _tipMaterials.add(tipMat);

      final palmMesh = createMesh(vm.Vector3(0.052, 0.014, 0.052), handMat);
      final fingerMesh = createMesh(vm.Vector3(0.010, 0.010, 0.030), handMat);
      final tipMesh = createMesh(vm.Vector3(0.019, 0.019, 0.019), tipMat);

      _add('holo_palm_$sideName', palmMesh);
      for (var finger = 0; finger < 5; finger++) {
        _add('holo_finger_${sideName}_$finger', fingerMesh);
      }
      _add('holo_tip_$sideName', tipMesh);
    }
    if (hideWhenUntracked) {
      _setAllVisible(false);
    }
  }

  final Node parent;
  final Color glowColor;
  bool hideWhenUntracked;
  bool colorByDepth;
  final double positionSmoothingAlpha;
  final List<PhysicallyBasedMaterial> _handMaterials =
      <PhysicallyBasedMaterial>[];
  final List<PhysicallyBasedMaterial> _tipMaterials =
      <PhysicallyBasedMaterial>[];
  final List<Node> _nodes = [];
  final List<vm.Vector3?> _smoothedRelBySide = <vm.Vector3?>[null, null];
  final vm.Vector3 _handCenter = vm.Vector3.zero();
  final vm.Vector3 _position = vm.Vector3.zero();

  static Mesh _boxMesh(vm.Vector3 size, PhysicallyBasedMaterial material) =>
      Mesh(CuboidGeometry(size), material);

  static const _fingerOffsets = [
    (-0.028, 0.004, -0.032),
    (-0.012, 0.007, -0.048),
    (0.004, 0.007, -0.052),
    (0.018, 0.005, -0.044),
    (0.032, 0.003, -0.036),
  ];

  void _add(String name, Mesh mesh) {
    final node = Node(name: name, mesh: mesh)..raycastable = false;
    _nodes.add(node);
    parent.add(node);
  }

  void _setSideVisible(int side, bool visible) {
    final base = side * 7;
    for (var i = 0; i < 7; i++) {
      _nodes[base + i].visible = visible;
    }
  }

  void _setAllVisible(bool visible) {
    for (final node in _nodes) {
      node.visible = visible;
    }
  }

  void update(
    vm.Vector3 eye,
    vm.Quaternion orientation,
    double seconds, {
    VrTrackedHandsSnapshot? trackedHands,
  }) {
    final hasLive = trackedHands != null && trackedHands.hasTrackedHand;
    if (!hasLive && hideWhenUntracked) {
      _setAllVisible(false);
      _smoothedRelBySide[0] = null;
      _smoothedRelBySide[1] = null;
      return;
    }

    final hoverY = sin(seconds * 2.2) * 0.008;
    final alpha = positionSmoothingAlpha.clamp(0.05, 1.0);

    for (var side = 0; side < 2; side++) {
      // side == 0 is right ('r'), side == 1 is left ('l')
      final mirror = side == 0 ? 1.0 : -1.0;
      final base = side * 7;
      final sample = side == 0 ? trackedHands?.right : trackedHands?.left;
      final isTracked = sample != null && sample.isTracked;

      if (hideWhenUntracked && !isTracked) {
        _setSideVisible(side, false);
        _smoothedRelBySide[side] = null;
        continue;
      }
      _setSideVisible(side, true);

      double handDistanceMeters;
      if (isTracked) {
        final rawRel = sample.headRelativeMeters;
        final targetLocal = vm.Vector3(
          // flutter_scene's screenRight is -X at rest; negate +X user-right so
          // the right hand renders on the right viewport side matching laserX.
          (-rawRel.x).clamp(-0.68, 0.68),
          rawRel.y.clamp(-0.58, 0.48),
          // Ergonomic minimum stereo distance (-0.48m): never "muy pegado"!
          rawRel.z.clamp(-1.35, -0.48),
        );
        final prev = _smoothedRelBySide[side];
        if (prev == null) {
          _smoothedRelBySide[side] = targetLocal.clone();
        } else {
          prev.setValues(
            prev.x + (targetLocal.x - prev.x) * alpha,
            prev.y + (targetLocal.y - prev.y) * alpha,
            prev.z + (targetLocal.z - prev.z) * alpha,
          );
        }
        final smoothed = _smoothedRelBySide[side]!;
        _handCenter.setFrom(smoothed);
        handDistanceMeters = smoothed.length;
      } else {
        _smoothedRelBySide[side] = null;
        _handCenter.setValues(mirror * 0.17, -0.22 + hoverY, -0.56);
        handDistanceMeters = _handCenter.length;
      }

      // Per-hand metric depth coloring for .vrlz and .vrlw experiences
      final handColor = colorByDepth
          ? VrDepthColorPalette.colorForDistanceMeters(handDistanceMeters)
          : glowColor;
      final isPinch = isTracked && sample.isPinching;
      final isRaised = isTracked && sample.raised;
      final confAlpha = isTracked
          ? (0.68 * sample.confidence.clamp(0.30, 1.0))
          : 0.58;
      final boost = isPinch ? 1.55 : (isRaised ? 1.20 : 0.85);
      final handMat = _handMaterials[side];
      final tipMat = _tipMaterials[side];
      handMat
        ..baseColorFactor = vm.Vector4(
          handColor.r,
          handColor.g,
          handColor.b,
          confAlpha,
        )
        ..emissiveFactor = vm.Vector4(
          (handColor.r * boost).clamp(0.0, 1.35),
          (handColor.g * boost).clamp(0.0, 1.35),
          (handColor.b * boost).clamp(0.0, 1.35),
          1.0,
        );
      tipMat
        ..baseColorFactor = vm.Vector4(1.0, 1.0, 1.0, confAlpha + 0.12)
        ..emissiveFactor = isPinch
            ? vm.Vector4(1.0, 0.84, 0.22, 1.0)
            : vm.Vector4(handColor.r, handColor.g, handColor.b, 1.0);

      orientation.rotate(_handCenter);
      _handCenter.add(eye);
      _nodes[base].position = _handCenter;

      final pinch = isTracked ? sample.pinchStrength.clamp(0.0, 1.0) : 0.0;
      for (var finger = 0; finger < _fingerOffsets.length; finger++) {
        final offset = _fingerOffsets[finger];
        final flex = isTracked
            ? -pinch * (finger <= 1 ? 0.016 : 0.008)
            : sin(seconds * 1.8 + finger + side * 1.5) * 0.003;
        final pinchPullX = (finger == 0 ? 0.014 : (finger == 1 ? -0.008 : 0.0)) *
            pinch;
        final pinchPullZ = (finger <= 1 ? 0.014 : 0.0) * pinch;
        _position.setValues(
          mirror * (offset.$1 + pinchPullX),
          offset.$2 + flex,
          offset.$3 + pinchPullZ,
        );
        orientation.rotate(_position);
        _position.add(_handCenter);
        _nodes[base + 1 + finger].position = _position;
      }

      _position.setValues(
        mirror * (-0.012 - 0.008 * pinch),
        0.007 - 0.008 * pinch,
        -0.048 + 0.014 * pinch,
      );
      orientation.rotate(_position);
      _position.add(_handCenter);
      _nodes[base + 6].position = _position;
    }
  }

  void dispose() {
    for (final node in _nodes) {
      parent.remove(node);
    }
    _nodes.clear();
  }
}
