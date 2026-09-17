extends SceneTree

# Spike de calibración M0 — Plan «Tensión del Loop Roguelite».
# REMEDIDO el 2026-09-17 al cerrar M0.5: la tabla de M0 se midió con la aritmética vieja, en
# la que limpiar sobre una casilla ya limpia bajaba el global igual. Con M0.5 el global solo
# baja lo que se quita de las casillas, así que ni el sitio de los Reforester ni la forma de
# medir (meseta artificial + extrapolación lineal) seguían valiendo.
#
#   godot-4 --headless --path . --script res://tests/sim_m0.gd
#
# DESECHABLE: se borra al cerrar M1. No forma parte del juego ni de la suite de tests;
# nada de res://tests/ se instancia desde Main.tscn.
#
# Conduce el juego entero en headless con la receta de Programación.md (§ Tests):
# instanciar Main.tscn, saltarse los menús con _start_game(), colocar con
# _on_factory_chosen() y acelerar con Engine.time_scale.
#
# NO TOCA NINGÚN FICHERO DEL JUEGO: las variantes de balance se prueban mutando el
# diccionario fileData ya cargado en memoria (factoryPlacer guarda la referencia, así que
# la mutación llega a las factorías que se construyan después).
#
# Trampas respetadas (Programación.md § Conducir el juego en headless):
#  - _start_game() elige mapa al azar: se reaplica el mapa a mano tras poner
#    total_pollution = 0.0 y pollution_per_cell.clear(), o se suma dos veces pollution_start.
#  - find_child("PollutionManager") devuelve el PRIMERO del árbol: se suelta el escenario
#    anterior antes de montar el siguiente.
#  - La pantalla de mejora pausa el árbol: se cierra por el handler de la PANTALLA.
#  - get_tree().paused sobrevive al escenario: se resetea en cada montaje.
#  - Los nodos se montan en _process(), no en _initialize(): ahí root todavía no existe.

const TIME_SCALE = 20.0;
const T_PRODUCCION = 40.0;      # fase 1: ensuciar
const T_RESTAURACION = 150.0;   # fase 2: tope; si no ha bajado aquí, no baja
const MUESTREO = 5.0;
const VENTANA_TASA = 20.0;      # ventana inicial de la fase 2 de la que sale la tasa neta
const VENTANA_ESTANCADO = 40.0; # sin bajar 0.2 en esta ventana, el escenario se corta

# Curva del umbral escalado, YA EN EL CÓDIGO desde M1: thr = BASE + K * pico
# (pollutionManager.restoration_base / restoration_peak_factor). Se repiten aquí solo para
# la tabla de sensibilidad; el umbral que decide la victoria lo da el propio manager.
const BASE_UMBRAL = 5.0;
const K_UMBRAL = 0.12;

# Celdas planas en los DOS mapas (ni especiales ni bloqueadas en forest_01/wasteland_01),
# para que los escenarios sean comparables. Ojo con (12,6) y (15,8): son `ruins` y abren la
# pantalla de mejora al construir encima.
const CELDAS_PRODUCCION = [
	Vector2i(1, 3), Vector2i(2, 3), Vector2i(3, 3),
	Vector2i(4, 3), Vector2i(5, 3), Vector2i(6, 3)
];
# REMEDIDO TRAS M0.5: los Reforester van en la fila pegada a las productoras, encima de la
# suciedad. El bloque 3x2 apartado que usaba la medición anterior ahora limpia exactamente
# 0.00/s —removePollution() solo descuenta del global lo que quita de una casilla— y toda la
# tabla salía «nunca». Que la geometría mande es justo el efecto que M0.5 buscaba.
# Siguen siendo adyacentes entre sí, así que el acantilado por sinergia
# (synergies.Reforester.pollution_mult, MULTIPLICATIVO: 1.25^vecinos) se sigue viendo.
const CELDAS_REFORESTER = [
	Vector2i(1, 4), Vector2i(2, 4), Vector2i(3, 4),
	Vector2i(4, 4), Vector2i(5, 4), Vector2i(6, 4)
];

const NS = [0, 1, 2, 3, 4, 5, 6];
const VARIANTES = ["actual", "propA", "propB"];

var _main_node = null;
var _sim_time = 0.0;
var _arrancado = false;
var _filas = [];
var _validacion = "";
var _sensibilidad = [];   # descensos completos de la validación, para barrer K a posteriori

func _initialize():
	Engine.time_scale = TIME_SCALE;
	Engine.max_fps = 0;

func _process(delta):
	_sim_time += delta;
	if not _arrancado:
		_arrancado = true;
		_ejecutar();
	return false;

# ---------------------------------------------------------------- orquestación

func _ejecutar():
	print("");
	print("=== Balactorio — M0: spike de calibración (headless, time_scale=%.0f) ===" % TIME_SCALE);
	print("");
	# Con `-- wasteland` se salta el barrido y solo corre la comprobación de ganabilidad,
	# que es la parte que se itera al ajustar la cobertura.
	if not ("wasteland" in OS.get_cmdline_user_args()):
		for variante in VARIANTES:
			for mapa in ["forest_01", "wasteland_01"]:
				for modo in ["sucio", "limpio"]:
					for n in NS:
						await _escenario(mapa, modo, n, variante);
	await _check_wasteland_ganable();
	_soltar_escenario();
	_imprimir_tabla();
	quit(0);

func _escenario(map_id, modo, n_ref, variante):
	await _montar(map_id, variante);
	var pm = _main_node.pollutionManager;

	# --- fase 1: producción (ensuciar) ---
	var n_prod = 6 if modo == "sucio" else 2;
	for i in range(n_prod):
		_main_node._on_factory_chosen("WoodCutter", CELDAS_PRODUCCION[i]);
	var t0 = _sim_time;
	var serie = [[0.0, pm.total_pollution]];
	while _sim_time - t0 < T_PRODUCCION:
		await _avanzar(MUESTREO);
		serie.append([_sim_time - t0, pm.total_pollution]);
	var pico = pm.total_pollution;
	var tasa_prod = _pendiente(serie, 10.0, 1e9);

	# --- fase 2: restauración, con la producción AÚN EN MARCHA (es la competencia real) ---
	for i in range(n_ref):
		_main_node._on_factory_chosen("Reforester", CELDAS_REFORESTER[i]);
	# Ya no se mide sobre la meseta artificial de 1000.0 que usaba la medición anterior:
	# desde M0.5 el descenso NO es una recta —cada casilla deja de aportar en cuanto se queda
	# limpia, y el global no puede bajar más que ellas—, así que una pendiente extrapolada
	# mentiría. Se muestrea el descenso REAL hasta cruzar el umbral o estancarse.
	var t1 = _sim_time;
	var descenso = [[0.0, pm.total_pollution]];
	while _sim_time - t1 < T_RESTAURACION:
		await _avanzar(MUESTREO);
		descenso.append([_sim_time - t1, pm.total_pollution]);
		if pm.total_pollution <= 5.0 or _estancado(descenso):
			break;
	var tasa_neta = _pendiente(descenso, 0.0, VENTANA_TASA);

	var thr = pm.getRestorationThreshold();
	# La limpieza bruta se mide contra la fila N=0 del MISMO grupo, en la misma ventana:
	# restar la tasa de la fase 1 mezclaría dos ventanas y arrastraría el ruido de
	# cuantización del Timer de 1 s (cada WoodCutter suelta 3.0 de golpe cada 4 s).
	var base = _fila(map_id, modo, variante, 0);
	var tasa_base = tasa_prod if base.is_empty() else base["tasa_neta"];
	_filas.append({
		"mapa": map_id, "modo": modo, "n": n_ref, "variante": variante,
		"pico": pico, "tasa_prod": tasa_prod, "tasa_neta": tasa_neta,
		"limpieza": tasa_base - tasa_neta,   # restauración bruta que aportan los N Reforester
		"thr": thr,
		"descenso": descenso,
		"t5": _cruce(descenso, 5.0),
		"tthr": _cruce(descenso, thr)
	});
	var f = _filas[-1];
	print("  %-12s %-6s %-6s N=%d  pico=%6.1f  prod=%+5.2f/s  neta=%+6.2f/s  limpieza=%5.2f/s  t->5=%s  t->%.0f=%s"
		% [map_id, modo, variante, n_ref, pico, tasa_prod, tasa_neta, f["limpieza"],
		   _fmt(f["t5"]), thr, _fmt(f["tthr"])]);

# El riesgo que M0.5 tenía que resolver: los 20 puntos de pollution_start de wasteland_01 ya
# no viven en el aire sino repartidos por las casillas del suelo, así que hay que CUBRIRLAS
# para restaurarlas. Se juega una run sucia entera y se comprueba que se llega a
# isRestored(), con dos coberturas: una que barre el mapa y otra que solo atiende los focos.
func _check_wasteland_ganable():
	for cobertura in ["mapa entero", "solo focos"]:
		await _montar("wasteland_01", "actual");
		var pm = _main_node.pollutionManager;
		var inicial = pm.total_pollution;
		for i in range(6):
			_main_node._on_factory_chosen("WoodCutter", CELDAS_PRODUCCION[i]);
		await _avanzar(T_PRODUCCION);
		var pico = pm.total_pollution;
		# La producción ya está hecha: el jugador demuele y se dedica a restaurar.
		for i in range(6):
			_main_node._demolish_at_cell(CELDAS_PRODUCCION[i]);
		var puestos = 0;
		for celda in _cobertura_wasteland(cobertura):
			var antes = _main_node.factoryArray.size();
			_main_node._on_factory_chosen("Reforester", celda);
			if _main_node.factoryArray.size() > antes:
				puestos += 1;
		# Se muestrea el descenso ENTERO —no se corta al cruzar el umbral— para poder leer
		# después qué K habría sido alcanzable y cuál habría dejado la run colgada.
		var t1 = _sim_time;
		var descenso = [[0.0, pm.total_pollution]];
		var restaurado_en = INF;
		while _sim_time - t1 < 400.0:
			await _avanzar(MUESTREO);
			descenso.append([_sim_time - t1, pm.total_pollution]);
			if restaurado_en == INF and pm.isRestored():
				restaurado_en = _sim_time - t1;
			if _estancado(descenso):
				break;
		_validacion += "  wasteland_01 (%-12s): inicio %5.1f | pico %6.1f | umbral %5.1f | %2d Reforester -> %s (fondo %5.1f tras %3.0f s)\n" % [
			cobertura, inicial, pico, pm.getRestorationThreshold(), puestos,
			("RESTAURADO en %3.0f s" % restaurado_en) if restaurado_en < INF else "NO restaurado",
			descenso[-1][1], descenso[-1][0]];
		_sensibilidad.append({ "escenario": "wasteland_01 sucio / %s" % cobertura,
			"pico": pico, "descenso": descenso });

	# La otra mitad de la pregunta: que el umbral no se vuelva un regalo en una run limpia.
	await _montar("forest_01", "actual");
	var pm2 = _main_node.pollutionManager;
	for i in range(2):
		_main_node._on_factory_chosen("WoodCutter", CELDAS_PRODUCCION[i]);
	await _avanzar(T_PRODUCCION);
	var pico2 = pm2.total_pollution;
	for i in range(2):
		_main_node._demolish_at_cell(CELDAS_PRODUCCION[i]);
	var puestos2 = 0;
	for celda in [Vector2i(1, 2), Vector2i(2, 2), Vector2i(1, 4), Vector2i(2, 4)]:
		var antes2 = _main_node.factoryArray.size();
		_main_node._on_factory_chosen("Reforester", celda);
		if _main_node.factoryArray.size() > antes2:
			puestos2 += 1;
	var t2 = _sim_time;
	var descenso2 = [[0.0, pm2.total_pollution]];
	var restaurado2 = INF;
	while _sim_time - t2 < 400.0:
		await _avanzar(MUESTREO);
		descenso2.append([_sim_time - t2, pm2.total_pollution]);
		if restaurado2 == INF and pm2.isRestored():
			restaurado2 = _sim_time - t2;
		if _estancado(descenso2):
			break;
	_validacion += "  forest_01   (%-12s): inicio   0.0 | pico %6.1f | umbral %5.1f | %2d Reforester -> %s (fondo %5.1f tras %3.0f s)\n" % [
		"run limpia", pico2, pm2.getRestorationThreshold(), puestos2,
		("RESTAURADO en %3.0f s" % restaurado2) if restaurado2 < INF else "NO restaurado",
		descenso2[-1][1], descenso2[-1][0]];
	_sensibilidad.append({ "escenario": "forest_01 limpio / 4 Reforester",
		"pico": pico2, "descenso": descenso2 });

# Dos coberturas del mismo mapa. `mapa entero`: rejilla cada 3 casillas (cada Reforester
# barre su 3x3) + racimo sobre la `toxic` + las celdas que dejaron las productoras.
# `solo focos`: lo que ensucia la producción más las casillas degradadas del mapa, que es
# donde vive la contaminación de partida desde M1. Es la cobertura que un jugador que
# atiende lo sucio pondría, y la que tiene que bastar para cerrar la run.
# Las casillas que no admiten Reforester (bloqueadas, mountain, lake, ocupadas) las filtra
# sola canPlaceFactory() dentro de _on_factory_chosen().
func _cobertura_wasteland(modo):
	var celdas = [];
	# Focos 1: doble fila pegada a las productoras. Sobre la propia celda sucia NO se puede
	# construir —isCellBlocked() la cierra a 12.5 de contaminación local y una celda con 40 s
	# de WoodCutter encima va por 30—, así que la limpieza tiene que venir de las vecinas.
	for x in range(1, 7):
		celdas.append(Vector2i(x, 2));
		celdas.append(Vector2i(x, 4));
	# Focos 2: racimo alrededor de la casilla toxic (6,7), que ensucia +0.5/s para siempre y
	# a la que un Reforester solo le quita 4.0/5 s/9 = 0.089/s. Sin racimo no se sostiene.
	for c in [Vector2i(5, 6), Vector2i(6, 6), Vector2i(7, 6), Vector2i(5, 8), Vector2i(6, 8), Vector2i(7, 8)]:
		celdas.append(c);
	# Focos 3: las casillas degradadas del mapa (dos `burned` y dos `swamp`), que desde M1
	# son las que cargan con los 20 puntos de pollution_start. Se cubren desde una vecina:
	# sobre la propia casilla sí se puede construir (5.0 < 12.5), pero desde al lado se
	# barren las dos de cada pareja a la vez.
	for c in [Vector2i(1, 2), Vector2i(2, 2), Vector2i(13, 4), Vector2i(14, 4)]:
		celdas.append(c);
	# Y el barrido del resto del mapa, para comparar contra la cobertura mínima.
	if modo == "mapa entero":
		for y in [0, 3, 6, 9]:
			for x in [1, 4, 7, 10, 13, 15]:
				celdas.append(Vector2i(x, y));
	return celdas;

# ---------------------------------------------------------------- escenario

func _soltar_escenario():
	if _main_node != null:
		root.remove_child(_main_node);
		_main_node.free();
		_main_node = null;

func _montar(map_id, variante):
	_soltar_escenario();
	paused = false;   # get_tree().paused sobrevive al escenario
	var main = load("res://Main.tscn").instantiate();
	root.add_child(main);
	_main_node = main;
	var menu = main.get_node_or_null("MainMenu");
	if menu:
		main.remove_child(menu);
		menu.free();
	main._start_game("standard");
	# gameManager desactivado: sin checkpoints no hay pantalla de mejora que pause el árbol
	# ni victoria que lo congele. Aquí se mide la curva de contaminación, no el flujo de run.
	main.gameManager.active = false;
	_aplicar_variante(main.fileData, variante);
	# Reaplicar el mapa elegido (pick_map() es aleatorio) sin sumar dos veces pollution_start.
	# Y sin arrastrar el pico del mapa descartado: desde M1 el pico decide el umbral de
	# victoria, así que dejarlo puesto mediría una run con la memoria de otra.
	var pm = main.pollutionManager;
	pm.total_pollution = 0.0;
	pm.pollution_per_cell.clear();
	pm.peak_pollution = 0.0;
	main.mapLoader.apply_map(_mapa_por_id(main.fileData, map_id), pm, main.get_node("TileMap"), main.fileData);
	await process_frame;

# Variantes de suavizado del acantilado. Se escriben en el diccionario en memoria:
# ni el JSON ni ningún .gd se tocan.
func _aplicar_variante(file_data, variante):
	var r = file_data["Factories"]["Reforester"];
	match variante:
		"propA":
			r["pollution"] = -1.2;
			r["tick"] = 1;
			r["synergies"]["Reforester"] = { "pollution_mult": 1.10 };
		"propB":
			r["pollution"] = -1.5;
			r["tick"] = 1;
			r["synergies"]["Reforester"] = { "pollution_mult": 1.0 };

func _mapa_por_id(file_data, map_id):
	for m in file_data.get("Maps", []):
		if m.get("id", "") == map_id:
			return m;
	return {};

func _avanzar(segundos):
	var objetivo = _sim_time + segundos;
	while _sim_time < objetivo:
		await process_frame;
		_cerrar_popups();

# Red de seguridad: con el gameManager apagado no deberían aparecer, pero si una casilla
# `ruins` se colase, la pantalla pausa el árbol y el escenario devuelve una tabla plana.
func _cerrar_popups():
	if _main_node == null:
		return;
	var up = _main_node.get_node_or_null("UpgradeScreen");
	if up:
		up._on_upgrade_chosen("__ninguna__");   # id inexistente: _apply_upgrade() sale sin aplicar
		_main_node.gameManager.active = false;
	var rs = _main_node.get_node_or_null("RunSummary");
	if rs:
		paused = false;
		_main_node.remove_child(rs);
		rs.free();

# ---------------------------------------------------------------- aritmética

# Pendiente (unidades/s) entre la primera muestra >= desde y la última <= hasta.
func _pendiente(serie, desde, hasta):
	var a = null;
	var b = null;
	for s in serie:
		if a == null and s[0] >= desde:
			a = s;
		if s[0] <= hasta:
			b = s;
	if a == null or b == null or b[0] - a[0] <= 0.0:
		if serie.size() < 2:
			return 0.0;
		a = serie[0];
		b = serie[-1];
	if b[0] - a[0] <= 0.0:
		return 0.0;
	return (b[1] - a[1]) / (b[0] - a[0]);

# Corta la fase 2 cuando el descenso ya no va a ningún sitio: si en los últimos
# VENTANA_ESTANCADO segundos el total no ha bajado ni 0.2, no va a bajar. Sustituye a la
# extrapolación lineal, que desde M0.5 no vale: el descenso se frena solo al limpiarse las
# casillas cubiertas, y lo que queda fuera del área no baja jamás.
func _estancado(serie):
	var ultimo = serie[-1];
	if ultimo[0] < VENTANA_ESTANCADO:
		return false;
	var previo = null;
	for s in serie:
		if s[0] <= ultimo[0] - VENTANA_ESTANCADO:
			previo = s;
	if previo == null:
		return false;
	return previo[1] - ultimo[1] < 0.2;

# Primer instante medido en que el total cae al umbral, interpolando entre muestras.
func _cruce(serie, thr):
	if serie[0][1] <= thr:
		return 0.0;
	for i in range(1, serie.size()):
		if serie[i][1] <= thr:
			var a = serie[i - 1];
			var b = serie[i];
			if a[1] <= b[1]:
				return b[0];
			return a[0] + (a[1] - thr) * (b[0] - a[0]) / (a[1] - b[1]);
	return INF;

func _fmt(t):
	if t == INF:
		return " nunca";
	return "%5.0fs" % t;

# ---------------------------------------------------------------- tabla

func _fila(mapa, modo, variante, n) -> Dictionary:
	for f in _filas:
		if f["mapa"] == mapa and f["modo"] == modo and f["variante"] == variante and f["n"] == n:
			return f;
	return {};

func _imprimir_tabla():
	print("");
	print("=== TABLA DE ESCENARIOS ===");
	print("umbral escalado (ya en pollutionManager): restoration_threshold = %.1f + %.2f * peak_pollution" % [BASE_UMBRAL, K_UMBRAL]);
	print("sucio = 6 WoodCutter | limpio = 2 WoodCutter | N Reforester pegados a las productoras | la producción sigue en marcha durante la restauración");
	print("t -> X es el descenso REAL medido (tope %.0f s); «nunca» = se estancó sin llegar" % T_RESTAURACION);
	print("");
	for variante in VARIANTES:
		print("--- Reforester: %s ---" % variante);
		print("| Mapa | Modo | N Ref | Pico (40 s) | Producción /s | Neta /s | Limpieza bruta /s | t → 5.0 (umbral de hoy) | Umbral escalado | t → umbral escalado |");
		print("|---|---|---|---|---|---|---|---|---|---|");
		for f in _filas:
			if f["variante"] != variante:
				continue;
			print("| %s | %s | %d | %.1f | %+.2f | %+.2f | %.2f | %s | %.1f | %s |"
				% [f["mapa"], f["modo"], f["n"], f["pico"], f["tasa_prod"], f["tasa_neta"],
				   f["limpieza"], _fmt(f["t5"]).strip_edges(), f["thr"], _fmt(f["tthr"]).strip_edges()]);
		print("");
	# Sensibilidad de K sobre los cuatro escenarios de referencia con N=5
	print("--- Sensibilidad de K (thr = 5.0 + K * pico), Reforester actual, N=5 ---");
	print("| Escenario | Pico | K=0.05 | K=0.10 | K=0.15 | K=0.20 | K=0.30 |");
	print("|---|---|---|---|---|---|---|");
	for mapa in ["forest_01", "wasteland_01"]:
		for modo in ["sucio", "limpio"]:
			var f = _fila(mapa, modo, "actual", 5);
			if f.is_empty():
				continue;
			var celdas = [];
			for k in [0.05, 0.10, 0.15, 0.20, 0.30]:
				var thr = 5.0 + k * f["pico"];
				celdas.append("%s (thr %.0f)" % [_fmt(_cruce(f["descenso"], thr)).strip_edges(), thr]);
			print("| %s / %s | %.1f | %s |" % [mapa, modo, f["pico"], " | ".join(celdas)]);
	print("");
	# Sesgo del banco de medida
	var w = _fila("wasteland_01", "sucio", "actual", 0);
	if not w.is_empty():
		print("Sesgo del banco: 6 WoodCutter nominales = 6 * 3.0 / 4 s = 4.50/s; medido %+.2f/s (factor %.3f)."
			% [w["tasa_prod"], w["tasa_prod"] / 4.5]);
		print("Es el overshoot del Timer de 1 s a time_scale %.0f; afecta por igual a producción y restauración, así que los cocientes de la tabla no lo arrastran." % TIME_SCALE);
	print("--- ¿Sigue siendo ganable? (producción demolida al acabar; el descenso se muestrea entero) ---");
	print(_validacion);
	print("--- Sensibilidad de K sobre esos mismos descensos: t -> (5.0 + K * pico) ---");
	print("| Escenario | Pico | K=0.00 | K=0.05 | K=0.12 | K=0.20 | K=0.30 |");
	print("|---|---|---|---|---|---|---|");
	for v in _sensibilidad:
		var celdas2 = [];
		for k in [0.0, 0.05, 0.12, 0.20, 0.30]:
			var thr2 = BASE_UMBRAL + k * v["pico"];
			celdas2.append("%s (thr %.0f)" % [_fmt(_cruce(v["descenso"], thr2)).strip_edges(), thr2]);
		print("| %s | %.1f | %s |" % [v["escenario"], v["pico"], " | ".join(celdas2)]);
	print("");
