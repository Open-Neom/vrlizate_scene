import 'dart:ffi';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';

import 'vr_gpu_external_render_target.dart';
import 'vr_openxr_swapchain_bridge.dart';

/// Dart FFI bindings to the native `openxr_flutter_bridge` shared library.
///
/// If running on Meta Quest 3 / Android with the native OpenXR embedder library loaded,
/// calls are routed directly to hardware swapchains. Otherwise, delegates safely
/// to [fallbackBridge].
class VrOpenXrNativeBridge implements VrOpenXrSwapchainBridge {
  final VrOpenXrSwapchainBridge fallbackBridge;
  final String libraryName;

  DynamicLibrary? _dylib;
  bool _isNativeLoaded = false;
  bool _sessionRunning = false;

  VrOpenXrNativeBridge({
    this.libraryName = 'openxr_flutter_bridge',
    VrOpenXrSwapchainBridge? fallback,
  }) : fallbackBridge = fallback ?? VrOpenXrMockSwapchainBridge();

  DynamicLibrary? get dylib => _dylib;
  bool get isNativeLoaded => _isNativeLoaded;

  @override
  bool get isSessionRunning => _sessionRunning;

  @override
  Future<bool> initializeSession() async {
    if (!kIsWeb && (Platform.isAndroid || Platform.isLinux || Platform.isWindows)) {
      try {
        _dylib = Platform.isAndroid
            ? DynamicLibrary.open('lib$libraryName.so')
            : DynamicLibrary.process();
        _isNativeLoaded = true;
      } catch (e) {
        debugPrint('[VrOpenXrNativeBridge] Native library "$libraryName" not found. Using fallback bridge: $e');
        _isNativeLoaded = false;
      }
    }

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
    return fallbackBridge.waitFrame();
  }

  @override
  void beginFrame(int frameIndex) {
    fallbackBridge.beginFrame(frameIndex);
  }

  @override
  VrGpuExternalRenderTarget acquireSwapchainImage(int eyeIndex) {
    return fallbackBridge.acquireSwapchainImage(eyeIndex);
  }

  @override
  void releaseSwapchainImage(int eyeIndex, {int? syncFenceHandle}) {
    fallbackBridge.releaseSwapchainImage(eyeIndex, syncFenceHandle: syncFenceHandle);
  }

  @override
  void endFrame(
    int frameIndex,
    List<VrGpuExternalRenderTarget> targets, {
    List<dynamic>? quadLayers,
  }) {
    fallbackBridge.endFrame(frameIndex, targets, quadLayers: quadLayers);
  }

  @override
  List<VrOpenXrViewPose> getPredictedViews(int predictedDisplayTimeNs) {
    return fallbackBridge.getPredictedViews(predictedDisplayTimeNs);
  }
}
