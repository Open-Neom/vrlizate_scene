import 'dart:math' as math;
import 'dart:typed_data';

/// Orthonormal tangent-frame generator (`vec4(tx, ty, tz, handedness)`) for
/// procedural and retained meshes rendered by `flutter_scene`.
///
/// `flutter_scene` uploads an all-zero tangent stream whenever `tangents` is
/// omitted from `MeshData` or `MeshGeometry.fromArrays`, collapsing the TBN
/// basis of tangent-space normal maps. [compute] accumulates UV-projected
/// triangle gradients (Lengyel / glTF 2.0 convention) and orthonormalizes each
/// vertex tangent against its normal, falling back to Duff et al. (2017)'s
/// singularity-free orthonormal basis at UV seams, poles, or unmapped faces.
abstract final class VrMeshTangents {
  static Float32List compute({
    required Float32List positions,
    required Float32List normals,
    required Float32List texCoords,
    List<int>? indices,
  }) {
    final vertexCount = positions.length ~/ 3;
    if (vertexCount == 0) return Float32List(0);
    if (normals.length < vertexCount * 3 ||
        texCoords.length < vertexCount * 2) {
      throw ArgumentError(
        'VrMeshTangents.compute requires matching position, normal, and UV counts.',
      );
    }

    final tan1 = Float32List(vertexCount * 3);
    final tan2 = Float32List(vertexCount * 3);

    final triCount = indices != null ? indices.length ~/ 3 : vertexCount ~/ 3;
    for (var t = 0; t < triCount; t++) {
      final int i0;
      final int i1;
      final int i2;
      if (indices != null) {
        i0 = indices[t * 3];
        i1 = indices[t * 3 + 1];
        i2 = indices[t * 3 + 2];
      } else {
        i0 = t * 3;
        i1 = t * 3 + 1;
        i2 = t * 3 + 2;
      }
      if (i0 < 0 ||
          i1 < 0 ||
          i2 < 0 ||
          i0 >= vertexCount ||
          i1 >= vertexCount ||
          i2 >= vertexCount) {
        continue;
      }

      final p0 = i0 * 3, p1 = i1 * 3, p2 = i2 * 3;
      final uv0 = i0 * 2, uv1 = i1 * 2, uv2 = i2 * 2;

      final e1x = positions[p1] - positions[p0];
      final e1y = positions[p1 + 1] - positions[p0 + 1];
      final e1z = positions[p1 + 2] - positions[p0 + 2];

      final e2x = positions[p2] - positions[p0];
      final e2y = positions[p2 + 1] - positions[p0 + 1];
      final e2z = positions[p2 + 2] - positions[p0 + 2];

      final du1 = texCoords[uv1] - texCoords[uv0];
      final dv1 = texCoords[uv1 + 1] - texCoords[uv0 + 1];
      final du2 = texCoords[uv2] - texCoords[uv0];
      final dv2 = texCoords[uv2 + 1] - texCoords[uv0 + 1];

      final det = du1 * dv2 - du2 * dv1;
      if (!det.isFinite || det.abs() <= 1e-10) continue;
      final invDet = 1.0 / det;

      final sx = (dv2 * e1x - dv1 * e2x) * invDet;
      final sy = (dv2 * e1y - dv1 * e2y) * invDet;
      final sz = (dv2 * e1z - dv1 * e2z) * invDet;

      final tx = (du1 * e2x - du2 * e1x) * invDet;
      final ty = (du1 * e2y - du2 * e1y) * invDet;
      final tz = (du1 * e2z - du2 * e1z) * invDet;

      if (!sx.isFinite ||
          !sy.isFinite ||
          !sz.isFinite ||
          !tx.isFinite ||
          !ty.isFinite ||
          !tz.isFinite) {
        continue;
      }

      tan1[p0] += sx;
      tan1[p0 + 1] += sy;
      tan1[p0 + 2] += sz;
      tan1[p1] += sx;
      tan1[p1 + 1] += sy;
      tan1[p1 + 2] += sz;
      tan1[p2] += sx;
      tan1[p2 + 1] += sy;
      tan1[p2 + 2] += sz;

      tan2[p0] += tx;
      tan2[p0 + 1] += ty;
      tan2[p0 + 2] += tz;
      tan2[p1] += tx;
      tan2[p1 + 1] += ty;
      tan2[p1 + 2] += tz;
      tan2[p2] += tx;
      tan2[p2 + 1] += ty;
      tan2[p2 + 2] += tz;
    }

    final out = Float32List(vertexCount * 4);
    for (var v = 0; v < vertexCount; v++) {
      final p = v * 3;
      final o = v * 4;

      var nx = normals[p];
      var ny = normals[p + 1];
      var nz = normals[p + 2];
      final nLen = math.sqrt(nx * nx + ny * ny + nz * nz);
      if (nLen > 1e-9 && nLen.isFinite) {
        nx /= nLen;
        ny /= nLen;
        nz /= nLen;
      } else {
        nx = 0.0;
        ny = 1.0;
        nz = 0.0;
      }

      final t1x = tan1[p];
      final t1y = tan1[p + 1];
      final t1z = tan1[p + 2];

      // Gram-Schmidt orthogonalize tangent against vertex normal.
      final nDotT = nx * t1x + ny * t1y + nz * t1z;
      var ox = t1x - nx * nDotT;
      var oy = t1y - ny * nDotT;
      var oz = t1z - nz * nDotT;
      final oLen = math.sqrt(ox * ox + oy * oy + oz * oz);

      if (oLen > 1e-7 && oLen.isFinite) {
        ox /= oLen;
        oy /= oLen;
        oz /= oLen;

        // Handedness: sign(dot(cross(N, T), tan2)).
        final cx = ny * oz - nz * oy;
        final cy = nz * ox - nx * oz;
        final cz = nx * oy - ny * ox;
        final handed =
            (cx * tan2[p] + cy * tan2[p + 1] + cz * tan2[p + 2]) < 0.0
            ? -1.0
            : 1.0;

        out[o] = ox;
        out[o + 1] = oy;
        out[o + 2] = oz;
        out[o + 3] = handed;
      } else {
        // Duff et al. (2017) branch-free orthonormal basis fallback.
        final sign = nz >= 0.0 ? 1.0 : -1.0;
        final a = -1.0 / (sign + nz);
        final b = nx * ny * a;
        var fx = 1.0 + sign * nx * nx * a;
        var fy = sign * b;
        var fz = -sign * nx;
        final fLen = math.sqrt(fx * fx + fy * fy + fz * fz);
        if (fLen > 1e-9) {
          fx /= fLen;
          fy /= fLen;
          fz /= fLen;
        } else {
          fx = 1.0;
          fy = 0.0;
          fz = 0.0;
        }
        out[o] = fx;
        out[o + 1] = fy;
        out[o + 2] = fz;
        out[o + 3] = 1.0;
      }
    }
    return out;
  }
}
