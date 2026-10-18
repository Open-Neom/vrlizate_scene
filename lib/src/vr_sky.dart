import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// Skies for the native demos: a visible background plus matching
/// image-based lighting, so a scene is no longer lit by the engine's studio
/// map under a black void.
///
/// Gradient skies follow Riviera's proven recipe: one `GradientSkySource`
/// drives both `Scene.skybox` and a `SkyEnvironment` baked once at 64 px.
/// The star sky is an equirect image synthesized in an isolate and uploaded
/// as the environment itself (`EnvironmentSkySource` shows the same map).
abstract final class VrSky {
  /// Clear midday: deep blue zenith, pale horizon, warm high sun.
  static GradientSkySource day({vm.Vector3? sunDirection}) => GradientSkySource(
    zenithColor: vm.Vector3(0.05, 0.22, 0.55),
    horizonColor: vm.Vector3(0.62, 0.78, 0.86),
    groundColor: vm.Vector3(0.14, 0.13, 0.10),
    sunDirection: sunDirection ?? vm.Vector3(0.45, 0.7, -0.35),
    sunColor: vm.Vector3(3.2, 2.9, 2.4),
  );

  /// Hazy desert noon: bleached zenith, sand-colored horizon.
  static GradientSkySource desert({vm.Vector3? sunDirection}) =>
      GradientSkySource(
        zenithColor: vm.Vector3(0.22, 0.42, 0.68),
        horizonColor: vm.Vector3(0.86, 0.78, 0.60),
        groundColor: vm.Vector3(0.36, 0.28, 0.16),
        sunDirection: sunDirection ?? vm.Vector3(0.2, 0.85, -0.3),
        sunColor: vm.Vector3(3.6, 3.3, 2.8),
        sunSharpness: 300,
      );

  /// Overcast arctic day: cold, low-contrast, sun a bright smear.
  static GradientSkySource tundra({vm.Vector3? sunDirection}) =>
      GradientSkySource(
        zenithColor: vm.Vector3(0.42, 0.52, 0.66),
        horizonColor: vm.Vector3(0.80, 0.86, 0.92),
        groundColor: vm.Vector3(0.62, 0.66, 0.72),
        sunDirection: sunDirection ?? vm.Vector3(0.5, 0.35, -0.6),
        sunColor: vm.Vector3(1.8, 1.8, 1.9),
        sunSharpness: 40,
      );

  /// Sunset: orange horizon under a violet zenith, low warm sun.
  static GradientSkySource dusk({vm.Vector3? sunDirection}) =>
      GradientSkySource(
        zenithColor: vm.Vector3(0.10, 0.08, 0.28),
        horizonColor: vm.Vector3(0.90, 0.45, 0.22),
        groundColor: vm.Vector3(0.10, 0.07, 0.06),
        sunDirection: sunDirection ?? vm.Vector3(-0.6, 0.12, -0.5),
        sunColor: vm.Vector3(4.0, 1.8, 0.8),
        sunSharpness: 250,
      );

  /// Moonlit night: near-black zenith, faint blue horizon, cool moon.
  static GradientSkySource night({vm.Vector3? moonDirection}) =>
      GradientSkySource(
        zenithColor: vm.Vector3(0.006, 0.010, 0.030),
        horizonColor: vm.Vector3(0.05, 0.08, 0.16),
        groundColor: vm.Vector3(0.02, 0.02, 0.03),
        sunDirection: moonDirection ?? vm.Vector3(0.3, 0.6, 0.4),
        sunColor: vm.Vector3(0.5, 0.6, 0.9),
        sunSharpness: 900,
      );

  /// Neutral indoor dome (a lit ceiling and a darker floor), no sun disk.
  static GradientSkySource interior({
    vm.Vector3? ceiling,
    vm.Vector3? walls,
    vm.Vector3? floor,
  }) => GradientSkySource(
    zenithColor: ceiling ?? vm.Vector3(0.30, 0.30, 0.34),
    horizonColor: walls ?? vm.Vector3(0.16, 0.16, 0.19),
    groundColor: floor ?? vm.Vector3(0.05, 0.05, 0.06),
    sunColor: vm.Vector3.zero(),
  );

  /// Cave or dungeon: nearly black all round, a hint of warm torchlight low.
  static GradientSkySource cave() => GradientSkySource(
    zenithColor: vm.Vector3(0.004, 0.004, 0.005),
    horizonColor: vm.Vector3(0.03, 0.02, 0.015),
    groundColor: vm.Vector3(0.01, 0.008, 0.006),
    sunColor: vm.Vector3.zero(),
  );

  /// Cyber hall: cold cyan ceiling glow over a magenta-tinted horizon.
  static GradientSkySource cyber() => GradientSkySource(
    zenithColor: vm.Vector3(0.02, 0.10, 0.14),
    horizonColor: vm.Vector3(0.10, 0.02, 0.12),
    groundColor: vm.Vector3(0.01, 0.01, 0.02),
    sunColor: vm.Vector3.zero(),
  );

  /// Shows [sky] behind the scene and lights the scene with it.
  ///
  /// The bake is one 64 px cube on entry (Riviera's budget); [refresh]
  /// `interval` re-bakes for a moving sun. [intensity] scales the IBL.
  static void applyGradient(
    Scene scene,
    GradientSkySource sky, {
    double intensity = 0.85,
    int faceResolution = 64,
    int equirectWidth = 256,
    SkyEnvironmentRefresh refresh = SkyEnvironmentRefresh.manual,
    Duration interval = const Duration(seconds: 2),
  }) {
    scene
      ..skybox = Skybox(sky)
      ..skyEnvironment = SkyEnvironment(
        sky,
        faceResolution: faceResolution,
        equirectWidth: equirectWidth,
        refresh: refresh,
        interval: interval,
      )
      ..environmentIntensity = intensity;
  }

  /// A directional light matching [sky]'s sun, so shadows and the baked
  /// lighting agree. The light travels opposite to the sun direction.
  static DirectionalLight sunFor(
    SunSky sky, {
    double? intensity,
    vm.Vector3? color,
    bool castsShadow = false,
    int shadowMapResolution = 1024,
    double shadowMaxDistance = 60,
  }) => DirectionalLight(
    direction: -sky.sunDirection.normalized(),
    color: color ?? sky.sunLightColor,
    intensity: intensity ?? math.min(sky.sunLightIntensity, 3.5),
    castsShadow: castsShadow,
    shadowMapResolution: shadowMapResolution,
    shadowMaxDistance: shadowMaxDistance,
    shadowCascadeCount: 2,
  );

  /// Synthesizes a star field (in an isolate), uploads it as the scene's
  /// environment and shows it as the skybox. Returns false, changing
  /// nothing, when [isCurrent] reports the caller is gone or the GPU is not
  /// ready.
  static Future<bool> applyStars(
    Scene scene, {
    required bool Function() isCurrent,
    VrStarfieldRequest request = const VrStarfieldRequest(),
    double intensity = 0.6,
  }) async {
    await Scene.initializeStaticResources();
    if (!isCurrent() || !Scene.isReadyToRender) return false;
    final map = await (_starfields[request] ??= _bakeStars(request));
    if (!isCurrent()) return false;
    scene
      ..skyEnvironment = null
      ..environment = map
      ..environmentIntensity = intensity
      ..skybox = Skybox(EnvironmentSkySource());
    return true;
  }

  static final Map<VrStarfieldRequest, Future<EnvironmentMap>> _starfields = {};

  static Future<EnvironmentMap> _bakeStars(VrStarfieldRequest request) async {
    final pixels = await compute(
      VrSkySynth.starfield,
      request,
      debugLabel: 'sky:stars',
    );
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      pixels,
      request.width,
      request.height,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    final image = await completer.future;
    return EnvironmentMap.fromUIImages(radianceImage: image);
  }

  @visibleForTesting
  static void clearCache() => _starfields.clear();
}

/// Parameters of a synthesized star sky (an equirect RGBA image).
@immutable
class VrStarfieldRequest {
  const VrStarfieldRequest({
    this.width = 1024,
    this.height = 512,
    this.seed = 1,
    this.starDensity = 1.0,
    this.nebula = 0.5,
    this.nebulaTint = 0xFF3A2C6E,
    this.milkyWay = 0.6,
    this.horizonGlow = 0.0,
  });

  final int width;
  final int height;
  final int seed;

  /// 1.0 ≈ 2 000 visible stars on a 1024 × 512 sky.
  final double starDensity;

  /// Strength of the soft nebula haze (0 disables).
  final double nebula;

  /// sRGB tint of the nebula haze.
  final int nebulaTint;

  /// Brightness of the tilted galactic band (0 disables).
  final double milkyWay;

  /// A faint warm glow just above the horizon (a city, a planet's limb).
  final double horizonGlow;

  @override
  bool operator ==(Object other) =>
      other is VrStarfieldRequest &&
      other.width == width &&
      other.height == height &&
      other.seed == seed &&
      other.starDensity == starDensity &&
      other.nebula == nebula &&
      other.nebulaTint == nebulaTint &&
      other.milkyWay == milkyWay &&
      other.horizonGlow == horizonGlow;

  @override
  int get hashCode => Object.hash(
    width,
    height,
    seed,
    starDensity,
    nebula,
    nebulaTint,
    milkyWay,
    horizonGlow,
  );
}

/// Pure-Dart sky image synthesis (isolate-safe).
abstract final class VrSkySynth {
  /// Equirect RGBA star sky: black-blue base, periodic-noise nebula, a
  /// tilted galactic band, and Gaussian stars with a color-temperature
  /// spread. Wraps seamlessly in longitude.
  static Uint8List starfield(VrStarfieldRequest r) {
    final w = r.width, h = r.height;
    final out = Uint8List(w * h * 4);
    final rng = math.Random(r.seed);
    final tintR = ((r.nebulaTint >> 16) & 0xFF) / 255.0;
    final tintG = ((r.nebulaTint >> 8) & 0xFF) / 255.0;
    final tintB = (r.nebulaTint & 0xFF) / 255.0;
    final noise = _PeriodicNoise(r.seed);

    // Base: haze and galactic band, written as floats first.
    final acc = Float32List(w * h * 3);
    for (var y = 0; y < h; y++) {
      final v = (y + 0.5) / h; // 0 top (zenith) .. 1 bottom (nadir)
      final lat = (0.5 - v) * math.pi; // +π/2 zenith .. −π/2 nadir
      for (var x = 0; x < w; x++) {
        final u = (x + 0.5) / w;
        final lon = u * 2 * math.pi;
        var rr = 0.004, gg = 0.006, bb = 0.014;
        if (r.nebula > 0) {
          final n = noise.fbm(u, v * 0.5, octaves: 4, cells: 6);
          final haze =
              math.pow((n - 0.45).clamp(0.0, 1.0) * 1.8, 2.2) * r.nebula;
          rr += tintR * haze * 0.10;
          gg += tintG * haze * 0.10;
          bb += tintB * haze * 0.10;
        }
        if (r.milkyWay > 0) {
          // Great circle tilted 62° from the equator: signed distance of
          // this direction to the band's plane.
          final dx = math.cos(lat) * math.cos(lon);
          final dy = math.sin(lat);
          final dz = math.cos(lat) * math.sin(lon);
          const tilt = 62 * math.pi / 180;
          final planeDist = (dy * math.cos(tilt) - dz * math.sin(tilt)).abs();
          final band =
              math.exp(-planeDist * planeDist * 28) *
              (0.6 + 0.4 * noise.fbm(u, v, octaves: 3, cells: 10));
          final dark = noise.fbm(u + 0.3, v, octaves: 3, cells: 16);
          final lanes = (1.0 - math.pow(dark, 3) * 0.9).clamp(0.2, 1.0);
          final m = band * lanes * r.milkyWay * 0.09 * (0.5 + 0.5 * dx.abs());
          rr += m * 0.85;
          gg += m * 0.85;
          bb += m;
        }
        if (r.horizonGlow > 0 && lat < 0.2) {
          final g =
              math.exp(-(lat - 0.02) * (lat - 0.02) * 120) * r.horizonGlow;
          rr += g * 0.25;
          gg += g * 0.14;
          bb += g * 0.06;
        }
        final o = (y * w + x) * 3;
        acc[o] = rr;
        acc[o + 1] = gg;
        acc[o + 2] = bb;
      }
    }

    // Stars: area-uniform on the sphere (cos-latitude rejection), splatted
    // as small Gaussians so they survive mipmapping and the 64 px bake.
    // Density is per solid angle: a smaller image gets proportionally
    // fewer stars, not the same stars packed tighter.
    final count = (2000 * r.starDensity * (w * h) / (1024 * 512)).round();
    var placed = 0;
    while (placed < count) {
      final u = rng.nextDouble();
      final v = rng.nextDouble();
      final lat = (0.5 - v) * math.pi;
      if (rng.nextDouble() > math.cos(lat)) continue;
      placed++;
      final bright = math.pow(rng.nextDouble(), 6).toDouble();
      final mag = 0.25 + bright * 2.4; // a few bright, most faint
      final temp = rng.nextDouble();
      final cr = temp < 0.2
          ? 1.0
          : temp < 0.7
          ? 0.95
          : 0.75;
      final cg = temp < 0.2
          ? 0.75
          : temp < 0.7
          ? 0.95
          : 0.85;
      final cb = temp < 0.2
          ? 0.55
          : temp < 0.7
          ? 1.0
          : 1.0;
      final sigma = 0.55 + bright * 1.1;
      final cx = u * w, cy = v * h;
      final reach = (sigma * 3).ceil();
      for (var dy = -reach; dy <= reach; dy++) {
        final py = cy.floor() + dy;
        if (py < 0 || py >= h) continue;
        for (var dx = -reach; dx <= reach; dx++) {
          final col = cx.floor() + dx;
          final px = (col % w + w) % w; // spill across the seam
          final ddx = col + 0.5 - cx, ddy = py + 0.5 - cy;
          final g = math.exp(-(ddx * ddx + ddy * ddy) / (2 * sigma * sigma));
          final o = (py * w + px) * 3;
          acc[o] += cr * mag * g;
          acc[o + 1] += cg * mag * g;
          acc[o + 2] += cb * mag * g;
        }
      }
    }

    for (var i = 0; i < w * h; i++) {
      out[i * 4] = _srgbByte(acc[i * 3]);
      out[i * 4 + 1] = _srgbByte(acc[i * 3 + 1]);
      out[i * 4 + 2] = _srgbByte(acc[i * 3 + 2]);
      out[i * 4 + 3] = 255;
    }
    return out;
  }

  /// Linear → sRGB byte with a soft shoulder so bright stars clip gently.
  static int _srgbByte(double linear) {
    final v = linear / (1 + linear * 0.35);
    final s = v <= 0.0031308 ? v * 12.92 : 1.055 * math.pow(v, 1 / 2.4) - 0.055;
    return (s.clamp(0.0, 1.0) * 255).round();
  }
}

/// Value noise that wraps in both axes (u in longitude, v in latitude).
class _PeriodicNoise {
  const _PeriodicNoise(this.seed);

  final int seed;

  double hash(int x, int y, int salt) {
    var h = x * 374761393 + y * 668265263 + (seed + salt) * 2147483647;
    h = (h ^ (h >> 13)) * 1274126177;
    h = h ^ (h >> 16);
    return (h & 0xFFFFFF) / 0x1000000;
  }

  double noise(double u, double v, int cells, int salt) {
    final x = u * cells, y = v * cells;
    final x0 = x.floor(), y0 = y.floor();
    final fx = x - x0, fy = y - y0;
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

  double fbm(double u, double v, {required int octaves, required int cells}) {
    var sum = 0.0, amplitude = 1.0, total = 0.0;
    var c = cells;
    for (var i = 0; i < octaves; i++) {
      sum += amplitude * noise(u, v, c, 100 + i);
      total += amplitude;
      amplitude *= 0.5;
      c *= 2;
    }
    return sum / total;
  }
}
