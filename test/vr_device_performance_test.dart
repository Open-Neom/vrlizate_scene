import 'package:flutter/widgets.dart';
import 'package:flutter_scene/scene.dart' show AntiAliasingMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:vrlizate_scene/vrlizate_scene.dart';

void main() {
  group('VrDevicePerformanceCatalog', () {
    test(
      'recognizes the tested Motorola with normalized case and whitespace',
      () {
        final profile = VrDevicePerformanceCatalog.match(
          manufacturer: '  MOTOROLA  ',
          model: '  Motorola   Edge 20\tLite  ',
        );
        expect(profile, same(VrDevicePerformanceCatalog.motorolaEdge20Lite));
        expect(profile!.id, 'motorola_edge_20_lite');
        expect(profile.initialTier, VrQualityTier.low);
        expect(profile.displayMaxHz, 90);
      },
    );

    test('recognizes only the explicit S25 Ultra SKU aliases', () {
      for (final model in [
        'SM-S938B',
        'SM-S938U',
        'SM-S938U1',
        'SM-S938W',
        'SM-S938N',
        'SM-S9380',
      ]) {
        for (final suffix in ['', '/DS', ' / ds']) {
          final profile = VrDevicePerformanceCatalog.match(
            manufacturer: ' Samsung ',
            model: ' ${model.toLowerCase()}$suffix ',
          );
          expect(
            profile,
            same(VrDevicePerformanceCatalog.samsungGalaxyS25Ultra),
            reason: '$model$suffix',
          );
          expect(profile!.id, 'samsung_galaxy_s25_ultra');
          expect(profile.initialTier, VrQualityTier.medium);
          expect(profile.displayMaxHz, 120);
        }
      }
    });

    test(
      'does not transfer evidence to another phone or a broad family name',
      () {
        const candidates = [
          ('motorola', 'moto g(20)'),
          ('motorola', 'Moto G20'),
          ('motorola', 'motorola edge 20'),
          ('motorola', 'motorola edge 20 pro'),
          ('motorola', 'motorola edge 20 lite 5g'),
          ('motorola', 'Dimensity 720'),
          ('samsung', 'Galaxy S25'),
          ('samsung', 'Galaxy S25 Ultra'),
          ('samsung', 'SM-S931B'),
          ('samsung', 'SM-S936B'),
          ('samsung', 'SM-S938'),
          ('samsung', 'SM-S938B-extra'),
          ('samsung', 'SM-S938B/DS/DS'),
          ('samsung', 'SM-S938O'),
          ('samsung', 'SM-S938B2'),
          ('samsung', 'Snapdragon 8 Elite'),
        ];
        for (final candidate in candidates) {
          expect(
            VrDevicePerformanceCatalog.match(
              manufacturer: candidate.$1,
              model: candidate.$2,
            ),
            isNull,
            reason: '${candidate.$1}: ${candidate.$2}',
          );
        }
      },
    );

    test(
      'requires the matching manufacturer and leaves unknown identity null',
      () {
        for (final candidate in [
          ('motorola', 'SM-S938B'),
          ('samsung', 'motorola edge 20 lite'),
          ('unknown', 'SM-S938B'),
          ('', 'SM-S938B'),
          ('motorola', ''),
          ('', ''),
        ]) {
          expect(
            VrDevicePerformanceCatalog.match(
              manufacturer: candidate.$1,
              model: candidate.$2,
            ),
            isNull,
          );
        }
      },
    );

    test('an external profile may leave panel capability unknown', () {
      const profile = VrDevicePerformanceProfile(
        id: 'host.reference',
        label: 'Host reference',
        initialTier: VrQualityTier.medium,
      );
      expect(profile.displayMaxHz, isNull);
    });
  });

  group('VrDevicePerformanceScope', () {
    testWidgets('a catalog suggestion seeds its matching quality preset', (
      tester,
    ) async {
      VrDevicePerformanceProfile? actualProfile;
      VrQualityPreset? actualPreset;
      await tester.pumpWidget(
        VrDevicePerformanceScope(
          profile: VrDevicePerformanceCatalog.motorolaEdge20Lite,
          child: Builder(
            builder: (context) {
              actualProfile = VrDevicePerformanceScope.maybeOf(context);
              actualPreset = VrDevicePerformanceScope.initialPresetOf(context);
              return const SizedBox();
            },
          ),
        ),
      );
      expect(
        actualProfile,
        same(VrDevicePerformanceCatalog.motorolaEdge20Lite),
      );
      expect(actualPreset, same(VrQualityPreset.low));
    });

    testWidgets(
      'explicit quality overrides a device suggestion without modification',
      (tester) async {
        const custom = VrQualityPreset(
          tier: VrQualityTier.high,
          pixelRatioScale: 0.77,
          antiAliasing: AntiAliasingMode.none,
          shadowMapResolution: 256,
          bloomEnabled: false,
        );
        VrQualityPreset? actual;
        await tester.pumpWidget(
          VrDevicePerformanceScope(
            profile: VrDevicePerformanceCatalog.motorolaEdge20Lite,
            child: Builder(
              builder: (context) {
                actual = VrDevicePerformanceScope.initialPresetOf(
                  context,
                  explicitQuality: custom,
                );
                return const SizedBox();
              },
            ),
          ),
        );
        expect(actual, same(custom));
        expect(actual!.pixelRatioScale, 0.77);
      },
    );

    testWidgets(
      'without a scope the original quality fallback remains available',
      (tester) async {
        VrDevicePerformanceProfile? actualProfile;
        VrQualityPreset? actualPreset;
        VrQualityPreset? fallback;
        await tester.pumpWidget(
          Builder(
            builder: (context) {
              actualProfile = VrDevicePerformanceScope.maybeOf(context);
              actualPreset = VrDevicePerformanceScope.initialPresetOf(context);
              fallback = VrQualityPreset.resolve(context, null);
              return const SizedBox();
            },
          ),
        );
        expect(actualProfile, isNull);
        expect(actualPreset, same(fallback));
      },
    );

    testWidgets(
      'an explicit unknown scope does not inherit an outer phone identity',
      (tester) async {
        VrDevicePerformanceProfile? actualProfile;
        VrQualityPreset? actualPreset;
        await tester.pumpWidget(
          VrDevicePerformanceScope(
            profile: VrDevicePerformanceCatalog.motorolaEdge20Lite,
            child: VrDevicePerformanceScope(
              profile: null,
              child: Builder(
                builder: (context) {
                  actualProfile = VrDevicePerformanceScope.maybeOf(context);
                  actualPreset = VrDevicePerformanceScope.initialPresetOf(
                    context,
                  );
                  return const SizedBox();
                },
              ),
            ),
          ),
        );
        expect(actualProfile, isNull);
        expect(actualPreset, same(VrQualityPreset.medium));
      },
    );

    testWidgets('consumers are notified when the resolved profile changes', (
      tester,
    ) async {
      VrDevicePerformanceProfile? actual;
      var builds = 0;
      final child = Builder(
        builder: (context) {
          actual = VrDevicePerformanceScope.maybeOf(context);
          builds++;
          return const SizedBox();
        },
      );
      await tester.pumpWidget(
        VrDevicePerformanceScope(
          profile: VrDevicePerformanceCatalog.motorolaEdge20Lite,
          child: child,
        ),
      );
      expect(actual, same(VrDevicePerformanceCatalog.motorolaEdge20Lite));
      final initialBuilds = builds;
      await tester.pumpWidget(
        VrDevicePerformanceScope(
          profile: VrDevicePerformanceCatalog.samsungGalaxyS25Ultra,
          child: child,
        ),
      );
      expect(actual, same(VrDevicePerformanceCatalog.samsungGalaxyS25Ultra));
      expect(builds, greaterThan(initialBuilds));
    });
  });
}
