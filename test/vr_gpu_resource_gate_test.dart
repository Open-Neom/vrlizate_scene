import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vrlizate_scene/vrlizate_scene.dart';

void main() {
  testWidgets('waits for completion and readiness before mounting GPU child', (
    tester,
  ) async {
    final pending = Completer<void>();
    var ready = false;
    var calls = 0;
    var builds = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: VrGpuResourceGate(
          initialize: () {
            calls++;
            return pending.future;
          },
          isReady: () => ready,
          builder: (_) {
            builds++;
            return const Text('GPU child');
          },
        ),
      ),
    );
    expect(find.textContaining('Preparing 3D graphics'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(builds, 0);
    ready = true;
    await tester.pump();
    expect(
      builds,
      0,
      reason: 'Do not rely on a flag before the initializer completes',
    );
    pending.complete();
    await tester.pump();
    expect(find.text('GPU child'), findsOneWidget);
    expect(calls, 1);
  });

  testWidgets(
    'swallowed shader failure is visible and rebuilds never auto-retry',
    (tester) async {
      var calls = 0;
      var builds = 0;
      Widget host() => MaterialApp(
        home: VrGpuResourceGate(
          initialize: () async {
            calls++;
          },
          isReady: () => false,
          builder: (_) {
            builds++;
            return const Text('GPU child');
          },
        ),
      );
      await tester.pumpWidget(host());
      await tester.pump();
      expect(find.textContaining('Could not load 3D graphics'), findsOneWidget);
      expect(find.textContaining('No se pudieron cargar'), findsOneWidget);
      expect(find.byKey(const ValueKey('vr_gpu_retry')), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      for (var i = 0; i < 3; i++) {
        await tester.pumpWidget(host());
        await tester.pump(const Duration(seconds: 1));
      }
      expect(calls, 1);
      expect(builds, 0);
    },
  );

  testWidgets('thrown initialization failure recovers only on explicit retry', (
    tester,
  ) async {
    var calls = 0;
    var ready = false;
    await tester.pumpWidget(
      MaterialApp(
        home: VrGpuResourceGate(
          initialize: () async {
            calls++;
            if (calls == 1) throw StateError('shader load failed');
            ready = true;
          },
          isReady: () => ready,
          builder: (_) => const Text('GPU child'),
        ),
      ),
    );
    await tester.pump();
    expect(calls, 1);
    expect(find.text('GPU child'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('vr_gpu_retry')));
    await tester.pump();
    expect(calls, 2);
    expect(find.text('GPU child'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('synchronous initializer and readiness-check errors are caught', (
    tester,
  ) async {
    var checkReady = false;
    await tester.pumpWidget(
      MaterialApp(
        home: VrGpuResourceGate(
          initialize: () {
            if (!checkReady) throw StateError('context unavailable');
            return Future.value();
          },
          isReady: () => throw StateError('readiness unavailable'),
          builder: (_) => const Text('GPU child'),
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('vr_gpu_retry')), findsOneWidget);
    checkReady = true;
    await tester.tap(find.byKey(const ValueKey('vr_gpu_retry')));
    await tester.pump();
    expect(find.textContaining('Could not load 3D graphics'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('timeout is bounded and late success cannot silently resume', (
    tester,
  ) async {
    final pending = Completer<void>();
    var ready = false;
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: VrGpuResourceGate(
          initialize: () {
            calls++;
            return pending.future;
          },
          isReady: () => ready,
          timeout: const Duration(milliseconds: 30),
          builder: (_) => const Text('GPU child'),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 31));
    expect(find.textContaining('Could not load 3D graphics'), findsOneWidget);
    ready = true;
    pending.complete();
    await tester.pump();
    expect(find.text('GPU child'), findsNothing);
    expect(calls, 1);
    await tester.tap(find.byKey(const ValueKey('vr_gpu_retry')));
    await tester.pump();
    expect(find.text('GPU child'), findsOneWidget);
    expect(calls, 2);
  });

  testWidgets('rapid retry clicks launch only one pending attempt', (
    tester,
  ) async {
    final pending = Completer<void>();
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: VrGpuResourceGate(
          initialize: () {
            calls++;
            return calls == 1 ? Future.value() : pending.future;
          },
          isReady: () => calls > 1,
          builder: (_) => const Text('GPU child'),
        ),
      ),
    );
    await tester.pump();
    final retry = find.byKey(const ValueKey('vr_gpu_retry'));
    await tester.tap(retry);
    await tester.tap(retry); // before Flutter has replaced the button
    expect(calls, 2);
    pending.complete();
    await tester.pump();
    expect(find.text('GPU child'), findsOneWidget);
  });

  testWidgets('world navigation back works during loading and after failure', (
    tester,
  ) async {
    final pending = Completer<void>();
    var backs = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: VrWorldNavigationScope(
          onHome: () => backs++,
          child: VrGpuResourceGate(
            initialize: () => pending.future,
            isReady: () => false,
            builder: (_) => const Text('GPU child'),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('vr_gpu_back')));
    expect(backs, 1);
    pending.complete();
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('vr_gpu_back')));
    expect(backs, 2);
  });

  testWidgets('late failed completion after dispose does not build or throw', (
    tester,
  ) async {
    final pending = Completer<void>();
    var builds = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: VrGpuResourceGate(
          initialize: () => pending.future,
          isReady: () => true,
          builder: (_) {
            builds++;
            return const Text('GPU child');
          },
        ),
      ),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    pending.completeError(StateError('late error'));
    await tester.pump();
    expect(builds, 0);
    expect(tester.takeException(), isNull);
  });
}
