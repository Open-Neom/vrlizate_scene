import 'dart:math' as math;

// Real Scene CPU primitive as a winding reference, without GPU allocation.
// ignore: implementation_imports
import 'package:flutter_scene/src/geometry/primitives.dart'
    show buildCuboidArrays;
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;
import 'package:vrlizate_avatar/vrlizate_avatar.dart';
import 'package:vrlizate_scene/src/avatar/vr_avatar_geometry.dart';
import 'package:vrlizate_scene/src/avatar/vr_avatar_plan.dart';

vm.Vector3 _vertex(List<double> data, int index) =>
    vm.Vector3(data[index * 3], data[index * 3 + 1], data[index * 3 + 2]);

double _facing(List<double> p, List<double> n, int a, int b, int c) =>
    (_vertex(p, b) - _vertex(p, a))
        .cross(_vertex(p, c) - _vertex(p, a))
        .dot(_vertex(n, a) + _vertex(n, b) + _vertex(n, c));

void main() {
  final meshes = {
    for (final shape in VrAvatarShape.values)
      for (final detail in VrAvatarDetail.values)
        (shape, detail): buildVrAvatarMeshData(shape, detail),
  };

  test(
    'all shared meshes have valid outward faces and smooth unit normals',
    () {
      final reference = buildCuboidArrays(vm.Vector3.all(1));
      final frontSign = _facing(
        reference.positions,
        reference.normals!,
        reference.indices[0],
        reference.indices[1],
        reference.indices[2],
      ).sign;
      expect(frontSign, isNot(0));
      for (final entry in meshes.entries) {
        final mesh = entry.value;
        final count = mesh.positions.length ~/ 3;
        expect(
          mesh.positions.every((v) => v.isFinite && v.abs() <= .500001),
          isTrue,
        );
        expect(mesh.normals.length, mesh.positions.length);
        expect(mesh.texCoords.length, count * 2);
        expect(
          mesh.texCoords.every((v) => v.isFinite && v >= 0 && v <= 1),
          isTrue,
        );
        expect(mesh.indices.every((v) => v >= 0 && v < count), isTrue);
        for (var vertex = 0; vertex < count; vertex++) {
          expect(
            _vertex(mesh.normals, vertex).length,
            closeTo(1, 2e-6),
            reason: '${entry.key}',
          );
        }
        for (var i = 0; i < mesh.indices.length; i += 3) {
          final a = mesh.indices[i],
              b = mesh.indices[i + 1],
              c = mesh.indices[i + 2];
          expect(
            _facing(mesh.positions, mesh.normals, a, b, c) * frontSign,
            greaterThan(1e-8),
            reason: '${entry.key}, face ${i ~/ 3}',
          );
        }
        expect(mesh.triangleCount, lessThanOrEqualTo(224));
      }
    },
  );

  test(
    'all species/proportion extremes fit the stage with feet on the floor',
    () {
      for (final species in VrAvatarSpecies.values) {
        for (final height in [1.0, 2.2]) {
          for (final head in [.8, 1.25]) {
            for (final feature in [.6, 1.4]) {
              final plan = VrAvatarPlan.build(
                VrAvatarAppearance(
                  species: species,
                  heightMeters: height,
                  headScale: head,
                  featureScale: feature,
                  pattern: VrAvatarPattern.spots,
                ),
              );
              final context = '$species h=$height head=$head feature=$feature';
              expect(plan.bounds.min.y, closeTo(0, 1e-6), reason: context);
              expect(plan.bounds.max.y, closeTo(height, 1e-6), reason: context);
              expect(
                plan.horizontalRadius,
                lessThanOrEqualTo(1.400001),
                reason: context,
              );
              // Both LODs must remain inside the published conservative bounds;
              // camera frustum culling cannot clip a larger near-detail feature.
              for (final detail in VrAvatarDetail.values) {
                var minY = double.infinity;
                var maxY = double.negativeInfinity;
                var maxRadius = 0.0;
                var triangles = 0;
                for (final part in plan.partsFor(detail)) {
                  final mesh = meshes[(part.shape, detail)]!;
                  triangles += mesh.triangleCount;
                  for (var i = 0; i < mesh.positions.length ~/ 3; i++) {
                    final point = part.transform.transformed3(
                      _vertex(mesh.positions, i),
                    );
                    minY = math.min(minY, point.y);
                    maxY = math.max(maxY, point.y);
                    maxRadius = math.max(
                      maxRadius,
                      math.sqrt(point.x * point.x + point.z * point.z),
                    );
                  }
                }
                expect(minY, closeTo(0, 1e-6), reason: context);
                expect(maxY, lessThanOrEqualTo(height + 1e-6), reason: context);
                expect(
                  maxRadius,
                  lessThanOrEqualTo(plan.horizontalRadius + 1e-6),
                  reason: context,
                );
                expect(triangles, plan.triangleCount(detail));
                expect(
                  triangles,
                  lessThanOrEqualTo(
                    detail == VrAvatarDetail.near ? 12000 : 2500,
                  ),
                  reason: context,
                );
                expect(
                  plan.batchCount(detail),
                  lessThanOrEqualTo(12),
                  reason: context,
                );
              }
            }
          }
        }
      }
    },
  );

  test(
    'colors and proportions preserve instance identities and batch topology',
    () {
      for (final species in VrAvatarSpecies.values) {
        for (final pattern in VrAvatarPattern.values) {
          final original = VrAvatarAppearance(
            species: species,
            pattern: pattern,
          );
          final before = VrAvatarPlan.build(original);
          final recolored = VrAvatarPlan.build(
            original.copyWith(
              bodyColorArgb: 0xff2a8743,
              accentColorArgb: 0xffec9d3a,
            ),
          );
          final resized = VrAvatarPlan.build(
            original.copyWith(
              heightMeters: 2.2,
              headScale: 1.25,
              featureScale: 1.4,
            ),
          );
          final topology = before.parts
              .map((p) => (p.id, p.shape, p.surface, p.nearOnly))
              .toList();
          expect(topology.map((p) => p.$1).toSet().length, topology.length);
          for (final after in [recolored, resized]) {
            expect(
              after.parts
                  .map((p) => (p.id, p.shape, p.surface, p.nearOnly))
                  .toList(),
              topology,
            );
          }
          for (var i = 0; i < before.parts.length; i++) {
            expect(
              recolored.parts[i].transform.storage,
              before.parts[i].transform.storage,
            );
          }
        }
      }
    },
  );

  test(
    'far LOD keeps species silhouettes and face while dropping small details',
    () {
      final identityPieces = {
        VrAvatarSpecies.human: ['head', 'ear_-1.0', 'hair_cap'],
        VrAvatarSpecies.robot: ['head', 'antenna_light', 'visor'],
        VrAvatarSpecies.orb: ['core', 'orbit_fin_-1.0', 'hover_stem'],
        VrAvatarSpecies.fox: ['ear_-1.0', 'tail', 'tail_tip', 'muzzle_-1.0'],
        VrAvatarSpecies.axolotl: ['gill_-1.0_0', 'gill_1.0_2', 'tail_fin'],
        VrAvatarSpecies.sprout: [
          'crown_leaf_center',
          'crown_leaf_-1.0',
          'left_arm_leaf',
        ],
      };
      for (final entry in identityPieces.entries) {
        final plan = VrAvatarPlan.build(
          VrAvatarAppearance(
            species: entry.key,
            pattern: VrAvatarPattern.stripes,
          ),
        );
        final far = plan.partsFor(VrAvatarDetail.far).toList();
        expect(far.map((p) => p.id), containsAll(entry.value));
        expect(far.map((p) => p.id), containsAll(['eye_-1.0', 'eye_1.0']));
        expect(far.any((p) => p.id.startsWith('stripe_')), isFalse);
        expect(
          plan.triangleCount(VrAvatarDetail.far),
          lessThan(plan.triangleCount(VrAvatarDetail.near) / 3),
        );
        // Placement contract: face is in +Z, so the host must not apply the
        // glTF importer's coordinate flip a second time.
        final eyes = far.where((p) => p.id.startsWith('eye_'));
        expect(eyes.every((p) => p.transform.getTranslation().z > 0), isTrue);
      }
    },
  );

  test(
    'ground contact shadows, conformal patterns and localized motion pivots are authored',
    () {
      for (final species in VrAvatarSpecies.values) {
        for (final pattern in [
          VrAvatarPattern.spots,
          VrAvatarPattern.stripes,
        ]) {
          final plan = VrAvatarPlan.build(
            VrAvatarAppearance(species: species, pattern: pattern),
          );
          final shadow = plan.parts.singleWhere(
            (p) => p.id == 'ground_shadow',
          );
          expect(shadow.surface, VrAvatarSurface.shadow);
          expect(shadow.motion, VrAvatarMotion.ground);
          expect(shadow.nearOnly, isFalse);
          expect(shadow.transform.getTranslation().y, lessThan(0.02));

          // Secondary shade surface enriches joint/silhouette transitions.
          expect(
            plan.parts.any((p) => p.surface == VrAvatarSurface.shade),
            isTrue,
          );

          // Every part has a finite motion pivot within the avatar envelope.
          for (final part in plan.parts) {
            expect(part.pivot.x.isFinite, isTrue);
            expect(part.pivot.y.isFinite, isTrue);
            expect(part.pivot.z.isFinite, isTrue);
            expect(
              part.pivot.y,
              inInclusiveRange(-1e-4, plan.bounds.max.y + 1e-4),
            );
          }

          // Pattern patches are ultra-thin conformal markings oriented forward.
          final markings = plan.parts.where(
            (p) => p.id.startsWith('spot_') || p.id.startsWith('stripe_'),
          );
          expect(markings, isNotEmpty);
          for (final mark in markings) {
            expect(mark.nearOnly, isTrue);
            final normal =
                mark.transform.transformed3(vm.Vector3(0, 0, .5)) -
                mark.transform.getTranslation();
            expect(normal.z, greaterThan(0));
            expect(normal.length, lessThan(0.015));
          }
        }
      }
    },
  );
}

