import 'package:flutter_scene/scene.dart';

/// One retained geometry/material pair with a set of instance transforms.
/// The same batch serves both eyes. Its owner attaches [node] to the scene and
/// updates [mesh] when instance residency or poses change.
final class VrSceneMeshBatch {
  VrSceneMeshBatch({
    required Geometry geometry,
    required Material material,
    String name = '',
    ShadowCastingMode shadowCastingMode = ShadowCastingMode.on,
    bool raycastable = true,
    bool visible = true,
  }) : mesh = InstancedMesh(
         geometry: geometry,
         material: material,
         cullInstances: true,
       ) {
    node = Node(name: name)
      ..raycastable = raycastable
      ..visible = visible
      ..shadowCastingMode = shadowCastingMode
      ..addComponent(InstancedMeshComponent(mesh));
  }

  final InstancedMesh mesh;
  late final Node node;
}
