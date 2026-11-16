# Calidad adaptativa y control térmico

El 13 de noviembre de 2026, OpenWorld conectó el monitor térmico al renderizador en Android. Las pruebas del monitor usan señales inyectadas. La medición física de estabilidad y FPS sigue pendiente.

## Implementación actual

`StereoSceneView` utiliza `VrFrameQualityPolicy` y `VrFrameQualityMonitor`. Compara por separado los tiempos Flutter de build y raster con el presupuesto del refresco elegido. Tras calentamiento inicial y presión sostenida puede bajar un nivel de calidad. Pausa la observación cuando la escena deja de estar visible o la app se suspende. Limita cada lote de mediciones a una transición. [Política y monitor](../lib/src/vr_frame_quality.dart), [integración de escena](../lib/src/stereo_scene_view.dart).

OpenWorld entrega a `StereoSceneView.readThermalStatus` el lector Android de la app. El monitor consulta cada 10 segundos mientras la escena está activa. Un estado de severidad 3 o superior solicita bajar un nivel. Para recuperar, exige al menos 30 segundos de lecturas nominales consecutivas y una ventana reciente con tiempos de build y raster inferiores al 70 % de su presupuesto. Recupera un nivel cada vez hasta el perfil solicitado, incluidos sus ajustes personalizados. Cambiar de escena, presupuesto o estado de actividad reinicia esa evidencia.

Cuando falta un proveedor, la disminución por presión de cuadros sigue disponible. `dynamicScaling: false` fija la calidad para las comparaciones. `targetRefreshRateHz` define el presupuesto de tiempo del monitor.

`VrThermalGovernor` está exportado como API separada, pero infiere rendimiento desde deltas de tiempo y no mide temperatura. No está conectado al renderer principal. Sus umbrales por defecto están orientados a 60 FPS y no deben reutilizarse sin revisión para 90/120 Hz. Tampoco conviene activarlo junto al monitor existente sobre los mismos recursos. [Governor previo](../lib/src/vr_thermal_governor.dart).

`VrUniversalEcosystemScaler`, en el módulo base `vrlizate`, ofrece adaptación matemática de presupuestos. No aporta por sí mismo frescura térmica, continuidad de muestras o coordinación entre controladores.

## Contrato de calidad y evolución del proveedor

El monitor concentra la suscripción a tiempos de Flutter y decide cuándo mantener, reducir o recuperar la calidad. La escena conserva tres estados.

- **Calidad solicitada y techo**: elección del usuario o presupuesto inicial del dispositivo, conservando también presets personalizados.
- **Calidad efectiva**: parámetros aplicados ahora a ambos ojos.
- **Historial de decisión**: presión, calentamiento, estabilidad, última transición y edad de las señales.

Una reducción adaptativa no sobrescribe la preferencia guardada. La recuperación nunca supera el techo solicitado. Al alcanzar un preset personalizado debe restaurarse su objeto completo, no sustituirlo por la constante de su categoría.

### Snapshot del proveedor

El DTO propuesto, aún pendiente de implementación, debe incluir campos opcionales y semántica explícita:

| Campo | Significado |
| --- | --- |
| `severity` y `nativeSeverity` | Severidad normalizada y valor nativo, con plataforma y esquema de conversión. |
| `thermalHeadroom` | Fracción térmica reportada por Android cuando esté disponible; no son grados ni porcentaje de CPU. |
| `batteryTemperatureC` | Temperatura de batería cuando el proveedor público la exponga. |
| `batteryLevel`, `charging`, `powerSaveMode` | Contexto energético opcional, separado de presión térmica. |
| `source`, `availableFields` | Procedencia y capacidades efectivas, incluyendo proveedor ausente. |
| `sampledAt` y `validFor` | Instante monotónico local y TTL para evaluar frescura. |

La lectura ausente o vencida no equivale a un dispositivo frío. Si una fuente antes caliente deja de actualizarse, su silencio no autoriza recuperar calidad. El proveedor debe representar `NaN`, errores y señales desconocidas sin inventar ceros. No guardar muestras térmicas como estado válido entre sesiones.

Los relojes monotónicos de teléfonos distintos no son directamente comparables. Si se transporta telemetría, conservar su origen y calcular edad de recepción en el consumidor; no mezclar la temperatura del mando con la del visor.

### Descenso y recuperación sin oscilaciones

Mantener el descenso actual ante presión sostenida y permitir una limitación conservadora ante severidad térmica elevada, aunque los cuadros sigan siendo rápidos. El sistema operativo sigue controlando frecuencias, protección térmica y apagado.

Como ensayo inicial, exigir 30–60 segundos continuos de señales frescas favorables y margen de render antes de recuperar un único escalón. Reiniciar esa continuidad cuando aparezca presión, una banda neutral, muestras vencidas, suspensión o un cambio de escena. Estas duraciones son parámetros de prueba, no límites del fabricante.

Después de una transición deben medirse cuadros nuevos de esa calidad. Si una subida provoca presión, bajar y aumentar el tiempo hasta el próximo intento. Evitar cambios dobles por lote, temporizadores que acumulen recuperación en segundo plano y asignaciones por cuadro. Usar un reloj inyectable en las pruebas.

Los tiempos de build/raster son señales de sus respectivas etapas, no FPS de pantalla ni tiempo de GPU completo. La recuperación es una prueba conservadora con posibilidad de volver al nivel anterior.

## Prioridades visuales y de recursos

Reducir primero trabajo opcional cuyo beneficio haya sido medido: resolución/frecuencia de sombras, efectos, partículas y detalle distante. Preservar inicialmente resolución central, lectura de texto, seguimiento de cabeza y respuesta del mando. `onQualityChanged` permite que las experiencias apliquen el presupuesto común a sus recursos.

El paso high→medium conserva la escala de píxeles en los presets actuales y reduce el presupuesto de sombras de 2048 a 1024. La aplicación efectiva del presupuesto de sombras depende de que el consumidor lo respete; no basta cambiar el valor del preset. [Presets](../lib/src/quality_preset.dart).

La resolución periférica reducida debe seguir siendo opt-in hasta validarla por escena y dispositivo. En Bosque Vivo, un ensayo S25 estéreo con la misma APK, calidad high fija, calentamiento de 60 s y ventanas de 35 s dio 108.61 FPS sin foveación, 88.30 con foveación y 109.60 al desactivarla. Las tres ventanas comenzaron con batería a 34.4 °C y dentro de las bandas térmicas declaradas. Es evidencia de regresión para esa configuración, no una conclusión sobre toda técnica foveada.

Añadir desenfoque después de renderizar la imagen completa no evita calcularla. La técnica periférica sólo debe activarse si el ahorro de píxeles supera el costo de vistas, composición, geometría y sombras adicionales. Ambos ojos deben compartir la decisión de calidad y mantener su proyección correcta.

Cambiar el objetivo real de 120 a 90/60 FPS exige un mecanismo separado de pacing/modo de pantalla soportado y su validación. El controlador propuesto no debe confundir un presupuesto de monitor con un límite efectivo de presentación.

## Proveedores públicos de plataforma

Android ofrece severidad y listeners desde API 29, y `getThermalHeadroom` desde API 30. El valor 1.0 representa el umbral de throttling severo y puede superarse. Una consulta compartida cada 10 segundos es un punto de partida conservador compatible con la guía de juegos; no hacer una consulta por escena, ojo o cuadro. Tratar ausencia de soporte y `NaN` como datos no disponibles. [PowerManager](https://developer.android.com/reference/android/os/PowerManager), [Thermal API](https://developer.android.com/games/optimize/adpf/thermal).

La temperatura de batería puede obtenerse mediante `BatteryManager.EXTRA_TEMPERATURE` en `ACTION_BATTERY_CHANGED`. No etiquetarla como temperatura de CPU. El estado de carga y ahorro aporta contexto, pero estar conectado al cargador no elimina calor. [BatteryManager](https://developer.android.com/reference/android/os/BatteryManager).

Las temperaturas CPU/GPU/piel de `HardwarePropertiesManager` están restringidas al propietario del dispositivo o servicio VR autorizado. Una aplicación que dibuja escenas VR no obtiene automáticamente ese privilegio. Las lecturas `dumpsys` del laboratorio ADB no constituyen un proveedor distribuible. Dejar esos campos ausentes cuando no exista una fuente autorizada. [HardwarePropertiesManager](https://developer.android.com/reference/android/os/HardwarePropertiesManager).

iOS ofrece `ProcessInfo.thermalState` y su notificación de cambio. Debe leerse la propiedad antes de registrar la notificación. El host puede aportar también nivel de batería y Low Power Mode; esta propuesta no utiliza APIs privadas de temperatura CPU/batería. Los estados nominal/fair/serious/critical requieren una conversión explícita, no igualdad ordinal con Android. [thermalState](https://developer.apple.com/documentation/foundation/processinfo/thermalstate-swift.property), [notificación](https://developer.apple.com/documentation/foundation/processinfo/thermalstatedidchangenotification), [batería](https://developer.apple.com/documentation/uikit/uidevice/batterylevel), [Low Power Mode](https://developer.apple.com/documentation/foundation/processinfo/islowpowermodeenabled).

## Frontera del SDK y distribución

Actualmente la app VRlizate privada registra `VrDeviceCapabilitiesPlugin` y el canal `vrlizate/device_capabilities` en Android. El lector Dart `VrDeviceProfiler` pertenece a `vrlizate_tracking` y refresca snapshots Android. Su campo `thermalStatus` no incluye TTL y puede conservar una lectura anterior si falta una nueva; no debe tratarse como señal fresca indefinidamente.

`vrlizate_tracking` depende de `vrlizate_scene` y no declara un plugin nativo auto-registrable. `vrlizate_scene` no debe importar tracking, porque produciría un ciclo. El reproductor mínimo del SDK tampoco registra actualmente ese puente privado. Descargar los paquetes no garantiza que existan sensores térmicos accesibles.

La primera integración entrega severidad fresca mediante `VrDeviceProfiler.readThermalStatus`. El lector usa el canal del host y devuelve `null` cuando falta la lectura. El monitor comprueba la edad y descarta resultados de generaciones anteriores. El DTO con batería y demás señales sigue pendiente.

Para instalación automática en aplicaciones independientes, distribuir el puente como plugin nativo real en una capa inferior sin dependencia de scene/tracking, con registro Android/iOS y limpieza de listeners. Declarar `platforms` en pubspec o exportar un archivo Kotlin no reemplaza la configuración de plugin. La política gráfica continúa compartida, aunque cambie la implementación del proveedor.

## Fases pendientes y criterio de aceptación

1. Ampliar el proveedor con batería, contexto energético y adaptación en iOS.
2. Distribuir el proveedor con el reproductor mínimo mediante un plugin nativo registrable.
3. Aplicar presupuestos mediante el punto común y callbacks existentes, comprobando qué recursos cambian realmente en Riviera, Bosque Vivo y mundos `.vrlw`.
4. Probar política con reloj simulado: descenso sostenido, recuperación gradual, techo personalizado, pausa, huecos, datos vencidos, `NaN`, señal caliente con frames rápidos y ausencia de oscilación. Conservar las regresiones actuales de 60/90/120 Hz, cuadros largos, rutas y un cambio por lote. [Pruebas existentes](../test/vr_frame_quality_test.dart).
5. Validar separadamente la máquina de estados con señales inyectadas y la lectura física de los proveedores. Una prueba sintética no acredita temperatura real.
6. Ejecutar sesiones sostenidas con adaptación apagada/encendida/apagada, conservando todas las pasadas. Medir presentaciones reales, térmica, cambios de calidad, memoria y capturas de ambos ojos. Reportar estabilidad, pérdida visual y recuperación como resultados separados.

Los umbrales térmicos usados para emparejar temperaturas en un benchmark no son límites de seguridad del dispositivo y no deben copiarse como política de producto. Ninguna de estas fases necesita cambiar el formato `.vrlw`.
