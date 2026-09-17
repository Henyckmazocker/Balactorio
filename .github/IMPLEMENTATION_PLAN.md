# Plan de implementación — Balactorio

## Estado actual del prototipo

| Sistema | Estado |
|---|---|
| Tilemap isométrico con hover | ✅ |
| Factories con tick via Timer | ✅ |
| Definición de factories en JSON | ✅ |
| Bag dinámica multi-recurso | ✅ |
| Colocar factory con click | ✅ |
| Animación de producción (rebote) | ✅ |
| Selección de factory desde inventario UI | ✅ |
| Factories procesadoras (consume inputs) | ✅ |
| Reset rápido con R | ✅ |
| HUD de recursos en tiempo real | ✅ |
| Sistema de adyacencia y sinergias | ✅ |
| Workers como recurso abstracto | ✅ |
| Menú radial de construcción | ✅ |
| Tooltips en factories colocadas | ✅ |
| Animación de recursos (+N texto) | ✅ |
| Menú principal | ✅ |

---

## ~~Fase 1 — Loop jugable mínimo~~ ✅ COMPLETADA

### 1.1 — Selección de factory funcional
**Prioridad: urgente** (bloquea todo lo demás de UX)
- Conectar clicks en el inventario UI → actualizar `player.selectedFactory`
- Actualmente `Main.gd` ignora `selectedFactory` y usa `availableFactories[0]`
- Archivos: `inventory.gd`, `Main.gd`, `player.gd`

### 1.2 — Bag dinámica multi-recurso
**Prioridad: urgente** (el sistema de factories procesadoras no puede funcionar sin esto)
- La Bag actual tiene `wood` hardcodeado. Hay que hacerla dinámica: que se auto-registren los recursos cuando una factory los produce por primera vez, o inicializarla leyendo todos los `material` del JSON
- `Bag.gd` necesita que `addToBag()` cree la entrada si no existe, y que `checkNeeds()` en `factoryData.gd` no rompa si el recurso no está en la Bag
- Archivos: `Bag.gd`, `factoryData.gd`

### 1.3 — HUD: objetivo de run visible
- Nodo en pantalla que muestre "Producir X de Y material"
- Progreso en tiempo real (conectado a la Bag)
- El objetivo inicial puede ser hardcodeado en JSON o en `Main.gd`
- Archivos: nuevo `hud.gd / hud.tscn`, `Main.gd`

### 1.4 — Condición de victoria y derrota
- **Victoria**: comparar cantidad producida de cada recurso objetivo contra el threshold del checkpoint
- **Derrota**: quedarse sin recursos para colocar factories (o bien no cumplir el checkpoint — por decidir, ver GDD/Mecánicas)
- Disparar pantalla de resumen al cumplirse
- Archivos: nuevo `gameManager.gd`, `Main.gd`

### 1.5 — Reset rápido de run
- Función que destruye todas las factories instanciadas, resetea la Bag y el estado del jugador
- Debe ser invocable desde el teclado (tecla R o ESC → confirmación)
- Archivos: `Main.gd`, `gameManager.gd`

---

## ~~Fase 2 — Checkpoints y mejoras~~ ✅ COMPLETADA

### 2.1 — Sistema de checkpoints
- Un Timer global de run dispara evaluación periódica
- Condición: `bag[recurso_objetivo].quantity >= cantidad_requerida`
- Al superar: pausa la run, lanza pantalla de selección de mejora
- Al fallar: game over (o penalización, según decisión de diseño)
- Archivos: `gameManager.gd`

### 2.2 — Pantalla de selección de mejora (estilo Balatro)
- Muestra 2-3 cartas con nombre + icono + descripción
- Cada carta es una mejora: nueva factory, boost de velocidad, más workers, etc.
- Animación de entrada
- Al seleccionar, aplica la mejora y reanuda la run
- Archivos: nuevo `upgradeScreen.gd / upgradeScreen.tscn`, nuevas entradas en JSON para mejoras

### 2.3 — Sistema de mejoras aplicables
- Catálogo de mejoras en JSON o GDScript (tipos: `add_factory`, `speed_boost`, `add_workers`, `rule_modifier`)
- `apply(target)` en cada mejora que modifica el estado de juego
- Algunas mejoras tienen **downside de mapa** (casillas bloqueadas, zona contaminada)

### 2.4 — Pantalla de resumen de run
- Stats finales: tiempo, factories usadas, checkpoints superados, contaminación generada
- Botón de volver a jugar (reset) y volver al menú
- Archivos: nuevo `runSummary.gd / runSummary.tscn`

---

## ~~Fase 3 — Sistema de contaminación~~ ✅ COMPLETADA

### 3.1 — Contaminación por factory
- Añadir campo `pollution` a cada factory en `factoryParams.json`
- Cada tick de producción suma al contador global de contaminación
- Archivos: `factoryParams.json`, `factoryData.gd`, nuevo `pollutionManager.gd`

### 3.2 — Visualización de contaminación en el tilemap
- Las casillas acumulan contaminación y cambian de color/sprite según el nivel
- El shader `tile_map.gdshader` es el lugar natural para esto (tint por nivel de contaminación)
- Archivos: `tileMap.gd`, `tile_map.gdshader`, `pollutionManager.gd`

### 3.3 — Edificios de restauración
- Nuevo tipo de factory en JSON: `"type": "restoration"`, con `pollution_removed` en lugar de `material`
- Usan el mismo sistema de tick que las factories productoras
- El jugador debe asignar casillas a restauración en vez de producción (trade-off central del juego)
- Archivos: `factoryParams.json`, `factoryData.gd` (o nuevo `restorationData.gd`)

### 3.4 — Contaminación modifica el mapa funcionalmente
- Casillas con alta contaminación: no se puede construir en ellas, o reducen el tick de factories adyacentes
- Lógica en `tileMap.gd` para consultar el nivel de contaminación por celda
- Archivos: `tileMap.gd`, `pollutionManager.gd`

### 3.5 — Condición de victoria actualizada (objetivo doble)
- La run termina cuando: producción cumplida **Y** contaminación ≤ umbral de restauración
- El `gameManager.gd` evalúa ambas condiciones simultáneamente
- Archivos: `gameManager.gd`

---

## Fase 4 — Sinergias y workers
> Objetivo: añadir profundidad al placement y la gestión de recursos.

### 4.1 — Sistema de adyacencia
- Al colocar una factory, evaluar las 4-8 celdas vecinas en el tilemap
- Si hay factories compatibles (definido en JSON con campo `synergies`), aplicar bonificador: multiplicador de tick, multiplicador de output, reducción de contaminación
- Archivos: `Main.gd`, `factoryData.gd`, `factoryParams.json`

### 4.2 — Workers como recurso abstracto
- Añadir `workers` a la Bag global como recurso numérico
- Las factories tienen un campo opcional `workers_needed` en JSON
- Asignar workers a una factory la activa o la acelera
- UI para asignar/desasignar workers (desde tooltip de factory colocada)
- Archivos: `Bag.gd`, `factoryData.gd`, `factoryParams.json`

---

## Fase 5 — UX completa

### 5.1 — Menú radial de construcción
- Al hacer click en casilla libre → aparece menú radial con las factories disponibles
- Hover sobre cada opción → tooltip (nombre, recurso producido, inputs, tick, contaminación)
- Reemplaza el sistema actual de inventario lateral para colocar factories
- Archivos: nuevo `radialMenu.gd / radialMenu.tscn`, refactor de `Main.gd`

### 5.2 — Tooltips en factories colocadas
- Click/hover sobre factory colocada → tooltip con estado de producción, stock, workers asignados
- Si la factory tiene múltiples outputs posibles: selector inline
- Archivos: nuevo `factoryTooltip.gd / factoryTooltip.tscn`

### 5.3 — Animación de recursos (gamefeel)
- Al producir, el recurso se anima moviéndose desde la factory hacia el contador del HUD
- Implementable como un `Tween` sobre un Label/Sprite instanciado temporalmente
- Archivos: `factoryData.gd`, nuevo `resourceFX.gd`

### 5.4 — Menú principal
- Pantalla de inicio: Jugar, Continuar (si hay run en pausa), Ajustes
- Archivos: nuevo `mainMenu.gd / mainMenu.tscn`

---

## Fase 6 — Meta-progresión roguelike

### 6.1 — Paquetes de inicio
- Definir paquetes en JSON: qué factories iniciales tiene el jugador, qué mejoras empiezan disponibles
- Pantalla de selección de paquete al iniciar run
- Archivos: nuevo campo en `factoryParams.json` o archivo `startingPackages.json`

### 6.2 — Sistema de desbloqueo entre runs
- Guardar en `user://save.json` qué paquetes/mejoras/eventos están desbloqueados
- Al completar una run, desbloquear nuevas opciones (no poder, solo variedad)
- Archivos: nuevo `saveManager.gd`

### 6.3 — Generación/carga de mapas por run
- Cada run carga un mapa distinto (o genera uno proceduralmente)
- Los mapas pueden tener modificadores ambientales (ver GDD/Mundo y Niveles): zonas bloqueadas, escasez, bonificadores zonales
- Archivos: `tileMap.gd`, nuevo `mapLoader.gd`

---

## ~~Fase 7 — Refactor técnico~~ ✅ COMPLETADA

### 7.1 — Separar lógica de juego de UI en `Main.gd`
- `Main.gd` actualmente mezcla: input handling, instanciación de factories, acceso al tilemap, carga del JSON
- Extraer a: `gameManager.gd` (estado de juego), `inputHandler.gd` (o mantener en Main solo el routing de input)

### 7.2 — Meta-fábrica
- Factory especial que crea nuevas factories o workers a alto coste
- Dilema de diseño: invertir en meta-fábrica vs. cumplir checkpoint rápido para mejores recompensas
- Implementar como factory procesadora con output de tipo `factory_token` o `worker`

---

## Orden de implementación recomendado

```
1.1 → 1.2 → 1.3 → 1.4 → 1.5   (loop jugable mínimo)
      ↓
2.1 → 2.2 → 2.3 → 2.4           (tensión y progresión)
      ↓
3.1 → 3.2 → 3.3 → 3.4 → 3.5    (segundo pilar: restauración)
      ↓
4.1 → 4.2                        (profundidad de placement)
      ↓
5.1 → 5.2 → 5.3 → 5.4           (UX completa)
      ↓
6.1 → 6.2 → 6.3                  (meta-progresión)
      ↓
7.1 → 7.2                        (refactor y meta-fábrica)
```
