#version 460 core

// ============================================================================
// Adapted from Qualcomm Snapdragon Game Super Resolution 1 (SGSR v1)
// Edge-Directed Mobile Spatial Upscaler (OperationMode 1 + UseEdgeDirection)
//
// Copyright (c) 2025, Qualcomm Innovation Center, Inc. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause
//
// Ported to Flutter Impeller runtime_effect GLSL for VRlizate StereoSceneView:
// - Explicit input-texel-center 12-tap cross stencil (no ES3.1 textureGather)
// - Strict stereo half-viewport clamping so eyes never bleed across x = 0.5
// - Extended-range HDR highlight preservation (> 1.0) without SDR top-clipping
// ============================================================================

#include <flutter/runtime_effect.glsl>

// Auto-populated by Impeller's ui.ImageFilter.shader to filtered layer size.
uniform vec2 u_size;
// Effective internal 3D render scale relative to u_size [0.25 .. 1.0].
uniform float u_render_scale;
// Edge reconstruction sharpness (SGSR1 default: 2.0).
uniform float u_sharpness;
// Early-exit edge vote threshold (SGSR1 default: 8.0 / 255.0).
uniform float u_threshold;
// 1.0 when left/right split-screen stereo is active; 0.0 for mono viewports.
uniform float u_stereo_split;

uniform sampler2D u_texture_input;

out vec4 fragColor;

vec2 toBackendUv(vec2 fullUv) {
  vec2 uv = clamp(fullUv, vec2(0.0005), vec2(0.9995));
#ifdef IMPELLER_TARGET_OPENGLES
  uv.y = 1.0 - uv.y;
#endif
  return uv;
}

vec2 eyeToScreenUv(vec2 eyeUv, bool isLeft, bool isStereo) {
  vec2 clamped = clamp(eyeUv, vec2(0.0005), vec2(0.9995));
  if (!isStereo) {
    return toBackendUv(clamped);
  }
  float fullX = isLeft ? (clamped.x * 0.5) : (0.5 + clamped.x * 0.5);
  return toBackendUv(vec2(fullX, clamped.y));
}

float luma(vec3 rgb) {
  return dot(rgb, vec3(0.299, 0.587, 0.114));
}

float sampleEyeTap(
  vec2 baseTexel,
  vec2 offset,
  vec2 eyeInputSize,
  bool isLeft,
  bool isStereo
) {
  vec2 texelCenter = clamp(
    baseTexel + offset + vec2(0.5),
    vec2(0.5),
    eyeInputSize - vec2(0.5)
  );
  vec2 eyeUv = texelCenter / eyeInputSize;
  return luma(
    texture(u_texture_input, eyeToScreenUv(eyeUv, isLeft, isStereo)).rgb
  );
}

float fastLanczos2(float x) {
  float wA = x - 4.0;
  float wB = x * wA - wA;
  wA *= wA;
  return wB * wA;
}

vec2 weightY(float dx, float dy, float c, vec3 data) {
  float std = data.x;
  vec2 dir = data.yz;
  float edgeDis = (dx * dir.y) + (dy * dir.x);
  float x = ((dx * dx) + (dy * dy)) +
      (edgeDis * edgeDis * ((clamp(c * c * std, 0.0, 1.0) * 0.7) - 1.0));
  float w = fastLanczos2(x);
  return vec2(w, w * c);
}

vec2 edgeDirection(vec4 left, vec4 right) {
  float rxLz = right.x - left.z;
  float rwLy = right.w - left.y;
  vec2 delta = vec2(rxLz + rwLy, rxLz - rwLy);
  float lengthInv = inversesqrt(
    (delta.x * delta.x + 3.075740e-05) + (delta.y * delta.y)
  );
  return delta * lengthInv;
}

void main() {
  vec2 safeSize = max(u_size, vec2(2.0));
  vec2 screenUv = FlutterFragCoord().xy / safeSize;
  bool isStereo = u_stereo_split > 0.5;
  bool isLeft = isStereo && (screenUv.x < 0.5);

  vec2 eyeUv = isStereo
      ? vec2(
          isLeft ? (screenUv.x * 2.0) : ((screenUv.x - 0.5) * 2.0),
          screenUv.y
        )
      : screenUv;

  vec4 color = texture(
    u_texture_input,
    eyeToScreenUv(eyeUv, isLeft, isStereo)
  );

  float scale = clamp(u_render_scale, 0.25, 1.0);
  if (scale >= 0.999) {
    fragColor = color;
    return;
  }

  vec2 eyeOutSize = vec2(
    isStereo ? (safeSize.x * 0.5) : safeSize.x,
    safeSize.y
  );
  vec2 eyeInputSize = max(floor(eyeOutSize * scale), vec2(2.0));

  vec2 imgCoord = (eyeUv * eyeInputSize) - vec2(0.5);
  vec2 imgCoordPixel = floor(imgCoord);
  vec2 pl = imgCoord - imgCoordPixel;

  float cLuma = luma(color.rgb);
  float leftZ = sampleEyeTap(
    imgCoordPixel,
    vec2(0.0, 0.0),
    eyeInputSize,
    isLeft,
    isStereo
  );
  float leftY = sampleEyeTap(
    imgCoordPixel,
    vec2(0.0, 1.0),
    eyeInputSize,
    isLeft,
    isStereo
  );
  float rightW = sampleEyeTap(
    imgCoordPixel,
    vec2(1.0, 0.0),
    eyeInputSize,
    isLeft,
    isStereo
  );

  float edgeVote =
      abs(leftZ - leftY) +
      abs(leftZ - rightW) +
      abs(cLuma - leftY) +
      abs(cLuma - leftZ);

  if (edgeVote > u_threshold) {
    vec4 left = vec4(
      sampleEyeTap(imgCoordPixel, vec2(-1.0, 1.0), eyeInputSize, isLeft, isStereo),
      leftY,
      leftZ,
      sampleEyeTap(imgCoordPixel, vec2(-1.0, 0.0), eyeInputSize, isLeft, isStereo)
    );
    vec4 right = vec4(
      sampleEyeTap(imgCoordPixel, vec2(1.0, 1.0), eyeInputSize, isLeft, isStereo),
      sampleEyeTap(imgCoordPixel, vec2(2.0, 1.0), eyeInputSize, isLeft, isStereo),
      sampleEyeTap(imgCoordPixel, vec2(2.0, 0.0), eyeInputSize, isLeft, isStereo),
      rightW
    );
    vec4 upDown = vec4(
      sampleEyeTap(imgCoordPixel, vec2(0.0, -1.0), eyeInputSize, isLeft, isStereo),
      sampleEyeTap(imgCoordPixel, vec2(1.0, -1.0), eyeInputSize, isLeft, isStereo),
      sampleEyeTap(imgCoordPixel, vec2(1.0, 2.0), eyeInputSize, isLeft, isStereo),
      sampleEyeTap(imgCoordPixel, vec2(0.0, 2.0), eyeInputSize, isLeft, isStereo)
    );

    float mean = (left.y + left.z + right.x + right.w) * 0.25;
    left -= vec4(mean);
    right -= vec4(mean);
    upDown -= vec4(mean);
    float centerDelta = cLuma - mean;

    float sum =
        abs(left.x) + abs(left.y) + abs(left.z) + abs(left.w) +
        abs(right.x) + abs(right.y) + abs(right.z) + abs(right.w) +
        abs(upDown.x) + abs(upDown.y) + abs(upDown.z) + abs(upDown.w);
    float sumMean = 1.014185e+01 / max(sum, 1.0e-5);
    float std = sumMean * sumMean;

    vec3 data = vec3(std, edgeDirection(left, right));

    vec2 aWY = weightY(pl.x, pl.y + 1.0, upDown.x, data);
    aWY += weightY(pl.x - 1.0, pl.y + 1.0, upDown.y, data);
    aWY += weightY(pl.x - 1.0, pl.y - 2.0, upDown.z, data);
    aWY += weightY(pl.x, pl.y - 2.0, upDown.w, data);
    aWY += weightY(pl.x + 1.0, pl.y - 1.0, left.x, data);
    aWY += weightY(pl.x, pl.y - 1.0, left.y, data);
    aWY += weightY(pl.x, pl.y, left.z, data);
    aWY += weightY(pl.x + 1.0, pl.y, left.w, data);
    aWY += weightY(pl.x - 1.0, pl.y - 1.0, right.x, data);
    aWY += weightY(pl.x - 2.0, pl.y - 1.0, right.y, data);
    aWY += weightY(pl.x - 2.0, pl.y, right.z, data);
    aWY += weightY(pl.x - 1.0, pl.y, right.w, data);

    float denom = abs(aWY.x) > 1.0e-5
        ? aWY.x
        : (aWY.x < 0.0 ? -1.0e-5 : 1.0e-5);
    float finalY = aWY.y / denom;
    float maxY = max(max(left.y, left.z), max(right.x, right.w));
    float minY = min(min(left.y, left.z), min(right.x, right.w));
    float deltaY = clamp(u_sharpness * finalY, minY, maxY) - centerDelta;

    float maxSwing = (23.0 / 255.0) * max(1.0, cLuma);
    deltaY = clamp(deltaY, -maxSwing, maxSwing);

    // Preserve extended-range HDR highlights (> 1.0) without top-clipping.
    color.rgb = max(color.rgb + vec3(deltaY), vec3(0.0));
  }

  fragColor = color;
}
