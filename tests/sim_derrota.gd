extends SceneTree

# Spike M6 — Plan «Condiciones de Derrota». Mide las dos constantes que M2 y M3 dejaron
# puestas a ojo: pollutionManager.contagion_rate y gameManager.DEADLOCK_GRACE.
#
#   godot-4 --headless --path . --script res://tests/sim_derrota.gd
#   godot-4 --headless --path . --script res://tests/sim_derrota.gd -- abandono
#   godot-4 --headless --path . --script res://tests/sim_derrota.gd -- cuidada nueve
#   godot-4 --headless --path . --script res://tests/sim_derrota.gd -- abandono rapido altos
#
# SE CONSERVA, al revés que tests/sim_m0.gd: lo que mide son constantes de balance que
# habrá que re-medir en cuanto entren factorías o eventos nuevos que alimenten la espiral.
# No es una prueba —no afirma nada, mide— y no va en la suite ni en ningún hook: el barrido
# entero tarda minutos.
#
# Los cuatro bloques:
#   abandono  — barrido de contagion_rate sobre un mapa abandonado: cuánto tarda en quedarse
#               sin casillas construibles y en emitir run_lost.
#   cuidada   — el mismo barrido sobre una run jugada con cuidado: cuántos focos llega a
#               tener, cuánto infla el pico y si el umbral de restauración sigue alcanzable.
#   nueve     — el equivalente al barrido de M7: 3 paquetes x 3 configuraciones, que tienen
#               que seguir terminando 5/5 y restaurando.
#   gracia    — el suelo de DEADLOCK_GRACE: cuánto tarda LA jugada que desatasca (un Reforester,
#               una productora sobre la última casilla libre) en romper una de las tres
#               condiciones, contado desde que se coloca. La gracia tiene que ser más larga que
#               el falso positivo más largo que el juego sabe producir.
#
# Trampas respetadas (Brain/Balactorio/Programación.md § Conducir el juego en headless, y el
# aviso de M6):
#  - Engine.time_scale acelera el reloj pero NO cambia el número de frames. Todo lo que se
#    mide aquí —contagio, tick pasivo, run_time, los Timer de las factorías— se escala por
#    delta, así que la aceleración es válida; nada de esto cuenta frames.
#  - _start_game() elige el mapa al azar: se reaplica a mano tras poner total_pollution = 0,
#    pollution_per_cell.clear() y peak_pollution = 0, o se suma dos veces pollution_start.
#  - find_child("PollutionManager") devuelve el PRIMERO del árbol: se suelta el escenario
#    anterior antes de montar el siguiente.
#  - La pantalla de mejora pausa el árbol: se cierra por el handler de la PANTALLA.
#  - get_tree().paused sobrevive al escenario: se resetea en cada montaje.
#  - Los nodos se montan en _process(), no en _initialize(): ahí root todavía no existe.
#  - removePollution() descuenta del global solo lo que quita DE VERDAD de la casilla: los
#    Reforester de la fase 2 se colocan SOBRE los focos (ver _cubrir_focos), nunca al tuntún.

const TIME_SCALE = 20.0;
const MUESTREO = 1.0;              # segundos de juego entre muestras de la tabla
const TOPE_ABANDONO = 2000.0;      # si un mapa abandonado no muere aquí, no muere
const TOPE_PRODUCCION = 900.0;
const TOPE_RESTAURACION = 1200.0;
const MAX_REFORESTER = 60;
# Tope de Reforester que el jugador cuidadoso mantiene DURANTE la produccion (ver
# _atender_focos). No es el de la fase 2, que es cuando se cubre el mapa de verdad.
const LIMITE_CUIDADO = 28;

# El barrido de contagion_rate. 0.0 es el control: sin contagio el mapa nunca se queda sin
# casillas y la derrota es inalcanzable, que es la razón de que M2 exista.
const RATES = [0.0, 0.02, 0.05, 0.08, 0.12, 0.20];

var _main_node = null;
var _sim_time = 0.0;
var _arrancado = false;

# --- estado de la run en curso ---
var _perdida_en = INF;
var _victoria_en = INF;
var _ofrecidas = [];
var _politica = "prudente";
var _pendientes = [];       # colocaciones que esperan a que haya workers o se desbloquee algo

# --- observador del punto muerto (réplica de gameManager._evaluate_deadlock, solo lectura) ---
var _obs_pending = 0;
var _obs_pollution = 0.0;
var _obs_checkpoint = 0;
var _obs_ini = { "c1": -1.0, "c12": -1.0, "c123": -1.0 };
var _obs_max = { "c1": 0.0, "c12": 0.0, "c123": 0.0 };
var _obs_focos_max = 0;
var _obs_celda_max = 0.0;
var _obs_sin_hueco = INF;

var _filas_abandono = [];
var _filas_cuidada = [];
var _filas_nueve = [];
var _filas_gracia = [];

# La aceleración real del banco. Con `-- rapido` sube a 60, y es lo único que acorta el bloque
# del mapa abandonado: un mapa saturado entero dispara ~1.300 addPollution() por frame (160
# focos por 8 vecinas), así que el banco va limitado por los FRAMES y no por el reloj. Subirla
# es válido AQUÍ porque lo que ese bloque mide —el frente del contagio— se escala por delta y
# nada de ello cuenta frames; comprobado: a 20 y a 60 el mapa abandonado muere en los mismos
# 780 / 564 / 382 s. Los bloques de run jugada se miden siempre a 20, que es donde el Timer de
# 1 s de las factorías apenas se cuantiza.
var _escala = TIME_SCALE;

func _initialize():
	if "rapido" in OS.get_cmdline_user_args():
		_escala = 60.0;
	Engine.time_scale = _escala;
	Engine.max_fps = 0;

func _process(delta):
	_sim_time += delta;
	if not _arrancado:
		_arrancado = true;
		_ejecutar();
	return false;

# ---------------------------------------------------------------- orquestación

func _ejecutar():
	var args = OS.get_cmdline_user_args();
	var todo = args.is_empty();
	print("");
	print("=== Balactorio — M6: spike de las dos constantes (headless, time_scale=%.0f) ===" % _escala);
	if todo or "abandono" in args:
		await _bloque_abandono();
	if todo or "cuidada" in args:
		await _bloque_cuidada();
	if todo or "nueve" in args:
		await _bloque_nueve();
	if todo or "gracia" in args:
		await _bloque_gracia();
	_soltar_escenario();
	_imprimir();
	quit(0);

# ---------------------------------------------------------------- bloque: mapa abandonado

# La run abandonada: se coloca una línea de producción y nadie vuelve a tocar el mapa. Las
# celdas de las productoras se autoahogan (una productora ensucia su propia casilla cada tick
# y nadie limpia), cruzan contagion_pollution y a partir de ahí el contagio es lo único que
# mueve el mapa. Lo que se mide es cuánto tarda en no quedar ni una casilla construible y,
# detrás, cuánto tarda en emitir run_lost.
const LINEA_ABANDONO = [
	Vector2i(1, 3), Vector2i(2, 3), Vector2i(3, 3),
	Vector2i(4, 3), Vector2i(5, 3), Vector2i(6, 3)
];

func _bloque_abandono():
	print("");
	print("--- BLOQUE 1: mapa abandonado (6 WoodCutter, nadie limpia, nadie vuelve) ---");
	# `-- altos` se salta los dos valores que ya se sabe que no saturan el mapa (0,00 y 0,02
	# tardan el tope entero) para poder reiterar sobre la zona útil del barrido.
	var rates = RATES;
	if "altos" in OS.get_cmdline_user_args():
		rates = [0.05, 0.08, 0.12, 0.20];
	if "finos" in OS.get_cmdline_user_args():
		rates = [0.10, 0.12];
	for mapa in ["forest_01", "wasteland_01"]:
		for rate in rates:
			await _escenario_abandono(mapa, rate);

func _escenario_abandono(map_id, rate):
	await _montar(map_id, "standard", rate);
	var main = _main_node;
	for celda in LINEA_ABANDONO:
		_colocar(main, "WoodCutter", celda);
	var t0 = _sim_time;
	while _sim_time - t0 < TOPE_ABANDONO:
		await _avanzar(MUESTREO);
		if _perdida_en < INF or _victoria_en < INF:
			break;
	var pm = main.pollutionManager;
	var fila = {
		"mapa": map_id, "rate": rate,
		"t_sin_hueco": (_obs_sin_hueco - t0) if _obs_sin_hueco < INF else INF,
		"t_derrota": (_perdida_en - t0) if _perdida_en < INF else INF,
		"pico": pm.peak_pollution,
		"focos": _contar_focos(pm),
		"libres": _contar_libres(main)
	};
	_filas_abandono.append(fila);
	print("  %-13s rate=%.2f  sin hueco en %s  derrota en %s  pico=%8.1f  focos=%3d  casillas libres al final=%3d" % [
		map_id, rate, _fmt(fila["t_sin_hueco"]), _fmt(fila["t_derrota"]),
		fila["pico"], fila["focos"], fila["libres"]]);

# ---------------------------------------------------------------- bloque: run cuidada

func _bloque_cuidada():
	print("");
	print("--- BLOQUE 2: run jugada con cuidado (Reforester pegados a la línea) ---");
	for mapa in ["forest_01", "wasteland_01"]:
		for rate in RATES:
			await _escenario_cuidada(mapa, rate);

func _escenario_cuidada(map_id, rate):
	await _montar(map_id, "standard", rate);
	var main = _main_node;
	for p in _plan("prudente"):
		_pendientes.append(p);
	_reintentar(main);
	var t0 = _sim_time;
	# Solo la fase de producción: lo que este bloque pregunta es si una run bien jugada
	# llega siquiera a tener un foco de contagio, y con él cuánto se le infla el pico.
	while _sim_time - t0 < TOPE_PRODUCCION:
		await _avanzar(MUESTREO);
		_reintentar(main);
		_atender_focos(main, LIMITE_CUIDADO);
		if main.gameManager.production_done or _perdida_en < INF or _victoria_en < INF:
			break;
	var pm = main.pollutionManager;
	var fila = {
		"mapa": map_id, "rate": rate,
		"checkpoints": main.gameManager.current_checkpoint_index,
		"t": _sim_time - t0,
		"pico": pm.peak_pollution,
		"umbral": pm.getRestorationThreshold(),
		"total": pm.total_pollution,
		"celda_max": _obs_celda_max,
		"focos_max": _obs_focos_max,
		"perdida": _perdida_en < INF
	};
	_filas_cuidada.append(fila);
	print("  %-13s rate=%.2f  %d/5 en %5.0fs  pico=%6.1f  umbral=%5.1f  total=%6.1f  celda max=%5.1f  focos max=%2d%s" % [
		map_id, rate, fila["checkpoints"], fila["t"], fila["pico"], fila["umbral"],
		fila["total"], fila["celda_max"], fila["focos_max"],
		"  <<< DERROTA" if fila["perdida"] else ""]);

# ---------------------------------------------------------------- bloque: las nueve runs

# El equivalente del barrido de M7, que no se conservó: 3 paquetes x 3 configuraciones
# (mapa x política de mejora), jugadas enteras hasta 5/5 y hasta restaurar.
# El eje que M7 barrió eran las POLÍTICAS DE MEJORA, no el dejar de limpiar: sus nueve runs
# terminaban 5/5 y restauraban. `agresivo` coge las cartas de tier 2 —las tres de una pantalla
# de tier 2 llevan `map_downside`, así que degradan casillas a `toxic`— y `prudente` las evita
# mientras pueda; las dos colocan y atienden igual, porque las dos son runs bien jugadas. El
# layout lo varían los mapas: wasteland_01 tiene cinco casillas bloqueadas que se comen dos
# Reforester de la fila de arriba.
const NUEVE = [
	["forest_01", "prudente"], ["wasteland_01", "prudente"], ["wasteland_01", "agresivo"]
];

func _bloque_nueve():
	print("");
	print("--- BLOQUE 3: las nueve runs (3 paquetes x 3 configuraciones), enteras ---");
	for paquete in ["standard", "lumberjack", "ecologist"]:
		for conf in NUEVE:
			await _run_entera(paquete, conf[0], conf[1]);
	# Y el contraste, fuera de las nueve: la misma partida jugada sin limpiar.
	await _run_entera("standard", "wasteland_01", "descuidada");

func _run_entera(paquete, map_id, politica):
	await _montar(map_id, paquete, -1.0);
	var main = _main_node;
	_politica = politica;
	for p in _plan(politica):
		_pendientes.append(p);
	_reintentar(main);
	var pm = main.pollutionManager;
	var t0 = _sim_time;
	# Fase 1: producción.
	while _sim_time - t0 < TOPE_PRODUCCION:
		await _avanzar(MUESTREO);
		_reintentar(main);
		if politica != "descuidada":
			_atender_focos(main, LIMITE_CUIDADO);
		if main.gameManager.production_done or _perdida_en < INF or _victoria_en < INF:
			break;
	var t_produccion = _sim_time - t0;
	var pico_produccion = pm.peak_pollution;
	var checkpoints = main.gameManager.current_checkpoint_index;
	# Fase 2: restauración. El jugador demuele lo que ensucia y cubre los focos.
	if _victoria_en == INF and _perdida_en == INF:
		_demoler_produccion(main);
		var t1 = _sim_time;
		while _sim_time - t1 < TOPE_RESTAURACION:
			_cubrir_focos(main);
			await _avanzar(5.0);
			if _victoria_en < INF or _perdida_en < INF:
				break;
	var fila = {
		"paquete": paquete, "mapa": map_id, "politica": politica,
		"checkpoints": checkpoints, "t_produccion": t_produccion,
		"pico": pm.peak_pollution, "pico_produccion": pico_produccion,
		"umbral": pm.getRestorationThreshold(), "total": pm.total_pollution,
		"ganada": _victoria_en < INF, "perdida": _perdida_en < INF,
		"t_total": (_victoria_en - t0) if _victoria_en < INF else (_sim_time - t0),
		"c1": _obs_max["c1"], "c12": _obs_max["c12"], "c123": _obs_max["c123"],
		"focos_max": _obs_focos_max, "celda_max": _obs_celda_max
	};
	_filas_nueve.append(fila);
	print("  %-11s %-13s %-9s  %d/5  pico=%6.1f  umbral=%5.1f  final=%6.1f  %s en %5.0fs   ventanas 1=%4.1f 1&2=%4.1f 1&2&3=%4.1f" % [
		paquete, map_id, politica, fila["checkpoints"], fila["pico"], fila["umbral"],
		fila["total"],
		("RESTAURADA" if fila["ganada"] else ("DERROTA" if fila["perdida"] else "sin cerrar")),
		fila["t_total"], fila["c1"], fila["c12"], fila["c123"]]);


# ---------------------------------------------------------------- bloque: la gracia

# El suelo de DEADLOCK_GRACE no sale de una run sana —en una run sana la condición 3 no se
# cumple nunca—, sale del FALSO POSITIVO: la ventana se abre, el jugador ya ha hecho la jugada
# que lo desatasca, y la gracia tiene que durar más de lo que esa jugada tarda en cambiar algo.
# Lo que se cronometra aquí es exactamente eso: de colocar la factoría a que rompa una
# condición. La de producción rompe la 1 (entrega una unidad del material pendiente) y el
# Reforester rompe la 2 (baja el total). `ahogo` es la contaminación local que se le deja a la
# casilla: una casilla pegada a una zona saturada no está limpia, y el ahogo multiplica el
# tiempo hasta la primera entrega —production_debt suelta 1 unidad cada ceil(1/choke) ticks—,
# que es de lejos el falso positivo más largo que el juego sabe producir.
const CASOS_GRACIA = [
	["Reforester sobre suciedad (rompe la condición 2)", "Reforester", 5.0],
	["WoodCutter sobre casilla limpia (choke 1,00)", "WoodCutter", 0.0],
	["WoodCutter con choke 0,50", "WoodCutter", 6.25],
	["WoodCutter con choke 0,25", "WoodCutter", 9.375],
	["WoodCutter con choke 0,10", "WoodCutter", 11.25],
	["WoodProcessing sin madera que darle", "WoodProcessing", 0.0]
];

const CELDA_GRACIA = Vector2i(8, 7);

func _bloque_gracia():
	print("");
	print("--- BLOQUE 4: la gracia. Cuánto tarda la jugada que desatasca en cambiar algo ---");
	for caso in CASOS_GRACIA:
		await _escenario_gracia(caso[0], caso[1], caso[2]);
	await _gracia_mapa_muerto();

func _escenario_gracia(etiqueta, tipo, ahogo):
	await _montar("forest_01", "standard", 0.0);
	var main = _main_node;
	var pm = main.pollutionManager;
	# El evaluador de verdad, inerte: sin TileMap inyectado no se evalúa el punto muerto (regla
	# de M3). Así la ventana se cronometra entera en vez de acabar cortada por el run_lost de
	# la gracia que hoy está puesta, que es justo el número que se quiere decidir.
	main.gameManager.tile_map_node = null;
	# Suciedad alrededor para que el Reforester tenga de dónde quitar: removePollution()
	# descuenta del global solo lo que quita DE VERDAD de la casilla.
	for offset in pm.NEIGHBOR_OFFSETS:
		pm.addPollution(5.0, CELDA_GRACIA + offset);
	if ahogo > 0.0:
		pm.addPollution(ahogo, CELDA_GRACIA);
	await _avanzar(2.0);
	var bag = main.get_node("Player").get_node("Bag");
	var antes_bolsa = bag.getQuantity("wood") + bag.getQuantity("plank");
	var antes_pol = pm.total_pollution;
	var t0 = _sim_time;
	var colocada = _colocar(main, tipo, CELDA_GRACIA);
	var cambio = INF;
	while _sim_time - t0 < 120.0:
		await _avanzar(0.25);
		if tipo == "Reforester":
			if pm.total_pollution < antes_pol - 0.0001:
				cambio = _sim_time - t0;
				break;
		elif bag.getQuantity("wood") + bag.getQuantity("plank") > antes_bolsa:
			cambio = _sim_time - t0;
			break;
	print("  %-48s %s  cambia algo a los %s" % [
		etiqueta, ("colocada" if colocada else "NO cabe "), _fmt(cambio)]);
	_filas_gracia.append({ "caso": etiqueta, "ventana": cambio, "colocada": colocada });

# El otro extremo, y es un hallazgo, no un falso positivo: con el mapa saturado ENTERO y el
# contagio en marcha, los ~1.300 puntos por segundo que generan 160 focos no los baja ningún
# Reforester, así que la condición 2 no se rompe y la cuenta atrás NO se cancela. No es un
# fallo de la gracia: es que ahí el mapa está muerto de verdad y no hay jugada que lo cambie.
func _gracia_mapa_muerto():
	await _montar("forest_01", "standard", -1.0);
	var main = _main_node;
	var pm = main.pollutionManager;
	var tm = main.get_node("TileMap");
	main.gameManager.tile_map_node = null;
	for celda in tm.get_used_cells(0):
		if celda != CELDA_GRACIA:
			pm.addPollution(20.0, celda);
	await _avanzar(2.0);
	var antes_pol = pm.total_pollution;
	var t0 = _sim_time;
	var colocada = _colocar(main, "Reforester", CELDA_GRACIA);
	var cambio = INF;
	while _sim_time - t0 < 120.0:
		await _avanzar(0.25);
		if pm.total_pollution < antes_pol - 0.0001:
			cambio = _sim_time - t0;
			break;
	print("  %-48s %s  cambia algo a los %s   (contagion_rate = %.2f)" % [
		"Reforester sobre el mapa saturado entero", ("colocada" if colocada else "NO cabe "),
		_fmt(cambio), pm.contagion_rate]);
	_filas_gracia.append({ "caso": "Reforester sobre el mapa saturado entero (160 focos)",
		"ventana": cambio, "colocada": colocada });

# ---------------------------------------------------------------- el jugador simulado

# Los dos layouts. `prudente` intercala WoodCutter y WoodProcessing (las dos sinergias se
# aplican en los dos sentidos) y los encierra entre dos filas de Reforester: sobre el papel
# cada casilla de producción tiene hasta seis vecinas limpiando. `agresivo` dobla la
# producción y deja la limpieza para el final, que es la run que de verdad pone a prueba el
# contagio. Las celdas evitan las especiales de los dos mapas (`ruins` abre pantalla de
# mejora al construir encima, y las bloqueadas de wasteland_01 no existen en el suelo):
# canPlaceFactory() filtra sola lo que no cabe.
func _plan(politica):
	var plan = [];
	if politica != "descuidada":
		plan.append([0, "WoodCutter", Vector2i(1, 3)]);
		plan.append([0, "WoodProcessing", Vector2i(2, 3)]);
		plan.append([0, "WoodCutter", Vector2i(3, 3)]);
		plan.append([0, "WoodProcessing", Vector2i(4, 3)]);
		plan.append([0, "WoodCutter", Vector2i(5, 3)]);
		plan.append([1, "WoodProcessing", Vector2i(6, 3)]);
		plan.append([2, "WoodCutter", Vector2i(7, 3)]);
		for x in range(1, 8):
			plan.append([0, "Reforester", Vector2i(x, 2)]);
			plan.append([0, "Reforester", Vector2i(x, 4)]);
	else:
		# Descuidada: dos filas enteras de producción y solo dos Reforester de cortesía. No es
		# una run bien jugada —es la que la cadena está hecha para castigar— y no cuenta entre
		# las nueve; se corre al final para tener el contraste medido.
		for x in range(1, 7):
			plan.append([0, "WoodCutter", Vector2i(x, 3)]);
		plan.append([0, "WoodProcessing", Vector2i(1, 4)]);
		plan.append([0, "WoodProcessing", Vector2i(3, 4)]);
		plan.append([1, "WoodProcessing", Vector2i(5, 4)]);
		plan.append([2, "WoodProcessing", Vector2i(2, 4)]);
		plan.append([0, "Reforester", Vector2i(1, 2)]);
		plan.append([0, "Reforester", Vector2i(2, 2)]);
	return plan;

# Coloca lo que ya se puede colocar. Se reintenta porque hay dos cosas que llegan tarde: los
# workers (WoodProcessing necesita 1, y la run arranca con 2) y el desbloqueo de la propia
# WoodProcessing, que en `lumberjack` y `ecologist` llega como carta de rescate al cerrar el
# primer checkpoint.
func _reintentar(main):
	var quedan = [];
	var gm = main.gameManager;
	for p in _pendientes:
		if gm.current_checkpoint_index < p[0]:
			quedan.append(p);
			continue;
		if not _colocar(main, p[1], p[2]):
			quedan.append(p);
	_pendientes = quedan;

func _colocar(main, tipo, celda) -> bool:
	var jugador = main.get_node_or_null("Player");
	if jugador == null or not jugador.availableFactories.has(tipo):
		return false;
	var params = main.fileData["Factories"][tipo];
	var necesita = int(params.get("workers_needed", 0));
	var bag = jugador.get_node("Bag");
	if necesita > 0 and bag.getFreeWorkers() < necesita:
		return false;
	var antes = main.factoryArray.size();
	main._on_factory_chosen(tipo, celda);
	return main.factoryArray.size() > antes;

# Jugar con cuidado no es solo colocar bien al principio: es atender lo que se ensucia. Las
# cartas de tier 2 degradan casillas a `toxic` —y en una pantalla de tier 2 las TRES cartas
# llevan `map_downside`, así que ni el jugador más prudente las esquiva—, y una `toxic` es
# +0,5/s eternos: el foco que enciende el contagio. Un solo Reforester al lado le quita
# 4,0/5 s/9 = 0,089/s y no la sostiene; hace falta RACIMO, que es justo lo que el spike de
# M0 ya había medido para wasteland_01. Este jugador pone hasta RACIMO vecinas limpiando
# sobre cada foco, que es lo que de verdad significa «jugar con cuidado».
# Sobre la propia `toxic` no se puede construir (buildable: false), de ahí la caída a las
# vecinas.
const RACIMO = 4;
const FOCO_MINIMO = 6.0;

func _atender_focos(main, limite):
	var pm = main.pollutionManager;
	var puestos = _contar_reforester(main);
	if puestos >= limite:
		return;
	for celda in pm.pollution_per_cell.keys():
		if puestos >= limite:
			return;
		if pm.pollution_per_cell[celda] < FOCO_MINIMO:
			continue;
		var cerca = _reforester_cerca(main, celda);
		if cerca >= RACIMO:
			continue;
		if _colocar(main, "Reforester", celda):
			puestos += 1;
			cerca += 1;
		for offset in pm.NEIGHBOR_OFFSETS:
			if cerca >= RACIMO or puestos >= limite:
				break;
			if _colocar(main, "Reforester", celda + offset):
				puestos += 1;
				cerca += 1;

func _contar_reforester(main):
	var n = 0;
	for fab in main.factoryArray:
		if fab.factory_type == "restoration":
			n += 1;
	return n;

# Reforester que limpian esta casilla: los de las 8 vecinas y el de encima, porque la
# restauración se reparte entre la celda propia y su vecindario (removePollutionArea).
func _reforester_cerca(main, celda):
	var n = 0;
	for fab in main.factoryArray:
		if fab.factory_type != "restoration":
			continue;
		var d = fab.cell_position - celda;
		if abs(d.x) <= 1 and abs(d.y) <= 1:
			n += 1;
	return n;

func _demoler_produccion(main):
	var celdas = [];
	for fab in main.factoryArray:
		if fab.factory_type == "production":
			celdas.append(fab.cell_position);
	for celda in celdas:
		main._demolish_at_cell(celda);

# Cubrir los focos, no el mapa: removePollution() descuenta del global solo lo que quita DE
# VERDAD de la casilla, así que un Reforester sobre suelo limpio no acerca la victoria. Se
# recorren las casillas de más sucia a menos y se intenta poner la factoría encima; si la
# casilla está cerrada por contaminación (>= cell_block_pollution) se cae a sus vecinas, que
# es desde donde se limpia una casilla saturada o una `toxic`.
func _cubrir_focos(main):
	var pm = main.pollutionManager;
	var puestos = 0;
	for fab in main.factoryArray:
		if fab.factory_type == "restoration":
			puestos += 1;
	if puestos >= MAX_REFORESTER:
		return;
	var sucias = [];
	for celda in pm.pollution_per_cell:
		if pm.pollution_per_cell[celda] > 0.2:
			sucias.append(celda);
	sucias.sort_custom(func(a, b): return pm.pollution_per_cell[a] > pm.pollution_per_cell[b]);
	for celda in sucias:
		if puestos >= MAX_REFORESTER:
			return;
		if _colocar(main, "Reforester", celda):
			puestos += 1;
			continue;
		for offset in pm.NEIGHBOR_OFFSETS:
			if puestos >= MAX_REFORESTER:
				return;
			if _colocar(main, "Reforester", celda + offset):
				puestos += 1;
				break;

# La política de mejora. `prudente` huye de las cartas con `map_downside` —degradan casillas
# a `toxic`, que ensucian +0,5/s para siempre— y prefiere ritmo y workers; `agresivo` coge
# justo esas, que es lo que M7 llamaba jugar a fondo.
func _elegir_mejora(main):
	var catalogo = main.fileData["Upgrades"];
	var con_castigo = [];
	var sin_castigo = [];
	for id in _ofrecidas:
		if catalogo.get(id, {}).has("map_downside"):
			con_castigo.append(id);
		else:
			sin_castigo.append(id);
	if _politica == "agresivo":
		if not con_castigo.is_empty():
			return con_castigo[0];
		return sin_castigo[0] if not sin_castigo.is_empty() else "";
	if not sin_castigo.is_empty():
		return sin_castigo[0];
	return con_castigo[0] if not con_castigo.is_empty() else "";

# ---------------------------------------------------------------- escenario

func _soltar_escenario():
	if _main_node != null:
		root.remove_child(_main_node);
		_main_node.free();
		_main_node = null;

func _montar(map_id, paquete, rate):
	_soltar_escenario();
	paused = false;   # get_tree().paused sobrevive al escenario
	_perdida_en = INF;
	_victoria_en = INF;
	_ofrecidas = [];
	_pendientes = [];
	_politica = "prudente";
	_obs_pending = 0;
	_obs_pollution = 0.0;
	_obs_checkpoint = 0;
	_obs_ini = { "c1": -1.0, "c12": -1.0, "c123": -1.0 };
	_obs_max = { "c1": 0.0, "c12": 0.0, "c123": 0.0 };
	_obs_focos_max = 0;
	_obs_celda_max = 0.0;
	_obs_sin_hueco = INF;
	# Semilla fija: _pick_upgrades() baraja la oferta y _apply_map_downside() elige a suerte
	# qué casillas degrada a `toxic`. Sin fijarla, dos escenarios del barrido no se diferencian
	# solo en contagion_rate sino también en qué cartas salieron y dónde cayó el castigo, y la
	# tabla deja de comparar lo que dice comparar.
	seed(20260917);
	var main = load("res://Main.tscn").instantiate();
	root.add_child(main);
	_main_node = main;
	var menu = main.get_node_or_null("MainMenu");
	if menu:
		main.remove_child(menu);
		menu.free();
	main._start_game(paquete);
	var pm = main.pollutionManager;
	if rate >= 0.0:
		pm.contagion_rate = rate;
	# Reaplicar el mapa elegido (pick_map() es aleatorio) sin sumar dos veces pollution_start
	# ni arrastrar el pico del mapa descartado: de ese pico sale el umbral de victoria.
	pm.total_pollution = 0.0;
	pm.pollution_per_cell.clear();
	pm.peak_pollution = 0.0;
	main.mapLoader.apply_map(_mapa_por_id(main.fileData, map_id), pm, main.get_node("TileMap"), main.fileData);
	main.gameManager.run_lost.connect(func(_stats): _perdida_en = _sim_time);
	main.gameManager.run_won.connect(func(_stats): _victoria_en = _sim_time);
	main.gameManager.checkpoint_reached.connect(func(ofrecidas, _r, _g): _ofrecidas = ofrecidas);
	await process_frame;

func _mapa_por_id(file_data, map_id):
	for m in file_data.get("Maps", []):
		if m.get("id", "") == map_id:
			return m;
	return {};

func _avanzar(segundos):
	var objetivo = _sim_time + segundos;
	while _sim_time < objetivo:
		await process_frame;
		_observar();
		_cerrar_popups();
		if _perdida_en < INF or _victoria_en < INF:
			return;

# La pantalla de mejora pausa el árbol; se cierra por el handler de la PANTALLA, que es quien
# emite la señal y se libera. Llamar a Main._on_upgrade_chosen() dejaría la pantalla puesta y
# la mejora se reaplicaría en cada frame.
func _cerrar_popups():
	if _main_node == null:
		return;
	var up = _main_node.get_node_or_null("UpgradeScreen");
	if up:
		var id = _elegir_mejora(_main_node);
		up._on_upgrade_chosen(id);
		_reintentar(_main_node);
	var token = _main_node.get_node_or_null("FactoryTokenScreen");
	if token and token.has_method("_on_chosen"):
		token._on_chosen("");

# ---------------------------------------------------------------- observador

# Réplica de gameManager._evaluate_deadlock() que SOLO LEE, para poder medir las ventanas de
# las tres condiciones sin depender del valor de DEADLOCK_GRACE (que es una const y no se
# puede barrer en caliente). Se muestrea una vez por frame, igual que el evaluador de verdad,
# y se calla cuando el árbol está pausado o el gameManager inactivo, que es cuando el
# evaluador tampoco corre.
func _observar():
	var main = _main_node;
	if main == null or paused:
		return;
	var gm = main.gameManager;
	var pm = main.pollutionManager;
	var tm = main.get_node_or_null("TileMap");
	if gm == null or pm == null or tm == null or not gm.active:
		_cerrar_ventanas();
		return;
	# Foto de la contaminación por casilla: el techo de una casilla y cuántos focos de
	# contagio (por encima de contagion_pollution) llega a haber.
	var focos = 0;
	for celda in pm.pollution_per_cell:
		var v = pm.pollution_per_cell[celda];
		if v > _obs_celda_max:
			_obs_celda_max = v;
		if v > pm.contagion_pollution:
			focos += 1;
	if focos > _obs_focos_max:
		_obs_focos_max = focos;
	# Cerrar el checkpoint reinicia las observaciones, igual que hace _reset_deadlock().
	if gm.current_checkpoint_index != _obs_checkpoint:
		_obs_checkpoint = gm.current_checkpoint_index;
		_obs_pending = 0;
		_obs_pollution = 0.0;
		_cerrar_ventanas();
		return;
	var bag = main.get_node("Player").get_node("Bag");
	var pending = gm._pending_quantity(bag);
	var produced = pending > _obs_pending;
	_obs_pending = pending;
	var pol = pm.total_pollution;
	var cleaned = pol < _obs_pollution - 0.0001;
	_obs_pollution = pol;
	var c1 = not produced;
	var c2 = c1 and not cleaned;
	var c3 = c2 and not tm.hasBuildableCell(main.factoryArray);
	if c3 and _obs_sin_hueco == INF:
		_obs_sin_hueco = _sim_time;
	_ventana("c1", c1);
	_ventana("c12", c2);
	_ventana("c123", c3);

func _ventana(clave, abierta):
	if abierta:
		if _obs_ini[clave] < 0.0:
			_obs_ini[clave] = _sim_time;
		var largo = _sim_time - _obs_ini[clave];
		if largo > _obs_max[clave]:
			_obs_max[clave] = largo;
	else:
		_obs_ini[clave] = -1.0;

func _cerrar_ventanas():
	_obs_ini = { "c1": -1.0, "c12": -1.0, "c123": -1.0 };

# ---------------------------------------------------------------- utilidades

func _contar_focos(pm):
	var n = 0;
	for celda in pm.pollution_per_cell:
		if pm.pollution_per_cell[celda] > pm.contagion_pollution:
			n += 1;
	return n;

func _contar_libres(main):
	var tm = main.get_node_or_null("TileMap");
	if tm == null:
		return -1;
	var n = 0;
	for celda in tm.get_used_cells(0):
		if tm.canPlaceFactory(celda, main.factoryArray):
			n += 1;
	return n;

func _fmt(t):
	if t == INF:
		return "  nunca";
	return "%5.0fs" % t;

# ---------------------------------------------------------------- tablas

func _imprimir():
	if not _filas_abandono.is_empty():
		print("");
		print("=== TABLA 1 — mapa abandonado: ¿cuándo muere? ===");
		print("| Mapa | contagion_rate | Sin casilla construible | run_lost | Pico | Focos | Libres al final |");
		print("|---|---|---|---|---|---|---|");
		for f in _filas_abandono:
			print("| %s | %.2f | %s | %s | %.0f | %d | %d |" % [
				f["mapa"], f["rate"], _fmt(f["t_sin_hueco"]).strip_edges(),
				_fmt(f["t_derrota"]).strip_edges(), f["pico"], f["focos"], f["libres"]]);
	if not _filas_cuidada.is_empty():
		print("");
		print("=== TABLA 2 — run cuidada: ¿lo nota? ===");
		print("| Mapa | contagion_rate | Checkpoints | Pico | Umbral (5.0+0.12*pico) | Total al cerrar | Casilla más sucia | Focos máx |");
		print("|---|---|---|---|---|---|---|---|");
		for f in _filas_cuidada:
			print("| %s | %.2f | %d/5 | %.1f | %.1f | %.1f | %.1f | %d |" % [
				f["mapa"], f["rate"], f["checkpoints"], f["pico"], f["umbral"],
				f["total"], f["celda_max"], f["focos_max"]]);
	if not _filas_nueve.is_empty():
		print("");
		print("=== TABLA 3 — las nueve runs ===");
		print("| Paquete | Mapa | Política | Checkpoints | Pico | Umbral | Total final | Resultado | t | Ventana 1 | 1&2 | 1&2&3 |");
		print("|---|---|---|---|---|---|---|---|---|---|---|---|");
		var ganadas = 0;
		var nueve = 0;
		for f in _filas_nueve:
			if f["politica"] == "descuidada":
				continue;
			nueve += 1;
			if f["ganada"]:
				ganadas += 1;
			print("| %s | %s | %s | %d/5 | %.1f | %.1f | %.1f | %s | %.0fs | %.1f | %.1f | %.1f |" % [
				f["paquete"], f["mapa"], f["politica"], f["checkpoints"], f["pico"],
				f["umbral"], f["total"],
				("restaurada" if f["ganada"] else ("DERROTA" if f["perdida"] else "sin cerrar")),
				f["t_total"], f["c1"], f["c12"], f["c123"]]);
		print("");
		print("Runs bien jugadas que terminan 5/5 y restauran: %d de %d" % [ganadas, nueve]);
		# Solo las runs que siguen vivas: la `descuidada` acaba en derrota, y su ventana de
		# 25 s no es un falso positivo sino la gracia contada entera antes de matarla.
		var peor = 0.0;
		for f in _filas_nueve:
			if f["politica"] == "descuidada" or f["perdida"]:
				continue;
			if f["c123"] > peor:
				peor = f["c123"];
		print("Ventana 1&2&3 más larga medida en una run que sigue viva: %.1f s" % peor);
		print("El suelo de DEADLOCK_GRACE no sale de ahí sino del bloque 4: en una run viva la");
		print("condición 3 no se cumple nunca.");
	if not _filas_gracia.is_empty():
		print("");
		print("=== TABLA 4 — el falso positivo: cuánto tarda la jugada que desatasca en cambiar algo ===");
		print("| Caso | La jugada cambia algo a los |");
		print("|---|---|");
		for f in _filas_gracia:
			print("| %s | %s |" % [f["caso"], _fmt(f["ventana"]).strip_edges()]);
	print("");
