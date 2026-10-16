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

`StereoSceneView(fixedFoveation: const VrFixedFoveation(), ...)` opts into an
experimental spatial-resolution trial. Each eye has a lower-resolution full
view and a projection-matched sharp center, drawn in the same frame through
one `SceneView`. The default targets contain about 72% of the uniform color
pixels, but four views instead of two add geometry, shadows and composition
work. Benchmark before selecting it for a device; it does not request 120 Hz.
Use plain tonemapping/fog without viewport-local effects (vignette, lens warp,
bloom, AO, SSR, depth of field), which need a crop-aware compositor. The border
is a rectangular resolution transition; no blur or temporal reuse is applied.
Leave `fixedFoveation` null for the existing uniform stereo path. The app's
OpenWorld trial offers a toggle in Puerto Neom and Bosque for A/B comparison.

`VrDevicePerformanceCatalog.match(manufacturer: ..., model: ...)` resolves a
small, explicit phone catalog. Hosts can inject the result with
`VrDevicePerformanceScope(profile: profile, child: app)`. `StereoSceneView`
uses it only for initial quality when the scene has no explicit preset. The
existing frame-quality monitor still adapts after startup. Unknown models keep
the normal fallback; a rebuild does not reset an adapted scene.

The initial entries cover Motorola Edge 20 Lite (`low`) and explicit Samsung
Galaxy S25 Ultra SKU aliases (`medium`). A profile's `displayMaxHz` describes
the panel ceiling, not current refresh or achievable FPS. Detection is supplied
by the host; the SDK does not read unique device identifiers, force display
modes, or treat a benchmark from one experience as a guarantee for another.

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

- Dart `^3.10.0`, Flutter `>=3.47.0`, and a runtime/backend supported by
  `flutter_scene` and Flutter GPU. The SDK constraint alone does not guarantee
  GPU support on a device.
- Follow the installed [flutter_scene setup instructions](https://pub.dev/packages/flutter_scene)
  for backend and shader/data-asset configuration.
- Shipping Windows or Linux releases requires Flutter `>=3.47.1` and Flutter
  GPU enabled in the platform runner, as documented by `flutter_scene`.
- This release was tested locally using Flutter
  `3.48.0-1.0.pre-371` / Dart `3.14.0-147.0.dev`. This records the tested
  environment; it is not a claim that every listed platform has been validated.
- The release depends on hosted `vrlizate ^1.12.0`,
  `vrlizate_widgets ^0.3.0` and `vrlizate_avatar ^0.1.0`. Those versions must be
  available before publishing or resolving this package from pub.dev.

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

## Procedural avatars

`VrAvatarNode` renders a `VrAvatarAppearance` from `vrlizate_avatar` directly
through Scene. The available species are `human`, `robot`, `orb`, `fox`,
`axolotl` and `sprout`; each has a distinct silhouette. Appearance parameters
include opaque `bodyColorArgb` / `accentColorArgb`, `heightMeters` (1–2.2),
`headScale` (0.8–1.25), `featureScale` (0.6–1.4), and the `solid`, `spots` or
`stripes` pattern. Feature scale changes ears, gills, leaves, antenna or fins
according to species. The legacy `VrAvatarStyle` is not the species API.

```dart
import 'package:vrlizate_avatar/vrlizate_avatar.dart';
import 'package:vrlizate_scene/vrlizate_scene.dart';

final avatar = VrAvatarNode(
  appearance: VrAvatarAppearance(
    species: VrAvatarSpecies.axolotl,
    bodyColorArgb: 0xff8258c9,
    accentColorArgb: 0xff7ef0dd,
    heightMeters: 1.7,
    pattern: VrAvatarPattern.spots,
  ),
  detail: VrAvatarDetail.near,
  animateIdle: true,
);
// Attach avatar.root to an existing world/placement node owned by the host.
```

The local origin is at the feet, +Y points up and **+Z points forward**. These
are authored Scene primitives, so do not apply a glTF import coordinate flip.
The conservative full silhouette, including ears/leaves, fits the requested
height and a horizontal envelope of at most 2.8 m at any yaw. `plan.bounds`
and `plan.horizontalRadius` support placement; Scene 0.24.3 does not include
instanced components in `Node.combinedLocalBounds`, although their render items
have aggregate bounds for normal frustum culling.

The owner calls `updateAppearance(value)` on semantic edits, `tick(dt)` only
while active, and `dispose()` when finished. `setDetail(VrAvatarDetail.far)`
uses a coarser rounded mesh and omits small glints/pattern/frill details.
The renderer does not choose distances itself. Home selects near detail below
8 m, returns to far at 12 m, mounts the showcase below 18 m and detaches it at
22 m. These hysteresis thresholds avoid repeated switching at a boundary.

Geometry is shared across avatars: three unit shapes at two detail levels,
with at most six cached GPU meshes. Each avatar owns four PBR materials shared
by its pieces, grouped as `InstancedMesh` submissions by shape/material. Color
edits change material factors; height/proportion edits update instance matrices
without recreating geometry, materials, nodes or groups. Species, pattern or
LOD changes can rebuild the small instance groups using cached meshes.
`instanceCount`, `triangleCount` and `batchCount` expose authored budgets;
`batchCount` is not a measured GPU draw-call count in stereo/shadow passes.

Appearance, profile identity, persistence and authorization belong to the host.
The renderer installs no state manager, timers or per-frame notifications.
Its optional idle is a slight yaw sway, not skeletal walking, hand tracking or
network synchronization. This addition does not enable multiplayer or establish
a measured FPS improvement. The static `.vrlw` import profile is unchanged.

## Animated GLB actors and template reuse

`VrActorAnimation(actor: importedRoot)` blends real GLB clips through semantic
`idle`, `walk` and `wave` actions, mapped by default to `Idle`, `Walking`, `Wave`.
`play(VrActorAction.walk)` crossfades over 0.25 s; a completed wave returns to idle.
Use a separate parent node for world placement and scale so authored channels
do not overwrite it. The source must contain all three clips (names configurable).

Call `tick(dt)` once per scene tick **before** Scene's animation pre-pass; it only
updates blend weights. Scene advances clip time and applies the pose. Do not
advance the clips a second time or rebuild SINT state per bone/frame. `pause`,
`resume`, `seek` and `dispose` preserve or release the owned clips explicitly.
`onActionChanged` reports only semantic transitions. `HomeShowcase` demonstrates
a `SceneTickListener` with proximity suspension and proper disposal.

`VrGlbTemplateCache(maxEntries: 2)` provides bounded LRU reuse of bundled GLB
imports. `instantiate(assetPath, maxTextureSize: ...)` returns a distinct node
tree with independent skin bindings, morph weights and animation playback;
retained concurrent requests for the same path/texture-size pair share one
import. Register `VrActorAnimation` on each returned clone, never on a template.
Geometry, textures, parsed animation curves and materials remain shared and
must be treated as **immutable**. For individual material edits, replace the
clone's material slots with instance-owned materials first.

The constructor defaults to four entries; Home explicitly uses two, for its
robot and lounge assets. The limit counts retained templates, including pending
imports, not GPU bytes or live clones. `clear()` or `invalidate(...)` releases
cache references without invalidating existing instances; pending completion
does not reinsert an evicted entry. Home calls `HomeShowcase.clearAssetCache()`
on `didHaveMemoryPressure`. Resources still referenced by mounted or retained
clones remain alive, so clearing is not a promise of immediate GPU reclamation.
Other hosts should clear on memory pressure and `dispose()` a session-owned
cache when finished; dispose also prevents pending imports from returning a
new instance after the owner has gone away.

## Quality and measured limits

| Preset | Resolution multiplier | Requested AA | Bloom |
|---|---:|---|---|
| low | 0.60× | none | off |
| medium | 1.00× | auto | off |
| high | 1.00× | MSAA | off |
| ultra | 1.15× | MSAA | on |

Resolution scales both dimensions relative to device pixels. Backend support
can change the effective AA technique. The initial automatic tier is conservative
medium; display density and refresh rate do not measure GPU capability.

With `dynamicScaling: true`, Flutter `FrameTiming` samples compare build and
raster durations separately with `1 / targetRefreshRateHz`. The default target
uses the display refresh rate, falling back to 60 Hz when unavailable; an explicit
target allows intentional lower-cadence rendering without changing the OS mode.
After 30 warmup samples, two consecutive 45-sample windows with at least 20%
over-budget frames reduce quality one tier. Long frames are retained. Monitoring
pauses in the background or outside `TickerMode`; scene, quality, visibility and
target-rate changes reset evaluation. This does not measure GPU completion,
promise a frame rate, or increase quality automatically.
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

The repository's `pubspec_overrides.yaml` uses sibling checkouts, including
`../vrlizate`, `../vrlizate_widgets` and `../vrlizate_avatar`, for coordinated
development. It is excluded from the published archive. Consumers resolve
hosted dependencies.

```sh
flutter pub get
flutter test
flutter analyze
flutter pub publish --dry-run
```

Tests cover physical disparity signs, convergence, rotated panel corners,
reticle/ray consistency, world navigation, gaze suppression and simulated-hand
picking/allocation behavior. Avatar CPU tests check real Scene winding,
normals, bounds at extreme proportions, stable instance topology, LOD budgets
and template-clone isolation. GPU runtime verification is a separate step; use
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
