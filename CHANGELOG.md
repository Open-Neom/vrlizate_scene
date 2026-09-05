# Changelog

## 0.4.0 — 2026-09-05

### Added

- `VrWorldNavigationScope` supplies a host-owned HOME action to stereo scenes.
  The HOME button is placed once in world space and remains selectable by gaze
  independently of application targets.
- Re-export world action panels/poses and advanced 3D controls from
  `vrlizate_widgets`, alongside the multimodal driver/arbiter interfaces.
- `StereoHeadRig.screenRight` exposes the renderer's screen-horizontal axis
  separately from the underlying rig's local `right` direction.
- Projection regression tests cover near/far disparity, convergence,
  off-center and rotated poses, and agreement between reticles and gaze rays.

### Fixed

- Corrected the left/right eye baseline to match flutter_scene's view convention,
  fixing inverted stereo depth.
- Replaced toe-in cameras with parallel cameras and an asymmetric off-axis
  projection. This preserves the configured convergence plane and image inset
  without vertical disparity in projected panel corners.
- Corrected signed binocular angular parallax, including disabled/infinite
  convergence; non-finite convergence settings no longer poison camera rays.
- Suppress dwell before advancing its state, so releasing a higher-priority
  controller restarts selection on the same target after hysteresis. Hover is
  preserved and suppressed dwell does not mark the target as already selected.
- Decorative hand visuals no longer intercept raycasts. They share three meshes
  and reuse scratch vectors and node transforms during animation.

### Packaging and documented limits

- Prepare the package for pub.dev with hosted dependencies on
  `vrlizate ^1.11.0` and `vrlizate_widgets ^0.3.0`; local workspace overrides
  are excluded from the archive.
- Document simulated hands, orientation-only tracking, frame-interval quality
  heuristics and the absence of a frame-rate guarantee.
- Document that the custom projection currently bypasses directional shadows,
  SSAO and SSR in flutter_scene 0.22.2, and that exposed lens-distortion
  coefficients are not applied. Remove earlier claims that convergence
  guarantees freedom from double vision or eye fatigue.
- Record the tested SDK and the companion Home's unresolved low-end
  profile-performance limitation.

The historical 0.3.0 notes below describe the earlier implementation. Its toe-in
and guaranteed-comfort claims are superseded by the corrections and limitations
in 0.4.0.

## 0.3.0 — 2026-09-03

### Added
- **Stereoscopic Optical Convergence (`StereoHeadRig.convergenceDistance = 1.8m`)**:
  - Replaced parallel infinity-only cameras with exact toe-in convergence aiming at a comfortable 1.8m focal plane (vergence-accommodation conflict mitigation).
  - Eliminates diplopia (double vision) and eye fatigue for near- and mid-field objects (1.0m to 2.5m).
  - Added analytical angular screen parallax function `parallaxAtDistance(distanceMeters)`: crossed (negative / pop-out), zero (focal comfort plane), and uncrossed (positive / deep into the scene).
  - Exposed per-eye convergence gaze rays (`leftGazeRay`, `rightGazeRay`) intersecting exactly at the convergence point.
- **Zero-GC `VrInputArbiter` Gaze Dwell Suppression**:
  - `StereoSceneView` now integrates with `VrInputArbiter`: automatically suppresses gaze dwell progression and accidental clicks whenever active higher-priority input sources (remote smartphone joystick, physical gamepad, laser pointer) are engaged.
- **Community Input Interfaces Re-Export**:
  - Re-exported `VrInputDriver`, `VrInputSink`, `VrGamepadDriver`, `VrGamepadButton`, and `VrGamepadStick` from `package:vrlizate_scene/vrlizate_scene.dart`.

## 0.2.0 — 2026-08-27

### Added
- **Dual Stereoscopic Reticles (`StereoSceneView`)**: Center-gaze reticle rendered into both eye viewports at 25% (left) and 75% (right) screen width with animated dwell arc.
- **Physical Visor Alignment Guide (`showAlignmentDivider = true`)**: Central 3px black divider with top and bottom cyan alignment notch ticks to prevent optical cross-bleed and assist physical visor centering.
- **Hands-Free Zenith Recenter (`zenithRecenter = true`)**: Tilting head upwards (>55° pitch) presents a calibration target with 0.8s dwell to recalibrate the forward heading hands-free.
- **Double-Tap Recenter (`doubleTapToRecenter = true`)**: Double-tapping the screen recalibrates orientation with medium haptic pulse.
- **Micro-Haptics Integration (`enableHaptics = true`)**: Integrated tactile feedback on dwell progress and selection.
- **Refined Smart Quality Tiers (`VrQualityPreset.detectTier`)**: Differentiates high-DPR flagships (≥90Hz & DPR ≥ 2.7) from budget 90Hz panels (Moto G20) which auto-select the optimized `low` preset (no MSAA/Bloom, 0.75x resolution).
- **Fast Dynamic Scaling**: Frame evaluation window tuned to ~1.2s for responsive throttling.
