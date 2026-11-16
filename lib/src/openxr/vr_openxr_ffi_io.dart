import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:vector_math/vector_math.dart' as vm;
import 'package:vrlizate/vrlizate.dart';

import '../third_party/openxr_flutter_bridge.g.dart';
import 'vr_gpu_external_render_target.dart';
import 'vr_openxr_ffi_stub.dart';
import 'vr_openxr_swapchain_bridge.dart';

typedef _MallocNative = ffi.Pointer<ffi.Void> Function(ffi.Size);
typedef _MallocDart = ffi.Pointer<ffi.Void> Function(int);
typedef _FreeNative = ffi.Void Function(ffi.Pointer<ffi.Void>);
typedef _FreeDart = void Function(ffi.Pointer<ffi.Void>);

VrOpenXrFfiDriver? tryOpenOpenXrFfiDriver(String libraryName) {
  final candidates = <String>[
    if (libraryName.contains('/') || libraryName.contains('\\'))
      libraryName
    else if (Platform.isAndroid || Platform.isLinux)
      'lib$libraryName.so'
    else if (Platform.isMacOS || Platform.isIOS)
      'lib$libraryName.dylib'
    else if (Platform.isWindows)
      '$libraryName.dll'
    else
      libraryName,
  ];

  for (final path in candidates) {
    try {
      final lib = ffi.DynamicLibrary.open(path);
      final bindings = OpenXrFlutterBridgeBindings(lib);
      // Verify core symbol resolution eagerly so missing symbols fail closed.
      lib.lookup<ffi.NativeType>('VrOpenXr_Initialize');
      final proc = ffi.DynamicLibrary.process();
      final malloc = proc.lookupFunction<_MallocNative, _MallocDart>(
        'malloc',
        isLeaf: true,
      );
      final free = proc.lookupFunction<_FreeNative, _FreeDart>(
        'free',
        isLeaf: true,
      );
      return _IoOpenXrFfiDriver(
        dylib: lib,
        bindings: bindings,
        malloc: malloc,
        free: free,
      );
    } on Object {
      // Try next candidate or fail closed when library is absent.
    }
  }
  return null;
}

final class _IoOpenXrFfiDriver implements VrOpenXrFfiDriver {
  _IoOpenXrFfiDriver({
    required ffi.DynamicLibrary dylib,
    required this.bindings,
    required this.malloc,
    required this.free,
  }) : _dylib = dylib,
       // Pre-allocate reusable native scratch structs so 90–120 Hz frame ticks
       // perform ZERO native or Dart C-struct allocations!
       _timingScratch = malloc(
         ffi.sizeOf<VrNativeFrameTiming>(),
       ).cast<VrNativeFrameTiming>(),
       _leftPoseScratch = malloc(
         ffi.sizeOf<VrNativeViewPose>(),
       ).cast<VrNativeViewPose>(),
       _rightPoseScratch = malloc(
         ffi.sizeOf<VrNativeViewPose>(),
       ).cast<VrNativeViewPose>();

  final ffi.DynamicLibrary _dylib;
  final OpenXrFlutterBridgeBindings bindings;
  final _MallocDart malloc;
  final _FreeDart free;
  final ffi.Pointer<VrNativeFrameTiming> _timingScratch;
  final ffi.Pointer<VrNativeViewPose> _leftPoseScratch;
  final ffi.Pointer<VrNativeViewPose> _rightPoseScratch;
  bool _disposed = false;

  @override
  Object? get dylib => _dylib;

  @override
  bool get isNativeLoaded => !_disposed;

  @override
  bool initialize({
    required int swapchainWidth,
    required int swapchainHeight,
  }) {
    if (_disposed) return false;
    final handles = VrDirectDeviceBridge.instance.androidOpenXrHandlesSync();
    final vmPtr = handles != null
        ? ffi.Pointer<ffi.Void>.fromAddress(handles.javaVmAddress)
        : ffi.nullptr;
    final ctxPtr = handles != null
        ? ffi.Pointer<ffi.Void>.fromAddress(handles.appContextAddress)
        : ffi.nullptr;
    final ok = bindings.VrOpenXr_Initialize(
      vmPtr,
      ctxPtr,
      VrNativeGpuBackend.VR_BACKEND_VULKAN,
    );
    if (!ok) return false;
    return bindings.VrOpenXr_CreateSwapchains(
      swapchainWidth,
      swapchainHeight,
      1,
    );
  }

  @override
  void shutdown() {
    if (_disposed) return;
    bindings.VrOpenXr_Shutdown();
  }

  @override
  VrOpenXrFrameTiming waitFrame() {
    final ok = bindings.VrOpenXr_WaitFrame(_timingScratch);
    if (!ok) {
      throw StateError('VrOpenXr_WaitFrame failed in native OpenXR runtime.');
    }
    final t = _timingScratch.ref;
    return VrOpenXrFrameTiming(
      frameIndex: t.frameIndex,
      predictedDisplayTimeNs: t.predictedDisplayTimeNs,
      predictedFrameIntervalSeconds: t.predictedFrameIntervalSeconds > 0
          ? t.predictedFrameIntervalSeconds
          : 1.0 / 72.0,
    );
  }

  @override
  void beginFrame(int frameIndex) {
    if (!bindings.VrOpenXr_BeginFrame(frameIndex)) {
      throw StateError('VrOpenXr_BeginFrame failed for frame $frameIndex.');
    }
  }

  @override
  VrGpuExternalRenderTarget acquireSwapchainImage(
    int eyeIndex, {
    required int width,
    required int height,
  }) {
    final handle = bindings.VrOpenXr_AcquireSwapchainImage(eyeIndex);
    return VrGpuExternalRenderTarget(
      targetId: handle,
      eyeIndex: eyeIndex,
      vkImageHandle: handle,
      descriptor: VrExternalRenderTargetDescriptor(
        width: width,
        height: height,
        backend: VrGpuBackend.vulkan,
        format: VrGpuTextureFormat.rgba8,
      ),
    );
  }

  @override
  void releaseSwapchainImage(int eyeIndex, {int? syncFenceHandle}) {
    final fencePtr = syncFenceHandle != null && syncFenceHandle != 0
        ? ffi.Pointer<ffi.Void>.fromAddress(syncFenceHandle)
        : ffi.nullptr;
    bindings.VrOpenXr_ReleaseSwapchainImage(eyeIndex, fencePtr);
  }

  @override
  void endFrame(int frameIndex) {
    if (!bindings.VrOpenXr_EndFrame(frameIndex, ffi.nullptr, 0)) {
      throw StateError('VrOpenXr_EndFrame failed for frame $frameIndex.');
    }
  }

  @override
  List<VrOpenXrViewPose> getPredictedViews(int predictedDisplayTimeNs) {
    final ok = bindings.VrOpenXr_GetPredictedViews(
      predictedDisplayTimeNs,
      _leftPoseScratch,
      _rightPoseScratch,
    );
    if (!ok) {
      throw StateError('VrOpenXr_GetPredictedViews failed.');
    }
    VrOpenXrViewPose decode(ffi.Pointer<VrNativeViewPose> ptr, int fallbackEye) {
      final p = ptr.ref;
      return VrOpenXrViewPose(
        eyeIndex: p.eyeIndex == 0 || p.eyeIndex == 1 ? p.eyeIndex : fallbackEye,
        position: vm.Vector3(p.posX, p.posY, p.posZ),
        orientation: vm.Quaternion(p.quatX, p.quatY, p.quatZ, p.quatW),
        fovLeft: p.fovLeft,
        fovRight: p.fovRight,
        fovUp: p.fovUp,
        fovDown: p.fovDown,
      );
    }

    return <VrOpenXrViewPose>[
      decode(_leftPoseScratch, 0),
      decode(_rightPoseScratch, 1),
    ];
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    free(_timingScratch.cast());
    free(_leftPoseScratch.cast());
    free(_rightPoseScratch.cast());
  }
}
