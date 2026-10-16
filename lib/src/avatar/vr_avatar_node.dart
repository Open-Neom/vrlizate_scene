import 'dart:math' as math;

import 'package:flutter_scene/scene.dart' as fs;
import 'package:vector_math/vector_math.dart' as vm;
import 'package:vrlizate_avatar/vrlizate_avatar.dart';

import 'vr_avatar_geometry.dart';
import 'vr_avatar_plan.dart';

export 'vr_avatar_geometry.dart' show VrAvatarDetail;
export 'vr_avatar_plan.dart' show VrAvatarMotion, VrAvatarPlan, VrAvatarSurface;

/// A retained, procedural Scene avatar built from a public appearance profile.
///
/// Attach [root] to the host's scene. Its origin is at the feet, +Y is up and
/// **+Z is forward** (these are direct Scene primitives, not imported glTF).
/// [VrAvatarAppearance.heightMeters] fits the conservative full silhouette,
/// including ears/leaves; [plan] also exposes bounds for host placement.
///
/// Six PBR materials belong to this avatar. Up to six immutable GPU geometries
/// (three shapes × two detail levels) are shared for the process lifetime.
/// Recoloring only updates material factors. Resizing updates instance matrices;
/// neither operation recreates geometry, materials, nodes or instance groups.
///
/// The caller advances [tick] only while active, chooses LOD with hysteresis,
/// and calls [dispose] when leaving. No timers, listeners, textures, asset loads
/// or per-frame state notifications are installed by this renderer.
class VrAvatarNode {
  VrAvatarNode({
    required VrAvatarAppearance appearance,
    this.animateIdle = true,
    VrAvatarDetail detail = VrAvatarDetail.near,
  }) : _appearance = appearance,
       _detail = detail {
    root.add(_sway);
    for (final surface in VrAvatarSurface.values) {
      _materials[surface] = fs.PhysicallyBasedMaterial()
        ..vertexColorWeight = 0
        ..metallicFactor = 0;
    }
    _updateMaterials();
    _plan = VrAvatarPlan.build(appearance);
    _buildBatches();
  }

  final fs.Node root = fs.Node(name: 'vr_avatar')..raycastable = false;
  final fs.Node _sway = fs.Node(name: 'vr_avatar_idle')..raycastable = false;
  final bool animateIdle;
  final _materials = <VrAvatarSurface, fs.PhysicallyBasedMaterial>{};
  final _batches = <(VrAvatarShape, VrAvatarSurface), _AvatarBatch>{};
  final vm.Matrix4 _delta = vm.Matrix4.identity();
  VrAvatarAppearance _appearance;
  VrAvatarDetail _detail;
  late VrAvatarPlan _plan;
  double _time = 0;
  bool _disposed = false;

  VrAvatarAppearance get appearance => _appearance;
  VrAvatarDetail get detail => _detail;
  VrAvatarPlan get plan => _plan;
  bool get isDisposed => _disposed;
  int get instanceCount => _plan.partsFor(_detail).length;
  int get triangleCount => _plan.triangleCount(_detail);

  /// Render submission groups. Stereo/shadows may submit each group more than
  /// once; this is not a measured hardware draw-call count.
  int get batchCount => _batches.length;

  void updateAppearance(VrAvatarAppearance appearance) {
    if (_disposed || appearance == _appearance) return;
    final previous = _appearance;
    _appearance = appearance;
    _updateMaterials();
    final shapeChanged =
        appearance.species != previous.species ||
        appearance.pattern != previous.pattern;
    final proportionsChanged =
        appearance.heightMeters != previous.heightMeters ||
        appearance.headScale != previous.headScale ||
        appearance.featureScale != previous.featureScale;
    if (!shapeChanged && !proportionsChanged) return;
    _plan = VrAvatarPlan.build(appearance);
    if (shapeChanged) {
      _buildBatches();
    } else {
      // Topology and ordering are stable while editing proportions.
      final groups = _groupParts();
      for (final entry in _batches.entries) {
        final parts = groups[entry.key]!;
        entry.value.parts = parts;
        entry.value.mesh.updateInstanceTransforms((transforms) {
          for (var i = 0; i < transforms.length; i++) {
            transforms[i].setFrom(parts[i].transform);
          }
        }, recomputeWinding: false);
        entry.value.node.markTransformDirty();
      }
    }
  }

  /// Swaps retained instance groups to the cached detail meshes; never called
  /// implicitly every frame. Far LOD drops glints/pattern/frill details only.
  void setDetail(VrAvatarDetail detail) {
    if (_disposed || detail == _detail) return;
    _detail = detail;
    _buildBatches();
  }

  /// Evaluates localized idle motion (breathing, head look, ear/gill/leaf/tail
  /// oscillation, orb hover) on retained instances while keeping feet and
  /// ground contact shadows planted on the floor.
  void tick(double dt) {
    if (_disposed ||
        !animateIdle ||
        !root.visible ||
        _detail == VrAvatarDetail.far ||
        !dt.isFinite ||
        dt <= 0) {
      return;
    }
    _time = (_time + dt) % (math.pi * 20);
    final t = _time;
    final breathY = math.sin(t * 2.1) * .006 * _appearance.heightMeters;
    final bodyPitch = math.sin(t * 2.1) * .018;
    final bodyYaw = math.sin(t * 1.05) * .022;
    final headYaw = math.sin(t * 1.35) * .048;
    final headPitch = math.sin(t * 2.1 + .6) * .028;
    final headRoll = math.cos(t * 1.35) * .022;
    final armSwing = math.sin(t * 2.1) * .038;
    final leftFeat = math.sin(t * 3.2) * .065;
    final rightFeat = math.sin(t * 3.2 + .9) * .065;
    final crownSway = math.sin(t * 2.6) * .055;
    final tailWag = math.sin(t * 2.8) * .085;
    final hoverY = math.sin(t * 2.4) * .016 * _appearance.heightMeters;
    final hoverRoll = math.cos(t * 1.6) * .032;

    for (final batch in _batches.values) {
      final parts = batch.parts;
      if (parts.every((p) => p.motion == VrAvatarMotion.ground)) continue;
      batch.mesh.updateInstanceTransforms((transforms) {
        for (var i = 0; i < transforms.length; i++) {
          final part = parts[i];
          if (part.motion == VrAvatarMotion.ground) {
            transforms[i].setFrom(part.transform);
            continue;
          }
          final p = part.pivot;
          _delta.setIdentity();
          switch (part.motion) {
            case VrAvatarMotion.ground:
              break;
            case VrAvatarMotion.body:
              _delta
                ..translateByDouble(p.x, p.y + breathY, p.z, 1)
                ..rotateY(bodyYaw)
                ..rotateX(bodyPitch)
                ..translateByDouble(-p.x, -p.y, -p.z, 1);
            case VrAvatarMotion.head:
              _delta
                ..translateByDouble(p.x, p.y + breathY, p.z, 1)
                ..rotateY(headYaw)
                ..rotateX(headPitch)
                ..rotateZ(headRoll)
                ..translateByDouble(-p.x, -p.y, -p.z, 1);
            case VrAvatarMotion.leftArm:
              _delta
                ..translateByDouble(p.x, p.y + breathY, p.z, 1)
                ..rotateZ(-armSwing * .5)
                ..rotateX(armSwing)
                ..translateByDouble(-p.x, -p.y, -p.z, 1);
            case VrAvatarMotion.rightArm:
              _delta
                ..translateByDouble(p.x, p.y + breathY, p.z, 1)
                ..rotateZ(armSwing * .5)
                ..rotateX(-armSwing)
                ..translateByDouble(-p.x, -p.y, -p.z, 1);
            case VrAvatarMotion.leftFeature:
              _delta
                ..translateByDouble(p.x, p.y + breathY, p.z, 1)
                ..rotateY(headYaw)
                ..rotateZ(leftFeat)
                ..translateByDouble(-p.x, -p.y, -p.z, 1);
            case VrAvatarMotion.rightFeature:
              _delta
                ..translateByDouble(p.x, p.y + breathY, p.z, 1)
                ..rotateY(headYaw)
                ..rotateZ(-rightFeat)
                ..translateByDouble(-p.x, -p.y, -p.z, 1);
            case VrAvatarMotion.crownFeature:
              _delta
                ..translateByDouble(p.x, p.y + breathY, p.z, 1)
                ..rotateY(headYaw)
                ..rotateZ(crownSway)
                ..rotateX(headPitch * .6)
                ..translateByDouble(-p.x, -p.y, -p.z, 1);
            case VrAvatarMotion.tail:
              _delta
                ..translateByDouble(p.x, p.y + breathY * .6, p.z, 1)
                ..rotateY(tailWag)
                ..rotateZ(tailWag * .45)
                ..translateByDouble(-p.x, -p.y, -p.z, 1);
            case VrAvatarMotion.hoverCore:
              _delta
                ..translateByDouble(p.x, p.y + hoverY, p.z, 1)
                ..rotateY(bodyYaw * 1.2)
                ..rotateZ(hoverRoll)
                ..translateByDouble(-p.x, -p.y, -p.z, 1);
          }
          transforms[i]
            ..setFrom(_delta)
            ..multiply(part.transform);
        }
      }, recomputeWinding: false);
      batch.node.markTransformDirty();
    }
  }

  /// Detaches the owned subtree. Shared immutable primitives stay available to
  /// other avatars; Scene releases per-instance resources after unmount/GC.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    root.visible = false;
    root.detach();
    _clearBatches();
    _sway.detach();
    _materials.clear();
  }

  Map<(VrAvatarShape, VrAvatarSurface), List<VrAvatarPart>> _groupParts() {
    final groups = <(VrAvatarShape, VrAvatarSurface), List<VrAvatarPart>>{};
    for (final part in _plan.partsFor(_detail)) {
      groups.putIfAbsent((part.shape, part.surface), () => []).add(part);
    }
    return groups;
  }

  void _buildBatches() {
    _clearBatches();
    _sway.localTransform = vm.Matrix4.identity();
    for (final entry in _groupParts().entries) {
      final mesh = fs.InstancedMesh(
        geometry: _AvatarGeometryCache.geometry(entry.key.$1, _detail),
        material: _materials[entry.key.$2]!,
        // An avatar is a compact group: aggregate culling avoids per-piece
        // frustum tests; each batch still has correct transformed bounds.
        cullInstances: false,
      );
      for (final part in entry.value) {
        mesh.addInstance(part.transform);
      }
      final surface = entry.key.$2;
      final node =
          fs.Node(name: 'vr_avatar_${entry.key.$1.name}_${surface.name}')
            ..raycastable = false
            // Existing scene lights/shadow quality policy own the passes. Small
            // eye/glint/contact-shadow meshes do not cast self-shadow artifacts.
            ..shadowCastingMode =
                surface == VrAvatarSurface.ink ||
                    surface == VrAvatarSurface.pearl ||
                    surface == VrAvatarSurface.shadow
                ? fs.ShadowCastingMode.off
                : fs.ShadowCastingMode.on
            ..addComponent(fs.InstancedMeshComponent(mesh));
      _sway.add(node);
      _batches[entry.key] = _AvatarBatch(node, mesh, entry.value);
    }
    _sway.markTransformDirty();
  }

  void _clearBatches() {
    for (final batch in _batches.values) {
      batch.node.detach();
      batch.mesh.clearInstances();
    }
    _batches.clear();
  }

  void _updateMaterials() {
    final species = _appearance.species;
    final body = _linearArgb(_appearance.bodyColorArgb);
    final accent = _linearArgb(_appearance.accentColorArgb);
    final deepTint = vm.Vector4(.014, .026, .042, 1);
    final shadeColor = vm.Vector4(
      body.x * .66 + deepTint.x * .34,
      body.y * .66 + deepTint.y * .34,
      body.z * .66 + deepTint.z * .34,
      1,
    );

    final (
      bodyRoughness,
      bodyMetallic,
      shadeRoughness,
      shadeMetallic,
      accentRoughness,
      accentEmissive,
      inkRoughness,
    ) = switch (species) {
      VrAvatarSpecies.robot => (.26, .48, .36, .58, .22, .08, .12),
      VrAvatarSpecies.orb => (.20, .18, .30, .46, .22, .10, .10),
      VrAvatarSpecies.axolotl => (.32, .04, .38, .04, .30, .03, .14),
      VrAvatarSpecies.sprout => (.48, .02, .68, .0, .42, .02, .18),
      VrAvatarSpecies.fox => (.80, .0, .86, .0, .74, .0, .20),
      VrAvatarSpecies.human => (.58, .02, .72, .02, .52, .0, .28),
    };

    _materials[VrAvatarSurface.body]!
      ..baseColorFactor = body
      ..metallicFactor = bodyMetallic
      ..roughnessFactor = bodyRoughness
      ..emissiveFactor = species == VrAvatarSpecies.orb
          ? vm.Vector4(body.x * .04, body.y * .04, body.z * .04, 1)
          : vm.Vector4(0, 0, 0, 1);

    _materials[VrAvatarSurface.shade]!
      ..baseColorFactor = shadeColor
      ..metallicFactor = shadeMetallic
      ..roughnessFactor = shadeRoughness
      ..emissiveFactor = vm.Vector4(0, 0, 0, 1);

    _materials[VrAvatarSurface.accent]!
      ..baseColorFactor = accent
      ..metallicFactor = species == VrAvatarSpecies.robot ? .14 : 0
      ..roughnessFactor = accentRoughness
      ..emissiveFactor = vm.Vector4(
        accent.x * accentEmissive,
        accent.y * accentEmissive,
        accent.z * accentEmissive,
        1,
      );

    _materials[VrAvatarSurface.ink]!
      ..baseColorFactor = vm.Vector4(.009, .016, .028, 1)
      ..metallicFactor =
          species == VrAvatarSpecies.robot || species == VrAvatarSpecies.orb
          ? .18
          : .04
      ..roughnessFactor = inkRoughness
      ..emissiveFactor = vm.Vector4(0, 0, 0, 1);

    _materials[VrAvatarSurface.pearl]!
      ..baseColorFactor = vm.Vector4(.93, .95, .93, 1)
      ..metallicFactor = 0
      ..roughnessFactor = .44
      ..emissiveFactor = vm.Vector4(.02, .02, .02, 1);

    // Ground contact shadow pool on the pedestal surface.
    _materials[VrAvatarSurface.shadow]!
      ..baseColorFactor = vm.Vector4(.018, .028, .034, 1)
      ..metallicFactor = 0
      ..roughnessFactor = 1.0
      ..emissiveFactor = vm.Vector4(0, 0, 0, 1)
      ..depthLayer = 3;
  }
}

class _AvatarBatch {
  _AvatarBatch(this.node, this.mesh, this.parts);
  final fs.Node node;
  final fs.InstancedMesh mesh;
  List<VrAvatarPart> parts;
}

class _AvatarGeometryCache {
  static final _geometries = <(VrAvatarShape, VrAvatarDetail), fs.Geometry>{};

  static fs.Geometry geometry(VrAvatarShape shape, VrAvatarDetail detail) =>
      _geometries.putIfAbsent((shape, detail), () {
        final data = buildVrAvatarMeshData(shape, detail);
        return fs.MeshGeometry.fromArrays(
          positions: data.positions,
          normals: data.normals,
          texCoords: data.texCoords,
          indices: data.indices,
          retainCpuData: false,
        );
      });
}

vm.Vector4 _linearArgb(int argb) {
  double channel(int shift) {
    final srgb = ((argb >> shift) & 255) / 255;
    return srgb <= .04045
        ? srgb / 12.92
        : math.pow((srgb + .055) / 1.055, 2.4).toDouble();
  }

  return vm.Vector4(channel(16), channel(8), channel(0), 1);
}

