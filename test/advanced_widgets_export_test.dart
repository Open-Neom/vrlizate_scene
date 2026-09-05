import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;
import 'package:vrlizate_scene/vrlizate_scene.dart';

void main() {
  test('advanced widgets are available through the vrlizate_scene facade', () {
    Mesh emptyMesh() => Mesh.primitives(primitives: const []);
    final center = vm.Vector3(0, 1.4, -2);

    final controls = <VrControl>[
      VrSegmentedControl3D(
        name: 'tabs',
        label: 'Tabs',
        center: center,
        options: const ['A', 'B'],
        meshBuilder: emptyMesh,
      ),
      VrProgressBar3D(
        name: 'progress',
        label: 'Progress',
        center: center,
        meshBuilder: emptyMesh,
      ),
      VrStepper3D(
        name: 'stepper',
        label: 'Stepper',
        center: center,
        meshBuilder: emptyMesh,
      ),
    ];

    final registry = VrControlRegistry();
    for (final control in controls) {
      registry.register(control);
    }
    expect(registry.controls, hasLength(3));

    final pose = VrWorldPose.fromViewer(
      eye: vm.Vector3(0, 1.6, 0),
      forward: vm.Vector3(0, 0, -1),
    );
    final action = VrWorldAction(id: 'home', label: 'Home', onPressed: () {});
    expect(pose.center.z, closeTo(-1.8, 1e-6));
    expect(action.id, 'home');
  });
}
