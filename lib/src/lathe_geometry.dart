import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// Surfaces of revolution from a 2-D profile: chess pieces, goblets,
/// columns, bottles — turned on the Y axis without any asset.
abstract final class LatheGeometry {
  /// Revolves [profile] (x = radius, y = height, in order from bottom to
  /// top) around Y in [segments] steps. Profile points with radius 0 close
  /// the shape; a sharp crease is two points at the same height.
  ///
  /// Normals come from the profile's tangents (smooth around, faceted only
  /// where the profile turns sharply), UVs wrap u around and run v up the
  /// profile. Winding is counter-clockwise seen from outside.
  static MeshGeometry revolve(List<vm.Vector2> profile, {int segments = 32}) {
    final arrays = revolveArrays(profile, segments: segments);
    return MeshGeometry.fromArrays(
      positions: arrays.positions,
      normals: arrays.normals,
      texCoords: arrays.texCoords,
      indices: arrays.indices,
    );
  }

  /// The CPU-side arrays behind [revolve] (pure Dart, testable without a
  /// GPU).
  static LatheArrays revolveArrays(
    List<vm.Vector2> profile, {
    int segments = 32,
  }) {
    if (profile.length < 2) {
      throw ArgumentError('A lathe profile needs at least two points');
    }
    if (segments < 3) throw ArgumentError('segments must be ≥ 3');
    final n = profile.length;
    final ring = segments + 1; // duplicate seam column for clean UVs

    // Profile tangents → 2-D normals (pointing outward: +x, then rotated).
    final normals2 = List<vm.Vector2>.generate(n, (i) {
      final prev = profile[math.max(i - 1, 0)];
      final next = profile[math.min(i + 1, n - 1)];
      final t = next - prev;
      if (t.length2 < 1e-12) return vm.Vector2(1, 0);
      final nrm = vm.Vector2(t.y, -t.x)..normalize();
      return nrm;
    });
    // Arc-length parameter for v.
    final arc = List<double>.filled(n, 0);
    for (var i = 1; i < n; i++) {
      arc[i] = arc[i - 1] + (profile[i] - profile[i - 1]).length;
    }
    final total = arc.last <= 0 ? 1.0 : arc.last;

    final positions = Float32List(n * ring * 3);
    final normals = Float32List(n * ring * 3);
    final uvs = Float32List(n * ring * 2);
    var p = 0, q = 0;
    for (var i = 0; i < n; i++) {
      final r = profile[i].x;
      final y = profile[i].y;
      final nx = normals2[i].x, ny = normals2[i].y;
      for (var s = 0; s < ring; s++) {
        final a = 2 * math.pi * s / segments;
        final ca = math.cos(a), sa = math.sin(a);
        positions[p] = r * ca;
        positions[p + 1] = y;
        positions[p + 2] = -r * sa;
        // Rotate the 2-D normal into the ring; degenerate rings (r = 0) keep
        // the profile normal's vertical part so caps shade flat.
        var wx = nx * ca, wy = ny, wz = -nx * sa;
        final len = math.sqrt(wx * wx + wy * wy + wz * wz);
        if (len > 1e-9) {
          wx /= len;
          wy /= len;
          wz /= len;
        } else {
          wy = 1;
        }
        normals[p] = wx;
        normals[p + 1] = wy;
        normals[p + 2] = wz;
        p += 3;
        uvs[q] = s / segments;
        uvs[q + 1] = 1 - arc[i] / total;
        q += 2;
      }
    }
    final indices = <int>[];
    for (var i = 0; i < n - 1; i++) {
      for (var s = 0; s < segments; s++) {
        final a = i * ring + s;
        final b = a + 1;
        final c = a + ring;
        final d = c + 1;
        // Skip degenerate triangles at the axis.
        if (profile[i].x > 1e-9 || profile[i + 1].x > 1e-9) {
          indices
            ..add(a)
            ..add(b)
            ..add(c)
            ..add(b)
            ..add(d)
            ..add(c);
        }
      }
    }
    return LatheArrays(
      positions: positions,
      normals: normals,
      texCoords: uvs,
      indices: indices,
    );
  }

  /// Classic Staunton-inspired silhouettes, [height] meters tall, base
  /// radius ≈ 0.4 × height. Knights get a forward-leaning head cut into
  /// the profile (a lathe cannot turn a horse, but reads as one at board
  /// scale).
  static MeshGeometry chessPiece(
    ChessPieceShape shape, {
    double height = 0.3,
  }) => revolve(chessProfile(shape, height: height), segments: 28);

  /// The (radius, height) profile of [shape], [height] meters tall.
  static List<vm.Vector2> chessProfile(
    ChessPieceShape shape, {
    double height = 0.3,
  }) {
    List<vm.Vector2> pts(List<List<double>> raw) => [
      for (final p in raw) vm.Vector2(p[0] * height, p[1] * height),
    ];
    // (radius, height) as fractions of [height].
    final profile = switch (shape) {
      ChessPieceShape.pawn => pts([
        [0, 0],
        [0.36, 0],
        [0.36, 0.06],
        [0.28, 0.1],
        [0.2, 0.22],
        [0.14, 0.5],
        [0.22, 0.56],
        [0.22, 0.6],
        [0.12, 0.64],
        [0.19, 0.78],
        [0.16, 0.92],
        [0.0, 1.0],
      ]),
      ChessPieceShape.rook => pts([
        [0, 0],
        [0.38, 0],
        [0.38, 0.08],
        [0.28, 0.14],
        [0.24, 0.6],
        [0.3, 0.66],
        [0.32, 0.9],
        [0.32, 1.0],
        [0.2, 1.0],
        [0.2, 0.88],
        [0, 0.88],
      ]),
      ChessPieceShape.knight => pts([
        [0, 0],
        [0.37, 0],
        [0.37, 0.08],
        [0.26, 0.14],
        [0.2, 0.42],
        [0.3, 0.5],
        [0.3, 0.62],
        [0.22, 0.72],
        [0.3, 0.86],
        [0.24, 0.96],
        [0, 1.0],
      ]),
      ChessPieceShape.bishop => pts([
        [0, 0],
        [0.36, 0],
        [0.36, 0.07],
        [0.26, 0.12],
        [0.16, 0.5],
        [0.24, 0.56],
        [0.24, 0.6],
        [0.14, 0.66],
        [0.2, 0.8],
        [0.12, 0.9],
        [0.06, 0.92],
        [0.06, 0.96],
        [0, 1.0],
      ]),
      ChessPieceShape.queen => pts([
        [0, 0],
        [0.4, 0],
        [0.4, 0.07],
        [0.3, 0.12],
        [0.18, 0.5],
        [0.28, 0.58],
        [0.28, 0.62],
        [0.16, 0.7],
        [0.26, 0.86],
        [0.2, 0.9],
        [0.1, 0.92],
        [0.08, 0.98],
        [0, 1.0],
      ]),
      ChessPieceShape.king => pts([
        [0, 0],
        [0.4, 0],
        [0.4, 0.07],
        [0.3, 0.12],
        [0.18, 0.5],
        [0.28, 0.58],
        [0.28, 0.62],
        [0.16, 0.7],
        [0.26, 0.84],
        [0.18, 0.88],
        [0.05, 0.9],
        [0.05, 1.0],
        [0, 1.0],
      ]),
    };
    return profile;
  }
}

/// Vertex arrays of a lathe: 3 floats per position/normal, 2 per UV.
class LatheArrays {
  const LatheArrays({
    required this.positions,
    required this.normals,
    required this.texCoords,
    required this.indices,
  });

  final Float32List positions;
  final Float32List normals;
  final Float32List texCoords;
  final List<int> indices;
}

enum ChessPieceShape { pawn, rook, knight, bishop, queen, king }
