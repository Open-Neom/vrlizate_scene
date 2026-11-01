#version 460 core

#include <flutter/runtime_effect.glsl>

// Auto-populated by Impeller's ui.ImageFilter.shader to filtered layer size.
uniform vec2 u_size;
// Stereo optical center horizontal inset [0.0 .. 0.35].
uniform float u_inset;
// Radial Brown-Conrady barrel distortion coefficients [0.0 .. 0.50].
uniform float u_k1;
uniform float u_k2;
// Per-channel lateral chromatic dispersion compensation [-0.08 .. 0.08].
uniform float u_ca_red;
uniform float u_ca_blue;
// Circular OLED black mask radius for folded Pancake optics (0.0 = disabled).
uniform float u_aperture;

uniform sampler2D u_texture_input;

out vec4 fragColor;

vec2 toBackendUv(vec2 fullUv) {
  vec2 uv = clamp(fullUv, vec2(0.0005), vec2(0.9995));
#ifdef IMPELLER_TARGET_OPENGLES
  uv.y = 1.0 - uv.y;
#endif
  return uv;
}

float eyeBorderMask(vec2 eyeUv) {
  vec2 d = min(eyeUv, vec2(1.0) - eyeUv);
  float edge = min(d.x, d.y);
  return smoothstep(-0.002, 0.008, edge);
}

vec2 eyeToScreenUv(vec2 eyeUv, bool isLeft) {
  float clampedX = clamp(eyeUv.x, 0.001, 0.999);
  float clampedY = clamp(eyeUv.y, 0.001, 0.999);
  float fullX = isLeft ? (clampedX * 0.5) : (0.5 + clampedX * 0.5);
  return toBackendUv(vec2(fullX, clampedY));
}

void main() {
  vec2 safeSize = max(u_size, vec2(1.0));
  vec2 screenUv = FlutterFragCoord().xy / safeSize;
  bool isLeft = screenUv.x < 0.5;

  vec2 eyeUv = vec2(
    isLeft ? (screenUv.x * 2.0) : ((screenUv.x - 0.5) * 2.0),
    screenUv.y
  );

  float centerShift = u_inset * 0.5;
  vec2 lensCenter = vec2(isLeft ? (0.5 + centerShift) : (0.5 - centerShift), 0.5);
  vec2 delta = (eyeUv - lensCenter) * 2.0;

  // Physical millimeter-isotropic radius inscribed in each eye half-viewport.
  float eyeAspect = (safeSize.x * 0.5) / safeSize.y;
  vec2 pMetric = (eyeAspect >= 1.0)
      ? vec2(delta.x * eyeAspect, delta.y)
      : vec2(delta.x, delta.y / max(eyeAspect, 0.001));

  float r2 = dot(pMetric, pMetric);
  float r4 = r2 * r2;

  float invZoom = 1.0 / max(1.0 + u_k1 * 0.55 + u_k2 * 0.30, 0.25);
  float baseWarp = (1.0 + u_k1 * r2 + u_k2 * r4) * invZoom;

  vec2 uvG = lensCenter + (delta * baseWarp) * 0.5;
  vec2 uvR = lensCenter + (delta * (baseWarp * (1.0 + u_ca_red * r2))) * 0.5;
  vec2 uvB = lensCenter + (delta * (baseWarp * (1.0 + u_ca_blue * r2))) * 0.5;

  float maskG = eyeBorderMask(uvG);
  float maskR = eyeBorderMask(uvR);
  float maskB = eyeBorderMask(uvB);

  vec4 sampleG = texture(u_texture_input, eyeToScreenUv(uvG, isLeft));
  float rChan = texture(u_texture_input, eyeToScreenUv(uvR, isLeft)).r * maskR;
  float gChan = sampleG.g * maskG;
  float bChan = texture(u_texture_input, eyeToScreenUv(uvB, isLeft)).b * maskB;

  float apertureMask = 1.0;
  if (u_aperture > 0.0) {
    float r = sqrt(r2);
    apertureMask = 1.0 - smoothstep(max(0.0, u_aperture - 0.03), u_aperture, r);
  }

  vec3 rgb = vec3(rChan, gChan, bChan) * apertureMask;
  fragColor = vec4(rgb, 1.0);
}
