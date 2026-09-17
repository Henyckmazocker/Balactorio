# CLAUDE.md — Balactorio

Guía para Claude Code al trabajar en este repositorio.

> Documentación en español por convención del proyecto. Identificadores en código en inglés.

## 🧠 Brain

Spec, GDD y estado en el segundo cerebro:
`/home/david/Documents/workspace/Brain/03 - Proyectos/Balactorio.md` (+ carpeta `Balactorio/`).
Léela para el diseño y el roadmap; este `CLAUDE.md` cubre el detalle técnico del repo.

## Qué es Balactorio

Videojuego de **gestión de factorías + roguelite** con vista isométrica, mezcla de *Factorio*
(cadenas de producción) y un loop por *runs* con mejoras. El jugador coloca factorías que producen y
consumen materiales encadenados, gestionando la **contaminación** que generan.

**Motor:** Godot **4.7** (Forward+, GDScript) | **Resolución:** 1280x720 | **Plataforma:** PC
(Windows/Linux) | **Escena principal:** `Main.tscn`.

## Cómo se ejecuta

Proyecto Godot nativo (sin Docker):

El binario del sistema es `godot-4` (snap):

```bash
godot-4 --path .                  # abrir en el editor
godot-4 --path . res://Main.tscn  # ejecutar la escena principal
```

## Tests

El proyecto tiene suite propia en `tests/run_tests.gd`. Es un script de `SceneTree`, no necesita
plugin ni dependencias:

```bash
godot-4 --headless --path . --script res://tests/run_tests.gd   # 331 pruebas
godot-4 --headless --path . --import                            # solo comprueba que importa
```

Sale con **código 0** si pasa todo y **1** si algo falla. Cubre el tick pasivo escalado por `delta`,
los signos y destinatarios de las sinergias, el escalado de la restauración por output, el reparto en
área, las reglas de colocación y el recálculo de sinergias al demoler, más una regresión de que las
factorías de producción no cambiaron.

**Al tocar mecánicas, ejecútala antes de dar nada por bueno**: que el proyecto importe no prueba
ningún comportamiento. Dos avisos para escribir pruebas nuevas:

- Los nodos se montan en `_process()`, **no en `_initialize()`**: ahí el `root` todavía no existe y
  lo que se le añade no queda dentro del árbol.
- `factoryData._apply_pollution()` localiza el manager con `find_child("PollutionManager")`, que
  devuelve **el primero** del árbol: suelta el escenario anterior antes de montar el siguiente.

Aparte de la suite está **`tests/sim_derrota.gd`**, que no es una prueba: es el **banco de balance**
que midió `contagion_rate` y `DEADLOCK_GRACE` en M6, conduciendo el juego entero en headless. No va
en la suite ni en ningún hook —el barrido completo tarda minutos— y **se conserva** para re-medir
esas constantes en cuanto entren factorías o eventos nuevos:

```bash
godot-4 --headless --path . --script res://tests/sim_derrota.gd              # los cuatro bloques
godot-4 --headless --path . --script res://tests/sim_derrota.gd -- gracia    # solo uno
```

## Arquitectura

- **`Main.gd` / `Main.tscn`** — kernel: instancia y orquesta los managers e inicializa la run. No
  hay autoloads; los managers son nodos hijos de la escena principal.
- **`managers/`** — lógica de negocio:
  - `gameManager.gd` — objetivos, checkpoints y condiciones de victoria y de derrota de la run.
  - `mapLoader.gd` — carga del mapa y aplicación del paquete inicial.
  - `pollutionManager.gd` — contabilidad de contaminación, global y por casilla. El tick pasivo de
    los tiles (lago, tóxico, lava) lo aplica `tileMap.tick_passive()`, no este manager.
  - `saveManager.gd` — **meta-progresión** en `user://save.json`: paquetes y mapas desbloqueados,
    runs completadas y mejor tiempo. **No guarda la run en curso**: no existe «continuar partida».
- **`entities/`**:
  - `factory/` — `factory.tscn`, `factoryData.gd` (tick, inputs, outputs), `factoryPlacer.gd`
    (colocación en grid), `factoryTemplate.tscn`.
  - `player/` — `player.tscn`/`player.gd` + `Bag.gd` (inventario de recursos/workers).
  - `tilemap/` — `tile_map.tscn` (mapa isométrico).
- **`ui/`** — `mainMenu`, `packageSelect`, `radialMenu`, `upgradeScreen`, `runSummary`,
  `factoryTooltip`. Pantallas construidas por código en su `initialize()`; no tienen `.tscn`.
  ⚠️ `inventory.gd` + `inventory.tscn` están **huérfanos**: nadie los instancia.
  - Controles: **click izquierdo** en casilla libre abre el radial de construcción; **click
    derecho** demuele la factoría y devuelve sus workers; `R` reinicia la run.
- **`resources/factoryParams.json`** — **definición declarativa de las factorías**: por cada tipo,
  su `material` de salida, `tick` (frecuencia), `recieve` (inputs), `deliverTo`, `pollution`,
  `workers_needed`, `type` y `synergies` con otras factorías. Para añadir/ajustar una factoría se
  edita este JSON, no el código.

## Flujo de juego

`mainMenu` → `packageSelect` (paquete inicial) → run: colocar factorías, encadenar producción,
controlar contaminación, alcanzar objetivos (`gameManager`) → `upgradeScreen` / `runSummary`.

## Buenos comportamientos en este repo

- **GDScript puro.** `class_name` cuando sea reutilizable, `snake_case` para vars/funciones,
  `PascalCase` para clases, señales para desacoplar.
- **Las factorías se definen en `factoryParams.json`**, no hardcodeadas: respeta ese contrato
  (material/tick/recieve/deliverTo/pollution/synergies).
- **Commits y comentarios en español; identificadores en inglés.**

## Estado / pendiente conocido

Implementado: tilemap isométrico con tipos de casilla, factorías con synergies, bag con workers,
contaminación global y por casilla, meta-progresión entre runs, UI de menús/upgrades/resumen,
objetivos y checkpoints, y derrota por punto muerto.

Pendiente conocido — **léelo antes de asumir que algo funciona**:

- `deliverTo` (JSON) y `toxic.restore_to_unlock` (JSON) están declarados y **ningún script los lee**.
  No hay transporte dirigido: el almacenaje es una Bag global compartida.
- Código muerto: `ui/inventory.gd` + `inventory.tscn` y `player.selectedFactory`.
  `Main._initiateInventory` es un `pass` que nadie llama.
- Los desbloqueos de paquetes/mapas están hardcodeados en `Main.gd`, no en el JSON.
- `ui/factoryTooltip.gd` pinta «Produce: `<null>`» en las factorías de restauración.
- El HUD **no enseña** el rendimiento de línea que decide el tier de la recompensa, así que el
  jugador no puede saber por qué le han dado una carta potente.

Reglas que **sí** funcionan y conviene no romper (arregladas el 2026-09-17):

- 🔴 **Se puede perder, y la cadena es ahogo → contagio → punto muerto.** La
  contaminación de una casilla ahoga lo que produce la factoría de encima (`factoryData`, solo
  `type: "production"`; las de restauración nunca se ahogan), una casilla saturada desborda sobre
  sus 8 vecinas (`tileMap.tick_contagion()`) y `gameManager._evaluate_deadlock()` declara muerta la
  run cuando durante `DEADLOCK_GRACE` no se produce, nadie limpia y no queda casilla donde
  construir. Las tres a la vez: si una se rompe la cuenta atrás se cancela, así que limpiar es la
  salida **mientras el mapa no esté saturado entero**: pasado ese punto el contagio genera más de
  lo que un `Reforester` puede quitar, la condición 2 ya no se rompe y el mapa está muerto de
  verdad (medido en M6). `Main._start_game()` le inyecta el TileMap al `gameManager` —**sin esa
  línea el evaluador es inerte**— y `_on_run_lost()` abre `runSummary` con `won = false`. Mientras
  la ventana corre, `getObjectiveText()` antepone al HUD el aviso con los segundos que quedan y las
  tres razones, y ese aviso **sustituye a la cola de contaminación** (que el propio aviso ya
  resume) para que la línea quepa — salvo en la fase de restauración, donde la cola es lo único
  que dice el texto y la línea es corta. El aviso **solo lee** `deadlock_timer`, porque el HUD se
  pinta cada frame.
- 🔴 **Las dos constantes de la derrota están MEDIDAS, no puestas a ojo** (spike de M6,
  `tests/sim_derrota.gd`, que se conserva para re-medirlas). `contagion_rate = 0.12`
  (`pollutionManager.gd`) es el valor más bajo que colapsa un mapa abandonado en menos de diez
  minutos en los dos mapas (564 s en `forest_01`, 450 s en `wasteland_01`) sin que una run jugada
  con cuidado lo note (el pico sube de 46,2 a 74,9 y la run cierra 5/5 en los mismos segundos).
  `DEADLOCK_GRACE = 25.0` (`gameManager.gd`) cubre los 16 s que tarda en entregar una productora
  recién colocada sobre una casilla a choke 0,25, que es el falso positivo más largo que el juego
  sabe producir. **Si cambias una, re-mide con el spike**: el razonamiento entero está en los
  comentarios de las dos constantes.
- 🔴 **Perder NO toca `user://save.json`.** `_on_run_lost()` es el espejo de `_on_run_won()` **sin**
  su bloque de `saveManager`: no registra la run, no mueve el mejor tiempo y no desbloquea paquetes
  ni mapas. La meta-progresión se gana terminando la run.
- 🔴 **`removePollution(amount, cell)` descuenta del global SOLO lo que quita de esa casilla.** Es la
  regla de la que cuelga media mecánica: la contaminación vive en las casillas, así que limpiar sobre
  suelo limpio no acerca la victoria y la fase 2 se gana **cubriendo** las zonas sucias en vez de
  apilar `Reforester`. Si alguien la «arregla» para que el global baje siempre, la geometría deja de
  importar y nada más falla — por eso hay una prueba dedicada.
- **`peak_pollution` nunca baja al limpiar.** De él sale el umbral de victoria
  (`5.0 + 0.12 × pico`), que es lo que hace que producir sin piedad se pague después.
- **`pollution_threshold` (200.0) es solo la escala del TINTADO.** Desde M7 ya no sale por el HUD:
  `Contaminación: 14209 / 200` dejaba de informar en cuanto el contagio arrancaba, así que
  `getStatusText()` enseña `Contaminación: N  (restaurar: ≤ M)` y la gravedad la cuenta el tinte,
  que sí se ve. **El HUD es UNA línea** (`Objective`, `Main.tscn`, `y=44`, con los recursos en
  `y=73`): no se parte con `\n` y no caben más de ~155 caracteres (`gameManager.HUD_MAX_CHARS`,
  con su prueba de longitud en la suite). Quien cierra una casilla a la construcción es
  `cell_block_pollution` (12,5), constante aparte **a propósito**: recalibrar el tinte no debe
  mover una regla de colocación.
- **`_check_toxic_unlock()` va ANTES de `tick_passive()`** en `Main._tick_world()`. Al revés, el tick
  pasivo suma su +0,5 justo antes de la comprobación y una casilla `toxic` no se desbloquea jamás.
  Y el check exige que la casilla **haya estado sucia**, o una `toxic` virgen se restauraría sola en
  el primer frame.
- **El tinte de casilla sale por el nodo `TintOverlay`, no por el `_draw()` del TileMap.** Dibujado
  desde el TileMap queda por debajo de los tiles y no se ve nada: fue el bug que hizo invisibles 8 de
  los 11 tipos de casilla.
- **Las factorías consumen `bag.getAvailable()`, no `bag.getQuantity()`.** El almacén aparta lo que
  el checkpoint en curso exige; sin eso, una serrería rápida se come la madera del mantenimiento y la
  run se cuelga para siempre.

- `passive_pollution_per_tick` de los `TileTypes` está **por segundo**: `tileMap.tick_passive()` lo
  escala por `delta`. No lo llames sin delta.
- En `synergies`, un `tick_bonus` **positivo acelera** (igual que en los `adjacency_bonus` de
  `TileTypes`), y `pollution_mult` multiplica un valor **con signo**: sobre una factoría de
  restauración, `> 1.0` potencia la limpieza.
- `A.synergies.B` significa «A aplica este bonus a **B**», en los dos órdenes de colocación.
- Al demoler, `Main._demolish_at_cell()` recalcula las 8 vecinas con
  `factoryPlacer.recompute_synergies()`, que resetea los acumuladores **y reaplica el
  `adjacency_bonus` del tile**. Si tocas esa función, no olvides el segundo paso.
- Las factorías de restauración reparten su limpieza entre su casilla y las 8 vecinas (un noveno cada
  una, total constante). Es lo que hace recuperable una casilla `toxic`.
- `tileMap.canPlaceFactory(cell, factory_array)` es el **único punto de verdad** de «¿cabe aquí?».

Detalle y planes de arreglo en el Brain (ver arriba).
