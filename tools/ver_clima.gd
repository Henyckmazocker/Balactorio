extends SceneTree

# Verificación VISUAL del clima (Plan «Eventos Climáticos», M5 —aviso y tintado— y, más
# adelante, M0 —el caso 🔴—). El *Hecho cuando* de M5 es visual: «el jugador ve dónde y qué
# está pasando sin leer nada, y el aviso desaparece de la línea si el deadlock reclama el sitio».
# Eso no lo contesta la suite: se mira.
#
# No es una prueba: no mide nada y no va en la suite. Arranca el juego CON render, fija el mapa,
# fuerza cada evento con `weatherManager.startEvent()` sobre un rectángulo conocido y captura.
#
#   timeout 120 godot-4 --path . --script res://tools/ver_clima.gd     # SIN --headless
#
# Las capturas salen en `res://capturas/clima_*.png` (el snap de Godot no puede escribir en /tmp).
#
# Para M0: el escenario `_riesgo()` es el caso 🔴 del plan —sequía sobre la línea con el mapa
# medio saturado—. Con el argumento de usuario `riesgo_largo` NO se hacen las capturas de M5: se
# monta ese caso sobre una línea cuidada (ver CORTADORAS) y se DEJA CORRER `RIESGO_SEGUNDOS` de
# run a `RIESGO_ESCALA`×, en tres variantes:
#   - «control»: el mismo mapa medio saturado SIN sequía — sin él no se puede decir si una muerte
#     es del clima o del montaje;
#   - «sin»: con sequía y el jugador no hace nada más (el peor caso: nadie reacciona);
#   - «con»: con sequía y reacción mínima, dos Reforester junto a la línea al empezar la sequía.
# Captura cada `RIESGO_CAPTURA_CADA` s (`capturas/clima_riesgo_<variante>_tNNN.png`, y `_fin` si
# muere) y escribe una
# traza por stdout (t, eventos, deadlock_timer, las tres condiciones, contaminación de la línea)
# y al final si la run murió y con qué recursos sin gastar.
#
#   timeout 180 godot-4 --path . --script res://tools/ver_clima.gd -- riesgo_largo
#
# 🔴 Esto MIRA un caso, no mide: una muerte aquí dice «este montaje muere», no «el clima mata».
# Antes de culpar al juego, mira el cierre de la traza: si el conductor tenía madera y casillas
# y no las usó, quien pierde es el conductor (skill ver-el-juego, el precedente del 2026-09-20).

# 🔴 La run guardada de David vive en `user://run.json`, el mismo `user://` que el de este conductor:
# `reset()`, ganar, perder y el autoguardado de cada 20 s lo pisarían o lo borrarían. Se redirige
# ANTES de instanciar Main, igual que la suite (Plan «Serialización de Run»).
const RunSave = preload("res://managers/runSave.gd");

const MAPA = "forest_01";
const PAQUETE = "standard";
const SEMILLA = 20260930;

# Las productoras de la escena: la banda alta de forest_01, la misma que usa ver_cuellos.gd
# (allí se colocan WoodCutter sin problema), lejos del almacén de `storage_cell` [13, 8].
const CELDAS_LINEA = [Vector2i(9, 2), Vector2i(10, 3), Vector2i(12, 2)];

# Zonas conocidas, cada una con el tamaño de su evento en el catálogo (`zone_size`).
const ZONA_SEQUIA = Rect2i(8, 1, 5, 4);
const ZONA_LLUVIA = Rect2i(2, 4, 5, 4);
const ZONA_TORMENTA = Rect2i(8, 1, 4, 3);
const ZONA_VIENTO = Rect2i(1, 1, 6, 5);

# Caso 🔴 dejado correr (M0). Constantes del CONDUCTOR, no del juego.
const RIESGO_SEGUNDOS = 300.0;      # segundos de run que se deja correr cada variante
const RIESGO_ESCALA = 20.0;         # Engine.time_scale (la skill admite hasta ~40× con render)
const RIESGO_TRAZA_CADA = 10.0;     # s de run entre líneas de traza
const RIESGO_CAPTURA_CADA = 100.0;  # s de run entre capturas
# La línea del caso largo NO es la de `_linea()` (tres cortadoras sin cinta, que llenan su búfer
# y se paran: ni producen para el checkpoint ni son una run sana). Es la que dejaría un jugador
# cuidadoso: dos cortadoras con cinta a una serrería, la serrería con cinta al almacén del mapa
# ([13, 8]) y cuatro Reforester cubriendo la línea: uno por cortadora y dos en la serrería (sin
# ellos una cortadora sola satura su propia casilla: ver `tools/ver_cuellos.gd`; con solo dos
# compartidos, la primera versión de este caso ya ahogaba la línea en el calentamiento). La
# línea cae dentro de ZONA_SEQUIA.
const CORTADORAS = [Vector2i(9, 2), Vector2i(9, 4)];
const SERRERIA = Vector2i(11, 3);
const LIMPIADORES_LINEA = [Vector2i(8, 2), Vector2i(8, 4), Vector2i(12, 2), Vector2i(12, 4)];
# Madera que se le da al conductor para montar la línea: lo justo con margen, y no las 500 de
# `_linea()`, para que el cierre de la traza («recursos sin gastar») signifique algo.
const MADERA_LINEA = 100;
# Segundos de run con la línea funcionando ANTES de ensuciar el mapa y soltar la sequía: el caso
# es «una run que iba bien hace treinta segundos».
const RIESGO_CALENTAMIENTO = 30.0;
# Dónde pondría un jugador atento sus dos Reforester de reacción: pegados a la línea, dentro de
# la sequía. Se prueban en orden hasta colocar dos (una casilla puede tener cinta o factoría).
const CELDAS_REACCION = [Vector2i(10, 1), Vector2i(10, 5), Vector2i(8, 1), Vector2i(12, 5), Vector2i(8, 5), Vector2i(12, 1)];

var _hecho = false;

func _process(_delta):
	if _hecho:
		return false;
	_hecho = true;
	RunSave.default_path = "user://ver_run.json";
	_todo();
	return false;

func _todo():
	seed(SEMILLA);
	DirAccess.make_dir_recursive_absolute("res://capturas");
	if "riesgo_largo" in OS.get_cmdline_user_args():
		await _riesgo_largo();
		quit();
		return;

	# 1. Sequía sobre la línea, con suciedad dentro y FUERA de la zona: lo que se mira es que la
	#    zona se distinga del rojo de contaminación de un vistazo.
	var main = await _montar();
	await _linea(main);
	_ensuciar(main, [Vector2i(9, 2), Vector2i(10, 2), Vector2i(4, 7), Vector2i(5, 7), Vector2i(4, 8)], 8.0);
	main.weatherManager.startEvent("drought", ZONA_SEQUIA);
	await _capturar_mapa(main, "res://capturas/clima_sequia.png");
	_soltar(main);

	# 2. Lluvia sobre suelo sucio: el azul encima del rojo.
	main = await _montar();
	_ensuciar(main, [Vector2i(3, 5), Vector2i(4, 5), Vector2i(4, 6), Vector2i(5, 6)], 6.0);
	main.weatherManager.startEvent("rain", ZONA_LLUVIA);
	await _capturar_mapa(main, "res://capturas/clima_lluvia.png");
	_soltar(main);

	# 3. Tormenta sobre la línea: las productoras de dentro tienen que llevar el marcador `storm`
	#    y la de fuera (12, 2) no.
	main = await _montar();
	await _linea(main);
	main.weatherManager.startEvent("storm", ZONA_TORMENTA);
	await _tick_fabricas(main);
	await _capturar_mapa(main, "res://capturas/clima_tormenta.png");
	print("  tormenta — marcadores: %s" % str(_censo(main)));
	# 3b. Y cuando escampa: la zona desaparece y el HUD dice «Tormenta: fin» un rato.
	main.weatherManager.advance(main.weatherManager.active[0].remaining + 0.1);
	await _tick_fabricas(main);
	await _capturar_mapa(main, "res://capturas/clima_fin.png");
	print("  tras la tormenta — marcadores: %s" % str(_censo(main)));
	_soltar(main);

	# 4. Viento: zona grande a la izquierda del mapa.
	main = await _montar();
	_ensuciar(main, [Vector2i(3, 3)], 13.0);
	main.weatherManager.startEvent("wind", ZONA_VIENTO);
	await _capturar_mapa(main, "res://capturas/clima_viento.png");
	_soltar(main);

	# 5. Solape: sequía y tormenta sobre la línea y lluvia al lado, con una esquina compartida.
	#    Tres avisos en el HUD a la vez.
	main = await _montar();
	await _linea(main);
	main.weatherManager.startEvent("drought", ZONA_SEQUIA);
	main.weatherManager.startEvent("rain", Rect2i(5, 3, 5, 4));
	main.weatherManager.startEvent("storm", Rect2i(11, 5, 4, 3));
	await _tick_fabricas(main);
	await _capturar_mapa(main, "res://capturas/clima_solape.png");
	_soltar(main);

	# 6. Punto muerto abierto con clima activo: el plan B 1 suspende el clima, así que NO debe
	#    verse ni la zona ni el aviso; sí el tinte rojo de colapso y el aviso de colapso.
	main = await _montar();
	await _linea(main);
	main.weatherManager.startEvent("drought", ZONA_SEQUIA);
	main.weatherManager.startEvent("rain", ZONA_LLUVIA);
	await _abrir_punto_muerto(main);
	await _capturar_mapa(main, "res://capturas/clima_deadlock.png");
	print("  deadlock — deadlock_timer %.1f, suspendido %s, HUD: %s" % [
		main.gameManager.deadlock_timer, str(main.weatherManager.isSuspended()),
		main.get_node("Objective").text]);
	_soltar(main);

	# 7. El caso 🔴 de M0, solo montado: sequía sobre la línea con el mapa medio saturado
	#    (casillas por debajo del umbral de bloqueo, que la sequía puede empujar por encima).
	main = await _riesgo();
	await _capturar_mapa(main, "res://capturas/clima_riesgo.png");
	_soltar(main);

	print("");
	print("  capturas en res://capturas/clima_*.png");
	quit();

# La línea de la escena: WoodCutter en CELDAS_LINEA, con dinero y gente de sobra (aquí se mira el
# clima, no la economía). Imprime las que no se pudieron colocar para no creerse una foto vacía.
func _linea(main):
	var bag = main.get_node("Player").get_node("Bag");
	bag.addToBag("wood", 500);
	bag.addWorkers(6);
	for celda in CELDAS_LINEA:
		main._on_factory_chosen("WoodCutter", celda);
		if _fab_en(main, celda) == null:
			print("  AVISO: no se pudo colocar WoodCutter en %s" % str(celda));
	await _esperar(3);

# `blocked_reason` lo escribe `update()` y nadie más: se tickea a mano para no esperar el tick
# de 4 s de cada factoría.
func _tick_fabricas(main):
	var bag = main.get_node("Player").get_node("Bag");
	for fab in main.factoryArray:
		if fab != null and is_instance_valid(fab) and fab.factory_type == "production":
			fab.update(bag);
	await _esperar(2);

func _ensuciar(main, celdas, cantidad):
	for c in celdas:
		main.pollutionManager.addPollution(cantidad, c);

# Satura TODO el suelo: sin casilla construible, las productoras ahogadas (no se produce) y sin
# restauradoras (nadie limpia), las tres condiciones a la vez. Se deja correr el juego unos
# frames para que `_evaluate_deadlock()` abra la ventana por su camino real, y unos segundos
# de gracia más para que el tinte de colapso ya se vea.
func _abrir_punto_muerto(main):
	var pm = main.pollutionManager;
	var tope = pm.cell_block_pollution * 2.0;
	for cell in main.get_node("TileMap").get_used_cells(0):
		pm.addPollution(tope, cell);
	await _tick_fabricas(main);
	paused = false;
	Engine.time_scale = 10.0;
	var vueltas = 0;
	while main.gameManager.deadlock_timer <= 0.0 and vueltas < 300:
		await process_frame;
		vueltas += 1;
	# Unos segundos de gracia corrida (a 10×) para que el rojo del colapso se lea.
	var abierta_en = main.gameManager.run_time;
	vueltas = 0;
	while main.gameManager.run_time < abierta_en + 8.0 and vueltas < 600:
		await process_frame;
		vueltas += 1;
	Engine.time_scale = 1.0;
	if main.gameManager.deadlock_timer <= 0.0:
		print("  AVISO: la ventana de punto muerto NO se abrió; la captura no vale");

# El caso 🔴 del plan: la línea puesta, el mapa ensuciado a ~70 % del umbral de bloqueo
# (medio saturado: todavía se construye, pero una emisión ×1,5 lo cruza pronto) y una sequía
# encima de la línea. Aquí solo se monta y se fotografía; M0 lo dejará correr.
func _riesgo():
	var main = await _montar();
	await _linea(main);
	var pm = main.pollutionManager;
	var medio = pm.cell_block_pollution * 0.7;
	var tm = main.get_node("TileMap");
	for cell in tm.get_used_cells(0):
		if cell.x >= 6:   # la mitad derecha, donde está la línea
			pm.addPollution(medio, cell);
	main.weatherManager.startEvent("drought", ZONA_SEQUIA);
	await _tick_fabricas(main);
	return main;

func _censo(main) -> Array:
	var fuera = [];
	for fab in main.factoryArray:
		if fab != null and is_instance_valid(fab) and fab.blocked_reason != "":
			fuera.append("%s%s:%s" % [fab.type, fab.cell_position, fab.blocked_reason]);
	return fuera;

func _fab_en(main, cell):
	for fab in main.factoryArray:
		if fab.cell_position == cell:
			return fab;
	return null;

# El montaje de `tools/ver_dilema.gd`, con su mismo porqué: `pick_map()` es aleatorio, así que el
# mapa se reaplica entero y hay que demoler antes el almacén del mapa descartado. Y el clima
# APAGADO antes de `_start_game()` (`weather_enabled = false`): el manager no tira nunca, así que
# los únicos eventos de la foto son los que este driver arranca con `startEvent()`.
func _montar():
	var main = load("res://Main.tscn").instantiate();
	root.add_child(main);
	var menu = main.get_node_or_null("MainMenu");
	if menu:
		main.remove_child(menu);
		menu.free();
	main.weather_enabled = false;
	main._start_game(PAQUETE);
	var pm = main.pollutionManager;
	pm.total_pollution = 0.0;
	pm.pollution_per_cell.clear();
	pm.peak_pollution = 0.0;
	for fab in main.factoryArray.duplicate():
		main._demolish_at_cell(fab.cell_position);
	var datos = {};
	for m in main.fileData.get("Maps", []):
		if m.get("id", "") == MAPA:
			datos = m;
	main.mapLoader.apply_map(datos, pm, main.get_node("TileMap"), main.fileData, {
		"placer": main.placer,
		"parent": main,
		"player": main.get_node("Player"),
		"bag": main.get_node("Player").get_node("Bag"),
		"factories": main.factoryArray,
		"on_produced": main._on_resource_produced,
	});
	await _esperar(10);
	_cerrar_pantallas(main);
	paused = false;
	await _esperar(3);
	return main;

# Las pantallas NO se buscan por nombre (trampa 1 de la skill ver-el-juego): se identifican por
# su señal.
#
# 🔴 Y al quitarla hay que REANUDAR la run a mano, como hace `Main._on_upgrade_chosen()`: abrirla
# deja `gameManager.active = false`, y con eso el reloj del clima no corre (weatherManager.advance()
# se congela con la run, a propósito) y `_evaluate_deadlock()` no evalúa. La primera versión de
# este driver la quitaba sin reanudar y fotografió una tormenta eterna y un punto muerto que no se
# abría nunca: el checkpoint 1 se cierra solo al arrancar con el paquete estándar.
func _cerrar_pantallas(main):
	var habia = false;
	for hijo in main.get_children():
		if hijo.has_signal("upgrade_chosen"):
			main.remove_child(hijo);
			hijo.queue_free();
			habia = true;
	if habia or not main.gameManager.active:
		main.gameManager.resume_after_upgrade();

func _soltar(main):
	paused = false;
	root.remove_child(main);
	main.free();

func _esperar(frames):
	for i in frames:
		await process_frame;

# Como en ver_cuellos.gd: se DESPAUSA unos frames para que `tileMap._process()` repinte el tinte
# y el StatusOverlay y `Main._process()` reescriba el HUD, y se PAUSA para la foto (si no, la run
# corre y puede abrir la pantalla de mejora encima). `frame_post_draw` antes de `save_png()`, o
# se guarda el frame anterior.
func _capturar_mapa(main, ruta):
	main._close_menus();
	_cerrar_pantallas(main);
	paused = false;
	await _esperar(5);
	paused = true;
	await _esperar(2);
	await RenderingServer.frame_post_draw;
	var img = root.get_texture().get_image();
	img.save_png(ruta);
	print("captura: %s  |  HUD: %s" % [ruta, main.get_node("Objective").text]);
	paused = false;

# ---------- M0: el caso 🔴 dejado correr ----------

func _riesgo_largo():
	# El control va PRIMERO y es el que permite clasificar: mismo montaje y mismo mapa medio
	# saturado SIN sequía. Si el control también muere, la sequía no es la causa.
	var res_ctl = await _correr_riesgo("control", false, false);
	var res_sin = await _correr_riesgo("sin", true, false);
	var res_con = await _correr_riesgo("con", true, true);
	print("");
	print("=== RESUMEN caso 🔴 (%.0f s de run a %.0f×) ===" % [RIESGO_SEGUNDOS, RIESGO_ESCALA]);
	for r in [res_ctl, res_sin, res_con]:
		print("  %s" % r);
	print("  capturas en res://capturas/clima_riesgo_*_t*.png");

# Una variante: la línea cuidada, un calentamiento con el mapa limpio y luego el golpe de
# `_riesgo()` (mitad derecha al 70 % del umbral + sequía
# encima) y a correr. `reaccionar` coloca dos Reforester junto a la línea al empezar la sequía.
# El clima sigue APAGADO (`_montar()`): la única sequía es la provocada, así que lo que pase es
# de ESTE caso y no de una tirada.
func _correr_riesgo(etiqueta: String, sequia: bool, reaccionar: bool) -> String:
	print("");
	print("=== caso 🔴 — %s: %s, %s ===" % [etiqueta, "CON sequía" if sequia else "SIN sequía (control)",
		"con reacción" if reaccionar else "nadie reacciona"]);
	var main = await _montar();
	var gm = main.gameManager;
	var pm = main.pollutionManager;
	var wm = main.weatherManager;
	var tm = main.get_node("TileMap");
	var bag = main.get_node("Player").get_node("Bag");
	await _linea_cuidada(main);
	# Calentamiento: la línea produce sola un rato, con el mapa limpio, antes del golpe.
	Engine.time_scale = RIESGO_ESCALA;
	var t_cal = gm.run_time;
	var v = 0;
	while gm.run_time < t_cal + RIESGO_CALENTAMIENTO and v < 5000:
		v += 1;
		await process_frame;
		_quitar_pantalla(main, gm, -1.0);
	Engine.time_scale = 1.0;
	print("  tras %.0f s de línea sana: plank %d, wood %d, marcadores %s, contaminación %.1f" % [
		RIESGO_CALENTAMIENTO, bag.getQuantity("plank"), bag.getQuantity("wood"), str(_censo(main)),
		pm.total_pollution]);
	# El golpe del caso 🔴: la mitad derecha (la de la línea) SUBIDA HASTA el 70 % del umbral de
	# bloqueo —no sumada: `_riesgo()` suma, y sobre la suciedad que la línea ya lleva eso la
	# dejaba por ENCIMA de 12,5 antes de la sequía, o sea muerta de salida y sin caso que mirar—
	# y una sequía encima de la línea. Las casillas de la línea quedan a 8,75: medio saturadas,
	# ahogo ~70 %, y es la sequía la que tendría que empujarlas por encima.
	var medio = pm.cell_block_pollution * 0.7;
	for cell in tm.get_used_cells(0):
		if cell.x >= 6:
			var falta = medio - float(pm.pollution_per_cell.get(cell, 0.0));
			if falta > 0.0:
				pm.addPollution(falta, cell);
	if sequia:
		wm.startEvent("drought", ZONA_SEQUIA);
	var t0 = gm.run_time;
	var muerte = {"t": -1.0};
	gm.run_lost.connect(func(_stats): muerte["t"] = gm.run_time - t0);

	var colocadas = [];
	if reaccionar:
		for c in CELDAS_REACCION:
			if colocadas.size() >= 2:
				break;
			main._on_factory_chosen("Reforester", c);
			var f = _fab_en(main, c);
			if f != null and f.type == "Reforester":
				colocadas.append(c);
		print("  reacción: Reforester en %s" % str(colocadas));
		if colocadas.size() < 2:
			print("  AVISO: solo se colocaron %d Reforester" % colocadas.size());

	print("  t(s)  | eventos             | deadlock   | c1 sin prod | c2 sin limpiar | c3 sin casilla | contaminación (bruta) de %s | total | plank" % str(_celdas_linea()));
	var prev_pend = gm._pending_quantity(bag);
	var prev_total = pm.total_pollution;
	var prox_traza = 0.0;
	var prox_captura = 0.0;
	var suspendido_antes = false;
	var ventanas = 0;
	var dl_antes = 0.0;
	var pantallas = 0;
	Engine.time_scale = RIESGO_ESCALA;
	paused = false;
	var vueltas = 0;
	# Techo de vueltas: a ~60 fps y 20× sobran de largo para 150 s de run.
	while vueltas < 20000:
		vueltas += 1;
		await process_frame;
		var t = gm.run_time - t0;
		# El checkpoint puede abrir su pantalla de mejora: el jugador simulado no elige carta
		# (una carta trae `map_downside` y ensuciaría el caso); se quita y se reanuda la run.
		if muerte["t"] < 0.0 and _quitar_pantalla(main, gm, t):
			pantallas += 1;
		# Plan B 1: anotar cuándo el clima se suspende por la ventana de punto muerto.
		var susp = wm.isSuspended();
		if susp != suspendido_antes:
			print("  [t=%6.1f] clima %s (plan B 1, deadlock_timer %.1f)" % [
				t, "SUSPENDIDO" if susp else "reanudado", gm.deadlock_timer]);
			suspendido_antes = susp;
		if gm.deadlock_timer > 0.0 and dl_antes <= 0.0:
			ventanas += 1;
			print("  [t=%6.1f] se ABRE la ventana de punto muerto" % t);
		elif gm.deadlock_timer <= 0.0 and dl_antes > 0.0 and muerte["t"] < 0.0:
			print("  [t=%6.1f] se CIERRA la ventana (tras %.1f s)" % [t, gm.run_time - dl_antes]);
		dl_antes = gm.deadlock_timer;
		if muerte["t"] >= 0.0:
			break;
		if t >= prox_traza:
			prox_traza += RIESGO_TRAZA_CADA;
			# Las condiciones, vistas entre dos líneas de traza (el gameManager las mira frame a
			# frame; esto es su resumen, no su evaluación).
			var pend = gm._pending_quantity(bag);
			var c1 = pend <= prev_pend;
			var c2 = pm.total_pollution >= prev_total - 0.0001;
			var c3 = not tm.hasBuildableCell(main.factoryArray);
			prev_pend = pend;
			prev_total = pm.total_pollution;
			var evs = [];
			for ev in wm.active:
				evs.append("%s %.0fs" % [ev.id, ev.remaining]);
			var linea = [];
			for c in _celdas_linea():
				linea.append("%.1f" % float(pm.pollution_per_cell.get(c, 0.0)));
			var dl = "cerrada";
			if gm.deadlock_timer > 0.0:
				dl = "%.1f/%.0f" % [gm.run_time - gm.deadlock_timer, gm.DEADLOCK_GRACE];
			print("  %6.1f | %-19s | %-10s | %-11s | %-14s | %-14s | %s | %.0f | %d" % [
				t, ", ".join(evs) if not evs.is_empty() else "-", dl, "SÍ" if c1 else "no",
				"SÍ" if c2 else "no", "SÍ" if c3 else "no",  " ".join(linea), pm.total_pollution, bag.getQuantity("plank")]);
		if t >= prox_captura:
			prox_captura += RIESGO_CAPTURA_CADA;
			var escala = Engine.time_scale;
			Engine.time_scale = 1.0;
			await _capturar_mapa(main, "res://capturas/clima_riesgo_%s_t%03d.png" % [etiqueta, int(round(t))]);
			Engine.time_scale = escala;
		# Al acabar el tiempo se para, SALVO con la ventana de punto muerto abierta: entonces se
		# deja terminar (muerte o cierre) para no cortar el desenlace.
		if t >= RIESGO_SEGUNDOS and (gm.deadlock_timer <= 0.0 or t >= RIESGO_SEGUNDOS + gm.DEADLOCK_GRACE + 5.0):
			break;
	Engine.time_scale = 1.0;
	var t_fin = gm.run_time - t0;
	if muerte["t"] >= 0.0:
		await _capturar_mapa(main, "res://capturas/clima_riesgo_%s_fin.png" % etiqueta);

	# El cierre que separa «el juego mata» de «el conductor no jugó»: qué le quedaba por gastar.
	var bloqueadas = 0;
	for c in tm.get_used_cells(0):
		if float(pm.pollution_per_cell.get(c, 0.0)) >= pm.cell_block_pollution:
			bloqueadas += 1;
	var censo = _censo(main);
	var murio = muerte["t"] >= 0.0;
	print("  --- cierre (%s) ---" % etiqueta);
	print("  %s" % ("MUERE en t=%.1f s" % muerte["t"] if murio else "NO muere en %.1f s de run" % t_fin));
	print("  ventanas de punto muerto abiertas: %d; pantallas de mejora quitadas: %d" % [ventanas, pantallas]);
	print("  bolsa: wood %d disponible %d, plank %d, workers libres %d" % [
		bag.getQuantity("wood"), bag.getAvailable("wood"),
		bag.getQuantity("plank"), bag.getFreeWorkers()]);
	print("  casillas saturadas (>= %.1f): %d de %d; ¿queda casilla construible?: %s" % [
		pm.cell_block_pollution, bloqueadas, tm.get_used_cells(0).size(),
		str(tm.hasBuildableCell(main.factoryArray))]);
	print("  marcadores de bloqueo: %s" % str(censo));
	print("  checkpoint %d, contaminación total %.0f, pico %.0f" % [
		gm.current_checkpoint_index, pm.total_pollution, pm.peak_pollution]);
	var resumen = "%-7s: %s; ventanas %d; wood %d; saturadas %d/%d" % [
		etiqueta, ("MUERE t=%.1f" % muerte["t"]) if murio else "vive %.0f s" % t_fin, ventanas,
		bag.getQuantity("wood"), bloqueadas, tm.get_used_cells(0).size()];
	_soltar(main);
	return resumen;

func _celdas_linea() -> Array:
	return CORTADORAS + [SERRERIA];

# La línea cuidada (ver CORTADORAS). Avisa de todo lo que no se pudo colocar o tender: una línea
# a medio montar no es el caso 🔴, es otra cosa.
func _linea_cuidada(main):
	var bag = main.get_node("Player").get_node("Bag");
	bag.addToBag("wood", MADERA_LINEA);
	bag.addWorkers(2);
	for c in CORTADORAS:
		main._on_factory_chosen("WoodCutter", c);
	main._on_factory_chosen("WoodProcessing", SERRERIA);
	for c in LIMPIADORES_LINEA:
		main._on_factory_chosen("Reforester", c);
	for c in CORTADORAS + [SERRERIA] + LIMPIADORES_LINEA:
		if _fab_en(main, c) == null:
			print("  AVISO: no se pudo colocar la factoría de %s" % str(c));
	var almacen = null;
	for fab in main.factoryArray:
		if fab.factory_type == "storage":
			almacen = fab;
	for c in CORTADORAS:
		if main.beltNetwork.place_drag(c, SERRERIA, main.factoryArray, bag, true).is_empty():
			print("  AVISO: no se pudo tender la cinta %s -> %s" % [str(c), str(SERRERIA)]);
	if almacen == null or main.beltNetwork.place_drag(
			SERRERIA, almacen.cell_position, main.factoryArray, bag, true).is_empty():
		print("  AVISO: no se pudo tender la cinta de la serrería al almacén");
	print("  línea cuidada montada: %d factorías, wood restante %d, workers libres %d" % [
		main.factoryArray.size(), bag.getQuantity("wood"), bag.getFreeWorkers()]);
	await _esperar(3);

# Si el checkpoint abrió su pantalla de mejora, la quita SIN elegir carta (una carta trae
# `map_downside` y ensuciaría el caso) y reanuda la run. Devuelve si había pantalla.
func _quitar_pantalla(main, gm, t) -> bool:
	var hay = false;
	for hijo in main.get_children():
		if hijo.has_signal("upgrade_chosen") and hijo.is_inside_tree():
			hay = true;
	if hay:
		print("  [t=%6.1f] checkpoint %d alcanzado: pantalla de mejora quitada sin elegir carta" % [
			t, gm.current_checkpoint_index]);
		_cerrar_pantallas(main);
		paused = false;
	return hay;
