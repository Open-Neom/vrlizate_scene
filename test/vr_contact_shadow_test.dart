import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;
import 'package:vrlizate_scene/src/vr_contact_shadow.dart';

void main() {
  test(
    'default footprint has a flat opaque-to-transparent top-facing mesh',
    () {
      final mesh = const VrContactShadowSpec(
        halfWidth: 1.12,
        halfLength: 2.3,
        surfaceHeight: .025,
        centerZ: -.2,
      ).buildMeshData();
      expect(mesh.vertexCount, 33);
      expect(mesh.indices, hasLength(48 * 3));
      expect(mesh.positions, hasLength(33 * 3));
      expect(mesh.normals, hasLength(33 * 3));
      expect(mesh.colors, hasLength(33 * 4));
      expect(mesh.texCoords, isNull);
      expect(mesh.colors![3], closeTo(.52, 1e-7));

      vm.Vector3 vertex(int i) => vm.Vector3.array(mesh.positions, i * 3);
      for (var i = 0; i < mesh.vertexCount; i++) {
        final p = vertex(i);
        expect(p.y, closeTo(.025, 1e-8));
        expect(p.x.abs(), lessThanOrEqualTo(1.120001));
        expect(p.z, inInclusiveRange(-2.500001, 2.100001));
        expect(mesh.normals!.sublist(i * 3, i * 3 + 3), [0, 1, 0]);
        expect(mesh.colors!.sublist(i * 4, i * 4 + 3), [0, 0, 0]);
        if (i > 0) {
          expect(mesh.colors![i * 4 + 3], closeTo(i <= 16 ? .38 : 0, 1e-7));
        }
      }
      final indices = mesh.indices!;
      for (var i = 0; i < indices.length; i += 3) {
        final a = vertex(indices[i]);
        final b = vertex(indices[i + 1]);
        final c = vertex(indices[i + 2]);
        expect((b - a).cross(c - a).y, greaterThan(0));
      }
    },
  );

  test(
    'independent dimensions, center and opacity support other footprints',
    () {
      final mesh = const VrContactShadowSpec(
        halfWidth: 4,
        halfLength: 2,
        surfaceHeight: -.5,
        centerX: 2,
        centerZ: -3,
        sides: 8,
        cornerExponent: 1,
        innerScale: .5,
        centerOpacity: .25,
        innerOpacity: .1,
      ).buildMeshData();
      expect(mesh.vertexCount, 17);
      expect(mesh.indices, hasLength(24 * 3));
      expect(mesh.positions.sublist(0, 3), [2, -.5, -3]);
      // First inner and outer vertices lie on the positive X axis.
      expect(mesh.positions.sublist(3, 6), [4, -.5, -3]);
      expect(mesh.positions.sublist(9 * 3, 10 * 3), [6, -.5, -3]);
      // The quarter-turn reaches the independently configured Z radius.
      expect(mesh.positions[11 * 3], closeTo(2, 1e-6));
      expect(mesh.positions[11 * 3 + 2], closeTo(-1, 1e-6));
      expect(mesh.colors![3], .25);
      expect(mesh.colors![7], closeTo(.1, 1e-7));
      expect(mesh.colors![9 * 4 + 3], 0);
    },
  );

  test('invalid geometry or alpha is rejected before mesh construction', () {
    final invalid = [
      const VrContactShadowSpec(halfWidth: 0, halfLength: 1),
      const VrContactShadowSpec(halfWidth: 1, halfLength: -1),
      const VrContactShadowSpec(
        halfWidth: 1,
        halfLength: 1,
        surfaceHeight: double.nan,
      ),
      const VrContactShadowSpec(
        halfWidth: 1,
        halfLength: 1,
        centerX: double.infinity,
      ),
      const VrContactShadowSpec(halfWidth: 1, halfLength: 1, sides: 2),
      const VrContactShadowSpec(halfWidth: 1, halfLength: 1, cornerExponent: 0),
      const VrContactShadowSpec(halfWidth: 1, halfLength: 1, innerScale: 0),
      const VrContactShadowSpec(halfWidth: 1, halfLength: 1, innerScale: 1),
      const VrContactShadowSpec(
        halfWidth: 1,
        halfLength: 1,
        centerOpacity: double.nan,
      ),
      const VrContactShadowSpec(halfWidth: 1, halfLength: 1, innerOpacity: 1.1),
    ];
    for (final spec in invalid) {
      expect(spec.buildMeshData, throwsArgumentError);
    }
  });

  test('material retains translucent decal behavior and selectable depth', () {
    const spec = VrContactShadowSpec(halfWidth: 1, halfLength: 2);
    final original = UnlitMaterial()
      ..alphaMode = AlphaMode.blend
      ..depthLayer = 3;
    final material = spec.createMaterial();
    expect(material.alphaMode, original.alphaMode);
    expect(material.depthLayer, original.depthLayer);
    expect(material.baseColorFactor, original.baseColorFactor);
    expect(material.doubleSided, original.doubleSided);
    expect(spec.createMaterial(depthLayer: 7).depthLayer, 7);
  });
}
