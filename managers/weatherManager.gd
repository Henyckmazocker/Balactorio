extends Node

# Clima por zonas (Plan «Eventos Climáticos», M1). Nodo hijo de Main, como el resto de managers
# (el único autoload del proyecto es Augur). Cada ROLL_INTERVAL segundos de run tira una vez;
# si sale, nace un evento del catálogo `WeatherEvents` del JSON sobre un rectángulo del mapa, y
# muere cuando se le acaba la duración.
#
# Los efectos NO se escriben en la casilla: se CONSULTAN (getMultiplierAt / getPassiveAt /
# haltsProductionAt). Un evento que tocase `tileMap.cell_types` dejaría rastro permanente si la
# run se guarda a mitad, y `cell_types` ya se muta en cuatro sitios exactos que no conviene
# ampliar. Consultar es reversible por construcción: cuando el evento sale de `active`, su
# efecto desaparece con él. Desde M2 consumen getMultiplierAt() factoryData._apply_pollution()
# y getPassiveAt() tileMap.tick_passive(); desde M4, getContagionDirectionAt()
# tileMap.tick_contagion().
#
# Plan B 1 del riesgo 🔴, desde el principio: mientras el gameManager tenga abierta la ventana
# de punto muerto (`deadlock_timer > 0`) no se tira, los eventos activos quedan SUSPENDIDOS
# —no descuentan tiempo— y todas las consultas devuelven el valor neutro. Un evento no puede
# ser quien remata una run que ya está agonizando.
#
# Modo «clima agresivo» (M0, para jugar a mano el peor clima): con la variable de entorno
# `BALACTORIO_WEATHER=aggressive` cada tirada sale con la probabilidad al tope (MAX_CHANCE) en vez
# de la escalada por el pico. La lee Main._start_game() con aggressiveFromEnv() y la IGNORA en
# build exportada (`OS.has_feature("template")`), igual que AUGUR_KEY: una build pública nunca
# juega con el clima trucado. Sin la variable no cambia nada. No toca ROLL_INTERVAL ni el plan B 1:
# se tira igual de a menudo y el clima sigue suspendido con la ventana de punto muerto abierta.
#
#   BALACTORIO_WEATHER=aggressive godot-4 --path . res://Main.tscn

signal weather_started(id: String, rect: Rect2i);  # escucha el HUD (M5)
signal weather_ended(id: String);

# Los tres números son un PUNTO DE PARTIDA, NO MEDIDOS: no hay instrumento de cantidades desde
# el 2026-09-23 y los fija el M0 del plan jugando a mano, a la espera del sistema de medición
# nuevo. Cambiarlos no rompe ninguna prueba de relaciones.
const ROLL_INTERVAL: float = 20.0;   # cada 20 s de run se tira una vez
const BASE_CHANCE: float = 0.15;     # suelo, con el mapa limpio
const PEAK_FACTOR: float = 0.004;    # + por punto de pico histórico de contaminación
# Tope de la probabilidad. `peak_pollution` no baja nunca, así que la probabilidad tampoco: sin
# tope, el final de una run sucia sería un evento en cada tirada.
const MAX_CHANCE: float = 0.75;

class WeatherEvent:
	var id: String = "";          # clave del catálogo
	var rect: Rect2i = Rect2i();  # zona afectada, en coordenadas de celda
	var remaining: float = 0.0;   # segundos que le quedan; <= 0 -> se retira
	func _init(p_id = "", p_rect = Rect2i(), p_remaining = 0.0):
		id = p_id;
		rect = p_rect;
		remaining = p_remaining;

var catalog = {};         # id -> dict (bloque `WeatherEvents` del JSON)
var active = [];          # Array de WeatherEvent vivos
var _roll_timer: float = ROLL_INTERVAL;
# Interruptor para la suite y las herramientas: apagado, el manager no tira nunca, pero los
# eventos que se arranquen a mano (startEvent) siguen viviendo y muriendo. Así ninguna prueba
# que monte Main recibe un evento por sorpresa, y las del propio clima lo controlan todo.
var enabled: bool = true;
# Modo «clima agresivo» (ver cabecera): la tirada usa MAX_CHANCE. Lo pone Main al crear el manager.
var aggressive: bool = false;
# Si el nacimiento y la muerte de cada evento salen por consola (M1: todavía no hay HUD que los
# enseñe). La suite lo apaga en las pruebas que tiran cientos de veces.
var log_events: bool = true;
# RNG propio y no el global: sembrarlo (setSeed) hace reproducible la secuencia de tiradas sin
# tocar el azar del resto del juego.
var _rng = RandomNumberGenerator.new();
# Tamaño del mapa en celdas; la zona se recorta contra él. 16x10 es el de los dos mapas de hoy
# y el mismo valor por defecto que usa mapLoader.
var map_size: Vector2i = Vector2i(16, 10);
# Estado vivo que inyecta Main._start_game(), igual que hace con el TileMap: de uno sale el
# pico que escala la probabilidad y del otro la ventana de punto muerto (plan B 1). Se guardan
# los nodos y se miran con is_instance_valid(): un nodo liberado se compara igual que null.
var pollution_manager = null;
var game_manager = null;

func _init():
	_rng.randomize();

func initialize(file_data):
	catalog = file_data.get("WeatherEvents", {});

func setPollutionManager(pm):
	pollution_manager = pm;

func setGameManager(gm):
	game_manager = gm;

func setMapSize(size):
	map_size = Vector2i(int(size[0]), int(size[1]));

func setSeed(seed_value: int):
	_rng.seed = seed_value;

# El reloj corre con el árbol: con la pantalla de cartas el árbol se pausa y este nodo, en
# PROCESS_MODE_INHERIT, deja de correr, que es lo que se quiere.
func _process(delta):
	advance(delta);

# Separado de _process para que la suite avance el reloj a mano.
func advance(delta: float):
	if isSuspended():
		return;
	# La run ya cerrada (o con la pantalla de mejora abierta) congela el clima igual que
	# congela `run_time`.
	if is_instance_valid(game_manager) and not game_manager.active:
		return;
	# Primero envejecen los vivos y luego se tira: un evento que nace en este frame no pierde
	# ya su primer delta.
	var survivors = [];
	for ev in active:
		ev.remaining -= delta;
		if ev.remaining <= 0.0:
			if log_events:
				print("[Clima] termina %s" % ev.id);
			weather_ended.emit(ev.id);
		else:
			survivors.append(ev);
	active = survivors;
	if not enabled:
		return;
	_roll_timer -= delta;
	while _roll_timer <= 0.0:
		_roll_timer += ROLL_INTERVAL;
		_roll();

# Plan B 1: la ventana de punto muerto abierta suspende el clima entero.
func isSuspended() -> bool:
	return is_instance_valid(game_manager) and game_manager.deadlock_timer > 0.0;

# Sale de `peak_pollution` y no de `total_pollution` a propósito: el pico no baja al limpiar,
# así que quien ha producido sin piedad se sigue comiendo el clima aunque limpie después.
func rollChance() -> float:
	if aggressive:
		return MAX_CHANCE;
	var peak = 0.0;
	if is_instance_valid(pollution_manager):
		peak = float(pollution_manager.peak_pollution);
	return min(MAX_CHANCE, BASE_CHANCE + PEAK_FACTOR * peak);

# ¿Pide el entorno el modo agresivo? `is_template` y el valor van por parámetro, como en
# Main._augur_settings(), para que la suite (que nunca es template) pruebe las dos ramas.
static func aggressiveFromEnv(is_template: bool, value: String) -> bool:
	if is_template:
		return false;
	return value.strip_edges().to_lower() == "aggressive";

func _roll():
	if catalog.is_empty():
		return;
	if _rng.randf() >= rollChance():
		return;
	# Claves ordenadas: con la misma semilla sale el mismo evento aunque el JSON cambie de orden.
	var ids = catalog.keys();
	ids.sort();
	var id = ids[_rng.randi_range(0, ids.size() - 1)];
	var center = Vector2i(_rng.randi_range(0, map_size.x - 1), _rng.randi_range(0, map_size.y - 1));
	startEvent(id, zoneAround(id, center));

# La zona del catálogo centrada en `center` y recortada contra el mapa. Centrar en una celda
# al azar y recortar (en vez de elegir una esquina que quepa) deja que el borde también se lleve
# clima, con la zona más pequeña.
func zoneAround(id: String, center: Vector2i) -> Rect2i:
	var zs = catalog.get(id, {}).get("zone_size", [1, 1]);
	var size = Vector2i(int(zs[0]), int(zs[1]));
	return clipToMap(Rect2i(center - size / 2, size));

func clipToMap(rect: Rect2i) -> Rect2i:
	return rect.intersection(Rect2i(Vector2i.ZERO, map_size));

# Arranca un evento del catálogo sobre `rect` (se recorta contra el mapa). Lo usa la tirada, y
# la suite y las herramientas para provocar un evento concreto. Devuelve el evento, o null si
# el id no existe o la zona queda vacía.
func startEvent(id: String, rect: Rect2i):
	if not catalog.has(id):
		push_warning("[Clima] evento desconocido: %s" % id);
		return null;
	var clipped = clipToMap(rect);
	if clipped.size.x <= 0 or clipped.size.y <= 0:
		return null;
	var ev = WeatherEvent.new(id, clipped, float(catalog[id].get("duration", 0.0)));
	active.append(ev);
	if log_events:
		print("[Clima] empieza %s en %s durante %.1f s" % [id, str(clipped), ev.remaining]);
	weather_started.emit(id, clipped);
	return ev;

# Producto de los `pollution_multiplier` de los eventos que cubren la celda: dos sequías
# solapadas se componen, no gana la última. Neutro 1.0.
func getMultiplierAt(cell: Vector2i) -> float:
	var result = 1.0;
	if isSuspended():
		return result;
	for ev in active:
		if ev.rect.has_point(cell):
			result *= float(catalog[ev.id].get("pollution_multiplier", 1.0));
	return result;

# Suma de los `passive_pollution_per_tick` (por SEGUNDO, como en TileTypes: tileMap lo aplica
# escalado por delta desde M2). Neutro 0.0.
func getPassiveAt(cell: Vector2i) -> float:
	var result = 0.0;
	if isSuspended():
		return result;
	for ev in active:
		if ev.rect.has_point(cell):
			result += float(catalog[ev.id].get("passive_pollution_per_tick", 0.0));
	return result;

# Neutro false.
func haltsProductionAt(cell: Vector2i) -> bool:
	if isSuspended():
		return false;
	for ev in active:
		if ev.rect.has_point(cell) and bool(catalog[ev.id].get("halts_production", false)):
			return true;
	return false;

# Dirección del viento sobre la celda (M4), la consulta tileMap.tick_contagion(). Neutro
# Vector2i.ZERO: contagio normal a las 8 vecinas.
# Solape: MANDA EL PRIMER evento activo con viento que cubra la celda —el más antiguo, porque
# `active` guarda el orden de nacimiento—. A diferencia del multiplicador (producto) y del
# pasivo (suma), dos direcciones no se componen en nada coherente: sumar [1,0] y [-1,0] daría
# ZERO, que es «sin viento», y sumar [1,0] y [0,1] daría una diagonal que no pidió ningún
# evento. Quedarse con el más antiguo además es estable: la dirección no salta cuando nace otro.
# Se normaliza a una vecina (componentes en -1..1) con sign(): el JSON podría traer [2, 0] y el
# contagio nunca debe saltar casillas.
func getContagionDirectionAt(cell: Vector2i) -> Vector2i:
	if isSuspended():
		return Vector2i.ZERO;
	for ev in active:
		if not ev.rect.has_point(cell):
			continue;
		var d = catalog[ev.id].get("contagion_direction", null);
		if d == null:
			continue;
		var dir = Vector2i(signi(int(d[0])), signi(int(d[1])));
		if dir != Vector2i.ZERO:
			return dir;
	return Vector2i.ZERO;


# ---------- Serialización de Run (M1) ----------

# Los eventos vivos, la cuenta de la próxima tirada y el estado del RNG, para que reanudar no
# re-baraje el clima. `catalog`, `map_size`, `enabled` y `aggressive` no: salen del JSON y del
# entorno. El Rect2i va como [x, y, w, h] porque JSON tampoco lo conserva.
# 🔴 `_rng.state` es un int de 64 bits y JSON guarda los números como double: pasado tal cual
# pierde los bits bajos y la secuencia de tiradas sería otra. Va como String y vuelve con int().
func snapshot() -> Dictionary:
	var eventos = [];
	for ev in active:
		eventos.append({
			"id": ev.id,
			"rect": [ev.rect.position.x, ev.rect.position.y, ev.rect.size.x, ev.rect.size.y],
			"remaining": float(ev.remaining),
		});
	return {
		"active": eventos,
		"_roll_timer": float(_roll_timer),
		"rng_state": str(_rng.state),
	};

# Serialización de Run (M2): el espejo de snapshot(). Los eventos se reconstruyen DIRECTAMENTE
# en `active` y no por startEvent(), por tres razones: startEvent() les daría la duración entera
# del catálogo y no la que les quedaba, recortaría otra vez una zona que ya se guardó recortada,
# y emitiría `weather_started`, que no es un evento nuevo sino uno que ya empezó. Nadie escucha
# esa señal para pintar —el HUD y el tinte leen `active` cada frame—, así que no emitirla no deja
# nada sin dibujar. Un id que ya no esté en el catálogo se descarta: las consultas indexan
# `catalog[ev.id]` y petarían (con `params_hash` no debería pasar nunca).
# El RNG vuelve por `state` y no por `seed`: la semilla reinicia la secuencia y el estado la deja
# en la tirada exacta en que se guardó. int() del String, porque como número JSON perdería bits.
func restore(d: Dictionary) -> void:
	active = [];
	for e in d.get("active", []):
		var id = String(e.get("id", ""));
		if not catalog.has(id):
			push_warning("[Clima] restore: evento desconocido %s, descartado" % id);
			continue;
		var r = e.get("rect", [0, 0, 0, 0]);
		active.append(WeatherEvent.new(id, Rect2i(int(r[0]), int(r[1]), int(r[2]), int(r[3])),
			float(e.get("remaining", 0.0))));
	_roll_timer = float(d.get("_roll_timer", ROLL_INTERVAL));
	if d.has("rng_state"):
		_rng.state = int(String(d["rng_state"]));
