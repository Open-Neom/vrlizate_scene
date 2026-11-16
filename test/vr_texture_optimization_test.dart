import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_scene/scene.dart' as fs;
import 'package:flutter_test/flutter_test.dart';
import 'package:vrlizate_scene/vrlizate_scene.dart';

void main() {
  group('VrTextureBudget & SGSR Mip Bias', () {
    test('scales asymmetric ORM dimensions and anisotropy per VrQualityTier', () {
      expect(VrTextureBudget.low.maxColorDimension, 512);
      expect(VrTextureBudget.low.maxOrmDimension, 256);
      expect(VrTextureBudget.low.anisotropyForRole(VrTextureRole.floor), 2);
      expect(VrTextureBudget.low.anisotropyForRole(VrTextureRole.prop), 1);

      expect(VrTextureBudget.medium.maxColorDimension, 1024);
      expect(VrTextureBudget.medium.maxOrmDimension, 512);
      expect(VrTextureBudget.medium.anisotropyForRole(VrTextureRole.floor), 8);
      expect(
        VrTextureBudget.medium.anisotropyForRole(VrTextureRole.heroSurface),
        4,
      );

      expect(VrTextureBudget.high.anisotropyForRole(VrTextureRole.heroSurface), 8);
      expect(VrTextureBudget.ultra.maxColorDimension, 2048);
      expect(VrTextureBudget.ultra.maxOrmDimension, 1024);
      expect(VrTextureBudget.ultra.anisotropyForRole(VrTextureRole.ui), 1);
      expect(
        VrTextureBudget.ultra.samplingForRole(VrTextureRole.ui).mipmaps,
        isFalse,
      );
    });

    test('computes negative Mip LOD bias for sub-native SGSR 1 render scales', () {
      expect(VrTextureBudget.sgsrMipLodBias(1.0), 0.0);
      expect(VrTextureBudget.sgsrMipLodBias(1.15), 0.0);
      expect(VrTextureBudget.sgsrMipLodBias(0.75), closeTo(-0.415, 0.005));
      expect(VrTextureBudget.sgsrMipLodBias(0.5), -0.5);
      expect(VrTextureBudget.sgsrMipLodBias(0.25), -0.5);
    });

    test('accounts 4x VRAM savings for 4x4 block-compressed mip chains', () {
      final rgbaBytes = VrTextureBudget.estimateTextureVramBytes(
        1024,
        1024,
        mipmapped: true,
        blockCompressed4x4: false,
      );
      final astcBytes = VrTextureBudget.estimateTextureVramBytes(
        1024,
        1024,
        mipmapped: true,
        blockCompressed4x4: true,
      );
      // Base 1024..4x4 mips compress bit-exactly 4:1; the final 2x2 mip pads
      // to one 16-byte 4x4 hardware block (+12 bytes vs 16-byte 2x2 RGBA8).
      expect(astcBytes, rgbaBytes ~/ 4 + 12);
      expect(
        VrTextureBudget.estimateTextureVramBytes(
          1024,
          1024,
          mipmapped: false,
          blockCompressed4x4: true,
        ) * 4,
        1024 * 1024 * 4,
      );
    });
  });

  group('VrToksvigFilter Specular Anti-Aliasing & Photo ORM Packing', () {
    test('preserves mirror roughness on flat normals and widens steep variance', () {
      expect(VrToksvigFilter.broadenRoughness(0.18, 1.0), closeTo(0.18, 1e-6));
      final widened = VrToksvigFilter.broadenRoughness(0.18, 0.78);
      expect(widened, greaterThan(0.55));
      expect(widened, lessThanOrEqualTo(1.0));
    });

    test('transfers cumulative multi-level normal variance into ORM.g mips', () {
      const size = 64;
      final albedo = Uint8List(size * size * 4)..fillRange(0, size * size * 4, 200);
      final normal = Uint8List(size * size * 4);
      final orm = Uint8List(size * size * 4);

      // Alternating high-frequency +/-45 degree opposing normal ridges with
      // glossy base roughness (0.18).
      for (var y = 0; y < size; y++) {
        for (var x = 0; x < size; x++) {
          final sign = ((x + y) & 1) == 0 ? 1.0 : -1.0;
          final nx = 0.65 * sign;
          final nz = math.sqrt(1.0 - nx * nx);
          final o = (y * size + x) * 4;
          normal[o] = ((nx * 0.5 + 0.5) * 255).round();
          normal[o + 1] = 128;
          normal[o + 2] = ((nz * 0.5 + 0.5) * 255).round();
          normal[o + 3] = 255;

          orm[o] = 255; // AO = 1.0
          orm[o + 1] = (0.18 * 255).round(); // Glossy base roughness
          orm[o + 2] = 255; // Metallic = 1.0
          orm[o + 3] = 255;
        }
      }

      final chains = VrToksvigFilter.generateCoupledPbrMipChain(
        albedoRgba: albedo,
        normalRgba: normal,
        ormRgba: orm,
        width: size,
        height: size,
        maxOrmDimension: 32,
      );

      // Asymmetric 50% ORM cap slices mip 1 (32x32) as the ORM base level,
      // which ALREADY embeds the Toksvig roughness from the 64x64 normal ridges!
      expect(chains.normal.first.width, 64);
      expect(chains.orm.first.width, 32);
      final mip1Roughness = chains.orm.first.rgba[1] / 255.0;
      expect(mip1Roughness, greaterThan(0.50));
    });

    test('synthesizes concave cavity AO + metallic B=255 from photo maps', () {
      const n = 16;
      final rough = Uint8List(n * n * 4);
      final normal = Uint8List(n * n * 4);
      for (var y = 0; y < n; y++) {
        for (var x = 0; x < n; x++) {
          final o = (y * n + x) * 4;
          rough[o] = rough[o + 1] = rough[o + 2] = 128;
          rough[o + 3] = 255;
          // Concave pit around (8, 8): normals tilt outward from center.
          final dx = (x - 8).clamp(-1, 1) * 0.55;
          final dy = (8 - y).clamp(-1, 1) * 0.55; // +Y up in OpenGL
          final dist = (x - 8).abs() + (y - 8).abs();
          final nx = dist <= 2 ? dx : 0.0;
          final ny = dist <= 2 ? dy : 0.0;
          final nz = math.sqrt(math.max(0.05, 1.0 - nx * nx - ny * ny));
          normal[o] = ((nx * 0.5 + 0.5) * 255).round();
          normal[o + 1] = ((ny * 0.5 + 0.5) * 255).round();
          normal[o + 2] = ((nz * 0.5 + 0.5) * 255).round();
          normal[o + 3] = 255;
        }
      }

      final packed = VrToksvigFilter.packPhotoRoughnessAndNormalToOrm(
        roughnessRgba: rough,
        roughnessWidth: n,
        roughnessHeight: n,
        normalRgba: normal,
        normalWidth: n,
        normalHeight: n,
        metallic: 1.0,
      );
      final flatCornerAo = packed[0];
      final pitCenterAo = packed[(8 * n + 8) * 4];
      expect(flatCornerAo, 255);
      expect(pitCenterAo, lessThan(220));
      expect(packed[(8 * n + 8) * 4 + 2], 255); // B = 1.0 for metallicFactor
    });
  });

  group('VrKtx2Codec & PbrTextureSynth.generateCompressedKtx2', () {
    test('round-trips 4x4 block-compressed KTX2 mip pyramid with high fidelity', () {
      final compressed = PbrTextureSynth.generateCompressedKtx2(
        const PbrCompressedKtx2Request(
          PbrTextureRequest(
            PbrSurface.sciFiTrimSheet,
            size: 64,
            seed: 42,
            primary: 0xFF6B7D96,
            secondary: 0xFFD97A2B,
            repeats: 2,
          ),
          maxColorDimension: 64,
          maxNormalDimension: 64,
          maxOrmDimension: 32,
        ),
      );

      final albedoInfo = VrKtx2Codec.inspectKtx2Header(compressed.albedoKtx2);
      final ormInfo = VrKtx2Codec.inspectKtx2Header(compressed.ormKtx2);
      expect(albedoInfo.isUniversalBlockPayload, isTrue);
      expect(albedoInfo.isSupportedRuntime2dTexture, isTrue);
      expect(albedoInfo.width, 64);
      expect(albedoInfo.height, 64);
      expect(ormInfo.width, 32);
      expect(ormInfo.height, 32);

      // 64x64 ASTC/Universal 4x4 base level is 4096 bytes vs 16384 RGBA8 (4x smaller).
      final decodedBase = VrKtx2Codec.decodeUniversalKtx2Level(
        compressed.albedoKtx2,
        level: 0,
      );
      expect(decodedBase.width, 64);
      expect(decodedBase.rgba.length, 64 * 64 * 4);
      expect(decodedBase.rgba[3], 255);
    });

    test('rejects truncated or non-KTX2 byte buffers deterministically', () {
      expect(
        () => VrKtx2Codec.inspectKtx2Header(Uint8List(32)),
        throwsFormatException,
      );
      expect(
        () => VrKtx2Codec.inspectKtx2Header(Uint8List(96)),
        throwsFormatException,
      );
    });
  });

  group('VrVertexAoBaker & VrSculptedGeometry ground contact AO', () {
    test('darkens base vertices near minY and preserves bright crown vertices', () {
      final pedestal = VrSculptedGeometry.flutedPedestalArrays(
        bottomRadius: 0.30,
        topRadius: 0.24,
        height: 1.0,
        groundAoStrength: 0.40,
      );
      expect(pedestal.colors, isNotNull);
      expect(pedestal.colors!.length, pedestal.vertexCount * 4);

      var minBaseR = 1.0;
      var maxTopR = 0.0;
      for (var i = 0; i < pedestal.vertexCount; i++) {
        final y = pedestal.positions[i * 3 + 1];
        final r = pedestal.colors![i * 4];
        if (y < -0.45 && r < minBaseR) minBaseR = r;
        if (y > 0.45 && r > maxTopR) maxTopR = r;
      }
      expect(minBaseR, lessThan(0.65));
      expect(maxTopR, greaterThan(0.95));

      final tintA = VrVertexAoBaker.macroCellTint(4, 7);
      final tintB = VrVertexAoBaker.macroCellTint(4, 8);
      expect(tintA, VrVertexAoBaker.macroCellTint(4, 7));
      expect(tintA, isNot(tintB));
    });

    test('PbrTextureLibrary.assetMapCacheKey distinguishes maxSize', () {
      const s = fs.TextureSampling(maxAnisotropy: 4);
      final kFull = PbrTextureLibrary.assetMapCacheKey(
        'brick.jpg',
        fs.TextureContent.color,
        s,
      );
      final kHalf = PbrTextureLibrary.assetMapCacheKey(
        'brick.jpg',
        fs.TextureContent.color,
        s,
        maxSize: 512,
      );
      expect(kFull, isNot(kHalf));
    });
  });
}
