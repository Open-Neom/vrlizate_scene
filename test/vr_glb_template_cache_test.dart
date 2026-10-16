import 'dart:async';

import 'package:flutter_scene/scene.dart' as fs;
// Construct real CPU animation channels without loading a GPU asset.
// ignore: implementation_imports
import 'package:flutter_scene/src/animation.dart'
    show AnimationChannel, BindKey, PropertyResolver;
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;
import 'package:vrlizate_scene/vrlizate_scene.dart';

// No buffers or shaders are needed to verify resource identity across clones.
class _CpuGeometry extends fs.Geometry {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

fs.Node _actorTemplate() {
  final joint = fs.Node(name: 'joint')..isJoint = true;
  final body = fs.Node(name: 'body')
    ..skin = (fs.Skin()
      ..joints.add(joint)
      ..inverseBindMatrices.add(vm.Matrix4.identity()));
  final root = fs.Node(name: 'actor')
    ..add(joint)
    ..add(body);
  for (final name in VrActorAnimation.defaultClipNames.values) {
    root.addParsedAnimation(
      fs.Animation(
        name: name,
        channels: [
          AnimationChannel(
            bindTarget: BindKey(nodeName: 'joint'),
            resolver: PropertyResolver.makeTranslationTimeline(
              [0, 1],
              [vm.Vector3.zero(), vm.Vector3(10, 0, 0)],
            ),
          ),
        ],
      ),
    );
  }
  return root;
}

void main() {
  test(
    'deduplicates import and returns independent rig/playback instances',
    () async {
      var calls = 0;
      final load = Completer<fs.Node>();
      final cache = VrGlbTemplateCache(
        loader: (_, {maxTextureSize}) {
          calls++;
          return load.future;
        },
      );
      addTearDown(cache.dispose);
      final first = cache.instantiate('actor.glb');
      final second = cache.instantiate('actor.glb');
      expect(calls, 1);
      final template = _actorTemplate();
      load.complete(template);
      final a = await first;
      final b = await second;
      expect(identical(a, b), isFalse);
      expect(identical(a, template), isFalse);
      expect(a.parent, isNull);
      expect(b.parent, isNull);
      expect(
        identical(
          a.getChildByName('body')!.skin!.joints.single,
          a.getChildByName('joint'),
        ),
        isTrue,
      );
      expect(
        identical(
          b.getChildByName('body')!.skin!.joints.single,
          b.getChildByName('joint'),
        ),
        isTrue,
      );
      final animationA = VrActorAnimation(actor: a);
      final animationB = VrActorAnimation(actor: b, autoplay: false);
      addTearDown(animationA.dispose);
      addTearDown(animationB.dispose);
      a.scenePrePass(.25);
      b.scenePrePass(.25);
      expect(animationA.playbackTime, closeTo(.25, 1e-6));
      expect(animationB.playbackTime, 0);
      expect(a.getChildByName('joint')!.position.x, closeTo(2.5, 1e-6));
      expect(b.getChildByName('joint')!.position.x, 0);
      expect(template.getChildByName('joint')!.position.x, 0);
    },
  );

  test('shares geometry but permits instance-owned material slots', () async {
    final geometry = _CpuGeometry();
    final material = fs.UnlitMaterial();
    final template = fs.Node(mesh: fs.Mesh(geometry, material));
    final cache = VrGlbTemplateCache(
      loader: (_, {maxTextureSize}) async => template,
    );
    addTearDown(cache.dispose);
    final a = await cache.instantiate('mesh.glb');
    final b = await cache.instantiate('mesh.glb');
    expect(identical(a.mesh, b.mesh), isFalse);
    expect(identical(a.mesh!.primitives.single.geometry, geometry), isTrue);
    expect(identical(b.mesh!.primitives.single.geometry, geometry), isTrue);
    final privateMaterial = fs.UnlitMaterial()
      ..baseColorFactor = vm.Vector4(1, 0, 0, 1);
    a.mesh!.primitives.single.material = privateMaterial;
    expect(
      identical(a.mesh!.primitives.single.material, privateMaterial),
      isTrue,
    );
    expect(identical(b.mesh!.primitives.single.material, material), isTrue);
    expect(
      identical(template.mesh!.primitives.single.material, material),
      isTrue,
    );
  });

  test(
    'bounds templates by LRU and includes texture cap in identity',
    () async {
      final calls = <String>[];
      final cache = VrGlbTemplateCache(
        maxEntries: 2,
        loader: (path, {maxTextureSize}) async {
          calls.add('$path:$maxTextureSize');
          return fs.Node(name: path);
        },
      );
      addTearDown(cache.dispose);
      await cache.instantiate('a.glb', maxTextureSize: 512);
      await cache.instantiate('b.glb');
      await cache.instantiate('a.glb', maxTextureSize: 512);
      await cache.instantiate('c.glb');
      expect(cache.retainedTemplateCount, 2);
      await cache.instantiate('a.glb', maxTextureSize: 512);
      expect(calls, ['a.glb:512', 'b.glb:null', 'c.glb:null']);
      await cache.instantiate('b.glb');
      await cache.instantiate('a.glb', maxTextureSize: 1024);
      expect(calls.last, 'a.glb:1024');
      expect(calls.where((key) => key == 'b.glb:null').length, 2);
      expect(cache.retainedTemplateCount, 2);
    },
  );

  test(
    'failed loads retry and stale completion cannot remove a replacement',
    () async {
      final loads = <Completer<fs.Node>>[];
      final cache = VrGlbTemplateCache(
        loader: (_, {maxTextureSize}) {
          final pending = Completer<fs.Node>();
          loads.add(pending);
          return pending.future;
        },
      );
      addTearDown(cache.dispose);
      final first = cache.instantiate('actor.glb');
      final failed = expectLater(first, throwsStateError);
      cache.invalidate('actor.glb');
      final replacement = cache.instantiate('actor.glb');
      loads[0].completeError(StateError('Invalid GLB'));
      await failed;
      loads[1].complete(fs.Node(name: 'replacement'));
      expect((await replacement).name, 'replacement');
      expect((await cache.instantiate('actor.glb')).name, 'replacement');
      expect(loads.length, 2);
      cache.invalidate('actor.glb');
      final retry = cache.instantiate('actor.glb');
      loads[2].complete(fs.Node(name: 'retry'));
      expect((await retry).name, 'retry');
    },
  );

  test(
    'clear while pending releases retention without later resurrection',
    () async {
      final load = Completer<fs.Node>();
      final cache = VrGlbTemplateCache(
        loader: (_, {maxTextureSize}) => load.future,
      );
      addTearDown(cache.dispose);
      final actor = cache.instantiate('actor.glb');
      cache.clear();
      expect(cache.retainedTemplateCount, 0);
      load.complete(fs.Node(name: 'actor'));
      expect((await actor).name, 'actor');
      expect(cache.retainedTemplateCount, 0);
    },
  );

  test('dispose rejects pending instances and all future requests', () async {
    final load = Completer<fs.Node>();
    final cache = VrGlbTemplateCache(
      loader: (_, {maxTextureSize}) => load.future,
    );
    final pending = cache.instantiate('actor.glb');
    final rejected = expectLater(pending, throwsStateError);
    cache.dispose();
    cache.dispose();
    expect(cache.isDisposed, isTrue);
    expect(cache.retainedTemplateCount, 0);
    load.complete(fs.Node());
    await rejected;
    await expectLater(cache.instantiate('actor.glb'), throwsStateError);
  });

  test('rejects invalid budgets and import options', () async {
    expect(() => VrGlbTemplateCache(maxEntries: 0), throwsArgumentError);
    var calls = 0;
    final cache = VrGlbTemplateCache(
      loader: (_, {maxTextureSize}) async {
        calls++;
        return fs.Node();
      },
    );
    addTearDown(cache.dispose);
    await expectLater(cache.instantiate(' '), throwsArgumentError);
    await expectLater(
      cache.instantiate('a.glb', maxTextureSize: 0),
      throwsArgumentError,
    );
    expect(calls, 0);
  });
}
