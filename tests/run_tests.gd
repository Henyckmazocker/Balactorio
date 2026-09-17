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

# Doble del canvas item sobre el que pinta tileMap.draw_tints(): apunta cada diamante en vez
# de dibujarlo, así que se puede afirmar QUÉ se tiñe y en qué orden sin mirar una captura.
class SpyCanvas:
	var polys = [];
	func draw_colored_polygon(puntos, color):
		polys.append({ "puntos": puntos, "color": color });

var _hecho = false;

# Los tests corren en el primer frame, no en _initialize(): ahí el `root` todavía no está
# montado y los nodos que se le añaden no quedan dentro del árbol, así que
# factoryData._apply_pollution() no encontraría el PollutionManager.
func _process(_delta):
	if _hecho:
		return true;
	_hecho = true;
	_ejecutar();
	return true;

func _ejecutar():
	print("");
	print("=== Balactorio — pruebas de M1..M6 + M0.5 + Tensión M1/M2/M3/M3.5/M4 ===");
	print("");
	var file_data = JSON.parse_string(FileAccess.get_file_as_string("resources/factoryParams.json"));
	if file_data == null:
		print("FATAL: no se pudo leer resources/factoryParams.json");
		quit(2);
		return;

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
	_test_regresion_produccion();

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

	main._apply_upgrade("extra_wood");
	var degradadas = _celdas_de_tipo(tm, "toxic");
	_check("la mejora degrada exactamente las casillas que anuncia su carta",
		degradadas.size() == 2, "degradó %d" % degradadas.size());
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
	_check("el castigo sobrevive a los primeros frames", _celdas_de_tipo(tm, "toxic").size() == 2);

	# Una mejora de tier 1 no toca el mapa.
	main._apply_upgrade("speed_woodcutter");
	_check("una mejora sin map_downside no degrada nada",
		_celdas_de_tipo(tm, "toxic").size() == 2);

	# Y limpiarla del todo la devuelve: el castigo es un préstamo, no una multa.
	var recuperada = degradadas[0];
	tm.restoreCell(recuperada);
	_check("restaurada, la casilla vuelve a admitir factorías", tm.canPlaceFactory(recuperada, []));
	_check("y pierde el tinte del tipo degradado", not tm._cell_colors.has(recuperada));

	_limpiar([main, pm]);

	# Elegibilidad: con un suelo de tres casillas —una especial, una ocupada y una libre— el
	# downside solo puede caer en la libre, aunque la mejora pida dos.
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
	_check("el HUD anuncia el mantenimiento con su progreso", "(mantenimiento reservado: 1 / 4 wood)" in texto,
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
		not ("mantenimiento" in gm.getObjectiveText(bag)), gm.getObjectiveText(bag));
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
	# El atasco medido al cerrar M5, en pequeño: el objetivo es `plank` y el peaje `wood`,
	# que es el insumo del `plank`. Dos serrerías con «Sierra industrial» (tick 1) piden 2
	# maderas por segundo y una cortadora talla 1 cada 4 s: sin reserva la madera se queda
	# clavada en 0, el peaje no se cubre nunca y —sin condición de derrota— la run no acaba.
	var gm = _new_gm(file_data, [
		{ "material": "plank", "quantity": 6, "label": "Uno", "maintenance": { "wood": 5 } }
	]);
	var bag = _new_bag();
	bag.initialize(file_data);
	var pm = _new_pm();
	root.add_child(pm);
	# Las tres van con pollution 0.0 desde el ahogo (Condiciones de Derrota M1): 400 ticks
	# seguidos sobre la misma casilla y sin nadie limpiando la saturan, y una línea ahogada
	# dejaría de talar por un motivo que esta prueba no mide. Lo que se prueba aquí es la
	# reserva del peaje, así que el ahogo se saca del escenario en vez de taparlo.
	var cortadora = _factoria_en_arbol("WoodCutter", Vector2i(0, 0));
	cortadora.initialize("WoodCutter", 4, null, "wood", 1, 0.0, "production", 0);
	var sierra1 = _factoria_en_arbol("WoodProcessing", Vector2i(1, 0));
	sierra1.initialize("WoodProcessing", 1, ["wood"], "plank", 1, 0.0, "production", 0);
	var sierra2 = _factoria_en_arbol("WoodProcessing", Vector2i(2, 0));
	sierra2.initialize("WoodProcessing", 1, ["wood"], "plank", 1, 0.0, "production", 0);

	var cerrado_en = -1;
	for t in range(1, 401):
		gm.update(bag);          # sincroniza la reserva y evalúa el checkpoint
		if t % 4 == 0:
			cortadora.update(bag);
		sierra1.update(bag);
		sierra2.update(bag);
		if gm.current_checkpoint_index >= 1 and cerrado_en < 0:
			cerrado_en = t;
	_check("el checkpoint se cierra pese a que las serrerías piden el doble de lo que se tala",
		cerrado_en > 0, "no se cerró en 400 ticks (wood %d, plank %d)" % [
			bag.getQuantity("wood"), bag.getQuantity("plank")]);
	# Y no a costa de parar la línea: el excedente sigue llegando a las serrerías, así que el
	# objetivo de tablones también se cubre. Un arreglo que congelara la producción cerraría
	# el peaje y colgaría la run por el otro lado.
	_check("y las serrerías siguen produciendo del excedente", cerrado_en > 0,
		"objetivo de plank sin cubrir");
	_limpiar([cortadora, sierra1, sierra2, gm, bag, pm]);

	# El contraste, para que la prueba de arriba no pase por casualidad: la misma línea sin
	# reserva se queda sin madera para siempre. Es el atasco que M6 viene a matar.
	var bag_sin = _new_bag();
	bag_sin.initialize(file_data);
	var pm2 = _new_pm();
	root.add_child(pm2);
	var cortadora2 = _factoria_en_arbol("WoodCutter", Vector2i(0, 0));
	cortadora2.initialize("WoodCutter", 4, null, "wood", 1, 0.0, "production", 0);
	var sierra3 = _factoria_en_arbol("WoodProcessing", Vector2i(1, 0));
	sierra3.initialize("WoodProcessing", 1, ["wood"], "plank", 1, 0.0, "production", 0);
	var sierra4 = _factoria_en_arbol("WoodProcessing", Vector2i(2, 0));
	sierra4.initialize("WoodProcessing", 1, ["wood"], "plank", 1, 0.0, "production", 0);
	for t in range(1, 401):
		if t % 4 == 0:
			cortadora2.update(bag_sin);
		sierra3.update(bag_sin);
		sierra4.update(bag_sin);
	_check("sin reserva la madera del peaje no llega a juntarse nunca",
		bag_sin.getQuantity("wood") < 5, "wood = %d" % bag_sin.getQuantity("wood"));
	_limpiar([cortadora2, sierra3, sierra4, bag_sin, pm2]);

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
	_check("el botón anuncia la sinergia bajo el nombre y el material",
		textos[0] == ["WoodCutter", "→ wood", "✦ Output +1", "✦ Mejora 1 vecina"], str(textos));
	_check("y una de restauración dice «(restauración)», no «<null>» (material null en el JSON)",
		textos[1] == ["Reforester", "(restauración)"], str(textos));
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

# Lo que una productora entrega a la bolsa en `ticks` ticks, con `suciedad` ya sembrada en su
# casilla. La factoría va con pollution 0.0 a propósito: lo que se mide es el ahogo de la
# suciedad sembrada, no el que la factoría se fabrica sola ensuciándose la casilla tick a tick.
# Cada escenario monta y suelta su propio PollutionManager: find_child devuelve el PRIMERO del
# árbol, así que dos escenarios vivos a la vez leerían el mismo manager.
func _entregado_en(file_data, celda, suciedad, ticks):
	var pm = _new_pm();
	root.add_child(pm);
	if suciedad > 0.0:
		pm.addPollution(suciedad, celda);
	var f = _factoria_en_arbol("WoodCutter", celda);
	f.initialize("WoodCutter", 1, null, "wood", 1, 0.0, "production", 0);
	var bag = _new_bag();
	bag.initialize(file_data);
	for i in range(ticks):
		f.update(bag);
	var total = bag.getQuantity("wood");
	_limpiar([f, pm, bag]);
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
	var bag = _new_bag();
	bag.initialize(file_data);
	bag.addToBag("wood", 5);
	sierra.update(bag);
	_check("el tick que no entrega nada no consume insumos", bag.getQuantity("wood") == 5,
		"quedan %d maderas" % bag.getQuantity("wood"));
	_check("ni ensucia", _near(pm2.pollution_per_cell[celda], 6.25),
		"la casilla quedó en %f" % pm2.pollution_per_cell[celda]);
	sierra.update(bag);
	_check("el tick siguiente sí consume, entrega y ensucia",
		bag.getQuantity("wood") == 4 and bag.getQuantity("plank") == 1
			and _near(pm2.pollution_per_cell[celda], 8.25),
		"wood %d, plank %d, casilla %f" % [bag.getQuantity("wood"), bag.getQuantity("plank"),
			pm2.pollution_per_cell[celda]]);
	_limpiar([sierra, pm2, bag]);

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
		gm._progressText(bag, pm, true) in texto and ("mantenimiento reservado" in texto), texto);
	_check("pero con la cola de contaminación fuera mientras la ventana corre",
		not ("Contaminación" in texto) and (pm.getStatusText() in gm._progressText(bag, pm)),
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
		restaurando.begins_with("⚠ COLAPSO EN") and ("Restaurando:" in restaurando), restaurando);
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


# ---------- Derrota M6: las dos constantes medidas ----------

# El spike (tests/sim_derrota.gd) mide los números; esto guarda las relaciones de las que
# salieron, que es lo que se rompe sin avisar al recalibrar. No repiten la medición —eso
# tarda minutos y no cabe en la suite—: afirman que los dos valores siguen cumpliendo su
# razón de ser.
func _test_cd6_constantes(file_data):
	print("Derrota M6 — las dos constantes medidas siguen cumpliendo su razón de ser");
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
	# de los 12,5 de cell_block_pollution) el spike midió 16 s, y la gracia tiene que cubrirlos.
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
	# abandonado conserva casillas libres para siempre y la derrota es inalcanzable (medido en
	# el bloque 1 del spike: 150 de 160 libres tras 2000 s). Y si un foco tardara demasiado en
	# saturar a una vecina limpia, el colapso dejaría de verse venir dentro de una sentada.
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
	_check("getStatusText() enseña el total y el umbral efectivo, sin cociente",
		pm.getStatusText() == "Contaminación: 22607  (restaurar: ≤ 2717)", pm.getStatusText());

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
		(objetivo in colapso) and ("mantenimiento reservado" in colapso), colapso);
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
		restaurando.begins_with("⚠ COLAPSO EN") and ("Restaurando: Contaminación:" in restaurando),
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
		(objetivo3 in normal) and ("mantenimiento reservado" in normal)
		and ("Contaminación: 77  (restaurar: ≤ 14)" in normal), normal);
	_check("y también cabe",
		normal.length() <= presupuesto,
		"%d caracteres de %d: %s" % [normal.length(), presupuesto, normal]);
	# El criterio del hito, literal: ningún camino del HUD enseña ya la escala.
	_check("ningún camino del HUD enseña ya el `/ 200` de la escala",
		not ("/ 200" in normal) and not ("/ 200" in colapso) and not ("/ 200" in restaurando),
		"%s || %s || %s" % [normal, colapso, restaurando]);
	_limpiar([esc["tm"], gm, bag, pm2, gm3, bag3, pm3]);
