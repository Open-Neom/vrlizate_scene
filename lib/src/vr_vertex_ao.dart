import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math.dart' as vm;

/// Zero-fragment-cost analytical Vertex Ambient Occlusion (`COLOR_0`) and
/// anti-repetition macro tint baker for stereoscopic VR meshes.
///
/// Mobile TBDR GPUs cannot afford screen-space ambient occlusion (SSAO) in
/// stereo at 60–120 Hz without spilling shader registers and doubling depth/normal
/// bandwidth. Because `flutter_scene`'s standard PBR shader already multiplies
/// `v_color` into linear albedo (`vertexColorWeight = 1.0`), baking smooth
/// floor-contact darkening and underside self-occlusion into vertex `COLOR_0`
/// grounds walls, columns, pedestals, and props at **zero runtime GPU cost**.
abstract final class VrVertexAoBaker {
  /// Computes RGBA float32 vertex colors (`4 * vertexCount`) combining:
  /// 1. Smooth floor-contact darkening near the mesh's base `minY` over
  ///    [contactHeightFraction] of the mesh's vertical span (`1 - groundAoStrength`
  ///    at the floor plane, smoothly easing to `1.0`).
  /// 2. Subtle underside self-shadowing (`downwardNormalShadow`) on downward-facing
  ///    bevels, soffits, and overhangs so stereo silhouettes read clearly even
  ///    without point-light shadows.
  static Float32List bakeGroundAndCreaseColors({
    required Float32List positions,
    required Float32List normals,
    double groundAoStrength = 0.36,
    double contactHeightFraction = 0.35,
    double downwardNormalShadow = 0.14,
    double? explicitMinY,
    double? explicitMaxY,
    vm.Vector3? baseTint,
  }) {
    final vertexCount = positions.length ~/ 3;
    final colors = Float32List(vertexCount * 4);
    if (vertexCount == 0) return colors;

    var minY = explicitMinY ?? double.infinity;
    var maxY = explicitMaxY ?? double.negativeInfinity;
    if (explicitMinY == null || explicitMaxY == null) {
      for (var i = 0; i < vertexCount; i++) {
        final y = positions[i * 3 + 1];
        if (explicitMinY == null && y < minY) minY = y;
        if (explicitMaxY == null && y > maxY) maxY = y;
      }
    }

    final spanY = math.max(1e-4, maxY - minY);
    final aoBand = math.max(1e-4, spanY * contactHeightFraction.clamp(0.05, 1.0));
    final gStrength = groundAoStrength.clamp(0.0, 0.85);
    final nShadow = downwardNormalShadow.clamp(0.0, 0.50);
    final tr = baseTint?.x ?? 1.0;
    final tg = baseTint?.y ?? 1.0;
    final tb = baseTint?.z ?? 1.0;

    for (var i = 0; i < vertexCount; i++) {
      final y = positions[i * 3 + 1];
      final ny = normals.length > i * 3 + 1 ? normals[i * 3 + 1] : 0.0;

      final hNorm = ((y - minY) / aoBand).clamp(0.0, 1.0);
      // Smoothstep curve keeps darkening concentrated right at the floor seam.
      final smoothH = hNorm * hNorm * (3.0 - 2.0 * hNorm);
      final groundFactor = 1.0 - gStrength * (1.0 - smoothH);

      final downAmount = math.max(0.0, -ny).clamp(0.0, 1.0);
      final normalFactor = 1.0 - nShadow * downAmount;

      final shade = (groundFactor * normalFactor).clamp(0.12, 1.0);
      final o = i * 4;
      colors[o] = (shade * tr).clamp(0.0, 1.0);
      colors[o + 1] = (shade * tg).clamp(0.0, 1.0);
      colors[o + 2] = (shade * tb).clamp(0.0, 1.0);
      colors[o + 3] = 1.0;
    }
    return colors;
  }

  /// Deterministic subtle warm/cool tint (`Vector4`) for modular grid cell
  /// `(cellX, cellZ)` to break visible texture tiling across large floors/walls.
  static vm.Vector4 macroCellTint(
    int cellX,
    int cellZ, {
    double amplitude = 0.045,
    int seed = 17,
  }) {
    final amp = amplitude.clamp(0.0, 0.25);
    final h1 = _hash01(cellX, cellZ, seed);
    final h2 = _hash01(cellX + 31, cellZ - 19, seed ^ 0x5A);
    final lumaShift = (h1 - 0.5) * 2.0 * amp;
    final tempShift = (h2 - 0.5) * amp * 0.65;
    return vm.Vector4(
      (1.0 + lumaShift + tempShift).clamp(0.5, 1.5),
      (1.0 + lumaShift).clamp(0.5, 1.5),
      (1.0 + lumaShift - tempShift).clamp(0.5, 1.5),
      1.0,
    );
  }

  static double _hash01(int x, int z, int seed) {
    var h = x * 374761393 + z * 668265263 + seed * 1442695041;
    h = (h ^ (h >> 13)) * 1274126177;
    h = h ^ (h >> 16);
    return (h & 0xFFFFFF) / 0x1000000;
  }
}
