import 'dart:math';
import 'package:vector_math/vector_math.dart' as vm;
import 'package:vrlizate/vrlizate.dart';

import 'vr_gpu_external_render_target.dart';

/// Frame pacing and timing information returned by `xrWaitFrame`.
class VrOpenXrFrameTiming {
  final int frameIndex;
  final int predictedDisplayTimeNs;
  final double predictedFrameIntervalSeconds;

  const VrOpenXrFrameTiming({
    required this.frameIndex,
    required this.predictedDisplayTimeNs,
    this.predictedFrameIntervalSeconds = 1.0 / 72.0, // Default 72 Hz for Meta Quest
  });

  double get targetFps => 1.0 / predictedFrameIntervalSeconds;
}

/// Head tracking and optical FOV for an individual eye view provided by OpenXR.
class VrOpenXrViewPose {
  final int eyeIndex; // 0 = Left, 1 = Right
  final vm.Vector3 position;
  final vm.Quaternion orientation;

  /// Field of view half-angles in radians (OpenXR XrFovf).
  final double fovLeft;
  final double fovRight;
  final double fovUp;
  final double fovDown;

  VrOpenXrViewPose({
    required this.eyeIndex,
    required this.position,
    required this.orientation,
    this.fovLeft = 0.82,  // ~47 degrees
    this.fovRight = 0.82,
    this.fovUp = 0.78,    // ~45 degrees
    this.fovDown = 0.78,
  });

  /// Computes the asymmetric off-axis projection matrix required by OpenXR optics.
  vm.Matrix4 computeProjectionMatrix({double near = 0.05, double far = 150.0}) {
    final left = -tan(fovLeft) * near;
    final right = tan(fovRight) * near;
    final bottom = -tan(fovDown) * near;
    final top = tan(fovUp) * near;

    return vm.makeFrustumMatrix(left, right, bottom, top, near, far);
  }

  /// Computes the camera view matrix for this eye pose.
  vm.Matrix4 computeViewMatrix() {
    final rot = vm.Matrix4.identity();
    rot.setRotation(orientation.asRotationMatrix());

    final trans = vm.Matrix4.translation(-position);
    // View = R^T * T(-pos)
    return rot.transposed() * trans;
  }
}

/// Abstract contract for communicating with native OpenXR runtimes (e.g. Meta Quest 3).
abstract class VrOpenXrSwapchainBridge {
  bool get isSessionRunning;

  /// Initializes the OpenXR instance and graphics swapchain bindings.
  Future<bool> initializeSession();

  /// Gracefully tears down the OpenXR session and destroys swapchains.
  Future<void> endSession();

  /// Blocks until the OpenXR compositor signals the start of the next display interval (`xrWaitFrame`).
  VrOpenXrFrameTiming waitFrame();

  /// Begins a new frame with the specified frame index (`xrBeginFrame`).
  void beginFrame(int frameIndex);

  /// Acquires the current hardware texture ID for the given eye from the swapchain (`xrAcquireSwapchainImage`).
  VrGpuExternalRenderTarget acquireSwapchainImage(int eyeIndex);

  /// Releases the acquired swapchain image after rendering has been dispatched (`xrReleaseSwapchainImage`).
  /// Passing [syncFenceHandle] attaches a GPU-to-GPU fence (EGLSync / VkFence) without CPU blocking.
  void releaseSwapchainImage(int eyeIndex, {int? syncFenceHandle});

  /// Submits the rendered projection layers and optional quad UI layers to the compositor (`xrEndFrame`).
  void endFrame(
    int frameIndex,
    List<VrGpuExternalRenderTarget> targets, {
    List<dynamic>? quadLayers,
  });

  /// Retrieves the predicted head view poses for both eyes at the specified display time.
  List<VrOpenXrViewPose> getPredictedViews(int predictedDisplayTimeNs);
}

/// In-memory mock implementation of [VrOpenXrSwapchainBridge] for unit testing and non-XR environments.
class VrOpenXrMockSwapchainBridge implements VrOpenXrSwapchainBridge {
  bool _running = false;
  int _currentFrame = 0;
  final int textureWidth;
  final int textureHeight;
  final double ipd;
  final VrGpuBackend backend;

  VrOpenXrMockSwapchainBridge({
    this.textureWidth = 2064,
    this.textureHeight = 2208,
    this.ipd = 0.064,
    this.backend = VrGpuBackend.openGlEs,
  });

  @override
  bool get isSessionRunning => _running;

  @override
  Future<bool> initializeSession() async {
    _running = true;
    _currentFrame = 0;
    return true;
  }

  @override
  Future<void> endSession() async {
    _running = false;
  }

  @override
  VrOpenXrFrameTiming waitFrame() {
    _currentFrame++;
    final nowNs = DateTime.now().microsecondsSinceEpoch * 1000;
    return VrOpenXrFrameTiming(
      frameIndex: _currentFrame,
      predictedDisplayTimeNs: nowNs + 13888888, // +13.8ms (72Hz interval)
      predictedFrameIntervalSeconds: 1.0 / 72.0,
    );
  }

  @override
  void beginFrame(int frameIndex) {}

  @override
  VrGpuExternalRenderTarget acquireSwapchainImage(int eyeIndex) {
    return VrGpuExternalRenderTarget(
      targetId: _currentFrame * 2 + eyeIndex,
      descriptor: VrExternalRenderTargetDescriptor(
        backend: backend,
        format: VrGpuTextureFormat.rgba8,
        width: textureWidth,
        height: textureHeight,
      ),
      eyeIndex: eyeIndex,
      glTextureId: backend == VrGpuBackend.openGlEs ? (1000 + eyeIndex) : null,
      vkImageHandle: backend == VrGpuBackend.vulkan ? (0xDEADBEEF0 + eyeIndex) : null,
      initiallyAcquired: true,
    );
  }

  @override
  void releaseSwapchainImage(int eyeIndex, {int? syncFenceHandle}) {}

  @override
  void endFrame(
    int frameIndex,
    List<VrGpuExternalRenderTarget> targets, {
    List<dynamic>? quadLayers,
  }) {
    for (final t in targets) {
      t.markReleased();
    }
  }

  @override
  List<VrOpenXrViewPose> getPredictedViews(int predictedDisplayTimeNs) {
    final halfIpd = ipd / 2.0;
    return [
      VrOpenXrViewPose(
        eyeIndex: 0,
        position: vm.Vector3(-halfIpd, 0, 0),
        orientation: vm.Quaternion.identity(),
      ),
      VrOpenXrViewPose(
        eyeIndex: 1,
        position: vm.Vector3(halfIpd, 0, 0),
        orientation: vm.Quaternion.identity(),
      ),
    ];
  }
}
