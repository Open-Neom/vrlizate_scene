// ============================================================================
// Copyright 2026 VRlizate Project. All rights reserved.
// OpenXR External GPU Render Target & Flutter Engine Embedder Bridge
//
// Reference implementation based on Visual Space (2026) architectural pattern
// for Meta Quest 3 / Standalone XR devices running Flutter GPU & flutter_scene.
// ============================================================================

#pragma once

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Supported graphics backends for external render targets.
typedef enum VrNativeGpuBackend {
    VR_BACKEND_OPENGL_ES = 0,
    VR_BACKEND_VULKAN = 1,
} VrNativeGpuBackend;

/// Timing returned by xrWaitFrame for motion-to-photon latency compensation.
typedef struct VrNativeFrameTiming {
    int64_t frameIndex;
    int64_t predictedDisplayTimeNs;
    double predictedFrameIntervalSeconds;
} VrNativeFrameTiming;

/// Eye view pose and optical FOV angles.
typedef struct VrNativeViewPose {
    int32_t eyeIndex; // 0 = Left, 1 = Right
    float posX, posY, posZ;
    float quatX, quatY, quatZ, quatW;
    float fovLeft, fovRight, fovUp, fovDown; // radians
} VrNativeViewPose;

/// Offscreen 2D UI Quad Layer descriptor for XrCompositionLayerQuad.
typedef struct VrNativeQuadLayerDescriptor {
    const char* layerId;
    uint32_t textureId; // GL texture ID or VkImageView index
    int32_t pixelWidth;
    int32_t pixelHeight;
    float widthMeters;
    float heightMeters;
    float posX, posY, posZ;
    float quatX, quatY, quatZ, quatW;
} VrNativeQuadLayerDescriptor;

/// Initializes the OpenXR instance and binds to Android activity / JVM context.
bool VrOpenXr_Initialize(void* jniVm, void* activityContext, VrNativeGpuBackend backend);

/// Tears down the OpenXR session and destroys swapchain images.
void VrOpenXr_Shutdown(void);

/// Creates dual eye swapchains with the requested dimensions and pixel format.
bool VrOpenXr_CreateSwapchains(int32_t width, int32_t height, int32_t sampleCount);

/// Blocks until the OpenXR compositor signals the frame boundary (xrWaitFrame).
bool VrOpenXr_WaitFrame(VrNativeFrameTiming* outTiming);

/// Begins the OpenXR frame (xrBeginFrame).
bool VrOpenXr_BeginFrame(int64_t frameIndex);

/// Acquires the hardware texture ID from the eye swapchain (xrAcquireSwapchainImage).
/// In OpenGL ES this is a GLuint texture name; in Vulkan it represents a VkImage index.
uint32_t VrOpenXr_AcquireSwapchainImage(int32_t eyeIndex);

/// Releases the swapchain image and submits a GPU sync fence handle (xrReleaseSwapchainImage).
/// Pass syncFenceHandle = 0 to insert an automatic EGLSyncKHR / VkFence.
bool VrOpenXr_ReleaseSwapchainImage(int32_t eyeIndex, void* syncFenceHandle);

/// Queries the predicted view poses for left and right eyes for the current frame.
bool VrOpenXr_GetPredictedViews(int64_t predictedDisplayTimeNs, VrNativeViewPose* outLeftView, VrNativeViewPose* outRightView);

/// Submits the stereo projection layer and optional 2D spatial quad layers to the compositor (xrEndFrame).
bool VrOpenXr_EndFrame(
    int64_t frameIndex,
    const VrNativeQuadLayerDescriptor* quadLayers,
    int32_t quadLayerCount
);

#ifdef __cplusplus
}
#endif
