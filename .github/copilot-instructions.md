# Balactorio — Agent Instructions

Roguelike de construcción de fábricas en **Godot 4.7 / GDScript**. Objetivo doble por run: cumplir la producción requerida + restaurar el mapa contaminado. Sin progresión de poder permanente — solo desbloqueo de variedad entre runs.

> Estas instrucciones y el `CLAUDE.md` de la raíz describen lo mismo. Si divergen, **manda el código**.

## Documentación completa

Toda la documentación detallada del proyecto vive en la bóveda Obsidian fuera del workspace. Usa las rutas absolutas con herramientas de lectura cuando necesites contexto adicional:

| Doc | Ruta |
|-----|------|
| Concepto y visión | `/home/david/Documents/workspace/Brain/03 - Proyectos/Balactorio/GDD/Concepto.md` |
| Mecánicas de juego | `/home/david/Documents/workspace/Brain/03 - Proyectos/Balactorio/GDD/Mecánicas.md` |
| Mundo, mapas y casillas | `/home/david/Documents/workspace/Brain/03 - Proyectos/Balactorio/GDD/Mundo y Niveles.md` |
| Programación y arquitectura | `/home/david/Documents/workspace/Brain/03 - Proyectos/Balactorio/Programación.md` |
| Build y publicación | `/home/david/Documents/workspace/Brain/03 - Proyectos/Balactorio/Build y Publicación.md` |
| Arte y estética | `/home/david/Documents/workspace/Brain/03 - Proyectos/Balactorio/GDD/Arte y Estética.md` |
| UI/UX | `/home/david/Documents/workspace/Brain/03 - Proyectos/Balactorio/GDD/UI - UX.md` |

## Stack técnico

- **Motor**: Godot 4.7 (Forward Plus), resolución 1280x720, escena principal `res://Main.tscn`
- **Tests**: `godot-4 --headless --path . --script res://tests/run_tests.gd` (233 pruebas, exit 0/1)
- **Lenguaje**: GDScript (sin tipado estático por ahora)
- **Datos del juego**: `resources/factoryParams.json` — iterable sin recompilar

## Arquitectura

```
Main.gd / Main.tscn            # Kernel: instancia managers, enruta input, FX de recursos
managers/                      # Lógica de negocio; nodos hijos de Main, sin autoloads
  gameManager.gd               # Checkpoints, objetivo doble, victoria y punto muerto
  mapLoader.gd                 # Paquete de inicio + selección y carga del mapa
  pollutionManager.gd          # Contaminación global y por casilla
  saveManager.gd               # Meta-progresión en user://save.json
entities/factory/              # factoryData.gd (tick/producción), factoryPlacer.gd (colocación+sinergias)
entities/player/               # player.gd (modificadores), Bag.gd (almacén global + workers)
entities/tilemap/              # tileMap.gd, tile_map.gdshader (highlight de hover), highligh.tres
ui/                            # mainMenu, packageSelect, radialMenu, upgradeScreen, runSummary, factoryTooltip
resources/factoryParams.json   # Factories, Workers, Checkpoints, Upgrades, StartingPackages, TileTypes, Maps
```

Los managers se instancian en `Main._start_game()` con `load(...).new()`, no vía autoload. Las
pantallas de `ui/` se construyen por código en su `initialize()`; no tienen `.tscn`.

## Sistema de factories

Las factories se definen en `factoryParams.json` → bloque `Factories`:

```json
"WoodProcessing": {
  "material": "plank", "tick": 3, "recieve": ["wood"], "deliverTo": null,
  "pollution": 2.0, "type": "production", "workers_needed": 1,
  "synergies": { "WoodCutter": { "output_bonus": 1 } }
}
```

- **Generadoras**: `recieve: null` — producen sin inputs
- **Procesadoras**: `recieve: [...]` — consumen materiales de la Bag global del jugador
- **Restauración**: `type: "restoration"`, `material: null` y `pollution` negativo
- `tick` = segundos entre producciones. **Cada factory tiene su propio `Timer`** (autostart, 1 s,
  definido en `factory.tscn`); `_on_timer_timeout` cuenta y produce al llegar al tick efectivo
- `synergies` da bonificadores por adyacencia (8 vecinos), evaluados en `factoryPlacer.gd`
- El almacenaje es **global abstracto** (Bag compartida) — no hay cintas transportadoras
- ⚠️ **`deliverTo` está declarado en el JSON pero ningún script lo lee.** No asumas que existe
  transporte dirigido
- Para añadir una factory nueva: solo añadir entrada en JSON, no recompilar

## Convenciones de código GDScript

- Variables sin tipo estático: `var type`, `var timer = 0`
- Punto y coma al final de declaraciones de variables (estilo personal del proyecto)
- Patrón `initialize(...)` en lugar de `_ready()` para nodos que requieren parámetros externos
- Los nodos se obtienen con `get_node()` / `get_node_or_null()` desde el árbol
- Escenas exportadas como `@export var factory: PackedScene` e instanciadas con `.instantiate()`
- Comentarios y commits en español; identificadores en inglés

## Trabajo pendiente (ver Programación.md para detalle)

- Transporte/encadenado visual entre factories (decidir antes qué se hace con `deliverTo`)
- Balance del loop roguelite y variedad de factorías
- Código muerto: `ui/inventory.gd` + `inventory.tscn` están huérfanos (`Main._initiateInventory` es
  un `pass` que nadie llama), y con ellos `player.selectedFactory`, que nadie lee
- Los desbloqueos de paquetes/mapas están hardcodeados en `Main.gd` en vez de en el JSON

> Los cuatro bugs de mecánica que había aquí listados (contaminación por frame, signo invertido de
> las sinergias, apilado de factorías y `toxic.restore_to_unlock`) se **arreglaron el 2026-09-17**.
> Las reglas vigentes están en el `CLAUDE.md` de la raíz, sección «Estado / pendiente conocido».

> El balance que aquí se daba por inexistente se implementó el 2026-09-17
> (`Plan - Tensión del Loop Roguelite`). Las cinco reglas de las que cuelga —contaminación por
> casilla, pico que no baja, umbral de bloqueo desacoplado, orden del desbloqueo de `toxic`, tinte por
> overlay y reserva del almacén— están en el `CLAUDE.md` de la raíz, sección «Reglas que sí
> funcionan». **Léelas antes de tocar `pollutionManager`, `tileMap` o `gameManager`.**

> La **condición de derrota** que aquí se daba por inexistente se implementó el 2026-09-17
> (`Plan - Condiciones de Derrota`): se pierde por **punto muerto**, no por umbral. La cadena es
> ahogo (la contaminación local recorta lo que produce la factoría de encima, salvo las de
> restauración) → contagio (una casilla saturada desborda sobre sus 8 vecinas,
> `tileMap.tick_contagion()`) → `gameManager._evaluate_deadlock()`, que mata la run cuando durante
> `DEADLOCK_GRACE` no se produce, nadie limpia y no queda casilla donde construir; romper cualquiera
> de las tres cancela la cuenta atrás — limpiar es la salida **mientras el mapa no esté saturado
> entero**, porque a partir de ahí el contagio genera más de lo que un `Reforester` quita y la
> condición 2 ya no se rompe (medido en M6). Las dos constantes están **medidas** por el spike de
> M6 (`tests/sim_derrota.gd`, que se conserva): `contagion_rate = 0.12` —el valor más bajo que
> colapsa un mapa abandonado en menos de diez minutos en los dos mapas sin que una run cuidada lo
> note— y `DEADLOCK_GRACE = 25.0` —cubre los 16 s de la productora recién colocada sobre casilla a
> choke 0,25, el falso positivo más largo del juego—. Si mueves una, re-mide con el spike.
> `Main._start_game()` inyecta el TileMap al `gameManager`
> —sin esa línea el evaluador es inerte— y `_on_run_lost()` abre `runSummary` con `won = false`.
> Mientras la cuenta atrás corre, `getObjectiveText()` antepone al HUD el aviso con los segundos que
> quedan y las tres razones, y **solo lee** `deadlock_timer` (el HUD se pinta cada frame). Ese aviso
> **sustituye a la cola de contaminación** —que él mismo ya resume— porque el HUD es UNA línea
> (`Objective`, `Main.tscn`, `y=44`, recursos en `y=73`) y no caben más de ~155 caracteres
> (`gameManager.HUD_MAX_CHARS`, con prueba de longitud en la suite); en la fase de restauración la
> cola se queda, porque ahí es lo único que dice el texto. Y `pollution_threshold` (200.0) es solo
> la escala del **tintado**: salió del HUD en M7 porque `… / 200` deja de informar en cuanto el
> contagio arranca, así que el texto es `Contaminación: N  (restaurar: ≤ M)`.
> **Perder no toca `user://save.json`**, al revés que `_on_run_won()`.

## Tests

```bash
godot-4 --headless --path . --script res://tests/run_tests.gd   # 331 pruebas, exit 0/1
```

El juego también se puede **conducir en headless** para medir balance (instanciar `Main.tscn`,
saltarse los menús con `_start_game()`, colocar con `_on_factory_chosen()` y acelerar con
`Engine.time_scale`). Receta y trampas en `Programación.md` del Brain. El banco montado así que
**se conserva** es `tests/sim_derrota.gd` (M6): midió `contagion_rate` y `DEADLOCK_GRACE` y hay que
volver a pasarlo si se tocan. No es una prueba y no va en la suite.

```bash
godot-4 --headless --path . --script res://tests/sim_derrota.gd -- gracia
```

## Build

No hay comandos de build por terminal. Se exporta desde el **Godot Editor**: `Project → Export`.
Requiere Export Templates de Godot 4.7. El binario del sistema es `godot-4` (snap):

```bash
godot-4 --path .                  # abrir en el editor
godot-4 --path . res://Main.tscn  # ejecutar la escena principal
```
