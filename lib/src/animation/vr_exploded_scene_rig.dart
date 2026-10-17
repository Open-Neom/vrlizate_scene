import 'dart:math' as math;

import 'package:flutter_scene/scene.dart' as fs;
import 'package:vector_math/vector_math.dart' as vm;
import 'package:vrlizate/vrlizate.dart' show VrCurves;

/// Descriptor for an inspectable 3D part inside a [VrExplodedSceneRig].
///
/// Adapted from Lemo-Opuscar `styles/hologram-hud/demo/engine/holo.js` and
/// `styles/teardown` (MIT License) for interactive VR museum/classroom inspection.
class VrExplodablePart {
  VrExplodablePart({
    required this.id,
    required this.node,
    required vm.Vector3 explodeVector,
    vm.Vector3? spinAxis,
    vm.Vector3? anchorOffset,
  }) : baseTransform = node.localTransform.clone(),
       explodeVector = explodeVector.clone(),
       spinAxis = (spinAxis ?? vm.Vector3(0, 1, 0)).normalized(),
       anchorOffset = anchorOffset?.clone() ?? vm.Vector3.zero();

  final String id;
  final fs.Node node;
  final vm.Matrix4 baseTransform;
  final vm.Vector3 explodeVector;
  final vm.Vector3 spinAxis;
  final vm.Vector3 anchorOffset;

  /// Base translation extracted from [baseTransform].
  vm.Vector3 get baseTranslation => baseTransform.getTranslation();
}

/// Interactive exploded-view, turntable, and scan-reveal controller for multi-part
/// `flutter_scene` 3D objects in VR classrooms (`neom_learning`) and museums (`neom_museum`).
class VrExplodedSceneRig {
  VrExplodedSceneRig({
    required this.root,
    required List<VrExplodablePart> parts,
  }) : _parts = List<VrExplodablePart>.unmodifiable(parts),
       _byId = {for (final p in parts) p.id: p};

  final fs.Node root;
  final List<VrExplodablePart> _parts;
  final Map<String, VrExplodablePart> _byId;

  double _globalExplode = 0.0;
  double _turntableSpin = 0.0;
  final Map<String, double> _partExplode = <String, double>{};
  final Map<String, double> _partSpin = <String, double>{};

  List<VrExplodablePart> get parts => _parts;
  double get globalExplode => _globalExplode;
  double get turntableSpin => _turntableSpin;

  VrExplodablePart? partById(String id) => _byId[id];

  /// Sets the uniform explosion factor (`0.0` = assembled, `1.0` = fully exploded)
  /// across all parts and updates their scene transforms.
  void setGlobalExplode(double factor) {
    _globalExplode = factor.clamp(0.0, 2.0);
    _apply();
  }

  /// Sets an individual part's explosion factor (`0.0..1.0`) and updates transforms.
  void setPartExplode(String partId, double factor) {
    if (!_byId.containsKey(partId)) return;
    _partExplode[partId] = factor.clamp(0.0, 2.0);
    _apply();
  }

  /// Sets an individual part's local spin angle (in radians) around its [VrExplodablePart.spinAxis].
  void setPartSpin(String partId, double radians) {
    if (!_byId.containsKey(partId)) return;
    _partSpin[partId] = radians;
    _apply();
  }

  /// Rotates the entire [root] around its Y axis like a holographic turntable.
  void setTurntableSpin(double radians) {
    _turntableSpin = radians;
    _apply();
  }

  /// Evaluates a vertical scan-reveal pass (`scanHeightY`) that hides parts above
  /// [scanHeightY] and pops visible parts in with a spring curve.
  void applyVerticalScan(double scanHeightY, {double bandMeters = 0.12}) {
    final band = math.max(0.001, bandMeters);
    for (final part in _parts) {
      final y = part.baseTranslation.y;
      if (y > scanHeightY + band) {
        part.node.visible = false;
        continue;
      }
      part.node.visible = true;
      final t = VrCurves.seg(scanHeightY, y - band, y + band);
      final scale = VrCurves.easeOutCubic(t).clamp(0.01, 1.0);
      _applyPartTransform(part, extraScale: scale);
    }
  }

  /// Resets all parts to their assembled base transforms and visibility.
  void reset() {
    _globalExplode = 0.0;
    _turntableSpin = 0.0;
    _partExplode.clear();
    _partSpin.clear();
    for (final part in _parts) {
      part.node.visible = true;
      part.node.localTransform = part.baseTransform.clone();
    }
    root.localTransform = vm.Matrix4.identity();
  }

  void _apply() {
    root.localTransform = vm.Matrix4.rotationY(_turntableSpin);
    for (final part in _parts) {
      _applyPartTransform(part);
    }
  }

  void _applyPartTransform(VrExplodablePart part, {double extraScale = 1.0}) {
    final explodeAmount = _partExplode[part.id] ?? _globalExplode;
    final spinAmount = _partSpin[part.id] ?? 0.0;
    final offset = part.explodeVector * explodeAmount;
    final basePos = part.baseTranslation;

    final m = vm.Matrix4.translationValues(
      basePos.x + offset.x,
      basePos.y + offset.y,
      basePos.z + offset.z,
    );
    if (spinAmount != 0.0) {
      final q = vm.Quaternion.axisAngle(part.spinAxis, spinAmount);
      m.multiply(vm.Matrix4.compose(vm.Vector3.zero(), q, vm.Vector3.all(1.0)));
    }
    if (extraScale != 1.0) {
      m.scaleByDouble(extraScale, extraScale, extraScale, 1.0);
    }
    // Preserve base rotation/scale relative to basePos
    final baseRelative = part.baseTransform.clone()
      ..setTranslation(vm.Vector3.zero());
    m.multiply(baseRelative);
    part.node.localTransform = m;
  }
}

/// Staggered pop-in growth schedule for world tiles, props, and room elements.
///
/// Adapted from Lemo-Opuscar `styles/lowpoly-island/demo/world.js` (MIT License).
class VrGrowthItem {
  VrGrowthItem({
    required this.id,
    required this.node,
    required this.startTime,
    this.duration = 0.45,
    this.dropDepthMeters = 0.35,
  }) : assert(duration > 0, 'Duration must be positive.'),
       baseTransform = node.localTransform.clone();

  final String id;
  final fs.Node node;
  final double startTime;
  final double duration;
  final double dropDepthMeters;
  final vm.Matrix4 baseTransform;
}

/// Evaluates elastic pop-in growth across a list of [VrGrowthItem] nodes at time `t`.
class VrGrowthSchedule {
  VrGrowthSchedule(List<VrGrowthItem> items)
    : _items = List<VrGrowthItem>.unmodifiable(items);

  final List<VrGrowthItem> _items;

  List<VrGrowthItem> get items => _items;

  /// Updates every item's visibility and transform for elapsed [timeSeconds].
  void evaluate(double timeSeconds) {
    for (final item in _items) {
      final u = VrCurves.seg(
        timeSeconds,
        item.startTime,
        item.startTime + item.duration,
      );
      if (u <= 0.0) {
        item.node.visible = false;
        continue;
      }
      item.node.visible = true;
      if (u >= 1.0) {
        item.node.localTransform = item.baseTransform.clone();
        continue;
      }
      final springVal = VrCurves.backOut(u, overshoot: 1.5);
      final scale = VrCurves.easeOutCubic(u).clamp(0.01, 1.0);
      final basePos = item.baseTransform.getTranslation();
      final yOffset = (1.0 - springVal) * -item.dropDepthMeters;

      final m = vm.Matrix4.translationValues(
        basePos.x,
        basePos.y + yOffset,
        basePos.z,
      )..scaleByDouble(scale, springVal.clamp(0.01, 1.35), scale, 1.0);
      final baseRotScale = item.baseTransform.clone()
        ..setTranslation(vm.Vector3.zero());
      m.multiply(baseRotScale);
      item.node.localTransform = m;
    }
  }
}
