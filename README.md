# vrlizate_scene

Optional [flutter_scene](https://pub.dev/packages/flutter_scene) (Flutter GPU)
adapter for the [vrlizate](https://pub.dev/packages/vrlizate) VR engine.

The vrlizate core is renderer-agnostic and ships its own software 3D pipeline.
Add `vrlizate_scene` when you want **real-time GPU 3D** — glTF models, PBR
materials with image-based lighting, shadows, post-processing — rendered
stereoscopically with vrlizate head tracking and joystick-free gaze input.

## Requirements

- Flutter **master** channel (Flutter GPU has not shipped to stable).
- `flutter config --enable-dart-data-assets` (scene/shader build hooks).
- Native: any platform where Impeller runs (Android, iOS, desktop with
  `--enable-impeller`). Web works via flutter_scene's WebGL2 backend.

## Usage

```dart
import 'package:flutter_scene/scene.dart';
import 'package:vrlizate_scene/vrlizate_scene.dart';

final scene = Scene();
// ...add nodes, lights, models...

StereoSceneView(
  scene: scene,
  gazeDwellSeconds: 1.2,
  onGazeSelect: (node) {
    // Dwell-selected a named node — no joystick, no buttons.
  },
)
```

- `StereoSceneView` renders the scene as two half-screen eye views, driven by
  the vrlizate `HeadTracker` (gyroscope) with touch-drag fallback.
- Center-gaze raycasting runs every frame through the vrlizate `GazePointer`
  (adaptive dwell + grace period). Only nodes with a non-empty `Node.name`
  are gaze-interactive.
- `StereoHeadRig` wraps a vrlizate `CameraRig` and exposes per-eye
  `PerspectiveCamera`s, the `gazeRay`, and `buildStereoViews()` if you want
  to drive `SceneView` manually.

## Adaptive quality

`StereoSceneView` takes a `VrQualityPreset` (or auto-detects one from the
display when omitted) and scales resolution (`pixelRatioScale`),
anti-aliasing, and bloom per device tier:

| Tier | Detection | Resolution | AA | Bloom |
|---|---|---|---|---|
| low | ≤60 Hz panel | 0.75× | FXAA | off |
| medium | 60 Hz + high DPR | 1.0× | FXAA | off |
| high | ≥90 Hz panel | 1.0× | MSAA | on |

With `dynamicScaling: true` (default) frame times are monitored after a
warmup; if the rolling average exceeds the ~45 FPS budget, quality steps
down one tier automatically. Apps should size shadow-casting lights with
`preset.shadowMapResolution` (read it from `StereoSceneView`'s
`effectivePreset` or via `onQualityChanged`).

## Roadmap: integration into vrlizate

This package is **private on purpose** and will not be published to pub.dev.
It exists as a separate package only because Flutter GPU (and therefore
flutter_scene) has not shipped on the Flutter **stable** channel — a hard
dependency would break `pub get` on stable and collapse vrlizate's pub.dev
score. Once Flutter GPU reaches stable, `vrlizate_scene` is expected to be
integrated directly into the `vrlizate` package (e.g.
`package:vrlizate/gpu.dart`), giving its software 3D engine a hardware GPU
backend — real-time PBR, glTF, shadows and post-processing — while keeping
the pure-Dart renderer as fallback.

The same is expected of **[Fluorite](https://fluorite.game)**, Toyota
Connected's open-source, console-grade 3D game and UI engine for Dart &
Flutter (unveiled February 2026): when it is released as a package, it is
expected to contribute substantially to vrlizate as another high-end
rendering/engine option for VR experiences.

## License

Apache 2.0 — see [LICENSE](LICENSE).
