import 'package:flutter/foundation.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'assets/vr_async_resource_cache.dart';
import 'pbr_texture_synth.dart';

export 'pbr_texture_synth.dart' show PbrSurface, PbrTextureRequest;

/// Runtime side of the procedural PBR textures: generates a set off the UI
/// thread, uploads it once, and dresses [PhysicallyBasedMaterial]s with it.
///
/// Usage mirrors the shipped asphalt loader: build the material with its
/// authored color first (the scene renders immediately), then call [apply]
/// and let the textures arrive a frame or two later. Sets are cached by
/// request, so every wall of a castle shares three GPU textures.
abstract final class PbrTextureLibrary {
  static const int _cacheLimit = 14;
  static final _uploaded = VrAsyncResourceCache<String, _Uploaded>(
    maxEntries: _cacheLimit,
  );

  /// Stable identity of a request, for the caches and for tests.
  static String cacheKey(PbrTextureRequest r) =>
      '${r.surface.name}/${r.size}/${r.seed}/${r.primary.toRadixString(16)}/'
      '${r.secondary.toRadixString(16)}/${r.repeats}/${r.reliefStrength}';

  /// UV repeats so that one texture tile spans [tileMeters] of a surface
  /// [worldWidth] × [worldHeight] meters wide. Primitives map 0..1 across
  /// each face, so the scale is the face size over the tile size.
  static vm.Vector2 tilesFor(
    double worldWidth,
    double worldHeight, {
    required double tileMeters,
  }) => vm.Vector2(
    (worldWidth / tileMeters).clamp(0.01, 4096.0),
    (worldHeight / tileMeters).clamp(0.01, 4096.0),
  );

  /// Generates (in an isolate) and uploads the set for [request], or returns
  /// the cached upload. Requires GPU resources; callers gate on
  /// `Scene.isReadyToRender`.
  static Future<_Uploaded> _load(PbrTextureRequest request) =>
      _uploaded.load(cacheKey(request), () async {
        final pixels = await compute(
          PbrTextureSynth.generate,
          request,
          debugLabel: 'pbr:${request.surface.name}',
        );
        const sampling = TextureSampling(maxAnisotropy: 8);
        return _Uploaded(
          albedo: Texture2D.fromPixels(
            pixels.albedo,
            pixels.size,
            pixels.size,
            content: TextureContent.color,
            sampling: sampling,
          ),
          normal: Texture2D.fromPixels(
            pixels.normal,
            pixels.size,
            pixels.size,
            content: TextureContent.normal,
            sampling: sampling,
          ),
          metallicRoughness: Texture2D.fromPixels(
            pixels.metallicRoughness,
            pixels.size,
            pixels.size,
            content: TextureContent.data,
            sampling: sampling,
          ),
          hasPackedOcclusion: true,
        );
      });

  /// Dresses [material] with the generated set of [request].
  ///
  /// [tiles] is the UV repeat (see [tilesFor]); [tint] multiplies the albedo
  /// (white keeps the texture's own colors); [normalScale] scales the relief
  /// in the shader on top of the request's [PbrTextureRequest.reliefStrength].
  /// Roughness and metalness come from the texture, so the material's
  /// factors are set to 1 unless [roughnessFactor]/[metallicFactor] override
  /// them (a dielectric texture stays dielectric regardless).
  ///
  /// Returns false, changing nothing, when [isCurrent] reports the caller is
  /// gone or the GPU is not ready — a departed route never mutates an
  /// orphaned material.
  static Future<bool> apply(
    PhysicallyBasedMaterial material,
    PbrTextureRequest request, {
    required bool Function() isCurrent,
    vm.Vector2? tiles,
    vm.Vector4? tint,
    double normalScale = 1.0,
    double roughnessFactor = 1.0,
    double metallicFactor = 1.0,
  }) async {
    await Scene.initializeStaticResources();
    if (!isCurrent() || !Scene.isReadyToRender) return false;
    final set = await _load(request);
    if (!isCurrent()) return false;
    _dress(
      material,
      set,
      tiles: tiles,
      tint: tint,
      normalScale: normalScale,
      roughnessFactor: roughnessFactor,
      metallicFactor: metallicFactor,
    );
    return true;
  }

  static void _dress(
    PhysicallyBasedMaterial material,
    _Uploaded set, {
    required vm.Vector2? tiles,
    required vm.Vector4? tint,
    required double normalScale,
    required double roughnessFactor,
    required double metallicFactor,
  }) {
    final scale = tiles ?? vm.Vector2(1, 1);
    material
      ..baseColorTexture = set.albedo
      ..baseColorTextureTransform = TextureTransform(scale: scale.clone())
      ..normalTexture = set.normal
      ..normalTextureTransform = TextureTransform(scale: scale.clone())
      ..normalScale = normalScale
      ..metallicRoughnessTexture = set.metallicRoughness
      ..metallicRoughnessTextureTransform = TextureTransform(
        scale: scale.clone(),
      )
      ..roughnessFactor = roughnessFactor
      ..metallicFactor = metallicFactor
      ..baseColorFactor = tint ?? vm.Vector4(1, 1, 1, 1);
    if (set.hasPackedOcclusion) {
      material
        ..occlusionTexture = set.metallicRoughness
        ..occlusionTextureTransform = TextureTransform(scale: scale.clone())
        ..occlusionStrength = 0.75;
    } else {
      material.occlusionTexture = null;
    }
  }

  /// Applies one request to several materials that share it (e.g. every
  /// tower of a castle), with one generation and one upload.
  static Future<void> applyAll(
    Iterable<PhysicallyBasedMaterial> materials,
    PbrTextureRequest request, {
    required bool Function() isCurrent,
    vm.Vector2? tiles,
    vm.Vector4? tint,
    double normalScale = 1.0,
    double roughnessFactor = 1.0,
    double metallicFactor = 1.0,
  }) async {
    for (final material in materials) {
      final ok = await apply(
        material,
        request,
        isCurrent: isCurrent,
        tiles: tiles,
        tint: tint,
        normalScale: normalScale,
        roughnessFactor: roughnessFactor,
        metallicFactor: metallicFactor,
      );
      if (!ok) return;
    }
  }

  /// Dresses [material] with a photo-scanned set shipped as assets (the
  /// ambientCG layout Riviera uses: `Color`, `NormalGL`, `Roughness` maps).
  /// Same tiling, tint and guard semantics as [apply]; the roughness map's
  /// gray value lands in G so metalness stays with [metallicFactor].
  static Future<bool> applyAsset(
    PhysicallyBasedMaterial material,
    PbrAssetSet set, {
    required bool Function() isCurrent,
    vm.Vector2? tiles,
    vm.Vector4? tint,
    double normalScale = 1.0,
    double roughnessFactor = 1.0,
    double metallicFactor = 0.0,
    TextureSampling sampling = const TextureSampling(maxAnisotropy: 8),
  }) async {
    await Scene.initializeStaticResources();
    if (!isCurrent() || !Scene.isReadyToRender) return false;
    final uploaded = await _loadAsset(set, sampling, isCurrent);
    if (uploaded == null || !isCurrent()) return false;
    _dress(
      material,
      uploaded,
      tiles: tiles,
      tint: tint,
      normalScale: normalScale,
      roughnessFactor: roughnessFactor,
      metallicFactor: metallicFactor,
    );
    return true;
  }

  /// Applies only the three photo maps and explicitly supplied factors.
  ///
  /// Unlike [applyAsset], this preserves existing UV transforms, occlusion and
  /// unspecified factors. Useful for an authored material whose tiling and
  /// metalness are already configured. Every decode is followed by [isCurrent]
  /// before the next map is requested; the material changes only after all
  /// three maps are ready and the caller is still current.
  static Future<bool> applyAssetMaps(
    PhysicallyBasedMaterial material,
    PbrAssetSet set, {
    required bool Function() isCurrent,
    TextureSampling sampling = const TextureSampling(maxAnisotropy: 8),
    vm.Vector4? tint,
    double? normalScale,
    double? roughnessFactor,
    double? metallicFactor,
  }) async {
    await Scene.initializeStaticResources();
    if (!isCurrent() || !Scene.isReadyToRender) return false;
    final uploaded = await _loadAsset(set, sampling, isCurrent);
    if (uploaded == null || !isCurrent()) return false;
    material
      ..baseColorTexture = uploaded.albedo
      ..normalTexture = uploaded.normal
      ..metallicRoughnessTexture = uploaded.metallicRoughness;
    if (tint != null) material.baseColorFactor = tint;
    if (normalScale != null) material.normalScale = normalScale;
    if (roughnessFactor != null) material.roughnessFactor = roughnessFactor;
    if (metallicFactor != null) material.metallicFactor = metallicFactor;
    return true;
  }

  /// Three maps per photo set, bounded independently of live materials. A route
  /// leaving cannot cancel a shared upload needed by another current route.
  static final _assetMaps = VrAsyncResourceCache<Object, Texture2D>(
    maxEntries: _cacheLimit * 3,
  );

  /// [TextureSampling] has identity equality, so key its complete value here.
  @visibleForTesting
  static Object assetMapCacheKey(
    String asset,
    TextureContent content,
    TextureSampling sampling,
  ) => (
    asset,
    content,
    sampling.mipmaps,
    sampling.maxMipmapLevels,
    sampling.minFilter,
    sampling.magFilter,
    sampling.mipFilter,
    sampling.maxAnisotropy,
    sampling.addressMode,
  );

  static Future<Texture2D> _loadAssetMap(
    String asset,
    TextureContent content,
    TextureSampling sampling,
  ) => _assetMaps.load(
    assetMapCacheKey(asset, content, sampling),
    () => Texture2D.fromAsset(asset, content: content, sampling: sampling),
  );

  static Future<_Uploaded?> _loadAsset(
    PbrAssetSet set,
    TextureSampling sampling,
    bool Function() isCurrent,
  ) async {
    if (!isCurrent()) return null;
    final color = await _loadAssetMap(
      set.colorAsset,
      TextureContent.color,
      sampling,
    );
    if (!isCurrent()) return null;
    final normal = await _loadAssetMap(
      set.normalAsset,
      TextureContent.normal,
      sampling,
    );
    if (!isCurrent()) return null;
    final roughness = await _loadAssetMap(
      set.roughnessAsset,
      TextureContent.data,
      sampling,
    );
    if (!isCurrent()) return null;
    return _Uploaded(
      albedo: color,
      normal: normal,
      metallicRoughness: roughness,
      hasPackedOcclusion: false,
    );
  }

  /// [applyAsset] for several materials sharing one photo set.
  static Future<void> applyAssetAll(
    Iterable<PhysicallyBasedMaterial> materials,
    PbrAssetSet set, {
    required bool Function() isCurrent,
    vm.Vector2? tiles,
    vm.Vector4? tint,
    double normalScale = 1.0,
    double roughnessFactor = 1.0,
    double metallicFactor = 0.0,
    TextureSampling sampling = const TextureSampling(maxAnisotropy: 8),
  }) async {
    for (final material in materials) {
      final ok = await applyAsset(
        material,
        set,
        isCurrent: isCurrent,
        tiles: tiles,
        tint: tint,
        normalScale: normalScale,
        roughnessFactor: roughnessFactor,
        metallicFactor: metallicFactor,
        sampling: sampling,
      );
      if (!ok) return;
    }
  }

  /// Drops every cached upload (tests, memory pressure).
  @visibleForTesting
  static void clearCache() {
    _uploaded.clear();
    _assetMaps.clear();
  }

  @visibleForTesting
  static int get cachedSetCount => _uploaded.completedCount;
}

class _Uploaded {
  const _Uploaded({
    required this.albedo,
    required this.normal,
    required this.metallicRoughness,
    required this.hasPackedOcclusion,
  });

  final Texture2D albedo;
  final Texture2D normal;
  final Texture2D metallicRoughness;
  final bool hasPackedOcclusion;
}

/// Asset paths of one photo-scanned PBR set (ambientCG `*_Color`,
/// `*_NormalGL`, `*_Roughness` JPGs). Ship them with a LICENSE.md and
/// SHA-256 table like `assets/riviera_rush/`.
class PbrAssetSet {
  const PbrAssetSet({
    required this.colorAsset,
    required this.normalAsset,
    required this.roughnessAsset,
    this.tileWidthMeters = 1.0,
    this.tileHeightMeters = 1.0,
  });

  /// `ambientCG` naming: `assets/<demo>/<Id>_1K-JPG_` plus the map suffix.
  /// [tileWidthMeters]/[tileHeightMeters] is the physical size one tile
  /// covers (ambientCG lists it for many sets).
  const PbrAssetSet.ambientCg(
    String root, {
    double tileWidthMeters = 1.0,
    double tileHeightMeters = 1.0,
  }) : this(
         colorAsset: '${root}Color.jpg',
         normalAsset: '${root}NormalGL.jpg',
         roughnessAsset: '${root}Roughness.jpg',
         tileWidthMeters: tileWidthMeters,
         tileHeightMeters: tileHeightMeters,
       );

  final String colorAsset;
  final String normalAsset;
  final String roughnessAsset;
  final double tileWidthMeters;
  final double tileHeightMeters;

  /// Identity of the decoded maps. UV scale is applied per material and does
  /// not require another upload; changing relief or roughness maps does.
  (String, String, String) get resourceKey =>
      (colorAsset, normalAsset, roughnessAsset);

  /// UV repeats so the set keeps its physical scale on a face
  /// [worldWidth] × [worldHeight] meters wide.
  vm.Vector2 tilesFor(double worldWidth, double worldHeight) => vm.Vector2(
    (worldWidth / tileWidthMeters).clamp(0.01, 4096.0),
    (worldHeight / tileHeightMeters).clamp(0.01, 4096.0),
  );
}

/// The photo-scanned CC0 sets shipped under `assets/textures/` (see each
/// folder's LICENSE.md for provenance and SHA-256).
abstract final class PbrPhotoSets {
  /// ambientCG Bricks 089: dark grey medieval stone blocks, 2.2 × 1.1 m.
  static const stoneBricks = PbrAssetSet.ambientCg(
    'assets/textures/Bricks089/Bricks089_1K-JPG_',
    tileWidthMeters: 2.2,
    tileHeightMeters: 1.1,
  );

  /// ambientCG Marble 012: glossy grey marble; ~2 m works for floors.
  static const marble = PbrAssetSet.ambientCg(
    'assets/textures/Marble012/Marble012_1K-JPG_',
    tileWidthMeters: 2.0,
    tileHeightMeters: 2.0,
  );

  /// ambientCG Grass 004: dense garden lawn, 1.4 × 1.4 m.
  static const grass = PbrAssetSet.ambientCg(
    'assets/textures/Grass004/Grass004_1K-JPG_',
    tileWidthMeters: 1.4,
    tileHeightMeters: 1.4,
  );

  /// ambientCG Metal Plates 017 A: sci-fi metal panels; ~1.6 m per tile.
  static const metalPanels = PbrAssetSet.ambientCg(
    'assets/textures/MetalPlates017A/MetalPlates017A_1K-JPG_',
    tileWidthMeters: 1.6,
    tileHeightMeters: 1.6,
  );
}
