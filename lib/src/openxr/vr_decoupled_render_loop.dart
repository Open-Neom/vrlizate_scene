import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:vector_math/vector_math.dart' as vm;
import 'package:flutter_scene/scene.dart';

import 'vr_gpu_external_render_target.dart';
import 'vr_openxr_swapchain_bridge.dart';
import 'vr_spatial_ui_quad_layer.dart';

/// Function signature for dispatching an eye render pass to an external GPU target.
typedef VrEyeRenderCallback = void Function(
  int eyeIndex,
  vm.Matrix4 viewMatrix,
  vm.Matrix4 projectionMatrix,
  VrGpuExternalRenderTarget renderTarget,
);

/// Decoupled high-frequency stereoscopic render loop for OpenXR.
///
/// Runs directly against the OpenXR frame cadence (72, 90, 120 Hz) without
/// waiting for Flutter's widget tree rebuild, layout, or paint phases.
class VrDecoupledRenderLoop {
  final VrOpenXrSwapchainBridge bridge;
  final Scene? scene;
  final VrEyeRenderCallback? onRenderEye;
  final List<VrSpatialUiQuadLayer> quadLayers;

  bool _isRunning = false;
  Timer? _loopTimer;
  int _totalFramesRendered = 0;
  int _droppedFrames = 0;
  double _currentFps = 0.0;
  double _lastFrameDurationMs = 0.0;
  double _frameDurationSumMs = 0.0;
  DateTime? _lastFrameTime;

  VrDecoupledRenderLoop({
    required this.bridge,
    this.scene,
    this.onRenderEye,
    List<VrSpatialUiQuadLayer>? quadLayers,
  }) : quadLayers = quadLayers ?? [];

  bool get isRunning => _isRunning;
  int get totalFramesRendered => _totalFramesRendered;
  int get droppedFrames => _droppedFrames;
  double get currentFps => _currentFps;
  double get lastFrameDurationMs => _lastFrameDurationMs;
  double get averageFrameDurationMs =>
      _totalFramesRendered > 0 ? _frameDurationSumMs / _totalFramesRendered : 0.0;

  /// Registers a spatial 2D UI quad layer to be composited with the 3D scene.
  void addQuadLayer(VrSpatialUiQuadLayer layer) {
    if (!quadLayers.contains(layer)) {
      quadLayers.add(layer);
    }
  }

  /// Removes a spatial 2D UI quad layer.
  void removeQuadLayer(String layerId) {
    quadLayers.removeWhere((l) => l.layerId == layerId);
  }

  /// Starts the decoupled render loop.
  Future<bool> start() async {
    if (_isRunning) return true;

    if (!bridge.isSessionRunning) {
      final ok = await bridge.initializeSession();
      if (!ok) return false;
    }

    _isRunning = true;
    _lastFrameTime = DateTime.now();

    // Run high-frequency ticker matching OpenXR frame interval
    _scheduleNextFrame();
    return true;
  }

  void _scheduleNextFrame() {
    if (!_isRunning) return;

    // Use microtask / tight timer to tick at OpenXR cadence
    _loopTimer = Timer(const Duration(milliseconds: 11), () {
      if (!_isRunning) return;
      try {
        renderSingleFrame();
      } catch (e, st) {
        _droppedFrames++;
        debugPrint('Error in VrDecoupledRenderLoop: $e\n$st');
      }
      _scheduleNextFrame();
    });
  }

  /// Executes a single complete stereo render frame against the OpenXR bridge.
  void renderSingleFrame() {
    final start = DateTime.now();

    // 1. Wait for compositor frame boundary
    final timing = bridge.waitFrame();

    // 2. Begin frame
    bridge.beginFrame(timing.frameIndex);

    // 3. Query predicted view poses for left and right eyes
    final views = bridge.getPredictedViews(timing.predictedDisplayTimeNs);
    if (views.length < 2) {
      bridge.endFrame(timing.frameIndex, const []);
      return;
    }

    // 4. Acquire swapchain images for both eyes
    final leftTarget = bridge.acquireSwapchainImage(0);
    final rightTarget = bridge.acquireSwapchainImage(1);

    // 5. Compute view and projection matrices
    final leftView = views[0].computeViewMatrix();
    final leftProj = views[0].computeProjectionMatrix();

    final rightView = views[1].computeViewMatrix();
    final rightProj = views[1].computeProjectionMatrix();

    // 6. Dispatch eye render passes
    _dispatchEye(0, leftView, leftProj, leftTarget);
    _dispatchEye(1, rightView, rightProj, rightTarget);

    // 7. Release swapchain images with GPU fence handles
    bridge.releaseSwapchainImage(0, syncFenceHandle: leftTarget.syncFenceHandle);
    bridge.releaseSwapchainImage(1, syncFenceHandle: rightTarget.syncFenceHandle);

    // 8. Submit stereo projection and quad UI layers to OpenXR compositor
    bridge.endFrame(
      timing.frameIndex,
      [leftTarget, rightTarget],
      quadLayers: quadLayers.map((l) => l.toOpenXrQuadDescriptor()).toList(),
    );

    // 9. Update telemetry
    final end = DateTime.now();
    _lastFrameDurationMs = end.difference(start).inMicroseconds / 1000.0;
    _frameDurationSumMs += _lastFrameDurationMs;
    _totalFramesRendered++;

    if (_lastFrameTime != null) {
      final deltaSec = end.difference(_lastFrameTime!).inMicroseconds / 1000000.0;
      if (deltaSec > 0.0) {
        _currentFps = 0.9 * _currentFps + 0.1 * (1.0 / deltaSec);
      }
    }
    _lastFrameTime = end;
  }

  void _dispatchEye(
    int eyeIndex,
    vm.Matrix4 viewMatrix,
    vm.Matrix4 projMatrix,
    VrGpuExternalRenderTarget target,
  ) {
    if (onRenderEye != null) {
      onRenderEye!(eyeIndex, viewMatrix, projMatrix, target);
    }
  }

  /// Stops the render loop.
  void stop() {
    _isRunning = false;
    _loopTimer?.cancel();
    _loopTimer = null;
  }

  /// Releases resources.
  void dispose() {
    stop();
    quadLayers.clear();
  }
}
