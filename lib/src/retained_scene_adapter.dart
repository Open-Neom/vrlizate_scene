import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_scene/scene.dart' as fs;
import 'package:vector_math/vector_math.dart' as vm;
import 'package:vrlizate/vrlizate.dart' as core;

/// GPU resource boundary. Override in tests, or use [headless], to exercise
/// scene synchronization without pretending a Flutter GPU context exists.
abstract class VrRetainedResourceFactory {
  const VrRetainedResourceFactory();

  factory VrRetainedResourceFactory.headless() = _HeadlessResources;

  fs.Scene? createScene() => fs.Scene();
  fs.Geometry? createGeometry(core.Geometry geometry, {bool wireframe = false});
  fs.Material? createMaterial({required bool unlit});
  void updateMaterial(fs.Material? target, core.VRMaterial source);
  Future<fs.Mesh?> createSurface(VrRetainedSurface surface);
  void setAmbient(fs.Scene? scene, vm.Vector3 radiance);
}

/// Immutable, bounded UI raster request. Only the panel/label is rasterized;
/// world geometry is always uploaded as actual three-dimensional geometry.
class VrRetainedSurface {
  const VrRetainedSurface({
    required this.widthPixels,
    required this.heightPixels,
    required this.worldWidth,
    required this.worldHeight,
    required this.paint,
  });

  final int widthPixels;
  final int heightPixels;
  final double worldWidth;
  final double worldHeight;
  final void Function(ui.Canvas, ui.Size) paint;

  /// Actual vertical world quad, with UV orientation matching the stereo
  /// renderer's screen basis. This pure geometry can be tested without a GPU.
  core.Geometry get geometry => _quad(worldWidth, worldHeight);
}

/// Default real Flutter GPU implementation. Creating geometry/textures requires
/// a supported runtime; failures propagate instead of silently omitting objects.
class VrRetainedGpuResources extends VrRetainedResourceFactory {
  const VrRetainedGpuResources();

  /// Pure conversion shared by tests and the GPU upload. Copies arrays once;
  /// no projection, rasterization, axis reflection or primitive substitution.
  static fs.MeshData buildMeshData(core.Geometry geometry) {
    if (geometry.normals.length != geometry.vertices.length ||
        geometry.uvs.length != geometry.vertices.length ||
        geometry.indices.length % 3 != 0 ||
        geometry.indices.any((i) => i < 0 || i >= geometry.vertices.length) ||
        geometry.vertices.any(
          (v) => !v.x.isFinite || !v.y.isFinite || !v.z.isFinite,
        ) ||
        geometry.normals.any(
          (v) => !v.x.isFinite || !v.y.isFinite || !v.z.isFinite,
        ) ||
        geometry.uvs.any((v) => !v.x.isFinite || !v.y.isFinite)) {
      throw ArgumentError(
        'Retained geometry requires finite position/normal/UV arrays of matching vertex counts and valid triangle indices.',
      );
    }
    final positions = Float32List(geometry.vertices.length * 3);
    final normals = Float32List(geometry.normals.length * 3);
    final uv = Float32List(geometry.uvs.length * 2);
    for (var i = 0; i < geometry.vertices.length; i++) {
      geometry.vertices[i].copyIntoArray(positions, i * 3);
    }
    for (var i = 0; i < geometry.normals.length; i++) {
      geometry.normals[i].copyIntoArray(normals, i * 3);
    }
    for (var i = 0; i < geometry.uvs.length; i++) {
      geometry.uvs[i].copyIntoArray(uv, i * 2);
    }
    return fs.MeshData(
      positions: positions,
      vertexCount: geometry.vertexCount,
      normals: normals,
      texCoords: uv,
      indices: List<int>.of(geometry.indices),
    );
  }

  @override
  fs.Geometry createGeometry(core.Geometry geometry, {bool wireframe = false}) {
    final data = buildMeshData(geometry);
    if (wireframe) {
      final points = <double>[];
      final edges = <(int, int)>{};
      for (var i = 0; i < geometry.indices.length; i += 3) {
        for (var j = 0; j < 3; j++) {
          final a = geometry.indices[i + j];
          final b = geometry.indices[i + (j + 1) % 3];
          final edge = a < b ? (a, b) : (b, a);
          if (!edges.add(edge)) continue;
          points.addAll(geometry.vertices[a].storage);
          points.addAll(geometry.vertices[b].storage);
        }
      }
      return fs.LineSegmentsGeometry(
        fs.LineSegmentData(positions: Float32List.fromList(points)),
        width: 0.004,
      );
    }
    return fs.MeshGeometry.fromMeshData(data);
  }

  @override
  fs.Material createMaterial({required bool unlit}) => unlit
      ? (fs.UnlitMaterial()..vertexColorWeight = 0)
      : (fs.PhysicallyBasedMaterial()..vertexColorWeight = 0);

  @override
  void updateMaterial(fs.Material? target, core.VRMaterial source) {
    final color = _linearColor(source.color, alpha: source.opacity);
    final alpha = source.opacity < 1 ? fs.AlphaMode.blend : fs.AlphaMode.opaque;
    if (target is fs.PhysicallyBasedMaterial) {
      final emission = _linearColor(source.emissive, alpha: 0);
      if (source is core.PBRMaterial) emission.scale(source.emissionIntensity);
      target
        ..baseColorFactor = color
        ..metallicFactor = source.metallic
        ..roughnessFactor = source.roughness
        ..emissiveFactor = emission
        ..alphaMode = alpha
        ..doubleSided = source.doubleSided;
    } else if (target is fs.UnlitMaterial) {
      target
        ..baseColorFactor = color
        ..alphaMode = alpha
        ..doubleSided = source.doubleSided;
    }
  }

  @override
  Future<fs.Mesh> createSurface(VrRetainedSurface surface) async {
    final recorder = ui.PictureRecorder();
    surface.paint(
      ui.Canvas(recorder),
      ui.Size(surface.widthPixels.toDouble(), surface.heightPixels.toDouble()),
    );
    final picture = recorder.endRecording();
    ui.Image? image;
    try {
      image = await picture.toImage(surface.widthPixels, surface.heightPixels);
      final texture = await fs.Texture2D.fromImage(image);
      final material = fs.UnlitMaterial(colorTexture: texture)
        ..alphaMode = fs.AlphaMode.blend
        ..doubleSided = true
        ..vertexColorWeight = 0;
      return fs.Mesh(createGeometry(surface.geometry), material);
    } finally {
      image?.dispose();
      picture.dispose();
    }
  }

  @override
  void setAmbient(fs.Scene? scene, vm.Vector3 radiance) {
    if (scene == null)
      throw StateError('GPU ambient lighting requires a Scene.');
    scene.environment = fs.EnvironmentMap.constantDiffuse(radiance);
  }
}

class _HeadlessResources extends VrRetainedResourceFactory {
  const _HeadlessResources();
  @override
  fs.Scene? createScene() => null;
  @override
  fs.Geometry? createGeometry(
    core.Geometry geometry, {
    bool wireframe = false,
  }) => null;
  @override
  fs.Material? createMaterial({required bool unlit}) => null;
  @override
  void updateMaterial(fs.Material? target, core.VRMaterial source) {}
  @override
  Future<fs.Mesh?> createSurface(VrRetainedSurface surface) async => null;
  @override
  void setAmbient(fs.Scene? scene, vm.Vector3 radiance) {}
}

/// Retained renderer bridge for legacy simulations. This owns no clock, input
/// listener, head tracker or physics. Call [sync] after the host's single
/// simulation step, then render [scene] with StereoSceneView.
///
/// Geometry and material identities are retained. Removed resources leave the
/// caches; unchanged meshes are neither rebuilt nor uploaded each frame.
/// Geometry arrays are treated as immutable; call [invalidateGeometry] after
/// editing them. Call [invalidateSurface] when a panel callback's captured
/// content changes. Unknown renderable node kinds and unsupported material
/// features fail explicitly.
///
/// Coordinates are preserved, not globally reflected. UI billboards become
/// actual world-sized, depth-tested quads. The host must use the same world
/// camera/ray basis for rendering and gameplay.
class VrRetainedSceneAdapter {
  VrRetainedSceneAdapter({
    required this.source,
    fs.Scene? scene,
    VrRetainedResourceFactory? resources,
  }) : _scene =
           scene ?? (resources ?? const VrRetainedGpuResources()).createScene(),
       resources = resources ?? const VrRetainedGpuResources() {
    _scene?.add(_root);
  }

  final core.Scene source;
  final fs.Scene? _scene;

  /// Available only with real GPU resources; headless tests exercise the node
  /// graph without substituting a fake renderer or calling the GPU backend.
  fs.Scene get scene =>
      _scene ??
      (throw StateError(
        'Headless retained adapter has no renderable GPU scene.',
      ));
  bool get isHeadless => _scene == null;
  final VrRetainedResourceFactory resources;
  final fs.Node _root = fs.Node(name: 'retained_scene');
  final Map<core.Node, _NodeEntry> _nodes = HashMap.identity();
  final Map<fs.Node, core.Node> _sources = HashMap.identity();
  final Map<core.Geometry, _GeometryEntry> _geometry = HashMap.identity();
  final Map<core.VRMaterial, _MaterialEntry> _lit = HashMap.identity();
  final Map<core.VRMaterial, _MaterialEntry> _unlit = HashMap.identity();
  final Set<Future<void>> _pending = {};
  final List<String> _diagnostics = [];
  final vm.Vector3 _ambient = vm.Vector3.zero();
  final vm.Vector3 _lastAmbient = vm.Vector3.all(-1);
  Object? _surfaceError;
  int _epoch = 0;
  bool _disposed = false;
  bool _hasAmbient = false;

  int get nodeCount => _nodes.length;
  int get geometryCount => _geometry.length;
  int get materialCount => _lit.length + _unlit.length;
  int get pendingSurfaceCount => _pending.length;
  ui.Color get backgroundColor => source.backgroundColor;
  List<String> get diagnostics => List.unmodifiable(_diagnostics);

  /// Waits for current and subsequently queued uploads, rethrowing any failure.
  Future<void> get pendingTextures async {
    while (_pending.isNotEmpty) {
      await Future.wait(List<Future<void>>.of(_pending));
    }
    if (_surfaceError case final error?) throw error;
  }

  fs.Node? sceneNodeFor(core.Node node) => _nodes[node]?.node;

  /// Includes generated surface/shell children. Names need not be unique.
  core.Node? sourceNodeFor(fs.Node node) {
    fs.Node? current = node;
    while (current != null) {
      final source = _sources[current];
      if (source != null) return source;
      current = current.parent;
    }
    return null;
  }

  /// Resolves meshes belonging to a composite legacy Pointable (e.g. arrows).
  core.Node? pointableSourceNodeFor(fs.Node node) {
    var current = sourceNodeFor(node);
    while (current != null) {
      if (current.pointable != null) return current;
      current = current.parent;
    }
    return null;
  }

  void invalidateGeometry(core.Geometry geometry) {
    _ensureAlive();
    _geometry.remove(geometry);
    for (final entry in _nodes.values) {
      if (entry.source is core.MeshNode &&
          identical((entry.source as core.MeshNode).geometry, geometry)) {
        entry.meshGeometry = null;
      }
    }
  }

  void invalidateSurface(core.Node node) {
    _ensureAlive();
    _nodes[node]?.surfaceSignature = null;
  }

  void sync({double elapsedSeconds = 0}) {
    _ensureAlive();
    if (!elapsedSeconds.isFinite || elapsedSeconds < 0) {
      throw ArgumentError.value(elapsedSeconds, 'elapsedSeconds');
    }
    if (_surfaceError case final error?) throw error;
    _epoch++;
    _ambient.setValues(0, 0, 0);
    _hasAmbient = false;
    _visit(source.root, _root, true, elapsedSeconds);
    final removed = _nodes.values.where((e) => e.epoch != _epoch).toList();
    for (final entry in removed) {
      entry.surfaceGeneration++;
      entry.node.parent?.remove(entry.node);
      _sources.remove(entry.node);
      _nodes.remove(entry.source);
    }
    _geometry.removeWhere((_, value) => value.epoch != _epoch);
    _lit.removeWhere((_, value) => value.epoch != _epoch);
    _unlit.removeWhere((_, value) => value.epoch != _epoch);
    if (!_hasAmbient) {
      _ambient.setValues(
        _linear(source.ambientColor.r),
        _linear(source.ambientColor.g),
        _linear(source.ambientColor.b),
      );
    }
    if (_ambient != _lastAmbient) {
      resources.setAmbient(_scene, _ambient);
      _lastAmbient.setFrom(_ambient);
    }
    _scene?.fog
      ?..enabled = source.fogDensity > 0
      ..mode = fs.FogMode.exponential
      ..density = source.fogDensity
      ..color = vm.Vector3(
        _linear(source.fogColor.r),
        _linear(source.fogColor.g),
        _linear(source.fogColor.b),
      );
  }

  void _visit(
    core.Node sourceNode,
    fs.Node parent,
    bool ancestorsVisible,
    double elapsed,
  ) {
    final entry = _nodes.putIfAbsent(sourceNode, () => _create(sourceNode));
    entry.epoch = _epoch;
    if (!identical(entry.node.parent, parent)) {
      entry.node.parent?.remove(entry.node);
      parent.add(entry.node);
    }
    entry.node.name = sourceNode.name;
    entry.node.visible = sourceNode.visible;
    _syncTransform(entry);
    final visible = ancestorsVisible && sourceNode.visible;
    if (sourceNode is core.MeshNode) {
      if (sourceNode is core.HologramMeshNode) {
        _validateMaterial(sourceNode.material, sourceNode);
        final body = entry.parts.first;
        body.material.color = sourceNode.hologramColor;
        body.material.emissive = sourceNode.hologramColor;
        body.material.opacity =
            sourceNode.material.opacity *
            (0.7 + 0.3 * math.sin(elapsed * sourceNode.flickerSpeed));
        _syncPart(body);
        final shell = entry.parts.last;
        shell.material.color = sourceNode.hologramColor;
        shell.material.opacity = body.material.opacity * 0.35;
        _syncPart(shell);
        // The normal mesh is replaced by these retained shell meshes.
        entry.node.mesh = null;
      } else {
        _syncMesh(
          entry,
          sourceNode.geometry,
          sourceNode.material,
          unlit: sourceNode is! core.LitMeshNode,
        );
      }
    } else if (sourceNode is core.Light) {
      _syncLight(entry, sourceNode, visible);
    } else if (sourceNode is core.GridFloor) {
      for (final part in entry.parts) {
        _syncPart(part);
      }
    } else if (sourceNode is core.WifiRadarNode) {
      entry.node.visible = sourceNode.visible && sourceNode.showGrid;
      for (var i = 0; i < entry.parts.length; i++) {
        final part = entry.parts[i];
        final progress = ((elapsed * sourceNode.pulseSpeed) / 10 + i / 3) % 1;
        part.node.localTransform = vm.Matrix4.diagonal3Values(
          math.max(0.001, progress * 4),
          1,
          math.max(0.001, progress * 4),
        );
        part.material.color = sourceNode.radarColor;
        part.material.opacity = (1 - progress) * 0.3;
        _syncPart(part);
      }
    } else if (sourceNode is core.SpatialText ||
        sourceNode is core.SpatialPanel) {
      _syncSurface(entry);
    }
    for (final child in sourceNode.children) {
      _visit(child, entry.node, visible, elapsed);
    }
  }

  _NodeEntry _create(core.Node sourceNode) {
    if (sourceNode is core.MeshNode &&
        sourceNode.runtimeType != core.MeshNode &&
        sourceNode.runtimeType != core.LitMeshNode &&
        sourceNode.runtimeType != core.HologramMeshNode) {
      throw UnsupportedError(
        'Retained scene: custom mesh ${sourceNode.runtimeType} "${sourceNode.name}" needs an explicit GPU converter.',
      );
    }
    if (sourceNode.isRenderable &&
        sourceNode is! core.MeshNode &&
        sourceNode is! core.GridFloor &&
        sourceNode is! core.SpatialText &&
        sourceNode is! core.SpatialPanel &&
        sourceNode is! core.WifiRadarNode) {
      throw UnsupportedError(
        'Retained scene: unsupported renderable ${sourceNode.runtimeType} "${sourceNode.name}". Add an explicit GPU converter.',
      );
    }
    final entry = _NodeEntry(sourceNode);
    _sources[entry.node] = sourceNode;
    if (sourceNode is core.GridFloor) {
      final geometry = _grid(sourceNode.size, sourceNode.divisions);
      entry.parts.add(
        _part(
          entry,
          geometry,
          core.VRMaterial(
            color: sourceNode.color,
            opacity: sourceNode.color.a,
            doubleSided: true,
          ),
        ),
      );
      entry.parts.add(
        _part(
          entry,
          _grid(sourceNode.size, sourceNode.divisions, centerOnly: true),
          core.VRMaterial(
            color: sourceNode.centerLineColor,
            opacity: sourceNode.centerLineColor.a,
            doubleSided: true,
          ),
        ),
      );
    } else if (sourceNode is core.WifiRadarNode) {
      final geometry = _ring();
      for (var i = 0; i < 3; i++) {
        entry.parts.add(
          _part(
            entry,
            geometry,
            core.VRMaterial(
              color: sourceNode.radarColor,
              opacity: 0.3,
              doubleSided: true,
            ),
          ),
        );
      }
    } else if (sourceNode is core.HologramMeshNode) {
      _diagnostics.add(
        '${sourceNode.name}: hologram uses retained emissive body + wire shell/flicker; screen-space scanlines and random Canvas glitch are not reproduced.',
      );
      final body = _part(
        entry,
        sourceNode.geometry,
        core.VRMaterial(
          color: sourceNode.hologramColor,
          emissive: sourceNode.hologramColor,
          opacity: 0.4,
          doubleSided: true,
        ),
      );
      final shell = _part(
        entry,
        sourceNode.geometry,
        core.VRMaterial(
          color: sourceNode.hologramColor,
          opacity: 0.14,
          wireframe: true,
          doubleSided: true,
        ),
      );
      shell.node.localTransform = vm.Matrix4.diagonal3Values(1.04, 1.04, 1.04);
      entry.parts.addAll([body, shell]);
    }
    return entry;
  }

  _Part _part(
    _NodeEntry entry,
    core.Geometry geometry,
    core.VRMaterial material,
  ) {
    final node = fs.Node(name: entry.source.name);
    entry.node.add(node);
    return _Part(node, geometry, material);
  }

  void _syncTransform(_NodeEntry entry) {
    final t = entry.source.transform;
    final billboard =
        entry.source is core.SpatialText || entry.source is core.SpatialPanel;
    if (!billboard &&
        entry.transformInitialized &&
        entry.lastPosition == t.position &&
        entry.lastRotation == t.rotation &&
        entry.lastScale == t.scale)
      return;
    final transform = _transform(entry.source);
    if (!entry.transformInitialized || entry.lastMatrix != transform) {
      entry.node.localTransform = transform;
      entry.lastMatrix.setFrom(transform);
    }
    entry.lastPosition.setFrom(t.position);
    entry.lastRotation.setFrom(t.rotation);
    entry.lastScale.setFrom(t.scale);
    entry.transformInitialized = true;
  }

  void _syncPart(_Part part) {
    final geometry = _geometryFor(part.geometry, part.material.wireframe);
    final material = _materialFor(part.material, true);
    if (!identical(part.gpuGeometry, geometry) ||
        !identical(part.gpuMaterial, material) ||
        !part.initialized) {
      part.node.mesh = geometry != null && material != null
          ? fs.Mesh(geometry, material)
          : null;
      part.gpuGeometry = geometry;
      part.gpuMaterial = material;
      part.initialized = true;
    }
  }

  void _syncMesh(
    _NodeEntry entry,
    core.Geometry geometry,
    core.VRMaterial material, {
    required bool unlit,
  }) {
    _validateMaterial(material, entry.source);
    final gpuGeometry = _geometryFor(geometry, material.wireframe);
    final gpuMaterial = _materialFor(material, unlit || material.wireframe);
    if (!identical(entry.meshGeometry, gpuGeometry) ||
        !identical(entry.meshMaterial, gpuMaterial) ||
        !entry.meshInitialized) {
      entry.node.mesh = gpuGeometry != null && gpuMaterial != null
          ? fs.Mesh(gpuGeometry, gpuMaterial)
          : null;
      entry.meshGeometry = gpuGeometry;
      entry.meshMaterial = gpuMaterial;
      entry.meshInitialized = true;
    }
  }

  fs.Geometry? _geometryFor(core.Geometry source, bool wireframe) {
    final entry = _geometry.putIfAbsent(source, _GeometryEntry.new)
      ..epoch = _epoch;
    if (wireframe) {
      if (!entry.wireCreated) {
        entry.wire = resources.createGeometry(source, wireframe: true);
        entry.wireCreated = true;
      }
      return entry.wire;
    }
    if (!entry.solidCreated) {
      entry.solid = resources.createGeometry(source);
      entry.solidCreated = true;
    }
    return entry.solid;
  }

  fs.Material? _materialFor(core.VRMaterial source, bool unlit) {
    final cache = unlit ? _unlit : _lit;
    final entry = cache.putIfAbsent(
      source,
      () => _MaterialEntry(resources.createMaterial(unlit: unlit)),
    )..epoch = _epoch;
    final signature = Object.hash(
      source.color,
      source.emissive,
      source.opacity,
      source.metallic,
      source.roughness,
      source.doubleSided,
      source is core.PBRMaterial ? source.emissionIntensity : 1.0,
    );
    if (entry.signature != signature) {
      resources.updateMaterial(entry.material, source);
      entry.signature = signature;
    }
    return entry.material;
  }

  void _validateMaterial(core.VRMaterial material, core.Node node) {
    if (!material.opacity.isFinite ||
        material.opacity < 0 ||
        material.opacity > 1) {
      throw ArgumentError(
        'Retained scene ${node.name}: opacity must be finite in [0,1].',
      );
    }
    if (material.blendMode != ui.BlendMode.srcOver ||
        material.map != null ||
        (material is core.PBRMaterial &&
            (material.colorMap != null ||
                material.normalMap != null ||
                material.metallicRoughnessMap != null ||
                material.emissionMap != null ||
                material.aoMap != null ||
                material.envMap != null ||
                material.alphaMap != null))) {
      throw UnsupportedError(
        'Retained scene ${node.name}: custom blend modes / legacy texture maps need an explicit GPU material conversion.',
      );
    }
  }

  void _syncLight(_NodeEntry entry, core.Light light, bool visible) {
    final color = _linearColor(light.color);
    if (light.type == core.LightType.ambient) {
      if (visible) {
        _hasAmbient = true;
        _ambient.add(
          vm.Vector3(color.x, color.y, color.z)..scale(light.intensity),
        );
      }
      return;
    }
    if (light.type == core.LightType.point) {
      final target = entry.point ??= fs.PointLight();
      if (entry.lightComponent == null) {
        entry.lightComponent = fs.PointLightComponent(target);
        entry.node.addComponent(entry.lightComponent!);
      }
      target
        ..color = vm.Vector3(color.x, color.y, color.z)
        ..intensity = light.intensity
        ..range = light.range;
    } else if (light.type == core.LightType.directional) {
      final target = entry.directional ??= fs.DirectionalLight(
        castsShadow: false,
      );
      if (entry.lightComponent == null || entry.direction != light.direction) {
        if (entry.lightComponent != null)
          entry.node.removeComponent(entry.lightComponent!);
        entry.lightComponent = fs.DirectionalLightComponent.aimed(
          target,
          light.direction,
        );
        entry.node.addComponent(entry.lightComponent!);
        entry.direction.setFrom(light.direction);
      }
      target
        ..color = vm.Vector3(color.x, color.y, color.z)
        ..intensity = light.intensity;
    } else {
      final target = entry.spot ??= fs.SpotLight();
      if (entry.lightComponent == null) {
        entry.lightComponent = fs.SpotLightComponent(target);
        entry.node.addComponent(entry.lightComponent!);
      }
      target
        ..color = vm.Vector3(color.x, color.y, color.z)
        ..intensity = light.intensity
        ..range = light.range
        ..direction = light.direction.clone()
        ..innerConeAngle = 0
        ..outerConeAngle = math.acos((1 - light.spotAngle).clamp(-1, 1));
    }
  }

  void _syncSurface(_NodeEntry entry) {
    final sourceNode = entry.source;
    final parent = sourceNode.parent;
    final signature = sourceNode is core.SpatialText
        ? Object.hash(
            sourceNode.text,
            sourceNode.fontSize,
            sourceNode.color,
            sourceNode.fontWeight,
            sourceNode.textAlign,
          )
        : sourceNode is core.SpatialPanel
        ? Object.hash(
            sourceNode.panelWidth,
            sourceNode.panelHeight,
            sourceNode.backgroundColor,
            sourceNode.borderColor,
            sourceNode.opacity,
            sourceNode.borderWidth,
            sourceNode.cornerRadius,
            sourceNode.onRenderContent,
            parent is core.SpatialButton ? parent.label : null,
            parent is core.SpatialButton ? parent.labelColor : null,
          )
        : 0;
    if (entry.surfaceSignature == signature) return;
    entry.surfaceSignature = signature;
    final generation = ++entry.surfaceGeneration;
    final request = _surface(sourceNode);
    late final Future<void> work;
    work = resources
        .createSurface(request)
        .then((mesh) {
          if (!_disposed &&
              identical(_nodes[sourceNode], entry) &&
              entry.surfaceGeneration == generation) {
            entry.node.mesh = mesh;
          }
        })
        .catchError((Object error, StackTrace stack) {
          if (!_disposed &&
              identical(_nodes[sourceNode], entry) &&
              entry.surfaceGeneration == generation)
            _surfaceError = error;
        })
        .whenComplete(() => _pending.remove(work));
    _pending.add(work);
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _root.parent?.remove(_root);
    // The root belongs to Scene, not another Node.
    _scene?.remove(_root);
    _root.removeAll();
    _nodes.clear();
    _sources.clear();
    _geometry.clear();
    _lit.clear();
    _unlit.clear();
  }

  void _ensureAlive() {
    if (_disposed) throw StateError('VrRetainedSceneAdapter is disposed.');
  }
}

class _NodeEntry {
  _NodeEntry(this.source) : node = fs.Node(name: source.name);
  final core.Node source;
  final fs.Node node;
  int epoch = 0;
  fs.Geometry? meshGeometry;
  fs.Material? meshMaterial;
  bool meshInitialized = false;
  bool transformInitialized = false;
  final vm.Vector3 lastPosition = vm.Vector3.zero();
  final vm.Quaternion lastRotation = vm.Quaternion.identity();
  final vm.Vector3 lastScale = vm.Vector3.zero();
  final vm.Matrix4 lastMatrix = vm.Matrix4.identity();
  final List<_Part> parts = [];
  int? surfaceSignature;
  int surfaceGeneration = 0;
  fs.Component? lightComponent;
  fs.PointLight? point;
  fs.DirectionalLight? directional;
  fs.SpotLight? spot;
  final vm.Vector3 direction = vm.Vector3.zero();
}

class _Part {
  _Part(this.node, this.geometry, this.material);
  final fs.Node node;
  final core.Geometry geometry;
  final core.VRMaterial material;
  fs.Geometry? gpuGeometry;
  fs.Material? gpuMaterial;
  bool initialized = false;
}

class _GeometryEntry {
  int epoch = 0;
  bool solidCreated = false;
  bool wireCreated = false;
  fs.Geometry? solid;
  fs.Geometry? wire;
}

class _MaterialEntry {
  _MaterialEntry(this.material);
  final fs.Material? material;
  int epoch = 0;
  int? signature;
}

double _linear(double value) => value <= 0.04045
    ? value / 12.92
    : math.pow((value + 0.055) / 1.055, 2.4).toDouble();
vm.Vector4 _linearColor(ui.Color value, {double alpha = 1}) =>
    vm.Vector4(_linear(value.r), _linear(value.g), _linear(value.b), alpha);

vm.Matrix4 _transform(core.Node node) {
  final t = node.transform;
  if (node is core.SpatialText || node is core.SpatialPanel) {
    final billboard = node as core.Billboard;
    final eye = billboard.cameraRig.position.clone();
    final parent = node.parent;
    if (parent != null) vm.Matrix4.inverted(parent.worldMatrix).transform3(eye);
    final delta = eye - t.position;
    // Upright world-positioned UI: head rotation cannot move its anchor.
    final yaw = math.atan2(delta.x, delta.z);
    return vm.Matrix4.compose(
      t.position,
      vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), yaw),
      t.scale,
    );
  }
  // Read scalar state, not core's optional invalidation-dependent world cache.
  return vm.Matrix4.compose(t.position, t.rotation, t.scale);
}

core.Geometry _quad(double width, double height) => core.Geometry(
  vertices: [
    vm.Vector3(-width / 2, -height / 2, 0),
    vm.Vector3(width / 2, -height / 2, 0),
    vm.Vector3(width / 2, height / 2, 0),
    vm.Vector3(-width / 2, height / 2, 0),
  ],
  normals: List.generate(4, (_) => vm.Vector3(0, 0, 1)),
  // Same horizontal convention as VrTextLabel: screen right is world -X.
  uvs: [vm.Vector2(1, 1), vm.Vector2(0, 1), vm.Vector2(0, 0), vm.Vector2(1, 0)],
  indices: [0, 1, 2, 0, 2, 3],
);

core.Geometry _grid(double size, int divisions, {bool centerOnly = false}) {
  if (!size.isFinite || size <= 0 || divisions < 1 || divisions > 1024) {
    throw ArgumentError(
      'Retained grid requires positive size and 1..1024 divisions.',
    );
  }
  final vertices = <vm.Vector3>[];
  final indices = <int>[];
  void strip(double x0, double z0, double x1, double z1) {
    final i = vertices.length;
    vertices.addAll([
      vm.Vector3(x0, 0.002, z0),
      vm.Vector3(x1, 0.002, z0),
      vm.Vector3(x1, 0.002, z1),
      vm.Vector3(x0, 0.002, z1),
    ]);
    indices.addAll([i, i + 2, i + 1, i, i + 3, i + 2]);
  }

  for (var i = 0; i <= divisions; i++) {
    if ((i == divisions ~/ 2) != centerOnly) continue;
    final p = -size / 2 + i * size / divisions;
    strip(p - 0.003, -size / 2, p + 0.003, size / 2);
    strip(-size / 2, p - 0.003, size / 2, p + 0.003);
  }
  return core.Geometry(vertices: vertices, indices: indices);
}

core.Geometry _ring() {
  final vertices = <vm.Vector3>[];
  final indices = <int>[];
  for (var i = 0; i <= 48; i++) {
    final a = i * math.pi * 2 / 48;
    for (final radius in [0.995, 1.005]) {
      vertices.add(
        vm.Vector3(math.cos(a) * radius, 0.006, math.sin(a) * radius),
      );
    }
    if (i < 48) {
      final n = i * 2;
      indices.addAll([n, n + 2, n + 1, n + 1, n + 2, n + 3]);
    }
  }
  return core.Geometry(vertices: vertices, indices: indices);
}

VrRetainedSurface _surface(core.Node node) {
  if (node is core.SpatialText) {
    final text = node.text;
    final color = node.color;
    final weight = node.fontWeight;
    final align = node.textAlign;
    final font = math.max(1.0, node.fontSize);
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(fontSize: 96, color: color, fontWeight: weight),
      ),
      textDirection: TextDirection.ltr,
      textAlign: align,
    )..layout(maxWidth: 1536);
    final width = (painter.width + 16).ceil().clamp(2, 2048);
    final height = (painter.height + 16).ceil().clamp(2, 512);
    final worldHeight = font / 300;
    painter.dispose();
    return VrRetainedSurface(
      widthPixels: width,
      heightPixels: height,
      worldWidth: worldHeight * width / height,
      worldHeight: worldHeight,
      paint: (canvas, size) {
        final label = TextPainter(
          text: TextSpan(
            text: text,
            style: TextStyle(fontSize: 96, color: color, fontWeight: weight),
          ),
          textDirection: TextDirection.ltr,
          textAlign: align,
        )..layout(maxWidth: size.width - 16);
        label.paint(canvas, const ui.Offset(8, 8));
        label.dispose();
      },
    );
  }
  final panel = node as core.SpatialPanel;
  if (panel.panelWidth <= 0 ||
      panel.panelHeight <= 0 ||
      !panel.panelWidth.isFinite ||
      !panel.panelHeight.isFinite) {
    throw ArgumentError(
      'Retained panel ${panel.name}: dimensions must be finite and positive.',
    );
  }
  final width = (panel.panelWidth * 768).ceil().clamp(32, 2048);
  final height = (panel.panelHeight * 768).ceil().clamp(32, 2048);
  final background = panel.backgroundColor.withValues(alpha: panel.opacity);
  final border = panel.borderColor.withValues(alpha: panel.opacity);
  final borderWidth = panel.borderWidth;
  final corner = panel.cornerRadius;
  final content = panel.onRenderContent;
  return VrRetainedSurface(
    widthPixels: width,
    heightPixels: height,
    worldWidth: panel.panelWidth,
    worldHeight: panel.panelHeight,
    paint: (canvas, size) {
      final rect = ui.RRect.fromRectAndRadius(
        ui.Offset.zero & size,
        ui.Radius.circular(corner),
      );
      canvas.drawRRect(rect, ui.Paint()..color = background);
      canvas.save();
      canvas.clipRRect(rect);
      content?.call(canvas, size);
      canvas.restore();
      canvas.drawRRect(
        rect,
        ui.Paint()
          ..color = border
          ..style = ui.PaintingStyle.stroke
          ..strokeWidth = borderWidth,
      );
    },
  );
}
