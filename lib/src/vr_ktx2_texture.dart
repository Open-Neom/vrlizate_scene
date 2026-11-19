import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_scene/gpu.dart' as gpu;
import 'package:flutter_scene/scene.dart';

/// Raw RGBA8888 mip level produced by [VrToksvigFilter] and consumed by
/// [VrKtx2Codec].
final class VrRawMipLevel {
  const VrRawMipLevel({
    required this.width,
    required this.height,
    required this.rgba,
  });

  final int width;
  final int height;
  final Uint8List rgba;
}

/// Coupled PBR mip chains for one material set (`albedo` sRGB, `normal`
/// tangent-space OpenGL, and `orm` glTF Occlusion-Roughness-Metallic).
final class VrCoupledPbrMipChains {
  const VrCoupledPbrMipChains({
    required this.albedo,
    required this.normal,
    required this.orm,
  });

  final List<VrRawMipLevel> albedo;
  final List<VrRawMipLevel> normal;
  final List<VrRawMipLevel> orm;
}

/// Specular anti-aliasing (Toksvig / Kaplanyan Normal-Variance-to-Roughness)
/// and coupled PBR mipmap generation for stereoscopic VR.
///
/// In VR headsets without aggressive Temporal Anti-Aliasing (TAA), independent
/// normal-map mip downsampling averages tangent-space bump vectors toward
/// `(0, 0, 1)` and renormalizes them while discarding the shortened vector
/// length `r = ||n_avg|| < 1`. Because perceptual roughness in the ORM map
/// stays low, distant grates, bricks, brushed metals, and woven fibers turn
/// into flat mirrors that sparkle violently across left/right eyes.
///
/// [VrToksvigFilter] tracks cumulative unnormalized normal vector length across
/// every level of the mip pyramid and transfers the lost micro-normal variance
/// `sigma^2 = (1 - r) / max(r, 1e-4)` directly into the GGX roughness lobe
/// (`ORM.g`) at **zero runtime fragment-shader cost**.
abstract final class VrToksvigFilter {
  static final Float64List _srgbToLinearLut = Float64List.fromList([
    for (var b = 0; b < 256; b++) _decodeSrgbByte(b),
  ]);

  static double _decodeSrgbByte(int byte) {
    final c = byte / 255.0;
    return c <= 0.04045
        ? c / 12.92
        : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
  }

  static int _encodeLinearToSrgbByte(double linear) {
    final clamped = linear.clamp(0.0, 1.0);
    final srgb = clamped <= 0.0031308
        ? clamped * 12.92
        : 1.055 * math.pow(clamped, 1.0 / 2.4).toDouble() - 0.055;
    return (srgb * 255.0).round().clamp(0, 255);
  }

  static int _encodeUnitComponent(double v) =>
      ((v.clamp(-1.0, 1.0) + 1.0) * 127.5).round().clamp(0, 255);

  /// Widens perceptual [baseRoughness] (`[0, 1]`) by the Toksvig variance
  /// implied by average normal magnitude [normalLength] (`(0, 1]`).
  static double broadenRoughness(
    double baseRoughness,
    double normalLength, {
    double strength = 1.0,
  }) {
    final rp = baseRoughness.clamp(0.045, 1.0);
    if (strength <= 0.0 || normalLength >= 0.99995) return rp;
    final r = normalLength.clamp(1e-4, 1.0);
    final sigmaSq = (1.0 - r) / r;
    final alpha = rp * rp;
    final alphaSqNew = math.min(
      1.0,
      alpha * alpha + strength * 2.0 * sigmaSq,
    );
    return math.sqrt(math.sqrt(alphaSqNew)).clamp(rp, 1.0);
  }

  /// Regularizes base-level `ORM.g` roughness in place (or into a new buffer)
  /// from each texel's periodic `3x3` tangent-space normal neighborhood,
  /// preventing sub-pixel specular sparkle on 1-texel ridges at grazing angles.
  static Uint8List regularizeBaseOrmRoughness({
    required Uint8List normalRgba,
    required Uint8List ormRgba,
    required int width,
    required int height,
    double strength = 0.55,
    bool wrap = true,
  }) {
    final out = Uint8List.fromList(ormRgba);
    if (strength <= 0.0 || width <= 1 || height <= 1) return out;

    int coord(int c, int extent) {
      if (wrap) return ((c % extent) + extent) % extent;
      return c < 0 ? 0 : (c >= extent ? extent - 1 : c);
    }

    for (var y = 0; y < height; y++) {
      final ym = coord(y - 1, height) * width;
      final y0 = y * width;
      final yp = coord(y + 1, height) * width;
      for (var x = 0; x < width; x++) {
        final xm = coord(x - 1, width);
        final xp = coord(x + 1, width);

        var sx = 0.0, sy = 0.0, sz = 0.0;
        void accum(int idx, double w) {
          final p = idx * 4;
          var nx = normalRgba[p] / 127.5 - 1.0;
          var ny = normalRgba[p + 1] / 127.5 - 1.0;
          var nz = normalRgba[p + 2] / 127.5 - 1.0;
          final l = math.sqrt(nx * nx + ny * ny + nz * nz);
          if (l > 1e-6) {
            nx /= l;
            ny /= l;
            nz /= l;
          } else {
            nx = 0.0;
            ny = 0.0;
            nz = 1.0;
          }
          sx += nx * w;
          sy += ny * w;
          sz += nz * w;
        }

        // 3x3 tent kernel (sum of weights = 16).
        accum(ym + xm, 1.0);
        accum(ym + x, 2.0);
        accum(ym + xp, 1.0);
        accum(y0 + xm, 2.0);
        accum(y0 + x, 4.0);
        accum(y0 + xp, 2.0);
        accum(yp + xm, 1.0);
        accum(yp + x, 2.0);
        accum(yp + xp, 1.0);

        final avgLen = math.sqrt(sx * sx + sy * sy + sz * sz) / 16.0;
        final o = (y0 + x) * 4;
        final baseRough = ormRgba[o + 1] / 255.0;
        final filtered = broadenRoughness(
          baseRough,
          avgLen,
          strength: strength,
        );
        out[o + 1] = (filtered * 255.0).round().clamp(0, 255);
      }
    }
    return out;
  }

  /// Synthesizes a full glTF 2.0 packed ORM texture (`R = cavity AO`,
  /// `G = Toksvig-filtered Roughness`, `B = Metallic`, `A = 255`) from a
  /// grayscale photo roughness map and its companion OpenGL normal map.
  ///
  /// AmbientCG photo sets ship separate `Roughness` and `NormalGL` JPGs without
  /// a runtime AO map. By integrating tangent-space normal divergence
  /// (`dn_x/dx - dn_y/dy`, positive inside concave crevices under OpenGL `+Y`
  /// up convention) and optional albedo cavity darkening, photo materials gain
  /// crisp crevice occlusion in `R` at **zero extra VRAM or sampler cost**.
  static Uint8List packPhotoRoughnessAndNormalToOrm({
    required Uint8List roughnessRgba,
    required int roughnessWidth,
    required int roughnessHeight,
    required Uint8List normalRgba,
    required int normalWidth,
    required int normalHeight,
    Uint8List? albedoRgba,
    int? albedoWidth,
    int? albedoHeight,
    double metallic = 0.0,
    double cavityAoStrength = 0.65,
    double toksvigStrength = 0.55,
  }) {
    final w = normalWidth;
    final h = normalHeight;
    final orm = Uint8List(w * h * 4);
    final metalByte = (metallic.clamp(0.0, 1.0) * 255.0).round();

    int wrap(int c, int ext) => ((c % ext) + ext) % ext;

    for (var y = 0; y < h; y++) {
      final ry = (y * roughnessHeight) ~/ h;
      final ay = albedoHeight != null ? (y * albedoHeight) ~/ h : 0;
      final yUp = wrap(y - 1, h);
      final yDn = wrap(y + 1, h);
      for (var x = 0; x < w; x++) {
        final rx = (x * roughnessWidth) ~/ w;
        final rIdx = (ry * roughnessWidth + rx) * 4;
        // Photo roughness JPGs carry grayscale roughness in R/G/B.
        final baseRough = roughnessRgba[rIdx + 1] / 255.0;

        final xLt = wrap(x - 1, w);
        final xRt = wrap(x + 1, w);
        final nxRt = normalRgba[(y * w + xRt) * 4] / 127.5 - 1.0;
        final nxLt = normalRgba[(y * w + xLt) * 4] / 127.5 - 1.0;
        final nyUp = normalRgba[(yUp * w + x) * 4 + 1] / 127.5 - 1.0;
        final nyDn = normalRgba[(yDn * w + x) * 4 + 1] / 127.5 - 1.0;
        final nzCenter = normalRgba[(y * w + x) * 4 + 2] / 127.5 - 1.0;

        // OpenGL normal convention: +X right, +Y up (toward y-1). Inside a
        // concave pit/joint, right texel tilts +X, left tilts -X, top tilts +Y,
        // bottom tilts -Y -> positive outward divergence.
        final div = ((nxRt - nxLt) + (nyUp - nyDn)) * 0.5;
        final steepPenalty = (1.0 - nzCenter.clamp(0.0, 1.0)) * 0.35;
        var cavity = (math.max(0.0, div) * 0.65 + steepPenalty) *
            cavityAoStrength;

        if (albedoRgba != null && albedoWidth != null && albedoHeight != null) {
          final ax = (x * albedoWidth) ~/ w;
          final aIdx = (ay * albedoWidth + ax) * 4;
          final luma =
              (0.2126 * albedoRgba[aIdx] +
                  0.7152 * albedoRgba[aIdx + 1] +
                  0.0722 * albedoRgba[aIdx + 2]) /
              255.0;
          cavity += math.max(0.0, 0.45 - luma) * 0.22 * cavityAoStrength;
        }

        final ao = (1.0 - cavity).clamp(0.50, 1.0);
        final o = (y * w + x) * 4;
        orm[o] = (ao * 255.0).round();
        orm[o + 1] = (baseRough.clamp(0.045, 1.0) * 255.0).round();
        orm[o + 2] = metalByte;
        orm[o + 3] = 255;
      }
    }

    return regularizeBaseOrmRoughness(
      normalRgba: normalRgba,
      ormRgba: orm,
      width: w,
      height: h,
      strength: toksvigStrength,
    );
  }

  /// Generates GPU-ready mip chains for (`albedo`, `normal`, `orm`) with:
  /// - Linear-light sRGB downsampling for `albedo`,
  /// - Exact cumulative multi-level Toksvig normal-variance transfer from
  ///   `normal` into `orm.g` across every mip level,
  /// - Optional asymmetric resolution capping ([maxColorDimension],
  ///   [maxNormalDimension], [maxOrmDimension]) so lower VR tiers or 50% ORM
  ///   budgets slice pre-filtered mips that retain full high-res normal variance.
  static VrCoupledPbrMipChains generateCoupledPbrMipChain({
    required Uint8List albedoRgba,
    required Uint8List normalRgba,
    required Uint8List ormRgba,
    required int width,
    required int height,
    double toksvigStrength = 1.0,
    int? maxColorDimension,
    int? maxNormalDimension,
    int? maxOrmDimension,
  }) {
    final albedoChain = downsampleColorMipChain(
      albedoRgba,
      width,
      height,
      maxBaseDimension: maxColorDimension,
    );

    final totalLevels = engineMipLevelCount(width, height);
    final normalLevels = <VrRawMipLevel>[
      VrRawMipLevel(width: width, height: height, rgba: normalRgba),
    ];
    final ormLevels = <VrRawMipLevel>[
      VrRawMipLevel(width: width, height: height, rgba: ormRgba),
    ];

    var curW = width;
    var curH = height;
    var curNorm = normalRgba;
    // Base-level unit normals stored as unnormalized magnitudes = 1.0.
    var curLengths = Float32List(width * height)..fillRange(0, width * height, 1.0);
    // Keep pristine base-averaged roughness (before Toksvig broadening) so
    // cumulative multi-level variance never double-counts across levels.
    var curBaseRough = Float32List(width * height);
    for (var i = 0; i < width * height; i++) {
      curBaseRough[i] = ormRgba[i * 4 + 1] / 255.0;
    }
    var curOrm = ormRgba;

    for (var level = 1; level < totalLevels; level++) {
      final nw = math.max(1, curW >> 1);
      final nh = math.max(1, curH >> 1);
      final nextNorm = Uint8List(nw * nh * 4);
      final nextLengths = Float32List(nw * nh);
      final nextBaseRough = Float32List(nw * nh);
      final nextOrm = Uint8List(nw * nh * 4);

      for (var y = 0; y < nh; y++) {
        final y0 = math.min(y * 2, curH - 1);
        final y1 = math.min(y0 + 1, curH - 1);
        for (var x = 0; x < nw; x++) {
          final x0 = math.min(x * 2, curW - 1);
          final x1 = math.min(x0 + 1, curW - 1);
          final idx0 = y0 * curW + x0;
          final idx1 = y0 * curW + x1;
          final idx2 = y1 * curW + x0;
          final idx3 = y1 * curW + x1;

          var sx = 0.0, sy = 0.0, sz = 0.0;
          void addWeightedNormal(int idx) {
            final p = idx * 4;
            var nx = curNorm[p] / 127.5 - 1.0;
            var ny = curNorm[p + 1] / 127.5 - 1.0;
            var nz = curNorm[p + 2] / 127.5 - 1.0;
            final l = math.sqrt(nx * nx + ny * ny + nz * nz);
            if (l > 1e-6) {
              final w = curLengths[idx] / l;
              sx += nx * w;
              sy += ny * w;
              sz += nz * w;
            } else {
              sz += curLengths[idx];
            }
          }

          addWeightedNormal(idx0);
          addWeightedNormal(idx1);
          addWeightedNormal(idx2);
          addWeightedNormal(idx3);

          sx *= 0.25;
          sy *= 0.25;
          sz *= 0.25;
          final mag = math.sqrt(sx * sx + sy * sy + sz * sz);
          final dstIdx = y * nw + x;
          nextLengths[dstIdx] = mag.clamp(1e-4, 1.0);

          final double ux, uy, uz;
          if (mag > 1e-6) {
            ux = sx / mag;
            uy = sy / mag;
            uz = sz / mag;
          } else {
            ux = 0.0;
            uy = 0.0;
            uz = 1.0;
          }
          final o = dstIdx * 4;
          nextNorm[o] = _encodeUnitComponent(ux);
          nextNorm[o + 1] = _encodeUnitComponent(uy);
          nextNorm[o + 2] = _encodeUnitComponent(uz);
          nextNorm[o + 3] = 255;

          final avgBaseRough =
              (curBaseRough[idx0] +
                  curBaseRough[idx1] +
                  curBaseRough[idx2] +
                  curBaseRough[idx3]) *
              0.25;
          nextBaseRough[dstIdx] = avgBaseRough;

          final toksvigRough = broadenRoughness(
            avgBaseRough,
            mag,
            strength: toksvigStrength,
          );

          final p0 = idx0 * 4;
          final p1 = idx1 * 4;
          final p2 = idx2 * 4;
          final p3 = idx3 * 4;
          nextOrm[o] =
              ((curOrm[p0] + curOrm[p1] + curOrm[p2] + curOrm[p3]) + 2) >> 2;
          nextOrm[o + 1] = (toksvigRough * 255.0).round().clamp(0, 255);
          nextOrm[o + 2] =
              ((curOrm[p0 + 2] +
                      curOrm[p1 + 2] +
                      curOrm[p2 + 2] +
                      curOrm[p3 + 2]) +
                  2) >>
              2;
          nextOrm[o + 3] = 255;
        }
      }

      normalLevels.add(VrRawMipLevel(width: nw, height: nh, rgba: nextNorm));
      ormLevels.add(VrRawMipLevel(width: nw, height: nh, rgba: nextOrm));
      curW = nw;
      curH = nh;
      curNorm = nextNorm;
      curLengths = nextLengths;
      curBaseRough = nextBaseRough;
      curOrm = nextOrm;
    }

    return VrCoupledPbrMipChains(
      albedo: albedoChain,
      normal: _sliceToMaxDimension(normalLevels, maxNormalDimension),
      orm: _sliceToMaxDimension(ormLevels, maxOrmDimension),
    );
  }

  /// Builds an sRGB linear-light averaged mip chain matching Flutter GPU's
  /// expected mip level count.
  static List<VrRawMipLevel> downsampleColorMipChain(
    Uint8List rgba,
    int width,
    int height, {
    int? maxBaseDimension,
  }) {
    final total = engineMipLevelCount(width, height);
    final levels = <VrRawMipLevel>[
      VrRawMipLevel(width: width, height: height, rgba: rgba),
    ];
    var cw = width;
    var ch = height;
    var cur = rgba;
    for (var level = 1; level < total; level++) {
      final nw = math.max(1, cw >> 1);
      final nh = math.max(1, ch >> 1);
      final dst = Uint8List(nw * nh * 4);
      for (var y = 0; y < nh; y++) {
        final y0 = math.min(y * 2, ch - 1);
        final y1 = math.min(y0 + 1, ch - 1);
        final r0 = y0 * cw;
        final r1 = y1 * cw;
        for (var x = 0; x < nw; x++) {
          final x0 = math.min(x * 2, cw - 1);
          final x1 = math.min(x0 + 1, cw - 1);
          final a = (r0 + x0) * 4;
          final b = (r0 + x1) * 4;
          final c = (r1 + x0) * 4;
          final d = (r1 + x1) * 4;
          final o = (y * nw + x) * 4;
          for (var chIdx = 0; chIdx < 3; chIdx++) {
            final avgLin =
                (_srgbToLinearLut[cur[a + chIdx]] +
                    _srgbToLinearLut[cur[b + chIdx]] +
                    _srgbToLinearLut[cur[c + chIdx]] +
                    _srgbToLinearLut[cur[d + chIdx]]) *
                0.25;
            dst[o + chIdx] = _encodeLinearToSrgbByte(avgLin);
          }
          dst[o + 3] = ((cur[a + 3] + cur[b + 3] + cur[c + 3] + cur[d + 3]) + 2) >> 2;
        }
      }
      levels.add(VrRawMipLevel(width: nw, height: nh, rgba: dst));
      cw = nw;
      ch = nh;
      cur = dst;
    }
    return _sliceToMaxDimension(levels, maxBaseDimension);
  }

  static List<VrRawMipLevel> _sliceToMaxDimension(
    List<VrRawMipLevel> levels,
    int? maxDim,
  ) {
    if (maxDim == null || levels.length <= 1) return levels;
    var start = 0;
    while (start < levels.length - 1 &&
        math.max(levels[start].width, levels[start].height) > maxDim) {
      start++;
    }
    if (start == 0) return levels;
    final sub = levels.sublist(start);
    final allowedCount = engineMipLevelCount(sub.first.width, sub.first.height);
    return sub.length > allowedCount ? sub.sublist(0, allowedCount) : sub;
  }

  /// Number of mip levels Flutter GPU expects for a `width × height` texture.
  static int engineMipLevelCount(int width, int height) {
    final smallest = math.min(width, height);
    if (smallest < 1) return 1;
    final count = smallest.bitLength - 1;
    return count > 0 ? count : 1;
  }
}

/// Metadata parsed from a Khronos KTX 2.0 header + Data Format Descriptor.
final class VrKtx2HeaderInfo {
  const VrKtx2HeaderInfo({
    required this.width,
    required this.height,
    required this.levelCount,
    required this.faceCount,
    required this.layerCount,
    required this.pixelDepth,
    required this.vkFormat,
    required this.supercompressionScheme,
    required this.dfdColorModel,
    required this.isUniversalBlockPayload,
    required this.estimatedGpuVramBytes,
    this.isLzSupercompressed = false,
    this.estimatedUncompressedVramBytes = 0,
  });

  final int width;
  final int height;
  final int levelCount;
  final int faceCount;
  final int layerCount;
  final int pixelDepth;
  final int vkFormat;
  final int supercompressionScheme;
  final int dfdColorModel;
  final bool isUniversalBlockPayload;
  final bool isLzSupercompressed;
  final int estimatedGpuVramBytes;
  final int estimatedUncompressedVramBytes;

  /// True for standard `KHR_texture_basisu` UASTC (`166`), ETC1S (`163`),
  /// uncompressed RGBA8 (`VK_FORMAT_R8G8B8A8_UNORM = 37` / `_SRGB = 43`), or
  /// `flutter_scene`'s universal 4x4 block payload (`fsBlockFormat=universal/1`).
  bool get isSupportedRuntime2dTexture =>
      faceCount == 1 &&
      layerCount <= 1 &&
      pixelDepth <= 1 &&
      width >= 1 &&
      height >= 1 &&
      supercompressionScheme >= 0 &&
      supercompressionScheme <= 3 &&
      (isUniversalBlockPayload ||
          dfdColorModel == 166 ||
          dfdColorModel == 163 ||
          vkFormat == 37 ||
          vkFormat == 43);
}

/// Pure-Dart Khronos KTX 2.0 header validator and 4x4 block-compressed encoder.
///
/// Encodes pre-filtered [VrRawMipLevel] pyramids into `KTX2` containers carrying
/// `4x4` 16-byte endpoint-interpolated blocks (`fsBlockFormat = universal/1`),
/// with optional `fsSupercompress = lz/1` payload supercompression for compact
/// disk caches and asset delivery. `flutter_scene` transcodes on a background
/// isolate directly to native GPU hardware block formats:
/// - `ASTC 4x4` (`astc4x4LDR`, 8 bpp — **4x less VRAM & memory bandwidth**) on
///   Android, iOS, visionOS, and Apple Silicon;
/// - `BC1` / `BC3` (4–8 bpp) on desktop GPUs;
/// - `ETC2` (4–8 bpp) on GLES3 mobile GPUs;
/// - `RGBA8` fallback on web without extensions.
abstract final class VrKtx2Codec {
  static const List<int> ktx2Magic = <int>[
    0xAB, 0x4B, 0x54, 0x58, 0x20, 0x32, 0x30, 0xBB, 0x0D, 0x0A, 0x1A, 0x0A, //
  ];

  static const String _blockFormatKey = 'fsBlockFormat';
  static const String _blockFormatUniversal = 'universal/1';
  static const String _supercompressKey = 'fsSupercompress';
  static const String _supercompressLz = 'lz/1';
  static const String _alphaKey = 'fsAlpha';

  static bool hasKtx2Magic(Uint8List bytes) {
    if (bytes.length < ktx2Magic.length) return false;
    for (var i = 0; i < ktx2Magic.length; i++) {
      if (bytes[i] != ktx2Magic[i]) return false;
    }
    return true;
  }

  /// Validates and inspects a KTX2 container without touching the GPU.
  /// Throws [FormatException] if the container is malformed or truncated.
  static VrKtx2HeaderInfo inspectKtx2Header(Uint8List bytes) {
    if (bytes.length < 80) {
      throw const FormatException('KTX2 texture is truncated (< 80 bytes).');
    }
    if (!hasKtx2Magic(bytes)) {
      throw const FormatException('Invalid KTX2 magic identifier.');
    }
    final data = ByteData.sublistView(bytes);
    final vkFormat = data.getUint32(12, Endian.little);
    final width = data.getUint32(20, Endian.little);
    final rawHeight = data.getUint32(24, Endian.little);
    final height = rawHeight == 0 ? 1 : rawHeight;
    final pixelDepth = data.getUint32(28, Endian.little);
    final layerCount = data.getUint32(32, Endian.little);
    final faceCount = data.getUint32(36, Endian.little);
    final rawLevels = data.getUint32(40, Endian.little);
    final levelCount = rawLevels == 0 ? 1 : rawLevels;
    final supercompression = data.getUint32(44, Endian.little);
    if (supercompression > 3) {
      throw FormatException(
        'Unsupported KTX2 supercompression scheme: $supercompression.',
      );
    }
    if (width < 1 || width > 16384 || height < 1 || height > 16384) {
      throw FormatException('Implausible KTX2 dimensions: ${width}x$height.');
    }

    final levelIndexEnd = 80 + levelCount * 24;
    if (bytes.length < levelIndexEnd) {
      throw const FormatException('Truncated KTX2 level index.');
    }
    for (var i = 0; i < levelCount; i++) {
      final entry = 80 + i * 24;
      final offsetLow = data.getUint32(entry, Endian.little);
      final offsetHigh = data.getUint32(entry + 4, Endian.little);
      final lenLow = data.getUint32(entry + 8, Endian.little);
      final lenHigh = data.getUint32(entry + 12, Endian.little);
      if (offsetHigh != 0 ||
          lenHigh != 0 ||
          offsetLow + lenLow > bytes.length) {
        throw const FormatException('KTX2 mip level payload out of bounds.');
      }
    }

    final dfdOffset = data.getUint32(48, Endian.little);
    final dfdLength = data.getUint32(52, Endian.little);
    var dfdColorModel = 0;
    if (dfdLength > 0) {
      if (dfdOffset + dfdLength > bytes.length || dfdLength < 16) {
        throw const FormatException('Malformed KTX2 Data Format Descriptor.');
      }
      dfdColorModel = bytes[dfdOffset + 12];
    }

    final kvdOffset = data.getUint32(56, Endian.little);
    final kvdLength = data.getUint32(60, Endian.little);
    var isUniversal = false;
    var isLzSupercompressed = false;
    if (kvdLength > 0) {
      if (kvdOffset + kvdLength > bytes.length) {
        throw const FormatException('Malformed KTX2 Key/Value section.');
      }
      final kvs = _decodeKeyValues(
        Uint8List.sublistView(bytes, kvdOffset, kvdOffset + kvdLength),
      );
      final marker = kvs[_blockFormatKey];
      if (marker != null && utf8.decode(marker) == _blockFormatUniversal) {
        isUniversal = true;
      }
      final sc = kvs[_supercompressKey];
      if (sc != null && utf8.decode(sc) == _supercompressLz) {
        isLzSupercompressed = true;
      }
    }

    final blockCompressed =
        isUniversal || dfdColorModel == 166 || dfdColorModel == 163;
    var vramBytes = 0;
    var uncompressedVramBytes = 0;
    for (var level = 0; level < levelCount; level++) {
      final mw = math.max(1, width >> level);
      final mh = math.max(1, height >> level);
      uncompressedVramBytes += mw * mh * 4;
      if (blockCompressed) {
        final bx = (mw + 3) >> 2;
        final by = (mh + 3) >> 2;
        // ETC1S RGB is 8 B/block, ASTC 4x4 / UASTC is 16 B/block; use 16 B as
        // a safe upper bound across mobile ASTC GPUs.
        vramBytes += bx * by * 16;
      } else {
        vramBytes += mw * mh * 4;
      }
    }

    return VrKtx2HeaderInfo(
      width: width,
      height: height,
      levelCount: levelCount,
      faceCount: faceCount,
      layerCount: layerCount,
      pixelDepth: pixelDepth,
      vkFormat: vkFormat,
      supercompressionScheme: supercompression,
      dfdColorModel: dfdColorModel,
      isUniversalBlockPayload: isUniversal,
      isLzSupercompressed: isLzSupercompressed,
      estimatedGpuVramBytes: vramBytes,
      estimatedUncompressedVramBytes: uncompressedVramBytes,
    );
  }

  /// Encodes a pre-filtered [levels] mip chain (level 0 = base) into KTX2 bytes
  /// carrying 16-byte `4x4` blocks ready for native GPU `ASTC 4x4` / `ETC2` /
  /// `BC1-BC3` transcoding.
  ///
  /// When [supercompress] is `true`, each mip level's block payload is wrapped
  /// with `flutter_scene`'s compatible `fsSupercompress = lz/1` LZ77 codec
  /// (typically 45–65% smaller on disk/flash while keeping identical GPU VRAM).
  static Uint8List encodeMipChainToKtx2(
    List<VrRawMipLevel> levels, {
    bool srgb = true,
    bool supercompress = false,
  }) {
    if (levels.isEmpty) {
      throw ArgumentError('KTX2 mip chain must contain at least one level.');
    }
    final base = levels.first;
    var hasAlpha = false;
    final basePixels = base.rgba;
    for (var i = 3; i < basePixels.length; i += 4) {
      if (basePixels[i] != 255) {
        hasAlpha = true;
        break;
      }
    }

    final rawBlockLevels = <Uint8List>[
      for (final lvl in levels)
        encodeUniversalBlocks4x4(lvl.rgba, lvl.width, lvl.height),
    ];
    final storedLevels = <Uint8List>[
      for (final blocks in rawBlockLevels)
        supercompress ? lzCompress(blocks) : blocks,
    ];

    final dfd = _buildDfd(srgb: srgb);
    final kvd = _encodeKeyValues({
      if (hasAlpha) _alphaKey: Uint8List.fromList(utf8.encode('1')),
      _blockFormatKey: Uint8List.fromList(utf8.encode(_blockFormatUniversal)),
      if (supercompress)
        _supercompressKey: Uint8List.fromList(utf8.encode(_supercompressLz)),
    });

    const headerEnd = 80;
    const entrySize = 24;
    var cursor = headerEnd + entrySize * storedLevels.length;
    final dfdOffset = _align(cursor, 4);
    cursor = dfdOffset + dfd.length;
    final kvdOffset = _align(cursor, 4);
    cursor = kvdOffset + kvd.length;

    // Store smallest mip first per KTX2 specification, 16-byte aligned.
    final levelOffsets = List<int>.filled(storedLevels.length, 0);
    for (var i = storedLevels.length - 1; i >= 0; i--) {
      cursor = _align(cursor, 16);
      levelOffsets[i] = cursor;
      cursor += storedLevels[i].length;
    }

    final out = Uint8List(cursor);
    final bd = ByteData.sublistView(out);
    out.setRange(0, ktx2Magic.length, ktx2Magic);
    bd.setUint32(12, 0, Endian.little); // VK_FORMAT_UNDEFINED
    bd.setUint32(16, 1, Endian.little); // typeSize = 1
    bd.setUint32(20, base.width, Endian.little);
    bd.setUint32(24, base.height, Endian.little);
    bd.setUint32(28, 0, Endian.little); // pixelDepth
    bd.setUint32(32, 0, Endian.little); // layerCount
    bd.setUint32(36, 1, Endian.little); // faceCount = 1
    bd.setUint32(40, storedLevels.length, Endian.little);
    bd.setUint32(44, 0, Endian.little); // supercompression = none
    bd.setUint32(48, dfdOffset, Endian.little);
    bd.setUint32(52, dfd.length, Endian.little);
    bd.setUint32(56, kvdOffset, Endian.little);
    bd.setUint32(60, kvd.length, Endian.little);
    // sgdByteOffset / sgdByteLength = 0 (bytes 64..79 already zero).

    for (var i = 0; i < storedLevels.length; i++) {
      final entry = headerEnd + i * entrySize;
      bd.setUint32(entry, levelOffsets[i], Endian.little);
      bd.setUint32(entry + 8, storedLevels[i].length, Endian.little);
      bd.setUint32(entry + 16, rawBlockLevels[i].length, Endian.little);
    }

    out.setRange(dfdOffset, dfdOffset + dfd.length, dfd);
    out.setRange(kvdOffset, kvdOffset + kvd.length, kvd);
    for (var i = 0; i < storedLevels.length; i++) {
      out.setRange(
        levelOffsets[i],
        levelOffsets[i] + storedLevels[i].length,
        storedLevels[i],
      );
    }
    return out;
  }

  /// Decodes one mip [level] of a universal-block KTX2 file back to RGBA8888
  /// for headless verification and unit testing.
  static VrRawMipLevel decodeUniversalKtx2Level(
    Uint8List ktx2Bytes, {
    int level = 0,
  }) {
    final info = inspectKtx2Header(ktx2Bytes);
    if (!info.isUniversalBlockPayload) {
      throw const FormatException('Not a universal/1 block KTX2 payload.');
    }
    if (level < 0 || level >= info.levelCount) {
      throw RangeError.index(level, null, 'level', null, info.levelCount);
    }
    final bd = ByteData.sublistView(ktx2Bytes);
    final entry = 80 + level * 24;
    final offset = bd.getUint32(entry, Endian.little);
    final length = bd.getUint32(entry + 8, Endian.little);
    final mw = math.max(1, info.width >> level);
    final mh = math.max(1, info.height >> level);
    final payload = Uint8List.sublistView(ktx2Bytes, offset, offset + length);
    final blocks = info.isLzSupercompressed
        ? lzDecompress(payload, ((mw + 3) >> 2) * ((mh + 3) >> 2) * 16)
        : payload;
    return VrRawMipLevel(
      width: mw,
      height: mh,
      rgba: decodeUniversalBlocks4x4(blocks, mw, mh),
    );
  }

  /// Pure-Dart LZ77 compressor matching `flutter_scene`'s `fsSupercompress=lz/1`
  /// format byte-for-byte.
  static Uint8List lzCompress(Uint8List input) {
    const minMatch = 4;
    const maxChain = 32;
    const hashBits = 16;
    const hashSize = 1 << hashBits;

    final n = input.length;
    final out = BytesBuilder(copy: false);
    if (n == 0) return out.toBytes();

    final head = Int32List(hashSize)..fillRange(0, hashSize, -1);
    final prev = Int32List(n);

    int hash4(int i) {
      final h =
          ((input[i] * 131 + input[i + 1]) * 131 + input[i + 2]) * 131 +
          input[i + 3];
      return (h ^ (h >> 13)) & (hashSize - 1);
    }

    int matchLenAt(int a, int b) {
      var len = 0;
      while (b + len < n && input[a + len] == input[b + len]) {
        len++;
      }
      return len;
    }

    void writeVarint(int value) {
      var v = value;
      while (v >= 0x80) {
        out.addByte((v & 0x7F) | 0x80);
        v >>= 7;
      }
      out.addByte(v);
    }

    void emitLiterals(int start, int end) {
      writeVarint(end - start);
      if (end > start) out.add(Uint8List.sublistView(input, start, end));
    }

    var i = 0;
    var literalStart = 0;
    while (i < n) {
      var matchLen = 0;
      var matchDist = 0;
      if (i + minMatch <= n) {
        final h = hash4(i);
        var candidate = head[h];
        prev[i] = candidate;
        head[h] = i;
        var tries = 0;
        while (candidate >= 0 && tries < maxChain) {
          final len = matchLenAt(candidate, i);
          if (len > matchLen) {
            matchLen = len;
            matchDist = i - candidate;
            if (i + len >= n) break;
          }
          candidate = prev[candidate];
          tries++;
        }
      }

      if (matchLen >= minMatch) {
        emitLiterals(literalStart, i);
        writeVarint(matchLen - minMatch);
        writeVarint(matchDist);
        final end = i + matchLen;
        for (var k = i + 1; k < end; k++) {
          if (k + minMatch <= n) {
            final h = hash4(k);
            prev[k] = head[h];
            head[h] = k;
          }
        }
        i = end;
        literalStart = i;
      } else {
        i++;
      }
    }
    emitLiterals(literalStart, n);
    return out.toBytes();
  }

  /// Pure-Dart LZ77 decompressor matching `flutter_scene`'s `fsSupercompress=lz/1`.
  static Uint8List lzDecompress(Uint8List compressed, int uncompressedSize) {
    const minMatch = 4;
    final out = Uint8List(uncompressedSize);
    var produced = 0;
    var p = 0;

    int readVarint() {
      var shift = 0;
      var result = 0;
      while (true) {
        if (p >= compressed.length) {
          throw const FormatException('Truncated LZ77 varint in KTX2 payload.');
        }
        final b = compressed[p++];
        result |= (b & 0x7F) << shift;
        if (b < 0x80) return result;
        shift += 7;
      }
    }

    while (produced < uncompressedSize) {
      final literalLength = readVarint();
      if (p + literalLength > compressed.length ||
          produced + literalLength > uncompressedSize) {
        throw const FormatException('LZ77 literal overrun in KTX2 payload.');
      }
      for (var k = 0; k < literalLength; k++) {
        out[produced++] = compressed[p++];
      }
      if (produced >= uncompressedSize) break;
      final matchLength = readVarint() + minMatch;
      final distance = readVarint();
      var src = produced - distance;
      if (src < 0 || distance <= 0 || produced + matchLength > uncompressedSize) {
        throw const FormatException('Invalid LZ77 back-reference in KTX2 payload.');
      }
      for (var k = 0; k < matchLength; k++) {
        out[produced++] = out[src++];
      }
    }
    return out;
  }

  /// Encodes `width × height` RGBA8 pixels into 16-byte `4x4` blocks using
  /// 8-iteration covariance power-method principal axis fitting + least-squares
  /// endpoint refinement.
  static Uint8List encodeUniversalBlocks4x4(
    Uint8List rgba,
    int width,
    int height,
  ) {
    if (rgba.length < width * height * 4) {
      throw ArgumentError('rgba is too small for ${width}x$height');
    }
    final blocksX = (width + 3) >> 2;
    final blocksY = (height + 3) >> 2;
    final out = Uint8List(blocksX * blocksY * 16);
    final texel = Int32List(64);
    final weights = Int32List(16);

    for (var by = 0; by < blocksY; by++) {
      for (var bx = 0; bx < blocksX; bx++) {
        for (var ty = 0; ty < 4; ty++) {
          final sy = math.min(by * 4 + ty, height - 1);
          for (var tx = 0; tx < 4; tx++) {
            final sx = math.min(bx * 4 + tx, width - 1);
            final src = (sy * width + sx) * 4;
            final dst = (ty * 4 + tx) * 4;
            texel[dst] = rgba[src];
            texel[dst + 1] = rgba[src + 1];
            texel[dst + 2] = rgba[src + 2];
            texel[dst + 3] = rgba[src + 3];
          }
        }
        _encodeSingleBlock(texel, weights, out, (by * blocksX + bx) * 16);
      }
    }
    return out;
  }

  static Uint8List decodeUniversalBlocks4x4(
    Uint8List blocks,
    int width,
    int height,
  ) {
    final blocksX = (width + 3) >> 2;
    final blocksY = (height + 3) >> 2;
    if (blocks.length < blocksX * blocksY * 16) {
      throw ArgumentError('blocks buffer too small for ${width}x$height');
    }
    final out = Uint8List(width * height * 4);
    for (var by = 0; by < blocksY; by++) {
      for (var bx = 0; bx < blocksX; bx++) {
        final bo = (by * blocksX + bx) * 16;
        final e0r = blocks[bo], e0g = blocks[bo + 1], e0b = blocks[bo + 2], e0a = blocks[bo + 3];
        final e1r = blocks[bo + 4], e1g = blocks[bo + 5], e1b = blocks[bo + 6], e1a = blocks[bo + 7];
        for (var i = 0; i < 16; i++) {
          final ty = i >> 2;
          final tx = i & 3;
          final dy = by * 4 + ty;
          final dx = bx * 4 + tx;
          if (dy >= height || dx >= width) continue;
          final wByte = blocks[bo + 8 + (i >> 1)];
          final w = (i & 1) == 0 ? (wByte & 0x0F) : ((wByte >> 4) & 0x0F);
          final dst = (dy * width + dx) * 4;
          out[dst] = ((e0r * (15 - w) + e1r * w + 7) ~/ 15).clamp(0, 255);
          out[dst + 1] = ((e0g * (15 - w) + e1g * w + 7) ~/ 15).clamp(0, 255);
          out[dst + 2] = ((e0b * (15 - w) + e1b * w + 7) ~/ 15).clamp(0, 255);
          out[dst + 3] = ((e0a * (15 - w) + e1a * w + 7) ~/ 15).clamp(0, 255);
        }
      }
    }
    return out;
  }

  static void _encodeSingleBlock(
    Int32List texel,
    Int32List weights,
    Uint8List out,
    int offset,
  ) {
    var mr = 0.0, mg = 0.0, mb = 0.0, ma = 0.0;
    for (var i = 0; i < 16; i++) {
      final p = i * 4;
      mr += texel[p];
      mg += texel[p + 1];
      mb += texel[p + 2];
      ma += texel[p + 3];
    }
    mr *= 0.0625;
    mg *= 0.0625;
    mb *= 0.0625;
    ma *= 0.0625;

    var vx = 1.0, vy = 1.0, vz = 1.0, vw = 0.0;
    for (var iter = 0; iter < 8; iter++) {
      var ax = 0.0, ay = 0.0, az = 0.0, aw = 0.0;
      for (var i = 0; i < 16; i++) {
        final p = i * 4;
        final dx = texel[p] - mr;
        final dy = texel[p + 1] - mg;
        final dz = texel[p + 2] - mb;
        final dw = texel[p + 3] - ma;
        final dot = dx * vx + dy * vy + dz * vz + dw * vw;
        ax += dot * dx;
        ay += dot * dy;
        az += dot * dz;
        aw += dot * dw;
      }
      final len = math.sqrt(ax * ax + ay * ay + az * az + aw * aw);
      if (len < 1e-9) break;
      vx = ax / len;
      vy = ay / len;
      vz = az / len;
      vw = aw / len;
    }

    var minT = double.infinity, maxT = double.negativeInfinity;
    for (var i = 0; i < 16; i++) {
      final p = i * 4;
      final t =
          (texel[p] - mr) * vx +
          (texel[p + 1] - mg) * vy +
          (texel[p + 2] - mb) * vz +
          (texel[p + 3] - ma) * vw;
      if (t < minT) minT = t;
      if (t > maxT) maxT = t;
    }

    if (maxT - minT < 1e-6) {
      for (var c = 0; c < 4; c++) {
        final b = texel[c].clamp(0, 255);
        out[offset + c] = b;
        out[offset + 4 + c] = b;
      }
      for (var i = 8; i < 16; i++) {
        out[offset + i] = 0;
      }
      return;
    }

    var e0r = mr + vx * minT, e0g = mg + vy * minT, e0b = mb + vz * minT, e0a = ma + vw * minT;
    var e1r = mr + vx * maxT, e1g = mg + vy * maxT, e1b = mb + vz * maxT, e1a = ma + vw * maxT;

    void assignWeights() {
      final dr = e1r - e0r, dg = e1g - e0g, db = e1b - e0b, da = e1a - e0a;
      final denom = dr * dr + dg * dg + db * db + da * da;
      if (denom < 1e-9) {
        for (var i = 0; i < 16; i++) {
          weights[i] = 0;
        }
        return;
      }
      final scale = 15.0 / denom;
      for (var i = 0; i < 16; i++) {
        final p = i * 4;
        final proj =
            ((texel[p] - e0r) * dr +
                (texel[p + 1] - e0g) * dg +
                (texel[p + 2] - e0b) * db +
                (texel[p + 3] - e0a) * da) *
            scale;
        weights[i] = proj.round().clamp(0, 15);
      }
    }

    assignWeights();

    // One least-squares endpoint refinement step over fixed weights.
    var s00 = 0.0, s01 = 0.0, s11 = 0.0;
    for (var i = 0; i < 16; i++) {
      final w1 = weights[i] / 15.0;
      final w0 = 1.0 - w1;
      s00 += w0 * w0;
      s01 += w0 * w1;
      s11 += w1 * w1;
    }
    final det = s00 * s11 - s01 * s01;
    if (det > 1e-6) {
      final invDet = 1.0 / det;
      final ep0 = Float64List(4);
      final ep1 = Float64List(4);
      for (var c = 0; c < 4; c++) {
        var b0 = 0.0, b1 = 0.0;
        for (var i = 0; i < 16; i++) {
          final w1 = weights[i] / 15.0;
          final w0 = 1.0 - w1;
          final v = texel[i * 4 + c].toDouble();
          b0 += w0 * v;
          b1 += w1 * v;
        }
        ep0[c] = (s11 * b0 - s01 * b1) * invDet;
        ep1[c] = (s00 * b1 - s01 * b0) * invDet;
      }
      e0r = ep0[0];
      e0g = ep0[1];
      e0b = ep0[2];
      e0a = ep0[3];
      e1r = ep1[0];
      e1g = ep1[1];
      e1b = ep1[2];
      e1a = ep1[3];
      assignWeights();
    }

    int clampByte(double v) => v.round().clamp(0, 255);
    out[offset] = clampByte(e0r);
    out[offset + 1] = clampByte(e0g);
    out[offset + 2] = clampByte(e0b);
    out[offset + 3] = clampByte(e0a);
    out[offset + 4] = clampByte(e1r);
    out[offset + 5] = clampByte(e1g);
    out[offset + 6] = clampByte(e1b);
    out[offset + 7] = clampByte(e1a);

    for (var b = 0; b < 8; b++) {
      final lo = weights[b * 2] & 0x0F;
      final hi = (weights[b * 2 + 1] & 0x0F) << 4;
      out[offset + 8 + b] = lo | hi;
    }
  }

  static Uint8List _buildDfd({required bool srgb}) {
    const totalBytes = 28;
    final bd = ByteData(totalBytes);
    bd.setUint32(0, totalBytes, Endian.little);
    bd.setUint32(4, 0, Endian.little);
    bd.setUint32(8, 2 | (24 << 16), Endian.little);
    bd.setUint8(12, 0); // unspecified (universal/1 block payload)
    bd.setUint8(13, 1); // BT.709
    bd.setUint8(14, srgb ? 2 : 1); // 2 = sRGB, 1 = linear
    bd.setUint8(15, 0);
    bd.setUint8(16, 3); // 4 - 1
    bd.setUint8(17, 3); // 4 - 1
    bd.setUint8(20, 16); // 16 bytes/block
    return bd.buffer.asUint8List();
  }

  static int _align(int value, int alignment) =>
      (value + alignment - 1) ~/ alignment * alignment;

  static Uint8List _encodeKeyValues(Map<String, Uint8List> kvs) {
    final keys = kvs.keys.toList()..sort();
    final builder = BytesBuilder(copy: false);
    for (final k in keys) {
      final kb = utf8.encode(k);
      final vb = kvs[k]!;
      final len = kb.length + 1 + vb.length;
      final hdr = Uint8List(4);
      ByteData.sublistView(hdr).setUint32(0, len, Endian.little);
      builder
        ..add(hdr)
        ..add(kb)
        ..addByte(0)
        ..add(vb);
      final pad = _align(len, 4) - len;
      if (pad > 0) builder.add(Uint8List(pad));
    }
    return builder.toBytes();
  }

  static Map<String, Uint8List> _decodeKeyValues(Uint8List kvd) {
    final out = <String, Uint8List>{};
    final bd = ByteData.sublistView(kvd);
    var offset = 0;
    while (offset + 4 <= kvd.length) {
      final len = bd.getUint32(offset, Endian.little);
      offset += 4;
      if (len == 0 || offset + len > kvd.length) break;
      final entry = Uint8List.sublistView(kvd, offset, offset + len);
      final nul = entry.indexOf(0);
      if (nul >= 0) {
        final key = utf8.decode(Uint8List.sublistView(entry, 0, nul));
        out[key] = Uint8List.sublistView(entry, nul + 1);
      }
      offset = _align(offset + len, 4);
    }
    return out;
  }
}

/// One KTX2 texture request for [VrKtx2TextureLoader.loadBatch].
final class VrKtx2LoadRequest {
  const VrKtx2LoadRequest({
    required this.bytes,
    this.content = TextureContent.color,
    this.sampling = const TextureSampling(),
  });

  final Uint8List bytes;
  final TextureContent content;
  final TextureSampling sampling;
}

/// Live runtime telemetry for VRlizate's KTX2 + Toksvig GPU texture pipeline.
@immutable
final class VrKtx2TextureStats {
  const VrKtx2TextureStats({
    required this.hardwareFormatLabel,
    required this.manualMipsSupported,
    required this.ktx2UploadedCount,
    required this.ktx2MipLevelsUploaded,
    required this.fallbackRgbaCount,
    required this.toksvigMaterialsCount,
    required this.estimatedVramBytes,
    required this.estimatedUncompressedVramBytes,
    this.lastFallbackError,
  });

  const VrKtx2TextureStats.initial()
    : hardwareFormatLabel = 'Pendiente',
      manualMipsSupported = false,
      ktx2UploadedCount = 0,
      ktx2MipLevelsUploaded = 0,
      fallbackRgbaCount = 0,
      toksvigMaterialsCount = 0,
      estimatedVramBytes = 0,
      estimatedUncompressedVramBytes = 0,
      lastFallbackError = null;

  final String hardwareFormatLabel;
  final bool manualMipsSupported;
  final int ktx2UploadedCount;
  final int ktx2MipLevelsUploaded;
  final int fallbackRgbaCount;
  final int toksvigMaterialsCount;
  final int estimatedVramBytes;
  final int estimatedUncompressedVramBytes;
  final String? lastFallbackError;

  int get vramSavedBytes =>
      math.max(0, estimatedUncompressedVramBytes - estimatedVramBytes);

  double get compressionRatio => estimatedVramBytes > 0
      ? estimatedUncompressedVramBytes / estimatedVramBytes
      : 1.0;

  bool get isHardwareCompressed =>
      ktx2UploadedCount > 0 &&
      hardwareFormatLabel != 'RGBA8' &&
      hardwareFormatLabel != 'Pendiente';

  /// Compact badge label for live HUD / Settings UI.
  String get compactBadgeEs {
    if (ktx2UploadedCount == 0) {
      return 'KTX2 · Toksvig AA (esperando GPU)';
    }
    final savedMb = vramSavedBytes / (1024 * 1024);
    final pctSaved = estimatedUncompressedVramBytes > 0
        ? ((vramSavedBytes * 100) / estimatedUncompressedVramBytes).round()
        : 0;
    final mipTag = manualMipsSupported ? 'Mips Toksvig' : 'Base';
    if (isHardwareCompressed && pctSaved > 0) {
      return 'KTX2 $hardwareFormatLabel · $mipTag · $ktx2UploadedCount mapas · -$pctSaved% VRAM (${savedMb.toStringAsFixed(1)} MB ahorrados)';
    }
    return 'KTX2 $hardwareFormatLabel · $mipTag · $ktx2UploadedCount mapas';
  }

  VrKtx2TextureStats copyWith({
    String? hardwareFormatLabel,
    bool? manualMipsSupported,
    int? ktx2UploadedCount,
    int? ktx2MipLevelsUploaded,
    int? fallbackRgbaCount,
    int? toksvigMaterialsCount,
    int? estimatedVramBytes,
    int? estimatedUncompressedVramBytes,
    String? lastFallbackError,
  }) => VrKtx2TextureStats(
    hardwareFormatLabel: hardwareFormatLabel ?? this.hardwareFormatLabel,
    manualMipsSupported: manualMipsSupported ?? this.manualMipsSupported,
    ktx2UploadedCount: ktx2UploadedCount ?? this.ktx2UploadedCount,
    ktx2MipLevelsUploaded: ktx2MipLevelsUploaded ?? this.ktx2MipLevelsUploaded,
    fallbackRgbaCount: fallbackRgbaCount ?? this.fallbackRgbaCount,
    toksvigMaterialsCount: toksvigMaterialsCount ?? this.toksvigMaterialsCount,
    estimatedVramBytes: estimatedVramBytes ?? this.estimatedVramBytes,
    estimatedUncompressedVramBytes:
        estimatedUncompressedVramBytes ?? this.estimatedUncompressedVramBytes,
    lastFallbackError: lastFallbackError ?? this.lastFallbackError,
  );
}

/// Public-API GPU uploader for Khronos KTX 2.0 textures (`UASTC`, `ETC1S`, and
/// [VrKtx2Codec] `universal/1` block payloads).
///
/// Synthesizes a minimal in-memory glTF 2.0 carrier (`KHR_texture_basisu`) and
/// delegates to `Node.fromGltfBytes` so `flutter_scene` transcodes the entire
/// batch on a shared background isolate directly into native GPU block formats
/// (`ASTC 4x4` / `ETC2` / `BC1-BC3`), then binds each uploaded [gpu.Texture]
/// with the caller's exact [TextureSampling] (`maxAnisotropy`, wrap, mip mode).
abstract final class VrKtx2TextureLoader {
  // Minimal 3-vertex degenerate triangle (36 bytes float32 vec3) so the carrier
  // glTF satisfies accessor rules with negligible overhead.
  static final Uint8List _carrierGeometryBin = Uint8List(36);
  static bool _loggedHardwareCaps = false;

  /// Live runtime telemetry for Settings & performance HUD.
  static final ValueNotifier<VrKtx2TextureStats> stats =
      ValueNotifier<VrKtx2TextureStats>(const VrKtx2TextureStats.initial());

  /// Extracts the underlying [gpu.Texture] handle from any [TextureSource]
  /// (`Texture2D` or `GpuTextureSource`) when ready.
  static gpu.Texture? gpuTextureOf(TextureSource? source) =>
      source?.sampledTexture;

  /// Inspects an actual uploaded [gpu.Texture] handle to report the exact
  /// native GPU pixel format (`ASTC 4×4`, `BC1/BC3`, `ETC2`, or `RGBA8`) and
  /// real uploaded mip level count without touching private engine APIs.
  static ({String formatLabel, bool isCompressed, int mipLevels, int vramBytes})
  inspectUploadedTexture(gpu.Texture tex, VrKtx2HeaderInfo header) {
    final fmtName = tex.format.name.toLowerCase();
    final String label;
    final bool isCompressed;
    if (fmtName.contains('astc')) {
      label = 'ASTC 4×4';
      isCompressed = true;
    } else if (fmtName.contains('bc1') || fmtName.contains('bc3')) {
      label = 'BC1/BC3';
      isCompressed = true;
    } else if (fmtName.contains('etc2')) {
      label = 'ETC2';
      isCompressed = true;
    } else {
      label = 'RGBA8';
      isCompressed = false;
    }
    final mips = tex.mipLevelCount > 0 ? tex.mipLevelCount : 1;
    var vramBytes = 0;
    try {
      for (var m = 0; m < mips; m++) {
        vramBytes += tex.getMipLevelSizeInBytes(m);
      }
    } on Object {
      vramBytes = isCompressed
          ? header.estimatedGpuVramBytes
          : (header.estimatedUncompressedVramBytes > 0
                ? header.estimatedUncompressedVramBytes
                : header.estimatedGpuVramBytes * 4);
    }
    if (vramBytes <= 0) {
      vramBytes = isCompressed
          ? header.estimatedGpuVramBytes
          : header.estimatedGpuVramBytes * 4;
    }
    if (!_loggedHardwareCaps) {
      _loggedHardwareCaps = true;
      debugPrint(
        'VRlizate KTX2 GPU active: $label '
        '(rawFormat=${tex.format.name} mips=$mips ${tex.width}x${tex.height} '
        'vramBytes=$vramBytes)',
      );
    }
    return (
      formatLabel: label,
      isCompressed: isCompressed,
      mipLevels: mips,
      vramBytes: vramBytes,
    );
  }

  /// Records a Toksvig-filtered material upload for live telemetry.
  static void recordToksvigMaterial() {
    final cur = stats.value;
    stats.value = cur.copyWith(
      toksvigMaterialsCount: cur.toksvigMaterialsCount + 1,
    );
  }

  /// Records a graceful RGBA8 fallback so failures are never silently masked.
  static void recordFallback(Object error, {int uncompressedBytes = 0}) {
    debugPrint('VRlizate KTX2 fallback to RGBA8: $error');
    final cur = stats.value;
    stats.value = cur.copyWith(
      fallbackRgbaCount: cur.fallbackRgbaCount + 1,
      estimatedVramBytes: cur.estimatedVramBytes + uncompressedBytes,
      estimatedUncompressedVramBytes:
          cur.estimatedUncompressedVramBytes + uncompressedBytes,
      lastFallbackError: error.toString(),
    );
  }

  @visibleForTesting
  static void resetStatsForTesting() {
    _loggedHardwareCaps = false;
    stats.value = const VrKtx2TextureStats.initial();
  }

  /// Transcodes and uploads [requests] in a single batched isolate hop.
  static Future<List<GpuTextureSource>> loadBatch(
    List<VrKtx2LoadRequest> requests, {
    int? maxTextureSize,
  }) async {
    if (requests.isEmpty) return const <GpuTextureSource>[];
    final headers = <VrKtx2HeaderInfo>[];
    for (final req in requests) {
      final info = VrKtx2Codec.inspectKtx2Header(req.bytes);
      if (!info.isSupportedRuntime2dTexture) {
        throw FormatException(
          'Unsupported KTX2 2D runtime format (dfd=${info.dfdColorModel}, '
          'vk=${info.vkFormat}, faces=${info.faceCount}).',
        );
      }
      headers.add(info);
    }

    final uriMap = <String, Uint8List>{'geom.bin': _carrierGeometryBin};
    final images = <Map<String, Object?>>[];
    final textures = <Map<String, Object?>>[];
    final materials = <Map<String, Object?>>[];
    final primitives = <Map<String, Object?>>[];

    for (var i = 0; i < requests.length; i++) {
      final uri = 'tex_$i.ktx2';
      uriMap[uri] = requests[i].bytes;
      images.add(<String, Object?>{'uri': uri, 'mimeType': 'image/ktx2'});
      textures.add(<String, Object?>{
        'extensions': <String, Object?>{
          'KHR_texture_basisu': <String, Object?>{'source': i},
        },
      });
      final roleBinding = switch (requests[i].content) {
        TextureContent.color => <String, Object?>{
          'pbrMetallicRoughness': <String, Object?>{
            'baseColorTexture': <String, Object?>{'index': i},
          },
        },
        TextureContent.normal => <String, Object?>{
          'normalTexture': <String, Object?>{'index': i},
        },
        TextureContent.data => <String, Object?>{
          'pbrMetallicRoughness': <String, Object?>{
            'metallicRoughnessTexture': <String, Object?>{'index': i},
          },
        },
      };
      materials.add(roleBinding);
      primitives.add(<String, Object?>{
        'attributes': <String, Object?>{'POSITION': 0},
        'material': i,
      });
    }

    final gltfDoc = <String, Object?>{
      'asset': const <String, Object?>{'version': '2.0'},
      'extensionsUsed': const <String>['KHR_texture_basisu'],
      'buffers': const <Map<String, Object?>>[
        <String, Object?>{'uri': 'geom.bin', 'byteLength': 36},
      ],
      'bufferViews': const <Map<String, Object?>>[
        <String, Object?>{'buffer': 0, 'byteOffset': 0, 'byteLength': 36},
      ],
      'accessors': const <Map<String, Object?>>[
        <String, Object?>{
          'bufferView': 0,
          'componentType': 5126,
          'count': 3,
          'type': 'VEC3',
          'min': <double>[0.0, 0.0, 0.0],
          'max': <double>[0.0, 0.0, 0.0],
        },
      ],
      'images': images,
      'textures': textures,
      'materials': materials,
      'meshes': <Map<String, Object?>>[
        <String, Object?>{'primitives': primitives},
      ],
      'nodes': const <Map<String, Object?>>[
        <String, Object?>{'mesh': 0},
      ],
      'scenes': const <Map<String, Object?>>[
        <String, Object?>{
          'nodes': <int>[0],
        },
      ],
      'scene': 0,
    };

    String? importFailure;
    final root = await Node.fromGltfBytes(
      Uint8List.fromList(utf8.encode(jsonEncode(gltfDoc))),
      maxTextureSize: maxTextureSize,
      resolveUri: (uri) async {
        final hit = uriMap[uri];
        if (hit == null) {
          throw FormatException('Unknown carrier URI: $uri');
        }
        return hit;
      },
      onWarning: (w) {
        importFailure ??= w.message;
      },
    );
    if (importFailure != null) {
      throw FormatException('KTX2 GPU import failed: $importFailure');
    }
    if (root.children.isEmpty || root.children.first.mesh == null) {
      throw const FormatException('KTX2 carrier mesh missing after import.');
    }

    final importedPrims = root.children.first.mesh!.primitives;
    if (importedPrims.length != requests.length) {
      throw const FormatException('KTX2 carrier primitive count mismatch.');
    }

    final out = <GpuTextureSource>[];
    var batchVram = 0;
    var batchUncompressed = 0;
    var batchMips = 0;
    var resolvedFormatLabel = stats.value.hardwareFormatLabel;
    var manualMips = stats.value.manualMipsSupported;

    for (var i = 0; i < requests.length; i++) {
      final mat = importedPrims[i].material as PhysicallyBasedMaterial;
      final source = switch (requests[i].content) {
        TextureContent.color => mat.baseColorTexture,
        TextureContent.normal => mat.normalTexture,
        TextureContent.data => mat.metallicRoughnessTexture,
      };
      final gpuTex = source?.sampledTexture;
      if (gpuTex == null) {
        throw const FormatException('KTX2 texture resolved to null GPU handle.');
      }
      final info = headers[i];
      final inspected = inspectUploadedTexture(gpuTex, info);
      resolvedFormatLabel = inspected.formatLabel;
      if (inspected.mipLevels > 1) manualMips = true;
      batchVram += inspected.vramBytes;
      batchMips += inspected.mipLevels;
      batchUncompressed += info.estimatedUncompressedVramBytes > 0
          ? info.estimatedUncompressedVramBytes
          : info.estimatedGpuVramBytes * 4;
      out.add(
        GpuTextureSource(
          gpuTex,
          sampler: requests[i].sampling.toSamplerOptions(),
        ),
      );
    }

    final cur = stats.value;
    stats.value = cur.copyWith(
      hardwareFormatLabel: resolvedFormatLabel,
      manualMipsSupported: manualMips,
      ktx2UploadedCount: cur.ktx2UploadedCount + headers.length,
      ktx2MipLevelsUploaded: cur.ktx2MipLevelsUploaded + batchMips,
      estimatedVramBytes: cur.estimatedVramBytes + batchVram,
      estimatedUncompressedVramBytes:
          cur.estimatedUncompressedVramBytes + batchUncompressed,
    );
    return out;
  }

  /// Loads a single KTX2 texture into a [GpuTextureSource].
  static Future<GpuTextureSource> load(
    Uint8List bytes, {
    TextureContent content = TextureContent.color,
    TextureSampling sampling = const TextureSampling(),
    int? maxTextureSize,
  }) async {
    final res = await loadBatch(<VrKtx2LoadRequest>[
      VrKtx2LoadRequest(bytes: bytes, content: content, sampling: sampling),
    ], maxTextureSize: maxTextureSize);
    return res.first;
  }
}
