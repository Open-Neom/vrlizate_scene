# Changelog

## 0.2.0 — 2026-08-27

### Added
- **Dual Stereoscopic Reticles (`StereoSceneView`)**: Center-gaze reticle rendered into both eye viewports at 25% (left) and 75% (right) screen width with animated dwell arc.
- **Physical Visor Alignment Guide (`showAlignmentDivider = true`)**: Central 3px black divider with top and bottom cyan alignment notch ticks to prevent optical cross-bleed and assist physical visor centering.
- **Hands-Free Zenith Recenter (`zenithRecenter = true`)**: Tilting head upwards (>55° pitch) presents a calibration target with 0.8s dwell to recalibrate the forward heading hands-free.
- **Double-Tap Recenter (`doubleTapToRecenter = true`)**: Double-tapping the screen recalibrates orientation with medium haptic pulse.
- **Micro-Haptics Integration (`enableHaptics = true`)**: Integrated tactile feedback on dwell progress and selection.
- **Refined Smart Quality Tiers (`VrQualityPreset.detectTier`)**: Differentiates high-DPR flagships (≥90Hz & DPR ≥ 2.7) from budget 90Hz panels (Moto G20) which auto-select the optimized `low` preset (no MSAA/Bloom, 0.75x resolution).
- **Fast Dynamic Scaling**: Frame evaluation window tuned to ~1.2s for responsive throttling.
