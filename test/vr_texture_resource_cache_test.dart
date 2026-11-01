import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vrlizate_scene/src/assets/vr_async_resource_cache.dart';
import 'package:vrlizate_scene/src/pbr_texture_library.dart';

void main() {
  test('synchronously completed resources remain shareable', () async {
    final cache = VrAsyncResourceCache<String, Object>(maxEntries: 2);
    final texture = Object();
    var loads = 0;
    Future<Object> loader() {
      loads++;
      return SynchronousFuture(texture);
    }

    final first = cache.load('stone', loader);
    final second = cache.load('stone', loader);
    expect(await first, same(texture));
    expect(await second, same(texture));
    expect(await cache.load('stone', loader), same(texture));
    expect(loads, 1);
  });

  test('concurrent materials share one complete load and upload', () async {
    final cache = VrAsyncResourceCache<String, Object>(maxEntries: 2);
    final decode = Completer<Object>();
    var loads = 0;
    Future<Object> loader() {
      loads++;
      return decode.future;
    }

    final first = cache.load('stone', loader);
    final second = cache.load('stone', loader);
    final texture = Object();
    decode.complete(texture);
    expect(await first, same(texture));
    expect(await second, same(texture));
    expect(await cache.load('stone', loader), same(texture));
    expect(loads, 1);
    expect(cache.completedCount, 1);
  });

  test(
    'same albedo with different normal or roughness stays distinct',
    () async {
      final cache = VrAsyncResourceCache<(String, String, String), Object>(
        maxEntries: 4,
      );
      const stone = PbrAssetSet(
        colorAsset: 'stone.jpg',
        normalAsset: 'smooth.jpg',
        roughnessAsset: 'matte.jpg',
      );
      const carved = PbrAssetSet(
        colorAsset: 'stone.jpg',
        normalAsset: 'carved.jpg',
        roughnessAsset: 'matte.jpg',
      );
      const polished = PbrAssetSet(
        colorAsset: 'stone.jpg',
        normalAsset: 'smooth.jpg',
        roughnessAsset: 'polished.jpg',
      );
      const retiled = PbrAssetSet(
        colorAsset: 'stone.jpg',
        normalAsset: 'smooth.jpg',
        roughnessAsset: 'matte.jpg',
        tileWidthMeters: 4,
        tileHeightMeters: 2,
      );
      var loads = 0;
      Future<Object> loader() async {
        loads++;
        return Object();
      }

      final a = await cache.load(stone.resourceKey, loader);
      final b = await cache.load(carved.resourceKey, loader);
      final c = await cache.load(polished.resourceKey, loader);
      expect(b, isNot(same(a)));
      expect(c, isNot(same(a)));
      expect(c, isNot(same(b)));
      expect(await cache.load(retiled.resourceKey, loader), same(a));
      expect(loads, 3);
    },
  );

  test('failed asynchronous and synchronous loads can retry', () async {
    final cache = VrAsyncResourceCache<String, Object>(maxEntries: 2);
    await expectLater(
      cache.load('stone', () async => throw StateError('decode')),
      throwsStateError,
    );
    await expectLater(
      cache.load('stone', () => throw StateError('upload')),
      throwsStateError,
    );
    final texture = Object();
    expect(await cache.load('stone', () async => texture), same(texture));
    expect(cache.completedCount, 1);
  });

  test(
    'LRU bounds retained resources without invalidating live users',
    () async {
      final cache = VrAsyncResourceCache<String, Object>(maxEntries: 2);
      final calls = <String>[];
      Future<Object> load(String key) => cache.load(key, () async {
        calls.add(key);
        return Object();
      });
      final a = await load('a');
      final b = await load('b');
      expect(await load('a'), same(a));
      await load('c');
      expect(cache.completedCount, 2);
      expect(await load('a'), same(a));
      expect(calls, ['a', 'b', 'c']);
      expect(await load('b'), isNot(same(b)));
      expect(cache.completedCount, 2);
    },
  );

  test('clear cannot resurrect an upload still in flight', () async {
    final cache = VrAsyncResourceCache<String, Object>(maxEntries: 2);
    final decode = Completer<Object>();
    final pending = cache.load('stone', () => decode.future);
    cache.clear();
    final texture = Object();
    decode.complete(texture);
    expect(await pending, same(texture));
    expect(cache.completedCount, 0);
    expect(
      await cache.load('stone', () async => Object()),
      isNot(same(texture)),
    );
  });

  for (final staleFails in [false, true]) {
    test(
      'stale ${staleFails ? 'failure' : 'success'} preserves replacement',
      () async {
        final cache = VrAsyncResourceCache<String, Object>(maxEntries: 2);
        final stale = Completer<Object>();
        final pending = cache.load('stone', () => stale.future);
        final observed = staleFails
            ? expectLater(pending, throwsStateError)
            : pending;
        cache.clear();
        final replacement = Object();
        expect(
          await cache.load('stone', () async => replacement),
          same(replacement),
        );
        if (staleFails) {
          stale.completeError(StateError('old decode'));
        } else {
          stale.complete(Object());
        }
        await observed;
        expect(
          await cache.load('stone', () async => Object()),
          same(replacement),
        );
        expect(cache.completedCount, 1);
      },
    );
  }

  test('rejects an empty cache budget', () {
    expect(
      () => VrAsyncResourceCache<String, Object>(maxEntries: 0),
      throwsArgumentError,
    );
  });
}
