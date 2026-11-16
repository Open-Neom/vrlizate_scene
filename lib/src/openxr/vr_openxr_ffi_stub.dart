import 'vr_gpu_external_render_target.dart';
import 'vr_openxr_swapchain_bridge.dart';

abstract interface class VrOpenXrFfiDriver {
  Object? get dylib;
  bool get isNativeLoaded;
  bool initialize({required int swapchainWidth, required int swapchainHeight});
  void shutdown();
  VrOpenXrFrameTiming waitFrame();
  void beginFrame(int frameIndex);
  VrGpuExternalRenderTarget acquireSwapchainImage(
    int eyeIndex, {
    required int width,
    required int height,
  });
  void releaseSwapchainImage(int eyeIndex, {int? syncFenceHandle});
  void endFrame(int frameIndex);
  List<VrOpenXrViewPose> getPredictedViews(int predictedDisplayTimeNs);
  void dispose();
}

VrOpenXrFfiDriver? tryOpenOpenXrFfiDriver(String libraryName) => null;
