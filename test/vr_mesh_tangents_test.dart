import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;
import 'package:vrlizate/vrlizate.dart' as core;
import 'package:vrlizate_scene/vrlizate_scene.dart';

void main() {
  group('VrMeshTangents', () {
    test('generates unit, orthogonal tangents aligned with +u and handedness', () {
      final positions = Float32List.fromList([
        -1, -1, 0, // 0
        1, -1, 0, // 1
        1, 1, 0, // 2
        -1, 1, 0, // 3
      ]);
      final normals = Float32List.fromList([
        0, 0, 1,
        0, 0, 1,
        0, 0, 1,
        0, 0, 1,
      ]);
      final uvs = Float32List.fromList([
        0, 0,
        1, 0,
        1, 1,
        0, 1,
      ]);
      final tangents = VrMeshTangents.compute(
        positions: positions,
        normals: normals,
        texCoords: uvs,
        indices: const [0, 1, 2, 0, 2, 3],
      );
      expect(tangents.length, 16);
      for (var v = 0; v < 4; v++) {
        final t = vm.Vector3(
          tangents[v * 4],
          tangents[v * 4 + 1],
          tangents[v * 4 + 2],
        );
        final n = vm.Vector3(0, 0, 1);
        expect(t.length, closeTo(1.0, 1e-6));
        expect(t.dot(n), closeTo(0.0, 1e-6));
        expect(t.x, closeTo(1.0, 1e-6));
        expect(tangents[v * 4 + 3].abs(), 1.0);
      }
    });

    test('falls back to singularity-free orthonormal basis when UVs collapse', () {
      final dirs = <vm.Vector3>[
        vm.Vector3(0, 0, 1),
        vm.Vector3(0, 0, -1),
        vm.Vector3(0, 1, 0),
        vm.Vector3(0, -1, 0),
        vm.Vector3(1, 0, 0),
        vm.Vector3(-1, 0, 0),
        vm.Vector3(0.3, -0.7, -0.648)..normalize(),
      ];
      final positions = Float32List(dirs.length * 3);
      final normals = Float32List(dirs.length * 3);
      final collapsedUvs = Float32List(dirs.length * 2); // all (0, 0)
      for (var i = 0; i < dirs.length; i++) {
        dirs[i].copyIntoArray(normals, i * 3);
      }
      final tangents = VrMeshTangents.compute(
        positions: positions,
        normals: normals,
        texCoords: collapsedUvs,
        indices: const [0, 1, 2],
      );
      for (var i = 0; i < dirs.length; i++) {
        final t = vm.Vector3(
          tangents[i * 4],
          tangents[i * 4 + 1],
          tangents[i * 4 + 2],
        );
        expect(t.storage.every((x) => x.isFinite), isTrue);
        expect(t.length, closeTo(1.0, 1e-5));
        expect(t.dot(dirs[i]), closeTo(0.0, 1e-5));
        expect(tangents[i * 4 + 3], 1.0);
      }
    });

    test('retained MeshData and LatheGeometry populate finite unit tangents', () {
      final meshData = VrRetainedGpuResources.buildMeshData(core.CubeGeometry());
      expect(meshData.tangents, isNotNull);
      expect(meshData.tangents!.length, meshData.vertexCount * 4);
      for (var i = 0; i < meshData.vertexCount; i++) {
        final tx = meshData.tangents![i * 4];
        final ty = meshData.tangents![i * 4 + 1];
        final tz = meshData.tangents![i * 4 + 2];
        final tw = meshData.tangents![i * 4 + 3];
        expect(tx * tx + ty * ty + tz * tz, closeTo(1.0, 1e-5));
        expect(tw.abs(), 1.0);
      }

      final lathe = LatheGeometry.revolveArrays(
        LatheGeometry.chessProfile(ChessPieceShape.queen),
      );
      final latheVerts = lathe.positions.length ~/ 3;
      expect(lathe.tangents.length, latheVerts * 4);
      for (var i = 0; i < latheVerts; i++) {
        final t = vm.Vector3(
          lathe.tangents[i * 4],
          lathe.tangents[i * 4 + 1],
          lathe.tangents[i * 4 + 2],
        );
        final n = vm.Vector3(
          lathe.normals[i * 3],
          lathe.normals[i * 3 + 1],
          lathe.normals[i * 3 + 2],
        );
        expect(t.length, closeTo(1.0, 1e-5));
        expect(t.dot(n), closeTo(0.0, 1e-4));
      }
    });
  });
}
