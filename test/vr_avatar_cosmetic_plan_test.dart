import 'package:flutter_test/flutter_test.dart';
import 'package:vrlizate_avatar/vrlizate_avatar.dart';
import 'package:vrlizate_scene/src/avatar/vr_avatar_geometry.dart';
import 'package:vrlizate_scene/src/avatar/vr_avatar_plan.dart';

void main() {
  test(
    'all accessories retain body topology and remain visible at both LODs',
    () {
      for (final species in VrAvatarSpecies.values) {
        final original = VrAvatarAppearance(
          species: species,
          pattern: VrAvatarPattern.spots,
        );
        final base = VrAvatarPlan.build(original);
        for (final item in VrAvatarCosmeticCatalog.all) {
          final plan = VrAvatarPlan.build(
            original.copyWith(cosmeticId: item.id),
          );
          final accessories = plan.parts
              .where((p) => p.id.startsWith('cosmetic_'))
              .toList();
          expect(accessories.length, inInclusiveRange(3, 4));
          expect(
            accessories.every((p) => p.id.startsWith('cosmetic_${item.id}_')),
            isTrue,
          );
          expect(
            plan.parts
                .map((p) => p.id)
                .toSet()
                .containsAll(base.parts.map((p) => p.id)),
            isTrue,
          );
          for (final detail in VrAvatarDetail.values) {
            expect(
              plan
                  .partsFor(detail)
                  .where((p) => p.id.startsWith('cosmetic_'))
                  .length,
              accessories.length,
            );
            expect(
              plan.triangleCount(detail) - base.triangleCount(detail),
              lessThanOrEqualTo(detail == VrAvatarDetail.near ? 896 : 192),
            );
            expect(
              plan.batchCount(detail) - base.batchCount(detail),
              lessThanOrEqualTo(3),
            );
          }
        }
      }
    },
  );

  test(
    'accessories fit real proportion extremes and use finite retained transforms',
    () {
      for (final species in VrAvatarSpecies.values) {
        for (final cosmetic in VrAvatarCosmeticCatalog.all) {
          for (final height in [1.0, 2.2]) {
            for (final head in [.8, 1.25]) {
              for (final feature in [.6, 1.4]) {
                final plan = VrAvatarPlan.build(
                  VrAvatarAppearance(
                    species: species,
                    cosmeticId: cosmetic.id,
                    heightMeters: height,
                    headScale: head,
                    featureScale: feature,
                    pattern: VrAvatarPattern.stripes,
                  ),
                );
                expect(plan.bounds.min.y, closeTo(0, 1e-6));
                expect(plan.bounds.max.y, closeTo(height, 1e-6));
                expect(plan.horizontalRadius, lessThanOrEqualTo(1.400001));
                for (final part in plan.parts) {
                  expect(
                    part.transform.storage.every((n) => n.isFinite),
                    isTrue,
                  );
                  expect(part.transform.determinant(), greaterThan(0));
                  expect(part.pivot.storage.every((n) => n.isFinite), isTrue);
                }
              }
            }
          }
        }
      }
    },
  );
}
