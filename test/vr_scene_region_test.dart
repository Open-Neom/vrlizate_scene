import 'package:flutter_scene/scene.dart' show Node;
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' show Vector3;
import 'package:vrlizate_scene/src/streaming/vr_scene_region.dart';

void main() {
  VrSceneRegionBounds bounds() => VrSceneRegionBounds(
    minX: -10,
    minY: 0,
    minZ: -10,
    maxX: 10,
    maxY: 5,
    maxZ: 10,
  );

  test('distance uses nearest region edge and handles positions inside', () {
    expect(bounds().distanceTo(Vector3(9, 2, 9)), 0);
    expect(bounds().distanceTo(Vector3(13, 2, 14)), 5);
    expect(bounds().distanceTo(Vector3(0, 8, 14)), 5);
  });

  test('invalid bounds and viewer inputs are rejected', () {
    expect(
      () => VrSceneRegionBounds(
        minX: 1,
        minY: 0,
        minZ: 0,
        maxX: 0,
        maxY: 1,
        maxZ: 1,
      ),
      throwsArgumentError,
    );
    expect(
      () => VrSceneRegionBounds(
        minX: 0,
        minY: 0,
        minZ: 0,
        maxX: double.infinity,
        maxY: 1,
        maxZ: 1,
      ),
      throwsArgumentError,
    );
    expect(
      () => bounds().distanceTo(Vector3(double.nan, 0, 0)),
      throwsArgumentError,
    );
  });

  test(
    'policy keeps a hidden region resident before its retention boundary',
    () {
      final policy = VrSceneRegionPolicy();
      expect(policy.select(20).visual, VrSceneRegionVisual.detail);
      expect(policy.select(40).visual, VrSceneRegionVisual.proxy);
      final cached = policy.select(70);
      expect(cached.visual, VrSceneRegionVisual.none);
      expect(cached.keepResident, isTrue);
      expect(policy.select(100).keepResident, isFalse);
      expect(policy.select(double.infinity).keepResident, isFalse);
    },
  );

  test('detail, proxy, and retention boundaries have exit hysteresis', () {
    final policy = VrSceneRegionPolicy();
    var current = policy.select(20);
    current = policy.select(26, previous: current);
    expect(current.visual, VrSceneRegionVisual.detail);
    current = policy.select(28, previous: current);
    expect(current.visual, VrSceneRegionVisual.proxy);
    current = policy.select(25, previous: current);
    expect(current.visual, VrSceneRegionVisual.proxy);
    current = policy.select(58, previous: current);
    expect(current.visual, VrSceneRegionVisual.proxy);
    current = policy.select(60, previous: current);
    expect(current.visual, VrSceneRegionVisual.none);
    current = policy.select(82, previous: current);
    expect(current.keepResident, isTrue);
    current = policy.select(84, previous: current);
    expect(current.keepResident, isFalse);
    expect(policy.select(81, previous: current).keepResident, isFalse);
  });

  test('policy rejects invalid distances and overlapping exit bands', () {
    expect(() => VrSceneRegionPolicy(detailDistance: -1), throwsArgumentError);
    expect(() => VrSceneRegionPolicy(proxyDistance: 25), throwsArgumentError);
    expect(
      () => VrSceneRegionPolicy(retentionDistance: 57),
      throwsArgumentError,
    );
    expect(
      () => VrSceneRegionPolicy(hysteresis: double.nan),
      throwsArgumentError,
    );
    expect(() => VrSceneRegionPolicy().select(-1), throwsArgumentError);
    expect(() => VrSceneRegionPolicy().select(double.nan), throwsArgumentError);
  });

  test(
    'only the selected visual is mounted; returning restores its identity',
    () {
      final parent = Node(name: 'world');
      final detail = Node(name: 'detail');
      final proxy = Node(name: 'proxy');
      final region = VrSceneRegion(
        parent: parent,
        bounds: bounds(),
        detail: detail,
        proxy: proxy,
      );
      region.update(Vector3(0, 2, 0));
      expect(parent.children, [detail]);
      expect(detail.frustumCulled, isTrue);
      region.update(Vector3(50, 2, 0));
      expect(parent.children, [proxy]);
      expect(detail.parent, isNull);
      region.update(Vector3(80, 2, 0));
      expect(parent.children, isEmpty);
      expect(region.decision.keepResident, isTrue);
      region.update(Vector3(0, 2, 0));
      expect(region.mountedNode, same(detail));
      expect(parent.children, [detail]);
      region.update(Vector3(100, 2, 0));
      expect(parent.children, isEmpty);
      expect(region.decision.keepResident, isFalse);
    },
  );

  test('missing proxy uses detail up to proxy range, then detaches it', () {
    final parent = Node();
    final detail = Node();
    final region = VrSceneRegion(
      parent: parent,
      bounds: bounds(),
      detail: detail,
    );
    region.update(Vector3(50, 2, 0));
    expect(region.decision.visual, VrSceneRegionVisual.proxy);
    expect(region.mountedNode, same(detail));
    region.update(Vector3(80, 2, 0));
    expect(detail.parent, isNull);
  });

  test('suspending detaches visuals without discarding resident state', () {
    final parent = Node();
    final detail = Node();
    final region = VrSceneRegion(
      parent: parent,
      bounds: bounds(),
      detail: detail,
    );
    region.update(Vector3.zero());
    region.update(Vector3.zero(), enabled: false);
    expect(parent.children, isEmpty);
    expect(region.decision.keepResident, isTrue);
    region.update(Vector3.zero());
    expect(region.mountedNode, same(detail));
    region.dispose();
    region.dispose();
    expect(parent.children, isEmpty);
    expect(() => region.update(Vector3.zero()), throwsStateError);
  });

  test('region ownership rejects aliases, attached roots, and cycles', () {
    final parent = Node();
    final detail = Node();
    expect(
      () => VrSceneRegion(parent: parent, bounds: bounds(), detail: parent),
      throwsArgumentError,
    );
    expect(
      () => VrSceneRegion(
        parent: parent,
        bounds: bounds(),
        detail: detail,
        proxy: detail,
      ),
      throwsArgumentError,
    );
    parent.add(detail);
    expect(
      () => VrSceneRegion(parent: parent, bounds: bounds(), detail: detail),
      throwsArgumentError,
    );
    expect(
      () => VrSceneRegion(parent: detail, bounds: bounds(), detail: parent),
      throwsArgumentError,
    );
  });
}
