import 'vr_gpu_external_render_target.dart';
import 'vr_openxr_swapchain_bridge.dart';

/// Experimental placeholder for future native OpenXR bindings.
///
/// No FFI calls or runtime integration are implemented. Initialization fails
/// closed unless the caller explicitly supplies a fallback or opts into the
/// mock. Simulation must never be reported as headset/native availability.
class VrOpenXrNativeBridge implements VrOpenXrSwapchainBridge {
  final VrOpenXrSwapchainBridge fallbackBridge;
  final String libraryName;

  final bool _fallbackEnabled;
  bool _sessionRunning = false;

  VrOpenXrNativeBridge({
    this.libraryName = 'openxr_flutter_bridge',
    VrOpenXrSwapchainBridge? fallback,
    bool allowMockFallback = false,
  }) : fallbackBridge = fallback ?? VrOpenXrMockSwapchainBridge(),
       _fallbackEnabled = fallback != null || allowMockFallback;

  /// Always null until actual native bindings exist.
  Object? get dylib => null;
  bool get isNativeLoaded => false;

  @override
  bool get isSessionRunning => _sessionRunning;

  @override
  Future<bool> initializeSession() async {
    if (!_fallbackEnabled) return false;
    _sessionRunning = await fallbackBridge.initializeSession();
    return _sessionRunning;
  }

  @override
  Future<void> endSession() async {
    _sessionRunning = false;
    await fallbackBridge.endSession();
  }

  @override
  VrOpenXrFrameTiming waitFrame() {
    _ensureSession();
    return fallbackBridge.waitFrame();
  }

  @override
  void beginFrame(int frameIndex) {
    _ensureSession();
    fallbackBridge.beginFrame(frameIndex);
  }

  @override
  VrGpuExternalRenderTarget acquireSwapchainImage(int eyeIndex) {
    _ensureSession();
    return fallbackBridge.acquireSwapchainImage(eyeIndex);
  }

  @override
  void releaseSwapchainImage(int eyeIndex, {int? syncFenceHandle}) {
    _ensureSession();
    fallbackBridge.releaseSwapchainImage(
      eyeIndex,
      syncFenceHandle: syncFenceHandle,
    );
  }

  @override
  void endFrame(
    int frameIndex,
    List<VrGpuExternalRenderTarget> targets, {
    List<dynamic>? quadLayers,
  }) {
    _ensureSession();
    fallbackBridge.endFrame(frameIndex, targets, quadLayers: quadLayers);
  }

  @override
  List<VrOpenXrViewPose> getPredictedViews(int predictedDisplayTimeNs) {
    _ensureSession();
    return fallbackBridge.getPredictedViews(predictedDisplayTimeNs);
  }

  void _ensureSession() {
    if (!_sessionRunning) {
      throw StateError(
        'Native OpenXR is unavailable; explicitly initialize a supplied fallback to simulate.',
      );
    }
  }
}
