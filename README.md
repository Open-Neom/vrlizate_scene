# vrlizate_scene

Stereoscopic [flutter_scene](https://pub.dev/packages/flutter_scene) adapter for
the [vrlizate](https://pub.dev/packages/vrlizate) input and VR engine.
The core remains renderer-independent; this optional package adds GPU-rendered
PBR scenes, head orientation, gaze selection and world-space navigation.

## Development 0.5.0 / Desarrollo sin publicar

Requires core 1.12.0, which must be published before this release can resolve
from pub.dev. The workspace uses sibling overrides for development.

Both engines now share normalized frame-based input. `select` is a semantic
action; listeners must check `event.handled` and call `event.consume()` when
handling it. HOME/recenter precede gameplay. `onInteractionRay` provides a
borrowed current ray for drag/manipulation; copy it if retained.

OpenXR and quad layers remain **experimental scaffolding**, not an implemented
native compositor. Mock operation requires explicit opt-in. They do not prove
zero-copy presentation, 0 ms UI cost or a device frame rate. Await loop disposal.

ES: selección única, rayo actual y locomoción por tiempo; HOME tiene prioridad.
Estas versiones están preparadas localmente, no publicadas. OpenXR sigue siendo
experimental y requiere integración nativa y validación física.

## Requirements and installation

`VrRetainedSceneAdapter` converts a core scene graph into retained GPU nodes,
geometry and materials. Call `sync()` after simulation updates and dispose the
adapter with its owner. It does not rasterize the entire world into a texture.
Unsupported custom renderables fail explicitly; hologram glitch/scanline effects
are approximated with diagnostics. `VrRetainedResourceFactory.headless()` is a
deliberate CPU-test seam, not a production rendering fallback.

`VrViewerProfileScope` distributes validated IPD, image inset, FOV and convergence
settings across `StereoSceneView` instances without changing head/world poses.
The host persists profiles through `toJson`/`fromJson`. Physical lens calibration
is still required; these settings do not implement a calibrated lens warp.

ES: el adaptador conserva la simulación y convierte su geometría a GPU; no
convierte el mundo en un bitmap. El perfil óptico se comparte entre escenas,
pero no garantiza fusión binocular ni una tasa de frames concreta.

`StereoSceneView` waits for confirmed shader readiness before starting its
renderer, input or tracking. `VrGpuResourceGate` can also wrap a lazy demo factory
before GPU-dependent constructors. Failed initialization offers explicit retry
and Back where navigation is available, not an automatic retry loop. The error
screen is intentionally ordinary Flutter UI: remove the headset to recover
when GPU rendering itself is unavailable.

- Dart `^3.10.0`, Flutter `>=3.44.0`, and a runtime/backend supported by
  `flutter_scene` and Flutter GPU. The SDK constraint alone does not guarantee
  GPU support on a device.
- Follow the installed [flutter_scene setup instructions](https://pub.dev/packages/flutter_scene)
  for backend and shader/data-asset configuration.
- This release was tested locally using Flutter
  `3.48.0-1.0.pre-371` / Dart `3.14.0-147.0.dev`. This records the tested
  environment; it is not a claim that every listed platform has been validated.
- The release depends on hosted `vrlizate ^1.12.0` and
  `vrlizate_widgets ^0.3.0`. Those versions must be available before publishing
  or resolving this package from pub.dev.

```sh
flutter pub add vrlizate_scene
```

## A scene with a world-space HOME control

```dart
import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vrlizate_scene/vrlizate_scene.dart';

Widget buildDemo(Scene scene, VoidCallback onHome) {
  // Keep the Scene alive in the owning State; do not recreate it on each build.
  return VrWorldNavigationScope(
    onHome: onHome,
    child: StereoSceneView(
      scene: scene,
      quality: VrQualityPreset.low,
      enableHandTracking: false,
      gazeDwellSeconds: 1.2,
      onGazeSelect: (node) {
        // Handle an application control identified by node.name.
      },
    ),
  );
}
```

`VrWorldNavigationScope` supplies a navigation callback to nested
`StereoSceneView` widgets. The view places one 3D HOME button near the initial
view direction. Its position remains fixed in world coordinates; head motion
does not drag it around the screen. The host owns navigation and decides
whether HOME pops a route or opens its home scene.

`VrWorldPose`, `VrWorldAction` and `VrWorldActionPanel3D` are re-exported from
`vrlizate_widgets` for world-space confirmation panels. Create their pose once
when opening a panel, add/remove their nodes with the panel lifecycle, and route
gaze or controller selection to the panel. Use `StereoSceneView.gazeFilter`
while a modal is open so background content cannot take its focus. These are
scene objects; a Flutter `showDialog` overlay is not made world-space by this
package.

## Stereo optics and input

- Both eye cameras remain parallel. An asymmetric, off-axis projection sets
  the zero-parallax plane at `convergenceDistance` (default 1.8 m), avoiding
  toe-in vertical disparity. Null, non-positive or non-finite distances disable
  the convergence shift.
- `stereoImageInset` independently shifts the eye images and reticles inward.
  IPD controls the stereo baseline; it is not a replacement for physical lens
  alignment. Viewing comfort still requires appropriate headset calibration.
- `StereoHeadRig.screenRight` matches the renderer's horizontal screen axis;
  legacy `right` remains the underlying rig's local +X axis. The physical
  left/right baseline uses the screen axis so depth is not inverted.
- Per-eye gaze rays agree with the inset-adjusted reticles. Head tracking
  provides orientation with touch-drag fallback; this adapter does not supply
  measured 6DoF head position.
- Pass a `VrInputArbiter` to `arbiter` to suppress automatic dwell while a
  higher-priority control is active. Dwell restarts after hysteresis even when
  the gaze remains on the same target; hover and explicit taps remain available.
- Only named, raycastable nodes can become gaze targets. Mark decorative
  geometry `raycastable = false` to avoid blocking useful controls.
- The legacy `enableHandTracking` option renders **simulated decorative hands**.
  It does not start a camera or consume measured hand landmarks. Set it to
  `false` when those visuals are not needed. Their meshes do not intercept gaze.

## Quality and measured limits

| Preset | Resolution multiplier | Requested AA | Bloom |
|---|---:|---|---|
| low | 0.75× | none | off |
| medium | 0.90× | FXAA | off |
| high | 1.00× | MSAA | on |
| ultra | 1.15× | MSAA | on |

Resolution scales both dimensions relative to device pixels. Backend support
can change the effective AA technique. Automatic tier detection uses display
density/refresh heuristics, not a GPU benchmark.

With `dynamicScaling: true`, an animation-tick interval monitor steps down
after a warmup and sustained intervals above its 18 ms budget. Its 30-frame
warmup and 45-frame evaluation window take longer on slow devices. It does not
measure GPU completion, promise 60 FPS, or increase quality automatically.
Use `onQualityChanged` to observe the effective preset; avoid running competing
quality controllers. The separately exported `VrThermalGovernor` estimates
performance from frame intervals and does not read hardware temperature.

The stereo adapter currently returns a custom `CameraProjection`.
In the tested `flutter_scene 0.22.2`, directional shadows, SSAO and SSR are
gated on `PerspectiveProjection` and therefore do **not** run through this
adapter. Material PBR/IBL and supported color post-processing still apply.
Do not interpret raycasting for interaction as rendering ray tracing.
Exposed lens-distortion coefficients in `VrLook` are not yet applied.

A profile-mode run of the companion app on a Motorola edge 20 lite / OpenGL ES
showed a sustained raster-thread median around 120 ms in its populated Home.
That is not acceptable interactive VR performance and is not a benchmark of
every scene or device. Raster-thread duration is not GPU completion time.
Profile representative content on target phones before choosing a quality tier;
unit tests validate logic and geometry, not a frame-rate guarantee.

## Development

The repository's `pubspec_overrides.yaml` uses sibling checkouts of
`../vrlizate` and `../vrlizate_widgets` for coordinated development. It is
excluded from the published archive. Consumers resolve hosted dependencies.

```sh
flutter pub get
flutter test
flutter analyze
flutter pub publish --dry-run
```

Tests cover physical disparity signs, convergence, rotated panel corners,
reticle/ray consistency, world navigation, gaze suppression and simulated-hand
picking/allocation behavior. GPU runtime verification is a separate step; use
`flutter run --profile` in a host application.

## Español

Adaptador opcional para escenas VR estéreo: incluye proyección off-axis,
selección por mirada y controles HOME/modales anclados al mundo 3D. El padre
de la escena define la navegación; los controles conservan su posición al
mover la cabeza.

Las manos decorativas son simuladas, el seguimiento de cabeza es de orientación,
y la calidad adaptativa no garantiza 60 FPS. En el backend probado, sombras,
SSAO y SSR no se activan con la proyección del adaptador. Los coeficientes de
distorsión óptica expuestos todavía no se aplican. Prueba el rendimiento en
modo profile y calibra el visor físico antes de evaluar la experiencia.

Para contribuir, utiliza los módulos hermanos indicados en
`pubspec_overrides.yaml`, ejecuta `flutter test` y `flutter analyze`, y conserva
pruebas de las interacciones y de la proyección cuando cambies estos sistemas.

## License

Apache 2.0 — see [LICENSE](LICENSE).
