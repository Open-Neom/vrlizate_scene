import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter_scene/scene.dart' as fs;
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;
import 'package:vrlizate/vrlizate.dart' as core;
import 'package:vrlizate_scene/vrlizate_scene.dart';

class RecordingResources extends VrRetainedResourceFactory {
  @override
  fs.Scene? createScene() => null;
  int geometries = 0;
  int materials = 0;
  int materialUpdates = 0;
  int ambientUpdates = 0;
  final List<core.Geometry> geometryInputs = [];
  final List<VrRetainedSurface> surfaces = [];
  final List<Completer<fs.Mesh?>> uploads = [];
  vm.Vector3 ambient = vm.Vector3.zero();
  bool deferUploads = false;
  bool failUploads = false;

  @override
  fs.Geometry? createGeometry(
    core.Geometry geometry, {
    bool wireframe = false,
  }) {
    geometries++;
    geometryInputs.add(geometry);
    return null;
  }

  @override
  fs.Material? createMaterial({required bool unlit}) {
    materials++;
    return null;
  }

  @override
  void updateMaterial(fs.Material? target, core.VRMaterial source) {
    materialUpdates++;
  }

  @override
  Future<fs.Mesh?> createSurface(VrRetainedSurface surface) async {
    surfaces.add(surface);
    if (failUploads) throw StateError('upload failed');
    if (deferUploads) {
      final completer = Completer<fs.Mesh?>();
      uploads.add(completer);
      return completer.future;
    }
    return null;
  }

  @override
  void setAmbient(fs.Scene? scene, vm.Vector3 radiance) {
    ambientUpdates++;
    ambient.setFrom(radiance);
  }
}

class UnknownRenderable extends core.Node {
  @override
  bool get isRenderable => true;
}

class UnknownMesh extends core.MeshNode {
  UnknownMesh() : super(geometry: core.CubeGeometry());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'GPU upload data preserves vertices, normals, UVs and triangle winding',
    () {
      final source = core.Geometry(
        vertices: [
          vm.Vector3(-2, 0, -3),
          vm.Vector3(1, 0, -3),
          vm.Vector3(0, 2, -3),
        ],
        normals: List.generate(3, (_) => vm.Vector3(0, 0, 1)),
        uvs: [vm.Vector2(0, 1), vm.Vector2(1, 1), vm.Vector2(0.5, 0)],
        indices: [0, 1, 2],
      );
      final data = VrRetainedGpuResources.buildMeshData(source);
      expect(data.positions, [-2, 0, -3, 1, 0, -3, 0, 2, -3]);
      expect(data.normals, [0, 0, 1, 0, 0, 1, 0, 0, 1]);
      expect(data.texCoords, [0, 1, 1, 1, 0.5, 0]);
      expect(data.indices, [0, 1, 2]);
      source.vertices.first.x = 100;
      source.indices[0] = 2;
      expect(data.positions.first, -2);
      expect(data.indices!.first, 0);
    },
  );

  test('malformed geometry is rejected before reaching the GPU', () {
    final geometry = core.Geometry(
      vertices: [vm.Vector3.zero()],
      normals: [],
      indices: [],
    );
    expect(
      () => VrRetainedGpuResources.buildMeshData(geometry),
      throwsArgumentError,
    );
  });

  test(
    'retains identities, meshes and materials across stable and moving frames',
    () {
      final source = core.Scene();
      final geometry = core.CubeGeometry();
      final material = core.VRMaterial();
      final a = core.LitMeshNode(
        name: 'same',
        geometry: geometry,
        material: material,
      );
      final b = core.LitMeshNode(
        name: 'same',
        geometry: geometry,
        material: material,
      );
      source
        ..add(a)
        ..add(b);
      final resources = RecordingResources();
      final adapter = VrRetainedSceneAdapter(
        source: source,
        resources: resources,
      );
      adapter.sync();
      final original = adapter.sceneNodeFor(a)!;
      expect(resources.geometries, 1);
      expect(resources.materials, 1);
      expect(resources.materialUpdates, 1);
      for (var i = 0; i < 120; i++) {
        a.transform.position.x = i / 100;
        adapter.sync(elapsedSeconds: i / 60);
      }
      expect(adapter.sceneNodeFor(a), same(original));
      expect(original.localTransform.getTranslation().x, closeTo(1.19, 1e-6));
      expect(adapter.sourceNodeFor(original), same(a));
      expect(adapter.sourceNodeFor(adapter.sceneNodeFor(b)!), same(b));
      expect(resources.geometries, 1);
      expect(resources.materials, 1);
      expect(resources.materialUpdates, 1);
      material.opacity = 0.5;
      adapter.sync();
      expect(resources.materialUpdates, 2);
      expect(resources.materials, 1);
      adapter.dispose();
    },
  );

  test(
    'reparent, visibility, detach and cache eviction follow the source tree',
    () {
      final source = core.Scene();
      final left = core.Node(name: 'left');
      final right = core.Node(name: 'right');
      final child = core.MeshNode(geometry: core.CubeGeometry());
      left.addChild(child);
      source
        ..add(left)
        ..add(right);
      final adapter = VrRetainedSceneAdapter(
        source: source,
        resources: VrRetainedResourceFactory.headless(),
      );
      adapter.sync();
      final retained = adapter.sceneNodeFor(child)!;
      right.addChild(child);
      right.visible = false;
      adapter.sync();
      expect(retained.parent, same(adapter.sceneNodeFor(right)));
      expect(adapter.sceneNodeFor(right)!.visible, isFalse);
      expect(adapter.nodeCount, 4);
      right.removeChild(child);
      adapter.sync();
      expect(adapter.sceneNodeFor(child), isNull);
      expect(adapter.sourceNodeFor(retained), isNull);
      expect(retained.parent, isNull);
      expect(adapter.geometryCount, 0);
      expect(adapter.materialCount, 0);
      adapter.dispose();
    },
  );

  test(
    'wireframe and explicit geometry invalidation upload only when needed',
    () {
      final source = core.Scene();
      final mesh = core.MeshNode(geometry: core.CubeGeometry());
      source.add(mesh);
      final resources = RecordingResources();
      final adapter = VrRetainedSceneAdapter(
        source: source,
        resources: resources,
      );
      adapter.sync();
      mesh.material.wireframe = true;
      adapter.sync();
      adapter.sync();
      expect(resources.geometries, 2);
      mesh.material.wireframe = false;
      adapter.sync();
      expect(resources.geometries, 2);
      adapter.invalidateGeometry(mesh.geometry);
      adapter.sync();
      expect(resources.geometries, 3);
      adapter.dispose();
    },
  );

  test(
    'grid, radar and hologram are retained geometry with declared differences',
    () {
      final source = core.Scene();
      final radar = core.WifiRadarNode(name: 'radar');
      final hologram = core.HologramMeshNode(
        name: 'holo',
        geometry: core.SphereGeometry(segments: 6),
      );
      source
        ..add(core.GridFloor(size: 4, divisions: 4))
        ..add(radar)
        ..add(hologram);
      final resources = RecordingResources();
      final adapter = VrRetainedSceneAdapter(
        source: source,
        resources: resources,
      );
      adapter.sync();
      final uploads = resources.geometries;
      expect(uploads, greaterThanOrEqualTo(4));
      expect(
        resources.geometryInputs.every((g) => g.indices.isNotEmpty),
        isTrue,
      );
      final ring = adapter.sceneNodeFor(radar)!.children.first;
      final matrix = ring.localTransform.clone();
      adapter.sync(elapsedSeconds: 0.5);
      expect(ring.localTransform, isNot(matrix));
      expect(resources.geometries, uploads);
      expect(adapter.sourceNodeFor(ring), same(radar));
      expect(adapter.diagnostics.single, contains('scanlines'));
      radar.showGrid = false;
      adapter.sync();
      expect(adapter.sceneNodeFor(radar)!.visible, isFalse);
      adapter.dispose();
    },
  );

  test(
    'ambient changes, ancestor visibility and punctual lights are retained',
    () {
      final source = core.Scene();
      final parent = core.Node();
      final ambient = core.Light.ambient(
        color: const ui.Color(0xFFFFFFFF),
        intensity: 0.2,
      );
      final point = core.Light.point(intensity: 2);
      final directional = core.Light.directional();
      final spot = core.Light(type: core.LightType.spot);
      parent.addChild(ambient);
      source
        ..add(parent)
        ..add(point)
        ..add(directional)
        ..add(spot);
      final resources = RecordingResources();
      final adapter = VrRetainedSceneAdapter(
        source: source,
        resources: resources,
      );
      adapter.sync();
      expect(resources.ambient.x, closeTo(0.2, 1e-6));
      adapter.sync();
      expect(resources.ambientUpdates, 1);
      ambient.intensity = 0.5;
      point.intensity = 3;
      directional.direction = vm.Vector3(1, -1, 0)..normalize();
      adapter.sync();
      expect(resources.ambient.x, closeTo(0.5, 1e-6));
      ambient.intensity = 0;
      adapter.sync();
      expect(resources.ambient.length2, 0);
      expect(
        adapter
            .sceneNodeFor(point)!
            .getComponent<fs.PointLightComponent>()!
            .light
            .intensity,
        3,
      );
      expect(
        adapter
            .sceneNodeFor(directional)!
            .getComponent<fs.DirectionalLightComponent>(),
        isNotNull,
      );
      expect(
        adapter.sceneNodeFor(spot)!.getComponent<fs.SpotLightComponent>(),
        isNotNull,
      );
      parent.visible = false;
      adapter.sync();
      expect(resources.ambient.x, lessThan(0.5));
      adapter.dispose();
    },
  );

  test(
    'labels and panels upload on content change, not each frame; bounded images',
    () async {
      final source = core.Scene();
      final camera = core.CameraRig();
      final text = core.SpatialText(cameraRig: camera, text: 'Hola');
      final panel = core.SpatialPanel(
        cameraRig: camera,
        panelWidth: 0.8,
        panelHeight: 0.5,
      );
      source
        ..add(text)
        ..add(panel);
      final resources = RecordingResources();
      final adapter = VrRetainedSceneAdapter(
        source: source,
        resources: resources,
      );
      adapter.sync();
      await adapter.pendingTextures;
      expect(resources.surfaces.length, 2);
      for (var i = 0; i < 60; i++) {
        adapter.sync();
      }
      await adapter.pendingTextures;
      expect(resources.surfaces.length, 2);
      text.text = 'Otro';
      adapter.sync();
      await adapter.pendingTextures;
      expect(resources.surfaces.length, 3);
      adapter.invalidateSurface(panel);
      adapter.sync();
      await adapter.pendingTextures;
      expect(resources.surfaces.length, 4);
      expect(
        resources.surfaces.every(
          (s) => s.widthPixels <= 2048 && s.heightPixels <= 2048,
        ),
        isTrue,
      );
      expect(resources.surfaces.first.worldHeight, greaterThan(0));
      final quad = resources.surfaces.first.geometry;
      // world -X is screen right; that vertex must sample the image's right.
      expect(quad.vertices[0].x, lessThan(quad.vertices[1].x));
      expect(quad.uvs[0].x, greaterThan(quad.uvs[1].x));
      expect(quad.vertices[2].y, greaterThan(quad.vertices[1].y));
      expect(quad.uvs[2].y, lessThan(quad.uvs[1].y));
      adapter.dispose();
    },
  );

  test(
    'late surface completion cannot resurrect a removed or disposed node',
    () async {
      final source = core.Scene();
      final text = core.SpatialText(
        cameraRig: core.CameraRig(),
        text: 'pending',
      );
      source.add(text);
      final resources = RecordingResources()..deferUploads = true;
      final adapter = VrRetainedSceneAdapter(
        source: source,
        resources: resources,
      );
      adapter.sync();
      expect(adapter.pendingSurfaceCount, 1);
      source.remove(text);
      adapter.sync();
      adapter.dispose();
      resources.uploads.single.complete(null);
      await adapter.pendingTextures;
      expect(adapter.nodeCount, 0);
      expect(adapter.pendingSurfaceCount, 0);
      expect(() => adapter.sync(), throwsStateError);
    },
  );

  test(
    'surface failures are observable through pendingTextures and sync',
    () async {
      final source = core.Scene()
        ..add(core.SpatialText(cameraRig: core.CameraRig(), text: 'failure'));
      final resources = RecordingResources()..failUploads = true;
      final adapter = VrRetainedSceneAdapter(
        source: source,
        resources: resources,
      );
      adapter.sync();
      await expectLater(adapter.pendingTextures, throwsStateError);
      expect(() => adapter.sync(), throwsStateError);
      adapter.dispose();
    },
  );

  test(
    'unsupported renderables, custom meshes and material maps fail explicitly',
    () {
      for (final node in <core.Node>[
        UnknownRenderable(),
        UnknownMesh(),
        core.MeshNode(
          geometry: core.CubeGeometry(),
          material: core.VRMaterial(blendMode: ui.BlendMode.plus),
        ),
        core.MeshNode(
          geometry: core.CubeGeometry(),
          material: core.VRMaterial(map: core.VRTexture()),
        ),
      ]) {
        final source = core.Scene()..add(node);
        final adapter = VrRetainedSceneAdapter(
          source: source,
          resources: VrRetainedResourceFactory.headless(),
        );
        expect(() => adapter.sync(), throwsUnsupportedError);
        adapter.dispose();
      }
    },
  );

  test('composite pointables resolve by identity, not repeated node names', () {
    final source = core.Scene();
    final arrow = core.SpatialNavigationArrow();
    source.add(arrow);
    final adapter = VrRetainedSceneAdapter(
      source: source,
      resources: VrRetainedResourceFactory.headless(),
    );
    adapter.sync();
    final shaft = adapter.sceneNodeFor(arrow.children.first)!;
    expect(adapter.pointableSourceNodeFor(shaft), same(arrow));
    expect(adapter.sourceNodeFor(shaft), same(arrow.children.first));
    adapter.dispose();
  });

  test('headless is explicit and never exposes a pretend GPU renderer', () {
    final adapter = VrRetainedSceneAdapter(
      source: core.Scene(),
      resources: VrRetainedResourceFactory.headless(),
    );
    expect(adapter.isHeadless, isTrue);
    expect(() => adapter.scene, throwsStateError);
    adapter.dispose();
  });
}
