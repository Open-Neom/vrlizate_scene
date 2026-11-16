import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_scene/scene.dart';

/// A flat, soft contact footprint for a known horizontal receiving surface.
///
/// This is authored translucent geometry, not a shadow map or ray tracing. It
/// does not follow uneven terrain or infer contact with other objects. Attach
/// one node in the object's coordinate space so both eyes share its geometry.
final class VrContactShadowSpec {
  const VrContactShadowSpec({
    required this.halfWidth,
    required this.halfLength,
    this.surfaceHeight = 0,
    this.centerX = 0,
    this.centerZ = 0,
    this.sides = 16,
    this.cornerExponent = .65,
    this.innerScale = .72,
    this.centerOpacity = .52,
    this.innerOpacity = .38,
  });

  final double halfWidth, halfLength;
  final double surfaceHeight, centerX, centerZ;

  /// Two rings plus one center vertex produce [sides] * 3 triangles.
  final int sides;

  /// One gives an ellipse; smaller positive values round a rectangular shape.
  final double cornerExponent;
  final double innerScale;
  final double centerOpacity, innerOpacity;

  /// CPU-only mesh construction. The outer ring fades to transparent black.
  MeshData buildMeshData() {
    _validate();
    final vertexCount = 1 + 2 * sides;
    final positions = Float32List(vertexCount * 3);
    final normals = Float32List(vertexCount * 3);
    final colors = Float32List(vertexCount * 4);
    final indices = <int>[];

    void vertex(int i, double x, double z, double alpha) {
      positions[i * 3] = centerX + x;
      positions[i * 3 + 1] = surfaceHeight;
      positions[i * 3 + 2] = centerZ + z;
      normals[i * 3 + 1] = 1;
      colors[i * 4 + 3] = alpha;
    }

    vertex(0, 0, 0, centerOpacity);
    for (var i = 0; i < sides; i++) {
      final angle = i * 2 * math.pi / sides;
      final c = math.cos(angle), s = math.sin(angle);
      final x = halfWidth * c.sign * math.pow(c.abs(), cornerExponent);
      final z = halfLength * s.sign * math.pow(s.abs(), cornerExponent);
      final inner = 1 + i;
      final next = 1 + (i + 1) % sides;
      vertex(inner, x * innerScale, z * innerScale, innerOpacity);
      vertex(inner + sides, x, z, 0);
      // Top-facing winding, matching Flutter Scene's horizontal plane.
      indices.addAll([
        0,
        next,
        inner,
        inner,
        next,
        inner + sides,
        next,
        next + sides,
        inner + sides,
      ]);
    }
    return MeshData(
      positions: positions,
      vertexCount: vertexCount,
      normals: normals,
      colors: colors,
      indices: indices,
    );
  }

  /// The material can also be shared by a host's own retained/instanced mesh.
  UnlitMaterial createMaterial({int depthLayer = 3}) => UnlitMaterial()
    ..alphaMode = AlphaMode.blend
    ..depthLayer = depthLayer;

  /// Creates GPU geometry; call only after Flutter Scene resources are ready.
  /// [depthLayer] orders a coplanar decal without lifting the footprint.
  Node createNode({String name = 'contact_shadow', int depthLayer = 3}) =>
      Node(
          name: name,
          mesh: Mesh(
            MeshGeometry.fromMeshData(buildMeshData()),
            createMaterial(depthLayer: depthLayer),
          ),
        )
        ..raycastable = false
        ..shadowCastingMode = ShadowCastingMode.off;

  void _validate() {
    if (!halfWidth.isFinite ||
        halfWidth <= 0 ||
        !halfLength.isFinite ||
        halfLength <= 0 ||
        !surfaceHeight.isFinite ||
        !centerX.isFinite ||
        !centerZ.isFinite ||
        sides < 3 ||
        !cornerExponent.isFinite ||
        cornerExponent <= 0 ||
        !innerScale.isFinite ||
        innerScale <= 0 ||
        innerScale >= 1 ||
        !centerOpacity.isFinite ||
        centerOpacity < 0 ||
        centerOpacity > 1 ||
        !innerOpacity.isFinite ||
        innerOpacity < 0 ||
        innerOpacity > 1) {
      throw ArgumentError('Invalid contact shadow footprint or opacity.');
    }
  }
}
