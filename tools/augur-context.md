Balactorio es un juego de gestión de factorías + roguelite (Godot). El jugador coloca factorías que encadenan materiales (wood → plank; stone → brick/glass), paga su coste, las une con cintas y controla la contaminación que generan. Una **run** es una partida: empieza con un paquete inicial en un mapa, pasa por checkpoints (objetivos de material) y acaba ganada (`win`), perdida por punto muerto (`lose`) o abandonada (`abandon`: `R` o cerrar la ventana).

**Una sesión de Augur NO es una run.** Una sesión es un arranque del juego y puede contener varias runs (reiniciar es barato). Por eso cada pregunta se contesta con `count`/`avg`/`sum` sobre **un único evento**, casi siempre `run_end` (una fila por run, con el censo completo) o `card_offered` (una fila por carta mostrada). No unas eventos entre sí ni leas embudos o `sessions` como runs. Todos los eventos de run llevan `run_id` (8 hex) y `run_t` (segundos de juego).

**El `n` de las gráficas cuenta sesiones, no filas.** Por eso cada gráfica `avg` va acompañada en su tablero de un `count` del mismo evento con la misma agrupación y filtro: ese es el recuento de verdad. No cites una media sin él.

Eventos:
- `ui_open` — se abre una pantalla (`screen`).
- `run_start` — empieza una run: `package`, `map`, `balance_id` y los valores de balance con los que se juega. Si es una run **continuada** de una guardada, lleva `resumed_from` = el `run_id` de la que se suspendió (desde 2026-10-01): una partida cerrada y retomada son dos runs encadenadas, y sus contadores empiezan en cero en cada trozo.
- `run_end` — acaba una run: `result` (`win`, `lose`, `abandon` = reiniciar con `R` o cerrar sin poder guardar, `suspend` = cerrar la ventana con la run guardada para continuarla; antes del 2026-10-01 cerrar la ventana contaba como `abandon`), `duration_ms`, `checkpoints` cerrados, contaminación final y pico, `built_<Factoría>`, `left_<material>` (sobrante disponible), workers, cartas elegidas, `screen` abierta al acabar, `idle_s`.
- `checkpoint_reached` — se cierra un checkpoint (1-based) con `tier` de la recompensa, `seg_t` y `rate` del tramo.
- `card_offered` — una carta mostrada, elegida o no (`chosen` 0/1), con `slot`, `source` (checkpoint/ruins/token) y `decision_ms`. `avg chosen` = tasa de elección.
- `card_granted` — carta concedida sin elegir (rescate o paquete).
- `deadlock_opened` / `deadlock_closed` — se abre / se cierra la ventana de punto muerto (`secs`, `outcome` recovered/lost).
- `cell_restored` — una casilla tóxica vuelve a ser construible.
- `factory_built` / `factory_demolished` — el jugador construye / demuele una factoría (casilla, tipo, lo pagado / devuelto).
- `belt_placed` / `belt_removed` / `belt_rejected` — tiende / borra / no puede tender cinta (`reason` no_fit/no_money).
- `radial_closed` — se cierra el menú de construcción, construyendo o no (`built` 0/1).
- `build_rejected` — elige una factoría y no se construye (`reason` cell_invalid/no_money).
- `click_rejected` — click en una casilla donde no cabe nada (`tile`, `saturated`).
- `panel_opened` — abre el panel de una factoría (`blocked`: por qué está parada).
- `workers_changed` / `material_selected` / `belt_filter_set` — acciones del panel que se aplican.
- `run_sample` — muestra de estado cada 10 s de juego: contaminación, casillas saturadas y tóxicas, stock, factorías vivas y paradas por motivo (`blocked_storm` = paradas por tormenta), climas vivos (`weather_active`, desde 2026-10-01), `idle_s`, `deadlock_s`.
- `weather_started` — empieza un clima (desde 2026-10-01): `weather` (drought, rain, storm, wind), su zona en casillas (`x`, `y`, `w`, `h`, ya recortada al mapa), `duration` (s), `chance` (probabilidad con la que salía la tirada; crece con el pico de contaminación) y `n_active` (climas vivos contando este). Con el punto muerto abierto no salen climas nuevos.
- `weather_ended` — termina un clima al agotar su duración: `weather` y `n_active` (los que siguen vivos). Una run continuada puede cerrar un clima cuyo inicio está en la run de `resumed_from`.
- `segment_rate` — rendimiento parcial del tramo en curso cada 1 s de juego, solo en la fase de producción y solo cuando hay número: `checkpoint` (el tramo en curso, 1-based: el mismo que llevará el `checkpoint_reached` que lo cierre), `seg_t` (segundos desde que arrancó el tramo) y `rate` (lo producido en el tramo sobre la integral del techo instalado, sin calentamiento). Sirve para ver cuándo se estabiliza el porcentaje frente al `rate` final del tramo.

**Los valores de balance de `run_start` son PROVISIONALES y no están validados** (`contagion_rate`, `deadlock_grace`, `tier2_efficiency`, precios, stock inicial…): no los trates como calibrados ni como argumento para no cambiarlos. Medirlos es precisamente para lo que existen estos datos.

**`balance_id`** es un hash del `factoryParams.json` y de esas constantes: cambia con **cualquier** cambio del JSON (también textos de cartas). Sirve para separar runs jugadas con reglas distintas, no mide cuánto difieren.
