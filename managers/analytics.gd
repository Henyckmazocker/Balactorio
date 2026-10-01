extends Node

# Analítica de runs (Plan «Analítica de Runs», M1). Nodo hijo de Main, NO autoload: `Augur` es la
# única excepción a esa regla y este nodo es quien habla con él. Lo crea `Main._ready()` antes de
# `_configure_augur()` y `reset()` NO lo libera: vive toda la sesión, como `SaveManager`, porque el
# `run_end` por cierre de ventana (`Augur.closing`) llega con el árbol en cierre.
#
# Tres trabajos:
#   1. Cargar y EXPANDIR `resources/analyticsCatalog.json`, la única lista de eventos y props. Los
#      enums salen de `factoryParams.json` y las familias (`built_*@per_factory`) se abren a una
#      prop por valor, así que añadir una factoría al JSON añade sus props sin tocar el catálogo.
#   2. VALIDAR cada evento contra ese catálogo con tipos cerrados (`int`, `float`, `bool01`,
#      `enum:<nombre>`, `id`). No hay `string` libre. Una prop no declarada, un valor fuera de su
#      enum o un `float` donde va `int` TUMBAN el evento: `track()` devuelve false, avisa y no
#      manda nada. Una prop ausente no se manda (todas son opcionales).
#   3. Atar cada evento de run a su run (`run_id`, `run_t`) y al balance vigente (`balance_id`).
#
# Sin `AUGUR_KEY`, `Augur.track()` no hace nada, así que este nodo tampoco escribe ni abre red. La
# suite sustituye `sink` por uno falso que apila `[name, props]`.
#
# 🔴 Nadie más llama a `Augur.track`: los ganchos llaman a `analytics.track("<evento>", …)`. Lo
# vigila la prueba de atadura de `tests/run_tests.gd`.

const CATALOG_PATH = "res://resources/analyticsCatalog.json";
const PARAMS_PATH = "res://resources/factoryParams.json";
# Las paradas de la muestra se cuentan con la MISMA regla que enseñan el tooltip y el panel
# (que ya calla el `workers` caducado del tick anterior): no se reimplementan aquí.
const BLOCKED_REASON = preload("res://ui/blockedReason.gd");
# `run_sample` cada 10 s de `gameManager.run_time` (M4), no de reloj: se para con las cartas.
const SAMPLE_EVERY = 10.0;
# `segment_rate` cada 1 s de `run_time` (Legibilidad M0), en su propia rejilla: el criterio que
# valida el porcentaje en vivo mira los primeros ~5 s de cada tramo, y `run_sample` a 10 s no
# los ve. Es un evento aparte y no una prop más de `run_sample` para no multiplicar por diez
# una muestra ancha solo por un número.
const SEGMENT_EVERY = 1.0;
const ID_MIN_LEN = 8;
const ID_MAX_LEN = 16;
const BALANCE_ID_LEN = 12;
# Los eventos de acción del jugador: cada uno pone a cero la inactividad (`idle_s`).
const ACTION_EVENTS = ["factory_built", "factory_demolished", "belt_placed", "belt_removed",
	"belt_rejected", "radial_closed", "build_rejected", "click_rejected", "panel_opened",
	"workers_changed", "material_selected", "belt_filter_set"];
const SCALAR_TYPES = ["int", "float", "bool01", "id"];

var sink = func(event_name, props): Augur.track(event_name, props);
# Lo que el censo de `run_end` no puede contar solo (M2): `Main` pone aquí su `_run_end_census()`,
# que devuelve `belt_cells` y `screen` preguntando por sus nodos. Se llama DESPUÉS de leer los
# contadores propios y la Bag, y solo si sigue válido: con la ventana cerrándose Main puede estar
# ya liberándose, y entonces el `run_end` sale sin esas dos props en vez de no salir.
var census_probe = Callable();

# Catálogo expandido. `enums`: nombre -> Array de valores (String). `events`: nombre ->
# {"description", "run", "props": {prop -> {"type": "int|float|bool01|id|enum", "enum": nombre}}}.
var enums = {};
var events = {};
var loaded = false;

var _params_text = "";

# Estado de la run viva. `_run_id == ""` = no hay run.
var _run_id = "";
var _balance_id = "";
var _package_id = "";
var _map_id = "";
var _run_start_ms = 0;
var _game_manager = null;
var _pollution_manager = null;
var _bag = null;
var _tile_map = null;
var _factories = [];
# Contadores propios del censo de `run_end`: se cuentan al pasar los eventos por `track()` y no se
# leen de nodos, porque el `run_end` por cierre de ventana llega con `Main` liberando los suyos.
var _built = {};
var _built_total = 0;
var _demolished_total = 0;
var _cards_chosen = 0;
var _last_action_t = 0.0;
var _last_run_t = 0.0;
# El último umbral de muestreo cruzado (M4), en `run_time`. Va en la rejilla 10, 20, 30… desde el
# `run_time` con que se abrió la run.
var _last_sample_t = 0.0;
# Lo mismo para `segment_rate`, en la rejilla 1, 2, 3…
var _last_segment_t = 0.0;

# Carga y expande el catálogo. `file_data` es el `factoryParams.json` ya parseado (de él salen los
# enums) y `file_text` su texto tal cual se leyó (de él sale `balance_id`); si no llega, se lee.
func initialize(file_data, file_text = "", catalog_path = CATALOG_PATH) -> bool:
	loaded = false;
	enums = {};
	events = {};
	_params_text = file_text if file_text != "" else FileAccess.get_file_as_string(PARAMS_PATH);
	var raw = JSON.parse_string(FileAccess.get_file_as_string(catalog_path));
	if not (raw is Dictionary):
		push_error("Analytics: no se pudo leer el catálogo %s" % catalog_path);
		return false;
	var spec_enums = raw.get("enums", {});
	for enum_name in spec_enums:
		if _resolve_enum(enum_name, spec_enums, file_data, []) == null:
			return false;
	var families = raw.get("families", {});
	var spec_events = raw.get("events", {});
	for event_name in spec_events:
		var ev = _expand_event(event_name, spec_events[event_name], families);
		if ev == null:
			return false;
		events[event_name] = ev;
	loaded = true;
	return true;

# --- Expansión del catálogo -------------------------------------------------------------------

# Resuelve un enum (y los que referencia con "enum") y lo guarda en `enums`. Devuelve null y
# avisa si la fuente no existe en el JSON o sale vacía: un enum vacío tumbaría todos sus eventos.
func _resolve_enum(enum_name, spec_enums, file_data, stack):
	if enums.has(enum_name):
		return enums[enum_name];
	if not spec_enums.has(enum_name) or stack.has(enum_name):
		push_error("Analytics: enum '%s' desconocido o circular" % enum_name);
		return null;
	var spec = spec_enums[enum_name];
	var values = [];
	if spec.has("values"):
		values.append_array(spec["values"]);
	if spec.has("enum"):
		var base = _resolve_enum(spec["enum"], spec_enums, file_data, stack + [enum_name]);
		if base == null:
			return null;
		values.append_array(base);
	if spec.has("from"):
		var sources = spec["from"] if spec["from"] is Array else [spec["from"]];
		for source in sources:
			var got = _values_from(file_data, source);
			if got == null:
				push_error("Analytics: la fuente '%s' del enum '%s' no existe en factoryParams.json" % [source, enum_name]);
				return null;
			values.append_array(got);
	if spec.has("plus_from"):
		var got = _values_from(file_data, spec["plus_from"]["keys"]);
		if got == null:
			push_error("Analytics: la fuente '%s' del enum '%s' no existe" % [spec["plus_from"]["keys"], enum_name]);
			return null;
		for v in got:
			values.append(String(spec["plus_from"].get("prefix", "")) + v);
	values.append_array(spec.get("plus", []));
	var unique = [];
	for v in values:
		var s = String(v);
		if s != "" and not unique.has(s):
			unique.append(s);
	if unique.is_empty():
		push_error("Analytics: el enum '%s' sale vacío" % enum_name);
		return null;
	enums[enum_name] = unique;
	return unique;

# "Bloque" → sus claves (dict) · "Bloque.campo" → el campo de cada valor (dict) o elemento (array);
# un campo array se aplana y un null se salta. null si el bloque no existe.
func _values_from(file_data, path):
	var parts = String(path).split(".");
	if not file_data.has(parts[0]):
		return null;
	var block = file_data[parts[0]];
	if parts.size() == 1:
		return block.keys() if block is Dictionary else null;
	var items = block.values() if block is Dictionary else block;
	var out = [];
	for item in items:
		if not (item is Dictionary):
			continue;
		var v = item.get(parts[1], null);
		if v is Array:
			out.append_array(v);
		elif v != null:
			out.append(v);
	return out;

func _expand_event(event_name, spec, families):
	var props = {};
	var is_run = bool(spec.get("run", false));
	var declared = spec.get("props", {}).duplicate();
	if is_run:
		declared["run_id"] = "id";
		declared["run_t"] = "float";
	for prop_name in declared:
		var type_spec = String(declared[prop_name]);
		var names = [prop_name];
		if type_spec.contains("@"):
			var bits = type_spec.split("@");
			type_spec = bits[0];
			var family = families.get(bits[1], null);
			if family == null or not enums.has(family.get("enum", "")) or not prop_name.contains("*"):
				push_error("Analytics: familia '%s' mal declarada en %s.%s" % [bits[1], event_name, prop_name]);
				return null;
			names = [];
			for v in enums[family["enum"]]:
				names.append(prop_name.replace("*", v));
		var typed = _parse_type(type_spec);
		if typed == null:
			push_error("Analytics: tipo '%s' desconocido en %s.%s" % [type_spec, event_name, prop_name]);
			return null;
		for n in names:
			if props.has(n) or not _valid_prop_name(n):
				push_error("Analytics: prop '%s' repetida o con nombre no válido en %s" % [n, event_name]);
				return null;
			props[n] = typed;
	return { "description": String(spec.get("description", "")), "run": is_run, "props": props };

func _parse_type(type_spec):
	if SCALAR_TYPES.has(type_spec):
		return { "type": type_spec };
	if type_spec.begins_with("enum:") and enums.has(type_spec.substr(5)):
		return { "type": "enum", "enum": type_spec.substr(5) };
	return null;

# El límite de las gráficas de Augur: `^[A-Za-z0-9_]{1,64}$`.
static func _valid_prop_name(n) -> bool:
	var re = RegEx.new();
	re.compile("^[A-Za-z0-9_]{1,64}$");
	return re.search(n) != null;

# El catálogo expandido en el formato de `catalog.upsert` de Augur: enum/id → string,
# int/float/bool01 → number. Lo imprime `tools/export_catalog.gd`.
func export_upsert() -> Array:
	var out = [];
	for event_name in events:
		var ev = events[event_name];
		var properties = {};
		for p in ev["props"]:
			var t = ev["props"][p]["type"];
			properties[p] = { "type": "string" if (t == "enum" or t == "id") else "number" };
		out.append({ "name": event_name, "description": ev["description"], "properties": properties });
	return out;

# --- Validación y envío ------------------------------------------------------------------------

func track(event_name: String, props: Dictionary = {}) -> bool:
	if not events.has(event_name):
		push_warning("Analytics: evento '%s' fuera del catálogo; no se manda" % event_name);
		return false;
	var ev = events[event_name];
	if ev["run"] and _run_id == "":
		push_warning("Analytics: '%s' es de run y no hay run viva; no se manda" % event_name);
		return false;
	var out = {};
	for p in props:
		if not ev["props"].has(p):
			push_warning("Analytics: %s.%s no está declarada; no se manda" % [event_name, p]);
			return false;
		var checked = _coerce(ev["props"][p], props[p]);
		if not checked[0]:
			push_warning("Analytics: %s.%s = %s no cumple su tipo; no se manda" % [event_name, p, str(props[p])]);
			return false;
		out[p] = checked[1];
	if ev["run"]:
		out["run_id"] = _run_id;
		out["run_t"] = _run_time();
	_count(event_name, out);
	if ACTION_EVENTS.has(event_name):
		note_action();
	sink.call(event_name, out);
	return true;

# [ok, valor]. `int` exige int de verdad (JSON.parse_string da float: el que construye los props
# pasa `int()`); `float` acepta int y lo convierte; `bool01` acepta bool y 0/1.
func _coerce(typed, v) -> Array:
	match typed["type"]:
		"int":
			return [typeof(v) == TYPE_INT, v];
		"float":
			if typeof(v) == TYPE_INT:
				return [true, float(v)];
			return [typeof(v) == TYPE_FLOAT and is_finite(v), v];
		"bool01":
			if typeof(v) == TYPE_BOOL:
				return [true, 1 if v else 0];
			return [typeof(v) == TYPE_INT and (v == 0 or v == 1), v];
		"id":
			var re = RegEx.new();
			re.compile("^[0-9a-f]{%d,%d}$" % [ID_MIN_LEN, ID_MAX_LEN]);
			return [typeof(v) == TYPE_STRING and re.search(v) != null, v];
		"enum":
			var ok = (typeof(v) == TYPE_STRING or typeof(v) == TYPE_STRING_NAME) \
				and enums[typed["enum"]].has(String(v));
			return [ok, String(v) if ok else v];
	return [false, v];

func _count(event_name, props):
	match event_name:
		"factory_built":
			var f = props.get("factory", "");
			_built[f] = _built.get(f, 0) + 1;
			_built_total += 1;
		"factory_demolished":
			_demolished_total += 1;
		"card_offered":
			if props.get("chosen", 0) == 1:
				_cards_chosen += 1;

func note_action() -> void:
	_last_action_t = _run_time();

func has_run() -> bool:
	return _run_id != "";

func run_id() -> String:
	return _run_id;

func _run_time() -> float:
	if is_instance_valid(_game_manager):
		_last_run_t = float(_game_manager.run_time);
	return _last_run_t;

# --- Ciclo de la run ---------------------------------------------------------------------------

# Abre la run: genera `run_id` (8 hex), calcula `balance_id` y emite `run_start`. Los nodos se
# guardan para el censo de `run_end` (y el muestreo del M4).
# `resumed_from` (Serialización de Run, M4): el `run_id` de la run guardada que esta continúa. La
# reanudada es una run NUEVA con `run_id` propio —la guardada ya mandó su `run_end` con
# `suspend` al cerrar—, y este enlace es lo único que las une. Vacío en una run nueva: entonces
# la prop no sale.
func begin_run(game_manager, pollution_manager, bag, tile_map, factories, package_id, map_id, resumed_from := "") -> void:
	if _run_id != "":
		push_warning("Analytics: begin_run() con la run %s aún viva; se descarta sin run_end" % _run_id);
	_game_manager = game_manager;
	_pollution_manager = pollution_manager;
	_bag = bag;
	_tile_map = tile_map;
	_factories = factories if factories != null else [];
	_package_id = String(package_id);
	_map_id = String(map_id);
	_built = {};
	_built_total = 0;
	_demolished_total = 0;
	_cards_chosen = 0;
	_last_run_t = 0.0;
	_run_id = Crypto.new().generate_random_bytes(4).hex_encode();
	_run_start_ms = Time.get_ticks_msec();
	_last_action_t = _run_time();
	_last_sample_t = _last_action_t;
	_last_segment_t = _last_action_t;
	var constants = run_constants(pollution_manager, game_manager);
	_balance_id = balance_id(_params_text, constants);
	var props = { "package": _package_id, "map": _map_id, "balance_id": _balance_id };
	props.merge(constants);
	# Solo si es un id válido: viene de un fichero en disco, y uno estropeado haría que track()
	# rechazara el `run_start` entero —la run se quedaría sin abrir para el tablero— por un
	# enlace que es accesorio.
	if resumed_from != "":
		if _coerce({"type": "id"}, resumed_from)[0]:
			props["resumed_from"] = resumed_from;
		else:
			push_warning("Analytics: resumed_from '%s' no es un id; run_start sale sin él" % resumed_from);
	track("run_start", props);

# Cierra la run con su censo, UNA vez: sin run viva no hace nada. Lo que `analytics` no puede saber
# por sí mismo —`belt_cells`, `screen`— lo pregunta a `census_probe`; `extra` completa o corrige
# lo anterior, y todo pasa el mismo validador.
func end_run(result: String, extra: Dictionary = {}) -> bool:
	if _run_id == "":
		return false;
	var t = _run_time();
	var census = {
		"result": result,
		"duration_ms": int(Time.get_ticks_msec() - _run_start_ms),
		"package": _package_id,
		"map": _map_id,
		"balance_id": _balance_id,
		"built_total": _built_total,
		"demolished_total": _demolished_total,
		"cards_chosen": _cards_chosen,
		"idle_s": max(0.0, t - _last_action_t),
	};
	for f in enums.get("factory", []):
		census["built_" + f] = int(_built.get(f, 0));
	if is_instance_valid(_bag):
		for m in enums.get("material", []):
			census["left_" + m] = int(_bag.getAvailable(m));
		census["workers_free"] = int(_bag.getFreeWorkers());
		census["workers_total"] = int(_bag.workers_total);
	if is_instance_valid(_game_manager):
		census["checkpoints"] = int(_game_manager.current_checkpoint_index);
	if is_instance_valid(_pollution_manager):
		census["final_pollution"] = float(_pollution_manager.total_pollution);
		census["peak_pollution"] = float(_pollution_manager.peak_pollution);
	if census_probe.is_valid():
		var probed = census_probe.call();
		if probed is Dictionary:
			census.merge(probed, true);
	census.merge(extra, true);
	var sent = track("run_end", census);
	_run_id = "";
	_game_manager = null;
	_pollution_manager = null;
	_bag = null;
	_tile_map = null;
	_factories = [];
	return sent;

# --- Muestra de estado (M4) -------------------------------------------------------------------

# `run_sample` cada SAMPLE_EVERY de `run_time` y `segment_rate` cada SEGMENT_EVERY, con la
# misma rejilla y las mismas reglas. El nodo va en PROCESS_MODE_INHERIT (el de Main):
# con el árbol pausado no se llama, y con las cartas (`active = false`) el `run_time` congelado
# no cruza umbral. Se lee `run_time` y no se acumula `delta`, así que tampoco cuenta el tiempo
# que el árbol estuvo pausado.
#
# UNA muestra por frame aunque un frame largo salte dos umbrales: `_last_sample_t` salta al
# último umbral cruzado (rejilla fija, sin muestras de recuperación con un `run_t` que no es el
# suyo). Tras `reset()` Main libera gameManager y compañía sin que este nodo muera: sin
# `gameManager` válido no se muestrea.
func _process(_delta) -> void:
	if _run_id == "" or not is_instance_valid(_game_manager):
		return;
	var t = float(_game_manager.run_time);
	if t - _last_segment_t >= SEGMENT_EVERY:
		_last_segment_t += floor((t - _last_segment_t) / SEGMENT_EVERY) * SEGMENT_EVERY;
		var seg = build_segment_rate();
		if not seg.is_empty():
			track("segment_rate", seg);
	if t - _last_sample_t < SAMPLE_EVERY:
		return;
	_last_sample_t += floor((t - _last_sample_t) / SAMPLE_EVERY) * SAMPLE_EVERY;
	track("run_sample", build_sample());

# Las props de `segment_rate`, o {} si no toca mandarlo. Solo en la fase de producción y solo
# con número: el −1.0 centinela (tramo sin integral) se calla, con el mismo criterio que el
# `rate` de `checkpoint_reached`, porque falsearía cualquier media. `checkpoint` es el tramo EN
# CURSO en 1-based (`current_checkpoint_index + 1`), el mismo número que llevará el
# `checkpoint_reached` que lo cierre: las dos tablas se cruzan por `run_id` + `checkpoint`.
func build_segment_rate() -> Dictionary:
	if not is_instance_valid(_game_manager) or _game_manager.production_done:
		return {};
	var rate = float(_game_manager.segmentLiveRate(_bag if is_instance_valid(_bag) else null));
	if rate < 0.0:
		return {};
	return {
		"checkpoint": int(_game_manager.current_checkpoint_index) + 1,
		"seg_t": max(0.0, float(_game_manager.run_time) - float(_game_manager.last_checkpoint_time)),
		"rate": rate,
	};

# Las props de `run_sample` leídas en el momento. Cada referencia se comprueba por separado: la
# que ya no es válida deja sus props fuera (todas son opcionales) en vez de tumbar la muestra.
func build_sample() -> Dictionary:
	var t = _run_time();
	var s = { "idle_s": max(0.0, t - _last_action_t) };
	if is_instance_valid(_game_manager):
		s["checkpoint"] = int(_game_manager.current_checkpoint_index);
		var opened = float(_game_manager.deadlock_timer);
		s["deadlock_s"] = max(0.0, t - opened) if opened > 0.0 else 0.0;
		# Climas vivos en este instante, suspendidos incluidos (con el punto muerto abierto siguen en
		# `active`, solo dejan de actuar). Se lee por el gameManager, que ya lleva su weatherManager
		# inyectado: analytics no tiene referencia propia, y sin clima (la suite) vale 0.
		var wm = _game_manager.weather_manager;
		s["weather_active"] = int(wm.active.size()) if is_instance_valid(wm) else 0;
	if is_instance_valid(_pollution_manager):
		s["pollution"] = float(_pollution_manager.total_pollution);
		s["peak"] = float(_pollution_manager.peak_pollution);
		var limit = float(_pollution_manager.cell_block_pollution);
		var saturated = 0;
		for cell in _pollution_manager.pollution_per_cell:
			if float(_pollution_manager.pollution_per_cell[cell]) >= limit:
				saturated += 1;
		s["saturated_cells"] = saturated;
	if is_instance_valid(_tile_map):
		var toxic = 0;
		for cell in _tile_map.cell_types:
			if _tile_map.cell_types[cell] == "toxic":
				toxic += 1;
		s["toxic_cells"] = toxic;
	if is_instance_valid(_bag):
		for m in enums.get("material", []):
			s["stock_" + m] = int(_bag.getQuantity(m));
			s["avail_" + m] = int(_bag.getAvailable(m));
		s["workers_free"] = int(_bag.getFreeWorkers());
		s["workers_total"] = int(_bag.workers_total);
	# `_factories` es el `factoryArray` de Main, el vivo: crece al construir y mengua al demoler.
	var alive = {};
	# Las mismas claves que el enum `blocked` del catálogo (menos "none") y que `blocked_*` de
	# `run_sample`: una razón que falte aquí no se cuenta, y una que sobre no pasa el validador.
	var blocked = { "workers": 0, "storm": 0, "input": 0, "output": 0, "choke": 0 };
	for fab in _factories:
		if not is_instance_valid(fab) or fab.is_queued_for_deletion():
			continue;
		var kind = String(fab.type);
		alive[kind] = alive.get(kind, 0) + 1;
		var reason = BLOCKED_REASON.reason_now(fab);
		if blocked.has(reason):
			blocked[reason] += 1;
	for f in enums.get("factory", []):
		s["n_" + f] = int(alive.get(f, 0));
	for reason in blocked:
		s["blocked_" + reason] = int(blocked[reason]);
	return s;

# --- Balance -----------------------------------------------------------------------------------

# Los valores provisionales con los que se juega la run (los de `run_start`), de donde viven hoy.
static func run_constants(pollution_manager, game_manager) -> Dictionary:
	return {
		"contagion_rate": float(pollution_manager.contagion_rate),
		"deadlock_grace": float(game_manager.DEADLOCK_GRACE),
		"tier2_efficiency": float(game_manager.TIER2_EFFICIENCY),
		"restoration_base": float(pollution_manager.restoration_base),
		"restoration_peak_factor": float(pollution_manager.restoration_peak_factor),
		"cell_block_pollution": float(pollution_manager.cell_block_pollution),
		"contagion_pollution": float(pollution_manager.contagion_pollution),
		"pollution_threshold": float(pollution_manager.pollution_threshold),
	};

# SHA-256 del texto de `factoryParams.json` tal cual se leyó + las constantes con claves
# ordenadas → 12 hex. Cambia con CUALQUIER cambio del JSON (también textos de cartas): es un
# identificador, no una distancia.
static func balance_id(file_text: String, constants: Dictionary) -> String:
	var ctx = HashingContext.new();
	ctx.start(HashingContext.HASH_SHA256);
	ctx.update(file_text.to_utf8_buffer());
	ctx.update(JSON.stringify(constants, "", true).to_utf8_buffer());
	return ctx.finish().hex_encode().substr(0, BALANCE_ID_LEN);
