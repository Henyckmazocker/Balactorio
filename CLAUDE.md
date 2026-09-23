# CLAUDE.md — Balactorio

Guía para Claude Code al trabajar en este repositorio.

> Documentación en español por convención del proyecto. Identificadores en código en inglés.

## 🧠 Brain

Spec, GDD y estado en el segundo cerebro:
`/home/david/Documents/workspace/Brain/03 - Proyectos/Balactorio.md` (+ carpeta `Balactorio/`).
Léela para el diseño y el roadmap; este `CLAUDE.md` cubre el detalle técnico del repo. La página
declara `repo:` apuntando aquí, así que el enlace vale en los dos sentidos.

Las sub-notas que más se usan, para no tener que abrir el índice primero:

| Qué | Dónde, bajo `Brain/03 - Proyectos/Balactorio/` |
|---|---|
| Mecánicas, balance y contenido | `GDD/Mecánicas.md`, `GDD/Mundo y Niveles.md` |
| Arquitectura, tests y **cómo probar el juego** | `Programación.md` |
| Lo que falta y lo que se ha decidido no hacer | `Roadmap.md` |
| Lo que se implementó y por qué | `Planes/Finalizadas/` |

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
godot-4 --headless --path . --script res://tests/run_tests.gd   # 1023 comprobaciones
godot-4 --headless --path . --import                            # solo comprueba que importa
```

Sale con **código 0** si pasa todo y **1** si algo falla. Cubre **relaciones**, no cantidades:
afirma que las constantes siguen cumpliendo su razón de ser, no las vuelve a medir. Cubre el tick
pasivo escalado por `delta`, los signos y destinatarios de las sinergias, el escalado de la
restauración por output, el reparto en área, las reglas de colocación y el recálculo de sinergias al
demoler, el panel de factoría (workers reasignados sin demoler y el selector de material con su
fallback), más una regresión de que las factorías de producción no cambiaron. Los bloques «Variedad
M0-M5» añaden el `accepts` de los checkpoints, el `requires_adjacent` de la colocación, la
restauradora sin insumo, el reparto del catálogo de 13 cartas y la cascada del rescate.

**Al tocar mecánicas, ejecútala antes de dar nada por bueno**: que el proyecto importe no prueba
ningún comportamiento. Dos avisos para escribir pruebas nuevas:

- Los nodos se montan en `_process()`, **no en `_initialize()`**: ahí el `root` todavía no existe y
  lo que se le añade no queda dentro del árbol.
- `factoryData._apply_pollution()` localiza el manager con `find_child("PollutionManager")`, que
  devuelve **el primero** del árbol: suelta el escenario anterior antes de montar el siguiente.

## 🔴 Medición: hoy NO hay ninguna *(retirada el 2026-09-23)*

**El repo no tiene ningún instrumento que mida cantidades.** Todo lo que se construyó para medir el
juego —tres generaciones de jugador simulado, los bancos de balance, el conductor de escenarios, la
telemetría de partida y las calculadoras de Python— se ha retirado por completo: como prueba fue
fallida y no servía para lo que se esperaba. La medición se va a **diseñar desde cero**, con el
objetivo de que sea **válida, objetiva y reutilizable** (Roadmap del Brain).

Lo que se borró, para que nadie lo busque:

| Qué | Cuándo |
|---|---|
| Bancos `tests/sim_*.gd` y el bot reactivo `tests/bot_reactivo.gd` | 2026-09-22 |
| `sim/` entero: `conductor.gd`, `medida.gd`, `m0_determinismo.gd`, `escenarios/`, `caricaturas/` | 2026-09-23 |
| `managers/telemetria.gd` y sus ganchos en `Main.gd` y `ui/factoryPanel.gd` | 2026-09-23 |
| `tools/analisis/` (esquema, huella, catálogo, baraja, ventanas, agregar, partidas) y `medidas/` | 2026-09-23 |
| El paso fijo: `Main.setFixedStep()`, `fixed_step` en `Main` y `gameManager`, `factoryData.advanceFixed()` | 2026-09-23 |
| Los 4 golden de `cadena_madera` y las pruebas de la suite que cargaban `sim/` o la telemetría | 2026-09-23 |
| El no-op `factoryData.refreshStorageCandidates()` (solo lo llamaba el conductor) | 2026-09-23 |

Lo que **se conserva**: la suite (arriba), `tools/ver_*.gd` con su skill (abajo, **miran**, no
miden), y dos piezas que nacieron para los bancos pero son del juego y de la suite —el
`PollutionManager` cacheado de `factoryData` y los interruptores headless `Main.render_enabled` /
`factoryData.animations_enabled`—.

🔴 **Todos los números de balance que salieron de aquellas mediciones se SUPONEN INCORRECTOS**
*(decisión del 2026-09-23)*: las mediciones se hacían mal. `contagion_rate` 0,12, `DEADLOCK_GRACE`
25, los precios de las nueve factorías, el `starting_stock`, `TIER2_EFFICIENCY` 0,55 y los tiers y
castigos de las cartas siguen en el juego porque algo tiene que haber, pero son **provisionales**: no
los cites como medidos ni como calibrados, y no los uses de argumento para no cambiar algo. La
primera tarea de la medición nueva será volver a medirlos. Lo que sí vale es lo que comprueba la
suite: **relaciones** (p. ej. `contagion_pollution / contagion_rate <= 120 s`), no cantidades.

**Las lecciones que la medición nueva tiene que respetar**, que es lo único valioso que dejó todo
esto:

- 🔴 **Un veredicto «el jugador no puede ganar» no vale nada hasta descartar que el que no puede es
  el instrumento.** El síntoma es siempre el mismo: **la run termina con recursos sin gastar**. Dos
  bots se borraron por medir su propia torpeza como si fuera del juego (runs con 66-2.676 de madera
  pagable sin comprar), y el 2026-09-20 un día entero de barridos dio por bueno un problema que no existía y
  que veinte minutos mirando el juego desmintieron.
- **Tres intentos de jugador simulado fracasaron**: plano fijo, reactivo y «caricaturas». El último
  no pasaba del checkpoint 1 porque los 20 `wood` gastables del primer frame cubren exactos
  cortadora+cinta, serrería+cinta y limpiador, y la jugada que gana —limpiadores preventivos en t=0
  sobre suelo limpio— exige juicio: en el segundo 0 no hay foco que mirar.
- Toda cifra tiene que llevar **sellada la versión del juego** que mide, y ninguna media puede
  imprimirse **sin su recuento y su contaminación al lado**.
- Lo que sí funcionó técnicamente fue el **determinismo** (paso fijo bit a bit).
- **¿Cantidad o diseño?** Antes de gastar una medición en una pregunta de diseño, pregúntate si un
  humano la contestaría mirando la pantalla cinco minutos. Si sí, mira primero.

### Lanzar un `godot-4` largo desde Claude Code sin dejar procesos vivos

Un `godot-4` que tarda minutos —la suite entera, un `--import`, un conductor con ventana— invita a
lanzarlo en segundo plano y **esperar con un bucle**. Ahí está la trampa que ha dejado veinte shells
colgados al cerrar sesión (*«Background work is running — the following will stop when you exit»*):

```bash
# 🔴 NUNCA. Este bucle no termina JAMÁS.
until [ "$(pgrep -c -f 'godot-4 --headless --path .')" = "0" ]; do sleep 5; done
```

`pgrep -f` compara contra la **línea de comandos completa**, y la línea de comandos del propio bucle
contiene el patrón que busca: el bucle **se encuentra a sí mismo**, el contador nunca baja a 0 y
sigue girando hasta que alguien mata la sesión. Medido el 2026-09-20 con **un** godot de verdad
corriendo:

| Comando | Cuenta |
|---|---|
| `pgrep -c -f 'godot-4 --headless --path .'` | **3** — godot + el `timeout` + el bash del bucle |
| `pgrep -c -x godot-4` | **1** — solo godot |

Lo mismo vale para `pgrep -f 'run_tests.gd'` o `until ! pgrep -f "ver_cuellos.gd"`. Y un
`until [ -f <fichero> ]` sin techo gira para siempre si el fichero nunca llega a escribirse.

**La receta buena: no hay bucle de espera.**

1. Lánzalo **directamente en segundo plano** (`run_in_background` del tool Bash) con la salida
   a un fichero. El harness lo vigila él, avisa solo cuando termina, y `TaskStop` lo mata:

   ```bash
   timeout 400 godot-4 --headless --path . --script res://tests/run_tests.gd \
     > "$SCRATCH/run_tests.log" 2>&1               # $SCRATCH = scratchpad de la sesión
   ```

2. Una pasada que baje de ~8 min cabe **en primer plano** con el `timeout` del propio tool Bash
   (máximo 600 000 ms). Sin tarea en segundo plano no hay nada que pueda quedarse colgado.
3. Si hace falta ver la salida mientras corre, eso es el tool `Monitor` sobre el log
   (`tail -f … | grep --line-buffered …`): expira solo y se cancela con `TaskStop`.

**Si aun así escribes un `pgrep`**, dos reglas innegociables: `-x godot-4` (por nombre de proceso,
que nunca se auto-encuentra) en vez de `-f`, y **siempre un techo de vueltas**:

```bash
for _ in $(seq 60); do pgrep -x godot-4 >/dev/null || break; sleep 5; done   # 5 min y se rinde
```

**Todo `godot-4` headless lleva `timeout N` delante.** Un godot encallado sin techo sobrevive a la
sesión. Y antes de cerrar, comprobar y limpiar es una línea:

```bash
pgrep -a -x godot-4    # ¿queda algo vivo?
pkill  -x godot-4      # matarlo — ojo: también cierra el editor si lo tienes abierto
```

### Mirar el juego: `tools/ver_dilema.gd`, `tools/ver_cuellos.gd` y `tools/ver_variedad.gd`

> **Hay skill propia para esto: `.claude/skills/ver-el-juego/SKILL.md`.** Léela antes de escribir un
> conductor con ventana: lleva el montaje mínimo y las cinco trampas. Sin ningún instrumento de
> medida en el repo (retirados el 2026-09-22/23) esto es, junto a la suite, **lo único que queda para
> verificar algo**. Lo de abajo es
> el resumen.

```bash
godot-4 --path . --script res://tools/ver_dilema.gd    # CON ventana; deja PNG en capturas/
godot-4 --path . --script res://tools/ver_cuellos.gd   # CON ventana; los cuatro estados de parada
godot-4 --path . --script res://tools/ver_variedad.gd  # CON ventana; las siete situaciones de Variedad
```

`ver_variedad.gd` (2026-09-22) es el tercero y monta las **siete** preguntas que la suite no sabe
hacer porque ninguna es una cantidad: el desplegable `brick`/`glass` del panel de la `Foundry`, el
color del FX de `brick`/`glass`/`stone`, la depuradora parada por `input` (tooltip y panel, que no
conviven), su botón del radial con el precio partido en dos líneas, y el radial con **seis**, con
**ocho** y abierto en una **esquina**. Deja los PNG en `capturas/` y **no juzga nada**: decide quien
mira.

Arranca el juego con render, aplica el castigo de las dos políticas extremas por el **camino real**
(`_on_checkpoint_reached()` → `upgradeScreen` → `_on_upgrade_chosen()` → `_apply_map_downside()`) y
deja cuatro capturas en `capturas/` (ignorado por git). No mide nada: se mira. Hay display X real
(`DISPLAY=:0`), no hace falta xvfb, y el bloque `ERROR: Condition "err != VK_SUCCESS"` seguido de
`switching to OpenGL 3` es ruido esperado.

Dos trampas que costaron cuatro iteraciones y que valen para **cualquier** conductor con ventana:

- 🔴 **Las pantallas de mejora no se buscan por nombre.** `ui/upgradeScreen.gd` extiende
  `CanvasLayer`, y en cuanto se apila más de una —`queue_free()` es diferido y el juego alcanza sus
  propios checkpoints mientras el conductor inyecta los suyos— Godot las renombra a
  `@CanvasLayer@N`: `get_node("UpgradeScreen")` encuentra solo la primera y la foto sale con un
  panel tapando el mapa. Se identifican por `has_signal("upgrade_chosen")`. Es la misma familia que
  la trampa del tooltip documentada más abajo.
- **Para fotografiar el mapa hay que pausar el árbol.** Despausarlo deja correr la run, que alcanza
  el checkpoint siguiente en unos frames y vuelve a abrir la pantalla encima de lo que querías ver.
- 🔴 **Pero hay que DESPAUSAR antes de mirar, y es el reverso de la anterior.** El juego pausa el
  árbol al abrir la pantalla de mejora, y con el árbol pausado `_process()` no corre —ni el de
  `Main` ni el del `TileMap`—, así que **los overlays no se repintan** y la foto enseña lo último
  que se dibujó cuando el juego estuvo vivo. La primera pasada de `tools/ver_cuellos.gd` capturó así
  cuatro factorías correctamente bloqueadas y **un mapa sin un solo marcador**, y pareció un fallo
  de `z_index` que no existía. Receta: cerrar pantallas → despausar → unos frames → pausar → foto
  (`_capturar_mapa()` y `_estabilizar()` en ese fichero).
- Y la de siempre: **`await RenderingServer.frame_post_draw` antes de `save_png()`**, o guardas el
  frame anterior.


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
  - `beltNetwork.gd` — **la red de cintas** (2026-09-18), indexada por celda (`Vector2i ->
    BeltSegment`), con `deliver()` como único camino por el que un material llega a su destino.
    🔴 Desde el 2026-09-23 `deliver()` está **partido en tres** para que el almacén pueda emitir por
    varias cintas: `route_destination(from, seg, material = null)` contesta «¿a quién lleva esta
    cinta?» (sin material no mira filtros), `deliver_via(from, seg, …)` entrega **empezando por un
    segmento dado**, y `deliver()` es `deliver_via(_entry_segment(…))`. El contrato «devuelve 0 o
    `amount`, nunca una entrega parcial» **no cambió**. Y `output_segments(cell)` devuelve **todas**
    las salidas de una celda, en el orden fijo de `ORTHOGONAL_DIRS`: `_entry_segment()` devuelve solo
    **la primera**, que es por lo que un almacén con dos cintas de salida habría usado una sola.
    Las cintas **no** son un tipo de casilla: no entran en `tileMap.cell_types`, viven en su propio
    diccionario. Dibuja por un `BeltOverlay` hijo del TileMap con `z_index` propio, por la misma
    razón que el `TintOverlay`.
- **`entities/`**:
  - `factory/` — `factory.tscn`, `factoryData.gd` (tick, inputs, outputs), `factoryPlacer.gd`
    (colocación en grid).
  - `player/` — `player.tscn`/`player.gd` + `Bag.gd` (inventario de recursos/workers).
  - `tilemap/` — `tile_map.tscn` (mapa isométrico).
- **`ui/`** — `mainMenu`, `packageSelect`, `radialMenu`, `upgradeScreen`, `runSummary`,
  `factoryTooltip`, `factoryPanel`. Pantallas construidas por código en su `initialize()`; no
  tienen `.tscn`.
  - Controles: **click izquierdo** en casilla libre abre el radial de construcción; **click
    izquierdo sobre casilla ocupada** abre el panel de esa factoría; **click derecho** demuele la
    factoría (o borra el segmento de cinta) y devuelve sus workers; `R` reinicia la run.
  - 🔴 **El gesto desambigua el click del arrastre, y no hay modo ni tecla modificadora**: pulsar y
    soltar en la MISMA celda es el click de siempre; pulsar en una y soltar en OTRA **tiende
    cinta**. Por eso el click de siempre se resuelve **al soltar** y no al pulsar: al pulsar todavía
    no se sabe cuál de los dos gestos es. Desde M7 los extremos del arrastre **pueden ser casillas
    con factoría** y se excluyen del camino, que es lo que permite la cinta de una sola casilla —y
    con ella unir dos factorías en diagonal—. `ui/mainMenu.gd` todavía **no anuncia** el arrastre.
  - 🔴 **El radial ESCALA con lo desbloqueado, y su radio se CALCULA** *(Variedad M4b,
    2026-09-22)*. El defecto: `RADIUS` era la constante 118 y `BUTTON_WIDTH` valía 130, así que con
    **seis** opciones cuatro pares de botones se montaban con una franja de 28 px —ningún texto
    pisaba a otro: lo que se solapaba eran las cajas, y esa franja era **zona de click ambiguo**—.
    Tres piezas: el **precio se parte en una línea por material** (`_cost_lines()`, que es lo que
    pide el `cost` mixto de `Foundry` y `WaterTreatment`), `BUTTON_WIDTH` baja a **112** —la línea
    más ancha que el menú sabe escribir es «✦ Mejora 2 vecinas», **101 px**, y sobran 11— y el
    radio lo calcula `_ring_radius()` sobre los **rectángulos reales**: `118` de 2 a 5 opciones (la
    corona de siempre), **136** con 6, **151** con 7 y **167** con 8, que es el techo real (las
    nueve entradas menos el `Storage`, que no se elige). **Cero solapes**, y no es una constante
    mágica que re-anclar cuando una factoría nueva añada una línea a su botón. Más `_fit_shift()`,
    que **traslada la corona entera** si el menú nace pegado a un borde: la envolvente de ocho mide
    446×400 y cabe en los 1280×720, pero no si nace en una esquina.
  - **Dos superficies distintas para una factoría colocada, y no se mezclan**: `factoryTooltip` es
    el hover —efímero, solo lectura, se destruye al salir de la casilla— y `factoryPanel` es el
    panel persistente con controles, que se cierra con `ESC` o click fuera. Mientras el panel vive,
    el tooltip se calla (`Main._update_hover_tooltip()`). Un tooltip con botones dentro **no es
    posible**: al mover el ratón hacia el botón sales de la casilla y el nodo muere.
  - En el panel, **`queue_free()` siempre**, nunca `free()`. Y si hay que liberar y recrear un nodo
    con el mismo nombre en el MISMO frame, `remove_child()` antes: `queue_free()` es diferido y el
    nodo viejo retiene su nombre hasta final de frame, así que el nuevo entra renombrado y quien lo
    busca por nombre no lo encuentra nunca (`Main._hide_factory_tooltip()`).
  - El panel reasigna **workers de uno en uno** moviendo a la vez `Bag.workers_assigned` y
    `factoryData.workers_assigned`. Esa invariante la mantienen también `factoryPlacer.build()` y
    `Main._demolish_at_cell()`: romperla duplica o pierde workers para el resto de la run.
- **`resources/factoryParams.json`** — **definición declarativa de las factorías**: por cada tipo,
  su `material` de salida, `tick` (frecuencia), `recieve` (inputs), `pollution`,
  `workers_needed`, `type` y `synergies` con otras factorías. Para añadir/ajustar una factoría se
  edita este JSON, no el código.
  - **Nueve entradas, y tres son de la SEGUNDA CADENA** *(Plan «Variedad de Factorías», M0,
    2026-09-22)*: `Quarry` (`stone`, tick 5, pollution 4,0, 1 worker, **sin sinergias**), `Foundry`
    (`brick`/`glass`, tick 4, pollution 3,0, 1 worker, `recieve: ["stone"]`, y `WoodProcessing` le
    da `output_bonus: 1`) y `WaterTreatment` (restauración, tick 4, pollution **−7,0**, 1 worker,
    `recieve: ["stone"]` y `requires_adjacent: ["stream", "lake"]`). Precios, más abajo.
    🔴 **De la `WaterTreatment` no hay NINGÚN número medido** —ni `tick`, ni `pollution`, ni
    `cost`—: salía a cero en las ocho filas del último barrido, que solo jugaba la fase de
    producción. Limpia casi el doble que el `Reforester` y se paga con insumo y con un worker, y
    ese contrapeso es **de diseño**. Nadie debe leerlo como calibrado.
  - **`accepts: [...]` es OPCIONAL, y es de un CHECKPOINT, no de una factoría** *(Variedad M0,
    2026-09-22)*: los materiales que ese checkpoint admite **además** del suyo, en una **bolsa
    común** —el objetivo se cierra con la suma—. Mismo contrato que `materials` y `cost`: **su
    ausencia significa «solo el suyo»**. La curva de hoy es `plank` 15 / 25 / 55 (`accepts:
    ["stone"]`) / 100 (`accepts: ["brick"]`) / 170 (`accepts: ["glass"]`), que es lo que hace de la
    segunda cadena una alternativa y no un adorno. Lo leen `gameManager._accepted_materials()` y,
    por él, `_checkpoint_cost()`, `_can_afford()`, `_stock_for_current()` y `_pending_quantity()`;
    el HUD escribe la lista entera con « o » —«Checkpoint 3/5: 40 / 55 plank o stone»—, porque
    enseñar solo el propio dejaría al jugador de piedra viendo un 0 con el almacén lleno.
    🔴 **Lo que un `accepts` NO añade es RESERVA**: el `maintenance` sigue apartándose material
    a material, que es la regla que impide colgar la run.
  - **`materials: [...]` es OPCIONAL** (añadido el 2026-09-17): la lista de materiales entre los
    que esa factoría puede elegir qué fabricar. **Su ausencia significa `[material]`**, así que de
    las NUEVE entradas lo declara **una sola** —la `Foundry`, con su `["brick", "glass"]`, desde el
    M3 del Plan «Variedad de Factorías» (2026-09-22)— y para las otras ocho no cambia nada, incluido
    el `material: null` del `Reforester` y de la `WaterTreatment`, cuyo único candidato es `null`.
    `material` sigue siendo con lo que la factoría se coloca; `materials` solo dice a qué puede
    cambiar después. El fallback vive en
    `factoryData.initialize()` (último parámetro, con default) y no en `factoryPlacer`, para que
    valga también para quien construye factorías a mano (hoy, la suite).
    🔴 **Y todo lo que enumere materiales tiene que leer `materials[]`, no solo `material`**:
    `glass` es el primero que **no es el `material` de ninguna entrada**. Los dos sitios que ya lo
    hacen son `gameManager._factory_materials()` (el rescate, Variedad M2) y
    `ui/factoryPanel._belt_filter_materials()` (el filtro de la cinta de salida, Variedad M3).
  - Cambiar de material (`factoryData.setProduction()`) **NO reinicia el `Timer`, ni su contador
    de ticks, ni `production_debt`**: es un cambio de destino, no una factoría nueva. Si se
    reiniciaran, cambiar de material sería un exploit o un castigo que nadie vería hasta medir el
    balance. `ui/factoryPanel.gd` enseña el desplegable solo cuando hay **más de un** candidato
    (`factoryData.hasMaterialChoice()`). 🔴 **El `Storage` ya NO lo tiene** *(2026-09-23)*: entre el
    2026-09-18 y esa fecha fue el único caso de lista **dinámica** (`refreshStorageCandidates(bag)`,
    recalculada con lo que hubiera en la bolsa), pero **la emisión dejó de elegirse a mano**. Hoy el
    almacén emite por **cada una** de sus cintas de salida lo que el consumidor del otro extremo
    declara en su `recieve` (`factoryData._tick_storage_emit()`), así que no hay nada que elegir y el
    panel pinta «Emite: lo que pidan sus cintas». `refreshStorageCandidates()` ya no existe. Y desde
    el 2026-09-22
    la `Foundry` es el caso **estático**, el que el campo se diseñó para servir: su lista sale del
    JSON y no cambia. 🔴 **Los dos materiales NO valen lo mismo**, y ahí está la decisión: el
    checkpoint 4 acepta `brick` y no `glass`, y el objetivo final acepta `glass` y no `brick`, así
    que la fundición se monta para ladrillo y se pasa a vidrio en el último tramo. Si alguien
    iguala los dos `accepts`, el desplegable se queda con una opción muerta. Las otras siete
    entradas siguen sin desplegable.
  - **`requires_adjacent: [...]` es OPCIONAL** *(Variedad M4, 2026-09-22)*: los tipos de casilla
    de los que ese tipo de factoría necesita **al menos una entre sus 8 vecinas** para poder
    colocarse. Mismo contrato que `materials` y `cost` —**su ausencia significa «ninguno»**—, y de
    las nueve entradas lo declara **una sola**, la `WaterTreatment` con `["stream", "lake"]`. La
    regla vive en `tileMap.canPlaceFactory()`, único punto de verdad, y entra por un **cuarto**
    parámetro con el NOMBRE del tipo (el tercero es la categoría): ver más abajo.
  - **El bloque `Upgrades` y sus tiers**: **13 cartas** — 6 de tier 1 **sin castigo** y **7** de
    tier 2 con `map_downside` graduado **1/1/1/1/2/2/3**. Las diez de siempre se revisaron entrada
    a entrada el 2026-09-20 (M2 del Plan «Catálogo de Mejoras», que no movió ninguna) y las **tres
    `unlock_factory` de la segunda cadena** las añadió el M5 del Plan «Variedad de Factorías» el
    2026-09-22: `unlock_quarry` (2 casillas `toxic`), `unlock_foundry` (1) y `unlock_watertreatment`
    (1), **las tres de tier 2**. Con eso el tier 2 pasa de 4 cartas y **4 manos posibles a 7 y 35**,
    y **el tier 1 NO se mueve**. 🔴 **Ni el tier ni el castigo de esas tres están MEDIDOS**: se
    eligieron por coherencia con la escala que ya existía —desbloquear una cadena entera pesa más
    que un `speed_boost`, y una carta de tier 2 sin castigo está descartada a propósito— y los
    bancos que podrían haberlos medido se borraron el mismo día. Dos cosas que leer el JSON no
    cuenta:
    - 🔴 **La baraja de tier 1 que el jugador ve son 5 cartas, nunca las 6 del JSON.**
      `unlock_woodprocessing` no entra jamás en el reparto: en `standard` la filtra
      `_usable_upgrades()` —ese paquete ya trae la procesadora— y en `lumberjack`/`ecologist` se
      **concede** antes de repartir (`_granted_upgrades()`), así que sale de `pool`. Su `tier` es
      por tanto **inerte**: moverla a tier 2 no cambiaría una sola pantalla —medido en la suite— y
      encima le cobraría un castigo a la única carta que el jugador ni elige ni puede rechazar.
    - Con 5 cartas hay **10 manos posibles** y `_pick_upgrades(3, 1)` las da todas (medido).
      Promover cualquier otra corriente dejaría 4 y la pantalla de la recompensa normal volvería a
      ser el trámite que M2 vino a quitar — y tendría que llevar `map_downside`, porque una carta
      de tier 2 sin castigo está descartada a propósito. Bloque «Catálogo M2» de
      `tests/run_tests.gd`.
    - 🔴 **Y un `unlock_factory` nuevo se cuela por el RESCATE, que no mira el tier.** Lo que
      `_unproducible_materials()` apunta se concede gratis, así que con las tres cartas de la
      segunda cadena dentro, `lumberjack` y `ecologist` llegaban a conceder de golpe **la
      serrería, la cantera Y la fundición** en el checkpoint 1 (medido): falta `plank` en los
      checkpoints 2 a 5, y como el 3 acepta `stone`, el 4 `brick` y el 5 `glass`, los cuatro
      materiales salían por imposibles cuando la serrería sola los cubre todos. Desde Variedad M5
      esa función **cascada**: lo que ya lleva carta apuntada cuenta como producible para los
      checkpoints siguientes. Lo que NO cambia es la decisión de Variedad M2 —cuando el primer
      checkpoint bloqueado acepta dos materiales imposibles se conceden las dos cartas—, y tiene
      su control en el bloque «Variedad M5».

## Economía: construir cuesta material *(2026-09-19)*

Desde el Plan «Costes de Construcción», colocar una factoría y tender cinta **se pagan**. Todo
declarado en `resources/factoryParams.json`, nada hardcodeado:

- **`cost` es OPCIONAL** en cada entrada de `Factories`, un diccionario `material -> cantidad`, y
  **su ausencia significa gratis** — mismo contrato que `materials: [...]`, para que nada que no lo
  declare (ni una prueba) tenga que enterarse de que existe una economía.
  Hoy:
  `WoodCutter` 4 `wood` · `Reforester` 6 · `WoodProcessing` 8 · `MetaFactory` 6 `plank` ·
  `WorkerCamp` 4 `plank` · `Storage` 10 `wood`, y las tres de la segunda cadena (Plan «Variedad de
  Factorías», M0) `Quarry` 8 `stone` · `Foundry` 6 `wood` + 12 `stone` · `WaterTreatment` 4 `wood` +
  8 `stone`. 🔴 **Todos estos precios son PROVISIONALES**: salieron de mediciones defectuosas
  (retiradas el 2026-09-23) y se suponen incorrectos; los de la `WaterTreatment` ni siquiera se
  midieron. Si tocas uno, nada te va a avisar de que se ha desequilibrado.
- **La cinta va en su propio bloque**, `"Belts": { "cost_per_cell": { "wood": 1 } }`, porque no es
  una factoría.
- **`starting_stock` por paquete** en `StartingPackages`, aplicado en `mapLoader.apply_package()`
  junto a `factories`/`extra_workers`/`speed_boosts`: `standard` 40 `wood` + 4 `plank` + **15
  `stone`**, `lumberjack` 50, `ecologist` 36+8. **No es decorado**: el checkpoint 1 cobra sus 15 de
  `wood` en el PRIMER frame, así que con 20 la run nacía sin poder colocar nada. Las cantidades
  son **provisionales** (mediciones defectuosas). Los 15 de `stone` están porque **ningún precio del
  juego se pagaba en `stone`** y una run de piedra acababa con la bolsa llena de un material que no
  compraba nada.

Cuatro reglas que **no se rompen**:

- 🔴 **Se cobra de `bag.getAvailable()`, NUNCA de `getQuantity()`.** Lo que el checkpoint reserva
  para su mantenimiento no se puede gastar en construir, igual que las factorías no se lo pueden
  comer como insumo. Es la regla que impide colgar la run, y tiene pruebas dedicadas.
- 🔴 **`charge_cost` es opt-in.** `factoryPlacer.build(..., charge_cost := false)` y
  `beltNetwork.place_drag(..., bag, charge_cost := false)` solo cobran si se les pasa `true`, y los
  únicos que lo pasan son el gesto del jugador (`Main._on_factory_chosen()` y el arrastre de
  `Main._unhandled_input()`). Por eso el **almacén inicial** que coloca `mapLoader.place_storage()`,
  y la suite construyen sin pagar. Cobrar por defecto le pasaría al
  jugador la factura del almacén del mapa y dejaría sin dinero a decenas de pruebas que no van de
  economía.
- 🔴 **La devolución sale de `factoryData.cost_paid`, un recibo por nodo, y NUNCA del `cost` del
  JSON.** `build()` solo lo rellena cuando ha cobrado de verdad, así que lo colocado gratis devuelve
  `{}`. Si la devolución mirase el precio, demoler el almacén regalado soltaría 5 de `wood` de la
  nada: demoler dejaría de costar para pasar a **imprimir** dinero. Se devuelve `floor(pagado/2)`
  por material, además de los workers.
- **El arrastre es todo o nada también con el dinero**: el precio se calcula sobre el tramo que de
  verdad llevará cinta —`cells.size()`, no `trace_path().size()`, porque los extremos ocupados por
  factoría se recortan— y si no alcanza no se tiende ni una casilla ni se cobra nada.

Lo que **ve el jugador**: el radial pinta el coste por opción —**una línea por material**
desde Variedad M4b— y **atenúa y deshabilita** lo que no
puede pagar (por material: puede faltarle `plank` y sobrarle `wood`); el panel dice lo que
devolvería demoler; y `Main._buildResourceText()` pinta `wood: 5/10 libres` **solo cuando ese
material tiene reserva** — sin ella, la línea es exactamente la de siempre. El número del castigo de
una mejora lo redacta `ui/upgradeScreen._downside_text()` leyendo el mismo `map_downside` del que
cobra `Main._apply_map_downside()`: **no lo escribas a mano en la descripción del JSON** o empezarán
a divergir.

## Flujo de juego

`mainMenu` → `packageSelect` (paquete inicial) → run: colocar factorías, encadenar producción,
controlar contaminación, alcanzar objetivos (`gameManager`) → `upgradeScreen` / `runSummary`.

## Buenos comportamientos en este repo

- **GDScript puro.** `class_name` cuando sea reutilizable, `snake_case` para vars/funciones,
  `PascalCase` para clases, señales para desacoplar.
- **Las factorías se definen en `factoryParams.json`**, no hardcodeadas: respeta ese contrato
  (material/tick/recieve/pollution/synergies).
- **Commits y comentarios en español; identificadores en inglés.**
- **Antes de concluir que el juego hace X, descarta que quien hace X sea tu instrumento.** Este repo
  ha retirado tres jugadores simulados y toda su medición por medir su propia torpeza como si fuera
  del juego. El síntoma clásico: una run que acaba con recursos sin gastar. Hoy no hay instrumento
  (ver «Medición»): una pregunta de **cantidad** no tiene respuesta automática, así que no la
  opines como si la tuviera; una de **diseño** se contesta mirando (`tools/ver_*.gd`).

## Estado / pendiente conocido

Implementado: tilemap isométrico con tipos de casilla, factorías con synergies, bag con workers,
contaminación global y por casilla, meta-progresión entre runs, UI de menús/upgrades/resumen,
objetivos y checkpoints, derrota por punto muerto, red de cintas, economía de construcción y —desde
el 2026-09-22— la **segunda cadena de materiales** (`stone` → `brick`/`glass`) con sus tres
factorías, el `accepts` de los checkpoints, el `requires_adjacent` de la colocación y las 13 cartas
del catálogo.

Pendiente conocido — **léelo antes de asumir que algo funciona**:

- `toxic.restore_to_unlock` (JSON) está declarado y **ningún script lo lee**. (`deliverTo`, el otro
  campo fantasma, se **eliminó** del JSON el 2026-09-17: llevaba 18 meses declarado sin consumirse,
  y el transporte dirigido que llegó el 2026-09-18 **no lo reintrodujo**: el destino lo dice la
  geometría de la red de cintas, no un campo del JSON.)
- Los desbloqueos de paquetes/mapas están hardcodeados en `Main.gd`, no en el JSON.
- ~~`ui/factoryTooltip.gd` pinta «Produce: `<null>`»~~ — **arreglado el 2026-09-17**. La causa: se
  comparaba `str(params.get("material", null))` contra el texto `"null"`, y `str(null)` devuelve
  `"<null>"`. Cuidado con repetirlo en cualquier UI nueva: compara contra `null`, no contra texto.
- El HUD **no enseña** el rendimiento de línea que decide el tier de la recompensa, así que el
  jugador no puede saber por qué le han dado una carta potente.
- El arrastre de cinta **no se previsualiza** mientras mantienes el botón: se tiende a ciegas y solo
  se ve el resultado al soltar. El `BeltOverlay` ya es el sitio donde pintarlo.
- 🔴 **Deuda de MEDICIÓN que dejó el Plan «Variedad de Factorías» (2026-09-22)**, y hay que leerla
  como lo que es: el `tick`, el `pollution` y el `cost` de la **`WaterTreatment` no se midieron
  nunca** —salía a cero en el último barrido—, y el **tier y el `map_downside` de las tres cartas
  nuevas** están **elegidos por coherencia** con la escala que ya existía, no calibrados. Los bancos
  que podrían haberlos medido se borraron ese mismo día, así que **nada va a avisar** si uno de esos
  números está desequilibrado: se re-mide a mano o **se mira jugando** (`tools/ver_*.gd`). 🔴 Toda la medición
  automática se retiró el 2026-09-23 (ver «Medición»), así que estas tres deudas esperan a la
  medición que se rehaga desde cero.

Reglas que **sí** funcionan y conviene no romper (arregladas el 2026-09-17):

- 🔴 **Se puede perder, y la cadena es ahogo → contagio → punto muerto.** La
  contaminación de una casilla ahoga lo que produce la factoría de encima (`factoryData`, solo
  `type: "production"`; las de restauración nunca se ahogan), una casilla saturada desborda sobre
  sus 8 vecinas (`tileMap.tick_contagion()`) y `gameManager._evaluate_deadlock()` declara muerta la
  run cuando durante `DEADLOCK_GRACE` no se produce, nadie limpia y no queda casilla donde
  construir. Las tres a la vez: si una se rompe la cuenta atrás se cancela, así que limpiar es la
  salida. **Desde Costes M7 (2026-09-19) lo es también sobre el mapa saturado**: una casilla
  cerrada por contaminación admite factorías de **restauración** (ver más abajo), así que el
  jugador que reacciona siempre tiene dónde poner el limpiador y puede romper la condición 2.
  Lo que ya no puede es ganarle al contagio **sin gastar**: cubrir el `forest_01` saturado le
  cuesta muchos `Reforester` y bastante tiempo de fase 2 (las cifras de M7 salieron de mediciones
  defectuosas). Quien NO reacciona sigue muriendo exactamente igual: la condición 3 pregunta
  por la regla estricta, así que el mapa abandonado se queda sin casilla construible y colapsa
  como siempre. `Main._start_game()` le inyecta el TileMap al `gameManager` —**sin esa
  línea el evaluador es inerte**— y `_on_run_lost()` abre `runSummary` con `won = false`. Mientras
  la ventana corre, `getObjectiveText()` antepone al HUD el aviso con los segundos que quedan y las
  tres razones, y ese aviso **sustituye a la cola de contaminación** (que el propio aviso ya
  resume) para que la línea quepa — salvo en la fase de restauración, donde la cola es lo único
  que dice el texto y la línea es corta. El aviso **solo lee** `deadlock_timer`, porque el HUD se
  pinta cada frame.
- 🔴 **Las dos constantes de la derrota son PROVISIONALES.** `contagion_rate = 0.12`
  (`pollutionManager.gd`) y `DEADLOCK_GRACE = 25.0` (`gameManager.gd`) salieron de mediciones que
  se hacían mal (retiradas el 2026-09-23) y se suponen incorrectas hasta volver a medirlas. Lo que
  sí vale es su **criterio de diseño**:
  - `contagion_rate`: un mapa abandonado tiene que colapsar dentro de una sentada (con 0,00 la
    derrota es inalcanzable, que es la razón de que el contagio exista) sin que una run jugada con
    cuidado pierda checkpoints por él. **El suelo que se comprueba solo es la suite**: la prueba
    «Derrota M6» exige que un foco sature a una vecina limpia en menos de dos minutos, o sea
    `contagion_pollution / contagion_rate <= 120 s`, que con los 12,5 de hoy pide `rate >= 0,105`.
  - `DEADLOCK_GRACE`: tiene que cubrir lo que tarda la jugada que desatasca en romper una de las
    tres condiciones (el caso más lento es una productora recién colocada sobre casilla a medio
    ahogar) más un margen para que el jugador lea el aviso. El choke 0,10 queda excluido a
    propósito.
  **Si cambias una de las dos**, el razonamiento está en los comentarios de cada una.
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
  mover una regla de colocación. **Y cierra la casilla a la PRODUCCIÓN, no a la limpieza**
  (Costes M7, 2026-09-19): `canPlaceFactory()` deja pasar a las de `type: "restoration"` sobre
  una casilla saturada, que es la misma idea por la que esas factorías no se ahogan —limpiar
  tiene que funcionar siempre—. Sin esa mitad, el suelo muerto era justo el único sitio donde no
  se podía poner el limpiador.
- **`_check_toxic_unlock()` va ANTES de `tick_passive()`** en `Main._tick_world()`. Al revés, el tick
  pasivo suma su +0,5 justo antes de la comprobación y una casilla `toxic` no se desbloquea jamás.
  Y el check exige que la casilla **haya estado sucia**, o una `toxic` virgen se restauraría sola en
  el primer frame.
- 🔴 **Un nodo LIBERADO se compara igual que `null` en GDScript.** `nodo != null` devuelve **false**
  sobre un objeto ya liberado, así que un guardia escrito con `!= null` no lo ve y el nodo muerto se
  cuela por todas las ramas. `is_instance_valid()` es el único que los distingue. Costó un bug
  latente en `Main._update_hover_tooltip()` / `_clear_hover()` (arreglado el 2026-09-20): el hover
  se quedaba apuntando a una factoría liberada con su razón de parada pegada, y ninguna de las tres
  comprobaciones que había lo detectaba.
- **Tres overlays cuelgan del TileMap y su ORDEN es una decisión, no un accidente**: `TintOverlay`
  (`z_index = 1`, color de casilla y contaminación), `BeltOverlay` (2, la red de cintas) y
  `StatusOverlay` (3, el marcador de factoría parada). El estado va el último a propósito: tiene que
  verse aunque cruce una cinta por la casilla. Hay una prueba que fija el orden — sin ella, un
  choque de `z_index` se vuelve a colar en silencio, que es justo lo que pasó al planificarlo.
- **Una factoría parada dice por qué, y lo dice en tres sitios con el mismo color.**
  `factoryData.blocked_reason` tiene cinco valores con prioridad fija — `""` / `workers` / `input` /
  `output` / `choke` — y lo escribe **solo `update()`**, que es donde vive esa prioridad (la única
  excepción es `clearOutputBuffer()`, que borra el `"output"` al desatascar). Lo pintan el
  `StatusOverlay` en el mapa y, en palabras, `ui/factoryTooltip.gd` y `ui/factoryPanel.gd`, los tres
  preguntando por `ui/blockedReason.gd` para que no puedan discrepar. 🔴 **Las dos superficies de
  detalle se repintan solas y tienen que seguir haciéndolo**: el panel por su `_process()` y el
  tooltip también **con el ratón quieto** (`Main._update_hover_tooltip()` compara la razón, no solo
  la factoría bajo el cursor). Una etiqueta estática se queda pegada y contradice al marcador del
  mapa, que sí está vivo.
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
  una, total constante). Es lo que hace recuperable una casilla `toxic`. Vale para **las dos**:
  la `WaterTreatment` reparte igual que el `Reforester`.
- 🔴 **Una restauradora puede quedarse sin INSUMO, y es lo único que la para** *(Variedad M4,
  2026-09-22)*. Hasta entonces `update()` desviaba las de `type: "restoration"` a
  `_tick_restoration()` **sin pasar por `checkNeeds()` ni `consumeNeeds()`**, así que la
  `WaterTreatment` —la primera restauradora con `recieve`— habría limpiado gratis. Ahora escribe
  `"input"` y se para, que es su contrapeso: limpia casi el doble que el `Reforester` y hay que
  alimentarla por cinta. **Lo que NO cambia son las dos reglas de las que cuelga la derrota**: una
  restauradora **nunca se ahoga** (`getPollutionChoke()` la exime, también con insumos) y **nunca
  se bloquea por `"output"`** (no produce material). Para las entradas con `recieve: null` —el
  `Reforester`— no cambia absolutamente nada: `itemNeeded` vacío, `checkNeeds()` true.
- `tileMap.canPlaceFactory(cell, factory_array, factory_kind = "", factory_type = "")` es el **único punto de verdad**
  de «¿cabe aquí?». Desde Costes M7 la respuesta **depende del tipo**: `factory_kind` es la
  categoría del JSON (`production` / `restoration` / `storage`) y la única diferencia que
  introduce es que una **restauradora cabe sobre casilla saturada** y las demás no. El `""` por
  defecto es la regla **estricta** —la de antes de M7— y es la que siguen preguntando
  `hasBuildableCell()` (condición 3 del punto muerto: si preguntara por la permisiva, el mapa
  saturado siempre tendría dónde construir y la derrota sería inalcanzable) y la validación del
  arrastre de cinta (**la cinta no es una factoría**: sobre suelo muerto no lo devuelve). Quien no
  sabe todavía qué se va a colocar —el click que abre el radial— pregunta por
  `canPlaceAnyFactory()`, que delega en la misma función con la categoría más permisiva; y el
  radial ofrece solo lo que cabe en ESA casilla (`Main._show_radial_menu()`).
  🔴 **Y desde Variedad M4 hay un CUARTO parámetro con el NOMBRE del tipo**, del que sale el
  `requires_adjacent`: lo pasan **solo** los dos caminos del gesto de construir
  (`Main._show_radial_menu()` y `Main._on_factory_chosen()`), y **quien no lo pase se comporta
  exactamente como antes** — que es lo que deja intactas la regla estricta de `hasBuildableCell()`
  y la validación del arrastre, las dos colgadas del default `""` del tercero. El JSON de
  factorías se lo inyecta `Main._start_game()` con `setFactoryParams()`, cuarto setter hermano de
  `setPollutionManager()` / `setBeltNetwork()` / `setFactories()`: **sin esa línea la regla es
  inerte**, igual que el evaluador de punto muerto sin su TileMap.

Detalle y planes de arreglo en el Brain (ver arriba).
