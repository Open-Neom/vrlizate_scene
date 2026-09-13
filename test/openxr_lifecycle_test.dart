import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;
import 'package:vrlizate_scene/vrlizate_scene.dart';

class _RecordingBridge extends VrOpenXrMockSwapchainBridge {
  int acquisitions = 0;
  int releases = 0;
  int ends = 0;
  int shutdowns = 0;
  bool failRightAcquire = false;
  List<VrGpuExternalRenderTarget>? submitted;
  List<dynamic>? layers;

  @override
  VrGpuExternalRenderTarget acquireSwapchainImage(int eyeIndex) {
    if (eyeIndex == 1 && failRightAcquire) throw StateError('right acquire');
    acquisitions++;
    return super.acquireSwapchainImage(eyeIndex);
  }

  @override
  void releaseSwapchainImage(int eyeIndex, {int? syncFenceHandle}) {
    releases++;
    super.releaseSwapchainImage(eyeIndex, syncFenceHandle: syncFenceHandle);
  }

  @override
  void endFrame(
    int index,
    List<VrGpuExternalRenderTarget> targets, {
    List<dynamic>? quadLayers,
  }) {
    ends++;
    submitted = targets;
    layers = quadLayers;
    super.endFrame(index, targets, quadLayers: quadLayers);
  }

  @override
  Future<void> endSession() async {
    shutdowns++;
    await super.endSession();
  }
}

class _PendingBridge extends _RecordingBridge {
  final initialized = Completer<bool>();
  int initializations = 0;
  @override
  Future<bool> initializeSession() async {
    initializations++;
    final ok = await initialized.future;
    if (ok) await super.initializeSession();
    return ok;
  }
}

void _render(
  int eye,
  vm.Matrix4 view,
  vm.Matrix4 projection,
  VrGpuExternalRenderTarget target,
) {}

void main() {
  test(
    'native placeholder fails closed; explicit simulation stays non-native',
    () async {
      final bridge = VrOpenXrNativeBridge();
      expect(await bridge.initializeSession(), isFalse);
      expect(bridge.isNativeLoaded, isFalse);
      expect(bridge.isSessionRunning, isFalse);
      expect(bridge.waitFrame, throwsStateError);
      final simulation = VrOpenXrNativeBridge(allowMockFallback: true);
      expect(await simulation.initializeSession(), isTrue);
      expect(simulation.isNativeLoaded, isFalse);
      expect(simulation.dylib, isNull);
      await simulation.endSession();
    },
  );

  test('absent renderer cannot initialize or count rendered frames', () async {
    final bridge = _RecordingBridge();
    final loop = VrDecoupledRenderLoop(bridge: bridge);
    expect(loop.start, throwsStateError);
    expect(loop.renderSingleFrame, throwsStateError);
    expect(bridge.isSessionRunning, isFalse);
    expect(loop.totalFramesRendered, 0);
    await loop.dispose();
  });

  test('render failure releases both images and ends with no layers', () async {
    final bridge = _RecordingBridge();
    await bridge.initializeSession();
    final loop = VrDecoupledRenderLoop(
      bridge: bridge,
      onRenderEye: (_, _, _, _) => throw StateError('renderer failed'),
    );
    expect(loop.renderSingleFrame, throwsStateError);
    expect(bridge.acquisitions, 2);
    expect(bridge.releases, 2);
    expect(bridge.ends, 1);
    expect(bridge.submitted, isEmpty);
    expect(bridge.layers, isEmpty);
    expect(loop.totalFramesRendered, 0);
    expect(loop.droppedFrames, 1);
    await loop.dispose();
    expect(bridge.shutdowns, 0); // The caller owns this pre-existing session.
    await bridge.endSession();
  });

  test('partial acquisition releases the already-acquired eye', () async {
    final bridge = _RecordingBridge()..failRightAcquire = true;
    await bridge.initializeSession();
    final loop = VrDecoupledRenderLoop(bridge: bridge, onRenderEye: _render);
    expect(loop.renderSingleFrame, throwsStateError);
    expect(bridge.acquisitions, 1);
    expect(bridge.releases, 1);
    expect(bridge.ends, 1);
    expect(bridge.submitted, isEmpty);
    await loop.dispose();
    await bridge.endSession();
  });

  test(
    'dispose cancels pending starts and closes an owned session once',
    () async {
      final bridge = _PendingBridge();
      final loop = VrDecoupledRenderLoop(bridge: bridge, onRenderEye: _render);
      final first = loop.start();
      final second = loop.start();
      final disposal = loop.dispose();
      bridge.initialized.complete(true);
      expect(await first, isFalse);
      expect(await second, isFalse);
      await disposal;
      expect(bridge.initializations, 1);
      expect(loop.isRunning, isFalse);
      expect(bridge.isSessionRunning, isFalse);
      expect(bridge.shutdowns, 1);
      expect(loop.start, throwsStateError);
      await loop.dispose();
      expect(bridge.shutdowns, 1);
    },
  );

  testWidgets(
    'concurrent starts keep one chain and use the reported interval',
    (tester) async {
      final bridge = _PendingBridge();
      final loop = VrDecoupledRenderLoop(bridge: bridge, onRenderEye: _render);
      final first = loop.start();
      final second = loop.start();
      bridge.initialized.complete(true);
      expect(await first, isTrue);
      expect(await second, isTrue);
      await tester.pump(const Duration(milliseconds: 110));
      expect(loop.totalFramesRendered, 7); // 72Hz, not two chains or fixed90Hz.
      expect(bridge.initializations, 1);
      await loop.dispose();
      await tester.pump(const Duration(seconds: 1));
      expect(loop.totalFramesRendered, 7);
      expect(bridge.shutdowns, 1);
    },
  );

  test('only clean quads with supplied textures are submitted', () async {
    VrSpatialUiQuadLayer quad(String id) => VrSpatialUiQuadLayer(
      layerId: id,
      pixelWidth: 100,
      pixelHeight: 50,
      widthMeters: 1,
      heightMeters: .5,
    );
    final ready = quad('ready')..markClean(updatedTextureId: 12);
    final noTexture = quad('empty')..markClean();
    final dirty = quad('dirty');
    final bridge = _RecordingBridge();
    await bridge.initializeSession();
    final loop = VrDecoupledRenderLoop(
      bridge: bridge,
      onRenderEye: _render,
      quadLayers: [ready, noTexture, dirty],
    );
    loop.renderSingleFrame();
    expect(bridge.layers, hasLength(1));
    expect((bridge.layers!.single as Map)['layerId'], 'ready');
    expect(bridge.submitted!.every((target) => !target.isAcquired), isTrue);
    await loop.dispose();
    await bridge.endSession();
  });

  test('signed asymmetric FOV maps near-plane boundaries correctly', () {
    final view = VrOpenXrViewPose(
      eyeIndex: 0,
      position: vm.Vector3.zero(),
      orientation: vm.Quaternion.identity(),
      fovLeft: -.7,
      fovRight: .9,
      fovUp: .8,
      fovDown: -.6,
    );
    const near = .1;
    final matrix = view.computeProjectionMatrix(near: near, far: 100);
    expect(matrix.storage.every((value) => value.isFinite), isTrue);
    vm.Vector4 project(double angleX, double angleY) => matrix.transform(
      vm.Vector4(math.tan(angleX) * near, math.tan(angleY) * near, -near, 1),
    );
    final bottomLeft = project(view.fovLeft, view.fovDown);
    final topRight = project(view.fovRight, view.fovUp);
    expect(bottomLeft.x / bottomLeft.w, closeTo(-1, .00001));
    expect(bottomLeft.y / bottomLeft.w, closeTo(-1, .00001));
    expect(topRight.x / topRight.w, closeTo(1, .00001));
    expect(topRight.y / topRight.w, closeTo(1, .00001));
    expect(bottomLeft.z / bottomLeft.w, closeTo(-1, .00001));
    expect(
      () => view.computeProjectionMatrix(near: 1, far: 1),
      throwsArgumentError,
    );
    final flat = VrOpenXrViewPose(
      eyeIndex: 0,
      position: vm.Vector3.zero(),
      orientation: vm.Quaternion.identity(),
      fovLeft: .8,
      fovRight: .8,
    );
    expect(flat.computeProjectionMatrix, throwsArgumentError);
  });
}
