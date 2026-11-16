import 'dart:math' as math;

import 'package:flutter_scene/gpu.dart' as gpu;
import 'package:flutter_scene/scene.dart';

import 'quality_preset.dart';

/// Semantic role of a 2D texture in a stereoscopic VR scene.
///
/// Mobile Tile-Based Deferred Rendering (TBDR) GPUs spend a large share of
/// their frame thermal budget fetching texels across memory buses. Separating
/// oblique ground planes ([floor]), primary relief surfaces ([heroSurface]),
/// secondary props ([prop]), linear packed material maps ([ormData]),
/// equirectangular skies ([sky]), and sharp non-mipmapped overlays ([ui]) lets
/// [VrTextureBudget] scale anisotropy and asymmetric resolution per tier.
enum VrTextureRole {
  /// Oblique floors, roads, and walkways viewed at grazing stereo angles.
  floor,

  /// Primary architectural walls, hero props, and close-range weapon/hand meshes.
  heroSurface,

  /// Secondary props, distant trim, and background geometry.
  prop,

  /// Linear packed Occlusion-Roughness-Metallic (ORM) or mask data maps.
  ormData,

  /// Equirectangular panorama sky textures.
  sky,

  /// Flat UI/HUD cards that are never minified at steep oblique angles.
  ui,
}

/// GPU texture memory, resolution, and anisotropic filtering policy coupled to
/// [VrQualityTier].
///
/// Mirrors modern standalone VR practices (Meta Horizon OS / Quest 3, visionOS,
/// Android XR):
/// - Preserves full normal-map resolution relative to ORM maps (asymmetric
///   50% ORM sizing saves 75% of ORM texels with negligible perceptual loss).
/// - Reserves `8x` anisotropic taps on mid-tier devices for grazing [floor]
///   surfaces while capping secondary props and budget GPUs (`low`) at `1x–2x`.
/// - Computes negative Mip LOD bias ([sgsrMipLodBias]) when paired with
///   spatial upscaling (`SGSR 1`) so sub-native render scales retain crisp
///   native-equivalent texel selection.
final class VrTextureBudget {
  const VrTextureBudget({
    required this.tier,
    required this.maxColorDimension,
    required this.maxNormalDimension,
    required this.maxOrmDimension,
    required this.floorAnisotropy,
    required this.surfaceAnisotropy,
    required this.propAnisotropy,
    this.preferGpuBlockCompression = true,
  });

  final VrQualityTier tier;

  /// Maximum longest-edge texel dimension for albedo / emissive maps.
  final int maxColorDimension;

  /// Maximum longest-edge texel dimension for tangent-space normal maps.
  final int maxNormalDimension;

  /// Maximum longest-edge texel dimension for packed ORM (AO/Roughness/Metallic) maps.
  final int maxOrmDimension;

  /// Anisotropy cap (`1..8`) for grazing ground/floor surfaces.
  final int floorAnisotropy;

  /// Anisotropy cap (`1..8`) for hero architectural & close-up surfaces.
  final int surfaceAnisotropy;

  /// Anisotropy cap (`1..8`) for secondary props & linear ORM data maps.
  final int propAnisotropy;

  /// Whether procedural and cooked KTX2 textures should upload as hardware
  /// block-compressed formats (`ASTC 4x4` / `ETC2` / `BC1-BC3`) when supported.
  final bool preferGpuBlockCompression;

  /// Budget profile for entry/budget mobile GPUs (Mali-G52/G57, entry Adreno).
  static const low = VrTextureBudget(
    tier: VrQualityTier.low,
    maxColorDimension: 512,
    maxNormalDimension: 512,
    maxOrmDimension: 256,
    floorAnisotropy: 2,
    surfaceAnisotropy: 2,
    propAnisotropy: 1,
  );

  /// Balanced profile for mainstream phones: 1K color/normal, 512 asymmetric
  /// ORM, `8x` anisotropy on floors and `4x` elsewhere.
  static const medium = VrTextureBudget(
    tier: VrQualityTier.medium,
    maxColorDimension: 1024,
    maxNormalDimension: 1024,
    maxOrmDimension: 512,
    floorAnisotropy: 8,
    surfaceAnisotropy: 4,
    propAnisotropy: 4,
  );

  /// High-tier profile: `8x` anisotropy on hero surfaces & floors, asymmetric
  /// 512 ORM for secondary props and 1K hero detail.
  static const high = VrTextureBudget(
    tier: VrQualityTier.high,
    maxColorDimension: 1024,
    maxNormalDimension: 1024,
    maxOrmDimension: 512,
    floorAnisotropy: 8,
    surfaceAnisotropy: 8,
    propAnisotropy: 4,
  );

  /// Flagship / desktop VR profile: up to 2K hero maps, 1K ORM, `8x` anisotropy.
  static const ultra = VrTextureBudget(
    tier: VrQualityTier.ultra,
    maxColorDimension: 2048,
    maxNormalDimension: 2048,
    maxOrmDimension: 1024,
    floorAnisotropy: 8,
    surfaceAnisotropy: 8,
    propAnisotropy: 8,
  );

  static VrTextureBudget forTier(VrQualityTier tier) => switch (tier) {
    VrQualityTier.low => low,
    VrQualityTier.medium => medium,
    VrQualityTier.high => high,
    VrQualityTier.ultra => ultra,
  };

  static VrTextureBudget forPreset(VrQualityPreset preset) =>
      forTier(preset.tier);

  /// Maximum texel dimension for [role] under this budget.
  int maxDimensionForRole(
    VrTextureRole role, {
    TextureContent content = TextureContent.color,
  }) {
    if (role == VrTextureRole.ormData || content == TextureContent.data) {
      return maxOrmDimension;
    }
    if (content == TextureContent.normal) {
      return maxNormalDimension;
    }
    return switch (role) {
      VrTextureRole.floor ||
      VrTextureRole.heroSurface ||
      VrTextureRole.sky => maxColorDimension,
      VrTextureRole.prop => math.min(maxColorDimension, 1024),
      VrTextureRole.ormData => maxOrmDimension,
      VrTextureRole.ui => math.min(maxColorDimension, 1024),
    };
  }

  /// Anisotropy factor (`1..8`) appropriate for [role].
  int anisotropyForRole(VrTextureRole role) => switch (role) {
    VrTextureRole.floor => floorAnisotropy,
    VrTextureRole.heroSurface => surfaceAnisotropy,
    VrTextureRole.prop || VrTextureRole.ormData => propAnisotropy,
    VrTextureRole.sky || VrTextureRole.ui => 1,
  };

  /// Builds a [TextureSampling] descriptor tuned for [role].
  TextureSampling samplingForRole(
    VrTextureRole role, {
    bool mipmaps = true,
    int? maxMipmapLevels,
    gpu.SamplerAddressMode addressMode = gpu.SamplerAddressMode.repeat,
  }) {
    final effectiveMips = role == VrTextureRole.ui ? false : mipmaps;
    final aniso = effectiveMips ? anisotropyForRole(role) : 1;
    return TextureSampling(
      mipmaps: effectiveMips,
      maxMipmapLevels: maxMipmapLevels,
      maxAnisotropy: aniso,
      addressMode: role == VrTextureRole.ui
          ? gpu.SamplerAddressMode.clampToEdge
          : addressMode,
    );
  }

  /// Negative mipmap LOD bias (`[-0.5, 0.0]`) recommended when rendering stereo
  /// views at sub-native [renderScale] ahead of spatial upscaling (`SGSR 1`).
  ///
  /// At `renderScale = 0.75`, `log2(0.75) ≈ -0.415`, offsetting the coarser
  /// screen-space UV derivatives of the reduced render target so textures
  /// sample near-native `1.0x` mip detail. Always pair with Toksvig
  /// normal-to-roughness filtering to prevent sub-pixel specular aliasing.
  static double sgsrMipLodBias(double renderScale) {
    if (!renderScale.isFinite || renderScale >= 1.0 || renderScale <= 0.0) {
      return 0.0;
    }
    final raw = math.log(renderScale) / math.ln2;
    return raw.clamp(-0.5, 0.0).toDouble();
  }

  /// Exact or conservative GPU memory footprint of a 2D texture across its
  /// mip chain (`4x4` 16-byte block compression vs 32-bpp `RGBA8888`).
  static int estimateTextureVramBytes(
    int width,
    int height, {
    bool mipmapped = true,
    bool blockCompressed4x4 = false,
  }) {
    if (width <= 0 || height <= 0) return 0;
    final smallest = math.min(width, height);
    final levelCount = mipmapped ? math.max(1, smallest.bitLength - 1) : 1;
    var total = 0;
    for (var level = 0; level < levelCount; level++) {
      final w = math.max(1, width >> level);
      final h = math.max(1, height >> level);
      if (blockCompressed4x4) {
        final bx = (w + 3) >> 2;
        final by = (h + 3) >> 2;
        total += bx * by * 16;
      } else {
        total += w * h * 4;
      }
    }
    return total;
  }
}
