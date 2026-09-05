import 'dart:math';

import 'package:flutter/painting.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// Decorative hands anchored relative to the viewer, with idle animation.
///
/// These visuals do not consume hand tracking or represent measured hand poses.
/// They never participate in picking, and their frame updates reuse scratch
/// vectors and each node's transform storage.
class SimulatedHandVisuals {
  SimulatedHandVisuals(
    this.parent,
    Color glowColor, {
    Mesh Function(vm.Vector3 size, PhysicallyBasedMaterial material)?
    meshBuilder,
  }) {
    final createMesh = meshBuilder ?? _boxMesh;
    final handMaterial = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(
        glowColor.r,
        glowColor.g,
        glowColor.b,
        0.85,
      )
      ..emissiveFactor = vm.Vector4(glowColor.r, glowColor.g, glowColor.b, 1)
      ..roughnessFactor = 0.15;
    final tipMaterial = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(1, 1, 1, 1)
      ..emissiveFactor = vm.Vector4(glowColor.r, glowColor.g, glowColor.b, 1)
      ..roughnessFactor = 0;
    final palmMesh = createMesh(vm.Vector3(0.065, 0.018, 0.065), handMaterial);
    final fingerMesh = createMesh(
      vm.Vector3(0.012, 0.012, 0.035),
      handMaterial,
    );
    final tipMesh = createMesh(vm.Vector3(0.024, 0.024, 0.024), tipMaterial);

    for (final side in const ['r', 'l']) {
      _add('holo_palm_$side', palmMesh);
      for (var finger = 0; finger < 5; finger++) {
        _add('holo_finger_${side}_$finger', fingerMesh);
      }
      _add('holo_tip_$side', tipMesh);
    }
  }

  final Node parent;
  final List<Node> _nodes = [];
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

  void update(vm.Vector3 eye, vm.Quaternion orientation, double seconds) {
    final hoverY = sin(seconds * 2.2) * 0.008;
    for (var side = 0; side < 2; side++) {
      final mirror = side == 0 ? 1.0 : -1.0;
      final base = side * 7;
      _handCenter.setValues(mirror * 0.17, -0.22 + hoverY, -0.46);
      orientation.rotate(_handCenter);
      _handCenter.add(eye);
      _nodes[base].position = _handCenter;

      for (var finger = 0; finger < _fingerOffsets.length; finger++) {
        final offset = _fingerOffsets[finger];
        final flex = sin(seconds * 1.8 + finger + side * 1.5) * 0.003;
        _position.setValues(mirror * offset.$1, offset.$2 + flex, offset.$3);
        orientation.rotate(_position);
        _position.add(_handCenter);
        _nodes[base + 1 + finger].position = _position;
      }

      _position.setValues(mirror * -0.012, 0.007, -0.048);
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
