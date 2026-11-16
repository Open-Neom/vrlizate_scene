import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';
import 'package:vrlizate_scene/vrlizate_scene.dart';

void main() {
  test('a scene batch retains resources and honors its node policy', () {
    final geometry = _Geometry();
    final material = PhysicallyBasedMaterial();
    final batch = VrSceneMeshBatch(
      name: 'portable_part',
      geometry: geometry,
      material: material,
      shadowCastingMode: ShadowCastingMode.off,
      raycastable: false,
      visible: false,
    );

    expect(batch.node.name, 'portable_part');
    expect(batch.node.raycastable, isFalse);
    expect(batch.node.visible, isFalse);
    expect(batch.node.shadowCastingMode, ShadowCastingMode.off);
    expect(
      batch.node.getComponent<InstancedMeshComponent>()!.instancedMesh,
      same(batch.mesh),
    );
    expect(batch.mesh.cullInstances, isTrue);
    expect(batch.mesh.geometry, same(geometry));
    expect(batch.mesh.material, same(material));

    batch.mesh.addInstance(Matrix4.identity());
    batch.mesh.addInstance(Matrix4.translationValues(1, 0, 0));
    expect(batch.mesh.instanceCount, 2);
    batch.mesh.clearInstances();
    expect(batch.mesh.instanceCount, 0);
  });
}

class _Geometry extends Fake implements Geometry {}
