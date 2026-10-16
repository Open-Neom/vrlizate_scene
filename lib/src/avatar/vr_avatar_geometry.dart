import 'dart:math' as math;
import 'dart:typed_data';

/// The host chooses distance thresholds and applies hysteresis between them.
enum VrAvatarDetail { near, far }

/// Three unit shapes, all bounded by [-.5, .5] on each axis.
enum VrAvatarShape { round, softBox, petal }

/// CPU mesh data kept separate from Scene's GPU allocation boundary.
class VrAvatarMeshData {
  const VrAvatarMeshData({
    required this.positions,
    required this.normals,
    required this.texCoords,
    required this.indices,
  });

  final Float32List positions;
  final Float32List normals;
  final Float32List texCoords;
  final Uint16List indices;
  int get triangleCount => indices.length ~/ 3;
}

/// Smooth, closed primitives with outward winding matching Flutter Scene.
///
/// This never touches a GPU. The renderer uploads each shape/detail pair once
/// and shares it across avatars. Proportions are instance transforms, not mesh
/// regeneration; even the far silhouette remains round rather than a cube.
VrAvatarMeshData buildVrAvatarMeshData(
  VrAvatarShape shape,
  VrAvatarDetail detail,
) {
  final segments = detail == VrAvatarDetail.near ? 16 : 8;
  final rings = detail == VrAvatarDetail.near ? 8 : 4;
  final positions = <double>[];
  final normals = <double>[];
  final uv = <double>[];
  for (var row = 0; row <= rings; row++) {
    final theta = math.pi * row / rings;
    final sinTheta = math.sin(theta);
    final cosTheta = math.cos(theta);
    for (var column = 0; column <= segments; column++) {
      final phi = 2 * math.pi * column / segments;
      final cosPhi = math.cos(phi);
      final sinPhi = math.sin(phi);
      var x = sinTheta * cosPhi;
      var y = cosTheta;
      var z = sinTheta * sinPhi;
      var nx = x;
      var ny = y;
      var nz = z;
      switch (shape) {
        case VrAvatarShape.round:
          x *= .5;
          y *= .5;
          z *= .5;
        case VrAvatarShape.softBox:
          // Radial projection onto an L4 sphere: rounded shell, smooth normals.
          final radius =
              .5 / math.pow(x * x * x * x + y * y * y * y + z * z * z * z, .25);
          x *= radius;
          y *= radius;
          z *= radius;
          nx = x * x * x;
          ny = y * y * y;
          nz = z * z * z;
        case VrAvatarShape.petal:
          final radial = .5 * math.pow(sinTheta.clamp(0, 1), 1.5);
          x = radial * cosPhi;
          y *= .5;
          z = radial * sinPhi;
          if (row == 0 || row == rings) {
            nx = 0;
            ny = cosTheta;
            nz = 0;
          } else {
            nx = .5 * sinTheta * cosPhi;
            ny = .75 * math.sqrt(sinTheta) * cosTheta;
            nz = .5 * sinTheta * sinPhi;
          }
      }
      final length = math.sqrt(nx * nx + ny * ny + nz * nz);
      positions.addAll([x, y, z]);
      normals.addAll([nx / length, ny / length, nz / length]);
      uv.addAll([column / segments, row / rings]);
    }
  }
  final indices = <int>[];
  for (var row = 0; row < rings; row++) {
    for (var column = 0; column < segments; column++) {
      final a = row * (segments + 1) + column;
      final b = a + segments + 1;
      // The poles have one fan triangle per sector, not zero-area quads.
      if (row > 0) indices.addAll([a, a + 1, b]);
      if (row < rings - 1) indices.addAll([a + 1, b + 1, b]);
    }
  }
  return VrAvatarMeshData(
    positions: Float32List.fromList(positions),
    normals: Float32List.fromList(normals),
    texCoords: Float32List.fromList(uv),
    indices: Uint16List.fromList(indices),
  );
}
