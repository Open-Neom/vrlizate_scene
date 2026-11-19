import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'assets/vr_async_resource_cache.dart';
import 'pbr_texture_synth.dart';
import 'quality_preset.dart';
import 'vr_ktx2_texture.dart';
import 'vr_texture_budget.dart';

export 'pbr_texture_synth.dart'
    show
        PbrCompressedKtx2Request,
        PbrCompressedKtx2Set,
        PbrSurface,
        PbrTextureRequest;

/// Optional host-supplied reader for persisted cooked KTX2 binaries (e.g.
/// local flash cache under `ApplicationSupportDirectory`). Kept callback-based
/// so `vrlizate_scene` stays 100% Web-safe with zero `dart:io` imports.
typedef VrKtx2CacheReader = Future<Uint8List?> Function(String cacheKey);

/// Optional host-supplied writer for persisted cooked KTX2 binaries.
typedef VrKtx2CacheWriter =
    Future<void> Function(String cacheKey, Uint8List bytes);

/// Runtime side of the procedural and photo-scanned PBR textures: generates or
/// cooks sets off the UI thread, uploads hardware block-compressed `KTX2`
/// (`ASTC 4x4` / `ETC2` / `BC1-BC3`) textures with coupled Toksvig specular
/// anti-aliasing mip chains, and dresses [PhysicallyBasedMaterial]s with them.
///
/// Usage mirrors the shipped asphalt loader: build the material with its
/// authored color first (the scene renders immediately), then call [apply]
/// and let the textures arrive a frame or two later. Sets are cached by
/// request + quality budget, so every wall of a castle shares GPU textures.
abstract final class PbrTextureLibrary {
  static const int _cacheLimit = 18;
  static final _uploaded = VrAsyncResourceCache<String, _Uploaded>(
    maxEntries: _cacheLimit,
  );
  static final _cookedSets = VrAsyncResourceCache<Object, _Uploaded>(
    maxEntries: _cacheLimit,
  );

  static VrKtx2CacheReader? _diskCacheRead;
  static VrKtx2CacheWriter? _diskCacheWrite;

  /// Configures an optional persistent KTX2 disk cache so coupled Toksvig
  /// KTX2 textures (both photo-scanned and procedural) only cook once and load
  /// in milliseconds on subsequent launches with zero APK bloat.
  static void configureKtx2DiskCache({
    VrKtx2CacheReader? read,
    VrKtx2CacheWriter? write,
  }) {
    _diskCacheRead = read;
    _diskCacheWrite = write;
  }

  /// Reads a previously cooked KTX2 binary from the configured disk cache,
  /// validating its KTX2 header before returning it.
  static Future<Uint8List?> readCookedKtx2(String key) async {
    final reader = _diskCacheRead;
    if (reader == null) return null;
    try {
      final bytes = await reader(key);
      if (bytes == null || bytes.length < 80) return null;
      final info = VrKtx2Codec.inspectKtx2Header(bytes);
      if (!info.isSupportedRuntime2dTexture) return null;
      return bytes;
    } on Object {
      return null;
    }
  }

  /// Persists a cooked KTX2 binary asynchronously to the configured disk cache.
  static void writeCookedKtx2(String key, Uint8List bytes) {
    final writer = _diskCacheWrite;
    if (writer == null) return;
    unawaited(
      Future<void>(() async {
        try {
          await writer(key, bytes);
        } on Object {
          // Non-fatal: disk cache is strictly an optimization.
        }
      }),
    );
  }

  /// Default VR quality tier used when a caller does not pass `qualityTier`
  /// explicitly. Apps can bind this to their active [VrQualityPreset].
  static VrQualityTier defaultQualityTier = VrQualityTier.high;

  /// Stable identity of a request, for the caches and for tests.
  static String cacheKey(
    PbrTextureRequest r, {
    VrQualityTier? qualityTier,
    VrTextureRole? role,
    bool? compressInVram,
  }) {
    final base =
        '${r.surface.name}/${r.size}/${r.seed}/${r.primary.toRadixString(16)}/'
        '${r.secondary.toRadixString(16)}/${r.repeats}/${r.reliefStrength}';
    if (qualityTier == null &&
        role == null &&
        compressInVram == null &&
        r.toksvigStrength == 0.55) {
      return base;
    }
    return '$base/tok:${r.toksvigStrength}'
        '/tier:${(qualityTier ?? defaultQualityTier).name}'
        '/role:${(role ?? VrTextureRole.heroSurface).name}'
        '/ktx2:${compressInVram ?? true}';
  }

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
  static Future<_Uploaded> _load(
    PbrTextureRequest request, {
    required VrQualityTier tier,
    required VrTextureRole role,
    required bool compressInVram,
  }) {
    final budget = VrTextureBudget.forTier(tier);
    final useKtx2 = compressInVram && budget.preferGpuBlockCompression;
    final key = cacheKey(
      request,
      qualityTier: tier,
      role: role,
      compressInVram: useKtx2,
    );
    return _uploaded.load(key, () async {
      final surfaceSampling = budget.samplingForRole(role);
      final ormSampling = budget.samplingForRole(VrTextureRole.ormData);
      if (useKtx2) {
        try {
          final cachePrefix = 'proc_v2|$key';
          var albedoBytes = await readCookedKtx2('$cachePrefix|color');
          var normalBytes = await readCookedKtx2('$cachePrefix|normal');
          var ormBytes = await readCookedKtx2('$cachePrefix|orm');
          if (albedoBytes == null || normalBytes == null || ormBytes == null) {
            final ktx2Set = await compute(
              PbrTextureSynth.generateCompressedKtx2,
              PbrCompressedKtx2Request(
                request,
                maxColorDimension: budget.maxDimensionForRole(
                  role,
                  content: TextureContent.color,
                ),
                maxNormalDimension: budget.maxDimensionForRole(
                  role,
                  content: TextureContent.normal,
                ),
                maxOrmDimension: budget.maxDimensionForRole(
                  VrTextureRole.ormData,
                  content: TextureContent.data,
                ),
              ),
              debugLabel: 'pbr-ktx2:${request.surface.name}',
            );
            albedoBytes = ktx2Set.albedoKtx2;
            normalBytes = ktx2Set.normalKtx2;
            ormBytes = ktx2Set.ormKtx2;
            writeCookedKtx2('$cachePrefix|color', albedoBytes);
            writeCookedKtx2('$cachePrefix|normal', normalBytes);
            writeCookedKtx2('$cachePrefix|orm', ormBytes);
          }
          final sources = await VrKtx2TextureLoader.loadBatch(
            <VrKtx2LoadRequest>[
              VrKtx2LoadRequest(
                bytes: albedoBytes,
                content: TextureContent.color,
                sampling: surfaceSampling,
              ),
              VrKtx2LoadRequest(
                bytes: normalBytes,
                content: TextureContent.normal,
                sampling: surfaceSampling,
              ),
              VrKtx2LoadRequest(
                bytes: ormBytes,
                content: TextureContent.data,
                sampling: ormSampling,
              ),
            ],
          );
          VrKtx2TextureLoader.recordToksvigMaterial();
          return _Uploaded(
            albedo: sources[0],
            normal: sources[1],
            metallicRoughness: sources[2],
            hasPackedOcclusion: true,
          );
        } on Object catch (error) {
          VrKtx2TextureLoader.recordFallback(
            error,
            uncompressedBytes: request.size * request.size * 4 * 3,
          );
        }
      }

      final pixels = await compute(
        PbrTextureSynth.generate,
        request,
        debugLabel: 'pbr:${request.surface.name}',
      );
      return _Uploaded(
        albedo: Texture2D.fromPixels(
          pixels.albedo,
          pixels.size,
          pixels.size,
          content: TextureContent.color,
          sampling: surfaceSampling,
        ),
        normal: Texture2D.fromPixels(
          pixels.normal,
          pixels.size,
          pixels.size,
          content: TextureContent.normal,
          sampling: surfaceSampling,
        ),
        metallicRoughness: Texture2D.fromPixels(
          pixels.metallicRoughness,
          pixels.size,
          pixels.size,
          content: TextureContent.data,
          sampling: ormSampling,
        ),
        hasPackedOcclusion: true,
      );
    });
  }

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
    VrQualityTier? qualityTier,
    VrTextureRole role = VrTextureRole.heroSurface,
    bool compressInVram = true,
  }) async {
    await Scene.initializeStaticResources();
    if (!isCurrent() || !Scene.isReadyToRender) return false;
    final set = await _load(
      request,
      tier: qualityTier ?? defaultQualityTier,
      role: role,
      compressInVram: compressInVram,
    );
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
    VrQualityTier? qualityTier,
    VrTextureRole role = VrTextureRole.heroSurface,
    bool compressInVram = true,
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
        qualityTier: qualityTier,
        role: role,
        compressInVram: compressInVram,
      );
      if (!ok) return;
    }
  }

  /// Dresses [material] with a photo-scanned set shipped as assets (the
  /// ambientCG layout Riviera uses: `Color`, `NormalGL`, `Roughness` maps).
  ///
  /// When [packPhotoOrm] is `true` (default), `Roughness` and `NormalGL` are
  /// fused on a background isolate into a hardware-compressed `KTX2` ORM map
  /// (`R = micro-cavity AO`, `G = Toksvig-filtered Roughness`, `B = 1.0`
  /// scaled by [metallicFactor]), giving photo surfaces free crevice occlusion
  /// and eliminating VR specular shimmer at 4x–8x lower ORM VRAM cost.
  static Future<bool> applyAsset(
    PhysicallyBasedMaterial material,
    PbrAssetSet set, {
    required bool Function() isCurrent,
    vm.Vector2? tiles,
    vm.Vector4? tint,
    double normalScale = 1.0,
    double roughnessFactor = 1.0,
    double metallicFactor = 0.0,
    TextureSampling? sampling,
    VrQualityTier? qualityTier,
    VrTextureRole role = VrTextureRole.heroSurface,
    bool packPhotoOrm = true,
  }) async {
    await Scene.initializeStaticResources();
    if (!isCurrent() || !Scene.isReadyToRender) return false;
    final budget = VrTextureBudget.forTier(qualityTier ?? defaultQualityTier);
    final effectiveSampling = sampling ?? budget.samplingForRole(role);
    final uploaded = await _loadAsset(
      set,
      effectiveSampling,
      isCurrent,
      budget: budget,
      role: role,
      packPhotoOrm: packPhotoOrm,
    );
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
  /// Unlike [applyAsset], this preserves existing UV transforms and unspecified
  /// factors. Useful for an authored material whose tiling and metalness are
  /// already configured (for example, Riviera Rush asphalt). When
  /// [packPhotoOrm] is `true` (default), all three maps (`Color`, `Normal`,
  /// `ORM`) cook into a coupled Toksvig `KTX2` (`ASTC 4×4` / `ETC2` / `BC`)
  /// pyramid and attach packed crevice AO if `material.occlusionTexture` is
  /// unset.
  static Future<bool> applyAssetMaps(
    PhysicallyBasedMaterial material,
    PbrAssetSet set, {
    required bool Function() isCurrent,
    TextureSampling sampling = const TextureSampling(maxAnisotropy: 8),
    vm.Vector4? tint,
    double? normalScale,
    double? roughnessFactor,
    double? metallicFactor,
    VrQualityTier? qualityTier,
    VrTextureRole role = VrTextureRole.floor,
    bool packPhotoOrm = true,
  }) async {
    await Scene.initializeStaticResources();
    if (!isCurrent() || !Scene.isReadyToRender) return false;
    final budget = VrTextureBudget.forTier(qualityTier ?? defaultQualityTier);
    final uploaded = await _loadAsset(
      set,
      sampling,
      isCurrent,
      budget: budget,
      role: role,
      packPhotoOrm: packPhotoOrm,
    );
    if (uploaded == null || !isCurrent()) return false;
    material
      ..baseColorTexture = uploaded.albedo
      ..normalTexture = uploaded.normal
      ..metallicRoughnessTexture = uploaded.metallicRoughness;
    if (uploaded.hasPackedOcclusion && material.occlusionTexture == null) {
      material
        ..occlusionTexture = uploaded.metallicRoughness
        ..occlusionTextureTransform = material.metallicRoughnessTextureTransform
        ..occlusionStrength = 0.72;
    }
    if (tint != null) material.baseColorFactor = tint;
    if (normalScale != null) material.normalScale = normalScale;
    if (roughnessFactor != null) material.roughnessFactor = roughnessFactor;
    if (metallicFactor != null) material.metallicFactor = metallicFactor;
    return true;
  }

  /// Maps per photo set, bounded independently of live materials. A route
  /// leaving cannot cancel a shared upload needed by another current route.
  static final _assetMaps = VrAsyncResourceCache<Object, TextureSource>(
    maxEntries: _cacheLimit * 3,
  );

  /// [TextureSampling] has identity equality, so key its complete value here.
  @visibleForTesting
  static Object assetMapCacheKey(
    String asset,
    TextureContent content,
    TextureSampling sampling, {
    int? maxSize,
  }) => maxSize == null
      ? (
          asset,
          content,
          sampling.mipmaps,
          sampling.maxMipmapLevels,
          sampling.minFilter,
          sampling.magFilter,
          sampling.mipFilter,
          sampling.maxAnisotropy,
          sampling.addressMode,
        )
      : (
          asset,
          content,
          sampling.mipmaps,
          sampling.maxMipmapLevels,
          sampling.minFilter,
          sampling.magFilter,
          sampling.mipFilter,
          sampling.maxAnisotropy,
          sampling.addressMode,
          maxSize,
        );

  static Future<TextureSource> _loadAssetMap(
    String asset,
    TextureContent content,
    TextureSampling sampling, {
    int? maxSize,
  }) => _assetMaps.load(
    assetMapCacheKey(asset, content, sampling, maxSize: maxSize),
    () => Texture2D.fromAsset(
      asset,
      content: content,
      sampling: sampling,
      maxSize: maxSize,
    ),
  );

  static Future<Uint8List> _loadRawAssetBytes(String assetPath) async {
    final data = await rootBundle.load(assetPath);
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }

  static Future<_Uploaded> _loadCoupledPhotoKtx2Set(
    PbrAssetSet set,
    TextureSampling surfaceSampling,
    TextureSampling ormSampling, {
    required int maxColorDim,
    required int maxNormalDim,
    required int maxOrmDim,
  }) => _cookedSets.load(
    (
      'coupledPhotoKtx2',
      set.resourceKey,
      maxColorDim,
      maxNormalDim,
      maxOrmDim,
      surfaceSampling.maxAnisotropy,
      ormSampling.maxAnisotropy,
    ),
    () async {
      Uint8List? colorKtx2;
      Uint8List? normalKtx2;
      Uint8List? ormKtx2;

      if (set.hasPreCookedKtx2) {
        colorKtx2 = await _loadRawAssetBytes(set.colorKtx2Asset!);
        normalKtx2 = await _loadRawAssetBytes(set.normalKtx2Asset!);
        ormKtx2 = await _loadRawAssetBytes(set.ormKtx2Asset!);
      } else {
        final cachePrefix =
            'photo_v2|${set.colorAsset}|${set.normalAsset}|${set.roughnessAsset}'
            '|$maxColorDim|$maxNormalDim|$maxOrmDim';
        colorKtx2 = await readCookedKtx2('$cachePrefix|color');
        normalKtx2 = await readCookedKtx2('$cachePrefix|normal');
        ormKtx2 = await readCookedKtx2('$cachePrefix|orm');

        if (colorKtx2 == null || normalKtx2 == null || ormKtx2 == null) {
          final decodeDim = maxColorDim > maxNormalDim
              ? maxColorDim
              : maxNormalDim;
          final colorDecoded = await _decodeAssetRgba(
            set.colorAsset,
            maxSize: decodeDim,
          );
          final normDecoded = await _decodeAssetRgba(
            set.normalAsset,
            maxSize: decodeDim,
          );
          final roughDecoded = await _decodeAssetRgba(
            set.roughnessAsset,
            maxSize: decodeDim,
          );
          final cooked = await compute(
            _cookCoupledPhotoSetKtx2Isolate,
            _CoupledPhotoKtx2CookInput(
              colorRgba: colorDecoded.rgba,
              colorW: colorDecoded.width,
              colorH: colorDecoded.height,
              normRgba: normDecoded.rgba,
              normW: normDecoded.width,
              normH: normDecoded.height,
              roughRgba: roughDecoded.rgba,
              roughW: roughDecoded.width,
              roughH: roughDecoded.height,
              maxColorDim: maxColorDim,
              maxNormalDim: maxNormalDim,
              maxOrmDim: maxOrmDim,
              supercompress: _diskCacheWrite != null,
            ),
            debugLabel: 'pbr-photo-ktx2:${set.colorAsset}',
          );
          colorKtx2 = cooked.colorKtx2;
          normalKtx2 = cooked.normalKtx2;
          ormKtx2 = cooked.ormKtx2;
          writeCookedKtx2('$cachePrefix|color', colorKtx2);
          writeCookedKtx2('$cachePrefix|normal', normalKtx2);
          writeCookedKtx2('$cachePrefix|orm', ormKtx2);
        }
      }

      final sources = await VrKtx2TextureLoader.loadBatch(<VrKtx2LoadRequest>[
        VrKtx2LoadRequest(
          bytes: colorKtx2,
          content: TextureContent.color,
          sampling: surfaceSampling,
        ),
        VrKtx2LoadRequest(
          bytes: normalKtx2,
          content: TextureContent.normal,
          sampling: surfaceSampling,
        ),
        VrKtx2LoadRequest(
          bytes: ormKtx2,
          content: TextureContent.data,
          sampling: ormSampling,
        ),
      ]);
      VrKtx2TextureLoader.recordToksvigMaterial();
      return _Uploaded(
        albedo: sources[0],
        normal: sources[1],
        metallicRoughness: sources[2],
        hasPackedOcclusion: true,
      );
    },
  );

  static Future<({Uint8List rgba, int width, int height})> _decodeAssetRgba(
    String assetPath, {
    required int maxSize,
  }) async {
    final data = await rootBundle.load(assetPath);
    final bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final codec = await ui.instantiateImageCodecWithSize(
      buffer,
      getTargetSize: (w, h) {
        final longest = w > h ? w : h;
        if (longest <= maxSize) {
          return ui.TargetImageSize(width: w, height: h);
        }
        final scale = maxSize / longest;
        return ui.TargetImageSize(
          width: (w * scale).round().clamp(1, maxSize),
          height: (h * scale).round().clamp(1, maxSize),
        );
      },
    );
    final frame = await codec.getNextFrame();
    final image = frame.image;
    try {
      final raw = await image.toByteData(
        format: ui.ImageByteFormat.rawStraightRgba,
      );
      if (raw == null) {
        throw StateError('Failed to decode RGBA bytes for $assetPath');
      }
      return (
        rgba: raw.buffer.asUint8List(),
        width: image.width,
        height: image.height,
      );
    } finally {
      image.dispose();
    }
  }

  static Future<_Uploaded?> _loadAsset(
    PbrAssetSet set,
    TextureSampling sampling,
    bool Function() isCurrent, {
    required VrTextureBudget? budget,
    required VrTextureRole role,
    required bool packPhotoOrm,
  }) async {
    if (!isCurrent()) return null;
    final colorMax = budget?.maxDimensionForRole(
      role,
      content: TextureContent.color,
    );
    final normalMax = budget?.maxDimensionForRole(
      role,
      content: TextureContent.normal,
    );
    final ormMax = budget?.maxDimensionForRole(
      VrTextureRole.ormData,
      content: TextureContent.data,
    );

    final useCoupledKtx2 =
        packPhotoOrm && (budget?.preferGpuBlockCompression ?? true);
    if (useCoupledKtx2) {
      final ormSampling = budget != null
          ? budget.samplingForRole(VrTextureRole.ormData)
          : sampling;
      try {
        final uploaded = await _loadCoupledPhotoKtx2Set(
          set,
          sampling,
          ormSampling,
          maxColorDim: colorMax ?? 1024,
          maxNormalDim: normalMax ?? 1024,
          maxOrmDim: ormMax ?? 512,
        );
        if (!isCurrent()) return null;
        return uploaded;
      } on Object catch (error) {
        final cDim = colorMax ?? 1024;
        VrKtx2TextureLoader.recordFallback(
          error,
          uncompressedBytes: cDim * cDim * 4 * 3,
        );
      }
    }

    final color = await _loadAssetMap(
      set.colorAsset,
      TextureContent.color,
      sampling,
      maxSize: colorMax,
    );
    if (!isCurrent()) return null;
    final normal = await _loadAssetMap(
      set.normalAsset,
      TextureContent.normal,
      sampling,
      maxSize: normalMax,
    );
    if (!isCurrent()) return null;

    final roughness = await _loadAssetMap(
      set.roughnessAsset,
      TextureContent.data,
      sampling,
      maxSize: ormMax,
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
    TextureSampling? sampling,
    VrQualityTier? qualityTier,
    VrTextureRole role = VrTextureRole.heroSurface,
    bool packPhotoOrm = true,
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
        qualityTier: qualityTier,
        role: role,
        packPhotoOrm: packPhotoOrm,
      );
      if (!ok) return;
    }
  }

  /// Drops every cached upload (tests, memory pressure).
  static void clearCache() {
    _uploaded.clear();
    _cookedSets.clear();
    _assetMaps.clear();
  }

  @visibleForTesting
  static int get cachedSetCount => _uploaded.completedCount;
}

final class _CoupledPhotoKtx2CookInput {
  const _CoupledPhotoKtx2CookInput({
    required this.colorRgba,
    required this.colorW,
    required this.colorH,
    required this.normRgba,
    required this.normW,
    required this.normH,
    required this.roughRgba,
    required this.roughW,
    required this.roughH,
    required this.maxColorDim,
    required this.maxNormalDim,
    required this.maxOrmDim,
    required this.supercompress,
  });

  final Uint8List colorRgba;
  final int colorW;
  final int colorH;
  final Uint8List normRgba;
  final int normW;
  final int normH;
  final Uint8List roughRgba;
  final int roughW;
  final int roughH;
  final int maxColorDim;
  final int maxNormalDim;
  final int maxOrmDim;
  final bool supercompress;
}

final class _CoupledPhotoKtx2CookResult {
  const _CoupledPhotoKtx2CookResult({
    required this.colorKtx2,
    required this.normalKtx2,
    required this.ormKtx2,
  });

  final Uint8List colorKtx2;
  final Uint8List normalKtx2;
  final Uint8List ormKtx2;
}

_CoupledPhotoKtx2CookResult _cookCoupledPhotoSetKtx2Isolate(
  _CoupledPhotoKtx2CookInput input,
) {
  // Store B = 1.0 (255) so `material.metallicFactor` continues to scale
  // dielectric (0.0) and metallic (e.g. MetalPlates 0.9) photo sets identically
  // to grayscale Roughness JPGs while R carries cavity AO (from both normal
  // divergence and albedo crevice luminance) and G carries Toksvig-filtered
  // perceptual roughness.
  final baseOrm = VrToksvigFilter.packPhotoRoughnessAndNormalToOrm(
    roughnessRgba: input.roughRgba,
    roughnessWidth: input.roughW,
    roughnessHeight: input.roughH,
    normalRgba: input.normRgba,
    normalWidth: input.normW,
    normalHeight: input.normH,
    albedoRgba: input.colorRgba,
    albedoWidth: input.colorW,
    albedoHeight: input.colorH,
    metallic: 1.0,
  );
  // Build coupled linear-light sRGB albedo, unit-renormalized normal, and
  // cumulative multi-level Toksvig ORM mip chains in one pass.
  final albedoChain = VrToksvigFilter.downsampleColorMipChain(
    input.colorRgba,
    input.colorW,
    input.colorH,
    maxBaseDimension: input.maxColorDim,
  );
  final dummyAlbedo = Uint8List(4)..fillRange(0, 4, 255);
  final coupled = VrToksvigFilter.generateCoupledPbrMipChain(
    albedoRgba: dummyAlbedo,
    normalRgba: input.normRgba,
    ormRgba: baseOrm,
    width: input.normW,
    height: input.normH,
    maxNormalDimension: input.maxNormalDim,
    maxOrmDimension: input.maxOrmDim,
  );
  return _CoupledPhotoKtx2CookResult(
    colorKtx2: VrKtx2Codec.encodeMipChainToKtx2(
      albedoChain,
      srgb: true,
      supercompress: input.supercompress,
    ),
    normalKtx2: VrKtx2Codec.encodeMipChainToKtx2(
      coupled.normal,
      srgb: false,
      supercompress: input.supercompress,
    ),
    ormKtx2: VrKtx2Codec.encodeMipChainToKtx2(
      coupled.orm,
      srgb: false,
      supercompress: input.supercompress,
    ),
  );
}

class _Uploaded {
  const _Uploaded({
    required this.albedo,
    required this.normal,
    required this.metallicRoughness,
    required this.hasPackedOcclusion,
  });

  final TextureSource albedo;
  final TextureSource normal;
  final TextureSource metallicRoughness;
  final bool hasPackedOcclusion;
}

/// Asset paths of one photo-scanned PBR set (ambientCG `*_Color`,
/// `*_NormalGL`, `*_Roughness` JPGs, and optional pre-cooked `.ktx2`
/// companions). Ship them with a LICENSE.md and SHA-256 table like
/// `assets/riviera_rush/`.
class PbrAssetSet {
  const PbrAssetSet({
    required this.colorAsset,
    required this.normalAsset,
    required this.roughnessAsset,
    this.colorKtx2Asset,
    this.normalKtx2Asset,
    this.ormKtx2Asset,
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
  final String? colorKtx2Asset;
  final String? normalKtx2Asset;
  final String? ormKtx2Asset;
  final double tileWidthMeters;
  final double tileHeightMeters;

  bool get hasPreCookedKtx2 =>
      colorKtx2Asset != null &&
      normalKtx2Asset != null &&
      ormKtx2Asset != null;

  /// Identity of the decoded maps. UV scale is applied per material and does
  /// not require another upload; changing relief or roughness maps does.
  (String, String, String) get resourceKey => (
    colorKtx2Asset ?? colorAsset,
    normalKtx2Asset ?? normalAsset,
    ormKtx2Asset ?? roughnessAsset,
  );

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
