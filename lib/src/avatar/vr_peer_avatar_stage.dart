import 'dart:math' as math;

import 'package:flutter_scene/scene.dart' as fs;
import 'package:vector_math/vector_math.dart' as vm;
import 'package:vrlizate_avatar/vrlizate_avatar.dart';

import 'vr_avatar_geometry.dart';
import 'vr_avatar_motion_frame.dart';
import 'vr_avatar_node.dart';
import 'vr_avatar_plan.dart';

/// Lightweight pose/motion packet for a remote multiplayer user or local NPC.
///
/// Designed for `10–20 Hz` network or AI updates while [VrPeerAvatarStage]
/// interpolates and dead-reckons visuals smoothly at `60–120 Hz` without GC
/// allocations or per-avatar draw-call proliferation.
class VrPeerAvatarSnapshot {
  const VrPeerAvatarSnapshot({
    required this.peerId,
    required this.appearance,
    required this.x,
    this.y = 0.0,
    required this.z,
    required this.yaw,
    this.vx = 0.0,
    this.vz = 0.0,
    this.pose,
    this.sequence,
    this.timestampSeconds = 0.0,
  });

  final String peerId;
  final VrAvatarAppearance appearance;
  final double x;
  final double y;
  final double z;
  final double yaw;
  final double vx;
  final double vz;
  final VrAvatarPose? pose;

  /// Optional uint16/int packet sequence. Older out-of-order packets are ignored.
  final int? sequence;
  final double timestampSeconds;
}

/// Shared, zero-GC instanced crowd & multiplayer peer avatar stage.
///
/// Instead of creating `8–15` separate `InstancedMesh`es and `6` materials *per
/// avatar* (which generates `300+` stereo draw calls for 12 avatars), this stage
/// batches **all remote users and NPCs** into **at most 3 shared `InstancedMesh`
/// draw calls total** (`round`, `softBox`, `petal`) using per-instance linear
/// RGBA colors, view-frustum + distance culling, dead-reckoning interpolation,
/// and tiered limb articulation.
class VrPeerAvatarStage {
  VrPeerAvatarStage({
    this.maxPeers = 32,
    this.maxVisibleDistance = 27.0,
    this.articulateDistance = 14.5,
    this.maxArticulatedPeers = 8,
    this.maxExtrapolationSeconds = 0.22,
    this.smoothingRate = 11.5,
    this.poseSmoothingRate = 10.5,
    this.meshDetail = VrAvatarDetail.near,
  }) : assert(maxPeers >= 1 && maxPeers <= 128);

  /// `flutter_scene` combines per-instance `instance_color` with vertex color
  /// via `mix(vec4(1), v_color, vertex_color_weight)`. Keeping this at `1.0`
  /// ensures every batched NPC/peer part renders its true PBR linear color
  /// instead of solid white.
  static const double sharedMaterialVertexColorWeight = 1.0;

  final int maxPeers;
  final double maxVisibleDistance;
  final double articulateDistance;
  final int maxArticulatedPeers;
  final double maxExtrapolationSeconds;
  final double smoothingRate;
  final double poseSmoothingRate;
  final VrAvatarDetail meshDetail;

  final fs.Node root = fs.Node(name: 'vr_peer_avatar_stage')
    ..raycastable = false
    ..shadowCastingMode = fs.ShadowCastingMode.off;

  final Map<String, _PeerRecord> _peers = {};
  final List<_PeerRecord> _peerList = [];
  final List<_PeerRecord> _articulationCandidates = [];
  final Map<VrAvatarShape, _ShapeBatch> _shapeBatches = {};

  // Reusable zero-GC scratch buffers for the per-frame render loop.
  final VrAvatarMotionFrame _motionScratch = VrAvatarMotionFrame();
  final vm.Matrix4 _deltaScratch = vm.Matrix4.identity();
  final vm.Matrix4 _rootScratch = vm.Matrix4.identity();
  static final vm.Matrix4 _hiddenMatrix = vm.Matrix4.zero();

  bool _gpuMounted = false;
  bool _shadowsEnabled = false;
  bool _slotsDirty = false;
  bool _disposed = false;
  double _clock = 0.0;
  int _visiblePeerCount = 0;
  int _articulatedPeerCount = 0;

  int get peerCount => _peerList.length;
  int get visiblePeerCount => _visiblePeerCount;
  int get articulatedPeerCount => _articulatedPeerCount;
  bool get isGpuMounted => _gpuMounted;

  /// Total GPU render batches across all peers (`<= 3`, regardless of crowd size).
  int get batchCount => _shapeBatches.length;

  /// Returns the current smoothly interpolated world position of [peerId].
  vm.Vector3? interpolatedPosition(String peerId) {
    final rec = _peers[peerId];
    if (rec == null) return null;
    return vm.Vector3(rec.renderX, rec.renderY, rec.renderZ);
  }

  /// Returns the current smoothly interpolated yaw (radians) of [peerId].
  double? interpolatedYaw(String peerId) => _peers[peerId]?.renderYaw;

  /// Whether [peerId] received full limb articulation on the most recent tick.
  bool isPeerArticulated(String peerId) =>
      _peers[peerId]?.wasArticulated ?? false;

  /// Enables or disables real directional shadow casting for all batched
  /// peers/NPCs (enabled on `high`/`ultra` tiers so avatars cast grounded
  /// shadows on the architectural floor).
  void setShadowsEnabled(bool enabled) {
    if (_shadowsEnabled == enabled) return;
    _shadowsEnabled = enabled;
    final mode = enabled
        ? fs.ShadowCastingMode.on
        : fs.ShadowCastingMode.off;
    root.shadowCastingMode = mode;
    for (final batch in _shapeBatches.values) {
      batch.node.shadowCastingMode = mode;
    }
  }

  /// Mounts the 3 shared `InstancedMesh` batches onto [parent] when Flutter GPU
  /// (`Scene.isReadyToRender`) is available.
  void mountGpu(fs.Node parent) {
    if (_disposed || _gpuMounted || !fs.Scene.isReadyToRender) return;
    _gpuMounted = true;
    final shadowMode = _shadowsEnabled
        ? fs.ShadowCastingMode.on
        : fs.ShadowCastingMode.off;
    root.shadowCastingMode = shadowMode;
    for (final shape in VrAvatarShape.values) {
      // Tune PBR response per geometric primitive family while keeping <= 3
      // instanced batches total:
      // - round: soft velvety matte-satin for skin, organic forms & textiles
      // - softBox: crisp architectural satin-metal for robot plating & trim
      // - petal: luminous refined finish for crests, foliage & emblems
      final (roughness, metallic) = switch (shape) {
        VrAvatarShape.round => (0.68, 0.02),
        VrAvatarShape.softBox => (0.34, 0.28),
        VrAvatarShape.petal => (0.28, 0.36),
      };
      final material = fs.PhysicallyBasedMaterial()
        ..baseColorFactor = vm.Vector4(1, 1, 1, 1)
        ..vertexColorWeight = sharedMaterialVertexColorWeight
        ..roughnessFactor = roughness
        ..metallicFactor = metallic;
      final mesh = fs.InstancedMesh(
        geometry: VrAvatarGeometryCache.geometry(shape, meshDetail),
        material: material,
        cullInstances: false,
      );
      final node = fs.Node(name: 'vr_peer_batch_${shape.name}')
        ..raycastable = false
        ..shadowCastingMode = shadowMode
        ..addComponent(fs.InstancedMeshComponent(mesh));
      root.add(node);
      _shapeBatches[shape] = _ShapeBatch(node: node, mesh: mesh);
    }
    parent.add(root);
    _rebuildInstanceSlots();
  }

  /// Inserts or updates a remote multiplayer user or local NPC state snapshot.
  ///
  /// Returns `true` if accepted, or `false` if rejected (capacity full or stale
  /// sequence number).
  bool upsertPeer(VrPeerAvatarSnapshot snapshot) {
    if (_disposed) return false;
    final existing = _peers[snapshot.peerId];
    if (existing != null) {
      if (snapshot.sequence != null &&
          existing.lastSequence != null &&
          !_isNewerSequence(snapshot.sequence!, existing.lastSequence!)) {
        return false;
      }
      existing.lastSequence = snapshot.sequence ?? existing.lastSequence;
      final appearanceChanged = existing.appearance != snapshot.appearance;
      if (appearanceChanged) {
        existing.updateAppearance(snapshot.appearance);
        _slotsDirty = true;
      }
      final teleported =
          _distSq(existing.renderX, existing.renderZ, snapshot.x, snapshot.z) >
          36.0;
      existing.targetX = snapshot.x;
      existing.targetY = snapshot.y;
      existing.targetZ = snapshot.z;
      existing.targetYaw = snapshot.yaw;
      existing.vx = snapshot.vx;
      existing.vz = snapshot.vz;
      existing.pose = snapshot.pose;
      existing.ageSinceSnapshot = 0.0;
      existing.poseDirty = true;
      if (teleported) {
        existing.renderX = snapshot.x;
        existing.renderY = snapshot.y;
        existing.renderZ = snapshot.z;
        existing.renderYaw = snapshot.yaw;
      }
      return true;
    }

    if (_peerList.length >= maxPeers) return false;
    final record = _PeerRecord(
      peerId: snapshot.peerId,
      appearance: snapshot.appearance,
      detail: meshDetail,
      x: snapshot.x,
      y: snapshot.y,
      z: snapshot.z,
      yaw: snapshot.yaw,
      vx: snapshot.vx,
      vz: snapshot.vz,
      pose: snapshot.pose,
      lastSequence: snapshot.sequence,
      phaseOffset: (_peerList.length * 0.83) % (math.pi * 2),
    );
    _peers[snapshot.peerId] = record;
    _peerList.add(record);
    _slotsDirty = true;
    return true;
  }

  /// Fast zero-allocation mutable update path for local NPCs already registered
  /// in the stage (avoids even allocating a [VrPeerAvatarSnapshot] struct).
  void updatePeerMotion(
    String peerId, {
    required double x,
    double y = 0.0,
    required double z,
    required double yaw,
    double vx = 0.0,
    double vz = 0.0,
    VrAvatarPose? pose,
  }) {
    final rec = _peers[peerId];
    if (rec == null || _disposed) return;
    rec.targetX = x;
    rec.targetY = y;
    rec.targetZ = z;
    rec.targetYaw = yaw;
    rec.vx = vx;
    rec.vz = vz;
    rec.pose = pose;
    rec.ageSinceSnapshot = 0.0;
    rec.poseDirty = true;
  }

  bool removePeer(String peerId) {
    final removed = _peers.remove(peerId);
    if (removed == null) return false;
    _peerList.remove(removed);
    _slotsDirty = true;
    return true;
  }

  void clear() {
    if (_peerList.isEmpty) return;
    _peers.clear();
    _peerList.clear();
    _articulationCandidates.clear();
    _slotsDirty = true;
  }

  /// Advances smooth dead-reckoned interpolation at `60–120 Hz`, applies stereo
  /// frustum + distance culling, and submits at most 1 buffer update per shape.
  void tick(
    double dt, {
    vm.Vector3? eyePosition,
    vm.Vector3? viewerForward,
  }) {
    if (_disposed || !dt.isFinite || dt <= 0) return;
    final clampedDt = dt.clamp(0.0, 0.1);
    _clock = (_clock + clampedDt) % (math.pi * 40);

    if (_gpuMounted && _slotsDirty) {
      _rebuildInstanceSlots();
    }

    final alpha = 1.0 - math.exp(-smoothingRate * clampedDt);
    final maxDistSq = maxVisibleDistance * maxVisibleDistance;
    final artDistSq = articulateDistance * articulateDistance;

    double fwdX = 0.0;
    double fwdZ = 0.0;
    var hasForward = false;
    if (viewerForward != null) {
      final len = math.sqrt(
        viewerForward.x * viewerForward.x + viewerForward.z * viewerForward.z,
      );
      if (len > 1e-4) {
        fwdX = viewerForward.x / len;
        fwdZ = viewerForward.z / len;
        hasForward = true;
      }
    }

    var visibleCount = 0;
    var articulatedCount = 0;
    _articulationCandidates.clear();

    // 1. Advance smooth kinematics & classify visibility/distance for all peers.
    for (var i = 0; i < _peerList.length; i++) {
      final p = _peerList[i];
      p.ageSinceSnapshot += clampedDt;
      final extrap = math.min(p.ageSinceSnapshot, maxExtrapolationSeconds);
      final predX = p.targetX + p.vx * extrap;
      final predZ = p.targetZ + p.vz * extrap;

      final prevX = p.renderX;
      final prevY = p.renderY;
      final prevZ = p.renderZ;
      final prevYaw = p.renderYaw;

      p.renderX += (predX - p.renderX) * alpha;
      p.renderY += (p.targetY - p.renderY) * alpha;
      p.renderZ += (predZ - p.renderZ) * alpha;
      p.renderYaw = _lerpAngle(p.renderYaw, p.targetYaw, alpha);

      p.movedRootThisFrame =
          (p.renderX - prevX).abs() > 4e-4 ||
          (p.renderY - prevY).abs() > 4e-4 ||
          (p.renderZ - prevZ).abs() > 4e-4 ||
          _angleDiff(p.renderYaw, prevYaw).abs() > 8e-4;

      var visible = true;
      var distSq = 0.0;
      if (eyePosition != null) {
        final dx = p.renderX - eyePosition.x;
        final dz = p.renderZ - eyePosition.z;
        distSq = dx * dx + dz * dz;
        if (distSq > maxDistSq) {
          visible = false;
        } else if (hasForward && distSq > 3.2 * 3.2) {
          final invDist = 1.0 / math.sqrt(distSq);
          final dot = (dx * invDist) * fwdX + (dz * invDist) * fwdZ;
          // Wide ~205° stereo safety cone (-0.22) so head turns never pop edges.
          if (dot < -0.22) {
            visible = false;
          }
        }
      }

      p.currentlyVisible = visible;
      p.currentDistSq = distSq;
      p.shouldArticulateThisFrame = false;
      if (!visible) {
        if (!p.wasCulled) {
          p.needsGpuWrite = true;
          p.wasCulled = true;
        } else {
          p.needsGpuWrite = false;
        }
        continue;
      }

      visibleCount++;
      if (distSq <= artDistSq) {
        _articulationCandidates.add(p);
      }
    }

    // 1b. Prioritize the closest visible peers for limb articulation (zero-GC
    // in-place insertion sort) so distant NPCs never steal slots from nearby
    // visitors standing right in front of the player.
    for (var i = 1; i < _articulationCandidates.length; i++) {
      final key = _articulationCandidates[i];
      var j = i - 1;
      while (j >= 0 &&
          _articulationCandidates[j].currentDistSq > key.currentDistSq) {
        _articulationCandidates[j + 1] = _articulationCandidates[j];
        j--;
      }
      _articulationCandidates[j + 1] = key;
    }
    final budget = math.min(maxArticulatedPeers, _articulationCandidates.length);
    for (var i = 0; i < budget; i++) {
      _articulationCandidates[i].shouldArticulateThisFrame = true;
    }
    articulatedCount = budget;

    // 1c. Apply smooth damped limb articulation (30 Hz) or rigid rest LOD.
    for (var i = 0; i < _peerList.length; i++) {
      final p = _peerList[i];
      if (!p.currentlyVisible) continue;
      final shouldArticulate = p.shouldArticulateThisFrame;
      if (shouldArticulate) {
        p.limbAccum += clampedDt;
        if (p.limbAccum >= (1.0 / 30.0) || p.poseDirty || p.wasCulled) {
          final limbDt = math.max(p.limbAccum, clampedDt);
          p.limbAccum = 0.0;
          p.poseDirty = false;
          final poseAlpha = 1.0 - math.exp(-poseSmoothingRate * limbDt);
          p.smoothedPose = VrAvatarPose.lerp(
            p.smoothedPose,
            p.pose ?? VrAvatarPose.neutral,
            poseAlpha,
          );
          _evaluateLocalLimbs(p, _clock + p.phaseOffset);
          p.needsGpuWrite = true;
        } else {
          p.needsGpuWrite = p.movedRootThisFrame;
        }
      } else {
        if (p.wasArticulated) {
          p.resetLocalToRest();
          p.wasArticulated = false;
          p.needsGpuWrite = true;
        } else {
          p.needsGpuWrite = p.movedRootThisFrame || p.wasCulled;
        }
      }
      p.wasCulled = false;
      p.wasArticulated = shouldArticulate;
    }

    _visiblePeerCount = visibleCount;
    _articulatedPeerCount = articulatedCount;

    if (!_gpuMounted) return;

    // 2. Mark which shape batches have at least one dirty peer, then upload in
    // a single `updateInstanceTransforms` call per shape (<= 3 total!).
    for (final shapeBatch in _shapeBatches.values) {
      shapeBatch.dirtyThisFrame = false;
    }
    for (var i = 0; i < _peerList.length; i++) {
      final p = _peerList[i];
      if (!p.needsGpuWrite) continue;
      for (var s = 0; s < p.slots.length; s++) {
        _shapeBatches[p.slots[s].part.shape]?.dirtyThisFrame = true;
      }
    }

    for (final entry in _shapeBatches.entries) {
      final shape = entry.key;
      final batch = entry.value;
      if (!batch.dirtyThisFrame) continue;
      batch.mesh.updateInstanceTransforms((transforms) {
        for (var i = 0; i < _peerList.length; i++) {
          final p = _peerList[i];
          if (!p.needsGpuWrite) continue;
          if (!p.currentlyVisible) {
            for (var s = 0; s < p.slots.length; s++) {
              final slot = p.slots[s];
              if (slot.part.shape == shape) {
                transforms[slot.instanceIndex].setFrom(_hiddenMatrix);
              }
            }
            continue;
          }
          _setRootMatrix(_rootScratch, p.renderX, p.renderY, p.renderZ, p.renderYaw);
          for (var s = 0; s < p.slots.length; s++) {
            final slot = p.slots[s];
            if (slot.part.shape != shape) continue;
            final out = transforms[slot.instanceIndex];
            out.setFrom(_rootScratch);
            out.multiply(slot.localMatrix);
          }
        }
      }, recomputeWinding: false);
      batch.node.markTransformDirty();
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    root.visible = false;
    for (final batch in _shapeBatches.values) {
      batch.mesh.clearInstances();
      batch.node.detach();
    }
    _shapeBatches.clear();
    _peers.clear();
    _peerList.clear();
    _articulationCandidates.clear();
    root.detach();
  }

  void _evaluateLocalLimbs(_PeerRecord peer, double t) {
    _motionScratch.prepare(
      time: t,
      heightMeters: peer.appearance.heightMeters,
      animateIdle: true,
      pose: peer.smoothedPose,
    );
    for (var i = 0; i < peer.slots.length; i++) {
      final slot = peer.slots[i];
      _motionScratch.transformPart(
        part: slot.part,
        outTransform: slot.localMatrix,
        scratchDelta: _deltaScratch,
      );
    }
  }

  void _rebuildInstanceSlots() {
    _slotsDirty = false;
    if (!_gpuMounted) return;
    for (final batch in _shapeBatches.values) {
      batch.mesh.clearInstances();
    }
    for (var i = 0; i < _peerList.length; i++) {
      final p = _peerList[i];
      _setRootMatrix(_rootScratch, p.renderX, p.renderY, p.renderZ, p.renderYaw);
      for (var s = 0; s < p.slots.length; s++) {
        final slot = p.slots[s];
        final batch = _shapeBatches[slot.part.shape]!;
        _deltaScratch.setFrom(_rootScratch);
        _deltaScratch.multiply(slot.localMatrix);
        slot.instanceIndex = batch.mesh.addInstance(
          p.currentlyVisible ? _deltaScratch : _hiddenMatrix,
          color: slot.color,
        );
      }
      p.needsGpuWrite = true;
      p.wasCulled = !p.currentlyVisible;
    }
    for (final batch in _shapeBatches.values) {
      batch.node.markTransformDirty();
    }
  }

  static void _setRootMatrix(
    vm.Matrix4 out,
    double x,
    double y,
    double z,
    double yaw,
  ) {
    final c = math.cos(yaw);
    final s = math.sin(yaw);
    final m = out.storage;
    m[0] = c;
    m[1] = 0.0;
    m[2] = -s;
    m[3] = 0.0;
    m[4] = 0.0;
    m[5] = 1.0;
    m[6] = 0.0;
    m[7] = 0.0;
    m[8] = s;
    m[9] = 0.0;
    m[10] = c;
    m[11] = 0.0;
    m[12] = x;
    m[13] = y;
    m[14] = z;
    m[15] = 1.0;
  }

  static double _distSq(double x1, double z1, double x2, double z2) {
    final dx = x2 - x1;
    final dz = z2 - z1;
    return dx * dx + dz * dz;
  }

  static double _angleDiff(double a, double b) {
    var d = (b - a) % (math.pi * 2);
    if (d > math.pi) d -= math.pi * 2;
    if (d < -math.pi) d += math.pi * 2;
    return d;
  }

  static double _lerpAngle(double from, double to, double t) =>
      from + _angleDiff(from, to) * t;

  static bool _isNewerSequence(int incoming, int current) {
    if (incoming == current) return true;
    final diff = (incoming - current) & 0xFFFF;
    return diff > 0 && diff < 32768;
  }
}

final class _ShapeBatch {
  _ShapeBatch({required this.node, required this.mesh});

  final fs.Node node;
  final fs.InstancedMesh mesh;
  bool dirtyThisFrame = false;
}

final class _PartSlot {
  _PartSlot({
    required this.part,
    required this.color,
  }) : localMatrix = part.transform.clone();

  final VrAvatarPart part;
  final vm.Vector4 color;
  final vm.Matrix4 localMatrix;
  int instanceIndex = -1;
}

final class _PeerRecord {
  _PeerRecord({
    required this.peerId,
    required VrAvatarAppearance appearance,
    required this.detail,
    required double x,
    required double y,
    required double z,
    required double yaw,
    required this.vx,
    required this.vz,
    required this.pose,
    required this.lastSequence,
    required this.phaseOffset,
  }) : _appearance = appearance,
       targetX = x,
       targetY = y,
       targetZ = z,
       targetYaw = yaw,
       renderX = x,
       renderY = y,
       renderZ = z,
       renderYaw = yaw,
       smoothedPose = pose ?? VrAvatarPose.neutral {
    _rebuildPlan();
  }

  final String peerId;
  final VrAvatarDetail detail;
  final double phaseOffset;
  VrAvatarAppearance _appearance;
  final List<_PartSlot> slots = [];

  double targetX;
  double targetY;
  double targetZ;
  double targetYaw;
  double vx;
  double vz;

  double renderX;
  double renderY;
  double renderZ;
  double renderYaw;

  VrAvatarPose? pose;
  VrAvatarPose smoothedPose;
  int? lastSequence;
  double ageSinceSnapshot = 0.0;
  double limbAccum = 1.0;
  double currentDistSq = 0.0;
  bool poseDirty = true;
  bool currentlyVisible = true;
  bool wasCulled = false;
  bool wasArticulated = false;
  bool needsGpuWrite = true;
  bool movedRootThisFrame = false;
  bool shouldArticulateThisFrame = false;

  VrAvatarAppearance get appearance => _appearance;

  void updateAppearance(VrAvatarAppearance next) {
    _appearance = next;
    _rebuildPlan();
  }

  void resetLocalToRest() {
    for (var i = 0; i < slots.length; i++) {
      slots[i].localMatrix.setFrom(slots[i].part.transform);
    }
  }

  void _rebuildPlan() {
    slots.clear();
    final plan = VrAvatarPlan.build(_appearance);
    final palette = _surfaceColorsFor(_appearance);
    final isHuman = _appearance.species == VrAvatarSpecies.human;
    final seed = _stableSeed(peerId, _appearance.bodyColorArgb);
    final skin = isHuman ? _humanSkinTone(seed) : null;
    final skinShade = skin == null
        ? null
        : vm.Vector4(skin.x * 0.80, skin.y * 0.74, skin.z * 0.72, 1.0);
    final hair = isHuman ? _humanHairTone(seed) : null;
    final trousers = isHuman ? _humanTrouserTone(seed) : null;
    final shoes = isHuman ? _humanShoeTone(seed) : null;

    for (final part in plan.partsFor(detail)) {
      // Skip flat pedestal contact-shadow discs in shared crowd batches to
      // avoid coplanar floor z-fighting and halve ground overdraw.
      if (part.surface == VrAvatarSurface.shadow) continue;
      final color = isHuman
          ? _resolveHumanPartColor(
              part: part,
              palette: palette,
              skin: skin!,
              skinShade: skinShade!,
              hair: hair!,
              trousers: trousers!,
              shoes: shoes!,
            )
          : palette[part.surface]!;
      slots.add(_PartSlot(part: part, color: color));
    }
  }

  static int _stableSeed(String id, int argb) {
    var h = argb ^ 0x517CC1B7;
    for (var i = 0; i < id.length; i++) {
      h = ((h * 31) ^ id.codeUnitAt(i)) & 0x7FFFFFFF;
    }
    return h;
  }

  static const _skinPalettesArgb = <int>[
    0xFFF0C9AE, // warm ivory
    0xFFE5B594, // natural peach-olive
    0xFFD49D76, // golden mediterranean tan
    0xFFBD8058, // warm caramel
    0xFF965E3D, // rich bronze
    0xFF6B412A, // deep warm umber
  ];

  static const _hairPalettesArgb = <int>[
    0xFF231B18, // natural raven espresso
    0xFF3E291D, // rich dark chestnut
    0xFF5A3724, // warm walnut brown
    0xFF6B3A26, // deep auburn
    0xFF8C6E4B, // warm dark honey-blonde
    0xFF6F767F, // architectural silver-slate
  ];

  static const _trouserPalettesArgb = <int>[
    0xFF282E36, // tailored charcoal
    0xFF243144, // deep architectural navy
    0xFF423D36, // warm dark taupe
    0xFF333D35, // muted slate olive
  ];

  static const _shoePalettesArgb = <int>[
    0xFF261E1A, // espresso leather
    0xFF1F242B, // matte obsidian sneaker
    0xFF3A2B22, // chestnut suede
  ];

  static vm.Vector4 _humanSkinTone(int seed) =>
      vrAvatarLinearArgb(_skinPalettesArgb[seed % _skinPalettesArgb.length]);

  static vm.Vector4 _humanHairTone(int seed) => vrAvatarLinearArgb(
    _hairPalettesArgb[(seed >> 3) % _hairPalettesArgb.length],
  );

  static vm.Vector4 _humanTrouserTone(int seed) => vrAvatarLinearArgb(
    _trouserPalettesArgb[(seed >> 6) % _trouserPalettesArgb.length],
  );

  static vm.Vector4 _humanShoeTone(int seed) => vrAvatarLinearArgb(
    _shoePalettesArgb[(seed >> 9) % _shoePalettesArgb.length],
  );

  static vm.Vector4 _resolveHumanPartColor({
    required VrAvatarPart part,
    required Map<VrAvatarSurface, vm.Vector4> palette,
    required vm.Vector4 skin,
    required vm.Vector4 skinShade,
    required vm.Vector4 hair,
    required vm.Vector4 trousers,
    required vm.Vector4 shoes,
  }) {
    final id = part.id;
    if (id == 'head' ||
        id == 'neck' ||
        id == 'nose' ||
        id == 'left_hand' ||
        id == 'right_hand' ||
        id.startsWith('ear_-') ||
        id.startsWith('ear_1')) {
      return skin;
    }
    if (id.startsWith('ear_inner_')) {
      return skinShade;
    }
    if (id == 'hair_cap' || id == 'hair_fringe' || id.startsWith('brow_')) {
      return hair;
    }
    if (id == 'pelvis' ||
        id.endsWith('_hip') ||
        id.endsWith('_leg')) {
      return trousers;
    }
    if (id.endsWith('_foot')) {
      return shoes;
    }
    return palette[part.surface]!;
  }

  static Map<VrAvatarSurface, vm.Vector4> _surfaceColorsFor(
    VrAvatarAppearance appearance,
  ) {
    final body = vrAvatarLinearArgb(appearance.bodyColorArgb);
    final accent = vrAvatarLinearArgb(appearance.accentColorArgb);
    final shade = vm.Vector4(
      body.x * .66 + .014 * .34,
      body.y * .66 + .026 * .34,
      body.z * .66 + .042 * .34,
      1,
    );
    return {
      VrAvatarSurface.body: body,
      VrAvatarSurface.shade: shade,
      VrAvatarSurface.accent: accent,
      VrAvatarSurface.ink: vm.Vector4(.012, .020, .034, 1),
      VrAvatarSurface.pearl: vm.Vector4(.93, .95, .93, 1),
      VrAvatarSurface.shadow: vm.Vector4(.018, .028, .034, 1),
    };
  }
}
