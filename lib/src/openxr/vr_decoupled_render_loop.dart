import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:vector_math/vector_math.dart' as vm;
import 'package:flutter_scene/scene.dart';

import 'vr_gpu_external_render_target.dart';
import 'vr_openxr_swapchain_bridge.dart';
import 'vr_spatial_ui_quad_layer.dart';

/// Function signature for dispatching an eye render pass to an external GPU target.
typedef VrEyeRenderCallback =
    void Function(
      int eyeIndex,
      vm.Matrix4 viewMatrix,
      vm.Matrix4 projectionMatrix,
      VrGpuExternalRenderTarget renderTarget,
    );

/// Experimental frame-lifecycle harness, not a native OpenXR compositor.
///
/// Runs on the caller's Dart isolate, so UI isolate stalls still delay frames.
/// Supply a renderer and a real runtime separately; no GPU textures are imported
/// by this class. Telemetry measures CPU callbacks, not GPU presentation.
class VrDecoupledRenderLoop {
  final VrOpenXrSwapchainBridge bridge;

  /// Application context only; the render callback must render it explicitly.
  final Scene? scene;
  final VrEyeRenderCallback? onRenderEye;
  final List<VrSpatialUiQuadLayer> quadLayers;

  bool _isRunning = false;
  bool _disposed = false;
  bool _rendering = false;
  bool _ownsSession = false;
  int _generation = 0;
  Future<bool>? _starting;
  Future<void>? _disposing;
  Duration _frameInterval = const Duration(microseconds: 13889);
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
  }) : quadLayers = List.of(quadLayers ?? const []);

  bool get isRunning => _isRunning;
  int get totalFramesRendered => _totalFramesRendered;
  int get droppedFrames => _droppedFrames;
  double get currentFps => _currentFps;
  double get lastFrameDurationMs => _lastFrameDurationMs;
  double get averageFrameDurationMs => _totalFramesRendered > 0
      ? _frameDurationSumMs / _totalFramesRendered
      : 0.0;

  /// Registers a spatial 2D UI quad layer to be composited with the 3D scene.
  void addQuadLayer(VrSpatialUiQuadLayer layer) {
    _ensureAlive();
    if (!quadLayers.contains(layer)) {
      quadLayers.add(layer);
    }
  }

  /// Removes a spatial 2D UI quad layer.
  void removeQuadLayer(String layerId) {
    _ensureAlive();
    quadLayers.removeWhere((l) => l.layerId == layerId);
  }

  /// Starts the decoupled render loop.
  Future<bool> start() {
    _ensureAlive();
    _ensureRenderer();
    if (_isRunning) return Future.value(true);
    final pending = _starting;
    if (pending != null) return pending;
    final future = _start(++_generation);
    _starting = future;
    return future.then(
      (value) {
        if (identical(_starting, future)) _starting = null;
        return value;
      },
      onError: (Object error, StackTrace stack) {
        if (identical(_starting, future)) _starting = null;
        Error.throwWithStackTrace(error, stack);
      },
    );
  }

  Future<bool> _start(int generation) async {
    if (!bridge.isSessionRunning) {
      final ok = await bridge.initializeSession();
      if (!ok) return false;
      _ownsSession = true;
    }
    if (_disposed || generation != _generation) return false;
    _isRunning = true;
    _lastFrameTime = DateTime.now();

    _scheduleNextFrame();
    return true;
  }

  void _scheduleNextFrame() {
    if (!_isRunning) return;

    // Experimental fallback pacing, not an independent compositor thread.
    _loopTimer = Timer(_frameInterval, () {
      if (!_isRunning) return;
      try {
        renderSingleFrame();
      } catch (e, st) {
        debugPrint('Error in VrDecoupledRenderLoop: $e\n$st');
      }
      _scheduleNextFrame();
    });
  }

  /// Executes a single complete stereo render frame against the OpenXR bridge.
  void renderSingleFrame() {
    _ensureAlive();
    _ensureRenderer();
    if (!bridge.isSessionRunning) {
      throw StateError('An initialized XR bridge session is required.');
    }
    if (_rendering) throw StateError('An XR frame is already in progress.');
    _rendering = true;
    final start = DateTime.now();
    final targets = <VrGpuExternalRenderTarget>[];
    VrOpenXrFrameTiming? timing;
    var begun = false;
    var rendered = false;
    Object? failure;
    StackTrace? failureStack;
    try {
      timing = bridge.waitFrame();
      final interval = timing.predictedFrameIntervalSeconds;
      if (!interval.isFinite || interval <= 0) {
        throw StateError('XR frame interval must be finite and positive.');
      }
      _frameInterval = Duration(
        microseconds: (interval * 1000000).round().clamp(1, 1000000),
      );
      bridge.beginFrame(timing.frameIndex);
      begun = true;
      final views = bridge.getPredictedViews(timing.predictedDisplayTimeNs);
      if (views.length >= 2) {
        targets.add(bridge.acquireSwapchainImage(0));
        targets.add(bridge.acquireSwapchainImage(1));
        for (var eye = 0; eye < 2; eye++) {
          _dispatchEye(
            eye,
            views[eye].computeViewMatrix(),
            views[eye].computeProjectionMatrix(),
            targets[eye],
          );
        }
        rendered = true;
      }
    } catch (error, stack) {
      failure = error;
      failureStack = stack;
    } finally {
      for (final target in targets) {
        try {
          bridge.releaseSwapchainImage(
            target.eyeIndex,
            syncFenceHandle: target.syncFenceHandle,
          );
          target.markReleased();
        } catch (error, stack) {
          failure ??= error;
          failureStack ??= stack;
        }
      }
      if (begun) {
        try {
          bridge.endFrame(
            timing!.frameIndex,
            failure == null && rendered ? targets : const [],
            quadLayers: failure == null && rendered
                ? quadLayers
                      .where(
                        (layer) => layer.textureId != null && !layer.isDirty,
                      )
                      .map((layer) => layer.toOpenXrQuadDescriptor())
                      .toList()
                : const [],
          );
        } catch (error, stack) {
          failure ??= error;
          failureStack ??= stack;
        }
      }
      _rendering = false;
    }
    if (failure != null) {
      _droppedFrames++;
      Error.throwWithStackTrace(failure, failureStack!);
    }
    if (!rendered) return;

    // 9. Update telemetry
    final end = DateTime.now();
    _lastFrameDurationMs = end.difference(start).inMicroseconds / 1000.0;
    _frameDurationSumMs += _lastFrameDurationMs;
    _totalFramesRendered++;

    if (_lastFrameTime != null) {
      final deltaSec =
          end.difference(_lastFrameTime!).inMicroseconds / 1000000.0;
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
    _generation++;
    _isRunning = false;
    _loopTimer?.cancel();
    _loopTimer = null;
  }

  /// Cancels pending starts and closes sessions initialized by this loop.
  /// Already-running, caller-owned sessions remain the caller's responsibility.
  Future<void> dispose() => _disposing ??= _dispose();

  Future<void> _dispose() async {
    _disposed = true;
    stop();
    try {
      await _starting;
    } finally {
      quadLayers.clear();
      if (_ownsSession) {
        _ownsSession = false;
        await bridge.endSession();
      }
    }
  }

  void _ensureAlive() {
    if (_disposed) throw StateError('VrDecoupledRenderLoop was disposed.');
  }

  void _ensureRenderer() {
    if (onRenderEye == null) {
      throw StateError(
        'Supply onRenderEye; the experimental loop has no built-in renderer.',
      );
    }
  }
}
