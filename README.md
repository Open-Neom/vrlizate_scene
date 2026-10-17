# vrlizate_scene

Adaptador estereoscópico sobre [flutter_scene](https://pub.dev/packages/flutter_scene) (Flutter GPU) para el motor [vrlizate](../vrlizate/README.md).

> Versión actual: **1.0.0**. Consulta [CHANGELOG.md](CHANGELOG.md) para el historial de cambios.

## Características principales

- **`StereoSceneView`:** vista estereoscópica con proyección asimétrica off-axis (`convergenceDistance` por defecto a 1.8 m), ajuste de IPD e `inset` óptico, seguimiento de cabeza 3DoF, selección por mirada/láser y botón `HOME` anclado al mundo (`VrWorldNavigationScope`).
- **Iluminación y transiciones de escena (`VrLightingPreset`, `VrSceneTransitionController`):** presets de iluminación (`daylight`, `neonArcade`, `warmGallery`, `deepSpace`, `sunset`) y estilos de transición (`instant`, `smoothFade`, `portalIris`, `zoomSlide`) con control de opacidad, apertura de iris y deformación de FOV al entrar o salir de portales y apps.
- **Calidad adaptativa y catálogo por dispositivo:** presets `low` (0.60×), `medium` (1.00×), `high` (1.00× MSAA) y `ultra` (1.15× MSAA + bloom), escalado dinámico por `FrameTiming` y perfil inicial opcional vía `VrDevicePerformanceCatalog` / `VrDevicePerformanceScope`.
- **Foveación fija opcional (`VrFixedFoveation`):** renderiza fondo periférico de menor resolución y centro nítido alineado por proyección en una sola pasada de `SceneView` (~72% de píxeles nominales).
- **Regiones visuales (`VrSceneRegion`):** histéresis de distancia para alternar entre detalle cercano, proxy lejano y subárbol desmontado.
- **Avatares procedurales (`VrAvatarNode`):** especies `human`, `robot`, `orb`, `fox`, `axolotl` y `sprout` con geometría GPU compartida, `InstancedMesh` y niveles de detalle cercano/lejano.
- **Actores GLB y caché de plantillas:** mezcla semántica de clips (`idle`, `walk`, `wave`) mediante `VrActorAnimation` y reutilización LRU de assets con `VrGlbTemplateCache`.
- **Adaptador retenido (`VrRetainedSceneAdapter`):** traduce el grafo de escena de `vrlizate` a nodos y materiales GPU retenidos.

## Instalación

Requiere Dart `^3.10.0`, Flutter `>=3.47.0` y un backend compatible con Flutter GPU / Impeller.

```yaml
dependencies:
  vrlizate_scene: ^1.0.0
```

## Uso básico

```dart
import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vrlizate_scene/vrlizate_scene.dart';

Widget buildDemo(Scene scene, VoidCallback onHome) {
  return VrWorldNavigationScope(
    onHome: onHome,
    child: StereoSceneView(
      scene: scene,
      quality: VrQualityPreset.medium,
      enableHandTracking: false,
      gazeDwellSeconds: 1.2,
      onGazeSelect: (node) {
        // Manejar selección sobre nodos con nombre y raycastable = true.
      },
    ),
  );
}
```

## Avatar procedural y actores GLB

```dart
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
```

Para modelos GLB reutilizables, instancia clones desde `VrGlbTemplateCache` y adjunta `VrActorAnimation` a cada instancia clonada (nunca a la plantilla compartida).

## Verificación

```sh
flutter pub get
flutter analyze
flutter test
```

## Licencia

Apache License 2.0 — consulta [LICENSE](LICENSE).
