import 'package:flutter_scene/scene.dart' as fs;
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;
import 'package:vrlizate_scene/src/pbr_texture_library.dart';
import 'package:vrlizate_scene/src/vr_look.dart';
import 'package:vrlizate_scene/src/vr_scene_material_cache.dart';

void main() {
  test(
    'unchanged PBR and unlit materials preserve exact imported identity',
    () {
      final cache = VrSceneMaterialCache();
      for (final material in <fs.Material>[
        fs.UnlitMaterial(),
        fs.PhysicallyBasedMaterial(),
      ]) {
        expect(cache.resolve(material), same(material));
        expect(cache.resolve(material), same(material));
      }
    },
  );

  test('PBR overrides share copies without changing source or other maps', () {
    final cache = VrSceneMaterialCache();
    final embedded = _TextureStub(), replacement = _TextureStub();
    final original = fs.PhysicallyBasedMaterial()
      ..name = 'road'
      ..baseColorFactor = vm.Vector4(.2, .3, .4, .5)
      ..emissiveFactor = vm.Vector4(.1, .2, .3, 0)
      ..roughnessFactor = .95
      ..metallicFactor = .2
      ..alphaMode = fs.AlphaMode.mask
      ..alphaCutoff = .3
      ..vertexColorWeight = .6
      ..doubleSided = true
      ..baseColorTexture = embedded
      ..baseColorTextureTexCoord = 1
      ..baseColorTextureTransform = fs.TextureTransform(scale: vm.Vector2(3, 4))
      ..normalTexture = embedded
      ..normalTextureTexCoord = 1
      ..normalTextureTransform = fs.TextureTransform(
        offset: vm.Vector2(.2, .3),
        scale: vm.Vector2(5, 6),
        rotation: .4,
      );
    final copy =
        cache.resolve(original, baseColor: replacement)
            as fs.PhysicallyBasedMaterial;
    expect(cache.resolve(original, baseColor: replacement), same(copy));
    expect(copy, isNot(same(original)));
    expect(copy.name, original.name);
    expect(copy.baseColorFactor, original.baseColorFactor);
    expect(copy.emissiveFactor, original.emissiveFactor);
    expect(copy.roughnessFactor, .95);
    expect(copy.metallicFactor, .2);
    expect(copy.alphaMode, fs.AlphaMode.mask);
    expect(copy.alphaCutoff, .3);
    expect(copy.vertexColorWeight, .6);
    expect(copy.doubleSided, isTrue);
    expect(copy.baseColorTexture, same(replacement));
    expect(copy.baseColorTextureTexCoord, 0);
    expect(copy.baseColorTextureTransform.scale, vm.Vector2.all(1));
    expect(copy.normalTexture, same(embedded));
    expect(copy.normalTextureTexCoord, 1);
    expect(copy.normalTextureTransform.offset, vm.Vector2(.2, .3));
    expect(copy.normalTextureTransform.scale, vm.Vector2(5, 6));
    expect(copy.normalTextureTransform.rotation, .4);

    copy.baseColorFactor.x = .9;
    copy.emissiveFactor.y = .8;
    copy.normalTextureTransform.scale.x = 9;
    expect(original.baseColorFactor.x, closeTo(.2, 1e-7));
    expect(original.emissiveFactor.y, closeTo(.2, 1e-7));
    expect(original.normalTextureTransform.scale, vm.Vector2(5, 6));
    expect(original.baseColorTexture, same(embedded));
    expect(original.baseColorTextureTexCoord, 1);
  });

  test('unlit overrides retain their unlit properties and independent UVs', () {
    final cache = VrSceneMaterialCache();
    final embedded = _TextureStub(), replacement = _TextureStub();
    final original = fs.UnlitMaterial(colorTexture: embedded)
      ..displayReferred = true
      ..baseColorTextureTransform = fs.TextureTransform(
        scale: vm.Vector2(3, 4),
      );
    final untouchedColor =
        cache.resolve(original, normal: replacement) as fs.UnlitMaterial;
    expect(untouchedColor.baseColorTexture, same(embedded));
    expect(untouchedColor.displayReferred, isTrue);
    expect(untouchedColor.baseColorTextureTransform.scale, vm.Vector2(3, 4));
    untouchedColor.baseColorTextureTransform.scale.x = 8;
    expect(original.baseColorTextureTransform.scale, vm.Vector2(3, 4));
    final changed =
        cache.resolve(original, baseColor: replacement) as fs.UnlitMaterial;
    expect(changed.baseColorTexture, same(replacement));
    expect(changed.baseColorTextureTransform.scale, vm.Vector2.all(1));
    expect(cache.resolve(original, baseColor: replacement), same(changed));
  });

  test('unsupported materials retain the portable adapter error contract', () {
    expect(
      () => VrSceneMaterialCache().resolve(_UnsupportedMaterial()),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          'Unsupported portable material.',
        ),
      ),
    );
  });

  test('photo uploads distinguish roles, assets and sampling values', () {
    Object key(
      fs.TextureSampling sampling, {
      String asset = 'asphalt.jpg',
      fs.TextureContent content = fs.TextureContent.color,
    }) => PbrTextureLibrary.assetMapCacheKey(asset, content, sampling);

    fs.TextureSampling sample(int anisotropy) =>
        fs.TextureSampling(maxAnisotropy: anisotropy);
    final four = sample(4);
    final equivalent = sample(4);
    final eight = sample(8);
    expect(identical(four, equivalent), isFalse);
    expect(key(four), key(equivalent));
    expect(key(four), isNot(key(eight)));
    expect(key(four), isNot(key(four, asset: 'different.jpg')));
    expect(key(four), isNot(key(four, content: fs.TextureContent.normal)));
    expect(
      key(four),
      isNot(key(const fs.TextureSampling(maxAnisotropy: 4, mipmaps: false))),
    );
    expect(
      key(four),
      isNot(
        key(const fs.TextureSampling(maxAnisotropy: 4, maxMipmapLevels: 2)),
      ),
    );
  });

  test('linear palette materials preserve color and explicit emission', () {
    final material = VrLook.material(
      .2,
      .4,
      .6,
      roughness: .95,
      metallic: .3,
      emission: 2,
    );
    expect(material.baseColorFactor, vm.Vector4(.2, .4, .6, 1));
    expect(material.emissiveFactor, vm.Vector4(.4, .8, 1.2, 0));
    expect(material.roughnessFactor, .95);
    expect(material.metallicFactor, .3);
    expect(material.vertexColorWeight, 0);
    expect(
      VrLook.material(.2, .4, .6).emissiveFactor,
      fs.PhysicallyBasedMaterial().emissiveFactor,
    );
    expect(VrLook.material(.2, .4, .6), isNot(same(material)));
  });
}

final class _TextureStub implements fs.TextureSource {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('No GPU access');
}

final class _UnsupportedMaterial implements fs.Material {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('No GPU access');
}
