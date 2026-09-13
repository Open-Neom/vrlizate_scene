import 'package:vrlizate/vrlizate.dart';

/// Experimental descriptor of an application-owned external GPU render target.
///
/// Storing a native handle does not import it into Flutter GPU or remove Canvas
/// copies. A platform-specific renderer and runtime must implement that binding.
class VrGpuExternalRenderTarget {
  final int targetId;
  final VrExternalRenderTargetDescriptor descriptor;
  final int eyeIndex; // 0 = Left eye, 1 = Right eye

  /// OpenGL ES native texture ID (if running under OpenGLES backend).
  final int? glTextureId;

  /// 64-bit handle/pointer to Vulkan VkImage (if running under Vulkan backend).
  final int? vkImageHandle;

  /// 64-bit handle/pointer to Vulkan VkImageView.
  final int? vkImageViewHandle;

  /// Direct GPU-to-GPU fence synchronization handle (e.g. EGLSyncKHR or VkFence).
  /// Its synchronization semantics must be implemented by the supplied bridge.
  int? syncFenceHandle;

  bool _isAcquired = false;

  VrGpuExternalRenderTarget({
    required this.targetId,
    required this.descriptor,
    required this.eyeIndex,
    this.glTextureId,
    this.vkImageHandle,
    this.vkImageViewHandle,
    this.syncFenceHandle,
    bool initiallyAcquired = true,
  }) : _isAcquired = initiallyAcquired,
       assert(
         eyeIndex == 0 || eyeIndex == 1,
         'eyeIndex must be 0 (left) or 1 (right)',
       ),
       assert(
         glTextureId != null || vkImageHandle != null,
         'Either glTextureId or vkImageHandle must be specified for external GPU target',
       );

  int get width => descriptor.width;
  int get height => descriptor.height;
  double get aspectRatio => descriptor.aspectRatio;
  VrGpuBackend get backend => descriptor.backend;
  VrGpuTextureFormat get format => descriptor.format;
  bool get isAcquired => _isAcquired;

  /// Marks this render target as acquired from the OpenXR swapchain.
  void markAcquired() {
    _isAcquired = true;
  }

  /// Marks this target as released back to the compositor after rendering.
  void markReleased({int? fenceHandle}) {
    _isAcquired = false;
    if (fenceHandle != null) {
      syncFenceHandle = fenceHandle;
    }
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'targetId': targetId,
    'descriptor': descriptor.toJson(),
    'eyeIndex': eyeIndex,
    'glTextureId': glTextureId,
    'vkImageHandle': vkImageHandle != null
        ? '0x${vkImageHandle!.toRadixString(16)}'
        : null,
    'vkImageViewHandle': vkImageViewHandle != null
        ? '0x${vkImageViewHandle!.toRadixString(16)}'
        : null,
    'syncFenceHandle': syncFenceHandle != null
        ? '0x${syncFenceHandle!.toRadixString(16)}'
        : null,
    'isAcquired': _isAcquired,
  };

  @override
  String toString() =>
      'VrGpuExternalRenderTarget(id: $targetId, eye: ${eyeIndex == 0 ? "L" : "R"}, '
      '${descriptor.backend.name} tex: ${glTextureId ?? vkImageHandle}, '
      'size: ${width}x$height, acquired: $_isAcquired)';
}
