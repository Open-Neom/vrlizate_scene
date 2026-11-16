import 'package:flutter_test/flutter_test.dart';
import 'package:vrlizate_scene/src/streaming/vr_distance_band.dart';
import 'package:vrlizate_scene/src/streaming/vr_scene_region.dart';

void main() {
  test('initial equality belongs to the explicitly chosen side', () {
    final inclusive = VrDistanceBand(distanceMeters: 18);
    final exclusive = VrDistanceBand(
      distanceMeters: 18,
      includeBoundary: false,
    );
    expect(inclusive.contains(18), isTrue);
    expect(exclusive.contains(18), isFalse);
    expect(inclusive.contains(18.001), isFalse);
    expect(exclusive.contains(17.999), isTrue);
  });

  test('exit-only bands retain the near side without delaying re-entry', () {
    final band = VrDistanceBand(distanceMeters: 14, exitMarginMeters: 2);
    expect(band.contains(14), isTrue);
    expect(band.contains(14.001), isFalse);
    expect(band.contains(16, wasInside: true), isTrue);
    expect(band.contains(16.001, wasInside: true), isFalse);
    expect(band.contains(14, wasInside: false), isTrue);
    expect(band.contains(14.001, wasInside: false), isFalse);
    // One policy can be shared without sharing the objects' retained states.
    expect(band.contains(15, wasInside: true), isTrue);
    expect(band.contains(15, wasInside: false), isFalse);
  });

  test('symmetric exclusive bands preserve both authored transition edges', () {
    final band = VrDistanceBand(
      distanceMeters: 18,
      enterMarginMeters: 2,
      exitMarginMeters: 2,
      includeBoundary: false,
    );
    expect(band.contains(18), isFalse);
    expect(band.contains(19.999, wasInside: true), isTrue);
    expect(band.contains(20, wasInside: true), isFalse);
    expect(band.contains(16, wasInside: false), isFalse);
    expect(band.contains(15.999, wasInside: false), isTrue);
  });

  test('invalid configuration and negative or NaN distances are rejected', () {
    for (final invalid in [-1.0, double.nan, double.infinity]) {
      expect(
        () => VrDistanceBand(distanceMeters: invalid),
        throwsArgumentError,
      );
      expect(
        () => VrDistanceBand(distanceMeters: 1, enterMarginMeters: invalid),
        throwsArgumentError,
      );
      expect(
        () => VrDistanceBand(distanceMeters: 1, exitMarginMeters: invalid),
        throwsArgumentError,
      );
    }
    final band = VrDistanceBand(distanceMeters: 1);
    expect(() => band.contains(-1), throwsArgumentError);
    expect(() => band.contains(double.nan), throwsArgumentError);
    expect(() => band.contains(double.negativeInfinity), throwsArgumentError);
    expect(band.contains(double.infinity), isFalse);
  });

  test(
    'OpenWorld exact cutoffs keep visual and retention states independent',
    () {
      final policy = VrSceneRegionPolicy(
        detailDistance: 14,
        proxyDistance: 28,
        retentionDistance: 40,
        hysteresis: 2,
      );
      const detail = VrSceneRegionDecision(
        visual: VrSceneRegionVisual.detail,
        keepResident: true,
      );
      const proxy = VrSceneRegionDecision(
        visual: VrSceneRegionVisual.proxy,
        keepResident: true,
      );
      const cached = VrSceneRegionDecision(
        visual: VrSceneRegionVisual.none,
        keepResident: true,
      );
      const inactive = VrSceneRegionDecision.inactive;
      for (final (previous, distance, visual, keepResident) in [
        (inactive, 14.0, VrSceneRegionVisual.detail, true),
        (inactive, 14.001, VrSceneRegionVisual.proxy, true),
        (detail, 16.0, VrSceneRegionVisual.detail, true),
        (detail, 16.001, VrSceneRegionVisual.proxy, true),
        (proxy, 14.0, VrSceneRegionVisual.detail, true),
        (proxy, 14.001, VrSceneRegionVisual.proxy, true),
        (detail, 30.0, VrSceneRegionVisual.proxy, true),
        (proxy, 30.0, VrSceneRegionVisual.proxy, true),
        (proxy, 30.001, VrSceneRegionVisual.none, true),
        (cached, 28.0, VrSceneRegionVisual.proxy, true),
        (cached, 28.001, VrSceneRegionVisual.none, true),
        (inactive, 40.0, VrSceneRegionVisual.none, true),
        (inactive, 40.001, VrSceneRegionVisual.none, false),
        (cached, 42.0, VrSceneRegionVisual.none, true),
        (cached, 42.001, VrSceneRegionVisual.none, false),
        (detail, double.infinity, VrSceneRegionVisual.none, false),
      ]) {
        final selected = policy.select(distance, previous: previous);
        expect(selected.visual, visual);
        expect(selected.keepResident, keepResident);
      }
    },
  );
}
