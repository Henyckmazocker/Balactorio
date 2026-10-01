extends SceneTree

# Suite de pruebas de Balactorio. Cubre las mecánicas saneadas en el
# Plan - Saneamiento de Mecánicas (M1-M6), el M0.5 del Plan - Tensión del Loop Roguelite
# (limpiar sobre casillas limpias no cuenta), su M1 (memoria de contaminación, umbral
# escalado, limpieza en área de los tiles y focos de partida), su M2 (catálogo de mejoras,
# filtrado por tier y evaluación de rendimiento), su M3 (downside de mapa y recuperación de
# una casilla degradada), su M3.5 (el tinte de casilla sale por un canvas item propio y llega
# a pantalla), su M4 (mantenimiento de los checkpoints, curva creciente y el material
# acumulado que no debe inflar el ritmo del tramo), su M5 (la carta que desatasca la run no
# depende de la suerte), su M6 (la bolsa reserva el peaje del checkpoint, así que ninguna
# mejora puede dejar la run sin salida), su M7 (el tier se juzga contra el techo de la línea
# instalada, así que discrimina cómo se juega en vez de premiar a todo el mundo), su M9 (el
# radial anticipa, sin aplicar nada, las sinergias que daría construir en esa casilla) y una
# regresión de las factorías de producción.
#
#   godot-4 --headless --path . --script res://tests/run_tests.gd
#
# Sale con código 0 si todo pasa y 1 si algo falla, así que sirve tal cual en un hook o en CI.
# No forma parte del juego: nada de res://tests/ se instancia desde Main.tscn.

var _passed = 0;
var _failed = 0;
var _fails = [];

class StubTileMap:
	var defs = {};
	func getCellTypeDef(cell):
		return defs.get(cell, {});

# Lo único que gameManager le pide al Player es su lista de factorías disponibles.
class StubPlayer:
	var availableFactories = [];

# Lo único que tileMap.canPlaceFactory() le pregunta a la red de cintas es si hay cinta en
# una celda (condición 5). El doble evita montar la red entera —que necesita su TileMap y su
# árbol— cuando lo que se prueba es la regla de colocación y no el transporte.
class StubBeltNetwork:
	var cells = {};
	func has_belt(cell):
		return cells.has(cell);

# Doble del canvas item sobre el que pinta tileMap.draw_tints(): apunta cada diamante en vez
# de dibujarlo, así que se puede afirmar QUÉ se tiñe y en qué orden sin mirar una captura.
class SpyCanvas:
	var polys = [];
	var lines = [];
	func draw_colored_polygon(puntos, color):
		polys.append({ "puntos": puntos, "color": color });
	# Las cintas pintan además una polilínea (entrada -> centro -> salida), así que el doble
	# la apunta igual que los polígonos: sin ella no se podría afirmar que la orientación se
	# dibuja.
	func draw_polyline(puntos, color, ancho = 1.0):
		lines.append({ "puntos": puntos, "color": color, "ancho": ancho });

# saveManager de verdad —su lógica de progresión entera— que no escribe: cuenta los save() en vez
# de abrir user://save.json. Ganar en la suite con el saveManager real pisaría la meta-progresión
# de David; con este, la huella del fichero real tiene que seguir quieta y se puede afirmar
# igualmente que ganar registró la run.
class SaveSinDisco extends "res://managers/saveManager.gd":
	var guardados = 0;
	func save():
		guardados += 1;

var _hecho = false;
# Serialización M3: el run.json REAL al empezar la suite, para afirmar al final que ninguna
# prueba lo ha creado, pisado ni borrado.
var _run_real_huella_inicial = "";

# Los tests corren en el primer frame, no en _initialize(): ahí el `root` todavía no está
# montado y los nodos que se le añaden no quedan dentro del árbol, así que
# factoryData._apply_pollution() no encontraría el PollutionManager.
# Devuelve FALSE: quien decide cuándo se sale es el `quit()` del final de `_ejecutar()`.
func _process(_delta):
	if _hecho:
		return false;
	_hecho = true;
	_ejecutar();
	return false;

func _ejecutar():
	# 🔴 LO PRIMERO, antes de que ninguna prueba construya un Main: todo runSave nace apuntando
	# al fichero de pruebas. Main toma su `path` de esta estática al construirse, así que ni las
	# pruebas viejas que pasan por reset() saben nada de esto ni lo necesitan (Serialización M3).
	var run_save_script = load("res://managers/runSave.gd");
	_run_real_huella_inicial = _huella_de(run_save_script.RUN_PATH);
	run_save_script.default_path = "user://test_run.json";
	print("");
	print("=== Balactorio — pruebas de M1..M6 + M0.5 + Tensión M1/M2/M3/M3.5/M4 + Cintas M1/M2/M3/M4/M5/M7 + Cuellos M1/M2/M3/M4/M5 ===");
	print("");
	var file_data = JSON.parse_string(FileAccess.get_file_as_string("resources/factoryParams.json"));
	if file_data == null:
		print("FATAL: no se pudo leer resources/factoryParams.json");
		quit(2);
		return;
	_augur_huella_inicial = _huella_augur();

	_test_m1_delta();
	_test_m2_json(file_data);
	_test_m2_efecto(file_data);
	_test_m3_fertile();
	_test_m05_aire();
	_test_m05_reparto_inicial(file_data);
	_test_tm1_pico();
	_test_tm1_umbral();
	_test_tm1_bloqueo_celda();
	_test_tm1_tiles_en_area();
	_test_tm1_focos(file_data);
	_test_tm2_catalogo(file_data);
	_test_tm2_tier(file_data);
	_test_tm2_ya_desbloqueadas(file_data);
	_test_tm2_rendimiento(file_data);
	_test_tm3_downside(file_data);
	_test_tm3_desbloqueo(file_data);
	_test_tm35_tinte(file_data);
	_test_tm4_curva(file_data);
	_test_tm4_mantenimiento(file_data);
	_test_tm4_acumulado(file_data);
	_test_tm5_rescate(file_data);
	_test_tm6_reserva(file_data);
	_test_tm6_no_cuelga(file_data);
	_test_tm7_linea(file_data);
	_test_tm8_cabos(file_data);
	_test_tm9_preview(file_data);
	_test_cd1_ahogo(file_data);
	_test_cd2_contagio(file_data);
	_test_cd3_derrota(file_data);
	_test_cd4_ciclo(file_data);
	_test_cd5_aviso(file_data);
	_test_cd6_constantes(file_data);
	_test_cd7_hud(file_data);
	_test_m5_reparto();
	_test_m4_colocacion();
	_test_m6_revertir(file_data);
	_test_m6_conserva_tile(file_data);
	_test_ui_m1_workers(file_data);
	_test_ui_m2_materiales(file_data);
	_test_ui_m3_tooltip(file_data);
	_test_cintas_m1(file_data);
	_test_cintas_m2(file_data);
	_test_cintas_m3(file_data);
	_test_cintas_m4(file_data);
	_test_cintas_m5(file_data);
	_test_cintas_m7(file_data);
	_test_costes_m1(file_data);
	_test_costes_m2(file_data);
	_test_costes_m3(file_data);
	_test_costes_m4(file_data);
	_test_costes_m5(file_data);
	_test_costes_m5b(file_data);
	_test_costes_m5c(file_data);
	_test_costes_m6b(file_data);
	_test_catalogo_m2_tiers(file_data);
	_test_variedad_m0_accepts(file_data);
	_test_variedad_m1_cantera(file_data);
	_test_variedad_m2_rescate(file_data);
	_test_variedad_m3_fundicion(file_data);
	_test_variedad_m4_depuradora(file_data);
	_test_variedad_m4b_legibilidad(file_data);
	_test_variedad_m5_catalogo(file_data);
	_test_rendimiento_m0b(file_data);
	_test_cuellos_m1(file_data);
	_test_cuellos_m2(file_data);
	_test_cuellos_m3(file_data);
	_test_cuellos_m4(file_data);
	_test_cuellos_m5_guardia(file_data);
	_test_regresion_produccion();
	_test_legibilidad_m1(file_data);
	_test_legibilidad_m2(file_data);
	_test_analitica_m1(file_data);
	_test_analitica_m2(file_data);
	_test_analitica_m3(file_data);
	_test_analitica_m4(file_data);
	_test_legibilidad_m0(file_data);
	_test_legibilidad_m3(file_data);
	_test_legibilidad_m4(file_data);
	_test_consentimiento_m1();
	_test_analitica_m1_sin_clave();
	_test_clima_m1(file_data);
	_test_clima_m2(file_data);
	_test_clima_m3(file_data);
	_test_clima_m4(file_data);
	_test_clima_m5(file_data);
	_test_clima_m0(file_data);
	_test_clima_m6(file_data);
	_test_clima_analitica(file_data);
	_test_serializacion_m1(file_data);
	_test_serializacion_m2(file_data);
	_test_serializacion_m3(file_data);
	_test_serializacion_m4(file_data);
	_test_serializacion_m5(file_data);

	# La guardia de Serialización M3, después de TODAS las pruebas: la run guardada de David
	# sigue exactamente como estaba (o sigue sin existir).
	_check("Serialización M3: la suite no ha tocado el user://run.json real",
		_huella_de(run_save_script.RUN_PATH) == _run_real_huella_inicial, "la huella cambió");

	print("");
	print("=== %d OK, %d FALLO ===" % [_passed, _failed]);
	for f in _fails:
		print("  FALLO: " + f);
	print("");
	quit(1 if _failed > 0 else 0);

# ---------- utilidades ----------

func _check(nombre, cond, detalle = ""):
	if cond:
		_passed += 1;
		print("  OK    " + nombre);
	else:
		_failed += 1;
		_fails.append(nombre + ("  — " + detalle if detalle != "" else ""));
		print("  FALLO " + nombre + ("  — " + detalle if detalle != "" else ""));

func _near(a, b, eps = 0.0001):
	return abs(a - b) < eps;

func _new_pm():
	var pm = load("res://managers/pollutionManager.gd").new();
	pm.name = "PollutionManager";
	return pm;

func _new_tilemap_script():
	return load("res://entities/tilemap/tileMap.gd").new();

# Factoría suelta (sin escena): sirve para la aritmética de sinergias.
func _new_factory(tipo, celda):
	var f = load("res://entities/factory/factoryData.gd").new();
	f.type = tipo;
	f.cell_position = celda;
	return f;

# Factoría productora ya inicializada: tiene `production`, `tickTimer` y `outputAmount`, que
# es lo que mira gameManager._installed_rate() para calcular el techo de la línea.
func _new_productora(tipo, material, tick, output = 1):
	var f = load("res://entities/factory/factoryData.gd").new();
	f.type = tipo;
	f.initialize(tipo, tick, null, material, output);
	return f;

# Factoría en el árbol y con AnimatedSprite2D, para los caminos que aplican contaminación.
func _new_factory_en_arbol(tipo, celda, pm):
	var f = _new_factory(tipo, celda);
	var spr = AnimatedSprite2D.new();
	spr.name = "AnimatedSprite2D";
	spr.sprite_frames = SpriteFrames.new();
	f.add_child(spr);
	root.add_child(pm);
	root.add_child(f);
	return f;

# Siembra `cantidad` de contaminación en las 9 casillas del área de un Reforester.
func _ensuciar_area(pm, centro, cantidad):
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			pm.addPollution(cantidad, centro + Vector2i(dx, dy));

# gameManager suelto (no necesita árbol: el tramo se mide en update(), no en _process).
# `checkpoints` permite montar una curva a medida sin tocar el JSON.
func _new_gm(fd, checkpoints = null):
	var gm = load("res://managers/gameManager.gd").new();
	gm.name = "GameManager";
	var datos = fd.duplicate();
	if checkpoints != null:
		datos["Checkpoints"] = checkpoints;
	gm.initialize(datos);
	return gm;

func _new_bag():
	return load("res://entities/player/Bag.gd").new();

func _todas_de_tier(catalogo, ids, tier):
	for id in ids:
		if int(catalogo[id].get("tier", 1)) != tier:
			return false;
	return true;

func _sin_repetidas(ids):
	var vistas = {};
	for id in ids:
		if vistas.has(id):
			return false;
		vistas[id] = true;
	return true;

func _mapa_por_id(fd, map_id):
	for m in fd.get("Maps", []):
		if m.get("id", "") == map_id:
			return m;
	return {};

func _limpiar(nodos):
	for n in nodos:
		if n.get_parent() != null:
			n.get_parent().remove_child(n);
		n.free();

# Main con lo justo para probar el downside y el desbloqueo: su TileMap y su Player. NO se
# monta en el árbol a propósito — Main._ready() levantaría el menú principal entero—, y nada
# de lo que se prueba con él lo necesita: _apply_upgrade() y _tick_world() trabajan sobre
# nodos hijos y sobre el pollutionManager que se les inyecta.
func _new_main_de_prueba(file_data):
	var main = load("res://Main.gd").new();
	main.name = "Main";
	main.fileData = file_data;
	var tm = load("res://entities/tilemap/tile_map.tscn").instantiate();
	tm.name = "TileMap";
	tm.tile_type_data = file_data["TileTypes"];
	main.add_child(tm);
	var jugador = load("res://entities/player/player.tscn").instantiate();
	jugador.name = "Player";
	main.add_child(jugador);
	return main;

func _celdas_de_tipo(tm, ttype):
	var cells = [];
	for cell in tm.cell_types:
		if tm.cell_types[cell] == ttype:
			cells.append(cell);
	return cells;

# ---------- M1: el tick pasivo se escala por delta ----------

func _test_m1_delta():
	print("M1 — tick pasivo escalado por delta");
	var tm = _new_tilemap_script();
	tm.cell_types = { Vector2i(0, 0): "lake" };
	tm.tile_type_data = { "lake": { "passive_pollution_per_tick": -0.5 } };

	# La suciedad se siembra en las NUEVE casillas del área: desde M0.5 el global solo baja
	# lo que se quita de una casilla, y desde Tensión-M1 un tile limpiador reparte su efecto
	# entre su celda y sus 8 vecinas. Lo que se mide aquí es el escalado por delta, así que
	# el área llega saturada para que el tope por casilla no se meta en medio.
	var pm = _new_pm();
	_ensuciar_area(pm, Vector2i(0, 0), 10.0);
	tm.tick_passive(pm, 1.0);
	_check("un segundo de lake limpia 0.5", _near(pm.total_pollution, 90.0 - 0.5),
		"esperado %f, obtenido %f" % [89.5, pm.total_pollution]);

	var pm2 = _new_pm();
	_ensuciar_area(pm2, Vector2i(0, 0), 10.0);
	tm.tick_passive(pm2, 1.0 / 60.0);
	_check("un frame a 60fps limpia 1/60 de eso", _near(pm2.total_pollution, 90.0 - 0.5 / 60.0),
		"esperado %f, obtenido %f" % [90.0 - 0.5 / 60.0, pm2.total_pollution]);

	# 60 frames deben equivaler a 1 segundo (es el bug original: antes equivalían a 60).
	var pm3 = _new_pm();
	_ensuciar_area(pm3, Vector2i(0, 0), 10.0);
	for i in range(60):
		tm.tick_passive(pm3, 1.0 / 60.0);
	_check("60 frames == 1 segundo", _near(pm3.total_pollution, 89.5, 0.001),
		"esperado 89.5, obtenido %f" % pm3.total_pollution);

	var tox = _new_tilemap_script();
	tox.cell_types = { Vector2i(3, 3): "toxic" };
	tox.tile_type_data = { "toxic": { "passive_pollution_per_tick": 0.5 } };
	var pm4 = _new_pm();
	tox.tick_passive(pm4, 2.0);
	_check("toxic ensucia +0.5/s en su celda", _near(pm4.pollution_per_cell[Vector2i(3, 3)], 1.0),
		"esperado 1.0, obtenido %f" % pm4.pollution_per_cell.get(Vector2i(3, 3), -1.0));

	_limpiar([tm, tox, pm, pm2, pm3, pm4]);

# ---------- M2: signos y destinatarios en el JSON ----------

func _test_m2_json(fd):
	print("M2 — datos del JSON");
	var f = fd["Factories"];
	_check("WoodCutter->WoodProcessing tick_bonus = +1",
		f["WoodCutter"]["synergies"].get("WoodProcessing", {}).get("tick_bonus", 0) == 1);
	_check("MetaFactory->WoodProcessing tick_bonus = +2",
		f["MetaFactory"]["synergies"].get("WoodProcessing", {}).get("tick_bonus", 0) == 2);
	_check("pollution_mult ya NO cuelga de WoodCutter->Reforester",
		not f["WoodCutter"]["synergies"].has("Reforester"));
	_check("Reforester->WoodCutter pollution_mult = 0.5",
		_near(f["Reforester"]["synergies"].get("WoodCutter", {}).get("pollution_mult", -1.0), 0.5));
	_check("Reforester->Reforester pollution_mult > 1 (potencia, no recorta)",
		f["Reforester"]["synergies"].get("Reforester", {}).get("pollution_mult", 0.0) > 1.0);
	# La convención de signo debe ser la misma que la de los TileTypes.
	_check("stream sigue con tick_bonus positivo (misma convención)",
		fd["TileTypes"]["stream"]["adjacency_bonus"]["*"]["tick_bonus"] > 0);

# ---------- M2: el efecto real sobre el tick ----------

func _test_m2_efecto(fd):
	print("M2 — efecto sobre el tick efectivo");
	var placer = load("res://entities/factory/factoryPlacer.gd").new();
	var arr = [];
	placer.initialize(null, fd, arr);

	var wp = _new_factory("WoodProcessing", Vector2i(2, 1));
	wp.tickTimer = int(fd["Factories"]["WoodProcessing"]["tick"]);
	var wc = _new_factory("WoodCutter", Vector2i(1, 1));
	arr.append(wc);
	arr.append(wp);

	var stub = StubTileMap.new();
	placer.recompute_synergies(wp, stub);
	_check("WoodProcessing junto a WoodCutter ACELERA (3 -> 2)", wp.getEffectiveTick() == 2,
		"tick efectivo = %d" % wp.getEffectiveTick());

	var ref = _new_factory("Reforester", Vector2i(5, 5));
	ref.pollutionAmount = float(fd["Factories"]["Reforester"]["pollution"]);
	var ref2 = _new_factory("Reforester", Vector2i(6, 5));
	var arr2 = [ref, ref2];
	placer.initialize(null, fd, arr2);
	placer.recompute_synergies(ref, stub);
	_check("dos Reforester adyacentes restauran MÁS que uno solo",
		ref.getEffectivePollution() < -4.0,
		"contaminación efectiva = %f (base -4.0)" % ref.getEffectivePollution());

	_limpiar([placer, wp, wc, ref, ref2]);

# ---------- M3: fertile tiene efecto ----------

func _test_m3_fertile():
	print("M3 — fertile escala la restauración");
	var pm = _new_pm();
	# Las nueve casillas del área llegan sucias: lo que se mide aquí es la escala del
	# output, no el tope por casilla que introdujo M0.5.
	_ensuciar_area(pm, Vector2i(4, 4), 5.0);
	var f = _new_factory_en_arbol("Reforester", Vector2i(4, 4), pm);
	f.factory_type = "restoration";
	f.pollutionAmount = -4.0;
	f.outputAmount = 1;

	_check("sin bonus, escala 1", f.getRestorationScale() == 1);
	f.synergy_output_bonus = 2;   # lo que concede la casilla fertile
	_check("con fertile (output_bonus 2), escala 3", f.getRestorationScale() == 3,
		"escala = %d" % f.getRestorationScale());

	var antes = pm.total_pollution;
	f._tick_restoration();
	_check("un Reforester sobre fertile limpia 12.0 y no 4.0",
		_near(antes - pm.total_pollution, 12.0),
		"limpió %f" % (antes - pm.total_pollution));

	_limpiar([f, pm]);

# ---------- M0.5: limpiar aire no cuenta ----------

func _test_m05_aire():
	print("M0.5 — limpiar sobre casillas limpias no baja el global");
	var pm = _new_pm();
	var propia = Vector2i(5, 5);
	var lejana = Vector2i(12, 1);
	pm.addPollution(1.0, propia);
	pm.addPollution(50.0, lejana);   # suciedad real, pero fuera del área del Reforester
	var total_antes = pm.total_pollution;

	var f = _new_factory_en_arbol("Reforester", propia, pm);
	f.factory_type = "restoration";
	f.pollutionAmount = -9.0;        # 1.0 por casilla del área
	f._apply_pollution(1.0);

	_check("el global baja SOLO el 1.0 de su propia casilla",
		_near(total_antes - pm.total_pollution, 1.0),
		"bajó %f (esperado 1.0)" % (total_antes - pm.total_pollution));
	_check("su casilla queda limpia", _near(pm.pollution_per_cell[propia], 0.0),
		"quedó %f" % pm.pollution_per_cell[propia]);
	_check("la suciedad que no cubre sigue intacta", _near(pm.pollution_per_cell[lejana], 50.0),
		"quedó %f" % pm.pollution_per_cell[lejana]);

	# Un segundo tick sobre el área ya limpia no acerca la victoria ni un punto.
	var tras_primero = pm.total_pollution;
	f._apply_pollution(1.0);
	_check("un tick sobre área ya limpia no mueve el global",
		_near(tras_primero - pm.total_pollution, 0.0),
		"bajó %f" % (tras_primero - pm.total_pollution));

	_limpiar([f, pm]);

func _test_m05_reparto_inicial(fd):
	print("M0.5 — la contaminación de partida vive en casillas");
	var escena = load("res://entities/tilemap/tile_map.tscn");
	if escena == null:
		_check("tile_map.tscn cargable", false, "no se pudo cargar la escena");
		return;
	var tm = escena.instantiate();
	root.add_child(tm);
	var loader = load("res://managers/mapLoader.gd").new();
	var pm = _new_pm();
	var mapa = _mapa_por_id(fd, "wasteland_01");
	loader.apply_map(mapa, pm, tm, fd);

	_check("wasteland_01 arranca con su pollution_start (20.0) en el global",
		_near(pm.total_pollution, 20.0, 0.01), "global = %f" % pm.total_pollution);
	var suma = 0.0;
	for c in pm.pollution_per_cell:
		suma += pm.pollution_per_cell[c];
	_check("y ese global está entero en las casillas (nada en el aire)",
		_near(suma, pm.total_pollution, 0.01),
		"celdas suman %f, global %f" % [suma, pm.total_pollution]);
	var todas_reales = true;
	for c in pm.pollution_per_cell:
		if tm.get_cell_source_id(0, c) == -1:
			todas_reales = false;
	_check("todas las casillas sucias existen en el suelo del mapa", todas_reales);
	var ninguna_bloqueada = true;
	for c in pm.pollution_per_cell:
		if tm.isCellBlocked(c):
			ninguna_bloqueada = false;
	_check("ninguna casilla arranca bloqueada por contaminación (< 12.5)", ninguna_bloqueada,
		"alguna casilla de partida llega a 12.5 y no se puede construir en ella");

	_limpiar([tm, loader, pm]);

# ---------- Tensión M1: memoria de contaminación (peak_pollution) ----------

func _test_tm1_pico():
	print("Tensión M1 — el pico recuerda lo ensuciado");
	var pm = _new_pm();
	_check("una run limpia arranca con pico 0", _near(pm.peak_pollution, 0.0),
		"pico = %f" % pm.peak_pollution);

	pm.addPollution(30.0, Vector2i(1, 1));
	pm.addPollution(20.0, Vector2i(2, 1));
	_check("el pico sigue al total mientras sube", _near(pm.peak_pollution, 50.0),
		"pico = %f" % pm.peak_pollution);

	# Es LA línea del pilar de diseño: limpiar borra la suciedad, no el recuerdo.
	pm.removePollution(40.0, Vector2i(1, 1));   # solo hay 30 en esa casilla
	pm.removePollution(15.0, null);
	_check("limpiar baja el total pero NO el pico",
		_near(pm.total_pollution, 5.0) and _near(pm.peak_pollution, 50.0),
		"total %f, pico %f" % [pm.total_pollution, pm.peak_pollution]);

	pm.addPollution(10.0, Vector2i(3, 3));
	_check("volver a ensuciar por debajo del pico no lo mueve", _near(pm.peak_pollution, 50.0),
		"pico = %f" % pm.peak_pollution);
	pm.addPollution(100.0, Vector2i(3, 3));
	_check("y superarlo sí", _near(pm.peak_pollution, 115.0),
		"pico = %f" % pm.peak_pollution);

	pm.reset();
	_check("reset() olvida el pico (empieza otra run)", _near(pm.peak_pollution, 0.0),
		"pico = %f" % pm.peak_pollution);

	_limpiar([pm]);

# ---------- Tensión M1: el umbral de restauración escala con el pico ----------

func _test_tm1_umbral():
	print("Tensión M1 — umbral de restauración escalado");
	var pm = _new_pm();
	_check("sin ensuciar, el umbral es el de siempre (5.0)",
		_near(pm.getRestorationThreshold(), 5.0),
		"umbral = %f" % pm.getRestorationThreshold());

	# Run sucia: pico 200 -> umbral 5.0 + 0.12 * 200 = 29.0
	pm.addPollution(200.0, Vector2i(4, 4));
	_check("con pico 200 el umbral sube a 29.0", _near(pm.getRestorationThreshold(), 29.0),
		"umbral = %f" % pm.getRestorationThreshold());
	pm.removePollution(165.0, Vector2i(4, 4));
	_check("35 sobre un umbral de 29 todavía NO es restaurado", not pm.isRestored(),
		"total %f, umbral %f" % [pm.total_pollution, pm.getRestorationThreshold()]);
	pm.removePollution(10.0, Vector2i(4, 4));
	_check("25 sobre ese mismo umbral sí lo es", pm.isRestored(),
		"total %f, umbral %f" % [pm.total_pollution, pm.getRestorationThreshold()]);

	# El mismo total restante en una run limpia (pico 50 -> umbral 11.0) no cierra nada:
	# es lo que hace que restaurar deje de costar lo mismo hayas ensuciado mucho o poco.
	var limpia = _new_pm();
	limpia.addPollution(50.0, Vector2i(4, 4));
	limpia.removePollution(25.0, Vector2i(4, 4));
	_check("el mismo 25 con pico 50 (umbral 11) NO es restaurado", not limpia.isRestored(),
		"total %f, umbral %f" % [limpia.total_pollution, limpia.getRestorationThreshold()]);

	# El HUD tiene que enseñar el umbral EFECTIVO o el jugador no entiende qué le piden.
	# Desde M7 enseña SOLO eso: el denominador fijo (pollution_threshold) salió del texto
	# porque mentía en cuanto el contagio arrancaba y porque sus 8 caracteres eran los que
	# echaban la línea fuera de pantalla. Que ya no haya cociente se afirma por el `/`: el
	# formato nuevo no tiene ninguno.
	_check("getStatusText() enseña el umbral efectivo (29)",
		"restaurar: ≤ 29" in pm.getStatusText(),
		"texto = %s" % pm.getStatusText());
	_check("y ya NO enseña la escala fija del tintado (200)",
		not ("/" in pm.getStatusText()) and not ("200" in pm.getStatusText()),
		"texto = %s" % pm.getStatusText());

	_limpiar([pm, limpia]);

# ---------- Tensión M1: subir la escala no mueve la regla de colocación ----------

func _test_tm1_bloqueo_celda():
	print("Tensión M1 — la escala del HUD y el bloqueo de celda van por separado");
	var pm = _new_pm();
	_check("la escala del HUD es 200", _near(pm.pollution_threshold, 200.0),
		"pollution_threshold = %f" % pm.pollution_threshold);
	pm.addPollution(100.0, null);
	_check("y 100 de contaminación global tiñe el mapa a la mitad, no al tope",
		_near(pm.getNormalizedPollution(), 0.5),
		"tintado = %f" % pm.getNormalizedPollution());

	# Lo que NO se ha movido: la contaminación LOCAL que cierra una casilla.
	var tm = _new_tilemap_script();
	tm.setPollutionManager(pm);
	var celda = Vector2i(2, 2);
	pm.addPollution(12.4, celda);
	_check("a 12.4 de contaminación local la casilla sigue construible",
		not tm.isCellBlocked(celda),
		"nivel = %f" % pm.getCellPollution(celda));
	pm.addPollution(0.1, celda);
	_check("a 12.5 se cierra, exactamente igual que antes de subir la escala",
		tm.isCellBlocked(celda), "nivel = %f" % pm.getCellPollution(celda));

	_limpiar([tm, pm]);

# ---------- Tensión M1: los tiles limpiadores limpian en área ----------

func _test_tm1_tiles_en_area():
	print("Tensión M1 — un lago limpia a su alrededor");
	var tm = _new_tilemap_script();
	var lago = Vector2i(5, 5);
	tm.cell_types = { lago: "lake" };
	tm.tile_type_data = { "lake": { "passive_pollution_per_tick": -0.5 } };

	var pm = _new_pm();
	var vecina = Vector2i(6, 5);
	var lejana = Vector2i(12, 1);
	pm.addPollution(10.0, vecina);
	pm.addPollution(10.0, lejana);
	# 9 s de lago = 4.5 repartidos entre 9 casillas = 0.5 por casilla; solo una tiene suciedad.
	tm.tick_passive(pm, 9.0);
	_check("la casilla de al lado se limpia (el lago deja de ser inerte)",
		_near(pm.pollution_per_cell[vecina], 9.5),
		"quedó %f" % pm.pollution_per_cell[vecina]);
	_check("una casilla fuera del área no la toca", _near(pm.pollution_per_cell[lejana], 10.0),
		"quedó %f" % pm.pollution_per_cell[lejana]);
	_check("y el global baja solo lo quitado de esa casilla", _near(pm.total_pollution, 19.5),
		"global = %f" % pm.total_pollution);

	# Sobre suelo limpio sigue sin limpiar nada: la regla de M0.5 manda también aquí.
	var pm2 = _new_pm();
	pm2.addPollution(10.0, Vector2i(0, 9));
	tm.tick_passive(pm2, 9.0);
	_check("un lago rodeado de casillas limpias no mueve el global",
		_near(pm2.total_pollution, 10.0), "global = %f" % pm2.total_pollution);

	_limpiar([tm, pm, pm2]);

# ---------- Tensión M1: la contaminación de partida se concentra en los focos ----------

func _test_tm1_focos(fd):
	print("Tensión M1 — la contaminación de partida vive en los focos");
	var escena = load("res://entities/tilemap/tile_map.tscn");
	if escena == null:
		_check("tile_map.tscn cargable", false, "no se pudo cargar la escena");
		return;
	var tm = escena.instantiate();
	root.add_child(tm);
	var loader = load("res://managers/mapLoader.gd").new();
	var pm = _new_pm();
	var mapa = _mapa_por_id(fd, "wasteland_01");
	loader.apply_map(mapa, pm, tm, fd);

	# Los focos de wasteland_01 son sus casillas degradadas CON tile en el suelo: dos
	# `burned` y dos `swamp`. La `toxic` (6,7) no tiene tile —generate() lo borra— y queda
	# fuera del reparto: ya se ensucia sola a +0.5/s.
	var focos = [Vector2i(1, 1), Vector2i(2, 1), Vector2i(13, 5), Vector2i(14, 5)];
	var solo_focos = true;
	for c in pm.pollution_per_cell:
		if pm.pollution_per_cell[c] > 0.0 and not focos.has(c):
			solo_focos = false;
	_check("solo ensucian los focos, no las 154 casillas del suelo", solo_focos,
		"casillas con suciedad = %d" % pm.pollution_per_cell.size());
	_check("y se reparten los 20.0 entre ellos (5.0 cada uno)",
		_near(pm.pollution_per_cell.get(Vector2i(1, 1), -1.0), 5.0, 0.01),
		"el foco (1,1) tiene %f" % pm.pollution_per_cell.get(Vector2i(1, 1), -1.0));
	_check("la toxic (6,7) queda fuera: no tiene tile en el suelo",
		not pm.pollution_per_cell.has(Vector2i(6, 7)) and tm.get_cell_source_id(0, Vector2i(6, 7)) == -1);

	var se_puede_construir_al_lado = true;
	for f in focos:
		if not tm.canPlaceFactory(f + Vector2i(1, 0), []) and not tm.canPlaceFactory(f + Vector2i(0, 1), []):
			se_puede_construir_al_lado = false;
	_check("cada foco arranca por debajo del bloqueo (12.5): se puede limpiar desde al lado",
		se_puede_construir_al_lado and not tm.isCellBlocked(Vector2i(1, 1)));

	_limpiar([tm, loader, pm]);

# ---------- Tensión M2: el catálogo de mejoras está etiquetado y es aplicable ----------

func _test_tm2_catalogo(file_data):
	print("Tensión M2 — catálogo de mejoras");
	var catalogo = file_data["Upgrades"];
	var factorias = file_data["Factories"];

	# Una mejora muerta contamina el pool: los tres paquetes ya traen Reforester, así que
	# desbloquearlo no hacía nada y salía como si fuera una opción.
	_check("unlock_reforester ya no está en el catálogo", not catalogo.has("unlock_reforester"));

	var tipos_aplicables = ["speed_boost", "extra_output", "unlock_factory", "add_workers"];
	var todas_con_tier = true;
	var todas_aplicables = true;
	var todos_los_objetivos_existen = true;
	for id in catalogo:
		var mejora = catalogo[id];
		if not mejora.has("tier"):
			todas_con_tier = false;
		# Un tipo que Main._apply_upgrade() no contempla es una carta que no hace nada.
		if not tipos_aplicables.has(mejora.get("type", "")):
			todas_aplicables = false;
		var objetivo = mejora.get("target", mejora.get("factory", null));
		if objetivo != null and not factorias.has(objetivo):
			todos_los_objetivos_existen = false;
	_check("todas las mejoras declaran su tier", todas_con_tier);
	_check("todas usan uno de los cuatro tipos que Main._apply_upgrade() aplica", todas_aplicables);
	_check("todas apuntan a una factoría que existe", todos_los_objetivos_existen);

	var n1 = 0;
	var n2 = 0;
	for id in catalogo:
		if int(catalogo[id]["tier"]) == 1:
			n1 += 1;
		elif int(catalogo[id]["tier"]) == 2:
			n2 += 1;
	# Con menos de tres por tier la pantalla repetiría siempre las mismas cartas, que es
	# justo el trámite que M2 viene a convertir en decisión.
	_check("hay al menos 5 mejoras de tier 1", n1 >= 5, "tier 1 = %d" % n1);
	_check("hay al menos 4 mejoras de tier 2", n2 >= 4, "tier 2 = %d" % n2);

# ---------- Tensión M2: _pick_upgrades filtra por tier y nunca deja la pantalla coja ----------

func _test_tm2_tier(file_data):
	print("Tensión M2 — filtrado por tier y relleno");
	var gm = _new_gm(file_data);
	var catalogo = file_data["Upgrades"];

	var corrientes = gm._pick_upgrades(3, 1);
	_check("pedir tier 1 devuelve 3 mejoras corrientes distintas",
		corrientes.size() == 3 and _sin_repetidas(corrientes) and _todas_de_tier(catalogo, corrientes, 1),
		"salieron %s" % str(corrientes));
	var potentes = gm._pick_upgrades(3, 2);
	_check("pedir tier 2 devuelve 3 mejoras potentes distintas",
		potentes.size() == 3 and _sin_repetidas(potentes) and _todas_de_tier(catalogo, potentes, 2),
		"salieron %s" % str(potentes));

	# El sitio de las ruinas (Main.gd) llama sin tier y no debe enterarse de que existen.
	var ruinas = gm._pick_upgrades(1);
	_check("la llamada sin tier de las ruinas sigue dando 1 mejora corriente",
		ruinas.size() == 1 and _todas_de_tier(catalogo, ruinas, 1),
		"salió %s" % str(ruinas));

	# Tier pedido escaso: se completa hacia abajo antes que enseñar una sola carta.
	gm.upgrades_catalog = {
		"c1": { "tier": 1 }, "c2": { "tier": 1 }, "c3": { "tier": 1 }, "p1": { "tier": 2 }
	};
	var mezcla = gm._pick_upgrades(3, 2);
	_check("un tier 2 con una sola mejora se rellena con tier 1 hasta las 3 cartas",
		mezcla.size() == 3 and _sin_repetidas(mezcla) and mezcla.has("p1"),
		"salieron %s" % str(mezcla));

	# Y al revés: pedir el tier más bajo cuando no hay «inferior» con el que rellenar.
	gm.upgrades_catalog = { "c1": { "tier": 1 }, "p1": { "tier": 2 }, "p2": { "tier": 2 } };
	var tirando_de_arriba = gm._pick_upgrades(3, 1);
	_check("un tier 1 escaso se completa con lo que quede del catálogo",
		tirando_de_arriba.size() == 3 and _sin_repetidas(tirando_de_arriba),
		"salieron %s" % str(tirando_de_arriba));

	# Un catálogo a medio etiquetar no puede caerse de todos los filtros.
	gm.upgrades_catalog = { "a": {}, "b": {}, "c": {} };
	var sin_tier = gm._pick_upgrades(3, 1);
	_check("una mejora sin `tier` cuenta como corriente y sale igual", sin_tier.size() == 3,
		"salieron %s" % str(sin_tier));

	_limpiar([gm]);

# ---------- Tensión M2 (2.ª enmienda): no se ofrece desbloquear lo ya desbloqueado ----------

func _test_tm2_ya_desbloqueadas(file_data):
	print("Tensión M2 — el filtro de lo ya desbloqueado");
	var catalogo = file_data["Upgrades"];
	var paquetes = file_data["StartingPackages"];

	# Las dos caras del filtro con el catálogo real. `unlock_woodprocessing` desbloquea la
	# procesadora, que `standard` ya trae: en esa partida es humo y no debe gastar una carta.
	# Desde M8 es el único `unlock_factory` del catálogo —`unlock_meta` se retiró porque los
	# tres paquetes traen MetaFactory y era humo SIEMPRE—, y por eso el filtro sigue haciendo
	# falta: el mismo id es útil o humo según el paquete, que es lo que el JSON no puede saber.
	var gm = _new_gm(file_data);
	var con_procesadora = StubPlayer.new();
	con_procesadora.availableFactories = paquetes["standard"]["factories"].duplicate();
	gm.setPlayer(con_procesadora);
	var baraja = gm._pick_upgrades(catalogo.size(), 2);
	_check("una unlock_factory de una factoría ya disponible NO sale",
		not baraja.has("unlock_woodprocessing"), "salieron %s" % str(baraja));

	# Enmienda 3.ª: con el filtro puesto, el tier 2 que queda tiene que seguir dando para
	# elegir. Con tres cartas exactas, _pick_upgrades(3, 2) ofrece siempre las mismas y la
	# pantalla de la recompensa buena vuelve a ser el trámite que M2 vino a quitar.
	var potentes_utiles = [];
	for id in gm._usable_upgrades():
		if int(catalogo[id].get("tier", 1)) == 2:
			potentes_utiles.append(id);
	_check("tras el filtro quedan al menos 4 mejoras de tier 2 entre las que elegir",
		potentes_utiles.size() >= 4, "quedaron %s" % str(potentes_utiles));

	# Y la otra cara: el mismo id sigue vivo donde la factoría falta de verdad.
	var sin_procesadora = StubPlayer.new();
	sin_procesadora.availableFactories = ["WoodCutter", "Reforester"];
	gm.setPlayer(sin_procesadora);
	baraja = gm._pick_upgrades(catalogo.size(), 2);
	_check("la misma unlock_factory SÍ sale si la factoría no está disponible",
		baraja.has("unlock_woodprocessing"), "salieron %s" % str(baraja));

	# Lo que obliga a guardar el nodo y no una copia: Main._apply_upgrade() amplía la lista al
	# aplicar la mejora, y el checkpoint siguiente no puede volver a ofrecer lo mismo.
	sin_procesadora.availableFactories.append("WoodProcessing");
	baraja = gm._pick_upgrades(catalogo.size(), 2);
	_check("tras desbloquearla en caliente desaparece de la baraja",
		not baraja.has("unlock_woodprocessing"), "salieron %s" % str(baraja));

	# El filtro va ANTES del reparto por tier: si fuera después, el relleno de un tier escaso
	# volvería a colar la carta muerta al completar las 3.
	gm.upgrades_catalog = {
		"muerta": { "tier": 2, "type": "unlock_factory", "factory": "WoodProcessing" },
		"c1": { "tier": 1 }, "c2": { "tier": 1 }, "c3": { "tier": 1 }
	};
	var rellenada = gm._pick_upgrades(3, 2);
	_check("el relleno de un tier vacío no reintroduce la carta muerta",
		rellenada.size() == 3 and not rellenada.has("muerta"), "salieron %s" % str(rellenada));

	# La mejora gratis de las ruinas (Main.gd, llamada sin tier) sigue dando su carta.
	var ruinas = gm._pick_upgrades(1);
	_check("las ruinas siguen dando 1 mejora, y nunca la muerta",
		ruinas.size() == 1 and not ruinas.has("muerta"), "salió %s" % str(ruinas));

	# Sin Player —un montaje a medias— no se filtra nada: el catálogo entero sigue saliendo.
	var gm2 = _new_gm(file_data);
	var sin_jugador = gm2._pick_upgrades(catalogo.size(), 2);
	_check("sin Player no se descarta nada", sin_jugador.size() == catalogo.size(),
		"salieron %d de %d" % [sin_jugador.size(), catalogo.size()]);

	_limpiar([gm, gm2]);

# ---------- Tensión M2: el tiempo del tramo decide la calidad de la recompensa ----------

func _test_tm2_rendimiento(file_data):
	print("Tensión M2 — el tramo decide el tier");
	var gm = _new_gm(file_data);
	# La referencia sale del JSON, no de un número inventado: 20 wood a tick 4 del WoodCutter.
	var cp_madera = { "material": "wood", "quantity": 20 };
	_check("la referencia de un checkpoint es cantidad x tick de quien produce el material",
		_near(gm._reference_time(cp_madera), 80.0), "referencia = %f" % gm._reference_time(cp_madera));
	_check("tardar menos que la referencia da tier 2", gm._evaluate_performance(cp_madera, 45.0) == 2);
	_check("clavar la referencia todavía da tier 2", gm._evaluate_performance(cp_madera, 80.0) == 2);
	_check("pasarse da tier 1", gm._evaluate_performance(cp_madera, 95.0) == 1);
	_check("un material que nadie produce cae al tier corriente",
		gm._evaluate_performance({ "material": "unobtanium", "quantity": 5 }, 1.0) == 1);
	_limpiar([gm]);

	# Y ahora conduciendo update(), que es quien mide el tramo de verdad.
	var curva = [
		{ "material": "wood", "quantity": 20, "label": "1" },
		{ "material": "wood", "quantity": 20, "label": "2" },
		{ "material": "plank", "quantity": 15, "label": "3" }
	];
	var gm2 = _new_gm(file_data, curva);
	var bag = _new_bag();
	bag.initialize(file_data);
	var catalogo = file_data["Upgrades"];
	var ofertas = [];
	gm2.checkpoint_reached.connect(func(ids, _rewards, _g): ofertas.append(ids));

	bag.addToBag("wood", 20);
	gm2.run_time = 45.0;            # tramo de 45 s sobre una referencia de 80: buen ritmo
	gm2.update(bag);
	_check("un tramo rápido ofrece mejoras potentes",
		ofertas.size() == 1 and _todas_de_tier(catalogo, ofertas[0], 2),
		"ofrecidas %s" % str(ofertas));
	_check("el cierre del tramo queda registrado", _near(gm2.last_checkpoint_time, 45.0),
		"last_checkpoint_time = %f" % gm2.last_checkpoint_time);

	gm2.resume_after_upgrade();
	bag.addToBag("wood", 20);
	gm2.run_time = 200.0;           # segundo tramo: 155 s, muy por encima de la referencia
	gm2.update(bag);
	_check("un tramo lento ofrece mejoras corrientes",
		ofertas.size() == 2 and _todas_de_tier(catalogo, ofertas[1], 1),
		"ofrecidas %s" % str(ofertas));
	# El tramo es tiempo jugado: el primero no se cuenta dos veces en el segundo.
	_check("el segundo tramo se mide desde el primero, no desde el inicio de la run",
		_near(gm2.last_checkpoint_time, 200.0), "last_checkpoint_time = %f" % gm2.last_checkpoint_time);

	gm2.reset();
	_check("reset() olvida el cierre del tramo anterior", _near(gm2.last_checkpoint_time, 0.0),
		"last_checkpoint_time = %f" % gm2.last_checkpoint_time);

	_limpiar([gm2, bag]);

# ---------- Tensión M3: el downside de mapa ----------

func _test_tm3_downside(file_data):
	print("Tensión M3 — el downside de mapa");
	var catalogo = file_data["Upgrades"];
	var tipos = file_data["TileTypes"];

	var con_downside = [];
	var bien_formado = true;
	var solo_tier_2 = true;
	for id in catalogo:
		if not catalogo[id].has("map_downside"):
			continue;
		con_downside.append(id);
		var d = catalogo[id]["map_downside"];
		var t = d.get("type", "");
		# Un tipo construible no sería castigo, y uno que no se pueda limpiar no sería
		# reversible: el dilema necesita las dos cosas a la vez.
		if int(d.get("cells", 0)) < 1 or not tipos.has(t):
			bien_formado = false;
		elif tipos[t].get("buildable", true) or not tipos[t].get("degraded", false):
			bien_formado = false;
		if int(catalogo[id].get("tier", 1)) != 2:
			solo_tier_2 = false;
	_check("hay mejoras que pagan mapa", con_downside.size() >= 3, "son %s" % str(con_downside));
	_check("todas degradan a un tipo no construible y recuperable", bien_formado);
	_check("y solo las potentes pagan: una mejora corriente no cuesta mapa", solo_tier_2);

	# Aplicación, entrando por la puerta real: _apply_upgrade() con el catálogo del juego.
	var pm = _new_pm();
	var main = _new_main_de_prueba(file_data);
	main.pollutionManager = pm;
	var tm = main.get_node("TileMap");
	tm.setPollutionManager(pm);
	for y in range(4):
		for x in range(4):
			tm.set_cell(0, Vector2i(x, y), 1, Vector2i(0, 0));

	# `extra_wood` es la carta más cara del castigo graduado de M6b: 3 casillas. El número no
	# se escribe a mano, se lee del catálogo, o esta prueba se volvería a quedar clavada en el
	# valor de ayer la próxima vez que la tabla se mueva.
	var cells_extra_wood = int(catalogo["extra_wood"]["map_downside"]["cells"]);
	main._apply_upgrade("extra_wood");
	var degradadas = _celdas_de_tipo(tm, "toxic");
	_check("la mejora degrada exactamente las casillas que anuncia su carta",
		degradadas.size() == cells_extra_wood,
		"degradó %d de %d" % [degradadas.size(), cells_extra_wood]);
	_check("y el beneficio se aplica igual: el castigo no lo sustituye",
		main.get_node("Player").getOutputForFactory("WoodCutter", 1) == 2);

	var suelo_intacto = true;
	var ninguna_construible = true;
	var todas_sucias = true;
	for cell in degradadas:
		if tm.get_cell_source_id(0, cell) == -1:
			suelo_intacto = false;
		if tm.canPlaceFactory(cell, []):
			ninguna_construible = false;
		if pm.pollution_per_cell.get(cell, 0.0) <= 0.0:
			todas_sucias = false;
	_check("la degradada conserva su tile del suelo: se ve y se puede limpiar", suelo_intacto);
	_check("y deja de admitir factorías", ninguna_construible);
	_check("nace sucia, o el castigo duraría un frame", todas_sucias);

	# El frame siguiente corre el check del desbloqueo ANTES del tick pasivo: si la casilla
	# naciera limpia, ese primer frame la devolvería y el downside se evaporaría.
	for i in range(10):
		main._tick_world(tm, 1.0 / 60.0);
	_check("el castigo sobrevive a los primeros frames",
		_celdas_de_tipo(tm, "toxic").size() == cells_extra_wood);

	# Una mejora de tier 1 no toca el mapa.
	main._apply_upgrade("speed_woodcutter");
	_check("una mejora sin map_downside no degrada nada",
		_celdas_de_tipo(tm, "toxic").size() == cells_extra_wood);

	# Y limpiarla del todo la devuelve: el castigo es un préstamo, no una multa.
	var recuperada = degradadas[0];
	tm.restoreCell(recuperada);
	_check("restaurada, la casilla vuelve a admitir factorías", tm.canPlaceFactory(recuperada, []));
	_check("y pierde el tinte del tipo degradado", not tm._cell_colors.has(recuperada));

	_limpiar([main, pm]);

	# Elegibilidad: con un suelo de tres casillas —una especial, una ocupada y una libre— el
	# downside solo puede caer en la libre, aunque la mejora pida tres.
	var main2 = _new_main_de_prueba(file_data);
	var tm2 = main2.get_node("TileMap");
	var especial = Vector2i(0, 0);
	var ocupada = Vector2i(1, 0);
	var libre = Vector2i(2, 0);
	for cell in [especial, ocupada, libre]:
		tm2.set_cell(0, cell, 1, Vector2i(0, 0));
	tm2.cell_types[especial] = "ruins";
	var ocupante = _new_factory("WoodCutter", ocupada);
	ocupante.tickTimer = 4;
	main2.factoryArray.append(ocupante);

	main2._apply_upgrade("extra_wood");
	_check("no se pisa una casilla especial: el mapa curado no se borra",
		tm2.getCellType(especial) == "ruins");
	_check("ni una con factoría encima: un castigo invisible no es un castigo",
		tm2.getCellType(ocupada) == "");
	_check("sí la única libre, y sin romperse al pedir más casillas de las que hay",
		tm2.getCellType(libre) == "toxic");

	_limpiar([main2, ocupante]);

# ---------- Tensión M3: la casilla degradada se recupera limpiándola ----------

func _test_tm3_desbloqueo(file_data):
	print("Tensión M3 — la casilla degradada se recupera");
	# Seis Reforester adyacentes compensan los +0.5/s de una `toxic`: cada uno reparte 4.0
	# entre nueve casillas cada 5 s, así que sobre la toxic caen 6 x 4/9 = 2.67 por cada 2.5
	# que acumula. Con cinco (2.22) nunca llega a cero. Ese es el precio del downside.
	var con_seis = _simular_toxic(file_data, 6, 60.0);
	var con_cinco = _simular_toxic(file_data, 5, 60.0);
	var sin_ninguno = _simular_toxic(file_data, 0, 2.0);

	_check("una toxic rodeada de seis Reforester acaba desbloqueándose",
		con_seis["t"] >= 0.0, "seguía toxic tras 60 s");
	_check("y al desbloquearse vuelve a admitir factorías", con_seis["construible"]);
	_check("con cinco no basta: la casilla aguanta los 60 s", con_cinco["t"] < 0.0,
		"se desbloqueó en %f s" % con_cinco["t"]);
	_check("mientras siga toxic no se puede construir en ella", not con_cinco["construible"]);
	# El check corre antes del tick pasivo: una toxic que todavía no se ha ensuciado marca 0
	# y se restauraría sola en el primer frame. Es la (6,7) de wasteland_01.
	_check("una toxic que nunca se ha ensuciado no se desbloquea sola",
		sin_ninguno["t"] < 0.0, "se desbloqueó en %f s" % sin_ninguno["t"]);
	_check("la degradada conserva su tile del suelo, limpia o sucia",
		con_seis["tile_en_suelo"] and con_cinco["tile_en_suelo"]);

# Monta un Main con su TileMap y le da frames: cada frame es _tick_world(), que es el orden
# real del juego —primero el check del desbloqueo, después el tick pasivo—, y cada `tick` del
# Reforester su limpieza en área. Devuelve el segundo en que la casilla dejó de ser toxic
# (-1.0 si aguantó), si conserva su tile en el suelo y si volvió a ser construible.
func _simular_toxic(file_data, n_reforester, segundos):
	var pm = _new_pm();
	root.add_child(pm);
	var main = _new_main_de_prueba(file_data);
	main.pollutionManager = pm;
	var tm = main.get_node("TileMap");
	tm.setPollutionManager(pm);

	var toxica = Vector2i(5, 5);
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			tm.set_cell(0, toxica + Vector2i(dx, dy), 1, Vector2i(0, 0));
	tm.degradeCell(toxica, "toxic");

	# Los Reforester van al árbol y no bajo `main`: factoryData._apply_pollution() busca el
	# PollutionManager con find_child() desde la raíz, y `main` se queda fuera del árbol.
	var reforesters = [];
	var vecinas = [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1),
		Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1)];
	for i in range(n_reforester):
		var f = _new_factory("Reforester", toxica + vecinas[i]);
		f.factory_type = "restoration";
		f.pollutionAmount = float(file_data["Factories"]["Reforester"]["pollution"]);
		root.add_child(f);
		reforesters.append(f);

	var delta = 1.0 / 60.0;
	var tick = float(file_data["Factories"]["Reforester"]["tick"]);
	var t = 0.0;
	var desde_el_ultimo_tick = 0.0;
	var desbloqueo = -1.0;
	while t < segundos:
		main._tick_world(tm, delta);
		if tm.getCellType(toxica) != "toxic":
			desbloqueo = t;
			break;
		t += delta;
		desde_el_ultimo_tick += delta;
		if desde_el_ultimo_tick >= tick:
			desde_el_ultimo_tick -= tick;
			for f in reforesters:
				f._apply_pollution(f.getRestorationScale());

	var resultado = {
		"t": desbloqueo,
		"tile_en_suelo": tm.get_cell_source_id(0, toxica) != -1,
		"construible": tm.canPlaceFactory(toxica, [])
	};
	_limpiar([main, pm] + reforesters);
	return resultado;

# ---------- Tensión M3.5: el tinte de casilla llega a pantalla ----------

func _test_tm35_tinte(file_data):
	print("Tensión M3.5 — el tinte de casilla se pinta encima del tile");
	var escena = load("res://entities/tilemap/tile_map.tscn");
	if escena == null:
		_check("tile_map.tscn cargable", false, "no se pudo cargar la escena");
		return;
	var tm = escena.instantiate();
	tm.name = "TileMap";
	root.add_child(tm);
	var verde = Vector2i(1, 1);
	var monte = Vector2i(2, 2);
	tm.generate([4, 4], [], [
		{ "pos": [1, 1], "type": "forest" },
		{ "pos": [2, 2], "type": "mountain" }
	], file_data["TileTypes"]);

	# Lo que rompía el hito: el _draw() de un TileMap queda DEBAJO de los canvas items de sus
	# capas. Si el tinte vuelve a salir por ahí, ocho tipos de casilla se hacen invisibles
	# otra vez y ninguna prueba de aritmética lo nota.
	var overlay = tm.get_node_or_null("TintOverlay");
	_check("el tinte sale por un canvas item propio, no por el _draw() del TileMap",
		overlay != null and overlay is Node2D);
	_check("y ese canvas item va por encima de las capas del tilemap (z_index > 0)",
		overlay != null and overlay.z_index > 0,
		"z_index = %s" % (str(overlay.z_index) if overlay != null else "sin overlay"));

	var spy = SpyCanvas.new();
	tm.draw_tints(spy);
	_check("una casilla de tipo con color pinta su diamante", spy.polys.size() == 1,
		"diamantes pintados: %d" % spy.polys.size());
	var col = file_data["TileTypes"]["forest"]["color"];
	_check("con el color que declara el JSON",
		spy.polys.size() == 1 and _near(spy.polys[0]["color"].r, float(col[0]))
		and _near(spy.polys[0]["color"].g, float(col[1]))
		and _near(spy.polys[0]["color"].b, float(col[2])),
		"color pintado = %s" % (str(spy.polys[0]["color"]) if spy.polys.size() > 0 else "ninguno"));
	_check("y centrado en su casilla",
		spy.polys.size() == 1 and spy.polys[0]["puntos"][0].is_equal_approx(
			tm.map_to_local(verde) + Vector2(0, -16.0)),
		"primer vértice = %s" % (str(spy.polys[0]["puntos"][0]) if spy.polys.size() > 0 else "ninguno"));
	_check("una casilla con sprite (mountain) no se tiñe: taparía su dibujo",
		not tm._cell_colors.has(monte));

	# El tinte rojo de contaminación va DESPUÉS del del tipo: sobre una casilla sucia hay que
	# leer lo sucia que está, no de qué tipo es.
	var pm = _new_pm();
	tm.setPollutionManager(pm);
	pm.addPollution(6.25, verde);
	var spy2 = SpyCanvas.new();
	tm.draw_tints(spy2);
	_check("una casilla sucia pinta dos diamantes", spy2.polys.size() == 2,
		"diamantes pintados: %d" % spy2.polys.size());
	_check("y el rojo de contaminación se pinta el último, para leerse sobre el tipo",
		spy2.polys.size() == 2 and spy2.polys[1]["color"].r > spy2.polys[1]["color"].g,
		"último color = %s" % (str(spy2.polys[1]["color"]) if spy2.polys.size() == 2 else "ninguno"));

	# La casilla degradada de M3 y su vuelta: es lo que el jugador tiene que ver aparecer y
	# desaparecer.
	var llana = Vector2i(0, 0);
	tm.degradeCell(llana, "toxic");
	var spy3 = SpyCanvas.new();
	tm.draw_tints(spy3);
	_check("degradar una casilla le añade su diamante", spy3.polys.size() == 3,
		"diamantes pintados: %d" % spy3.polys.size());
	tm.restoreCell(llana);
	var spy4 = SpyCanvas.new();
	tm.draw_tints(spy4);
	_check("y recuperarla se lo quita", spy4.polys.size() == 2,
		"diamantes pintados: %d" % spy4.polys.size());

	_limpiar([tm, pm]);

# ---------- Tensión M4: mantenimiento y curva de checkpoints ----------

func _test_tm4_curva(file_data):
	print("Tensión M4 — la curva del JSON");
	var curva = file_data["Checkpoints"];
	_check("la curva tiene 4 o 5 checkpoints", curva.size() >= 4 and curva.size() <= 5,
		"%d checkpoints" % curva.size());
	var gm = _new_gm(file_data);
	# «Creciente» se mide con la misma vara que decide la recompensa —los segundos que
	# tardaría la factoría base en cubrir el checkpoint—, y no comparando cantidades a pelo:
	# 25 tablones cuestan más trabajo que 15 maderas aunque el número sea mayor.
	var referencias = [];
	var creciente = true;
	for cp in curva:
		var ref = gm._reference_time(cp);
		if not referencias.is_empty() and ref <= referencias[-1]:
			creciente = false;
		referencias.append(ref);
	_check("cada checkpoint pide más trabajo que el anterior", creciente,
		"referencias = %s" % str(referencias));

	# Un mantenimiento de un material que ninguna factoría produce sería un requisito
	# imposible, y como el checkpoint no se supera hasta pagarlo dejaría la run colgada
	# para siempre: no hay condición de derrota que lo recoja (`run_lost` no se emite).
	var producidos = [];
	for nombre in file_data["Factories"]:
		var material = file_data["Factories"][nombre].get("material", null);
		if material != null:
			producidos.append(material);
	var pagable = true;
	var totales = [];
	for cp in curva:
		var total = 0;
		for material in cp.get("maintenance", {}):
			if not producidos.has(material):
				pagable = false;
			total += int(cp["maintenance"][material]);
		totales.append(total);
	_check("todo mantenimiento pide un material que alguna factoría produce", pagable);
	_check("el primer checkpoint no cobra mantenimiento", totales[0] == 0,
		"mantenimiento del primero = %d" % totales[0]);
	var mant_creciente = true;
	for i in range(1, totales.size()):
		if totales[i] < totales[i - 1]:
			mant_creciente = false;
	_check("el mantenimiento no decrece a lo largo de la curva", mant_creciente,
		"totales = %s" % str(totales));
	_limpiar([gm]);

func _test_tm4_mantenimiento(file_data):
	print("Tensión M4 — el mantenimiento se anuncia y se cobra");
	var curva = [
		{ "material": "plank", "quantity": 10, "label": "Uno", "maintenance": { "wood": 4 } },
		{ "material": "plank", "quantity": 10, "label": "Dos" }
	];
	var gm = _new_gm(file_data, curva);
	var bag = _new_bag();
	bag.initialize(file_data);

	bag.addToBag("plank", 10);
	bag.addToBag("wood", 1);
	var texto = gm.getObjectiveText(bag);
	# El anuncio va ANTES del cobro y con su progreso: es la mitad del requisito, y sin
	# verlo el jugador con los tablones hechos no entendería por qué no se cierra.
	# Desde M6 el texto dice además que está RESERVADO, porque desde M6 lo está de verdad: esa
	# madera no se puede consumir como insumo, y sin nombrarlo el jugador vería serrerías
	# paradas con el almacén lleno.
	_check("el HUD anuncia el mantenimiento con su progreso", "(peaje reservado: 1 / 4 wood)" in texto,
		texto);
	gm.update(bag);
	_check("con el objetivo cubierto pero sin mantenimiento el checkpoint no se supera",
		gm.current_checkpoint_index == 0 and bag.getQuantity("plank") == 10,
		"índice %d, plank %d" % [gm.current_checkpoint_index, bag.getQuantity("plank")]);

	bag.addToBag("wood", 3);
	gm.update(bag);
	_check("en cuanto entra el mantenimiento el checkpoint se cierra", gm.current_checkpoint_index == 1);
	_check("y se cobran objetivo y mantenimiento de la misma bolsa",
		bag.getQuantity("plank") == 0 and bag.getQuantity("wood") == 0,
		"plank %d, wood %d" % [bag.getQuantity("plank"), bag.getQuantity("wood")]);
	_check("un checkpoint sin mantenimiento no ensucia el HUD con un paréntesis vacío",
		not ("reservado" in gm.getObjectiveText(bag)), gm.getObjectiveText(bag));
	_limpiar([gm, bag]);

	# Mantenimiento del MISMO material que el objetivo: los dos salen de la bolsa, así que
	# se suman en vez de pisarse.
	var gm2 = _new_gm(file_data, [
		{ "material": "wood", "quantity": 10, "label": "Uno", "maintenance": { "wood": 3 } },
		{ "material": "wood", "quantity": 10, "label": "Dos" }
	]);
	var bag2 = _new_bag();
	bag2.initialize(file_data);
	bag2.addToBag("wood", 12);
	gm2.update(bag2);
	_check("objetivo y mantenimiento del mismo material se suman", gm2.current_checkpoint_index == 0,
		"cerró con 12 de las 13 que cuesta");
	bag2.addToBag("wood", 1);
	gm2.update(bag2);
	_check("con las 13 sí se cierra y la bolsa queda a cero",
		gm2.current_checkpoint_index == 1 and bag2.getQuantity("wood") == 0,
		"índice %d, wood %d" % [gm2.current_checkpoint_index, bag2.getQuantity("wood")]);
	_limpiar([gm2, bag2]);

	# El último checkpoint cobra igual que los demás y dispara la victoria: la fase de
	# restauración empieza con la bolsa ya descontada.
	var gm3 = _new_gm(file_data, [
		{ "material": "plank", "quantity": 5, "label": "Final", "maintenance": { "wood": 2 } }
	]);
	var bag3 = _new_bag();
	bag3.initialize(file_data);
	var victorias = [];
	gm3.run_won.connect(func(stats): victorias.append(stats));
	bag3.addToBag("plank", 5);
	bag3.addToBag("wood", 2);
	gm3.update(bag3);
	_check("el último checkpoint también cobra el mantenimiento",
		bag3.getQuantity("wood") == 0 and bag3.getQuantity("plank") == 0);
	# `== 1` desde M8: la victoria salía dos veces en la misma llamada cuando el último
	# checkpoint se cerraba con el mapa ya restaurado, porque la rama de producción y la de
	# restauración no se excluían. Ahora solo gana la de restauración (ver _test_tm8_cabos).
	_check("y dispara la victoria una sola vez", victorias.size() == 1 and gm3.production_done,
		"victorias = %d" % victorias.size());
	_limpiar([gm3, bag3]);

func _test_tm4_acumulado(file_data):
	print("Tensión M4 — el material acumulado no infla el ritmo del tramo");
	var gm = _new_gm(file_data);
	var cp = { "material": "plank", "quantity": 20 };
	_check("sin acumulado la referencia es la de siempre", _near(gm._reference_time(cp), 60.0),
		"%f" % gm._reference_time(cp));
	_check("el acumulado del tramo anterior se descuenta de la referencia",
		_near(gm._reference_time(cp, 15), 15.0), "%f" % gm._reference_time(cp, 15));
	_check("un objetivo ya cubierto de antemano no tiene ritmo que premiar",
		gm._evaluate_performance(cp, 0.5, 20) == 1);
	_limpiar([gm]);

	# La trampa real de una curva de cinco checkpoints: el tramo de `wood` deja tablones
	# hechos, así que el checkpoint de `plank` siguiente se cerraría en un frame y, medido
	# contra la cantidad entera, parecería un ritmo récord.
	var gm2 = _new_gm(file_data, [
		{ "material": "wood", "quantity": 10, "label": "Uno" },
		{ "material": "plank", "quantity": 20, "label": "Dos" },
		{ "material": "plank", "quantity": 20, "label": "Tres" }
	]);
	var bag = _new_bag();
	bag.initialize(file_data);
	var catalogo = file_data["Upgrades"];
	var ofertas = [];
	gm2.checkpoint_reached.connect(func(ids, _r, _g): ofertas.append(ids));

	bag.addToBag("wood", 10);
	bag.addToBag("plank", 20);       # producidos durante el tramo de madera
	gm2.run_time = 5.0;
	gm2.update(bag);
	_check("el primer tramo se juzga entero: nada venía de antes",
		ofertas.size() == 1 and _todas_de_tier(catalogo, ofertas[0], 2), "ofrecidas %s" % str(ofertas));
	_check("el arranque del tramo siguiente guarda lo que ya estaba hecho",
		gm2.segment_start_stock == 20, "segment_start_stock = %d" % gm2.segment_start_stock);

	gm2.resume_after_upgrade();
	gm2.run_time = 6.0;              # tramo de 1 s sobre una referencia nominal de 60
	gm2.update(bag);
	_check("un objetivo que venía hecho del tramo anterior NO regala la recompensa potente",
		ofertas.size() == 2 and _todas_de_tier(catalogo, ofertas[1], 1), "ofrecidas %s" % str(ofertas));

	gm2.reset();
	_check("reset() olvida el acumulado", gm2.segment_start_stock == 0,
		"segment_start_stock = %d" % gm2.segment_start_stock);
	_limpiar([gm2, bag]);

# ---------- Tensión M6: el peaje reservado, para que ninguna mejora cuelgue la run ----------

func _test_tm6_reserva(file_data):
	print("Tensión M6 — la bolsa aparta el peaje del checkpoint");
	var bag = _new_bag();
	bag.initialize(file_data);
	bag.addToBag("wood", 12);
	bag.setReserved({ "wood": 10 });
	_check("lo disponible es lo que hay menos lo reservado", bag.getAvailable("wood") == 2,
		"disponible = %d" % bag.getAvailable("wood"));
	# La reserva no toca la cantidad: es la misma que _can_afford() exige y la que el HUD
	# enseña. Si restara de verdad, el checkpoint no se cerraría nunca y el HUD mentiría.
	_check("la reserva no toca la cantidad real, que es la que cobra el checkpoint",
		bag.getQuantity("wood") == 12, "cantidad = %d" % bag.getQuantity("wood"));
	bag.setReserved({ "wood": 30 });
	_check("no se puede apartar lo que no hay: disponible nunca es negativo",
		bag.getAvailable("wood") == 0, "disponible = %d" % bag.getAvailable("wood"));
	bag.setReserved({});
	_check("sin reserva, disponible es todo", bag.getAvailable("wood") == 12);
	_check("un material sin reserva ni existencias da 0", bag.getAvailable("factory_token") == 0);
	bag.setReserved({ "wood": 5 });
	bag.reset();
	_check("reset() olvida la reserva", bag.getReserved("wood") == 0,
		"reservado = %d" % bag.getReserved("wood"));
	_limpiar([bag]);

	# La reserva la sincroniza update() con el checkpoint EN CURSO, así que se mueve sola
	# cuando la curva avanza y nadie tiene que acordarse de actualizarla.
	var curva = [
		{ "material": "plank", "quantity": 5, "label": "Uno", "maintenance": { "wood": 4 } },
		{ "material": "plank", "quantity": 5, "label": "Dos", "maintenance": { "wood": 6 } }
	];
	var gm = _new_gm(file_data, curva);
	var bag2 = _new_bag();
	bag2.initialize(file_data);
	gm.update(bag2);
	_check("la reserva es el mantenimiento del checkpoint en curso", bag2.getReserved("wood") == 4,
		"reservado = %d" % bag2.getReserved("wood"));
	bag2.addToBag("plank", 5);
	bag2.addToBag("wood", 4);
	gm.update(bag2);
	_check("al cerrarse un checkpoint la reserva pasa a la del siguiente",
		gm.current_checkpoint_index == 1 and bag2.getReserved("wood") == 6,
		"índice %d, reservado %d" % [gm.current_checkpoint_index, bag2.getReserved("wood")]);
	# Cerrar un checkpoint deja `active = false` hasta que se elige la mejora: sin esto,
	# update() sale por la primera línea y el último checkpoint no llegaría a evaluarse.
	gm.resume_after_upgrade();
	bag2.addToBag("plank", 5);
	bag2.addToBag("wood", 6);
	gm.update(bag2);
	# Terminada la producción ya no hay peaje que proteger y la MetaFactory o el WorkerCamp
	# vuelven a comer de todo: la fase de restauración no tiene por qué heredar el freno.
	_check("terminada la producción se levanta la reserva",
		gm.production_done and bag2.getReserved("wood") == 0,
		"production_done %s, reservado %d" % [str(gm.production_done), bag2.getReserved("wood")]);
	_limpiar([gm, bag2]);

	# El objetivo se aparta solo cuando es una MATERIA PRIMA: `wood` sale del WoodCutter, que
	# no consume nada, así que es la raíz de la cadena y quien se la coma por debajo de lo
	# exigido bloquea el checkpoint para siempre. Es lo que colgaba el primer checkpoint —15
	# maderas— en cuanto se levantaban dos serrerías nada más empezar, sin una sola mejora.
	var gm3 = _new_gm(file_data, [{ "material": "wood", "quantity": 5, "label": "Materia prima" }]);
	var bag3 = _new_bag();
	bag3.initialize(file_data);
	bag3.addToBag("wood", 1);
	gm3.update(bag3);
	_check("un objetivo de materia prima se reserva aunque no haya peaje",
		bag3.getReserved("wood") == 5, "reservado = %d" % bag3.getReserved("wood"));
	_limpiar([gm3, bag3]);

	# Y el procesado NO: comerse un tablón solo retrasa el checkpoint —la serrería sigue
	# fabricando del excedente de madera—, mientras que apartarlo dejaría a la MetaFactory y
	# al WorkerCamp sin consumir un solo tablón en toda la fase de producción.
	var gm4 = _new_gm(file_data, [{ "material": "plank", "quantity": 5, "label": "Procesado" }]);
	var bag4 = _new_bag();
	bag4.initialize(file_data);
	bag4.addToBag("plank", 3);
	gm4.update(bag4);
	_check("un objetivo procesado no se reserva", bag4.getReserved("plank") == 0,
		"reservado = %d" % bag4.getReserved("plank"));
	_check("y sigue disponible entero para quien lo consuma", bag4.getAvailable("plank") == 3);
	_limpiar([gm4, bag4]);

	var gm5 = _new_gm(file_data);
	_check("wood es materia prima (WoodCutter no consume nada)", gm5._is_raw_material("wood"));
	_check("plank no lo es (WoodProcessing consume madera)", not gm5._is_raw_material("plank"));
	_check("un material que nadie fabrica tampoco lo es", not gm5._is_raw_material("hierro"));

	# El invariante que sostiene el hito entero: de lo que un checkpoint exige, lo que la
	# bolsa NO aparta solo lo consumen factorías a las que ninguna mejora del catálogo puede
	# acelerar. Así ninguna combinación de mejoras puede vaciar un requisito. El día que
	# alguien añada una «Meta-fábrica rápida», esta prueba se pone roja antes que la partida.
	var acelerable = "";
	for cp in file_data["Checkpoints"]:
		var reservado = gm5._reserved_materials(cp);
		for material in gm5._checkpoint_cost(cp):
			if material == "" or reservado.has(material):
				continue;
			for nombre in file_data["Factories"]:
				var insumos = file_data["Factories"][nombre].get("recieve", null);
				if insumos == null or not insumos.has(material):
					continue;
				for id in file_data["Upgrades"]:
					var mejora = file_data["Upgrades"][id];
					if mejora.get("type", "") == "speed_boost" and mejora.get("target", "") == nombre:
						acelerable = "%s consume %s (sin reservar) y la mejora %s la acelera" % [nombre, material, id];
	_check("ninguna mejora acelera a un consumidor de lo que un checkpoint exige sin reservar",
		acelerable == "", acelerable);
	_limpiar([gm5]);

	# La reserva no puede morderse la cola: si el material apartado lo fabricase una factoría
	# que consume otro material apartado del MISMO checkpoint, apartar los dos los congelaría
	# a la vez y la run se colgaría por el arreglo en vez de por el bug. Hoy no pasa —`wood`
	# sale del WoodCutter, que no consume nada—, y esto lo fija para el que toque la curva.
	var sano = true;
	var detalle = "";
	for cp in file_data["Checkpoints"]:
		var peaje = cp.get("maintenance", {});
		for material in peaje:
			for nombre in file_data["Factories"]:
				var f = file_data["Factories"][nombre];
				if f.get("material", null) != material:
					continue;
				for insumo in (f.get("recieve", null) if f.get("recieve", null) != null else []):
					if peaje.has(insumo):
						sano = false;
						detalle = "%s fabrica %s consumiendo %s, y los dos están reservados" % [nombre, material, insumo];
	_check("el material reservado lo fabrica alguien que no depende de otro reservado", sano, detalle);

func _test_tm6_no_cuelga(file_data):
	print("Tensión M6 — un consumidor más rápido que el productor ya no cuelga la run");
	# El atasco medido al cerrar M5, en pequeño: el objetivo es `plank` y el peaje `wood`, que
	# es el insumo del `plank`. Dos serrerías con «Sierra industrial» (tick 1) piden 2 maderas
	# por segundo y una cortadora talla 1 cada 4 s.
	# Hasta Cintas M2 lo que impedía que las serrerías se comieran el peaje era la reserva de
	# la bolsa (`Bag.getAvailable()`). Desde M2 la protección es ESTRUCTURAL y más fuerte: la
	# serrería come de su BÚFER DE ENTRADA —lo que una cinta le ha traído— y la madera de la
	# bolsa no está a su alcance, reservada o no. La reserva sigue viva y sin tocar en `Bag`
	# para quien sí la necesita, el evaluador de checkpoints.
	var gm = _new_gm(file_data, [
		{ "material": "plank", "quantity": 6, "label": "Uno", "maintenance": { "wood": 5 } }
	]);
	var bag = _new_bag();
	bag.initialize(file_data);
	var pm = _new_pm();
	root.add_child(pm);
	# Las tres van con pollution 0.0 desde el ahogo (Condiciones de Derrota M1): 400 ticks
	# seguidos sobre la misma casilla y sin nadie limpiando la saturan, y una línea ahogada
	# dejaría de talar por un motivo que esta prueba no mide. Lo que se prueba aquí es de
	# dónde come la serrería, así que el ahogo se saca del escenario en vez de taparlo.
	var cortadora = _factoria_en_arbol("WoodCutter", Vector2i(0, 0));
	cortadora.initialize("WoodCutter", 4, null, "wood", 1, 0.0, "production", 0);
	var sierra1 = _factoria_en_arbol("WoodProcessing", Vector2i(1, 0));
	sierra1.initialize("WoodProcessing", 1, ["wood"], "plank", 1, 0.0, "production", 0);
	var sierra2 = _factoria_en_arbol("WoodProcessing", Vector2i(2, 0));
	sierra2.initialize("WoodProcessing", 1, ["wood"], "plank", 1, 0.0, "production", 0);
	# La cinta, a mano (lo que hace beltNetwork.deliver() en el juego): la madera de la
	# cortadora llega a la PRIMERA serrería y a ninguna más. La segunda se queda sin cinta a
	# propósito: es el contraste de esta prueba.
	cortadora.resource_produced.connect(
		func(mat, cantidad, _pos): sierra1.receiveMaterial(mat, cantidad));
	# Y el almacén de M3, también a mano: los tablones son lo único que llega a la bolsa. El
	# peaje de madera se da por ya almacenado antes de empezar.
	var al_almacen = func(mat, cantidad, _pos): bag.addToBag(mat, cantidad);
	sierra1.resource_produced.connect(al_almacen);
	sierra2.resource_produced.connect(al_almacen);
	var sin_cinta = [0];
	sierra2.resource_produced.connect(func(_mat, cantidad, _pos): sin_cinta[0] += cantidad);
	bag.addToBag("wood", 5);

	var cerrado_en = -1;
	var peaje_minimo = 5;
	for t in range(1, 401):
		gm.update(bag);          # sincroniza la reserva y evalúa el checkpoint
		if t % 4 == 0:
			cortadora.update();
		sierra1.update();
		sierra2.update();
		if gm.current_checkpoint_index >= 1:
			if cerrado_en < 0:
				cerrado_en = t;
		else:
			peaje_minimo = min(peaje_minimo, bag.getQuantity("wood"));
	_check("el checkpoint se cierra pese a que las serrerías piden el doble de lo que se tala",
		cerrado_en > 0, "no se cerró en 400 ticks (wood %d, plank %d)" % [
			bag.getQuantity("wood"), bag.getQuantity("plank")]);
	# Y no a costa de parar la línea: la serrería con cinta sigue entregando, así que el
	# objetivo de tablones también se cubre. Un arreglo que congelara la producción cerraría
	# el peaje y colgaría la run por el otro lado.
	_check("y las serrerías siguen produciendo de lo que les trae la cinta", cerrado_en > 0,
		"objetivo de plank sin cubrir");
	_check("el peaje no baja ni una madera: la serrería ya no puede comer de la bolsa",
		peaje_minimo == 5, "el peaje bajó a %d" % peaje_minimo);
	# El contraste, para que lo de arriba no pase por casualidad: la serrería SIN cinta no
	# produce nada en 400 ticks aunque la bolsa esté llena de madera. Es la regla de Cintas M2
	# —una factoría solo come lo que le han entregado— y sustituye al contraste de la reserva,
	# que medía la protección vieja sobre el input de la factoría.
	_check("una serrería sin cinta no produce nada aunque la bolsa tenga madera",
		sin_cinta[0] == 0 and sierra2.input_buffer.is_empty(),
		"entregó %d con el búfer %s" % [sin_cinta[0], str(sierra2.input_buffer)]);
	_limpiar([cortadora, sierra1, sierra2, gm, bag, pm]);

# Factoría en el árbol con su sprite, sin arrastrar un PollutionManager propio:
# _new_factory_en_arbol() añade el suyo en cada llamada y aquí se montan varias a la vez.
func _factoria_en_arbol(tipo, celda):
	var f = _new_factory(tipo, celda);
	var spr = AnimatedSprite2D.new();
	spr.name = "AnimatedSprite2D";
	spr.sprite_frames = SpriteFrames.new();
	f.add_child(spr);
	root.add_child(f);
	return f;

# ---------- Tensión M5: la carta que desatasca la run no depende de la suerte ----------

func _test_tm5_rescate(file_data):
	print("Tensión M5 — los tres paquetes son jugables");
	var catalogo = file_data["Upgrades"];
	var paquetes = file_data["StartingPackages"];

	# El callejón que M5 abre: WoodProcessing es la única fuente de `plank`, los checkpoints
	# 2 a 5 piden `plank` y la MetaFactory —la otra vía de desbloqueo— también lo consume.
	var fuentes_de_plank = [];
	for nombre in file_data["Factories"]:
		if file_data["Factories"][nombre].get("material", null) == "plank":
			fuentes_de_plank.append(nombre);
	_check("WoodProcessing sigue siendo la única fuente de plank",
		fuentes_de_plank == ["WoodProcessing"], "producen plank: %s" % str(fuentes_de_plank));
	var desbloquea_procesadora = [];
	for id in catalogo:
		if catalogo[id].get("type", "") == "unlock_factory" and catalogo[id].get("factory", "") == "WoodProcessing":
			desbloquea_procesadora.append(id);
	_check("el catálogo tiene una mejora que desbloquea WoodProcessing",
		desbloquea_procesadora.size() == 1, "salieron %s" % str(desbloquea_procesadora));
	if desbloquea_procesadora.is_empty():
		return;
	var rescate = desbloquea_procesadora[0];

	# `standard` la trae de inicio: su baraja tiene que quedarse exactamente como estaba
	# antes de M5, o el hito habría cambiado el juego de quien no tenía el problema.
	var gm = _new_gm(file_data);
	var estandar = StubPlayer.new();
	estandar.availableFactories = paquetes["standard"]["factories"].duplicate();
	gm.setPlayer(estandar);
	_check("en standard la mejora nueva no entra siquiera en la baraja",
		not gm._usable_upgrades().has(rescate), "baraja %s" % str(gm._usable_upgrades()));
	var vista_en_standard = false;
	for i in range(60):
		if gm._pick_upgrades(3, 1).has(rescate) or gm._pick_upgrades(3, 2).has(rescate):
			vista_en_standard = true;
	_check("y en 120 pantallas de standard no sale ni una vez", not vista_en_standard);
	_check("standard no ve tampoco ninguna carta fijada (nada que desatascar)",
		gm._rescue_upgrades(gm._usable_upgrades()).is_empty());

	# Los dos paquetes que no la traen: la carta tiene que salir SIEMPRE, no cuando toque.
	# 60 pantallas por paquete y tier: si dependiera del shuffle, con seis cartas de tier 1
	# se caería en la mitad de las tiradas.
	for paquete in ["lumberjack", "ecologist"]:
		var jugador = StubPlayer.new();
		jugador.availableFactories = paquetes[paquete]["factories"].duplicate();
		gm.setPlayer(jugador);
		var siempre = true;
		for i in range(60):
			if not gm._pick_upgrades(3, 1).has(rescate) or not gm._pick_upgrades(3, 2).has(rescate):
				siempre = false;
		_check("en %s la carta que desatasca sale en las 120 pantallas" % paquete, siempre);
		var tres = gm._pick_upgrades(3, 1);
		_check("y la pantalla sigue ofreciendo 3 cartas distintas en %s" % paquete,
			tres.size() == 3 and _sin_repetidas(tres), "salieron %s" % str(tres));
		# La llamada sin tier de las ruinas (Main.gd) es la segunda oportunidad: una sola
		# carta, y con la run atascada tiene que ser justo la que la desatasca.
		var ruinas = gm._pick_upgrades(1);
		_check("las ruinas de %s dan esa misma carta" % paquete,
			ruinas == [rescate], "salió %s" % str(ruinas));

	# En cuanto se desbloquea —por esta carta o por el factory token— deja de fijarse y la
	# baraja vuelve a la normalidad: el rescate es para salir del atasco, no un peaje eterno.
	var lenador = StubPlayer.new();
	lenador.availableFactories = paquetes["lumberjack"]["factories"].duplicate();
	gm.setPlayer(lenador);
	lenador.availableFactories.append("WoodProcessing");
	var tras_desbloquear = gm._pick_upgrades(3, 2);
	_check("tras conseguir WoodProcessing la carta desaparece de la baraja",
		not tras_desbloquear.has(rescate) and _todas_de_tier(catalogo, tras_desbloquear, 2),
		"salieron %s" % str(tras_desbloquear));

	# La garantía se deriva de la curva, no del nombre de nadie: con checkpoints que solo
	# piden madera —que lumberjack sí sabe fabricar— no hay nada que desatascar.
	var gm_solo_madera = _new_gm(file_data, [
		{ "material": "wood", "quantity": 15, "label": "Único" },
		{ "material": "wood", "quantity": 30, "label": "Final" }
	]);
	var lenador2 = StubPlayer.new();
	lenador2.availableFactories = paquetes["lumberjack"]["factories"].duplicate();
	gm_solo_madera.setPlayer(lenador2);
	_check("con una curva que solo pide madera no se fija ninguna carta",
		gm_solo_madera._rescue_upgrades(gm_solo_madera._usable_upgrades()).is_empty());
	# Y al revés: el mantenimiento cuenta igual que el objetivo, porque desde M4 los dos son
	# requisito para cerrar el checkpoint.
	var gm_mantenimiento = _new_gm(file_data, [
		{ "material": "wood", "quantity": 15, "label": "Único", "maintenance": { "plank": 5 } }
	]);
	gm_mantenimiento.setPlayer(lenador2);
	_check("un material que solo pide el mantenimiento también fija la carta",
		gm_mantenimiento._rescue_upgrades(gm_mantenimiento._usable_upgrades()) == [rescate]);

	# Un montaje a medias (sin Player) no puede fijar nada: se seguiría ofreciendo el catálogo
	# entero, que es lo que hacía antes de este filtro.
	var gm_sin_jugador = _new_gm(file_data);
	_check("sin Player no se fija ninguna carta",
		gm_sin_jugador._rescue_upgrades(gm_sin_jugador._usable_upgrades()).is_empty());
	var potentes = gm_sin_jugador._pick_upgrades(3, 2);
	_check("y pedir tier 2 sin Player sigue dando 3 cartas potentes",
		potentes.size() == 3 and _todas_de_tier(catalogo, potentes, 2), "salieron %s" % str(potentes));

	# La puerta real: aplicar la carta por Main._apply_upgrade() deja la procesadora en el
	# Player, que es de donde tira el radial de construcción.
	var main = _new_main_de_prueba(file_data);
	var jugador_main = main.get_node("Player");
	jugador_main.availableFactories = paquetes["lumberjack"]["factories"].duplicate();
	main._apply_upgrade(rescate);
	_check("aplicarla por la puerta real añade WoodProcessing al Player",
		jugador_main.availableFactories.has("WoodProcessing"),
		"quedó %s" % str(jugador_main.availableFactories));

	_limpiar([gm, gm_solo_madera, gm_mantenimiento, gm_sin_jugador, main]);

# ---------- Tensión M7: el tier se mide contra la línea que tienes puesta ----------

func _test_tm7_linea(file_data):
	print("Tensión M7 — el tier mide tu propia línea, no una factoría imaginaria");
	var liston = load("res://managers/gameManager.gd").TIER2_EFFICIENCY;
	# Un listón fuera de este rango no sería una decisión de balance sino un interruptor:
	# por debajo lo pasa cualquier fábrica y por encima no lo pasa ninguna, que son los dos
	# extremos que M7 vino a quitar.
	_check("el listón de rendimiento es exigible y alcanzable", liston >= 0.4 and liston <= 0.8,
		"TIER2_EFFICIENCY = %f" % liston);

	var gm = _new_gm(file_data);
	var cp = { "material": "plank", "quantity": 60 };
	var sierra_a = _new_productora("WoodProcessing", "plank", 3);
	var sierra_b = _new_productora("WoodProcessing", "plank", 3);
	var cortadora = _new_productora("WoodCutter", "wood", 4);
	var linea = [sierra_a, sierra_b, cortadora];
	gm.setFactories(linea);

	_check("el techo suma output/tick de las que producen ESE material",
		_near(gm._installed_rate("plank"), 2.0 / 3.0), "%f" % gm._installed_rate("plank"));
	_check("y no cuenta las que producen otra cosa",
		_near(gm._installed_rate("wood"), 0.25), "%f" % gm._installed_rate("wood"));
	# Main._apply_upgrade() suma a outputAmount de las factorías ya puestas: la carta potente
	# sube el techo el mismo día que se coge, y quien no la alimente baja de tier.
	sierra_a.outputAmount += 1;
	_check("una mejora de output sube el techo al instante",
		_near(gm._installed_rate("plank"), 1.0), "%f" % gm._installed_rate("plank"));
	sierra_a.outputAmount -= 1;
	# Se guarda el array de Main, no una copia: construir durante la partida se ve solo.
	var sierra_c = _new_productora("WoodProcessing", "plank", 3);
	linea.append(sierra_c);
	_check("construir durante la run se ve sin volver a inyectar nada",
		_near(gm._installed_rate("plank"), 1.0), "%f" % gm._installed_rate("plank"));
	linea.erase(sierra_c);

	# LA PRUEBA DEL HITO: el mismo tramo, con el mismo objetivo, da tier distinto según la
	# línea que estuviera puesta. Con dos serrerías el techo son 90 s y 120 s es buen ritmo;
	# con seis el techo baja a 30 s y esos mismos 120 s son media fábrica parada.
	var ritmo_corto = gm._installed_rate("plank");          # 0,667 plank/s → techo 90 s
	var ritmo_largo = 3.0 * ritmo_corto;                    # 2,0 plank/s   → techo 30 s
	_check("con línea corta y bien alimentada, 120 s de tramo son recompensa potente",
		gm._evaluate_performance(cp, 120.0, 0, ritmo_corto) == 2);
	_check("con el triple de línea, ESOS MISMOS 120 s son recompensa corriente",
		gm._evaluate_performance(cp, 120.0, 0, ritmo_largo) == 1);
	# Y el listón se respeta a los dos lados, sea cual sea la constante.
	var techo = 60.0 / ritmo_largo;
	_check("justo por debajo del listón, recompensa potente",
		gm._evaluate_performance(cp, techo / liston * 0.95, 0, ritmo_largo) == 2);
	_check("justo por encima, corriente",
		gm._evaluate_performance(cp, techo / liston * 1.05, 0, ritmo_largo) == 1);

	# La vara de M2 —la factoría base, 180 s para 60 tablones— ya no decide sola: batirla no
	# basta si tu propia línea podía haber ido mucho más rápido. Es exactamente el defecto
	# que M7 vino a arreglar.
	_check("batir la referencia de la factoría base ya no garantiza el tier 2",
		gm._reference_time(cp) > 120.0 and gm._evaluate_performance(cp, 120.0, 0, ritmo_largo) == 1,
		"referencia base = %f" % gm._reference_time(cp));
	# Pero sin línea que medir se conserva la regla de M2 tal cual: un montaje sin factorías
	# —o una llamada directa desde una prueba— no puede quedarse sin criterio.
	_check("sin línea medida se juzga con la factoría base, como en M2",
		gm._evaluate_performance(cp, 170.0, 0, 0.0) == 2
		and gm._evaluate_performance(cp, 190.0, 0, 0.0) == 1);
	_check("un objetivo que ya venía hecho sigue sin tener ritmo que premiar",
		gm._evaluate_performance(cp, 1.0, 60, ritmo_corto) == 1);
	_limpiar([gm, sierra_a, sierra_b, sierra_c, cortadora]);

	# Y ahora conduciendo update(), que es quien muestrea el techo de verdad.
	var gm2 = _new_gm(file_data, [
		{ "material": "plank", "quantity": 40, "label": "Uno" },
		{ "material": "plank", "quantity": 40, "label": "Dos" },
		{ "material": "plank", "quantity": 40, "label": "Tres" }
	]);
	var bag = _new_bag();
	bag.initialize(file_data);
	var catalogo = file_data["Upgrades"];
	var ofertas = [];
	gm2.checkpoint_reached.connect(func(ids, _r, _g): ofertas.append(ids));
	var primera = _new_productora("WoodProcessing", "plank", 2);    # 0,5 plank/s
	var segunda = _new_productora("WoodProcessing", "plank", 2);
	var fabrica = [primera];
	gm2.setFactories(fabrica);
	for i in range(20):
		gm2.run_time = float(i + 1);
		gm2.update(bag);
	_check("el techo del tramo es el de la línea que estuvo puesta",
		_near(gm2._segment_rate(), 0.5), "ritmo medido = %f" % gm2._segment_rate());
	# Doblar la línea a mitad de tramo no se juzga como si hubiera estado desde el principio:
	# la media va ponderada por tiempo, o el criterio castigaría crecer, que es el juego.
	fabrica.append(segunda);
	for i in range(20):
		gm2.run_time = float(21 + i);
		gm2.update(bag);
	_check("construir a mitad de tramo pesa solo el rato que estuvo construido",
		_near(gm2._segment_rate(), 0.75), "ritmo medido = %f" % gm2._segment_rate());

	# Cierre del checkpoint: 40 tablones en 40 s con un techo medio de 0,75/s —53,3 s si nada
	# la hubiera parado— es una línea que ha rendido por encima de su techo teórico, porque
	# la mitad de ella se construyó a mitad de camino. Recompensa potente con cualquier listón.
	bag.addToBag("plank", 40);
	gm2.update(bag);
	_check("un tramo que sostiene su techo ofrece mejoras potentes",
		ofertas.size() == 1 and _todas_de_tier(catalogo, ofertas[0], 2),
		"ofrecidas %s" % str(ofertas));
	_check("y el tramo siguiente empieza a medir su línea desde cero",
		_near(gm2.segment_capacity_area, 0.0) and _near(gm2.segment_capacity_time, 0.0),
		"area = %f, tiempo = %f" % [gm2.segment_capacity_area, gm2.segment_capacity_time]);

	# El mismo checkpoint, el mismo tiempo, pero con una línea ocho veces mayor parada casi
	# entera: la recompensa baja a corriente.
	gm2.resume_after_upgrade();
	for i in range(6):
		fabrica.append(_new_productora("WoodProcessing", "plank", 1, 2));
	for i in range(200):
		gm2.run_time = float(41 + i);
		gm2.update(bag);
	bag.addToBag("plank", 40);
	gm2.update(bag);
	_check("una línea enorme y parada ofrece mejoras corrientes",
		ofertas.size() == 2 and _todas_de_tier(catalogo, ofertas[1], 1),
		"ofrecidas %s" % str(ofertas));

	gm2.reset();
	_check("reset() olvida el techo acumulado",
		_near(gm2.segment_capacity_area, 0.0) and _near(gm2.segment_capacity_time, 0.0)
		and _near(gm2.last_capacity_sample, 0.0),
		"area = %f, tiempo = %f, muestra = %f" % [gm2.segment_capacity_area,
			gm2.segment_capacity_time, gm2.last_capacity_sample]);

	var sueltas = [gm2, bag, primera, segunda];
	for f in fabrica:
		if not sueltas.has(f):
			sueltas.append(f);
	_limpiar(sueltas);

# ---------- Tensión M9: el radial anuncia lo que daría construir ahí ----------

func _test_tm9_preview(fd):
	print("Tensión M9 — sinergias anticipadas al abrir el radial");
	var placer = load("res://entities/factory/factoryPlacer.gd").new();
	var arr = [];
	placer.initialize(null, fd, arr);
	var stub = StubTileMap.new();

	var wp = _new_factory("WoodProcessing", Vector2i(2, 3));
	arr.append(wp);

	# La casilla del hito: pegada a una WoodProcessing, que concede +1 output al WoodCutter.
	var pegada = placer.preview_synergies("WoodCutter", Vector2i(1, 3), stub);
	_check("casilla pegada a WoodProcessing: el WoodCutter anuncia su +1 output",
		pegada["output_bonus"] == 1 and pegada["tick_bonus"] == 0
		and _near(pegada["pollution_mult"], 1.0), str(pegada));
	_check("y anuncia que mejoraría a la vecina, que es la otra mitad del factor 5",
		pegada["gives_to"] == 1, str(pegada));

	# La casilla de control: sin vecinas ni tipo de casilla no hay nada que prometer.
	var aislada = placer.preview_synergies("WoodCutter", Vector2i(6, 6), stub);
	_check("casilla aislada: la consulta no promete nada",
		aislada["output_bonus"] == 0 and aislada["tick_bonus"] == 0
		and _near(aislada["pollution_mult"], 1.0) and aislada["gives_to"] == 0, str(aislada));

	# La casilla también cuenta: el arroyo acelera a cualquiera (adjacency_bonus "*").
	var stub_tiles = StubTileMap.new();
	stub_tiles.defs[Vector2i(9, 1)] = fd["TileTypes"]["stream"];
	stub_tiles.defs[Vector2i(5, 4)] = fd["TileTypes"]["fertile"];
	_check("el tipo de casilla entra en la consulta: el arroyo acelera a cualquiera",
		placer.preview_synergies("MetaFactory", Vector2i(9, 1), stub_tiles)["tick_bonus"] == 1);
	_check("y la tierra fértil solo al Reforester",
		placer.preview_synergies("Reforester", Vector2i(5, 4), stub_tiles)["output_bonus"] == 2
		and placer.preview_synergies("WoodCutter", Vector2i(5, 4), stub_tiles)["output_bonus"] == 0);

	# Un pollution_mult, que es el bonus que no se puede revertir dividiendo y por el que la
	# consulta no aplica-y-deshace.
	var ref_vecino = _new_factory("Reforester", Vector2i(7, 1));
	arr.append(ref_vecino);
	var junto_a_ref = placer.preview_synergies("Reforester", Vector2i(8, 1), stub);
	_check("dos Reforester juntos: la consulta anticipa el ×1.25 de limpieza",
		_near(junto_a_ref["pollution_mult"], 1.25) and junto_a_ref["gives_to"] == 1,
		str(junto_a_ref));

	# Consultar no es colocar: ni el estado de las vecinas ni el array se mueven.
	var antes = [wp.synergy_tick_bonus, wp.synergy_output_bonus, wp.synergy_pollution_mult,
		ref_vecino.synergy_pollution_mult, arr.size()];
	for i in range(10):
		placer.preview_synergies("WoodCutter", Vector2i(1, 3), stub);
		placer.preview_synergies("Reforester", Vector2i(8, 1), stub);
	_check("consultar 20 veces no toca a las vecinas ni mete nada en el array",
		antes == [wp.synergy_tick_bonus, wp.synergy_output_bonus, wp.synergy_pollution_mult,
			ref_vecino.synergy_pollution_mult, arr.size()],
		"antes %s, después %s" % [str(antes), str([wp.synergy_tick_bonus,
			wp.synergy_output_bonus, wp.synergy_pollution_mult,
			ref_vecino.synergy_pollution_mult, arr.size()])]);

	# Y lo anunciado es exactamente lo que se aplica al construir de verdad: si divergen, el
	# radial estaría vendiendo una casilla distinta de la que se coloca.
	var wc = _new_factory("WoodCutter", Vector2i(1, 3));
	placer._apply_tile_adjacency_bonus(wc, "WoodCutter", Vector2i(1, 3), stub);
	placer.register_and_evaluate(wc, Vector2i(1, 3));
	_check("lo anticipado es lo que se aplica al colocar",
		wc.synergy_output_bonus == pegada["output_bonus"]
		and wc.synergy_tick_bonus == pegada["tick_bonus"]
		and _near(wc.synergy_pollution_mult, pegada["pollution_mult"]),
		"aplicado %d/%d/%f" % [wc.synergy_output_bonus, wc.synergy_tick_bonus,
			wc.synergy_pollution_mult]);
	_check("y el gives_to anunciado se materializa en la vecina",
		wp.synergy_tick_bonus == 1, "tick de la vecina = %d" % wp.synergy_tick_bonus);

	# La redacción que ve el jugador, con el vocabulario del tooltip.
	var radial = load("res://ui/radialMenu.gd").new();
	var lineas = radial._synergy_lines(pegada);
	_check("el radial lo redacta como el tooltip",
		lineas == ["✦ Output +1", "✦ Mejora 1 vecina"], str(lineas));
	_check("sobre casilla aislada el radial no escribe ni una línea",
		radial._synergy_lines(aislada).is_empty(), str(radial._synergy_lines(aislada)));
	_check("un tick_bonus positivo se redacta como resta de segundos, igual que en el tooltip",
		radial._synergy_lines({ "tick_bonus": 2 }) == ["✦ Tick -2s"]);
	_check("y el multiplicador de contaminación con su palabra",
		radial._synergy_lines({ "pollution_mult": 1.25 }) == ["✦ Contam. ×1.25"]);

	# El menú montado entero: el texto que sale por pantalla y el click, que es lo que no se
	# puede romper por meterle labels dentro al botón.
	root.add_child(radial);
	radial.initialize(["WoodCutter", "Reforester"], fd, Vector2i(1, 3), Vector2(640, 360),
		{ "WoodCutter": pegada });
	var botones = radial.find_children("", "Button", true, false);
	var textos = [];
	var pasan_el_raton = true;
	for b in botones:
		var t = [];
		for l in b.find_children("", "Label", true, false):
			t.append(l.text);
			pasan_el_raton = pasan_el_raton and l.mouse_filter == Control.MOUSE_FILTER_IGNORE;
		for c in b.find_children("", "Container", true, false):
			pasan_el_raton = pasan_el_raton and c.mouse_filter == Control.MOUSE_FILTER_IGNORE;
		textos.append(t);
	# El precio (Costes M5) entra entre lo que cuesta y lo que se gana: sin diccionario de
	# asequibilidad todo se puede pagar, así que aquí sale en su redacción normal.
	_check("el botón anuncia el precio y la sinergia bajo el nombre y el material",
		textos[0] == ["WoodCutter", "→ wood", "Coste: 4 wood", "✦ Output +1", "✦ Mejora 1 vecina"],
		str(textos));
	_check("y una de restauración dice «(restauración)», no «<null>» (material null en el JSON)",
		textos[1] == ["Reforester", "(restauración)", "Coste: 6 wood"], str(textos));
	_check("las labels y su contenedor dejan pasar el ratón: el click sigue siendo del botón",
		pasan_el_raton);
	var elegidas = [];
	radial.factory_chosen.connect(func(tipo, celda): elegidas.append([tipo, celda]));
	botones[0].pressed.emit();
	_check("pulsar el botón sigue eligiendo su factoría para esta casilla",
		elegidas == [["WoodCutter", Vector2i(1, 3)]], str(elegidas));

	# radial se ha pedido a sí mismo queue_free() al elegir: no se suelta a mano.
	_limpiar([placer, wp, wc, ref_vecino]);

# ---------- M5: la restauración se reparte en área ----------

func _test_m5_reparto():
	print("M5 — restauración repartida sobre 9 casillas");
	var pm = _new_pm();
	var propia = Vector2i(5, 5);
	var vecina = Vector2i(6, 6);
	var lejana = Vector2i(0, 0);
	pm.addPollution(5.0, propia);
	pm.addPollution(5.0, vecina);
	pm.addPollution(5.0, lejana);
	var total_antes = pm.total_pollution;

	var f = _new_factory_en_arbol("Reforester", propia, pm);
	f.factory_type = "restoration";
	f.pollutionAmount = -9.0;      # 9 celdas x 1.0 cada una
	f._apply_pollution(1.0);

	_check("la celda propia se limpia 1.0", _near(pm.pollution_per_cell[propia], 4.0),
		"quedó %f" % pm.pollution_per_cell[propia]);
	_check("una vecina en diagonal también se limpia 1.0", _near(pm.pollution_per_cell[vecina], 4.0),
		"quedó %f" % pm.pollution_per_cell[vecina]);
	_check("una celda lejana NO se toca", _near(pm.pollution_per_cell[lejana], 5.0),
		"quedó %f" % pm.pollution_per_cell[lejana]);
	# Antes de M0.5 el global bajaba 9.0 aunque solo dos casillas tuvieran suciedad. Ahora
	# baja exactamente lo que se ha quitado de las casillas: 1.0 de la propia + 1.0 de la vecina.
	_check("el global baja solo lo quitado de las casillas (1.0 + 1.0)",
		_near(total_antes - pm.total_pollution, 2.0),
		"bajó %f" % (total_antes - pm.total_pollution));

	# Ojo: _apply_pollution() localiza el manager con find_child("PollutionManager"), que devuelve
	# el PRIMERO del árbol. Hay que soltar el anterior antes de montar el segundo escenario.
	_limpiar([f, pm]);

	# Lo que M5 venía a hacer posible: que una casilla toxic vecina llegue a 0.
	var pm2 = _new_pm();
	var toxica = Vector2i(5, 4);
	pm2.addPollution(2.0, toxica);
	var f2 = _new_factory_en_arbol("Reforester", propia, pm2);
	f2.factory_type = "restoration";
	f2.pollutionAmount = -9.0;
	for i in range(3):
		f2._apply_pollution(1.0);
	_check("una casilla toxic vecina llega a 0 (desbloqueo alcanzable)",
		_near(pm2.getCellPollution(toxica), 0.0),
		"contaminación local normalizada = %f" % pm2.getCellPollution(toxica));

	_limpiar([f2, pm2]);

# ---------- M4: una factoría por casilla ----------

func _test_m4_colocacion():
	print("M4 — reglas de colocación");
	var escena = load("res://entities/tilemap/tile_map.tscn");
	if escena == null:
		_check("tile_map.tscn cargable", false, "no se pudo cargar la escena");
		return;
	var tm = escena.instantiate();
	root.add_child(tm);

	var libre = Vector2i(2, 2);
	var sin_tile = Vector2i(40, 40);
	tm.set_cell(0, libre, 1, Vector2i(0, 0));

	_check("celda con tile y libre -> se puede construir", tm.canPlaceFactory(libre, []) == true);
	_check("celda sin tile -> no se puede", tm.canPlaceFactory(sin_tile, []) == false);

	var ocupante = _new_factory("WoodCutter", libre);
	_check("celda ya ocupada -> no se puede (fin del apilado)",
		tm.canPlaceFactory(libre, [ocupante]) == false);

	tm.cell_types = { libre: "toxic" };
	tm.tile_type_data = { "toxic": { "buildable": false } };
	_check("casilla toxic -> no se puede construir", tm.canPlaceFactory(libre, []) == false);

	_limpiar([tm, ocupante]);

	# ---------- Costes M7: la casilla saturada admite limpieza, no producción ----------
	# `cell_block_pollution` existe para impedir que levantes una FÁBRICA sobre suelo muerto,
	# no para impedir que lo LIMPIES. Sin esta excepción, el mapa que más necesita un
	# Reforester es justo el único donde no cabe y la fase 2 de una run sucia no la gana
	# nadie. Esta prueba fija esa relación.
	var tm7 = escena.instantiate();
	root.add_child(tm7);
	var pm7 = _new_pm();
	tm7.setPollutionManager(pm7);
	var sucia = Vector2i(4, 4);
	var limpia = Vector2i(6, 4);
	tm7.set_cell(0, sucia, 1, Vector2i(0, 0));
	tm7.set_cell(0, limpia, 1, Vector2i(0, 0));
	pm7.addPollution(pm7.cell_block_pollution, sucia);
	_check("la casilla saturada sigue cerrada a la producción",
		tm7.canPlaceFactory(sucia, [], "production") == false);
	_check("pero admite una factoría de restauración: limpiar es la salida",
		tm7.canPlaceFactory(sucia, [], "restoration") == true);
	_check("el almacén no limpia, así que la saturada le sigue cerrada",
		tm7.canPlaceFactory(sucia, [], "storage") == false);
	_check("y sin tipo la respuesta es la estricta de siempre (regresión)",
		tm7.canPlaceFactory(sucia, []) == false);
	# La excepción es SOLO la condición 2. Las otras cuatro siguen valiendo para quien limpia,
	# o la regla nueva sería una puerta de atrás a todas las reglas de colocación.
	_check("la excepción no alcanza a la casilla fuera del mapa",
		tm7.canPlaceFactory(Vector2i(40, 40), [], "restoration") == false);
	var ocupante7 = _new_factory("Reforester", sucia);
	_check("ni a la casilla ya ocupada",
		tm7.canPlaceFactory(sucia, [ocupante7], "restoration") == false);
	var red7 = StubBeltNetwork.new();
	red7.cells[sucia] = true;
	tm7.setBeltNetwork(red7);
	_check("ni a la casilla con cinta",
		tm7.canPlaceFactory(sucia, [], "restoration") == false);
	tm7.setBeltNetwork(null);
	tm7.cell_types = { sucia: "toxic" };
	tm7.tile_type_data = { "toxic": { "buildable": false } };
	_check("ni a la casilla `toxic`, que se limpia desde las vecinas y no desde encima",
		tm7.canPlaceFactory(sucia, [], "restoration") == false);
	tm7.cell_types = {};
	# Y sobre suelo limpio la respuesta no depende del tipo: la regla nueva no toca nada de
	# lo que ya funcionaba.
	_check("sobre casilla limpia caben las tres clases, igual que antes de M7",
		tm7.canPlaceFactory(limpia, [], "production")
		and tm7.canPlaceFactory(limpia, [], "restoration")
		and tm7.canPlaceFactory(limpia, [], "storage")
		and tm7.canPlaceFactory(limpia, []));
	# El puente del click que abre el radial: pregunta por la clase más permisiva y por eso
	# la saturada SÍ abre menú, que es lo que deja al jugador poner ahí el Reforester.
	_check("canPlaceAnyFactory() abre la saturada", tm7.canPlaceAnyFactory(sucia, []) == true);
	_check("y sigue cerrando lo que no es del mapa",
		tm7.canPlaceAnyFactory(Vector2i(40, 40), []) == false);
	# 🔴 Y LA CONDICIÓN 3 DEL PUNTO MUERTO NO SE MUEVE: hasBuildableCell() pregunta por la
	# regla estricta. Con la permisiva, un mapa saturado siempre tendría dónde poner un
	# Reforester, la condición 3 sería inalcanzable y la derrota por punto muerto —de la que
	# cuelga el criterio de `contagion_rate`— dejaría de poder cumplirse.
	pm7.addPollution(pm7.cell_block_pollution, limpia);
	_check("un mapa entero saturado sigue sin tener casilla construible (punto muerto)",
		tm7.hasBuildableCell([]) == false);
	_check("aunque un Reforester sí cabría en él",
		tm7.canPlaceFactory(sucia, [], "restoration") == true);

	_limpiar([tm7, pm7, ocupante7]);

# ---------- M6: las sinergias se revierten al demoler ----------

func _test_m6_revertir(fd):
	print("M6 — revertir sinergias al demoler");
	var placer = load("res://entities/factory/factoryPlacer.gd").new();
	var arr = [];
	placer.initialize(null, fd, arr);
	var stub = StubTileMap.new();

	var wc = _new_factory("WoodCutter", Vector2i(1, 1));
	var wp = _new_factory("WoodProcessing", Vector2i(2, 1));
	wp.tickTimer = 3;
	arr.append(wc);
	arr.append(wp);
	placer.recompute_synergies(wp, stub);
	var con_vecino = wp.getEffectiveTick();

	# Se demuele el WoodCutter: sale del array y se recalcula la vecina.
	arr.erase(wc);
	placer.recompute_synergies(wp, stub);
	_check("con vecino acelera y al demolerlo vuelve al tick base",
		con_vecino == 2 and wp.getEffectiveTick() == 3,
		"con vecino %d, tras demoler %d (base 3)" % [con_vecino, wp.getEffectiveTick()]);

	# Repetir colocar/demoler no debe acumular nada (era el exploit).
	for i in range(5):
		arr.append(wc);
		placer.recompute_synergies(wp, stub);
		arr.erase(wc);
		placer.recompute_synergies(wp, stub);
	_check("colocar y demoler 5 veces no acumula bonus (exploit cerrado)",
		wp.getEffectiveTick() == 3 and wp.synergy_tick_bonus == 0,
		"tick %d, acumulador %d" % [wp.getEffectiveTick(), wp.synergy_tick_bonus]);

	_limpiar([placer, wc, wp]);

# ---------- M6: el recálculo NO borra el bonus de la casilla ----------

func _test_m6_conserva_tile(fd):
	print("M6 — el recálculo conserva el bonus del tile");
	var placer = load("res://entities/factory/factoryPlacer.gd").new();
	var arr = [];
	placer.initialize(null, fd, arr);

	var celda = Vector2i(1, 1);
	var stub = StubTileMap.new();
	stub.defs[celda] = fd["TileTypes"]["forest"];   # +1 output a WoodCutter

	var wc = _new_factory("WoodCutter", celda);
	wc.outputAmount = 1;
	arr.append(wc);

	placer.recompute_synergies(wc, stub);
	_check("WoodCutter sobre forest conserva su +1 output tras recalcular",
		wc.getEffectiveOutput() == 2,
		"output efectivo = %d (esperado 2)" % wc.getEffectiveOutput());

	# Y recalcular N veces no lo multiplica ni lo pierde.
	for i in range(4):
		placer.recompute_synergies(wc, stub);
	_check("recalcular 5 veces deja el mismo bonus de tile (idempotente)",
		wc.getEffectiveOutput() == 2,
		"output efectivo = %d" % wc.getEffectiveOutput());

	_limpiar([placer, wc]);

# ---------- UI M1: asignar y desasignar workers sin demoler ----------

# El caso que hasta hoy obligaba a demoler, entero y con los nodos de verdad: la MetaFactory
# (2 workers) construida primero se lleva los dos únicos workers de la bolsa, así que la
# WoodProcessing que viene detrás sale inactiva y la única salida era demoler una de las dos.
# Se conduce por los botones del panel, no llamando a la Bag a mano: lo que se prueba es el
# camino que pulsa el jugador, incluida la invariante de que los DOS contadores de workers
# —el de la factoría y el de la bolsa— se mueven siempre juntos.
func _test_ui_m1_workers(fd):
	print("UI M1 — reasignar workers desde el panel de la factoría");
	var main = _new_main_de_prueba(fd);
	var tile_map = main.get_node("TileMap");
	var jugador = main.get_node("Player");
	var bag = _new_bag();
	bag.initialize(fd);
	_check("el escenario arranca con los 2 workers que reparte el JSON",
		bag.workers_total == 2 and bag.getFreeWorkers() == 2,
		"total %d, libres %d" % [bag.workers_total, bag.getFreeWorkers()]);

	var arr = [];
	var placer = load("res://entities/factory/factoryPlacer.gd").new();
	placer.initialize(load("res://entities/factory/factory.tscn"), fd, arr);
	# Celdas lejanas y no adyacentes entre sí: ni se conceden sinergias ni se cruzan con la
	# contaminación que hayan sembrado las pruebas anteriores. Lo segundo importa porque
	# _apply_pollution() y getPollutionChoke() localizan el PRIMER PollutionManager del árbol,
	# así que un ahogo heredado bajaría la producción y esta prueba mediría otra cosa.
	var meta = placer.build("MetaFactory", Vector2i(60, 60), jugador, bag, tile_map);
	arr.append(meta);
	root.add_child(meta);
	_check("la MetaFactory construida primero se lleva los dos workers y arranca activa",
		meta.workers_assigned == 2 and meta.isActive() and bag.getFreeWorkers() == 0,
		"asignados %d, libres %d" % [meta.workers_assigned, bag.getFreeWorkers()]);

	var sierra = placer.build("WoodProcessing", Vector2i(64, 60), jugador, bag, tile_map);
	arr.append(sierra);
	root.add_child(sierra);
	_check("y la WoodProcessing que viene detrás sale inactiva, sin un solo worker",
		sierra.workers_assigned == 0 and not sierra.isActive() and bag.getFreeWorkers() == 0,
		"asignados %d, libres %d" % [sierra.workers_assigned, bag.getFreeWorkers()]);

	# Insumos para las dos, para mirar quién produce de verdad y no solo quién se declara activa.
	# Desde Cintas M2 el insumo entra por el BÚFER —lo que le ha traído una cinta— y lo
	# producido se cuenta en `resource_produced`, porque producir ya no llena la bolsa.
	meta.input_buffer = { "plank": 10 };
	sierra.input_buffer = { "wood": 10 };
	var tokens = [0];
	var tablones = [0];
	meta.resource_produced.connect(func(_mat, cantidad, _pos): tokens[0] += cantidad);
	sierra.resource_produced.connect(func(_mat, cantidad, _pos): tablones[0] += cantidad);
	meta.update();
	sierra.update();
	_check("de partida produce la MetaFactory y la serrería no",
		tokens[0] == 1 and tablones[0] == 0 and meta.input_buffer["plank"] == 9
		and sierra.input_buffer["wood"] == 10,
		"token %d, plank %d, búfer meta %d, búfer sierra %d" % [tokens[0], tablones[0],
			meta.input_buffer["plank"], sierra.input_buffer["wood"]]);

	# --- El panel de la MetaFactory: se le quita un worker ---
	var panel_meta = load("res://ui/factoryPanel.gd").new();
	root.add_child(panel_meta);
	panel_meta.initialize(meta, fd, Vector2(640, 360), bag);
	var botones = panel_meta.find_children("", "Button", true, false);
	_check("el panel de una factoría con workers monta los dos botones",
		botones.size() == 2 and botones[0].text == "− 1 worker" and botones[1].text == "+ 1 worker",
		str(botones.map(func(b): return b.text)));
	_check("con la bolsa sin libres, «+ 1 worker» sale apagado y «− 1 worker» encendido",
		botones[1].disabled and not botones[0].disabled);

	botones[0].pressed.emit();
	_check("quitarle un worker detiene la MetaFactory y lo devuelve a la bolsa",
		meta.workers_assigned == 1 and not meta.isActive() and bag.getFreeWorkers() == 1,
		"asignados %d, libres %d" % [meta.workers_assigned, bag.getFreeWorkers()]);
	_check("los dos contadores siguen cuadrando: la bolsa ni inventa ni pierde workers",
		bag.workers_assigned == meta.workers_assigned + sierra.workers_assigned,
		"bolsa %d, factorías %d" % [bag.workers_assigned,
			meta.workers_assigned + sierra.workers_assigned]);
	_check("el panel se repinta in situ en vez de remontarse: sigue vivo y ya dice 1/2",
		not panel_meta.is_queued_for_deletion()
		and panel_meta._workers_label.text == "Workers: 1/2"
		and panel_meta._blocked_label.visible, panel_meta._workers_label.text);

	# --- El panel de la WoodProcessing: se le da ese worker ---
	var panel_sierra = load("res://ui/factoryPanel.gd").new();
	root.add_child(panel_sierra);
	panel_sierra.initialize(sierra, fd, Vector2(640, 360), bag);
	var botones_s = panel_sierra.find_children("", "Button", true, false);
	_check("con un worker libre en la bolsa, la serrería puede pedirlo",
		not botones_s[1].disabled and botones_s[0].disabled);
	botones_s[1].pressed.emit();
	_check("dárselo a la WoodProcessing la activa y deja la bolsa a cero libres",
		sierra.workers_assigned == 1 and sierra.isActive() and bag.getFreeWorkers() == 0,
		"asignados %d, libres %d" % [sierra.workers_assigned, bag.getFreeWorkers()]);
	_check("y la MetaFactory sigue detenida: el worker está en una, no en las dos",
		not meta.isActive()
		and bag.workers_assigned == meta.workers_assigned + sierra.workers_assigned,
		"bolsa %d, factorías %d" % [bag.workers_assigned,
			meta.workers_assigned + sierra.workers_assigned]);

	meta.update();
	sierra.update();
	_check("tras reasignar produce la serrería y la MetaFactory se ha detenido",
		tokens[0] == 1 and tablones[0] == 1 and meta.input_buffer["plank"] == 9
		and sierra.input_buffer["wood"] == 9,
		"token %d, plank %d, búfer meta %d, búfer sierra %d" % [tokens[0], tablones[0],
			meta.input_buffer["plank"], sierra.input_buffer["wood"]]);

	# --- Los dos extremos, que son los que descuadran la bolsa si no se miran ---
	var antes = [bag.workers_assigned, sierra.workers_assigned];
	_check("sin libres, asignar no mueve ni el contador de la bolsa ni el de la factoría",
		panel_sierra.assign_one() == false
		and [bag.workers_assigned, sierra.workers_assigned] == antes, str(antes));
	panel_sierra.unassign_one();
	_check("devolver el único worker deja la serrería a 0 y la bolsa con 1 libre",
		sierra.workers_assigned == 0 and not sierra.isActive() and bag.getFreeWorkers() == 1,
		"asignados %d, libres %d" % [sierra.workers_assigned, bag.getFreeWorkers()]);
	_check("y volver a desasignar a 0 no le roba a la bolsa un worker que está en la otra",
		panel_sierra.unassign_one() == false and bag.workers_assigned == 1
		and bag.getFreeWorkers() == 1,
		"asignados en bolsa %d, libres %d" % [bag.workers_assigned, bag.getFreeWorkers()]);

	# Una factoría que no necesita workers no enseña el bloque: nada que repartir.
	var cortadora = placer.build("WoodCutter", Vector2i(68, 60), jugador, bag, tile_map);
	arr.append(cortadora);
	root.add_child(cortadora);
	var panel_wc = load("res://ui/factoryPanel.gd").new();
	root.add_child(panel_wc);
	panel_wc.initialize(cortadora, fd, Vector2(640, 360), bag);
	_check("una factoría con workers_needed 0 no monta botones",
		panel_wc.find_children("", "Button", true, false).is_empty());

	_limpiar([panel_meta, panel_sierra, panel_wc, meta, sierra, cortadora, placer, bag, main]);

# ---------- UI M2: selector de material ----------

# El camino que abre este hito no lo ejercitaba NINGUNA factoría del juego cuando se escribió
# —el hito construía la infraestructura y no el caso de uso—, así que la factoría multi-material
# se declara AQUÍ, sobre una copia PROFUNDA del JSON: una copia superficial compartiría el dict
# `Factories` con las pruebas que vienen detrás. Se mantiene sintética a propósito **aunque
# desde el 2026-09-22 la `Foundry` ya declare su `materials`** (Variedad M3): esto prueba el
# CONTRATO —candidatos, fallback, rechazo— con nombres que no son de nadie, y el caso de uso
# real tiene su propio bloque, «Variedad M3». Si un día la fundición cambia de materiales, estas
# comprobaciones no se tienen que tocar.
func _test_ui_m2_materiales(fd):
	print("UI M2 — selector de material");

	# El contrato de OPCIONALIDAD, que es lo que este hito fijó: quien no declara `materials`
	# vale exactamente por su `material`. Desde Variedad M3 la `Foundry` SÍ lo declara —es el
	# primer y único consumidor real—, así que lo que se afirma es eso: una y solo una, y las
	# otras ocho siguen sin enterarse de que el campo existe.
	var declaran = [];
	for nombre in fd["Factories"]:
		if fd["Factories"][nombre].has("materials"):
			declaran.append(nombre);
	_check("en el JSON del juego solo la Foundry declara `materials`", declaran == ["Foundry"],
		"lo declaran %s" % str(declaran));

	var fd_multi = fd.duplicate(true);
	fd_multi["Factories"]["MultiFactory"] = {
		"material": "a",
		"materials": ["a", "b"],
		"tick": 1,
		"recieve": null,
		"pollution": 0.0,
		"type": "production",
		"workers_needed": 0,
		"synergies": {}
	};

	var main = _new_main_de_prueba(fd_multi);
	var tile_map = main.get_node("TileMap");
	var jugador = main.get_node("Player");
	var bag = _new_bag();
	bag.initialize(fd_multi);

	var arr = [];
	var placer = load("res://entities/factory/factoryPlacer.gd").new();
	placer.initialize(load("res://entities/factory/factory.tscn"), fd_multi, arr);

	# Celdas lejanas, limpias y no adyacentes entre sí: getPollutionChoke() localiza el PRIMER
	# PollutionManager del árbol, así que un ahogo heredado de otra prueba haría que el tick no
	# entregara nada y esto mediría otra cosa.
	var multi = placer.build("MultiFactory", Vector2i(80, 80), jugador, bag, tile_map);
	arr.append(multi);
	root.add_child(multi);
	_check("una factoría con `materials` guarda los dos candidatos y arranca en su `material`",
		multi.production_candidates == ["a", "b"] and multi.production == "a"
		and multi.hasMaterialChoice(), str(multi.production_candidates));

	# Desde Cintas M2 producir no llena la bolsa: lo fabricado sale por `resource_produced` y
	# es Main quien lo encamina por la red. Lo que esta prueba mira —QUÉ material fabrica— se
	# cuenta en la señal.
	var salida = {};
	multi.resource_produced.connect(func(mat, cantidad, _pos): salida[mat] = int(salida.get(mat, 0)) + cantidad);
	multi.update();
	_check("de partida lo que sale de la factoría es el material declarado",
		int(salida.get("a", 0)) == 1 and int(salida.get("b", 0)) == 0, str(salida));

	# --- El fallback: sin `materials`, un candidato y es su `material` ---
	var cortadora = placer.build("WoodCutter", Vector2i(84, 80), jugador, bag, tile_map);
	arr.append(cortadora);
	root.add_child(cortadora);
	_check("sin `materials` la lista de candidatos es exactamente [material]",
		cortadora.production_candidates == ["wood"] and not cortadora.hasMaterialChoice(),
		str(cortadora.production_candidates));

	# El Reforester es el caso límite del fallback: su `material` es null en el JSON.
	var refo = placer.build("Reforester", Vector2i(88, 80), jugador, bag, tile_map);
	arr.append(refo);
	root.add_child(refo);
	_check("el Reforester (`material: null`) cae al fallback sin romperlo: un candidato, nulo",
		refo.production_candidates.size() == 1 and refo.production_candidates[0] == null
		and refo.production == null and not refo.hasMaterialChoice(),
		str(refo.production_candidates));

	# --- Cambiar de material NO es una factoría nueva ---
	# El `Timer` de factory.tscn y el contador de timeouts marcan el tick a medio cumplir, y
	# `production_debt` arrastra la producción fraccionaria que el ahogo dejó a deber. Reiniciar
	# cualquiera de los tres al cambiar de material sería un exploit o un castigo invisible.
	var reloj = multi.get_node("Timer");
	multi.production_debt = 0.4;
	multi.timer = 7;
	var espera = reloj.wait_time;
	var parado = reloj.is_stopped();
	_check("cambiar a un material candidato se acepta y mueve `production`",
		multi.setProduction("b") and multi.production == "b", str(multi.production));
	_check("y NO reinicia el Timer, ni su contador de ticks, ni toca production_debt",
		_near(multi.production_debt, 0.4) and multi.timer == 7
		and reloj.wait_time == espera and reloj.is_stopped() == parado,
		"debt %f, timer %d" % [multi.production_debt, multi.timer]);
	_check("un material que no es candidato se rechaza y deja la producción donde estaba",
		multi.setProduction("plank") == false and multi.production == "b",
		str(multi.production));

	multi.update();
	_check("tras cambiar de material, lo que sale de la factoría es el nuevo",
		int(salida.get("b", 0)) == 1 and int(salida.get("a", 0)) == 1, str(salida));
	_check("y la deuda fraccionaria heredada sigue contando: 0,4 + 1 entrega 1 y deja 0,4",
		_near(multi.production_debt, 0.4), str(multi.production_debt));

	# --- El panel: el desplegable solo aparece cuando hay algo que elegir ---
	var panel_multi = load("res://ui/factoryPanel.gd").new();
	root.add_child(panel_multi);
	panel_multi.initialize(multi, fd_multi, Vector2(640, 360), bag);
	var opciones = panel_multi.find_children("", "OptionButton", true, false);
	_check("el panel de una factoría con dos candidatos monta el desplegable, con los dos",
		opciones.size() == 1 and opciones[0].item_count == 2,
		"%d desplegables" % opciones.size());
	_check("y llega marcando lo que la factoría produce AHORA, no el primero de la lista",
		opciones[0].get_item_text(opciones[0].selected) == "b",
		opciones[0].get_item_text(opciones[0].selected));

	opciones[0].item_selected.emit(0);
	_check("elegir en el desplegable cambia la producción de la factoría",
		multi.production == "a", str(multi.production));
	multi.update();
	_check("y con ella cambia lo que sale de la factoría",
		int(salida.get("a", 0)) == 2 and int(salida.get("b", 0)) == 1, str(salida));
	_check("el panel se repinta in situ en vez de remontarse: sigue vivo y marcando el nuevo",
		not panel_multi.is_queued_for_deletion()
		and opciones[0].get_item_text(opciones[0].selected) == "a",
		opciones[0].get_item_text(opciones[0].selected));

	# Con un solo candidato —las cinco del juego— no hay desplegable y el texto es el de siempre.
	var panel_wc = load("res://ui/factoryPanel.gd").new();
	root.add_child(panel_wc);
	panel_wc.initialize(cortadora, fd_multi, Vector2(640, 360), bag);
	_check("con un solo candidato el desplegable no aparece",
		panel_wc.find_children("", "OptionButton", true, false).is_empty());
	_check("y la etiqueta «Produce:» de siempre se queda",
		_tiene_etiqueta(panel_wc, "Produce: wood"));

	var panel_refo = load("res://ui/factoryPanel.gd").new();
	root.add_child(panel_refo);
	panel_refo.initialize(refo, fd_multi, Vector2(640, 360), bag);
	_check("el panel del Reforester se monta sin desplegable y sin pintar `<null>`",
		panel_refo.find_children("", "OptionButton", true, false).is_empty()
		and _tiene_etiqueta(panel_refo, "Produce: — (restauración)")
		and not _tiene_etiqueta(panel_refo, "Produce: <null>"));

	_limpiar([panel_multi, panel_wc, panel_refo, multi, cortadora, refo, placer, bag, main]);

# ---------- M3: el tooltip deja de mentir ----------

# El bug que arregla M3 no es de lógica, es de comparación: `str(null)` devuelve "<null>", NO
# "null", así que `if str(params.get("material", null)) != "null"` acertaba SIEMPRE y la rama de
# restauración era código muerto. Se prueba sobre el texto pintado y no sobre el estado interno
# porque el defecto era exactamente ese: lo que el jugador leía.
func _test_ui_m3_tooltip(fd):
	print("UI M3 — el tooltip del Reforester deja de pintar `<null>`");

	var refo = _new_factory("Reforester", Vector2i(3, 3));
	refo.initialize("Reforester", 5, null, null, 1, -4.0, "restoration", 0);
	var tip_refo = load("res://ui/factoryTooltip.gd").new();
	root.add_child(tip_refo);
	tip_refo.initialize(refo, fd);
	_check("el Reforester pinta «Produce: — (restauración)», no «Produce: <null>»",
		_tiene_etiqueta(tip_refo, "Produce: — (restauración)")
		and not _tiene_etiqueta(tip_refo, "Produce: <null>"));

	# La otra mitad del arreglo: al enderezar la comparación, las productoras tienen que seguir
	# diciendo lo mismo de antes. Es la rama que ANTES funcionaba y que un arreglo torpe invierte.
	var wc = _new_factory("WoodCutter", Vector2i(4, 4));
	wc.initialize("WoodCutter", 4, null, "wood", 1, 3.0, "production", 0);
	var tip_wc = load("res://ui/factoryTooltip.gd").new();
	root.add_child(tip_wc);
	tip_wc.initialize(wc, fd);
	_check("y una productora sigue pintando su material de siempre",
		_tiene_etiqueta(tip_wc, "Produce: wood"));

	# El tooltip lee `production` de la factoría, no `material` del JSON: desde M2 las dos cosas
	# pueden diferir, y quien manda es lo que la factoría fabrica AHORA.
	var multi = _new_factory("MultiFactory", Vector2i(5, 5));
	multi.initialize("MultiFactory", 2, null, "a", 1, 0.0, "production", 0, ["a", "b"]);
	_check("cambiar de material devuelve true y mueve `production`",
		multi.setProduction("b") and multi.production == "b");
	var fd_multi = fd.duplicate(true);
	fd_multi["Factories"]["MultiFactory"] = {
		"material": "a", "materials": ["a", "b"], "tick": 2, "recieve": null,
		"pollution": 0.0, "type": "production", "workers_needed": 0, "synergies": {}
	};
	var tip_multi = load("res://ui/factoryTooltip.gd").new();
	root.add_child(tip_multi);
	tip_multi.initialize(multi, fd_multi);
	_check("y el tooltip enseña el material ELEGIDO, no el de por defecto del JSON",
		_tiene_etiqueta(tip_multi, "Produce: b")
		and not _tiene_etiqueta(tip_multi, "Produce: a"));

	_limpiar([tip_refo, tip_wc, tip_multi, refo, wc, multi]);

# ¿Alguna etiqueta del panel dice exactamente esto? Mira el texto pintado, no el estado interno.
func _tiene_etiqueta(panel, texto):
	for lbl in panel.find_children("", "Label", true, false):
		if lbl.text == texto:
			return true;
	return false;

# ---------- Cintas M1: la entidad cinta y su colocación ----------

func _test_cintas_m1(file_data):
	print("Cintas M1 — la entidad cinta y su colocación");
	var script_red = load("res://managers/beltNetwork.gd");
	var main = _new_main_de_prueba(file_data);
	var tm = main.get_node("TileMap");
	# Un rectángulo de suelo de 8x6: es lo que el arrastre necesita para tener por dónde ir.
	for y in range(6):
		for x in range(8):
			tm.set_cell(0, Vector2i(x, y), 1, Vector2i(0, 0));
	var red = script_red.new();
	red.name = "BeltNetwork";
	main.add_child(red);
	red.initialize(tm);
	tm.setBeltNetwork(red);
	var avisos = [0];
	red.belt_network_changed.connect(func(): avisos[0] += 1);

	# --- El trazado en L del arrastre: primero horizontal y luego vertical, con los dos
	# extremos incluidos. No hay pathfinding: rodear un obstáculo elegiría por el jugador
	# dónde gasta sus casillas, que es justo la decisión que el diseño le deja a él.
	var camino = red.trace_path(Vector2i(1, 1), Vector2i(4, 3));
	var esperado = [Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1), Vector2i(4, 1),
		Vector2i(4, 2), Vector2i(4, 3)];
	_check("el arrastre traza una L: primero horizontal y luego vertical",
		camino == esperado, str(camino));
	_check("y el primer paso es horizontal, no la L contraria",
		camino[1] == Vector2i(2, 1), str(camino[1]));

	# --- Tender: seis casillas de un solo arrastre, que es el criterio literal del hito.
	var puestas = red.place_drag(Vector2i(1, 1), Vector2i(4, 3), main.factoryArray);
	_check("se tiende una cinta de 6 casillas arrastrando",
		puestas == esperado and red.belt_count() == 6,
		"%d segmentos: %s" % [red.belt_count(), str(puestas)]);
	_check("y colocar avisa por belt_network_changed", avisos[0] == 1, "%d avisos" % avisos[0]);

	# --- dir_in / dir_out encadenados: el dir_out de cada segmento lleva a la celda del
	# siguiente y el dir_in del siguiente vuelve a la del anterior.
	var encadenados = true;
	var solo_ortogonales = true;
	var distintos = true;
	for i in range(esperado.size()):
		var seg = red.get_belt(esperado[i]);
		if seg == null:
			encadenados = false;
			continue;
		if not (seg.dir_in in script_red.ORTHOGONAL_DIRS) or not (seg.dir_out in script_red.ORTHOGONAL_DIRS):
			solo_ortogonales = false;
		if seg.dir_in == seg.dir_out:
			distintos = false;
		if i < esperado.size() - 1:
			var siguiente = red.get_belt(esperado[i + 1]);
			if seg.cell + seg.dir_out != esperado[i + 1]:
				encadenados = false;
			elif siguiente == null or siguiente.cell + siguiente.dir_in != esperado[i]:
				encadenados = false;
	_check("los segmentos quedan encadenados por dir_out/dir_in", encadenados);
	_check("y solo usan las 4 direcciones ortogonales, nunca 8", solo_ortogonales);
	_check("con dir_in distinto de dir_out en todos", distintos);
	# Los dos extremos apuntan a la casilla de la factoría que se les pegue: es lo que
	# deliver() busca en M2, y por eso el primero mira hacia atrás y el último sigue recto.
	_check("el primer segmento mira hacia atrás y el último sigue recto",
		red.get_belt(Vector2i(1, 1)).dir_in == Vector2i(-1, 0)
		and red.get_belt(Vector2i(4, 3)).dir_out == Vector2i(0, 1),
		"%s / %s" % [str(red.get_belt(Vector2i(1, 1)).dir_in), str(red.get_belt(Vector2i(4, 3)).dir_out)]);
	_check("el filtro de material nace vacío (acepta todo; se usa en M5)",
		red.get_belt(Vector2i(2, 1)).filter == "");

	# --- La quinta condición de canPlaceFactory(): una celda con cinta está ocupada.
	_check("canPlaceFactory() rechaza una celda con cinta",
		tm.canPlaceFactory(Vector2i(2, 1), main.factoryArray) == false);
	_check("y sigue admitiendo la casilla de al lado",
		tm.canPlaceFactory(Vector2i(2, 2), main.factoryArray) == true);
	# Sin red inyectada la función tiene que comportarse EXACTAMENTE como antes de M1: hay
	# llamadores fuera del juego (esta suite) que monta
	# escenarios sin cintas y no deben verse afectados.
	tm.setBeltNetwork(null);
	_check("sin beltNetwork inyectado canPlaceFactory() se comporta como antes de M1",
		tm.canPlaceFactory(Vector2i(2, 1), main.factoryArray) == true);
	tm.setBeltNetwork(red);

	# --- Todo o nada: una sola celda que no admita tumba el arrastre entero.
	var estorbo = _new_factory("WoodCutter", Vector2i(3, 0));
	main.factoryArray.append(estorbo);
	var antes = red.belt_count();
	var fallido = red.place_drag(Vector2i(0, 0), Vector2i(5, 0), main.factoryArray);
	_check("el arrastre aborta ENTERO si una celda del camino no admite",
		fallido.is_empty() and red.belt_count() == antes,
		"devolvió %s y la red tiene %d" % [str(fallido), red.belt_count()]);
	_check("y no deja media cinta tendida antes del obstáculo",
		not red.has_belt(Vector2i(0, 0)) and not red.has_belt(Vector2i(1, 0))
		and not red.has_belt(Vector2i(2, 0)));
	_check("un arrastre que no cabe tampoco avisa", avisos[0] == 1, "%d avisos" % avisos[0]);
	# Y tampoco se tiende encima de otra cinta: la condición 5 vale para los dos sentidos.
	_check("tampoco se tiende encima de otra cinta",
		red.place_drag(Vector2i(2, 0), Vector2i(2, 3), main.factoryArray).is_empty());
	_check("ni un arrastre que empieza y acaba en la misma celda",
		red.place_drag(Vector2i(6, 4), Vector2i(6, 4), main.factoryArray).is_empty());

	# --- Demoler un segmento del medio parte la cadena y deja los otros cinco.
	var borrado = red.remove_belt(Vector2i(3, 1));
	_check("el click derecho borra un segmento del medio y los otros cinco siguen ahí",
		borrado and red.belt_count() == 5 and not red.has_belt(Vector2i(3, 1))
		and red.has_belt(Vector2i(2, 1)) and red.has_belt(Vector2i(4, 1)),
		"borrado=%s, quedan %d" % [str(borrado), red.belt_count()]);
	# La cadena queda PARTIDA a propósito: el vecino de antes sigue apuntando al hueco, que es
	# donde deliver() se detendrá en M2. Recablear sería deshacer lo que el jugador ha pedido.
	var anterior = red.get_belt(Vector2i(2, 1));
	_check("y la cadena queda partida: el segmento anterior apunta a un hueco",
		anterior.cell + anterior.dir_out == Vector2i(3, 1) and not red.has_belt(Vector2i(3, 1)));
	_check("demoler también avisa por belt_network_changed", avisos[0] == 2, "%d avisos" % avisos[0]);
	_check("borrar donde no hay cinta no hace nada",
		red.remove_belt(Vector2i(7, 5)) == false and red.belt_count() == 5 and avisos[0] == 2);
	_check("la casilla liberada vuelve a admitir factoría",
		tm.canPlaceFactory(Vector2i(3, 1), main.factoryArray) == true);

	# --- El dibujo sale por un canvas item PROPIO hijo del TileMap, no por su _draw():
	# dibujado desde el TileMap quedaría por debajo de los tiles, que es el bug que hizo
	# invisibles 8 de los 11 tipos de casilla.
	var overlay = tm.get_node_or_null("BeltOverlay");
	_check("el dibujo de las cintas sale por un overlay propio hijo del TileMap",
		overlay != null and overlay.z_index > 0, "overlay=%s" % str(overlay));
	var spy = SpyCanvas.new();
	red.draw_belts(spy);
	_check("y cada segmento pinta su base y su flecha de orientación",
		spy.polys.size() == red.belt_count() * 2 and spy.lines.size() == red.belt_count(),
		"%d polígonos y %d líneas para %d segmentos" % [spy.polys.size(), spy.lines.size(), red.belt_count()]);

	# --- La cache de factorías por celda que consume M2 nace vacía y se invalida entera.
	var indice_vacio = red._factory_index.is_empty();
	red._factory_index[Vector2i(9, 9)] = null;
	red.invalidate_factory_index();
	_check("_factory_index nace vacío y se invalida entero (lo consume M2)",
		indice_vacio and red._factory_index.is_empty());

	_limpiar([main, estorbo]);

	# --- La ocupación llega hasta hasBuildableCell(), y con ella hasta la condición 3 del
	# punto muerto. Es la decisión del 2026-09-18 (ningún plan B: las cintas compiten por
	# espacio), no un efecto colateral que haya que corregir.
	var tm2 = load("res://entities/tilemap/tile_map.tscn").instantiate();
	tm2.name = "TileMapMinimo";
	tm2.set_cell(0, Vector2i(0, 0), 1, Vector2i(0, 0));
	tm2.set_cell(0, Vector2i(1, 0), 1, Vector2i(0, 0));
	var red2 = script_red.new();
	red2.initialize(tm2);
	tm2.setBeltNetwork(red2);
	_check("un mapa mínimo sin cintas tiene dónde construir", tm2.hasBuildableCell([]) == true);
	red2.place_drag(Vector2i(0, 0), Vector2i(1, 0), []);
	_check("y con las dos casillas tendidas ya no: la cinta cuenta como ocupación",
		tm2.hasBuildableCell([]) == false);
	_limpiar([tm2, red2]);


# ---------- Cintas M2: la propagación ----------

# Main DENTRO del árbol y sin que corra su `_ready()`: el nodo entra primero pelado y el script
# se le pone después, así que no se levanta el menú principal entero —que es justo por lo que
# _new_main_de_prueba() deja el suyo fuera—. Aquí hace falta dentro porque la propagación se
# prueba por el camino real, Main._on_resource_produced(), y ése acaba en _spawn_fx_label(),
# que crea un Tween y eso solo vale para un nodo montado.
func _new_main_en_arbol(file_data):
	var main = Node.new();
	main.name = "Main";
	root.add_child(main);
	main.set_script(load("res://Main.gd"));
	main.fileData = file_data;
	var tm = load("res://entities/tilemap/tile_map.tscn").instantiate();
	tm.name = "TileMap";
	tm.tile_type_data = file_data["TileTypes"];
	main.add_child(tm);
	var jugador = load("res://entities/player/player.tscn").instantiate();
	jugador.name = "Player";
	main.add_child(jugador);
	jugador.get_node("Bag").initialize(file_data);
	return main;

# Factoría colgada de ese Main y registrada en su `factoryArray`, con la cache de la red
# invalidada como hace Main._on_factory_chosen(). Sin registrar no existe para deliver().
# `ftype` va al final y con default por lo mismo que el `materials` de
# factoryData.initialize(): los llamadores de M2 lo pasan todo posicionalmente.
func _factoria_en_main(main, tipo, celda, tick, recibe, material, ftype = "production"):
	var f = load("res://entities/factory/factoryData.gd").new();
	var spr = AnimatedSprite2D.new();
	spr.name = "AnimatedSprite2D";
	spr.sprite_frames = SpriteFrames.new();
	f.add_child(spr);
	f.initialize(tipo, tick, recibe, material, 1, 0.0, ftype, 0);
	f.type = tipo;
	f.cell_position = celda;
	main.add_child(f);
	main.factoryArray.append(f);
	if main.beltNetwork:
		main.beltNetwork.invalidate_factory_index();
	return f;

func _test_cintas_m2(file_data):
	print("Cintas M2 — la propagación");
	var script_red = load("res://managers/beltNetwork.gd");
	var main = _new_main_en_arbol(file_data);
	var tm = main.get_node("TileMap");
	var bolsa = main.get_node("Player/Bag");
	# Un rectángulo de suelo de 10x8: caben la línea, el bucle y las dos excepciones sin que
	# se estorben.
	for y in range(8):
		for x in range(10):
			tm.set_cell(0, Vector2i(x, y), 1, Vector2i(0, 0));
	var red = script_red.new();
	red.name = "BeltNetwork";
	main.add_child(red);
	red.initialize(tm, main.factoryArray);
	tm.setBeltNetwork(red);
	main.beltNetwork = red;

	# --- deliver() con camino válido: del borde de la cortadora al de la serrería.
	var cortadora = _factoria_en_main(main, "WoodCutter", Vector2i(1, 1), 1, null, "wood");
	var sierra = _factoria_en_main(main, "WoodProcessing", Vector2i(6, 1), 1, ["wood"], "plank");
	# Y una serrería PEGADA a la cortadora, sin cinta: la decisión del 2026-09-18 es que no
	# recibe nada: todo pasa por cinta, también entre vecinas.
	var sierra_pegada = _factoria_en_main(main, "WoodProcessing", Vector2i(1, 2), 1, ["wood"], "plank");
	var tendida = red.place_drag(Vector2i(2, 1), Vector2i(5, 1), main.factoryArray);
	_check("la cinta se tiende entre las dos factorías, sin tocarlas", tendida.size() == 4,
		"tendió %s" % str(tendida));
	_check("deliver() con camino válido suma al input_buffer de la factoría del final",
		red.deliver(Vector2i(1, 1), "wood", 3) == 3
		and int(sierra.input_buffer.get("wood", 0)) == 3,
		"búfer = %s" % str(sierra.input_buffer));
	_check("y la vecina pegada no recibe nada: no hay excepción por adyacencia",
		sierra_pegada.input_buffer.is_empty(), str(sierra_pegada.input_buffer));
	# El destino se resuelve por el índice de celdas, no recorriendo factoryArray: es lo que
	# M0 midió (0,207-0,553 ms de mediana contra 0,023-0,036 ms).
	_check("deliver() resuelve el destino por _factory_index, ya poblado",
		red.factory_at(Vector2i(6, 1)) == sierra
		and red._factory_index.size() == main.factoryArray.size(),
		"%d entradas para %d factorías" % [red._factory_index.size(), main.factoryArray.size()]);

	# --- El criterio literal del hito, jugado por el camino real: la cortadora emite, Main lo
	# encamina por la red y la serrería acaba entregando plank.
	sierra.input_buffer.clear();
	var tablones = [0];
	sierra.resource_produced.connect(func(_m, c, _p): tablones[0] += c);
	var tablones_pegada = [0];
	sierra_pegada.resource_produced.connect(func(_m, c, _p): tablones_pegada[0] += c);
	cortadora.resource_produced.connect(main._on_resource_produced.bind(cortadora));
	for t in range(4):
		cortadora.update();
		sierra.update();
		sierra_pegada.update();
	_check("un WoodCutter con cinta hasta una WoodProcessing la alimenta y produce plank",
		tablones[0] == 4, "entregó %d tablones" % tablones[0]);
	_check("y sin cinta la WoodProcessing no produce nada",
		tablones_pegada[0] == 0 and sierra_pegada.input_buffer.is_empty(),
		"entregó %d tablones" % tablones_pegada[0]);
	_check("producir ya no llena la bolsa: lo que no llega a un destino se pierde (hasta M3)",
		bolsa.getQuantity("wood") == 0 and bolsa.getQuantity("plank") == 0,
		"wood %d, plank %d" % [bolsa.getQuantity("wood"), bolsa.getQuantity("plank")]);

	# --- deliver() sin camino, con destino que no acepta, con filtro que rechaza y con la
	# cadena partida: los cuatro finales que devuelven 0.
	_check("deliver() desde una celda de la que no sale ninguna cinta devuelve 0",
		red.deliver(Vector2i(6, 1), "plank", 1) == 0);
	_check("una factoría que no declara el material en su `recieve` no lo recibe",
		red.deliver(Vector2i(1, 1), "plank", 1) == 0 and not sierra.input_buffer.has("plank"),
		str(sierra.input_buffer));
	red.get_belt(Vector2i(3, 1)).filter = "plank";
	_check("un filtro que rechaza corta la entrega (su interfaz es M5; la regla es de M2)",
		red.deliver(Vector2i(1, 1), "wood", 1) == 0);
	red.get_belt(Vector2i(3, 1)).filter = "";
	red.remove_belt(Vector2i(4, 1));
	_check("con la cadena partida la entrega se pierde",
		red.deliver(Vector2i(1, 1), "wood", 1) == 0);

	# --- El bucle. Es trivial de construir arrastrando en círculo: cuatro arrastres cierran el
	# anillo (1,5)->(3,5)->(3,7)->(1,7)->(1,5). Sin el set de visitadas y el tope de MAX_PATH,
	# la primera entrega colgaría el juego.
	red.place_drag(Vector2i(1, 5), Vector2i(2, 5), main.factoryArray);
	red.place_drag(Vector2i(3, 5), Vector2i(3, 6), main.factoryArray);
	red.place_drag(Vector2i(3, 7), Vector2i(2, 7), main.factoryArray);
	red.place_drag(Vector2i(1, 7), Vector2i(1, 6), main.factoryArray);
	var anillo = true;
	for celda in [Vector2i(1, 5), Vector2i(2, 5), Vector2i(3, 5), Vector2i(3, 6),
			Vector2i(3, 7), Vector2i(2, 7), Vector2i(1, 7), Vector2i(1, 6)]:
		var seg = red.get_belt(celda);
		if seg == null or not red.has_belt(seg.cell + seg.dir_out):
			anillo = false;
	_check("cuatro arrastres cierran un anillo de cintas sin salida", anillo);
	var t0 = Time.get_ticks_msec();
	var en_bucle = red.deliver(Vector2i(0, 5), "wood", 1);
	var tardo = Time.get_ticks_msec() - t0;
	_check("un bucle de cintas devuelve 0 y no cuelga el juego",
		en_bucle == 0 and tardo < 500, "devolvió %d en %d ms" % [en_bucle, tardo]);
	_check("y el tope de saltos sigue en su sitio por si el set no ve venir el camino",
		script_red.MAX_PATH == 64, "MAX_PATH = %d" % script_red.MAX_PATH);

	# --- checkNeeds() contra el input_buffer, que es el cambio del que cuelga todo el plan.
	bolsa.addToBag("wood", 99);
	var sierra_check = _factoria_en_main(main, "WoodProcessing", Vector2i(8, 5), 1, ["wood"], "plank");
	_check("checkNeeds() dice que no con la bolsa llena si el búfer está vacío",
		bolsa.getAvailable("wood") == 99 and sierra_check.checkNeeds() == false,
		"disponible %d" % bolsa.getAvailable("wood"));
	sierra_check.receiveMaterial("wood", 2);
	_check("y dice que sí en cuanto una cinta le entrega", sierra_check.checkNeeds() == true);
	sierra_check.consumeNeeds();
	_check("consumeNeeds() vacía el BÚFER y deja la bolsa intacta",
		int(sierra_check.input_buffer["wood"]) == 1 and bolsa.getQuantity("wood") == 99,
		"búfer %d, bolsa %d" % [int(sierra_check.input_buffer["wood"]), bolsa.getQuantity("wood")]);

	# --- Las dos excepciones, intactas: ni el worker ni el factory_token viajan por cinta. Se
	# prueban por el camino real, que es donde vive la desviación: Main._on_resource_produced().
	var campamento = _factoria_en_main(main, "WorkerCamp", Vector2i(6, 3), 1, null, "worker");
	var receptor = _factoria_en_main(main, "Receptor", Vector2i(9, 3), 1,
		["worker", "factory_token"], "plank");
	red.place_drag(Vector2i(7, 3), Vector2i(8, 3), main.factoryArray);
	_check("la red SABRÍA llevarlo: el camino existe y el receptor acepta los dos materiales",
		red.deliver(Vector2i(6, 3), "worker", 1) == 1
		and int(receptor.input_buffer["worker"]) == 1, str(receptor.input_buffer));
	receptor.input_buffer.clear();
	# Con todas las factorías ya disponibles, la pantalla del token se cierra sola sin pausar
	# el árbol: lo que se mide aquí es el desvío, no la UI.
	main.get_node("Player").availableFactories = file_data["Factories"].keys();
	var workers_antes = bolsa.workers_total;
	var tokens_antes = bolsa.getQuantity("factory_token");
	main._on_resource_produced("worker", 1, Vector2.ZERO, campamento);
	main._on_resource_produced("factory_token", 1, Vector2.ZERO, campamento);
	_check("el worker lo intercepta Main antes de la red y sigue yendo a la bolsa",
		bolsa.workers_total == workers_antes + 1, "%d -> %d" % [workers_antes, bolsa.workers_total]);
	_check("el factory_token abre su pantalla y se cuenta en la bolsa, como hasta M1",
		bolsa.getQuantity("factory_token") == tokens_antes + 1);
	_check("y ninguno de los dos pasa por cinta", receptor.input_buffer.is_empty(),
		str(receptor.input_buffer));

	_limpiar([main]);

# ---------- Cintas M3: el almacén ----------

func _test_cintas_m3(file_data):
	print("Cintas M3 — el almacén");
	var script_red = load("res://managers/beltNetwork.gd");
	var script_loader = load("res://managers/mapLoader.gd");
	var escena_factoria = load("res://entities/factory/factory.tscn");

	# --- El contrato del JSON. El almacén es una factoría más del JSON y no un tipo
	# hardcodeado: es lo que hace que la rama nueva de update() encaje donde las otras dos.
	var alm = file_data["Factories"].get("Storage", null);
	_check("el JSON declara la factoría Storage", alm != null);
	if alm == null:
		return;
	_check("Storage es el tercer type, junto a production y restoration",
		alm.get("type", "") == "storage", str(alm.get("type", "")));
	_check("el almacén no produce nada: material null y sin `recieve`",
		alm.get("material", "x") == null and alm.get("recieve", "x") == null);
	_check("ni contamina ni pide workers",
		_near(float(alm.get("pollution", -1.0)), 0.0) and int(alm.get("workers_needed", -1)) == 0);
	_check("vuelca cada tick y no tiene sinergias",
		int(alm.get("tick", 0)) == 1 and alm.get("synergies", {}).is_empty());
	_check("y NO declara `materials`: elegir qué emite es M5", not alm.has("materials"));
	var en_paquete = [];
	for pid in file_data["StartingPackages"]:
		if file_data["StartingPackages"][pid].get("factories", []).has("Storage"):
			en_paquete.append(pid);
	_check("ningún paquete inicial lo ofrece: al almacén lo coloca el mapa, no el jugador",
		en_paquete.is_empty(), str(en_paquete));

	# --- La storage_cell de cada mapa está elegida a mano, y lo que la hace válida es no
	# pisar las special_cells curadas una a una ni una casilla bloqueada.
	for mapa in file_data["Maps"]:
		var mid = str(mapa.get("id", "?"));
		var raw = mapa.get("storage_cell", null);
		_check("%s declara su storage_cell" % mid, raw != null);
		if raw == null:
			continue;
		var celda_json = Vector2i(int(raw[0]), int(raw[1]));
		var tam = mapa.get("size", [16, 10]);
		_check("%s: la storage_cell %s cae dentro del mapa" % [mid, str(celda_json)],
			celda_json.x >= 0 and celda_json.y >= 0
			and celda_json.x < int(tam[0]) and celda_json.y < int(tam[1]));
		var pisada = "";
		for sc in mapa.get("special_cells", []):
			if Vector2i(int(sc["pos"][0]), int(sc["pos"][1])) == celda_json:
				pisada = str(sc.get("type", "?"));
		_check("%s: la storage_cell no pisa ninguna special_cell" % mid, pisada == "",
			"cae sobre una casilla %s" % pisada);
		var bloqueada = false;
		for bc in mapa.get("blocked_cells", []):
			if Vector2i(int(bc[0]), int(bc[1])) == celda_json:
				bloqueada = true;
		_check("%s: ni ninguna blocked_cell" % mid, not bloqueada);

	# --- Y apply_map() lo coloca YA CONSTRUIDO en los dos mapas, por el camino real: es lo
	# que hace que al empezar una run haya un almacén en el mapa.
	for mapa in file_data["Maps"]:
		var mid = str(mapa.get("id", "?"));
		var main_m = _new_main_en_arbol(file_data);
		var pm_m = _new_pm();
		main_m.add_child(pm_m);
		var placer_m = load("res://entities/factory/factoryPlacer.gd").new();
		placer_m.initialize(escena_factoria, file_data, main_m.factoryArray);
		var loader = script_loader.new();
		loader.apply_map(mapa, pm_m, main_m.get_node("TileMap"), file_data, {
			"placer": placer_m,
			"parent": main_m,
			"player": main_m.get_node("Player"),
			"bag": main_m.get_node("Player/Bag"),
			"factories": main_m.factoryArray,
		});
		var celda_m = Vector2i(int(mapa["storage_cell"][0]), int(mapa["storage_cell"][1]));
		var puestos = [];
		for f in main_m.factoryArray:
			puestos.append("%s en %s" % [f.type, str(f.cell_position)]);
		var uno = main_m.factoryArray.size() == 1;
		_check("%s: al empezar la run hay UN almacén en el mapa y nada más" % mid,
			uno and main_m.factoryArray[0].type == "Storage"
			and main_m.factoryArray[0].cell_position == celda_m, str(puestos));
		if uno:
			_check("%s: y es de verdad un almacén — factory_type storage y sin producción" % mid,
				main_m.factoryArray[0].factory_type == "storage"
				and main_m.factoryArray[0].production == null);
		# Ocupa casilla como cualquier otra factoría: canPlaceFactory() es el único punto de
		# verdad y cuenta ese almacén como cualquier otra ocupación del mapa.
		_check("%s: su casilla deja de admitir factoría" % mid,
			not main_m.get_node("TileMap").canPlaceFactory(celda_m, main_m.factoryArray));
		# El loader y el placer no cuelgan del árbol —mapLoader nunca lo hace—, así que hay
		# que soltarlos a mano o quedan como instancias filtradas al salir.
		_limpiar([main_m, loader, placer_m]);

	# --- El volcado: lo que una cinta le entrega al almacén acaba en la Bag. Desde M2
	# producir no llena la bolsa, así que el almacén pasa a ser el único que la llena — y de
	# ahí sale gratis «solo cuenta lo que ha pasado por un almacén», sin tocar el evaluador.
	var main = _new_main_en_arbol(file_data);
	var tm = main.get_node("TileMap");
	var bolsa = main.get_node("Player/Bag");
	for y in range(8):
		for x in range(10):
			tm.set_cell(0, Vector2i(x, y), 1, Vector2i(0, 0));
	var red = script_red.new();
	red.name = "BeltNetwork";
	main.add_child(red);
	red.initialize(tm, main.factoryArray);
	tm.setBeltNetwork(red);
	main.beltNetwork = red;

	var cortadora = _factoria_en_main(main, "WoodCutter", Vector2i(1, 1), 1, null, "wood");
	var almacen = _factoria_en_main(main, "Storage", Vector2i(6, 1), 1, null, null, "storage");
	var tendida = red.place_drag(Vector2i(2, 1), Vector2i(5, 1), main.factoryArray);
	_check("la cinta se tiende de la cortadora al almacén, sin tocar a ninguno",
		tendida.size() == 4, "tendió %s" % str(tendida));
	_check("deliver() termina en el almacén y le entrega",
		red.deliver(Vector2i(1, 1), "wood", 5) == 5
		and int(almacen.input_buffer.get("wood", 0)) == 5, str(almacen.input_buffer));
	_check("el almacén acepta CUALQUIER material, no solo lo que declare en `recieve`",
		almacen.itemNeeded.is_empty() and red.deliver(Vector2i(1, 1), "plank", 2) == 2
		and int(almacen.input_buffer.get("plank", 0)) == 2, str(almacen.input_buffer));
	_check("y todavía no está en la bolsa: el volcado es del tick del almacén",
		bolsa.getQuantity("wood") == 0 and bolsa.getQuantity("plank") == 0);
	almacen.update(bolsa);
	_check("su tick lo vuelca entero en la Bag y vacía el búfer",
		bolsa.getQuantity("wood") == 5 and bolsa.getQuantity("plank") == 2
		and almacen.input_buffer.is_empty(),
		"wood %d, plank %d, búfer %s" % [bolsa.getQuantity("wood"),
			bolsa.getQuantity("plank"), str(almacen.input_buffer)]);
	# El almacén no produce: su tick no emite `resource_produced`, así que deliver() no se
	# llama nunca para él. Emitir a una cinta es M5.
	var emitido = [0];
	almacen.resource_produced.connect(func(_m, c, _p): emitido[0] += c);
	almacen.update(bolsa);
	almacen.receiveMaterial("wood", 1);
	almacen.update(bolsa);
	_check("un tick de almacén no emite nada: no produce y no necesita cinta de salida",
		emitido[0] == 0 and bolsa.getQuantity("wood") == 6,
		"emitió %d, bolsa %d" % [emitido[0], bolsa.getQuantity("wood")]);

	# --- El camino real entero, que es el del *Hecho cuando*: la cortadora emite, Main lo
	# encamina por la red, el almacén lo recoge y su tick lo pone en la bolsa — que es
	# exactamente lo que pinta el HUD de recursos (Main._buildResourceText()).
	cortadora.resource_produced.connect(main._on_resource_produced.bind(cortadora));
	var antes = bolsa.getQuantity("wood");
	for t in range(4):
		cortadora.update();
	almacen.update(bolsa);
	_check("lo que un WoodCutter produce llega a la bolsa por la cinta y el almacén",
		bolsa.getQuantity("wood") == antes + 4,
		"%d -> %d" % [antes, bolsa.getQuantity("wood")]);
	_check("y aparece en el HUD de recursos, que lee la bolsa",
		main._buildResourceText(bolsa).contains("wood: %d" % bolsa.getQuantity("wood")),
		main._buildResourceText(bolsa));

	# --- El criterio literal del hito: el checkpoint 1 se cierra SOLO con material que ha
	# pasado por el almacén. Una cortadora aislada produce igual y no lo acerca ni una unidad.
	bolsa.reset();
	var gm = _new_gm(file_data);
	var cp1 = file_data["Checkpoints"][0];
	var objetivo = int(cp1["quantity"]);
	var aislada = _factoria_en_main(main, "WoodCutter", Vector2i(1, 6), 1, null, "wood");
	aislada.resource_produced.connect(main._on_resource_produced.bind(aislada));
	for t in range(objetivo + 5):
		aislada.update();
	gm.update(bolsa, null);
	_check("una cortadora sin cinta al almacén no acerca el checkpoint 1",
		bolsa.getQuantity(cp1["material"]) == 0 and gm.current_checkpoint_index == 0,
		"bolsa %d, índice %d" % [bolsa.getQuantity(cp1["material"]), gm.current_checkpoint_index]);
	for t in range(objetivo):
		cortadora.update();
		almacen.update(bolsa);
	gm.update(bolsa, null);
	_check("y el checkpoint 1 se cierra con material que SÍ ha pasado por él",
		gm.current_checkpoint_index == 1,
		"bolsa %d de %d, índice %d" % [bolsa.getQuantity(cp1["material"]), objetivo,
			gm.current_checkpoint_index]);
	_limpiar([main, gm]);

	# --- Y el almacén no se cuela en la oferta del factory token: lo coloca el mapa. Con
	# todo lo demás ya disponible la lista de candidatas queda vacía y la pantalla ni se
	# abre; si Storage colara, se abriría.
	var main_tok = _new_main_en_arbol(file_data);
	var disponibles = [];
	for nombre in file_data["Factories"]:
		if nombre != "Storage":
			disponibles.append(nombre);
	main_tok.get_node("Player").availableFactories = disponibles;
	main_tok._show_factory_token_screen();
	_check("el factory token no ofrece «Desbloquear Storage»",
		main_tok.get_node_or_null("TokenUnlock") == null);
	# Este script ES el SceneTree, así que la pausa se levanta sobre sí mismo: si la
	# comprobación de arriba fallara, la pantalla habría pausado el árbol para el resto de la suite.
	paused = false;
	_limpiar([main_tok]);

# ---------- Cintas M4: búfer de salida y parada ----------

func _test_cintas_m4(file_data):
	print("Cintas M4 — búfer de salida y parada");
	var script_red = load("res://managers/beltNetwork.gd");
	var script_fab = load("res://entities/factory/factoryData.gd");

	# --- El contrato del estado nuevo, literal del plan.
	_check("OUTPUT_BUFFER_MAX vale 10", script_fab.OUTPUT_BUFFER_MAX == 10,
		"vale %d" % script_fab.OUTPUT_BUFFER_MAX);
	var pelada = _new_productora("WoodCutter", "wood", 1);
	_check("una factoría nace con el búfer de salida vacío y sin razón de bloqueo",
		pelada.output_buffer == 0 and pelada.blocked_reason == "",
		"búfer %d, razón '%s'" % [pelada.output_buffer, pelada.blocked_reason]);
	_check("storeOutput() devuelve lo que ha cabido", pelada.storeOutput(4) == 4
		and pelada.output_buffer == 4, "búfer %d" % pelada.output_buffer);
	_check("y recorta en el tope: lo que rebosa SE PIERDE, el búfer es el freno y no un almacén",
		pelada.storeOutput(99) == 6 and pelada.output_buffer == script_fab.OUTPUT_BUFFER_MAX,
		"búfer %d" % pelada.output_buffer);
	pelada.clearOutputBuffer();
	_check("clearOutputBuffer() lo deja a cero", pelada.output_buffer == 0);
	_limpiar([pelada]);

	# --- El *Hecho cuando*, primera mitad: un WoodCutter AISLADO produce 10 unidades y se
	# para. El escenario es el camino real —la señal entra en Main._on_resource_produced(),
	# que pregunta a la red y guarda en el búfer lo que no ha podido entregar—.
	var main = _new_main_en_arbol(file_data);
	var tm = main.get_node("TileMap");
	var bolsa = main.get_node("Player/Bag");
	for y in range(8):
		for x in range(10):
			tm.set_cell(0, Vector2i(x, y), 1, Vector2i(0, 0));
	var red = script_red.new();
	red.name = "BeltNetwork";
	main.add_child(red);
	red.initialize(tm, main.factoryArray);
	tm.setBeltNetwork(red);
	main.beltNetwork = red;

	var cortadora = _factoria_en_main(main, "WoodCutter", Vector2i(1, 1), 1, null, "wood");
	var emitido = [0];
	cortadora.resource_produced.connect(func(_m, c, _p): emitido[0] += c);
	cortadora.resource_produced.connect(main._on_resource_produced.bind(cortadora));
	# En este escenario NO hay PollutionManager en el árbol, así que el ahogo vale 1.0 y cada
	# tick entrega 1 entero: la cuenta de 10 es exacta. (find_child devuelve el PRIMER
	# PollutionManager del árbol, de ahí que los escenarios se suelten uno a uno.)
	_check("el escenario está limpio de PollutionManager: cada tick entrega 1 entero",
		_near(cortadora.getPollutionChoke(), 1.0), "choke %f" % cortadora.getPollutionChoke());
	for t in range(15):
		cortadora.update();
	_check("un WoodCutter aislado produce 10 unidades y se para",
		emitido[0] == 10 and cortadora.output_buffer == script_fab.OUTPUT_BUFFER_MAX,
		"emitió %d, búfer %d" % [emitido[0], cortadora.output_buffer]);
	_check("y su estado dice por qué: blocked_reason == 'output'",
		cortadora.blocked_reason == "output", "razón '%s'" % cortadora.blocked_reason);
	_check("sin cinta el material ya no se pierde: nada ha entrado en la bolsa, está en el búfer",
		bolsa.getQuantity("wood") == 0, "bolsa %d" % bolsa.getQuantity("wood"));
	# Parar no es ahogarse: la deuda NO acumula mientras está parada, o al desatascarla
	# soltaría de golpe todo lo que «debió» producir sin salida.
	var deuda = cortadora.production_debt;
	for t in range(25):
		cortadora.update();
	_check("una vez parada no emite nada más y su deuda de producción tampoco acumula",
		emitido[0] == 10 and _near(cortadora.production_debt, deuda),
		"emitió %d, deuda %f -> %f" % [emitido[0], deuda, cortadora.production_debt]);
	# El techo de la línea NO lo toca la parada, igual que no lo toca el ahogo: es lo que
	# gameManager._installed_rate() usa para juzgar el tier, y bajarlo pagaría cartas potentes
	# por jugar mal.
	_check("una factoría parada no baja su techo: getEffectiveOutput() no se entera",
		cortadora.getEffectiveOutput() == 1 and cortadora.blocked_reason == "output",
		"techo %d" % cortadora.getEffectiveOutput());

	# --- Parada por búfer lleno NO consume insumos, igual que el tick ahogado: sería un
	# sumidero de material, porque consumeNeeds() vacía el input_buffer.
	var sierra = _factoria_en_main(main, "WoodProcessing", Vector2i(1, 4), 1, ["wood"], "plank");
	sierra.resource_produced.connect(main._on_resource_produced.bind(sierra));
	sierra.receiveMaterial("wood", 99);
	for t in range(10):
		sierra.update();
	_check("una serrería con insumo de sobra y sin salida produce 10 y llena el búfer",
		sierra.output_buffer == script_fab.OUTPUT_BUFFER_MAX
		and int(sierra.input_buffer["wood"]) == 89,
		"búfer %d, insumo %d" % [sierra.output_buffer, int(sierra.input_buffer["wood"])]);
	# La razón la escribe update() y SOLO update(), que es donde vive la prioridad de las
	# cuatro: storeOutput() no la toca, o una factoría sin workers y con el búfer lleno diría
	# "output". Así que el tick que llena el búfer produce, y el que se para es el siguiente.
	sierra.update();
	_check("y se para en el tick siguiente, que es cuando de verdad no produce",
		sierra.blocked_reason == "output" and int(sierra.input_buffer["wood"]) == 89,
		"razón '%s', insumo %d" % [sierra.blocked_reason, int(sierra.input_buffer["wood"])]);
	for t in range(20):
		sierra.update();
	_check("y parada NO consume insumos: el búfer de entrada no baja ni una unidad",
		int(sierra.input_buffer["wood"]) == 89 and sierra.blocked_reason == "output",
		"insumo %d" % int(sierra.input_buffer["wood"]));

	# --- La prioridad de las cuatro razones: workers -> input -> output. La fija el Plan -
	# Feedback de Cuellos de Botella y aquí se comprueba con las tres cumpliéndose a la vez.
	var prio = _factoria_en_main(main, "WoodProcessing", Vector2i(1, 6), 1, ["wood"], "plank");
	prio.workers_needed = 1;
	prio.workers_assigned = 0;
	prio.output_buffer = script_fab.OUTPUT_BUFFER_MAX;
	prio.update();
	_check("sin workers manda 'workers', aunque falte el insumo y el búfer esté lleno",
		prio.blocked_reason == "workers", "razón '%s'" % prio.blocked_reason);
	prio.workers_assigned = 1;
	prio.update();
	_check("con workers y sin insumo, 'input' antes que 'output'",
		prio.blocked_reason == "input", "razón '%s'" % prio.blocked_reason);
	prio.receiveMaterial("wood", 3);
	prio.update();
	_check("con insumo y el búfer lleno, 'output'",
		prio.blocked_reason == "output" and int(prio.input_buffer["wood"]) == 3,
		"razón '%s', insumo %d" % [prio.blocked_reason, int(prio.input_buffer["wood"])]);
	prio.clearOutputBuffer();
	prio.update();
	_check("y con el búfer vacío vuelve a producir, con la razón en blanco",
		prio.blocked_reason == "" and int(prio.input_buffer["wood"]) == 2,
		"razón '%s', insumo %d" % [prio.blocked_reason, int(prio.input_buffer["wood"])]);

	# --- Las que no producen material no tienen salida que atascar. La restauración NUNCA se
	# bloquea por 'output': que se ahogase limpiar es justo lo que el diseño evita.
	var bosque = _factoria_en_main(main, "Reforester", Vector2i(3, 6), 1, null, null, "restoration");
	bosque.output_buffer = script_fab.OUTPUT_BUFFER_MAX;
	bosque.update();
	_check("el Reforester no se bloquea por 'output' ni con el búfer forzado al tope",
		bosque.blocked_reason == "", "razón '%s'" % bosque.blocked_reason);
	var alm_libre = _factoria_en_main(main, "Storage", Vector2i(3, 2), 1, null, null, "storage");
	alm_libre.output_buffer = script_fab.OUTPUT_BUFFER_MAX;
	alm_libre.receiveMaterial("wood", 3);
	alm_libre.update(bolsa);
	_check("y el almacén tampoco: vuelca en la bolsa aunque le fuercen el búfer de salida",
		alm_libre.blocked_reason == "" and bolsa.getQuantity("wood") == 3
		and alm_libre.input_buffer.is_empty(),
		"razón '%s', bolsa %d" % [alm_libre.blocked_reason, bolsa.getQuantity("wood")]);

	# --- Las dos excepciones: ni el worker ni el factory_token viajan por cinta, así que
	# tampoco pueden llenar un búfer de salida. Una WorkerCamp sin cinta NO DEBE pararse jamás
	# —si se parara, el juego se quedaría sin workers por no tender una cinta que no le hace
	# falta—.
	main.get_node("Player").availableFactories = file_data["Factories"].keys();
	var campamento = _factoria_en_main(main, "WorkerCamp", Vector2i(8, 1), 1, null, "worker");
	campamento.resource_produced.connect(main._on_resource_produced.bind(campamento));
	var workers_antes = bolsa.workers_total;
	for t in range(30):
		campamento.update();
	_check("una WorkerCamp sin cinta no se atasca nunca: 30 ticks, 30 workers y el búfer a cero",
		campamento.output_buffer == 0 and campamento.blocked_reason == ""
		and bolsa.workers_total == workers_antes + 30,
		"búfer %d, razón '%s', workers %d -> %d" % [campamento.output_buffer,
			campamento.blocked_reason, workers_antes, bolsa.workers_total]);
	var meta = _factoria_en_main(main, "MetaFactory", Vector2i(8, 4), 1, null, "factory_token");
	meta.resource_produced.connect(main._on_resource_produced.bind(meta));
	for t in range(30):
		meta.update();
	_check("y una MetaFactory tampoco: el factory_token no pasa por cinta y no llena búfer",
		meta.output_buffer == 0 and meta.blocked_reason == ""
		and bolsa.getQuantity("factory_token") == 30,
		"búfer %d, razón '%s', tokens %d" % [meta.output_buffer, meta.blocked_reason,
			bolsa.getQuantity("factory_token")]);
	paused = false;

	# --- El *Hecho cuando*, segunda mitad: al tenderle una cinta al almacén vacía su búfer y
	# sigue. El vaciado ocurre en el gesto mismo (beltNetwork.place_drag() -> flush), no al
	# tick siguiente: una factoría parada no emite nada, así que nada dispararía el reintento.
	var wood_antes = bolsa.getQuantity("wood");
	var almacen = _factoria_en_main(main, "Storage", Vector2i(6, 1), 1, null, null, "storage");
	var tendida = red.place_drag(Vector2i(2, 1), Vector2i(5, 1), main.factoryArray);
	_check("la cinta se tiende de la cortadora parada al almacén",
		tendida.size() == 4, "tendió %s" % str(tendida));
	_check("al tenderla vacía el búfer en el acto y deja de estar bloqueada",
		cortadora.output_buffer == 0 and cortadora.blocked_reason == ""
		and int(almacen.input_buffer.get("wood", 0)) == 10,
		"búfer %d, razón '%s', almacén %s" % [cortadora.output_buffer,
			cortadora.blocked_reason, str(almacen.input_buffer)]);
	almacen.update(bolsa);
	_check("y esas 10 unidades atascadas acaban en la bolsa por el almacén",
		bolsa.getQuantity("wood") == wood_antes + 10,
		"%d -> %d" % [wood_antes, bolsa.getQuantity("wood")]);
	var emitido_antes = emitido[0];
	for t in range(5):
		cortadora.update();
		almacen.update(bolsa);
	_check("y sigue produciendo: con salida el búfer ya no vuelve a llenarse",
		emitido[0] == emitido_antes + 5 and cortadora.output_buffer == 0
		and cortadora.blocked_reason == "" and bolsa.getQuantity("wood") == wood_antes + 15,
		"emitió %d, búfer %d, bolsa %d" % [emitido[0], cortadora.output_buffer,
			bolsa.getQuantity("wood")]);
	# La serrería de (1,4) sigue parada: el flush recorre todas las factorías, pero solo
	# desatasca a las que de verdad tienen camino.
	_check("el flush no regala salida a quien no tiene cinta: la serrería sigue parada",
		sierra.output_buffer == script_fab.OUTPUT_BUFFER_MAX and sierra.blocked_reason == "output",
		"búfer %d" % sierra.output_buffer);
	_limpiar([main]);

	# --- «Y por tanto DEJA DE CONTAMINAR», que es la mitad cara del hito: la que mueve el
	# balance de la derrota. Escenario aparte y montado después de
	# soltar el anterior, porque _apply_pollution() y getPollutionChoke() localizan el manager
	# con find_child y ése devuelve el PRIMER PollutionManager del árbol.
	var main_p = _new_main_en_arbol(file_data);
	var tm_p = main_p.get_node("TileMap");
	var bolsa_p = main_p.get_node("Player/Bag");
	for y in range(8):
		for x in range(10):
			tm_p.set_cell(0, Vector2i(x, y), 1, Vector2i(0, 0));
	var pm = _new_pm();
	pm.name = "PollutionManager";
	main_p.add_child(pm);
	var red_p = script_red.new();
	red_p.name = "BeltNetwork";
	main_p.add_child(red_p);
	red_p.initialize(tm_p, main_p.factoryArray);
	tm_p.setBeltNetwork(red_p);
	main_p.beltNetwork = red_p;

	var sucia = _factoria_en_main(main_p, "WoodCutter", Vector2i(1, 1), 1, null, "wood");
	sucia.pollutionAmount = 0.1;
	sucia.resource_produced.connect(main_p._on_resource_produced.bind(sucia));
	var vueltas = 0;
	while sucia.blocked_reason != "output" and vueltas < 300:
		sucia.update();
		vueltas += 1;
	_check("una cortadora que ensucia acaba parándose igual por búfer lleno",
		sucia.blocked_reason == "output" and sucia.output_buffer == script_fab.OUTPUT_BUFFER_MAX,
		"razón '%s' tras %d ticks" % [sucia.blocked_reason, vueltas]);
	var sucio_al_parar = pm.total_pollution;
	_check("hasta pararse sí había ensuciado", sucio_al_parar > 0.0,
		"contaminación %f" % sucio_al_parar);
	for t in range(30):
		sucia.update();
	_check("y una vez parada DEJA DE CONTAMINAR: 30 ticks más y la contaminación no sube",
		_near(pm.total_pollution, sucio_al_parar),
		"%f -> %f" % [sucio_al_parar, pm.total_pollution]);

	# --- La regla del tick ahogado, ya existente, sigue en pie y no la pisa la parada nueva:
	# un tick con eff_out <= 0 no entrega, no ensucia y no anima, pero la DEUDA acumula — es
	# lo que hace del ahogo una rampa y no un interruptor. Lo que SÍ cambió es el estado: el
	# quinto valor ('choke') lo escribe desde el M1 del Plan - Feedback de Cuellos de Botella,
	# que es de quien era la decisión; hasta entonces este tick dejaba la razón en blanco.
	var ahogada = _factoria_en_main(main_p, "WoodCutter", Vector2i(1, 6), 1, null, "wood");
	# 6,25 de 12,5 es exactamente medio ahogo, así que la rampa es 1 de cada 2 ticks y la
	# cuenta no depende de cómo redondee el float.
	pm.addPollution(6.25, Vector2i(1, 6));
	var emitido_ahogo = [0];
	ahogada.resource_produced.connect(func(_m, c, _p): emitido_ahogo[0] += c);
	_check("la casilla ahoga a la mitad", _near(ahogada.getPollutionChoke(), 0.5),
		"choke %f" % ahogada.getPollutionChoke());
	ahogada.update();
	_check("un tick ahogado sigue sin entregar y la deuda acumula, como antes de M4",
		emitido_ahogo[0] == 0 and _near(ahogada.production_debt, 0.5),
		"emitió %d, deuda %f" % [emitido_ahogo[0], ahogada.production_debt]);
	_check("y desde Cuellos M1 lo dice: el tick ahogado escribe blocked_reason == 'choke'",
		ahogada.blocked_reason == "choke", "razón '%s'" % ahogada.blocked_reason);
	ahogada.update();
	_check("y al segundo tick entrega 1: la rampa sigue siendo rampa y no un interruptor",
		emitido_ahogo[0] == 1, "emitió %d" % emitido_ahogo[0]);

	# --- Y el cierre: con la cinta puesta la contaminada vuelve a producir Y a ensuciar. Es
	# lo que hace que la parada sea reversible y no una sentencia.
	var almacen_p = _factoria_en_main(main_p, "Storage", Vector2i(6, 1), 1, null, null, "storage");
	red_p.place_drag(Vector2i(2, 1), Vector2i(5, 1), main_p.factoryArray);
	_check("al tenderle la cinta se desatasca también la que contamina",
		sucia.output_buffer == 0 and sucia.blocked_reason == ""
		and int(almacen_p.input_buffer.get("wood", 0)) == 10, str(almacen_p.input_buffer));
	var sucio_antes = pm.total_pollution;
	for t in range(10):
		sucia.update();
	_check("y vuelve a producir y a ensuciar, así que la parada es reversible",
		pm.total_pollution > sucio_antes and sucia.output_buffer == 0,
		"%f -> %f, búfer %d" % [sucio_antes, pm.total_pollution, sucia.output_buffer]);

	# --- La otra forma de que aparezca un camino: la cinta ya estaba tendida y lo que faltaba
	# era el DESTINO al final. Es lo que hace Main._on_factory_chosen() al construir —invalida
	# el índice y vacía los búferes—, y sin ello una factoría parada no se enteraría nunca: no
	# produce, así que nada dispararía el reintento.
	var colgada = _factoria_en_main(main_p, "WoodCutter", Vector2i(1, 4), 1, null, "wood");
	colgada.resource_produced.connect(main_p._on_resource_produced.bind(colgada));
	red_p.place_drag(Vector2i(2, 4), Vector2i(5, 4), main_p.factoryArray);
	for t in range(11):
		colgada.update();
	_check("una cinta que no lleva a ninguna parte no desatasca nada: se para igual",
		colgada.output_buffer == script_fab.OUTPUT_BUFFER_MAX
		and colgada.blocked_reason == "output",
		"búfer %d, razón '%s'" % [colgada.output_buffer, colgada.blocked_reason]);
	var destino = _factoria_en_main(main_p, "Storage", Vector2i(6, 4), 1, null, null, "storage");
	red_p.flush_output_buffers();
	_check("poner el destino al final de la cinta la desatasca, como al construir en el juego",
		colgada.output_buffer == 0 and colgada.blocked_reason == ""
		and int(destino.input_buffer.get("wood", 0)) == 10,
		"búfer %d, razón '%s', destino %s" % [colgada.output_buffer, colgada.blocked_reason,
			str(destino.input_buffer)]);
	_limpiar([main_p]);

# ---------- Cintas M5: el almacén emite a sus consumidores, y el filtro ----------

# 🔴 QUÉ MIDE ESTE BLOQUE DESDE EL 2026-09-23. La mitad de arriba cambió entera: el almacén ya
# no emite «el material que el jugador elija en el panel» sino LO QUE PIDEN los consumidores que
# hay al final de cada una de sus cintas de salida, y por TODAS sus cintas, no solo por la
# primera. Lo que estas pruebas fijan es esa regla nueva —quién recibe, qué, cuánto y en qué
# orden— más lo que NO cambió: el filtro de la cinta, la reserva del checkpoint, el guardia del
# almacén que se auto-entrega y que emitir no le da búfer de salida.
func _test_cintas_m5(file_data):
	print("Cintas M5 — el almacén emite a sus consumidores, y el filtro");
	var script_red = load("res://managers/beltNetwork.gd");
	var script_fab = load("res://entities/factory/factoryData.gd");
	var main = _new_main_en_arbol(file_data);
	var tm = main.get_node("TileMap");
	var bolsa = main.get_node("Player/Bag");
	# 16x16 de suelo: caben la línea larga del criterio del hito, el anillo que se cierra en el
	# propio almacén y los cuatro repartos de abajo sin estorbarse entre sí.
	for y in range(16):
		for x in range(16):
			tm.set_cell(0, Vector2i(x, y), 1, Vector2i(0, 0));
	var red = script_red.new();
	red.name = "BeltNetwork";
	main.add_child(red);
	red.initialize(tm, main.factoryArray);
	tm.setBeltNetwork(red);
	main.beltNetwork = red;

	# --- (1) LA SELECCIÓN MANUAL SE FUE ---
	var almacen = _factoria_en_main(main, "Storage", Vector2i(1, 1), 1, null, null, "storage");
	# El almacén del mapa lo conecta mapLoader.place_storage() con el `on_produced` del
	# contexto; aquí se ata a mano igual que Main._on_factory_chosen(), con el nodo bindeado
	# porque deliver() necesita la CELDA y la señal solo lleva la posición de mundo.
	almacen.resource_produced.connect(main._on_resource_produced.bind(almacen));
	_check("un almacén no tiene nada que elegir: su único candidato es el `null` del JSON",
		almacen.production_candidates == [null] and not almacen.hasMaterialChoice()
		and almacen.production == null, str(almacen.production_candidates));

	bolsa.addToBag("wood", 10);
	bolsa.addToBag("plank", 40);
	_check("y llenar la bolsa ya no le cambia la lista: la lista dinámica se fue con el desplegable",
		almacen.production_candidates == [null], str(almacen.production_candidates));
	_check("setProduction() rechaza cualquier material en un almacén: no hay elección que hacer",
		not almacen.setProduction("plank") and almacen.production == null,
		str(almacen.production));
	# Las dos excepciones de siempre siguen donde estaban: ni el worker ni el factory_token
	# viajan por cinta, y más abajo se comprueba que un almacén tampoco los emite aunque un
	# destino los declare en su `recieve`.
	_check("y la lista de exclusiones es exactamente esas dos",
		script_fab.BELT_EXCLUDED_MATERIALS == ["worker", "factory_token"],
		str(script_fab.BELT_EXCLUDED_MATERIALS));

	# La contrapartida del cambio: en el resto del JSON no se ha movido nada. La `Foundry` sigue
	# siendo la única con desplegable —su lista ESTÁTICA, la que el campo `materials` vino a
	# servir—.
	var solo_la_fundicion = true;
	for nombre in file_data["Factories"]:
		var f = script_fab.new();
		var p = file_data["Factories"][nombre];
		f.initialize(nombre, p["tick"], p.get("recieve", null), p.get("material", null), 1, 0.0,
			p.get("type", "production"), int(p.get("workers_needed", 0)),
			p.get("materials", null));
		if f.hasMaterialChoice() != (nombre == "Foundry"):
			solo_la_fundicion = false;
		f.free();
	_check("de las nueve entradas del JSON solo la Foundry tiene desplegable: el almacén ya no",
		solo_la_fundicion);

	# --- (2) SIN CINTA DE SALIDA NO EMITE NADA ---
	var meta = _factoria_en_main(main, "MetaFactory", Vector2i(8, 1), 12, ["plank"], "factory_token");
	var wood_antes = bolsa.getQuantity("wood");
	var plank_antes = bolsa.getQuantity("plank");
	almacen.update(bolsa);
	_check("sin cinta de salida no emite nada, por llena que esté la bolsa",
		bolsa.getQuantity("plank") == plank_antes and bolsa.getQuantity("wood") == wood_antes
		and meta.input_buffer.is_empty() and red.output_segments(Vector2i(1, 1)).is_empty(),
		"bolsa plank %d, búfer %s" % [bolsa.getQuantity("plank"), str(meta.input_buffer)]);

	# Y una cinta que va HACIA el almacén NO es una salida suya: la cadena típica, con todas las
	# cintas terminando en el almacén, no cambia con esta regla.
	var cortadora = _factoria_en_main(main, "WoodCutter", Vector2i(1, 5), 1, null, "wood");
	red.place_drag(cortadora.cell_position, almacen.cell_position, main.factoryArray);
	plank_antes = bolsa.getQuantity("plank");
	almacen.update(bolsa);
	_check("una cinta que va HACIA el almacén no es una salida: sigue sin emitir",
		red.output_segments(Vector2i(1, 1)).is_empty()
		and bolsa.getQuantity("plank") == plank_antes,
		"salidas %d" % red.output_segments(Vector2i(1, 1)).size());

	# --- (3) UNA CINTA A UN CONSUMIDOR: le emite lo que ese consumidor declara ---
	# Lejano y por cinta, que es la decisión del 2026-09-18: no hay entrega por adyacencia,
	# tampoco desde el almacén.
	var tendida = red.place_drag(almacen.cell_position, meta.cell_position, main.factoryArray);
	_check("la cinta va del almacén a la MetaFactory lejana, seis casillas de por medio",
		tendida.size() == 6, "tendió %s" % str(tendida));
	plank_antes = bolsa.getQuantity("plank");
	wood_antes = bolsa.getQuantity("wood");
	for t in range(5):
		almacen.update(bolsa);
	_check("🔴 el almacén emite SOLO lo que la MetaFactory declara en su `recieve`, sin que nadie lo elija",
		int(meta.input_buffer.get("plank", 0)) == 5
		and bolsa.getQuantity("plank") == plank_antes - 5
		and bolsa.getQuantity("wood") == wood_antes,
		"búfer %s, plank %d (antes %d), wood %d (antes %d)" % [str(meta.input_buffer),
			bolsa.getQuantity("plank"), plank_antes, bolsa.getQuantity("wood"), wood_antes]);
	_check("y emitir no le da búfer de salida: el almacén no se atasca (contrato de M4)",
		almacen.output_buffer == 0 and almacen.blocked_reason == "",
		"búfer %d, razón '%s'" % [almacen.output_buffer, almacen.blocked_reason]);
	_check("la cinta de cada emisión se apunta solo DURANTE el emit: fuera de él no queda rastro",
		almacen.emit_route_cell == null, str(almacen.emit_route_cell));
	_check("storeOutput() es un no-op en el almacén, se le llame desde donde se le llame",
		almacen.storeOutput(7) == 0 and almacen.output_buffer == 0);

	# --- (4) EL FILTRO POR CINTA (M5), que la regla nueva consulta ANTES de elegir material ---
	_check("un segmento recién tendido nace sin filtro: acepta todo",
		red.get_belt_filter(Vector2i(2, 1)) == "", red.get_belt_filter(Vector2i(2, 1)));
	var avisos = [0];
	red.belt_network_changed.connect(func(): avisos[0] += 1);

	# Filtro que DEJA PASAR: el mismo material que el destino pide.
	_check("set_belt_filter() pone el filtro y avisa por belt_network_changed",
		red.set_belt_filter(Vector2i(2, 1), "plank")
		and red.get_belt(Vector2i(2, 1)).filter == "plank" and avisos[0] == 1,
		"filtro '%s', avisos %d" % [red.get_belt(Vector2i(2, 1)).filter, avisos[0]]);
	meta.input_buffer.clear();
	plank_antes = bolsa.getQuantity("plank");
	almacen.update(bolsa);
	_check("con filtro «plank» la cinta deja pasar y la MetaFactory sigue recibiendo",
		int(meta.input_buffer.get("plank", 0)) == 1
		and bolsa.getQuantity("plank") == plank_antes - 1,
		"búfer %s, bolsa %d" % [str(meta.input_buffer), bolsa.getQuantity("plank")]);

	# Filtro que RECHAZA. Y aquí está la diferencia con la versión de 2026-09-18: el almacén
	# consulta el filtro ANTES de sacar nada, así que no hay ni emisión ni devolución — la
	# bolsa no se mueve en ningún momento, en vez de moverse dos veces en el mismo tick.
	red.set_belt_filter(Vector2i(2, 1), "wood");
	meta.input_buffer.clear();
	plank_antes = bolsa.getQuantity("plank");
	for t in range(3):
		almacen.update(bolsa);
	_check("poniéndole filtro «wood» a esa misma cinta la MetaFactory deja de recibir",
		meta.input_buffer.is_empty(), str(meta.input_buffer));
	_check("y con el filtro cerrado la bolsa no se mueve: no se emite lo que la cinta no lleva",
		bolsa.getQuantity("plank") == plank_antes,
		"bolsa %d (antes %d)" % [bolsa.getQuantity("plank"), plank_antes]);
	_check("el almacén rechazado sigue sin búfer de salida y sin bloquearse",
		almacen.output_buffer == 0 and almacen.blocked_reason == "",
		"búfer %d, razón '%s'" % [almacen.output_buffer, almacen.blocked_reason]);

	# La red de seguridad de Main sigue viva y hace falta: quien PLANEA la emisión (el tick) y
	# quien la ENTREGA (Main._on_resource_produced) son dos pasos distintos, y entre medias
	# alguien puede haber filtrado, borrado o demolido. Se llama al encaminador a mano, que es
	# exactamente lo que pasaría si la red cambiara entre los dos pasos.
	var plank_devuelto = bolsa.getQuantity("plank");
	main._on_resource_produced("plank", 3, almacen.global_position, almacen);
	_check("una emisión ya descontada que no encuentra salida VUELVE a la bolsa, sin perderse",
		bolsa.getQuantity("plank") == plank_devuelto + 3,
		"bolsa %d (antes %d)" % [bolsa.getQuantity("plank"), plank_devuelto]);
	bolsa.removeFromBag("plank", 3);

	# Filtro "" : el valor por defecto, que vuelve a aceptar todo.
	red.set_belt_filter(Vector2i(2, 1), "");
	meta.input_buffer.clear();
	plank_antes = bolsa.getQuantity("plank");
	almacen.update(bolsa);
	_check("el filtro «» acepta todo otra vez y la línea vuelve a fluir",
		int(meta.input_buffer.get("plank", 0)) == 1
		and bolsa.getQuantity("plank") == plank_antes - 1
		and red.get_belt_filter(Vector2i(2, 1)) == "",
		"búfer %s, filtro '%s'" % [str(meta.input_buffer), red.get_belt_filter(Vector2i(2, 1))]);
	_check("poner el filtro que ya estaba no cambia nada y no vuelve a avisar",
		red.set_belt_filter(Vector2i(2, 1), "") == false);
	_check("y una celda sin cinta no tiene filtro que poner",
		red.set_belt_filter(Vector2i(9, 9), "wood") == false
		and red.get_belt_filter(Vector2i(9, 9)) == "");

	# --- (5) 🔴 LA RESERVA DEL PEAJE: se emite de getAvailable(), NO de getQuantity() ---
	# Es la regla del CLAUDE.md por la que las factorías consumen de getAvailable(): el
	# almacén aparta lo que el checkpoint en curso exige, y un almacén que emitiera el peaje
	# por una cinta colgaría la run para siempre. El bug ya se sufrió una vez.
	meta.input_buffer.clear();
	bolsa.setReserved({ "plank": bolsa.getQuantity("plank") });
	plank_antes = bolsa.getQuantity("plank");
	for t in range(3):
		almacen.update(bolsa);
	_check("con TODO el plank reservado para el checkpoint el almacén no emite ni uno",
		meta.input_buffer.is_empty() and bolsa.getQuantity("plank") == plank_antes
		and bolsa.getAvailable("plank") == 0,
		"búfer %s, bolsa %d" % [str(meta.input_buffer), bolsa.getQuantity("plank")]);
	bolsa.setReserved({ "plank": plank_antes - 2 });
	almacen.update(bolsa);
	almacen.update(bolsa);
	almacen.update(bolsa);
	_check("y con solo 2 fuera de la reserva emite exactamente 2 y se para ahí",
		int(meta.input_buffer.get("plank", 0)) == 2
		and bolsa.getQuantity("plank") == plank_antes - 2,
		"búfer %s, bolsa %d de %d" % [str(meta.input_buffer), bolsa.getQuantity("plank"),
			plank_antes]);
	bolsa.setReserved({});

	# --- (6) SIN EXISTENCIAS, NI EMISIÓN NI RUIDO ---
	meta.input_buffer.clear();
	bolsa.removeFromBag("plank", bolsa.getQuantity("plank"));
	almacen.update(bolsa);
	_check("con la bolsa a cero del material que piden simplemente no emite",
		meta.input_buffer.is_empty() and bolsa.getQuantity("plank") == 0
		and almacen.blocked_reason == "", str(meta.input_buffer));
	bolsa.addToBag("plank", 30);

	# --- (7) El almacén sigue ACEPTANDO lo que le llega (M3) mientras emite ---
	almacen.receiveMaterial("wood", 4);
	wood_antes = bolsa.getQuantity("wood");
	almacen.update(bolsa);
	_check("el almacén vuelca en la bolsa lo que le traen y emite lo suyo en el mismo tick",
		bolsa.getQuantity("wood") == wood_antes + 4 and almacen.input_buffer.is_empty()
		and int(meta.input_buffer.get("plank", 0)) >= 1,
		"wood %d (antes %d), búfer meta %s" % [bolsa.getQuantity("wood"), wood_antes,
			str(meta.input_buffer)]);

	# --- (8) El bucle que se cierra en el PROPIO almacén ---
	# Dos arrastres bastan: la L horizontal-primero hace que el primer tramo mire hacia atrás
	# (al almacén) y que el último siga recto, y el segundo arrastre termina subiendo justo
	# sobre su casilla. Sin el guardia, el almacén sacaría de la bolsa y se lo volvería a
	# meter cada tick; el set de visitadas no lo ve, porque el ciclo se cierra por fuera de
	# la cinta, en la factoría.
	var lazo = _factoria_en_main(main, "Storage", Vector2i(5, 6), 1, null, null, "storage");
	lazo.resource_produced.connect(main._on_resource_produced.bind(lazo));
	red.place_drag(Vector2i(6, 6), Vector2i(7, 7), main.factoryArray);
	red.place_drag(Vector2i(7, 8), Vector2i(5, 7), main.factoryArray);
	_check("el anillo sale del almacén y vuelve a su casilla",
		red.output_segment(Vector2i(5, 6)) != null
		and red.get_belt(Vector2i(5, 7)) != null
		and red.get_belt(Vector2i(5, 7)).cell + red.get_belt(Vector2i(5, 7)).dir_out == Vector2i(5, 6),
		"salida %s" % str(red.get_belt(Vector2i(5, 7)).dir_out if red.get_belt(Vector2i(5, 7)) else null));
	var t0 = Time.get_ticks_msec();
	var plank_lazo = bolsa.getQuantity("plank");
	for t in range(5):
		lazo.update(bolsa);
	_check("un almacén que se auto-entrega no saca nada de la bolsa y no cuelga el juego",
		bolsa.getQuantity("plank") == plank_lazo and lazo.input_buffer.is_empty()
		and Time.get_ticks_msec() - t0 < 500,
		"bolsa %d (antes %d), búfer %s" % [bolsa.getQuantity("plank"), plank_lazo,
			str(lazo.input_buffer)]);
	_check("deliver() corta la entrega a uno mismo antes de tocar el búfer de entrada",
		red.deliver(Vector2i(5, 6), "plank", 3) == 0 and lazo.input_buffer.is_empty(),
		str(lazo.input_buffer));

	# --- (9) 🔴 VARIAS CINTAS: emite por TODAS, y a cada una lo suyo ---
	# El defecto que esto cierra: `_entry_segment()` devuelve el PRIMER vecino cuyo `dir_in`
	# apunte a la celda, así que un almacén con dos líneas alimentaba solo a una y la otra era
	# decorado. Tres cintas: dos consumidores que piden materiales DISTINTOS y un tercer
	# almacén, que no debe recibir nada.
	var almacen_r = _factoria_en_main(main, "Storage", Vector2i(3, 11), 1, null, null, "storage");
	almacen_r.resource_produced.connect(main._on_resource_produced.bind(almacen_r));
	var sierra = _factoria_en_main(main, "WoodProcessing", Vector2i(7, 11), 4, ["wood"], "plank");
	var meta_o = _factoria_en_main(main, "MetaFactory", Vector2i(0, 11), 12, ["plank"], "factory_token");
	var almacen_n = _factoria_en_main(main, "Storage", Vector2i(3, 9), 1, null, null, "storage");
	red.place_drag(almacen_r.cell_position, sierra.cell_position, main.factoryArray);
	red.place_drag(almacen_r.cell_position, meta_o.cell_position, main.factoryArray);
	red.place_drag(almacen_r.cell_position, almacen_n.cell_position, main.factoryArray);
	var celdas_salida = [];
	for seg in red.output_segments(almacen_r.cell_position):
		celdas_salida.append(seg.cell);
	_check("🔴 output_segments() devuelve las TRES salidas, en el orden fijo de ORTHOGONAL_DIRS",
		celdas_salida == [Vector2i(4, 11), Vector2i(2, 11), Vector2i(3, 10)],
		str(celdas_salida));
	_check("y output_segment() sigue devolviendo una sola: el panel edita el filtro de UNA cinta",
		red.output_segment(almacen_r.cell_position).cell == Vector2i(4, 11),
		str(red.output_segment(almacen_r.cell_position).cell));
	var wood_r = bolsa.getQuantity("wood");
	var plank_r = bolsa.getQuantity("plank");
	almacen_r.update(bolsa);
	_check("🔴 con dos cintas emite por LAS DOS, y a cada destino lo que ese destino pide",
		int(sierra.input_buffer.get("wood", 0)) == 1
		and int(meta_o.input_buffer.get("plank", 0)) == 1
		and bolsa.getQuantity("wood") == wood_r - 1
		and bolsa.getQuantity("plank") == plank_r - 1,
		"sierra %s, meta %s, wood %d/%d, plank %d/%d" % [str(sierra.input_buffer),
			str(meta_o.input_buffer), bolsa.getQuantity("wood"), wood_r,
			bolsa.getQuantity("plank"), plank_r]);
	_check("🔴 y al almacén del final de la tercera cinta NO le manda nada: sería trasiego en bucle",
		almacen_n.input_buffer.is_empty(), str(almacen_n.input_buffer));

	# --- (10) Un destino que pide DOS materiales: uno por tick, el primero de su `recieve` ---
	var almacen_dos = _factoria_en_main(main, "Storage", Vector2i(13, 1), 1, null, null, "storage");
	almacen_dos.resource_produced.connect(main._on_resource_produced.bind(almacen_dos));
	var fundicion = _factoria_en_main(main, "Foundry", Vector2i(13, 4), 4, ["stone", "wood"], "brick");
	red.place_drag(almacen_dos.cell_position, fundicion.cell_position, main.factoryArray);
	bolsa.addToBag("stone", 6);
	var stone_antes = bolsa.getQuantity("stone");
	wood_antes = bolsa.getQuantity("wood");
	almacen_dos.update(bolsa);
	_check("a un destino que pide dos materiales le manda UNO por tick: el primero de su `recieve`",
		fundicion.input_buffer == { "stone": 1 }
		and bolsa.getQuantity("stone") == stone_antes - 1
		and bolsa.getQuantity("wood") == wood_antes, str(fundicion.input_buffer));

	# --- (11) DOS DESTINOS NO SE GASTAN LO MISMO, y con existencias justas manda el orden ---
	var almacen_c = _factoria_en_main(main, "Storage", Vector2i(8, 14), 1, null, null, "storage");
	almacen_c.resource_produced.connect(main._on_resource_produced.bind(almacen_c));
	var sierra_e = _factoria_en_main(main, "WoodProcessing", Vector2i(11, 14), 4, ["wood"], "plank");
	var sierra_o = _factoria_en_main(main, "WoodProcessing", Vector2i(5, 14), 4, ["wood"], "plank");
	red.place_drag(almacen_c.cell_position, sierra_e.cell_position, main.factoryArray);
	red.place_drag(almacen_c.cell_position, sierra_o.cell_position, main.factoryArray);
	# Una sola unidad disponible para dos destinos que piden lo MISMO: el peaje del checkpoint
	# se lleva el resto. Sin descontar lo ya emitido dentro del tick, los dos se llevarían una
	# y la bolsa se quedaría corta.
	bolsa.setReserved({ "wood": bolsa.getQuantity("wood") - 1 });
	wood_antes = bolsa.getQuantity("wood");
	almacen_c.update(bolsa);
	_check("🔴 con existencias para UNO solo, dos destinos no se gastan la misma madera",
		int(sierra_e.input_buffer.get("wood", 0)) + int(sierra_o.input_buffer.get("wood", 0)) == 1
		and bolsa.getQuantity("wood") == wood_antes - 1,
		"este %s, oeste %s, bolsa %d (antes %d)" % [str(sierra_e.input_buffer),
			str(sierra_o.input_buffer), bolsa.getQuantity("wood"), wood_antes]);
	_check("🔴 y se la lleva la cinta que va primero en ORTHOGONAL_DIRS: el reparto es determinista",
		int(sierra_e.input_buffer.get("wood", 0)) == 1 and sierra_o.input_buffer.is_empty(),
		"este %s, oeste %s" % [str(sierra_e.input_buffer), str(sierra_o.input_buffer)]);
	bolsa.setReserved({});
	sierra_e.input_buffer.clear();
	wood_antes = bolsa.getQuantity("wood");
	almacen_c.update(bolsa);
	_check("con existencias de sobra las dos cintas cobran lo suyo en el mismo tick",
		int(sierra_e.input_buffer.get("wood", 0)) == 1
		and int(sierra_o.input_buffer.get("wood", 0)) == 1
		and bolsa.getQuantity("wood") == wood_antes - 2,
		"este %s, oeste %s, bolsa %d (antes %d)" % [str(sierra_e.input_buffer),
			str(sierra_o.input_buffer), bolsa.getQuantity("wood"), wood_antes]);

	# --- (12) `worker` y `factory_token` NO salen por cinta ni pedidos por su nombre ---
	# Main._on_resource_produced() los intercepta ANTES de la red, así que emitirlos sería
	# sacarlos de la bolsa para volver a metértelos por el camino de la excepción.
	var almacen_w = _factoria_en_main(main, "Storage", Vector2i(13, 13), 1, null, null, "storage");
	almacen_w.resource_produced.connect(main._on_resource_produced.bind(almacen_w));
	var campamento = _factoria_en_main(main, "WorkerCamp", Vector2i(13, 10), 5,
		["worker", "plank"], "worker");
	red.place_drag(almacen_w.cell_position, campamento.cell_position, main.factoryArray);
	bolsa.addToBag("worker", 5);
	bolsa.addToBag("factory_token", 3);
	var workers_antes = bolsa.getQuantity("worker");
	plank_antes = bolsa.getQuantity("plank");
	almacen_w.update(bolsa);
	_check("🔴 un destino que pide `worker` no recibe ninguno: no viajan por cinta",
		int(campamento.input_buffer.get("worker", 0)) == 0
		and bolsa.getQuantity("worker") == workers_antes,
		"búfer %s, bolsa %d" % [str(campamento.input_buffer), bolsa.getQuantity("worker")]);
	_check("y se salta al SIGUIENTE material que ese destino pide, en vez de callarse la cinta",
		int(campamento.input_buffer.get("plank", 0)) == 1
		and bolsa.getQuantity("plank") == plank_antes - 1,
		"búfer %s, bolsa %d (antes %d)" % [str(campamento.input_buffer),
			bolsa.getQuantity("plank"), plank_antes]);

	# --- (13) DOS CINTAS AL MISMO CONSUMIDOR: le llega UNA entrega por tick, no dos ---
	# Duplicar cintas no es producir. Sin el guardia de `servidos`, tender una segunda línea al
	# mismo destino le doblaría el ritmo a un almacén sin tocar una sola factoría.
	var almacen_dup = _factoria_en_main(main, "Storage", Vector2i(8, 3), 1, null, null, "storage");
	almacen_dup.resource_produced.connect(main._on_resource_produced.bind(almacen_dup));
	var meta_dup = _factoria_en_main(main, "MetaFactory", Vector2i(10, 3), 12, ["plank"], "factory_token");
	red.place_drag(almacen_dup.cell_position, meta_dup.cell_position, main.factoryArray);
	# El segundo camino al mismo sitio, en tres tramos: sale del almacén hacia abajo, cruza y
	# sube hasta la casilla de la MetaFactory.
	red.place_drag(almacen_dup.cell_position, Vector2i(8, 4), main.factoryArray);
	red.place_drag(Vector2i(8, 5), Vector2i(10, 4), main.factoryArray);
	var celdas_dup = [];
	for seg in red.output_segments(almacen_dup.cell_position):
		celdas_dup.append(seg.cell);
	_check("el almacén tiene DOS salidas y las dos acaban en la misma MetaFactory",
		celdas_dup == [Vector2i(9, 3), Vector2i(8, 4)]
		and red.route_destination(almacen_dup.cell_position, red.get_belt(Vector2i(9, 3))) == meta_dup
		and red.route_destination(almacen_dup.cell_position, red.get_belt(Vector2i(8, 4))) == meta_dup,
		str(celdas_dup));
	plank_antes = bolsa.getQuantity("plank");
	almacen_dup.update(bolsa);
	_check("🔴 y aun así le entrega UNA vez por tick: duplicar cintas no es producir",
		int(meta_dup.input_buffer.get("plank", 0)) == 1
		and bolsa.getQuantity("plank") == plank_antes - 1,
		"búfer %s, bolsa %d (antes %d)" % [str(meta_dup.input_buffer),
			bolsa.getQuantity("plank"), plank_antes]);

	# --- (14) EL PANEL: el almacén ya no tiene desplegable, y el filtro sigue ahí ---
	var panel = load("res://ui/factoryPanel.gd").new();
	main.add_child(panel);
	panel.initialize(almacen, file_data, Vector2(640, 360), bolsa, red);
	_check("🔴 el panel del almacén ya NO monta el desplegable de material: no hay nada que elegir",
		panel._material_option == null);
	_check("y en su lugar dice qué emite de verdad, que es lo que le pidan sus cintas",
		_textos_panel(panel).has("Emite: lo que pidan sus cintas"), str(_textos_panel(panel)));
	_check("el panel monta también el control del filtro de la cinta de salida",
		panel._belt_option != null and panel._belt_row.visible
		and not panel._belt_none_label.visible);
	_check("el índice 0 del filtro es «todo», que es el valor por defecto del segmento",
		panel._belt_option.selected == 0
		and panel._belt_option.get_item_text(0) == "Todo (sin filtro)",
		"seleccionado %d" % panel._belt_option.selected);
	# Solo los materiales que viajan por cinta, sacados del JSON: wood, plank y —desde el M0
	# del Plan «Variedad de Factorías» (2026-09-20)— stone y brick, ni worker ni factory_token.
	# Y `glass` desde el M3 (2026-09-22), que es el primero que NO es el `material` de ninguna
	# entrada: solo aparece en el `materials: [...]` de la `Foundry`, así que si esta lista
	# volviera a leer únicamente `material` el jugador que ha cambiado su fundición a vidrio no
	# podría encaminarlo por un filtro aunque la red sí lo mueva.
	# La lista NO está escrita a ojo: sale de `Factories` y por eso crece con cada factoría
	# nueva. Se compara contra la esperada y no contra el JSON para que añadir una factoría que
	# produzca `worker` o `factory_token` siga poniendo esto en rojo.
	var textos_filtro = [];
	for i in range(panel._belt_option.item_count):
		textos_filtro.append(panel._belt_option.get_item_text(i));
	_check("el filtro ofrece «todo» y los materiales que viajan por cinta, nada más",
		textos_filtro == ["Todo (sin filtro)", "brick", "glass", "plank", "stone", "wood"],
		str(textos_filtro));

	var idx_filtro_wood = textos_filtro.find("wood");
	panel._belt_option.item_selected.emit(idx_filtro_wood);
	_check("marcar «wood» en el panel escribe el filtro en el segmento de salida",
		red.get_belt(Vector2i(2, 1)).filter == "wood",
		red.get_belt(Vector2i(2, 1)).filter);
	meta.input_buffer.clear();
	almacen.update(bolsa);
	_check("y con el filtro puesto DESDE EL PANEL la MetaFactory deja de recibir",
		meta.input_buffer.is_empty(), str(meta.input_buffer));
	panel._belt_option.item_selected.emit(0);
	_check("volver a «todo» desde el panel levanta el filtro",
		red.get_belt(Vector2i(2, 1)).filter == "");

	# `belt_network_changed` existe desde M1 y el plan dice que la escucha el panel: si la red
	# cambia con el panel abierto, lo que enseña se queda viejo.
	_check("el panel escucha belt_network_changed, como dice el plan",
		red.belt_network_changed.is_connected(panel._on_belt_network_changed));
	red.remove_belt(Vector2i(2, 1));
	_check("al borrar la cinta de salida el panel se entera y deja de ofrecer el filtro",
		not panel._belt_row.visible and panel._belt_none_label.visible
		and panel._belt_cell == null);
	# Se retira la línea entera antes de volver a tenderla: `canPlaceFactory()` rechaza una
	# celda que ya tiene cinta, así que un arrastre sobre los cinco tramos que quedaban no
	# cabría (y `place_drag()` es todo o nada).
	for x in range(3, 8):
		red.remove_belt(Vector2i(x, 1));
	red.place_drag(Vector2i(2, 1), Vector2i(7, 1), main.factoryArray);
	_check("y al volver a tenderla el control reaparece solo, sin reabrir el panel",
		panel._belt_row.visible and panel._belt_cell == Vector2i(2, 1)
		and panel._belt_option.selected == 0,
		"celda %s" % str(panel._belt_cell));

	# Y la contrapartida en una factoría de las de siempre: sin desplegable de material.
	var panel_cortadora = load("res://ui/factoryPanel.gd").new();
	main.add_child(panel_cortadora);
	var cortadora_panel = _factoria_en_main(main, "WoodCutter", Vector2i(10, 8), 4, null, "wood");
	panel_cortadora.initialize(cortadora_panel, file_data, Vector2(640, 360), bolsa, red);
	_check("en una WoodCutter el desplegable de material sigue sin aparecer",
		panel_cortadora._material_option == null);
	_check("pero el filtro de cinta sí se le ofrece: es de la cinta, no de la factoría",
		panel_cortadora._belt_option != null and panel_cortadora._belt_none_label.visible,
		"sin cinta de salida todavía");

	_limpiar([main]);

# ---------- Cintas M7: la cinta de una sola casilla ----------

# M7 amplía QUÉ vale como extremo de un arrastre, y nada más: la casilla de una factoría se
# acepta como punta y se excluye del camino, así que la cinta se tiende ENTRE las dos. Es lo
# que hace posible el segmento único y con él unir dos factorías en diagonal. La regla de
# gesto de M1 —misma celda = click de siempre— y el arrastre entre dos celdas libres quedan
# exactamente como estaban, y estas pruebas son sobre todo eso: que no se han movido.
func _test_cintas_m7(file_data):
	print("Cintas M7 — la cinta de una sola casilla");
	var script_red = load("res://managers/beltNetwork.gd");
	var main = _new_main_en_arbol(file_data);
	var tm = main.get_node("TileMap");
	# Suelo de 12x12: caben los seis casos sin que se estorben entre sí.
	for y in range(12):
		for x in range(12):
			tm.set_cell(0, Vector2i(x, y), 1, Vector2i(0, 0));
	var red = script_red.new();
	red.name = "BeltNetwork";
	main.add_child(red);
	red.initialize(tm, main.factoryArray);
	tm.setBeltNetwork(red);
	main.beltNetwork = red;
	var avisos = [0];
	red.belt_network_changed.connect(func(): avisos[0] += 1);

	# --- CASO 1: celda libre -> celda libre. Igual que hasta M6, extremos INCLUIDOS.
	var libres = red.place_drag(Vector2i(1, 1), Vector2i(4, 1), main.factoryArray);
	_check("el arrastre entre dos celdas libres se comporta exactamente igual que hasta M6",
		libres == [Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1), Vector2i(4, 1)],
		"tendió %s" % str(libres));
	var punta = red.get_belt(Vector2i(1, 1));
	var cola = red.get_belt(Vector2i(4, 1));
	_check("y sus dos puntas siguen mirando fuera del camino, como en M1",
		punta.dir_in == Vector2i(-1, 0) and cola.dir_out == Vector2i(1, 0),
		"in %s / out %s" % [str(punta.dir_in), str(cola.dir_out)]);

	# --- CASO 2: dos factorías EN DIAGONAL (manhattan 2). El caso del hito.
	var cortadora = _factoria_en_main(main, "WoodCutter", Vector2i(1, 3), 1, null, "wood");
	var sierra = _factoria_en_main(main, "WoodProcessing", Vector2i(2, 4), 1, ["wood"], "plank");
	var antes = red.belt_count();
	var diagonal = red.place_drag(cortadora.cell_position, sierra.cell_position, main.factoryArray);
	_check("dos factorías en diagonal se unen arrastrando de una a otra",
		diagonal == [Vector2i(2, 3)], "tendió %s" % str(diagonal));
	_check("y queda UN solo segmento entre ellas",
		red.belt_count() == antes + 1, "%d segmentos" % (red.belt_count() - antes));
	var codo = red.get_belt(Vector2i(2, 3));
	_check("las casillas de las dos factorías quedan fuera del camino: no llevan cinta",
		not red.has_belt(cortadora.cell_position) and not red.has_belt(sierra.cell_position));
	_check("el `dir_in` del segmento único apunta a la factoría de origen",
		codo.cell + codo.dir_in == cortadora.cell_position,
		"in %s desde %s" % [str(codo.dir_in), str(codo.cell)]);
	_check("y su `dir_out` apunta a la de destino",
		codo.cell + codo.dir_out == sierra.cell_position,
		"out %s desde %s" % [str(codo.dir_out), str(codo.cell)]);
	_check("`dir_in` y `dir_out` son perpendiculares: la cinta curva, como desde M1",
		codo.dir_in.x * codo.dir_out.x + codo.dir_in.y * codo.dir_out.y == 0
		and codo.dir_in in red.ORTHOGONAL_DIRS and codo.dir_out in red.ORTHOGONAL_DIRS,
		"in %s / out %s" % [str(codo.dir_in), str(codo.dir_out)]);
	_check("el material llega: deliver() encuentra el segmento y entrega en el búfer",
		red.deliver(cortadora.cell_position, "wood", 3) == 3
		and int(sierra.input_buffer.get("wood", 0)) == 3,
		"búfer = %s" % str(sierra.input_buffer));
	# Y por el camino real, que es el que juega el jugador: la cortadora emite, Main encamina.
	sierra.input_buffer.clear();
	cortadora.resource_produced.connect(main._on_resource_produced.bind(cortadora));
	for t in range(3):
		cortadora.update();
	_check("y también por el camino real, emitiendo la cortadora",
		int(sierra.input_buffer.get("wood", 0)) > 0, "búfer = %s" % str(sierra.input_buffer));

	# --- CASO 3: dos factorías EN LÍNEA a manhattan 3. Dos segmentos.
	var c3 = _factoria_en_main(main, "WoodCutter", Vector2i(1, 6), 1, null, "wood");
	var s3 = _factoria_en_main(main, "WoodProcessing", Vector2i(4, 6), 1, ["wood"], "plank");
	var linea = red.place_drag(c3.cell_position, s3.cell_position, main.factoryArray);
	_check("dos factorías en línea a manhattan 3 quedan unidas por DOS segmentos",
		linea == [Vector2i(2, 6), Vector2i(3, 6)], "tendió %s" % str(linea));
	var l0 = red.get_belt(Vector2i(2, 6));
	var l1 = red.get_belt(Vector2i(3, 6));
	_check("la primera mira a su factoría y la última apunta a la otra",
		l0.cell + l0.dir_in == c3.cell_position and l1.cell + l1.dir_out == s3.cell_position,
		"in %s / out %s" % [str(l0.dir_in), str(l1.dir_out)]);
	_check("y el material recorre los dos segmentos",
		red.deliver(c3.cell_position, "wood", 2) == 2
		and int(s3.input_buffer.get("wood", 0)) == 2, str(s3.input_buffer));

	# --- CASO 4: dos factorías ORTOGONALMENTE PEGADAS. Sigue fallando, y es diseño.
	var c4 = _factoria_en_main(main, "WoodCutter", Vector2i(7, 1), 1, null, "wood");
	var s4 = _factoria_en_main(main, "WoodProcessing", Vector2i(8, 1), 1, ["wood"], "plank");
	var antes_4 = red.belt_count();
	var avisos_4 = avisos[0];
	var pegadas = red.place_drag(c4.cell_position, s4.cell_position, main.factoryArray);
	_check("dos factorías pegadas siguen sin poder unirse: entre ellas no hay casilla",
		pegadas.is_empty() and red.belt_count() == antes_4,
		"devolvió %s y la red tiene %d" % [str(pegadas), red.belt_count()]);
	_check("y ese arrastre no avisa por belt_network_changed: no ha pasado nada",
		avisos[0] == avisos_4, "%d avisos" % (avisos[0] - avisos_4));
	_check("tampoco recibe nada la pegada, con o sin M7",
		red.deliver(c4.cell_position, "wood", 1) == 0 and s4.input_buffer.is_empty(),
		str(s4.input_buffer));
	_check("can_place_drag() lo dice igual de claro",
		red.can_place_drag(c4.cell_position, s4.cell_position, main.factoryArray) == false);

	# --- CASO 5: pulsar y soltar en la MISMA celda. La regla de gesto de M1 no se toca.
	var antes_5 = red.belt_count();
	_check("un arrastre que empieza y acaba en la misma celda LIBRE sigue sin tender nada",
		red.place_drag(Vector2i(9, 9), Vector2i(9, 9), main.factoryArray).is_empty()
		and red.belt_count() == antes_5);
	# Y sobre una factoría, que es donde M7 podría haberse colado: recortar los dos extremos
	# de un camino de una celda dejaría el tramo vacío, pero ni siquiera se llega a mirar.
	_check("ni sobre la casilla de una factoría: ahí el click sigue abriendo su panel",
		red.place_drag(cortadora.cell_position, cortadora.cell_position, main.factoryArray).is_empty()
		and not red.has_belt(cortadora.cell_position)
		and red.belt_count() == antes_5);

	# --- CASO 6: mixto. Factoría -> celda libre y celda libre -> factoría, recortando SOLO
	# el extremo ocupado.
	var c6 = _factoria_en_main(main, "WoodCutter", Vector2i(1, 9), 1, null, "wood");
	var salida = red.place_drag(c6.cell_position, Vector2i(3, 9), main.factoryArray);
	_check("factoría -> celda libre tiende cinta excluyendo SOLO el extremo ocupado",
		salida == [Vector2i(2, 9), Vector2i(3, 9)], "tendió %s" % str(salida));
	var s6 = red.get_belt(Vector2i(2, 9));
	_check("y el primer segmento sigue mirando a la factoría del arrastre",
		s6.cell + s6.dir_in == c6.cell_position, str(s6.dir_in));
	var e6 = _factoria_en_main(main, "WoodProcessing", Vector2i(8, 9), 1, ["wood"], "plank");
	var entrada = red.place_drag(Vector2i(6, 9), e6.cell_position, main.factoryArray);
	_check("celda libre -> factoría tiende cinta excluyendo SOLO el extremo ocupado",
		entrada == [Vector2i(6, 9), Vector2i(7, 9)], "tendió %s" % str(entrada));
	var f6 = red.get_belt(Vector2i(7, 9));
	_check("y el último segmento apunta a la factoría del arrastre",
		f6.cell + f6.dir_out == e6.cell_position, str(f6.dir_out));

	# --- La regla de todo o nada NO se relaja para las celdas de en medio: M7 recorta los
	# extremos, no la validación.
	var c7 = _factoria_en_main(main, "WoodCutter", Vector2i(1, 11), 1, null, "wood");
	var estorbo = _factoria_en_main(main, "WoodCutter", Vector2i(3, 11), 1, null, "wood");
	var s7 = _factoria_en_main(main, "WoodProcessing", Vector2i(5, 11), 1, ["wood"], "plank");
	var antes_7 = red.belt_count();
	var tumbado = red.place_drag(c7.cell_position, s7.cell_position, main.factoryArray);
	_check("una factoría en MEDIO del camino sigue tumbando el arrastre entero",
		tumbado.is_empty() and red.belt_count() == antes_7
		and not red.has_belt(Vector2i(2, 11)) and not red.has_belt(Vector2i(4, 11)),
		"devolvió %s" % str(tumbado));
	_check("y una cinta ya tendida en medio también",
		red.place_drag(c6.cell_position, Vector2i(5, 9), main.factoryArray).is_empty());
	# Un lago en medio, que no es ocupación sino tile: la condición 3 de canPlaceFactory().
	tm.set_cell(0, Vector2i(2, 6), 1, Vector2i(0, 0));
	var c8 = _factoria_en_main(main, "WoodCutter", Vector2i(10, 3), 1, null, "wood");
	var s8 = _factoria_en_main(main, "WoodProcessing", Vector2i(10, 7), 1, ["wood"], "plank");
	tm.cell_types[Vector2i(10, 5)] = "mountain";
	_check("y un tile que no admite construcción en medio, también",
		red.place_drag(c8.cell_position, s8.cell_position, main.factoryArray).is_empty()
		and not red.has_belt(Vector2i(10, 4)),
		"cinta en (10,4): %s" % str(red.has_belt(Vector2i(10, 4))));
	tm.cell_types.erase(Vector2i(10, 5));
	_check("quitado el obstáculo, ese mismo arrastre sí tiende los tres segmentos de en medio",
		red.place_drag(c8.cell_position, s8.cell_position, main.factoryArray)
			== [Vector2i(10, 4), Vector2i(10, 5), Vector2i(10, 6)]);

	_limpiar([main]);

# ---------- Costes M1: el campo `cost` y el cobro ----------

# El precio de construir. Se prueba en los dos niveles a los que existe: el placer —que es el
# punto de verdad de «¿puedo pagarlo?» y «cóbramelo», igual que canPlaceFactory() lo es de
# «¿cabe aquí?»— y el camino que pulsa el jugador, Main._on_factory_chosen(), que es donde el
# rechazo tiene que verse. El caso que manda es el tercero: con todo reservado para el
# checkpoint no se puede construir, aunque la bolsa marque de sobra.
func _test_costes_m1(fd):
	print("Costes M1 — el precio de construir y el cobro");

	# (1) Los siete precios, tal y como están hoy en el JSON. Son PROVISIONALES: salieron de
	# mediciones defectuosas, ya retiradas, y se suponen incorrectos. Van en el JSON y no en el
	# código, como todo lo demás de una factoría, así que esto congela el valor actual de la
	# tabla, no una verdad medida: moverlos tiene que costar cambiar una prueba.
	var precios = {
		"WoodCutter": { "wood": 4 },
		"WoodProcessing": { "wood": 8 },
		"Reforester": { "wood": 6 },
		"MetaFactory": { "plank": 6 },
		"WorkerCamp": { "plank": 4 },
		"Storage": { "wood": 10 },
	};
	# Se compara material a material y con int(): JSON.parse_string() devuelve todo número como
	# float, así que `{ "wood": 4.0 } == { "wood": 4 }` es false y compararlo de golpe mediría
	# el parser en vez del precio.
	var tabla_ok = true;
	var leidos = {};
	for nombre in precios:
		var declarado = fd["Factories"].get(nombre, {}).get("cost", {});
		leidos[nombre] = declarado;
		if declarado.size() != precios[nombre].size():
			tabla_ok = false;
			continue;
		for material in precios[nombre]:
			if int(declarado.get(material, -1)) != int(precios[nombre][material]):
				tabla_ok = false;
	_check("las seis factorías del JSON declaran su `cost` con el precio actual del JSON",
		tabla_ok, str(leidos));
	var cinta = fd.get("Belts", {}).get("cost_per_cell", {});
	_check("y la cinta lleva su precio por casilla en su propio bloque, fuera de `Factories`",
		cinta.size() == 1 and int(cinta.get("wood", -1)) == 1, str(fd.get("Belts", {})));

	var main = _new_main_de_prueba(fd);
	var tile_map = main.get_node("TileMap");
	var jugador = main.get_node("Player");
	var arr = [];
	var placer = load("res://entities/factory/factoryPlacer.gd").new();
	placer.initialize(load("res://entities/factory/factory.tscn"), fd, arr);

	# (2) La bolsa a 0: no se puede colocar nada de lo que cuesta, que es la mitad del
	# «hecho cuando» del hito.
	var vacia = _new_bag();
	vacia.initialize(fd);
	var nada_asequible = true;
	for nombre in precios:
		if placer.canAfford(nombre, vacia):
			nada_asequible = false;
	_check("con la bolsa a 0 no se puede pagar ninguna de las seis", nada_asequible);

	# (3) La bolsa justa y la bolsa que se queda a uno. El corte es `>=`, no `>`: pagar hasta
	# el último tronco es legítimo.
	var justa = _new_bag();
	justa.initialize(fd);
	justa.addToBag("wood", 4);
	_check("con 4 de madera exactas se puede pagar un WoodCutter de coste 4",
		placer.canAfford("WoodCutter", justa));
	_check("pero no una WoodProcessing de coste 8",
		not placer.canAfford("WoodProcessing", justa));
	var corta = _new_bag();
	corta.initialize(fd);
	corta.addToBag("wood", 3);
	_check("con 3 de madera el WoodCutter ya no se puede pagar",
		not placer.canAfford("WoodCutter", corta));
	# El coste es un diccionario `material -> cantidad`, así que tener madera de sobra no paga
	# lo que se cobra en tablones.
	var maderera = _new_bag();
	maderera.initialize(fd);
	maderera.addToBag("wood", 100);
	_check("100 de madera no pagan una MetaFactory, que se cobra en tablones",
		not placer.canAfford("MetaFactory", maderera));

	# (4) 🔴 El caso que evita colgar la run: todo lo que hay está reservado para el checkpoint
	# en curso. canAfford() mira getAvailable() y NO getQuantity(), igual que las factorías al
	# consumir; si mirara el total, construir se comería el peaje y el checkpoint sería
	# imposible de cerrar para siempre.
	var reservada = _new_bag();
	reservada.initialize(fd);
	reservada.addToBag("wood", 20);
	reservada.setReserved({ "wood": 20 });
	_check("con los 20 de madera reservados por el checkpoint no se puede construir nada",
		not placer.canAfford("WoodCutter", reservada)
		and reservada.getQuantity("wood") == 20 and reservada.getAvailable("wood") == 0,
		"total %d, disponible %d" % [reservada.getQuantity("wood"), reservada.getAvailable("wood")]);

	# (5) payCost() descuenta del excedente y deja la reserva intacta: 25 en la bolsa con 18
	# apartados son 7 para gastar, así que el WoodCutter (4) entra y la WoodProcessing (8) no,
	# aunque el total de la bolsa la pagaría tres veces.
	var mixta = _new_bag();
	mixta.initialize(fd);
	mixta.addToBag("wood", 25);
	mixta.setReserved({ "wood": 18 });
	_check("con 7 disponibles de 25 se paga el WoodCutter pero no la WoodProcessing",
		placer.canAfford("WoodCutter", mixta) and not placer.canAfford("WoodProcessing", mixta));
	placer.payCost("WoodCutter", mixta);
	_check("y al cobrarlo la bolsa baja 4: 21 en total, 3 disponibles, la reserva sin tocar",
		mixta.getQuantity("wood") == 21 and mixta.getAvailable("wood") == 3
		and mixta.getReserved("wood") == 18,
		"total %d, disponible %d" % [mixta.getQuantity("wood"), mixta.getAvailable("wood")]);

	# (6) `cost` es OPCIONAL y su ausencia significa GRATIS — el mismo contrato que `materials`.
	# Se prueba sobre una copia PROFUNDA del JSON: una superficial compartiría el dict
	# `Factories` con las pruebas que vienen detrás y les quitaría el precio.
	var fd_gratis = fd.duplicate(true);
	fd_gratis["Factories"]["WoodCutter"].erase("cost");
	var arr_gratis = [];
	var placer_gratis = load("res://entities/factory/factoryPlacer.gd").new();
	placer_gratis.initialize(load("res://entities/factory/factory.tscn"), fd_gratis, arr_gratis);
	var sin_blanca = _new_bag();
	sin_blanca.initialize(fd_gratis);
	_check("una entrada sin `cost` es gratis: se paga con la bolsa a 0",
		placer_gratis.getCost("WoodCutter").is_empty()
		and placer_gratis.canAfford("WoodCutter", sin_blanca));
	var gratis = placer_gratis.build("WoodCutter", Vector2i(70, 70), jugador, sin_blanca, tile_map, true);
	root.add_child(gratis);
	_check("y construirla cobrando no saca nada de la bolsa ni devuelve null",
		gratis != null and sin_blanca.getQuantity("wood") == 0);

	# (7) El cobro vive dentro de build(), pero solo lo pide quien compra. Colocar sin cobrar
	# —el almacén que trae el mapa (mapLoader.place_storage()), la suite— no mueve
	# la bolsa; ése es el default de `charge_cost`.
	var bolsa = _new_bag();
	bolsa.initialize(fd);
	bolsa.addToBag("wood", 20);
	var regalada = placer.build("Storage", Vector2i(72, 70), jugador, bolsa, tile_map);
	arr.append(regalada);
	root.add_child(regalada);
	_check("build() sin cobrar coloca un Storage de coste 10 y deja la bolsa en 20",
		regalada != null and bolsa.getQuantity("wood") == 20, str(bolsa.getQuantity("wood")));
	var pagada = placer.build("WoodCutter", Vector2i(74, 70), jugador, bolsa, tile_map, true);
	arr.append(pagada);
	root.add_child(pagada);
	_check("y cobrando, el mismo build() deja los 20 de madera en 16",
		pagada != null and bolsa.getQuantity("wood") == 16, str(bolsa.getQuantity("wood")));
	# Sin dinero build() devuelve null en vez de una factoría a medio pagar, y no cobra nada a
	# cuenta: el rechazo es entero, como el del arrastre.
	var tiesa = _new_bag();
	tiesa.initialize(fd);
	tiesa.addToBag("wood", 3);
	var fallida = placer.build("WoodCutter", Vector2i(76, 70), jugador, tiesa, tile_map, true);
	_check("con 3 de madera build() no construye y no cobra a cuenta",
		fallida == null and tiesa.getQuantity("wood") == 3, str(tiesa.getQuantity("wood")));

	_limpiar([gratis, regalada, pagada, placer, placer_gratis, vacia, justa, corta, maderera,
		reservada, mixta, sin_blanca, bolsa, tiesa, main]);

	# (8) El camino del jugador, entero: Main._on_factory_chosen() revalida el dinero como
	# revalida la colocación, y rechaza sin colocar nada. Es lo que el hito pide ver.
	var main2 = _new_main_en_arbol(fd);
	var tm2 = main2.get_node("TileMap");
	for y in range(4):
		for x in range(4):
			tm2.set_cell(0, Vector2i(x, y), 1, Vector2i(0, 0));
	main2.placer = load("res://entities/factory/factoryPlacer.gd").new();
	main2.placer.initialize(load("res://entities/factory/factory.tscn"), fd, main2.factoryArray);
	var bolsa2 = main2.get_node("Player/Bag");
	main2._on_factory_chosen("WoodCutter", Vector2i(1, 1));
	_check("con la bolsa a 0 el jugador no coloca nada: el radial elige y Main rechaza",
		main2.factoryArray.is_empty(), "colocadas %d" % main2.factoryArray.size());
	bolsa2.addToBag("wood", 20);
	main2._on_factory_chosen("WoodCutter", Vector2i(1, 1));
	_check("con 20 de madera coloca el WoodCutter y la bolsa queda en 16",
		main2.factoryArray.size() == 1 and bolsa2.getQuantity("wood") == 16,
		"colocadas %d, madera %d" % [main2.factoryArray.size(), bolsa2.getQuantity("wood")]);
	# Y lo reservado tampoco se puede gastar por este camino: la segunda no se coloca aunque
	# la bolsa marque 16, porque el checkpoint en curso los aparta enteros.
	bolsa2.setReserved({ "wood": 16 });
	main2._on_factory_chosen("WoodCutter", Vector2i(2, 2));
	_check("y con esos 16 reservados por el checkpoint la siguiente ya no se coloca",
		main2.factoryArray.size() == 1 and bolsa2.getQuantity("wood") == 16,
		"colocadas %d, madera %d" % [main2.factoryArray.size(), bolsa2.getQuantity("wood")]);

	_limpiar([main2.placer, main2]);

# ---------- Costes M2: el stock de salida de los paquetes ----------

# El paquete decide con qué arrancas. Se prueba en los tres niveles que tiene: el JSON (los
# números, PROVISIONALES y sin validar), mapLoader.apply_package() (quien los reparte) y
# la run de verdad (_start_game(), que es el único sitio que la llama). El caso que manda es
# el último: apply_package() SUMA, así que «una sola vez» no es una propiedad de la función
# sino del arranque, y es ahí donde hay que afirmarla.
func _test_costes_m2(fd):
	print("Costes M2 — el stock de salida de cada paquete");

	# (1) Los tres stocks, con los valores actuales del JSON. Van en el JSON y no en el
	# código, como las factorías y los boosts del paquete, así que esta es la regresión de la
	# tabla: son +20 sobre los que el plan propuso a ojo porque el checkpoint 1 se cobra sus 15
	# de madera en el primer frame y el 2 aparta 5 más — mover uno cambia la salida de la run
	# entera y tiene que costar cambiar una prueba.
	# Los 15 de `stone` de `standard` son del M0 del Plan «Variedad de Factorías» (2026-09-20):
	# desde que la `Quarry` se paga ENTERA en piedra (10), sin stock de salida la segunda cadena
	# no se puede abrir, y son 10 de la cantera + 5 de margen. Los otros dos paquetes NO lo
	# llevan a propósito: qué paquete trae la cantera lo deciden M1 y M5. Valores provisionales:
	# salieron de mediciones defectuosas, ya retiradas; aquí se congela la tabla, no se valida.
	var stocks = {
		"standard": { "wood": 40, "plank": 4, "stone": 15 },
		"lumberjack": { "wood": 50 },
		"ecologist": { "wood": 36, "plank": 8 },
	};
	# Material a material y con int(), por lo mismo que los precios de M1: JSON.parse_string()
	# devuelve todo número como float y comparar los diccionarios de golpe mediría el parser.
	var tabla_ok = true;
	var leidos = {};
	for paquete in stocks:
		var declarado = fd["StartingPackages"].get(paquete, {}).get("starting_stock", {});
		leidos[paquete] = declarado;
		if declarado.size() != stocks[paquete].size():
			tabla_ok = false;
			continue;
		for material in stocks[paquete]:
			if int(declarado.get(material, -1)) != int(stocks[paquete][material]):
				tabla_ok = false;
	_check("los tres paquetes declaran su `starting_stock` con el número actual del JSON",
		tabla_ok, str(leidos));

	# (2) apply_package() reparte el del paquete que se le pide y solo ése: cada uno arranca
	# con bolsa no vacía y con LA SUYA, que es la mitad del «hecho cuando» del hito.
	var loader = load("res://managers/mapLoader.gd").new();
	var cada_uno_el_suyo = true;
	var repartido = {};
	var escenarios = [];
	for paquete in stocks:
		var main = _new_main_de_prueba(fd);
		escenarios.append(main);
		var bolsa = main.get_node("Player").get_node("Bag");
		bolsa.initialize(fd);
		loader.apply_package(paquete, fd, main.get_node("Player"), bolsa);
		repartido[paquete] = { "wood": bolsa.getQuantity("wood"), "plank": bolsa.getQuantity("plank") };
		for material in ["wood", "plank"]:
			if int(bolsa.getQuantity(material)) != int(stocks[paquete].get(material, 0)):
				cada_uno_el_suyo = false;
	_check("y apply_package() le da a cada uno el suyo, sin inventar materiales de más",
		cada_uno_el_suyo, str(repartido));

	# (3) 🔴 apply_package() SUMA, no asigna: una segunda llamada DUPLICA el stock. Se afirma a
	# propósito —es el detalle que el plan marca como el que cuesta una tarde— para que el día
	# que alguien la haga idempotente, o le cuele una segunda llamada al flujo de arranque,
	# esta prueba salte y la decisión se tome a la vista.
	var doble = _new_main_de_prueba(fd);
	var bolsa_doble = doble.get_node("Player").get_node("Bag");
	bolsa_doble.initialize(fd);
	loader.apply_package("standard", fd, doble.get_node("Player"), bolsa_doble);
	loader.apply_package("standard", fd, doble.get_node("Player"), bolsa_doble);
	_check("llamarla dos veces duplica el stock: no es idempotente y el arranque no la repite",
		bolsa_doble.getQuantity("wood") == 80 and bolsa_doble.getQuantity("plank") == 8,
		"madera %d, tablones %d" % [bolsa_doble.getQuantity("wood"), bolsa_doble.getQuantity("plank")]);

	# (4) `starting_stock` es OPCIONAL y su ausencia significa bolsa vacía — el mismo contrato
	# que `cost` y que `materials`. Copia PROFUNDA del JSON: una superficial le quitaría el
	# stock a las pruebas que vienen detrás.
	var fd_sin = fd.duplicate(true);
	fd_sin["StartingPackages"]["standard"].erase("starting_stock");
	var pelado = _new_main_de_prueba(fd_sin);
	var bolsa_pelada = pelado.get_node("Player").get_node("Bag");
	bolsa_pelada.initialize(fd_sin);
	loader.apply_package("standard", fd_sin, pelado.get_node("Player"), bolsa_pelada);
	_check("un paquete sin `starting_stock` arranca con la bolsa a 0 y no revienta",
		bolsa_pelada.getQuantity("wood") == 0 and bolsa_pelada.getQuantity("plank") == 0
		and pelado.get_node("Player").availableFactories.size() == 5);

	escenarios.append_array([doble, pelado, loader]);
	_limpiar(escenarios);

	# (5) La run de verdad, que es donde «una sola vez» se puede afirmar: _start_game() llama a
	# apply_package() una vez y nadie más la llama, así que la bolsa del primer frame es
	# EXACTAMENTE el stock del paquete. Y con esa bolsa la run es jugable desde el segundo 0:
	# tras el primer update() —que cobra los 15 del checkpoint 1 y aparta los 5 del 2— todavía
	# queda disponible para comprar, que es la razón entera de que los tres números sean +20.
	for paquete in stocks:
		var main = _main_para_run();
		main._start_game(paquete);
		var bolsa = main.get_node("Player").get_node("Bag");
		var recien_nacida = (int(bolsa.getQuantity("wood")) == int(stocks[paquete].get("wood", 0))
			and int(bolsa.getQuantity("plank")) == int(stocks[paquete].get("plank", 0)));
		_check("la run de '%s' nace con su stock y sin duplicarlo: el arranque aplica el paquete una sola vez" % paquete,
			recien_nacida,
			"madera %d, tablones %d" % [bolsa.getQuantity("wood"), bolsa.getQuantity("plank")]);
		# El primer update() del gameManager, el que se lleva el peaje de salida. Se desconecta
		# antes checkpoint_reached: cerrar el checkpoint 1 abriría la pantalla de mejora y, con
		# ella, un get_tree().paused = true que se quedaría puesto para el resto de la suite.
		# Lo que este bloque mide es la bolsa, no la pantalla.
		main.gameManager.checkpoint_reached.disconnect(main._on_checkpoint_reached);
		main.gameManager.update(bolsa, main.pollutionManager);
		var esperado = int(stocks[paquete].get("wood", 0)) - 15 - 5;
		_check("y con '%s' quedan %d de madera disponibles tras el checkpoint 1: se puede construir sin nada colocado" % [paquete, esperado],
			int(bolsa.getAvailable("wood")) == esperado
			and main.placer.canAfford("WoodCutter", bolsa),
			"disponible %d de %d" % [bolsa.getAvailable("wood"), bolsa.getQuantity("wood")]);
		# placer y mapLoader son nodos que Main nunca añade al árbol: se sueltan a mano, igual
		# que en Derrota M4.
		_limpiar([main.placer, main.mapLoader, main]);

# ---------- Costes M3: el precio de la cinta ----------

# El cobro por casilla del arrastre. Lo que manda aquí es TODO O NADA: el precio del tramo se
# calcula antes de confirmar y, si no alcanza, no se tiende ni una casilla, no se cobra nada y
# la red queda exactamente como estaba — media cinta pagada no transporta nada y el jugador
# habría tirado la madera. Los dos casos del «hecho cuando» del hito (6 casillas con 5 de
# madera y con 6) son las pruebas (2) y (4).
func _test_costes_m3(file_data):
	print("Costes M3 — el precio de la cinta y el arrastre todo o nada");
	var script_red = load("res://managers/beltNetwork.gd");
	var main = _new_main_en_arbol(file_data);
	var tm = main.get_node("TileMap");
	# Suelo de 12x12: caben los cuatro escenarios sin que se estorben entre sí.
	for y in range(12):
		for x in range(12):
			tm.set_cell(0, Vector2i(x, y), 1, Vector2i(0, 0));
	var red = script_red.new();
	red.name = "BeltNetwork";
	main.add_child(red);
	# El tercer argumento es de M3: de él sale el precio por casilla. Sin él la cinta es
	# gratis, que es como la tiende el resto de la suite — se prueba en (8).
	red.initialize(tm, main.factoryArray, file_data);
	tm.setBeltNetwork(red);
	main.beltNetwork = red;
	var bolsa = main.get_node("Player/Bag");
	var avisos = [0];
	red.belt_network_changed.connect(func(): avisos[0] += 1);

	# (1) El precio sale del JSON y no del código, igual que el `cost` de las factorías. El
	# total es una multiplicación por casillas, no un número suelto: un arrastre largo cuesta
	# proporcionalmente más, que es lo que hace cara la ruta mal pensada.
	var por_casilla = red.get_cost_per_cell();
	_check("la red lee `Belts.cost_per_cell` del JSON de la run",
		por_casilla.size() == 1 and int(por_casilla.get("wood", -1)) == 1, str(por_casilla));
	_check("y el precio del arrastre es ese por casilla, multiplicado por las casillas",
		int(red.belt_cost_for(6).get("wood", -1)) == 6
		and int(red.belt_cost_for(1).get("wood", -1)) == 1
		and red.belt_cost_for(0).is_empty(), str(red.belt_cost_for(6)));

	# (2) 🔴 EL «HECHO CUANDO», primera mitad: seis casillas con cinco de madera no tienden
	# NINGUNA. Y no se cobra nada, no se emite la señal y la red sigue vacía: el rechazo es
	# entero, no un tendido a medias de cinco casillas.
	bolsa.addToBag("wood", 5);
	var pobre = red.place_drag(Vector2i(1, 1), Vector2i(4, 3), main.factoryArray, bolsa, true);
	_check("tender 6 casillas con 5 de madera no tiende ninguna",
		pobre.is_empty() and red.belt_count() == 0,
		"devolvió %s y la red tiene %d" % [str(pobre), red.belt_count()]);
	_check("y no cobra nada ni avisa: la bolsa sigue en 5 y no ha pasado nada",
		bolsa.getQuantity("wood") == 5 and avisos[0] == 0,
		"madera %d, %d avisos" % [bolsa.getQuantity("wood"), avisos[0]]);

	# (3) 🔴 can_place_drag() y place_drag() tienen que decir LO MISMO, o preguntar «¿cabe?»
	# devolvería un sí que el tendido no cumple. El dinero vive en la validación, que es la
	# que place_drag() llama de primero.
	_check("can_place_drag() lo rechaza igual cuando se le pide que cobre",
		red.can_place_drag(Vector2i(1, 1), Vector2i(4, 3), main.factoryArray, bolsa, true) == false);
	_check("y sin cobrar dice que sí: el arrastre cabe, lo que falta es dinero",
		red.can_place_drag(Vector2i(1, 1), Vector2i(4, 3), main.factoryArray) == true);

	# (4) 🔴 EL «HECHO CUANDO», segunda mitad: con seis, se tienden las seis y la bolsa queda
	# a 0. Con el dinero JUSTO, que es el caso que separa «alcanza» de «no alcanza».
	bolsa.addToBag("wood", 1);
	var justo = red.place_drag(Vector2i(1, 1), Vector2i(4, 3), main.factoryArray, bolsa, true);
	_check("con 6 de madera se tienden las seis casillas",
		justo.size() == 6 and red.belt_count() == 6, "tendió %s" % str(justo));
	_check("y la bolsa queda a 0: se ha cobrado una por casilla, ni más ni menos",
		bolsa.getQuantity("wood") == 0 and avisos[0] == 1,
		"madera %d, %d avisos" % [bolsa.getQuantity("wood"), avisos[0]]);

	# (5) 🔴 getAvailable() y NUNCA getQuantity(): lo que el almacén aparta para el checkpoint
	# en curso no se puede gastar en cinta. Es la misma regla que M1 le puso a las factorías, y
	# la que impide colgar la run gastándose el peaje en logística.
	bolsa.addToBag("wood", 6);
	bolsa.setReserved({ "wood": 2 });
	var reservada = red.place_drag(Vector2i(1, 5), Vector2i(4, 7), main.factoryArray, bolsa, true);
	_check("con 6 de madera pero 2 reservadas para el checkpoint, el arrastre de 6 se rechaza",
		reservada.is_empty() and bolsa.getQuantity("wood") == 6,
		"devolvió %s con %d de madera (%d disponible)" % [
			str(reservada), bolsa.getQuantity("wood"), bolsa.getAvailable("wood")]);
	bolsa.setReserved({});
	_check("y levantada la reserva, ese mismo arrastre se tiende y se cobra",
		red.place_drag(Vector2i(1, 5), Vector2i(4, 7), main.factoryArray, bolsa, true).size() == 6
		and bolsa.getQuantity("wood") == 0, "madera %d" % bolsa.getQuantity("wood"));

	# (6) 🔴 LO QUE SE COBRA NO ES EL LARGO DEL CAMINO. `trace_path()` incluye origen y destino
	# y `_belt_range()` recorta los extremos ocupados por una factoría (M7 del plan de cintas:
	# se arrastra de la cortadora a la serrería y la cinta se tiende ENTRE las dos), así que de
	# un camino de 6 se pagan 4. Cobrar el camino entero le pasaría al jugador dos casillas
	# fantasma en cada tendido entre factorías, que es el gesto que el diseño quiere que haga.
	var cortadora = _factoria_en_main(main, "WoodCutter", Vector2i(1, 9), 1, null, "wood");
	var serreria = _factoria_en_main(main, "WoodProcessing", Vector2i(6, 9), 1, ["wood"], "plank");
	var camino = red.trace_path(cortadora.cell_position, serreria.cell_position);
	bolsa.addToBag("wood", 3);
	var corto = red.place_drag(cortadora.cell_position, serreria.cell_position,
		main.factoryArray, bolsa, true);
	_check("un camino de 6 entre dos factorías cuesta 4, no 6: con 3 de madera no se tiende",
		camino.size() == 6 and corto.is_empty() and bolsa.getQuantity("wood") == 3,
		"camino de %d, devolvió %s" % [camino.size(), str(corto)]);
	bolsa.addToBag("wood", 1);
	var entre = red.place_drag(cortadora.cell_position, serreria.cell_position,
		main.factoryArray, bolsa, true);
	_check("y con 4 se tienden las 4 casillas de en medio y la bolsa queda a 0",
		entre.size() == 4 and bolsa.getQuantity("wood") == 0
		and not red.has_belt(cortadora.cell_position) and not red.has_belt(serreria.cell_position),
		"tendió %s con %d de madera" % [str(entre), bolsa.getQuantity("wood")]);

	# (7) El rechazo por dinero no mueve NADA más: ni un búfer, ni la señal. place_drag() vacía
	# los búferes de salida al tender (Cintas M4) y avisa por belt_network_changed, y las dos
	# cosas tienen que quedarse sin hacer si el arrastre no se paga.
	var avisos_7 = avisos[0];
	serreria.output_buffer = 3;
	var sin_fondos = red.place_drag(Vector2i(8, 1), Vector2i(11, 1), main.factoryArray, bolsa, true);
	_check("con la bolsa a 0 el arrastre no tiende, no avisa y no vacía los búferes de salida",
		sin_fondos.is_empty() and avisos[0] == avisos_7 and serreria.output_buffer == 3,
		"devolvió %s, %d avisos, búfer %d" % [
			str(sin_fondos), avisos[0] - avisos_7, serreria.output_buffer]);

	_limpiar([main]);

	# (8) La exención, que es el mismo opt-in de `charge_cost` que M1 le puso a build(): sin
	# JSON inyectado la cinta es GRATIS, y así la tiende la suite, que monta redes enteras
	# con bolsas que nunca pensaron en pagar. Es lo que evita tener dos
	# mecanismos distintos para lo mismo dentro del mismo plan.
	var libre = _new_main_en_arbol(file_data);
	var tm_libre = libre.get_node("TileMap");
	for y in range(4):
		for x in range(8):
			tm_libre.set_cell(0, Vector2i(x, y), 1, Vector2i(0, 0));
	var red_libre = script_red.new();
	red_libre.name = "BeltNetwork";
	libre.add_child(red_libre);
	red_libre.initialize(tm_libre, libre.factoryArray);
	tm_libre.setBeltNetwork(red_libre);
	var bolsa_libre = libre.get_node("Player/Bag");
	_check("una red sin JSON no conoce precio y la cinta le sale gratis",
		red_libre.get_cost_per_cell().is_empty() and red_libre.belt_cost_for(4).is_empty());
	_check("y con la bolsa a 0 tiende igual, aunque se le pida que cobre",
		red_libre.place_drag(Vector2i(1, 1), Vector2i(4, 1), libre.factoryArray, bolsa_libre, true).size() == 4
		and bolsa_libre.getQuantity("wood") == 0);
	# Y el default, que es por donde pasan los cientos de arrastres de la suite: sin bolsa y
	# sin `charge_cost`, place_drag() se comporta exactamente como antes de M3.
	_check("sin bolsa y sin charge_cost, el arrastre se comporta igual que antes de M3",
		red_libre.place_drag(Vector2i(1, 3), Vector2i(4, 3), libre.factoryArray).size() == 4);

	_limpiar([libre]);

# ---------- Costes M4: la devolución al demoler ----------

# Demoler devuelve la MITAD de lo pagado, redondeando abajo, además de los workers que ya
# volvían. Las dos cosas que este bloque vigila valen más que la aritmética:
#   - lo que NO se pagó no se devuelve (el almacén con el que arranca el mapa, la suite: si
#     devolvieran precio de catálogo, demoler imprimiría material), y
#   - por muchas vueltas que se le dé, la bolsa BAJA: colocar y demoler nunca es un ingreso,
#     que es la prueba jugada nº 3 del plan hecha suite.
func _test_costes_m4(fd):
	print("Costes M4 — la devolución al demoler");
	var main = _new_main_en_arbol(fd);
	var tm = main.get_node("TileMap");
	# Suelo de 12x12: los cuatro escenarios del bloque caben sin pisarse, y el bucle de diez
	# vuelve siempre a la misma celda a propósito (es el gesto que se quiere medir).
	for y in range(12):
		for x in range(12):
			tm.set_cell(0, Vector2i(x, y), 1, Vector2i(0, 0));
	main.placer = load("res://entities/factory/factoryPlacer.gd").new();
	main.placer.initialize(load("res://entities/factory/factory.tscn"), fd, main.factoryArray);
	var bolsa = main.get_node("Player/Bag");

	# (1) 🔴 EL «HECHO CUANDO» del hito, por el camino del jugador entero: colocar y demoler un
	# WoodCutter de coste 4 deja la bolsa DOS por debajo de donde estaba. Ni igual (sondeo
	# gratuito del mapa) ni cuatro por debajo (el reset rápido que el GDD promete, castigado).
	bolsa.addToBag("wood", 20);
	main._on_factory_chosen("WoodCutter", Vector2i(1, 1));
	_check("colocar el WoodCutter de coste 4 deja los 20 de madera en 16",
		main.factoryArray.size() == 1 and bolsa.getQuantity("wood") == 16,
		"colocadas %d, madera %d" % [main.factoryArray.size(), bolsa.getQuantity("wood")]);
	main._demolish_at_cell(Vector2i(1, 1));
	_check("y demolerlo devuelve 2: la bolsa queda en 18, dos por debajo de los 20 de salida",
		main.factoryArray.is_empty() and bolsa.getQuantity("wood") == 18,
		"colocadas %d, madera %d" % [main.factoryArray.size(), bolsa.getQuantity("wood")]);

	# (2) 🔴 Los workers siguen volviendo ENTEROS, y la devolución de material se SUMA a eso.
	# La invariante de los workers (Bag.workers_assigned y factoryData.workers_assigned se
	# mueven a la vez) es anterior a este hito y romperla duplica o pierde workers para el
	# resto de la run: se prueba aquí con la WoodProcessing, que es la que pide uno.
	var libres_antes = bolsa.getFreeWorkers();
	bolsa.addToBag("wood", 2);   # 20 en total: la WoodProcessing cuesta 8
	main._on_factory_chosen("WoodProcessing", Vector2i(3, 1));
	var wp = main.factoryArray[0] if main.factoryArray.size() == 1 else null;
	_check("colocar la WoodProcessing de 8 cobra 8 y le asigna su worker",
		wp != null and bolsa.getQuantity("wood") == 12 and wp.workers_assigned == 1
		and bolsa.getFreeWorkers() == libres_antes - 1,
		"madera %d, libres %d" % [bolsa.getQuantity("wood"), bolsa.getFreeWorkers()]);
	main._demolish_at_cell(Vector2i(3, 1));
	_check("y demolerla devuelve 4 de madera Y el worker: los dos, no uno de los dos",
		bolsa.getQuantity("wood") == 16 and bolsa.getFreeWorkers() == libres_antes,
		"madera %d, libres %d de %d" % [
			bolsa.getQuantity("wood"), bolsa.getFreeWorkers(), libres_antes]);

	# (3) La tabla entera, para que mover un precio obligue a mirar también lo que devuelve.
	# Se mide sobre el recibo (`cost_paid`) y no construyendo seis veces: lo que se prueba es
	# la mitad redondeada, y construirlas costaría un mapa y una bolsa por cada una.
	var mitades = {
		"WoodCutter": { "wood": 2 }, "WoodProcessing": { "wood": 4 },
		"Reforester": { "wood": 3 }, "MetaFactory": { "plank": 3 },
		"WorkerCamp": { "plank": 2 }, "Storage": { "wood": 5 },
	};
	var tabla_ok = true;
	var devueltos = {};
	var recibo = _factoria_en_main(main, "WoodCutter", Vector2i(9, 9), 4, null, "wood");
	for nombre in mitades:
		recibo.cost_paid = fd["Factories"][nombre]["cost"];
		var r = main.placer.getRefund(recibo);
		devueltos[nombre] = r;
		if r.size() != mitades[nombre].size():
			tabla_ok = false;
			continue;
		for material in mitades[nombre]:
			if int(r.get(material, -1)) != int(mitades[nombre][material]):
				tabla_ok = false;
	recibo.cost_paid = {};
	_check("las seis factorías devuelven la mitad de su precio, material a material",
		tabla_ok, str(devueltos));

	# (4) 🔴 LO QUE NO SE PAGÓ NO SE DEVUELVE. build() solo cobra con `charge_cost`, así que el
	# almacén con el que arranca el mapa (mapLoader.place_storage()) se coloca gratis: si
	# demolerlo soltara los 5 de la mitad de su precio, «colocar y demoler» dejaría de costar
	# dinero para pasar a IMPRIMIRLO, y con un Storage de 10 la run se financiaría sola.
	var antes_regalo = bolsa.getQuantity("wood");
	var regalado = main.placer.build(
		"Storage", Vector2i(5, 1), main.get_node("Player"), bolsa, tm);
	main.add_child(regalado);
	main.placer.register_and_evaluate(regalado, Vector2i(5, 1));
	_check("el almacén regalado se coloca sin cobrar y su recibo queda vacío",
		regalado != null and regalado.cost_paid.is_empty()
		and bolsa.getQuantity("wood") == antes_regalo, str(regalado.cost_paid));
	main._demolish_at_cell(Vector2i(5, 1));
	_check("y demolerlo no devuelve ni un tronco: la bolsa no se mueve",
		bolsa.getQuantity("wood") == antes_regalo,
		"madera %d, esperada %d" % [bolsa.getQuantity("wood"), antes_regalo]);

	# (5) Lo mismo para la factoría que una prueba monta a mano, que es como está
	# construida media suite: sin pasar por build() no hay recibo, y sin recibo no hay
	# devolución. Es el mismo opt-in de `charge_cost` visto desde el otro lado.
	var a_mano = _factoria_en_main(main, "Reforester", Vector2i(7, 1), 5, null, null, "restoration");
	var antes_mano = bolsa.getQuantity("wood");
	main._demolish_at_cell(Vector2i(7, 1));
	_check("demoler una factoría montada a mano por la suite tampoco devuelve nada",
		bolsa.getQuantity("wood") == antes_mano and a_mano != null,
		"madera %d, esperada %d" % [bolsa.getQuantity("wood"), antes_mano]);

	# (6) La reserva del checkpoint no se toca al devolver: lo devuelto entra al TOTAL y por
	# tanto es excedente desde el primer frame, que es lo que hace de demoler una salida real
	# cuando la bolsa se atasca. Lo que el peaje aparta sigue apartado.
	bolsa.setReserved({ "wood": 10 });
	var total_antes = bolsa.getQuantity("wood");
	main._on_factory_chosen("WoodCutter", Vector2i(2, 4));
	main._demolish_at_cell(Vector2i(2, 4));
	_check("con 10 reservados, colocar y demoler baja 2 del total y deja la reserva intacta",
		bolsa.getQuantity("wood") == total_antes - 2 and bolsa.getReserved("wood") == 10
		and bolsa.getAvailable("wood") == total_antes - 12,
		"total %d, reservado %d, disponible %d" % [
			bolsa.getQuantity("wood"), bolsa.getReserved("wood"), bolsa.getAvailable("wood")]);
	bolsa.setReserved({});

	# (7) Demoler dos veces la misma celda no cobra la devolución dos veces: la primera saca la
	# factoría de `factoryArray` y la segunda no encuentra nada. Parece obvio y es justo el
	# gesto que un doble click hace solo.
	main._on_factory_chosen("WoodCutter", Vector2i(4, 4));
	main._demolish_at_cell(Vector2i(4, 4));
	var tras_una = bolsa.getQuantity("wood");
	main._demolish_at_cell(Vector2i(4, 4));
	_check("demoler la misma celda dos veces devuelve una sola vez",
		bolsa.getQuantity("wood") == tras_una, "madera %d, esperada %d" % [
			bolsa.getQuantity("wood"), tras_una]);

	# (8) 🔴 LA MONOTONÍA, que es la prueba jugada nº 3 del plan: diez ciclos de colocar y
	# demoler sobre la misma casilla, y la bolsa BAJA en cada uno. No basta con que el saldo
	# final sea menor: se comprueba paso a paso, porque un ciclo que subiera y otro que bajara
	# el doble darían el mismo final y serían un exploit repetible.
	# Con madera de sobra para los diez, a propósito: si la bolsa se quedara corta a mitad, los
	# ciclos que faltan no colocarían nada y la serie saldría plana — que también es «no sube»,
	# pero mediría el rechazo por dinero y no la devolución. Por eso se cuenta además que las
	# diez factorías se colocaron de verdad.
	bolsa.addToBag("wood", 40);
	var serie = [bolsa.getQuantity("wood")];
	var colocadas = 0;
	for i in range(10):
		main._on_factory_chosen("WoodCutter", Vector2i(6, 6));
		if main._get_factory_at_cell(Vector2i(6, 6)) != null:
			colocadas += 1;
		main._demolish_at_cell(Vector2i(6, 6));
		serie.append(bolsa.getQuantity("wood"));
	var baja_siempre = true;
	var neto_dos = true;
	for i in range(1, serie.size()):
		if serie[i] >= serie[i - 1]:
			baja_siempre = false;
		if serie[i] != serie[i - 1] - 2:
			neto_dos = false;
	_check("diez veces colocar y demoler: la bolsa baja en los diez ciclos, nunca sube",
		baja_siempre and colocadas == 10 and serie.size() == 11,
		"%d colocadas, serie %s" % [colocadas, str(serie)]);
	_check("y cada ciclo cuesta exactamente 2: pagar 4 y recuperar 2, sin residuos",
		neto_dos and serie[10] == serie[0] - 20, str(serie));

	_limpiar([main.placer, main]);

	# (9) El redondeo HACIA ABAJO, sobre un precio impar. Ninguna de las seis lo tiene hoy, así
	# que se prueba sobre una copia PROFUNDA del JSON —una superficial le cambiaría el precio a
	# las pruebas de detrás—: pagar 5 devuelve 2 y no 3. El medio tronco se queda la casa, que
	# es lo que garantiza que ningún coste, par o impar, salga rentable de demoler.
	var fd_impar = fd.duplicate(true);
	fd_impar["Factories"]["WoodCutter"]["cost"] = { "wood": 5 };
	var main_i = _new_main_en_arbol(fd_impar);
	var tm_i = main_i.get_node("TileMap");
	for y in range(4):
		for x in range(4):
			tm_i.set_cell(0, Vector2i(x, y), 1, Vector2i(0, 0));
	main_i.placer = load("res://entities/factory/factoryPlacer.gd").new();
	main_i.placer.initialize(
		load("res://entities/factory/factory.tscn"), fd_impar, main_i.factoryArray);
	var bolsa_i = main_i.get_node("Player/Bag");
	bolsa_i.addToBag("wood", 10);
	main_i._on_factory_chosen("WoodCutter", Vector2i(1, 1));
	_check("con un coste impar de 5 se cobran los 5 enteros", bolsa_i.getQuantity("wood") == 5,
		"madera %d" % bolsa_i.getQuantity("wood"));
	main_i._demolish_at_cell(Vector2i(1, 1));
	_check("y al demoler se devuelven 2, no 3: floor(5/2), el ciclo cuesta 3",
		bolsa_i.getQuantity("wood") == 7, "madera %d (esperada 7)" % bolsa_i.getQuantity("wood"));

	_limpiar([main_i.placer, main_i]);

	# (10) Y el contrato opcional otra vez: una entrada sin `cost` es gratis, así que colocarla
	# y demolerla no mueve la bolsa en ninguna de las dos direcciones. Sin esto, «gratis»
	# necesitaría un caso aparte en la devolución y tarde o temprano alguien lo olvidaría.
	var fd_gratis = fd.duplicate(true);
	fd_gratis["Factories"]["WoodCutter"].erase("cost");
	var main_g = _new_main_en_arbol(fd_gratis);
	var tm_g = main_g.get_node("TileMap");
	for y in range(4):
		for x in range(4):
			tm_g.set_cell(0, Vector2i(x, y), 1, Vector2i(0, 0));
	main_g.placer = load("res://entities/factory/factoryPlacer.gd").new();
	main_g.placer.initialize(
		load("res://entities/factory/factory.tscn"), fd_gratis, main_g.factoryArray);
	var bolsa_g = main_g.get_node("Player/Bag");
	bolsa_g.addToBag("wood", 7);
	main_g._on_factory_chosen("WoodCutter", Vector2i(1, 1));
	main_g._demolish_at_cell(Vector2i(1, 1));
	_check("lo que se coloca gratis se demuele gratis: la bolsa no se mueve en ninguna dirección",
		bolsa_g.getQuantity("wood") == 7 and main_g.factoryArray.is_empty(),
		"madera %d" % bolsa_g.getQuantity("wood"));

	_limpiar([main_g.placer, main_g]);

# ---------- Costes M5: el precio, visible antes de pagar ----------

# El precio existía desde M1 pero era invisible, y un rechazo por dinero se vivía como un gesto
# roto. Este bloque vigila las tres cosas que lo arreglan:
#   - el radial escribe lo que cuesta cada opción, con el precio que build() va a cobrar de
#     verdad (el del JSON, no una copia);
#   - lo que no se puede pagar se ve apagado Y no se puede elegir —atenuar solo sería una
#     promesa rota—, medido contra `getAvailable()` y nunca contra el total de la bolsa, que es
#     la única forma de que la UI diga lo mismo que el cobro; y
#   - el panel enseña lo que devolvería demoler, con la misma redacción del dinero.
func _test_costes_m5(fd):
	print("Costes M5 — el precio, visible antes de pagar");
	var main = _new_main_en_arbol(fd);
	var tm = main.get_node("TileMap");
	for y in range(8):
		for x in range(8):
			tm.set_cell(0, Vector2i(x, y), 1, Vector2i(0, 0));
	main.placer = load("res://entities/factory/factoryPlacer.gd").new();
	main.placer.initialize(load("res://entities/factory/factory.tscn"), fd, main.factoryArray);
	var bolsa = main.get_node("Player/Bag");
	# Las dos que el paquete estándar desbloquea, que son las del «hecho cuando»: una de 4 y
	# otra de 8, con 5 de madera en la bolsa.
	main.get_node("Player").availableFactories = ["WoodCutter", "WoodProcessing"];

	# (1) 🔴 EL «HECHO CUANDO» del hito, por el camino del jugador: con 5 de madera el radial
	# enseña la WoodProcessing con su precio, apagada, y no la deja elegir.
	bolsa.addToBag("wood", 5);
	main._show_radial_menu(Vector2i(2, 2));
	var radial = main.get_node("RadialMenu");
	var por_nombre = _botones_radial(radial);
	var wp = por_nombre.get("WoodProcessing");
	var wc = por_nombre.get("WoodCutter");
	_check("con 5 de madera el botón de la WoodProcessing canta su precio y lo marca impagable",
		wp != null and _textos_boton(wp) == ["WoodProcessing", "→ plank", "⚙ 1W", "✖ Coste: 8 wood"],
		str(_textos_boton(wp)) if wp != null else "sin botón de WoodProcessing");
	_check("y el WoodCutter, que sí se paga con 5, enseña su precio sin marca",
		wc != null and _textos_boton(wc) == ["WoodCutter", "→ wood", "Coste: 4 wood"],
		str(_textos_boton(wc)) if wc != null else "sin botón de WoodCutter");
	_check("la impagable está DESACTIVADA y la pagable no: atenuar sin bloquear sería una promesa rota",
		wp != null and wc != null and wp.disabled and not wc.disabled,
		"WoodProcessing.disabled=%s, WoodCutter.disabled=%s" % [
			str(wp.disabled) if wp != null else "?", str(wc.disabled) if wc != null else "?"]);

	# Y se ve apagada: el `disabled` del Button NO tiñe las labels hijas —llevan su propio
	# override de color—, así que si el atenuado no se hiciera a mano la opción impagable se
	# vería exactamente igual de disponible que las demás. Se comprueba que baja el ALFA y que
	# el TONO se conserva: el naranja de «contamina» tiene que seguir siendo naranja apagado, o
	# el atenuado habría pisado el código de color que ese botón ya usaba.
	var labels_wp = wp.find_children("", "Label", true, false);
	var labels_wc = wc.find_children("", "Label", true, false);
	# El alfa se compara con margen: un Color guarda sus componentes en 32 bits y el `0.35` de
	# la constante es un float de 64, así que la igualdad exacta falla por el último decimal.
	var atenuadas = labels_wp.size() == 4;
	for i in range(labels_wp.size() - 1):
		if not _near(labels_wp[i].get_theme_color("font_color").a, radial.DIMMED_ALPHA):
			atenuadas = false;
	_check("todas las líneas de la impagable se atenúan bajando el alfa",
		atenuadas, str(labels_wp.map(func(l): return l.get_theme_color("font_color"))));
	_check("y conservando el tono: el naranja de «contamina» sigue siendo naranja",
		labels_wp[0].get_theme_color("font_color")
			== Color(1.0, 0.6, 0.3, radial.DIMMED_ALPHA),
		str(labels_wp[0].get_theme_color("font_color")));
	_check("la línea del precio es la única que NO se apaga: es la razón del apagado, en rojo",
		labels_wp[3].get_theme_color("font_color") == radial.UNAFFORDABLE_PRICE_COLOR,
		str(labels_wp[3].get_theme_color("font_color")));
	var wc_entera = true;
	for l in labels_wc:
		if l.get_theme_color("font_color").a != 1.0:
			wc_entera = false;
	_check("y la opción que sí se paga no se atenúa en ninguna de sus líneas", wc_entera,
		str(labels_wc.map(func(l): return l.get_theme_color("font_color"))));
	_check("el precio que se puede pagar va en el color del dinero, ni naranja ni verde",
		labels_wc[2].get_theme_color("font_color") == radial.PRICE_COLOR,
		str(labels_wc[2].get_theme_color("font_color")));

	# «No deja seleccionarla»: además de `disabled`, la señal del botón impagable ni siquiera se
	# conecta, así que ni forzando la pulsación se elige nada. La pagable sí elige, construye y
	# cobra, que es lo que prueba que el apagado no se ha llevado por delante el menú entero.
	var elegidas = [];
	radial.factory_chosen.connect(func(tipo, celda): elegidas.append([tipo, celda]));
	wp.pressed.emit();
	_check("forzar la pulsación de la impagable no elige nada ni mueve la bolsa",
		elegidas.is_empty() and main.factoryArray.is_empty()
		and bolsa.getQuantity("wood") == 5, str(elegidas));
	wc.pressed.emit();
	_check("y la que sí se paga se elige, se construye y cobra sus 4: la bolsa queda en 1",
		elegidas == [["WoodCutter", Vector2i(2, 2)]] and main.factoryArray.size() == 1
		and bolsa.getQuantity("wood") == 1,
		"elegidas %s, colocadas %d, madera %d" % [
			str(elegidas), main.factoryArray.size(), bolsa.getQuantity("wood")]);

	# (2) 🔴 LA MISMA VERDAD QUE EL COBRO. El radial pinta contra `getAvailable()` —lo que se
	# puede gastar— y no contra `getQuantity()`: con la bolsa llena pero todo apartado para el
	# checkpoint, el botón tiene que decir que NO, que es lo que dirá Main al elegir. Si pintara
	# el total, el jugador vería «puedes» y el juego contestaría «no».
	# El radial anterior se pidió a sí mismo queue_free() al elegir, y queue_free() es diferido:
	# sigue ocupando el nombre «RadialMenu» hasta final de frame, así que se saca del árbol antes
	# de abrir el siguiente o `get_node()` devolvería el viejo.
	var viejo = main.get_node_or_null("RadialMenu");
	if viejo != null:
		main.remove_child(viejo);
	bolsa.addToBag("wood", 19);
	bolsa.setReserved({ "wood": 17 });
	main._show_radial_menu(Vector2i(5, 5));
	var radial_reserva = main.get_node("RadialMenu");
	var reservado = _botones_radial(radial_reserva);
	_check("con 20 en la bolsa pero 17 reservados, las dos salen impagables: manda el excedente",
		reservado["WoodCutter"].disabled and reservado["WoodProcessing"].disabled,
		"total %d, disponible %d" % [bolsa.getQuantity("wood"), bolsa.getAvailable("wood")]);
	bolsa.setReserved({});
	main.remove_child(radial_reserva);
	radial_reserva.queue_free();

	# (3) El panel enseña lo que devolvería demoler, y sale de `getRefund()` —lo PAGADO— y no de
	# una división propia: pagar 8 por la WoodProcessing se anuncia como 4.
	bolsa.addToBag("wood", 10);
	main._on_factory_chosen("WoodProcessing", Vector2i(6, 1));
	var comprada = main._get_factory_at_cell(Vector2i(6, 1));
	main._show_factory_panel(comprada);
	var panel = main.get_node("FactoryPanel");
	_check("el panel de una factoría comprada anuncia la mitad que devolvería al demolerla",
		_textos_panel(panel).has("Demoler devuelve: 4 wood"), str(_textos_panel(panel)));

	# (4) Y lo que nadie compró no anuncia devolución ninguna: el almacén con el que arranca el
	# mapa se coloca gratis, así que su panel no puede ofrecer una devolución que al demoler no
	# va a llegar. Es la misma regla de M4 vista desde la pantalla.
	main.remove_child(panel);
	panel.queue_free();
	var regalada = main.placer.build(
		"Storage", Vector2i(1, 6), main.get_node("Player"), bolsa, tm);
	main.add_child(regalada);
	main.placer.register_and_evaluate(regalada, Vector2i(1, 6));
	main._show_factory_panel(regalada);
	var textos_regalo = _textos_panel(main.get_node("FactoryPanel"));
	var sin_devolucion = true;
	for t in textos_regalo:
		if t.begins_with("Demoler devuelve"):
			sin_devolucion = false;
	_check("y el almacén que el mapa regala no ofrece devolución: no hay línea que enseñar",
		sin_devolucion, str(textos_regalo));

	_limpiar([main.placer, main]);

	# (5) 🔴 EL ANCHO, RE-ANCLADO EN LAS LÍNEAS (Variedad M0, 2026-09-20). `BUTTON_WIDTH` es fijo
	# y una Label NO se recorta: lo que no puede pasarse de «✦ Mejora 1 vecina» ya no es «el
	# precio» sino CADA UNA de las líneas en que el precio se parte, porque desde el `cost` mixto
	# de la `Foundry` (12 wood + 6 stone) el precio ocupa una línea por material. De una tirada
	# medía 138 px contra los 130 del botón; partido, la más larga es la del primer material.
	# Se mide con la fuente de verdad —el proyecto no declara tema propio, así que la del juego
	# es la fallback— y al tamaño con el que el radial pinta sus labels, 11.
	var molde = load("res://ui/radialMenu.gd").new();
	var fuente = ThemeDB.fallback_font;
	var referencia = fuente.get_string_size(
		"✦ Mejora 1 vecina", HORIZONTAL_ALIGNMENT_CENTER, -1, 11).x;
	var ancho_max = 0.0;
	var mas_ancha = "";
	for nombre in fd["Factories"]:
		# La variante con «✖», que es la más larga de las dos redacciones posibles.
		for texto in molde._cost_lines(fd["Factories"][nombre].get("cost", null), false):
			var ancho = fuente.get_string_size(texto, HORIZONTAL_ALIGNMENT_CENTER, -1, 11).x;
			if ancho > ancho_max:
				ancho_max = ancho;
				mas_ancha = texto;
	_check("la línea de precio más larga cabe en el botón y no pasa de la que fija el ancho",
		ancho_max <= referencia and ancho_max < molde.BUTTON_WIDTH,
		"«%s» mide %.0fpx; «✦ Mejora 1 vecina» %.0fpx; el botón %d" % [
			mas_ancha, ancho_max, referencia, molde.BUTTON_WIDTH]);

	# Y el reparto en sí: un precio de dos materiales son DOS líneas, con el primero pegado al
	# «Coste:» para que los seis precios de un solo material sigan ocupando una sola.
	_check("un precio de dos materiales se parte en dos líneas y el de uno se queda en una",
		molde._cost_lines({ "wood": 12, "stone": 6 }, true) == ["Coste: 12 wood", "6 stone"]
		and molde._cost_lines({ "wood": 12, "stone": 6 }, false) == ["✖ Coste: 12 wood", "6 stone"]
		and molde._cost_lines({ "wood": 4 }, true) == ["Coste: 4 wood"]
		and molde._cost_lines(null, true) == [],
		str(molde._cost_lines({ "wood": 12, "stone": 6 }, false)));

	# (6) Las dos pantallas escriben el dinero IGUAL. Son dos funciones porque son dos
	# pantallas sin relación, y esta prueba es lo que impide que una de las dos derive: dos
	# redacciones distintas para lo mismo se leerían como dos mecánicas distintas.
	var molde_panel = load("res://ui/factoryPanel.gd").new();
	_check("el radial y el panel redactan una cantidad exactamente igual",
		molde._cost_text({ "wood": 8 }) == molde_panel._amount_text({ "wood": 8 })
		and molde._cost_text({ "wood": 8 }) == "8 wood",
		"%s vs %s" % [molde._cost_text({ "wood": 8 }), molde_panel._amount_text({ "wood": 8 })]);
	# Y el número se imprime como entero: el JSON parseado los da todos como float, así que sin
	# el int() el botón anunciaría «Coste: 8.0 wood».
	_check("las cantidades salen del JSON como float y se imprimen enteras",
		molde._cost_text(fd["Factories"]["WoodProcessing"]["cost"]) == "8 wood"
		and molde_panel._amount_text({ "plank": 3.0 }) == "3 plank",
		molde._cost_text(fd["Factories"]["WoodProcessing"]["cost"]));
	# Varios materiales a la vez: el formato es `material -> cantidad` desde M1 justamente para
	# que un precio mixto no obligue a cambiar el JSON, y la UI tiene que saber pintarlo.
	_check("un precio de dos materiales se escribe con los dos, separados por coma",
		molde._cost_text({ "wood": 4, "plank": 2 }) == "4 wood, 2 plank",
		molde._cost_text({ "wood": 4, "plank": 2 }));

	# (7) El contrato opcional en pantalla: sin `cost` la factoría es gratis, y el botón lo dice
	# con todas las letras en vez de callarse la línea — una opción sin precio y una opción cuyo
	# precio no se ha pintado se verían igual, que es justo lo que este hito viene a arreglar.
	var fd_gratis = fd.duplicate(true);
	fd_gratis["Factories"]["WoodCutter"].erase("cost");
	var radial_g = load("res://ui/radialMenu.gd").new();
	root.add_child(radial_g);
	radial_g.initialize(["WoodCutter"], fd_gratis, Vector2i(0, 0), Vector2(640, 360));
	var boton_g = _botones_radial(radial_g)["WoodCutter"];
	_check("una entrada sin `cost` se anuncia como gratis y se puede elegir",
		_textos_boton(boton_g) == ["WoodCutter", "→ wood", "Gratis"] and not boton_g.disabled,
		str(_textos_boton(boton_g)));

	# (8) Y sin diccionario de asequibilidad —la suite, cualquiera que no sepa de
	# dinero— el menú se monta como siempre: todo elegible. La ausencia de una clave significa
	# «se puede pagar», igual que la ausencia de `cost` significa gratis.
	var radial_sin = load("res://ui/radialMenu.gd").new();
	root.add_child(radial_sin);
	radial_sin.initialize(["WoodCutter", "WoodProcessing"], fd, Vector2i(0, 0), Vector2(640, 360));
	var sin_dinero = _botones_radial(radial_sin);
	_check("sin diccionario de asequibilidad no se apaga nada: el menú es el de antes, con precio",
		not sin_dinero["WoodCutter"].disabled and not sin_dinero["WoodProcessing"].disabled
		and _textos_boton(sin_dinero["WoodProcessing"]).has("Coste: 8 wood"),
		str(_textos_boton(sin_dinero["WoodProcessing"])));

	_limpiar([molde, molde_panel, radial_g, radial_sin]);

# ---------- Costes M5b: el arrastre prueba las dos L ----------

# Hasta M5b el arrastre trazaba SIEMPRE horizontal-primero, así que UNA sola casilla cerrada
# por contaminación en la fila de paso dejaba inalcanzable todo lo que hubiera detrás, y con
# costes escuece el doble: rodear a mano se paga en casillas de cinta. Ahora se prueban las
# dos L, en orden fijo. Este bloque vigila las cuatro cosas de las que depende que eso no
# rompa nada:
#   - las dos mitades del «hecho cuando»: con la L horizontal cortada se tiende por la
#     vertical, y con las dos cortadas no se tiende nada Y no se cobra nada;
#   - 🔴 que validar, tender y cobrar miren el MISMO camino: desde M5b hay dos posibles, así
#     que resolverlos por separado sería validar una L y tender otra;
#   - que el precio no dependa de cuál salga elegida, que es lo que permite que el dinero se
#     compruebe sobre el camino ya elegido sin volver a probar el otro; y
#   - que el orden de preferencia sea FIJO: la vertical entra solo cuando la horizontal no
#     cabe, o el jugador no podría predecir por dónde va a ir la cinta.
func _test_costes_m5b(file_data):
	print("Costes M5b — el arrastre prueba las dos L");
	var main = _new_main_en_arbol(file_data);
	var tm = main.get_node("TileMap");
	# Suelo de 12x12: los cinco escenarios caben sin estorbarse, y cada uno usa su franja.
	for y in range(12):
		for x in range(12):
			tm.set_cell(0, Vector2i(x, y), 1, Vector2i(0, 0));
	# El pollutionManager es quien cierra casillas: 20,0 en una celda pasa de sobra el
	# `cell_block_pollution` de 12,5, así que `canPlaceFactory()` la rechaza por su condición 2
	# — exactamente la casilla cerrada en la fila de paso que este bloque necesita.
	var pm = _new_pm();
	tm.setPollutionManager(pm);
	var red = load("res://managers/beltNetwork.gd").new();
	red.name = "BeltNetwork";
	main.add_child(red);
	red.initialize(tm, main.factoryArray, file_data);
	tm.setBeltNetwork(red);
	main.beltNetwork = red;
	var bolsa = main.get_node("Player/Bag");
	var avisos = [0];
	red.belt_network_changed.connect(func(): avisos[0] += 1);

	# Las dos L del arrastre (1,1) -> (4,3), escritas A MANO: si salieran de la función que se
	# está probando, la prueba diría que el código hace lo que hace y no lo que debe.
	var ele_h = [Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1), Vector2i(4, 1), Vector2i(4, 2), Vector2i(4, 3)];
	var ele_v = [Vector2i(1, 1), Vector2i(1, 2), Vector2i(1, 3), Vector2i(2, 3), Vector2i(3, 3), Vector2i(4, 3)];

	# (1) El orden de preferencia, con el mapa despejado: dos candidatos, el horizontal el
	# primero, y las dos L con el MISMO largo (la distancia manhattan + 1).
	var candidatos = red._candidate_paths(Vector2i(1, 1), Vector2i(4, 3));
	_check("un arrastre en diagonal ofrece DOS caminos, el horizontal-primero por delante",
		candidatos.size() == 2 and candidatos[0] == ele_h and candidatos[1] == ele_v,
		str(candidatos));
	_check("y las dos L miden lo mismo, así que MAX_PATH no puede descartar una y dejar la otra",
		candidatos[0].size() == candidatos[1].size(), "%d y %d" % [candidatos[0].size(), candidatos[1].size()]);
	_check("con el mapa despejado el camino elegido es el horizontal-primero, como antes de M5b",
		red.resolve_drag_path(Vector2i(1, 1), Vector2i(4, 3), main.factoryArray) == ele_h,
		str(red.resolve_drag_path(Vector2i(1, 1), Vector2i(4, 3), main.factoryArray)));
	var preferente = red.place_drag(Vector2i(6, 1), Vector2i(9, 3), main.factoryArray);
	_check("y se tiende esa: la L preferente no cambia por el hecho de haber una alternativa",
		preferente == [Vector2i(6, 1), Vector2i(7, 1), Vector2i(8, 1), Vector2i(9, 1), Vector2i(9, 2), Vector2i(9, 3)],
		"tendió %s" % str(preferente));

	# (2) 🔴 EL «HECHO CUANDO», primera mitad: con la casilla intermedia de la L horizontal
	# cerrada por contaminación, el arrastre se tiende igualmente por la L vertical.
	pm.addPollution(20.0, Vector2i(3, 1));
	_check("la contaminación cierra de verdad la casilla intermedia de la L horizontal",
		not tm.canPlaceFactory(Vector2i(3, 1), main.factoryArray));
	_check("con la L horizontal cortada el arrastre SIGUE cabiendo",
		red.can_place_drag(Vector2i(1, 1), Vector2i(4, 3), main.factoryArray));
	_check("y el camino que se anuncia es la L vertical, entera",
		red.resolve_drag_path(Vector2i(1, 1), Vector2i(4, 3), main.factoryArray) == ele_v,
		str(red.resolve_drag_path(Vector2i(1, 1), Vector2i(4, 3), main.factoryArray)));
	# Con 6 de madera justas: el tramo son las seis casillas del camino (ningún extremo lo
	# ocupa una factoría) a 1 de madera cada una, que es el precio de `Belts.cost_per_cell`.
	bolsa.addToBag("wood", 6);
	var vertical = red.place_drag(Vector2i(1, 1), Vector2i(4, 3), main.factoryArray, bolsa, true);
	_check("🔴 con la L horizontal cortada, el arrastre se tiende por la vertical",
		vertical == ele_v, "tendió %s" % str(vertical));
	_check("y no deja ni un segmento en la L horizontal que no cabía",
		not red.has_belt(Vector2i(2, 1)) and not red.has_belt(Vector2i(4, 1))
		and not red.has_belt(Vector2i(4, 2)));
	_check("se cobra lo que se tiende y ni una casilla más: seis casillas, seis de madera",
		bolsa.getQuantity("wood") == 0, "quedan %d" % bolsa.getQuantity("wood"));

	# (3) 🔴 EL «HECHO CUANDO», segunda mitad: con las dos L cortadas no se tiende nada y no se
	# cobra nada. Ni un segmento, ni una moneda, ni la señal.
	pm.addPollution(20.0, Vector2i(3, 5));   # corta la L horizontal de (1,5) -> (4,7)
	pm.addPollution(20.0, Vector2i(2, 7));   # y ésta la vertical
	bolsa.addToBag("wood", 20);
	var segmentos_antes = red.belt_count();
	var avisos_antes = avisos[0];
	var ninguna = red.place_drag(Vector2i(1, 5), Vector2i(4, 7), main.factoryArray, bolsa, true);
	_check("🔴 con las dos L cortadas no se tiende nada",
		ninguna.is_empty() and red.belt_count() == segmentos_antes,
		"devolvió %s y la red tiene %d (tenía %d)" % [str(ninguna), red.belt_count(), segmentos_antes]);
	_check("🔴 y no se cobra nada: la bolsa se queda exactamente donde estaba",
		bolsa.getQuantity("wood") == 20, "quedan %d" % bolsa.getQuantity("wood"));
	_check("ni se avisa a quien escucha: no ha cambiado nada que mirar",
		avisos[0] == avisos_antes, "%d avisos nuevos" % (avisos[0] - avisos_antes));
	_check("y la validación dice lo mismo que el tendido: no cabe",
		not red.can_place_drag(Vector2i(1, 5), Vector2i(4, 7), main.factoryArray)
		and red.resolve_drag_path(Vector2i(1, 5), Vector2i(4, 7), main.factoryArray).is_empty());

	# (4) 🔴 VALIDAR, TENDER Y COBRAR MIRAN EL MISMO CAMINO. Con factorías en los dos extremos,
	# que es donde el precio podría separarse del largo del camino: `_belt_range()` recorta los
	# extremos ocupados, y hay que comprobar que recorta IGUAL en las dos L — si no, el precio
	# validado y el cobrado podrían ser dos números distintos según qué L saliera elegida.
	var cortadora = _factoria_en_main(main, "WoodCutter", Vector2i(6, 5), 1, null, "wood");
	var sierra = _factoria_en_main(main, "WoodProcessing", Vector2i(9, 7), 1, ["wood"], "plank");
	var dos = red._candidate_paths(cortadora.cell_position, sierra.cell_position);
	var tramo_h = red._belt_range(dos[0], main.factoryArray);
	var tramo_v = red._belt_range(dos[1], main.factoryArray);
	_check("las dos L recortan los mismos extremos: son las mismas dos casillas en las dos",
		tramo_h == tramo_v and tramo_h == Vector2i(1, 4), "%s y %s" % [str(tramo_h), str(tramo_v)]);
	_check("así que las dos cuestan lo MISMO, y el dinero no puede elegir camino",
		red.belt_cost_for(tramo_h.y - tramo_h.x + 1) == red.belt_cost_for(tramo_v.y - tramo_v.x + 1));
	pm.addPollution(20.0, Vector2i(8, 5));   # cierra la L horizontal entre las dos factorías
	var anunciado = red.resolve_drag_path(cortadora.cell_position, sierra.cell_position, main.factoryArray);
	_check("con la horizontal cortada, el camino anunciado es la vertical aunque los extremos estén ocupados",
		anunciado == [Vector2i(6, 5), Vector2i(6, 6), Vector2i(6, 7), Vector2i(7, 7), Vector2i(8, 7), Vector2i(9, 7)],
		str(anunciado));
	# El precio de ese camino: cuatro casillas, porque los dos extremos los ocupan las
	# factorías. Con 3 de madera no alcanza y con 4 sí — el mismo número por los dos lados.
	bolsa.removeFromBag("wood", 17);
	_check("con 3 de madera la validación rechaza el arrastre de cuatro casillas",
		not red.can_place_drag(cortadora.cell_position, sierra.cell_position, main.factoryArray, bolsa, true),
		"madera %d" % bolsa.getQuantity("wood"));
	bolsa.addToBag("wood", 1);
	_check("y con 4 lo acepta: el precio validado es el del camino elegido, no el del preferente",
		red.can_place_drag(cortadora.cell_position, sierra.cell_position, main.factoryArray, bolsa, true));
	var entre = red.place_drag(cortadora.cell_position, sierra.cell_position, main.factoryArray, bolsa, true);
	_check("se tiende ese mismo camino, sin las casillas de las dos factorías",
		entre == [Vector2i(6, 6), Vector2i(6, 7), Vector2i(7, 7), Vector2i(8, 7)],
		"tendió %s" % str(entre));
	_check("y se cobra ese mismo número: lo validado y lo cobrado son 4, no 6",
		bolsa.getQuantity("wood") == 0, "quedan %d" % bolsa.getQuantity("wood"));
	# Y la L que se eligió es la que ORIENTA los segmentos: un codo distinto es un `dir_in` y
	# un `dir_out` distintos, y de ellos cuelgan _entry_segment() y deliver().
	var punta = red.get_belt(Vector2i(6, 6));
	var cola = red.get_belt(Vector2i(8, 7));
	_check("la punta del camino elegido mira a la factoría de origen",
		punta.cell + punta.dir_in == cortadora.cell_position, str(punta.dir_in));
	_check("y su cola apunta a la de destino",
		cola.cell + cola.dir_out == sierra.cell_position, str(cola.dir_out));
	_check("así que la entrega llega de punta a punta por la L vertical",
		red.deliver(cortadora.cell_position, "wood", 3) == 3
		and int(sierra.input_buffer.get("wood", 0)) == 3, str(sierra.input_buffer));

	# (5) La alternativa NO se usa cuando la preferente cabe: una casilla cerrada que solo
	# estorba a la L vertical no cambia el trazado. Es la mitad que hace predecible el gesto.
	pm.addPollution(20.0, Vector2i(2, 11));
	var sigue_h = red.place_drag(Vector2i(1, 9), Vector2i(4, 11), main.factoryArray);
	_check("una casilla cerrada que solo corta la L vertical no mueve el trazado preferente",
		sigue_h == [Vector2i(1, 9), Vector2i(2, 9), Vector2i(3, 9), Vector2i(4, 9), Vector2i(4, 10), Vector2i(4, 11)],
		"tendió %s" % str(sigue_h));

	# (6) Y un arrastre RECTO no tiene dos L: la misma fila o la misma columna dan un solo
	# camino, así que una casilla cerrada en medio lo tumba igual que antes de M5b.
	pm.addPollution(20.0, Vector2i(8, 9));
	_check("un arrastre recto ofrece UN solo camino: las dos L serían el mismo",
		red._candidate_paths(Vector2i(6, 9), Vector2i(9, 9)).size() == 1);
	_check("y una casilla cerrada en medio lo sigue tumbando entero",
		red.place_drag(Vector2i(6, 9), Vector2i(9, 9), main.factoryArray).is_empty()
		and not red.has_belt(Vector2i(7, 9)));

	_limpiar([pm, main]);

# ---------- Costes M5c: el HUD enseña lo que se puede gastar ----------

# El agujero lo destapó ARRANCAR el juego, no la suite: el HUD anunciaba `wood: 10` mientras el
# radial, en la misma pantalla, apagaba una opción con `✖ Coste: 8 wood`. Los dos decían la
# verdad —5 de esos 10 estaban reservados para el mantenimiento del checkpoint— pero entenderlo
# exigía restar dos números de dos sitios distintos. Este bloque vigila las dos mitades del
# criterio, que tiran en sentidos contrarios:
#   - CON reserva, la línea distingue el disponible del total (y el disponible es el número
#     contra el que de verdad decide el cobro);
#   - SIN reserva, la línea es carácter por carácter la de antes del hito — que es la
#     regresión que protege el criterio: el desglose no puede volverse ruido permanente.
# Y la condición es POR MATERIAL: `reserved` puede apartar `wood` y no apartar `plank`.
func _test_costes_m5c(fd):
	print("Costes M5c — el HUD enseña lo que se puede gastar");
	var main = _new_main_de_prueba(fd);
	var bolsa = _new_bag();
	bolsa.initialize(fd);
	bolsa.workers_total = 3;

	# El texto de referencia: el que este mismo HUD pintaba ANTES del hito, reconstruido aquí
	# con el algoritmo viejo (una línea por recurso con getQuantity(), y la de workers). Se
	# compara carácter por carácter y no por `contains()`: lo que el criterio de David protege
	# es que sin reserva no aparezca NADA nuevo, ni un separador ni un espacio de más.
	bolsa.addToBag("wood", 10);
	bolsa.addToBag("plank", 4);
	var esperado_viejo = "";
	for recurso in bolsa.bag:
		esperado_viejo += recurso + ": " + str(bolsa.getQuantity(recurso)) + "\n";
	esperado_viejo += "Workers: 3/3 libres\n";

	# (1) 🔴 La mitad regresiva del «hecho cuando»: con la reserva levantada —la mayor parte de
	# la run, y toda la fase de restauración— el bloque entero se lee exactamente como antes.
	_check("sin reserva el HUD de recursos es carácter por carácter el de antes del hito",
		main._buildResourceText(bolsa) == esperado_viejo,
		"%s != %s" % [main._buildResourceText(bolsa), esperado_viejo]);

	# (2) 🔴 La otra mitad, con los números literales del hito: 10 de madera y 5 reservados.
	bolsa.setReserved({ "wood": 5 });
	var con_reserva = main._buildResourceText(bolsa);
	_check("con 10 de madera y 5 reservados la línea distingue los dos números",
		con_reserva.contains("wood: 5/10 libres\n"), con_reserva);
	_check("y no queda rastro de la línea vieja, que diría solo el total",
		not con_reserva.contains("wood: 10\n"), con_reserva);

	# (3) La condición es POR MATERIAL y no global: el mismo frame tiene `wood` apartado y
	# `plank` no, porque el mantenimiento del checkpoint pide un material y no la bolsa entera.
	# Si la condición fuera global, `plank` se desglosaría sin tener nada que explicar.
	_check("el plank, que no tiene reserva, se queda exactamente como estaba",
		con_reserva.contains("plank: 4\n") and not con_reserva.contains("plank: 4/4"),
		con_reserva);
	_check("y la línea de workers no se toca: el desglose es de material",
		con_reserva.contains("Workers: 3/3 libres\n"), con_reserva);

	# (4) El caso que más necesita leerse bien: la reserva SUPERA lo que hay (el checkpoint
	# pide 15 y tienes 10). getAvailable() corta en 0 y el total sigue siendo 10, así que la
	# línea tiene que decir las dos cosas: no puedes gastar nada, y no has perdido la madera.
	bolsa.setReserved({ "wood": 15 });
	var ahogada = main._buildResourceText(bolsa);
	_check("con la reserva por encima de la bolsa el disponible es 0 y el total sigue visible",
		ahogada.contains("wood: 0/10 libres\n"), ahogada);

	# (5) Una reserva declarada a 0 no es una reserva: no hay nada que explicar y la línea no
	# se parte. Pasa de verdad —gameManager sincroniza el mantenimiento del checkpoint en
	# curso, y hay checkpoints que no cobran—, y con un `> 0` mal puesto saldría `10/10`.
	bolsa.setReserved({ "wood": 0, "plank": 0 });
	_check("una reserva de 0 no parte la línea: no hay dos números que distinguir",
		main._buildResourceText(bolsa) == esperado_viejo,
		main._buildResourceText(bolsa));

	# (6) Y levantarla entera (dict vacío) devuelve el HUD al texto de antes, que es lo que
	# ocurre al cerrar el checkpoint y durante toda la fase de restauración.
	bolsa.setReserved({});
	_check("al levantar la reserva el HUD vuelve al texto de antes, sin residuo",
		main._buildResourceText(bolsa) == esperado_viejo,
		main._buildResourceText(bolsa));

	# (7) La razón de ser del hito: el número NUEVO que el HUD pinta es exactamente el que
	# decide el cobro. Con 10 de madera y 5 reservados, la WoodProcessing de 8 no se puede
	# pagar —canAfford() mira getAvailable()—, y ahora el HUD lo explica él solo en vez de
	# dejar al jugador restando la línea de objetivo de la de recursos.
	bolsa.setReserved({ "wood": 5 });
	var placer = load("res://entities/factory/factoryPlacer.gd").new();
	placer.initialize(load("res://entities/factory/factory.tscn"), fd, []);
	_check("el número que el HUD enseña es el mismo contra el que decide canAfford()",
		not placer.canAfford("WoodProcessing", bolsa)
		and main._buildResourceText(bolsa).contains(
			"wood: " + str(bolsa.getAvailable("wood")) + "/10 libres"),
		"canAfford=%s, HUD=%s" % [str(placer.canAfford("WoodProcessing", bolsa)),
			main._buildResourceText(bolsa)]);

	_limpiar([placer, bolsa, main]);

# ---------- Costes M6b: el castigo graduado del catálogo ----------

# El 🔴 que el roadmap arrastraba desde el 2026-09-17: las CUATRO cartas de tier 2 llevaban
# castigo y la pantalla ofrece tres, así que no había carta potente sin castigo y el dilema no
# llegaba a plantearse — la run se decidía en el sorteo del checkpoint 1. M6b no quita el
# castigo (eso sería regalar el tier 2), lo GRADÚA por cuánto acelera cada carta el reloj:
# `extra_wood` toca la fuente de toda la cadena y paga 3; `extra_plank` actúa un escalón más
# abajo y paga 2; `speed_woodprocessing_ii` es un tick sobre un solo tipo y paga 1; y
# `extra_reforest` potencia la limpieza, o sea que ya se paga su propio castigo — cobrarle más
# de 1 sería cobrarle dos veces.
# La tabla va escrita A MANO aquí porque es el diseño cerrado: una prueba que la leyera del
# JSON solo diría que el JSON es igual a sí mismo.
func _test_costes_m6b(fd):
	print("Costes M6b — el castigo graduado del catálogo");
	var catalogo = fd["Upgrades"];
	# 🔴 La tabla creció de cuatro a SIETE con Variedad M5 (2026-09-22): las tres
	# `unlock_factory` de la segunda cadena entran en tier 2, y el `## 🧭 Alcance` del Plan
	# «Catálogo de Mejoras» obliga a que una carta de tier 2 lleve castigo. Sus tres números,
	# provisionales como el resto de la tabla, se eligieron por coherencia con esta escala: la cantera paga 2 como `extra_plank` (abre la segunda cadena y es
	# la factoría que más ensucia del juego, `pollution 4.0`), y la fundición y la depuradora
	# pagan el suelo del tier, 1, la primera porque sin piedra que le llegue no hace nada y la
	# segunda por lo mismo que `extra_reforest`: limpia, o sea que ya se paga su castigo.
	var esperado = {
		"speed_woodprocessing_ii": 1,
		"extra_reforest": 1,
		"extra_plank": 2,
		"extra_wood": 3,
		"unlock_quarry": 2,
		"unlock_foundry": 1,
		"unlock_watertreatment": 1
	};

	# (1) El tier 2 es exactamente ese. Si mañana entra una carta potente que no pasó por la
	# tabla, el castigo graduado deja de estar completo y esto lo canta.
	var tier_2 = [];
	for id in catalogo:
		if int(catalogo[id].get("tier", 1)) == 2:
			tier_2.append(id);
	tier_2.sort();
	var ids_esperados = esperado.keys();
	ids_esperados.sort();
	_check("el tier 2 son las siete cartas del castigo graduado", tier_2 == ids_esperados,
		"tier 2 = %s" % str(tier_2));

	# (2) Cada una declara lo suyo, y el castigo es GRADUADO de verdad: tres escalones, con
	# `extra_wood` sola en el más caro y `extra_reforest` en el mínimo.
	var declarados = {};
	var todas_bien = true;
	for id in esperado:
		var d = catalogo.get(id, {}).get("map_downside", {});
		declarados[id] = int(d.get("cells", 0));
		if declarados[id] != int(esperado[id]) or str(d.get("type", "")) != "toxic":
			todas_bien = false;
	_check("las siete declaran el castigo de la tabla (1/1/1/1/2/2/3, todas a toxic)", todas_bien,
		"declarado %s, esperado %s" % [str(declarados), str(esperado)]);
	var escalones = {};
	for id in declarados:
		escalones[declarados[id]] = true;
	_check("y no son siete castigos iguales: hay tres escalones",
		escalones.size() == 3, "escalones %s" % str(escalones.keys()));
	_check("la carta que toca la fuente de la cadena es la más cara, ella sola",
		declarados["extra_wood"] > declarados["extra_plank"]
		and declarados["extra_plank"] > declarados["speed_woodprocessing_ii"],
		str(declarados));
	_check("y la que potencia la limpieza paga el mínimo: ya se paga su propio castigo",
		declarados["extra_reforest"] == 1, str(declarados));

	# (3) Lo que el jugador LEE. El número no se escribe a mano en el `description` del JSON:
	# lo redacta `upgradeScreen._downside_text()` a partir del MISMO `map_downside` del que
	# cobra `Main._apply_map_downside()`, y por eso no pueden divergir — que es justo el bug
	# que este hito no podía introducir (decir «2 casillas» y degradar 3 es mentirle al
	# jugador). Se ata igualmente por las dos puntas, y de paso se vigila que ninguna
	# `description` cuele un recuento de casillas propio que contradiga al declarado.
	var pantalla = load("res://ui/upgradeScreen.gd").new();
	var re = RegEx.new();
	re.compile("(\\d+)\\s+casilla");
	# Control negativo: un guardián que no sabe cazar la mentira no guarda nada. Si el patrón
	# no compilara, `search()` devolvería null siempre y la comprobación de abajo pasaría
	# sola sin mirar una sola descripción.
	var mentira = re.search("Degrada 9 casillas del mapa y produce el doble");
	_check("el guardián de la descripción sabe leer un recuento escrito a mano",
		mentira != null and int(mentira.get_string(1)) == 9);
	var texto_dice_el_numero = true;
	var descripcion_no_miente = true;
	var textos = [];
	for id in esperado:
		var n = declarados[id];
		var texto = str(pantalla._downside_text(catalogo[id]["map_downside"]));
		textos.append(texto);
		var fragmento = "%d %s" % [n, "casilla" if n == 1 else "casillas"];
		if not fragmento in texto:
			texto_dice_el_numero = false;
		var m = re.search(str(catalogo[id].get("description", "")));
		if m != null and int(m.get_string(1)) != n:
			descripcion_no_miente = false;
	_check("cada carta le anuncia al jugador el número de casillas que declara",
		texto_dice_el_numero, str(textos));
	_check("y ninguna descripción cuela un recuento que contradiga al declarado",
		descripcion_no_miente);
	pantalla.free();

	# (4) Y no es papel: aplicada por la puerta real (`_apply_upgrade()` con el catálogo del
	# juego), cada carta degrada EXACTAMENTE lo que anuncia. Un suelo de 6x6 le sobra a la
	# más cara.
	var aplicado = {};
	var aplica_bien = true;
	for id in esperado:
		var pm = _new_pm();
		var main = _new_main_de_prueba(fd);
		main.pollutionManager = pm;
		var tm = main.get_node("TileMap");
		tm.setPollutionManager(pm);
		for y in range(6):
			for x in range(6):
				tm.set_cell(0, Vector2i(x, y), 1, Vector2i(0, 0));
		main._apply_upgrade(id);
		aplicado[id] = _celdas_de_tipo(tm, "toxic").size();
		if aplicado[id] != declarados[id]:
			aplica_bien = false;
		_limpiar([main, pm]);
	_check("aplicadas de verdad, las siete degradan lo que anuncian", aplica_bien,
		"aplicado %s, declarado %s" % [str(aplicado), str(declarados)]);

	# (5) La trampa de la gradación: `_degradable_cells()` solo cuenta suelo libre y SIN tipo,
	# así que en un mapa apretado un castigo de 3 podría degradar menos de 3 y la gradación no
	# existiría en la práctica — el castigo se diluiría solo. Se mide sobre el mapa REAL
	# `forest_01` (16x10 con sus 7 especiales) en una foto de run avanzada: 14 factorías en pie
	# y una troncal de cinta tendida por la red. Las cintas **no** restan —no viven en
	# `cell_types` ni son factorías, así que `_degradable_cells()` ni las mira—, y por eso el
	# transporte no diluyó nada.
	var mapa = {};
	for m in fd["Maps"]:
		if str(m.get("id", "")) == "forest_01":
			mapa = m;
	var ancho = int(mapa["size"][0]);
	var alto = int(mapa["size"][1]);
	var main_lleno = _new_main_en_arbol(fd);
	var pm_lleno = _new_pm();
	main_lleno.pollutionManager = pm_lleno;
	var tm_lleno = main_lleno.get_node("TileMap");
	tm_lleno.setPollutionManager(pm_lleno);
	for y in range(alto):
		for x in range(ancho):
			tm_lleno.set_cell(0, Vector2i(x, y), 1, Vector2i(0, 0));
	for sc in mapa["special_cells"]:
		tm_lleno.cell_types[Vector2i(int(sc["pos"][0]), int(sc["pos"][1]))] = str(sc["type"]);
	var ocupantes = [];
	for i in range(14):
		var f = _new_factory("WoodCutter", Vector2i(i % ancho, int(i / ancho)));
		main_lleno.factoryArray.append(f);
		ocupantes.append(f);
	var red = load("res://managers/beltNetwork.gd").new();
	red.name = "BeltNetwork";
	main_lleno.add_child(red);
	red.initialize(tm_lleno, main_lleno.factoryArray, fd);
	tm_lleno.setBeltNetwork(red);
	main_lleno.beltNetwork = red;
	var tendidas = red.place_drag(Vector2i(2, 8), Vector2i(13, 8), main_lleno.factoryArray).size();
	var degradables = main_lleno._degradable_cells(tm_lleno).size();
	print("    medido: %d casillas degradables de %d de suelo (14 factorías, %d de cinta)"
		% [degradables, ancho * alto, tendidas]);
	_check("en un mapa de run avanzada sobran casillas: el castigo NO se diluye",
		degradables >= declarados["extra_wood"],
		"%d degradables, la carta más cara pide %d" % [degradables, declarados["extra_wood"]]);
	_check("y las cintas tendidas no le quitan ni una: no son casillas con tipo ni factorías",
		tendidas > 0 and degradables == ancho * alto - mapa["special_cells"].size() - ocupantes.size(),
		"%d degradables, %d de cinta" % [degradables, tendidas]);
	main_lleno._apply_upgrade("extra_wood");
	_check("así que `extra_wood` paga sus 3 casillas enteras sobre el mapa real",
		_celdas_de_tipo(tm_lleno, "toxic").size() == declarados["extra_wood"],
		"degradó %d" % _celdas_de_tipo(tm_lleno, "toxic").size());
	_limpiar(ocupantes);
	_limpiar([main_lleno, pm_lleno]);

	# (6) El otro lado de la misma moneda, y es intencional: donde NO hay sitio, el castigo se
	# encoge en silencio en vez de reventar. Con una sola casilla degradable, `extra_wood`
	# degrada una. No es un fallo: es lo que impide que la carta se quede sin poder aplicarse.
	var main_corto = _new_main_de_prueba(fd);
	var tm_corto = main_corto.get_node("TileMap");
	for cell in [Vector2i(0, 0), Vector2i(1, 0)]:
		tm_corto.set_cell(0, cell, 1, Vector2i(0, 0));
	tm_corto.cell_types[Vector2i(0, 0)] = "ruins";
	main_corto._apply_upgrade("extra_wood");
	_check("y sin sitio el castigo se encoge en silencio, no revienta",
		_celdas_de_tipo(tm_corto, "toxic").size() == 1,
		"degradó %d" % _celdas_de_tipo(tm_corto, "toxic").size());
	_limpiar([main_corto]);

# ---------- Catálogo M2: la revisión de tiers ----------

# M2 revisó las 10 entradas contra lo que valen de verdad y NO movió ninguna. Lo que esta
# prueba fija no es «el JSON es igual a sí mismo», son las dos cosas de las que cuelga esa
# decisión y que no vigila nadie más:
#
# (a) El tier 1 le llega al jugador con CINCO cartas, nunca con las seis del JSON.
#     `unlock_woodprocessing` no entra jamás en la baraja de la que se reparte: en `standard`
#     la filtra `_usable_upgrades()` —ya trae la procesadora— y en `lumberjack`/`ecologist`
#     se CONCEDE antes de repartir (`_granted_upgrades()`), así que sale de `pool`. Su tier es
#     inerte, y se mide más abajo: moverla a tier 2 no cambia una sola pantalla, y encima
#     obligaría a cobrarle un castigo a la única carta que el jugador ni elige ni puede
#     rechazar. Se queda en tier 1.
# (b) Con cinco cartas, elegir tres deja diez manos distintas. Promover cualquier OTRA de las
#     cinco dejaría cuatro —y la pantalla de la recompensa corriente volvería a ser el trámite
#     que la 3.ª enmienda de M2 le quitó al tier 2—, además de meter una quinta carta castigada
#     en el tier 2.
func _test_catalogo_m2_tiers(fd):
	print("Catálogo M2 — la revisión de tiers");
	var catalogo = fd["Upgrades"];

	# (1) La tabla de la revisión, escrita A MANO: es la decisión de M2, no un reflejo del
	# JSON. Si mañana una carta cambia de tier sin pasar por la revisión, esto lo canta.
	var esperado_1 = ["speed_woodcutter", "speed_woodprocessing", "speed_reforester",
		"more_workers", "extra_workers_camp", "unlock_woodprocessing"];
	# 🔴 El tier 2 pasó de cuatro cartas a SIETE con Variedad M5 (2026-09-22): las tres
	# `unlock_factory` de la segunda cadena. El tier 1 NO se ha tocado, que es lo que deja
	# intactas las 5 cartas de la baraja corriente y sus 10 manos.
	var esperado_2 = ["speed_woodprocessing_ii", "extra_wood", "extra_plank", "extra_reforest",
		"unlock_quarry", "unlock_foundry", "unlock_watertreatment"];
	esperado_1.sort();
	esperado_2.sort();
	var reparto = {};
	for id in catalogo:
		var t = int(catalogo[id].get("tier", 1));
		if not reparto.has(t):
			reparto[t] = [];
		reparto[t].append(id);
	var uno = reparto.get(1, []).duplicate();
	var dos = reparto.get(2, []).duplicate();
	uno.sort();
	dos.sort();
	_check("el tier 1 son las seis entradas que M2 revisó y dejó donde estaban",
		uno == esperado_1, "tier 1 = %s" % str(uno));
	_check("y el tier 2 son las siete del castigo graduado: el cuarteto más las tres de Variedad M5",
		dos == esperado_2, "tier 2 = %s" % str(dos));
	_check("no hay más tiers que esos dos", reparto.size() == 2,
		"tiers = %s" % str(reparto.keys()));

	# (2) La regla que ata las dos mitades y que decide qué puede promoverse: el tier 2 se
	# paga y el tier 1 no. Una carta promovida sin `map_downside` sería la quinta carta gratis
	# de tier 2 que el plan descarta a propósito.
	var tier_1_gratis = true;
	var tier_2_pagado = true;
	for id in esperado_1:
		if catalogo[id].has("map_downside"):
			tier_1_gratis = false;
	for id in esperado_2:
		if int(catalogo[id].get("map_downside", {}).get("cells", 0)) <= 0:
			tier_2_pagado = false;
	_check("ninguna corriente lleva castigo", tier_1_gratis);
	_check("y las siete potentes lo llevan: promover una carta es cobrarle un castigo",
		tier_2_pagado);

	# (3) El criterio de «hecho» del hito, caminado de verdad: los 5 checkpoints de las dos
	# rutas (la corriente y la potente) en los tres paquetes, 30 repartos. Se avanza
	# `current_checkpoint_index` y se aplica lo concedido igual que hace
	# `Main._on_checkpoint_reached()`, porque la baraja cambia con la curva.
	var manos = 0;
	var con_concedida = 0;
	var siempre_tres = true;
	var siempre_del_tier = true;
	var rescate_aparte = true;
	var baraja_de_cinco = true;
	var detalle = "";
	for paquete in fd["StartingPackages"]:
		for ruta in [1, 2]:
			var gm = _new_gm(fd);
			var jugador = StubPlayer.new();
			jugador.availableFactories = fd["StartingPackages"][paquete]["factories"].duplicate();
			gm.setPlayer(jugador);
			for i in range(fd["Checkpoints"].size()):
				gm.current_checkpoint_index = i;
				var concedidas = gm._granted_upgrades();
				var ofrecidas = gm._pick_upgrades(3, ruta, concedidas);
				manos += 1;
				if not concedidas.is_empty():
					con_concedida += 1;
				if ofrecidas.size() != 3 or not _sin_repetidas(ofrecidas):
					siempre_tres = false;
					detalle = "%s/tier %d/cp %d: %s" % [paquete, ruta, i + 1, str(ofrecidas)];
				if not _todas_de_tier(catalogo, ofrecidas, ruta):
					siempre_del_tier = false;
					detalle = "%s/tier %d/cp %d: %s" % [paquete, ruta, i + 1, str(ofrecidas)];
				for id in concedidas:
					if ofrecidas.has(id):
						rescate_aparte = false;
						detalle = "%s/tier %d/cp %d: %s" % [paquete, ruta, i + 1, str(ofrecidas)];
				var corrientes_vivas = [];
				for id in gm._usable_upgrades():
					if int(catalogo[id].get("tier", 1)) == 1 and not concedidas.has(id):
						corrientes_vivas.append(id);
				if corrientes_vivas.size() != 5:
					baraja_de_cinco = false;
					detalle = "%s/tier %d/cp %d: %s" % [paquete, ruta, i + 1, str(corrientes_vivas)];
				# Lo concedido se aplica en el acto, como en Main: el checkpoint siguiente ya
				# no puede volver a concederlo ni a ofrecerlo.
				for id in concedidas:
					var factoria = str(catalogo[id].get("factory", ""));
					if factoria != "" and not jugador.availableFactories.has(factoria):
						jugador.availableFactories.append(factoria);
			_limpiar([gm]);
	_check("se reparten las 30 pantallas de la revisión (3 paquetes x 5 checkpoints x 2 rutas)",
		manos == 30, "fueron %d" % manos);
	_check("todas ofrecen 3 cartas distintas", siempre_tres, detalle);
	_check("y ninguna baja de tier por falta de candidatas", siempre_del_tier, detalle);
	# Control de que lo de arriba no pasa en vacío: la carta de rescate se concede de verdad
	# en el primer checkpoint de los dos paquetes que no traen procesadora, en las dos rutas.
	_check("hay 4 pantallas con carta concedida (lumberjack y ecologist, checkpoint 1, dos rutas)",
		con_concedida == 4, "fueron %d" % con_concedida);
	_check("y la concedida nunca ocupa una de las tres: se da aparte", rescate_aparte, detalle);
	_check("la baraja corriente son siempre 5 cartas, no las 6 del JSON", baraja_de_cinco, detalle);

	# (4) Por qué el tier de `unlock_woodprocessing` es inerte, medido en vez de razonado: se
	# le mueve el tier en una copia del catálogo y se vuelve a repartir la única pantalla en la
	# que la carta está viva —el checkpoint 1 de `lumberjack`—. No cambia nada, porque quien la
	# entrega es `_rescue_upgrades()`, que no mira el tier. Promoverla no sería una decisión de
	# diseño: sería un cambio que el jugador no puede ver.
	var movido = catalogo.duplicate(true);
	movido["unlock_woodprocessing"]["tier"] = 2;
	var gm_movido = _new_gm(fd);
	gm_movido.upgrades_catalog = movido;
	var lenador = StubPlayer.new();
	lenador.availableFactories = fd["StartingPackages"]["lumberjack"]["factories"].duplicate();
	gm_movido.setPlayer(lenador);
	var concedidas_movido = gm_movido._granted_upgrades();
	var corrientes_movido = gm_movido._pick_upgrades(3, 1, concedidas_movido);
	var potentes_movido = gm_movido._pick_upgrades(3, 2, concedidas_movido);
	_check("con la carta de rescate en tier 2 se sigue concediendo igual: el rescate no mira el tier",
		concedidas_movido == ["unlock_woodprocessing"], "concedió %s" % str(concedidas_movido));
	_check("y la pantalla sigue dando 3 corrientes y 3 potentes sin enseñarla",
		corrientes_movido.size() == 3 and _todas_de_tier(movido, corrientes_movido, 1)
		and potentes_movido.size() == 3 and _todas_de_tier(movido, potentes_movido, 2)
		and not corrientes_movido.has("unlock_woodprocessing")
		and not potentes_movido.has("unlock_woodprocessing"),
		"corrientes %s, potentes %s" % [str(corrientes_movido), str(potentes_movido)]);
	_limpiar([gm_movido]);

	# (5) Y por qué cinco cartas y no cuatro: con cinco hay 10 manos posibles y la pantalla
	# corriente sigue siendo una elección. Se mide, que es lo que convierte el argumento en
	# criterio — con cuatro serían 4 manos, y con tres siempre la misma.
	var gm_manos = _new_gm(fd);
	var estandar = StubPlayer.new();
	estandar.availableFactories = fd["StartingPackages"]["standard"]["factories"].duplicate();
	gm_manos.setPlayer(estandar);
	var vistas = {};
	for i in range(120):
		var mano = gm_manos._pick_upgrades(3, 1);
		mano.sort();
		vistas[str(mano)] = true;
	print("    medido: %d manos distintas de tier 1 en 120 pantallas de standard" % vistas.size());
	_check("la pantalla corriente no es un trámite: salen varias manos distintas",
		vistas.size() >= 5, "%d manos" % vistas.size());
	_limpiar([gm_manos]);

# Los botones de un radial montado, indexados por el nombre que cada uno pinta en su primera
# línea: el orden de `available_factories` es un detalle del menú y no de lo que se prueba.
func _botones_radial(radial) -> Dictionary:
	var por_nombre = {};
	for b in radial.find_children("", "Button", true, false):
		var labels = b.find_children("", "Label", true, false);
		if labels.is_empty():
			continue;
		por_nombre[labels[0].text] = b;
	return por_nombre;

func _textos_boton(btn) -> Array:
	var textos = [];
	for l in btn.find_children("", "Label", true, false):
		textos.append(l.text);
	return textos;

func _textos_panel(panel) -> Array:
	var textos = [];
	for l in panel.find_children("", "Label", true, false):
		textos.append(l.text);
	return textos;

# ---------- Rendimiento M0b: el HUD sin ventana y el manager cacheado ----------

# Main de verdad —su `_process()` es lo que se prueba— con lo justo para que ese `_process()`
# llegue entero: los dos Label del HUD de Main.tscn, el Player con su bolsa, el TileMap y los
# dos managers. Montado en el árbol y con el script puesto DESPUÉS, por lo mismo que
# _new_main_en_arbol(): así no se levanta el menú principal.
func _main_hud(file_data, celdas = {}):
	var main = _new_main_en_arbol(file_data);
	for nombre in ["Label", "Objective"]:
		var l = Label.new();
		l.name = nombre;
		main.add_child(l);
	var tm = main.get_node("TileMap");
	tm.cell_types = celdas.duplicate();
	var pm = _new_pm();
	pm.name = "PollutionManager";
	main.add_child(pm);
	main.pollutionManager = pm;
	var gm = _new_gm(file_data);
	main.add_child(gm);
	main.gameManager = gm;
	# El evaluador del punto muerto, inerte: sin TileMap inyectado no se evalúa, igual que en
	# los escenarios de «Condiciones de Derrota». Lo que aquí se mide es el HUD y el reloj.
	gm.tile_map_node = null;
	return main;

func _test_rendimiento_m0b(file_data):
	print("Rendimiento M0b — el HUD no se construye sin ventana y el manager se cachea");

	# --- 1) La detección: en headless —que es donde corre esta suite— las dos banderas nacen
	# apagadas solas. Es lo que ata `DisplayServer.get_name()` al contrato.
	_check("sin ventana, DisplayServer se llama 'headless'", DisplayServer.get_name() == "headless",
		"se llama '%s'" % DisplayServer.get_name());
	var main_por_defecto = load("res://Main.gd").new();
	_check("sin ventana, Main nace con el HUD apagado", main_por_defecto.render_enabled == false);
	_check("sin ventana, las factorías nacen sin animar",
		load("res://entities/factory/factoryData.gd").animations_enabled == false);
	main_por_defecto.free();

	# --- 2) EL CONTRATO DEL HUD, EN LOS DOS SENTIDOS. Lo que el jugador lee —el texto del
	# objetivo, el aviso de colapso y el mantenimiento reservado— tiene prueba propia en esta
	# suite y no se toca: lo único que este hito apaga es CONSTRUIRLO cuando no hay ventana.
	var main = _main_hud(file_data);
	var bolsa = main.get_node("Player").get_node("Bag");
	# La bolsa se deja a cero a propósito: con el checkpoint 1 sin cubrir, el evaluador reserva
	# su peaje y esa reserva es lo que prueba, más abajo, que update() ha corrido sin ventana.
	main.render_enabled = true;
	main._process(0.016);
	var con_ventana_label = main.get_node("Label").text;
	var con_ventana_obj = main.get_node("Objective").text;
	_check("CON ventana el HUD se construye: la línea de recursos", con_ventana_label.find("wood") >= 0,
		"decía '%s'" % con_ventana_label);
	_check("CON ventana el HUD se construye: el texto del objetivo", con_ventana_obj.length() > 0,
		"decía '%s'" % con_ventana_obj);

	main.get_node("Label").text = "";
	main.get_node("Objective").text = "";
	# La reserva la sincroniza gameManager.update(), que tiene que seguir corriendo SIN ventana:
	# es el evaluador de la partida y no tiene nada que ver con pintar. Se borra a mano para que
	# volver a verla después pruebe que update() ha corrido en esta pasada y no en la anterior.
	bolsa.setReserved({});
	main.render_enabled = false;
	main._process(0.016);
	_check("SIN ventana el HUD no se construye: la línea de recursos", main.get_node("Label").text == "",
		"decía '%s'" % main.get_node("Label").text);
	_check("SIN ventana el HUD no se construye: el texto del objetivo", main.get_node("Objective").text == "",
		"decía '%s'" % main.get_node("Objective").text);
	_check("SIN ventana el evaluador SÍ corre: la reserva se ha vuelto a sincronizar",
		int(bolsa.getReserved("wood")) > 0, "reservado = %d" % int(bolsa.getReserved("wood")));
	# Y el texto que se ahorra es exactamente el mismo que el jugador leería: quien lo pida
	# sigue teniéndolo, que es lo que impide que «no construirlo» se convierta en «no existe».
	_check("SIN ventana el texto del objetivo sigue disponible para quien lo pida",
		main.gameManager.getObjectiveText(bolsa, main.pollutionManager).length() > 0);
	_limpiar([main]);

	# --- 3) 🔴 EL PollutionManager CACHEADO TIENE QUE SOBREVIVIR AL CAMBIO DE ESCENARIO.
	# La suite monta y suelta escenarios en serie y find_child() devuelve el PRIMERO del
	# árbol; una referencia cacheada a un manager LIBERADO no la detecta ningún `!= null`
	# —un nodo liberado se compara igual que null— y la prueba seguiría midiendo contra el
	# escenario anterior.
	var pm1 = _new_pm();
	var fab2 = _new_factory_en_arbol("WoodCutter", Vector2i(4, 4), pm1);
	fab2.initialize("WoodCutter", 1, null, "wood", 1, 3.0);
	fab2._apply_pollution();
	_check("el manager del escenario se encuentra y se cachea",
		fab2._pollution_manager == pm1 and _near(pm1.total_pollution, 3.0),
		"total = %f" % pm1.total_pollution);
	fab2._apply_pollution();
	_check("y el segundo tick lo reutiliza sin volver a buscarlo",
		fab2._pollution_manager == pm1 and _near(pm1.total_pollution, 6.0),
		"total = %f" % pm1.total_pollution);
	# Se suelta el escenario y se monta el siguiente, que es lo que hace la suite entre bloques.
	root.remove_child(pm1);
	pm1.free();
	var pm2 = _new_pm();
	root.add_child(pm2);
	fab2._apply_pollution();
	_check("soltado el escenario, la cache se invalida y ensucia el manager NUEVO",
		fab2._pollution_manager == pm2 and _near(pm2.total_pollution, 3.0),
		"total = %f" % pm2.total_pollution);
	_limpiar([fab2, pm2]);
	print("");


# ---------- Cuellos M1: blocked_reason poblado en los cuatro puntos de salida ----------

func _test_cuellos_m1(file_data):
	print("Cuellos M1 — las cinco razones de bloqueo y su prioridad");
	var script_fab = load("res://entities/factory/factoryData.gd");
	var main = _new_main_en_arbol(file_data);
	var tm = main.get_node("TileMap");
	var bolsa = main.get_node("Player/Bag");
	for y in range(8):
		for x in range(10):
			tm.set_cell(0, Vector2i(x, y), 1, Vector2i(0, 0));
	# El PollutionManager va DENTRO de este main y se suelta con él al final: getPollutionChoke()
	# lo localiza con find_child, que devuelve el PRIMER PollutionManager del árbol, así que dos
	# escenarios vivos a la vez medirían el ahogo sobre el manager equivocado.
	var pm = _new_pm();
	main.add_child(pm);

	# --- El *Hecho cuando* del hito, literal y sobre UNA sola factoría: la misma WoodProcessing
	# pasa por las cuatro razones y por el "" de producir, en el orden en que un jugador las
	# arreglaría. Nada de esto emite por cinta —no hay red en el escenario—, así que el búfer de
	# salida solo sube cuando la prueba lo fuerza y la cuenta no depende del transporte.
	var sierra = _factoria_en_main(main, "WoodProcessing", Vector2i(2, 2), 1, ["wood"], "plank");
	sierra.workers_needed = 1;
	sierra.workers_assigned = 0;
	sierra.update();
	_check("sin workers, blocked_reason == 'workers'",
		sierra.blocked_reason == "workers", "razón '%s'" % sierra.blocked_reason);
	sierra.workers_assigned = 1;
	sierra.update();
	_check("con workers y sin insumo, blocked_reason == 'input'",
		sierra.blocked_reason == "input", "razón '%s'" % sierra.blocked_reason);
	sierra.receiveMaterial("wood", 5);
	sierra.output_buffer = script_fab.OUTPUT_BUFFER_MAX;
	sierra.update();
	_check("con insumo y el búfer lleno, blocked_reason == 'output'",
		sierra.blocked_reason == "output", "razón '%s'" % sierra.blocked_reason);
	sierra.clearOutputBuffer();
	sierra.update();
	# Se comprueba que ha PRODUCIDO de verdad (el insumo baja) y no solo que la razón esté en
	# blanco: clearOutputBuffer() ya la borra, así que mirar el "" a secas no probaría nada.
	_check("y con el búfer vacío produce y limpia la razón: blocked_reason == ''",
		sierra.blocked_reason == "" and int(sierra.input_buffer["wood"]) == 4,
		"razón '%s', insumo %d" % [sierra.blocked_reason, int(sierra.input_buffer["wood"])]);
	# 6,25 de 12,5 es medio ahogo exacto, así que la rampa es 1 de cada 2 ticks y la cuenta no
	# depende de cómo redondee el float.
	pm.addPollution(6.25, Vector2i(2, 2));
	_check("la casilla la ahoga a la mitad", _near(sierra.getPollutionChoke(), 0.5),
		"choke %f" % sierra.getPollutionChoke());
	sierra.update();
	_check("sobre casilla ahogada el tick que no entrega dice 'choke'",
		sierra.blocked_reason == "choke" and int(sierra.input_buffer["wood"]) == 4,
		"razón '%s', insumo %d" % [sierra.blocked_reason, int(sierra.input_buffer["wood"])]);
	sierra.update();
	# El estado parpadea a propósito: el ahogo es una RAMPA, no una parada, y el jugador tiene
	# que ver que la casilla le está costando la mitad de la producción y no que está muerta.
	_check("y al tick siguiente la rampa entrega y la razón vuelve a ''",
		sierra.blocked_reason == "" and int(sierra.input_buffer["wood"]) == 3,
		"razón '%s', insumo %d" % [sierra.blocked_reason, int(sierra.input_buffer["wood"])]);

	# --- La prioridad, con las CUATRO razones cumpliéndose a la vez y quitándolas de una en
	# una. Es la tabla del plan de arriba abajo: cada arreglo destapa la siguiente, y "choke" va
	# el último porque las otras tres lo enmascaran —una factoría sin insumo tampoco produciría
	# con el suelo limpio, así que decirle «limpia» la mandaría al arreglo equivocado—.
	var prio = _factoria_en_main(main, "WoodProcessing", Vector2i(5, 2), 1, ["wood"], "plank");
	pm.addPollution(6.25, Vector2i(5, 2));
	prio.workers_needed = 1;
	prio.workers_assigned = 0;
	prio.output_buffer = script_fab.OUTPUT_BUFFER_MAX;
	prio.update();
	_check("las cuatro a la vez: manda 'workers'",
		prio.blocked_reason == "workers", "razón '%s'" % prio.blocked_reason);
	prio.workers_assigned = 1;
	prio.update();
	_check("con los workers puestos, la siguiente es 'input' (antes que output y choke)",
		prio.blocked_reason == "input", "razón '%s'" % prio.blocked_reason);
	prio.receiveMaterial("wood", 3);
	prio.update();
	_check("con el insumo puesto, la siguiente es 'output' (antes que choke)",
		prio.blocked_reason == "output", "razón '%s'" % prio.blocked_reason);
	prio.clearOutputBuffer();
	prio.update();
	_check("y solo cuando no queda ninguna otra sale 'choke': va el último",
		prio.blocked_reason == "choke", "razón '%s'" % prio.blocked_reason);
	# Y al revés: el ahogo no se queda pegado. Si vuelve a faltar algo más accionable, el estado
	# lo dice — la prioridad se recalcula entera en cada tick, no se acumula.
	prio.workers_assigned = 0;
	prio.update();
	_check("y el 'choke' no se queda pegado: si vuelven a faltar workers, manda 'workers'",
		prio.blocked_reason == "workers", "razón '%s'" % prio.blocked_reason);

	# --- El mapa en silencio cuando todo va bien, que es la mitad del plan que se puede perder
	# sin que nada falle: una factoría sana no debe llevar indicador NUNCA. Sobre suelo limpio
	# choke vale 1.0, así que eff_out >= 1 en todos los ticks y no hay razón que escribir.
	var limpia = _factoria_en_main(main, "WoodCutter", Vector2i(7, 2), 1, null, "wood");
	var manchas = 0;
	for t in range(20):
		limpia.update();
		if limpia.blocked_reason != "":
			manchas += 1;
	_check("una factoría sana no escribe razón en 20 ticks seguidos: el mapa se queda en silencio",
		manchas == 0 and limpia.blocked_reason == "",
		"%d ticks con razón, última '%s'" % [manchas, limpia.blocked_reason]);

	# --- Un Reforester NUNCA recibe 'choke'. Es el contrapeso que hace justa la derrota: si
	# limpiar rindiera menos sobre suelo sucio, saturar el mapa sería irreversible. Aquí se
	# comprueba sobre casilla SATURADA, que es donde el jugador de verdad lo pone.
	var bosque = _factoria_en_main(main, "Reforester", Vector2i(2, 6), 5, null, null, "restoration");
	bosque.pollutionAmount = -4.0;
	pm.addPollution(100.0, Vector2i(2, 6));
	_check("la casilla del Reforester está saturada del todo",
		_near(pm.getCellPollution(Vector2i(2, 6)), 1.0),
		"celda %f" % pm.getCellPollution(Vector2i(2, 6)));
	_check("y aun así no se ahoga: getPollutionChoke() vale 1.0 sobre suelo saturado",
		_near(bosque.getPollutionChoke(), 1.0), "choke %f" % bosque.getPollutionChoke());
	var sucio_antes = pm.total_pollution;
	var manchas_bosque = 0;
	for t in range(20):
		bosque.update();
		if bosque.blocked_reason != "":
			manchas_bosque += 1;
	_check("un Reforester sobre casilla saturada NUNCA recibe 'choke' y sigue limpiando",
		manchas_bosque == 0 and pm.total_pollution < sucio_antes,
		"%d ticks con razón ('%s'), contaminación %f -> %f" % [manchas_bosque,
			bosque.blocked_reason, sucio_antes, pm.total_pollution]);
	# La exención es del ahogo y del búfer, NO de la prioridad 1: la rama de restauración sale
	# después de isActive(), así que un Reforester sin workers sí dice 'workers'. Hoy el JSON no
	# le pide ninguno, pero el orden tiene que ser el mismo para todos o la tabla del plan
	# tendría una excepción que nadie ha escrito.
	bosque.workers_needed = 1;
	bosque.workers_assigned = 0;
	bosque.update();
	_check("pero la exención no lo saca de la prioridad 1: sin workers dice 'workers'",
		bosque.blocked_reason == "workers", "razón '%s'" % bosque.blocked_reason);

	# --- El almacén no recibe NINGUNA razón: no produce, así que no tiene insumo que le falte,
	# ni búfer de salida que se le llene, ni output que ahogar. Sale por su rama antes de todo
	# eso y con la razón en blanco.
	var almacen = _factoria_en_main(main, "Storage", Vector2i(8, 6), 1, null, null, "storage");
	pm.addPollution(100.0, Vector2i(8, 6));
	almacen.output_buffer = script_fab.OUTPUT_BUFFER_MAX;
	almacen.receiveMaterial("wood", 4);
	var wood_antes = bolsa.getQuantity("wood");
	almacen.update(bolsa);
	_check("el almacén sobre casilla saturada y con el búfer forzado no tiene razón, y vuelca",
		almacen.blocked_reason == "" and bolsa.getQuantity("wood") == wood_antes + 4,
		"razón '%s', bolsa %d -> %d" % [almacen.blocked_reason, wood_antes,
			bolsa.getQuantity("wood")]);
	var manchas_alm = 0;
	for t in range(20):
		almacen.update(bolsa);
		if almacen.blocked_reason != "":
			manchas_alm += 1;
	_check("y tampoco la tiene cuando no le llega nada que mover: 20 ticks en blanco",
		manchas_alm == 0, "%d ticks con razón ('%s')" % [manchas_alm, almacen.blocked_reason]);
	# Lo de arriba solo vale mientras el JSON no le pida workers: la prioridad 1 es de todos y
	# un Storage con workers_needed > 0 diría 'workers' como cualquiera.
	_check("y el JSON lo respalda: el almacén no pide workers, así que ni la prioridad 1 le toca",
		int(file_data["Factories"]["Storage"].get("workers_needed", 0)) == 0,
		"workers_needed %d" % int(file_data["Factories"]["Storage"].get("workers_needed", 0)));

	_limpiar([main]);

# ---------- Cuellos M2: el StatusOverlay ----------

# Lo que este bloque PUEDE afirmar en headless es que el nodo existe, por dónde sale y qué
# pinta; lo que no puede es que se VEA, que es la verificación jugada del hito. Aun así la
# mitad estructural es la que más vale: el z_index es todo el plan —dibujar desde el _draw()
# del TileMap dejó invisibles 8 de los 11 tipos de casilla— y sin prueba se vuelve a romper en
# silencio, que es justo lo que pasó con el 2 ya ocupado por el BeltOverlay.
func _test_cuellos_m2(file_data):
	print("Cuellos M2 — el StatusOverlay: por dónde sale el estado y qué pinta");
	var main = _new_main_en_arbol(file_data);
	var tm = main.get_node("TileMap");
	for y in range(8):
		for x in range(10):
			tm.set_cell(0, Vector2i(x, y), 1, Vector2i(0, 0));
	var pm = _new_pm();
	main.add_child(pm);
	# La red se monta solo para tener su BeltOverlay de verdad colgando del MISMO TileMap: el
	# choque del z_index no se puede afirmar contra un número escrito a mano aquí.
	var red = load("res://managers/beltNetwork.gd").new();
	red.name = "BeltNetwork";
	main.add_child(red);
	red.initialize(tm, main.factoryArray, file_data);

	# --- Los tres canvas items, y su orden.
	var estado = tm.get_node_or_null("StatusOverlay");
	var cintas = tm.get_node_or_null("BeltOverlay");
	var tinte = tm.get_node_or_null("TintOverlay");
	_check("el estado sale por un canvas item propio hijo del TileMap, no por su _draw()",
		estado != null and estado is Node2D, "overlay = %s" % str(estado));
	_check("y crearlo no se ha llevado por delante el TintOverlay",
		tinte != null and tinte is Node2D and tinte.z_index == 1,
		"tinte = %s" % str(tinte));
	_check("el StatusOverlay va al z_index 3", estado != null and estado.z_index == 3,
		"z_index = %s" % (str(estado.z_index) if estado != null else "sin overlay"));
	# 🔴 La razón de que sea 3 y no el 2 que el plan pedía: el 2 ya es del BeltOverlay, y con
	# los dos empatados el orden lo decidiría el árbol. Una factoría parada con una cinta
	# cruzándole la casilla tiene que seguir enseñando por qué está parada.
	_check("y por encima del BeltOverlay, que es quien ocupa el 2",
		estado != null and cintas != null and estado.z_index > cintas.z_index,
		"estado %s vs cintas %s" % [str(estado), str(cintas)]);
	_check("el overlay sabe a quién preguntarle qué pintar",
		estado != null and estado.tile_map == tm);

	# --- Los colores: las claves son EXACTAMENTE los valores que update() escribe en
	# blocked_reason —las cuatro de M1 y "storm" desde Eventos Climáticos M3—. Una razón sin
	# color se dibujaría en negro o no se dibujaría, y una clave de más sería una razón que
	# nadie escribe.
	var script_tm = load("res://entities/tilemap/tileMap.gd");
	var claves = script_tm.STATUS_COLORS.keys();
	claves.sort();
	_check("STATUS_COLORS tiene las cinco razones y ninguna más",
		claves == ["choke", "input", "output", "storm", "workers"], "claves = %s" % str(claves));
	var todos_color = true;
	var distintos = {};
	for k in script_tm.STATUS_COLORS:
		if not (script_tm.STATUS_COLORS[k] is Color):
			todos_color = false;
		distintos[str(script_tm.STATUS_COLORS[k])] = true;
	_check("los cinco son Color y ninguno se repite: cinco razones, cinco lecturas",
		todos_color and distintos.size() == 5, "%d colores distintos" % distintos.size());

	# --- Sin lista no peta. No es un caso raro: la suite monta el TileMap
	# a mano y no llaman nunca a setFactories(), así que el nodo tiene que aguantarlo.
	var spy = SpyCanvas.new();
	tm.draw_status(spy, null);
	tm.draw_status(spy, []);
	_check("draw_status() aguanta el array nulo y el vacío sin pintar nada",
		spy.polys.is_empty(), "%d polígonos" % spy.polys.size());
	_check("y el TileMap nace con la lista vacía, no con null",
		tm._factory_array is Array and tm._factory_array.is_empty());

	# --- El *Hecho cuando* del hito, en lo que headless sí alcanza: una WoodProcessing sin
	# cinta de entrada lleva el marcador naranja, y deja de llevarlo en cuanto le llega
	# madera. Lo que no se puede afirmar aquí es que se vea en pantalla.
	var sierra = _factoria_en_main(main, "WoodProcessing", Vector2i(3, 3), 1, ["wood"], "plank");
	sierra.workers_needed = 1;
	sierra.workers_assigned = 1;
	tm.setFactories(main.factoryArray);
	sierra.update();
	spy = SpyCanvas.new();
	tm.draw_status(spy, tm._factory_array);
	_check("una WoodProcessing sin insumo está parada por 'input'",
		sierra.blocked_reason == "input", "razón '%s'" % sierra.blocked_reason);
	# Dos polígonos y no uno: el borde oscuro va debajo del color para que el mismo marcador
	# se lea sobre suelo claro y sobre una casilla teñida de rojo por la contaminación.
	_check("y el mapa le pinta su marcador: borde y relleno",
		spy.polys.size() == 2, "%d polígonos" % spy.polys.size());
	_check("del naranja de 'input', opaco y no al 45% como el tinte",
		spy.polys.size() == 2 and spy.polys[1]["color"] == script_tm.STATUS_COLORS["input"]
		and spy.polys[1]["color"].a == 1.0,
		"color = %s" % (str(spy.polys[1]["color"]) if spy.polys.size() == 2 else "sin marcador"));

	# El marcador es un icono en el vértice de ARRIBA, no el rombo entero: el rombo ya lo usan
	# el tinte del tipo y el rojo de la contaminación, y repintarlo en cuatro colores más
	# volvería el mapa ilegible.
	var puntos = spy.polys[1]["puntos"] if spy.polys.size() == 2 else PackedVector2Array();
	var centro = Vector2.ZERO;
	for punto in puntos:
		centro += punto;
	if puntos.size() > 0:
		centro /= puntos.size();
	var vertice = tm.map_to_local(Vector2i(3, 3)) + Vector2(0, -16.0);
	_check("centrado en el vértice superior de la celda, no en la celda",
		puntos.size() == 4 and centro.distance_to(vertice) < 0.01,
		"centro %s contra vértice %s" % [str(centro), str(vertice)]);
	var ancho = 0.0;
	var alto = 0.0;
	for punto in puntos:
		ancho = max(ancho, abs(punto.x - centro.x) * 2.0);
		alto = max(alto, abs(punto.y - centro.y) * 2.0);
	_check("y es pequeño y más alto que ancho: no se confunde con el rombo (64x32)",
		ancho < 32.0 and alto < 32.0 and alto > ancho, "%.1f x %.1f" % [ancho, alto]);

	# --- En cuanto le llega madera y produce, el icono desaparece. Es la segunda mitad del
	# *Hecho cuando*: el mapa en silencio significa que todo va.
	sierra.receiveMaterial("wood", 5);
	sierra.update();
	spy = SpyCanvas.new();
	tm.draw_status(spy, tm._factory_array);
	_check("y en cuanto le llega madera y produce, el marcador desaparece",
		sierra.blocked_reason == "" and spy.polys.is_empty(),
		"razón '%s', %d polígonos" % [sierra.blocked_reason, spy.polys.size()]);

	# --- Las cuatro razones, cada una con su color y una sola vez. Que el campo se pueble
	# bien ya lo prueba «Cuellos M1»: aquí se afirma el reparto de colores, así que las cuatro
	# se ponen a mano sobre cuatro factorías.
	var paradas = [
		_factoria_en_main(main, "WoodCutter", Vector2i(5, 3), 1, null, "wood"),
		_factoria_en_main(main, "WoodCutter", Vector2i(6, 3), 1, null, "wood"),
		_factoria_en_main(main, "WoodCutter", Vector2i(7, 3), 1, null, "wood"),
		_factoria_en_main(main, "WoodCutter", Vector2i(8, 3), 1, null, "wood"),
	];
	var razones = ["workers", "input", "output", "choke"];
	for i in range(4):
		paradas[i].blocked_reason = razones[i];
	spy = SpyCanvas.new();
	tm.draw_status(spy, tm._factory_array);
	var rellenos = [];
	for i in range(spy.polys.size()):
		if i % 2 == 1:
			rellenos.append(spy.polys[i]["color"]);
	var esperados = [];
	for r in razones:
		esperados.append(script_tm.STATUS_COLORS[r]);
	_check("las cuatro razones pintan sus cuatro colores, y la que produce ninguno",
		spy.polys.size() == 8 and rellenos == esperados,
		"%d polígonos, colores %s" % [spy.polys.size(), str(rellenos)]);

	# --- La lista va VIVA: lo que se inyecta es el array de Main, que `placer` muta al
	# construir y _demolish_at_cell() al demoler. Con una copia, el icono de una demolida se
	# quedaría flotando sobre la casilla vacía.
	_check("lo inyectado es el MISMO array, no una copia",
		is_same(tm._factory_array, main.factoryArray));
	main.factoryArray.erase(paradas[0]);
	spy = SpyCanvas.new();
	tm.draw_status(spy, tm._factory_array);
	_check("así que sacar una factoría de la lista le quita el marcador sin reinyectar nada",
		spy.polys.size() == 6, "%d polígonos" % spy.polys.size());
	# Y una razón que nadie ha declarado no pinta: mejor un mapa callado que un marcador
	# negro que el jugador no sabe leer.
	paradas[1].blocked_reason = "inventada";
	spy = SpyCanvas.new();
	tm.draw_status(spy, tm._factory_array);
	_check("una razón sin color en STATUS_COLORS no pinta nada",
		spy.polys.size() == 4, "%d polígonos" % spy.polys.size());

	_limpiar([main]);

	# --- El cableado: sin esta línea de Main._start_game() el overlay dibuja sobre una lista
	# vacía para siempre y el hito entero es inerte. Se comprueba sobre la run de verdad, que
	# es el único sitio donde se puede afirmar.
	var real = _main_para_run();
	real._start_game("standard");
	var tm_real = real.get_node("TileMap");
	_check("_start_game() inyecta la línea de producción viva en el TileMap",
		is_same(tm_real._factory_array, real.factoryArray),
		"inyectado = %s" % str(tm_real._factory_array));
	_check("y el mapa de la run nace con su StatusOverlay por encima del BeltOverlay",
		tm_real.get_node_or_null("StatusOverlay") != null
		and tm_real.get_node_or_null("BeltOverlay") != null
		and tm_real.get_node("StatusOverlay").z_index > tm_real.get_node("BeltOverlay").z_index);
	# placer y mapLoader son nodos que Main nunca añade al árbol: se sueltan a mano.
	_limpiar([real.placer, real.mapLoader, real]);

# ---------- Cuellos M3: la razón en palabras, en las dos superficies de detalle ----------

# La línea de parada que pinta una superficie, o null si está callada. Se busca por el prefijo
# y no por el texto exacto a propósito: la mitad del *Hecho cuando* es que la factoría que
# produce NO diga nada de esto, y comparar contra una frase concreta no probaría que no hay
# otra distinta. Se mira `visible` porque el panel esconde su etiqueta en vez de borrarla.
func _linea_de_parada(superficie):
	for lbl in superficie.find_children("", "Label", true, false):
		if lbl.visible and lbl.text.begins_with("⚠ Parada"):
			return lbl;
	return null;

# El tooltip de esa factoría, montado y colgado del árbol. Nace y muere con el ratón, así que
# en las pruebas se monta uno nuevo por cada estado que se quiere mirar: es exactamente lo que
# hace el juego al entrar y salir de la casilla.
func _tooltip_de(fab, file_data, basura):
	var tip = load("res://ui/factoryTooltip.gd").new();
	root.add_child(tip);
	tip.initialize(fab, file_data);
	basura.append(tip);
	return tip;

func _test_cuellos_m3(file_data):
	print("Cuellos M3 — la razón de parada, en palabras, en el tooltip y en el panel");
	var script_tm = load("res://entities/tilemap/tileMap.gd");
	var blocked = load("res://ui/blockedReason.gd");
	var basura = [];
	var main = _new_main_en_arbol(file_data);
	var tm = main.get_node("TileMap");
	var bolsa = main.get_node("Player/Bag");
	for y in range(8):
		for x in range(10):
			tm.set_cell(0, Vector2i(x, y), 1, Vector2i(0, 0));
	# El PollutionManager va DENTRO de este main, por lo mismo que en «Cuellos M1»:
	# getPollutionChoke() lo busca con find_child y cogería el de otro escenario vivo.
	var pm = _new_pm();
	main.add_child(pm);

	# --- El vocabulario: una frase por razón (las cuatro de M1 y "storm" desde Eventos
	# Climáticos M3), y los MISMOS colores que el mapa.
	var claves = blocked.TEXTS.keys();
	claves.sort();
	_check("hay una frase por razón y ninguna de más: las mismas cinco que escribe update()",
		claves == ["choke", "input", "output", "storm", "workers"], "claves = %s" % str(claves));
	var frases_ok = true;
	var distintas = {};
	for k in blocked.TEXTS:
		var frase = blocked.TEXTS[k];
		# Ni "<null>" ni "null": la trampa que pintó «Produce: <null>» durante meses en este
		# mismo fichero era comparar contra un texto, y una frase que lo contenga la invita.
		if frase == "" or frase.find("null") >= 0:
			frases_ok = false;
		distintas[frase] = true;
	_check("las cinco frases dicen algo, son distintas y ninguna arrastra un 'null'",
		frases_ok and distintas.size() == 5, "%d frases distintas" % distintas.size());
	var mismo_color = true;
	for k in blocked.TEXTS:
		if blocked.color_for(k) != script_tm.STATUS_COLORS[k]:
			mismo_color = false;
	_check("y se escriben con el color del marcador del mapa, no con uno propio",
		mismo_color, "colores = %s" % str(script_tm.STATUS_COLORS));
	_check("una razón que nadie ha declarado no tiene frase: la superficie se calla",
		blocked.text_for("inventada") == "" and blocked.text_for("") == "");

	# --- El *Hecho cuando*, literal: el hover sobre una factoría parada dice por qué en una
	# frase, y sobre una que produce no dice nada de esto.
	var sierra = _factoria_en_main(main, "WoodProcessing", Vector2i(2, 2), 1, ["wood"], "plank");
	sierra.workers_needed = 1;
	sierra.workers_assigned = 1;
	sierra.update();
	var tip = _tooltip_de(sierra, file_data, basura);
	var linea = _linea_de_parada(tip);
	_check("el hover sobre una serrería sin madera dice por qué está parada, en una frase",
		sierra.blocked_reason == "input" and linea != null
		and linea.text == blocked.TEXTS["input"],
		"razón '%s', línea '%s'" % [sierra.blocked_reason,
			linea.text if linea != null else "ninguna"]);
	_check("y con el naranja de 'input', el mismo del marcador del mapa",
		linea != null and linea.get_theme_color("font_color") == script_tm.STATUS_COLORS["input"],
		"color = %s" % (str(linea.get_theme_color("font_color")) if linea != null else "sin línea"));
	sierra.receiveMaterial("wood", 5);
	sierra.update();
	tip = _tooltip_de(sierra, file_data, basura);
	_check("y en cuanto le llega madera y produce, el hover NO dice nada de esto",
		sierra.blocked_reason == "" and _linea_de_parada(tip) == null,
		"razón '%s', línea '%s'" % [sierra.blocked_reason,
			_linea_de_parada(tip).text if _linea_de_parada(tip) != null else "ninguna"]);

	# --- Las cuatro razones, cada una con su frase. Que el campo se pueble bien ya lo prueba
	# «Cuellos M1» y que se pinte en el mapa «Cuellos M2»: aquí se afirma la redacción.
	var razones = ["input", "output", "choke"];
	for razon in razones:
		var fab = _factoria_en_main(main, "WoodCutter", Vector2i(5, 2), 1, null, "wood");
		fab.blocked_reason = razon;
		var t = _tooltip_de(fab, file_data, basura);
		var l = _linea_de_parada(t);
		_check("la razón '%s' se lee en el hover con su frase y su color" % razon,
			l != null and l.text == blocked.TEXTS[razon]
			and l.get_theme_color("font_color") == script_tm.STATUS_COLORS[razon],
			"línea '%s'" % (l.text if l != null else "ninguna"));
	var rara = _factoria_en_main(main, "WoodCutter", Vector2i(6, 2), 1, null, "wood");
	rara.blocked_reason = "inventada";
	_check("y una razón sin frase no pinta línea, igual que no pinta marcador en el mapa",
		_linea_de_parada(_tooltip_de(rara, file_data, basura)) == null);

	# --- La prioridad 1 se lee VIVA, y por eso no hay dos avisos de lo mismo. El aviso viejo
	# `⚠ INACTIVA (sin workers)` decía este mismo estado en rojo y en otro sitio: M3 lo
	# sustituye, no lo acompaña.
	var sin_gente = _factoria_en_main(main, "MetaFactory", Vector2i(8, 2), 1, ["plank"], "factory_token");
	sin_gente.workers_needed = 2;
	sin_gente.workers_assigned = 0;
	var tip_sin = _tooltip_de(sin_gente, file_data, basura);
	_check("una factoría sin workers dice «le faltan workers» sin haber tickeado todavía",
		sin_gente.blocked_reason == "" and _linea_de_parada(tip_sin) != null
		and _linea_de_parada(tip_sin).text == blocked.TEXTS["workers"],
		"razón guardada '%s'" % sin_gente.blocked_reason);
	_check("y ya no sale además el viejo «⚠ INACTIVA (sin workers)»: un solo aviso por estado",
		not _tiene_etiqueta(tip_sin, "⚠ INACTIVA (sin workers)"));
	# Y al revés: el "workers" del tick anterior con la factoría ya activa está caducado. Sin
	# esta mitad, darle el worker que le falta dejaría la frase pegada un tick entero.
	sin_gente.workers_assigned = 2;
	sin_gente.blocked_reason = "workers";
	_check("el 'workers' del tick anterior con la factoría ya activa no se enseña: ha caducado",
		blocked.reason_now(sin_gente) == ""
		and _linea_de_parada(_tooltip_de(sin_gente, file_data, basura)) == null);

	# --- Ni el Reforester ni el almacén dicen nunca nada: uno no se ahoga jamás y el otro no
	# produce. Lo garantiza el `""` de update(), pero es la clase de silencio que se rompe sin
	# que nada falle.
	var bosque = _factoria_en_main(main, "Reforester", Vector2i(2, 6), 5, null, null, "restoration");
	bosque.pollutionAmount = -4.0;
	pm.addPollution(100.0, Vector2i(2, 6));
	bosque.update();
	_check("un Reforester sobre casilla saturada no dice nada de parada",
		bosque.blocked_reason == "" and _linea_de_parada(_tooltip_de(bosque, file_data, basura)) == null,
		"razón '%s'" % bosque.blocked_reason);
	var almacen = _factoria_en_main(main, "Storage", Vector2i(8, 6), 1, null, null, "storage");
	almacen.update(bolsa);
	_check("y el almacén tampoco: no produce, así que no tiene por qué pararse",
		almacen.blocked_reason == "" and _linea_de_parada(_tooltip_de(almacen, file_data, basura)) == null,
		"razón '%s'" % almacen.blocked_reason);

	# --- El panel, que es la superficie delicada: se monta UNA vez y vive hasta que se cierra.
	var parada = _factoria_en_main(main, "WoodProcessing", Vector2i(4, 4), 1, ["wood"], "plank");
	parada.workers_needed = 1;
	parada.workers_assigned = 1;
	parada.update();
	var panel = load("res://ui/factoryPanel.gd").new();
	root.add_child(panel);
	panel.initialize(parada, file_data, Vector2(640, 360), bolsa);
	basura.append(panel);
	var l_panel = _linea_de_parada(panel);
	_check("el panel de una factoría parada dice la MISMA frase que el hover, no otra",
		l_panel != null and l_panel.text == blocked.TEXTS["input"]
		and l_panel.get_theme_color("font_color") == script_tm.STATUS_COLORS["input"],
		"línea '%s'" % (l_panel.text if l_panel != null else "ninguna"));

	# El `_process()`: repinta cuando la razón cambia. Es lo que una etiqueta estática no puede
	# hacer, y sin ello la frase se quedaría pegada en cuanto llegue la madera.
	parada.blocked_reason = "output";
	panel._process(0.0);
	_check("y el panel repinta la línea cuando la razón cambia, sin cerrarlo ni remontarlo",
		_linea_de_parada(panel) != null
		and _linea_de_parada(panel).text == blocked.TEXTS["output"]
		and _linea_de_parada(panel).get_theme_color("font_color") == script_tm.STATUS_COLORS["output"],
		"línea '%s'" % (_linea_de_parada(panel).text if _linea_de_parada(panel) != null else "ninguna"));

	# ...y NO repinta cuando no cambia. Se firma la etiqueta a mano: si el frame siguiente la
	# reescribiera, la firma desaparecería. Repintar por frame obliga a remedir el panel entero
	# y a recortarlo contra la pantalla para escribir siempre lo mismo.
	_linea_de_parada(panel).text = "⚠ Parada: CENTINELA";
	panel._process(0.0);
	panel._process(0.0);
	_check("y no la repinta mientras la razón no cambie: la firma sigue ahí tras dos frames",
		_linea_de_parada(panel) != null
		and _linea_de_parada(panel).text == "⚠ Parada: CENTINELA",
		"línea '%s'" % (_linea_de_parada(panel).text if _linea_de_parada(panel) != null else "ninguna"));
	parada.blocked_reason = "input";
	panel._process(0.0);
	_check("pero el siguiente cambio de razón sí la recupera",
		_linea_de_parada(panel) != null
		and _linea_de_parada(panel).text == blocked.TEXTS["input"]);

	# Cuando produce, la línea se ESCONDE en vez de desmontarse: aparecer y desaparecer es lo
	# que cambia el alto del panel, y remedirlo sale más barato que recrear la etiqueta.
	parada.blocked_reason = "";
	panel._process(0.0);
	_check("cuando la factoría produce, el panel se calla: la etiqueta sigue montada y oculta",
		_linea_de_parada(panel) == null and panel._blocked_label != null
		and not panel._blocked_label.visible);

	# --- El worker se asigna con los botones de ESTE panel, así que la frase tiene que caerse
	# en la pulsación y no un tick (ni un frame) después: si no, el panel se contradiría con el
	# «Workers: 1/1» en verde que pinta dos líneas más abajo.
	var floja = _factoria_en_main(main, "MetaFactory", Vector2i(6, 6), 1, ["plank"], "factory_token");
	floja.workers_needed = 1;
	floja.workers_assigned = 0;
	floja.update();
	var panel_w = load("res://ui/factoryPanel.gd").new();
	root.add_child(panel_w);
	panel_w.initialize(floja, file_data, Vector2(640, 360), bolsa);
	basura.append(panel_w);
	_check("el panel de una factoría sin workers dice que le faltan",
		_linea_de_parada(panel_w) != null
		and _linea_de_parada(panel_w).text == blocked.TEXTS["workers"],
		"línea '%s'" % (_linea_de_parada(panel_w).text if _linea_de_parada(panel_w) != null else "ninguna"));
	var botones = panel_w.find_children("", "Button", true, false);
	botones[1].pressed.emit();
	_check("y darle el worker que falta con el botón del panel borra la frase EN EL ACTO",
		floja.isActive() and floja.blocked_reason == "workers"
		and _linea_de_parada(panel_w) == null,
		"asignados %d, razón guardada '%s'" % [floja.workers_assigned, floja.blocked_reason]);

	# --- Y el panel aguanta que le demuelan la factoría con él abierto: Main._demolish_at_cell()
	# cierra el tooltip pero NO este panel, así que aquí llega una factoría liberada.
	main.factoryArray.erase(floja);
	main.remove_child(floja);
	floja.free();
	panel_w._process(0.0);
	panel_w._process(0.0);
	_check("con la factoría demolida y el panel abierto no peta, y la línea desaparece",
		not panel_w.is_queued_for_deletion() and _linea_de_parada(panel_w) == null
		and panel_w._factory_node == null);

	_limpiar(basura);
	_limpiar([main]);

# ---------- Cuellos M4: el tooltip tampoco se repinta solo ----------

# Cuántos tooltips cuelgan de ese Main. Es la trampa de `queue_free()`, que es diferido: si
# reconstruir no sacara el viejo del árbol con `remove_child()` antes, el nuevo entraría
# renombrado a `@CanvasLayer@N` y `get_node("FactoryTooltip")` seguiría encontrando al muerto
# para siempre. Se cuentan por su método y no por su nombre justo porque el renombrado es lo
# que se quiere detectar.
func _tooltips_colgando(main):
	var n = 0;
	for hijo in main.get_children():
		if hijo.has_method("update_position"):
			n += 1;
	return n;

func _test_cuellos_m4(file_data):
	print("Cuellos M4 — el tooltip se repinta con el ratón quieto");
	var script_tm = load("res://entities/tilemap/tileMap.gd");
	var blocked = load("res://ui/blockedReason.gd");
	var main = _new_main_en_arbol(file_data);
	var tm = main.get_node("TileMap");
	# El PollutionManager va DENTRO de este main, por lo mismo que en «Cuellos M1» y «M3»:
	# _apply_pollution() lo busca con find_child y cogería el de otro escenario todavía vivo.
	var pm = _new_pm();
	main.add_child(pm);

	# La celda que el cursor «tiene debajo» no se inventa: se le pregunta al TileMap igual que
	# hace `_update_hover_tooltip()`, y la factoría se coloca ahí. Es la forma de probar el hover
	# sin ratón —en headless no se puede mover—, y además deja el ratón QUIETO por construcción,
	# que es justo la condición del *Hecho cuando*.
	var bajo_el_raton = tm.local_to_map(tm.get_local_mouse_position());
	var sierra = _factoria_en_main(main, "WoodProcessing", bajo_el_raton, 1, ["wood"], "plank");
	sierra.workers_needed = 1;
	sierra.workers_assigned = 1;
	sierra.update();

	main._update_hover_tooltip();
	var tip = main.get_node_or_null("FactoryTooltip");
	_check("el primer frame con el cursor encima monta el tooltip y dice por qué está parada",
		tip != null and _linea_de_parada(tip) != null
		and _linea_de_parada(tip).text == blocked.TEXTS["input"],
		"razón '%s', línea '%s'" % [sierra.blocked_reason,
			_linea_de_parada(tip).text if tip != null and _linea_de_parada(tip) != null else "ninguna"]);
	_check("y Main se apunta la razón con la que lo pintó, para poder compararla luego",
		main._hovered_reason == "input", "guardada '%s'" % main._hovered_reason);

	# --- Mientras la razón no cambie NO se reconstruye. Se mira el id de instancia y no el
	# texto: rehacer un CanvasLayer con una etiqueta por línea sesenta veces por segundo para
	# escribir lo mismo es el gasto que `ui/factoryPanel.gd` ya decidió no hacer.
	var id_original = tip.get_instance_id();
	main._update_hover_tooltip();
	main._update_hover_tooltip();
	_check("con el ratón quieto y la razón igual no se reconstruye: sigue siendo el mismo nodo",
		main.get_node_or_null("FactoryTooltip") != null
		and main.get_node_or_null("FactoryTooltip").get_instance_id() == id_original);

	# --- El *Hecho cuando*, primera mitad: la línea se CAE al volver a producir, sin mover el
	# cursor. Es exactamente lo que la etiqueta estática de M3 no sabía hacer.
	sierra.receiveMaterial("wood", 5);
	sierra.update();
	main._update_hover_tooltip();
	var tip2 = main.get_node_or_null("FactoryTooltip");
	_check("al volver a producir el tooltip se rehace solo y la línea de «Parada» desaparece",
		tip2 != null and tip2.get_instance_id() != id_original
		and _linea_de_parada(tip2) == null and main._hovered_reason == "",
		"razón '%s', guardada '%s'" % [sierra.blocked_reason, main._hovered_reason]);
	_check("y sin dejar dos tooltips peleándose por el nombre: cuelga exactamente uno",
		_tooltips_colgando(main) == 1, "%d tooltips" % _tooltips_colgando(main));

	# --- Y la otra mitad: se para con el cursor encima y la línea APARECE, con la frase y el
	# color del marcador que esa misma casilla lleva pintado. Es la contradicción que destapó la
	# verificación jugada, al revés.
	sierra.blocked_reason = "choke";
	main._update_hover_tooltip();
	var l3 = _linea_de_parada(main.get_node_or_null("FactoryTooltip"));
	_check("al pararse con el cursor quieto la línea aparece sola, con la frase y el color del mapa",
		l3 != null and l3.text == blocked.TEXTS["choke"]
		and l3.get_theme_color("font_color") == script_tm.STATUS_COLORS["choke"],
		"línea '%s'" % (l3.text if l3 != null else "ninguna"));

	# --- Se compara contra `reason_now()` y NO contra `blocked_reason` a pelo: quitarle el
	# worker cambia lo que se enseña sin tocar el campo, y el tooltip tiene que enterarse o
	# diría algo distinto del panel, que lee por ese mismo sitio.
	sierra.workers_assigned = 0;
	main._update_hover_tooltip();
	var l4 = _linea_de_parada(main.get_node_or_null("FactoryTooltip"));
	_check("quitarle el worker repinta el tooltip aunque `blocked_reason` siga diciendo 'choke'",
		l4 != null and l4.text == blocked.TEXTS["workers"] and sierra.blocked_reason == "choke",
		"línea '%s', campo '%s'" % [l4.text if l4 != null else "ninguna", sierra.blocked_reason]);

	# --- Con el panel abierto no hay tooltip, y M4 no toca esa regla. El panel de mentira basta:
	# `_factory_panel_open()` solo le pregunta al árbol por el nombre.
	var falso_panel = CanvasLayer.new();
	falso_panel.name = "FactoryPanel";
	main.add_child(falso_panel);
	main._update_hover_tooltip();
	_check("con el panel abierto el hover se calla, y la razón guardada se va con el tooltip",
		main.get_node_or_null("FactoryTooltip") == null
		and main._hovered_factory == null and main._hovered_reason == "",
		"guardada '%s'" % main._hovered_reason);
	main.remove_child(falso_panel);
	falso_panel.free();

	# --- Cerrado el panel, el hover vuelve por el camino normal y con la razón de AHORA, no con
	# la de antes de abrirlo.
	main._update_hover_tooltip();
	_check("cerrado el panel vuelve a montarse, y con la razón de ahora",
		main.get_node_or_null("FactoryTooltip") != null and main._hovered_reason == "workers",
		"guardada '%s'" % main._hovered_reason);

	# --- Y `_clear_hover()` deja el estado a cero. Si la razón sobreviviera, volver a la MISMA
	# factoría compararía contra una de hace rato: o repinta de más, o no repinta nunca.
	main._clear_hover();
	_check("_clear_hover() deja factoría, tooltip y razón a cero: nada caducado con que comparar",
		main._hovered_factory == null and main._hovered_reason == ""
		and main.get_node_or_null("FactoryTooltip") == null and _tooltips_colgando(main) == 0,
		"guardada '%s', %d tooltips" % [main._hovered_reason, _tooltips_colgando(main)]);

	_limpiar([main]);

# ---------- Cuellos M5: el guardia de validez de la rama del ratón quieto ----------
#
# La rama de M4 lee `_hovered_factory` cada frame. Por el camino normal nunca le llega un nodo
# liberado —`_demolish_at_cell()` lo anula y `_get_factory_at_cell()` no devuelve liberados—, así
# que esto prueba el guardia y no el camino: se le pone a mano una factoría ya liberada, que es
# el estado del que el panel SÍ se protege desde la enmienda de M3. Sin `is_instance_valid()`,
# `reason_now()` recibe un nodo muerto.
func _test_cuellos_m5_guardia(file_data):
	print("Cuellos M5 — el hover aguanta una factoría liberada");
	var main = _new_main_de_prueba(file_data);
	var fab = _new_factory("WoodCutter", Vector2i(2, 2));
	main.add_child(fab);
	main.factoryArray.append(fab);
	main._hovered_factory = fab;
	main._hovered_reason = "output";
	# Se libera por debajo, sin pasar por _demolish_at_cell(): es justo el estado que el camino
	# normal no sabe producir y del que el guardia tiene que salvar.
	main.factoryArray.erase(fab);
	main.remove_child(fab);
	fab.free();
	main._update_hover_tooltip();
	_check("con la factoría liberada bajo el cursor, _update_hover_tooltip() no revienta",
		true);
	_check("y deja el hover a cero en vez de arrastrar un nodo muerto",
		main._hovered_factory == null and main._hovered_reason == "",
		"factoría %s, razón '%s'" % [str(main._hovered_factory), main._hovered_reason]);

	_limpiar([main]);

# ---------- regresión: las productoras no cambiaron ----------

func _test_regresion_produccion():
	print("Regresión — las factorías de producción no se han tocado");
	var pm = _new_pm();
	var propia = Vector2i(7, 7);
	var vecina = Vector2i(8, 8);
	pm.addPollution(1.0, vecina);
	var f = _new_factory_en_arbol("WoodCutter", propia, pm);
	f.factory_type = "production";
	f.pollutionAmount = 3.0;
	f._apply_pollution();

	_check("una productora ensucia SOLO su celda", _near(pm.pollution_per_cell[propia], 3.0),
		"celda propia = %f" % pm.pollution_per_cell.get(propia, -1.0));
	_check("una productora no ensucia a sus vecinas", _near(pm.pollution_per_cell[vecina], 1.0),
		"vecina = %f" % pm.pollution_per_cell[vecina]);
	_check("el global sube lo mismo que antes", _near(pm.total_pollution, 4.0),
		"global = %f" % pm.total_pollution);

	_limpiar([f, pm]);

# ---------- Tensión M8: los cuatro cabos sueltos ----------

# El verde del suelo llano de forest_01, medido sobre una captura real al cerrar M3.5. Es el
# fondo contra el que se lee cualquier tinte de casilla.
const SUELO_MEDIDO = Color(0.42, 0.75, 0.19);
# Alpha con el que tileMap.draw_tints() pinta el color del tipo encima del tile.
const ALPHA_TINTE = 0.45;
# Separación mínima que se le exige a un tinte para darlo por legible, en fracción de canal.
# M3.5 midió `toxic` en ~12/255 (0.047) contra el suelo y la conclusión fue que se veía pero
# había que buscarla; 0.15 son 38/255, el triple de aquello.
const CONTRASTE_MINIMO = 0.15;

var _m8_ofertas = [];
var _m8_concedidas = [];

func _m8_apuntar(ids, _rewards, granted):
	_m8_ofertas.append(ids);
	_m8_concedidas.append(granted);

func _tinte_sobre_suelo(color_json):
	var c = Color(color_json[0], color_json[1], color_json[2]);
	return SUELO_MEDIDO.lerp(c, ALPHA_TINTE);

func _distancia_max(a, b):
	return max(max(abs(a.r - b.r), abs(a.g - b.g)), abs(a.b - b.b));

func _test_tm8_cabos(file_data):
	print("Tensión M8 — cabos sueltos");
	var catalogo = file_data["Upgrades"];
	var paquetes = file_data["StartingPackages"];

	# --- Cabo 1: run_won se emite UNA vez ---
	# El caso que lo rompía: el último checkpoint se cierra con el mapa ya restaurado, así que
	# la rama de producción y la de restauración se cumplían las dos en la misma llamada.
	var gm = _new_gm(file_data, [{ "material": "wood", "quantity": 5, "label": "Único" }]);
	var bag = _new_bag();
	bag.initialize(file_data);
	bag.addToBag("wood", 5);
	var pm = _new_pm();   # sin una sola mota: isRestored() es true desde el primer frame
	var victorias = [];
	gm.run_won.connect(func(_stats): victorias.append(1));
	gm.update(bag, pm);
	_check("el último checkpoint con el mapa ya limpio emite run_won UNA vez",
		victorias.size() == 1, "emisiones = %d" % victorias.size());
	gm.update(bag, pm);
	gm.update(bag, pm);
	_check("y los frames siguientes no la vuelven a emitir", victorias.size() == 1,
		"emisiones = %d" % victorias.size());
	_limpiar([gm, bag, pm]);

	# La otra mitad del cabo: con el mapa sucio la victoria sigue esperando a la restauración,
	# y cuando llega también es una sola.
	var gm_sucio = _new_gm(file_data, [{ "material": "wood", "quantity": 5, "label": "Único" }]);
	var bag_sucio = _new_bag();
	bag_sucio.initialize(file_data);
	bag_sucio.addToBag("wood", 5);
	var pm_sucio = _new_pm();
	pm_sucio.addPollution(100.0);   # pico 100 → umbral 17
	var victorias_sucias = [];
	gm_sucio.run_won.connect(func(_stats): victorias_sucias.append(1));
	gm_sucio.update(bag_sucio, pm_sucio);
	_check("con el mapa sucio la producción termina pero no se gana",
		gm_sucio.production_done and victorias_sucias.is_empty(),
		"emisiones = %d" % victorias_sucias.size());
	pm_sucio.removePollution(95.0);   # total 5, por debajo del umbral
	gm_sucio.update(bag_sucio, pm_sucio);
	gm_sucio.update(bag_sucio, pm_sucio);
	_check("y al restaurarse se gana, también una sola vez", victorias_sucias.size() == 1,
		"emisiones = %d" % victorias_sucias.size());
	_limpiar([gm_sucio, bag_sucio, pm_sucio]);

	# --- Cabo 2: la carta de rescate no se puede perder ---
	var rescate = "unlock_woodprocessing";
	var gm2 = _new_gm(file_data, [
		{ "material": "wood", "quantity": 5, "label": "Uno" },
		{ "material": "plank", "quantity": 5, "label": "Dos" }
	]);
	var lenador = StubPlayer.new();
	lenador.availableFactories = paquetes["lumberjack"]["factories"].duplicate();
	gm2.setPlayer(lenador);
	_m8_ofertas = [];
	_m8_concedidas = [];
	gm2.checkpoint_reached.connect(_m8_apuntar);
	var bag2 = _new_bag();
	bag2.initialize(file_data);
	bag2.addToBag("wood", 5);
	gm2.update(bag2);
	_check("la carta que desatasca viaja con la señal como CONCEDIDA",
		_m8_concedidas.size() == 1 and _m8_concedidas[0] == [rescate],
		"concedidas %s" % str(_m8_concedidas));
	_check("y ya no ocupa una de las tres cartas que se ofrecen",
		_m8_ofertas.size() == 1 and not _m8_ofertas[0].has(rescate),
		"ofrecidas %s" % str(_m8_ofertas));
	_check("la pantalla sigue ofreciendo 3 cartas distintas de verdad",
		_m8_ofertas[0].size() == 3 and _sin_repetidas(_m8_ofertas[0]),
		"ofrecidas %s" % str(_m8_ofertas));
	# Elegir cualquiera de las tres ya no puede tirar la salida: la concedida no estaba entre
	# ellas, así que no hay elección que la pierda.
	var puede_perderse = false;
	for i in range(60):
		if gm2._pick_upgrades(3, 1, gm2._granted_upgrades()).has(rescate):
			puede_perderse = true;
		if gm2._pick_upgrades(3, 2, gm2._granted_upgrades()).has(rescate):
			puede_perderse = true;
	_check("en 120 pantallas la carta concedida no vuelve a salir como opción",
		not puede_perderse);
	_limpiar([gm2, bag2]);

	# En `standard`, que trae la procesadora, no se concede nada: la pantalla es la de siempre.
	var gm_std = _new_gm(file_data);
	var estandar = StubPlayer.new();
	estandar.availableFactories = paquetes["standard"]["factories"].duplicate();
	gm_std.setPlayer(estandar);
	_check("en standard no se concede ninguna mejora", gm_std._granted_upgrades().is_empty(),
		"concedidas %s" % str(gm_std._granted_upgrades()));
	_limpiar([gm_std]);

	# La puerta real: Main aplica lo concedido sin que el jugador pulse nada, y lo aplica
	# ANTES de la pantalla. Aquí se comprueba el efecto, que es lo que garantiza la salida.
	var main = _new_main_de_prueba(file_data);
	var jugador_main = main.get_node("Player");
	jugador_main.availableFactories = paquetes["lumberjack"]["factories"].duplicate();
	main._apply_granted_upgrades([rescate]);
	_check("Main aplica la concedida sin intervención del jugador",
		jugador_main.availableFactories.has("WoodProcessing"),
		"quedó %s" % str(jugador_main.availableFactories));
	# Y una vez dentro deja de concederse: el rescate saca del atasco, no es un peaje eterno.
	var gm3 = _new_gm(file_data, [{ "material": "plank", "quantity": 5, "label": "Uno" },
		{ "material": "plank", "quantity": 9, "label": "Dos" }]);
	gm3.setPlayer(jugador_main);
	_check("con la procesadora ya dentro no se concede nada más",
		gm3._granted_upgrades().is_empty(), "concedidas %s" % str(gm3._granted_upgrades()));
	_limpiar([gm3, main]);

	# --- Cabo 3: `fertile` se distingue del suelo y del resto de la paleta ---
	var tipos = file_data["TileTypes"];
	var fertil = _tinte_sobre_suelo(tipos["fertile"]["color"]);
	_check("el tinte de `fertile` se separa del verde del suelo",
		_distancia_max(fertil, SUELO_MEDIDO) >= CONTRASTE_MINIMO,
		"separación %f" % _distancia_max(fertil, SUELO_MEDIDO));
	var choque = "";
	for tipo in tipos:
		if tipo == "fertile":
			continue;
		var otro = _tinte_sobre_suelo(tipos[tipo]["color"]);
		if _distancia_max(fertil, otro) < CONTRASTE_MINIMO:
			choque = tipo;
	_check("y no se confunde con ningún otro tipo de casilla", choque == "",
		"choca con %s" % choque);
	# El resto de la paleta no se ha movido: M8 solo autorizaba `fertile`.
	_check("`toxic` sigue en el magenta que se le puso al cerrar M4",
		tipos["toxic"]["color"] == [0.85, 0.1, 0.75, 1.0], "quedó %s" % str(tipos["toxic"]["color"]));
	_check("`forest` sigue en su verde oscuro",
		tipos["forest"]["color"] == [0.1, 0.6, 0.1, 1.0], "quedó %s" % str(tipos["forest"]["color"]));

	# --- Cabo 4: el catálogo no tiene cartas muertas ---
	# Una `unlock_factory` cuya factoría traen los TRES paquetes no puede salir nunca: el
	# filtro de M2 la esconde en silencio y solo ocupa sitio en el JSON.
	var muertas = [];
	for id in catalogo:
		if catalogo[id].get("type", "") != "unlock_factory":
			continue;
		var factoria = catalogo[id].get("factory", "");
		var falta_en_alguno = false;
		for paquete in paquetes:
			if not paquetes[paquete]["factories"].has(factoria):
				falta_en_alguno = true;
		if not falta_en_alguno:
			muertas.append(id);
	_check("ninguna unlock_factory del catálogo está ya en los tres paquetes",
		muertas.is_empty(), "muertas: %s" % str(muertas));
	# La cara fuerte: toda carta del catálogo tiene al menos una partida en la que se ofrece.
	var alguna_vez = {};
	for paquete in paquetes:
		var gm_p = _new_gm(file_data);
		var jugador = StubPlayer.new();
		jugador.availableFactories = paquetes[paquete]["factories"].duplicate();
		gm_p.setPlayer(jugador);
		for id in gm_p._usable_upgrades():
			alguna_vez[id] = true;
		_limpiar([gm_p]);
	var nunca = [];
	for id in catalogo:
		if not alguna_vez.has(id):
			nunca.append(id);
	_check("toda mejora del catálogo puede salir en algún paquete", nunca.is_empty(),
		"nunca salen: %s" % str(nunca));

# ---------- Derrota M1: el ahogo ----------

# Lo que una productora ENTREGA en `ticks` ticks, con `suciedad` ya sembrada en su casilla. La
# factoría va con pollution 0.0 a propósito: lo que se mide es el ahogo de la suciedad
# sembrada, no el que la factoría se fabrica sola ensuciándose la casilla tick a tick.
# Cada escenario monta y suelta su propio PollutionManager: find_child devuelve el PRIMERO del
# árbol, así que dos escenarios vivos a la vez leerían el mismo manager.
# Desde Cintas M2 lo entregado NO se mide en la bolsa: producir ya no la llena —el material
# sale por `resource_produced` y lo encamina Main por la red de cintas—, así que se cuenta en
# la señal, que es el único punto por el que la producción sale de la factoría.
func _entregado_en(_file_data, celda, suciedad, ticks):
	var pm = _new_pm();
	root.add_child(pm);
	if suciedad > 0.0:
		pm.addPollution(suciedad, celda);
	var f = _factoria_en_arbol("WoodCutter", celda);
	f.initialize("WoodCutter", 1, null, "wood", 1, 0.0, "production", 0);
	var entregado = [0];
	f.resource_produced.connect(func(_mat, cantidad, _pos): entregado[0] += cantidad);
	for i in range(ticks):
		f.update();
	var total = entregado[0];
	_limpiar([f, pm]);
	return total;

# Lo que un Reforester le quita a UNA vecina fija según lo sucia que esté su propia casilla. La
# vecina se siembra igual en los tres escenarios, así que si el ahogo alcanzara a las
# restauradoras el noveno que le llega sería menor sobre suelo sucio.
func _limpieza_en_vecina(celda, suciedad_propia):
	var pm = _new_pm();
	root.add_child(pm);
	var vecina = celda + Vector2i(1, 0);
	pm.addPollution(10.0, vecina);
	if suciedad_propia > 0.0:
		pm.addPollution(suciedad_propia, celda);
	var f = _factoria_en_arbol("Reforester", celda);
	f.initialize("Reforester", 1, null, null, 1, -9.0, "restoration", 0);
	var choke = f.getPollutionChoke();
	f.update(null);
	var quitado = 10.0 - pm.pollution_per_cell[vecina];
	_limpiar([f, pm]);
	return { "quitado": quitado, "choke": choke };

func _test_cd1_ahogo(file_data):
	print("Derrota M1 — la casilla sucia ahoga la producción");
	var celda = Vector2i(4, 4);

	# 6,25 de suciedad local = la mitad de cell_block_pollution (12,5) = choke 0,5.
	var limpia = _entregado_en(file_data, celda, 0.0, 20);
	var media = _entregado_en(file_data, celda, 6.25, 20);
	var saturada = _entregado_en(file_data, celda, 12.5, 20);
	_check("sobre casilla limpia entrega una unidad por tick", limpia == 20,
		"entregó %d" % limpia);
	_check("sobre casilla a medio saturar entrega la mitad", media == 10,
		"entregó %d en vez de %d" % [media, limpia / 2]);
	_check("sobre casilla saturada no entrega nada", saturada == 0,
		"entregó %d" % saturada);

	# Rampa y no interruptor: con output 1 un int(1 * 0.5) daría 0 para siempre. El acumulador
	# hace que el tick perdido se recupere en el siguiente.
	_check("al 50 % el primer tick no entrega nada...",
		_entregado_en(file_data, celda, 6.25, 1) == 0);
	_check("...y el segundo entrega la unidad entera (acumulador, no redondeo)",
		_entregado_en(file_data, celda, 6.25, 2) == 1);

	# Regla 2: el ahogo no baja el TECHO con el que gameManager._installed_rate() juzga el tier.
	# Si lo bajara, ahogar la propia línea haría cobrar cartas potentes por jugar mal.
	var pm_techo = _new_pm();
	root.add_child(pm_techo);
	pm_techo.addPollution(12.5, celda);
	var ahogada = _factoria_en_arbol("WoodCutter", celda);
	ahogada.initialize("WoodCutter", 1, null, "wood", 1, 0.0, "production", 0);
	_check("el techo (getEffectiveOutput) no lo toca el ahogo", ahogada.getEffectiveOutput() == 1,
		"techo = %d" % ahogada.getEffectiveOutput());
	_check("y el choke sí llega a 0 en esa misma casilla", _near(ahogada.getPollutionChoke(), 0.0),
		"choke = %f" % ahogada.getPollutionChoke());
	_limpiar([ahogada, pm_techo]);

	# El contrapeso que hace justa la derrota: limpiar funciona siempre, o saturar el mapa sería
	# irreversible y el jugador perdería sin agencia.
	var r_limpia = _limpieza_en_vecina(celda, 0.0);
	var r_media = _limpieza_en_vecina(celda, 6.25);
	var r_saturada = _limpieza_en_vecina(celda, 12.5);
	_check("un Reforester no se ahoga nunca (choke 1.0 en las tres casillas)",
		_near(r_limpia["choke"], 1.0) and _near(r_media["choke"], 1.0) and _near(r_saturada["choke"], 1.0),
		"chokes = %f / %f / %f" % [r_limpia["choke"], r_media["choke"], r_saturada["choke"]]);
	_check("y limpia exactamente igual sobre suelo limpio, a medias y saturado",
		_near(r_limpia["quitado"], 1.0) and _near(r_media["quitado"], 1.0)
			and _near(r_saturada["quitado"], 1.0),
		"quitó %f / %f / %f" % [r_limpia["quitado"], r_media["quitado"], r_saturada["quitado"]]);

	# Decisión de M1: un tick que no entrega nada no consume insumos ni ensucia. Si consumiera,
	# el ahogo sería además un sumidero de recursos y aceleraría la espiral por un camino que el
	# plan no ha diseñado; la deuda, en cambio, sí acumula.
	var pm2 = _new_pm();
	root.add_child(pm2);
	pm2.addPollution(6.25, celda);
	var sierra = _factoria_en_arbol("WoodProcessing", celda);
	sierra.initialize("WoodProcessing", 1, ["wood"], "plank", 1, 2.0, "production", 0);
	# Desde Cintas M2 el insumo sale del BÚFER DE ENTRADA —lo que le ha traído una cinta—, no
	# de la bolsa global, y lo entregado se cuenta en la señal.
	sierra.input_buffer = { "wood": 5 };
	var entregado_sierra = [0];
	sierra.resource_produced.connect(func(_mat, cantidad, _pos): entregado_sierra[0] += cantidad);
	sierra.update();
	_check("el tick que no entrega nada no consume insumos", sierra.input_buffer["wood"] == 5,
		"quedan %d maderas en el búfer" % sierra.input_buffer["wood"]);
	_check("ni ensucia", _near(pm2.pollution_per_cell[celda], 6.25),
		"la casilla quedó en %f" % pm2.pollution_per_cell[celda]);
	sierra.update();
	_check("el tick siguiente sí consume, entrega y ensucia",
		sierra.input_buffer["wood"] == 4 and entregado_sierra[0] == 1
			and _near(pm2.pollution_per_cell[celda], 8.25),
		"búfer %d, entregado %d, casilla %f" % [sierra.input_buffer["wood"],
			entregado_sierra[0], pm2.pollution_per_cell[celda]]);
	_limpiar([sierra, pm2]);

	# El WorkerCamp es una productora como las demás: se ahoga igual, y su salida sigue sin
	# pasar por la bolsa (la intercepta Main._on_resource_produced vía resource_produced).
	var pm3 = _new_pm();
	root.add_child(pm3);
	pm3.addPollution(6.25, celda);
	var campamento = _factoria_en_arbol("WorkerCamp", celda);
	campamento.initialize("WorkerCamp", 1, null, "worker", 1, 0.0, "production", 0);
	var bag3 = _new_bag();
	bag3.initialize(file_data);
	var emisiones = [];
	campamento.resource_produced.connect(func(_mat, cantidad, _pos): emisiones.append(cantidad));
	for i in range(20):
		campamento.update(bag3);
	_check("el WorkerCamp se ahoga como cualquier productora", emisiones.size() == 10,
		"emitió %d veces" % emisiones.size());
	_check("y su salida sigue sin pasar por la bolsa", bag3.getQuantity("worker") == 0,
		"la bolsa tiene %d workers" % bag3.getQuantity("worker"));
	_limpiar([campamento, pm3, bag3]);

# ---------- Derrota M2: el contagio ----------

# TileMap de la escena (no el script suelto): set_cell/get_cell_source_id necesitan su TileSet,
# y el contagio pregunta justo por eso. Deja sembrado un cuadrado de casillas con tile.
func _tilemap_con_suelo(celdas):
	var tm = load("res://entities/tilemap/tile_map.tscn").instantiate();
	root.add_child(tm);
	for c in celdas:
		tm.set_cell(0, c, 1, Vector2i(0, 0));
	return tm;

func _vecindario(centro):
	var celdas = [];
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			celdas.append(centro + Vector2i(dx, dy));
	return celdas;

func _test_cd2_contagio(file_data):
	print("Derrota M2 — la casilla saturada desborda sobre sus vecinas");
	var foco = Vector2i(5, 5);
	var tm = _tilemap_con_suelo(_vecindario(foco));
	var pm = _new_pm();
	var segundos = 4.0;
	var esperado = pm.contagion_rate * segundos;

	pm.addPollution(13.0, foco);
	for i in range(240):
		tm.tick_contagion(pm, 1.0 / 60.0);

	var todas_sucias = true;
	for offset in pm.NEIGHBOR_OFFSETS:
		if not _near(pm.pollution_per_cell.get(foco + offset, 0.0), esperado, 0.001):
			todas_sucias = false;
	_check("una casilla a 13 ensucia a sus 8 vecinas", todas_sucias,
		"vecina (6,5) = %f, esperado %f" % [pm.pollution_per_cell.get(Vector2i(6, 5), -1.0), esperado]);
	# Genera, no reparte: el foco no pierde nada y el global SUBE. Repartir conservaría el
	# total y el mapa convergería a un empate tibio por debajo de la saturación.
	_check("el foco no pierde nada de lo que contagia", _near(pm.pollution_per_cell[foco], 13.0),
		"el foco quedó en %f" % pm.pollution_per_cell[foco]);
	_check("y el total global sube", _near(pm.total_pollution, 13.0 + 8.0 * esperado, 0.001),
		"global = %f" % pm.total_pollution);
	_check("el contagio infla peak_pollution (el precio de generar)",
		_near(pm.peak_pollution, pm.total_pollution, 0.001), "pico = %f" % pm.peak_pollution);
	# Simetría con removePollution(): al haber sumado POR CASILLA, limpiar deshace el contagio
	# hasta el último decimal. Sumado al global a secas sería suciedad irreversible.
	for offset in pm.NEIGHBOR_OFFSETS:
		pm.removePollution(esperado, foco + offset);
	_check("limpiar una vecina deshace el contagio del todo (suma por casilla, no al global)",
		_near(pm.total_pollution, 13.0, 0.001), "global = %f" % pm.total_pollution);

	# Por debajo del umbral no pasa nada: contagion_pollution se SUPERA, no se toca.
	var tm2 = _tilemap_con_suelo(_vecindario(foco));
	var pm2 = _new_pm();
	pm2.addPollution(12.0, foco);
	var pm3 = _new_pm();
	pm3.addPollution(pm3.contagion_pollution, foco);
	for i in range(240):
		tm2.tick_contagion(pm2, 1.0 / 60.0);
		tm2.tick_contagion(pm3, 1.0 / 60.0);
	_check("una casilla a 12 no contagia a nadie",
		pm2.pollution_per_cell.size() == 1 and _near(pm2.total_pollution, 12.0),
		"casillas sucias = %d, global = %f" % [pm2.pollution_per_cell.size(), pm2.total_pollution]);
	_check("ni una justo en el umbral (12,5): hay que superarlo",
		pm3.pollution_per_cell.size() == 1, "casillas sucias = %d" % pm3.pollution_per_cell.size());

	# El contagio no se sale del mapa: un foco en la esquina solo tiene 3 vecinas con tile.
	var esquina = Vector2i(0, 0);
	var tm3 = _tilemap_con_suelo([esquina, Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]);
	var pm4 = _new_pm();
	pm4.addPollution(13.0, esquina);
	for i in range(240):
		tm3.tick_contagion(pm4, 1.0 / 60.0);
	var fuera_limpio = true;
	for offset in pm4.NEIGHBOR_OFFSETS:
		var vecina = esquina + offset;
		if tm3.get_cell_source_id(0, vecina) == -1 and pm4.pollution_per_cell.has(vecina):
			fuera_limpio = false;
	_check("las vecinas que no existen en la capa de suelo no reciben nada", fuera_limpio,
		"casillas sucias = %d" % pm4.pollution_per_cell.size());
	_check("y las 3 que sí existen sí lo reciben",
		_near(pm4.total_pollution, 13.0 + 3.0 * esperado, 0.001), "global = %f" % pm4.total_pollution);

	_limpiar([tm, tm2, tm3, pm, pm2, pm3, pm4]);

	# Cableado real: el contagio corre desde Main._tick_world(), detrás del tick pasivo. Sin
	# esta llamada las pruebas de arriba pasarían igual y la mecánica no existiría en el juego.
	var pm5 = _new_pm();
	root.add_child(pm5);
	var main = _new_main_de_prueba(file_data);
	main.pollutionManager = pm5;
	var tm4 = main.get_node("TileMap");
	for c in _vecindario(foco):
		tm4.set_cell(0, c, 1, Vector2i(0, 0));
	pm5.addPollution(13.0, foco);
	for i in range(240):
		main._tick_world(tm4, 1.0 / 60.0);
	_check("Main._tick_world() lo llama cada frame",
		_near(pm5.pollution_per_cell.get(Vector2i(6, 5), 0.0), esperado, 0.001),
		"la vecina quedó en %f" % pm5.pollution_per_cell.get(Vector2i(6, 5), -1.0));
	_limpiar([main, pm5]);

# ---------- Condiciones de Derrota M3: el punto muerto emite la derrota ----------

# Mapa con suelo y TODAS sus casillas saturadas: ninguna admite factoría, que es la condición
# 3 del punto muerto. 20,0 por casilla pasa de sobra el cell_block_pollution de 12,5.
func _mapa_saturado(pm, centro):
	var tm = _tilemap_con_suelo(_vecindario(centro));
	tm.setPollutionManager(pm);
	for c in _vecindario(centro):
		pm.addPollution(20.0, c);
	return tm;

# Escenario de punto muerto listo para usar: mapa saturado, bolsa vacía, un objetivo
# inalcanzable a propósito —lo que se mide es la derrota, no el checkpoint— y el gameManager
# con sus dos inyecciones puestas. Devuelve todo lo que la prueba tiene que manejar.
func _escenario_muerto(file_data, centro, pm):
	var tm = _mapa_saturado(pm, centro);
	var gm = _new_gm(file_data, [
		{ "material": "plank", "quantity": 999, "label": "Uno", "maintenance": { "wood": 5 } }
	]);
	var bag = _new_bag();
	bag.initialize(file_data);
	var fabricas = [];
	gm.setFactories(fabricas);
	gm.setTileMap(tm);
	return { "tm": tm, "gm": gm, "bag": bag, "fabricas": fabricas, "perdidas": [] };

# Corre la run hasta `hasta` segundos de run_time, a 60 fps. run_time se mueve a mano porque
# gameManager._process() no corre con el nodo fuera del árbol, y porque la gracia se mide
# contra run_time y no contra frames: update() no recibe delta.
func _correr_hasta(esc, desde, hasta, extra = null):
	var t = desde;
	while t < hasta:
		t += 1.0 / 60.0;
		esc["gm"].run_time = t;
		esc["gm"].update(esc["bag"], esc["pm"]);
		if extra != null:
			extra.call();
	return t;

func _test_cd3_derrota(file_data):
	print("Derrota M3 — el punto muerto emite run_lost");
	var gracia = load("res://managers/gameManager.gd").DEADLOCK_GRACE;
	var centro = Vector2i(5, 5);

	# --- Las tres condiciones a la vez: la run se declara muerta al agotarse la gracia.
	var pm = _new_pm();
	var esc = _escenario_muerto(file_data, centro, pm);
	esc["pm"] = pm;
	var gm = esc["gm"];
	gm.run_lost.connect(func(stats): esc["perdidas"].append(stats));
	_check("un mapa saturado no tiene ni una casilla construible", not esc["tm"].hasBuildableCell([]));

	var t0 = 10.0;
	gm.run_time = t0;
	gm.update(esc["bag"], pm);
	_check("la ventana se abre en el primer frame en punto muerto", _near(gm.deadlock_timer, t0),
		"deadlock_timer = %f" % gm.deadlock_timer);
	var t = _correr_hasta(esc, t0, t0 + gracia - 0.1);
	_check("la gracia entera corre sin emitir nada", esc["perdidas"].is_empty(),
		"emitió %d veces antes de tiempo" % esc["perdidas"].size());
	_check("y sin apagar la run", gm.active);

	t = _correr_hasta(esc, t, t0 + gracia + 0.1);
	_check("al agotarse la gracia se emite run_lost", esc["perdidas"].size() == 1,
		"emisiones = %d" % esc["perdidas"].size());
	_check("y la run queda apagada", not gm.active);
	var stats = esc["perdidas"][0] if esc["perdidas"].size() > 0 else {};
	# Mismo diccionario que _triggerWin(), para que runSummary no tenga que saber si se ganó
	# o se perdió. factories_placed va a 0 porque lo rellena Main, igual que en la victoria.
	_check("stats viaja con los cuatro campos de la victoria",
		stats.has("time") and stats.has("checkpoints") and stats.has("factories_placed")
		and stats.has("final_pollution"), "stats = %s" % str(stats));
	# El tiempo es el del instante de la muerte —el primer frame pasada la gracia—, no el de
	# la llamada que lo comprueba: la run se congela ahí.
	var muerta_en = stats.get("time", -1.0);
	_check("y con los valores de la run muerta",
		muerta_en >= t0 + gracia and muerta_en < t0 + gracia + 1.0 / 30.0
		and stats.get("checkpoints", -1) == 0 and stats.get("factories_placed", -1) == 0
		and stats.get("final_pollution", -1) == 180, "stats = %s" % str(stats));

	# Una sola vez: `active = false` va ANTES de emitir, así que update() sale por su guardia
	# en todas las llamadas siguientes. Es el bug del run_won que se emitía dos veces.
	_correr_hasta(esc, t, t + 5.0);
	_check("y una sola vez, por mucho que siga llamándose a update()", esc["perdidas"].size() == 1,
		"emisiones = %d" % esc["perdidas"].size());

	gm.reset();
	_check("reset() limpia los tres campos del punto muerto",
		gm.deadlock_timer == 0.0 and gm.last_pending_quantity == 0 and gm.last_seen_pollution == 0.0,
		"timer %f, pendiente %d, contaminación %f" % [gm.deadlock_timer, gm.last_pending_quantity,
			gm.last_seen_pollution]);
	_limpiar([esc["tm"], gm, esc["bag"], pm]);

	# --- Condición 1: el material pendiente no es solo el del objetivo. Desde la Tensión del
	# Loop un checkpoint cobra objetivo Y mantenimiento, y los dos son requisito por igual:
	# talar una madera del peaje mueve la run tanto como serrar un tablón.
	var pm2 = _new_pm();
	var esc2 = _escenario_muerto(file_data, centro, pm2);
	esc2["pm"] = pm2;
	var gm2 = esc2["gm"];
	gm2.run_lost.connect(func(stats): esc2["perdidas"].append(stats));
	gm2.run_time = t0;
	gm2.update(esc2["bag"], pm2);
	var t2 = _correr_hasta(esc2, t0, t0 + gracia - 1.0);
	_check("la cuenta atrás está corriendo cuando llega la madera", gm2.deadlock_timer > 0.0);
	var abierta_en = gm2.deadlock_timer;
	esc2["bag"].addToBag("wood", 1);
	t2 = _correr_hasta(esc2, t2, t2 + 3.0 / 60.0);
	_check("producir el material del MANTENIMIENTO también rompe la condición 1",
		gm2.deadlock_timer > abierta_en,
		"la ventana se abrió en %f y sigue abierta desde ahí" % abierta_en);
	_correr_hasta(esc2, t2, t0 + gracia + 0.5);
	_check("y la ventana vuelve a empezar de cero: los segundos ya corridos no cuentan",
		esc2["perdidas"].is_empty(), "emisiones = %d" % esc2["perdidas"].size());
	_limpiar([esc2["tm"], gm2, esc2["bag"], pm2]);

	# --- Condición 2: colocar un Reforester a mitad de la cuenta atrás la cancela. Es el
	# contrapeso que hace justa la derrota — limpiar siempre funciona— y la razón de que el
	# aviso de M5 sea una cuenta atrás cancelable y no una sentencia.
	var pm3 = _new_pm();
	root.add_child(pm3);   # el Reforester lo localiza con find_child, así que va en el árbol
	var esc3 = _escenario_muerto(file_data, centro, pm3);
	esc3["pm"] = pm3;
	var gm3 = esc3["gm"];
	gm3.run_lost.connect(func(stats): esc3["perdidas"].append(stats));
	gm3.run_time = t0;
	gm3.update(esc3["bag"], pm3);
	var t3 = _correr_hasta(esc3, t0, t0 + gracia * 0.5);
	_check("a mitad de la gracia la cuenta atrás sigue corriendo y no ha emitido nada",
		gm3.deadlock_timer > 0.0 and esc3["perdidas"].is_empty());
	var reforestador = _factoria_en_arbol("Reforester", centro);
	reforestador.initialize("Reforester", 1, null, null, 1, -1.0, "restoration", 0);
	# El array de factorías se comparte por referencia con Main, que lo muta al construir: se
	# añade al que ya tiene el gameManager en vez de inyectar uno nuevo.
	esc3["fabricas"].append(reforestador);
	var limpiar_un_tick = func(): reforestador.update(esc3["bag"]);
	_correr_hasta(esc3, t3, t0 + gracia * 1.5 + 2.0, limpiar_un_tick);
	_check("colocar un Reforester cancela la cuenta atrás", gm3.deadlock_timer == 0.0,
		"deadlock_timer = %f" % gm3.deadlock_timer);
	_check("y no se emite nada, ni pasada la gracia entera", esc3["perdidas"].is_empty(),
		"emisiones = %d" % esc3["perdidas"].size());
	_check("porque la contaminación total ha bajado", pm3.total_pollution < 180.0,
		"global = %f" % pm3.total_pollution);
	_limpiar([reforestador, esc3["tm"], gm3, esc3["bag"], pm3]);

	# --- Sin TileMap inyectado no se evalúa nada. Es lo que protege a las 257 pruebas que
	# llaman update(bag) a secas, y a la partida hasta que M4 haga la inyección: sin las tres
	# observaciones no hay punto muerto que demostrar, y callar es lo correcto.
	var pm4 = _new_pm();
	var esc4 = _escenario_muerto(file_data, centro, pm4);
	esc4["pm"] = pm4;
	var gm4 = esc4["gm"];
	gm4.setTileMap(null);
	gm4.run_lost.connect(func(stats): esc4["perdidas"].append(stats));
	_correr_hasta(esc4, t0, t0 + gracia * 2.0);
	_check("sin TileMap el punto muerto no se evalúa ni se acumula",
		esc4["perdidas"].is_empty() and gm4.deadlock_timer == 0.0,
		"emisiones = %d, timer = %f" % [esc4["perdidas"].size(), gm4.deadlock_timer]);
	# Y sin PollutionManager tampoco: es el camino de update(bag) sin segundo argumento.
	var esc5 = _escenario_muerto(file_data, centro, pm4);
	esc5["pm"] = null;
	var gm5 = esc5["gm"];
	gm5.run_lost.connect(func(stats): esc5["perdidas"].append(stats));
	_correr_hasta(esc5, t0, t0 + gracia * 2.0);
	_check("ni sin PollutionManager: update(bag) a secas nunca pierde",
		esc5["perdidas"].is_empty() and gm5.deadlock_timer == 0.0,
		"emisiones = %d, timer = %f" % [esc5["perdidas"].size(), gm5.deadlock_timer]);
	_limpiar([esc4["tm"], esc5["tm"], gm4, gm5, esc4["bag"], esc5["bag"], pm4]);

# ---------- Condiciones de Derrota M4: la derrota llega a la pantalla ----------

# Main de verdad, y este SÍ montado en el árbol, al revés que _new_main_de_prueba(): lo pide
# _start_game(), que genera el mapa, y tileMap.generate() lo centra con get_viewport(), que
# fuera del árbol es null. El precio es que _ready() levanta el menú principal —inofensivo, y
# se libera con él—; a cambio no hay que falsificar nada de lo que _ready() deja puesto.
func _main_para_run():
	var main = load("res://Main.gd").new();
	main.name = "Main";
	main.factory = load("res://entities/factory/factory.tscn");
	main.player = load("res://entities/player/player.tscn");
	main.grid = load("res://entities/tilemap/tile_map.tscn");
	# Al entrar en el árbol, _ready() deja puestos fileData, mapLoader y saveManager.
	root.add_child(main);
	return main;

# ¿La señal `senal` de `emisor` acaba en `receptor.metodo`? Es lo que M4 monta, y afirmarlo
# así no obliga a disparar la señal: disparar run_lost llamaría a _on_run_lost(), que pausa
# el árbol, y este Main vive fuera de él a propósito.
func _conectada(emisor, senal, receptor, metodo):
	for c in emisor.get_signal_connection_list(senal):
		if c["callable"].get_object() == receptor and c["callable"].get_method() == metodo:
			return true;
	return false;

# Todos los textos de una pantalla, en orden. Deja afirmar QUÉ pone la tabla del resumen sin
# depender de cómo esté anidada.
func _textos_de(nodo):
	var textos = [];
	if nodo is Label or nodo is Button:
		textos.append(nodo.text);
	for hijo in nodo.get_children():
		textos += _textos_de(hijo);
	return textos;

func _primer_boton(nodo):
	if nodo is Button:
		return nodo;
	for hijo in nodo.get_children():
		var encontrado = _primer_boton(hijo);
		if encontrado != null:
			return encontrado;
	return null;

# La huella de user://save.json: si existe y con qué contenido. Perder no debe moverla —es la
# asimetría entera con la victoria— y compararla completa es lo que afirma «ni un byte».
func _huella_del_save():
	var ruta = load("res://managers/saveManager.gd").SAVE_PATH;
	if not FileAccess.file_exists(ruta):
		return "<no existe>";
	return FileAccess.get_file_as_string(ruta);

func _test_cd4_ciclo(file_data):
	print("Derrota M4 — la derrota llega a la pantalla y no toca el save");

	# La huella del save se toma antes de tocar nada y se vuelve a mirar al final: nada de lo
	# que hace este hito puede moverla.
	var antes = _huella_del_save();
	# saveManager suelto: fuera del árbol no corre su _ready(), así que ni lee ni escribe el
	# fichero. Sirve de testigo de que perder no le pide nada.
	var sm = load("res://managers/saveManager.gd").new();
	sm.name = "SaveManager";

	# --- El cableado de _start_game(): las dos líneas que M4 añade.
	var main = _main_para_run();
	main._start_game("standard");
	var gm = main.gameManager;
	_check("_start_game() inyecta el TileMap en el gameManager",
		gm.tile_map_node != null and gm.tile_map_node == main.get_node("TileMap"));
	_check("y conecta run_lost con _on_run_lost", _conectada(gm, "run_lost", main, "_on_run_lost"));
	_check("sin perder las dos conexiones que ya había",
		_conectada(gm, "run_won", main, "_on_run_won")
		and _conectada(gm, "checkpoint_reached", main, "_on_checkpoint_reached"));

	# Y con el TileMap puesto el evaluador deja de ser inerte, que es el motivo de la línea:
	# sobre el mapa real de la run, saturado entero, la cuenta atrás arranca. No se la deja
	# agotar aquí a propósito —al hacerlo llamaría a _on_run_lost(), que pausa el árbol— y la
	# pantalla se comprueba abajo, sin árbol, por _close_lost_run().
	var bolsa = main.get_node("Player").get_node("Bag");
	# La bolsa se vacía a mano: desde Costes M2 el paquete `standard` nace con 40 de madera y
	# el primer update() cerraría el checkpoint 1 con ella. Cerrar un checkpoint llama a
	# _reset_deadlock() —la cuenta atrás no arrancaría nunca— y abre la pantalla de mejora, que
	# pausa el árbol para el resto de la suite. Lo que este bloque mide es que el evaluador
	# deje de ser inerte con el TileMap inyectado, no lo que traiga el paquete de inicio.
	bolsa.reset();
	var mapa = main.get_node("TileMap");
	for celda in mapa.get_used_cells(0):
		main.pollutionManager.addPollution(20.0, celda);
	_check("el mapa saturado de la run no admite ni una factoría",
		not mapa.hasBuildableCell(main.factoryArray));
	for i in range(3):
		gm.run_time = 1.0 + i / 60.0;
		gm.update(bolsa, main.pollutionManager);
	_check("y la cuenta atrás del punto muerto corre en la partida de verdad",
		gm.deadlock_timer > 0.0, "deadlock_timer = %f" % gm.deadlock_timer);
	# placer y mapLoader son nodos que Main nunca añade al árbol: se sueltan a mano.
	_limpiar([main.placer, main.mapLoader, main]);

	# --- La pantalla de derrota y la asimetría con la victoria.
	var main2 = _new_main_de_prueba(file_data);
	main2.saveManager = sm;
	var fabricas = [_new_factory("WoodCutter", Vector2i(0, 0)), _new_factory("WoodCutter", Vector2i(1, 0))];
	main2.factoryArray.append_array(fabricas);
	# El dict tal y como lo emite gameManager: factories_placed a 0, porque quien cuenta lo
	# construido es Main.
	var stats = { "time": 125.0, "checkpoints": 2, "factories_placed": 0, "final_pollution": 180 };
	main2._close_lost_run(stats);
	var pantalla = main2.get_node_or_null("RunSummary");
	_check("perder monta el resumen de la run", pantalla != null);
	var textos = _textos_de(pantalla) if pantalla != null else [];
	_check("con el título de la derrota y no el de la victoria",
		textos.has("Run fallida") and not textos.has("¡Run completada!"), "textos = %s" % str(textos));
	_check("Main rellena factories_placed, que gameManager emite a 0",
		stats.get("factories_placed", -1) == 2, "stats = %s" % str(stats));
	_check("y la tabla sale rellena con los datos de la run",
		textos.has("Tiempo: 02:05") and textos.has("Checkpoints superados: 2")
		and textos.has("Factories usadas: 2"), "textos = %s" % str(textos));
	# Se reutiliza runSummary justo por esto: su initialize() la pone en PROCESS_MODE_ALWAYS y
	# sin esa línea la pantalla saldría muerta bajo el get_tree().paused de _on_run_lost().
	_check("la pantalla sigue viva con el árbol pausado",
		pantalla != null and pantalla.process_mode == Node.PROCESS_MODE_ALWAYS);

	# 🔴 La pieza que más importa: perder no es progresión.
	_check("perder no toca user://save.json ni un byte", _huella_del_save() == antes,
		"la huella cambió");
	_check("y runs_completed no sube, ni se registra mejor tiempo",
		sm.get_runs_completed() == 0 and sm.get_best_time() == 0.0,
		"runs = %d, mejor = %f" % [sm.get_runs_completed(), sm.get_best_time()]);
	_check("ni se desbloquea nada de lo que concede la victoria",
		not sm.is_package_unlocked("lumberjack") and not sm.is_map_unlocked("wasteland_01")
		and not sm.is_package_unlocked("ecologist"));

	# --- Reiniciar: el botón y la `R`.
	_check("el resumen queda cableado a reset()",
		pantalla != null and _conectada(pantalla, "restart_pressed", main2, "reset"));
	# Se desconecta antes de tirar del cable: reset() despausa el árbol y libera los managers,
	# y este Main vive fuera del árbol. Lo que se afirma aquí es que las dos entradas emiten
	# restart_pressed, y arriba, que quien la escucha es reset().
	if pantalla != null:
		pantalla.restart_pressed.disconnect(main2.reset);
		var reinicios = [];
		pantalla.restart_pressed.connect(func(): reinicios.append(1));
		var tecla = InputEventKey.new();
		tecla.keycode = KEY_R;
		tecla.pressed = true;
		pantalla._unhandled_input(tecla);
		_check("la R de la pantalla pide reiniciar", reinicios.size() == 1,
			"emisiones = %d" % reinicios.size());
		var boton = _primer_boton(pantalla);
		_check("y el botón del resumen es el de volver a jugar",
			boton != null and boton.text.begins_with("Volver a jugar"),
			"botón = %s" % ("<ninguno>" if boton == null else boton.text));
		if boton != null:
			boton.pressed.emit();
		_check("que pide reiniciar igual que la tecla", reinicios.size() == 2,
			"emisiones = %d" % reinicios.size());
	_limpiar(fabricas);
	_limpiar([main2, sm]);

# ---------- Condiciones de Derrota M5: el aviso del colapso en el HUD ----------

# Los segundos que ANUNCIA el aviso, o -1 si no hay aviso. Se sacan del texto y no de
# `deadlock_timer` a propósito: lo que este hito promete es lo que el jugador lee.
func _segundos_del_aviso(texto):
	var marca = "COLAPSO EN ";
	var i = texto.find(marca);
	if i < 0:
		return -1;
	var resto = texto.substr(i + marca.length());
	return int(resto.substr(0, resto.find(" ")));

func _test_cd5_aviso(file_data):
	print("Derrota M5 — el HUD anuncia el colapso y por qué");
	var gracia = load("res://managers/gameManager.gd").DEADLOCK_GRACE;
	var centro = Vector2i(5, 5);

	var pm = _new_pm();
	var esc = _escenario_muerto(file_data, centro, pm);
	esc["pm"] = pm;
	var gm = esc["gm"];
	var bag = esc["bag"];

	# --- Sin ventana abierta, el HUD es exactamente el de siempre.
	var limpio = gm.getObjectiveText(bag, pm);
	_check("sin punto muerto el HUD no habla de ningún colapso", not ("COLAPSO" in limpio), limpio);
	_check("y dice lo que decía antes del hito", limpio == gm._progressText(bag, pm), limpio);

	# --- Al abrirse la ventana, el aviso sale delante y con la gracia entera.
	var t0 = 10.0;
	gm.run_time = t0;
	gm.update(bag, pm);
	var texto = gm.getObjectiveText(bag, pm);
	_check("al entrar en punto muerto el aviso va DELANTE de todo lo demás",
		texto.begins_with("⚠ COLAPSO EN"), texto);
	_check("con la gracia entera en el frame en que se abre la ventana",
		_segundos_del_aviso(texto) == int(gracia), texto);
	# Las tres patas, que son la única pista que el jugador va a tener de por qué muere.
	_check("y nombra las tres condiciones que se están cumpliendo a la vez",
		("no se produce" in texto) and ("nadie limpia" in texto)
		and ("no queda dónde construir" in texto), texto);
	# Desde M7 el aviso SUSTITUYE a la cola de contaminación en vez de sumarse a ella: sin eso
	# la línea no cabía en el Label y se cortaba a media palabra (ver _test_cd7_hud). Lo que
	# no se toca es el objetivo y su mantenimiento reservado, que son lo que el jugador tiene
	# que mirar para romper la condición 1 y cancelar la cuenta atrás.
	_check("sin comerse el objetivo ni el mantenimiento reservado",
		gm._progressText(bag, pm, true) in texto and ("peaje reservado" in texto), texto);
	# Desde Legibilidad M1 la etiqueta la pone _progressText() y no getStatusText(), así que
	# lo que se comprueba es la cola ENTERA, rótulo incluido, sin la ventana abierta.
	_check("pero con la cola de contaminación fuera mientras la ventana corre",
		not ("Contaminación" in texto)
		and (("  |  Contaminación: " + pm.getStatusText()) in gm._progressText(bag, pm)),
		texto);

	# --- La cuenta atrás baja de verdad con el reloj de la run.
	var t = _correr_hasta(esc, t0, t0 + gracia * 0.5);
	var medio = gm.getObjectiveText(bag, pm);
	var quedan = _segundos_del_aviso(medio);
	_check("a mitad de la gracia quedan menos segundos, y más de cero",
		quedan > 0 and quedan < int(gracia) and quedan <= int(ceil(gracia * 0.5)) + 1,
		"anuncia %d s de %d" % [quedan, int(gracia)]);

	# --- Consultar el HUD no mueve la partida: getObjectiveText() solo lee.
	var timer_antes = gm.deadlock_timer;
	var pendiente_antes = gm.last_pending_quantity;
	var vista_antes = gm.last_seen_pollution;
	for i in range(5):
		gm.getObjectiveText(bag, pm);
	_check("mirar el HUD no toca el deadlock_timer ni las observaciones",
		gm.deadlock_timer == timer_antes and gm.last_pending_quantity == pendiente_antes
		and gm.last_seen_pollution == vista_antes,
		"timer %f→%f" % [timer_antes, gm.deadlock_timer]);

	# --- Los otros dos caminos de salida del texto. El punto muerto puede darse también en la
	# fase de restauración —allí la condición 1 se cumple sola, porque ya no queda material
	# pendiente (ver _pending_quantity())—, así que el aviso tiene que salir igual.
	gm.production_done = true;
	var restaurando = gm.getObjectiveText(bag, pm);
	_check("el aviso sale también en la fase de restauración",
		restaurando.begins_with("⚠ COLAPSO EN") and ("Contaminación:" in restaurando), restaurando);
	_check("y sin PollutionManager en el texto, por el camino corto",
		gm.getObjectiveText(bag).begins_with("⚠ COLAPSO EN")
		and ("¡Producción completada!" in gm.getObjectiveText(bag)), gm.getObjectiveText(bag));
	gm.production_done = false;
	gm.current_checkpoint_index = gm.checkpoints.size();
	_check("y por el de la curva agotada",
		gm.getObjectiveText(bag, pm).begins_with("⚠ COLAPSO EN"), gm.getObjectiveText(bag, pm));
	gm.current_checkpoint_index = 0;

	# --- Romper la condición 1 borra el aviso sin dejar residuo. Se avanza UN frame y se mira:
	# la ventana se cierra en el frame en que la condición se rompe, y si nadie vuelve a
	# producir se reabre en el siguiente. Que se reabra no es residuo, es la regla de M3 vista
	# desde el HUD —la cuenta atrás es cancelable y empieza de cero, nunca continúa—.
	bag.addToBag("wood", 1);
	t += 1.0 / 60.0;
	gm.run_time = t;
	gm.update(bag, pm);
	var tras_producir = gm.getObjectiveText(bag, pm);
	_check("producir una unidad borra el aviso", not ("COLAPSO" in tras_producir), tras_producir);
	_check("y no deja residuo: ni separador suelto ni texto a medias",
		tras_producir == gm._progressText(bag, pm), tras_producir);
	t += 1.0 / 60.0;
	gm.run_time = t;
	gm.update(bag, pm);
	_check("y si el punto muerto vuelve, la cuenta atrás se anuncia entera otra vez",
		_segundos_del_aviso(gm.getObjectiveText(bag, pm)) == int(gracia),
		gm.getObjectiveText(bag, pm));
	_limpiar([esc["tm"], gm, bag, pm]);

	# --- Y romper la condición 2 igual: limpiar es la salida, y el HUD tiene que reflejarlo.
	var pm2 = _new_pm();
	var esc2 = _escenario_muerto(file_data, centro, pm2);
	esc2["pm"] = pm2;
	var gm2 = esc2["gm"];
	gm2.run_time = t0;
	gm2.update(esc2["bag"], pm2);
	_check("la ventana está abierta antes de limpiar",
		gm2.getObjectiveText(esc2["bag"], pm2).begins_with("⚠ COLAPSO EN"));
	# Se quitan 5 de una casilla de 20: el global baja —condición 2 rota— pero la casilla sigue
	# por encima de cell_block_pollution, así que la condición 3 no se mueve.
	pm2.removePollution(5.0, centro);
	gm2.run_time = t0 + 1.0 / 60.0;
	gm2.update(esc2["bag"], pm2);
	var tras_limpiar = gm2.getObjectiveText(esc2["bag"], pm2);
	_check("que la contaminación baje borra el aviso igual", not ("COLAPSO" in tras_limpiar),
		tras_limpiar);
	_check("y tampoco deja residuo", tras_limpiar == gm2._progressText(esc2["bag"], pm2),
		tras_limpiar);
	_limpiar([esc2["tm"], gm2, esc2["bag"], pm2]);

	# --- El evaluador es inerte sin TileMap, y el aviso lo hereda gratis: sin ventana abierta
	# no hay nada que anunciar, por saturado que esté el mapa.
	var pm3 = _new_pm();
	var esc3 = _escenario_muerto(file_data, centro, pm3);
	esc3["pm"] = pm3;
	var gm3 = esc3["gm"];
	gm3.setTileMap(null);
	_correr_hasta(esc3, t0, t0 + gracia * 2.0);
	_check("sin TileMap inyectado el HUD no anuncia ningún colapso",
		not ("COLAPSO" in gm3.getObjectiveText(esc3["bag"], pm3)),
		gm3.getObjectiveText(esc3["bag"], pm3));
	# Y sin PollutionManager tampoco: es el camino de update(bag) a secas de las pruebas.
	var esc4 = _escenario_muerto(file_data, centro, pm3);
	esc4["pm"] = null;
	var gm4 = esc4["gm"];
	_correr_hasta(esc4, t0, t0 + gracia * 2.0);
	_check("ni sin PollutionManager", not ("COLAPSO" in gm4.getObjectiveText(esc4["bag"])),
		gm4.getObjectiveText(esc4["bag"]));
	_limpiar([esc3["tm"], esc4["tm"], gm3, gm4, esc3["bag"], esc4["bag"], pm3]);


# ---------- Derrota M6: las dos constantes de la derrota ----------

# Valores provisionales: salieron de mediciones defectuosas, ya retiradas; aquí se fija la
# relación, no la cantidad. Esto guarda las RELACIONES que las justifican, que es lo que se
# rompe sin avisar al cambiarlas: afirma que los dos valores siguen cumpliendo su razón de ser. El porqué de cada
# valor vive en su comentario (managers/pollutionManager.gd, managers/gameManager.gd).
func _test_cd6_constantes(file_data):
	print("Derrota M6 — las dos constantes siguen cumpliendo su razón de ser");
	var gracia = load("res://managers/gameManager.gd").DEADLOCK_GRACE;
	var pm = _new_pm();

	# --- La gracia cubre LA jugada que desatasca: colocar un Reforester. Rompe la condición 2
	# en su primer tick, así que por debajo de ese tick la cuenta atrás mataría runs que el
	# jugador acaba de salvar.
	var tick_reforester = float(file_data["Factories"]["Reforester"]["tick"]);
	_check("la gracia cubre el primer tick de un Reforester recién colocado",
		gracia >= tick_reforester, "gracia %.1f s contra un tick de %.1f s" % [gracia, tick_reforester]);

	# --- Y cubre también la otra jugada: una productora sobre la última casilla libre, que en
	# un mapa medio saturado está SUCIA. El ahogo es lo que alarga la espera —production_debt
	# suelta una unidad cada ceil(1/choke) ticks—, no el `tick` del JSON. A choke 0,25 (9,375
	# de los 12,5 de cell_block_pollution) son cuatro ticks de producción, y la gracia tiene
	# que cubrirlos.
	var celda = Vector2i(4, 4);
	var suciedad = 0.75 * pm.cell_block_pollution;
	var ticks = 0;
	for n in range(1, 13):
		if _entregado_en(file_data, celda, suciedad, n) >= 1:
			ticks = n;
			break;
	var tick_woodcutter = float(file_data["Factories"]["WoodCutter"]["tick"]);
	_check("una productora a choke 0,25 tarda cuatro ticks en entregar la primera unidad",
		ticks == 4, "tardó %d" % ticks);
	_check("y la gracia cubre esos cuatro ticks",
		gracia >= ticks * tick_woodcutter,
		"gracia %.1f s contra %.1f s de espera" % [gracia, ticks * tick_woodcutter]);

	# --- El contagio tiene que existir y tiene que correr. Con contagion_rate a 0 un mapa
	# abandonado conserva casillas libres para siempre y la derrota es inalcanzable. Y si un
	# foco tardara demasiado en saturar a una vecina limpia, el colapso dejaría de verse venir
	# dentro de una sentada.
	_check("contagion_rate es mayor que cero, o el punto muerto es inalcanzable",
		pm.contagion_rate > 0.0);
	var segundos_vecina = pm.contagion_pollution / pm.contagion_rate;
	_check("un foco solo satura a una vecina limpia en menos de dos minutos",
		segundos_vecina <= 120.0, "tarda %.0f s" % segundos_vecina);
	_limpiar([pm]);


# ---------- Derrota M7: que el HUD no mienta ni se salga ----------

# Las seis pruebas de arriba verifican comportamiento; esta verifica que el comportamiento se
# LEE. El Label `Objective` de Main.tscn es una línea sola a 1280 px y no hace wrap: lo que no
# cabe se corta a media palabra y se pierde entero. Los seis hitos anteriores se dieron por
# buenos en headless y el defecto solo salió al mirar el juego en pantalla, así que esta
# prueba existe para que no vuelva a hacer falta mirar.
func _test_cd7_hud(file_data):
	print("Derrota M7 — el HUD no miente ni se sale de pantalla");
	var presupuesto = load("res://managers/gameManager.gd").HUD_MAX_CHARS;
	var centro = Vector2i(5, 5);

	# --- El denominador fijo se fue del texto: `Contaminación: 14209 / 200` dejaba de informar
	# en cuanto el contagio arrancaba, porque el 200 es la escala del TINTE y nunca fue un
	# objetivo que alcanzar.
	var pm = _new_pm();
	pm.addPollution(22607.0, centro);
	# Sin etiqueta desde Legibilidad M1: «Contaminación: » la antepone el HUD (_progressText).
	_check("getStatusText() enseña el total y el umbral efectivo, sin cociente",
		pm.getStatusText() == "22607  (restaurar: ≤ 2717)", pm.getStatusText());

	# Y pollution_threshold sigue entero donde sí sirve: es la escala del tintado del mapa, que
	# es quien comunica la gravedad de verdad. Borrarlo dejaría sin tintar los 11 tipos de casilla.
	var tinte = _new_pm();
	tinte.addPollution(50.0, centro);
	_check("pero pollution_threshold sigue siendo la escala del tinte, intacta",
		tinte.pollution_threshold == 200.0 and abs(tinte.getNormalizedPollution() - 0.25) < 0.0001,
		"normalizada %f" % tinte.getNormalizedPollution());
	_limpiar([pm, tinte]);

	# --- La línea del colapso, con los números más grandes que la curva REAL puede enseñar: el
	# último checkpoint (la etiqueta más larga), a una unidad de cerrarse y con el mantenimiento
	# casi cubierto, sobre un mapa en plena espiral.
	var pm2 = _new_pm();
	var esc = _escenario_muerto(file_data, centro, pm2);
	esc["pm"] = pm2;
	var gm = esc["gm"];
	var bag = esc["bag"];
	gm.checkpoints = file_data["Checkpoints"];
	gm.current_checkpoint_index = gm.checkpoints.size() - 1;
	var ultimo = gm.checkpoints[gm.current_checkpoint_index];
	bag.addToBag(ultimo["material"], int(ultimo["quantity"]) - 1);
	for material in ultimo.get("maintenance", {}):
		bag.addToBag(material, int(ultimo["maintenance"][material]) - 1);
	pm2.addPollution(22607.0, centro);
	# Dos updates: la primera observación fija el listón de la condición 1 —la bolsa acaba de
	# llenarse a mano y eso cuenta como producir— y la segunda abre la ventana.
	var t0 = 10.0;
	gm.run_time = t0;
	gm.update(bag, pm2);
	gm.run_time = t0 + 1.0 / 60.0;
	gm.update(bag, pm2);
	var colapso = gm.getObjectiveText(bag, pm2);
	_check("en pleno colapso el aviso sigue entero y delante",
		colapso.begins_with("⚠ COLAPSO EN") and ("no queda dónde construir" in colapso), colapso);
	var objetivo = "%s: %d / %d %s" % [ultimo.get("label", "Objetivo"),
		int(ultimo["quantity"]) - 1, int(ultimo["quantity"]), ultimo["material"]];
	_check("con el objetivo y el mantenimiento reservado, que es lo que rompe la condición 1",
		(objetivo in colapso) and ("peaje reservado" in colapso), colapso);
	_check("y sin la cola de contaminación, que el propio aviso ya resume",
		not ("Contaminación" in colapso), colapso);
	_check("la línea del colapso CABE en el Label de una sola línea",
		colapso.length() <= presupuesto,
		"%d caracteres de %d: %s" % [colapso.length(), presupuesto, colapso]);

	# El presupuesto tiene dientes: el formato de M5 —aviso MÁS cola con denominador fijo— no
	# cabía, y es exactamente lo que se vio cortado en pantalla (`… | Contamin`). Sin esta
	# comprobación el límite sería un número que se cumple solo.
	var como_en_m5 = colapso + "  |  Contaminación: %d / %d  (restaurar: ≤ %d)" % [
		int(pm2.total_pollution), int(pm2.pollution_threshold), int(pm2.getRestorationThreshold())];
	_check("y el formato anterior a M7 no cabía, que es el defecto que este hito arregla",
		como_en_m5.length() > presupuesto, "%d caracteres de %d" % [como_en_m5.length(), presupuesto]);

	# --- La excepción de la fase de restauración: ahí la cola es lo ÚNICO que dice el texto
	# —cuánto falta para cerrar la run—, así que el aviso se antepone como en M5 en vez de
	# sustituirla. La línea es corta y cabe de sobra.
	gm.production_done = true;
	var restaurando = gm.getObjectiveText(bag, pm2);
	_check("en restauración el aviso se antepone y la cola se QUEDA",
		restaurando.begins_with("⚠ COLAPSO EN")
		and restaurando.ends_with("  |  Contaminación: " + pm2.getStatusText())
		and restaurando.count("Contaminación") == 1,
		restaurando);
	_check("y esa línea también cabe",
		restaurando.length() <= presupuesto,
		"%d caracteres de %d: %s" % [restaurando.length(), presupuesto, restaurando]);
	gm.production_done = false;

	# --- Y el HUD de una run normal, sin ventana abierta, sigue enseñando las tres cosas.
	var pm3 = _new_pm();
	pm3.addPollution(77.0, centro);
	var gm3 = _new_gm(file_data);
	var bag3 = _new_bag();
	bag3.initialize(file_data);
	gm3.current_checkpoint_index = 1;
	var cp = gm3.checkpoints[1];
	for material in cp.get("maintenance", {}):
		bag3.addToBag(material, int(cp["maintenance"][material]));
	var normal = gm3.getObjectiveText(bag3, pm3);
	var objetivo3 = "%s: 0 / %d %s" % [cp.get("label", "Objetivo"), int(cp["quantity"]), cp["material"]];
	_check("una run normal enseña objetivo, mantenimiento reservado y contaminación",
		(objetivo3 in normal) and ("peaje reservado" in normal)
		and ("Contaminación: 77  (restaurar: ≤ 14)" in normal), normal);
	_check("y también cabe",
		normal.length() <= presupuesto,
		"%d caracteres de %d: %s" % [normal.length(), presupuesto, normal]);
	# El criterio del hito, literal: ningún camino del HUD enseña ya la escala.
	_check("ningún camino del HUD enseña ya el `/ 200` de la escala",
		not ("/ 200" in normal) and not ("/ 200" in colapso) and not ("/ 200" in restaurando),
		"%s || %s || %s" % [normal, colapso, restaurando]);
	_limpiar([esc["tm"], gm, bag, pm2, gm3, bag3, pm3]);

# ---------- Variedad M0: `accepts`, el checkpoint que admite dos materiales ----------

# El campo que hace posible el `*Hecho cuando:*` del M0. Las dos cadenas del juego tienen
# materiales DISJUNTOS —{wood, plank} contra {stone, brick}— y _can_afford() exige material a
# material, así que con un solo material por checkpoint cualquier curva mata a una de las dos
# estrategias. (Las cifras que lo apoyaban salieron de mediciones defectuosas, ya retiradas;
# el argumento se sostiene solo por la aritmética de _can_afford().)
# Estas pruebas fijan las tres cosas que el contrato promete: que su AUSENCIA no cambia nada,
# que los aceptados son UNA bolsa común, y que el peaje no se cuenta dos veces.
func _test_variedad_m0_accepts(file_data):
	print("Variedad M0 — `accepts`: un checkpoint con dos materiales aceptados");

	# --- El contrato, que es el mismo de `materials` y de `cost`: su ausencia significa
	# `[material]`. Sin esto, cada prueba que no lo declare mediría otro juego.
	var gm = _new_gm(file_data, [{ "material": "plank", "quantity": 10, "label": "Sin accepts" }]);
	var bag = _new_bag();
	bag.initialize(file_data);
	_check("un checkpoint sin `accepts` acepta exactamente su material",
		gm._accepted_materials(gm.checkpoints[0]) == ["plank"],
		str(gm._accepted_materials(gm.checkpoints[0])));
	bag.addToBag("plank", 4);
	bag.addToBag("stone", 99);
	_check("y el reparto con bolsa es el mismo que sin ella cuando no hay alternativas",
		gm._checkpoint_cost(gm.checkpoints[0], bag) == gm._checkpoint_cost(gm.checkpoints[0]),
		"%s contra %s" % [str(gm._checkpoint_cost(gm.checkpoints[0], bag)),
			str(gm._checkpoint_cost(gm.checkpoints[0]))]);
	gm.update(bag);
	_check("así que 99 de un material que no acepta no le cierran el checkpoint",
		gm.current_checkpoint_index == 0, "índice %d" % gm.current_checkpoint_index);
	_check("y el HUD sigue nombrando un solo material",
		gm._progressText(bag) == "Sin accepts: 4 / 10 plank", gm._progressText(bag));
	_limpiar([gm, bag]);

	# --- Los aceptados son UNA bolsa común: 6 tablones y 4 piedras cierran un objetivo de 10.
	# La alternativa se cobra DESPUÉS del material propio, que es el orden en que se declara.
	var curva = [
		{ "material": "plank", "quantity": 10, "accepts": ["stone"], "label": "Mixto" },
		{ "material": "plank", "quantity": 10, "label": "Dos" }
	];
	var gm2 = _new_gm(file_data, curva);
	var bag2 = _new_bag();
	bag2.initialize(file_data);
	bag2.addToBag("plank", 6);
	bag2.addToBag("stone", 3);
	gm2.update(bag2);
	_check("con 6 + 3 de los 10 el checkpoint no se cierra", gm2.current_checkpoint_index == 0,
		"índice %d" % gm2.current_checkpoint_index);
	_check("y el HUD enseña la bolsa común y los dos nombres",
		gm2._progressText(bag2) == "Mixto: 9 / 10 plank o stone", gm2._progressText(bag2));
	bag2.addToBag("stone", 7);
	gm2.update(bag2);
	_check("en cuanto la suma llega a 10 se cierra", gm2.current_checkpoint_index == 1);
	_check("y se cobra primero el material propio y solo después la alternativa",
		bag2.getQuantity("plank") == 0 and bag2.getQuantity("stone") == 6,
		"plank %d, stone %d" % [bag2.getQuantity("plank"), bag2.getQuantity("stone")]);
	_limpiar([gm2, bag2]);

	# --- Y el peaje no se cuenta dos veces. Es la trampa del reparto: si el objetivo pudiera
	# gastar la misma madera que el mantenimiento exige, el checkpoint se cerraría cobrando dos
	# veces unas unidades que solo existen una vez.
	var gm3 = _new_gm(file_data, [
		{ "material": "wood", "quantity": 10, "accepts": ["stone"], "label": "Con peaje",
			"maintenance": { "wood": 5 } },
		{ "material": "wood", "quantity": 10, "label": "Dos" }
	]);
	var bag3 = _new_bag();
	bag3.initialize(file_data);
	bag3.addToBag("wood", 10);
	bag3.addToBag("stone", 4);
	gm3.update(bag3);
	_check("la madera del peaje no cuenta también para el objetivo",
		gm3.current_checkpoint_index == 0, "índice %d" % gm3.current_checkpoint_index);
	bag3.addToBag("stone", 1);
	gm3.update(bag3);
	_check("con la quinta piedra sí se cierra, y la bolsa queda exactamente a cero",
		gm3.current_checkpoint_index == 1 and bag3.getQuantity("wood") == 0
		and bag3.getQuantity("stone") == 0,
		"índice %d, wood %d, stone %d" % [gm3.current_checkpoint_index,
			bag3.getQuantity("wood"), bag3.getQuantity("stone")]);
	_limpiar([gm3, bag3]);

	# --- La reserva. Se aparta el peaje entero y el objetivo solo si el material PROPIO es
	# materia prima; la alternativa NO se aparta aunque lo sea. Apartarla colgaría la run que
	# este campo vino a salvar: `stone` es el insumo de la Foundry, así que reservar las
	# unidades del checkpoint 3 dejaría a la cadena de piedra sin fabricar un solo `brick`.
	var gm4 = _new_gm(file_data, [{ "material": "wood", "quantity": 8, "accepts": ["stone"],
		"label": "Prima con alternativa" }]);
	var bag4 = _new_bag();
	bag4.initialize(file_data);
	# Con 3 piedras el checkpoint todavía no se cierra —cerrado, la reserva se levanta entera y
	# no habría nada que mirar—, que es exactamente el estado en que la reserva manda.
	bag4.addToBag("stone", 3);
	gm4.update(bag4);
	_check("stone es materia prima (la Quarry no consume nada)", gm4._is_raw_material("stone"));
	_check("el objetivo propio de materia prima se sigue reservando",
		bag4.getReserved("wood") == 8, "reservado %d" % bag4.getReserved("wood"));
	_check("pero la alternativa aceptada no se aparta ni un gramo",
		bag4.getReserved("stone") == 0 and bag4.getAvailable("stone") == 3,
		"reservado %d, disponible %d" % [bag4.getReserved("stone"), bag4.getAvailable("stone")]);
	_limpiar([gm4, bag4]);

	# --- El punto muerto: producir la alternativa mueve la run, así que tiene que romper la
	# condición 1. Sin esto, una cantera entregando sin parar contaría como «no se ha producido
	# nada» y la cuenta atrás correría con la fábrica funcionando.
	var gm5 = _new_gm(file_data, [{ "material": "plank", "quantity": 10, "accepts": ["stone"],
		"label": "Pendiente" }]);
	var bag5 = _new_bag();
	bag5.initialize(file_data);
	bag5.addToBag("stone", 3);
	_check("lo pendiente cuenta también la alternativa", gm5._pending_quantity(bag5) == 3,
		"pendiente %d" % gm5._pending_quantity(bag5));
	_limpiar([gm5, bag5]);

	# --- La curva REAL del JSON, que es la que fija este hito: el checkpoint 3 admite `plank`
	# o `stone` y el 4 y el 5 `plank` o `brick`, y todo lo que se acepta lo fabrica alguna
	# factoría del catálogo (aceptar un material que nadie produce sería un requisito muerto).
	#
	# 🔴 SON TRES Y NO DOS DESDE EL 2026-09-22, Y EL TERCERO ES EL QUE HACE QUE LA FUNDICIÓN
	# EXISTA. Con el `brick` pedido solo en el checkpoint FINAL, fabricarlo no compensaba hasta
	# el último tramo, y para entonces el tablero está lleno: la `Foundry` no se construía, así
	# que `brick` no existía y el `accepts` del checkpoint 5 era letra muerta. Bajar el
	# `brick` un eslabón le da a la segunda cadena un tramo propio en el que es la jugada
	# buena. Si alguien quita este `accepts`, la fundición vuelve a cero y con ella la mitad
	# del M0.
	var gm6 = _new_gm(file_data);
	var producidos = {};
	for nombre in file_data["Factories"]:
		var materiales = file_data["Factories"][nombre].get("materials", null);
		if materiales == null:
			materiales = [file_data["Factories"][nombre].get("material", null)];
		for m in materiales:
			if m != null:
				producidos[m] = true;
	var todos_producibles = true;
	var con_accepts = 0;
	for cp in file_data["Checkpoints"]:
		if not cp.get("accepts", []).is_empty():
			con_accepts += 1;
		for m in gm6._accepted_materials(cp):
			if not producidos.has(m):
				todos_producibles = false;
	_check("la curva real acepta un segundo material en tres checkpoints", con_accepts == 3,
		"%d checkpoints con accepts" % con_accepts);
	_check("y todo material aceptado lo fabrica alguna factoría del catálogo", todos_producibles);
	_check("el checkpoint 3 admite la cadena de piedra",
		gm6._accepted_materials(file_data["Checkpoints"][2]) == ["plank", "stone"],
		str(gm6._accepted_materials(file_data["Checkpoints"][2])));
	_check("el checkpoint 4 admite ya el ladrillo de la fundición",
		gm6._accepted_materials(file_data["Checkpoints"][3]) == ["plank", "brick"],
		str(gm6._accepted_materials(file_data["Checkpoints"][3])));
	# 🔴 EL 5 PIDE `glass` Y NO `brick`, Y ES LO QUE HACE VIVO EL DESPLEGABLE (Variedad M3,
	# 2026-09-22). El plan fijaba «`stone` en el 3 y `glass` en el 5» desde su redacción; el M0
	# tuvo que dejar `brick` ahí porque el `glass` no existía hasta que la `Foundry` declarara
	# sus `materials`, y el M3 es el hito que se los da. Con `brick` en los DOS tramos, `glass`
	# valdría exactamente lo mismo que `brick` para la curva y —siendo la opción que el diseño
	# quiere lenta— sería estrictamente peor: un desplegable con una opción muerta, que es el
	# fallo que ya costó el M0 («un material que nadie tiene razón para fabricar es un material
	# que nadie fabrica»). Con el 4 en `brick` y el 5 en `glass`, la fundición tiene un tramo
	# para cada material y cambiar de uno a otro es la jugada que el panel sirve.
	_check("y el 5 pide el vidrio, que es la razón por la que alguien lo fabrica",
		gm6._accepted_materials(file_data["Checkpoints"][4]) == ["plank", "glass"],
		str(gm6._accepted_materials(file_data["Checkpoints"][4])));
	_check("los dos tramos de la segunda cadena piden materiales DISTINTOS: el 4 no acepta `glass` ni el 5 `brick`",
		not gm6._accepted_materials(file_data["Checkpoints"][3]).has("glass")
		and not gm6._accepted_materials(file_data["Checkpoints"][4]).has("brick"));

	# --- Y CABE. Cada alternativa cuesta 8-9 caracteres de un presupuesto medido en pantalla, y
	# la línea más larga de la curva real —el checkpoint 3 con su peaje y la cola de
	# contaminación— es la que el jugador ve durante la mitad de la run.
	var presupuesto = load("res://managers/gameManager.gd").HUD_MAX_CHARS;
	var bag6 = _new_bag();
	bag6.initialize(file_data);
	gm6.current_checkpoint_index = 2;
	bag6.addToBag("plank", 30);
	bag6.addToBag("stone", 10);
	bag6.addToBag("wood", 10);
	var pm6 = _new_pm();
	pm6.addPollution(22607.0, Vector2i(5, 5));
	var linea = gm6.getObjectiveText(bag6, pm6);
	_check("el HUD del checkpoint 3 dice `40 / 55 plank o stone`",
		linea.begins_with("Checkpoint 3/5: 40 / 55 plank o stone"), linea);
	_check("y esa línea cabe en el Label de una sola línea", linea.length() <= presupuesto,
		"%d caracteres de %d: %s" % [linea.length(), presupuesto, linea]);
	# Y la del checkpoint 4, que desde el 2026-09-22 también nombra dos materiales: es el mismo
	# presupuesto de pantalla y el `accepts` nuevo no puede pasarse de él.
	gm6.current_checkpoint_index = 3;
	bag6.addToBag("brick", 6);
	var linea4 = gm6.getObjectiveText(bag6, pm6);
	_check("el HUD del checkpoint 4 nombra los dos materiales",
		linea4.begins_with("Checkpoint 4/5: ") and linea4.contains("plank o brick"), linea4);
	_check("y también cabe en el Label de una sola línea", linea4.length() <= presupuesto,
		"%d caracteres de %d: %s" % [linea4.length(), presupuesto, linea4]);
	# Y la del 5, que desde Variedad M3 nombra `glass`. Es el tramo con el peaje más caro de la
	# curva, así que es donde el presupuesto de pantalla aprieta más: `glass` mide lo mismo que
	# el `brick` al que sustituye, y esto es lo que lo deja dicho por si algún día el material
	# de este tramo se renombra a algo más largo.
	gm6.current_checkpoint_index = 4;
	bag6.addToBag("glass", 4);
	var linea5 = gm6.getObjectiveText(bag6, pm6);
	_check("el HUD del objetivo final pide `plank o glass`", linea5.contains("plank o glass"),
		linea5);
	_check("y esa línea también cabe", linea5.length() <= presupuesto,
		"%d caracteres de %d: %s" % [linea5.length(), presupuesto, linea5]);
	_limpiar([gm6, bag6, pm6]);

# ---------- Variedad M1: la cantera, `mineral` y el `stone` que llega al almacén ----------

# El `*Hecho cuando:*` del hito, entero y en tres tramos: una `Quarry` sobre `mineral` da 3 de
# `stone` por tick contra 1 fuera de ella, esa piedra llega al almacén por cinta, y lo que el
# almacén vuelca en la bolsa cierra un checkpoint que la acepta.
#
# El M0 dejó puesta la mitad declarativa —la entrada `Quarry`, el `adjacency_bonus` de
# `mineral`, las 8 casillas sembradas, los 15 de `stone` del paquete estándar y el
# `accepts: ["stone"]` del checkpoint 3—, así que la primera sección de este bloque la FIJA:
# valores provisionales: salieron de mediciones defectuosas, ya retiradas; aquí se fija la
# relación, no la cantidad.
#
# 🔴 Y no hay una sola línea de código nueva detrás de la circulación: `stone` viaja porque
# `beltNetwork.deliver()`, `factoryData.receiveMaterial()` y el volcado del almacén son
# GENÉRICOS por material, y cuenta porque los checkpoints lo son también. Estas pruebas son
# la red que impide que dejen de serlo — una excepción por material metida en cualquiera de
# los tres sitios rompería la segunda cadena sin romper ninguna prueba de la primera.
func _test_variedad_m1_cantera(file_data):
	print("Variedad M1 — la cantera, `mineral` y el `stone` que llega al almacén");

	# --- (1) El contrato declarativo. Todo en el JSON, nada hardcodeado.
	var q = file_data["Factories"].get("Quarry", null);
	_check("el JSON declara la factoría Quarry", q != null);
	if q == null:
		return;
	_check("produce `stone` y no consume nada: es la segunda GENERADORA del juego",
		q.get("material", "") == "stone" and q.get("recieve", "x") == null,
		"material %s, recieve %s" % [str(q.get("material", "")), str(q.get("recieve", "x"))]);
	_check("es de producción y pide un worker",
		q.get("type", "") == "production" and int(q.get("workers_needed", -1)) == 1,
		"type %s, workers %d" % [str(q.get("type", "")), int(q.get("workers_needed", -1))]);
	_check("no declara `materials`: elegir qué fabrica es de la Foundry, no suyo",
		not q.has("materials"));
	# El precio en piedra no es decoración: sin un solo precio pagadero en `stone`, una run de
	# piedra acaba con la bolsa llena de un material que no compra nada.
	_check("y se paga en `stone`, que es lo que le da un sumidero al material nuevo",
		q.get("cost", {}).has("stone"), str(q.get("cost", {})));
	# Las dos RELACIONES que fijan su personalidad: es la sucia y es la lenta. No se comprueba
	# el número —provisional— sino la relación con la cortadora, que es lo que el diseño
	# promete.
	var wc = file_data["Factories"]["WoodCutter"];
	_check("ensucia más que el WoodCutter: la piedra es el material sucio",
		float(q["pollution"]) > float(wc["pollution"]),
		"%.1f contra %.1f" % [float(q["pollution"]), float(wc["pollution"])]);
	_check("y va más lenta que él, que es la otra mitad de su personalidad",
		int(q["tick"]) > int(wc["tick"]), "tick %d contra %d" % [int(q["tick"]), int(wc["tick"])]);
	_check("ensucia más por SEGUNDO y no solo por tick (0,80/s contra 0,75/s)",
		float(q["pollution"]) / float(q["tick"]) > float(wc["pollution"]) / float(wc["tick"]),
		"%.2f/s contra %.2f/s" % [float(q["pollution"]) / float(q["tick"]),
			float(wc["pollution"]) / float(wc["tick"])]);

	# La casilla huérfana, que este hito estrena: `mineral` llevaba desde siempre declarada
	# «sin bonificador todavía».
	var mineral = file_data["TileTypes"]["mineral"];
	var bonus_mineral = mineral.get("adjacency_bonus", {});
	_check("`mineral` premia a la Quarry con +2 de output: deja de ser decorado",
		int(bonus_mineral.get("Quarry", {}).get("output_bonus", 0)) == 2,
		str(bonus_mineral));
	_check("y el premio es SUYO: la casilla no lleva comodín `*` que se lo dé a cualquiera",
		not bonus_mineral.has("*"), str(bonus_mineral.keys()));
	_check("`mineral` es construible, o el premio no tendría dónde cobrarse",
		mineral.get("buildable", false));
	# Sembrada en los DOS mapas (M0, 2026-09-20): con una sola casilla en una esquina de un
	# mapa, colocar la cantera no es una decisión de sitio sino un trámite.
	for mapa in file_data["Maps"]:
		var mid = str(mapa.get("id", "?"));
		var minerales = [];
		for sc in mapa.get("special_cells", []):
			if str(sc.get("type", "")) == "mineral":
				minerales.append(Vector2i(int(sc["pos"][0]), int(sc["pos"][1])));
		_check("%s siembra al menos 3 casillas `mineral`" % mid, minerales.size() >= 3,
			"%d: %s" % [minerales.size(), str(minerales)]);
		var repetidas = {};
		var unicas = true;
		for c in minerales:
			if repetidas.has(c):
				unicas = false;
			repetidas[c] = true;
		_check("%s: y ninguna repetida" % mid, unicas, str(minerales));

	# `stone` circula: no es ninguna de las dos excepciones que NO viajan por cinta.
	var excluidos = load("res://entities/factory/factoryData.gd").BELT_EXCLUDED_MATERIALS;
	_check("`stone` no está entre lo que no viaja por cinta (solo lo están worker y token)",
		not excluidos.has("stone"), str(excluidos));
	# La economía de la piedra: el paquete estándar trae con qué pagar la primera cantera.
	# Sin esto la piedra no compra nada y la cadena no arranca nunca.
	var stock = file_data["StartingPackages"]["standard"].get("starting_stock", {});
	_check("el paquete estándar trae piedra de sobra para pagar la primera cantera",
		int(stock.get("stone", 0)) >= int(q["cost"]["stone"]),
		"%d de stock contra %d de precio" % [int(stock.get("stone", 0)),
			int(q["cost"]["stone"])]);
	# --- (1b) Y la entrada tiene por dónde entrar en una run. La cantera NO viene en ningún
	# `StartingPackages.factories`: el camino por el que el jugador la consigue es el factory
	# token, que ofrece lo que todavía no tiene. Si alguien la metiera en el paquete, esta
	# prueba lo diría.
	# (Aquí decía además «y no puede venir sin rehacer el radial: con 6 opciones sus botones se
	# solapan». Eso YA está rehecho —Variedad M4b, 2026-09-22—: el radial aguanta hasta ocho
	# opciones sin un solo par montado, y su bloque de pruebas lo fija. Lo que queda es la
	# decisión de diseño de que la cantera se desbloquee, no una limitación de la pantalla.)
	var main_token = _new_main_en_arbol(file_data);
	var paquete_std = file_data["StartingPackages"]["standard"]["factories"];
	main_token.get_node("Player").availableFactories = paquete_std.duplicate();
	_check("la cantera no viene desbloqueada en el paquete estándar",
		not main_token.get_node("Player").availableFactories.has("Quarry"),
		str(main_token.get_node("Player").availableFactories));
	main_token._show_factory_token_screen();
	var pantalla = main_token.get_node_or_null("TokenUnlock");
	var ofrece_cantera = false;
	if pantalla != null:
		for t in _textos_de(pantalla):
			if t.contains("Desbloquear Quarry"):
				ofrece_cantera = true;
	_check("pero el factory token la ofrece, que es por donde entra en la run",
		ofrece_cantera, str(_textos_de(pantalla)) if pantalla != null else "sin pantalla");
	# Este script ES el SceneTree y la pantalla pausa el árbol: si no se levanta, la pausa se
	# queda puesta para el resto de la suite (misma trampa que en Cintas M3).
	paused = false;
	_limpiar([main_token]);

	# Y el material tiene cara propia en pantalla: el FX que sube al HUD no puede pintarse con
	# el color de «material desconocido», que es el que comparten todos los que nadie ha
	# declarado.
	var main_color = _new_main_de_prueba(file_data);
	_check("`stone` tiene su propio color en el FX, distinto del de un material sin declarar",
		main_color._get_material_color("stone") != main_color._get_material_color("__nada__"));
	_limpiar([main_color]);

	# --- (2) 3 CONTRA 1, por el camino real: factoryPlacer.build() sobre el TileMap.
	var main = _new_main_en_arbol(file_data);
	var tm = main.get_node("TileMap");
	# Suelo lejano: el ahogo se calcula sobre la contaminación POR CELDA y el
	# PollutionManager se busca por todo el árbol, así que una celda sucia heredada de otra
	# prueba mediría otra cosa. Se comprueba además con getPollutionChoke() más abajo.
	for x in range(100, 113):
		for y in range(100, 104):
			tm.set_cell(0, Vector2i(x, y), 1, Vector2i(0, 0));
	tm.cell_types[Vector2i(100, 100)] = "mineral";
	main.placer = load("res://entities/factory/factoryPlacer.gd").new();
	main.placer.initialize(load("res://entities/factory/factory.tscn"), file_data,
		main.factoryArray);
	var jugador = main.get_node("Player");
	var bolsa = main.get_node("Player/Bag");

	var encima = main.placer.build("Quarry", Vector2i(100, 100), jugador, bolsa, tm);
	main.add_child(encima);
	main.placer.register_and_evaluate(encima, Vector2i(100, 100));
	var fuera = main.placer.build("Quarry", Vector2i(104, 100), jugador, bolsa, tm);
	main.add_child(fuera);
	main.placer.register_and_evaluate(fuera, Vector2i(104, 100));
	_check("las dos canteras arrancan con sus dos workers y sobre suelo limpio",
		encima.isActive() and fuera.isActive()
		and _near(encima.getPollutionChoke(), 1.0) and _near(fuera.getPollutionChoke(), 1.0),
		"choke %.2f y %.2f" % [encima.getPollutionChoke(), fuera.getPollutionChoke()]);
	_check("🔴 la cantera SOBRE `mineral` produce 3 y la de fuera 1",
		encima.getEffectiveOutput() == 3 and fuera.getEffectiveOutput() == 1,
		"encima %d, fuera %d" % [encima.getEffectiveOutput(), fuera.getEffectiveOutput()]);
	# Y no es solo el techo: el tick entrega esos 3. getEffectiveOutput() es lo que la
	# factoría PODRÍA dar —de ahí sale el tier de la recompensa— y lo que se produce de
	# verdad sale por la señal, que es lo que Main encamina por la red.
	var dado_encima = [0];
	var dado_fuera = [0];
	encima.resource_produced.connect(func(_m, c, _p): dado_encima[0] += c);
	fuera.resource_produced.connect(func(_m, c, _p): dado_fuera[0] += c);
	encima.update();
	fuera.update();
	_check("y un tick de cada una entrega 3 de `stone` contra 1",
		dado_encima[0] == 3 and dado_fuera[0] == 1,
		"%d contra %d" % [dado_encima[0], dado_fuera[0]]);
	# El bonus es de la casilla de DEBAJO, no de las vecinas: es la regla de
	# _apply_tile_adjacency_bonus() y es lo que hace que colocar la cantera sea una decisión
	# de sitio. Esta tercera se queda sin worker (solo hay 2) y por eso solo se mira su techo.
	var pegada = main.placer.build("Quarry", Vector2i(101, 101), jugador, bolsa, tm);
	main.add_child(pegada);
	main.placer.register_and_evaluate(pegada, Vector2i(101, 101));
	_check("una cantera PEGADA a la casilla mineral, pero no encima, produce 1",
		pegada.getEffectiveOutput() == 1, "output %d" % pegada.getEffectiveOutput());
	# Y el recálculo de las 8 vecinas al demoler —que resetea los acumuladores— no puede
	# borrar el +2 del tile: sin el segundo paso de recompute_synergies() la cantera perdería
	# su bonus para siempre en cuanto alguien demoliera algo a su lado.
	for i in range(5):
		main.placer.recompute_synergies(encima, tm);
	_check("recalcular sus sinergias 5 veces no pierde ni multiplica el +2 de `mineral`",
		encima.getEffectiveOutput() == 3, "output %d" % encima.getEffectiveOutput());
	_limpiar([main.placer, main]);

	# --- (3) y (4) El camino entero: la cantera paga con la piedra del paquete, produce sobre
	# `mineral`, el material cruza la red, el almacén lo vuelca en la bolsa y eso —y solo
	# eso— cierra un checkpoint que acepta `stone`.
	var main2 = _new_main_en_arbol(file_data);
	var tm2 = main2.get_node("TileMap");
	for x in range(100, 113):
		for y in range(100, 104):
			tm2.set_cell(0, Vector2i(x, y), 1, Vector2i(0, 0));
	tm2.cell_types[Vector2i(100, 100)] = "mineral";
	main2.placer = load("res://entities/factory/factoryPlacer.gd").new();
	main2.placer.initialize(load("res://entities/factory/factory.tscn"), file_data,
		main2.factoryArray);
	var red = load("res://managers/beltNetwork.gd").new();
	red.name = "BeltNetwork";
	main2.add_child(red);
	red.initialize(tm2, main2.factoryArray, file_data);
	tm2.setBeltNetwork(red);
	main2.beltNetwork = red;
	var jugador2 = main2.get_node("Player");
	var bolsa2 = main2.get_node("Player/Bag");
	# El almacén, gratis: lo coloca el mapa (mapLoader.place_storage()), no el jugador.
	var almacen = main2.placer.build("Storage", Vector2i(106, 100), jugador2, bolsa2, tm2);
	main2.add_child(almacen);
	main2.placer.register_and_evaluate(almacen, Vector2i(106, 100));

	# La piedra del paquete estándar es la que paga la cantera, y se coloca por el GESTO del
	# jugador —el único camino que cobra—, no a mano.
	bolsa2.addToBag("stone", int(stock.get("stone", 0)));
	var piedra_inicial = bolsa2.getQuantity("stone");
	main2._on_factory_chosen("Quarry", Vector2i(100, 100));
	var cantera = null;
	for f in main2.factoryArray:
		if f.type == "Quarry":
			cantera = f;
	_check("la cantera se coloca y se paga con la piedra que trae el paquete estándar",
		cantera != null
		and bolsa2.getQuantity("stone") == piedra_inicial - int(q["cost"]["stone"]),
		"stone %d, esperados %d" % [bolsa2.getQuantity("stone"),
			piedra_inicial - int(q["cost"]["stone"])]);
	if cantera == null:
		_limpiar([main2.placer, main2]);
		return;
	_check("y sobre `mineral` nace dando 3, que es lo que el jugador va a ver salir",
		cantera.getEffectiveOutput() == 3 and _near(cantera.getPollutionChoke(), 1.0),
		"output %d, choke %.2f" % [cantera.getEffectiveOutput(), cantera.getPollutionChoke()]);

	var tendida = red.place_drag(Vector2i(101, 100), Vector2i(105, 100), main2.factoryArray);
	_check("la cinta se tiende de la cantera al almacén sin tocar ninguno de los dos",
		tendida.size() == 5, "tendió %s" % str(tendida));

	# La bolsa se deja a cero de piedra: lo que quedaba del paquete es stock de salida y
	# taparía justo lo que este tramo quiere ver, que es la piedra que LLEGA.
	bolsa2.removeFromBag("stone", bolsa2.getQuantity("stone"));
	var gm = _new_gm(file_data, [
		{ "material": "plank", "quantity": 3, "accepts": ["stone"], "label": "Pide piedra" },
		{ "material": "plank", "quantity": 99, "label": "Dos" }
	]);
	gm.update(bolsa2, null);
	_check("con la bolsa vacía, el checkpoint que acepta `stone` no se mueve",
		gm.current_checkpoint_index == 0, "índice %d" % gm.current_checkpoint_index);

	cantera.update();
	_check("un tick manda los 3 de `stone` por la red hasta el búfer del almacén",
		int(almacen.input_buffer.get("stone", 0)) == 3 and cantera.output_buffer == 0,
		"búfer del almacén %s, atasco de la cantera %d" % [str(almacen.input_buffer),
			cantera.output_buffer]);
	gm.update(bolsa2, null);
	_check("lo que va por la cinta todavía no cuenta: solo cuenta lo que el almacén vuelca",
		bolsa2.getQuantity("stone") == 0 and gm.current_checkpoint_index == 0,
		"stone %d, índice %d" % [bolsa2.getQuantity("stone"), gm.current_checkpoint_index]);
	almacen.update(bolsa2);
	_check("🔴 el tick del almacén pone los 3 de `stone` en la bolsa",
		bolsa2.getQuantity("stone") == 3 and almacen.input_buffer.is_empty(),
		"stone %d, búfer %s" % [bolsa2.getQuantity("stone"), str(almacen.input_buffer)]);
	_check("y salen por el HUD de recursos, que lee la bolsa",
		main2._buildResourceText(bolsa2).contains("stone: 3"),
		main2._buildResourceText(bolsa2));
	gm.update(bolsa2, null);
	_check("🔴 y esos 3 cierran el checkpoint que pide `plank` o `stone`",
		gm.current_checkpoint_index == 1, "índice %d, stone %d" % [
			gm.current_checkpoint_index, bolsa2.getQuantity("stone")]);
	_check("la curva REAL acepta `stone` en el checkpoint 3, que es donde la piedra cuenta",
		gm._accepted_materials(file_data["Checkpoints"][2]).has("stone"),
		str(gm._accepted_materials(file_data["Checkpoints"][2])));

	# Y la cara negativa, que es la regla entera del almacén: sin cinta que llegue a él la
	# piedra no entra en la bolsa, se le queda a la cantera en el búfer de salida y acaba
	# parándola (Cintas M4). Una segunda cantera, sin cinta y sobre suelo pelado.
	var muda = main2.placer.build("Quarry", Vector2i(100, 103), jugador2, bolsa2, tm2);
	main2.add_child(muda);
	main2.placer.register_and_evaluate(muda, Vector2i(100, 103));
	muda.resource_produced.connect(main2._on_resource_produced.bind(muda));
	var antes_muda = bolsa2.getQuantity("stone");
	muda.update();
	almacen.update(bolsa2);
	_check("una cantera sin cinta al almacén no pone ni una piedra en la bolsa",
		bolsa2.getQuantity("stone") == antes_muda and muda.output_buffer > 0,
		"stone %d, atasco %d" % [bolsa2.getQuantity("stone"), muda.output_buffer]);
	_limpiar([gm, main2.placer, main2]);

# ---------- Variedad M2: el rescate, con las DOS cadenas dentro ----------

# El `*Hecho cuando:*` de este hito tras su enmienda del 2026-09-22: «la mejora de rescate se
# sigue concediendo cuando falta la factoría necesaria». La otra mitad —que la curva pida las
# dos cadenas— la dejó puesta el M0 y la fija el bloque «Variedad M0»; y la que decía «una run
# que solo monta madera no pasa del checkpoint 3» se TACHÓ, porque `accepts` es un O y se
# eligió así a propósito.
#
# Lo que cambia son las dos funciones del rescate, y las dos por herencia de hitos anteriores:
#
# 1. **Se mira `materials[]`, no solo `material`.** La `Foundry` declarará `material: "brick"`
#    con `glass` en su lista (M3), así que un checkpoint que pidiera `glass` no encontraría
#    rescate y la run se colgaría sin salida. Aquí se prueba sobre un catálogo SINTÉTICO
#    —`materials` se le añade a una copia en memoria— porque esa entrada del JSON es del M3.
# 2. **Falta un material cuando NINGUNO de los aceptados es producible.** Con `accepts: [...]`
#    (M0) el objetivo es una bolsa común: mirar solo el material propio daba por bloqueado un
#    checkpoint que la otra cadena sí sabía cerrar, y concedía cartas que no rescatan de nada.
#
# El mantenimiento NO hereda esa regla y por eso se prueba aparte: es un `material -> cantidad`
# que _can_afford() exige material a material, no una bolsa común.
func _test_variedad_m2_rescate(file_data):
	print("Variedad M2 — la mejora de rescate se sigue concediendo cuando falta la factoría");

	var paquetes = file_data["StartingPackages"];

	# --- (1) El contrato de `materials[]` sobre el catálogo REAL: su ausencia significa
	# `[material]`, así que las OTRAS ocho entradas no cambian de comportamiento. La novena es
	# la `Foundry`, que lo declara desde Variedad M3 (2026-09-22): cuando este bloque se
	# escribió no lo declaraba ninguna y la multi-material había que fabricarla en memoria; hoy
	# el caso de uso es real y esta comprobación pasa a medirlo sobre el JSON del juego.
	var gm_contrato = _new_gm(file_data);
	var declaran = [];
	for nombre in file_data["Factories"]:
		if file_data["Factories"][nombre].has("materials"):
			declaran.append(nombre);
	_check("solo la Foundry declara `materials` en el JSON del juego", declaran == ["Foundry"],
		"lo declaran %s" % str(declaran));
	_check("y sin declararlo, una factoría vale exactamente por su `material`",
		gm_contrato._factory_materials("WoodProcessing") == ["plank"]
		and gm_contrato._factory_materials("Quarry") == ["stone"],
		"%s / %s" % [str(gm_contrato._factory_materials("WoodProcessing")),
			str(gm_contrato._factory_materials("Quarry"))]);
	_check("y la que sí lo declara vale por su lista entera: la Foundry rescata `brick` y `glass`",
		gm_contrato._factory_materials("Foundry") == ["brick", "glass"],
		str(gm_contrato._factory_materials("Foundry")));
	_check("una factoría de `material: null` no fabrica nada que un checkpoint pueda pedir",
		gm_contrato._factory_materials("Reforester").is_empty()
		and gm_contrato._factory_materials("WaterTreatment").is_empty()
		and gm_contrato._factory_materials("Storage").is_empty());
	_check("y un nombre que no está en el catálogo tampoco",
		gm_contrato._factory_materials("NoExiste").is_empty());
	_limpiar([gm_contrato]);

	# --- (2) La multi-material: el rescate tiene que verla por su `materials[]`.
	# Copia en memoria con lo que el M3 escribirá en el JSON, más una carta que la desbloquee
	# (la carta de verdad es del M5; hoy las tres nuevas entran por el factory token).
	var fd_multi = file_data.duplicate(true);
	fd_multi["Factories"]["Foundry"]["materials"] = ["brick", "glass"];
	fd_multi["Upgrades"]["unlock_foundry"] = {
		"name": "Horno de campaña",
		"description": "Desbloquea Foundry.",
		"type": "unlock_factory",
		"factory": "Foundry",
		"tier": 1
	};
	var curva_glass = [{ "material": "glass", "quantity": 20, "label": "Único" }];
	var gm_glass = _new_gm(fd_multi, curva_glass);
	var estandar = StubPlayer.new();
	estandar.availableFactories = paquetes["standard"]["factories"].duplicate();
	gm_glass.setPlayer(estandar);
	_check("🔴 una multi-material rescata por su `materials[]`: la Foundry desatasca un checkpoint de `glass`",
		gm_glass._rescue_upgrades(gm_glass._usable_upgrades()) == ["unlock_foundry"],
		"rescate %s" % str(gm_glass._rescue_upgrades(gm_glass._usable_upgrades())));
	_check("y se CONCEDE, que es lo que el `*Hecho cuando:*` pide",
		gm_glass._granted_upgrades() == ["unlock_foundry"],
		"concedidas %s" % str(gm_glass._granted_upgrades()));
	_check("la concedida sale de la baraja: la pantalla sigue ofreciendo 3 cartas distintas",
		not gm_glass._pick_upgrades(3, 1, gm_glass._granted_upgrades()).has("unlock_foundry")
		and _sin_repetidas(gm_glass._pick_upgrades(3, 1, gm_glass._granted_upgrades())));

	# El control de que lo de arriba no pasa en vacío: la MISMA carta y la MISMA curva con la
	# Foundry de hoy —sin `materials[]`— no rescatan nada. Es exactamente la run colgada que
	# este hito viene a impedir, y la razón por la que mirar solo `material` no vale.
	var fd_simple = file_data.duplicate(true);
	# El `materials` se le QUITA a mano: desde Variedad M3 el JSON del juego ya lo trae, y el
	# control tiene que seguir siendo la fundición de un solo material —que es la que no
	# rescataría— y no la de hoy.
	fd_simple["Factories"]["Foundry"].erase("materials");
	fd_simple["Upgrades"]["unlock_foundry"] = fd_multi["Upgrades"]["unlock_foundry"].duplicate();
	var gm_simple = _new_gm(fd_simple, curva_glass);
	gm_simple.setPlayer(estandar);
	_check("control: sin `materials[]` ese mismo checkpoint de `glass` se queda SIN rescate",
		gm_simple._rescue_upgrades(gm_simple._usable_upgrades()).is_empty(),
		"rescate %s" % str(gm_simple._rescue_upgrades(gm_simple._usable_upgrades())));
	# Y la mitad que no se puede mover: por su material de siempre rescata igual que antes.
	var curva_brick = [{ "material": "brick", "quantity": 20, "label": "Único" }];
	var gm_brick = _new_gm(fd_simple, curva_brick);
	gm_brick.setPlayer(estandar);
	var gm_brick_multi = _new_gm(fd_multi, curva_brick);
	gm_brick_multi.setPlayer(estandar);
	_check("por su `material` de siempre rescata igual, declare o no `materials[]`",
		gm_brick._granted_upgrades() == ["unlock_foundry"]
		and gm_brick_multi._granted_upgrades() == ["unlock_foundry"]);
	_limpiar([gm_brick, gm_brick_multi]);

	# --- (3) La consecuencia de `accepts`: falta un material cuando NINGUNO de los aceptados
	# es producible. Mismo checkpoint de `glass`, pero aceptando además `plank`, que el
	# jugador estándar YA sabe fabricar.
	var gm_o = _new_gm(fd_multi, [
		{ "material": "glass", "quantity": 20, "accepts": ["plank"], "label": "Único" }
	]);
	gm_o.setPlayer(estandar);
	_check("🔴 un checkpoint con `accepts` no se da por bloqueado si UNO de los suyos es producible",
		gm_o._unproducible_materials().is_empty(),
		"faltan %s" % str(gm_o._unproducible_materials()));
	_check("y por eso no concede una carta que no rescataría de nada",
		gm_o._granted_upgrades().is_empty(), "concedidas %s" % str(gm_o._granted_upgrades()));
	_check("control: el MISMO checkpoint sin `accepts` sí fija la carta",
		gm_glass._granted_upgrades() == ["unlock_foundry"]);
	_limpiar([gm_o, gm_glass, gm_simple]);

	# Y sobre la curva REAL, con el jugador que solo sabe la cadena de piedra: el checkpoint 3
	# pide `plank` o `stone`, y con la cantera puesta no hay nada que desatascar.
	var piedra = StubPlayer.new();
	piedra.availableFactories = ["WoodCutter", "Quarry", "Reforester", "MetaFactory", "WorkerCamp"];
	var gm_cp3 = _new_gm(file_data, [file_data["Checkpoints"][2]]);
	gm_cp3.setPlayer(piedra);
	_check("🔴 con la curva REAL, el checkpoint 3 (`plank` o `stone`) no bloquea a quien sabe piedra",
		gm_cp3._unproducible_materials().is_empty() and gm_cp3._granted_upgrades().is_empty(),
		"faltan %s, concedidas %s" % [str(gm_cp3._unproducible_materials()),
			str(gm_cp3._granted_upgrades())]);
	# El checkpoint 4 acepta `plank` o `brick` y ese jugador no sabe ninguno de los dos: ahí
	# faltan LOS DOS, y cualquiera de las dos cadenas lo desatasca.
	var gm_cp4 = _new_gm(fd_multi, [file_data["Checkpoints"][3]]);
	gm_cp4.setPlayer(piedra);
	var faltan_cp4 = gm_cp4._unproducible_materials();
	_check("el checkpoint 4 sí bloquea a ese jugador, y por los DOS materiales que acepta",
		faltan_cp4.has("plank") and faltan_cp4.has("brick") and faltan_cp4.size() == 2,
		"faltan %s" % str(faltan_cp4));
	var concedidas_cp4 = gm_cp4._granted_upgrades();
	_check("y se conceden las dos cartas: cualquiera de las dos cadenas lo cierra",
		concedidas_cp4.size() == 2 and concedidas_cp4.has("unlock_woodprocessing")
		and concedidas_cp4.has("unlock_foundry"), "concedidas %s" % str(concedidas_cp4));
	_limpiar([gm_cp3, gm_cp4]);

	# El mantenimiento NO es una bolsa común: se exige material a material, así que un peaje
	# que el jugador no sabe fabricar fija la carta aunque el objetivo esté cubierto de sobra.
	var gm_mant = _new_gm(file_data, [
		{ "material": "wood", "quantity": 15, "accepts": ["stone"], "label": "Único",
			"maintenance": { "plank": 5 } }
	]);
	var lenador = StubPlayer.new();
	lenador.availableFactories = paquetes["lumberjack"]["factories"].duplicate();
	gm_mant.setPlayer(lenador);
	_check("el mantenimiento se exige material a material: `accepts` no lo diluye",
		gm_mant._unproducible_materials().has("plank")
		and gm_mant._granted_upgrades() == ["unlock_woodprocessing"],
		"faltan %s, concedidas %s" % [str(gm_mant._unproducible_materials()),
			str(gm_mant._granted_upgrades())]);
	_limpiar([gm_mant]);

	# Sin Player no hay partida que desatascar, y sigue sin fijarse nada: un montaje a medias
	# no debe dejar clavadas cartas que aquí no rescatan de nada.
	var gm_sin_jugador = _new_gm(fd_multi, curva_glass);
	_check("sin Player el rescate sigue devolviendo vacío",
		gm_sin_jugador._rescue_upgrades(gm_sin_jugador._usable_upgrades()).is_empty());
	_limpiar([gm_sin_jugador]);

	# --- (4) 🔴 El caso que NO se puede mover: `unlock_woodprocessing` nunca entra en el
	# reparto —en `standard` la filtra _usable_upgrades(), en los otros dos se concede antes—,
	# y con las 5 cartas de tier 1 que quedan hay 10 manos posibles, todas alcanzables.
	var gm_real = _new_gm(file_data);
	var estandar2 = StubPlayer.new();
	estandar2.availableFactories = paquetes["standard"]["factories"].duplicate();
	gm_real.setPlayer(estandar2);
	_check("en standard la serrería no entra siquiera en la baraja y no se concede nada",
		not gm_real._usable_upgrades().has("unlock_woodprocessing")
		and gm_real._granted_upgrades().is_empty(),
		"concedidas %s" % str(gm_real._granted_upgrades()));
	for paquete in ["lumberjack", "ecologist"]:
		var jugador = StubPlayer.new();
		jugador.availableFactories = paquetes[paquete]["factories"].duplicate();
		gm_real.setPlayer(jugador);
		_check("en %s se sigue CONCEDIENDO la serrería con la curva real" % paquete,
			gm_real._granted_upgrades() == ["unlock_woodprocessing"],
			"concedidas %s" % str(gm_real._granted_upgrades()));
	for paquete in ["standard", "lumberjack", "ecologist"]:
		var jugador = StubPlayer.new();
		jugador.availableFactories = paquetes[paquete]["factories"].duplicate();
		gm_real.setPlayer(jugador);
		var concedidas = gm_real._granted_upgrades();
		var manos = {};
		var colada = false;
		for i in range(300):
			var mano = gm_real._pick_upgrades(3, 1, concedidas);
			if mano.has("unlock_woodprocessing"):
				colada = true;
			mano.sort();
			manos[str(mano)] = true;
		_check("en %s la serrería no se cuela en 300 pantallas y salen las 10 manos" % paquete,
			not colada and manos.size() == 10, "%d manos, colada=%s" % [manos.size(), str(colada)]);
	# En cuanto se desbloquea deja de concederse: el rescate es para salir del atasco.
	var lenador2 = StubPlayer.new();
	lenador2.availableFactories = paquetes["lumberjack"]["factories"].duplicate();
	lenador2.availableFactories.append("WoodProcessing");
	gm_real.setPlayer(lenador2);
	_check("tras desbloquearla, ni se concede ni vuelve a la baraja",
		gm_real._granted_upgrades().is_empty()
		and not gm_real._usable_upgrades().has("unlock_woodprocessing"));
	_limpiar([gm_real]);

# ---------- Variedad M3: la fundición y el selector de material, por fin en pantalla ----------

# El `*Hecho cuando:*` del hito, entero y en sus tres partes: el panel de una `Foundry` monta el
# desplegable con DOS opciones, cambiar de material NO reinicia su tick ni su `production_debt`,
# y lo nuevo sale por su cinta.
#
# 🔴 Y LA PREGUNTA QUE ESTE BLOQUE CONTESTA ANTES QUE NINGUNA: ¿POR QUÉ FABRICARÍA ALGUIEN
# `glass`? Porque el **objetivo final lo pide y no acepta `brick`**, mientras que el checkpoint 4
# pide `brick` y no acepta `glass`. Sin eso, los dos materiales valdrían exactamente lo mismo
# para la curva y el desplegable tendría una opción muerta — que es, con otro nombre, el fallo
# que ya costó el M0: «un material que nadie tiene razón para fabricar es un material que nadie
# fabrica». El plan lo llevaba fijado desde su redacción («`stone` en el 3 y `glass` en el 5»);
# lo que faltaba era que el `glass` existiera, y existe desde este hito.
#
# La infraestructura NO es nueva —`materials: [...]`, `hasMaterialChoice()` y `setProduction()`
# son del 2026-09-17 y el desplegable del panel ya lo estrenó el almacén—, así que lo que estas
# pruebas fijan es el primer caso ESTÁTICO: una lista que sale del JSON, no de la bolsa.
func _test_variedad_m3_fundicion(file_data):
	print("Variedad M3 — la fundición y el selector de material");

	var f = file_data["Factories"]["Foundry"];

	# --- (1) El contrato declarativo: todo en el JSON, nada hardcodeado ---
	_check("la Foundry declara los dos materiales entre los que se elige",
		f.get("materials", null) == ["brick", "glass"], str(f.get("materials", null)));
	_check("y se sigue COLOCANDO con `brick`, que es su `material` de siempre y está en la lista",
		f["material"] == "brick" and f["materials"].has(f["material"]), str(f["material"]));
	# Valores provisionales: salieron de mediciones defectuosas, ya retiradas; aquí se congela el
	# valor actual del JSON: este hito le añade a la fundición una decisión, no un balance.
	_check("los valores actuales del JSON no se han movido",
		int(f["tick"]) == 4 and _near(float(f["pollution"]), 3.0)
		and int(f["workers_needed"]) == 1 and f["recieve"] == ["stone"]
		and int(f["cost"]["wood"]) == 6 and int(f["cost"]["stone"]) == 12, str(f));

	# `glass` es el primer material del juego que no es el `material` de NADIE: solo existe como
	# candidato. De ahí que todo lo que enumere materiales tenga que leer `materials[]` y no solo
	# `material` —el filtro de cinta del panel y el rescate de gameManager son los dos sitios—.
	var es_material_de_alguien = [];
	for nombre in file_data["Factories"]:
		if file_data["Factories"][nombre].get("material", null) == "glass":
			es_material_de_alguien.append(nombre);
	_check("`glass` no es el `material` de ninguna entrada: vive solo en la lista de candidatos",
		es_material_de_alguien.is_empty(), str(es_material_de_alguien));
	var excluidos = load("res://entities/factory/factoryData.gd").BELT_EXCLUDED_MATERIALS;
	_check("y los dos viajan por cinta: ninguno es `worker` ni `factory_token`",
		not excluidos.has("brick") and not excluidos.has("glass"));

	# --- (2) 🔴 LA RAZÓN PARA ELEGIR: la curva pide uno en cada tramo ---
	var gm_curva = _new_gm(file_data);
	var cp4 = gm_curva._accepted_materials(file_data["Checkpoints"][3]);
	var cp5 = gm_curva._accepted_materials(file_data["Checkpoints"][4]);
	_check("🔴 el checkpoint 4 acepta `brick` y NO `glass`",
		cp4.has("brick") and not cp4.has("glass"), str(cp4));
	_check("🔴 y el objetivo final acepta `glass` y NO `brick`: cambiar de material es la jugada",
		cp5.has("glass") and not cp5.has("brick"), str(cp5));
	_check("el rescate ve la fundición por sus DOS materiales, así que un final de `glass` no cuelga la run",
		gm_curva._factory_materials("Foundry") == ["brick", "glass"],
		str(gm_curva._factory_materials("Foundry")));
	_limpiar([gm_curva]);

	# --- El montaje: una fundición colocada por el GESTO del jugador, con su almacén y su red ---
	# Celdas lejanas y limpias: `_apply_pollution()` localiza el PRIMER PollutionManager del
	# árbol, así que la suciedad heredada de otra prueba ahogaría el tick y esto mediría otra cosa.
	var main = _new_main_en_arbol(file_data);
	var tm = main.get_node("TileMap");
	for x in range(200, 213):
		for y in range(200, 204):
			tm.set_cell(0, Vector2i(x, y), 1, Vector2i(0, 0));
	main.placer = load("res://entities/factory/factoryPlacer.gd").new();
	main.placer.initialize(load("res://entities/factory/factory.tscn"), file_data,
		main.factoryArray);
	var red = load("res://managers/beltNetwork.gd").new();
	red.name = "BeltNetwork";
	main.add_child(red);
	red.initialize(tm, main.factoryArray, file_data);
	tm.setBeltNetwork(red);
	main.beltNetwork = red;
	var jugador = main.get_node("Player");
	var bolsa = main.get_node("Player/Bag");
	var almacen = main.placer.build("Storage", Vector2i(206, 200), jugador, bolsa, tm);
	main.add_child(almacen);
	main.placer.register_and_evaluate(almacen, Vector2i(206, 200));

	bolsa.addToBag("wood", int(f["cost"]["wood"]));
	bolsa.addToBag("stone", int(f["cost"]["stone"]));
	main._on_factory_chosen("Foundry", Vector2i(200, 200));
	var fundicion = null;
	var cortadora = null;
	for nodo in main.factoryArray:
		if nodo.type == "Foundry":
			fundicion = nodo;
	_check("la fundición se coloca por el camino real y arranca fabricando `brick`",
		fundicion != null and fundicion.production == "brick", str(fundicion));
	if fundicion == null:
		_limpiar([main.placer, main]);
		return;
	_check("y con sus dos candidatos cargados del JSON, así que tiene algo que elegir",
		fundicion.production_candidates == ["brick", "glass"] and fundicion.hasMaterialChoice(),
		str(fundicion.production_candidates));
	_check("el worker del paquete se le ha asignado: sin él no produciría nada",
		fundicion.isActive() and fundicion.workers_assigned == 1);

	# --- (3) EL DESPLEGABLE, que es la mitad del hito que se ve ---
	var panel = load("res://ui/factoryPanel.gd").new();
	root.add_child(panel);
	panel.initialize(fundicion, file_data, Vector2(640, 360), bolsa, red);
	_check("🔴 el panel de una Foundry monta el desplegable de material",
		panel._material_option != null);
	if panel._material_option == null:
		_limpiar([panel, main.placer, main]);
		return;
	_check("con DOS opciones y en el orden del JSON",
		panel._material_option.item_count == 2
		and panel._material_option.get_item_text(0) == "brick"
		and panel._material_option.get_item_text(1) == "glass",
		"%d opciones" % panel._material_option.item_count);
	_check("y marcando lo que la fundición produce AHORA, no el primero de la lista",
		panel._material_option.get_item_text(panel._material_option.selected) == "brick",
		panel._material_option.get_item_text(panel._material_option.selected));
	# Y `glass` se puede encaminar: el filtro de la cinta lee `materials[]`, no solo `material`.
	var textos_filtro = [];
	for i in range(panel._belt_option.item_count):
		textos_filtro.append(panel._belt_option.get_item_text(i));
	_check("el filtro de cinta ofrece también `glass`, que no es el `material` de nadie",
		textos_filtro.has("glass") and textos_filtro.has("brick"), str(textos_filtro));

	# El control, que es lo que hace que el desplegable signifique algo: una factoría de un solo
	# material NO lo monta y sigue enseñando su etiqueta de siempre.
	cortadora = main.placer.build("WoodCutter", Vector2i(200, 203), jugador, bolsa, tm);
	main.add_child(cortadora);
	main.placer.register_and_evaluate(cortadora, Vector2i(200, 203));
	var panel_wc = load("res://ui/factoryPanel.gd").new();
	root.add_child(panel_wc);
	panel_wc.initialize(cortadora, file_data, Vector2(640, 360), bolsa, red);
	_check("el panel de una WoodCutter no monta NINGÚN desplegable de material",
		panel_wc._material_option == null);
	var texto_produce = "";
	for lbl in panel_wc.find_children("", "Label", true, false):
		if str(lbl.text).begins_with("Produce:"):
			texto_produce = str(lbl.text);
	_check("y en su lugar dice «Produce: wood», que es el panel de siempre",
		texto_produce == "Produce: wood", texto_produce);

	# --- (4) CAMBIAR DE MATERIAL NO ES UNA FACTORÍA NUEVA ---
	# El `Timer` de factory.tscn y su contador de timeouts llevan el tick a medio cumplir, y
	# `production_debt` arrastra la producción fraccionaria que el ahogo dejó a deber. Reiniciar
	# cualquiera de los tres al cambiar de material sería un exploit —saltarse el tick a medio
	# cumplir— o un castigo invisible, y el desajuste no se vería hasta medir el balance.
	var reloj = fundicion.get_node("Timer");
	fundicion.production_debt = 0.4;
	fundicion.timer = 7;
	var espera = reloj.wait_time;
	var parado = reloj.is_stopped();
	panel._material_option.item_selected.emit(1);
	_check("🔴 elegir `glass` en el desplegable cambia lo que la fundición fabrica",
		fundicion.production == "glass", str(fundicion.production));
	_check("🔴 y NO reinicia el Timer, ni su contador de ticks, ni toca `production_debt`",
		_near(fundicion.production_debt, 0.4) and fundicion.timer == 7
		and reloj.wait_time == espera and reloj.is_stopped() == parado,
		"deuda %f, timer %d, wait %f" % [fundicion.production_debt, fundicion.timer,
			reloj.wait_time]);
	_check("el panel se repinta in situ en vez de remontarse: sigue vivo y marcando el nuevo",
		not panel.is_queued_for_deletion()
		and panel._material_option.get_item_text(panel._material_option.selected) == "glass",
		panel._material_option.get_item_text(panel._material_option.selected));

	# --- (5) LO NUEVO SALE POR SU CINTA ---
	var tendida = red.place_drag(Vector2i(201, 200), Vector2i(205, 200), main.factoryArray);
	_check("la cinta se tiende de la fundición al almacén sin tocar ninguno de los dos",
		tendida.size() == 5, "tendió %s" % str(tendida));
	# La bolsa se deja sin piedra ni vidrio: lo que quedara taparía justo lo que este tramo
	# quiere ver, que es lo que LLEGA por la cinta.
	bolsa.removeFromBag("stone", bolsa.getQuantity("stone"));
	_check("la casilla de la fundición está limpia, así que el tick entrega entero",
		_near(fundicion.getPollutionChoke(), 1.0), str(fundicion.getPollutionChoke()));
	fundicion.receiveMaterial("stone", 2);
	fundicion.update();
	_check("🔴 un tick manda `glass` —y no `brick`— por la red hasta el búfer del almacén",
		int(almacen.input_buffer.get("glass", 0)) == 1
		and not almacen.input_buffer.has("brick") and fundicion.output_buffer == 0,
		"búfer del almacén %s, atasco %d" % [str(almacen.input_buffer),
			fundicion.output_buffer]);
	almacen.update(bolsa);
	_check("🔴 el tick del almacén pone el `glass` en la bolsa",
		bolsa.getQuantity("glass") == 1 and almacen.input_buffer.is_empty(),
		"glass %d, búfer %s" % [bolsa.getQuantity("glass"), str(almacen.input_buffer)]);
	var gm_final = _new_gm(file_data, [
		{ "material": "plank", "quantity": 1, "accepts": ["glass"], "label": "Pide vidrio" },
		{ "material": "plank", "quantity": 99, "label": "Dos" }
	]);
	gm_final.update(bolsa, null);
	_check("🔴 y ese vidrio cierra un checkpoint que pide `plank` o `glass`",
		gm_final.current_checkpoint_index == 1, "índice %d" % gm_final.current_checkpoint_index);

	# Y la vuelta, que es la decisión completa: el jugador que ya tiene su vidrio puede volver a
	# ladrillo sin demoler nada, y lo que sale por la misma cinta cambia con él.
	panel._material_option.item_selected.emit(0);
	fundicion.update();
	almacen.update(bolsa);
	# (El vidrio ya no está en la bolsa: cerrar el checkpoint de arriba lo cobró, que es
	# exactamente lo que se le pedía.)
	_check("volver a `brick` en el mismo panel cambia otra vez lo que llega al almacén",
		fundicion.production == "brick" and bolsa.getQuantity("brick") == 1
		and bolsa.getQuantity("glass") == 0,
		"brick %d, glass %d" % [bolsa.getQuantity("brick"), bolsa.getQuantity("glass")]);
	_check("y el consumo es el de siempre: un `stone` por tick, sea cual sea la salida",
		int(fundicion.input_buffer.get("stone", 0)) == 0,
		str(fundicion.input_buffer));
	_limpiar([gm_final, panel, panel_wc, main.placer, main]);

# ---------- Variedad M4: la depuradora y `requires_adjacent` ----------

# Las tres cosas del hito, y la tercera es la que más pide: (a) la regla de geografía en
# canPlaceFactory(), (b) que el radial la respete, y (c) que la depuradora CONSUMA su `stone`,
# que hasta hoy no lo hacía —factoryData.update() desviaba las de restauración a
# _tick_restoration() sin pasar por checkNeeds() ni consumeNeeds(), así que limpiaba gratis—.
#
# 🔴 Lo que este bloque NO puede afirmar: que los números de la WaterTreatment estén
# equilibrados. `tick: 4`, `pollution: -7.0` y `cost: {wood 4, stone 8}` llegan del DISEÑO y no
# de una medición. Lo que se fija aquí son RELACIONES (limpia más que el Reforester, se para
# sin insumo, no se ahoga).
func _test_variedad_m4_depuradora(file_data):
	print("Variedad M4 — la depuradora y `requires_adjacent`");

	var wt = file_data["Factories"]["WaterTreatment"];

	# --- (1) El contrato declarativo: todo en el JSON, nada hardcodeado ---
	_check("🔴 la WaterTreatment declara el agua que necesita al lado",
		wt.get("requires_adjacent", null) == ["stream", "lake"],
		str(wt.get("requires_adjacent", null)));
	_check("los valores provisionales del JSON se quedan donde el diseño los puso",
		int(wt["tick"]) == 4 and _near(float(wt["pollution"]), -7.0)
		and int(wt["workers_needed"]) == 1 and wt["recieve"] == ["stone"]
		and int(wt["cost"]["wood"]) == 4 and int(wt["cost"]["stone"]) == 8
		and wt["type"] == "restoration" and wt.get("material", 0) == null, str(wt));
	_check("limpia casi el doble que el Reforester: es la razón de que valga la pena atarla al agua",
		float(wt["pollution"]) < float(file_data["Factories"]["Reforester"]["pollution"]),
		"%f contra %f" % [float(wt["pollution"]),
			float(file_data["Factories"]["Reforester"]["pollution"])]);
	# Mismo contrato que `materials: [...]`, `cost` y `accepts`: su ausencia significa «ninguno»
	# y nada que no lo declare se entera de que la regla existe.
	var lo_declaran = [];
	for nombre in file_data["Factories"]:
		if file_data["Factories"][nombre].has("requires_adjacent"):
			lo_declaran.append(nombre);
	_check("y es la ÚNICA entrada que lo declara: las otras ocho se colocan como siempre",
		lo_declaran == ["WaterTreatment"], str(lo_declaran));
	for t in ["stream", "lake"]:
		_check("el tipo de casilla `%s` existe en TileTypes, así que la regla se puede cumplir" % t,
			file_data["TileTypes"].has(t));
	# Su insumo tiene que poder llegarle, y solo llega por cinta: si `stone` fuera de los dos
	# materiales excluidos, la depuradora nacería imposible de alimentar.
	var excluidos = load("res://entities/factory/factoryData.gd").BELT_EXCLUDED_MATERIALS;
	_check("`stone` viaja por cinta: la depuradora se puede alimentar de verdad",
		not excluidos.has("stone"));

	# --- (2) LA REGLA en canPlaceFactory(), que es el único punto de verdad ---
	# Suelo lejano y limpio, con el agua sembrada a mano: `_apply_pollution()` y los mapas de
	# otras pruebas no tienen nada que hacer aquí.
	var tm = load("res://entities/tilemap/tile_map.tscn").instantiate();
	tm.name = "TileMapM4";
	root.add_child(tm);
	tm.tile_type_data = file_data["TileTypes"];
	for x in range(300, 316):
		for y in range(300, 304):
			tm.set_cell(0, Vector2i(x, y), 1, Vector2i(0, 0));
	var seco = Vector2i(300, 300);
	var arroyo = Vector2i(305, 301);
	var junto_arroyo = Vector2i(306, 301);
	var diagonal_arroyo = Vector2i(304, 300);
	var lago = Vector2i(310, 301);
	var junto_lago = Vector2i(311, 301);
	tm.cell_types[arroyo] = "stream";
	tm.cell_types[lago] = "lake";

	# Sin inyectar los params la regla es INERTE, que es lo que deja intacta a la suite entera
	# y a cualquier montaje a mano: el JSON de factorías no es del TileMap hasta que se le da.
	_check("sin `setFactoryParams()` la regla no existe: quien monta un TileMap a mano no se entera",
		tm.canPlaceFactory(seco, [], "restoration", "WaterTreatment") == true);
	tm.setFactoryParams(file_data["Factories"]);

	_check("🔴 lejos del agua la depuradora NO cabe",
		tm.canPlaceFactory(seco, [], "restoration", "WaterTreatment") == false);
	_check("🔴 pegada a un `stream` sí",
		tm.canPlaceFactory(junto_arroyo, [], "restoration", "WaterTreatment") == true);
	_check("🔴 y pegada a un `lake` también",
		tm.canPlaceFactory(junto_lago, [], "restoration", "WaterTreatment") == true);
	_check("la vecindad son las OCHO: en diagonal cuenta igual",
		tm.canPlaceFactory(diagonal_arroyo, [], "restoration", "WaterTreatment") == true);
	# Una casilla no es vecina de sí misma: sobre el propio `stream` —que es construible— la
	# depuradora tampoco cabe. Va AL LADO del agua, nunca encima.
	_check("sobre el propio `stream` no cabe: una casilla no es vecina de sí misma",
		tm.canPlaceFactory(arroyo, [], "restoration", "WaterTreatment") == false);
	_check("y sobre el `lake` menos: es `buildable: false` y lo para la condición 3",
		tm.canPlaceFactory(lago, [], "restoration", "WaterTreatment") == false);
	# La regla nueva SE SUMA a las cinco de siempre, no las sustituye: la casilla junto al agua
	# sigue teniendo que estar libre.
	var ocupante = _new_factory("Reforester", junto_arroyo);
	_check("junto al agua pero ocupada: la condición 4 sigue mandando",
		tm.canPlaceFactory(junto_arroyo, [ocupante], "restoration", "WaterTreatment") == false);
	_check("un tipo SIN `requires_adjacent` cabe en seco, como siempre",
		tm.canPlaceFactory(seco, [], "restoration", "Reforester") == true
		and tm.canPlaceFactory(seco, [], "production", "WoodCutter") == true);
	_check("y un tipo que el JSON no conoce tampoco inventa exigencias",
		tm.canPlaceFactory(seco, [], "production", "NoExiste") == true);
	_check("`requiredAdjacentTypes()` contesta [] sin tipo y la lista del JSON con él",
		tm.requiredAdjacentTypes("") == [] and tm.requiredAdjacentTypes("Reforester") == []
		and tm.requiredAdjacentTypes("WaterTreatment") == ["stream", "lake"]);

	# --- (3) 🔴 QUIEN NO PASA EL CUARTO PARÁMETRO SE COMPORTA EXACTAMENTE COMO HOY ---
	# De ahí cuelgan la condición 3 del punto muerto y el arrastre de cinta, y las dos preguntan
	# por el default "" del TERCERO. Si la regla nueva se les colara, un mapa sin agua no
	# tendría nunca dónde construir y la derrota llegaría sola.
	_check("🔴 hasBuildableCell() no ve la regla: un suelo entero sin agua sigue siendo construible",
		tm.hasBuildableCell([]) == true);
	_check("canPlaceAnyFactory() tampoco: el click sigue abriendo el radial sobre casilla seca",
		tm.canPlaceAnyFactory(seco, []) == true);
	var red = load("res://managers/beltNetwork.gd").new();
	red.name = "BeltNetworkM4";
	root.add_child(red);
	red.initialize(tm, [], file_data);
	tm.setBeltNetwork(red);
	_check("🔴 y el arrastre de cinta sigue tendiendo sobre casilla seca: la cinta no es una factoría",
		red.can_place_drag(seco, Vector2i(303, 300), []) == true);
	var tendida = red.place_drag(seco, Vector2i(303, 300), []);
	_check("el tramo se tiende entero, como antes de M4",
		tendida.size() == 4, "tendió %s" % str(tendida));
	for celda in tendida:
		red.remove_belt(celda);
	tm.setBeltNetwork(null);
	_limpiar([red]);

	# --- (4) ¿CABE EN LOS DOS MAPAS? Si en uno no hubiera sitio, la depuradora sería decorado.
	for mapa in file_data["Maps"]:
		var tm_mapa = load("res://entities/tilemap/tile_map.tscn").instantiate();
		tm_mapa.name = "TileMapMapa";
		root.add_child(tm_mapa);
		tm_mapa.generate(mapa["size"], mapa.get("blocked_cells", []),
			mapa.get("special_cells", []), file_data["TileTypes"]);
		tm_mapa.setFactoryParams(file_data["Factories"]);
		var sitios = 0;
		for celda in tm_mapa.get_used_cells(0):
			if tm_mapa.canPlaceFactory(celda, [], "restoration", "WaterTreatment"):
				sitios += 1;
		_check("🔴 en `%s` quedan casillas construibles junto al agua: la depuradora es jugable" % mapa["id"],
			sitios > 0, "%d casillas" % sitios);
		print("    (%s: %d casillas admiten la depuradora)" % [mapa["id"], sitios]);
		_limpiar([tm_mapa]);

	# --- (5) EL RADIAL: ofrece y no ofrece donde toca ---
	var main = _new_main_en_arbol(file_data);
	var tm_main = main.get_node("TileMap");
	for x in range(300, 316):
		for y in range(300, 304):
			tm_main.set_cell(0, Vector2i(x, y), 1, Vector2i(0, 0));
	tm_main.cell_types[arroyo] = "stream";
	tm_main.setFactoryParams(file_data["Factories"]);
	main.placer = load("res://entities/factory/factoryPlacer.gd").new();
	main.placer.initialize(load("res://entities/factory/factory.tscn"), file_data,
		main.factoryArray);
	var jugador = main.get_node("Player");
	var bolsa = main.get_node("Player/Bag");
	jugador.availableFactories = ["WoodCutter", "Reforester", "WaterTreatment"];
	bolsa.addToBag("wood", 100);
	bolsa.addToBag("stone", 100);

	main._show_radial_menu(seco);
	_check("🔴 sobre casilla sin agua alrededor el radial NO ofrece la depuradora",
		not _opciones_del_radial(main).has("WaterTreatment")
		and _opciones_del_radial(main).has("Reforester"),
		str(_opciones_del_radial(main)));
	var menu_seco = main.get_node_or_null("RadialMenu");
	if menu_seco != null:
		menu_seco.queue_free();
		main.remove_child(menu_seco);
	main._show_radial_menu(junto_arroyo);
	_check("🔴 y junto a un `stream` sí la ofrece",
		_opciones_del_radial(main).has("WaterTreatment"),
		str(_opciones_del_radial(main)));
	var menu_agua = main.get_node_or_null("RadialMenu");
	if menu_agua != null:
		menu_agua.queue_free();
		main.remove_child(menu_agua);

	# La salida temprana que ya existía: si lo único disponible no cabe, no se monta menú. Es
	# lo que impide que el gesto abra un radial vacío sobre la casilla seca.
	jugador.availableFactories = ["WaterTreatment"];
	main._show_radial_menu(seco);
	_check("con la depuradora como única opción, la casilla seca no abre menú ninguno",
		main.get_node_or_null("RadialMenu") == null);
	jugador.availableFactories = ["WoodCutter", "Reforester", "WaterTreatment"];

	# Y el rechazo que MANDA, que no es el del radial: _on_factory_chosen() revalida.
	main._on_factory_chosen("WaterTreatment", seco);
	_check("🔴 el camino que construye la rechaza igual en seco, no solo el filtro del menú",
		main.factoryArray.is_empty(), str(main.factoryArray.size()));
	main._on_factory_chosen("WaterTreatment", junto_arroyo);
	var depuradora_colocada = null;
	for nodo in main.factoryArray:
		if nodo.type == "WaterTreatment":
			depuradora_colocada = nodo;
	_check("🔴 y junto al arroyo la coloca por el camino real, con su worker",
		depuradora_colocada != null and depuradora_colocada.factory_type == "restoration"
		and depuradora_colocada.itemNeeded == ["stone"], str(depuradora_colocada));
	_limpiar([main.placer, main]);

	# --- (6) 🔴 EL CONSUMO: una depuradora sin `stone` DEJA DE LIMPIAR ---
	var pm = _new_pm();
	var celda = Vector2i(400, 400);
	var dep = _new_factory_en_arbol("WaterTreatment", celda, pm);
	dep.initialize("WaterTreatment", int(wt["tick"]), wt["recieve"], wt.get("material", null),
		1, float(wt["pollution"]), "restoration", 0);
	dep.cell_position = celda;
	_ensuciar_area(pm, celda, 20.0);
	var sucio_antes = pm.total_pollution;
	dep.update();
	_check("🔴 sin `stone` en el búfer la depuradora no limpia NADA",
		_near(pm.total_pollution, sucio_antes), "%f -> %f" % [sucio_antes, pm.total_pollution]);
	_check("🔴 y lo dice: `blocked_reason` es 'input', la razón que ya existía",
		dep.blocked_reason == "input", "razón '%s'" % dep.blocked_reason);
	_check("y la UI sabe redactarla sin inventar nada nuevo",
		load("res://ui/blockedReason.gd").text_for(dep.blocked_reason) != ""
		and load("res://ui/blockedReason.gd").reason_now(dep) == "input");

	dep.receiveMaterial("stone", 1);
	dep.update();
	_check("🔴 con un `stone` en el búfer vuelve a limpiar",
		pm.total_pollution < sucio_antes and dep.blocked_reason == "",
		"%f -> %f, razón '%s'" % [sucio_antes, pm.total_pollution, dep.blocked_reason]);
	_check("y se lo ha comido: un `stone` por tick, como cualquier otra factoría con insumos",
		int(dep.input_buffer.get("stone", 0)) == 0, str(dep.input_buffer));
	var tras_limpiar = pm.total_pollution;
	dep.update();
	_check("🔴 al tick siguiente, sin más `stone`, vuelve a pararse: la cinta cortada la para",
		_near(pm.total_pollution, tras_limpiar) and dep.blocked_reason == "input",
		"%f -> %f, razón '%s'" % [tras_limpiar, pm.total_pollution, dep.blocked_reason]);

	# El control que le da sentido: el Reforester NO tiene insumos y esto no le cambia nada.
	var refo = _new_factory("Reforester", Vector2i(402, 402));
	refo.initialize("Reforester", 5, file_data["Factories"]["Reforester"]["recieve"], null,
		1, -4.0, "restoration", 0);
	var spr = AnimatedSprite2D.new();
	spr.name = "AnimatedSprite2D";
	spr.sprite_frames = SpriteFrames.new();
	refo.add_child(spr);
	root.add_child(refo);
	refo.cell_position = Vector2i(402, 402);
	_ensuciar_area(pm, Vector2i(402, 402), 20.0);
	var refo_antes = pm.total_pollution;
	var manchas = 0;
	for t in range(20):
		refo.update();
		if refo.blocked_reason != "":
			manchas += 1;
	_check("un Reforester (`recieve: null`) no dice 'input' JAMÁS y sigue limpiando en silencio",
		manchas == 0 and pm.total_pollution < refo_antes,
		"%d ticks con razón ('%s')" % [manchas, refo.blocked_reason]);
	_limpiar([refo]);

	# --- (7) 🔴 LOS DOS CONTRAPESOS QUE NO SE TOCAN: ni se ahoga ni se atasca ---
	# Es lo que hace justa la derrota, y tener insumos no la saca de la excepción.
	pm.addPollution(1000.0, celda);
	_check("la casilla de la depuradora está saturada del todo",
		_near(pm.getCellPollution(celda), 1.0), "celda %f" % pm.getCellPollution(celda));
	_check("🔴 y aun así NO se ahoga: choke 1.0 aunque tenga insumos",
		_near(dep.getPollutionChoke(), 1.0), "choke %f" % dep.getPollutionChoke());
	dep.output_buffer = load("res://entities/factory/factoryData.gd").OUTPUT_BUFFER_MAX;
	var manchas_dep = 0;
	var saturado_antes = pm.total_pollution;
	for t in range(10):
		dep.receiveMaterial("stone", 1);
		dep.update();
		if dep.blocked_reason != "":
			manchas_dep += 1;
	_check("🔴 alimentada, NUNCA dice 'choke' ni 'output' sobre casilla saturada, y limpia",
		manchas_dep == 0 and pm.total_pollution < saturado_antes,
		"%d ticks con razón ('%s')" % [manchas_dep, dep.blocked_reason]);
	dep.output_buffer = 0;
	# Pero la exención no la saca de la prioridad 1, igual que al Reforester: sin workers la
	# razón sigue siendo 'workers' aunque además le falte el insumo.
	dep.workers_needed = int(wt["workers_needed"]);
	dep.workers_assigned = 0;
	dep.update();
	_check("sin workers dice 'workers' y no 'input': la prioridad de las cinco razones no se mueve",
		dep.blocked_reason == "workers", "razón '%s'" % dep.blocked_reason);
	dep.workers_assigned = dep.workers_needed;
	_limpiar([dep, pm]);

	# --- (8) 🔴 REPARTE SU LIMPIEZA EN ÁREA, como el Reforester ---
	# Sin esto las casillas `toxic` —que son `buildable: false` y nunca tienen factoría
	# encima— dejarían de ser recuperables por ella.
	var pm2 = _new_pm();
	var centro = Vector2i(500, 500);
	var vecina = Vector2i(501, 501);
	var lejana = Vector2i(520, 520);
	var dep2 = _new_factory_en_arbol("WaterTreatment", centro, pm2);
	dep2.initialize("WaterTreatment", 4, ["stone"], null, 1, -9.0, "restoration", 0);
	dep2.cell_position = centro;
	pm2.addPollution(5.0, centro);
	pm2.addPollution(5.0, vecina);
	pm2.addPollution(5.0, lejana);
	dep2.receiveMaterial("stone", 1);
	dep2.update();
	_check("🔴 la depuradora reparte su limpieza en las 9 casillas, igual que el Reforester",
		_near(pm2.pollution_per_cell[centro], 4.0)
		and _near(pm2.pollution_per_cell[vecina], 4.0),
		"propia %f, vecina %f" % [pm2.pollution_per_cell[centro],
			pm2.pollution_per_cell[vecina]]);
	_check("y una casilla fuera del área no se toca",
		_near(pm2.pollution_per_cell[lejana], 5.0), "quedó %f" % pm2.pollution_per_cell[lejana]);
	_limpiar([dep2, pm2, ocupante, tm]);

	# --- (9) La run de verdad: Main le inyecta al TileMap el JSON del que sale la regla ---
	# Sin esta línea la regla sería inerte EN EL JUEGO y solo la suite se enteraría.
	var run = _main_para_run();
	run._start_game("standard");
	var tm_run = run.get_node("TileMap");
	_check("🔴 `_start_game()` le pasa al TileMap el bloque `Factories`: la regla vive en la run",
		tm_run.requiredAdjacentTypes("WaterTreatment") == ["stream", "lake"],
		str(tm_run.requiredAdjacentTypes("WaterTreatment")));
	run.gameManager.checkpoint_reached.disconnect(run._on_checkpoint_reached);
	_limpiar([run.placer, run.mapLoader, run]);

# Los tipos de factoría que el radial acaba de ofrecer, leídos de los botones montados: es lo
# que el jugador ve, no lo que Main pensaba enseñar. El nombre del tipo es la primera label de
# cada botón (ver ui/radialMenu.gd y la prueba TM9).
func _opciones_del_radial(main) -> Array:
	var menu = main.get_node_or_null("RadialMenu");
	if menu == null:
		return [];
	var tipos = [];
	for b in menu.find_children("", "Button", true, false):
		var labels = b.find_children("", "Label", true, false);
		if not labels.is_empty():
			tipos.append(str(labels[0].text));
	return tipos;

# ---------- Variedad M4b: el radial con seis opciones y tres arreglos de legibilidad ----------

# El hito que salió de MIRAR el juego, no de medirlo (`tools/ver_variedad.gd`, 2026-09-22). Este
# bloque fija los números que la captura no puede fijar sola —que no haya un solo par de botones
# montado, que el marco del tooltip tenga aire, que la línea de parada no reserve sitio cuando
# calla—, pero el veredicto último de los cuatro arreglos sigue siendo la foto: la suite no sabe
# si un gris se lee sobre un cubo oscuro.
#
# 🔴 Lo que este bloque SÍ es capaz de afirmar y la captura no: que la corona aguanta con 2, 3,
# 4, 5, 6, 7 y 8 opciones —ocho es el techo real: las nueve entradas del JSON menos el `Storage`,
# que el jugador no elige— Y con todos los botones anunciando sinergias, que es el caso más alto
# que el menú sabe pintar. La captura solo enseña uno de esos siete.
func _test_variedad_m4b_legibilidad(file_data):
	print("Variedad M4b — el radial con seis opciones y tres arreglos de legibilidad");
	var molde = load("res://ui/radialMenu.gd").new();
	var fuente = ThemeDB.fallback_font;

	# --- (1) EL ANCHO. Se bajó de 130 a 112 y esa es la mitad del arreglo, así que lo que hay
	# que impedir es justo lo contrario del bug: que estrecharlo recorte un texto. Una Label no
	# se recorta —se saldría del botón—, así que se miden TODAS las líneas que el radial sabe
	# escribir, no solo las de precio como hacía la prueba de Costes M5.
	var ancho_max = 0.0;
	var mas_ancha = "";
	for texto in _lineas_posibles_del_radial(molde, file_data):
		var ancho = fuente.get_string_size(texto, HORIZONTAL_ALIGNMENT_CENTER, -1, 11).x;
		if ancho > ancho_max:
			ancho_max = ancho;
			mas_ancha = texto;
	_check("🔴 ninguna línea que el radial sepa escribir se sale del botón: no se recorta nada",
		ancho_max <= float(molde.BUTTON_WIDTH),
		"«%s» mide %.0f px contra los %d del botón" % [mas_ancha, ancho_max, molde.BUTTON_WIDTH]);
	_check("y el botón no se ha estrechado hasta rozar el texto: le quedan 8 px de holgura",
		float(molde.BUTTON_WIDTH) - ancho_max >= 8.0,
		"holgura %.0f px sobre «%s»" % [float(molde.BUTTON_WIDTH) - ancho_max, mas_ancha]);

	# --- (2) LA CORONA. El defecto que abrió el hito: con seis opciones cuatro pares de botones
	# se montaban con una franja de 28 px, que en un menú de construcción es zona de click
	# ambiguo. Se comprueba por el camino real —`initialize()` monta los botones de verdad— y
	# sobre los rectángulos que el jugador pulsa.
	var ocho = ["WoodCutter", "WoodProcessing", "Quarry", "Foundry", "Reforester",
		"WaterTreatment", "MetaFactory", "WorkerCamp"];
	var elegibles = [];
	for nombre in file_data["Factories"]:
		if str(file_data["Factories"][nombre].get("type", "production")) != "storage":
			elegibles.append(nombre);
	elegibles.sort();
	var copia = ocho.duplicate();
	copia.sort();
	_check("ocho es el techo del menú: las nueve entradas del JSON menos el `Storage`",
		copia == elegibles, "%s contra %s" % [str(copia), str(elegibles)]);
	# Una sinergia gorda para todos: cuatro líneas más por botón, que es el botón más alto que
	# este menú sabe pintar. Sin esto la prueba mediría el caso cómodo.
	var gorda = { "tick_bonus": 1, "output_bonus": 1, "pollution_mult": 0.75, "gives_to": 2 };
	for n in range(2, 9):
		for con_sinergia in [false, true]:
			var opciones = ocho.slice(0, n);
			var preview = {};
			if con_sinergia:
				for t in opciones:
					preview[t] = gorda;
			var menu = load("res://ui/radialMenu.gd").new();
			root.add_child(menu);
			menu.initialize(opciones, file_data, Vector2i(3, 3), Vector2(640, 360), preview);
			var rects = _rects_del_radial(menu);
			var peor = "";
			var solapes = 0;
			for i in range(rects.size()):
				for j in range(i + 1, rects.size()):
					var inter = rects[i].intersection(rects[j]);
					if inter.size.x > 0.0 and inter.size.y > 0.0:
						solapes += 1;
						peor = "%d×%d entre el %d y el %d" % [
							int(inter.size.x), int(inter.size.y), i, j];
			_check("🔴 con %d opciones%s no se solapa un solo par de botones" % [
					n, (" y todas con sinergia" if con_sinergia else "")],
				rects.size() == n and solapes == 0,
				"%d solapes, el peor %s" % [solapes, peor]);
			if n == 8 and con_sinergia:
				# Y la corona entera cabe en la resolución del proyecto. Es la otra mitad de
				# subir el radio: una corona que no se solapa pero se sale de la ventana deja
				# botones que no se pueden pulsar, que es el mismo gesto roto.
				var caja = rects[0];
				for k in range(1, rects.size()):
					caja = caja.merge(rects[k]);
				_check("y la corona más grande que el menú sabe montar cabe en 1280x720",
					caja.size.x <= 1280.0 and caja.size.y <= 720.0,
					"envolvente %.0f x %.0f" % [caja.size.x, caja.size.y]);
			menu.free();
	# El radio es una función de los altos y del ancho, no una constante: con pocas opciones
	# devuelve el suelo de siempre y solo crece cuando de verdad hace falta.
	var seis_altos = [66.0, 82.0, 82.0, 98.0, 66.0, 98.0];
	_check("con 5 opciones o menos la corona es exactamente la de siempre (118 px)",
		_near(molde._ring_radius(seis_altos.slice(0, 5)), molde.MIN_RADIUS)
		and _near(molde._ring_radius(seis_altos.slice(0, 2)), molde.MIN_RADIUS),
		"%f y %f" % [molde._ring_radius(seis_altos.slice(0, 5)),
			molde._ring_radius(seis_altos.slice(0, 2))]);
	_check("y con 6 crece lo justo: 136 px, nueve más de radio efectivo que los 183 de antes",
		molde._ring_radius(seis_altos) > molde.MIN_RADIUS
		and molde._ring_radius(seis_altos) < 140.0,
		"%f" % molde._ring_radius(seis_altos));
	# Y el alto cuenta: los dos botones que caen a la MISMA x no se separan nada en horizontal,
	# así que lo único que los mantiene apartados es lo altos que sean. Un arreglo que solo
	# mirase el ancho los dejaría montados en cuanto un botón creciera de líneas.
	var altisimos = [300.0, 300.0, 300.0, 300.0, 300.0, 300.0];
	_check("🔴 el radio mira también los ALTOS: seis botones gigantes piden más corona",
		molde._ring_radius(altisimos) > molde._ring_radius(seis_altos),
		"%f contra %f" % [molde._ring_radius(altisimos), molde._ring_radius(seis_altos)]);

	# --- (3) Y LA CORONA SE METE EN LA VENTANA. El menú nace donde está el ratón, que puede ser
	# el borde del mapa. Se traslada entera —no se recoloca—, que es lo único que no deshace lo
	# de arriba: mover todos los botones lo mismo no cambia ninguna distancia entre dos de ellos.
	var esquina = load("res://ui/radialMenu.gd").new();
	root.add_child(esquina);
	esquina.initialize(ocho.slice(0, 6), file_data, Vector2i(0, 0), Vector2(20, 20));
	var r_esq = _rects_del_radial(esquina);
	var dentro = true;
	var solapes_esq = 0;
	for i in range(r_esq.size()):
		if r_esq[i].position.x < 0.0 or r_esq[i].position.y < 0.0:
			dentro = false;
		for j in range(i + 1, r_esq.size()):
			var it = r_esq[i].intersection(r_esq[j]);
			if it.size.x > 0.0 and it.size.y > 0.0:
				solapes_esq += 1;
	_check("un radial abierto en la esquina de la pantalla cae entero DENTRO de la ventana",
		dentro, str(r_esq));
	_check("y trasladarlo no vuelve a montar ningún par: una traslación no cambia distancias",
		solapes_esq == 0, "%d solapes" % solapes_esq);
	esquina.free();
	var centrado = load("res://ui/radialMenu.gd").new();
	root.add_child(centrado);
	centrado.initialize(ocho.slice(0, 6), file_data, Vector2i(0, 0), Vector2(640, 360));
	var r_cen = _rects_del_radial(centrado);
	_check("y el que ya cabía no se mueve ni un píxel: la corona sigue alrededor del cursor",
		_near(r_cen[0].get_center().x, 640.0), "%f" % r_cen[0].get_center().x);
	centrado.free();
	molde.free();

	# --- (4) EL TOOLTIP TIENE AIRE. `⚠ Parada: sin insumo — tiéndele cinta de entrada` es la
	# línea más ancha que estas superficies escriben —289 px— y llenaba el marco de borde a
	# borde, 0 px a cada lado: el `panel` del tema por defecto trae los cuatro `content_margin`
	# a cero y un PanelContainer estira su hijo a todo lo que el marco mide.
	var basura = [];
	var main = _new_main_en_arbol(file_data);
	var tm = main.get_node("TileMap");
	for y in range(8):
		for x in range(10):
			tm.set_cell(0, Vector2i(x, y), 1, Vector2i(0, 0));
	var bolsa = main.get_node("Player/Bag");
	var parada = _factoria_en_main(main, "WaterTreatment", Vector2i(4, 4), 4, ["stone"], null,
		"restoration");
	parada.workers_needed = 1;
	parada.workers_assigned = 1;
	parada.update(bolsa);
	var tip = _tooltip_de(parada, file_data, basura);
	var ancho_marco = tip._panel.get_combined_minimum_size().x;
	var ancho_texto = 0.0;
	var linea_larga = "";
	for l in tip.find_children("", "Label", true, false):
		if l.get_minimum_size().x > ancho_texto:
			ancho_texto = l.get_minimum_size().x;
			linea_larga = l.text;
	_check("el tooltip de la depuradora parada dice la frase de `input`",
		_linea_de_parada(tip) != null, str(_textos_panel(tip)));
	_check("🔴 y su línea más ancha ya no llena el marco de borde a borde",
		ancho_marco - ancho_texto >= 2.0 * float(tip.MARGIN_H),
		"marco %.0f px, texto %.0f px («%s»), holgura %.0f" % [
			ancho_marco, ancho_texto, linea_larga, ancho_marco - ancho_texto]);
	_check("y el margen es el mismo a los dos lados: el marco no queda descentrado",
		tip.MARGIN_H > 0 and tip.MARGIN_V > 0,
		"%d x %d" % [tip.MARGIN_H, tip.MARGIN_V]);

	# --- (5) EL PANEL NO RESERVA LÍNEA CUANDO CALLA. La etiqueta de la razón de parada se monta
	# siempre y se esconde, y un BoxContainer de Godot salta a los hijos invisibles tanto al
	# repartir sitio como al calcular su mínimo. Se mide la diferencia de alto entre las dos
	# situaciones: tiene que ser EXACTAMENTE una línea, ni un píxel cuando la factoría funciona.
	var sana = _factoria_en_main(main, "WoodCutter", Vector2i(6, 1), 5, null, "wood");
	sana.workers_needed = 1;
	sana.workers_assigned = 1;
	sana.update(bolsa);
	var panel = load("res://ui/factoryPanel.gd").new();
	root.add_child(panel);
	panel.initialize(sana, file_data, Vector2(640, 360), bolsa);
	basura.append(panel);
	var caja_panel = panel._panel.get_child(0);
	var alto_sano = caja_panel.get_combined_minimum_size().y;
	_check("con la factoría funcionando la etiqueta de parada está montada y escondida",
		panel._blocked_label != null and not panel._blocked_label.visible
		and _linea_de_parada(panel) == null);
	sana.blocked_reason = "choke";
	panel._process(0.0);
	var alto_parado = caja_panel.get_combined_minimum_size().y;
	var una_linea = (panel._blocked_label.get_combined_minimum_size().y
		+ caja_panel.get_theme_constant("separation"));
	_check("🔴 y esconderla le quita al panel UNA LÍNEA EXACTA: callada no reserva sitio",
		_linea_de_parada(panel) != null and _near(alto_parado - alto_sano, una_linea),
		"parado %.0f, sano %.0f, una línea %.0f" % [alto_parado, alto_sano, una_linea]);
	# Y el `_process()` tiene que seguir repintando: el panel vive hasta que se cierra y la razón
	# la escribe el Timer de la factoría, sin señal a la que engancharse.
	sana.blocked_reason = "";
	panel._process(0.0);
	_check("y el `_process()` sigue vivo: cuando la factoría arranca, la línea vuelve a irse",
		_linea_de_parada(panel) == null
		and _near(caja_panel.get_combined_minimum_size().y, alto_sano),
		"%.0f contra %.0f" % [caja_panel.get_combined_minimum_size().y, alto_sano]);

	# --- (6) EL COLOR DEL `+5` DE `stone`. La suite no sabe si un gris se lee sobre un cubo
	# oscuro —eso es la captura—, pero sí sabe fijar las dos relaciones de las que el arreglo
	# cuelga: que se ACLARÓ (contraste) y que no se acercó a ninguno de los otros dos.
	var pintor = _new_main_de_prueba(file_data);
	var c_stone = pintor._get_material_color("stone");
	var c_brick = pintor._get_material_color("brick");
	var c_glass = pintor._get_material_color("glass");
	_check("🔴 el `+5` de `stone` es claro: es lo que le da contraste sobre el cubo de la factoría",
		c_stone.get_luminance() > 0.85, "luminancia %f" % c_stone.get_luminance());
	var d_brick = Vector3(c_stone.r - c_brick.r, c_stone.g - c_brick.g, c_stone.b - c_brick.b);
	var d_glass = Vector3(c_stone.r - c_glass.r, c_stone.g - c_glass.g, c_stone.b - c_glass.b);
	_check("y aclararlo lo ALEJA del terracota del `brick`, no lo acerca",
		d_brick.length() > 0.8, "distancia %f" % d_brick.length());
	_check("y del azul-cristal del `glass` tampoco se acerca",
		d_glass.length() > 0.4, "distancia %f" % d_glass.length());
	_check("y los tres siguen siendo tres colores distintos entre sí",
		c_stone != c_brick and c_stone != c_glass and c_brick != c_glass);
	_limpiar([pintor]);

	_limpiar(basura);
	_limpiar([main]);


# ---------- Variedad M5: las tres cartas de catálogo de la segunda cadena ----------

# El `*Hecho cuando:*` del hito: «`_pick_upgrades()` sigue ofreciendo 3 candidatas en los dos
# tiers y las mejoras nuevas aparecen en runs de los tres paquetes». Las dos mitades se caminan
# aquí por el camino real —`_granted_upgrades()` + `_pick_upgrades(3, tier, granted)`, que es
# exactamente lo que hace `gameManager.update()` al cerrar un checkpoint—, y no sobre el JSON.
#
# Las tres cartas nuevas son `unlock_quarry`, `unlock_foundry` y `unlock_watertreatment`, las
# TRES de tier 2. La decisión de meterlas todas en el tier potente y ninguna en el corriente es
# lo que deja el catálogo revisado del Plan «Catálogo de Mejoras» intacto, y se puede decir con
# números:
#
# - **El tier 1 no se toca**: sigue con sus 6 entradas de JSON, 5 en la baraja que el jugador ve
#   —`unlock_woodprocessing` no entra jamás— y sus **10 manos**. Una sola carta nueva ahí lo
#   habría dejado en 6 y 20, y encima sería una carta que en la mayoría de las runs no se puede
#   usar todavía.
# - **El tier 2 pasa de 4 cartas a 7**, o sea de **4 manos a 35**: la pantalla más pobre del
#   juego —cuatro cartas, siempre tres de las mismas cuatro— pasa a ser la más rica, y es la
#   que solo se ve jugando bien.
# - **El factory token conserva su razón de ser**: sigue siendo el único camino a la segunda
#   cadena en la ruta corriente, y las tres cartas nuevas se caen solas de la baraja en cuanto
#   la factoría está desbloqueada (`_usable_upgrades()`), así que las dos vías no se pisan.
#
# Lo que NO se ha hecho, y es la otra mitad de la decisión: **no hay cartas de `speed_boost` ni
# de `extra_output` para las tres**. Una `speed_quarry` sería humo en toda run que no haya
# desbloqueado la cantera —que son casi todas—, y filtrarla como se filtra un `unlock_factory`
# no se puede: el filtro miraría `availableFactories` en el instante del reparto, y en
# `lumberjack` eso dejaría fuera también a `speed_woodprocessing` —la procesadora se concede en
# esa misma pantalla, después de repartir— y la baraja corriente bajaría de 5 a 4, que es
# justo lo que el catálogo revisado prohíbe.
func _test_variedad_m5_catalogo(file_data):
	print("Variedad M5 — las tres cartas de catálogo de la segunda cadena");
	var catalogo = file_data["Upgrades"];
	var nuevas = ["unlock_quarry", "unlock_foundry", "unlock_watertreatment"];
	var factoria_de = { "unlock_quarry": "Quarry", "unlock_foundry": "Foundry",
		"unlock_watertreatment": "WaterTreatment" };

	# --- (1) EL CONTRATO DECLARATIVO. Las tres son `unlock_factory` de una factoría que existe,
	# de tier 2 y con castigo: una carta de tier 2 sin `map_downside` está descartada a propósito
	# (`## 🧭 Alcance` del Plan «Catálogo de Mejoras»). El número de casillas lo fija la tabla del
	# bloque «Costes M6b», que es donde vive la escala entera y donde se comprueba además que
	# aplicadas de verdad degradan lo que anuncian.
	var contrato = true;
	var detalle_contrato = "";
	for id in nuevas:
		var carta = catalogo.get(id, {});
		if str(carta.get("type", "")) != "unlock_factory" \
			or str(carta.get("factory", "")) != factoria_de[id] \
			or not file_data["Factories"].has(str(carta.get("factory", ""))) \
			or int(carta.get("tier", 1)) != 2 \
			or int(carta.get("map_downside", {}).get("cells", 0)) <= 0:
			contrato = false;
			detalle_contrato = "%s = %s" % [id, str(carta)];
	_check("las tres cartas nuevas desbloquean una factoría que existe, en tier 2 y con castigo",
		contrato, detalle_contrato);
	# Y la carta tiene algo que desbloquear: ninguna de las tres viene en un paquete inicial, o
	# sería la mejora muerta que `_usable_upgrades()` existe para quitar (el caso
	# `unlock_reforester`, borrado del catálogo en su día).
	var en_paquete = [];
	for paquete in file_data["StartingPackages"]:
		for f in file_data["StartingPackages"][paquete]["factories"]:
			if factoria_de.values().has(f) and not en_paquete.has(f):
				en_paquete.append(f);
	_check("ninguna de las tres viene en un paquete inicial: las cartas no nacen muertas",
		en_paquete.is_empty(), "vienen en un paquete %s" % str(en_paquete));

	# --- (2) EL REPARTO, y es la primera mitad del `*Hecho cuando:*`. Las 30 pantallas de la
	# revisión del catálogo (3 paquetes x 5 checkpoints x 2 rutas), caminadas igual que en el
	# bloque «Catálogo M2»: se avanza `current_checkpoint_index` y se aplica lo concedido, como
	# hace `Main._on_checkpoint_reached()`, porque la baraja cambia con la curva.
	var manos = 0;
	var siempre_tres = true;
	var siempre_del_tier = true;
	var baraja_1_de_cinco = true;
	var baraja_2_de_siete = true;
	var woodprocessing_nunca_ofrecida = true;
	var nuevas_nunca_concedidas = true;
	var vistas_por_paquete = {};
	var detalle = "";
	for paquete in file_data["StartingPackages"]:
		vistas_por_paquete[paquete] = {};
		for ruta in [1, 2]:
			var gm = _new_gm(file_data);
			var jugador = StubPlayer.new();
			jugador.availableFactories = file_data["StartingPackages"][paquete]["factories"].duplicate();
			gm.setPlayer(jugador);
			for i in range(file_data["Checkpoints"].size()):
				gm.current_checkpoint_index = i;
				var concedidas = gm._granted_upgrades();
				var ofrecidas = gm._pick_upgrades(3, ruta, concedidas);
				manos += 1;
				if ofrecidas.size() != 3 or not _sin_repetidas(ofrecidas):
					siempre_tres = false;
					detalle = "%s/tier %d/cp %d: %s" % [paquete, ruta, i + 1, str(ofrecidas)];
				if not _todas_de_tier(catalogo, ofrecidas, ruta):
					siempre_del_tier = false;
					detalle = "%s/tier %d/cp %d: %s" % [paquete, ruta, i + 1, str(ofrecidas)];
				if ofrecidas.has("unlock_woodprocessing"):
					woodprocessing_nunca_ofrecida = false;
					detalle = "%s/tier %d/cp %d: %s" % [paquete, ruta, i + 1, str(ofrecidas)];
				for id in concedidas:
					if nuevas.has(id):
						nuevas_nunca_concedidas = false;
						detalle = "%s/tier %d/cp %d concedió %s" % [paquete, ruta, i + 1, id];
				for id in ofrecidas:
					vistas_por_paquete[paquete][id] = true;
				# Las dos barajas, contadas en cada pantalla: la corriente son 5 cartas y la
				# potente 7. Son los dos números de los que cuelga el hito.
				var vivas_1 = [];
				var vivas_2 = [];
				for id in gm._usable_upgrades():
					if concedidas.has(id):
						continue;
					if int(catalogo[id].get("tier", 1)) == 1:
						vivas_1.append(id);
					elif int(catalogo[id].get("tier", 1)) == 2:
						vivas_2.append(id);
				if vivas_1.size() != 5:
					baraja_1_de_cinco = false;
					detalle = "%s/tier %d/cp %d: tier 1 = %s" % [paquete, ruta, i + 1, str(vivas_1)];
				if vivas_2.size() != 7:
					baraja_2_de_siete = false;
					detalle = "%s/tier %d/cp %d: tier 2 = %s" % [paquete, ruta, i + 1, str(vivas_2)];
				for id in concedidas:
					var factoria = str(catalogo[id].get("factory", ""));
					if factoria != "" and not jugador.availableFactories.has(factoria):
						jugador.availableFactories.append(factoria);
			_limpiar([gm]);
	_check("se reparten las 30 pantallas (3 paquetes x 5 checkpoints x 2 rutas)", manos == 30,
		"fueron %d" % manos);
	_check("🔴 con las tres cartas nuevas dentro se siguen ofreciendo 3 candidatas distintas",
		siempre_tres, detalle);
	_check("y las tres son SIEMPRE del tier pedido: ninguna pantalla baja de tier por falta de cartas",
		siempre_del_tier, detalle);
	_check("la baraja corriente sigue siendo de 5 cartas: el tier 1 no se ha tocado",
		baraja_1_de_cinco, detalle);
	_check("y la potente pasa a 7: el cuarteto graduado más las tres de este hito",
		baraja_2_de_siete, detalle);
	_check("`unlock_woodprocessing` sigue sin colarse en una sola de las 30 pantallas",
		woodprocessing_nunca_ofrecida, detalle);

	# --- (3) LAS MANOS, medidas. Es el número que el `CLAUDE.md` del repo tiene escrito para el
	# tier 1 y que este hito no podía mover, y el que sí mueve en el tier 2.
	var gm_manos = _new_gm(file_data);
	var estandar = StubPlayer.new();
	estandar.availableFactories = file_data["StartingPackages"]["standard"]["factories"].duplicate();
	gm_manos.setPlayer(estandar);
	var manos_1 = {};
	var manos_2 = {};
	# 800 repartos por tier: con 35 manos equiprobables —`_shuffled_tier()` baraja y corta— no
	# verlas todas en 800 tiradas es un suceso de una entre mil millones. Con menos muestras
	# esta prueba sería la que parpadea.
	for i in range(800):
		var mano_1 = gm_manos._pick_upgrades(3, 1);
		mano_1.sort();
		manos_1[str(mano_1)] = true;
		var mano_2 = gm_manos._pick_upgrades(3, 2);
		mano_2.sort();
		manos_2[str(mano_2)] = true;
	print("    medido: %d manos distintas de tier 1 y %d de tier 2 en 800 repartos de standard"
		% [manos_1.size(), manos_2.size()]);
	_check("🔴 el tier 1 sigue dando sus 10 manos: 5 cartas, C(5,3) = 10", manos_1.size() == 10,
		"%d manos" % manos_1.size());
	_check("y el tier 2 pasa de 4 manos a 35: 7 cartas, C(7,3) = 35", manos_2.size() == 35,
		"%d manos" % manos_2.size());
	_limpiar([gm_manos]);

	# --- (4) Y LA SEGUNDA MITAD DEL `*Hecho cuando:*`: las tres aparecen en runs de los TRES
	# paquetes. Se mira sobre lo repartido en el (2) —las 30 pantallas de verdad—, repetido las
	# veces que hagan falta para que el azar no decida el veredicto.
	var aparecen = {};
	for paquete in file_data["StartingPackages"]:
		aparecen[paquete] = {};
	for intento in range(40):
		for paquete in file_data["StartingPackages"]:
			var gm_run = _new_gm(file_data);
			var jugador_run = StubPlayer.new();
			jugador_run.availableFactories = file_data["StartingPackages"][paquete]["factories"].duplicate();
			gm_run.setPlayer(jugador_run);
			for i in range(file_data["Checkpoints"].size()):
				gm_run.current_checkpoint_index = i;
				var concedidas_run = gm_run._granted_upgrades();
				for id in gm_run._pick_upgrades(3, 2, concedidas_run):
					aparecen[paquete][id] = true;
				for id in concedidas_run:
					var f = str(catalogo[id].get("factory", ""));
					if f != "" and not jugador_run.availableFactories.has(f):
						jugador_run.availableFactories.append(f);
			_limpiar([gm_run]);
	var faltan_en = [];
	for paquete in aparecen:
		for id in nuevas:
			if not aparecen[paquete].has(id):
				faltan_en.append("%s/%s" % [paquete, id]);
	_check("🔴 las tres cartas nuevas salen en runs de los tres paquetes (standard, lumberjack, ecologist)",
		faltan_en.is_empty(), "no salieron %s" % str(faltan_en));

	# --- (5) Y NO SE REGALAN. Una `unlock_factory` nueva puede acabar concediéndose como
	# rescate, y con la curva real eso era basura de verdad: en `lumberjack` y `ecologist` falta
	# `plank` en los checkpoints 2 a 5, y como el 3 acepta `stone`, el 4 `brick` y el 5 `glass`,
	# `_unproducible_materials()` daba por imposibles los cuatro materiales y el rescate
	# concedía de golpe la serrería, la cantera Y la fundición — la segunda cadena entera
	# regalada en el checkpoint 1, y el factory token sin razón de ser. La cascada de
	# `_unproducible_materials()` (Variedad M5) lo cierra: lo que ya lleva carta cuenta como
	# producible para los checkpoints siguientes.
	_check("ninguna de las tres se concede en las 30 pantallas: el rescate no regala la segunda cadena",
		nuevas_nunca_concedidas, detalle);
	for paquete in ["lumberjack", "ecologist"]:
		var gm_res = _new_gm(file_data);
		var jugador_res = StubPlayer.new();
		jugador_res.availableFactories = file_data["StartingPackages"][paquete]["factories"].duplicate();
		gm_res.setPlayer(jugador_res);
		_check("🔴 en `%s` el checkpoint 1 concede la serrería y SOLO la serrería" % paquete,
			gm_res._granted_upgrades() == ["unlock_woodprocessing"],
			"concedió %s" % str(gm_res._granted_upgrades()));
		_limpiar([gm_res]);
	# Y el control de que la cascada no poda de más: cuando el segundo checkpoint bloqueado no
	# lo desatasca la carta del primero, se siguen concediendo las dos. Sin este control, «solo
	# una carta» podría estar tapando un agujero en la garantía de que ninguna run se cuelga.
	var gm_dos = _new_gm(file_data, [
		{ "material": "plank", "quantity": 10, "label": "Uno" },
		{ "material": "brick", "quantity": 10, "label": "Dos" }
	]);
	var lenador_dos = StubPlayer.new();
	lenador_dos.availableFactories = file_data["StartingPackages"]["lumberjack"]["factories"].duplicate();
	gm_dos.setPlayer(lenador_dos);
	var concedidas_dos = gm_dos._granted_upgrades();
	_check("control: dos checkpoints que piden cadenas distintas conceden las DOS cartas",
		concedidas_dos.size() == 2 and concedidas_dos.has("unlock_woodprocessing")
		and concedidas_dos.has("unlock_foundry"), "concedidas %s" % str(concedidas_dos));
	_limpiar([gm_dos]);

	# --- (6) EL FACTORY TOKEN SIGUE TENIENDO RAZÓN DE SER, que es la otra cara de repartir
	# desbloqueos: en la ruta corriente sigue siendo el ÚNICO camino a la segunda cadena, y las
	# dos vías no se pisan porque la carta se cae sola de la baraja en cuanto la factoría está
	# desbloqueada.
	var main_token = _new_main_en_arbol(file_data);
	var paquete_estandar = file_data["StartingPackages"]["standard"]["factories"];
	main_token.get_node("Player").availableFactories = paquete_estandar.duplicate();
	main_token._show_factory_token_screen();
	var pantalla = main_token.get_node_or_null("TokenUnlock");
	var ofrecidas_token = [];
	if pantalla != null:
		for t in _textos_de(pantalla):
			for f in factoria_de.values():
				if t.contains("Desbloquear " + f) and not ofrecidas_token.has(f):
					ofrecidas_token.append(f);
	ofrecidas_token.sort();
	var esperadas_token = factoria_de.values();
	esperadas_token.sort();
	_check("el factory token sigue ofreciendo las tres: es el camino de la ruta corriente",
		ofrecidas_token == esperadas_token, str(ofrecidas_token));
	# Este script ES el SceneTree y la pantalla pausa el árbol: si no se levanta, la pausa se
	# queda puesta para el resto de la suite (misma trampa que en Cintas M3 y en Variedad M1).
	paused = false;
	_limpiar([main_token]);

	# Y por la puerta real: aplicada la carta, la factoría queda desbloqueada y la carta sale de
	# la baraja. Una carta que siguiera ofreciéndose después sería exactamente la mejora muerta
	# que `_usable_upgrades()` existe para quitar.
	var main_carta = _new_main_de_prueba(file_data);
	var jugador_carta = main_carta.get_node("Player");
	jugador_carta.availableFactories = file_data["StartingPackages"]["standard"]["factories"].duplicate();
	main_carta._apply_upgrade("unlock_quarry");
	_check("aplicada por la puerta real, `unlock_quarry` desbloquea la cantera",
		jugador_carta.availableFactories.has("Quarry"), str(jugador_carta.availableFactories));
	var gm_gastada = _new_gm(file_data);
	var jugador_gastado = StubPlayer.new();
	jugador_gastado.availableFactories = jugador_carta.availableFactories.duplicate();
	gm_gastada.setPlayer(jugador_gastado);
	var vivas = gm_gastada._usable_upgrades();
	_check("y con la cantera puesta su carta se cae de la baraja: el tier 2 vuelve a 6",
		not vivas.has("unlock_quarry") and vivas.has("unlock_foundry")
		and vivas.has("unlock_watertreatment"), str(vivas));
	_limpiar([gm_gastada]);
	_limpiar([main_carta]);

# Todas las líneas que un botón del radial puede llegar a escribir, sacadas del JSON de verdad y
# de las cuatro redacciones de sinergia. Es la lista contra la que se mide `BUTTON_WIDTH`: una
# Label no se recorta, así que la más ancha de TODAS es la que decide si el botón vale.
func _lineas_posibles_del_radial(molde, file_data) -> Array:
	var lineas = [];
	for nombre in file_data["Factories"]:
		var params = file_data["Factories"][nombre];
		lineas.append(str(nombre));
		var material = params.get("material");
		lineas.append("(restauración)" if material == null else "→ " + str(material));
		# `materials: [...]` no cambia el botón —el radial pinta con qué se COLOCA—, pero un
		# material largo de esa lista podría llegar a ser el `material` de una entrada futura.
		for m in params.get("materials", []):
			lineas.append("→ " + str(m));
		var w = int(params.get("workers_needed", 0));
		if w > 0:
			lineas.append("⚙ " + str(w) + "W");
		for texto in molde._cost_lines(params.get("cost", null), true):
			lineas.append(texto);
		for texto in molde._cost_lines(params.get("cost", null), false):
			lineas.append(texto);
		if not (params.get("cost", null) is Dictionary):
			lineas.append("Gratis");
	# Las de sinergia, con el peor número de cada redacción: `gives_to` llega hasta 8 (las ocho
	# vecinas) y `pollution_mult` se escribe con dos decimales.
	lineas.append("✦ Tick -8s");
	lineas.append("✦ Output +8");
	lineas.append("✦ Contam. ×0.75");
	for i in range(1, 9):
		lineas.append("✦ Mejora " + str(i) + (" vecina" if i == 1 else " vecinas"));
	# Y desde Legibilidad M2 las de la CASILLA, sacadas de los `TileTypes` de verdad y por la
	# función de verdad, con los dos signos de factoría: la productora escribe «⚠ Pantano ×…» y
	# la restauradora «✦ Limpieza ×…», que no miden lo mismo.
	for tname in file_data["TileTypes"]:
		var tdef = file_data["TileTypes"][tname];
		var pv = {
			"tile_pollution_mult": float(tdef.get("pollution_multiplier", 1.0)),
			"tile_on_build_pollution": float(tdef.get("on_build_pollution", 0.0)),
		};
		for signo in [1.0, -1.0]:
			for par in molde._tile_lines(pv, signo):
				lineas.append(par[0]);
	return lineas;

# Los rectángulos de los botones del radial, en las coordenadas del Control que los cuelga —que
# es el mismo para todos, así que es donde el solape se decide—. No se usa `get_global_rect()`:
# el menú se monta y se mide en el mismo frame, y la transformada global todavía no ha pasado.
func _rects_del_radial(menu) -> Array:
	var rects = [];
	for b in menu.find_children("", "Button", true, false):
		rects.append(Rect2(b.position, b.size));
	return rects;


# ---------- Legibilidad M1: la etiqueta de la contaminación, una sola vez ----------

# Hasta este hito la fase de restauración decía `Restaurando: Contaminación: N (restaurar: ≤ M)`:
# getStatusText() traía su rótulo y _progressText() le ponía otro delante. Ahora el dato sale
# desnudo del PollutionManager y el rótulo lo pone el HUD, en sus dos caminos. Se cuenta con
# count() y no con `in` porque el defecto era justo la REPETICIÓN: `in` lo daba por bueno.
func _test_legibilidad_m1(file_data):
	print("Legibilidad M1 — la contaminación se nombra una sola vez");
	var presupuesto = load("res://managers/gameManager.gd").HUD_MAX_CHARS;
	var pm = _new_pm();
	pm.addPollution(22607.0, Vector2i(5, 5));
	_check("getStatusText() devuelve solo el dato, sin rótulo",
		not ("Contaminación" in pm.getStatusText()) and pm.getStatusText().begins_with("22607"),
		pm.getStatusText());

	var gm = _new_gm(file_data);
	var bag = _new_bag();
	bag.initialize(file_data);

	# --- Fase de restauración, sin ventana de punto muerto.
	gm.production_done = true;
	var restaurando = gm.getObjectiveText(bag, pm);
	_check("en restauración el HUD dice `Contaminación: N  (restaurar: ≤ M)`",
		restaurando == "Contaminación: 22607  (restaurar: ≤ 2717)", restaurando);
	_check("con «Contaminación» exactamente UNA vez",
		restaurando.count("Contaminación") == 1, restaurando);
	_check("y sin el «Restaurando» que la duplicaba",
		not ("Restaurando" in restaurando), restaurando);
	_check("y cabe en el Label de una sola línea",
		restaurando.length() <= presupuesto and not ("\n" in restaurando), restaurando);

	# --- Fase de producción: la cola `  |  ` sigue rotulada, también una sola vez.
	gm.production_done = false;
	gm.current_checkpoint_index = 0;
	var produciendo = gm.getObjectiveText(bag, pm);
	_check("en producción la cola sigue diciendo `  |  Contaminación: N  (restaurar: ≤ M)`",
		produciendo.ends_with("  |  Contaminación: 22607  (restaurar: ≤ 2717)"), produciendo);
	_check("también con «Contaminación» exactamente UNA vez",
		produciendo.count("Contaminación") == 1, produciendo);
	_check("y la escala del tinte (200) no vuelve al HUD por ningún camino",
		not ("/ 200" in restaurando) and not ("/ 200" in produciendo),
		"%s || %s" % [restaurando, produciendo]);

	_limpiar([pm, gm, bag]);


# ---------- Legibilidad M2: el radial avisa de lo que la casilla le hace a lo construido ----------

# Hasta este hito `preview_synergies()` miraba dos fuentes —el adjacency_bonus del tile y las
# vecinas— y callaba otras dos que el juego sí aplica: el ×1.5 del pantano (build()) y el +10 de
# la tierra quemada (Main._on_factory_chosen()). El jugador se enteraba después de pagar. Aquí se
# fija que el preview las trae en claves PROPIAS, que el radial las pinta con el color que toca
# según ensucien o limpien, que una casilla normal no añade nada y que consultar no mueve nada.
# El veredicto visual —si el rojo se lee sobre el botón— es de quien mire el juego.
func _test_legibilidad_m2(file_data):
	print("Legibilidad M2 — el radial anuncia pantano y tierra quemada antes de construir");
	var placer = load("res://entities/factory/factoryPlacer.gd").new();
	var arr = [];
	placer.initialize(null, file_data, arr);
	var swamp = file_data["TileTypes"]["swamp"];
	var burned = file_data["TileTypes"]["burned"];
	var mult_json = float(swamp["pollution_multiplier"]);
	var on_build_json = float(burned["on_build_pollution"]);
	var stub = StubTileMap.new();
	var c_swamp = Vector2i(3, 3);
	var c_burned = Vector2i(6, 3);
	var c_forest = Vector2i(9, 3);
	var c_vacia = Vector2i(12, 3);
	stub.defs[c_swamp] = swamp;
	stub.defs[c_burned] = burned;
	stub.defs[c_forest] = file_data["TileTypes"]["forest"];

	# --- (1) El preview trae las dos fuentes, leídas del JSON y en claves propias.
	var p_swamp = placer.preview_synergies("WoodCutter", c_swamp, stub);
	_check("sobre swamp el preview trae el multiplicador del JSON en su propia clave",
		_near(p_swamp["tile_pollution_mult"], mult_json) and _near(mult_json, 1.5), str(p_swamp));
	_check("y NO lo mezcla con el pollution_mult de las sinergias, que sigue neutro",
		_near(p_swamp["pollution_mult"], 1.0) and _near(p_swamp["tile_on_build_pollution"], 0.0),
		str(p_swamp));
	var p_burned = placer.preview_synergies("WoodCutter", c_burned, stub);
	_check("sobre burned el preview trae el +10 del JSON en su propia clave",
		_near(p_burned["tile_on_build_pollution"], on_build_json) and _near(on_build_json, 10.0)
		and _near(p_burned["tile_pollution_mult"], 1.0), str(p_burned));
	var p_forest = placer.preview_synergies("WoodCutter", c_forest, stub);
	var p_vacia = placer.preview_synergies("WoodCutter", c_vacia, stub);
	_check("sobre casilla normal (forest y sin tipo) las dos claves quedan neutras",
		_near(p_forest["tile_pollution_mult"], 1.0) and _near(p_forest["tile_on_build_pollution"], 0.0)
		and _near(p_vacia["tile_pollution_mult"], 1.0)
		and _near(p_vacia["tile_on_build_pollution"], 0.0), "%s / %s" % [str(p_forest), str(p_vacia)]);
	_check("y el adjacency_bonus de forest sigue llegando como antes",
		p_forest["output_bonus"] == 1, str(p_forest));

	# --- (2) La redacción y el color, por la función de verdad.
	var radial = load("res://ui/radialMenu.gd").new();
	var fac = file_data["Factories"];
	var wc_sw = radial._tile_lines(p_swamp, float(fac["WoodCutter"]["pollution"]));
	_check("productora sobre swamp: «⚠ Pantano ×1.5» en rojo",
		wc_sw.size() == 1 and wc_sw[0][0] == "⚠ Pantano ×1.5"
		and wc_sw[0][1] == radial.TILE_WARNING_COLOR, str(wc_sw));
	for tipo in ["Reforester", "WaterTreatment"]:
		var pv = placer.preview_synergies(tipo, c_swamp, stub);
		var ls = radial._tile_lines(pv, float(fac[tipo]["pollution"]));
		_check("restauradora (%s) sobre swamp: «✦ Limpieza ×1.5» en el verde de las sinergias" % tipo,
			ls.size() == 1 and ls[0][0] == "✦ Limpieza ×1.5"
			and ls[0][1] == radial.SYNERGY_COLOR, str(ls));
	var mf_sw = radial._tile_lines(placer.preview_synergies("WorkerCamp", c_swamp, stub),
		float(fac["WorkerCamp"]["pollution"]));
	_check("una factoría de contaminación 0 (WorkerCamp) no anuncia el pantano: ×1.5 sobre 0 es 0",
		_near(float(fac["WorkerCamp"]["pollution"]), 0.0) and mf_sw.is_empty(), str(mf_sw));
	for tipo in ["WoodCutter", "Reforester"]:
		var ls = radial._tile_lines(placer.preview_synergies(tipo, c_burned, stub),
			float(fac[tipo]["pollution"]));
		_check("%s sobre burned: «⚠ Quemada +10» en rojo, limpie o no" % tipo,
			ls.size() == 1 and ls[0][0] == "⚠ Quemada +10"
			and ls[0][1] == radial.TILE_WARNING_COLOR, str(ls));
	_check("sobre casilla normal ninguna línea nueva",
		radial._tile_lines(p_forest, 3.0).is_empty() and radial._tile_lines(p_vacia, -4.0).is_empty()
		and radial._tile_lines({}, 3.0).is_empty());

	# --- (3) El ancho: cada línea nueva cabe con la holgura que exige M4b.
	var fuente = ThemeDB.fallback_font;
	var nuevas = [wc_sw[0][0], "✦ Limpieza ×1.5", "⚠ Quemada +10"];
	var peor = 0.0;
	for t in nuevas:
		peor = max(peor, fuente.get_string_size(t, HORIZONTAL_ALIGNMENT_CENTER, -1, 11).x);
	_check("las tres líneas nuevas caben en el botón con 8 px de holgura",
		peor <= float(radial.BUTTON_WIDTH) - 8.0, "la más ancha mide %.0f px" % peor);

	# --- (4) El menú montado: la línea sale en el botón de verdad, con su color.
	root.add_child(radial);
	radial.initialize(["WoodCutter", "Reforester"], file_data, c_swamp, Vector2(640, 360),
		{ "WoodCutter": p_swamp,
		  "Reforester": placer.preview_synergies("Reforester", c_swamp, stub) });
	var vistas = {};
	for l in radial.find_children("", "Label", true, false):
		vistas[l.text] = l.get_theme_color("font_color");
	_check("montado sobre swamp, el botón del WoodCutter pinta «⚠ Pantano ×1.5» en rojo",
		vistas.get("⚠ Pantano ×1.5", null) == radial.TILE_WARNING_COLOR, str(vistas.keys()));
	_check("y el del Reforester «✦ Limpieza ×1.5» en verde",
		vistas.get("✦ Limpieza ×1.5", null) == radial.SYNERGY_COLOR, str(vistas.keys()));
	var rects = _rects_del_radial(radial);
	var solapes = 0;
	for i in range(rects.size()):
		for j in range(i + 1, rects.size()):
			if rects[i].intersects(rects[j]):
				solapes += 1;
	_check("y la línea de más no monta ningún botón sobre otro", solapes == 0, str(rects));
	_limpiar([radial]);

	# --- (5) Consultar no aplica: ni el valor base de una vecina ni la contaminación de la celda.
	var pm = _new_pm();
	pm.addPollution(4.0, c_burned);
	var vecina = _new_factory("WoodCutter", c_swamp + Vector2i(1, 0));
	vecina.pollutionAmount = 3.0;
	arr.append(vecina);
	var antes = [vecina.pollutionAmount, vecina.synergy_pollution_mult, pm.getCellPollution(c_burned),
		pm.getCellPollution(c_swamp), pm.total_pollution, arr.size(),
		float(swamp["pollution_multiplier"]), float(burned["on_build_pollution"])];
	for i in range(10):
		placer.preview_synergies("WoodCutter", c_swamp, stub);
		placer.preview_synergies("Reforester", c_burned, stub);
	var despues = [vecina.pollutionAmount, vecina.synergy_pollution_mult,
		pm.getCellPollution(c_burned), pm.getCellPollution(c_swamp), pm.total_pollution, arr.size(),
		float(swamp["pollution_multiplier"]), float(burned["on_build_pollution"])];
	_check("consultar 20 veces sobre swamp y burned no mueve pollutionAmount, la celda ni el JSON",
		antes == despues, "antes %s, después %s" % [str(antes), str(despues)]);

	_limpiar([pm, vecina, placer]);


# ---------- Analítica M1: catálogo, analytics.gd y la atadura con el código ----------

# `resources/analyticsCatalog.json` es la única lista de eventos y props, y `managers/analytics.gd`
# el único que habla con `Augur`. Aquí se fija: que ningún `analytics.track("…")` del código nombra
# un evento fuera del catálogo y que nadie más llama a `Augur.track`; que el validador tumba lo que
# no cumple su tipo sin mandar nada; que las familias y los enums salen del factoryParams.json; que
# una run abre y cierra con el mismo `run_id` y un solo `run_end`; que `balance_id` es estable y
# cambia con el balance; y que Main crea el nodo y reset() no lo libera. La secuencia por el camino
# real (`_on_factory_chosen` → demoler → `end_run`) necesita los ganchos de M2/M3 y va en M3.

# Los únicos sitios desde los que se puede llamar a `Augur.track`. Desde M2 el humo de Augur
# (`_start_game()` y `_track_run_end()`) ya pasa por `analytics.begin_run()` / `end_run()` y no
# queda ninguna excepción más.
const AUGUR_TRACK_PERMITIDO = [
	["res://managers/analytics.gd", ""],
	["res://Main.gd", "_configure_augur"],
];

var _augur_huella_inicial = null;

func _gd_del_proyecto(dir_path, out):
	var dir = DirAccess.open(dir_path);
	if dir == null:
		return out;
	for sub in dir.get_directories():
		if sub.begins_with(".") or (dir_path == "res://" and sub == "addons"):
			continue;
		_gd_del_proyecto(dir_path.path_join(sub), out);
	for f in dir.get_files():
		if f.ends_with(".gd"):
			out.append(dir_path.path_join(f));
	return out;

# Las llamadas a `Augur.track` de un fichero que caen fuera de lo permitido, como
# "fichero:línea (función)". Se ignora lo que va detrás de `#`, y el patrón se arma por trozos
# para que este mismo fichero no se denuncie a sí mismo.
func _augur_track_fuera(path, text):
	var re_call = RegEx.new();
	re_call.compile("\\b" + "Aug" + "ur\\.track\\s*\\(");
	var re_func = RegEx.new();
	re_func.compile("^(static\\s+)?func\\s+(\\w+)");
	var fuera = [];
	var funcion = "";
	var lineas = text.split("\n");
	for i in range(lineas.size()):
		var m = re_func.search(lineas[i]);
		if m != null:
			funcion = m.get_string(2);
		var codigo = lineas[i].split("#")[0];
		if re_call.search(codigo) == null:
			continue;
		var ok = false;
		for permitido in AUGUR_TRACK_PERMITIDO:
			if permitido[0] == path and (permitido[1] == "" or permitido[1] == funcion):
				ok = true;
		if not ok:
			fuera.append("%s:%d (%s)" % [path, i + 1, funcion]);
	return fuera;

func _huella_augur():
	var raiz = "user://augur/";
	if not DirAccess.dir_exists_absolute(raiz):
		return null;
	var huella = {};
	var pendientes = [raiz];
	while not pendientes.is_empty():
		var d = pendientes.pop_back();
		var dir = DirAccess.open(d);
		if dir == null:
			continue;
		huella[d] = "dir";
		for sub in dir.get_directories():
			pendientes.append(d.path_join(sub));
		for f in dir.get_files():
			var p = d.path_join(f);
			huella[p] = "%d:%d" % [FileAccess.get_modified_time(p), FileAccess.get_file_as_bytes(p).size()];
	return huella;

func _new_analytics(file_data, recibidos):
	var a = load("res://managers/analytics.gd").new();
	a.name = "Analytics";
	a.initialize(file_data);
	a.sink = func(n, p): recibidos.append([n, p]);
	return a;

func _test_analitica_m1(file_data):
	print("Analítica M1 — catálogo expandido, validador, run_id, balance_id y atadura con el código");
	var params_text = FileAccess.get_file_as_string("res://resources/factoryParams.json");

	# --- (1) Atadura código ↔ catálogo.
	var recibidos = [];
	var a = _new_analytics(file_data, recibidos);
	_check("el catálogo carga y se expande", a.loaded);
	var re_track = RegEx.new();
	re_track.compile("\\banalytics\\.track\\(\\s*\"([^\"]+)\"");
	var re_propio = RegEx.new();
	re_propio.compile("(?<![\\w.])track\\(\\s*\"([^\"]+)\"");
	var nombrados = [];
	var desconocidos = [];
	var augur_fuera = [];
	for path in _gd_del_proyecto("res://", []):
		if path.begins_with("res://tests/"):
			continue;
		var text = FileAccess.get_file_as_string(path);
		var hits = re_track.search_all(text);
		if path == "res://managers/analytics.gd":
			hits = re_propio.search_all(text);
		for m in hits:
			nombrados.append(m.get_string(1));
			if not a.events.has(m.get_string(1)):
				desconocidos.append("%s: %s" % [path, m.get_string(1)]);
		augur_fuera.append_array(_augur_track_fuera(path, text));
	_check("el rastreo encuentra los track() propios de analytics.gd (run_start y run_end)",
		nombrados.has("run_start") and nombrados.has("run_end"), str(nombrados));
	_check("ningún track(\"…\") del código nombra un evento fuera del catálogo",
		desconocidos.is_empty(), str(desconocidos));
	_check("nadie fuera de analytics.gd y _configure_augur() llama a Augur.track",
		augur_fuera.is_empty(), str(augur_fuera));
	var plantada = "func _otra():\n\t" + "Aug" + "ur.track(\"x\", {})\n";
	_check("y el detector sí denuncia una llamada plantada fuera de lo permitido",
		_augur_track_fuera("res://ui/falso.gd", plantada).size() == 1
		and _augur_track_fuera("res://Main.gd", plantada).size() == 1);

	# --- (2) Expansión.
	_check("el catálogo trae los 25 eventos: los 22 de las tres tablas, segment_rate (Legibilidad M0) y weather_started/weather_ended (2026-10-01)", a.events.size() == 25, str(a.events.keys()));
	var factorias = file_data["Factories"].keys();
	var run_end = a.events["run_end"]["props"];
	var built = [];
	for p in run_end:
		if p.begins_with("built_") and p != "built_total":
			built.append(p);
	var esperadas = [];
	for f in factorias:
		esperadas.append("built_" + f);
	built.sort();
	esperadas.sort();
	_check("built_*@per_factory abre una prop por cada clave de Factories, y ninguna más",
		built == esperadas, "%s vs %s" % [str(built), str(esperadas)]);
	var cartas = a.enums["card"];
	var faltan = [];
	for u in file_data["Upgrades"]:
		if not cartas.has(u):
			faltan.append(u);
	for f in factorias:
		if not cartas.has("token_unlock_" + f):
			faltan.append("token_unlock_" + f);
	_check("card incluye las %d de Upgrades y un token_unlock_* por factoría" % file_data["Upgrades"].size(),
		faltan.is_empty() and file_data["Upgrades"].size() == 13
		and cartas.size() == file_data["Upgrades"].size() + factorias.size(), str(faltan));
	var mats = a.enums["material"];
	_check("material sale de material y materials[] de Factories: wood, plank, stone y también glass",
		mats.has("wood") and mats.has("plank") and mats.has("stone") and mats.has("glass")
		and not mats.has(null), str(mats));
	var mapas = [];
	for m in file_data["Maps"]:
		mapas.append(m["id"]);
	_check("map son los id de Maps y tile trae plain", a.enums["map"] == mapas and a.enums["tile"].has("plain"),
		str(a.enums["map"]));
	var re_nombre = RegEx.new();
	re_nombre.compile("^[A-Za-z0-9_]{1,64}$");
	var malos = [];
	var sin_run = [];
	for ev in a.events:
		if a.events[ev]["description"] == "":
			malos.append(ev + " sin descripción");
		for p in a.events[ev]["props"]:
			if re_nombre.search(p) == null:
				malos.append(ev + "." + p);
		if a.events[ev]["run"] and not (a.events[ev]["props"].has("run_id") and a.events[ev]["props"].has("run_t")):
			sin_run.append(ev);
	_check("toda prop cabe en ^[A-Za-z0-9_]{1,64}$ y todo evento tiene descripción", malos.is_empty(), str(malos));
	_check("todo evento de run declara run_id y run_t, y ui_open es el único que no es de run",
		sin_run.is_empty() and not a.events["ui_open"]["run"], str(sin_run));
	var upsert = a.export_upsert();
	var fe = {};
	for e in upsert:
		if e["name"] == "factory_built":
			fe = e["properties"];
	_check("export_upsert: enum/id → string, int/float/bool01 → number",
		upsert.size() == 25 and fe.get("factory", {}).get("type") == "string"
		and fe.get("run_id", {}).get("type") == "string" and fe.get("cx", {}).get("type") == "number"
		and fe.get("run_t", {}).get("type") == "number" and fe.has("paid_wood"), str(fe));

	# --- (3) Validador: nada que no cumpla llega al sink.
	_check("un evento sin run (ui_open) pasa sin run viva",
		a.track("ui_open", {"screen": "main_menu"}) and recibidos.size() == 1);
	recibidos.clear();
	var rechazos = [
		a.track("no_existe"),
		a.track("ui_open", {"screen": "no_es_pantalla"}),
		a.track("ui_open", {"screen": "main_menu", "extra": 1}),
		a.track("factory_built", {"factory": "WoodCutter", "cx": 3, "cy": 4}),
	];
	_check("evento desconocido, valor fuera de enum, prop no declarada y evento de run sin run → false",
		rechazos == [false, false, false, false] and recibidos.is_empty(), str(rechazos));

	var pm = _new_pm();
	var gm = _new_gm(file_data);
	var bag = _new_bag();
	bag.initialize(file_data);
	bag.addToBag("wood", 40.0);
	a.begin_run(gm, pm, bag, null, [], "standard", "forest_01");
	recibidos.clear();
	var r_float = a.track("factory_built", {"factory": "WoodCutter", "cx": 3.0, "cy": 4});
	var r_bool = a.track("card_offered", {"card": "extra_wood", "chosen": 2});
	var r_id = a.track("run_start", {"balance_id": "XYZ"});
	_check("float donde va int, bool01 fuera de 0/1 e id que no es hex → false y el sink no recibe nada",
		[r_float, r_bool, r_id] == [false, false, false] and recibidos.is_empty());
	_check("bool01 acepta un bool y lo manda como 1; float acepta int y lo manda como float",
		a.track("card_offered", {"card": "extra_wood", "chosen": true, "decision_ms": 1200})
		and a.track("deadlock_closed", {"secs": 3, "outcome": "recovered"})
		and typeof(recibidos[0][1]["chosen"]) == TYPE_INT and recibidos[0][1]["chosen"] == 1
		and typeof(recibidos[1][1]["secs"]) == TYPE_FLOAT, str(recibidos));
	a.end_run("abandon");

	# --- (4) Secuencia directa sobre analytics (la de Main va en M3).
	recibidos.clear();
	gm.run_time = 5.0;
	a.begin_run(gm, pm, bag, null, [], "standard", "forest_01");
	gm.run_time = 12.5;
	a.track("factory_built", {"factory": "WoodCutter", "cx": 3, "cy": 4, "tile": "plain",
		"n_synergies": 0, "paid_wood": 4});
	gm.run_time = 20.0;
	a.track("factory_demolished", {"factory": "WoodCutter", "cx": 3, "cy": 4, "age_s": 7.5,
		"refund_wood": 2});
	var cerrado = a.end_run("abandon");
	var segundo = a.end_run("abandon");
	var nombres = [];
	var ids = {};
	for r in recibidos:
		nombres.append(r[0]);
		ids[r[1].get("run_id", "")] = true;
	_check("begin_run → factory_built → factory_demolished → end_run emite exactamente esos cuatro",
		nombres == ["run_start", "factory_built", "factory_demolished", "run_end"], str(nombres));
	_check("los cuatro con el mismo run_id, de 8 hex", ids.size() == 1 and String(ids.keys()[0]).length() == 8,
		str(ids.keys()));
	_check("un segundo end_run no emite", cerrado and not segundo and recibidos.size() == 4);
	var rs = recibidos[0][1];
	var re = recibidos[3][1];
	_check("run_start lleva paquete, mapa, balance_id de 12 hex y las 8 constantes",
		rs["package"] == "standard" and rs["map"] == "forest_01" and String(rs["balance_id"]).length() == 12
		and rs.has("contagion_rate") and rs.has("pollution_threshold") and rs["run_t"] == 5.0, str(rs));
	_check("run_end cuenta built_WoodCutter = 1, built_total = 1, demolished_total = 1 y built_Quarry = 0",
		re["result"] == "abandon" and re["built_WoodCutter"] == 1 and re["built_total"] == 1
		and re["demolished_total"] == 1 and re["built_Quarry"] == 0, str(re));
	_check("run_end lee Bag y los managers con int() explícito (left_wood %s, checkpoints %s)" % [str(re.get("left_wood")), str(re.get("checkpoints"))],
		typeof(re["left_wood"]) == TYPE_INT and re["left_wood"] == int(bag.getAvailable("wood"))
		and typeof(re["checkpoints"]) == TYPE_INT and typeof(re["workers_total"]) == TYPE_INT
		and typeof(re["duration_ms"]) == TYPE_INT and re["balance_id"] == rs["balance_id"]);
	_check("idle_s cuenta desde la última acción (demoler en t=20) y run_t es el run_time",
		_near(re["idle_s"], 0.0) and re["run_t"] == 20.0 and recibidos[1][1]["run_t"] == 12.5, str(re["idle_s"]));
	_check("sin run viva, un evento de run vuelve a rechazarse",
		not a.track("belt_removed", {"cx": 1, "cy": 1}) and recibidos.size() == 4);

	# --- (5) balance_id.
	var consts = a.run_constants(pm, gm);
	var b1 = a.balance_id(params_text, consts);
	var b2 = a.balance_id(params_text, consts.duplicate());
	var tocadas = consts.duplicate();
	tocadas["contagion_rate"] = consts["contagion_rate"] + 0.01;
	var b3 = a.balance_id(params_text, tocadas);
	var b4 = a.balance_id(params_text + " ", consts);
	_check("balance_id es estable con el mismo JSON y las mismas constantes", b1 == b2 and b1.length() == 12, b1);
	_check("y cambia al tocar contagion_rate o el texto del JSON", b3 != b1 and b4 != b1, "%s %s %s" % [b1, b3, b4]);
	var props_rs = a.events["run_start"]["props"];
	var constantes_ok = consts.size() == 8;
	for k in consts:
		constantes_ok = constantes_ok and props_rs.has(k) and typeof(consts[k]) == TYPE_FLOAT;
	_check("run_constants da las 8 de run_start, en float", constantes_ok, str(consts));
	_limpiar([a, pm, gm, bag]);

	# --- (6) Main crea Analytics en _ready() y reset() no lo libera.
	var main = load("res://Main.gd").new();
	main.name = "Main";
	root.add_child(main);
	var nodo = main.get_node_or_null("Analytics");
	var sm = main.get_node_or_null("SaveManager");
	_check("Main._ready() crea el hijo Analytics, cargado, antes que el SaveManager",
		nodo != null and nodo == main.analytics and nodo.loaded and sm != null
		and nodo.get_index() < sm.get_index());
	main.reset();
	_check("reset() no libera Analytics: sigue siendo el mismo nodo",
		is_instance_valid(nodo) and not nodo.is_queued_for_deletion() and main.get_node_or_null("Analytics") == nodo);
	# `mapLoader` es un nodo que Main crea y nunca cuelga del árbol: se suelta a mano.
	var ml = main.mapLoader;
	_limpiar([main]);
	if is_instance_valid(ml) and ml is Node:
		ml.free();

# ---------- Analítica M2: el ciclo de la run por el camino de Main ----------

# Una run de verdad (`_start_game()`) con el `sink` falso: `run_start` con el mapa de `pick_map()`,
# el `checkpoint_reached` que Main lee de `gameManager.last_tier`/`last_segment_rate`, una fila de
# `card_offered` por carta mostrada (slot 1..N, un `chosen` 1) también desde las ruinas (oferta de
# una), la ventana del punto muerto y el `run_end` de la `R` con `screen: none`, todos con el mismo
# `run_id`; un segundo cierre no emite. El censo de construcción va a 0: lo cuenta M3.
func _nombres_de(recibidos):
	var nombres = [];
	for r in recibidos:
		nombres.append(r[0]);
	return nombres;

func _filas_de(recibidos, nombre):
	var filas = [];
	for r in recibidos:
		if r[0] == nombre:
			filas.append(r[1]);
	return filas;

func _test_analitica_m2(file_data):
	print("Analítica M2 — ciclo de la run por Main: run_start, checkpoint, cartas, punto muerto y run_end");
	var main = _main_para_run();
	var recibidos = [];
	main.analytics.sink = func(n, p): recibidos.append([n, p]);
	main._start_game("standard");
	var gm = main.gameManager;
	var placer = main.placer;

	# --- (1) run_start desde _start_game(), con el mapa que eligió pick_map().
	_check("_start_game() emite run_start y nada más", _nombres_de(recibidos) == ["run_start"],
		str(_nombres_de(recibidos)));
	var rs = recibidos[0][1] if recibidos.size() > 0 else {};
	_check("run_start lleva el paquete y el mapa de pick_map() (%s)" % main._run_map_id,
		main._run_map_id != "" and rs.get("map", "") == main._run_map_id
		and rs.get("package", "") == "standard" and main.analytics.has_run(), str(rs));

	# --- (2) Se cierra el checkpoint 1: la señal real del gameManager llega a Main.
	recibidos.clear();
	gm.current_checkpoint_index = 1;
	gm.run_time = 42.0;
	gm.last_checkpoint_time = 42.0;
	gm.last_tier = 2;
	gm.last_segment_rate = 0.75;
	var oferta = ["speed_woodcutter", "more_workers", "extra_wood"];
	gm.checkpoint_reached.emit(oferta, {}, []);
	var cr = _filas_de(recibidos, "checkpoint_reached");
	_check("checkpoint_reached sale una vez con checkpoint 1, seg_t, tier y rate del gameManager",
		cr.size() == 1 and cr[0]["checkpoint"] == 1 and _near(cr[0]["seg_t"], 42.0)
		and cr[0]["tier"] == 2 and _near(cr[0]["rate"], 0.75), str(cr));
	_check("y se abre la pantalla de carta con su ui_open",
		_filas_de(recibidos, "ui_open").map(func(p): return p["screen"]) == ["upgrade"]
		and main.get_node_or_null("UpgradeScreen") != null, str(_nombres_de(recibidos)));
	_check("montar la oferta no emite card_offered: se manda al elegir",
		_filas_de(recibidos, "card_offered").is_empty());
	recibidos.clear();
	main.get_node("UpgradeScreen")._on_upgrade_chosen("more_workers");
	var co = _filas_de(recibidos, "card_offered");
	var slots = [];
	var cartas = [];
	var elegidas = 0;
	var co_ok = co.size() == 3;
	for fila in co:
		slots.append(fila["slot"]);
		cartas.append(fila["card"]);
		elegidas += fila["chosen"];
		co_ok = (co_ok and fila["source"] == "checkpoint" and fila["checkpoint"] == 1
			and typeof(fila["decision_ms"]) == TYPE_INT and fila["decision_ms"] >= 0
			and fila["tier"] == int(file_data["Upgrades"][fila["card"]]["tier"])
			and fila["chosen"] == (1 if fila["card"] == "more_workers" else 0));
	_check("elegir manda 3 × card_offered, una fila por carta en su orden (slot 1..3)",
		co_ok and slots == [1, 2, 3] and cartas == oferta, str(co));
	_check("y exactamente una con chosen 1, la elegida", elegidas == 1);
	paused = false;

	# --- (3) Las ruinas: oferta de UNA carta, source ruins y sin checkpoint_reached. Por el
	# camino real: construir sobre la casilla de ruinas del mapa.
	recibidos.clear();
	var tm = main.get_node("TileMap");
	var ruina = null;
	for c in tm.cell_types:
		if tm.cell_types[c] == "ruins":
			ruina = c;
	_check("el mapa de la run tiene su casilla de ruinas", ruina != null);
	if ruina != null:
		main._on_factory_chosen("WoodCutter", ruina);
	var pantalla = main.get_child(main.get_child_count() - 1);
	var ofrecida = main._offer_ids.duplicate();
	_check("construir sobre ruinas monta una oferta de una carta, sin checkpoint_reached",
		ofrecida.size() == 1 and pantalla.has_signal("upgrade_chosen")
		and _filas_de(recibidos, "checkpoint_reached").is_empty()
		and _filas_de(recibidos, "ui_open").size() == 1, "%s %s" % [str(ofrecida), str(_nombres_de(recibidos))]);
	recibidos.clear();
	if pantalla.has_signal("upgrade_chosen") and ofrecida.size() == 1:
		pantalla._on_upgrade_chosen(ofrecida[0]);
	var cr_ruina = _filas_de(recibidos, "card_offered");
	_check("elegirla manda 1 × card_offered con source ruins, slot 1 y chosen 1",
		cr_ruina.size() == 1 and cr_ruina[0]["source"] == "ruins" and cr_ruina[0]["slot"] == 1
		and cr_ruina[0]["chosen"] == 1 and cr_ruina[0]["checkpoint"] == 1, str(cr_ruina));
	paused = false;

	# --- (4) La ventana del punto muerto, por las señales nuevas del gameManager.
	recibidos.clear();
	gm.deadlock_opened.emit();
	gm.deadlock_closed.emit(4.5, false);
	gm.deadlock_closed.emit(2.0, true);
	var dl = recibidos.map(func(r): return [r[0], r[1].get("checkpoint", r[1].get("outcome", ""))]);
	_check("deadlock_opened lleva el checkpoint y deadlock_closed secs + outcome recovered/lost",
		dl == [["deadlock_opened", 1], ["deadlock_closed", "recovered"], ["deadlock_closed", "lost"]]
		and _near(recibidos[1][1]["secs"], 4.5), str(recibidos));

	# --- (5) `R` con la run viva: run_end abandon con screen none, y luego el package_select.
	recibidos.clear();
	var tecla = InputEventKey.new();
	tecla.keycode = KEY_R;
	tecla.pressed = true;
	main._unhandled_input(tecla);
	var re = _filas_de(recibidos, "run_end");
	var fin = re[0] if re.size() == 1 else {};
	_check("R emite un run_end abandon con screen none", re.size() == 1
		and fin.get("result") == "abandon" and fin.get("screen") == "none", str(re));
	# Desde M3 el WoodCutter de las ruinas cuenta: es el único que el jugador construyó.
	_check("con el censo de M2: checkpoints 1, cards_chosen 2, belt_cells de la red, y el WoodCutter de las ruinas (M3)",
		fin.get("checkpoints") == 1 and fin.get("cards_chosen") == 2
		and typeof(fin.get("belt_cells")) == TYPE_INT and fin.get("built_total") == 1
		and fin.get("demolished_total") == 0 and fin.get("built_WoodCutter") == 1
		and typeof(fin.get("left_wood")) == TYPE_INT and fin.get("map") == main._run_map_id, str(fin));
	_check("y después se abre el package_select con su ui_open",
		_nombres_de(recibidos) == ["run_end", "ui_open"] and recibidos[1][1]["screen"] == "package_select",
		str(_nombres_de(recibidos)));
	_check("el run_id del run_end es el del run_start", fin.get("run_id", "") == rs.get("run_id", "-"));
	recibidos.clear();
	main._end_run("abandon");
	main._unhandled_input(tecla);
	# Desde Serialización M4 la R sin run montada no hace nada —ni reabre el package_select—:
	# antes reiniciaba igual y volvía a mandar el ui_open.
	_check("un segundo cierre (otra R, o ganar tras abandonar) no emite nada",
		_nombres_de(recibidos).is_empty() and not main.analytics.has_run(), str(_nombres_de(recibidos)));
	paused = false;
	var ml = main.mapLoader;
	_limpiar([main]);
	for n in [placer, ml]:
		if is_instance_valid(n) and n is Node:
			n.free();

	# --- (6) Todo con el mismo run_id: una run completa sin cortes, del run_start al run_end.
	var main2 = _main_para_run();
	var todos = [];
	main2.analytics.sink = func(n, p): todos.append([n, p]);
	main2._start_game("standard");
	var gm2 = main2.gameManager;
	gm2.current_checkpoint_index = 1;
	gm2.last_checkpoint_time = 30.0;
	gm2.checkpoint_reached.emit(["speed_woodcutter", "extra_wood", "more_workers"], {}, []);
	main2.get_node("UpgradeScreen")._on_upgrade_chosen("extra_wood");
	# Una carta concedida y una casilla tóxica que vuelve a suelo, por sus caminos de Main.
	main2._apply_granted_upgrades(["more_workers"]);
	var tm2 = main2.get_node("TileMap");
	var toxica = Vector2i(0, 0);
	tm2.cell_types[toxica] = "toxic";
	main2.pollutionManager.pollution_per_cell[toxica] = 0.0;
	main2._check_toxic_unlock(tm2);
	main2._end_run("abandon");
	var ids = {};
	var de_run = [];
	for r in todos:
		if r[0] == "ui_open":
			continue;
		de_run.append(r[0]);
		ids[r[1].get("run_id", "")] = true;
	_check("run_start → checkpoint_reached → 3 × card_offered → card_granted → cell_restored → run_end, mismo run_id",
		de_run == ["run_start", "checkpoint_reached", "card_offered", "card_offered", "card_offered",
			"card_granted", "cell_restored", "run_end"]
		and ids.size() == 1 and not ids.has(""), "%s %s" % [str(de_run), str(ids.keys())]);
	var cg = _filas_de(todos, "card_granted");
	var cz = _filas_de(todos, "cell_restored");
	_check("card_granted lleva carta y checkpoint; cell_restored la casilla",
		cg.size() == 1 and cg[0]["card"] == "more_workers" and cg[0]["checkpoint"] == 1
		and cz.size() == 1 and cz[0]["cx"] == 0 and cz[0]["cy"] == 0, "%s %s" % [str(cg), str(cz)]);
	paused = false;
	var placer2 = main2.placer;
	var ml2 = main2.mapLoader;
	_limpiar([main2]);
	for n in [placer2, ml2]:
		if is_instance_valid(n) and n is Node:
			n.free();

	# --- (7) El gameManager: la ventana se anuncia al abrirse, se cierra como recuperada o como
	# perdida (ANTES de run_lost, con la run aún viva para la analítica) y nunca dos veces.
	var gracia = load("res://managers/gameManager.gd").DEADLOCK_GRACE;
	var centro = Vector2i(5, 5);
	var pm = _new_pm();
	var esc = _escenario_muerto(file_data, centro, pm);
	esc["pm"] = pm;
	var g = esc["gm"];
	var orden = [];
	g.deadlock_opened.connect(func(): orden.append(["opened"]));
	g.deadlock_closed.connect(func(secs, lost): orden.append(["closed", secs, lost]));
	g.run_lost.connect(func(_stats): orden.append(["lost"]));
	var t0 = 10.0;
	g.run_time = t0;
	g.update(esc["bag"], pm);
	_check("abrir la ventana emite deadlock_opened una vez", orden == [["opened"]], str(orden));
	var t = _correr_hasta(esc, t0, t0 + gracia + 0.1);
	_check("al perder: deadlock_closed(secs≈gracia, lost) y DESPUÉS run_lost",
		orden.size() == 3 and orden[1][0] == "closed" and orden[1][2] == true
		and orden[1][1] >= gracia and orden[1][1] < gracia + 0.1 and orden[2] == ["lost"], str(orden));
	_correr_hasta(esc, t, t + 1.0);
	g.reset();
	_check("y ni más frames ni reset() lo vuelven a cerrar", orden.size() == 3, str(orden));
	_limpiar([esc["tm"], g, esc["bag"], pm]);

	var pm2 = _new_pm();
	var esc2 = _escenario_muerto(file_data, centro, pm2);
	esc2["pm"] = pm2;
	var g2 = esc2["gm"];
	var orden2 = [];
	g2.deadlock_opened.connect(func(): orden2.append(["opened"]));
	g2.deadlock_closed.connect(func(secs, lost): orden2.append(["closed", secs, lost]));
	g2.run_time = t0;
	g2.update(esc2["bag"], pm2);
	var t2 = _correr_hasta(esc2, t0, t0 + 5.0);
	esc2["bag"].addToBag("wood", 1);
	_correr_hasta(esc2, t2, t2 + 1.0 / 60.0);
	_check("producir cierra la ventana como recuperada, con los segundos que estuvo abierta",
		orden2.size() >= 2 and orden2[0] == ["opened"] and orden2[1][0] == "closed"
		and orden2[1][2] == false and absf(orden2[1][1] - 5.0) < 0.1, str(orden2));
	var n_antes = orden2.size();
	g2.deadlock_timer = 0.0;
	g2._deadlock_announced = false;
	g2._reset_deadlock();
	_check("_reset_deadlock() sin ventana anunciada no emite", orden2.size() == n_antes, str(orden2));
	_limpiar([esc2["tm"], g2, esc2["bag"], pm2]);

	# --- (8) last_tier y last_segment_rate: el gameManager los escribe al cerrar de verdad un
	# checkpoint, antes de emitir.
	var g3 = _new_gm(file_data, [
		{ "material": "wood", "quantity": 5, "label": "Uno" },
		{ "material": "wood", "quantity": 999, "label": "Dos" },
	]);
	var bolsa3 = _new_bag();
	bolsa3.initialize(file_data);
	bolsa3.addToBag("wood", 10.0);
	var visto = [];
	g3.checkpoint_reached.connect(func(_o, _r, _gr): visto.append([g3.last_tier, g3.last_segment_rate]));
	g3.run_time = 3.0;
	g3.update(bolsa3, null);
	_check("cerrar un checkpoint deja last_tier (1-2) y last_segment_rate (float) escritos al emitir",
		visto.size() == 1 and (visto[0][0] == 1 or visto[0][0] == 2) and typeof(visto[0][1]) == TYPE_FLOAT,
		str(visto));
	_limpiar([g3, bolsa3]);

# ---------- Analítica M3: las acciones del jugador ----------

# Los doce eventos de acción por sus caminos de Main, con el `sink` falso. Lo que va por el ratón
# (arrastre de cinta, click rechazado, borrar cinta) se conduce por `_unhandled_input()` moviendo
# el TileMap para que la casilla pedida quede bajo el cursor, que headless no se mueve.
const ANALITICA_ACCION = ["factory_built", "factory_demolished", "belt_placed", "belt_removed",
	"belt_rejected", "radial_closed", "build_rejected", "click_rejected", "panel_opened",
	"workers_changed", "material_selected", "belt_filter_set", "run_start", "run_end"];

func _solo_accion_y_ciclo(recibidos):
	return _nombres_de(recibidos).filter(func(n): return ANALITICA_ACCION.has(n));

# Primera casilla de una fila de `n` libres y de suelo normal (sin tipo), con las filas de arriba
# y de abajo también libres si `aislada` (para que nada vecino meta sinergias).
func _fila_libre(main, n, aislada = true):
	var tm = main.get_node("TileMap");
	var celdas = tm.get_used_cells(0);
	celdas.sort();
	for c in celdas:
		var ok = true;
		var borde = 1 if aislada else 0;
		for i in range(-borde, n + borde):
			for dy in ([-1, 0, 1] if aislada else [0]):
				var cc = c + Vector2i(i, dy);
				if tm.cell_types.has(cc) or not tm.canPlaceFactory(cc, main.factoryArray):
					ok = false;
					break;
			if not ok:
				break;
		if ok:
			return c;
	return null;

# Pone `cell` bajo el cursor: el cursor headless no se mueve, así que se mueve el TileMap.
func _apuntar(tm, cell):
	tm.position = tm.get_global_mouse_position() - tm.map_to_local(cell);

func _raton(boton, pulsado):
	var ev = InputEventMouseButton.new();
	ev.button_index = boton;
	ev.pressed = pulsado;
	return ev;

func _arrastrar(main, tm, desde, hasta):
	_apuntar(tm, desde);
	main._unhandled_input(_raton(MOUSE_BUTTON_LEFT, true));
	_apuntar(tm, hasta);
	main._unhandled_input(_raton(MOUSE_BUTTON_LEFT, false));

func _vaciar_bolsa(bag):
	for m in ["wood", "plank", "stone"]:
		bag.removeFromBag(m, bag.getQuantity(m));

func _liberar_main(main):
	paused = false;
	var placer = main.placer;
	var ml = main.mapLoader;
	_limpiar([main]);
	for n in [placer, ml]:
		if is_instance_valid(n) and n is Node:
			n.free();

func _test_analitica_m3(file_data):
	print("Analítica M3 — acciones del jugador: construir, demoler, cintas, radial, rechazos y panel");

	# --- (1) SECUENCIA: begin_run → construir un WoodCutter por _on_factory_chosen → demolerlo →
	# end_run("abandon"): exactamente cuatro eventos, con el mismo run_id.
	var main = _main_para_run();
	var recibidos = [];
	main.analytics.sink = func(n, p): recibidos.append([n, p]);
	main._start_game("standard");
	var celda = _fila_libre(main, 1);
	_check("el mapa tiene una casilla libre para la secuencia", celda != null);
	if celda == null:
		_liberar_main(main);
		return;
	main.gameManager.run_time = 5.0;
	main._on_factory_chosen("WoodCutter", celda);
	main.gameManager.run_time = 12.5;
	main._demolish_at_cell(celda);
	main._end_run("abandon");
	_check("secuencia: run_start, factory_built, factory_demolished, run_end y nada más",
		_nombres_de(recibidos) == ["run_start", "factory_built", "factory_demolished", "run_end"],
		str(_nombres_de(recibidos)));
	var fb = _filas_de(recibidos, "factory_built");
	var fd = _filas_de(recibidos, "factory_demolished");
	var fin = _filas_de(recibidos, "run_end");
	var b = fb[0] if fb.size() == 1 else {};
	var d = fd[0] if fd.size() == 1 else {};
	var e = fin[0] if fin.size() == 1 else {};
	_check("run_end trae built_WoodCutter 1, built_total 1 y demolished_total 1",
		e.get("built_WoodCutter") == 1 and e.get("built_total") == 1 and e.get("demolished_total") == 1, str(e));
	var ids = {};
	for r in recibidos:
		ids[r[1].get("run_id", "")] = true;
	_check("los cuatro con el mismo run_id", ids.size() == 1 and not ids.has(""), str(ids.keys()));
	_check("factory_built: factoría, casilla, tile plain, n_synergies 0 y paid_wood del recibo",
		b.get("factory") == "WoodCutter" and b.get("cx") == celda.x and b.get("cy") == celda.y
		and b.get("tile") == "plain" and b.get("n_synergies") == 0
		and b.get("paid_wood") == int(file_data["Factories"]["WoodCutter"]["cost"]["wood"])
		and typeof(b.get("paid_wood")) == TYPE_INT, str(b));
	_check("factory_demolished: casilla, age_s desde la construcción y refund_wood = floor(pagado/2)",
		d.get("factory") == "WoodCutter" and d.get("cx") == celda.x and _near(d.get("age_s", -1.0), 7.5)
		and d.get("refund_wood") == int(file_data["Factories"]["WoodCutter"]["cost"]["wood"]) / 2, str(d));
	recibidos.clear();
	main._end_run("abandon");
	_check("un segundo end_run no emite", recibidos.is_empty(), str(_nombres_de(recibidos)));
	_liberar_main(main);

	# --- (2) Radial: closed(built) una sola vez por cierre; built 1 al elegir, 0 con fondo/ESC.
	main = _main_para_run();
	recibidos = [];
	main.analytics.sink = func(n, p): recibidos.append([n, p]);
	main._start_game("standard");
	var tm = main.get_node("TileMap");
	var bag = main.get_node("Player/Bag");
	var fila = _fila_libre(main, 7, false);
	_check("el mapa tiene una fila libre de 7 casillas", fila != null);
	if fila == null:
		_liberar_main(main);
		return;
	recibidos.clear();
	main._show_radial_menu(fila);
	var radial = main.get_node_or_null("RadialMenu");
	var n_opc = _opciones_del_radial(main).size();
	if radial != null:
		radial._on_factory_pressed("WoodCutter");
		radial._on_bg_input(_raton(MOUSE_BUTTON_LEFT, true));
	var rc = _filas_de(recibidos, "radial_closed");
	_check("elegir en el radial: factory_built y después UN radial_closed con built 1",
		_solo_accion_y_ciclo(recibidos) == ["factory_built", "radial_closed"] and rc.size() == 1
		and rc[0]["built"] == 1 and rc[0]["cx"] == fila.x and rc[0]["cy"] == fila.y, str(recibidos));
	_check("radial_closed lleva n_options (%d) y n_affordable (<= n_options)" % n_opc,
		rc.size() == 1 and rc[0]["n_options"] == n_opc and n_opc > 0
		and rc[0]["n_affordable"] >= 1 and rc[0]["n_affordable"] <= n_opc, str(rc));
	recibidos.clear();
	var sin_dinero = fila + Vector2i(6, 0);
	var guardado = {};
	for m in ["wood", "plank", "stone"]:
		guardado[m] = bag.getQuantity(m);
	_vaciar_bolsa(bag);
	main._show_radial_menu(sin_dinero);
	radial = main.get_child(main.get_child_count() - 1);
	var esc = InputEventKey.new();
	esc.keycode = KEY_ESCAPE;
	esc.pressed = true;
	if radial.has_signal("closed"):
		radial._unhandled_input(esc);
		radial._on_bg_input(_raton(MOUSE_BUTTON_LEFT, true));
		radial._unhandled_input(esc);
	rc = _filas_de(recibidos, "radial_closed");
	_check("ESC y luego click de fondo en el mismo frame: UN radial_closed con built 0",
		_solo_accion_y_ciclo(recibidos) == ["radial_closed"] and rc.size() == 1 and rc[0]["built"] == 0,
		str(recibidos));
	_check("y sin dinero n_affordable 0", rc.size() == 1 and rc[0]["n_affordable"] == 0, str(rc));

	# --- (3) build_rejected: casilla ocupada (cell_invalid) y sin dinero (no_money).
	recibidos.clear();
	main._on_factory_chosen("WoodCutter", sin_dinero);
	main._on_factory_chosen("WoodCutter", fila);
	var br = _filas_de(recibidos, "build_rejected");
	_check("build_rejected: no_money sin dinero, cell_invalid sobre casilla ocupada, y nada construido",
		_solo_accion_y_ciclo(recibidos) == ["build_rejected", "build_rejected"]
		and br[0]["reason"] == "no_money" and br[1]["reason"] == "cell_invalid"
		and br[0]["factory"] == "WoodCutter", str(recibidos));
	for m in guardado:
		bag.addToBag(m, guardado[m]);

	# --- (4) Cintas por el gesto real: no_fit (factoría en medio del tramo recto), no_money (sin
	# madera, cabía) y belt_placed; y el derecho sobre la cinta, belt_removed.
	var a = fila + Vector2i(1, 0);
	var z = fila + Vector2i(5, 0);
	main._on_factory_chosen("WoodCutter", fila + Vector2i(3, 0));
	recibidos.clear();
	_arrastrar(main, tm, a, z);
	main._demolish_at_cell(fila + Vector2i(3, 0));
	guardado = {};
	for m in ["wood", "plank", "stone"]:
		guardado[m] = bag.getQuantity(m);
	_vaciar_bolsa(bag);
	_arrastrar(main, tm, a, z);
	for m in guardado:
		bag.addToBag(m, guardado[m]);
	var madera_antes = bag.getQuantity("wood");
	_arrastrar(main, tm, a, z);
	var bj = _filas_de(recibidos, "belt_rejected");
	var bp = _filas_de(recibidos, "belt_placed");
	_check("arrastre que no cabe: belt_rejected no_fit con el largo del gesto (5)",
		bj.size() == 2 and bj[0]["reason"] == "no_fit" and bj[0]["cells"] == 5, str(bj));
	_check("arrastre que cabía sin madera: belt_rejected no_money", bj.size() == 2 and bj[1]["reason"] == "no_money",
		str(bj));
	_check("arrastre tendido: belt_placed con extremos, 5 celdas y paid_wood = lo cobrado",
		bp.size() == 1 and bp[0]["x0"] == a.x and bp[0]["y0"] == a.y and bp[0]["x1"] == z.x
		and bp[0]["y1"] == z.y and bp[0]["cells"] == 5
		and bp[0]["paid_wood"] == int(round(madera_antes - bag.getQuantity("wood"))) and bp[0]["paid_wood"] > 0,
		"%s gastado %s" % [str(bp), str(madera_antes - bag.getQuantity("wood"))]);
	recibidos.clear();
	_apuntar(tm, a + Vector2i(1, 0));
	main._unhandled_input(_raton(MOUSE_BUTTON_RIGHT, true));
	var bo = _filas_de(recibidos, "belt_removed");
	_check("derecho sobre la cinta: belt_removed con su casilla",
		_solo_accion_y_ciclo(recibidos) == ["belt_removed"] and bo[0]["cx"] == a.x + 1 and bo[0]["cy"] == a.y,
		str(recibidos));

	# --- (5) click_rejected: casilla sin sitio (con tipo), saturada, y fuera del mapa no cuenta.
	var bloqueada = null;
	for c in tm.cell_types:
		if not tm.canPlaceAnyFactory(c, main.factoryArray) and main._get_factory_at_cell(c) == null \
				and not main.beltNetwork.belts.has(c):
			bloqueada = c;
			break;
	recibidos.clear();
	if bloqueada != null:
		_apuntar(tm, bloqueada);
		main._unhandled_input(_raton(MOUSE_BUTTON_LEFT, true));
		main._unhandled_input(_raton(MOUSE_BUTTON_LEFT, false));
	if bloqueada != null:
		main.pollutionManager.pollution_per_cell[bloqueada] = float(main.pollutionManager.cell_block_pollution) * 2.0;
		main._unhandled_input(_raton(MOUSE_BUTTON_LEFT, true));
		main._unhandled_input(_raton(MOUSE_BUTTON_LEFT, false));
		main.pollutionManager.pollution_per_cell.erase(bloqueada);
	_apuntar(tm, Vector2i(-500, -500));
	main._unhandled_input(_raton(MOUSE_BUTTON_LEFT, true));
	main._unhandled_input(_raton(MOUSE_BUTTON_LEFT, false));
	var ck = _filas_de(recibidos, "click_rejected");
	_check("el mapa tiene una casilla con tipo donde no cabe nada (%s)" % str(bloqueada), bloqueada != null);
	_check("click sobre ella: click_rejected con su tile y saturated 0; saturada, saturated 1",
		ck.size() == 2 and bloqueada != null and ck[0]["cx"] == bloqueada.x and ck[0]["cy"] == bloqueada.y
		and ck[0]["tile"] == tm.cell_types[bloqueada] and ck[0]["saturated"] == 0
		and ck[1]["saturated"] == 1 and ck[1]["tile"] == ck[0]["tile"], str(ck));
	_check("click fuera del mapa: no hay casilla y no se manda (%d filas)" % ck.size(), ck.size() == 2);
	var r_abierto = main.get_node_or_null("RadialMenu");
	if r_abierto != null:
		main.remove_child(r_abierto);
		r_abierto.free();
	tm.position = Vector2.ZERO;
	_liberar_main(main);

	# --- (6) El panel: panel_opened con la razón que enseña y las tres señales SOLO si se aplican.
	main = _main_para_run();
	recibidos = [];
	main.analytics.sink = func(n, p): recibidos.append([n, p]);
	main._start_game("standard");
	bag = main.get_node("Player/Bag");
	fila = _fila_libre(main, 5, false);
	main._on_factory_chosen("Foundry", fila);
	var fundicion = main._get_factory_at_cell(fila);
	_check("se construye una Foundry para probar el panel", fundicion != null);
	if fundicion == null:
		_liberar_main(main);
		return;
	main.beltNetwork.place_drag(fila, fila + Vector2i(3, 0), main.factoryArray);
	bag.addWorkers(2);
	recibidos.clear();
	main._show_factory_panel(fundicion);
	var panel = main.get_node("FactoryPanel");
	var po = _filas_de(recibidos, "panel_opened");
	_check("panel_opened: factoría, casilla y blocked none (build() ya le dio su worker)",
		po.size() == 1 and po[0]["factory"] == "Foundry" and po[0]["cx"] == fila.x and po[0]["cy"] == fila.y
		and po[0]["blocked"] == "none" and fundicion.workers_assigned == 1, str(po));
	recibidos.clear();
	panel.unassign_one();
	panel.unassign_one();
	panel.assign_one();
	panel.assign_one();
	var wc = _filas_de(recibidos, "workers_changed");
	_check("workers_changed solo en los dos movimientos aplicados: −1 (assigned 0) y +1 (assigned 1)",
		_solo_accion_y_ciclo(recibidos) == ["workers_changed", "workers_changed"]
		and wc[0]["delta"] == -1 and wc[0]["assigned"] == 0 and wc[1]["delta"] == 1 and wc[1]["assigned"] == 1
		and wc[0]["factory"] == "Foundry", str(recibidos));
	panel.unassign_one();
	# El panel viejo se libera ya: en el juego su queue_free() llega al final del frame, y aquí
	# seguiría conectado a la red fuera del árbol durante el resto de la prueba.
	main.remove_child(panel);
	panel.free();
	recibidos.clear();
	main._show_factory_panel(fundicion);
	panel = main.get_node("FactoryPanel");
	po = _filas_de(recibidos, "panel_opened");
	_check("sin su worker, panel_opened dice blocked workers (la razón que enseña blockedReason)",
		po.size() == 1 and po[0]["blocked"] == "workers", str(po));
	recibidos.clear();
	var idx_glass = fundicion.production_candidates.find("glass");
	panel._on_material_selected(idx_glass);
	panel._on_material_selected(idx_glass);
	panel._on_material_selected(99);
	var ms = _filas_de(recibidos, "material_selected");
	_check("material_selected solo al cambiar de verdad (glass), no al repetir ni fuera de rango",
		_solo_accion_y_ciclo(recibidos) == ["material_selected"] and ms[0]["material"] == "glass"
		and ms[0]["factory"] == "Foundry", str(recibidos));
	recibidos.clear();
	var celda_cinta = panel._belt_cell;
	panel._on_belt_filter_selected(1);
	var filtro = panel._belt_option.get_item_text(1) if panel._belt_option != null else "";
	panel._on_belt_filter_selected(1);
	panel._on_belt_filter_selected(0);
	var bf = _filas_de(recibidos, "belt_filter_set");
	_check("belt_filter_set solo al cambiar el filtro: %s y luego any (repetir no emite)" % filtro,
		celda_cinta != null and _solo_accion_y_ciclo(recibidos) == ["belt_filter_set", "belt_filter_set"]
		and bf[0]["material"] == filtro and bf[1]["material"] == "any"
		and bf[0]["cx"] == celda_cinta.x and bf[0]["cy"] == celda_cinta.y, str(recibidos));
	main._end_run("abandon");
	recibidos.clear();
	panel.assign_one();
	_check("sin run viva las señales del panel no mandan nada", recibidos.is_empty(), str(recibidos));
	_liberar_main(main);

	# --- (7) Enmienda de M2: checkpoint_reached.rate se omite con el −1.0 centinela.
	main = _main_para_run();
	recibidos = [];
	main.analytics.sink = func(n, p): recibidos.append([n, p]);
	main._start_game("standard");
	var gm = main.gameManager;
	for caso in [[-1.0, false], [0.0, true], [0.4, true]]:
		recibidos.clear();
		gm.current_checkpoint_index += 1;
		gm.last_segment_rate = caso[0];
		gm.checkpoint_reached.emit(["speed_woodcutter", "more_workers", "extra_wood"], {}, []);
		var cr = _filas_de(recibidos, "checkpoint_reached");
		_check("checkpoint_reached con last_segment_rate %s %s rate" % [str(caso[0]), "lleva" if caso[1] else "sale sin"],
			cr.size() == 1 and cr[0].has("rate") == caso[1]
			and (not caso[1] or _near(cr[0]["rate"], caso[0])), str(cr));
		var pantalla = main.get_node_or_null("UpgradeScreen");
		if pantalla != null:
			pantalla._on_upgrade_chosen("more_workers");
			main.remove_child(pantalla);
			pantalla.free();
		paused = false;
	_liberar_main(main);

# ---------- Analítica M4: la muestra de estado ----------

# `run_sample` cada 10 s de `gameManager.run_time`, con el `sink` falso. El `run_time` se mueve a
# mano y se llama a `analytics._process()` como lo haría el árbol: headless no pasan frames
# mientras corre la suite.
func _muestras(recibidos):
	return _filas_de(recibidos, "run_sample");

# Avanza el `run_time` de `gm` hasta `hasta` en pasos de `paso` (asignado, no acumulado, para que
# 600 pasos de 1/60 den 10.0 exacto) y deja a `analytics` muestrear en cada uno.
func _correr_run(main, desde, hasta, paso):
	var i = int(round(desde / paso));
	var fin = int(round(hasta / paso));
	while i < fin:
		i += 1;
		main.gameManager.run_time = i * paso;
		main.analytics._process(paso);

func _test_analitica_m4(file_data):
	print("Analítica M4 — run_sample cada 10 s de run_time, congelado con las cartas y sin run viva");

	# --- (1) 35 s de run en frames de 0,5 s: tres muestras con run_t 10/20/30.
	var main = _main_para_run();
	var recibidos = [];
	main.analytics.sink = func(n, p): recibidos.append([n, p]);
	main._start_game("standard");
	var a = main.analytics;
	_check("Analytics va en PROCESS_MODE_INHERIT (con el árbol pausado no muestrea)",
		a.process_mode == Node.PROCESS_MODE_INHERIT);
	paused = true;
	var pausado = a.can_process();
	paused = false;
	_check("y con el árbol pausado can_process() es false", not pausado);
	_correr_run(main, 0.0, 35.0, 0.5);
	var ms = _muestras(recibidos);
	var ts = ms.map(func(m): return m["run_t"]);
	_check("35 s de run dan 3 run_sample con run_t 10/20/30", ts.size() == 3
		and _near(ts[0], 10.0) and _near(ts[1], 20.0) and _near(ts[2], 30.0), str(ts));
	_check("todas con el run_id de la run", ms.all(func(m): return m["run_id"] == a.run_id()));

	# --- (2) Las props: todas las del catálogo, y las familias en enteros.
	var m0 = ms[0] if ms.size() > 0 else {};
	var faltan = [];
	for p in a.events["run_sample"]["props"]:
		if not m0.has(p):
			faltan.append(p);
	_check("una muestra de una run de verdad lleva todas las props del catálogo", faltan.is_empty(), str(faltan));
	var no_int = [];
	for p in m0:
		if (p.begins_with("stock_") or p.begins_with("avail_") or p.begins_with("n_")) \
				and typeof(m0[p]) != TYPE_INT:
			no_int.append(p);
	_check("stock_*/avail_*/n_* traen enteros", not m0.is_empty() and no_int.is_empty(), str(no_int));
	var bag = main.get_node("Player").get_node("Bag");
	_check("stock_wood/avail_wood/workers_total son los de la Bag",
		m0.get("stock_wood", -1) == int(bag.getQuantity("wood"))
		and m0.get("avail_wood", -1) == int(bag.getAvailable("wood"))
		and m0.get("workers_total", -1) == int(bag.workers_total), str(m0));
	_check("n_Storage cuenta el almacén inicial del mapa", m0.get("n_Storage", 0) >= 1, str(m0.get("n_Storage")));
	var suma_n = 0;
	for f in a.enums["factory"]:
		suma_n += m0.get("n_" + f, 0);
	_check("la suma de n_* es el tamaño del factoryArray vivo", suma_n == main.factoryArray.size(),
		"%d vs %d" % [suma_n, main.factoryArray.size()]);
	recibidos.clear();
	var construida = a.build_sample();
	_check("build_sample() de una run de verdad pasa el validador del catálogo",
		a.track("run_sample", construida) and _nombres_de(recibidos) == ["run_sample"], str(construida));

	# --- (3) El array de factorías es el vivo: construir se ve en la siguiente muestra.
	var celda = _fila_libre(main, 1);
	var antes = a.build_sample().get("n_WoodCutter", -1);
	if celda != null:
		main._on_factory_chosen("WoodCutter", celda);
	_check("construir un WoodCutter sube n_WoodCutter en uno (analytics ve el factoryArray vivo)",
		celda != null and a.build_sample().get("n_WoodCutter", -1) == antes + 1);

	# --- (4) idle_s: 10 en la primera muestra sin acciones; a cero tras un evento de acción.
	_check("idle_s de la 1.ª muestra = 10 (ninguna acción desde el run_start)",
		ms.size() > 0 and _near(ms[0]["idle_s"], 10.0), str(ms[0].get("idle_s") if ms.size() > 0 else null));
	recibidos.clear();
	main.gameManager.run_time = 35.0;
	a.track("click_rejected", {});
	_correr_run(main, 35.0, 40.0, 0.5);
	ms = _muestras(recibidos);
	_check("tras un evento de acción a los 35 s, la muestra de los 40 s trae idle_s = 5",
		ms.size() == 1 and _near(ms[0]["run_t"], 40.0) and _near(ms[0]["idle_s"], 5.0), str(ms));

	# --- (5) Cartas: con `active = false` el run_time no avanza por el camino real y no sale nada.
	recibidos.clear();
	var gm = main.gameManager;
	gm.active = false;
	for i in range(120):
		gm._process(0.5);
		a._process(0.5);
	_check("con gameManager.active = false (cartas) 60 s de frames no dan ninguna muestra",
		_muestras(recibidos).is_empty() and _near(gm.run_time, 40.0), "run_time %s" % str(gm.run_time));
	gm.active = true;
	for i in range(20):
		gm._process(0.5);
		a._process(0.5);
	ms = _muestras(recibidos);
	_check("al cerrar las cartas sigue la rejilla: la siguiente sale a los 50 s de run_time",
		ms.size() == 1 and _near(ms[0]["run_t"], 50.0), str(ms.map(func(m): return m["run_t"])));

	# --- (6) Un frame largo que salta dos umbrales da UNA muestra, y la rejilla sigue en 10.
	recibidos.clear();
	gm.run_time = 75.0;
	a._process(25.0);
	gm.run_time = 80.0;
	a._process(5.0);
	ts = _muestras(recibidos).map(func(m): return m["run_t"]);
	_check("un salto de 50 a 75 s da una muestra (75) y la siguiente sale a los 80",
		ts.size() == 2 and _near(ts[0], 75.0) and _near(ts[1], 80.0), str(ts));

	# --- (7) Sin run viva, ninguna.
	main._end_run("abandon");
	recibidos.clear();
	_correr_run(main, 80.0, 120.0, 0.5);
	_check("sin run viva (tras end_run) 40 s de run_time no dan ninguna muestra", recibidos.is_empty(), str(recibidos));
	_liberar_main(main);

	# --- (8) Con el gameManager liberado (reset() sin end_run) no se toca nada ni sale muestra.
	main = _main_para_run();
	recibidos = [];
	main.analytics.sink = func(n, p): recibidos.append([n, p]);
	main._start_game("standard");
	a = main.analytics;
	gm = main.gameManager;
	gm.run_time = 30.0;
	main.remove_child(gm);
	gm.free();
	main.gameManager = null;
	recibidos.clear();
	a._process(0.5);
	_check("con el gameManager liberado y la run viva _process no muestrea", recibidos.is_empty(), str(recibidos));
	a.end_run("abandon");
	_liberar_main(main);

	# --- (9) 3 min de run a 60 fps: cuántas muestras salen y con qué separación.
	main = _main_para_run();
	recibidos = [];
	main.analytics.sink = func(n, p): recibidos.append([n, p]);
	main._start_game("standard");
	_correr_run(main, 0.0, 180.0, 1.0 / 60.0);
	ts = _muestras(recibidos).map(func(m): return m["run_t"]);
	var separadas = true;
	for i in range(ts.size()):
		var previo = ts[i - 1] if i > 0 else 0.0;
		if abs(ts[i] - previo - 10.0) > 1.0 / 60.0 + 0.0001:
			separadas = false;
	print("  (3 min a 60 fps: %d run_sample, run_t %s)" % [ts.size(), str(ts)]);
	_check("3 min de run a 60 fps dan 18 run_sample (10…180) separadas 10 s ±1 frame",
		ts.size() == 18 and separadas, str(ts));
	main._end_run("abandon");
	_liberar_main(main);

# ---------- Legibilidad M0: el rendimiento parcial y `segment_rate` ----------

# `gameManager.segmentLiveRate()` (el parcial del tramo, sin calentamiento) y el evento que lo graba
# cada 1 s de `run_time`, con el `sink` falso de las pruebas de Analítica. Es la instrumentación
# con la que se decide en M0b si el porcentaje en vivo es honesto.
func _test_legibilidad_m0(file_data):
	print("Legibilidad M0 — segmentLiveRate() y segment_rate cada 1 s de run_time");

	# --- (1) segmentLiveRate() a pie, con un gameManager suelto: -1.0 sin integral, lo producido
	# en el tramo sobre la integral del techo con ella, y el mismo cociente que deja el cierre.
	var gm = _new_gm(file_data, [
		{ "material": "plank", "quantity": 40, "label": "Uno" },
		{ "material": "plank", "quantity": 999, "label": "Dos" },
	]);
	var bag = _new_bag();
	bag.initialize(file_data);
	var linea = _new_productora("WoodProcessing", "plank", 2);    # 0,5 plank/s
	gm.setFactories([linea]);
	_check("sin integral (el tramo no ha corrido) segmentLiveRate() vale -1.0",
		_near(gm.segmentLiveRate(bag), -1.0), str(gm.segmentLiveRate(bag)));
	for i in range(20):
		gm.run_time = float(i + 1);
		gm.update(bag);
	bag.addToBag("plank", 5);
	_check("5 plank sobre un techo de 0,5/s durante 20 s: segmentLiveRate() = 5 / 10 = 0,5",
		_near(gm.segmentLiveRate(bag), 0.5), str(gm.segmentLiveRate(bag)));
	_check("sin bolsa y sin Player del que sacarla, -1.0", _near(gm.segmentLiveRate(), -1.0));
	# Justo antes de cerrar: se completa el objetivo sin mover `run_time`, así que la muestra del
	# update que cierra no añade integral y lo que se lee aquí es lo que juzga el cierre.
	bag.addToBag("plank", 35);
	var antes = gm.segmentLiveRate(bag);
	var cerrado = [];
	gm.checkpoint_reached.connect(func(_o, _r, _g): cerrado.append(gm.last_segment_rate));
	gm.update(bag);
	_check("segmentLiveRate() justo antes de cerrar vale el last_segment_rate que deja el cierre (4,0)",
		cerrado.size() == 1 and _near(antes, cerrado[0]) and _near(antes, 4.0),
		"antes %s, cierre %s" % [str(antes), str(cerrado)]);
	_check("y al arrancar el tramo siguiente vuelve a -1.0 (la integral se ha puesto a cero)",
		_near(gm.segmentLiveRate(bag), -1.0), str(gm.segmentLiveRate(bag)));
	gm.production_done = true;
	gm.segment_capacity_area = 10.0;
	_check("fuera de la fase de producción, -1.0 aunque haya integral",
		_near(gm.segmentLiveRate(bag), -1.0));
	_limpiar([gm, bag, linea]);

	# --- (2) segment_rate por el camino de Main: sin integral no sale nada.
	var main = _main_para_run();
	var recibidos = [];
	main.analytics.sink = func(n, p): recibidos.append([n, p]);
	main._start_game("standard");
	var a = main.analytics;
	gm = main.gameManager;
	bag = main.get_node("Player").get_node("Bag");
	gm.segment_capacity_area = 0.0;
	_correr_run(main, 0.0, 3.0, 0.5);
	_check("con rate -1.0 (sin integral) 3 s de run no dan ningún segment_rate",
		_filas_de(recibidos, "segment_rate").is_empty(), str(_nombres_de(recibidos)));

	# --- (3) Cadencia: con integral, uno por segundo de run_time en la rejilla 1, 2, 3…
	gm.segment_capacity_area = 10.0;
	recibidos.clear();
	_correr_run(main, 3.0, 10.0, 0.25);
	var sr = _filas_de(recibidos, "segment_rate");
	var ts = sr.map(func(f): return f["run_t"]);
	_check("de 3 a 10 s en frames de 0,25 s salen 7 segment_rate con run_t 4…10",
		ts.size() == 7 and _near(ts[0], 4.0) and _near(ts[6], 10.0), str(ts));
	var bien = sr.size() > 0;
	for f in sr:
		bien = bien and f["checkpoint"] == 1 and typeof(f["checkpoint"]) == TYPE_INT \
			and _near(f["seg_t"], f["run_t"] - gm.last_checkpoint_time) \
			and _near(f["rate"], gm.segmentLiveRate(bag)) and f["run_id"] == a.run_id();
	_check("cada uno trae checkpoint 1 (int), seg_t = run_t − last_checkpoint_time y el rate del gameManager",
		bien, str(sr));
	_check("y run_sample sigue a su ritmo: uno solo, a los 10 s",
		_filas_de(recibidos, "run_sample").map(func(f): return f["run_t"]) == [10.0],
		str(_nombres_de(recibidos)));
	recibidos.clear();
	gm.run_time = 13.5;
	a._process(3.5);
	gm.run_time = 14.0;
	a._process(0.5);
	ts = _filas_de(recibidos, "segment_rate").map(func(f): return f["run_t"]);
	_check("un frame largo de 10 a 13,5 s da UNO (13,5) y la rejilla sigue: el siguiente a los 14",
		ts.size() == 2 and _near(ts[0], 13.5) and _near(ts[1], 14.0), str(ts));

	# --- (4) El checkpoint de segment_rate es el del checkpoint_reached que cierra el tramo.
	var cp = gm.checkpoints[gm.current_checkpoint_index];
	var coste = gm._checkpoint_cost(cp, bag);
	for m in coste:
		bag.addToBag(m, coste[m]);
	recibidos.clear();
	gm.run_time = 15.0;
	a._process(1.0);
	gm.update(bag, main.pollutionManager);
	var previos = _filas_de(recibidos, "segment_rate");
	var cierre = _filas_de(recibidos, "checkpoint_reached");
	_check("el último segment_rate antes del cierre lleva el checkpoint del checkpoint_reached (1)",
		previos.size() == 1 and cierre.size() == 1 and previos[0]["checkpoint"] == cierre[0]["checkpoint"]
		and cierre[0]["checkpoint"] == 1, "%s / %s" % [str(previos), str(cierre)]);
	if main._offer_ids.size() > 0 and main.get_node_or_null("UpgradeScreen") != null:
		main.get_node("UpgradeScreen")._on_upgrade_chosen(main._offer_ids[0]);
	paused = false;
	gm.segment_capacity_area = 10.0;
	recibidos.clear();
	_correr_run(main, 15.0, 18.0, 0.5);
	sr = _filas_de(recibidos, "segment_rate");
	var segundo = sr.size() >= 2;
	for f in sr:
		segundo = segundo and f["checkpoint"] == 2 and _near(f["seg_t"], f["run_t"] - 15.0);
	_check("tras elegir carta el tramo nuevo sale con checkpoint 2 y seg_t desde el cierre",
		gm.active and segundo, str(sr));

	# --- (5) En la fase de restauración, ninguno aunque quede integral.
	gm.production_done = true;
	gm.segment_capacity_area = 10.0;
	recibidos.clear();
	_correr_run(main, 18.0, 26.0, 0.5);
	_check("en la fase de restauración 8 s de run no dan ningún segment_rate",
		_filas_de(recibidos, "segment_rate").is_empty(), str(_nombres_de(recibidos)));
	main._end_run("abandon");
	_liberar_main(main);

# ---------- Legibilidad M3: el semáforo de la línea en el HUD ----------

# getLiveRate() es segmentLiveRate() con WARMUP_SECONDS de silencio al arrancar el tramo, y
# getLineState() lo traduce a «floja / ajustada / sobrada» con cortes a ±LINE_STATE_MARGIN de
# TIER2_EFFICIENCY. Todo se escribe contra las constantes y no contra 0,45 / 0,65 / 20: las tres son
# provisionales y la prueba tiene que seguir diciendo lo mismo si se mueven. El HUD ya hace cumplir
# HUD_MAX_CHARS: el semáforo es lo primero que se cae y el aviso de punto muerto no se toca nunca.
# El veredicto visual —si el estado se lee en la línea— es de quien mire el juego.
func _test_legibilidad_m3(file_data):
	print("Legibilidad M3 — getLiveRate(), getLineState() y el presupuesto del HUD");
	var gm_script = load("res://managers/gameManager.gd");
	var presupuesto = gm_script.HUD_MAX_CHARS;
	var warmup = gm_script.WARMUP_SECONDS;
	var liston = gm_script.TIER2_EFFICIENCY;
	var margen = gm_script.LINE_STATE_MARGIN;

	# --- (1) Los cortes, en sus bordes exactos y a un pelo por debajo.
	var gm = _new_gm(file_data, [
		{ "material": "plank", "quantity": 999, "label": "Checkpoint 2/5" },
	]);
	var bajo = liston - margen;
	var alto = liston + margen;
	_check("sin número (-1.0) el estado es vacío", gm._lineStateFor(-1.0) == "");
	_check("una línea parada (0,0) está floja", gm._lineStateFor(0.0) == "floja");
	_check("a un pelo por debajo de TIER2 − margen, floja", gm._lineStateFor(bajo - 0.000001) == "floja",
		gm._lineStateFor(bajo - 0.000001));
	_check("en TIER2 − margen exacto ya es ajustada", gm._lineStateFor(bajo) == "ajustada",
		gm._lineStateFor(bajo));
	_check("en TIER2 exacto, ajustada", gm._lineStateFor(liston) == "ajustada");
	_check("a un pelo por debajo de TIER2 + margen, todavía ajustada",
		gm._lineStateFor(alto - 0.000001) == "ajustada", gm._lineStateFor(alto - 0.000001));
	_check("en TIER2 + margen exacto ya es sobrada", gm._lineStateFor(alto) == "sobrada",
		gm._lineStateFor(alto));
	_check("los cortes rodean al listón del tier: floja < TIER2 <= sobrada",
		bajo < liston and liston < alto and margen > 0.0);

	# --- (2) El calentamiento: con número de sobra, callado hasta WARMUP_SECONDS de tramo.
	var bag = _new_bag();
	bag.initialize(file_data);
	var linea = _new_productora("WoodProcessing", "plank", 2);    # techo de 0,5 plank/s
	gm.setFactories([linea]);
	var paso = 1.0;
	var t = 0.0;
	while t + paso < warmup:
		t += paso;
		gm.run_time = t;
		gm.update(bag);
	bag.addToBag("plank", int(ceil(t * 0.5 * alto)) + 1);
	_check("dentro del calentamiento segmentLiveRate() ya tiene número…",
		gm.segmentLiveRate(bag) >= 0.0, str(gm.segmentLiveRate(bag)));
	_check("…pero getLiveRate() devuelve -1.0", _near(gm.getLiveRate(bag), -1.0), str(gm.getLiveRate(bag)));
	_check("y getLineState() está vacío", gm.getLineState(bag) == "", gm.getLineState(bag));
	var callado = gm.getObjectiveText(bag);
	_check("y el HUD no pinta la parte «Línea»", not ("Línea" in callado), callado);
	gm.run_time = warmup;
	gm.update(bag);
	_check("a los WARMUP_SECONDS justos getLiveRate() es el parcial del tramo",
		gm.getLiveRate(bag) >= 0.0 and _near(gm.getLiveRate(bag), gm.segmentLiveRate(bag)),
		"%s vs %s" % [str(gm.getLiveRate(bag)), str(gm.segmentLiveRate(bag))]);
	_check("y el estado aparece", gm.getLineState(bag) != "", gm.getLineState(bag));

	# --- (3) Alimentar mejor o peor la cadena mueve el semáforo (relaciones, no cantidades):
	# se fija el stock del tramo para caer en cada franja sobre la integral que haya.
	# La integral se lee en cada llamada (no se captura): sigue creciendo mientras corre el tramo.
	var fijar = func(ratio):
		var falta = int(ceil(ratio * gm.segment_capacity_area)) - bag.getQuantity("plank");
		if falta > 0:
			bag.addToBag("plank", falta);
		elif falta < 0:
			bag.removeFromBag("plank", -falta);
	bag.removeFromBag("plank", bag.getQuantity("plank"));
	fijar.call(bajo * 0.5);
	var estado_flojo = gm.getLineState(bag);
	fijar.call(liston);
	var estado_ajustado = gm.getLineState(bag);
	fijar.call(alto * 1.5);
	var estado_sobrado = gm.getLineState(bag);
	_check("con poco stock en el tramo la línea está floja", estado_flojo == "floja", estado_flojo);
	_check("con el stock del listón, ajustada", estado_ajustado == "ajustada", estado_ajustado);
	_check("y al alimentar mejor la cadena pasa a sobrada", estado_sobrado == "sobrada", estado_sobrado);
	var t_parado = gm.run_time;
	while gm.run_time < t_parado + warmup * 4.0:
		gm.run_time += paso;
		gm.update(bag);
	_check("y si la cadena deja de producir, el techo sigue contando y vuelve a caer",
		gm.getLineState(bag) != "sobrada", "%s (rate %s)" % [gm.getLineState(bag), str(gm.getLiveRate(bag))]);

	# --- (4) El HUD de producción con el semáforo, y la restauración sin él.
	fijar.call(liston);
	var pm = _new_pm();
	pm.addPollution(22607.0, Vector2i(5, 5));
	var produciendo = gm.getObjectiveText(bag, pm);
	_check("en producción el HUD dice `…plank   ·   Línea: ajustada` antes de la contaminación",
		("plank   ·   Línea: ajustada  |  Contaminación: " in produciendo), produciendo);
	_check("una sola línea y dentro de HUD_MAX_CHARS",
		produciendo.length() <= presupuesto and not ("\n" in produciendo),
		"%d de %d: %s" % [produciendo.length(), presupuesto, produciendo]);
	gm.production_done = true;
	var restaurando = gm.getObjectiveText(bag, pm);
	_check("en restauración no hay tramo y no hay «Línea»", not ("Línea" in restaurando)
		and gm.getLineState(bag) == "", restaurando);
	_check("y cabe", restaurando.length() <= presupuesto, "%d de %d" % [restaurando.length(), presupuesto]);
	_limpiar([gm, bag, linea, pm]);

	# --- (5) Punto muerto + rendimiento, en el checkpoint final de la curva real: la línea del
	# colapso ya iba a ~151 de 155, así que el semáforo es lo que se cae y el aviso queda entero.
	var centro = Vector2i(5, 5);
	var pm2 = _new_pm();
	var esc = _escenario_muerto(file_data, centro, pm2);
	esc["pm"] = pm2;
	var gm2 = esc["gm"];
	var bag2 = esc["bag"];
	gm2.checkpoints = file_data["Checkpoints"];
	gm2.current_checkpoint_index = gm2.checkpoints.size() - 1;
	var ultimo = gm2.checkpoints[gm2.current_checkpoint_index];
	bag2.addToBag(ultimo["material"], int(ultimo["quantity"]) - 1);
	for material in ultimo.get("maintenance", {}):
		bag2.addToBag(material, int(ultimo["maintenance"][material]) - 1);
	pm2.addPollution(22607.0, centro);
	var t0 = warmup + 10.0;
	gm2.run_time = t0;
	gm2.update(bag2, pm2);
	gm2.run_time = t0 + 1.0 / 60.0;
	gm2.update(bag2, pm2);
	# Sin factorías el techo es 0 y no hay integral: se le da una a mano para que haya estado.
	gm2.segment_capacity_area = float(int(ultimo["quantity"]));
	var estado = gm2.getLineState(bag2);
	var colapso = gm2.getObjectiveText(bag2, pm2);
	_check("con la ventana abierta y rendimiento que enseñar (%s)" % estado,
		estado != "" and gm2.deadlock_timer > 0.0, estado);
	_check("el aviso de colapso sigue entero y delante",
		colapso.begins_with(gm2._deadlockText()) and ("no queda dónde construir" in colapso), colapso);
	_check("el semáforo DESAPARECE en vez de desbordar", not ("Línea" in colapso), colapso);
	_check("y la línea cabe", colapso.length() <= presupuesto,
		"%d de %d: %s" % [colapso.length(), presupuesto, colapso]);
	var desbordada = gm2._deadlockText() + gm2._progressText(bag2, pm2, true,
		gm_script.LINE_STATE_TEXT % estado);
	_check("porque con él no cabía (el recorte tiene dientes)", desbordada.length() > presupuesto,
		"%d de %d" % [desbordada.length(), presupuesto]);
	_check("y lo que se cae es solo el semáforo: el resto es el texto de siempre",
		colapso == gm2._deadlockText() + gm2._progressText(bag2, pm2, true), colapso);

	# Con el aviso abierto el semáforo NO se pinta aunque quepa (decidido con David el
	# 2026-09-30): en un checkpoint de etiqueta corta cabrían los dos, y «no se produce…» junto
	# a «Línea: sobrada» se contradicen.
	gm2.current_checkpoint_index = 0;
	var corto = gm2.getObjectiveText(bag2, pm2);
	var corto_con_linea = gm2._deadlockText() + gm2._progressText(bag2, pm2, true,
		gm_script.LINE_STATE_TEXT % gm2._lineStateFor(1.0));
	_check("con el aviso y un checkpoint corto el semáforo cabría…",
		corto_con_linea.length() <= presupuesto, "%d de %d" % [corto_con_linea.length(), presupuesto]);
	_check("…y aun así no se pinta: con el aviso abierto el semáforo calla siempre",
		corto.begins_with(gm2._deadlockText()) and not ("Línea" in corto)
		and corto.length() <= presupuesto and not ("\n" in corto),
		"%d de %d: %s" % [corto.length(), presupuesto, corto]);

	# --- (6) Si ni sin el semáforo cabe, se recorta el progreso y nunca el aviso.
	gm2.checkpoints = [{ "material": "plank", "quantity": 999, "label": "Etiqueta ".repeat(20) }];
	gm2.current_checkpoint_index = 0;
	var larga = gm2.getObjectiveText(bag2, pm2);
	_check("una etiqueta imposible se recorta con «…» a HUD_MAX_CHARS justos",
		larga.length() == presupuesto and larga.ends_with("…"), "%d: %s" % [larga.length(), larga]);
	_check("y el aviso de colapso llega entero", larga.begins_with(gm2._deadlockText()), larga);
	_limpiar([esc["tm"], gm2, bag2, pm2]);

# ---------- Consentimiento M1 (Plan «Builds Públicas con Consentimiento») ----------

# Busca un botón por su texto en todo el subárbol: lo que el jugador ve es el texto, no la variable.
func _boton_con_texto(nodo, texto):
	for hijo in nodo.get_children():
		if hijo is Button and hijo.text == texto:
			return hijo;
		var dentro = _boton_con_texto(hijo, texto);
		if dentro != null:
			return dentro;
	return null;

# La pantalla solo emite la decisión —quien llama al SDK es Main—, así que se prueba pulsando sus
# botones sin encender Augur. El menú enseña «Privacidad» solo con Augur configurado. Y sin
# `AUGUR_KEY` `_configure_augur()` no configura nada ni deja a Main creyendo que sí.
func _test_consentimiento_m1():
	print("Consentimiento M1 — pantalla de primer arranque, «Privacidad» y _configure_augur() sin clave");
	var augur = root.get_node_or_null("Augur");
	var screen_script = load("res://ui/consentScreen.gd");

	# --- (1) first_run: cada botón emite su decisión, una vez, y la pantalla se cierra.
	for caso in [["Aceptar", true], ["No, gracias", false]]:
		var screen = screen_script.new();
		screen.initialize(screen_script.MODE_FIRST_RUN);
		var recibidas = [];
		screen.decided.connect(func(g): recibidas.append(g));
		var boton = _boton_con_texto(screen, caso[0]);
		_check("first_run tiene el botón «%s»" % caso[0], boton != null);
		if boton == null:
			screen.free();
			continue;
		boton.pressed.emit();
		_check("«%s» emite decided(%s) una sola vez" % [caso[0], str(caso[1])],
			recibidas == [caso[1]], str(recibidas));
		_check("y la pantalla se cierra al decidir", screen.is_queued_for_deletion());
		_check("first_run no tiene «Volver»: hay que elegir", _boton_con_texto(screen, "Volver") == null);
	_check("la pantalla no ha tocado Augur (sigue sin configurar ni decisión)",
		augur != null and not augur._configured and not augur.has_consent_decision());

	# --- (2) Los dos botones pesan lo mismo: nada de patrón oscuro.
	var igual = screen_script.new();
	igual.initialize(screen_script.MODE_FIRST_RUN);
	_check("«Aceptar» y «No, gracias» con el mismo tamaño mínimo y la misma fuente",
		igual.accept_button.custom_minimum_size == igual.decline_button.custom_minimum_size
		and igual.accept_button.get_theme_font_size("font_size") == igual.decline_button.get_theme_font_size("font_size"));
	_check("la pantalla va por encima del menú (layer 25 > 20) y no se congela con pausa",
		igual.layer == 25 and igual.process_mode == Node.PROCESS_MODE_ALWAYS);
	igual.free();

	# --- (3) change: «Volver» sale sin decidir.
	var cambio = screen_script.new();
	cambio.initialize(screen_script.MODE_CHANGE, true);
	var decisiones = [];
	var cerrada = [false];
	cambio.decided.connect(func(g): decisiones.append(g));
	cambio.closed.connect(func(): cerrada[0] = true);
	var volver = _boton_con_texto(cambio, "Volver");
	_check("change tiene «Volver»", volver != null);
	if volver != null:
		volver.pressed.emit();
		_check("«Volver» cierra sin emitir decided", cerrada[0] and decisiones.is_empty(), str(decisiones));
	else:
		cambio.free();

	# --- (4) mainMenu: «Privacidad» solo con Augur configurado.
	var menu_script = load("res://ui/mainMenu.gd");
	var sin = menu_script.new();
	sin.initialize(null, false);
	_check("mainMenu con augur_enabled = false no tiene «Privacidad»",
		_boton_con_texto(sin, "Privacidad") == null and sin.privacy_button == null);
	var con = menu_script.new();
	con.initialize(null, true);
	var privacidad = _boton_con_texto(con, "Privacidad");
	_check("mainMenu con augur_enabled = true tiene «Privacidad»", privacidad != null);
	if privacidad != null:
		var avisos = [0];
		con.privacy_pressed.connect(func(): avisos[0] += 1);
		privacidad.pressed.emit();
		_check("«Privacidad» emite privacy_pressed y el menú sigue vivo",
			avisos[0] == 1 and not con.is_queued_for_deletion(), str(avisos[0]));
		# Justo debajo de JUGAR: el siguiente hermano en la columna.
		var jugar = _boton_con_texto(con, "JUGAR");
		_check("«Privacidad» va justo bajo «JUGAR»",
			jugar != null and jugar.get_parent() == privacidad.get_parent()
			and privacidad.get_index() == jugar.get_index() + 1);
	_limpiar([sin, con]);

	# --- (5) _configure_augur() sin AUGUR_KEY y fuera de template: nada.
	if OS.get_environment("AUGUR_KEY") == "" and not OS.has_feature("template"):
		var main = load("res://Main.gd").new();
		main._configure_augur();
		_check("_configure_augur() sin AUGUR_KEY no configura Augur ni enciende _augur_enabled",
			not main._augur_enabled and augur != null and not augur._configured);
		main.free();
	else:
		_check("_configure_augur() sin AUGUR_KEY: la suite corre sin clave", false,
			"lánzala con `env -u AUGUR_KEY`");

	# --- (6) M2: de dónde sale la clave. Fuera de template un `augur_release.cfg` presente se
	# IGNORA (desde el editor nunca se manda a prod); en template se lee y el entorno no cuenta.
	# El `.cfg` de prueba va a `user://` con otro nombre —no a `res://`, que es el repo, ni a
	# `user://augur/`, que la suite promete no tocar— y se borra al acabar.
	var cfg_path = "user://test_augur_release.cfg";
	var cfg = ConfigFile.new();
	cfg.set_value("augur", "write_key", "clave-de-prueba");
	cfg.set_value("augur", "endpoint", "https://prueba.invalid");
	cfg.save(cfg_path);
	var m2 = load("res://Main.gd").new();
	var fuera = m2._augur_settings(false, cfg_path);
	_check("fuera de template el .cfg presente se ignora y manda el entorno",
		fuera["key"] == OS.get_environment("AUGUR_KEY")
		and fuera["endpoint"] == OS.get_environment("AUGUR_ENDPOINT")
		and fuera["key"] != "clave-de-prueba", str(fuera["endpoint"]));
	var dentro = m2._augur_settings(true, cfg_path);
	_check("en template se leen write_key y endpoint del .cfg",
		dentro["key"] == "clave-de-prueba" and dentro["endpoint"] == "https://prueba.invalid",
		str(dentro["endpoint"]));
	var sin_cfg = m2._augur_settings(true, "user://no_existe_augur_release.cfg");
	_check("en template sin .cfg no hay clave (la build no manda nada)", sin_cfg["key"] == "");
	m2.free();
	DirAccess.remove_absolute(ProjectSettings.globalize_path(cfg_path));
	_check("el .cfg de prueba se ha borrado", not FileAccess.file_exists(cfg_path));

# Sin `AUGUR_KEY` el SDK no escribe nada: la suite entera no crea `user://augur/` (ni lo toca si
# ya existía de una sesión de humo). Va la ÚLTIMA para cubrir todo lo que corrió antes.
func _test_analitica_m1_sin_clave():
	print("Analítica M1 — sin AUGUR_KEY la suite no crea ni toca user://augur/");
	var con_clave = OS.get_environment("AUGUR_KEY") != "";
	_check("la suite corre sin AUGUR_KEY (lánzala con `env -u AUGUR_KEY`)", not con_clave);
	var augur = root.get_node_or_null("Augur");
	_check("y el autoload Augur está cargado y sigue sin configurar",
		augur != null and not augur._configured);
	var ahora = _huella_augur();
	if _augur_huella_inicial == null:
		_check("user://augur/ no existía y sigue sin existir", ahora == null, str(ahora));
	else:
		_check("user://augur/ ya existía (humo) y la suite no lo ha tocado", ahora == _augur_huella_inicial,
			"antes %s, después %s" % [str(_augur_huella_inicial), str(ahora)]);

# ---------- Legibilidad M4: el tinte de colapso ----------

# Los diamantes de la tercera pasada de draw_tints(), reconocidos por su color: el rojo del
# colapso no tiene verde y el de la contaminación sí, así que no se confunden.
func _diamantes_colapso(spy, tm_script):
	var c = tm_script.COLLAPSE_COLOR;
	var hallados = [];
	for p in spy.polys:
		var col = p["color"];
		if _near(col.r, c.r) and _near(col.g, c.g) and _near(col.b, c.b):
			hallados.append(p);
	return hallados;

# El *Hecho cuando* es visual («la pantalla se tiñe progresivamente… y se corta en seco»); aquí
# se fijan sus relaciones: 0 cerrado, monótona con run_time dentro de la ventana, 0 en el mismo
# frame en que un Reforester la cierra, nada sin gameManager, y sin escribir en el gameManager.
func _test_legibilidad_m4(file_data):
	print("Legibilidad M4 — el tinte de colapso");
	var tm_script = load("res://entities/tilemap/tileMap.gd");
	var gracia = load("res://managers/gameManager.gd").DEADLOCK_GRACE;
	var tope = tm_script.COLLAPSE_MAX_ALPHA;
	var centro = Vector2i(5, 5);

	# --- (1) Sin gameManager —como en casi toda la suite— la pasada no existe.
	var suelto = _tilemap_con_suelo(_vecindario(centro));
	var spy0 = SpyCanvas.new();
	suelto.draw_tints(spy0);
	_check("sin gameManager la intensidad del colapso es 0", suelto.collapseIntensity() == 0.0);
	_check("y draw_tints() no pinta ni un diamante de colapso",
		_diamantes_colapso(spy0, tm_script).is_empty(), "polígonos = %d" % spy0.polys.size());
	_limpiar([suelto]);

	# --- (2) Punto muerto real: sube con run_time y a la gracia entera llega al tope.
	var pm = _new_pm();
	root.add_child(pm);   # el Reforester lo localiza con find_child, así que va en el árbol
	var esc = _escenario_muerto(file_data, centro, pm);
	esc["pm"] = pm;
	var gm = esc["gm"];
	var tm = esc["tm"];
	tm.setGameManager(gm);
	_check("el overlay del tinte sigue siendo el TintOverlay a z 1 (la pasada no crea otro)",
		tm.get_node_or_null("TintOverlay") != null and tm.get_node("TintOverlay").z_index == 1);
	_check("con la ventana cerrada la intensidad es 0", gm.deadlock_timer == 0.0
		and tm.collapseIntensity() == 0.0, "timer %f" % gm.deadlock_timer);
	var spy_cerrada = SpyCanvas.new();
	tm.draw_tints(spy_cerrada);
	_check("y no se pinta la pasada, aunque el mapa esté sucio",
		_diamantes_colapso(spy_cerrada, tm_script).is_empty() and spy_cerrada.polys.size() > 0,
		"polígonos = %d" % spy_cerrada.polys.size());

	var t0 = 10.0;
	gm.run_time = t0;
	gm.update(esc["bag"], pm);
	_check("la ventana se abre (precondición)", gm.deadlock_timer > 0.0);
	_check("en el frame en que se abre la intensidad es 0: aún no ha corrido gracia",
		tm.collapseIntensity() == 0.0, "%f" % tm.collapseIntensity());

	# Solo lectura: mirar la intensidad y pintar no mueve nada del gameManager.
	gm.run_time = t0 + 1.0;
	var antes = [gm.deadlock_timer, gm.run_time, gm.last_pending_quantity, gm.last_seen_pollution,
		gm.active];
	var i_uno = tm.collapseIntensity();
	var spy_uno = SpyCanvas.new();
	tm.draw_tints(spy_uno);
	var despues = [gm.deadlock_timer, gm.run_time, gm.last_pending_quantity, gm.last_seen_pollution,
		gm.active];
	_check("collapseIntensity() y draw_tints() no escriben en el gameManager", antes == despues,
		"%s → %s" % [str(antes), str(despues)]);
	_check("la intensidad es lo corrido sobre DEADLOCK_GRACE (se lee la constante)",
		_near(i_uno, 1.0 / gracia), "%f frente a %f" % [i_uno, 1.0 / gracia]);
	var colapso_uno = _diamantes_colapso(spy_uno, tm_script);
	_check("con la ventana abierta se tiñe cada casilla del suelo",
		colapso_uno.size() == tm.get_used_cells(0).size(),
		"%d de %d" % [colapso_uno.size(), tm.get_used_cells(0).size()]);
	_check("con alpha = intensidad × COLLAPSE_MAX_ALPHA",
		not colapso_uno.is_empty() and _near(colapso_uno[0]["color"].a, i_uno * tope),
		str(colapso_uno[0]["color"]) if not colapso_uno.is_empty() else "ninguno");
	_check("y el colapso es la ÚLTIMA pasada: se lee encima de tipo y contaminación",
		not spy_uno.polys.is_empty() and _diamantes_colapso(
			{ "polys": [spy_uno.polys[spy_uno.polys.size() - 1]] }, tm_script).size() == 1);

	# Monótona frame a frame durante media gracia, sin saltos hacia atrás.
	var monotona = true;
	var previa = -1.0;
	var t = t0;
	while t < t0 + gracia * 0.5:
		t += 1.0 / 60.0;
		gm.run_time = t;
		gm.update(esc["bag"], pm);
		var i = tm.collapseIntensity();
		if i < previa:
			monotona = false;
		previa = i;
	_check("crece monótona con run_time dentro de la ventana", monotona);
	_check("a media gracia va por la mitad", _near(previa, 0.5, 0.01), "%f" % previa);

	# --- (3) El corte en seco: el Reforester rompe la condición 2 y, en el MISMO frame en que
	# la ventana se cierra, la intensidad vuelve a 0 y la pasada desaparece.
	var reforestador = _factoria_en_arbol("Reforester", centro);
	reforestador.initialize("Reforester", 1, null, null, 1, -1.0, "restoration", 0);
	esc["fabricas"].append(reforestador);
	var cerrada_en_frame = false;
	var justo_antes = 0.0;
	var al_cerrar = -1.0;
	var pasada_al_cerrar = -1;
	var limite = t + gracia;
	while t < limite:
		var i_prev = tm.collapseIntensity();
		t += 1.0 / 60.0;
		gm.run_time = t;
		reforestador.update(esc["bag"]);
		gm.update(esc["bag"], pm);
		if gm.deadlock_timer == 0.0:
			cerrada_en_frame = true;
			justo_antes = i_prev;
			al_cerrar = tm.collapseIntensity();
			var spy_corte = SpyCanvas.new();
			tm.draw_tints(spy_corte);
			pasada_al_cerrar = _diamantes_colapso(spy_corte, tm_script).size();
			break;
	_check("colocar un Reforester cierra la ventana (precondición)", cerrada_en_frame);
	_check("el frame anterior al cierre el tinte estaba puesto", justo_antes > 0.0,
		"%f" % justo_antes);
	_check("y en el frame del cierre la intensidad es 0, sin rampa de bajada", al_cerrar == 0.0,
		"%f" % al_cerrar);
	_check("y draw_tints() ya no pinta la pasada", pasada_al_cerrar == 0,
		"diamantes de colapso = %d" % pasada_al_cerrar);
	_limpiar([reforestador, tm, gm, esc["bag"], pm]);

	# --- (4) Con la gracia agotada se queda en el tope, sin pasarse.
	var pm2 = _new_pm();
	var esc2 = _escenario_muerto(file_data, centro, pm2);
	esc2["pm"] = pm2;
	var gm2 = esc2["gm"];
	esc2["tm"].setGameManager(gm2);
	gm2.run_time = t0;
	gm2.update(esc2["bag"], pm2);
	_correr_hasta(esc2, t0, t0 + gracia + 2.0);
	_check("la run se ha perdido por el punto muerto (precondición)", not gm2.active);
	_check("y el tinte queda al tope: intensidad 1, nunca más",
		esc2["tm"].collapseIntensity() == 1.0, "%f" % esc2["tm"].collapseIntensity());
	# Un gameManager ya liberado (la run anterior) no puede reventar el dibujo.
	var tm2 = esc2["tm"];
	_limpiar([gm2]);
	_check("con el gameManager liberado la intensidad vuelve a 0 sin error",
		tm2.collapseIntensity() == 0.0);
	_limpiar([tm2, esc2["bag"], pm2]);

# ---------- Clima M1: el manager y el ciclo de vida ----------

# Un weatherManager suelto (sin árbol: su reloj se avanza a mano con advance()) y APAGADO, para
# que ninguna tirada meta un evento que la prueba no ha pedido. Mapa de 16x10, el de hoy.
func _new_wm(fd):
	var wm = load("res://managers/weatherManager.gd").new();
	wm.name = "WeatherManager";
	wm.initialize(fd);
	wm.setMapSize([16, 10]);
	wm.enabled = false;
	return wm;

# M1 no aplica efectos: lo que se prueba es que los eventos nacen, viven y MUEREN a su hora, que
# la probabilidad sube con el pico, que la zona no se sale del mapa, que el plan B 1 suspende el
# clima con la ventana de punto muerto abierta, que dos eventos solapados se componen y que la
# suite (los Main que se montan en ella) no recibe eventos por sorpresa.
func _test_clima_m1(file_data):
	print("Clima M1 — el manager, el ciclo de vida y el plan B 1");
	var script_wm = load("res://managers/weatherManager.gd");
	var mapa = Rect2i(Vector2i.ZERO, Vector2i(16, 10));

	# --- (0) El catálogo está en el JSON con los cuatro tipos y sus campos base.
	var catalogo = file_data.get("WeatherEvents", {});
	var ids = catalogo.keys();
	ids.sort();
	_check("el JSON trae el catálogo `WeatherEvents` con sequía, lluvia, tormenta y viento",
		ids == ["drought", "rain", "storm", "wind"], str(ids));
	var completos = true;
	for id in ids:
		var e = catalogo[id];
		if not (e.has("name") and e.has("duration") and e.has("zone_size") and e.has("color")):
			completos = false;
	_check("y cada entrada lleva name, duration, zone_size y color", completos);

	# --- (1) Ciclo de vida: la sequía (duration 30) se retira a los 30 s, ni antes ni después.
	var wm = _new_wm(file_data);
	_check("la sequía dura 30 s en el catálogo (precondición)",
		float(catalogo["drought"]["duration"]) == 30.0);
	var nacidos = [];
	var muertos = [];
	wm.weather_started.connect(func(id, r): nacidos.append([id, r]));
	wm.weather_ended.connect(func(id): muertos.append(id));
	var zona = Rect2i(2, 2, 5, 4);
	wm.startEvent("drought", zona);
	_check("startEvent() mete el evento en `active` y emite weather_started con su id y su zona",
		wm.active.size() == 1 and nacidos == [["drought", zona]], str(nacidos));
	for i in range(29):
		wm.advance(1.0);
	_check("a los 29 s sigue vivo y le queda 1 s",
		wm.active.size() == 1 and _near(wm.active[0].remaining, 1.0) and muertos.is_empty(),
		"activos %d" % wm.active.size());
	_check("y mientras vive la consulta ya lo ve (×1,5 dentro, ×1 fuera)",
		_near(wm.getMultiplierAt(Vector2i(3, 3)), 1.5) and _near(wm.getMultiplierAt(Vector2i(10, 8)), 1.0));
	wm.advance(1.0);
	_check("a los 30 s se retira y emite weather_ended",
		wm.active.is_empty() and muertos == ["drought"], str(muertos));
	_check("y al retirarse no deja rastro: la consulta vuelve al neutro",
		_near(wm.getMultiplierAt(Vector2i(3, 3)), 1.0));

	# --- (2) Probabilidad: sube con peak_pollution y se queda en el tope 0,75.
	var pm = _new_pm();
	wm.setPollutionManager(pm);
	var probs = [];
	for pico in [0.0, 25.0, 50.0, 100.0, 150.0]:
		pm.peak_pollution = pico;
		probs.append(wm.rollChance());
	var crece = true;
	for i in range(1, probs.size()):
		if probs[i] <= probs[i - 1]:
			crece = false;
	_check("con el mapa limpio la probabilidad es BASE_CHANCE", _near(probs[0], script_wm.BASE_CHANCE),
		str(probs));
	_check("la probabilidad sube estrictamente al subir peak_pollution", crece, str(probs));
	_check("y sigue la fórmula: BASE_CHANCE + PEAK_FACTOR × pico",
		_near(probs[2], script_wm.BASE_CHANCE + script_wm.PEAK_FACTOR * 50.0), str(probs));
	pm.peak_pollution = 100000.0;
	_check("con un pico enorme se queda en el tope 0,75", _near(wm.rollChance(), 0.75),
		"%f" % wm.rollChance());
	# Y la relación, tirando de verdad: misma semilla, mismas tiradas, y el mapa sucio se come
	# más eventos que el limpio.
	var cuentas = [];
	for pico in [0.0, 150.0]:
		var wt = _new_wm(file_data);
		wt.enabled = true;
		wt.log_events = false;
		var pmt = _new_pm();
		pmt.peak_pollution = pico;
		wt.setPollutionManager(pmt);
		wt.setSeed(1234);
		var n = [0];
		wt.weather_started.connect(func(_id, _r): n[0] += 1);
		for i in range(200):
			wt.advance(script_wm.ROLL_INTERVAL);
		cuentas.append(n[0]);
		wt.free();
		pmt.free();
	_check("con la misma semilla y 200 tiradas, la run sucia recibe más eventos que la limpia",
		cuentas[1] > cuentas[0], "limpia %d, sucia %d" % cuentas);
	# Antes de ROLL_INTERVAL no se tira nunca, aunque la probabilidad esté al tope.
	var wp = _new_wm(file_data);
	wp.enabled = true;
	wp.setPollutionManager(pm);
	wp.advance(script_wm.ROLL_INTERVAL - 0.5);
	_check("antes de ROLL_INTERVAL no hay tirada", wp.active.is_empty());
	wp.free();

	# --- (3) La zona no se sale del mapa: se recorta contra 16x10.
	var esquina = wm.zoneAround("wind", Vector2i(15, 9));
	_check("el viento (6x5) centrado en la esquina (15,9) queda dentro del mapa y recortado",
		mapa.encloses(esquina) and esquina.size.x < 6 and esquina.size.y < 5, str(esquina));
	var centro = wm.zoneAround("wind", Vector2i(8, 5));
	_check("y en el centro conserva su 6x5 entero", centro.size == Vector2i(6, 5) and mapa.encloses(centro),
		str(centro));
	var fuera = wm.startEvent("storm", Rect2i(-2, -1, 4, 3));
	_check("startEvent() también recorta una zona que asoma por el borde",
		fuera != null and fuera.rect == Rect2i(0, 0, 2, 2), str(fuera.rect if fuera else null));
	_check("y una zona entera fuera del mapa no crea evento",
		wm.startEvent("storm", Rect2i(30, 30, 4, 3)) == null);
	var wz = _new_wm(file_data);
	wz.enabled = true;
	wz.log_events = false;
	var pmz = _new_pm();
	pmz.peak_pollution = 100000.0;
	wz.setPollutionManager(pmz);
	wz.setSeed(99);
	var zonas = [];
	wz.weather_started.connect(func(_id, r): zonas.append(r));
	for i in range(100):
		wz.advance(script_wm.ROLL_INTERVAL);
	var dentro = true;
	for r in zonas:
		if not (mapa.encloses(r) and r.size.x > 0 and r.size.y > 0):
			dentro = false;
	_check("las %d zonas que sortean 100 tiradas quedan todas dentro del mapa" % zonas.size(),
		dentro and zonas.size() > 0);
	wz.free();
	pmz.free();
	wm.active.clear();

	# --- (4) Plan B 1: con la ventana de punto muerto abierta no se tira, los activos no
	# descuentan y las tres consultas devuelven el neutro.
	var gm = _new_gm(file_data);
	var wb = _new_wm(file_data);
	wb.enabled = true;
	wb.log_events = false;
	wb.setPollutionManager(pm);  # pico enorme: la probabilidad está al tope
	wb.setGameManager(gm);
	wb.startEvent("drought", Rect2i(0, 0, 5, 4));
	wb.startEvent("rain", Rect2i(0, 0, 5, 4));
	wb.startEvent("storm", Rect2i(0, 0, 4, 3));
	var celda = Vector2i(1, 1);
	_check("sin ventana abierta las tres consultas ven los eventos (precondición)",
		not wb.isSuspended() and _near(wb.getMultiplierAt(celda), 1.5)
		and _near(wb.getPassiveAt(celda), -0.4) and wb.haltsProductionAt(celda));
	gm.deadlock_timer = 12.0;  # `deadlock_timer` es el run_time en que se abrió; > 0 = abierta
	var restantes = [];
	for ev in wb.active:
		restantes.append(ev.remaining);
	var reloj = wb._roll_timer;
	var nacidos_b = [0];
	wb.weather_started.connect(func(_id, _r): nacidos_b[0] += 1);
	for i in range(50):
		wb.advance(script_wm.ROLL_INTERVAL);
	var intactos = wb.active.size() == 3;
	for i in range(min(3, wb.active.size())):
		if wb.active[i].remaining != restantes[i]:
			intactos = false;
	_check("con deadlock_timer > 0 el clima está suspendido", wb.isSuspended());
	_check("y en 1000 s no se tira ni una vez", nacidos_b[0] == 0 and wb._roll_timer == reloj,
		"nacidos %d" % nacidos_b[0]);
	_check("y los activos no descuentan tiempo", intactos);
	_check("y las tres consultas devuelven el neutro (1.0, 0.0, false)",
		wb.getMultiplierAt(celda) == 1.0 and wb.getPassiveAt(celda) == 0.0
		and wb.haltsProductionAt(celda) == false);
	gm.deadlock_timer = 0.0;
	_check("al cerrarse la ventana vuelven, con el tiempo que les quedaba",
		not wb.isSuspended() and _near(wb.getMultiplierAt(celda), 1.5) and wb.haltsProductionAt(celda)
		and wb.active.size() == 3 and wb.active[0].remaining == restantes[0]);
	# Un gameManager liberado (la run anterior) no puede dejar el clima suspendido ni reventar.
	gm.free();
	_check("con el gameManager liberado no revienta y no queda suspendido", not wb.isSuspended());
	wb.free();

	# --- (5) Solape: el multiplicador multiplica y el pasivo suma; no gana el último.
	var ws = _new_wm(file_data);
	ws.startEvent("drought", Rect2i(0, 0, 5, 4));
	ws.startEvent("drought", Rect2i(2, 2, 5, 4));
	ws.startEvent("rain", Rect2i(0, 0, 5, 4));
	ws.startEvent("rain", Rect2i(3, 0, 5, 4));
	_check("dos sequías solapadas: ×1,5 × ×1,5 = ×2,25 en la intersección",
		_near(ws.getMultiplierAt(Vector2i(3, 3)), 2.25), "%f" % ws.getMultiplierAt(Vector2i(3, 3)));
	_check("y ×1,5 donde solo cubre una", _near(ws.getMultiplierAt(Vector2i(0, 0)), 1.5));
	_check("dos lluvias solapadas suman: −0,4 + −0,4 = −0,8",
		_near(ws.getPassiveAt(Vector2i(3, 1)), -0.8), "%f" % ws.getPassiveAt(Vector2i(3, 1)));
	_check("una lluvia no toca el multiplicador ni una sequía el pasivo",
		_near(ws.getMultiplierAt(Vector2i(7, 0)), 1.0) and _near(ws.getPassiveAt(Vector2i(6, 3)), -0.4));
	_check("fuera de todas las zonas, neutro", _near(ws.getMultiplierAt(Vector2i(15, 9)), 1.0)
		and _near(ws.getPassiveAt(Vector2i(15, 9)), 0.0) and not ws.haltsProductionAt(Vector2i(15, 9)));
	ws.free();
	wm.free();
	pm.free();

	# --- (6) Main: _start_game() monta el manager cableado, y la suite no recibe eventos por
	# sorpresa. Con `weather_enabled = false` antes de arrancar, el clima no tira nunca.
	var main = _main_para_run();
	main._start_game("standard");
	var wr = main.get_node_or_null("WeatherManager");
	_check("_start_game() crea el nodo WeatherManager como hijo de Main",
		wr != null and wr == main.weatherManager);
	_check("inyectado con el pollutionManager y el gameManager de ESTA run",
		wr != null and wr.pollution_manager == main.pollutionManager and wr.game_manager == main.gameManager);
	_check("y con el tamaño del mapa elegido", wr != null and wr.map_size == Vector2i(16, 10),
		str(wr.map_size if wr else null));
	_check("recién arrancada la run no hay ningún evento ni se ha tirado todavía",
		wr != null and wr.active.is_empty() and wr._roll_timer > script_wm.ROLL_INTERVAL - 1.0);
	_limpiar([main.placer, main.mapLoader, main]);
	var apagado = _main_para_run();
	apagado.weather_enabled = false;
	apagado._start_game("standard");
	var wa = apagado.weatherManager;
	wa.advance(10000.0);
	_check("con weather_enabled = false la run no recibe ni un evento en 10000 s",
		not wa.enabled and wa.active.is_empty());
	_limpiar([apagado.placer, apagado.mapLoader, apagado]);
	var fuente = FileAccess.get_file_as_string("res://Main.gd");
	_check("Main.reset() suelta el WeatherManager con el resto de nodos de la run",
		fuente.find("\"BeltNetwork\", \"WeatherManager\"]") != -1);

# ---------- Clima M2: sequía y lluvia ----------

# Productora en el árbol con un WoodCutter de verdad en cuanto al tipo, y la emisión fijada a
# mano (2.0 por tick) para que la aritmética del ×1,5 sea exacta y no dependa del JSON.
# Si el `pm` ya está en el árbol (segunda productora del mismo escenario) no se vuelve a añadir.
func _clima_productora(celda, pm):
	var f;
	if pm.get_parent() == null:
		f = _new_factory_en_arbol("WoodCutter", celda, pm);
	else:
		f = _new_factory("WoodCutter", celda);
		root.add_child(f);
	f.factory_type = "production";
	f.pollutionAmount = 2.0;
	return f;

# Lo que ensucia un tick de `f`, medido en su propia casilla.
func _clima_emision(f, pm):
	var antes = pm.pollution_per_cell.get(f.cell_position, 0.0);
	f._apply_pollution(1.0);
	return pm.pollution_per_cell.get(f.cell_position, 0.0) - antes;

# El WeatherManager como HERMANO de las factorías (hijo de root), que es donde lo busca
# factoryData._weatherMultiplier(), igual que en el juego cuelgan los dos de Main.
func _clima_wm_en_arbol(fd):
	var wm = _new_wm(fd);
	wm.log_events = false;
	root.add_child(wm);
	return wm;

# Las 160 casillas de un mapa 16x10, todas con tile de suelo y sin tipo especial: la lluvia
# tiene que llegar al suelo NORMAL, que no está en `cell_types`.
func _clima_mapa_16x10():
	var celdas = [];
	for y in range(10):
		for x in range(16):
			celdas.append(Vector2i(x, y));
	return celdas;

# Qué prueba: la sequía multiplica la emisión de una productora solo mientras dura y sin dejar
# rastro, no toca a una restauradora ni cuando está suspendida; la lluvia limpia casilla a
# casilla solo su zona (incluido el suelo normal fuera de `cell_types`), por delta; el solape
# es coherente; y sin manager o sin eventos todo da exactamente lo de antes.
func _test_clima_m2(file_data):
	print("Clima M2 — sequía y lluvia");
	var celda = Vector2i(3, 3);
	var zona = Rect2i(2, 2, 5, 4);

	# --- (0) Regresión: factoría suelta (sin padre, sin manager) — lo de siempre.
	var pm = _new_pm();
	var suelta = _new_factory("WoodCutter", celda);
	_check("una factoría sin padre no ve clima: multiplicador neutro 1.0",
		suelta._weatherMultiplier() == 1.0);
	suelta.free();
	var f = _clima_productora(celda, pm);
	var base = _clima_emision(f, pm);
	_check("sin WeatherManager en el árbol la productora ensucia lo de antes (2.0)", base == 2.0,
		"%f" % base);

	# --- (1) Sequía sobre un WoodCutter: ×1,5 mientras dura, exactamente lo de antes al acabar.
	var wm = _clima_wm_en_arbol(file_data);
	_check("con WeatherManager y sin eventos ensucia exactamente lo mismo",
		_clima_emision(f, pm) == base);
	wm.startEvent("drought", zona);
	var seca = _clima_emision(f, pm);
	_check("con sequía encima ensucia un 50 % más (3.0)", _near(seca, base * 1.5), "%f" % seca);
	var lejos = _clima_productora(Vector2i(12, 8), pm);
	_check("y otra productora fuera de la zona sigue igual",
		_clima_emision(lejos, pm) == base);
	for i in range(29):
		wm.advance(1.0);
	_check("a los 29 s la sequía sigue multiplicando", _near(_clima_emision(f, pm), base * 1.5));
	wm.advance(1.0);
	_check("a los 30 s se retira (precondición)", wm.active.is_empty());
	var despues = _clima_emision(f, pm);
	_check("y al terminar la emisión vuelve EXACTAMENTE a la de antes", despues == base,
		"%f" % despues);
	_check("sin tocar `pollutionAmount`: no se hornea nada", f.pollutionAmount == 2.0);

	# --- (2) Plan B 1: con la ventana de punto muerto abierta la sequía no multiplica.
	var gm = _new_gm(file_data);
	wm.setGameManager(gm);
	wm.startEvent("drought", zona);
	gm.deadlock_timer = 12.0;
	_check("sequía suspendida (deadlock_timer > 0): la emisión es la de antes",
		_clima_emision(f, pm) == base);
	gm.deadlock_timer = 0.0;
	_check("y al cerrarse la ventana vuelve a multiplicar", _near(_clima_emision(f, pm), base * 1.5));
	wm.setGameManager(null);
	gm.free();
	_limpiar([f, lejos, pm]);

	# --- (3) Una restauradora bajo la sequía limpia exactamente lo mismo que sin ella.
	var limpiezas = [];
	for con_sequia in [false, true]:
		var pmr = _new_pm();
		var centro = Vector2i(4, 4);
		_ensuciar_area(pmr, centro, 10.0);
		var r = _new_factory_en_arbol("Reforester", centro, pmr);
		r.factory_type = "restoration";
		r.pollutionAmount = -9.0;
		wm.active.clear();
		if con_sequia:
			wm.startEvent("drought", zona);
		var antes = pmr.total_pollution;
		r._apply_pollution(1.0);
		limpiezas.append(antes - pmr.total_pollution);
		_limpiar([r, pmr]);
	_check("una restauradora bajo sequía limpia lo mismo que sin ella (9.0)",
		limpiezas[0] == limpiezas[1] and _near(limpiezas[0], 9.0), str(limpiezas));
	wm.active.clear();

	# --- (4) Lluvia: limpia su zona casilla a casilla, suelo normal incluido, y nada más.
	var mapa = _clima_mapa_16x10();
	var sin_suelo = Vector2i(6, 5);  # dentro de la zona, pero sin tile: no es del mapa
	var con_suelo = mapa.duplicate();
	con_suelo.erase(sin_suelo);
	var tm = _tilemap_con_suelo(con_suelo);
	tm.cell_types = {};
	var pml = _new_pm();
	for c in mapa:
		pml.addPollution(10.0, c);
	tm.setWeatherManager(wm);
	wm.startEvent("rain", zona);
	var lluvia = float(file_data["WeatherEvents"]["rain"]["passive_pollution_per_tick"]);
	_check("la lluvia del catálogo limpia (pasivo negativo, precondición)", lluvia < 0.0);
	var total_antes = pml.total_pollution;
	tm.tick_passive(pml, 1.0);
	var dentro_ok = true;
	var fuera_ok = true;
	var mojadas = 0;
	for c in mapa:
		var v = pml.pollution_per_cell[c];
		if zona.has_point(c) and c != sin_suelo:
			mojadas += 1;
			if not _near(v, 10.0 + lluvia):
				dentro_ok = false;
		elif v != 10.0:
			fuera_ok = false;
	_check("un segundo de lluvia quita %.1f a cada casilla de suelo de la zona" % -lluvia, dentro_ok);
	_check("las casillas de la zona son suelo normal: ninguna está en `cell_types`",
		tm.cell_types.is_empty() and mojadas == 19, "mojadas %d" % mojadas);
	_check("fuera de la zona no toca ni una casilla", fuera_ok);
	_check("una casilla de la zona sin tile de suelo no es del mapa y no se toca",
		pml.pollution_per_cell[sin_suelo] == 10.0);
	_check("el global baja exactamente lo quitado de las casillas",
		_near(total_antes - pml.total_pollution, -lluvia * 19), "%f" % (total_antes - pml.total_pollution));
	# Por delta: 60 frames a 60 fps son un segundo, no sesenta.
	var pmd = _new_pm();
	pmd.addPollution(10.0, celda);
	for i in range(60):
		tm.tick_passive(pmd, 1.0 / 60.0);
	_check("escalada por delta: 60 frames a 60 fps == 1 s de lluvia",
		_near(pmd.pollution_per_cell[celda], 10.0 + lluvia, 0.001), "%f" % pmd.pollution_per_cell[celda]);
	# Casilla a casilla, no en área: sobre suelo limpio no hay nada que quitar, y la vecina sucia
	# FUERA de la zona no recibe nada de la casilla del borde.
	var pmc = _new_pm();
	pmc.addPollution(10.0, Vector2i(7, 3));   # justo fuera, pegada al borde derecho de la zona
	tm.tick_passive(pmc, 1.0);
	_check("casilla a casilla: la vecina sucia fuera de la zona no recibe limpieza",
		pmc.pollution_per_cell[Vector2i(7, 3)] == 10.0 and pmc.total_pollution == 10.0);
	# Suspendida por el plan B 1, la lluvia tampoco limpia.
	var gml = _new_gm(file_data);
	wm.setGameManager(gml);
	gml.deadlock_timer = 12.0;
	var pms = _new_pm();
	pms.addPollution(10.0, celda);
	tm.tick_passive(pms, 1.0);
	_check("lluvia suspendida (deadlock_timer > 0) no limpia", pms.pollution_per_cell[celda] == 10.0);
	wm.setGameManager(null);
	gml.free();

	# --- (5) Solape: dos lluvias suman una sola vez por casilla; sequía + lluvia conviven.
	wm.active.clear();
	wm.startEvent("rain", Rect2i(2, 2, 3, 3));
	wm.startEvent("rain", Rect2i(3, 3, 3, 3));
	var pmo = _new_pm();
	for c in [Vector2i(2, 2), Vector2i(3, 3), Vector2i(5, 5)]:
		pmo.addPollution(10.0, c);
	tm.tick_passive(pmo, 1.0);
	_check("dos lluvias solapadas: la intersección recibe la suma (2 × %.1f), no el doble de eso" % -lluvia,
		_near(pmo.pollution_per_cell[Vector2i(3, 3)], 10.0 + 2.0 * lluvia),
		"%f" % pmo.pollution_per_cell[Vector2i(3, 3)]);
	_check("y cada zona sola, una lluvia",
		_near(pmo.pollution_per_cell[Vector2i(2, 2)], 10.0 + lluvia)
		and _near(pmo.pollution_per_cell[Vector2i(5, 5)], 10.0 + lluvia));
	wm.active.clear();
	wm.startEvent("drought", zona);
	wm.startEvent("rain", zona);
	var pmx = _new_pm();
	var fx = _clima_productora(celda, pmx);
	var emitido = _clima_emision(fx, pmx);
	tm.tick_passive(pmx, 1.0);
	_check("sequía + lluvia en la misma casilla: ensucia ×1,5 y la lluvia le quita su parte",
		_near(emitido, 3.0) and _near(pmx.pollution_per_cell[celda], 3.0 + lluvia),
		"emitido %f, queda %f" % [emitido, pmx.pollution_per_cell[celda]]);
	_limpiar([fx, pmx]);

	# --- (6) Regresión de tick_passive: sin manager, con él liberado o sin eventos, lo de antes.
	# Con un lago en el mapa, para que el bucle de `cell_types` también trabaje.
	var lago = Vector2i(10, 5);
	tm.cell_types = { lago: "lake" };
	tm.tile_type_data = { "lake": { "passive_pollution_per_tick": -0.5 } };
	var resultados = [];
	for modo in ["sin_manager", "sin_eventos", "con_lluvia_lejos"]:
		var pmg = _new_pm();
		for c in mapa:
			pmg.addPollution(5.0, c);
		wm.active.clear();
		tm.setWeatherManager(null if modo == "sin_manager" else wm);
		if modo == "con_lluvia_lejos":
			wm.startEvent("rain", Rect2i(0, 0, 2, 2));  # lejos del lago
		tm.tick_passive(pmg, 0.5);
		resultados.append(pmg.pollution_per_cell.duplicate());
		pmg.free();
	_check("sin manager y con manager sin eventos, tick_passive da exactamente lo mismo",
		resultados[0] == resultados[1]);
	var solo_zona = true;
	for c in resultados[0]:
		if Rect2i(0, 0, 2, 2).has_point(c):
			continue;
		if resultados[2][c] != resultados[0][c]:
			solo_zona = false;
	_check("y con lluvia lejos, el lago y el resto del mapa quedan idénticos", solo_zona);
	wm.active.clear();
	wm.startEvent("rain", zona);
	tm.setWeatherManager(wm);
	_limpiar([wm]);
	var pmf = _new_pm();
	pmf.addPollution(10.0, celda);
	tm.tick_passive(pmf, 1.0);
	_check("con el WeatherManager liberado tick_passive no revienta y no llueve",
		pmf.pollution_per_cell[celda] == 10.0);
	_limpiar([tm, pml, pmd, pmc, pms, pmo, pmf]);

	# --- (7) Main: el TileMap recibe el manager de ESTA run, y una factoría hija de Main lo ve.
	var main = _main_para_run();
	main.weather_enabled = false;
	main._start_game("standard");
	var wr = main.weatherManager;
	wr.log_events = false;
	_check("_start_game() inyecta el WeatherManager en el TileMap",
		wr != null and main.get_node("TileMap").weather_manager == wr);
	var hija = _new_factory("WoodCutter", celda);
	main.add_child(hija);
	_check("una factoría hija de Main sin eventos: multiplicador 1.0", hija._weatherMultiplier() == 1.0);
	wr.startEvent("drought", zona);
	_check("y con sequía encima lo encuentra como hermano: ×1,5", _near(hija._weatherMultiplier(), 1.5));
	_limpiar([hija, main.placer, main.mapLoader, main]);

# Factoría INICIALIZADA (con `production`, `tick` e insumos) colgando de root, hermana del
# WeatherManager de _clima_wm_en_arbol(): update() la recorre entera, que es donde mira M3.
func _clima_fab(tipo, celda, recibe, material, pollution, ftype = "production", w_needed = 0):
	var f = load("res://entities/factory/factoryData.gd").new();
	var spr = AnimatedSprite2D.new();
	spr.name = "AnimatedSprite2D";
	spr.sprite_frames = SpriteFrames.new();
	f.add_child(spr);
	f.initialize(tipo, 1, recibe, material, 1, pollution, ftype, w_needed);
	f.cell_position = celda;
	root.add_child(f);
	return f;

# Qué prueba: la tormenta para a las productoras de su zona con la razón "storm" —sin emitir,
# sin ensuciar, sin comerse el insumo y sin acumular deuda—, y vuelven solas al retirarse; la
# prioridad workers -> storm -> input; las restauradoras y el almacén exentos; el plan B 1
# también la suspende; y el vocabulario (frase, color, analítica) conoce la sexta razón.
func _test_clima_m3(file_data):
	print("Clima M3 — tormenta");
	var celda = Vector2i(3, 3);
	var zona = Rect2i(2, 2, 4, 3);
	var tormenta = file_data["WeatherEvents"]["storm"];
	_check("la tormenta del catálogo para la producción y dura 15 s (precondición)",
		bool(tormenta.get("halts_production", false)) and float(tormenta["duration"]) == 15.0);

	# --- (0) Regresión: sin padre / sin manager no para nada.
	var suelta = _new_factory("WoodCutter", celda);
	_check("una factoría sin padre no ve tormenta", not suelta._haltedByWeather());
	suelta.free();
	var pm = _new_pm();
	root.add_child(pm);
	var sin_wm = _clima_fab("WoodCutter", celda, null, "wood", 2.0);
	sin_wm.update();
	_check("sin WeatherManager en el árbol la productora produce como siempre",
		sin_wm.blocked_reason == "" and _near(pm.pollution_per_cell.get(celda, 0.0), 2.0));
	_limpiar([sin_wm, pm]);

	# --- (1) Una productora con insumo bajo tormenta: parada, sin efectos, y vuelve sola.
	pm = _new_pm();
	root.add_child(pm);
	var wm = _clima_wm_en_arbol(file_data);
	var sierra = _clima_fab("WoodProcessing", celda, ["wood"], "plank", 2.0);
	sierra.receiveMaterial("wood", 5);
	var producidos = [];
	sierra.resource_produced.connect(func(m, n, _p): producidos.append([m, n]));
	wm.startEvent("storm", zona);
	sierra.update();
	_check("bajo tormenta blocked_reason == 'storm'", sierra.blocked_reason == "storm",
		"razón '%s'" % sierra.blocked_reason);
	_check("no emite resource_produced", producidos.is_empty(), str(producidos));
	_check("no ensucia su casilla", pm.pollution_per_cell.get(celda, 0.0) == 0.0 and pm.total_pollution == 0.0);
	_check("no se come el insumo", int(sierra.input_buffer["wood"]) == 5);
	_check("y no acumula production_debt: es una parada, no una rampa",
		sierra.production_debt == 0.0, "%f" % sierra.production_debt);
	var fuera = _clima_fab("WoodCutter", Vector2i(12, 8), null, "wood", 2.0);
	fuera.update();
	_check("otra productora fuera de la zona produce como siempre", fuera.blocked_reason == "");
	for i in range(14):
		wm.advance(1.0);
		sierra.update();
	_check("a los 14 s sigue parada por la tormenta", sierra.blocked_reason == "storm"
		and producidos.is_empty() and int(sierra.input_buffer["wood"]) == 5);
	wm.advance(1.0);
	_check("a los 15 s la tormenta se retira (precondición)", wm.active.is_empty());
	sierra.update();
	_check("y la factoría vuelve SOLA a producir: razón '', emite 1 plank y come 1 wood",
		sierra.blocked_reason == "" and producidos == [["plank", 1]] and int(sierra.input_buffer["wood"]) == 4,
		"razón '%s', %s" % [sierra.blocked_reason, str(producidos)]);
	_check("ensucia lo de un tick, no lo acumulado durante la parada (2.0)",
		_near(pm.pollution_per_cell.get(celda, 0.0), 2.0), "%f" % pm.pollution_per_cell.get(celda, 0.0));
	_check("sin deuda arrastrada", sierra.production_debt == 0.0);

	# --- (2) Prioridad workers -> storm -> input.
	var prio = _clima_fab("WoodProcessing", Vector2i(4, 3), ["wood"], "plank", 2.0, "production", 1);
	wm.startEvent("storm", zona);
	prio.update();
	_check("sin workers dice 'workers' aunque haya tormenta", prio.blocked_reason == "workers",
		"razón '%s'" % prio.blocked_reason);
	prio.workers_assigned = 1;
	prio.update();
	_check("con workers, con tormenta y sin insumo dice 'storm' (antes que input)",
		prio.blocked_reason == "storm", "razón '%s'" % prio.blocked_reason);
	wm.active.clear();
	prio.update();
	_check("sin tormenta, la siguiente es 'input'", prio.blocked_reason == "input");

	# --- (3) Plan B 1: la tormenta suspendida no para nada.
	var gm = _new_gm(file_data);
	wm.setGameManager(gm);
	wm.startEvent("storm", zona);
	gm.deadlock_timer = 12.0;
	var libre = _clima_fab("WoodCutter", Vector2i(5, 4), null, "wood", 2.0);
	libre.update();
	_check("tormenta suspendida (deadlock_timer > 0): produce como siempre", libre.blocked_reason == "");
	gm.deadlock_timer = 0.0;
	libre.update();
	_check("y al cerrarse la ventana vuelve a pararla", libre.blocked_reason == "storm");
	wm.setGameManager(null);
	gm.free();
	_limpiar([sierra, fuera, prio, libre, pm]);

	# --- (4) Restauradoras exentas: limpian bajo tormenta exactamente lo mismo que sin ella.
	var tipos = [["Reforester", null, -4.0, 0], ["WaterTreatment", ["stone"], -7.0, 1]];
	for t in tipos:
		var limpiezas = [];
		for con_tormenta in [false, true]:
			var pmr = _new_pm();
			root.add_child(pmr);
			_ensuciar_area(pmr, celda, 10.0);
			var r = _clima_fab(t[0], celda, t[1], null, t[2], "restoration", t[3]);
			r.workers_assigned = t[3];
			if t[1] != null:
				r.receiveMaterial("stone", 3);
			wm.active.clear();
			if con_tormenta:
				wm.startEvent("storm", zona);
			var antes = pmr.total_pollution;
			r.update();
			limpiezas.append([antes - pmr.total_pollution, r.blocked_reason,
				int(r.input_buffer.get("stone", 0))]);
			_limpiar([r, pmr]);
		_check("%s bajo tormenta sigue limpiando lo mismo, sin razón de parada" % t[0],
			limpiezas[0] == limpiezas[1] and limpiezas[1][0] > 0.0 and limpiezas[1][1] == "",
			str(limpiezas));
	wm.active.clear();

	# --- (5) El almacén no se toca: vuelca en la bolsa lo que le traen, con tormenta o sin ella.
	var bag = _new_bag();
	var almacen = _clima_fab("Storage", celda, null, null, 0.0, "storage");
	almacen.receiveMaterial("wood", 3);
	wm.startEvent("storm", zona);
	almacen.update(bag);
	_check("el almacén bajo tormenta vuelca en la bolsa y no dice 'storm'",
		almacen.blocked_reason == "" and int(bag.getQuantity("wood")) == 3 and almacen.input_buffer.is_empty(),
		"razón '%s', wood %d" % [almacen.blocked_reason, int(bag.getQuantity("wood"))]);
	_limpiar([almacen, wm]);
	if is_instance_valid(bag) and bag is Node:
		bag.free();

	# --- (6) Vocabulario: frase y color propios, distintos de las otras cuatro.
	var blocked = load("res://ui/blockedReason.gd");
	var script_tm = load("res://entities/tilemap/tileMap.gd");
	var frase = blocked.text_for("storm");
	_check("blockedReason tiene frase para 'storm'", frase != "" and frase.find("null") < 0, frase);
	var color = blocked.color_for("storm");
	var repetido = false;
	for k in ["workers", "input", "output", "choke"]:
		if script_tm.STATUS_COLORS[k] == color:
			repetido = true;
	_check("y su color es el de STATUS_COLORS y no repite ninguno de los otros",
		script_tm.STATUS_COLORS.has("storm") and color == script_tm.STATUS_COLORS["storm"] and not repetido,
		str(color));

	# --- (7) Main: la analítica acepta la razón nueva y la cuenta en run_sample.
	var main = _main_para_run();
	main.weather_enabled = false;
	var recibidos = [];
	main.analytics.sink = func(n, p): recibidos.append([n, p]);
	main._start_game("standard");
	var wr = main.weatherManager;
	wr.log_events = false;
	var a = main.analytics;
	_check("el enum `blocked` del catálogo incluye 'storm'", a.enums["blocked"].has("storm"),
		str(a.enums["blocked"]));
	_check("y run_sample declara blocked_storm", a.events["run_sample"]["props"].has("blocked_storm"));
	var hija = _factoria_en_main(main, "WoodCutter", Vector2i(3, 3), 1, null, "wood");
	wr.startEvent("storm", zona);
	hija.update();
	_check("una factoría hija de Main encuentra la tormenta como hermana: 'storm'",
		hija.blocked_reason == "storm", "razón '%s'" % hija.blocked_reason);
	recibidos.clear();
	main._show_factory_panel(hija);
	var po = _filas_de(recibidos, "panel_opened");
	_check("panel_opened con blocked 'storm' pasa el validador y se manda",
		po.size() == 1 and po[0]["blocked"] == "storm", str(recibidos));
	var panel = main.get_node_or_null("FactoryPanel");
	if panel != null:
		main.remove_child(panel);
		panel.free();
	recibidos.clear();
	var muestra = a.build_sample();
	_check("run_sample cuenta la parada en blocked_storm",
		muestra.get("blocked_storm", -1) >= 1 and typeof(muestra.get("blocked_storm")) == TYPE_INT, str(muestra.get("blocked_storm")));
	_check("y la muestra con blocked_storm pasa el validador del catálogo",
		a.track("run_sample", muestra) and _nombres_de(recibidos) == ["run_sample"], str(recibidos));
	_liberar_main(main);

# ---------- Clima en la analítica (2026-10-01) ----------

# Hasta el 2026-10-01 el clima solo llegaba a Augur como `blocked_storm`: sin evento de inicio ni de
# fin no se sabía qué clima salió, dónde ni cuánto duró. Aquí se afirma el cableado de Main a la
# analítica y que todo pasa el validador del catálogo (un prop que no casara tumbaría el evento).
func _test_clima_analitica(file_data):
	print("Clima en la analítica — weather_started, weather_ended y weather_active en run_sample");
	var main = _main_para_run();
	main.weather_enabled = false;
	var recibidos = [];
	main.analytics.sink = func(n, p): recibidos.append([n, p]);
	main._start_game("standard");
	var wm = main.weatherManager;
	wm.log_events = false;
	var a = main.analytics;
	var ids = file_data.get("WeatherEvents", {}).keys();
	ids.sort();
	var enum_ids = a.enums.get("weather", []).duplicate();
	enum_ids.sort();
	_check("el enum `weather` del catálogo son exactamente los climas de WeatherEvents",
		enum_ids == ids and ids.size() > 0, "%s vs %s" % [str(enum_ids), str(ids)]);

	# --- Inicio: zona recortada, duración del JSON, probabilidad y activos contando este.
	recibidos.clear();
	var ev = wm.startEvent("drought", Rect2i(-2, -1, 5, 4));
	var ws = _filas_de(recibidos, "weather_started");
	_check("startEvent() manda un weather_started que pasa el validador",
		ev != null and ws.size() == 1, str(recibidos));
	if ws.size() == 1:
		var f = ws[0];
		_check("con el clima, la zona YA recortada al mapa y la duración del catálogo",
			f["weather"] == "drought" and f["x"] == ev.rect.position.x and f["y"] == ev.rect.position.y
				and f["w"] == ev.rect.size.x and f["h"] == ev.rect.size.y and f["w"] < 5
				and is_equal_approx(f["duration"], float(file_data["WeatherEvents"]["drought"]["duration"])),
			str(f));
		_check("la probabilidad de la tirada y n_active = 1",
			is_equal_approx(f["chance"], wm.rollChance()) and f["n_active"] == 1, str(f));
	var ev2 = wm.startEvent("rain", Rect2i(8, 4, 5, 4));
	ws = _filas_de(recibidos, "weather_started");
	_check("un segundo clima solapado cuenta n_active = 2",
		ev2 != null and ws.size() == 2 and ws[1]["n_active"] == 2, str(ws));

	# --- run_sample: los dos vivos.
	recibidos.clear();
	var muestra = a.build_sample();
	_check("run_sample lleva weather_active = 2, int",
		muestra.get("weather_active", -1) == 2 and typeof(muestra.get("weather_active")) == TYPE_INT,
		str(muestra.get("weather_active")));
	_check("y la muestra pasa el validador",
		a.track("run_sample", muestra) and _nombres_de(recibidos) == ["run_sample"], str(recibidos));

	# --- Fin: la sequía se agota antes; al acabar queda uno vivo.
	recibidos.clear();
	ev.remaining = 0.5;
	ev2.remaining = 100.0;
	wm.advance(1.0);
	var we = _filas_de(recibidos, "weather_ended");
	_check("agotar la sequía manda weather_ended con n_active = 1 (los vivos, no el array viejo)",
		we.size() == 1 and we[0]["weather"] == "drought" and we[0]["n_active"] == 1, str(recibidos));
	_check("y el HUD sigue recibiendo su aviso de fin, como antes",
		main.gameManager._weather_end_id == "drought", main.gameManager._weather_end_id);

	# --- Sin run viva no se manda nada (track() lo rechazaría con un aviso).
	main._end_run("abandon");
	recibidos.clear();
	wm.startEvent("storm", Rect2i(0, 0, 3, 3));
	_check("sin run viva el clima no manda nada", _filas_de(recibidos, "weather_started").is_empty(),
		str(recibidos));
	_liberar_main(main);

# ---------- Clima M4: viento ----------

# Un segundo de contagio en pasos de 1/60, como en _test_cd2_contagio.
func _clima_contagio_1s(tm, pm):
	for i in range(60):
		tm.tick_contagion(pm, 1.0 / 60.0);

# Qué recibe cada una de las 8 vecinas de `foco`.
func _clima_vecinas(pm, foco):
	var r = {};
	for offset in pm.NEIGHBOR_OFFSETS:
		r[offset] = pm.pollution_per_cell.get(foco + offset, 0.0);
	return r;

# Un foco saturado (13 > 12,5) en `foco`, un segundo de contagio, y el pm resultante.
func _clima_foco_1s(tm, foco):
	var pm = _new_pm();
	pm.addPollution(13.0, foco);
	_clima_contagio_1s(tm, pm);
	return pm;

# Qué prueba: con viento el contagio de un foco de su zona va ENTERO a la vecina de sotavento
# (8×amount, el total añadido idéntico al de sin viento); fuera de la zona, con sotavento
# fuera del mapa, con el viento retirado o suspendido (plan B 1), y con el TileMap suelto,
# el contagio es el de siempre a las 8; y con dos vientos solapados manda el más antiguo.
func _test_clima_m4(file_data):
	print("Clima M4 — viento");
	var viento = file_data["WeatherEvents"]["wind"];
	_check("el viento del catálogo sopla hacia [1, 0] y dura 20 s (precondición)",
		int(viento["contagion_direction"][0]) == 1 and int(viento["contagion_direction"][1]) == 0
		and float(viento["duration"]) == 20.0);
	var foco = Vector2i(5, 5);
	var este = Vector2i(1, 0);
	var tm = _tilemap_con_suelo(_clima_mapa_16x10());

	# --- (0) Regresión: TileMap suelto, sin WeatherManager inyectado — lo de siempre.
	_check("sin WeatherManager la dirección del viento es ZERO", tm._windAt(foco) == Vector2i.ZERO);
	var pm0 = _clima_foco_1s(tm, foco);
	var esperado = pm0.contagion_rate * 1.0;
	var vec0 = _clima_vecinas(pm0, foco);
	var ocho = true;
	for offset in vec0:
		if not _near(vec0[offset], esperado, 0.001):
			ocho = false;
	_check("sin WeatherManager el foco contagia a sus 8 vecinas", ocho, str(vec0));
	var total_sin_viento = pm0.total_pollution;
	_check("y el global sube 8×amount (precondición de la conservación)",
		_near(total_sin_viento, 13.0 + 8.0 * esperado, 0.001), "%f" % total_sin_viento);

	# --- (1) Viento [1,0] sobre el foco: todo a sotavento, total idéntico.
	var wm = _new_wm(file_data);
	wm.log_events = false;
	tm.setWeatherManager(wm);
	wm.startEvent("wind", Rect2i(2, 2, 6, 5));
	_check("dentro de la zona la dirección es [1, 0]", wm.getContagionDirectionAt(foco) == este);
	var pm1 = _clima_foco_1s(tm, foco);
	var vec1 = _clima_vecinas(pm1, foco);
	var solo_sotavento = true;
	for offset in vec1:
		if offset != este and vec1[offset] != 0.0:
			solo_sotavento = false;
	_check("con viento solo la vecina de sotavento recibe contagio", solo_sotavento, str(vec1));
	_check("y recibe 8×amount", _near(vec1[este], 8.0 * esperado, 0.001),
		"%f, esperado %f" % [vec1[este], 8.0 * esperado]);
	_check("el total añadido es idéntico al de sin viento (se conserva, solo cambia la dirección)",
		_near(pm1.total_pollution, total_sin_viento, 0.001),
		"%f contra %f" % [pm1.total_pollution, total_sin_viento]);
	_check("y peak_pollution sube lo mismo", _near(pm1.peak_pollution, pm0.peak_pollution, 0.001));
	_check("el foco no pierde nada", _near(pm1.pollution_per_cell[foco], 13.0));

	# --- (2) Foco fuera de la zona: contagia a las 8 aunque sople viento en otro sitio.
	var lejos = Vector2i(12, 2);
	var pm2 = _clima_foco_1s(tm, lejos);
	var vec2 = _clima_vecinas(pm2, lejos);
	var ocho2 = true;
	for offset in vec2:
		if not _near(vec2[offset], esperado, 0.001):
			ocho2 = false;
	_check("un foco fuera de la zona de viento contagia a las 8 como siempre", ocho2, str(vec2));

	# --- (3) Foco en la zona con sotavento fuera del mapa: contagio normal (5 vecinas en el borde).
	var borde = Vector2i(15, 5);
	wm.active.clear();
	wm.startEvent("wind", Rect2i(12, 3, 6, 5));
	_check("el foco del borde está en la zona (precondición)",
		wm.getContagionDirectionAt(borde) == este and tm.get_cell_source_id(0, borde + este) == -1);
	var pm3 = _clima_foco_1s(tm, borde);
	var vec3 = _clima_vecinas(pm3, borde);
	var normal3 = true;
	for offset in vec3:
		var existe = tm.get_cell_source_id(0, borde + offset) != -1;
		if not _near(vec3[offset], esperado if existe else 0.0, 0.001):
			normal3 = false;
	_check("con sotavento fuera del mapa el foco contagia como siempre a las que existen", normal3,
		str(vec3));
	_check("ni se pierde ni se sale: el global sube 5×amount",
		_near(pm3.total_pollution, 13.0 + 5.0 * esperado, 0.001) and not pm3.pollution_per_cell.has(borde + este),
		"%f" % pm3.total_pollution);

	# --- (4) El viento se retira a los 20 s y el contagio vuelve a las 8.
	wm.active.clear();
	wm.startEvent("wind", Rect2i(2, 2, 6, 5));
	wm.advance(19.0);
	var pm4a = _clima_foco_1s(tm, foco);
	_check("a los 19 s aún sopla", _near(pm4a.pollution_per_cell.get(foco + este, 0.0), 8.0 * esperado, 0.001));
	wm.advance(1.0);
	_check("a los 20 s el viento se retira (precondición)", wm.active.is_empty());
	var pm4 = _clima_foco_1s(tm, foco);
	var vec4 = _clima_vecinas(pm4, foco);
	var ocho4 = true;
	for offset in vec4:
		if not _near(vec4[offset], esperado, 0.001):
			ocho4 = false;
	_check("al retirarse el viento el contagio vuelve a las 8 vecinas", ocho4, str(vec4));

	# --- (5) Plan B 1: viento suspendido no desvía; al cerrarse la ventana vuelve a desviar.
	var gm = _new_gm(file_data);
	wm.setGameManager(gm);
	wm.startEvent("wind", Rect2i(2, 2, 6, 5));
	gm.deadlock_timer = 12.0;
	_check("suspendido, la dirección es ZERO", wm.getContagionDirectionAt(foco) == Vector2i.ZERO);
	var pm5 = _clima_foco_1s(tm, foco);
	var vec5 = _clima_vecinas(pm5, foco);
	var ocho5 = true;
	for offset in vec5:
		if not _near(vec5[offset], esperado, 0.001):
			ocho5 = false;
	_check("viento suspendido (deadlock_timer > 0): contagio a las 8 como siempre", ocho5, str(vec5));
	gm.deadlock_timer = 0.0;
	var pm5b = _clima_foco_1s(tm, foco);
	_check("y al cerrarse la ventana vuelve a desviar",
		_near(pm5b.pollution_per_cell.get(foco + este, 0.0), 8.0 * esperado, 0.001)
		and pm5b.pollution_per_cell.get(foco + Vector2i(-1, 0), 0.0) == 0.0);
	wm.setGameManager(null);
	gm.free();

	# --- (6) Solape: manda el PRIMER evento activo con viento que cubra la celda. Un viento
	# de oeste se añade al catálogo de ESTE manager (copia, no el file_data compartido).
	wm.active.clear();
	wm.catalog = wm.catalog.duplicate(true);
	wm.catalog["wind_west"] = {"name": "Viento de poniente", "duration": 20.0, "zone_size": [6, 5],
		"contagion_direction": [-1, 0]};
	var oeste = Vector2i(-1, 0);
	wm.startEvent("wind", Rect2i(2, 2, 6, 5));
	wm.startEvent("wind_west", Rect2i(3, 3, 6, 5));
	_check("solape: con el de levante primero, sopla a levante",
		wm.getContagionDirectionAt(foco) == este);
	var pm6 = _clima_foco_1s(tm, foco);
	_check("y todo el contagio va a levante, nada a poniente",
		_near(pm6.pollution_per_cell.get(foco + este, 0.0), 8.0 * esperado, 0.001)
		and pm6.pollution_per_cell.get(foco + oeste, 0.0) == 0.0);
	wm.active.clear();
	wm.startEvent("wind_west", Rect2i(3, 3, 6, 5));
	wm.startEvent("wind", Rect2i(2, 2, 6, 5));
	var pm7 = _clima_foco_1s(tm, foco);
	_check("con el de poniente primero, todo a poniente (no se suman ni se anulan)",
		_near(pm7.pollution_per_cell.get(foco + oeste, 0.0), 8.0 * esperado, 0.001)
		and pm7.pollution_per_cell.get(foco + este, 0.0) == 0.0);
	# Un evento sin viento que cubra la celda antes no tapa al que sí lo trae.
	wm.active.clear();
	wm.startEvent("rain", Rect2i(2, 2, 6, 5));
	wm.startEvent("wind", Rect2i(2, 2, 6, 5));
	_check("una lluvia más antigua sobre la celda no tapa al viento",
		wm.getContagionDirectionAt(foco) == este);

	# --- (7) Solo cambia la dirección: las constantes de la derrota no se han movido.
	_check("contagion_rate sigue en 0,12 (provisional, no se toca en M4)", _near(pm0.contagion_rate, 0.12));
	_check("contagion_pollution sigue en 12,5", _near(pm0.contagion_pollution, 12.5));

	tm.setWeatherManager(null);
	_limpiar([tm, wm, pm0, pm1, pm2, pm3, pm4a, pm4, pm5, pm5b, pm6, pm7]);

# ---------- Clima M5: aviso y tintado ----------

# Los polígonos de `spy` pintados con el color de un evento del catálogo (alpha incluido: el
# relleno de la zona usa el del JSON tal cual). Ningún otro tinte comparte esos colores.
func _clima_polys_de(spy, catalogo, id):
	var col = catalogo[id]["color"];
	var hallados = [];
	for i in spy.polys.size():
		var c = spy.polys[i]["color"];
		if _near(c.r, float(col[0])) and _near(c.g, float(col[1])) and _near(c.b, float(col[2])) \
				and _near(c.a, float(col[3])):
			hallados.append(i);
	return hallados;

# Qué prueba: el HUD nombra el evento vivo y su tiempo, y anuncia el fin un rato; con la
# ventana de punto muerto abierta no sale el clima; la prioridad deadlock > progreso > clima >
# línea y ninguna combinación pasa de HUD_MAX_CHARS; el texto es solo lectura; la pasada de
# draw_tints() pinta la zona (y su contorno) mientras dura y deja de pintarla al retirarse, va
# después de la contaminación y antes del colapso, no pinta suspendida, y los overlays siguen
# siendo los de siempre. El veredicto visual es de tools/ver_clima.gd.
func _test_clima_m5(file_data):
	print("Clima M5 — aviso en el HUD y tinte de la zona");
	var gm_script = load("res://managers/gameManager.gd");
	var presupuesto = gm_script.HUD_MAX_CHARS;
	var catalogo = file_data["WeatherEvents"];
	var zona = Rect2i(2, 2, 4, 3);

	# --- (1) El aviso: nombre del catálogo y segundos, delante del progreso.
	var gm = _new_gm(file_data, [{ "material": "plank", "quantity": 20, "label": "Checkpoint 1/5" }]);
	var bag = _new_bag();
	bag.initialize(file_data);
	var sin_clima = gm.getObjectiveText(bag);
	var wm = _new_wm(file_data);
	wm.log_events = false;
	gm.setWeatherManager(wm);
	wm.weather_ended.connect(gm._on_weather_ended);
	_check("con el manager inyectado y sin eventos el HUD es el de antes",
		gm.getObjectiveText(bag) == sin_clima, gm.getObjectiveText(bag));
	wm.startEvent("storm", zona);
	var con_tormenta = gm.getObjectiveText(bag);
	_check("con una tormenta viva el HUD la nombra con sus segundos, delante",
		con_tormenta.begins_with("%s 15 s" % catalogo["storm"]["name"]), con_tormenta);
	_check("y el progreso sigue entero detrás", con_tormenta.ends_with(sin_clima), con_tormenta);
	wm.advance(3.2);
	_check("los segundos bajan con el reloj del manager (hacia arriba: 11,8 → 12)",
		gm.getObjectiveText(bag).begins_with("%s 12 s" % catalogo["storm"]["name"]), gm.getObjectiveText(bag));
	wm.startEvent("drought", zona);
	var dos = gm.getObjectiveText(bag);
	_check("con dos eventos salen los dos, en orden de nacimiento",
		dos.begins_with("%s 12 s%s%s 30 s" % [catalogo["storm"]["name"], gm_script.WEATHER_SEPARATOR,
			catalogo["drought"]["name"]]), dos);
	_check("una sola línea", not ("\n" in dos));

	# Solo lectura: mirar el HUD no mueve ni el manager ni el gameManager.
	var antes = [wm.active.size(), wm.active[0].remaining, gm.run_time, gm._weather_end_id, gm.active];
	for i in 5:
		gm.getObjectiveText(bag);
	_check("getObjectiveText() no toca el clima ni el gameManager",
		antes == [wm.active.size(), wm.active[0].remaining, gm.run_time, gm._weather_end_id, gm.active]);

	# --- (2) El fin: la señal lo anota y el HUD lo enseña WEATHER_END_NOTICE_SECS.
	gm.run_time = 50.0;
	wm.advance(12.0);   # la tormenta (11,8 s) termina; la sequía sigue
	var fin = gm.getObjectiveText(bag);
	_check("al terminar la tormenta el HUD ya no la cuenta, pero anuncia su fin",
		not ("%s 1" % catalogo["storm"]["name"] in fin) and ("%s: fin" % catalogo["storm"]["name"] in fin), fin);
	_check("y la sequía sigue ahí", fin.begins_with(catalogo["drought"]["name"]), fin);
	gm.run_time = 50.0 + gm_script.WEATHER_END_NOTICE_SECS + 0.1;
	_check("pasados WEATHER_END_NOTICE_SECS el aviso de fin se va",
		not (": fin" in gm.getObjectiveText(bag)), gm.getObjectiveText(bag));
	wm.active.clear();
	_check("sin eventos y sin fin reciente, el HUD vuelve a ser el de antes",
		gm.getObjectiveText(bag) == sin_clima, gm.getObjectiveText(bag));
	gm.run_time = 60.0;
	gm._on_weather_ended("rain");
	wm.startEvent("rain", zona);
	var vuelve = gm.getObjectiveText(bag);
	_check("si el mismo evento vuelve a empezar, no se anuncia a la vez su fin",
		not (": fin" in vuelve) and vuelve.begins_with(catalogo["rain"]["name"]), vuelve);
	wm.active.clear();
	gm._weather_end_id = "";

	# --- (3) Prioridad y presupuesto, en el checkpoint final de la curva real con la cola de
	# contaminación y el semáforo: la peor línea que el juego sabe producir, más los cuatro
	# eventos a la vez y un fin reciente.
	var gm3 = _new_gm(file_data);
	gm3.setWeatherManager(wm);
	gm3.current_checkpoint_index = gm3.checkpoints.size() - 1;
	var ultimo = gm3.checkpoints[gm3.current_checkpoint_index];
	var bag3 = _new_bag();
	bag3.initialize(file_data);
	bag3.addToBag(ultimo["material"], int(ultimo["quantity"]) - 1);
	var pm3 = _new_pm();
	pm3.addPollution(22607.0, Vector2i(5, 5));
	gm3.segment_capacity_area = float(int(ultimo["quantity"]));
	gm3.run_time = gm_script.WARMUP_SECONDS + 10.0;
	gm3.last_checkpoint_time = 0.0;
	var ids = catalogo.keys();
	ids.sort();
	for id in ids:
		wm.startEvent(id, zona);
	gm3._weather_end_id = "wind";
	gm3._weather_end_at = gm3.run_time;
	var estado = gm3.getLineState(bag3);
	var progreso = gm3._progressText(bag3, pm3, false);
	var todo = gm3.getObjectiveText(bag3, pm3);
	_check("hay semáforo que enseñar (precondición)", estado != "", estado);
	_check("los cuatro eventos + fin + progreso + línea: una línea dentro de HUD_MAX_CHARS",
		todo.length() <= presupuesto and not ("\n" in todo), "%d de %d: %s" % [todo.length(), presupuesto, todo]);
	_check("el progreso del checkpoint llega ENTERO (no se sacrifica por el clima)",
		todo.ends_with(progreso) or todo.ends_with(gm3._progressText(bag3, pm3, false,
			gm_script.LINE_STATE_TEXT % estado)), todo);
	_check("y el semáforo cede ante el clima: con clima y sin sitio, fuera la línea",
		not ("Línea" in todo) and todo.begins_with(catalogo[ids[0]]["name"]), todo);
	# Con un solo evento y una etiqueta corta caben todos, línea incluida.
	wm.active.clear();
	wm.startEvent("storm", zona);
	gm3.checkpoints = [{ "material": "plank", "quantity": 99, "label": "Checkpoint 2/5" }];
	gm3.current_checkpoint_index = 0;
	gm3._weather_end_id = "";
	var holgado = gm3.getObjectiveText(bag3, pm3);
	_check("con sitio de sobra salen clima, progreso y línea",
		holgado.begins_with(catalogo["storm"]["name"]) and ("Línea" in holgado)
		and holgado.length() <= presupuesto, holgado);
	# Si ni el clima con el progreso cabe, se cae el clima y el progreso se queda.
	gm3.checkpoints = [{ "material": "plank", "quantity": 99, "label": "Etiqueta ".repeat(15) }];
	var apretado = gm3.getObjectiveText(bag3, pm3);
	_check("con un progreso que ya llena la línea, el clima se cae y el progreso manda",
		not (catalogo["storm"]["name"] in apretado) and apretado.length() <= presupuesto
		and apretado.begins_with("Etiqueta"), "%d: %s" % [apretado.length(), apretado]);
	wm.active.clear();

	# --- (4) Punto muerto abierto: el clima ni se anuncia ni se tiñe (plan B 1).
	var centro = Vector2i(5, 5);
	var pm4 = _new_pm();
	var esc = _escenario_muerto(file_data, centro, pm4);
	esc["pm"] = pm4;
	var gm4 = esc["gm"];
	var tm4 = esc["tm"];
	tm4.setGameManager(gm4);
	var wm4 = _new_wm(file_data);
	wm4.log_events = false;
	wm4.setGameManager(gm4);
	gm4.setWeatherManager(wm4);
	tm4.setWeatherManager(wm4);
	wm4.startEvent("drought", Rect2i(4, 4, 3, 3));
	var spy_abierto = SpyCanvas.new();
	tm4.draw_tints(spy_abierto);
	_check("con la ventana cerrada la sequía se tiñe (precondición)",
		_clima_polys_de(spy_abierto, catalogo, "drought").size() == 9 and spy_abierto.lines.size() > 0,
		"%d polígonos, %d líneas" % [_clima_polys_de(spy_abierto, catalogo, "drought").size(), spy_abierto.lines.size()]);
	gm4.run_time = 10.0;
	gm4.update(esc["bag"], pm4);
	gm4.run_time = 11.0;
	_check("la ventana se abre (precondición)", gm4.deadlock_timer > 0.0 and wm4.isSuspended());
	var colapso = gm4.getObjectiveText(esc["bag"], pm4);
	_check("con la ventana abierta el HUD no anuncia el clima",
		colapso.begins_with(gm4._deadlockText()) and not (catalogo["drought"]["name"] in colapso), colapso);
	gm4._weather_end_id = "storm";
	gm4._weather_end_at = gm4.run_time;
	_check("ni siquiera un fin reciente",
		not (": fin" in gm4.getObjectiveText(esc["bag"], pm4)), gm4.getObjectiveText(esc["bag"], pm4));
	var spy_susp = SpyCanvas.new();
	tm4.draw_tints(spy_susp);
	_check("y draw_tints() no tiñe la zona ni dibuja su contorno",
		_clima_polys_de(spy_susp, catalogo, "drought").is_empty() and spy_susp.lines.is_empty(),
		"%d polígonos, %d líneas" % [_clima_polys_de(spy_susp, catalogo, "drought").size(), spy_susp.lines.size()]);

	# --- (5) El orden de las pasadas: tipo → contaminación → clima → colapso. Clima y colapso
	# no coinciden en el juego (suspendido); aquí se fuerza soltando el gameManager del manager.
	wm4.setGameManager(null);
	tm4.set_cell_color(centro, Color(0.2, 0.6, 0.2));
	var spy_orden = SpyCanvas.new();
	tm4.draw_tints(spy_orden);
	var tm_script = load("res://entities/tilemap/tileMap.gd");
	var clima_idx = _clima_polys_de(spy_orden, catalogo, "drought");
	var colapso_idx = [];
	for p in _diamantes_colapso(spy_orden, tm_script):
		colapso_idx.append(spy_orden.polys.find(p));
	var contaminacion_idx = [];
	for i in spy_orden.polys.size():
		var c = spy_orden.polys[i]["color"];
		if _near(c.r, 1.0) and _near(c.g, 0.15) and _near(c.b, 0.0):
			contaminacion_idx.append(i);
	_check("hay de las tres pasadas (precondición)",
		not clima_idx.is_empty() and not colapso_idx.is_empty() and not contaminacion_idx.is_empty());
	_check("el clima va DESPUÉS de la contaminación", contaminacion_idx.max() < clima_idx.min(),
		"%s / %s" % [str(contaminacion_idx.max()), str(clima_idx.min())]);
	_check("y ANTES del colapso", clima_idx.max() < colapso_idx.min(),
		"%s / %s" % [str(clima_idx.max()), str(colapso_idx.min())]);
	_check("el overlay sigue siendo el TintOverlay a z 1 y el StatusOverlay a z 3 (la pasada no crea otro)",
		tm4.get_node_or_null("TintOverlay") != null and tm4.get_node("TintOverlay").z_index == 1
		and tm4.get_node_or_null("StatusOverlay") != null and tm4.get_node("StatusOverlay").z_index == 3);
	tm4.setWeatherManager(null);
	_limpiar([tm4, gm4, esc["bag"], pm4, wm4]);

	# --- (6) La zona: qué casillas tiñe, que las tiñe entera mientras dura y que al retirarse
	# deja de pintarla. Mapa 16x10 entero de suelo.
	var tm = _tilemap_con_suelo(_clima_mapa_16x10());
	var spy_sin = SpyCanvas.new();
	tm.draw_tints(spy_sin);
	_check("sin WeatherManager inyectado draw_tints() no dibuja contornos", spy_sin.lines.is_empty());
	tm.setWeatherManager(wm);
	wm.active.clear();
	var tormenta = wm.startEvent("storm", Rect2i(14, 8, 4, 3));   # se recorta a 2x2 en la esquina
	var celdas = tm.weatherCells(tormenta);
	_check("weatherCells() da las casillas del rectángulo ya recortado",
		celdas.size() == 4 and celdas.has(Vector2i(15, 9)) and not celdas.has(Vector2i(16, 9)), str(celdas));
	var spy_viva = SpyCanvas.new();
	tm.draw_tints(spy_viva);
	_check("con la tormenta viva se tiñe cada casilla de su zona con el color del catálogo",
		_clima_polys_de(spy_viva, catalogo, "storm").size() == celdas.size(),
		"%d de %d" % [_clima_polys_de(spy_viva, catalogo, "storm").size(), celdas.size()]);
	var col_t = catalogo["storm"]["color"];
	var borde = [];
	for l in spy_viva.lines:
		if _near(l["color"].r, float(col_t[0])) and _near(l["color"].b, float(col_t[2])):
			borde.append(l);
	_check("y su contorno del color del catálogo: 8 lados para un bloque de 2x2", borde.size() == 8,
		"%d de %d líneas" % [borde.size(), spy_viva.lines.size()]);
	var opaco = true;
	for l in borde:
		if l["color"].a <= float(col_t[3]):
			opaco = false;
	_check("más opaco que el relleno", opaco);
	_check("y con su filo oscuro debajo, uno por lado y pintado ANTES que el color",
		spy_viva.lines.size() == 16 and spy_viva.lines.find(borde[0]) == 8, str(spy_viva.lines.size()));
	wm.advance(float(catalogo["storm"]["duration"]) + 0.1);
	var spy_ida = SpyCanvas.new();
	tm.draw_tints(spy_ida);
	_check("al retirarse la tormenta la zona deja de pintarse",
		wm.active.is_empty() and _clima_polys_de(spy_ida, catalogo, "storm").is_empty()
		and spy_ida.lines.is_empty());

	# --- (7) El cableado de Main._start_game(): el gameManager recibe el manager y su fin.
	var main = _main_para_run();
	main.weather_enabled = false;
	main._start_game("standard");
	var wr = main.weatherManager;
	wr.log_events = false;
	_check("_start_game() inyecta el WeatherManager en el gameManager",
		wr != null and main.gameManager.weather_manager == wr);
	_check("y conecta weather_ended al aviso de fin",
		wr.weather_ended.is_connected(main.gameManager._on_weather_ended));
	tm.setWeatherManager(null);
	_limpiar([main.placer, main.mapLoader, main, tm, gm, bag, gm3, bag3, pm3, wm]);

# ---------- Clima M0: el modo «clima agresivo» para jugar a mano ----------

# M0 se juega a mano con el clima en su versión más agresiva. `BALACTORIO_WEATHER=aggressive`
# pone la tirada al tope; sin la variable, nada cambia; en build exportada se ignora (como
# AUGUR_KEY). La lectura del entorno va por parámetro (aggressiveFromEnv) para probar las ramas
# sin tocar el entorno real de quien corre la suite.
func _test_clima_m0(file_data):
	print("Clima M0 — el modo «clima agresivo»");
	var script_wm = load("res://managers/weatherManager.gd");
	var pm = load("res://managers/pollutionManager.gd").new();
	pm.peak_pollution = 20.0;

	# --- (1) Sin el override, la probabilidad es la de siempre.
	var wm = _new_wm(file_data);
	wm.setPollutionManager(pm);
	var esperada = min(script_wm.MAX_CHANCE, script_wm.BASE_CHANCE + script_wm.PEAK_FACTOR * 20.0);
	_check("sin override, el manager nace sin modo agresivo", wm.aggressive == false);
	_check("y la probabilidad es BASE + PEAK × pico (0,15 + 0,004 × 20 = 0,23)",
		_near(wm.rollChance(), esperada) and esperada < script_wm.MAX_CHANCE, str(wm.rollChance()));

	# --- (2) Con el override, MAX_CHANCE sea cual sea el pico; y al quitarlo vuelve.
	wm.aggressive = true;
	_check("con el modo agresivo la probabilidad es MAX_CHANCE",
		_near(wm.rollChance(), script_wm.MAX_CHANCE), str(wm.rollChance()));
	pm.peak_pollution = 0.0;
	_check("también con el mapa limpio (pico 0)", _near(wm.rollChance(), script_wm.MAX_CHANCE));
	wm.aggressive = false;
	_check("y sin él, pico 0 vuelve a BASE_CHANCE", _near(wm.rollChance(), script_wm.BASE_CHANCE));

	# --- (3) La lectura del entorno: solo «aggressive», y nunca en build exportada.
	_check("variable vacía -> no agresivo", script_wm.aggressiveFromEnv(false, "") == false);
	_check("«aggressive» fuera de build -> agresivo", script_wm.aggressiveFromEnv(false, "aggressive") == true);
	_check("tolera mayúsculas y espacios", script_wm.aggressiveFromEnv(false, " Aggressive ") == true);
	_check("otro valor -> no agresivo", script_wm.aggressiveFromEnv(false, "calm") == false);
	_check("en build exportada (template) se ignora", script_wm.aggressiveFromEnv(true, "aggressive") == false);

	# --- (4) El cableado real de Main._start_game(): lo que diga el entorno de ESTA ejecución de
	#     la suite (sin la variable, que es lo normal, sale apagado).
	var main = _main_para_run();
	main.weather_enabled = false;
	main._start_game("standard");
	var wr = main.weatherManager;
	wr.log_events = false;
	var pide = script_wm.aggressiveFromEnv(OS.has_feature("template"), OS.get_environment("BALACTORIO_WEATHER"));
	_check("_start_game() aplica al manager lo que pide el entorno (%s)" % ("agresivo" if pide else "normal"),
		wr.aggressive == pide);
	if OS.get_environment("BALACTORIO_WEATHER") == "":
		_check("sin la variable, la run nace con la probabilidad de siempre",
			wr.aggressive == false and _near(wr.rollChance(),
				min(script_wm.MAX_CHANCE, script_wm.BASE_CHANCE + script_wm.PEAK_FACTOR * float(main.pollutionManager.peak_pollution))));
	_limpiar([main.placer, main.mapLoader, main, wm, pm]);

# ---------- Clima M6: la derrota sigue en pie con clima ----------

# Un tramo de MUNDO con varios sistemas a la vez, sin Main: TileMap 16x10 de suelo con su
# PollutionManager, factorías inicializadas colgando de root y, si `op.wm`, un WeatherManager
# HERMANO (hijo de root con su nombre, donde lo buscan las factorías) inyectado en el TileMap.
# Cada frame (1/60) avanza el clima, el pasivo y el contagio, en el orden de Main._tick_world();
# cada 60 frames (1 s) hace un update() de cada factoría y apunta lo que ha limpiado, su razón y
# su ahogo. Lo suelta TODO al acabar: find_child("PollutionManager") devuelve el primero del
# árbol y el hermano "WeatherManager" se busca por nombre, así que los tramos van en serie.
#   op: wm (bool), eventos ([[id, Rect2i]]), caducar (bool: retira los eventos antes del tramo),
#       suciedad ({celda: cantidad}), lagos ([celda]), segundos (float),
#       fabricas ([[tipo, celda, recibe, material, pollution, ftype, workers, insumo]]).
func _clima_m6_tramo(file_data, op):
	var pm = _new_pm();
	root.add_child(pm);
	var tm = _tilemap_con_suelo(_clima_mapa_16x10());
	tm.setPollutionManager(pm);
	tm.cell_types = {};
	tm.tile_type_data = { "lake": { "passive_pollution_per_tick": -0.5, "buildable": false } };
	for c in op.get("lagos", []):
		tm.cell_types[c] = "lake";
	var suciedad = op.get("suciedad", {});
	for c in suciedad:
		pm.addPollution(suciedad[c], c);
	var wm = null;
	if op.get("wm", false):
		wm = _clima_wm_en_arbol(file_data);
		tm.setWeatherManager(wm);
		for e in op.get("eventos", []):
			wm.startEvent(e[0], e[1]);
		if op.get("caducar", false):
			wm.advance(1000.0);
	var fabs = [];
	var producidos = [];
	for d in op.get("fabricas", []):
		var f = _clima_fab(d[0], d[1], d[2], d[3], d[4], d[5], d[6]);
		f.workers_assigned = d[6];
		if d.size() > 7 and d[7] != null:
			f.receiveMaterial(d[7], 99);
		var idx = fabs.size();
		f.resource_produced.connect(func(m, n, _p): producidos.append([idx, m, n]));
		fabs.append(f);
	var r = {
		"primero": root.find_child("PollutionManager", true, false) == pm,
		"hermano": wm == null or root.get_node_or_null("WeatherManager") == wm,
		"total0": pm.total_pollution, "peak0": pm.peak_pollution,
		"limpiado": [], "razones": [], "chokes": [],
	};
	for f in fabs:
		r["limpiado"].append([]);
		r["razones"].append([]);
		r["chokes"].append([]);
	var dt = 1.0 / 60.0;
	var frames = int(round(float(op.get("segundos", 1.0)) * 60.0));
	for i in range(frames):
		if wm != null:
			wm.advance(dt);
		tm.tick_passive(pm, dt);
		tm.tick_contagion(pm, dt);
		if (i + 1) % 60 == 0:
			for k in fabs.size():
				var antes = pm.total_pollution;
				fabs[k].update();
				r["limpiado"][k].append(antes - pm.total_pollution);
				r["razones"][k].append(fabs[k].blocked_reason);
				r["chokes"][k].append(fabs[k].getPollutionChoke());
	r["celdas"] = pm.pollution_per_cell.duplicate();
	r["total"] = pm.total_pollution;
	r["peak"] = pm.peak_pollution;
	r["producidos"] = producidos;
	r["activos"] = wm.active.size() if wm != null else 0;
	r["contagion_rate"] = pm.contagion_rate;
	r["contagion_pollution"] = pm.contagion_pollution;
	tm.setWeatherManager(null);
	var nodos = fabs + [tm, pm];
	if wm != null:
		nodos.append(wm);
	_limpiar(nodos);
	return r;

# M6 no re-mide nada (no hay instrumento desde el 2026-09-23): fija las RELACIONES que el clima
# no puede romper, montadas con varios sistemas a la vez. Lo que ya prueba un hito anterior se
# cita y no se repite: sequía ×1,5 y retirada (M2 §1), restauradora bajo sequía en un tick
# (M2 §3) y bajo tormenta en un tick (M3 §4), viento 8×amount de UN foco en 1 s (M4 §1),
# suspensión B1 de cada consulta por separado (M1 §4, M2 §2/§4, M3 §3, M4 §5), tick_passive
# sin manager == sin eventos (M2 §6), HUD sin eventos == antes (M5 §1), y contagion_rate 0,12 /
# contagion_pollution 12,5 (M4 §7).
func _test_clima_m6(file_data):
	print("Clima M6 — la derrota sigue en pie con clima");
	var script_wm = load("res://managers/weatherManager.gd");
	var script_gm = load("res://managers/gameManager.gd");
	var todo = Rect2i(0, 0, 16, 10);

	# --- (1) Restauradoras bajo CADA clima, 10 s de mundo con contagio y pasivo corriendo: no
	# se ahogan, nunca dicen storm/choke, y cada tick limpian EXACTAMENTE lo mismo que sin
	# clima (la sequía no reduce ni amplifica, la lluvia y el viento van por otro lado).
	# Casillas a 20 (saturadas): una productora ahí tendría choke 0.
	var suciedad = {};
	for centro in [Vector2i(4, 4), Vector2i(10, 5)]:
		for c in _vecindario(centro):
			suciedad[c] = 20.0;
	var restauradoras = [
		["Reforester", Vector2i(4, 4), null, null, -4.0, "restoration", 0, null],
		["WaterTreatment", Vector2i(10, 5), ["stone"], null, -7.0, "restoration", 1, "stone"],
	];
	var base = _clima_m6_tramo(file_data, { "wm": true, "suciedad": suciedad,
		"fabricas": restauradoras, "segundos": 10.0 });
	_check("tramo de restauradoras: el PollutionManager y el WeatherManager son los del tramo (precondición)",
		base["primero"] and base["hermano"]);
	var limpia_base = true;
	for k in 2:
		if base["limpiado"][k].size() != 10:
			limpia_base = false;
		for v in base["limpiado"][k]:
			if v <= 0.0:
				limpia_base = false;
	_check("sin clima las dos restauradoras limpian en cada uno de los 10 ticks (precondición)",
		limpia_base, str(base["limpiado"]));
	for id in ["drought", "rain", "storm", "wind"]:
		var r = _clima_m6_tramo(file_data, { "wm": true, "eventos": [[id, todo]], "suciedad": suciedad,
			"fabricas": restauradoras, "segundos": 10.0 });
		var sin_ahogo = true;
		var sin_parada = true;
		var igual = r["primero"] and r["hermano"] and r["activos"] == 1;
		for k in 2:
			for ch in r["chokes"][k]:
				if ch != 1.0:
					sin_ahogo = false;
			for rz in r["razones"][k]:
				if rz != "":
					sin_parada = false;
			if r["limpiado"][k].size() != base["limpiado"][k].size():
				igual = false;
				continue;
			for t in r["limpiado"][k].size():
				if not _near(r["limpiado"][k][t], base["limpiado"][k][t], 0.00001):
					igual = false;
		_check("bajo %s, Reforester y WaterTreatment alimentada: getPollutionChoke() == 1.0 en cada tick" % id,
			sin_ahogo, str(r["chokes"]));
		_check("bajo %s, ninguna dice 'storm' ni 'choke' (ni otra razón)" % id, sin_parada, str(r["razones"]));
		_check("bajo %s, cada tick limpian exactamente lo mismo que sin clima" % id, igual,
			"%s contra %s" % [str(r["limpiado"]), str(base["limpiado"])]);

	# --- (2) Viento con VARIOS focos, 5 s de mundo: el total y el pico suben lo mismo con
	# viento que sin él y que sin manager; solo cambia el reparto. Focos en el interior, en el
	# borde de sotavento (contagio normal), dos pegados (sotavento de uno = el otro foco) y 5 s
	# para que ninguna casilla de sotavento cruce 12,5 y se vuelva foco (8 × 0,12 × 5 = 4,8).
	var focos = {};
	for c in [Vector2i(3, 3), Vector2i(8, 5), Vector2i(15, 2), Vector2i(12, 8), Vector2i(5, 7), Vector2i(6, 7)]:
		focos[c] = 13.0;
	var sin_wm = _clima_m6_tramo(file_data, { "wm": false, "suciedad": focos, "segundos": 5.0 });
	var calma = _clima_m6_tramo(file_data, { "wm": true, "suciedad": focos, "segundos": 5.0 });
	var viento = _clima_m6_tramo(file_data, { "wm": true, "eventos": [["wind", todo]],
		"suciedad": focos, "segundos": 5.0 });
	var sube_sin = sin_wm["total"] - sin_wm["total0"];
	var sube_con = viento["total"] - viento["total0"];
	_check("tramo de focos: los managers son los del tramo y el viento sigue vivo (precondición)",
		sin_wm["primero"] and calma["primero"] and calma["hermano"] and viento["primero"]
		and viento["hermano"] and viento["activos"] == 1);
	_check("sin viento los 6 focos generan contagio (precondición)", sube_sin > 1.0, "%f" % sube_sin);
	_check("con viento, el incremento de total_pollution en 5 s es el mismo que sin él",
		_near(sube_con, sube_sin, 0.001), "%f contra %f" % [sube_con, sube_sin]);
	_check("y el de peak_pollution también",
		_near(viento["peak"] - viento["peak0"], sin_wm["peak"] - sin_wm["peak0"], 0.001),
		"%f contra %f" % [viento["peak"] - viento["peak0"], sin_wm["peak"] - sin_wm["peak0"]]);
	_check("y con el manager presente sin viento, igual que sin manager",
		_near(calma["total"] - calma["total0"], sube_sin, 0.001));
	var reparte_distinto = false;
	for c in viento["celdas"]:
		if not _near(viento["celdas"][c], sin_wm["celdas"].get(c, 0.0), 0.001):
			reparte_distinto = true;
			break;
	_check("lo único que cambia es el reparto: hay casillas con otra suciedad", reparte_distinto);
	_check("ninguna casilla de sotavento se ha vuelto foco (precondición de la conservación)",
		viento["celdas"].get(Vector2i(4, 3), 0.0) < 12.5 and viento["celdas"].get(Vector2i(7, 7), 0.0) < 12.5);
	_check("y tras el tramo con viento el PollutionManager conserva contagion_rate 0,12 y contagion_pollution 12,5",
		_near(viento["contagion_rate"], 0.12) and _near(viento["contagion_pollution"], 12.5));

	# --- (3) Plan B 1 integrado: la ventana de punto muerto ABIERTA DE VERDAD por
	# _evaluate_deadlock() sobre el mapa saturado, clima agresivo (probabilidad al tope) y
	# sembrado, y 2×ROLL_INTERVAL + 5 s de reloj corriendo: no nace nada y los activos no
	# descuentan. El control (misma semilla, sin ventana) demuestra que en ese tramo SÍ habría
	# tiradas con premio. Y la derrota llega a su hora, con clima o sin él.
	var tramo = 2.0 * script_wm.ROLL_INTERVAL + 5.0;
	var gracia = script_gm.DEADLOCK_GRACE;
	var centro = Vector2i(5, 5);
	var nacidos = {};
	for abierta in [false, true]:
		var pm = _new_pm();
		var esc = _escenario_muerto(file_data, centro, pm);
		esc["pm"] = pm;
		var gm = esc["gm"];
		var wm = _new_wm(file_data);
		wm.enabled = true;
		wm.log_events = false;
		wm.aggressive = true;
		wm.setSeed(20260930);
		wm.setPollutionManager(pm);
		wm.setGameManager(gm);
		gm.setWeatherManager(wm);
		esc["tm"].setWeatherManager(wm);
		wm.startEvent("drought", Rect2i(4, 4, 3, 3));
		wm.startEvent("wind", Rect2i(3, 3, 5, 5));
		var restantes = [wm.active[0].remaining, wm.active[1].remaining];
		var originales = [wm.active[0], wm.active[1]];
		var reloj = wm._roll_timer;
		var n = [0];
		wm.weather_started.connect(func(_id, _r): n[0] += 1);
		gm.run_lost.connect(func(stats): esc["perdidas"].append(stats));
		var t0 = 10.0;
		var avanza = func(): wm.advance(1.0 / 60.0);
		if not abierta:
			var frames = int(round(tramo * 60.0));
			for i in range(frames):
				avanza.call();
			nacidos["control"] = n[0];
			_check("control sin ventana: en %.0f s el clima agresivo sembrado sí saca eventos" % tramo,
				n[0] >= 1, "nacidos %d" % n[0]);
			_check("y los activos del control sí descuentan (la sequía y el viento de partida ya se retiraron)",
				not wm.active.has(originales[0]) and not wm.active.has(originales[1]), str(wm.active.size()));
		else:
			gm.run_time = t0;
			gm.update(esc["bag"], pm);
			_check("_evaluate_deadlock() abre la ventana con dos eventos activos encima",
				_near(gm.deadlock_timer, t0) and wm.isSuspended(), "deadlock_timer %f" % gm.deadlock_timer);
			var t = _correr_hasta(esc, t0, t0 + gracia - 0.1, avanza);
			_check("a mitad de gracia la ventana sigue abierta, sin eventos nuevos",
				gm.deadlock_timer > 0.0 and n[0] == 0 and esc["perdidas"].is_empty());
			_correr_hasta(esc, t, t0 + tramo, avanza);
			_check("en %.0f s (≥ 2×ROLL_INTERVAL) con la ventana abierta no nace ni un evento" % tramo,
				n[0] == 0 and wm.active.size() == 2 and wm._roll_timer == reloj, "nacidos %d" % n[0]);
			_check("y los dos activos no han descontado nada",
				wm.active[0].remaining == restantes[0] and wm.active[1].remaining == restantes[1],
				"%f / %f" % [wm.active[0].remaining, wm.active[1].remaining]);
			_check("y la derrota llega igual: run_lost una sola vez, al agotarse DEADLOCK_GRACE",
				esc["perdidas"].size() == 1 and abs(float(esc["perdidas"][0]["time"]) - (t0 + gracia)) < 0.05,
				str(esc["perdidas"]));
		esc["tm"].setWeatherManager(null);
		gm.setWeatherManager(null);
		_limpiar([esc["tm"], gm, esc["bag"], pm, wm]);

	# --- (4) La condición 3 del punto muerto no depende del clima: sobre el MISMO mapa,
	# hasBuildableCell() (regla estricta) y canPlaceFactory() de las 160 casillas dan lo mismo
	# sin manager, con manager sin eventos y con los cuatro climas cubriendo el mapa entero.
	var pm4 = _new_pm();
	var tm4 = _tilemap_con_suelo(_clima_mapa_16x10());
	tm4.setPollutionManager(pm4);
	tm4.cell_types = {};
	tm4.tile_type_data = file_data["TileTypes"];
	var wm4 = _new_wm(file_data);
	wm4.log_events = false;
	var ocupante = _new_factory("WoodCutter", Vector2i(7, 4));
	var mapa = _clima_mapa_16x10();
	for c in mapa:
		pm4.addPollution(20.0, c);
	# Cuatro mapas: saturado, con una casilla libre, con esa casilla ocupada y con ella tóxica.
	var casos = [
		["saturado", func(): pass, [], false],
		["una casilla limpia", func(): pm4.removePollution(20.0, Vector2i(7, 4)), [], true],
		["la limpia, ocupada", func(): pass, [ocupante], false],
		["la limpia, tóxica", func(): tm4.cell_types[Vector2i(7, 4)] = "toxic", [], false],
	];
	var modos = ["sin_manager", "sin_eventos", "cuatro_climas"];
	for caso in casos:
		caso[1].call();
		var respuestas = [];
		for modo in modos:
			wm4.active.clear();
			tm4.setWeatherManager(null if modo == "sin_manager" else wm4);
			if modo == "cuatro_climas":
				for id in ["drought", "rain", "storm", "wind"]:
					wm4.startEvent(id, todo);
			var celdas = [];
			for c in mapa:
				celdas.append(tm4.canPlaceFactory(c, caso[2]));
			respuestas.append([tm4.hasBuildableCell(caso[2]), celdas]);
		_check("mapa %s: hasBuildableCell() == %s sin clima (precondición)" % [caso[0], str(caso[3])],
			respuestas[0][0] == caso[3], str(respuestas[0][0]));
		_check("mapa %s: mismo hasBuildableCell() y mismas 160 canPlaceFactory() con y sin clima" % caso[0],
			respuestas[0] == respuestas[1] and respuestas[0] == respuestas[2]);
	tm4.setWeatherManager(null);
	_limpiar([tm4, pm4, wm4, ocupante]);

	# --- (5) Sin eventos activos, un tramo de mundo con TODO (productoras que se ahogan, una sin
	# insumo, un Reforester, un lago, un foco que contagia) da EXACTAMENTE lo mismo sin manager,
	# con el manager hermano sin eventos, y con eventos que ya se retiraron antes del tramo.
	var mundo = {};
	for c in _vecindario(Vector2i(10, 6)):
		mundo[c] = 10.0;
	mundo[Vector2i(7, 8)] = 13.0;
	mundo[Vector2i(12, 2)] = 6.0;
	var fabricas = [
		["WoodCutter", Vector2i(3, 3), null, "wood", 2.0, "production", 0, null],
		["WoodCutter", Vector2i(4, 3), null, "wood", 2.0, "production", 0, null],
		["WoodProcessing", Vector2i(3, 5), ["wood"], "plank", 2.0, "production", 0, null],
		["Reforester", Vector2i(10, 6), null, null, -4.0, "restoration", 0, null],
	];
	var tramos = [];
	for op in [{ "wm": false }, { "wm": true }, { "wm": true, "caducar": true,
			"eventos": [["drought", todo], ["rain", todo], ["storm", todo], ["wind", todo]] }]:
		op["suciedad"] = mundo;
		op["lagos"] = [Vector2i(13, 2)];
		op["fabricas"] = fabricas;
		op["segundos"] = 30.0;
		tramos.append(_clima_m6_tramo(file_data, op));
	var a = tramos[0];
	_check("tramo de mundo: los managers son los del tramo, y los eventos caducados ya no están (precondición)",
		a["primero"] and tramos[1]["primero"] and tramos[1]["hermano"] and tramos[2]["primero"]
		and tramos[2]["hermano"] and tramos[2]["activos"] == 0);
	var razones_a = {};
	for k in a["razones"].size():
		for rz in a["razones"][k]:
			razones_a[rz] = true;
	_check("el tramo ejercita ahogo, insumo, producción y limpieza (precondición)",
		razones_a.has("choke") and razones_a.has("input") and razones_a.has("")
		and not a["producidos"].is_empty() and a["limpiado"][3][0] > 0.0, str(razones_a.keys()));
	for i in [1, 2]:
		var b = tramos[i];
		var nombre = "con el manager sin eventos" if i == 1 else "con eventos ya retirados";
		_check("%s: la suciedad de cada casilla es idéntica a sin manager" % nombre, b["celdas"] == a["celdas"]);
		_check("%s: total, pico, producción, razones y ahogos idénticos" % nombre,
			b["total"] == a["total"] and b["peak"] == a["peak"] and b["producidos"] == a["producidos"]
			and b["razones"] == a["razones"] and b["chokes"] == a["chokes"] and b["limpiado"] == a["limpiado"]);

	# --- (6) Guardia: la constante de la derrota que ningún hito del clima cita. Las otras dos
	# (contagion_rate 0,12, contagion_pollution 12,5) las fija M4 §7 y, tras un tramo con
	# viento, el §2 de arriba.
	_check("DEADLOCK_GRACE sigue en 25 s (provisional, sin re-medir con clima)", _near(gracia, 25.0),
		"%f" % gracia);

# ---------- Serialización M1: la captura ----------

# ¿Es `v` JSON puro? Solo nulos, booleanos, números, Strings, Arrays y Dictionaries de claves
# String. Hace falta aparte del round-trip porque `JSON.stringify()` NO falla con un Vector2i:
# lo escribe como el texto "(3, 4)" en silencio, y lo mismo con un nodo o un Object. Y un int
# por encima de 2^53 tampoco cuenta como puro: JSON lo devuelve como double y pierde bits, que
# es justo lo que le pasaría al estado del RNG del clima guardado como número.
func _json_puro(v) -> bool:
	match typeof(v):
		TYPE_NIL, TYPE_BOOL, TYPE_FLOAT, TYPE_STRING:
			return true;
		TYPE_INT:
			return absi(v) <= 9007199254740992;
		TYPE_ARRAY:
			for x in v:
				if not _json_puro(x):
					return false;
			return true;
		TYPE_DICTIONARY:
			for k in v:
				if typeof(k) != TYPE_STRING or not _json_puro(v[k]):
					return false;
			return true;
	return false;

# Igualdad de dos valores JSON tras una ida y vuelta. Dos concesiones, las dos de Godot y no del
# snapshot: `parse_string()` devuelve TODO número como float (40 vuelve como 40.0, y
# `{"a": 1} == {"a": 1.0}` es false en GDScript), y `stringify()` escribe los floats con 15 cifras
# significativas. Por eso los números se comparan por valor con tolerancia relativa 1e-12, y todo
# lo demás —claves, Strings, nulos, longitudes— exacto.
func _json_igual(a, b) -> bool:
	var ta = typeof(a);
	var tb = typeof(b);
	if (ta == TYPE_INT or ta == TYPE_FLOAT) and (tb == TYPE_INT or tb == TYPE_FLOAT):
		return abs(float(a) - float(b)) <= 1e-12 * max(1.0, abs(float(a)));
	if ta != tb:
		return false;
	match ta:
		TYPE_DICTIONARY:
			if a.size() != b.size():
				return false;
			for k in a:
				if not b.has(k) or not _json_igual(a[k], b[k]):
					return false;
			return true;
		TYPE_ARRAY:
			if a.size() != b.size():
				return false;
			for i in a.size():
				if not _json_igual(a[i], b[i]):
					return false;
			return true;
	return a == b;

func _claves_ordenadas(d) -> Array:
	var ks = Array(d.keys());
	ks.sort();
	return ks;

func _test_serializacion_m1(file_data):
	print("Serialización M1 — la captura de la run");
	var run_save = load("res://managers/runSave.gd");

	# --- (1) La conversión de celdas, en los dos sentidos y con negativos: las direcciones de
	# las cintas son Vector2i(-1, 0) y salen por la misma función.
	var ida_vuelta = true;
	for c in [Vector2i(0, 0), Vector2i(3, 4), Vector2i(-1, 0), Vector2i(12, -7)]:
		if run_save.parse_cell(run_save.cell_key(c)) != c:
			ida_vuelta = false;
	_check("runSave: cell_key/parse_cell es una ida y vuelta exacta, negativos incluidos",
		ida_vuelta and run_save.cell_key(Vector2i(3, 4)) == "3,4");
	# Y el motivo de que exista: stringify no protesta ante un Vector2i, lo convierte en texto.
	var traicion = JSON.parse_string(JSON.stringify({"c": Vector2i(3, 4)}));
	_check("JSON.stringify convierte un Vector2i en texto en silencio: el round-trip solo no basta",
		typeof(traicion["c"]) == TYPE_STRING and not _json_puro({"c": Vector2i(3, 4)})
		and not _json_puro({"n": Node}) and not _json_puro({Vector2i(1, 1): 1.0}),
		str(traicion));

	# --- (2) Una run de verdad (_start_game()) con todo lo que M1 pide. El JSON se recorta a
	# forest_01 para que el mapa no dependa de lo que el save de David tenga desbloqueado, y el
	# clima nace apagado: el evento se arranca a mano.
	var fd = file_data.duplicate(true);
	fd["Maps"] = [_mapa_por_id(file_data, "forest_01")];
	var main = _main_para_run();
	main.fileData = fd;
	main.weather_enabled = false;
	main._start_game("standard");
	main.weatherManager.log_events = false;
	var tm = main.get_node("TileMap");
	var bolsa = main.get_node("Player").get_node("Bag");
	_check("la run arranca en forest_01 con el paquete standard (precondición)",
		main._run_map_id == "forest_01" and main._run_package_id == "standard",
		"%s / %s" % [main._run_map_id, main._run_package_id]);

	# Cadena: cortadora → cinta → serrería, por el camino del jugador.
	main._on_factory_chosen("WoodCutter", Vector2i(7, 6));
	main._on_factory_chosen("WoodProcessing", Vector2i(10, 6));
	var tendida = main.beltNetwork.place_drag(Vector2i(7, 6), Vector2i(10, 6), main.factoryArray);
	var cortadora = main._get_factory_at_cell(Vector2i(7, 6));
	var sierra = main._get_factory_at_cell(Vector2i(10, 6));
	_check("cadena montada: dos factorías nuevas y dos casillas de cinta entre ellas (precondición)",
		cortadora != null and sierra != null and tendida.size() == 2 and main.factoryArray.size() == 3,
		"cinta %d, factorías %d" % [tendida.size(), main.factoryArray.size()]);
	# Estado que build() no reproduciría, para que la captura tenga qué llevarse.
	cortadora.timer = 7;
	cortadora.production_debt = 0.35;
	sierra.input_buffer = {"wood": 3};
	sierra.output_buffer = 2;
	var almacen = main._get_factory_at_cell(Vector2i(13, 8));
	almacen.emit_route_cell = Vector2i(12, 8);
	main.gameManager.run_time = 12.75;
	main.get_node("Player").applySpeedBoost("WoodCutter", 1);

	# Una `toxic` por el downside de verdad de una carta (casilla al azar entre las libres).
	main._apply_map_downside({"cells": 1, "type": "toxic"});
	var toxicas = _celdas_de_tipo(tm, "toxic");
	# Y un clima vivo.
	var ev = main.weatherManager.startEvent("rain", Rect2i(2, 3, 3, 2));
	_check("una toxic degradada y un clima activo (precondición)",
		toxicas.size() == 1 and ev != null and main.weatherManager.active.size() == 1);

	# --- (3) Primera captura, SIN pantalla de cartas: la oferta pendiente es null.
	var snap1 = main._capture_run();
	_check("sin pantalla de cartas abierta, pending_offer es null", snap1.get("pending_offer", "falta") == null);
	_check("antes de la ruina, cells es exactamente la toxic degradada",
		toxicas.size() == 1 and snap1["cells"] == {run_save.cell_key(toxicas[0]): "toxic"}, str(snap1["cells"]));

	# --- (4) La ruina, consumida por el camino del jugador: construir encima regala una carta y
	# abre la pantalla —que es, de paso, la oferta pendiente que hay que capturar—.
	main._on_factory_chosen("WoodCutter", Vector2i(12, 6));
	var pantalla = main.get_node_or_null("UpgradeScreen");
	_check("construir sobre la ruina la consume y abre la carta regalada (precondición)",
		not tm.cell_types.has(Vector2i(12, 6)) and pantalla != null and main._offer_ids.size() == 1);
	var snap = main._capture_run();

	# --- (5) Todos los bloques de la tabla, con todas sus claves.
	_check("el snapshot tiene todos los bloques del plan y ninguno más",
		_claves_ordenadas(snap) == ["bag", "belts", "cells", "factories", "game", "map_id",
			"package_id", "params_hash", "pending_offer", "player", "pollution",
			"prev_checkpoint_t", "resumed_from", "version", "weather"],
		str(_claves_ordenadas(snap)));
	_check("cabecera: versión, huella del balance, mapa, paquete y run_id de la run viva",
		snap["version"] == run_save.VERSION and String(snap["params_hash"]).length() == 12
		and snap["map_id"] == "forest_01" and snap["package_id"] == "standard"
		and snap["resumed_from"] == main.analytics.run_id(),
		"%s %s" % [snap["params_hash"], snap["resumed_from"]]);
	_check("bag: bolsa, workers y reserva",
		_claves_ordenadas(snap["bag"]) == ["bag", "reserved", "workers_assigned", "workers_total"]
		and int(snap["bag"]["bag"]["wood"]["quantity"]) == bolsa.getQuantity("wood"));
	_check("player: factorías disponibles y modificadores acumulados",
		_claves_ordenadas(snap["player"]) == ["availableFactories", "outputModifiers", "speedModifiers"]
		and int(snap["player"]["speedModifiers"].get("WoodCutter", 0)) == main.get_node("Player").speedModifiers["WoodCutter"]);
	_check("pollution: total, pico y la suciedad por casilla con claves \"x,y\"",
		_claves_ordenadas(snap["pollution"]) == ["peak_pollution", "pollution_per_cell", "total_pollution"]
		and snap["pollution"]["pollution_per_cell"].size() == main.pollutionManager.pollution_per_cell.size()
		and snap["pollution"]["pollution_per_cell"].has(run_save.cell_key(toxicas[0])));
	_check("game: las once variables de la tabla, y ninguna de la ventana de punto muerto",
		_claves_ordenadas(snap["game"]) == ["active", "current_checkpoint_index", "last_capacity_sample",
			"last_checkpoint_time", "last_segment_rate", "last_tier", "production_done",
			"run_time", "segment_capacity_area", "segment_capacity_time", "segment_start_stock"]
		and _near(snap["game"]["run_time"], 12.75), str(_claves_ordenadas(snap["game"])));
	var clima = snap["weather"];
	_check("weather: el evento vivo con su zona como [x,y,w,h], la tirada y el RNG",
		_claves_ordenadas(clima) == ["_roll_timer", "active", "rng_state"] and clima["active"].size() == 1
		and clima["active"][0]["id"] == "rain" and clima["active"][0]["rect"] == [2, 3, 3, 2]
		and _near(clima["active"][0]["remaining"], ev.remaining), str(clima["active"]));
	_check("el estado del RNG del clima va como String y vuelve exacto con int()",
		typeof(clima["rng_state"]) == TYPE_STRING and int(clima["rng_state"]) == main.weatherManager._rng.state);
	var celdas_cinta = [];
	for tramo in snap["belts"]:
		celdas_cinta.append(tramo["cell"]);
	_check("belts: los dos tramos de la cadena, con celda y direcciones en \"x,y\"",
		celdas_cinta == ["8,6", "9,6"] and _claves_ordenadas(snap["belts"][0]) == ["cell", "dir_in", "dir_out", "filter"]
		and snap["belts"][0]["dir_in"] == "-1,0" and snap["belts"][0]["dir_out"] == "1,0", str(snap["belts"]));
	var por_celda = {};
	for f in snap["factories"]:
		por_celda[f["cell"]] = f;
	_check("factories: las cuatro —almacén, cadena y la de la ruina— con los dieciséis campos",
		snap["factories"].size() == 4 and _claves_ordenadas(snap["factories"][0]) == ["cell", "cost_paid",
			"emit_route_cell", "input_buffer", "outputAmount", "output_buffer", "pollutionAmount",
			"production", "production_debt", "synergy_output_bonus", "synergy_pollution_mult",
			"synergy_tick_bonus", "tickTimer", "timer", "type", "workers_assigned"]
		and por_celda.has("13,8") and por_celda.has("7,6") and por_celda.has("10,6") and por_celda.has("12,6"),
		str(por_celda.keys()));
	_check("factories: el contador `timer`, la deuda, los búferes y el recibo de lo pagado",
		int(por_celda["7,6"]["timer"]) == 7 and _near(por_celda["7,6"]["production_debt"], 0.35)
		and por_celda["7,6"]["cost_paid"] == cortadora.cost_paid and not cortadora.cost_paid.is_empty()
		and por_celda["10,6"]["input_buffer"] == {"wood": 3} and por_celda["10,6"]["output_buffer"] == 2
		and por_celda["10,6"]["production"] == "plank");
	_check("factories: emit_route_cell en \"x,y\" o null",
		por_celda["13,8"]["emit_route_cell"] == "12,8" and por_celda["7,6"]["emit_route_cell"] == null);

	# --- (6) Las mutaciones del mapa, exactamente esas dos: la toxic nueva y la ruina que ya no está.
	_check("cells es el diff exacto: la toxic degradada y la ruina consumida (null)",
		snap["cells"] == {run_save.cell_key(toxicas[0]): "toxic", "12,6": null}, str(snap["cells"]));
	# --- (7) La oferta pendiente, tal cual se mostró.
	_check("pending_offer: la carta de la ruina, con su fuente y sus ids",
		snap["pending_offer"] is Dictionary and snap["pending_offer"]["source"] == "ruins"
		and snap["pending_offer"]["ids"] == main._offer_ids, str(snap["pending_offer"]));

	# --- (8) Lo que hace que se pueda escribir a disco: JSON puro y una ida y vuelta fiel.
	_check("el snapshot es JSON puro: ni un Vector2i, ni un nodo, ni un Object, ni un int de 64 bits",
		_json_puro(snap));
	var vuelta = JSON.parse_string(JSON.stringify(snap));
	_check("JSON.stringify → JSON.parse_string devuelve el mismo dict (números por valor)",
		vuelta is Dictionary and _json_igual(snap, vuelta));
	# Y el comparador no es complaciente: una sola mutación lo pone en rojo.
	var trucada = JSON.parse_string(JSON.stringify(snap));
	trucada["cells"]["12,6"] = "ruins";
	_check("y el comparador ve un solo valor cambiado", not _json_igual(snap, trucada));

	# El árbol quedó pausado por la pantalla de la ruina: se despausa para el resto de la suite.
	paused = false;
	_limpiar([main.placer, main.mapLoader, main]);

# ---------- Serialización M2: la restauración en memoria ----------

# El snapshot sin `resumed_from`: es el `run_id` de la run capturada, y la reanudada abre uno
# nuevo a propósito (la analítica la enlaza en M4), así que es lo único que NO debe coincidir.
func _sin_run_id(snap) -> Dictionary:
	var copia = snap.duplicate(true);
	copia.erase("resumed_from");
	return copia;

# Un Main de verdad, en el árbol y con el mismo JSON recortado, listo para _continue_game().
func _main_para_reanudar(fd):
	var main = _main_para_run();
	main.fileData = fd;
	main.weather_enabled = false;
	return main;

func _cuenta_tipo(main, tipo) -> int:
	var n = 0;
	for f in main.factoryArray:
		if f.type == tipo:
			n += 1;
	return n;

func _test_serializacion_m2(file_data):
	print("Serialización M2 — la restauración en memoria");
	var fd = file_data.duplicate(true);
	fd["Maps"] = [_mapa_por_id(file_data, "forest_01")];

	# --- (1) La run original: la de M1 —cadena, cinta, estado que build() no reproduciría, una
	# toxic degradada, la ruina consumida y un clima vivo— pero con la carta de la ruina YA
	# elegida, para que esta primera captura no tenga oferta pendiente.
	var a = _main_para_reanudar(fd);
	a._start_game("standard");
	a.weatherManager.log_events = false;
	a._on_factory_chosen("WoodCutter", Vector2i(7, 6));
	a._on_factory_chosen("WoodProcessing", Vector2i(10, 6));
	a.beltNetwork.place_drag(Vector2i(7, 6), Vector2i(10, 6), a.factoryArray);
	a.beltNetwork.set_belt_filter(Vector2i(9, 6), "wood");
	var cortadora = a._get_factory_at_cell(Vector2i(7, 6));
	var sierra = a._get_factory_at_cell(Vector2i(10, 6));
	cortadora.timer = 7;
	cortadora.production_debt = 0.35;
	sierra.input_buffer = {"wood": 3};
	sierra.output_buffer = 2;
	a._get_factory_at_cell(Vector2i(13, 8)).emit_route_cell = Vector2i(12, 8);
	a.gameManager.run_time = 12.75;
	a._prev_checkpoint_t = 3.5;
	a.get_node("Player").applySpeedBoost("WoodCutter", 1);
	a._apply_map_downside({"cells": 1, "type": "toxic"});
	a.weatherManager.startEvent("rain", Rect2i(2, 3, 3, 2));
	a._on_factory_chosen("WoodCutter", Vector2i(12, 6));
	var ruina_ids = a._offer_ids.duplicate();
	# Por el botón de verdad: la pantalla emite y se libera ella sola. Se saca además del árbol
	# porque su queue_free() es diferido y seguiría ocupando el nombre «UpgradeScreen»: la del
	# checkpoint de (5) nacería renombrada y la captura no la vería.
	var pantalla_ruina = a.get_node_or_null("UpgradeScreen");
	if pantalla_ruina != null and not ruina_ids.is_empty():
		pantalla_ruina._on_upgrade_chosen(ruina_ids[0]);
		a.remove_child(pantalla_ruina);
	# Un reparto de workers que build() NO reproduciría: se le quita el suyo a la cortadora y se
	# deja libre, que es lo que haría el panel. Al reconstruir, build() se lo volvería a dar por
	# orden de llegada; la restauración tiene que dejarla sin él.
	var bolsa_a = a.get_node("Player").get_node("Bag");
	if cortadora.workers_assigned > 0:
		bolsa_a.unassignWorkers(cortadora.workers_assigned);
		cortadora.workers_assigned = 0;
	var snap = a._capture_run();
	_check("la run original lleva cadena, cinta filtrada, toxic, ruina consumida y clima, sin oferta (precondición)",
		a.factoryArray.size() == 4 and snap["belts"].size() == 2 and snap["cells"].size() == 2
		and snap["cells"].get("12,6", "falta") == null and snap["weather"]["active"].size() == 1
		and snap["pending_offer"] == null and ruina_ids.size() == 1,
		"factorías %d, cells %s, oferta %s" % [a.factoryArray.size(), str(snap["cells"]), str(snap["pending_offer"])]);

	# --- (2) La ida y vuelta EN MEMORIA, sin pasar por JSON: capturar → _continue_game() en un
	# Main nuevo → capturar. Aquí la igualdad tiene que ser `==` exacto, tipos incluidos (en
	# GDScript `{"a": 1} == {"a": 1.0}` es false), así que esto prueba además que snapshot() y
	# restore() fijan el mismo tipo a cada campo.
	var b = _main_para_reanudar(fd);
	var reanudada = b._continue_game(snap);
	b.weatherManager.log_events = false;
	var snap_b = b._capture_run();
	_check("_continue_game() reanuda (devuelve true)", reanudada);
	_check("ida y vuelta en memoria: la captura de la run restaurada es IDÉNTICA (==) a la original",
		_sin_run_id(snap) == _sin_run_id(snap_b), _primera_diferencia(_sin_run_id(snap), _sin_run_id(snap_b)));
	_check("la reanudada es una run NUEVA para la analítica (otro run_id)",
		b.analytics.has_run() and snap_b["resumed_from"] != snap["resumed_from"]);

	# --- (3) Un almacén, no dos: apply_map() sin storage_ctx no construye el suyo.
	_check("hay UN almacén y no dos, y tantas factorías como en el snapshot",
		_cuenta_tipo(b, "Storage") == 1 and b.factoryArray.size() == snap["factories"].size(),
		"almacenes %d, factorías %d" % [_cuenta_tipo(b, "Storage"), b.factoryArray.size()]);
	var hijas = 0;
	for hijo in b.get_children():
		if hijo.has_signal("resource_produced"):
			hijas += 1;
	_check("ni una factoría huérfana colgando de Main fuera del factoryArray", hijas == b.factoryArray.size(),
		"%d hijas, %d en el array" % [hijas, b.factoryArray.size()]);
	var conectadas = true;
	for f in b.factoryArray:
		if f.resource_produced.get_connections().size() != 1:
			conectadas = false;
	_check("cada factoría restaurada —almacén incluido— tiene su resource_produced conectado una vez", conectadas);
	_check("la contaminación de partida no se suma a la guardada (restore() va después de apply_map())",
		b.pollutionManager.total_pollution == a.pollutionManager.total_pollution
		and b.pollutionManager.pollution_per_cell.size() == a.pollutionManager.pollution_per_cell.size());
	_check("las mutaciones del mapa vuelven: la toxic teñida y la ruina sin tipo",
		b.get_node("TileMap").cell_types == a.get_node("TileMap").cell_types);
	_check("los workers son los guardados, no los que build() repartió por orden de llegada",
		b.get_node("Player/Bag").workers_assigned == bolsa_a.workers_assigned
		and b._get_factory_at_cell(Vector2i(7, 6)).workers_assigned == cortadora.workers_assigned);
	_check("el clima sigue: mismo evento, misma cuenta atrás y el RNG en la misma tirada",
		b.weatherManager.active.size() == 1 and b.weatherManager.active[0].rect == Rect2i(2, 3, 3, 2)
		and b.weatherManager._rng.state == a.weatherManager._rng.state);

	# --- (4) La misma ida y vuelta pasando por JSON, que es lo que M3 leerá del disco: todo número
	# vuelve como float, así que esto prueba los int() de cada restore(). Se compara con la
	# tolerancia de M1 (el JSON de Godot pierde hasta 1 ulp), y los tipos se miran aparte.
	var texto = JSON.stringify(snap, "", true, true);
	var c = _main_para_reanudar(fd);
	var desde_json = c._continue_game(JSON.parse_string(texto));
	c.weatherManager.log_events = false;
	var snap_c = c._capture_run();
	_check("ida y vuelta por JSON: la captura de la restaurada coincide con la original (números por valor)",
		desde_json and _json_igual(_sin_run_id(snap), _sin_run_id(snap_c)),
		_primera_diferencia(_sin_run_id(snap), _sin_run_id(snap_c)));
	var cortadora_c = c._get_factory_at_cell(Vector2i(7, 6));
	_check("desde JSON los contadores vuelven como int, no como float",
		typeof(cortadora_c.timer) == TYPE_INT and typeof(cortadora_c.workers_assigned) == TYPE_INT
		and typeof(c._get_factory_at_cell(Vector2i(10, 6)).output_buffer) == TYPE_INT
		and typeof(c._get_factory_at_cell(Vector2i(10, 6)).input_buffer["wood"]) == TYPE_INT
		and typeof(c.get_node("Player/Bag").bag["wood"]["quantity"]) == TYPE_INT
		and typeof(c.gameManager.current_checkpoint_index) == TYPE_INT
		and typeof(c.get_node("Player").speedModifiers["WoodCutter"]) == TYPE_INT);
	_check("desde JSON el estado del RNG del clima vuelve exacto (64 bits, vía String)",
		c.weatherManager._rng.state == a.weatherManager._rng.state);
	_check("desde JSON la celda de emisión del almacén vuelve como Vector2i",
		c._get_factory_at_cell(Vector2i(13, 8)).emit_route_cell == Vector2i(12, 8));

	# --- (5) La restaurada cierra el siguiente checkpoint IGUAL que la original: misma bolsa,
	# mismo update() y el mismo resultado —tier, cociente del tramo, cobro, índice—. Las cartas
	# ofrecidas se barajan con el RNG global, así que de la oferta solo se compara la forma.
	for m in [a, b]:
		var bolsa = m.get_node("Player").get_node("Bag");
		for material in ["wood", "plank", "stone"]:
			bolsa.addToBag(material, 200);
		m.gameManager.update(bolsa, m.pollutionManager);
	var tras_a = a._capture_run();
	var tras_b = b._capture_run();
	_check("las dos cierran el checkpoint 1 (precondición)",
		a.gameManager.current_checkpoint_index == 1 and b.gameManager.current_checkpoint_index == 1,
		"%d / %d" % [a.gameManager.current_checkpoint_index, b.gameManager.current_checkpoint_index]);
	_check("y lo cierran igual: gameManager, bolsa, Player y factorías idénticos tras el cierre",
		tras_a["game"] == tras_b["game"] and tras_a["bag"] == tras_b["bag"]
		and tras_a["player"] == tras_b["player"] and tras_a["factories"] == tras_b["factories"],
		_primera_diferencia(tras_a["game"], tras_b["game"]));
	_check("mismo tier y mismo cociente del tramo",
		a.gameManager.last_tier == b.gameManager.last_tier
		and a.gameManager.last_segment_rate == b.gameManager.last_segment_rate);

	# --- (6) Una captura CON oferta pendiente reabre UpgradeScreen con los mismos ids. La de la
	# original es la del checkpoint que acaba de cerrar.
	var oferta = tras_a["pending_offer"];
	_check("la original tiene la oferta del checkpoint en pantalla (precondición)",
		oferta is Dictionary and oferta["source"] == "checkpoint" and oferta["ids"].size() > 0, str(oferta));
	var d = _main_para_reanudar(fd);
	d._continue_game(tras_a);
	d.weatherManager.log_events = false;
	var pantalla = d.get_node_or_null("UpgradeScreen");
	_check("reanudar con oferta pendiente reabre UpgradeScreen con los MISMOS ids, sin re-barajar",
		pantalla != null and d._offer_ids == oferta["ids"] and d._offer_source == "checkpoint",
		"%s vs %s" % [str(d._offer_ids), str(oferta["ids"])]);
	var textos = _textos_de(pantalla) if pantalla != null else [];
	var nombres = true;
	for id in oferta["ids"]:
		if not textos.has(String(fd["Upgrades"][id].get("name", id))):
			nombres = false;
	_check("y la pantalla pinta esas cartas", nombres, str(textos));
	_check("con el árbol pausado y el gameManager parado, como la original",
		paused and d.gameManager.active == false and a.gameManager.active == false);
	_check("y su captura es idéntica a la de la original, oferta incluida",
		_sin_run_id(tras_a) == _sin_run_id(d._capture_run()),
		_primera_diferencia(_sin_run_id(tras_a), _sin_run_id(d._capture_run())));
	# --- (6b) El HUD de detrás de la oferta ya está pintado. Con la oferta pendiente el árbol se
	# pausa antes de que _process() corra un solo frame, y sin _paint_hud() quedaba el texto de
	# relleno de Main.tscn («Objective: 2 wood»): visto con ventana, no con la suite. Aquí se
	# simula la ventana —render_enabled y los dos Label— porque en headless no se pinta nada.
	var h = _main_para_reanudar(fd);
	h.render_enabled = true;
	for nombre in ["Label", "Objective"]:
		var l = Label.new();
		l.name = nombre;
		l.text = "relleno";
		h.add_child(l);
	h._continue_game(tras_a);
	h.weatherManager.log_events = false;
	var hud_bag = h.get_node("Player").get_node("Bag");
	_check("reanudar con oferta pendiente deja el HUD pintado con la run, no con el relleno",
		h.get_node("Label").text == h._buildResourceText(hud_bag)
			and h.get_node("Objective").text == h.gameManager.getObjectiveText(hud_bag, h.pollutionManager)
			and h.get_node("Objective").text != "relleno",
		"%s | %s" % [h.get_node("Objective").text, h.get_node("Label").text.left(40)]);
	# Se apaga para que no siga pintando con los frames que le queden a la suite, como los otros
	# Main de este bloque, que tampoco se liberan.
	h.render_enabled = false;
	# Elegir en la reanudada desbloquea la run como en cualquier otra.
	d._on_upgrade_chosen(oferta["ids"][0]);
	_check("elegir una carta en la reanudada despausa y reactiva el gameManager",
		not paused and d.gameManager.active);

	paused = false;
	for m in [a, b, c, d]:
		_limpiar([m.placer, m.mapLoader, m]);

# La primera ruta en la que dos valores difieren, para que un rojo de la ida y vuelta diga QUÉ
# campo falta en snapshot() o restore() en vez de solo «no es igual». Estricto con los tipos,
# como el `==` de GDScript.
func _primera_diferencia(x, y, ruta = "") -> String:
	if typeof(x) != typeof(y):
		return "%s: %s (%s) vs %s (%s)" % [ruta, str(x), type_string(typeof(x)), str(y), type_string(typeof(y))];
	if x is Dictionary:
		for k in x:
			if not y.has(k):
				return "%s/%s: falta en la segunda" % [ruta, str(k)];
			var r = _primera_diferencia(x[k], y[k], "%s/%s" % [ruta, str(k)]);
			if r != "":
				return r;
		for k in y:
			if not x.has(k):
				return "%s/%s: sobra en la segunda" % [ruta, str(k)];
		return "";
	if x is Array:
		if x.size() != y.size():
			return "%s: longitud %d vs %d" % [ruta, x.size(), y.size()];
		for i in x.size():
			var r = _primera_diferencia(x[i], y[i], "%s[%d]" % [ruta, i]);
			if r != "":
				return r;
		return "";
	return "" if x == y else "%s: %s vs %s" % [ruta, str(x), str(y)];

# ---------- Serialización M3: el fichero y su ciclo de vida ----------

# Si existe y con qué contenido, como _huella_del_save() pero para cualquier ruta.
func _huella_de(ruta):
	if not FileAccess.file_exists(ruta):
		return "<no existe>";
	return FileAccess.get_file_as_string(ruta);

func _escribe_texto(ruta, texto):
	var f = FileAccess.open(ruta, FileAccess.WRITE);
	f.store_string(texto);
	f.close();

func _test_serializacion_m3(file_data):
	print("Serialización M3 — el fichero y su ciclo de vida");
	var run_save = load("res://managers/runSave.gd");
	var fd = file_data.duplicate(true);
	fd["Maps"] = [_mapa_por_id(file_data, "forest_01")];

	# --- (1) La redirección: todo Main de la suite —por cualquiera de sus tres montajes— apunta
	# al fichero de pruebas, y no al real.
	var suelto = _new_main_de_prueba(file_data);
	var en_arbol = _new_main_en_arbol(file_data);
	var a = _main_para_reanudar(fd);
	_check("todo Main de la suite escribe en user://test_run.json, nunca en RUN_PATH",
		suelto.runSave.path == "user://test_run.json" and en_arbol.runSave.path == "user://test_run.json"
		and a.runSave.path == "user://test_run.json" and run_save.RUN_PATH == "user://run.json",
		"%s / %s / %s" % [suelto.runSave.path, en_arbol.runSave.path, a.runSave.path]);
	_limpiar([suelto, en_arbol]);
	var rs = a.runSave;
	rs.clear();
	var ruta = rs.path;

	# --- (2) Escribir y leer: una run de verdad con cadena, cinta y una toxic, por disco.
	a._start_game("standard");
	a.weatherManager.log_events = false;
	a._on_factory_chosen("WoodCutter", Vector2i(7, 6));
	a._on_factory_chosen("WoodProcessing", Vector2i(10, 6));
	a.beltNetwork.place_drag(Vector2i(7, 6), Vector2i(10, 6), a.factoryArray);
	a._apply_map_downside({"cells": 1, "type": "toxic"});
	a.gameManager.run_time = 12.75;
	var snap = a._capture_run();
	var huella_params = a._params_hash;
	_check("sin fichero: read_valid() da {} y exists_valid() false",
		rs.read_valid(huella_params).is_empty() and not rs.exists_valid(huella_params));
	_check("write() escribe y no deja el .tmp a la vista",
		rs.write(snap) and FileAccess.file_exists(ruta) and not FileAccess.file_exists(ruta + ".tmp"));
	_check("y escribir encima de un save que ya existe también vale (el rename pisa)",
		rs.write(snap) and FileAccess.file_exists(ruta) and not FileAccess.file_exists(ruta + ".tmp"));
	_check("exists_valid() lo reconoce", rs.exists_valid(huella_params));
	var leido = rs.read_valid(huella_params);
	_check("read_valid() devuelve el snapshot escrito (números por valor)",
		_json_igual(snap, leido), _primera_diferencia(snap, leido));
	_check("sin reordenar claves: la bolsa vuelve en el orden del HUD",
		not leido.is_empty() and Array(leido["bag"]["bag"].keys()) == Array(snap["bag"]["bag"].keys()),
		"%s vs %s" % [str(snap["bag"]["bag"].keys()), str(leido["bag"]["bag"].keys()) if not leido.is_empty() else "{}"]);
	_check("con precisión completa: el run_time vuelve exacto", not leido.is_empty()
		and float(leido["game"]["run_time"]) == float(snap["game"]["run_time"]));
	_check("un save válido NO se borra al leerlo: lo borra quien lo restaura", FileAccess.file_exists(ruta));

	# --- (3) Los saves que no valen: se tiran sin petar. exists_valid() solo mira; read_valid() borra.
	var texto = JSON.stringify(snap, "", false, true);
	var otra_version = snap.duplicate(true);
	otra_version["version"] = 0;
	var otro_balance = snap.duplicate(true);
	otro_balance["params_hash"] = "otro" + huella_params;
	var malos = {
		"version 0": JSON.stringify(otra_version),
		"otro params_hash": JSON.stringify(otro_balance),
		"JSON truncado": texto.substr(0, texto.length() / 2),
		"JSON que no es un objeto": "[1, 2, 3]",
		"sin version": "{\"params_hash\": \"%s\"}" % huella_params,
	};
	for caso in malos:
		_escribe_texto(ruta, malos[caso]);
		var visto = rs.exists_valid(huella_params);
		var sigue = FileAccess.file_exists(ruta);
		var r = rs.read_valid(huella_params);
		_check("%s: exists_valid() false sin borrar, read_valid() {} y BORRA" % caso,
			not visto and sigue and r.is_empty() and not FileAccess.file_exists(ruta),
			"visto %s, seguía %s, leído %d claves, existe %s" % [visto, sigue, r.size(), FileAccess.file_exists(ruta)]);

	# --- (4) Ganar, perder y reiniciar borran run.json y NI UN BYTE de save.json. El saveManager
	# es uno que no escribe, para no tocar la meta-progresión real; si el borrado de run.json
	# arrastrara a save.json por otro camino, la huella lo vería.
	var sm = SaveSinDisco.new();
	a.saveManager = sm;
	var stats = {"time": 125.0, "checkpoints": 2, "factories_placed": 0, "final_pollution": 10};
	var antes = _huella_del_save();
	rs.write(snap);
	a._on_run_won(stats.duplicate());
	_check("ganar borra run.json", not FileAccess.file_exists(ruta));
	_check("y deja save.json idéntico", _huella_del_save() == antes, "la huella cambió");
	_check("sin dejar de registrar la victoria en la meta-progresión",
		sm.get_runs_completed() == 1 and sm.guardados > 0, "runs %d" % sm.get_runs_completed());
	paused = false;
	var runs_antes = sm.get_runs_completed();
	var guardados_antes = sm.guardados;
	rs.write(snap);
	a._close_lost_run(stats.duplicate());
	_check("perder borra run.json", not FileAccess.file_exists(ruta));
	_check("y deja save.json idéntico", _huella_del_save() == antes, "la huella cambió");
	_check("sin pedirle nada al saveManager (perder no es progresión)",
		sm.get_runs_completed() == runs_antes and sm.guardados == guardados_antes);
	rs.write(snap);
	a.reset();
	_check("reset() borra run.json", not FileAccess.file_exists(ruta));
	_check("y deja save.json idéntico", _huella_del_save() == antes, "la huella cambió");

	# --- (5) Continuar desde el fichero: restaura y borra (paso 12). Con un save inválido no
	# monta nada y el fichero se va igual.
	var b = _main_para_reanudar(fd);
	rs.write(snap);
	b.runSave.path = ruta;
	var siguio = b._continue_from_file();
	_check("_continue_from_file() reanuda la run del fichero",
		siguio and b.gameManager != null and b.factoryArray.size() == snap["factories"].size(),
		"factorías %d vs %d" % [b.factoryArray.size(), snap["factories"].size()]);
	_check("y borra run.json tras restaurar: reanudar no es rebobinar", not FileAccess.file_exists(ruta));
	if b.weatherManager:
		b.weatherManager.log_events = false;
	var c = _main_para_reanudar(fd);
	_escribe_texto(ruta, texto.substr(0, 20));
	_check("con un save roto, _continue_from_file() da false sin montar nada y lo borra",
		not c._continue_from_file() and c.gameManager == null and not FileAccess.file_exists(ruta));

	rs.clear();
	paused = false;
	for m in [a, b, c]:
		_limpiar([m.placer, m.mapLoader, m] if m.placer != null else [m.mapLoader, m]);

# ---------- Serialización M4: autoguardado, cierre y analítica ----------

# Con el `sink` de prueba de los bloques «Analítica M*» y `_filas_de()` de Analítica M2. El
# cierre de la ventana se prueba llamando a `_on_app_closing()`: la suite no tiene clave de
# Augur, así que `Augur.closing` no se emite nunca y la atadura no se puede disparar.
func _test_serializacion_m4(file_data):
	print("Serialización M4 — autoguardado, cierre y analítica");
	var fd = file_data.duplicate(true);
	fd["Maps"] = [_mapa_por_id(file_data, "forest_01")];
	var tecla_r = InputEventKey.new();
	tecla_r.keycode = KEY_R;
	tecla_r.pressed = true;

	# --- (1) Sin run viva: _save_run() da false y no escribe; la R no reinicia ni borra.
	var vacio = _main_para_reanudar(fd);
	var rs = vacio.runSave;
	var ruta = rs.path;
	rs.clear();
	_check("sin run montada _save_run() da false y no escribe nada",
		not vacio._save_run() and not FileAccess.file_exists(ruta));
	var recibidos = [];
	vacio.analytics.sink = func(n, p): recibidos.append([n, p]);
	vacio._on_app_closing();
	_check("y _on_app_closing() sin run viva no manda nada", recibidos.is_empty(), str(recibidos));
	_escribe_texto(ruta, "{\"version\": 1}");
	vacio._unhandled_input(tecla_r);
	_check("la R en el menú, sin run, no borra la run guardada ni abre el package_select",
		FileAccess.file_exists(ruta) and vacio.get_node_or_null("PackageSelect") == null
		and recibidos.is_empty(), str(_nombres_de(recibidos)));
	rs.clear();

	# --- (2) El autoguardado: 20 s de _tick_world() escriben; 19 no; con el árbol pausado no.
	var a = _main_para_reanudar(fd);
	a._start_game("standard");
	a.weatherManager.log_events = false;
	a._on_factory_chosen("WoodCutter", Vector2i(7, 6));
	var tm = a.get_node("TileMap");
	rs.clear();
	_check("una run recién montada arranca el reloj del autoguardado en 0", a._autosave_t == 0.0);
	for i in 19:
		a._tick_world(tm, 1.0);
	_check("19 s de _tick_world() no escriben todavía", not FileAccess.file_exists(ruta));
	a._tick_world(tm, 1.0);
	_check("a los 20 s _tick_world() escribe run.json", FileAccess.file_exists(ruta));
	var leido = rs.read_valid(a._params_hash);
	_check("con la run en curso: su mapa, su factoría y el run_id vivo como resumed_from",
		not leido.is_empty() and leido.get("map_id") == a._run_map_id
		and leido.get("factories", []).size() == a.factoryArray.size()
		and leido.get("resumed_from") == a.analytics.run_id(), str(leido.keys()));
	_check("y el reloj vuelve a 0", a._autosave_t == 0.0, str(a._autosave_t));
	rs.clear();
	paused = true;
	for i in 25:
		a._tick_world(tm, 1.0);
	var en_pausa = FileAccess.file_exists(ruta);
	var t_pausa = a._autosave_t;
	paused = false;
	_check("con el árbol pausado 25 s de _tick_world() no escriben ni acumulan",
		not en_pausa and t_pausa == 0.0, "existe %s, t %s" % [en_pausa, t_pausa]);

	# --- (3) Con la oferta de cartas abierta SÍ guarda, con la oferta dentro.
	var oferta = ["speed_woodcutter", "more_workers", "extra_wood"];
	a.gameManager.checkpoint_reached.emit(oferta, {}, []);
	var guardo_oferta = a._save_run();
	var con_oferta = rs.read_valid(a._params_hash);
	var po = con_oferta.get("pending_offer", null);
	_check("con UpgradeScreen abierta _save_run() escribe y lleva pending_offer",
		guardo_oferta and po is Dictionary and Array(po.get("ids", [])) == oferta, str(po));
	a.get_node("UpgradeScreen")._on_upgrade_chosen("more_workers");
	paused = false;
	rs.clear();

	# --- (4) Cerrar con Augur: _on_app_closing() con run viva escribe y manda run_end suspend.
	recibidos = [];
	a.analytics.sink = func(n, p): recibidos.append([n, p]);
	var id_cerrada = a.analytics.run_id();
	a._on_app_closing();
	var fin = _filas_de(recibidos, "run_end");
	_check("_on_app_closing() con run viva escribe run.json", FileAccess.file_exists(ruta));
	_check("y manda UN run_end con result suspend y el run_id de la run",
		fin.size() == 1 and fin[0].get("result") == "suspend" and fin[0].get("run_id") == id_cerrada
		and not a.analytics.has_run(), str(fin));
	var snap = rs.read_valid(a._params_hash);
	_check("el fichero cita esa misma run como resumed_from", snap.get("resumed_from", "") == id_cerrada);
	recibidos.clear();
	a._on_app_closing();
	_check("un segundo cierre (la notificación tras el closing) vuelve a escribir y no manda nada",
		recibidos.is_empty() and FileAccess.file_exists(ruta), str(recibidos));
	rs.clear();
	a._notification(Node.NOTIFICATION_WM_CLOSE_REQUEST);
	_check("sin Augur, la notificación de cierre de Main escribe run.json", FileAccess.file_exists(ruta));
	rs.clear();

	# --- (5) Continuar manda run_start con resumed_from y un run_id nuevo; una run nueva, sin él.
	var b = _main_para_reanudar(fd);
	var de_b = [];
	b.analytics.sink = func(n, p): de_b.append([n, p]);
	b._continue_game(snap);
	if b.weatherManager:
		b.weatherManager.log_events = false;
	var rs_b = _filas_de(de_b, "run_start");
	_check("_continue_game() manda run_start con resumed_from = el run_id de la suspendida",
		rs_b.size() == 1 and rs_b[0].get("resumed_from") == id_cerrada, str(rs_b));
	_check("y abre un run_id NUEVO", rs_b.size() == 1 and rs_b[0].get("run_id", "") != id_cerrada
		and String(rs_b[0].get("run_id", "")).length() == 8);
	_check("la run reanudada arranca su reloj de autoguardado en 0", b._autosave_t == 0.0);
	var c = _main_para_reanudar(fd);
	var de_c = [];
	c.analytics.sink = func(n, p): de_c.append([n, p]);
	c._start_game("standard");
	if c.weatherManager:
		c.weatherManager.log_events = false;
	var rs_c = _filas_de(de_c, "run_start");
	_check("una run nueva manda run_start SIN resumed_from",
		rs_c.size() == 1 and not rs_c[0].has("resumed_from"), str(rs_c));
	# Un resumed_from estropeado (viene de disco) no puede tumbar el run_start entero.
	var d = _main_para_reanudar(fd);
	var de_d = [];
	d.analytics.sink = func(n, p): de_d.append([n, p]);
	var roto = snap.duplicate(true);
	roto["resumed_from"] = "no-es-un-id";
	d._continue_game(roto);
	if d.weatherManager:
		d.weatherManager.log_events = false;
	var rs_d = _filas_de(de_d, "run_start");
	_check("con un resumed_from que no es id, run_start sale igual, sin él",
		rs_d.size() == 1 and not rs_d[0].has("resumed_from"), str(rs_d));
	_check("el catálogo admite suspend como resultado y resumed_from en run_start",
		b.analytics.enums["result"].has("suspend")
		and b.analytics.events["run_start"]["props"].get("resumed_from", {}).get("type", "") == "id");

	# --- (6) Ganada la run, el resumen la da por terminada: ni autoguardado ni cierre guardan.
	b.saveManager = SaveSinDisco.new();
	b._on_run_won({"time": 10.0, "checkpoints": 1, "factories_placed": 0, "final_pollution": 0});
	de_b.clear();
	var guardo_ganada = b._save_run();
	b._on_app_closing();
	_check("con el RunSummary abierto _save_run() da false, no escribe y el cierre no manda nada",
		not guardo_ganada and not FileAccess.file_exists(ruta) and _filas_de(de_b, "run_end").is_empty(),
		str(_nombres_de(de_b)));
	paused = false;

	# --- (7) La R con run viva sigue reiniciando y borrando el save.
	rs.write(snap);
	c._unhandled_input(tecla_r);
	_check("la R con run viva reinicia (package_select) y borra run.json",
		c.gameManager == null and c.get_node_or_null("PackageSelect") != null
		and not FileAccess.file_exists(ruta));

	rs.clear();
	paused = false;
	for m in [vacio, a, b, c, d]:
		_limpiar([m.placer, m.mapLoader, m] if m.placer != null else [m.mapLoader, m]);

# ---------- Serialización M5: el botón «Continuar» ----------

# El menú se monta como lo monta Main: _show_main_menu() sobre un Main en el árbol, con el
# fichero de pruebas (user://test_run.json) delante o no. El ConfirmationDialog no se muestra:
# se emite su `confirmed`/`canceled`, que es lo que hacen sus botones.
func _menu_de(main):
	var viejo = main.get_node_or_null("MainMenu");
	if viejo != null:
		main.remove_child(viejo);
		viejo.free();
	main._show_main_menu();
	return main.get_node("MainMenu");

func _test_serializacion_m5(file_data):
	print("Serialización M5 — el botón «Continuar»");
	var fd = file_data.duplicate(true);
	fd["Maps"] = [_mapa_por_id(file_data, "forest_01")];
	var menu_script = load("res://ui/mainMenu.gd");

	# Un snapshot de verdad, de una run montada con una factoría.
	var a = _main_para_reanudar(fd);
	a._start_game("standard");
	a._on_factory_chosen("WoodCutter", Vector2i(7, 6));
	var snap = a._capture_run();
	var rs = a.runSave;
	var ruta = rs.path;
	rs.clear();

	# --- (1) Sin save no aparece; con uno de otro params_hash tampoco (y no se borra al mirar).
	var b = _main_para_reanudar(fd);
	var m = _menu_de(b);
	_check("sin run guardada el menú no tiene «CONTINUAR»",
		_boton_con_texto(m, "CONTINUAR") == null and m.continue_button == null);
	var ajeno = snap.duplicate(true);
	ajeno["params_hash"] = "otro_balance";
	rs.write(ajeno);
	m = _menu_de(b);
	_check("con un save de otro params_hash tampoco", _boton_con_texto(m, "CONTINUAR") == null);
	_check("y pintar el menú no lo borra (exists_valid solo mira)", FileAccess.file_exists(ruta));
	rs.clear();

	# --- (2) Con save válido: «CONTINUAR» encima de «JUGAR», mismo tamaño.
	rs.write(snap);
	m = _menu_de(b);
	var cont = _boton_con_texto(m, "CONTINUAR");
	var jugar = _boton_con_texto(m, "JUGAR");
	_check("con run guardada aparece «CONTINUAR»", cont != null and cont == m.continue_button);
	_check("justo encima de «JUGAR» y con su mismo tamaño (240×56)",
		cont != null and jugar != null and cont.get_parent() == jugar.get_parent()
		and cont.get_index() == jugar.get_index() - 1
		and cont.custom_minimum_size == Vector2(240, 56)
		and cont.custom_minimum_size == jugar.custom_minimum_size);
	_check("Main cablea continue_pressed y play_pressed del menú",
		_conectada(m, "continue_pressed", b, "_on_menu_continue")
		and _conectada(m, "play_pressed", b, "_on_menu_play"));

	# --- (3) «JUGAR» con save pide confirmación; «Cancelar» deja todo como estaba.
	var jugadas = [0];
	m.play_pressed.connect(func(): jugadas[0] += 1);
	jugar.pressed.emit();
	var dlg = m.confirm_dialog;
	_check("«JUGAR» con save abre un ConfirmationDialog y no emite play_pressed todavía",
		dlg is ConfirmationDialog and dlg.get_parent() == m and jugadas[0] == 0
		and not m.is_queued_for_deletion());
	_check("con sus textos: «Hay una run guardada. Empezar otra la borra.» / «Empezar nueva» / «Cancelar»",
		dlg != null and dlg.dialog_text == "Hay una run guardada. Empezar otra la borra."
		and dlg.ok_button_text == "Empezar nueva" and dlg.cancel_button_text == "Cancelar");
	if dlg != null:
		dlg.canceled.emit();
	_check("«Cancelar» no emite, no borra y deja el menú vivo",
		jugadas[0] == 0 and FileAccess.file_exists(ruta) and not m.is_queued_for_deletion()
		and b.get_node_or_null("PackageSelect") == null);

	# --- (4) «Empezar nueva»: borra run.json ANTES de ir a packageSelect.
	var habia_al_abrir = [null];
	b.child_entered_tree.connect(func(n):
		if n.name == "PackageSelect":
			habia_al_abrir[0] = FileAccess.file_exists(ruta), CONNECT_ONE_SHOT);
	if dlg != null:
		dlg.confirmed.emit();
	_check("«Empezar nueva» emite play_pressed y libera el menú",
		jugadas[0] == 1 and m.is_queued_for_deletion());
	_check("y Main borra run.json antes de montar el packageSelect",
		b.get_node_or_null("PackageSelect") != null and habia_al_abrir[0] == false
		and not FileAccess.file_exists(ruta), str(habia_al_abrir[0]));
	var ps = b.get_node_or_null("PackageSelect");
	if ps != null:
		b.remove_child(ps);
		ps.free();

	# --- (5) Sin save, «JUGAR» va directo (sin diálogo), como siempre.
	var sin = menu_script.new();
	sin.initialize(null, false, false);
	var directas = [0];
	sin.play_pressed.connect(func(): directas[0] += 1);
	_boton_con_texto(sin, "JUGAR").pressed.emit();
	_check("sin save «JUGAR» emite play_pressed sin diálogo",
		directas[0] == 1 and sin.confirm_dialog == null and sin.is_queued_for_deletion());
	sin.free();

	# --- (6) «CONTINUAR» reanuda la run del fichero, libera el menú y borra el save.
	var c = _main_para_reanudar(fd);
	rs.write(snap);
	m = _menu_de(c);
	_boton_con_texto(m, "CONTINUAR").pressed.emit();
	if c.weatherManager:
		c.weatherManager.log_events = false;
	_check("«CONTINUAR» reanuda la run guardada y libera el menú",
		c.gameManager != null and c.factoryArray.size() == snap["factories"].size()
		and m.is_queued_for_deletion() and c.get_node_or_null("PackageSelect") == null,
		"factorías %d vs %d" % [c.factoryArray.size(), snap["factories"].size()]);
	_check("y el save se borra al cargarlo", not FileAccess.file_exists(ruta));

	# --- (7) Si el save se invalida entre el menú y el click, se cae a elegir paquete.
	var d = _main_para_reanudar(fd);
	rs.write(snap);
	m = _menu_de(d);
	_escribe_texto(ruta, "{roto");
	_boton_con_texto(m, "CONTINUAR").pressed.emit();
	_check("con el save roto al pulsar, «CONTINUAR» abre el packageSelect en vez de dejar negro",
		d.gameManager == null and d.get_node_or_null("PackageSelect") != null
		and not FileAccess.file_exists(ruta));

	rs.clear();
	paused = false;
	for x in [a, b, c, d]:
		_limpiar([x.placer, x.mapLoader, x] if x.placer != null else [x.mapLoader, x]);
