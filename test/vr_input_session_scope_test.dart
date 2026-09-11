import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vrlizate_scene/vrlizate_scene.dart';

void main() {
  testWidgets('VrInputSessionScope exposes shared arbiter down the widget tree', (
    tester,
  ) async {
    final arbiter = VrInputArbiter();
    VrInputArbiter? foundArbiter;

    await tester.pumpWidget(
      MaterialApp(
        home: VrInputSessionScope(
          arbiter: arbiter,
          child: Builder(
            builder: (context) {
              foundArbiter = VrInputSessionScope.arbiterOf(context);
              return const SizedBox();
            },
          ),
        ),
      ),
    );

    expect(foundArbiter, same(arbiter));
    expect(VrInputSessionScope.maybeOf(tester.element(find.byType(SizedBox)))?.arbiter, same(arbiter));
    arbiter.dispose();
  });
}
