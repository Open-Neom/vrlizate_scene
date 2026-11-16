import 'package:flutter_scene/scene.dart' as fs;

typedef _MaterialKey = (
  fs.Material,
  fs.TextureSource?,
  fs.TextureSource?,
  fs.TextureSource?,
  fs.TextureSource?,
  fs.TextureSource?,
  fs.TextureSource?,
);

/// Reuses imported materials unless a binding overrides one of their maps.
///
/// Preserves baked lightmaps (`TEXCOORD_1`, RGBM), normal/occlusion strengths,
/// emissive HDR strength, and glTF PBR extensions (`ior`, `specular`, `clearcoat`)
/// when cloning a [fs.PhysicallyBasedMaterial] for texture overrides. Also
/// supports optional per-slot material targeting ([targetMaterialName]) so
/// multi-material GLBs keep non-targeted submeshes intact.
final class VrSceneMaterialCache {
  final _materials = <_MaterialKey, fs.Material>{};

  fs.Material resolve(
    fs.Material original, {
    fs.TextureSource? baseColor,
    fs.TextureSource? normal,
    fs.TextureSource? metallicRoughness,
    fs.TextureSource? emissive,
    fs.TextureSource? occlusion,
    fs.TextureSource? lightmap,
    String? targetMaterialName,
  }) {
    if (original is! fs.UnlitMaterial &&
        original is! fs.PhysicallyBasedMaterial) {
      throw const FormatException('Unsupported portable material.');
    }
    if (targetMaterialName != null && original.name != targetMaterialName) {
      return original;
    }
    final key = (
      original,
      baseColor,
      normal,
      metallicRoughness,
      emissive,
      occlusion,
      lightmap,
    );
    return _materials.putIfAbsent(key, () {
      if (baseColor == null &&
          normal == null &&
          metallicRoughness == null &&
          emissive == null &&
          occlusion == null &&
          lightmap == null) {
        // Preserve the importer texture, sampler and all material properties.
        return original;
      }
      fs.TextureTransform transform(fs.TextureTransform source) =>
          fs.TextureTransform(
            offset: source.offset.clone(),
            scale: source.scale.clone(),
            rotation: source.rotation,
          );
      if (original is fs.UnlitMaterial) {
        return fs.UnlitMaterial(
            colorTexture: baseColor ?? original.baseColorTexture,
          )
          ..name = original.name
          ..baseColorFactor = original.baseColorFactor.clone()
          ..baseColorTextureTransform = baseColor == null
              ? transform(original.baseColorTextureTransform)
              : fs.TextureTransform()
          ..baseColorTextureTexCoord = baseColor == null
              ? original.baseColorTextureTexCoord
              : 0
          ..alphaMode = original.alphaMode
          ..vertexColorWeight = original.vertexColorWeight
          ..doubleSided = original.doubleSided
          ..displayReferred = original.displayReferred;
      }
      final physical = original as fs.PhysicallyBasedMaterial;
      return fs.PhysicallyBasedMaterial()
        ..name = physical.name
        ..environment = physical.environment
        ..baseColorFactor = physical.baseColorFactor.clone()
        ..roughnessFactor = physical.roughnessFactor
        ..metallicFactor = physical.metallicFactor
        ..normalScale = physical.normalScale
        ..emissiveFactor = physical.emissiveFactor.clone()
        ..emissiveStrength = physical.emissiveStrength
        ..occlusionStrength = physical.occlusionStrength
        ..alphaMode = physical.alphaMode
        ..alphaCutoff = physical.alphaCutoff
        ..vertexColorWeight = physical.vertexColorWeight
        ..doubleSided = physical.doubleSided
        ..ior = physical.ior
        ..specular = physical.specular
        ..specularColor = physical.specularColor.clone()
        ..specularTexture = physical.specularTexture
        ..specularTextureTransform = transform(
          physical.specularTextureTransform,
        )
        ..specularTextureTexCoord = physical.specularTextureTexCoord
        ..specularColorTexture = physical.specularColorTexture
        ..specularColorTextureTransform = transform(
          physical.specularColorTextureTransform,
        )
        ..specularColorTextureTexCoord = physical.specularColorTextureTexCoord
        ..clearcoat = physical.clearcoat
        ..clearcoatRoughness = physical.clearcoatRoughness
        ..clearcoatNormalScale = physical.clearcoatNormalScale.clone()
        ..clearcoatTexture = physical.clearcoatTexture
        ..clearcoatTextureTransform = transform(
          physical.clearcoatTextureTransform,
        )
        ..clearcoatTextureTexCoord = physical.clearcoatTextureTexCoord
        ..clearcoatRoughnessTexture = physical.clearcoatRoughnessTexture
        ..clearcoatRoughnessTextureTransform = transform(
          physical.clearcoatRoughnessTextureTransform,
        )
        ..clearcoatRoughnessTextureTexCoord =
            physical.clearcoatRoughnessTextureTexCoord
        ..clearcoatNormalTexture = physical.clearcoatNormalTexture
        ..clearcoatNormalTextureTransform = transform(
          physical.clearcoatNormalTextureTransform,
        )
        ..clearcoatNormalTextureTexCoord =
            physical.clearcoatNormalTextureTexCoord
        ..baseColorTexture = baseColor ?? physical.baseColorTexture
        ..baseColorTextureTransform = baseColor == null
            ? transform(physical.baseColorTextureTransform)
            : fs.TextureTransform()
        ..baseColorTextureTexCoord = baseColor == null
            ? physical.baseColorTextureTexCoord
            : 0
        ..normalTexture = normal ?? physical.normalTexture
        ..normalTextureTransform = normal == null
            ? transform(physical.normalTextureTransform)
            : fs.TextureTransform()
        ..normalTextureTexCoord = normal == null
            ? physical.normalTextureTexCoord
            : 0
        ..metallicRoughnessTexture =
            metallicRoughness ?? physical.metallicRoughnessTexture
        ..metallicRoughnessTextureTransform = metallicRoughness == null
            ? transform(physical.metallicRoughnessTextureTransform)
            : fs.TextureTransform()
        ..metallicRoughnessTextureTexCoord = metallicRoughness == null
            ? physical.metallicRoughnessTextureTexCoord
            : 0
        ..emissiveTexture = emissive ?? physical.emissiveTexture
        ..emissiveTextureTransform = emissive == null
            ? transform(physical.emissiveTextureTransform)
            : fs.TextureTransform()
        ..emissiveTextureTexCoord = emissive == null
            ? physical.emissiveTextureTexCoord
            : 0
        ..occlusionTexture = occlusion ?? physical.occlusionTexture
        ..occlusionTextureTransform = occlusion == null
            ? transform(physical.occlusionTextureTransform)
            : fs.TextureTransform()
        ..occlusionTextureTexCoord = occlusion == null
            ? physical.occlusionTextureTexCoord
            : 0
        ..lightmapTexture = lightmap ?? physical.lightmapTexture
        ..lightmapTextureTransform = lightmap == null
            ? transform(physical.lightmapTextureTransform)
            : fs.TextureTransform()
        ..lightmapTextureTexCoord = lightmap == null
            ? physical.lightmapTextureTexCoord
            : 1
        ..lightmapIntensity = physical.lightmapIntensity
        ..lightmapRgbm = physical.lightmapRgbm;
    });
  }
}
