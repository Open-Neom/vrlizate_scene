import 'dart:math' as math;

import 'package:vector_math/vector_math.dart' as vm;
import 'package:vrlizate_avatar/vrlizate_avatar.dart';

import 'vr_avatar_geometry.dart';

enum VrAvatarSurface { body, shade, accent, ink, pearl, shadow }

/// Localized idle-animation role evaluated in place on retained instance slots.
enum VrAvatarMotion {
  ground,
  body,
  head,
  leftArm,
  rightArm,
  leftFeature,
  rightFeature,
  crownFeature,
  tail,
  hoverCore,
}

/// One retained instance; its ID and batch stay stable during recolor/resize.
class VrAvatarPart {
  const VrAvatarPart({
    required this.id,
    required this.shape,
    required this.surface,
    required this.transform,
    required this.pivot,
    this.motion = VrAvatarMotion.body,
    this.nearOnly = false,
  });

  final String id;
  final VrAvatarShape shape;
  final VrAvatarSurface surface;
  final vm.Matrix4 transform;
  final vm.Vector3 pivot;
  final VrAvatarMotion motion;
  final bool nearOnly;
}

/// CPU-only authoring plan. Coordinates use meters, +Y up, +Z facing forward.
///
/// All shapes fit their unit bounds. The complete silhouette is fitted to the
/// requested height with its lowest point at y=0; enlarged ears/foliage are
/// included. Width/depth are capped for a shared 2.8 m presentation space.
/// [bounds] is conservative and includes all near-detail pieces.
class VrAvatarPlan {
  VrAvatarPlan._(this.parts, this.bounds, this.horizontalRadius);

  final List<VrAvatarPart> parts;
  final vm.Aabb3 bounds;
  final double horizontalRadius;

  Iterable<VrAvatarPart> partsFor(VrAvatarDetail detail) =>
      parts.where((part) => detail == VrAvatarDetail.near || !part.nearOnly);

  int triangleCount(VrAvatarDetail detail) =>
      partsFor(detail).length * (detail == VrAvatarDetail.near ? 224 : 48);

  int batchCount(VrAvatarDetail detail) =>
      partsFor(detail).map((part) => (part.shape, part.surface)).toSet().length;

  static VrAvatarPlan build(VrAvatarAppearance appearance) =>
      _AvatarAuthor(appearance).build();
}

class _AvatarAuthor {
  _AvatarAuthor(this.appearance);
  final VrAvatarAppearance appearance;
  final _parts = <VrAvatarPart>[];
  late final h = appearance.headScale;
  late final f = appearance.featureScale;
  late final species = appearance.species;
  static const round = VrAvatarShape.round;
  static const petal = VrAvatarShape.petal;
  static const box = VrAvatarShape.softBox;
  static const body = VrAvatarSurface.body;
  static const shade = VrAvatarSurface.shade;
  static const accent = VrAvatarSurface.accent;
  static const ink = VrAvatarSurface.ink;
  static const pearl = VrAvatarSurface.pearl;
  static const shadow = VrAvatarSurface.shadow;

  static final _waistPivot = vm.Vector3(0, .31, 0);

  void add(
    String id,
    VrAvatarShape shape,
    VrAvatarSurface surface,
    double x,
    double y,
    double z,
    double sx,
    double sy,
    double sz, {
    double roll = 0,
    double pitch = 0,
    double yaw = 0,
    bool head = false,
    bool nearOnly = false,
    VrAvatarMotion? motion,
    vm.Vector3? pivot,
  }) {
    var px = pivot?.x ?? x;
    var py = pivot?.y ?? y;
    var pz = pivot?.z ?? z;
    if (head) {
      x *= h;
      y = .77 + (y - .77) * h;
      z *= h;
      sx *= h;
      sy *= h;
      sz *= h;
      if (pivot != null) {
        px *= h;
        py = .77 + (py - .77) * h;
        pz *= h;
      } else {
        px = 0;
        py = .69;
        pz = 0;
      }
    }
    final transform = vm.Matrix4.translationValues(x, y, z);
    if (yaw != 0) transform.rotateY(yaw);
    if (pitch != 0) transform.rotateX(pitch);
    if (roll != 0) transform.rotateZ(roll);
    transform.multiply(vm.Matrix4.diagonal3Values(sx, sy, sz));
    _parts.add(
      VrAvatarPart(
        id: id,
        shape: shape,
        surface: surface,
        transform: transform,
        pivot: vm.Vector3(px, py, pz),
        motion: motion ?? (head ? VrAvatarMotion.head : VrAvatarMotion.body),
        nearOnly: nearOnly,
      ),
    );
  }

  /// Exact analytic +Z surface height of the avatar's front silhouette at (x, y).
  /// Accounts for both torso and the raised chest patch so conformal markings
  /// never clip into the chest mesh.
  double _frontZ(double x, double y) {
    if (species == VrAvatarSpecies.orb) {
      final r = .31 * h;
      final dy = y - .62;
      final rem = r * r - x * x - dy * dy;
      return rem > 0 ? math.sqrt(rem) : 0;
    }
    final rxT = species == VrAvatarSpecies.sprout ? .180 : .185;
    const ryT = .190;
    const rzT = .130;
    final dyT = y - .475;
    final uT = 1.0 - (x * x) / (rxT * rxT) - (dyT * dyT) / (ryT * ryT);
    var z = uT > 0 ? rzT * math.sqrt(uT) : 0.0;
    if (species != VrAvatarSpecies.sprout) {
      final dyC = y - .470;
      final uC = 1.0 - (x * x) / (.120 * .120) - (dyC * dyC) / (.130 * .130);
      if (uC > 0) {
        z = math.max(z, .105 + .035 * math.sqrt(uC));
      }
    }
    return z;
  }

  /// Places a thin surface-conforming marking at (x, y) on the outer front
  /// surface, orienting its local +Z axis along the outward normal of [_frontZ].
  void addSurfaceMark(
    String id,
    VrAvatarShape shape,
    VrAvatarSurface surface, {
    required double x,
    required double y,
    required double width,
    required double height,
    double thickness = .015,
    double normalOffset = .0055,
    double roll = 0,
    required VrAvatarMotion motion,
    required vm.Vector3 pivot,
  }) {
    final z0 = _frontZ(x, y);
    final dzdx = (_frontZ(x + .004, y) - _frontZ(x - .004, y)) / .008;
    final dzdy = (_frontZ(x, y + .004) - _frontZ(x, y - .004)) / .008;
    final nx = -dzdx;
    final ny = -dzdy;
    const nz = 1.0;
    final nLen = math.sqrt(nx * nx + ny * ny + nz * nz);
    final unitNx = nx / nLen;
    final unitNy = ny / nLen;
    final unitNz = nz / nLen;
    final pitch = -math.asin(unitNy.clamp(-1.0, 1.0));
    final yaw = math.atan2(unitNx, unitNz);
    add(
      id,
      shape,
      surface,
      x + unitNx * normalOffset,
      y + unitNy * normalOffset,
      z0 + unitNz * normalOffset,
      width,
      height,
      thickness,
      yaw: yaw,
      pitch: pitch,
      roll: roll,
      nearOnly: true,
      motion: motion,
      pivot: pivot,
    );
  }

  VrAvatarPlan build() {
    if (species == VrAvatarSpecies.orb) {
      _orb();
    } else {
      _body();
      switch (species) {
        case VrAvatarSpecies.human:
          _human();
        case VrAvatarSpecies.robot:
          _robot();
        case VrAvatarSpecies.fox:
          _fox();
        case VrAvatarSpecies.axolotl:
          _axolotl();
        case VrAvatarSpecies.sprout:
          _sprout();
        case VrAvatarSpecies.orb:
          break;
      }
      _face();
    }
    _pattern();
    final raw = _bounds(_parts);
    final scale = appearance.heightMeters / (raw.max.y - raw.min.y);
    final rawRadius =
        math.sqrt(
          math.pow(math.max(raw.min.x.abs(), raw.max.x.abs()), 2) +
              math.pow(math.max(raw.min.z.abs(), raw.max.z.abs()), 2),
        ) *
        scale;
    // Fit the complete yaw envelope, including an asymmetric fox tail.
    final horizontal = math.min(1.0, 1.4 / rawRadius);
    final sxz = scale * horizontal;
    final fit = vm.Matrix4.diagonal3Values(sxz, scale, sxz)
      ..multiply(vm.Matrix4.translationValues(0, -raw.min.y, 0));
    final fitted = List<VrAvatarPart>.unmodifiable([
      for (final part in _parts)
        VrAvatarPart(
          id: part.id,
          shape: part.shape,
          surface: part.surface,
          transform: fit * part.transform,
          pivot: vm.Vector3(
            part.pivot.x * sxz,
            (part.pivot.y - raw.min.y) * scale,
            part.pivot.z * sxz,
          ),
          motion: part.motion,
          nearOnly: part.nearOnly,
        ),
    ]);
    final bounds = _bounds(fitted);
    final radius = math.sqrt(
      math.pow(math.max(bounds.min.x.abs(), bounds.max.x.abs()), 2) +
          math.pow(math.max(bounds.min.z.abs(), bounds.max.z.abs()), 2),
    );
    return VrAvatarPlan._(fitted, bounds, radius);
  }

  void _groundContact({bool orb = false}) {
    // Broad soft ambient-occlusion pool flush with y = 0 on the pedestal.
    add(
      'ground_shadow',
      round,
      shadow,
      0,
      .003,
      orb ? 0 : .018,
      orb ? .44 : .48,
      .006,
      orb ? .44 : .38,
      motion: VrAvatarMotion.ground,
      pivot: vm.Vector3.zero(),
    );
  }

  void _body() {
    _groundContact();
    final robot = species == VrAvatarSpecies.robot;
    final plant = species == VrAvatarSpecies.sprout;
    final mainShape = robot ? box : round;

    // Torso with integrated pelvis and collar transitions so limbs connect.
    add(
      'torso',
      mainShape,
      body,
      0,
      .475,
      0,
      plant ? .36 : .37,
      .38,
      .26,
      motion: VrAvatarMotion.body,
      pivot: _waistPivot,
    );
    add(
      'pelvis',
      mainShape,
      shade,
      0,
      .31,
      -.004,
      .295,
      .14,
      .22,
      motion: VrAvatarMotion.body,
      pivot: _waistPivot,
    );
    add(
      'collar',
      mainShape,
      shade,
      0,
      .635,
      .005,
      .245,
      .075,
      .195,
      motion: VrAvatarMotion.body,
      pivot: _waistPivot,
    );
    if (!plant) {
      add(
        'chest',
        round,
        accent,
        0,
        .47,
        .105,
        .24,
        .26,
        .07,
        motion: VrAvatarMotion.body,
        pivot: _waistPivot,
      );
    }
    for (final side in [-1.0, 1.0]) {
      final tag = side < 0 ? 'left' : 'right';
      final armPivot = vm.Vector3(side * .172, .58, 0);
      final armMotion = side < 0
          ? VrAvatarMotion.leftArm
          : VrAvatarMotion.rightArm;

      add(
        '${tag}_hip',
        round,
        shade,
        side * .096,
        .27,
        0,
        .132,
        .105,
        .136,
        nearOnly: true,
        motion: VrAvatarMotion.ground,
        pivot: vm.Vector3(side * .096, .27, 0),
      );
      add(
        '${tag}_leg',
        mainShape,
        body,
        side * .096,
        .172,
        0,
        .126,
        .268,
        .136,
        motion: VrAvatarMotion.ground,
        pivot: vm.Vector3(side * .096, .172, 0),
      );
      add(
        '${tag}_foot',
        round,
        plant ? shade : accent,
        side * .096,
        .048,
        .038,
        .156,
        .096,
        .23,
        motion: VrAvatarMotion.ground,
        pivot: vm.Vector3(side * .096, 0, .038),
      );
      if (plant) {
        add(
          '${tag}_shoulder_bud',
          round,
          shade,
          side * .142,
          .515,
          .01,
          .072,
          .072,
          .072,
          nearOnly: true,
          motion: armMotion,
          pivot: armPivot,
        );
        add(
          '${tag}_arm_leaf',
          petal,
          side < 0 ? body : accent,
          side * (.195 + .038 * f),
          .495,
          .015,
          .175 * f,
          .34 * f,
          .065 * f,
          roll: -side * .64,
          yaw: side * .16,
          motion: armMotion,
          pivot: armPivot,
        );
      } else {
        // Sloped shoulder cap bridges upper torso and arm without any air gap.
        add(
          '${tag}_shoulder_cap',
          mainShape,
          shade,
          side * .172,
          .582,
          .004,
          .122,
          .108,
          .124,
          roll: -side * .28,
          motion: armMotion,
          pivot: armPivot,
        );
        add(
          '${tag}_arm',
          mainShape,
          body,
          side * .212,
          .462,
          .012,
          .112,
          .295,
          .122,
          roll: side * .13,
          pitch: -.05,
          motion: armMotion,
          pivot: armPivot,
        );
        add(
          '${tag}_hand',
          round,
          accent,
          side * .234,
          .318,
          .024,
          .116,
          .112,
          .12,
          motion: armMotion,
          pivot: armPivot,
        );
        if (robot) {
          add(
            '${tag}_shoulder',
            round,
            ink,
            side * .195,
            .575,
            0,
            .095,
            .095,
            .11,
            motion: armMotion,
            pivot: armPivot,
          );
          add(
            '${tag}_knee',
            round,
            ink,
            side * .096,
            .165,
            .062,
            .068,
            .068,
            .042,
            motion: VrAvatarMotion.ground,
            pivot: vm.Vector3(side * .096, .165, .062),
          );
        }
      }
    }
    add(
      'neck',
      round,
      body,
      0,
      .67,
      0,
      .128,
      .105,
      .132,
      motion: VrAvatarMotion.body,
      pivot: _waistPivot,
    );
  }

  void _human() {
    add('head', round, body, 0, .80, .005, .36, .36, .315, head: true);
    add(
      'hair_cap',
      round,
      ink,
      0,
      .905,
      -.012,
      .375,
      .18,
      .335,
      pitch: -.08,
      head: true,
    );
    add(
      'hair_fringe',
      petal,
      ink,
      .015,
      .915,
      .122,
      .26,
      .085,
      .12,
      pitch: .36,
      roll: -.12,
      head: true,
      nearOnly: true,
    );
    for (final side in [-1.0, 1.0]) {
      add(
        'brow_$side',
        box,
        ink,
        side * .085,
        .852,
        .152,
        .054,
        .015,
        .02,
        roll: -side * .08,
        head: true,
        nearOnly: true,
      );
      add(
        'ear_$side',
        round,
        accent,
        side * (.174 + .012 * f),
        .795,
        0,
        .062 * f,
        .115 * f,
        .082 * f,
        head: true,
      );
      add(
        'ear_inner_$side',
        round,
        shade,
        side * (.178 + .012 * f),
        .795,
        .008,
        .034 * f,
        .068 * f,
        .042 * f,
        head: true,
        nearOnly: true,
      );
    }
    add('nose', round, accent, 0, .782, .165, .054, .064, .056, head: true);
  }

  void _robot() {
    final antennaPivot = vm.Vector3(0, .94, 0);
    add('head', box, body, 0, .80, 0, .39, .31, .30, head: true);
    add(
      'visor_bezel',
      box,
      shade,
      0,
      .81,
      .134,
      .335,
      .17,
      .048,
      head: true,
      nearOnly: true,
    );
    add('visor', box, ink, 0, .81, .142, .31, .148, .045, head: true);
    add(
      'antenna_base',
      box,
      shade,
      0,
      .952,
      0,
      .085,
      .036,
      .085,
      head: true,
      nearOnly: true,
    );
    add(
      'antenna_stem',
      round,
      ink,
      0,
      .955 + .035 * f,
      0,
      .026,
      .09 * f,
      .026,
      head: true,
      motion: VrAvatarMotion.crownFeature,
      pivot: antennaPivot,
    );
    add(
      'antenna_light',
      round,
      accent,
      0,
      .955 + .085 * f,
      0,
      .066 * f,
      .066 * f,
      .066 * f,
      head: true,
      motion: VrAvatarMotion.crownFeature,
      pivot: antennaPivot,
    );
    add(
      'chest_light',
      box,
      pearl,
      0,
      .49,
      .142,
      .105,
      .044,
      .022,
      motion: VrAvatarMotion.body,
      pivot: _waistPivot,
    );
  }

  void _fox() {
    add('head', round, body, 0, .79, .015, .43, .32, .33, head: true);
    for (final side in [-1.0, 1.0]) {
      final earPivot = vm.Vector3(side * .135, .91, -.005);
      final earMotion = side < 0
          ? VrAvatarMotion.leftFeature
          : VrAvatarMotion.rightFeature;
      add(
        'ear_base_$side',
        round,
        shade,
        side * .142,
        .915,
        -.008,
        .105,
        .068,
        .088,
        roll: -side * .18,
        head: true,
        nearOnly: true,
        motion: earMotion,
        pivot: earPivot,
      );
      add(
        'ear_$side',
        petal,
        body,
        side * .145,
        .91 + .055 * f,
        -.005,
        .185 * f,
        .285 * f,
        .125 * f,
        head: true,
        roll: -side * .16,
        motion: earMotion,
        pivot: earPivot,
      );
      add(
        'inner_ear_$side',
        petal,
        accent,
        side * .145,
        .915 + .055 * f,
        .048 * f,
        .10 * f,
        .19 * f,
        .035 * f,
        head: true,
        roll: -side * .16,
        motion: earMotion,
        pivot: earPivot,
      );
      add(
        'muzzle_$side',
        round,
        pearl,
        side * .066,
        .738,
        .158,
        .185,
        .126,
        .165,
        head: true,
        roll: side * .22,
      );
      add(
        'cheek_$side',
        petal,
        accent,
        side * .188,
        .742,
        .055,
        .108,
        .195,
        .088,
        head: true,
        roll: side * .88,
      );
    }
    // Sculpted central snout bridge unites the muzzle cheeks into a true snout.
    add(
      'snout_bridge',
      round,
      pearl,
      0,
      .748,
      .176,
      .138,
      .096,
      .135,
      head: true,
    );
    add('nose', round, ink, 0, .762, .242, .058, .044, .042, head: true);
    final tailPivot = vm.Vector3(.08, .33, -.12);
    add(
      'tail_base',
      round,
      shade,
      .15,
      .34,
      -.15,
      .21 * f,
      .22 * f,
      .22 * f,
      roll: -.38,
      motion: VrAvatarMotion.tail,
      pivot: tailPivot,
    );
    add(
      'tail',
      petal,
      body,
      .28,
      .45,
      -.22,
      .27 * f,
      .50 * f,
      .24 * f,
      roll: -.54,
      motion: VrAvatarMotion.tail,
      pivot: tailPivot,
    );
    add(
      'tail_tip',
      petal,
      pearl,
      .39,
      .64,
      -.22,
      .185 * f,
      .265 * f,
      .175 * f,
      roll: -.54,
      motion: VrAvatarMotion.tail,
      pivot: tailPivot,
    );
  }

  void _axolotl() {
    add('head', round, body, 0, .80, .015, .47, .30, .33, head: true);
    for (final side in [-1.0, 1.0]) {
      final gillPivot = vm.Vector3(side * .205, .80, -.012);
      final gillMotion = side < 0
          ? VrAvatarMotion.leftFeature
          : VrAvatarMotion.rightFeature;
      add(
        'gill_root_$side',
        round,
        shade,
        side * .21,
        .80,
        -.012,
        .075,
        .135,
        .082,
        head: true,
        nearOnly: true,
        motion: gillMotion,
        pivot: gillPivot,
      );
      for (var index = 0; index < 3; index++) {
        final angle = (index - 1) * .62;
        final anchorX = side * .212;
        final centerX = anchorX + side * .088 * f * math.cos(angle);
        final centerY = .80 + .115 * f * math.sin(angle);
        add(
          'gill_${side}_$index',
          petal,
          accent,
          centerX,
          centerY,
          -.015,
          .088 * f,
          .275 * f,
          .082 * f,
          head: true,
          roll: -side * (math.pi / 2 - angle),
          motion: gillMotion,
          pivot: gillPivot,
        );
        add(
          'gill_tip_${side}_$index',
          petal,
          pearl,
          centerX + side * .068 * f * math.cos(angle),
          centerY + .068 * f * math.sin(angle),
          .006,
          .054 * f,
          .155 * f,
          .038 * f,
          head: true,
          roll: -side * (.52 - angle),
          nearOnly: true,
          motion: gillMotion,
          pivot: gillPivot,
        );
      }
      add(
        'cheek_$side',
        round,
        accent,
        side * .152,
        .752,
        .158,
        .086,
        .044,
        .025,
        head: true,
      );
    }
    final tailPivot = vm.Vector3(0, .31, -.13);
    add(
      'tail_base',
      round,
      shade,
      0,
      .305,
      -.14,
      .145,
      .135,
      .145,
      nearOnly: true,
      motion: VrAvatarMotion.tail,
      pivot: tailPivot,
    );
    add(
      'tail',
      petal,
      body,
      0,
      .31,
      -.245,
      .138 * f,
      .42 * f,
      .128 * f,
      pitch: .95,
      motion: VrAvatarMotion.tail,
      pivot: tailPivot,
    );
    add(
      'tail_fin',
      petal,
      accent,
      0,
      .365,
      -.305,
      .038 * f,
      .415 * f,
      .195 * f,
      pitch: .95,
      motion: VrAvatarMotion.tail,
      pivot: tailPivot,
    );
  }

  void _sprout() {
    final crownPivot = vm.Vector3(0, .95, 0);
    add('head', round, body, 0, .80, .015, .39, .35, .32, head: true);
    // Botanical calyx cup joins the stem and crown leaves cleanly to the head.
    add(
      'crown_calyx',
      round,
      shade,
      0,
      .955,
      -.005,
      .135,
      .065,
      .135,
      head: true,
      motion: VrAvatarMotion.crownFeature,
      pivot: crownPivot,
    );
    add(
      'stem',
      round,
      shade,
      0,
      .965 + .025 * f,
      0,
      .042,
      .12 * f,
      .042,
      head: true,
      motion: VrAvatarMotion.crownFeature,
      pivot: crownPivot,
    );
    for (final side in [-1.0, 1.0]) {
      add(
        'crown_leaf_$side',
        petal,
        accent,
        side * .085 * f,
        .99 + .065 * f,
        0,
        .188 * f,
        .295 * f,
        .064 * f,
        head: true,
        roll: -side * .64,
        motion: VrAvatarMotion.crownFeature,
        pivot: crownPivot,
      );
      add(
        'leaf_vein_$side',
        petal,
        pearl,
        side * .085 * f,
        .99 + .065 * f,
        .034 * f,
        .018 * f,
        .215 * f,
        .01 * f,
        head: true,
        roll: -side * .64,
        nearOnly: true,
        motion: VrAvatarMotion.crownFeature,
        pivot: crownPivot,
      );
      add(
        'collar_sepal_$side',
        petal,
        shade,
        side * .092,
        .64,
        .042,
        .095,
        .11,
        .045,
        roll: -side * .92,
        pitch: .38,
        nearOnly: true,
        motion: VrAvatarMotion.body,
        pivot: _waistPivot,
      );
    }
    add(
      'crown_leaf_center',
      petal,
      body,
      0,
      1.005 + .08 * f,
      -.024,
      .13 * f,
      .315 * f,
      .068 * f,
      head: true,
      pitch: -.2,
      motion: VrAvatarMotion.crownFeature,
      pivot: crownPivot,
    );
  }

  void _face() {
    final robot = species == VrAvatarSpecies.robot;
    for (final side in [-1.0, 1.0]) {
      add(
        'eye_$side',
        round,
        robot ? accent : ink,
        side * .088,
        .815,
        .168,
        .044,
        robot ? .04 : .056,
        .028,
        head: true,
      );
      add(
        'eye_glint_$side',
        round,
        pearl,
        side * .088 - .008,
        .827,
        .184,
        .013,
        .016,
        .009,
        head: true,
        nearOnly: true,
      );
    }
    if (species != VrAvatarSpecies.fox) {
      add(
        'smile_left',
        round,
        ink,
        -.018,
        .728,
        .155,
        .046,
        .015,
        .018,
        head: true,
        roll: -.16,
      );
      add(
        'smile_right',
        round,
        ink,
        .018,
        .728,
        .155,
        .046,
        .015,
        .018,
        head: true,
        roll: .16,
      );
    }
  }

  void _orb() {
    _groundContact(orb: true);
    final corePivot = vm.Vector3(0, .62, 0);
    add(
      'core',
      round,
      body,
      0,
      .62,
      0,
      .62 * h,
      .62 * h,
      .62 * h,
      motion: VrAvatarMotion.hoverCore,
      pivot: corePivot,
    );
    add(
      'equator_ring',
      round,
      shade,
      0,
      .61,
      0,
      .648 * h,
      .095 * h,
      .642 * h,
      pitch: .08,
      motion: VrAvatarMotion.hoverCore,
      pivot: corePivot,
    );
    add(
      'visor_bezel',
      box,
      shade,
      0,
      .63,
      .278 * h,
      .435 * h,
      .152 * h,
      .058 * h,
      nearOnly: true,
      motion: VrAvatarMotion.hoverCore,
      pivot: corePivot,
    );
    add(
      'visor',
      box,
      ink,
      0,
      .63,
      .29 * h,
      .41 * h,
      .13 * h,
      .055 * h,
      motion: VrAvatarMotion.hoverCore,
      pivot: corePivot,
    );
    for (final side in [-1.0, 1.0]) {
      final finPivot = vm.Vector3(side * .29 * h, .61, 0);
      add(
        'eye_$side',
        round,
        accent,
        side * .10 * h,
        .64,
        .325 * h,
        .052 * h,
        .045 * h,
        .025 * h,
        motion: VrAvatarMotion.hoverCore,
        pivot: corePivot,
      );
      add(
        'orbit_fin_$side',
        petal,
        accent,
        side * (.30 + .055 * f),
        .61,
        0,
        .14 * f,
        .36 * f,
        .12 * f,
        roll: -side * 1.3,
        motion: side < 0
            ? VrAvatarMotion.leftFeature
            : VrAvatarMotion.rightFeature,
        pivot: finPivot,
      );
    }
    add(
      'hover_stem',
      petal,
      accent,
      0,
      .16,
      0,
      .095,
      .32,
      .095,
      motion: VrAvatarMotion.ground,
      pivot: vm.Vector3(0, .16, 0),
    );
    add(
      'hover_collar',
      round,
      shade,
      0,
      .315,
      0,
      .165,
      .045,
      .165,
      nearOnly: true,
      motion: VrAvatarMotion.hoverCore,
      pivot: corePivot,
    );
    add(
      'hover_pearl',
      round,
      pearl,
      0,
      .34,
      0,
      .075,
      .075,
      .075,
      motion: VrAvatarMotion.hoverCore,
      pivot: corePivot,
    );
    add(
      'crown_glint',
      round,
      pearl,
      -.11 * h,
      .80,
      .22 * h,
      .14 * h,
      .065 * h,
      .03 * h,
      nearOnly: true,
      motion: VrAvatarMotion.hoverCore,
      pivot: corePivot,
    );
  }

  void _pattern() {
    if (appearance.pattern == VrAvatarPattern.solid) return;
    final orb = species == VrAvatarSpecies.orb;
    final motion = orb ? VrAvatarMotion.hoverCore : VrAvatarMotion.body;
    final pivot = orb ? vm.Vector3(0, .62, 0) : _waistPivot;
    final thickness = orb ? .012 : .015;
    final offset = orb ? .0045 : .0055;

    if (appearance.pattern == VrAvatarPattern.spots) {
      final spots = orb
          ? <(double, double, double)>[
              (-.11 * h, .52, .054 * h),
              (.11 * h, .52, .054 * h),
              (0.0, .48, .058 * h),
              (-.09 * h, .44, .048 * h),
              (.09 * h, .44, .048 * h),
            ]
          : const <(double, double, double)>[
              (-.064, .522, .054),
              (.064, .512, .052),
              (-.012, .465, .058),
              (.062, .418, .050),
              (-.064, .412, .050),
            ];
      for (var i = 0; i < spots.length; i++) {
        final (x, y, size) = spots[i];
        addSurfaceMark(
          'spot_$i',
          round,
          i.isEven ? shade : pearl,
          x: x,
          y: y,
          width: size,
          height: size,
          thickness: thickness,
          normalOffset: offset,
          motion: motion,
          pivot: pivot,
        );
      }
    } else {
      for (var i = 0; i < 3; i++) {
        final y = orb ? (.52 - i * .045) : (.520 - i * .052);
        final width = orb
            ? (i == 1 ? .17 * h : .145 * h)
            : (i == 1 ? .148 : .132);
        addSurfaceMark(
          'stripe_$i',
          round,
          i == 1 ? pearl : shade,
          x: 0,
          y: y,
          width: width,
          height: .025,
          thickness: thickness,
          normalOffset: offset,
          motion: motion,
          pivot: pivot,
        );
      }
      for (final side in [-1.0, 1.0]) {
        addSurfaceMark(
          'stripe_flank_$side',
          round,
          pearl,
          x: side * (orb ? .15 * h : .116),
          y: orb ? .49 : .468,
          width: orb ? .095 * h : .086,
          height: .024,
          thickness: thickness,
          normalOffset: offset,
          roll: -side * .14,
          motion: motion,
          pivot: pivot,
        );
      }
    }
  }
}

vm.Aabb3 _bounds(Iterable<VrAvatarPart> parts) {
  final bounds = vm.Aabb3.minMax(
    vm.Vector3.all(double.infinity),
    vm.Vector3.all(double.negativeInfinity),
  );
  for (final part in parts) {
    // Bounding corners deliberately overestimate curved surfaces and remain
    // valid when a host swaps near/far meshes or rotates ears and leaves.
    for (final x in [-.5, .5]) {
      for (final y in [-.5, .5]) {
        for (final z in [-.5, .5]) {
          bounds.hullPoint(part.transform.transformed3(vm.Vector3(x, y, z)));
        }
      }
    }
  }
  return bounds;
}

