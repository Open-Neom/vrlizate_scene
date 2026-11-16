import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;
import 'package:vrlizate_widgets/vrlizate_widgets.dart'
    show VrBeveledBoxArrays, VrBeveledBoxGeometry;

import 'lathe_geometry.dart';
import 'vr_mesh_tangents.dart';

/// CPU-side buffers for procedural 3D sculpted primitives, enabling headless
/// unit tests of vertex bounds, normals, CCW winding, and orthonormal tangents
/// without requiring an active Impeller GPU context.
final class VrSculptedArrays {
  const VrSculptedArrays({
    required this.positions,
    required this.normals,
    required this.texCoords,
    required this.tangents,
    required this.indices,
  });

  final Float32List positions;
  final Float32List normals;
  final Float32List texCoords;
  final Float32List tangents;
  final List<int> indices;

  int get vertexCount => positions.length ~/ 3;
  int get triangleCount => indices.length ~/ 3;
}

/// High-craft procedural 3D geometry primitives for VRlizate scenes & games:
/// - [beveledBox]: Filleted/chamfered slabs, walls, casings, and cartridges.
/// - [capsule]: Smooth hemisphere-capped capsules for limbs, bolts, and pods.
/// - [facetedCrystal]: Split-vertex flat-faceted gems & harmonic prisms whose
///   individual planar normals catch razor-sharp specular IBL highlights.
/// - [octaCore] & [icosaCore]: Split-vertex polyhedral sci-fi cores, drones,
///   and bio-mech carapaces.
/// - [flutedPedestal] & [sciFiPylon]: Architectural turned columns and stepped
///   cyber monoliths.
///
/// All GPU [MeshGeometry] outputs carry orthonormal glTF 2.0 tangent frames
/// (`vec4(tx, ty, tz, w)`) and share a bounded LRU GPU cache.
abstract final class VrSculptedGeometry {
  static const int _maxCached = 96;
  static final LinkedHashMap<Object, MeshGeometry> _cache =
      LinkedHashMap<Object, MeshGeometry>();

  static void clearCache() {
    _cache.clear();
    VrBeveledBoxGeometry.clearCache();
  }

  static MeshGeometry _cached(Object key, VrSculptedArrays Function() build) {
    final hit = _cache.remove(key);
    if (hit != null) {
      _cache[key] = hit;
      return hit;
    }
    final a = build();
    final geo = MeshGeometry.fromArrays(
      positions: a.positions,
      normals: a.normals,
      texCoords: a.texCoords,
      tangents: a.tangents,
      indices: a.indices,
    );
    while (_cache.length >= _maxCached) {
      _cache.remove(_cache.keys.first);
    }
    _cache[key] = geo;
    return geo;
  }

  /// Filleted/chamfered 3D box centered at `(0, 0, 0)` with exact extents [size].
  static MeshGeometry beveledBox(
    vm.Vector3 size, {
    double? cornerRadius,
    double? bevelZ,
    int cornerSegments = 3,
    int bevelSegments = 2,
  }) => VrBeveledBoxGeometry.create(
    size,
    cornerRadius: cornerRadius,
    bevelZ: bevelZ,
    cornerSegments: cornerSegments,
    bevelSegments: bevelSegments,
  );

  static VrSculptedArrays beveledBoxArrays(
    vm.Vector3 size, {
    double? cornerRadius,
    double? bevelZ,
    int cornerSegments = 3,
    int bevelSegments = 2,
  }) {
    final VrBeveledBoxArrays a = VrBeveledBoxGeometry.buildArrays(
      size,
      cornerRadius: cornerRadius,
      bevelZ: bevelZ,
      cornerSegments: cornerSegments,
      bevelSegments: bevelSegments,
    );
    return VrSculptedArrays(
      positions: a.positions,
      normals: a.normals,
      texCoords: a.texCoords,
      tangents: a.tangents,
      indices: a.indices,
    );
  }

  /// Smooth vertical capsule centered at `(0, 0, 0)` with total [height] and
  /// cylinder/cap [radius].
  static MeshGeometry capsule({
    double radius = 0.18,
    double height = 0.72,
    int capRings = 6,
    int segments = 20,
  }) {
    final r = math.max(radius.abs(), 1e-3);
    final h = math.max(height.abs(), r * 2.02);
    final rings = capRings.clamp(2, 16);
    final segs = segments.clamp(6, 48);
    return _cached(
      ('capsule', (r * 10000).round(), (h * 10000).round(), rings, segs),
      () => capsuleArrays(
        radius: r,
        height: h,
        capRings: rings,
        segments: segs,
      ),
    );
  }

  static VrSculptedArrays capsuleArrays({
    double radius = 0.18,
    double height = 0.72,
    int capRings = 6,
    int segments = 20,
  }) {
    final r = math.max(radius.abs(), 1e-3);
    final h = math.max(height.abs(), r * 2.02);
    final halfShaft = math.max(0.0, h * 0.5 - r);
    final rings = capRings.clamp(2, 16);
    final segs = segments.clamp(6, 48);

    final profile = <vm.Vector2>[];
    // Bottom hemisphere: phi from -pi/2 .. 0
    for (var i = 0; i <= rings; i++) {
      final phi = -math.pi * 0.5 + (i / rings) * (math.pi * 0.5);
      final x = i == 0 ? 0.0 : r * math.cos(phi);
      final y = -halfShaft + r * math.sin(phi);
      profile.add(vm.Vector2(x, y));
    }
    // Top hemisphere: phi from 0 .. +pi/2
    final startTop = halfShaft > 1e-5 ? 0 : 1;
    for (var i = startTop; i <= rings; i++) {
      final phi = (i / rings) * (math.pi * 0.5);
      final x = i == rings ? 0.0 : r * math.cos(phi);
      final y = halfShaft + r * math.sin(phi);
      profile.add(vm.Vector2(x, y));
    }

    final lathe = LatheGeometry.revolveArrays(profile, segments: segs);
    return VrSculptedArrays(
      positions: lathe.positions,
      normals: lathe.normals,
      texCoords: lathe.texCoords,
      tangents: lathe.tangents,
      indices: lathe.indices,
    );
  }

  /// Split-vertex flat-faceted double-terminated crystal / gem centered at
  /// `(0, 0, 0)` with total [height] and equatorial girdle [radius].
  ///
  /// Every facet owns unshared vertices with an exact planar normal so dynamic
  /// lights and IBL produce crisp jeweler-cut specular flashes.
  static MeshGeometry facetedCrystal({
    double radius = 0.26,
    double height = 0.68,
    int sides = 6,
    double crownTableScale = 0.52,
  }) {
    final r = math.max(radius.abs(), 1e-3);
    final h = math.max(height.abs(), 2e-3);
    final s = sides.clamp(4, 16);
    final crown = crownTableScale.clamp(0.18, 0.85);
    return _cached(
      (
        'crystal',
        (r * 10000).round(),
        (h * 10000).round(),
        s,
        (crown * 1000).round(),
      ),
      () => facetedCrystalArrays(
        radius: r,
        height: h,
        sides: s,
        crownTableScale: crown,
      ),
    );
  }

  static VrSculptedArrays facetedCrystalArrays({
    double radius = 0.26,
    double height = 0.68,
    int sides = 6,
    double crownTableScale = 0.52,
  }) {
    final r = math.max(radius.abs(), 1e-3);
    final h = math.max(height.abs(), 2e-3);
    final s = sides.clamp(4, 16);
    final tableR = r * crownTableScale.clamp(0.18, 0.85);
    final halfH = h * 0.5;
    final yUpperGirdle = halfH * 0.26;
    final yLowerGirdle = -halfH * 0.22;

    vm.Vector3 ringPt(double rad, double y, int k, {double twist = 0.0}) {
      final a = (2.0 * math.pi * k / s) + twist;
      return vm.Vector3(rad * math.cos(a), y, -rad * math.sin(a));
    }

    final topCenter = vm.Vector3(0, halfH, 0);
    final bottomTip = vm.Vector3(0, -halfH, 0);
    final builder = _FlatFacetBuilder();

    for (var k = 0; k < s; k++) {
      final nk = (k + 1) % s;
      final t0 = ringPt(tableR, halfH * 0.86, k);
      final t1 = ringPt(tableR, halfH * 0.86, nk);
      final u0 = ringPt(r, yUpperGirdle, k);
      final u1 = ringPt(r, yUpperGirdle, nk);
      final l0 = ringPt(r * 0.94, yLowerGirdle, k, twist: math.pi / s);
      final l1 = ringPt(r * 0.94, yLowerGirdle, nk, twist: math.pi / s);

      // Apex cap facet:
      builder.addTriangle(topCenter, t0, t1);
      // Crown bevel trapezoid (2 crisp triangles -> 1 planar quad when untwisted):
      builder.addQuad(t0, u0, u1, t1);
      // Interlocked girdle triangular facets (brilliant-cut style!):
      builder.addTriangle(u0, l0, u1);
      builder.addTriangle(u1, l0, l1);
      // Pavilion point facet:
      builder.addTriangle(l0, bottomTip, l1);
    }

    return builder.build();
  }

  /// Split-vertex flat-faceted bipyramidal octahedron core centered at origin.
  static MeshGeometry octaCore({
    double radius = 0.28,
    double verticalScale = 1.15,
  }) {
    final r = math.max(radius.abs(), 1e-3);
    final vs = verticalScale.clamp(0.35, 3.0);
    return _cached(
      ('octa', (r * 10000).round(), (vs * 1000).round()),
      () => octaCoreArrays(radius: r, verticalScale: vs),
    );
  }

  static VrSculptedArrays octaCoreArrays({
    double radius = 0.28,
    double verticalScale = 1.15,
  }) {
    final r = math.max(radius.abs(), 1e-3);
    final top = vm.Vector3(0, r * verticalScale, 0);
    final bot = vm.Vector3(0, -r * verticalScale, 0);
    final eq = <vm.Vector3>[
      vm.Vector3(r, 0, 0),
      vm.Vector3(0, 0, -r),
      vm.Vector3(-r, 0, 0),
      vm.Vector3(0, 0, r),
    ];
    final b = _FlatFacetBuilder();
    for (var i = 0; i < 4; i++) {
      final a = eq[i];
      final c = eq[(i + 1) % 4];
      b.addTriangle(top, a, c);
      b.addTriangle(a, bot, c);
    }
    return b.build();
  }

  /// Split-vertex flat-faceted 20-face regular icosahedron core centered at origin.
  static MeshGeometry icosaCore({double radius = 0.30}) {
    final r = math.max(radius.abs(), 1e-3);
    return _cached(
      ('icosa', (r * 10000).round()),
      () => icosaCoreArrays(radius: r),
    );
  }

  static VrSculptedArrays icosaCoreArrays({double radius = 0.30}) {
    final r = math.max(radius.abs(), 1e-3);
    final t = (1.0 + math.sqrt(5.0)) * 0.5;
    vm.Vector3 v(double x, double y, double z) =>
        (vm.Vector3(x, y, z)..normalize()).scaled(r);

    final verts = <vm.Vector3>[
      v(-1, t, 0),
      v(1, t, 0),
      v(-1, -t, 0),
      v(1, -t, 0),
      v(0, -1, t),
      v(0, 1, t),
      v(0, -1, -t),
      v(0, 1, -t),
      v(t, 0, -1),
      v(t, 0, 1),
      v(-t, 0, -1),
      v(-t, 0, 1),
    ];
    const faces = <(int, int, int)>[
      (0, 11, 5),
      (0, 5, 1),
      (0, 1, 7),
      (0, 7, 10),
      (0, 10, 11),
      (1, 5, 9),
      (5, 11, 4),
      (11, 10, 2),
      (10, 7, 6),
      (7, 1, 8),
      (3, 9, 4),
      (3, 4, 2),
      (3, 2, 6),
      (3, 6, 8),
      (3, 8, 9),
      (4, 9, 5),
      (2, 4, 11),
      (6, 2, 10),
      (8, 6, 7),
      (9, 8, 1),
    ];
    final b = _FlatFacetBuilder();
    for (final (i0, i1, i2) in faces) {
      b.addTriangle(verts[i0], verts[i1], verts[i2]);
    }
    return b.build();
  }

  /// Turned architectural pedestal / column centered vertically on `[0 .. height]`
  /// or `[-height/2 .. +height/2]` when [centerAtOrigin] is `true`.
  static MeshGeometry flutedPedestal({
    double bottomRadius = 0.28,
    double topRadius = 0.23,
    double height = 0.92,
    int segments = 24,
    bool centerAtOrigin = true,
  }) {
    final br = math.max(bottomRadius.abs(), 0.02);
    final tr = math.max(topRadius.abs(), 0.02);
    final h = math.max(height.abs(), 0.05);
    final segs = segments.clamp(8, 48);
    return _cached(
      (
        'pedestal',
        (br * 10000).round(),
        (tr * 10000).round(),
        (h * 10000).round(),
        segs,
        centerAtOrigin,
      ),
      () => flutedPedestalArrays(
        bottomRadius: br,
        topRadius: tr,
        height: h,
        segments: segs,
        centerAtOrigin: centerAtOrigin,
      ),
    );
  }

  static VrSculptedArrays flutedPedestalArrays({
    double bottomRadius = 0.28,
    double topRadius = 0.23,
    double height = 0.92,
    int segments = 24,
    bool centerAtOrigin = true,
  }) {
    final y0 = centerAtOrigin ? -height * 0.5 : 0.0;
    final shaftBot = bottomRadius * 0.78;
    final shaftTop = topRadius * 0.80;
    vm.Vector2 p(double r, double t) => vm.Vector2(r, y0 + t * height);

    final profile = <vm.Vector2>[
      p(0.0, 0.0),
      p(bottomRadius, 0.0),
      p(bottomRadius, 0.07),
      p(bottomRadius * 0.92, 0.09),
      p(bottomRadius * 0.94, 0.13),
      p(shaftBot, 0.17),
      p(shaftTop, 0.81),
      p(topRadius * 0.94, 0.85),
      p(topRadius * 0.90, 0.88),
      p(topRadius * 1.04, 0.93),
      p(topRadius * 1.04, 1.0),
      p(0.0, 1.0),
    ];

    final lathe = LatheGeometry.revolveArrays(
      profile,
      segments: segments.clamp(8, 48),
    );
    return VrSculptedArrays(
      positions: lathe.positions,
      normals: lathe.normals,
      texCoords: lathe.texCoords,
      tangents: lathe.tangents,
      indices: lathe.indices,
    );
  }

  /// Stepped octagonal sci-fi obelisk / arena pylon centered at `(0, 0, 0)`.
  static MeshGeometry sciFiPylon({
    double radius = 0.26,
    double height = 4.2,
    int sides = 8,
  }) {
    final r = math.max(radius.abs(), 0.04);
    final h = math.max(height.abs(), 0.2);
    final s = sides.clamp(4, 16);
    return _cached(('pylon', (r * 10000).round(), (h * 10000).round(), s), () {
      final y0 = -h * 0.5;
      vm.Vector2 p(double radScale, double t) =>
          vm.Vector2(r * radScale, y0 + t * h);
      final lathe = LatheGeometry.revolveArrays([
        p(0.0, 0.0),
        p(1.18, 0.0),
        p(1.18, 0.08),
        p(0.92, 0.12),
        p(0.86, 0.46),
        p(0.72, 0.48),
        p(0.72, 0.53),
        p(0.84, 0.55),
        p(0.76, 0.90),
        p(0.96, 0.94),
        p(0.55, 1.0),
        p(0.0, 1.0),
      ], segments: s);
      return VrSculptedArrays(
        positions: lathe.positions,
        normals: lathe.normals,
        texCoords: lathe.texCoords,
        tangents: lathe.tangents,
        indices: lathe.indices,
      );
    });
  }
}

final class _FlatFacetBuilder {
  final List<double> _pos = <double>[];
  final List<double> _nrm = <double>[];
  final List<double> _uv = <double>[];
  final List<int> _idx = <int>[];

  void addTriangle(vm.Vector3 a, vm.Vector3 b, vm.Vector3 c) {
    final n = (b - a).cross(c - a);
    if (n.length2 <= 1e-14) return;
    n.normalize();

    final base = _pos.length ~/ 3;
    void push(vm.Vector3 v, double u, double tv) {
      _pos
        ..add(v.x)
        ..add(v.y)
        ..add(v.z);
      _nrm
        ..add(n.x)
        ..add(n.y)
        ..add(n.z);
      _uv
        ..add(u)
        ..add(tv);
    }

    push(a, 0.5, 0.0);
    push(b, 0.0, 1.0);
    push(c, 1.0, 1.0);
    _idx
      ..add(base)
      ..add(base + 1)
      ..add(base + 2);
  }

  void addQuad(vm.Vector3 a, vm.Vector3 b, vm.Vector3 c, vm.Vector3 d) {
    final n = ((b - a).cross(c - a) + (c - a).cross(d - a));
    if (n.length2 <= 1e-14) return;
    n.normalize();

    final base = _pos.length ~/ 3;
    void push(vm.Vector3 v, double u, double tv) {
      _pos
        ..add(v.x)
        ..add(v.y)
        ..add(v.z);
      _nrm
        ..add(n.x)
        ..add(n.y)
        ..add(n.z);
      _uv
        ..add(u)
        ..add(tv);
    }

    push(a, 0.0, 0.0);
    push(b, 0.0, 1.0);
    push(c, 1.0, 1.0);
    push(d, 1.0, 0.0);
    _idx
      ..add(base)
      ..add(base + 1)
      ..add(base + 2)
      ..add(base)
      ..add(base + 2)
      ..add(base + 3);
  }

  VrSculptedArrays build() {
    final positions = Float32List.fromList(_pos);
    final normals = Float32List.fromList(_nrm);
    final texCoords = Float32List.fromList(_uv);
    final tangents = VrMeshTangents.compute(
      positions: positions,
      normals: normals,
      texCoords: texCoords,
      indices: _idx,
    );
    return VrSculptedArrays(
      positions: positions,
      normals: normals,
      texCoords: texCoords,
      tangents: tangents,
      indices: List<int>.unmodifiable(_idx),
    );
  }
}
