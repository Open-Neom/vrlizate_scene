import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:vrlizate_avatar/vrlizate_avatar.dart';
import 'package:vrlizate_scene/src/avatar/vr_avatar_geometry.dart';
import 'package:vrlizate_scene/src/avatar/vr_avatar_plan.dart';

void main() {
  test(
    'equipped accessories preserve the existing avatar triangle budgets',
    () {
      var near = 0, far = 0, batches = 0;
      final deltas = <String, List<int>>{};
      for (final species in VrAvatarSpecies.values) {
        for (final pattern in VrAvatarPattern.values) {
          final appearance = VrAvatarAppearance(
            species: species,
            pattern: pattern,
          );
          final base = VrAvatarPlan.build(appearance);
          for (final item in VrAvatarCosmeticCatalog.all) {
            final plan = VrAvatarPlan.build(
              appearance.copyWith(cosmeticId: item.id),
            );
            near = math.max(near, plan.triangleCount(VrAvatarDetail.near));
            far = math.max(far, plan.triangleCount(VrAvatarDetail.far));
            batches = math.max(batches, plan.batchCount(VrAvatarDetail.near));
            deltas[item.id] = [
              plan.parts.length - base.parts.length,
              plan.triangleCount(VrAvatarDetail.near) -
                  base.triangleCount(VrAvatarDetail.near),
              plan.triangleCount(VrAvatarDetail.far) -
                  base.triangleCount(VrAvatarDetail.far),
            ];
          }
        }
      }
      expect(near, lessThanOrEqualTo(12000));
      expect(far, lessThanOrEqualTo(2500));
      expect(batches, lessThanOrEqualTo(15));
      // Reproducible geometry accounting, not measured GPU draws or frame rate.
      print(
        jsonEncode({
          'avatarMaxNearTriangles': near,
          'avatarMaxFarTriangles': far,
          'maxNearBatches': batches,
          'accessoryExtraInstancesNearFarTriangles': deltas,
        }),
      );
    },
  );
}
