import 'vr_gpu_external_render_target.dart';
import 'vr_openxr_ffi_stub.dart'
    if (dart.library.ffi) 'vr_openxr_ffi_io.dart'
    as ffi_loader;
import 'vr_openxr_ffi_stub.dart' show VrOpenXrFfiDriver;
import 'vr_openxr_swapchain_bridge.dart';

/// Direct `package:ffigen` C-ABI OpenXR bridge (`openxr_flutter_bridge.g.dart`).
///
/// Attempts to bind `libopenxr_flutter_bridge.so` / `.dylib` / `.dll` via
/// zero-serialization synchronous FFI, passing Android `JavaVM*` and global
/// `Application` context handles directly from `VrDirectDeviceBridge` without
/// platform channels. When no OpenXR native shared library is bundled on the
/// host, initialization fails closed unless the caller explicitly supplies a
/// [fallback] or sets `allowMockFallback: true`.
class VrOpenXrNativeBridge implements VrOpenXrSwapchainBridge {
  final VrOpenXrSwapchainBridge fallbackBridge;
  final String libraryName;
  final int swapchainWidth;
  final int swapchainHeight;

  final bool _fallbackEnabled;
  VrOpenXrFfiDriver? _driver;
  bool _usingNative = false;
  bool _sessionRunning = false;

  VrOpenXrNativeBridge({
    this.libraryName = 'openxr_flutter_bridge',
    this.swapchainWidth = 2064,
    this.swapchainHeight = 2208,
    VrOpenXrSwapchainBridge? fallback,
    bool allowMockFallback = false,
  }) : fallbackBridge = fallback ?? VrOpenXrMockSwapchainBridge(),
       _fallbackEnabled = fallback != null || allowMockFallback {
    _driver = ffi_loader.tryOpenOpenXrFfiDriver(libraryName);
  }

  /// Loaded `DynamicLibrary` handle when the OpenXR C bridge `.so`/`.dylib` is
  /// present, or `null` when running without a native OpenXR runtime.
  Object? get dylib => _driver?.dylib;
  bool get isNativeLoaded => _driver?.isNativeLoaded ?? false;

  @override
  bool get isSessionRunning => _sessionRunning;

  @override
  Future<bool> initializeSession() async {
    final driver = _driver;
    if (driver != null && driver.isNativeLoaded) {
      final ok = driver.initialize(
        swapchainWidth: swapchainWidth,
        swapchainHeight: swapchainHeight,
      );
      if (ok) {
        _usingNative = true;
        _sessionRunning = true;
        return true;
      }
    }
    _usingNative = false;
    if (!_fallbackEnabled) return false;
    _sessionRunning = await fallbackBridge.initializeSession();
    return _sessionRunning;
  }

  @override
  Future<void> endSession() async {
    final wasNative = _usingNative;
    _usingNative = false;
    _sessionRunning = false;
    if (wasNative) {
      _driver?.shutdown();
    } else {
      await fallbackBridge.endSession();
    }
  }

  @override
  VrOpenXrFrameTiming waitFrame() {
    _ensureSession();
    return _usingNative ? _driver!.waitFrame() : fallbackBridge.waitFrame();
  }

  @override
  void beginFrame(int frameIndex) {
    _ensureSession();
    if (_usingNative) {
      _driver!.beginFrame(frameIndex);
    } else {
      fallbackBridge.beginFrame(frameIndex);
    }
  }

  @override
  VrGpuExternalRenderTarget acquireSwapchainImage(int eyeIndex) {
    _ensureSession();
    return _usingNative
        ? _driver!.acquireSwapchainImage(
            eyeIndex,
            width: swapchainWidth,
            height: swapchainHeight,
          )
        : fallbackBridge.acquireSwapchainImage(eyeIndex);
  }

  @override
  void releaseSwapchainImage(int eyeIndex, {int? syncFenceHandle}) {
    _ensureSession();
    if (_usingNative) {
      _driver!.releaseSwapchainImage(
        eyeIndex,
        syncFenceHandle: syncFenceHandle,
      );
    } else {
      fallbackBridge.releaseSwapchainImage(
        eyeIndex,
        syncFenceHandle: syncFenceHandle,
      );
    }
  }

  @override
  void endFrame(
    int frameIndex,
    List<VrGpuExternalRenderTarget> targets, {
    List<dynamic>? quadLayers,
  }) {
    _ensureSession();
    if (_usingNative) {
      _driver!.endFrame(frameIndex);
    } else {
      fallbackBridge.endFrame(frameIndex, targets, quadLayers: quadLayers);
    }
  }

  @override
  List<VrOpenXrViewPose> getPredictedViews(int predictedDisplayTimeNs) {
    _ensureSession();
    return _usingNative
        ? _driver!.getPredictedViews(predictedDisplayTimeNs)
        : fallbackBridge.getPredictedViews(predictedDisplayTimeNs);
  }

  void dispose() {
    _driver?.dispose();
    _driver = null;
  }

  void _ensureSession() {
    if (!_sessionRunning) {
      throw StateError(
        'OpenXR session is not running. Call initializeSession() first.',
      );
    }
  }
}
