import 'dart:math' as math;

import 'package:flutter_scene/scene.dart' show Node;
import 'package:vector_math/vector_math.dart' show Vector3;

/// An axis-aligned region in the current local world frame, in meters.
///
/// Distance is measured to the closest point of the region, not its center:
/// a large tile stays active while the viewer is standing at either edge.
class VrSceneRegionBounds {
  VrSceneRegionBounds({
    required this.minX,
    required this.minY,
    required this.minZ,
    required this.maxX,
    required this.maxY,
    required this.maxZ,
  }) {
    if (![minX, minY, minZ, maxX, maxY, maxZ].every((v) => v.isFinite) ||
        minX > maxX ||
        minY > maxY ||
        minZ > maxZ) {
      throw ArgumentError('Region bounds must be finite and ordered.');
    }
  }

  final double minX, minY, minZ, maxX, maxY, maxZ;

  double distanceTo(Vector3 point) {
    if (!point.x.isFinite || !point.y.isFinite || !point.z.isFinite) {
      throw ArgumentError.value(point, 'point', 'Must be finite.');
    }
    final dx = math.max(math.max(minX - point.x, point.x - maxX), 0.0);
    final dy = math.max(math.max(minY - point.y, point.y - maxY), 0.0);
    final dz = math.max(math.max(minZ - point.z, point.z - maxZ), 0.0);
    final scale = math.max(dx, math.max(dy, dz));
    if (scale == 0 || !scale.isFinite) return scale;
    // Scale first so a finite far-away viewer cannot overflow the squares.
    return scale *
        math.sqrt(
          (dx / scale) * (dx / scale) +
              (dy / scale) * (dy / scale) +
              (dz / scale) * (dz / scale),
        );
  }
}

enum VrSceneRegionVisual { detail, proxy, none }

/// [keepResident] is a host retention hint, independent of drawing.
///
/// A hidden nearby region may stay decoded for a quick return. A false hint
/// allows its owner to release the region, while a persistent disk cache can
/// keep the downloaded bytes until its own byte/age budget requires eviction.
class VrSceneRegionDecision {
  const VrSceneRegionDecision({
    required this.visual,
    required this.keepResident,
  });

  static const inactive = VrSceneRegionDecision(
    visual: VrSceneRegionVisual.none,
    keepResident: false,
  );

  final VrSceneRegionVisual visual;
  final bool keepResident;
}

/// Distance-based detail and residency policy, independent of the renderer.
///
/// The exit margin prevents repeated mounting and LOD changes while hovering
/// around a boundary. Retention is not a network TTL or a disk-cache lifetime.
class VrSceneRegionPolicy {
  VrSceneRegionPolicy({
    this.detailDistance = 24,
    this.proxyDistance = 56,
    this.retentionDistance = 80,
    this.hysteresis = 3,
  }) {
    if (![
          detailDistance,
          proxyDistance,
          retentionDistance,
          hysteresis,
        ].every((v) => v.isFinite) ||
        detailDistance < 0 ||
        hysteresis < 0 ||
        proxyDistance < detailDistance + hysteresis ||
        retentionDistance < proxyDistance + hysteresis) {
      throw ArgumentError(
        'Distances must be finite, nonnegative, and ordered with room '
        'for hysteresis between detail, proxy, and retention.',
      );
    }
  }

  final double detailDistance;
  final double proxyDistance;
  final double retentionDistance;
  final double hysteresis;

  VrSceneRegionDecision select(
    double distance, {
    VrSceneRegionDecision previous = VrSceneRegionDecision.inactive,
  }) {
    if (distance.isNaN || distance < 0) {
      throw ArgumentError.value(distance, 'distance', 'Must be nonnegative.');
    }
    final keep =
        distance <=
        retentionDistance + (previous.keepResident ? hysteresis : 0);
    if (!keep) return VrSceneRegionDecision.inactive;
    if (distance <=
        detailDistance +
            (previous.visual == VrSceneRegionVisual.detail ? hysteresis : 0)) {
      return const VrSceneRegionDecision(
        visual: VrSceneRegionVisual.detail,
        keepResident: true,
      );
    }
    if (distance <=
        proxyDistance +
            (previous.visual != VrSceneRegionVisual.none ? hysteresis : 0)) {
      return const VrSceneRegionDecision(
        visual: VrSceneRegionVisual.proxy,
        keepResident: true,
      );
    }
    return const VrSceneRegionDecision(
      visual: VrSceneRegionVisual.none,
      keepResident: true,
    );
  }
}

/// Mounts a detailed or simplified region without changing gameplay state.
///
/// Both nodes must use the same local world frame as [bounds] and [parent].
/// Keep persistent entity state outside these render nodes. A proxy should be
/// a cheap mesh or authored impostor; this class does not capture screenshots.
/// If no proxy exists, detail is used throughout the proxy distance as well.
///
/// Native Flutter Scene frustum tests remain enabled and run per eye. Do not
/// disable a region merely because it is behind the center-eye direction:
/// it may still affect shadows, audio, collisions, or the other eye's view.
///
/// Unselected roots are detached, so their components are not ticked by the
/// scene. Detachment does not immediately free GPU memory. Once retention
/// ends, the host must drop this owner and release its resource-group claims;
/// shared geometry/materials must not be disposed while another region uses
/// them. Audio and authoritative simulation need their own interest policies.
class VrSceneRegion {
  VrSceneRegion({
    required this.parent,
    required this.bounds,
    required this.detail,
    this.proxy,
    VrSceneRegionPolicy? policy,
  }) : policy = policy ?? VrSceneRegionPolicy() {
    if (identical(parent, detail) ||
        identical(parent, proxy) ||
        identical(detail, proxy)) {
      throw ArgumentError('Parent, detail, and proxy must be distinct nodes.');
    }
    for (final root in [detail, if (proxy != null) proxy!]) {
      if (root.parent != null) {
        throw ArgumentError('Region roots must start detached.');
      }
      // A detached ancestor of parent would create a scene-graph cycle.
      for (
        Node? ancestor = parent;
        ancestor != null;
        ancestor = ancestor.parent
      ) {
        if (identical(root, ancestor)) {
          throw ArgumentError('A region cannot contain its own parent.');
        }
      }
    }
  }

  final Node parent;
  final VrSceneRegionBounds bounds;
  final Node detail;
  final Node? proxy;
  final VrSceneRegionPolicy policy;
  VrSceneRegionDecision _decision = VrSceneRegionDecision.inactive;
  Node? _mounted;
  bool _disposed = false;

  VrSceneRegionDecision get decision => _decision;
  Node? get mountedNode => _mounted;

  /// Call after updating the viewer's position in this local world frame.
  ///
  /// [enabled] suspends visual work while retaining the normal distance hint.
  VrSceneRegionDecision update(Vector3 viewer, {bool enabled = true}) {
    if (_disposed) throw StateError('The region was disposed.');
    final selected = policy.select(
      bounds.distanceTo(viewer),
      previous: _decision,
    );
    _decision = enabled
        ? selected
        : VrSceneRegionDecision(
            visual: VrSceneRegionVisual.none,
            keepResident: selected.keepResident,
          );
    final target = switch (_decision.visual) {
      VrSceneRegionVisual.detail => detail,
      VrSceneRegionVisual.proxy => proxy ?? detail,
      VrSceneRegionVisual.none => null,
    };
    if (!identical(_mounted, target)) {
      if (target?.parent != null) {
        throw StateError('A region root was mounted by another owner.');
      }
      _mounted?.detach();
      if (target != null) parent.add(target);
      _mounted = target;
    }
    return _decision;
  }

  /// Detaches visual roots; the host still owns shared assets and saved state.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _mounted?.detach();
    _mounted = null;
    _decision = VrSceneRegionDecision.inactive;
  }
}
