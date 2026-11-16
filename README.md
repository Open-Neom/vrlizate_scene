# vrlizate_scene

Adaptador estereoscópico sobre [flutter_scene](https://pub.dev/packages/flutter_scene) (Flutter GPU) para el motor [vrlizate](../vrlizate/README.md).

> Versión actual: **1.0.0**. Consulta [CHANGELOG.md](CHANGELOG.md) para el historial de cambios.

## Características principales

- **`StereoSceneView`:** vista estereoscópica con proyección asimétrica off-axis (`convergenceDistance` por defecto a 1.8 m), ajuste de IPD e `inset` óptico, seguimiento de cabeza 3DoF, selección por mirada/láser y botón `HOME` anclado al mundo (`VrWorldNavigationScope`).
- **Iluminación y transiciones de escena (`VrLightingPreset`, `VrSceneTransitionController`):** presets de iluminación (`daylight`, `neonArcade`, `warmGallery`, `deepSpace`, `sunset`) y estilos de transición (`instant`, `smoothFade`, `portalIris`, `zoomSlide`) con control de opacidad, apertura de iris y deformación de FOV al entrar o salir de portales y apps.
- **Calidad adaptativa y catálogo por dispositivo:** presets `low` (0.60×), `medium` (1.00×), `high` (1.00× MSAA) y `ultra` (1.15× MSAA + bloom), escalado dinámico por `FrameTiming` y perfil inicial opcional vía `VrDevicePerformanceCatalog` / `VrDevicePerformanceScope`.
- **Foveación fija opcional (`VrFixedFoveation`):** combina una vista periférica de menor resolución y un recorte central nítido por ojo, a la misma frecuencia. Son cuatro vistas en un `SceneView`; con escalas 0.6/0.6 producen ~72% de píxeles nominales de color, pero pueden aumentar trabajo de CPU, sombras y memoria. Debe medirse por escena/dispositivo antes de activarse; no garantiza mayor FPS.
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

## Recursos compartidos entre experiencias

El [diseño de control térmico y recuperación de calidad](docs/adaptive_thermal_quality.md)
distingue la adaptación por tiempos de render ya activa de la integración
térmica pendiente. Define una política común, frescura de lecturas y el techo
de calidad del usuario, sin cambiar el formato `.vrlw`.

- Usa `PbrTextureLibrary` para cargar y reutilizar mapas PBR y
  `VrSceneMaterialCache` para resolver mapas de un material importado.
- Usa `VrSceneMeshBatch` para instanciar una geometría con un solo material.
  La experiencia decide qué instancias están activas y cuándo liberar el lote.
- Configura sombras direccionales con `VrDirectionalShadowSettings`. Para una
  huella suave sobre una superficie horizontal, usa `VrContactShadowSpec`.
- Evalúa `VrDistanceBand` desde el centro de la vista y conserva el nivel previo
  para aplicar el margen de transición. Cada experiencia define sus umbrales
  y cuándo debe actualizar las instancias.

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

## Capacidades experimentales y límites de alcance

Los siguientes componentes se incluyen como ayudas heurísticas o adaptadores experimentales y **no** equivalen a sistemas certificados de seguridad física ni a drivers nativos completos:

- **`VrPhysicalGuardianService` (experimental):** evalúa detecciones espaciales con confianza `>= minObstacleConfidence` (`0.30`) y aplica un piso temporal separado (`guardianPassthroughFloorMix`) sin sobrescribir la mezcla manual del usuario (`controllerPassthroughMix`). Respeta `VrPassthroughMode.off` por defecto salvo que el host habilite explícitamente `allowGuardianPassthroughWhenOff` o `allowOverrideOffMode`. No sustituye un sistema físico certificado de delimitación de sala.
- **`VrMultiCameraSpaceMapper` y `VrSyntheticLidarScanner` (experimentales):** proyectan contornos y fusionan ecos acústicos, RTT/RSSI y heurísticas ópticas bajo presupuestos acotados (`maxTrackedObjects`, `maxFreeContours`, `maxVoxels`, `maxReconstructedObjects`, `voxelTtlMicros`). Las hipótesis de atenuación RF y proyecciones sin extrínsecos calibrados son estimaciones heurísticas (`isHeuristicEstimate == true`), no mediciones de un escáner LiDAR físico.
- **`VrOpenXrNativeBridge` (experimental):** define el contrato de ciclo de vida y superficies externas en Dart sin biblioteca FFI OpenXR nativa certificada para visores dedicados.

## Verificación

```sh
flutter pub get
flutter analyze
flutter test
```

## Licencia

Apache License 2.0 — consulta [LICENSE](LICENSE).
