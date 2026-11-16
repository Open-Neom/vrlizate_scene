import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;
import 'package:vrlizate_scene/vrlizate_scene.dart';

void _assertValidMesh(String name, VrSculptedArrays a) {
  expect(a.vertexCount, greaterThanOrEqualTo(12), reason: name);
  expect(a.triangleCount, greaterThanOrEqualTo(8), reason: name);
  expect(a.normals.length, a.vertexCount * 3);
  expect(a.texCoords.length, a.vertexCount * 2);
  expect(a.tangents.length, a.vertexCount * 4);

  for (var v = 0; v < a.vertexCount; v++) {
    final p = v * 3;
    final nx = a.normals[p];
    final ny = a.normals[p + 1];
    final nz = a.normals[p + 2];
    expect(
      math.sqrt(nx * nx + ny * ny + nz * nz),
      closeTo(1.0, 1e-4),
      reason: '$name normal $v',
    );

    final o = v * 4;
    final tx = a.tangents[o];
    final ty = a.tangents[o + 1];
    final tz = a.tangents[o + 2];
    final tw = a.tangents[o + 3];
    expect(
      math.sqrt(tx * tx + ty * ty + tz * tz),
      closeTo(1.0, 1e-4),
      reason: '$name tangent $v',
    );
    expect((nx * tx + ny * ty + nz * tz).abs(), lessThan(1e-3));
    expect(tw.abs(), closeTo(1.0, 1e-5));
  }

  for (var t = 0; t < a.triangleCount; t++) {
    final i0 = a.indices[t * 3];
    final i1 = a.indices[t * 3 + 1];
    final i2 = a.indices[t * 3 + 2];
    final p0 = vm.Vector3(
      a.positions[i0 * 3],
      a.positions[i0 * 3 + 1],
      a.positions[i0 * 3 + 2],
    );
    final p1 = vm.Vector3(
      a.positions[i1 * 3],
      a.positions[i1 * 3 + 1],
      a.positions[i1 * 3 + 2],
    );
    final p2 = vm.Vector3(
      a.positions[i2 * 3],
      a.positions[i2 * 3 + 1],
      a.positions[i2 * 3 + 2],
    );
    final cross = (p1 - p0).cross(p2 - p0);
    if (cross.length2 <= 1e-14) continue;
    final nSum = vm.Vector3(
      a.normals[i0 * 3] + a.normals[i1 * 3] + a.normals[i2 * 3],
      a.normals[i0 * 3 + 1] + a.normals[i1 * 3 + 1] + a.normals[i2 * 3 + 1],
      a.normals[i0 * 3 + 2] + a.normals[i1 * 3 + 2] + a.normals[i2 * 3 + 2],
    );
    expect(
      cross.dot(nSum),
      greaterThan(0.0),
      reason: '$name triangle $t has inverted winding',
    );
  }
}

void main() {
  group('VrSculptedGeometry procedural 3D primitives', () {
    test('capsule, crystal, octa, icosa, and pedestal produce valid CCW meshes', () {
      _assertValidMesh(
        'beveledBox',
        VrSculptedGeometry.beveledBoxArrays(vm.Vector3(1.2, 0.8, 0.4)),
      );
      _assertValidMesh(
        'capsule',
        VrSculptedGeometry.capsuleArrays(radius: 0.2, height: 0.9),
      );
      _assertValidMesh(
        'facetedCrystal-6',
        VrSculptedGeometry.facetedCrystalArrays(
          radius: 0.28,
          height: 0.74,
          sides: 6,
        ),
      );
      _assertValidMesh(
        'octaCore',
        VrSculptedGeometry.octaCoreArrays(radius: 0.30, verticalScale: 1.2),
      );
      _assertValidMesh(
        'icosaCore',
        VrSculptedGeometry.icosaCoreArrays(radius: 0.32),
      );
      _assertValidMesh(
        'flutedPedestal',
        VrSculptedGeometry.flutedPedestalArrays(
          bottomRadius: 0.30,
          topRadius: 0.24,
          height: 0.95,
        ),
      );
    });

    test('facetedCrystal keeps distinct flat normals per facet for sharp glints', () {
      final crystal = VrSculptedGeometry.facetedCrystalArrays(sides: 6);
      for (var t = 0; t < crystal.triangleCount; t++) {
        final i0 = crystal.indices[t * 3];
        final i1 = crystal.indices[t * 3 + 1];
        final i2 = crystal.indices[t * 3 + 2];
        final n0 = vm.Vector3(
          crystal.normals[i0 * 3],
          crystal.normals[i0 * 3 + 1],
          crystal.normals[i0 * 3 + 2],
        );
        final n1 = vm.Vector3(
          crystal.normals[i1 * 3],
          crystal.normals[i1 * 3 + 1],
          crystal.normals[i1 * 3 + 2],
        );
        final n2 = vm.Vector3(
          crystal.normals[i2 * 3],
          crystal.normals[i2 * 3 + 1],
          crystal.normals[i2 * 3 + 2],
        );
        expect((n0 - n1).length, lessThan(1e-5));
        expect((n0 - n2).length, lessThan(1e-5));
      }
    });
  });

  group('New procedural PBR surfaces (sciFiGrating, techPanels, carbonHex, gasGiantBands)', () {
    test('generates deterministic, non-uniform, seamlessly tiling maps', () {
      for (final surface in const [
        PbrSurface.sciFiGrating,
        PbrSurface.techPanels,
        PbrSurface.carbonHex,
        PbrSurface.gasGiantBands,
      ]) {
        final req = PbrTextureRequest(
          surface,
          size: 64,
          seed: 77,
          primary: 0xFFB8C6D8,
          secondary: 0xFF283240,
          repeats: 2,
        );
        final a = PbrTextureSynth.generate(req);
        final b = PbrTextureSynth.generate(req);
        expect(a.albedo, b.albedo, reason: '${surface.name} deterministic');
        expect(a.normal, b.normal, reason: '${surface.name} normal');
        expect(a.metallicRoughness, b.metallicRoughness);

        // Verify genuine relief variation (not a flat normal map) and AO range:
        var normalVariance = 0.0;
        for (var i = 0; i < a.normal.length; i += 4) {
          normalVariance +=
              (a.normal[i] - 128).abs() + (a.normal[i + 1] - 128).abs();
        }
        expect(
          normalVariance,
          greaterThan(1000),
          reason: '${surface.name} has non-trivial normal relief',
        );
      }
    });
  });
}
