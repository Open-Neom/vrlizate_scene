import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vrlizate_scene/vrlizate_scene.dart';

void main() {
  testWidgets('world navigation scope exposes one HOME intent to a scene', (
    tester,
  ) async {
    var homeRequests = 0;
    late VrWorldNavigationScope scope;

    await tester.pumpWidget(
      MaterialApp(
        home: VrWorldNavigationScope(
          onHome: () => homeRequests++,
          child: Builder(
            builder: (context) {
              scope = VrWorldNavigationScope.maybeOf(context)!;
              return const SizedBox();
            },
          ),
        ),
      ),
    );

    expect(scope.homeLabel, '↖  HOME');
    scope.onHome();
    expect(homeRequests, 1);
  });
}
