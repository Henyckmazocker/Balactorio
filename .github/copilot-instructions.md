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
- **Tests**: `godot-4 --headless --path . --script res://tests/run_tests.gd` (1023 comprobaciones, exit 0/1)
- **Lenguaje**: GDScript (sin tipado estático por ahora)
- **Datos del juego**: `resources/factoryParams.json` — iterable sin recompilar

> 🔴 **Medición: hoy no hay ninguna** *(retirada el 2026-09-23)*. Los bots, los bancos, `sim/`
> (conductor, escenarios, caricaturas), la telemetría de partida, `tools/analisis/` y el paso fijo se
> borraron: la prueba fue fallida. La medición se rehará desde cero, válida, objetiva y reutilizable.
> Una pregunta de **legibilidad** se contesta mirando, con `tools/ver_*.gd`; una de **cantidad** no
> tiene hoy respuesta automática. **Antes de concluir que el juego hace X, descarta que quien hace X
> sea tu instrumento.** Ver `CLAUDE.md`, sección «Medición».

## Arquitectura

```
Main.gd / Main.tscn            # Kernel: instancia managers, enruta input, FX de recursos
managers/                      # Lógica de negocio; nodos hijos de Main, sin autoloads
  gameManager.gd               # Checkpoints, objetivo doble, victoria y punto muerto
  mapLoader.gd                 # Paquete de inicio + selección y carga del mapa
  pollutionManager.gd          # Contaminación global y por casilla
  saveManager.gd               # Meta-progresión en user://save.json
  beltNetwork.gd               # Red de cintas indexada por celda; deliver() es el único camino
entities/factory/              # factoryData.gd (tick/producción), factoryPlacer.gd (colocación+sinergias)
entities/player/               # player.gd (modificadores), Bag.gd (almacén global + workers)
entities/tilemap/              # tileMap.gd, tile_map.gdshader (highlight de hover), highligh.tres
ui/                            # mainMenu, packageSelect, radialMenu, upgradeScreen, runSummary, factoryTooltip, factoryPanel
resources/factoryParams.json   # Factories, Workers, Checkpoints, Upgrades, StartingPackages, TileTypes, Maps
tools/                         # ver_dilema.gd, ver_cuellos.gd, ver_variedad.gd — conductores CON ventana
```

Los managers se instancian en `Main._start_game()` con `load(...).new()`, no vía autoload. Las
pantallas de `ui/` se construyen por código en su `initialize()`; no tienen `.tscn`.

## Sistema de factories

Las factories se definen en `factoryParams.json` → bloque `Factories`:

```json
"WoodProcessing": {
  "material": "plank", "tick": 3, "recieve": ["wood"],
  "pollution": 2.0, "type": "production", "workers_needed": 1,
  "synergies": { "WoodCutter": { "output_bonus": 1 } }
}
```

- **Generadoras**: `recieve: null` — producen sin inputs
- **Procesadoras**: `recieve: [...]` — consumen de su **`input_buffer`**, que les llena una cinta. Desde el 2026-09-18 **no leen la Bag**
- **Restauración**: `type: "restoration"`, `material: null` y `pollution` negativo
- 🏭 **Nueve entradas, y tres son la SEGUNDA CADENA** (Plan «Variedad de Factorías», 2026-09-22):
  `Quarry` (`stone`, tick 5, pollution 4,0, 1 worker, **sin sinergias**), `Foundry`
  (`brick`/`glass`, tick 4, pollution 3,0, 1 worker, `recieve: ["stone"]`, `WoodProcessing` le da
  `output_bonus: 1`) y `WaterTreatment` (restauración, tick 4, pollution **−7,0**, 1 worker,
  `recieve: ["stone"]`, `requires_adjacent: ["stream", "lake"]`). 🔴 **De la `WaterTreatment` no
  hay ningún número medido** —ni `tick`, ni `pollution`, ni `cost`—: es **diseño**, no calibrado
- 🔴 **Una restauradora puede quedarse SIN INSUMO, y es lo único que la para** (Variedad M4,
  2026-09-22). Hasta entonces `factoryData.update()` desviaba las de `type: "restoration"` a
  `_tick_restoration()` **sin pasar por `checkNeeds()`**, y la `WaterTreatment` —la primera con
  `recieve`— habría limpiado gratis. Ahora escribe `blocked_reason = "input"` y se para. **Lo que
  NO cambia son las dos reglas de las que cuelga la derrota**: una restauradora **nunca se ahoga**
  por contaminación y **nunca se bloquea por `"output"`**, que es el contrapeso que hace justa la
  derrota. Con `recieve: null` —el `Reforester`— no cambia nada: `checkNeeds()` contesta true
- **`accepts: [...]` (opcional, Variedad M0, 2026-09-22) es de un CHECKPOINT, no de una factoría**:
  los materiales que admite **además** del suyo, en **bolsa común** —se cierra con la suma—. Mismo
  contrato que `materials` y `cost`: **su ausencia = «solo el suyo»**. Curva de hoy: `plank` 15 /
  25 / 55 (`accepts: ["stone"]`) / 100 (`brick`) / 170 (`glass`), que es lo que hace de la segunda
  cadena una alternativa real. Lo implementan `gameManager._accepted_materials()` y, por él,
  `_checkpoint_cost()`, `_can_afford()`, `_stock_for_current()` y `_pending_quantity()`; el HUD
  escribe la lista con « o » («40 / 55 plank o stone»). 🔴 **No añade RESERVA**: el `maintenance`
  se sigue apartando material a material, que es lo que impide colgar la run
- **`requires_adjacent: [...]` (opcional, Variedad M4, 2026-09-22)**: los tipos de casilla de los
  que ese tipo de factoría necesita **al menos uno entre sus 8 vecinos**. Ausencia = ninguno, y lo
  declara **una sola** de las nueve, la `WaterTreatment`. Vive en `tileMap.canPlaceFactory()`, que
  gana un **CUARTO** parámetro opcional con el **nombre del tipo** —el tercero sigue siendo la
  **categoría**— y lo pasan **solo los dos caminos del gesto de construir**
  (`Main._show_radial_menu()` y `_on_factory_chosen()`). 🔴 **Quien no lo pase se comporta
  exactamente como antes**, y eso incluye `hasBuildableCell()` (condición 3 del punto muerto) y la
  validación del arrastre de cinta. El JSON se lo inyecta `Main._start_game()` con
  `setFactoryParams()`: **sin esa línea la regla es inerte**
- **`materials: [...]` (opcional, 2026-09-17)**: entre qué materiales puede elegir esa factoría qué
  fabricar. **Su ausencia significa `[material]`** —lo declara **una sola** de las nueve entradas, la
  `Foundry` con su `["brick", "glass"]` desde el M3 del Plan «Variedad de Factorías» (2026-09-22), y
  las otras ocho no se enteran de que el campo existe—; el fallback lo aplica `factoryData.initialize()` (último
  parámetro, con default, porque `factoryPlacer.build()` los pasa posicionalmente). Cambiar de
  material con `factoryData.setProduction()` **no reinicia el `Timer` ni toca `production_debt`**:
  es un cambio de destino, no una factoría nueva. El desplegable de `ui/factoryPanel.gd` solo
  aparece con **más de un** candidato. 🔴 **El `Storage` ya no lo tiene** *(2026-09-23)*: fue el
  caso de lista **dinámica** entre el 2026-09-18 y esa fecha, pero hoy **no se le elige material** —
  emite por **cada** cinta de salida lo que el consumidor del otro extremo pide en su `recieve`
  (`factoryData._tick_storage_emit()`)—, así que el único con desplegable es la `Foundry`, el caso
  **estático** desde el 2026-09-22 y el que el campo se diseñó para servir. 🔴 `brick` y `glass` no valen lo mismo: el
  checkpoint 4 acepta `brick` y el objetivo final `glass`, así que elegir tiene consecuencia
- `tick` = segundos entre producciones. **Cada factory tiene su propio `Timer`** (autostart, 1 s,
  definido en `factory.tscn`); `_on_timer_timeout` cuenta y produce al llegar al tick efectivo
- `synergies` da bonificadores por adyacencia (8 vecinos), evaluados en `factoryPlacer.gd`
- 🔴 **Hay transporte dirigido desde el 2026-09-18** (`managers/beltNetwork.gd`). El jugador tiende
  cintas **arrastrando** de una casilla a otra; **ocupan casilla construible** y son el único camino
  por el que un material llega a su destino. **Todo pasa por cinta, también entre vecinas**: dos
  factorías pegadas no se entregan nada. En diagonal se unen con **un solo segmento**, y ese par
  **conserva su sinergia** porque la adyacencia mira las 8 vecinas
- **Solo el `Storage` llena la Bag**, y cada mapa arranca con uno construido. Lo que no llega a un
  almacén **no cuenta para los checkpoints**. 🔴 Y el almacén también **EMITE**, desde el 2026-09-23
  **sin que se le elija material**: `factoryData._tick_storage_emit()` recorre **todas** sus cintas
  de salida (`beltNetwork.output_segments()`, orden fijo de `ORTHOGONAL_DIRS` — la reproducibilidad
  se mide con igualdad exacta) y por cada una saca lo que el consumidor del otro extremo declara en
  su `recieve`. Sale de `getAvailable()` y **nunca** de `getQuantity()` (emitir el peaje del
  checkpoint colgaría la run; ya pasó una vez), se descuenta sobre la marcha para que dos destinos no
  gasten la misma madera, un destino se sirve **una sola vez por tick** aunque le lleguen dos cintas,
  y **nunca** se emite hacia otro almacén. Una factoría sin salida acumula 10 unidades y **se
  para, dejando de contaminar** (`output_buffer` / `blocked_reason`), y desde el 2026-09-20 el mapa
  lo **enseña**: marcador de color sobre la casilla, y la razón en palabras en tooltip y panel
- 🔴 **Un nodo LIBERADO se compara igual que `null`**: `nodo != null` es **false** sobre un objeto
  ya liberado, así que un guardia con `!= null` no lo ve. `is_instance_valid()` es el único que los
  distingue — costó un bug latente en el hover (arreglado el 2026-09-20)
- ⚠️ El campo `deliverTo` **no volvió**: se eliminó del JSON el 2026-09-17 y el transporte dirigido
  no lo necesita — el destino lo dice la geometría de la red, no un campo. El campo fantasma que
  **sigue** vivo es `toxic.restore_to_unlock`
- 💰 **Construir CUESTA material** (2026-09-19). `cost` es un campo **opcional** de cada entrada de
  `Factories` (`material -> cantidad`; su ausencia = gratis, igual que `materials`), la cinta tiene
  su bloque aparte `Belts.cost_per_cell`, y los tres `StartingPackages` traen `starting_stock`
  (`standard` 40 `wood` + 4 `plank` + **15 `stone`**, porque ningún precio del juego se pagaba en
  `stone`). Precios de hoy: `WoodCutter` 4 · `Reforester` 6 · `WoodProcessing` 8 `wood`,
  `MetaFactory` 6 · `WorkerCamp` 4 `plank`, `Storage` 10 `wood`, cinta 1 `wood`/casilla, y la segunda
  cadena `Quarry` 8 `stone` · `Foundry` 6 `wood` + 12 `stone` · `WaterTreatment` 4 `wood` + 8 `stone`.
  🔴 **Precios y stock son PROVISIONALES**: salieron de mediciones defectuosas (retiradas el
  2026-09-23) y se suponen incorrectos; los de la `WaterTreatment` ni se midieron.
  Cuatro reglas que no se rompen:
  - 🔴 Se cobra de **`bag.getAvailable()`**, nunca de `getQuantity()`: lo reservado para el
    mantenimiento del checkpoint no se puede gastar en construir. Es lo que impide colgar la run.
  - 🔴 **`charge_cost` es opt-in** en `factoryPlacer.build()` y en `beltNetwork.place_drag()`, y
    solo lo pasan los dos gestos del jugador. Por eso el almacén inicial del mapa, y la suite
    colocan sin pagar.
  - 🔴 Demoler devuelve `floor(pagado/2)` leyendo **`factoryData.cost_paid`** —un recibo por nodo—
    y **nunca** el `cost` del JSON: si mirase el precio, demoler el almacén regalado imprimiría
    madera de la nada.
  - El arrastre es **todo o nada** también con el dinero, y se cobra el tramo que de verdad lleva
    cinta (los extremos ocupados por factoría se recortan), no la longitud del camino.
- 🎴 **El bloque `Upgrades`: 13 cartas — 6 de tier 1 sin castigo y 7 de tier 2 con `map_downside`
  graduado 1/1/1/1/2/2/3** (el cuarteto revisado entrada a entrada el 2026-09-20 por el M2 del Plan
  «Catálogo de Mejoras», que no movió ninguna, más las tres `unlock_factory` de la segunda cadena
  que añadió el M5 del Plan «Variedad de Factorías» el 2026-09-22 —`unlock_quarry` 2 casillas
  `toxic`, `unlock_foundry` 1 y `unlock_watertreatment` 1—: las 4 manos de tier 2 pasan a **35**, y
  el tier 1 no se toca; 🔴 **ni el tier ni el `map_downside` de esas tres están MEDIDOS**: se
  eligieron por coherencia con la escala que ya existía). Lo que el JSON no cuenta: **la baraja de tier 1 que el jugador ve
  son 5 cartas, nunca las 6** — `unlock_woodprocessing` no entra jamás en el reparto (en `standard`
  la filtra `_usable_upgrades()`, y en `lumberjack`/`ecologist` se **concede** antes de repartir con
  `_granted_upgrades()`), así que **su `tier` es inerte**: moverla no cambiaría una sola pantalla y
  le cobraría un castigo a la única carta que el jugador no elige. Con 5 cartas hay 10 manos
  posibles y el reparto las da todas; promover cualquier otra corriente dejaría 4 —la pantalla
  normal volvería a ser trámite— y tendría que llevar `map_downside`, porque una carta de tier 2
  sin castigo está descartada a propósito. Bloque «Catálogo M2» de `tests/run_tests.gd`
- 🔴 **Un `unlock_factory` nuevo se cuela por el RESCATE, que no mira el tier.** Lo que
  `gameManager._unproducible_materials()` apunta se concede **gratis**. Desde Variedad M2 cruza
  `_factory_materials()` —el `materials[]` entero, no solo `material`— contra la lista `accepts`
  **entera** del checkpoint, y desde Variedad M5 **cascada**: lo que ya lleva carta apuntada cuenta
  como producible para los checkpoints siguientes. Sin la cascada, `lumberjack` y `ecologist`
  recibían en el checkpoint 1 **la segunda cadena entera regalada** (falta `plank` en los
  checkpoints 2 a 5, y el 3 acepta `stone`, el 4 `brick` y el 5 `glass`) cuando la serrería sola los
  cubre todos. Lo que NO cambia: si el primer checkpoint bloqueado acepta **dos** materiales
  imposibles se conceden las dos cartas (decisión de Variedad M2). Bloques «Variedad M5» de la suite
- Para añadir una factory nueva: solo añadir entrada en JSON, **con su `cost`**, no recompilar

## Convenciones de código GDScript

- Variables sin tipo estático: `var type`, `var timer = 0`
- Punto y coma al final de declaraciones de variables (estilo personal del proyecto)
- Patrón `initialize(...)` en lugar de `_ready()` para nodos que requieren parámetros externos
- Los nodos se obtienen con `get_node()` / `get_node_or_null()` desde el árbol
- Escenas exportadas como `@export var factory: PackedScene` e instanciadas con `.instantiate()`
- Comentarios y commits en español; identificadores en inglés
- ⚠️ **`str(null)` devuelve `"<null>"`, no `"null"`.** Comparar contra el texto `"null"` no acierta
  jamás. Se compara contra `null` directamente. Fue un bug vivo 18 meses en `ui/factoryTooltip.gd`
  (el `Reforester` pintaba `Produce: <null>`), arreglado el 2026-09-17.
- ⚠️ **`queue_free()` es diferido: el nodo retiene su nombre hasta final de frame.** Si liberas y
  recreas un nodo con el mismo nombre en el mismo frame, el nuevo entra renombrado y `get_node()`
  no vuelve a encontrarlo. `remove_child()` antes del `queue_free()`. En UI, `queue_free()` siempre,
  nunca `free()`: liberar en el acto puede matar el nodo en mitad de un evento de entrada.
- ⚠️ **El radial ESCALA y su radio se CALCULA** (Variedad M4b, 2026-09-22). Con `RADIUS = 118`
  constante y `BUTTON_WIDTH = 130`, seis opciones montaban cuatro pares de botones con 28 px de
  **click ambiguo** (los textos no se pisaban; las cajas sí). Tres piezas: el precio se parte en
  **una línea por material** (`_cost_lines()`, que es lo que pide el `cost` mixto de `Foundry` y
  `WaterTreatment`), `BUTTON_WIDTH` baja a **112** —la línea más ancha que sabe escribir,
  «✦ Mejora 2 vecinas», mide **101 px**— y `_ring_radius()` calcula el radio sobre los
  **rectángulos reales**: **118** hasta 5 opciones, **136** con 6, **151** con 7 y **167** con 8
  (el techo: las nueve entradas menos el `Storage`). **Cero solapes**, y nada que re-anclar cuando
  una factoría nueva añada una línea. Más `_fit_shift()`, que **traslada la corona entera** si el
  menú nace en un borde
- ⚠️ **Una factoría colocada tiene DOS superficies y no se mezclan**: `ui/factoryTooltip.gd` es el
  hover efímero de solo lectura, `ui/factoryPanel.gd` el panel persistente con controles (click
  izquierdo sobre casilla ocupada; `ESC` o click fuera lo cierra). Un tooltip con botones dentro no
  es posible: al ir hacia el botón sales de la casilla y el nodo muere.
- ⚠️ **Los dos contadores de workers se mueven juntos**: `Bag.workers_assigned` y
  `factoryData.workers_assigned`. Lo respetan `factoryPlacer.build()`, `Main._demolish_at_cell()` y
  los botones de `factoryPanel`. Romperlo duplica o pierde workers para el resto de la run.

## Trabajo pendiente (ver Programación.md para detalle)

- ~~**Feedback visual del atasco**~~ — **hecho el 2026-09-20**. `blocked_reason` tiene ya sus cinco
  valores con prioridad fija (`""`/`workers`/`input`/`output`/`choke`, y lo escribe **solo**
  `update()`), un `StatusOverlay` (`z_index = 3`, por encima del `BeltOverlay`) pinta un marcador de
  color por factoría parada, y el tooltip y el panel dicen la razón en palabras con ese mismo color
  preguntando los tres por `ui/blockedReason.gd`. 🔴 Las dos superficies de detalle **se repintan
  solas** —el panel por `_process()`, el tooltip también con el ratón quieto— porque una etiqueta
  estática se queda pegada y contradice al marcador del mapa
- **El arrastre no se previsualiza** mientras mantienes el botón: se tiende a ciegas. El
  `BeltOverlay` ya es el sitio donde pintarlo
- `ui/mainMenu.gd` **no anuncia el arrastre** para tender cinta, siendo el único texto que enseña
  los controles
- Los desbloqueos de paquetes/mapas están hardcodeados en `Main.gd` en vez de en el JSON

> Los cuatro bugs de mecánica que había aquí listados (contaminación por frame, signo invertido de
> las sinergias, apilado de factorías y `toxic.restore_to_unlock`) se **arreglaron el 2026-09-17**.
> Ese mismo día se retiró el **código muerto** que también se listaba aquí: `ui/inventory.gd` +
> `inventory.tscn`, `factoryTemplate.tscn`, `Main._initiateInventory()`, `player.selectedFactory` y,
> en `factoryData.gd`, `in_inventory` / `factory_selected` / `_on_input_event()` — y con ellos el
> `input_pickable = true` que hacía que cada factoría del mapa se tragase los clicks.
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
> de las tres cancela la cuenta atrás — limpiar es la salida, y **desde Costes M7 (2026-09-19) lo
> es también sobre el mapa saturado**: `tileMap.canPlaceFactory(cell, factory_array,
> factory_kind = "", factory_type = "")` recibe la categoría de lo que se coloca y deja pasar a las de
> `type: "restoration"` sobre una casilla cerrada por `cell_block_pollution` —la misma idea por la
> que esas factorías no se ahogan: limpiar tiene que funcionar siempre—. El `""` es la regla
> ESTRICTA de siempre y es la que preguntan `hasBuildableCell()` (si no, la condición 3 sería
> inalcanzable y no habría derrota) y el arrastre de cinta (una cinta no es una factoría). Limpiar
> el mapa saturado no es gratis.
> 🔴 **Las dos constantes son PROVISIONALES**: `contagion_rate = 0.12` y `DEADLOCK_GRACE = 25.0`
> salieron de mediciones que se hacían mal (retiradas el 2026-09-23) y se suponen incorrectas hasta
> volver a medirlas. Vale su criterio de diseño —un mapa abandonado colapsa dentro de una sentada sin
> que una run cuidada lo note; la gracia cubre lo que tarda la jugada que desatasca más un margen
> para leer el aviso— y el suelo que comprueba la suite: la prueba «Derrota M6» exige
> `contagion_pollution / contagion_rate <= 120 s`, o sea `rate >= 0,105`. El razonamiento está en
> sus comentarios (`pollutionManager.gd`, `gameManager.gd`).
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
godot-4 --headless --path . --script res://tests/run_tests.gd   # 1023 comprobaciones, exit 0/1
```

`tests/run_tests.gd` cubre **relaciones**, no cantidades: afirma que las constantes siguen
cumpliendo su razón de ser, no las vuelve a medir.

🔴 **No hay ningún instrumento de medida** *(2026-09-23)*. Se retiró todo: los bancos y el bot
(2026-09-22), y `sim/`, `managers/telemetria.gd`, `tools/analisis/`, `medidas/`, el paso fijo
(`Main.setFixedStep()`) y los golden de la suite (2026-09-23). Lecciones que la medición nueva debe
respetar, detalladas en `CLAUDE.md` («Medición»): un veredicto «el jugador no puede ganar» no vale
hasta descartar al instrumento —síntoma: **recursos sin gastar**—; toda cifra lleva sellada la
versión que mide; y antes de medir una pregunta de diseño, **mírala**.

Lo que queda para verificar, además de la suite, es mirar el juego con ventana:

```bash
godot-4 --path . --script res://tools/ver_dilema.gd    # CON ventana; deja PNG en capturas/
godot-4 --path . --script res://tools/ver_cuellos.gd   # CON ventana; los cuatro estados de parada
godot-4 --path . --script res://tools/ver_variedad.gd  # CON ventana; las siete situaciones de Variedad
```

`ver_variedad.gd` (2026-09-22) es el tercero: el desplegable `brick`/`glass` del panel de la
`Foundry`, el color del FX de `brick`/`glass`/`stone`, la depuradora parada por `input` (tooltip y
panel, que no conviven), su botón del radial con el precio partido, y el radial con **seis**, con
**ocho** y en una **esquina**. Deja PNG en `capturas/` y **no juzga nada**: decide quien mira.

**Hay skill propia**: `.claude/skills/ver-el-juego/SKILL.md`, con el montaje mínimo y las trampas.
Sin instrumento de medida, es la vía principal para comprobar algo que la suite no cubre.

Trampas del conductor con ventana: las pantallas de mejora **no se buscan por nombre** (extienden
`CanvasLayer` y se renombran a `@CanvasLayer@N` al apilarse — usa `has_signal("upgrade_chosen")`),
hay que **pausar el árbol** para fotografiar el mapa —pero 🔴 **despausándolo antes de mirar**: el
juego pausa el árbol con la pantalla de mejora abierta y entonces `_process()` no corre, así que los
overlays no se repintan y la foto enseña el estado de hace rato—, y `await
RenderingServer.frame_post_draw` antes de `save_png()` o guardas el frame anterior. Detalle en el
`CLAUDE.md` de la raíz.

## Build

No hay comandos de build por terminal. Se exporta desde el **Godot Editor**: `Project → Export`.
Requiere Export Templates de Godot 4.7. El binario del sistema es `godot-4` (snap):

```bash
godot-4 --path .                  # abrir en el editor
godot-4 --path . res://Main.tscn  # ejecutar la escena principal
```
