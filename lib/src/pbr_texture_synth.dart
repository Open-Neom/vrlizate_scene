import 'dart:math' as math;
import 'dart:typed_data';

/// Procedural, seamlessly tiling PBR texture sets — albedo, tangent-space
/// normal and metallic-roughness — generated in pure Dart.
///
/// Every surface is authored as a height field plus an albedo and a
/// roughness function over the unit tile. Noise is *periodic* (the lattice
/// wraps at the tile border) so the maps tile without seams at any repeat
/// count. The normal map is derived from the height field in the OpenGL
/// convention (+G toward the top image row), the same convention as the
/// ambientCG `NormalGL` maps the app already ships. The metallic-roughness
/// map follows glTF: roughness in G, metallic in B.
///
/// Pure and deterministic: `generate(request)` returns the same bytes for
/// the same request, so it is fully testable headless and safe to run in an
/// isolate (see `PbrTextureLibrary`).
enum PbrSurface {
  /// Running-bond bricks with mortar, per-brick tint and bevelled edges.
  bricks,

  /// Large irregular flagstones with chamfered joints.
  flagstones,

  /// Vertical wooden planks with grain and gaps.
  planks,

  /// Riveted metal panels with seams and scratches (metallic).
  metalPlates,

  /// Polished marble with turbulent veins.
  marble,

  /// Grass clumps: fine blades over low mounds.
  grass,

  /// Rocky terrain with craters: planets, asteroids, cave rock.
  rock,

  /// Fine woven carpet / seat fabric.
  fabric,

  /// Lightly troweled plaster or painted concrete.
  plaster,

  /// Loose sand with wind ripples.
  sand,
}

/// Everything a generator needs, in plain values so it crosses isolates.
class PbrTextureRequest {
  const PbrTextureRequest(
    this.surface, {
    this.size = 512,
    this.seed = 1,
    this.primary = 0xFFB0B0B0,
    this.secondary = 0xFF606060,
    this.repeats = 1,
    this.reliefStrength = 1.0,
  }) : assert(size >= 8 && size <= 2048),
       assert(repeats >= 1 && repeats <= 16);

  final PbrSurface surface;

  /// Square texture edge in pixels (power of two recommended).
  final int size;

  /// Noise seed; different seeds give different but equally tiling maps.
  final int seed;

  /// Dominant sRGB color (0xAARRGGBB).
  final int primary;

  /// Secondary sRGB color: mortar, veins, gaps, dark grains.
  final int secondary;

  /// How many pattern cells (brick courses, planks, stones) fit across one
  /// tile. Doubling it halves the apparent feature size for the same UV
  /// scale.
  final int repeats;

  /// Multiplier on the normal-map slope; 1 is the authored relief.
  final double reliefStrength;
}

/// The generated maps of one request. Pixels are RGBA8, row-major, straight
/// alpha, `size × size` each.
class PbrTextureSet {
  const PbrTextureSet({
    required this.size,
    required this.albedo,
    required this.normal,
    required this.metallicRoughness,
  });

  final int size;

  /// sRGB color.
  final Uint8List albedo;

  /// Tangent-space normal, OpenGL convention, `n * 0.5 + 0.5`.
  final Uint8List normal;

  /// glTF layout: R unused (255), G roughness, B metallic, A 255.
  final Uint8List metallicRoughness;
}

/// Pure generator. See [generate].
abstract final class PbrTextureSynth {
  /// Generates every map of [request]. CPU only; a 512² set takes tens of
  /// milliseconds, so callers run it through `compute` at runtime.
  static PbrTextureSet generate(PbrTextureRequest request) {
    final n = request.size;
    final field = _Field(n, request);
    switch (request.surface) {
      case PbrSurface.bricks:
        _bricks(field);
      case PbrSurface.flagstones:
        _flagstones(field);
      case PbrSurface.planks:
        _planks(field);
      case PbrSurface.metalPlates:
        _metalPlates(field);
      case PbrSurface.marble:
        _marble(field);
      case PbrSurface.grass:
        _grass(field);
      case PbrSurface.rock:
        _rock(field);
      case PbrSurface.fabric:
        _fabric(field);
      case PbrSurface.plaster:
        _plaster(field);
      case PbrSurface.sand:
        _sand(field);
    }
    return PbrTextureSet(
      size: n,
      albedo: field.albedoBytes(),
      normal: field.normalBytes(request.reliefStrength),
      metallicRoughness: field.metallicRoughnessBytes(),
    );
  }

  // ─── Surfaces ──────────────────────────────────────────────────────

  static void _bricks(_Field f) {
    final r = f.request;
    final courses = 4 * r.repeats; // rows per tile
    final columns = 2 * r.repeats; // bricks per row
    final brick = _Rgb.of(r.primary);
    final mortar = _Rgb.of(r.secondary);
    const mortarFraction = 0.10;
    f.each((u, v, px) {
      final row = (v * courses).floor();
      final rowV = v * courses - row;
      final offset = row.isOdd ? 0.5 : 0.0;
      final t = u * columns + offset;
      final col = t.floor() % columns;
      final cellU = t - t.floor();
      // Distance to the nearest mortar line, in cell units.
      final du = math.min(cellU, 1 - cellU);
      final dv = math.min(rowV, 1 - rowV);
      final inset = math.min(du, dv);
      final edge = mortarFraction / 2;
      final bevel = _smoothstep(edge, edge + 0.08, inset);
      final inMortar = inset < edge;
      final surface = f.fbm(u, v, octaves: 4, cells: 8 * r.repeats);
      final grain = f.fbm(u, v, octaves: 2, cells: 64 * r.repeats);
      final tint = 0.82 + 0.36 * f.hash(col + row * 131, row, 7);
      if (inMortar) {
        px.height = 0.15 + 0.10 * surface;
        px.albedo = mortar.scaled(0.9 + 0.2 * surface);
        px.roughness = 0.95;
      } else {
        px.height = 0.15 + 0.85 * bevel - 0.08 * surface + 0.03 * grain;
        px.albedo = brick.scaled(tint * (0.94 + 0.12 * grain));
        px.roughness = 0.82 + 0.12 * surface;
      }
    });
  }

  static void _flagstones(_Field f) {
    final r = f.request;
    final cells = 3 * r.repeats;
    final stone = _Rgb.of(r.primary);
    final joint = _Rgb.of(r.secondary);
    f.each((u, v, px) {
      // Jittered grid: each cell's corner moves by a hashed offset so the
      // joints wander; the jitter is periodic because the hash wraps.
      final cx = (u * cells).floor();
      final cy = (v * cells).floor();
      var best = double.infinity;
      var second = double.infinity;
      var owner = 0;
      for (var j = -1; j <= 1; j++) {
        for (var i = -1; i <= 1; i++) {
          final gx = cx + i;
          final gy = cy + j;
          final wx = ((gx % cells) + cells) % cells;
          final wy = ((gy % cells) + cells) % cells;
          final jx = gx + 0.25 + 0.5 * f.hash(wx, wy, 3);
          final jy = gy + 0.25 + 0.5 * f.hash(wx, wy, 5);
          final dx = u * cells - jx;
          final dy = v * cells - jy;
          final d = dx * dx + dy * dy;
          if (d < best) {
            second = best;
            best = d;
            owner = wx + wy * 977;
          } else if (d < second) {
            second = d;
          }
        }
      }
      // Distance to the cell boundary ≈ difference of the two nearest sites.
      final ridge = math.sqrt(second) - math.sqrt(best);
      final jointW = 0.06;
      final chamfer = _smoothstep(jointW, jointW + 0.12, ridge);
      final surface = f.fbm(u, v, octaves: 5, cells: 6 * r.repeats);
      final tint = 0.8 + 0.4 * f.hash(owner, 11, 13);
      if (ridge < jointW) {
        px.height = 0.05 + 0.08 * surface;
        px.albedo = joint.scaled(0.85 + 0.3 * surface);
        px.roughness = 0.95;
      } else {
        px.height = 0.05 + 0.9 * chamfer + 0.12 * (surface - 0.5);
        px.albedo = stone.scaled(tint * (0.9 + 0.2 * surface));
        px.roughness = 0.62 + 0.25 * surface;
      }
    });
  }

  static void _planks(_Field f) {
    final r = f.request;
    final planks = 4 * r.repeats;
    final wood = _Rgb.of(r.primary);
    final dark = _Rgb.of(r.secondary);
    f.each((u, v, px) {
      final p = (u * planks).floor();
      final pu = u * planks - p;
      final gap = 0.035;
      final inGap = pu < gap / 2 || pu > 1 - gap / 2;
      final phase = f.hash(p, 1, 17);
      // Grain: rings along the plank, warped by low-frequency noise.
      final warp = f.fbm(u, v, octaves: 3, cells: 3 * r.repeats);
      final rings =
          0.5 + 0.5 * math.sin((v * 22 + warp * 6 + phase * 40) * math.pi);
      final fibre = f.fbm(u * 1, v * 8, octaves: 3, cells: 12 * r.repeats);
      final ringMix = 0.35 * rings + 0.25 * fibre;
      final tint = 0.85 + 0.3 * phase;
      if (inGap) {
        px.height = 0.0;
        px.albedo = dark.scaled(0.6);
        px.roughness = 0.9;
      } else {
        px.height = 0.7 + 0.12 * (1 - rings) + 0.05 * fibre;
        px.albedo = _Rgb.lerp(wood, dark, ringMix * 0.7).scaled(tint);
        px.roughness = 0.55 + 0.2 * rings;
      }
    });
  }

  static void _metalPlates(_Field f) {
    final r = f.request;
    final panels = 2 * r.repeats;
    final metal = _Rgb.of(r.primary);
    final seamColor = _Rgb.of(r.secondary);
    f.each((u, v, px) {
      final pu = u * panels - (u * panels).floor();
      final pv = v * panels - (v * panels).floor();
      final seam = 0.03;
      final du = math.min(pu, 1 - pu);
      final dv = math.min(pv, 1 - pv);
      final inSeam = du < seam / 2 || dv < seam / 2;
      // Rivets inset from every panel corner.
      const rivetInset = 0.09;
      const rivetRadius = 0.028;
      var rivet = 0.0;
      for (final ru in [rivetInset, 1 - rivetInset]) {
        for (final rv in [rivetInset, 1 - rivetInset]) {
          final d = math.sqrt((pu - ru) * (pu - ru) + (pv - rv) * (pv - rv));
          if (d < rivetRadius) {
            final t = d / rivetRadius;
            rivet = math.max(rivet, math.sqrt(math.max(0, 1 - t * t)));
          }
        }
      }
      final wear = f.fbm(u, v, octaves: 4, cells: 5 * r.repeats);
      // Directional scratches: stretched noise.
      final scratch = f.fbm(u * 1, v * 0.08, octaves: 2, cells: 90 * r.repeats);
      final scratchMask = _smoothstep(0.62, 0.7, scratch);
      final panelId = (u * panels).floor() + (v * panels).floor() * 31;
      final tint = 0.92 + 0.16 * f.hash(panelId, 2, 23);
      if (inSeam) {
        px.height = 0.2;
        px.albedo = seamColor;
        px.roughness = 0.75;
        px.metallic = 1.0;
      } else {
        px.height =
            0.6 + 0.35 * rivet + 0.03 * (wear - 0.5) - 0.02 * scratchMask;
        px.albedo = metal.scaled(tint * (0.95 + 0.1 * wear));
        px.roughness = 0.32 + 0.25 * wear + 0.3 * scratchMask;
        px.metallic = 1.0;
      }
    });
  }

  static void _marble(_Field f) {
    final r = f.request;
    final base = _Rgb.of(r.primary);
    final vein = _Rgb.of(r.secondary);
    f.each((u, v, px) {
      final turb = f.fbm(u, v, octaves: 6, cells: 3 * r.repeats);
      // Integer half-period counts keep the vein wave periodic over the tile
      // (an odd multiple of π across u would leave a seam).
      final veinPhase =
          (u * 4 + v * 2) * math.pi * r.repeats + turb * 5 * math.pi;
      final veins = math.pow(0.5 + 0.5 * math.sin(veinPhase), 6).toDouble();
      final fine = f.fbm(u, v, octaves: 3, cells: 24 * r.repeats);
      final cloud = f.fbm(u, v, octaves: 4, cells: 2 * r.repeats);
      px.albedo = _Rgb.lerp(
        base.scaled(0.92 + 0.12 * cloud),
        vein,
        (veins * 0.85 + 0.1 * fine).clamp(0.0, 1.0),
      );
      px.height = 0.5 + 0.02 * fine - 0.03 * veins;
      px.roughness = 0.18 + 0.12 * veins + 0.05 * fine;
    });
  }

  static void _grass(_Field f) {
    final r = f.request;
    final green = _Rgb.of(r.primary);
    final dry = _Rgb.of(r.secondary);
    f.each((u, v, px) {
      final mounds = f.fbm(u, v, octaves: 3, cells: 4 * r.repeats);
      final clumps = f.fbm(u, v, octaves: 4, cells: 16 * r.repeats);
      final blades = f.fbm(u * 1, v * 3, octaves: 2, cells: 96 * r.repeats);
      final dryness = _smoothstep(0.55, 0.8, clumps);
      px.height = 0.3 + 0.3 * mounds + 0.25 * clumps + 0.15 * blades;
      px.albedo = _Rgb.lerp(green, dry, dryness).scaled(0.85 + 0.3 * blades);
      px.roughness = 0.9 + 0.1 * blades;
    });
  }

  static void _rock(_Field f) {
    final r = f.request;
    final light = _Rgb.of(r.primary);
    final dark = _Rgb.of(r.secondary);
    final craters = 6 * r.repeats;
    f.each((u, v, px) {
      final terrain = f.fbm(u, v, octaves: 6, cells: 4 * r.repeats);
      var h = terrain;
      // Craters: periodic set of rims with bowls.
      for (var i = 0; i < craters; i++) {
        final cx = f.hash(i, 41, 3);
        final cy = f.hash(i, 43, 5);
        final radius = 0.04 + 0.1 * f.hash(i, 47, 7);
        var dx = (u - cx).abs();
        var dy = (v - cy).abs();
        if (dx > 0.5) dx = 1 - dx;
        if (dy > 0.5) dy = 1 - dy;
        final d = math.sqrt(dx * dx + dy * dy) / radius;
        if (d < 1.3) {
          final bowl = d < 1 ? -(1 - d * d) * 0.35 : 0;
          final rim = math.exp(-((d - 1) * (d - 1)) / 0.02) * 0.18;
          h += bowl + rim;
        }
      }
      final grit = f.fbm(u, v, octaves: 2, cells: 48 * r.repeats);
      px.height = (h * 0.8 + 0.1 * grit).clamp(0.0, 1.0);
      px.albedo = _Rgb.lerp(dark, light, px.height).scaled(0.9 + 0.2 * grit);
      px.roughness = 0.85 + 0.15 * grit;
    });
  }

  static void _fabric(_Field f) {
    final r = f.request;
    final base = _Rgb.of(r.primary);
    final shade = _Rgb.of(r.secondary);
    final weave = 48 * r.repeats;
    f.each((u, v, px) {
      final warp = 0.5 + 0.5 * math.sin(u * weave * 2 * math.pi);
      final weft = 0.5 + 0.5 * math.sin(v * weave * 2 * math.pi);
      final over = ((u * weave).floor() + (v * weave).floor()).isEven;
      final thread = over ? warp * 0.7 + weft * 0.3 : weft * 0.7 + warp * 0.3;
      final fuzz = f.fbm(u, v, octaves: 3, cells: 20 * r.repeats);
      px.height = 0.4 + 0.4 * thread + 0.1 * fuzz;
      px.albedo = _Rgb.lerp(
        shade,
        base,
        0.6 + 0.4 * thread,
      ).scaled(0.9 + 0.2 * fuzz);
      px.roughness = 0.95;
    });
  }

  static void _plaster(_Field f) {
    final r = f.request;
    final base = _Rgb.of(r.primary);
    final stain = _Rgb.of(r.secondary);
    f.each((u, v, px) {
      final trowel = f.fbm(u, v, octaves: 4, cells: 3 * r.repeats);
      final fine = f.fbm(u, v, octaves: 3, cells: 40 * r.repeats);
      final staining = _smoothstep(0.6, 0.85, trowel);
      px.height = 0.5 + 0.06 * (trowel - 0.5) + 0.02 * (fine - 0.5);
      px.albedo = _Rgb.lerp(
        base,
        stain,
        staining * 0.5,
      ).scaled(0.95 + 0.08 * fine);
      px.roughness = 0.85 + 0.1 * fine;
    });
  }

  static void _sand(_Field f) {
    final r = f.request;
    final light = _Rgb.of(r.primary);
    final shade = _Rgb.of(r.secondary);
    f.each((u, v, px) {
      final warp = f.fbm(u, v, octaves: 3, cells: 2 * r.repeats);
      final ripplePhase =
          (v * 14 + u * 4) * math.pi * r.repeats + warp * 2.5 * math.pi;
      final ripples = 0.5 + 0.5 * math.sin(ripplePhase);
      final grains = f.fbm(u, v, octaves: 2, cells: 80 * r.repeats);
      px.height = 0.35 + 0.35 * ripples + 0.1 * grains + 0.1 * warp;
      px.albedo = _Rgb.lerp(
        shade,
        light,
        0.55 + 0.45 * ripples,
      ).scaled(0.95 + 0.1 * grains);
      px.roughness = 0.92 + 0.08 * grains;
    });
  }

  static double _smoothstep(double a, double b, double x) {
    final t = ((x - a) / (b - a)).clamp(0.0, 1.0);
    return t * t * (3 - 2 * t);
  }
}

/// One texel's authored values before encoding.
class _Texel {
  double height = 0.5;
  _Rgb albedo = const _Rgb(0.5, 0.5, 0.5);
  double roughness = 0.8;
  double metallic = 0.0;
}

/// The working buffers of one texture set plus periodic noise helpers.
class _Field {
  _Field(this.size, this.request)
    : _height = Float32List(size * size),
      _albedo = Uint8List(size * size * 4),
      _rough = Uint8List(size * size * 4);

  final int size;
  final PbrTextureRequest request;
  final Float32List _height;
  final Uint8List _albedo;
  final Uint8List _rough;

  void each(void Function(double u, double v, _Texel px) author) {
    final px = _Texel();
    for (var y = 0; y < size; y++) {
      final v = (y + 0.5) / size;
      for (var x = 0; x < size; x++) {
        final u = (x + 0.5) / size;
        px
          ..height = 0.5
          ..albedo = const _Rgb(0.5, 0.5, 0.5)
          ..roughness = 0.8
          ..metallic = 0.0;
        author(u, v, px);
        final i = y * size + x;
        _height[i] = px.height.clamp(0.0, 1.0);
        final o = i * 4;
        _albedo[o] = _byte(px.albedo.r);
        _albedo[o + 1] = _byte(px.albedo.g);
        _albedo[o + 2] = _byte(px.albedo.b);
        _albedo[o + 3] = 255;
        _rough[o] = 255;
        _rough[o + 1] = _byte(px.roughness);
        _rough[o + 2] = _byte(px.metallic);
        _rough[o + 3] = 255;
      }
    }
  }

  Uint8List albedoBytes() => _albedo;
  Uint8List metallicRoughnessBytes() => _rough;

  /// Central differences on the wrapped height field, OpenGL encoding.
  Uint8List normalBytes(double strength) {
    final out = Uint8List(size * size * 4);
    // Relief in texels: a full 0→1 step over one texel is a 45° slope at
    // strength 1 when the tile is 512 px, scaled so results match across
    // sizes.
    final k = strength * size / 512 * 2.2;
    for (var y = 0; y < size; y++) {
      final up = (y - 1 + size) % size;
      final down = (y + 1) % size;
      for (var x = 0; x < size; x++) {
        final left = (x - 1 + size) % size;
        final right = (x + 1) % size;
        final gx = _height[y * size + right] - _height[y * size + left];
        final gr = _height[down * size + x] - _height[up * size + x];
        var nx = -gx * k;
        var ny = gr * k; // +G points toward the top image row (GL).
        var nz = 1.0;
        final len = math.sqrt(nx * nx + ny * ny + nz * nz);
        nx /= len;
        ny /= len;
        nz /= len;
        final o = (y * size + x) * 4;
        out[o] = _byte(nx * 0.5 + 0.5);
        out[o + 1] = _byte(ny * 0.5 + 0.5);
        out[o + 2] = _byte(nz * 0.5 + 0.5);
        out[o + 3] = 255;
      }
    }
    return out;
  }

  /// Deterministic hash in [0, 1).
  double hash(int x, int y, int salt) {
    var h = x * 374761393 + y * 668265263 + (request.seed + salt) * 2147483647;
    h = (h ^ (h >> 13)) * 1274126177;
    h = h ^ (h >> 16);
    return (h & 0xFFFFFF) / 0x1000000;
  }

  /// Periodic value noise with [cells] lattice cells across the tile.
  double noise(double u, double v, int cells, int salt) {
    final x = u * cells;
    final y = v * cells;
    final x0 = x.floor();
    final y0 = y.floor();
    final fx = x - x0;
    final fy = y - y0;
    final sx = fx * fx * (3 - 2 * fx);
    final sy = fy * fy * (3 - 2 * fy);
    int wrap(int a) => ((a % cells) + cells) % cells;
    final a = hash(wrap(x0), wrap(y0), salt);
    final b = hash(wrap(x0 + 1), wrap(y0), salt);
    final c = hash(wrap(x0), wrap(y0 + 1), salt);
    final d = hash(wrap(x0 + 1), wrap(y0 + 1), salt);
    final top = a + (b - a) * sx;
    final bottom = c + (d - c) * sx;
    return top + (bottom - top) * sy;
  }

  /// Fractal sum of [octaves] periodic noises, normalized to [0, 1].
  double fbm(double u, double v, {required int octaves, required int cells}) {
    var sum = 0.0;
    var amplitude = 1.0;
    var total = 0.0;
    var c = cells;
    for (var i = 0; i < octaves; i++) {
      sum += amplitude * noise(u, v, c, 100 + i);
      total += amplitude;
      amplitude *= 0.5;
      c *= 2;
    }
    return sum / total;
  }

  static int _byte(double v) => (v.clamp(0.0, 1.0) * 255).round();
}

class _Rgb {
  const _Rgb(this.r, this.g, this.b);

  factory _Rgb.of(int argb) => _Rgb(
    ((argb >> 16) & 255) / 255,
    ((argb >> 8) & 255) / 255,
    (argb & 255) / 255,
  );

  final double r, g, b;

  _Rgb scaled(double k) => _Rgb(r * k, g * k, b * k);

  static _Rgb lerp(_Rgb a, _Rgb b, double t) =>
      _Rgb(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t);
}
