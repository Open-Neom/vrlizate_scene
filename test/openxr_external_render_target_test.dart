import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;
import 'package:vrlizate/vrlizate.dart';
import 'package:vrlizate_scene/vrlizate_scene.dart';

void main() {
  group('VrGpuExternalRenderTarget', () {
    test('constructs valid external render target for OpenGL ES', () {
      final target = VrGpuExternalRenderTarget(
        targetId: 101,
        descriptor: const VrExternalRenderTargetDescriptor(
          backend: VrGpuBackend.openGlEs,
          format: VrGpuTextureFormat.rgba8,
          width: 2064,
          height: 2208,
        ),
        eyeIndex: 0,
        glTextureId: 5432,
      );

      expect(target.targetId, equals(101));
      expect(target.eyeIndex, equals(0));
      expect(target.glTextureId, equals(5432));
      expect(target.vkImageHandle, isNull);
      expect(target.width, equals(2064));
      expect(target.height, equals(2208));
      expect(target.isAcquired, isTrue);

      target.markReleased(fenceHandle: 0x9999);
      expect(target.isAcquired, isFalse);
      expect(target.syncFenceHandle, equals(0x9999));

      target.markAcquired();
      expect(target.isAcquired, isTrue);
    });

    test('constructs valid external render target for Vulkan with 64-bit handle', () {
      final target = VrGpuExternalRenderTarget(
        targetId: 102,
        descriptor: const VrExternalRenderTargetDescriptor(
          backend: VrGpuBackend.vulkan,
          format: VrGpuTextureFormat.srgb8Alpha8,
          width: 2064,
          height: 2208,
        ),
        eyeIndex: 1,
        vkImageHandle: 0xDEADBEEFCAFE,
        vkImageViewHandle: 0xCAFEBABE1234,
      );

      expect(target.eyeIndex, equals(1));
      expect(target.backend, equals(VrGpuBackend.vulkan));
      expect(target.vkImageHandle, equals(0xDEADBEEFCAFE));
      expect(target.vkImageViewHandle, equals(0xCAFEBABE1234));
    });

    test('throws assertion error if eyeIndex is invalid or no texture handle provided', () {
      expect(
        () => VrGpuExternalRenderTarget(
          targetId: 1,
          descriptor: const VrExternalRenderTargetDescriptor(
            backend: VrGpuBackend.openGlEs,
            format: VrGpuTextureFormat.rgba8,
            width: 100,
            height: 100,
          ),
          eyeIndex: 2, // Invalid: must be 0 or 1
          glTextureId: 1,
        ),
        throwsA(isA<AssertionError>()),
      );

      expect(
        () => VrGpuExternalRenderTarget(
          targetId: 1,
          descriptor: const VrExternalRenderTargetDescriptor(
            backend: VrGpuBackend.openGlEs,
            format: VrGpuTextureFormat.rgba8,
            width: 100,
            height: 100,
          ),
          eyeIndex: 0,
          glTextureId: null,
          vkImageHandle: null, // Invalid: must specify one
        ),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('VrOpenXrSwapchainBridge & Mock', () {
    test('simulates OpenXR lifecycle and produces valid projection & view matrices', () async {
      final bridge = VrOpenXrMockSwapchainBridge(
        textureWidth: 2064,
        textureHeight: 2208,
        ipd: 0.064,
      );

      expect(bridge.isSessionRunning, isFalse);
      final ok = await bridge.initializeSession();
      expect(ok, isTrue);
      expect(bridge.isSessionRunning, isTrue);

      final timing = bridge.waitFrame();
      expect(timing.frameIndex, equals(1));
      expect(timing.predictedDisplayTimeNs, greaterThan(0));
      expect(timing.targetFps, closeTo(72.0, 0.5));

      final views = bridge.getPredictedViews(timing.predictedDisplayTimeNs);
      expect(views.length, equals(2));

      // Left eye is offset -halfIpd (-0.032m), right eye is +0.032m
      expect(views[0].position.x, closeTo(-0.032, 0.0001));
      expect(views[1].position.x, closeTo(0.032, 0.0001));

      // Projection matrices
      final leftProj = views[0].computeProjectionMatrix(near: 0.1, far: 100.0);
      final rightProj = views[1].computeProjectionMatrix(near: 0.1, far: 100.0);
      expect(leftProj[15], equals(0.0)); // Perspective projection has zero at [15]
      expect(rightProj[15], equals(0.0));

      // View matrices
      final leftView = views[0].computeViewMatrix();
      final rightView = views[1].computeViewMatrix();
      expect(leftView[12], closeTo(0.032, 0.0001)); // Inverted position translation
      expect(rightView[12], closeTo(-0.032, 0.0001));

      // Swapchain acquire / release
      final leftTarget = bridge.acquireSwapchainImage(0);
      final rightTarget = bridge.acquireSwapchainImage(1);
      expect(leftTarget.glTextureId, equals(1000));
      expect(rightTarget.glTextureId, equals(1001));

      bridge.endFrame(timing.frameIndex, [leftTarget, rightTarget]);
      expect(leftTarget.isAcquired, isFalse);
      expect(rightTarget.isAcquired, isFalse);

      await bridge.endSession();
      expect(bridge.isSessionRunning, isFalse);
    });
  });

  group('VrSpatialUiQuadLayer', () {
    test('manages spatial quad pose and dirty tracking', () {
      final quad = VrSpatialUiQuadLayer(
        layerId: 'hud_menu',
        pixelWidth: 1024,
        pixelHeight: 512,
        widthMeters: 1.2,
        heightMeters: 0.6,
        position: vm.Vector3(0, 0.2, -1.8),
      );

      expect(quad.layerId, equals('hud_menu'));
      expect(quad.isDirty, isTrue); // Initially dirty to force initial rasterization
      expect(quad.position.z, closeTo(-1.8, 0.001));

      quad.markClean(updatedTextureId: 9001);
      expect(quad.isDirty, isFalse);
      expect(quad.textureId, equals(9001));

      quad.markDirty();
      expect(quad.isDirty, isTrue);

      // Model matrix computation
      final matrix = quad.computeTransformMatrix();
      expect(matrix[12], closeTo(0.0, 0.001)); // translation X
      expect(matrix[13], closeTo(0.2, 0.001)); // translation Y
      expect(matrix[14], closeTo(-1.8, 0.001)); // translation Z

      final desc = quad.toOpenXrQuadDescriptor();
      expect(desc['layerId'], equals('hud_menu'));
      expect(desc['pixelWidth'], equals(1024));
      expect(desc['widthMeters'], equals(1.2));
      expect(desc['textureId'], equals(9001));
    });
  });

  group('VrDecoupledRenderLoop', () {
    test('renders stereo frames with callbacks and calculates frame telemetry', () async {
      final bridge = VrOpenXrMockSwapchainBridge();
      final dispatchedEyes = <int>[];
      final viewMatrices = <vm.Matrix4>[];

      final loop = VrDecoupledRenderLoop(
        bridge: bridge,
        onRenderEye: (eyeIndex, viewMatrix, projMatrix, target) {
          dispatchedEyes.add(eyeIndex);
          viewMatrices.add(viewMatrix);
          expect(target.isAcquired, isTrue);
        },
      );

      final quad = VrSpatialUiQuadLayer(
        layerId: 'action_panel',
        pixelWidth: 512,
        pixelHeight: 256,
        widthMeters: 0.8,
        heightMeters: 0.4,
      );
      loop.addQuadLayer(quad);
      expect(loop.quadLayers.length, equals(1));

      await bridge.initializeSession();

      // Execute single frame synchronously
      loop.renderSingleFrame();

      expect(loop.totalFramesRendered, equals(1));
      expect(dispatchedEyes, equals([0, 1])); // Both left and right eyes rendered
      expect(viewMatrices.length, equals(2));
      expect(loop.lastFrameDurationMs, greaterThanOrEqualTo(0.0));
      expect(loop.averageFrameDurationMs, greaterThanOrEqualTo(0.0));

      loop.removeQuadLayer('action_panel');
      expect(loop.quadLayers.isEmpty, isTrue);

      loop.dispose();
      expect(loop.isRunning, isFalse);
    });
  });

  group('VrOpenXrNativeBridge', () {
    test('delegates cleanly to fallback when native dylib is absent', () async {
      final nativeBridge = VrOpenXrNativeBridge();
      expect(nativeBridge.isSessionRunning, isFalse);

      final ok = await nativeBridge.initializeSession();
      expect(ok, isTrue);
      expect(nativeBridge.isSessionRunning, isTrue);

      final timing = nativeBridge.waitFrame();
      expect(timing.frameIndex, greaterThan(0));

      final views = nativeBridge.getPredictedViews(timing.predictedDisplayTimeNs);
      expect(views.length, equals(2));

      await nativeBridge.endSession();
      expect(nativeBridge.isSessionRunning, isFalse);
    });
  });
}
