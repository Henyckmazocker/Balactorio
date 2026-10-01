extends Node

# La razón de parada tal y como se ENSEÑA ahora mismo, que no siempre es `blocked_reason` a
# pelo: la prioridad 1 se lee viva de `isActive()`, porque el campo solo se escribe una vez por
# tick. Se pregunta por aquí y no por el campo para que el tooltip no pueda discrepar del panel
# ni del marcador del mapa, que ya preguntan por este mismo sitio.
const BLOCKED_REASON = preload("res://ui/blockedReason.gd");
const ConsentScreen = preload("res://ui/consentScreen.gd");
# La clave de prod de las builds (M2 del plan de builds públicas). La genera `tools/export.sh`, está
# en `.gitignore` y solo se lee en build exportada: ver `_augur_settings()`.
const AUGUR_RELEASE_CFG = "res://augur_release.cfg";
# El fichero de la run en curso (Plan «Serialización de Run»). En M1 solo la versión del formato
# y la conversión de celdas a "x,y", que es lo que necesita _capture_run().
const RunSave = preload("res://managers/runSave.gd");

var factoryArray = [];
var file = "resources/factoryParams.json";
var fileData;
var gameManager;
var pollutionManager;
var saveManager;
var analytics;
var mapLoader;
var placer;
var beltNetwork;
# Clima por zonas (Plan «Eventos Climáticos», M1). Hermano de los demás managers: nodo hijo de
# Main creado en _start_game(), no autoload.
var weatherManager;
# Interruptor del clima para la suite y las herramientas: una prueba que monta Main lo pone a
# false ANTES de _start_game() y la run nace con el clima apagado —no tira nunca—, así que la
# suite no puede volverse aleatoria. El juego lo deja siempre a true.
var weather_enabled: bool = true;
var _hovered_factory = null;
# La razón con la que se pintó el tooltip que hay en pantalla ahora mismo (M4). El tooltip no se
# repinta solo: `_update_hover_tooltip()` solo lo reconstruía cuando el cursor cambiaba de
# factoría, así que con el ratón quieto sobre una que se para —o que vuelve a producir— el
# contenido se quedaba de hace rato y contradecía al marcador que esa misma casilla lleva pintado
# en el mapa. Guardando aquí lo que el tooltip DICE se puede comparar por frame contra lo que la
# factoría ES y reconstruirlo solo cuando difieren, que es el criterio con el que
# `ui/factoryPanel.gd` repinta su línea: rehacer un CanvasLayer entero a 60 fps es caro.
var _hovered_reason = "";
# Celda donde se pulsó el botón izquierdo, mientras el botón sigue abajo. El gesto es lo que
# desambigua construir de tender cinta: ver _unhandled_input().
var _drag_start_cell = null;

# 🔴 SIN VENTANA NO HAY HUD QUE LEER NI RATÓN QUE PREGUNTAR (M0b, 2026-09-21). `_process()`
# reconstruía por frame las dos líneas del HUD —`_buildResourceText()` y los ~155 caracteres
# de `gameManager.getObjectiveText()`, con su aviso de colapso, su mantenimiento reservado y
# su cola de contaminación (`HUD_MAX_CHARS`)— y repintaba el hover del ratón. Sin ventana
# (la suite, headless) no hay ratón ni nadie que lea ese trabajo.
# Quién decide: `DisplayServer.get_name()`, que con `--headless` vale exactamente "headless"
# —es el único servidor que el motor monta sin ventana— y se pregunta UNA vez al instanciar el
# nodo, no por frame. Es `var` y no `const` a propósito: es el único punto por el que la suite
# puede fijar el contrato EN LOS DOS SENTIDOS (bloque «Rendimiento M0b» de run_tests.gd), y lo
# que aquí se apaga es solo el HUD sin ventana — con ventana se construye exactamente como
# siempre, que es lo que el jugador lee.
var render_enabled: bool = DisplayServer.get_name() != "headless";

# Analítica de runs (Plan «Analítica de Runs», M2). El `run_end` una sola vez por run lo guarda
# `analytics.end_run()`, que es idempotente: ganar y luego pulsar `R`, o la `R` desde el menú sin
# run, no mandan nada. Aquí solo queda lo que `analytics` no puede saber por sí mismo:
# - el mapa que eligió `pick_map()`, para `run_start`/`run_end`;
# - la oferta de cartas en pantalla, para mandar al elegir una fila de `card_offered` por carta
#   (`slot` 1..N: las ruinas ofrecen una sola) con `decision_ms` desde que se montó;
# - el `run_time` del checkpoint anterior, para el `seg_t` de `checkpoint_reached`.
var _run_map_id := "";
var _offer_ids := [];
var _offer_source := "";
var _offer_checkpoint := 0;
var _offer_ms := 0;
var _prev_checkpoint_t := 0.0;
# Serialización de Run (M1). El paquete con el que arrancó la run: hasta ahora solo lo recibía
# _start_game() y se perdía al salir de ella, y el snapshot lo necesita para que la run reanudada
# diga de qué paquete viene. Lo asigna _start_game(); "" sin run.
var _run_package_id := "";
# La huella del JSON de balance con la que se leyó esta sesión (`Analytics.balance_id()` sobre el
# texto tal cual, sin constantes): un snapshot de otro balance puede citar factorías o materiales
# que ya no existen y se tira entero (M3). Se calcula una vez en _ready(), con el texto a mano.
var _params_hash := "";
# El fichero de la run en curso (M3). Una sola instancia, la única que lo toca: su `path` sale
# de `RunSave.default_path` al construirse Main, que es como la suite lo aparta del real.
var runSave = RunSave.new();
# Autoguardado (M4): cada AUTOSAVE_INTERVAL segundos de mundo se escribe la run, para que matar el
# proceso —sin cierre de ventana que avise— pierda como mucho eso. Se acumula en _tick_world(),
# que solo corre con el árbol sin pausar: con las cartas o el resumen en pantalla no hay nada
# nuevo que guardar. Vuelve a 0 en cada run que se monta.
const AUTOSAVE_INTERVAL: float = 20.0;
var _autosave_t: float = 0.0;
# true tras `Augur.configure()` en `_configure_augur()` (Plan «Builds Públicas con Consentimiento»,
# M1). Sin él no se pregunta el consentimiento ni sale «Privacidad» en el menú.
var _augur_enabled := false;

@export var factory: PackedScene
@export var player: PackedScene
@export var grid: PackedScene

func _ready():
	var json_as_text = FileAccess.get_file_as_string(file);
	fileData = JSON.parse_string(json_as_text);
	_params_hash = load("res://managers/analytics.gd").balance_id(json_as_text, {});

	# Analítica de runs (Plan «Analítica de Runs», M1): la única que habla con `Augur`. Va ANTES de
	# _configure_augur(), que en M2 le ata el `Augur.closing`, y vive toda la sesión como el
	# SaveManager: reset() no la libera, porque el `run_end` por cierre de ventana llega con los
	# nodos de la run ya liberándose. Recibe el texto del JSON tal cual se leyó para `balance_id`.
	analytics = load("res://managers/analytics.gd").new();
	analytics.name = "Analytics";
	add_child(analytics);
	analytics.initialize(fileData, json_as_text);
	# Lo que el censo de `run_end` no puede contar solo: cintas y pantalla abierta (M2).
	analytics.census_probe = _run_end_census;

	_configure_augur();
	saveManager = load("res://managers/saveManager.gd").new();
	saveManager.name = "SaveManager";
	add_child(saveManager);

	mapLoader = load("res://managers/mapLoader.gd").new();

	# Plan «Builds Públicas con Consentimiento», M1: sin decisión en disco se pregunta ANTES de
	# que exista el menú, y el menú nace en `decided`. Sin Augur configurado no hay nada que
	# preguntar y se va derecho al menú, como siempre.
	if _augur_enabled and not Augur.has_consent_decision():
		_show_consent_screen(ConsentScreen.MODE_FIRST_RUN);
	else:
		_show_main_menu();

# El menú principal. Solo lo crea `_ready()`, directamente o tras la primera decisión de
# consentimiento: `reset()` vuelve a `packageSelect`, no aquí.
func _show_main_menu():
	var menu = load("res://ui/mainMenu.gd").new();
	menu.name = "MainMenu";
	# Serialización de Run (M5): «CONTINUAR» solo con un save que valga para este balance.
	# exists_valid() no borra; el de otro balance lo tira read_valid() al pulsar JUGAR o continuar.
	# initialize() ANTES de add_child(): si no, el _ready() del menú lo construía una vez sin
	# saveManager y initialize() otra encima, y debajo quedaba un «JUGAR» sin la confirmación.
	menu.initialize(saveManager, _augur_enabled, runSave.exists_valid(_params_hash));
	add_child(menu);
	menu.play_pressed.connect(_on_menu_play);
	menu.continue_pressed.connect(_on_menu_continue);
	menu.privacy_pressed.connect(_on_privacy_pressed);
	analytics.track("ui_open", {"screen": "main_menu"});

# «JUGAR» (con run guardada, ya confirmado «Empezar nueva»): la run guardada se borra ANTES de
# elegir paquete. Borra aquí y no el menú porque el menú no toca disco; sin save es un no-op.
func _on_menu_play():
	runSave.clear();
	_show_package_select();

# «CONTINUAR». Si el save dejó de valer entre que se pintó el menú y el click (read_valid() ya lo
# ha borrado), se cae a elegir paquete: el menú ya se ha liberado y la pantalla quedaría en negro.
func _on_menu_continue():
	if not _continue_from_file():
		_show_package_select();

# Monta la pantalla de consentimiento. La pantalla no toca `Augur`: la decisión vuelve por
# `decided` y el SDK lo llama Main, que es quien sabe si está configurado.
func _show_consent_screen(mode: String):
	var screen = ConsentScreen.new();
	screen.name = "ConsentScreen";
	add_child(screen);
	screen.initialize(mode, Augur.has_consent());
	if mode == ConsentScreen.MODE_FIRST_RUN:
		screen.decided.connect(_on_first_consent);
	else:
		screen.decided.connect(_on_consent_changed);

# Primer arranque: se guarda la decisión y AHORA nace el menú. Con «Aceptar» `set_consent(true)`
# abre la sesión antes del `ui_open` del menú, así que ese evento ya entra en ella; con «No,
# gracias» `track()` no escribe nada.
func _on_first_consent(granted: bool):
	Augur.set_consent(granted);
	_show_main_menu();

# Desde «Privacidad»: el menú sigue debajo. Solo se llama al SDK si la decisión cambia; retirarla
# (`set_consent(false)`) borra la cola local, que es lo que promete el texto.
func _on_consent_changed(granted: bool):
	if granted != Augur.has_consent():
		Augur.set_consent(granted);

func _on_privacy_pressed():
	if get_node_or_null("ConsentScreen") != null:
		return;
	_show_consent_screen(ConsentScreen.MODE_CHANGE);

# Enciende Augur si hay clave (Plan «Builds Públicas con Consentimiento», M1-M2). Sin clave no se
# llama a nada y el autoload `Augur` no escribe en disco ni abre red: la suite y cualquier partida
# normal se quedan exactamente como antes, y tampoco se pregunta nada (`_augur_enabled` sigue en
# false). Con clave, el consentimiento NO lo da el entorno: lo pide la pantalla de consentimiento en
# el primer arranque y se cambia desde «Privacidad», también en el editor. De dónde sale la clave
# lo decide `_augur_settings()`: entorno en el editor, `res://augur_release.cfg` en build.
func _configure_augur():
	var settings := _augur_settings(OS.has_feature("template"), AUGUR_RELEASE_CFG);
	var key: String = settings["key"];
	if key == "":
		return;
	var endpoint: String = settings["endpoint"];
	if endpoint == "":
		endpoint = "http://localhost:8897";
	Augur.configure(key, endpoint);
	# El SDK no expone si está configurado (`_configured` es privado), así que Main lleva su propia
	# cuenta: de ella cuelgan la pantalla del primer arranque y el botón «Privacidad».
	_augur_enabled = true;
	# Cerrar la ventana con una run viva la GUARDA y la cierra como `suspend` (Serialización M4;
	# antes era `abandon`: con «Continuar», cerrar ya no es abandonar). Va por la señal del SDK
	# porque el autoload recibe el cierre antes que Main y mandaría su `session_end` primero. Sin
	# run viva `end_run()` no hace nada. Los Main de la suite no tienen analytics.
	if analytics:
		Augur.closing.connect(_on_app_closing);

# Clave y endpoint de Augur según dónde corre el juego. En una build exportada (`template`, true
# también en las debug) salen de `res://augur_release.cfg`, que escribe `tools/export.sh` dentro del
# `.pck` y borra al acabar: una build pública no tiene entorno, y rotar la clave no pide commit. En
# el editor salen de `AUGUR_KEY`/`AUGUR_ENDPOINT` y el `.cfg` se IGNORA aunque exista (p. ej. si un
# export se cortó a medias): desde el editor nunca se manda a prod. `is_template` y `cfg_path` van
# por parámetro para que la suite, que nunca es template, pruebe las dos ramas sin exportar.
func _augur_settings(is_template: bool, cfg_path: String) -> Dictionary:
	var key := "";
	var endpoint := "";
	if is_template:
		var cfg := ConfigFile.new();
		if cfg.load(cfg_path) == OK:
			key = str(cfg.get_value("augur", "write_key", "")).strip_edges();
			endpoint = str(cfg.get_value("augur", "endpoint", "")).strip_edges();
	else:
		key = OS.get_environment("AUGUR_KEY");
		endpoint = OS.get_environment("AUGUR_ENDPOINT");
	return {"key": key, "endpoint": endpoint};

# Cierra la run para la analítica (M2). `end_run()` es idempotente por run y, sin `AUGUR_KEY`, su
# `Augur.track()` no hace nada. Los Main de la suite montados sin `_ready()` no tienen analytics.
func _end_run(result):
	if analytics:
		analytics.end_run(result);

# Lo que `run_end` necesita de Main y `analytics` no cuenta solo: las casillas de cinta y qué
# pantalla había abierta al acabar. Lo llama `analytics.end_run()` DESPUÉS de leer sus contadores
# y la Bag; con la ventana cerrándose (`Augur.closing`) los nodos pueden estar ya fuera, así que
# todo se pregunta con `is_instance_valid()` y lo que falte no se manda.
func _run_end_census() -> Dictionary:
	var extra = {"screen": _open_screen()};
	if is_instance_valid(beltNetwork):
		extra["belt_cells"] = int(beltNetwork.belt_count());
	return extra;

# La pantalla abierta, de más a menos modal. Un nodo en cola de borrado ya no lo ve el jugador.
func _open_screen() -> String:
	for pair in [["RunSummary", "run_summary"], ["UpgradeScreen", "upgrade"], ["TokenUnlock", "token"],
			["FactoryPanel", "panel"], ["RadialMenu", "radial"]]:
		var node = get_node_or_null(pair[0]);
		if node != null and not node.is_queued_for_deletion():
			return pair[1];
	return "none";

# Los eventos de run solo con run viva: sin ella `track()` los rechaza con un aviso, y los Main
# de la suite montados a mano ni siquiera tienen analytics.
func _run_tracked() -> bool:
	return analytics != null and analytics.has_run();

func _show_package_select():
	var screen = load("res://ui/packageSelect.gd").new();
	screen.name = "PackageSelect";
	add_child(screen);
	screen.initialize(fileData, saveManager);
	screen.package_chosen.connect(_start_game);
	if analytics:
		analytics.track("ui_open", {"screen": "package_select"});

# Serialización de Run (M2): el arranque está partido en dos. Lo que ELIGE —el paquete, que
# `apply_package()` SUMA a la bolsa, y el mapa, que `pick_map()` baraja— se queda aquí y solo
# corre en una run nueva; el CABLEADO de managers, con su orden justificado, vive en
# _mount_run() y lo comparte _continue_game(). Duplicarlo garantizaría que las dos copias
# divergieran en el próximo plan que añada un manager.
func _start_game(package_id = "standard"):
	_mount_player_and_grid();

	# Aplicar paquete de inicio
	_run_package_id = String(package_id);
	mapLoader.apply_package(package_id, fileData, get_node("Player"), get_node("Player").get_node("Bag"));

	# Elegir mapa de la run. Va antes de _mount_run() —y no entre el placer y apply_map() como
	# cuando todo vivía aquí— porque pick_map() solo lee el JSON y el saveManager: adelantarlo no
	# cambia nada de lo que se monta después.
	var map_data = mapLoader.pick_map(fileData, saveManager);
	_run_map_id = String(map_data.get("id", ""));
	_mount_run(map_data, true);
	_offer_ids = [];
	_prev_checkpoint_t = 0.0;
	# La run empieza para la analítica: `run_id`, `balance_id` y `run_start` (M2).
	if analytics:
		analytics.begin_run(gameManager, pollutionManager, get_node("Player").get_node("Bag"),
			get_node("TileMap"), factoryArray, package_id, _run_map_id);

# El Player y el TileMap de la run, con la bolsa con sus claves a 0. Es el paso 1 de los dos
# caminos de arranque: una run nueva le suma después el paquete; una reanudada, nada —la bolsa
# guardada la pisa al final de _continue_game()—.
func _mount_player_and_grid():
	var playerNode = player.instantiate();
	add_child(playerNode);
	var playGrid = grid.instantiate();
	add_child(playGrid);
	get_node("Player").get_node("Bag").initialize(fileData);

# El cableado de una run sobre un mapa ya elegido: managers, inyecciones y señales, en el orden
# que justifica cada comentario. `storage` dice si apply_map() construye el almacén del mapa: en
# una run nueva sí; al reanudar NO, porque el almacén vuelve como una factoría más del snapshot
# y construirlo aquí daría dos en la misma celda (sin `storage_ctx`, place_storage() devuelve
# null sin tocar nada).
func _mount_run(map_data: Dictionary, storage: bool):
	# El reloj del autoguardado es de la run: lo acumulado por la anterior no adelanta el primero.
	_autosave_t = 0.0;
	pollutionManager = load("res://managers/pollutionManager.gd").new();
	pollutionManager.name = "PollutionManager";
	add_child(pollutionManager);
	get_node("TileMap").setPollutionManager(pollutionManager);
	# Y el bloque `Factories` del JSON, del que canPlaceFactory() saca el `requires_adjacent`
	# de la depuradora (Variedad M4). Va aquí, junto a las otras inyecciones y ANTES de
	# apply_map(), porque el mapa coloca su almacén nada más generarse y la regla tiene que
	# estar puesta desde la primera pregunta de colocación de la run.
	get_node("TileMap").setFactoryParams(fileData.get("Factories", {}));

	# FactoryPlacer — lógica de colocación desacoplada de Main. Va ANTES de apply_map() desde
	# M3: el mapa arranca con un almacén ya construido en su `storage_cell` y quien lo
	# construye es el placer. No depende del TileMap ni del mapa, así que adelantarlo no
	# cambia nada más.
	placer = load("res://entities/factory/factoryPlacer.gd").new();
	placer.initialize(factory, fileData, factoryArray);

	# Aplicar mapa de la run
	var storage_ctx = null;
	if storage:
		storage_ctx = {
			"placer": placer,
			"parent": self,
			"player": get_node("Player"),
			"bag": get_node("Player").get_node("Bag"),
			"factories": factoryArray,
			# Desde M5 el almacén EMITE, así que su `resource_produced` tiene que llegar al mismo
			# encaminador que el de cualquier otra factoría. Va atado igual que en
			# _on_factory_chosen(): la señal solo lleva la posición de mundo y deliver() necesita
			# la celda, así que place_storage() le bindea el nodo.
			"on_produced": _on_resource_produced,
		};
	mapLoader.apply_map(map_data, pollutionManager, get_node("TileMap"), fileData, storage_ctx);

	# Red de cintas — hermana de pollutionManager: nodo hijo de Main, no autoload. Va DESPUÉS
	# de apply_map() porque su overlay cuelga del TileMap ya generado, y antes del gameManager
	# porque canPlaceFactory() —la condición 3 del punto muerto— pasa a consultarla.
	beltNetwork = load("res://managers/beltNetwork.gd").new();
	beltNetwork.name = "BeltNetwork";
	add_child(beltNetwork);
	# El array de factorías va vivo, no una copia: `placer` lo muta al construir y
	# _demolish_at_cell() al demoler, y de él sale el destino del camino en deliver(). Y el
	# `fileData` entra por lo mismo que en el placer: de él sale el precio por casilla de
	# cinta (`Belts.cost_per_cell`, Costes M3), que se lee del JSON y nunca se hardcodea.
	beltNetwork.initialize(get_node("TileMap"), factoryArray, fileData);
	get_node("TileMap").setBeltNetwork(beltNetwork);
	# Y la misma lista viva al TileMap, que desde el M2 de «Feedback de Cuellos de Botella»
	# pinta el estado de cada factoría parada por su StatusOverlay. Va por referencia y no en
	# copia por lo mismo que la línea de arriba: `placer` la muta al construir y
	# _demolish_at_cell() al demoler, y un icono de parada sobre una casilla ya vacía sería
	# peor que no pintar nada.
	get_node("TileMap").setFactories(factoryArray);

	gameManager = load("res://managers/gameManager.gd").new();
	gameManager.name = "GameManager";
	add_child(gameManager);
	gameManager.initialize(fileData);
	# La baraja de mejoras necesita saber qué factorías tiene ya esta partida para no ofrecer
	# un desbloqueo que no desbloquea nada. Se le pasa el nodo y no la lista: _apply_upgrade()
	# y el factory token la amplían sobre la marcha, y una copia se quedaría vieja. Va aquí,
	# antes de cualquier _pick_upgrades(), así que la mejora gratis de las ruinas también
	# sale ya filtrada.
	gameManager.setPlayer(get_node("Player"));
	# Y la línea de producción viva, que desde M7 es la vara con la que se juzga el tramo: el
	# tier ya no compara contra una factoría imaginaria sino contra lo que esta fábrica podría
	# estar dando. Se le pasa el array, no una copia, por lo mismo que el Player: `placer` lo
	# muta al construir y `_demolish_at_cell()` al demoler.
	gameManager.setFactories(factoryArray);
	# Y el TileMap, tercer trozo de estado vivo y por el mismo motivo que los dos de arriba:
	# quién sabe qué casillas existen y cuáles admiten factoría es el mapa, no el JSON. Sin
	# esta línea el punto muerto no se evalúa nunca y la run no se puede perder. Va aquí, con
	# el playGrid ya instanciado por _mount_player_and_grid().
	gameManager.setTileMap(get_node("TileMap"));
	# Y al revés: el TileMap pinta el tinte de colapso leyendo la ventana del punto muerto del
	# gameManager (Plan «Legibilidad de la Run», M4). Va aquí porque es el primer punto en que
	# existe el gameManager de ESTA run; el de la anterior ya no vale.
	get_node("TileMap").setGameManager(gameManager);
	gameManager.checkpoint_reached.connect(_on_checkpoint_reached);
	gameManager.run_won.connect(_on_run_won);
	gameManager.run_lost.connect(_on_run_lost);
	gameManager.deadlock_opened.connect(_on_deadlock_opened);
	gameManager.deadlock_closed.connect(_on_deadlock_closed);
	# Clima (Plan «Eventos Climáticos», M1). Va DESPUÉS del gameManager porque le hace falta el
	# de ESTA run: de su `deadlock_timer` sale el plan B 1 (ventana de punto muerto abierta =
	# clima suspendido). Del pollutionManager sale el pico que escala la probabilidad, y del
	# mapa elegido el tamaño contra el que se recorta cada zona.
	weatherManager = load("res://managers/weatherManager.gd").new();
	weatherManager.name = "WeatherManager";
	weatherManager.initialize(fileData);
	weatherManager.setPollutionManager(pollutionManager);
	weatherManager.setGameManager(gameManager);
	weatherManager.setMapSize(map_data.get("size", [16, 10]));
	weatherManager.enabled = weather_enabled;
	# M0: `BALACTORIO_WEATHER=aggressive` pone cada tirada al tope (MAX_CHANCE); ignorada en build
	# exportada, como AUGUR_KEY.
	weatherManager.aggressive = weatherManager.aggressiveFromEnv(
		OS.has_feature("template"), OS.get_environment("BALACTORIO_WEATHER"));
	if weatherManager.aggressive:
		print("[Clima] modo agresivo: probabilidad %.2f en cada tirada" % weatherManager.MAX_CHANCE);
	add_child(weatherManager);
	# M2: la lluvia se aplica desde tick_passive(), que corre en el TileMap cada frame; se le
	# inyecta como al pollutionManager en vez de buscarse en el árbol. La sequía no necesita
	# inyección: las factorías lo preguntan a su padre (Main) por nombre.
	get_node("TileMap").setWeatherManager(weatherManager);
	# M5: el aviso del HUD. El gameManager lee los eventos vivos cada frame para el texto (como
	# lee su propio `deadlock_timer`), y el FIN le llega por la señal porque cuando un evento
	# termina ya no queda en `active` nada que leer. El tinte de la zona lo pinta el TileMap con
	# el mismo manager que ya tiene inyectado arriba.
	gameManager.setWeatherManager(weatherManager);
	weatherManager.weather_ended.connect(gameManager._on_weather_ended);
	# Y a la analítica, que hasta el 2026-10-01 no sabía del clima más que `blocked_storm`.
	weatherManager.weather_started.connect(_on_weather_started);
	weatherManager.weather_ended.connect(_on_weather_ended);

func _on_deadlock_opened():
	if _run_tracked():
		analytics.track("deadlock_opened", {"checkpoint": int(gameManager.current_checkpoint_index)});

func _on_deadlock_closed(secs, lost):
	if _run_tracked():
		analytics.track("deadlock_closed", {"secs": float(secs), "outcome": "lost" if lost else "recovered"});

# El clima en Augur. `weather_started` sale DESPUÉS de meter el evento en `active`, así que su tamaño
# ya lo cuenta. Restaurar una run no emite `weather_started` (weatherManager.restore()), así que un
# clima que venía de la run suspendida solo deja aquí su fin.
func _on_weather_started(id, rect):
	if not _run_tracked():
		return;
	analytics.track("weather_started", {
		"weather": String(id),
		"x": int(rect.position.x), "y": int(rect.position.y),
		"w": int(rect.size.x), "h": int(rect.size.y),
		"duration": float(weatherManager.catalog.get(id, {}).get("duration", 0.0)),
		"chance": float(weatherManager.rollChance()),
		"n_active": int(weatherManager.active.size()),
	});

# `weather_ended` sale DENTRO de la pasada de advance(), antes de que `active` pierda los que
# terminan: los vivos son los que aún tienen tiempo, no el tamaño del array.
func _on_weather_ended(id):
	if not _run_tracked():
		return;
	var vivos = 0;
	for ev in weatherManager.active:
		if ev.remaining > 0.0:
			vivos += 1;
	analytics.track("weather_ended", {"weather": String(id), "n_active": vivos});

func _process(delta):
	if not fileData or not gameManager:
		return;
	var player_node = get_node_or_null("Player");
	if not player_node:
		return;
	var bag = player_node.get_node("Bag");
	# `gameManager.update()` va SIEMPRE, con ventana y sin ella: es el evaluador de la partida
	# —checkpoints, reserva y punto muerto— y no tiene nada que ver con pintar. Lo único que se
	# ahorra sin ventana es CONSTRUIR los dos textos que nadie va a leer.
	if render_enabled:
		get_node("Label").text = _buildResourceText(bag);
	gameManager.update(bag, pollutionManager);
	if render_enabled:
		get_node("Objective").text = gameManager.getObjectiveText(bag, pollutionManager);
	var tile_map_node = get_node_or_null("TileMap");
	if tile_map_node and pollutionManager:
		_tick_world(tile_map_node, delta);
	if render_enabled:
		_update_hover_tooltip();

# Un frame de mundo: primero se mira quién ha quedado limpio y sólo después se vuelve a
# ensuciar. El orden es la regla, no un detalle de implementación: tick_passive() le suma
# +0.5/s a cada casilla `toxic`, así que comprobando después nunca se ve un 0 y una casilla
# degradada no se desbloqueaba jamás —medido: ni con ocho Reforester alrededor—. Comprobando
# antes sí se ve el 0 al que la dejó la limpieza del frame anterior. El precio es un frame de
# latencia en el desbloqueo, que nadie puede percibir.
# Vive fuera de _process() para que se le puedan dar frames sin montar la escena entera.
func _tick_world(tile_map, delta):
	# Desbloquear celdas toxic cuya contaminación local bajó a 0
	_check_toxic_unlock(tile_map);
	# Tick pasivo de tiles (lago reduce contaminación, toxic la aumenta)
	tile_map.tick_passive(pollutionManager, delta);
	# El contagio va DETRÁS del tick pasivo, y los dos detrás del check de desbloqueo: sumar
	# suciedad antes de comprobar quién ha quedado limpio deja una casilla `toxic` sin
	# desbloquear para siempre, que es la razón entera de que este orden esté escrito.
	tile_map.tick_contagion(pollutionManager, delta);
	_tick_autosave(delta);

# El autoguardado (M4), aparte para que _tick_world() siga leyéndose como el orden del mundo. Con
# el árbol pausado _process() no llama aquí, pero se pregunta igual con can_process(): así la
# regla vale también para quien llame a _tick_world() a mano —la suite— y un Main fuera del árbol
# (los de prueba sueltos) no escribe nunca. Al cumplirse se vuelve a 0 en vez de restar: un
# frame enorme no debe disparar dos guardados seguidos de la misma run.
func _tick_autosave(delta):
	if not is_inside_tree() or not can_process():
		return;
	_autosave_t += delta;
	if _autosave_t >= AUTOSAVE_INTERVAL:
		_autosave_t = 0.0;
		_save_run();

func _buildResourceText(bag):
	var text = "";
	for resource in bag.bag:
		var total = bag.getQuantity(resource);
		# El número contra el que decide todo lo que se compra —el cobro de la factoría (M1), el
		# de la cinta (M3) y el atenuado del radial (M5)— es `getAvailable()`, no el total: lo
		# que el checkpoint aparta para su mantenimiento no se puede gastar. Pintando solo el
		# total, el HUD anunciaba `wood: 10` mientras el radial, en la MISMA pantalla, apagaba
		# una opción con `✖ Coste: 8 wood`: los dos decían la verdad y el jugador tenía que
		# restar dos números de dos sitios distintos para entenderlo.
		#
		# El desglose sale SOLO cuando hay reserva, y la condición es POR MATERIAL y no global:
		# `reserved` lo sincroniza gameManager cada frame con el mantenimiento del checkpoint en
		# curso y se levanta entero (dict vacío) en la fase de restauración y en los checkpoints
		# que no cobran nada, y puede apartar `wood` sin apartar `plank`. Sin reserva los dos
		# números son el mismo, así que enseñar los dos sería ruido permanente para explicar un
		# caso que no está ocurriendo — y la línea se lee exactamente como antes de este hito.
		#
		# La redacción es la de la línea de workers de aquí abajo (`3/3 libres`), que resuelve
		# este mismo problema en este mismo bloque: dos formatos distintos para «tengo tanto y
		# puedo usar tanto» se leerían como dos mecánicas distintas. Y como `getAvailable()`
		# nunca es negativo, una reserva mayor que la bolsa sale `0/10 libres`, que es justo el
		# caso que más necesita leerse bien.
		if bag.getReserved(resource) > 0:
			text += resource + ": " + str(bag.getAvailable(resource)) + "/" + str(total) + " libres\n";
		else:
			text += resource + ": " + str(total) + "\n";
	var free_workers = bag.getFreeWorkers();
	var total_workers = bag.workers_total;
	text += "Workers: " + str(free_workers) + "/" + str(total_workers) + " libres\n";
	return text;

func _unhandled_input(event):
	if event is InputEventKey and event.pressed and event.keycode == KEY_R:
		# Solo con una run montada (enmienda M4): en el menú, sin run, reset() borraría la run
		# guardada que «Continuar» ofrece al lado. Tras ganar o perder sí reinicia, como el botón
		# del resumen; su `run_end` ya salió y `_end_run()` no repite.
		if not gameManager:
			return;
		_end_run("abandon");
		reset();
		return;
	var tile_map = get_node_or_null("TileMap");
	if not tile_map or not gameManager:
		return;
	var mouse_pos = tile_map.get_local_mouse_position();
	var cell = tile_map.local_to_map(mouse_pos);
	if event is InputEventMouseButton:
		# El izquierdo hace dos cosas y las desambigua EL GESTO, sin modo ni tecla
		# modificadora: pulsar y soltar en la MISMA celda es el click de siempre (panel o
		# radial) y pulsar en una y soltar en OTRA tiende cinta. Por eso el click de siempre
		# se resuelve al soltar y no al pulsar: al pulsar todavía no se sabe cuál de los dos
		# gestos es. No añade ningún control que aprender.
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if not gameManager.active:
				return;
			_drag_start_cell = cell;
			return;
		if event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			var start = _drag_start_cell;
			_drag_start_cell = null;
			# Sin celda de inicio el soltar no es nuestro: es el que sobra tras cerrar el
			# radial o el panel, cuyo pulsar se tragó su fondo.
			if start == null or not gameManager.active:
				return;
			if cell != start:
				# Arrastre: camino en L, todo o nada. Si una sola celda no admite, no se
				# tiende ninguna y el jugador tiende en dos tramos.
				#
				# Este es el ÚNICO llamante que compra, y por eso el único que pasa la bolsa
				# y `true` (Costes M3): el precio del tramo entero se compara con el
				# excedente ANTES de confirmar, y si no alcanza no se tiende ni una casilla
				# ni se cobra nada. La regla de todo o nada vale igual para el mapa y para el
				# dinero — media cinta pagada no transporta nada.
				if beltNetwork:
					var drag_bag = get_node_or_null("Player/Bag");
					var tendidas = beltNetwork.place_drag(start, cell, factoryArray, drag_bag, true);
					_track_belt_drag(start, cell, tendidas, drag_bag);
				return;
			# El izquierdo gestiona lo que ya hay y construye donde no hay nada. La casilla
			# ocupada no pasa el filtro de colocación de abajo —canPlaceFactory() incluye el
			# check de ocupación—, así que su click se perdía entero: aquí es donde entra el
			# panel de la factoría.
			var fab = _get_factory_at_cell(cell);
			if fab != null:
				_show_factory_panel(fab);
				return;
			# Reglas de colocación: tile, contaminación, tipo de casilla, ocupación y cinta.
			# Se pregunta por la regla PERMISIVA porque aquí todavía no se sabe qué factoría
			# va a elegir el jugador: desde Costes M7 una casilla saturada admite limpieza y
			# no producción, así que preguntar por la estricta dejaría el menú sin abrir
			# justo donde hay que poner el Reforester. Quién cabe de verdad lo decide el
			# radial, que solo ofrece lo que entra en ESTA casilla, y lo revalida
			# _on_factory_chosen() con el tipo elegido.
			if not tile_map.canPlaceAnyFactory(cell, factoryArray):
				_track_click_rejected(tile_map, cell);
				return;
			_show_radial_menu(cell);
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			# Sobre una cinta el derecho borra ESE segmento (y parte la cadena); sobre una
			# factoría sigue demoliendo. Las dos cosas no coinciden nunca en una casilla:
			# canPlaceFactory() impide tender sobre una factoría y construir sobre una cinta.
			if beltNetwork and beltNetwork.remove_belt(cell):
				if _run_tracked():
					analytics.track("belt_removed", {"cx": int(cell.x), "cy": int(cell.y)});
				return;
			_demolish_at_cell(cell);

# Analítica M3: el arrastre de cinta, tendido o rechazado. `tendidas` es lo que devolvió
# `place_drag()`: con celdas, `belt_placed` con lo que se cobró; vacío, `belt_rejected`, y el
# porqué se averigua preguntando lo mismo SIN dinero: si así sí cabía, lo que faltó fue madera
# (`no_money`); si tampoco, el trazado (`no_fit`). En el rechazo `cells` es el largo del gesto
# (manhattan + 1): no hay tramo tendido que contar.
func _track_belt_drag(start, end, tendidas, bag):
	if not _run_tracked():
		return;
	if not tendidas.is_empty():
		var paid = beltNetwork.belt_cost_for(tendidas.size()) if bag != null else {};
		analytics.track("belt_placed", {"x0": int(start.x), "y0": int(start.y),
			"x1": int(end.x), "y1": int(end.y), "cells": int(tendidas.size()),
			"paid_wood": int(paid.get("wood", 0))});
		return;
	var cabia = beltNetwork.can_place_drag(start, end, factoryArray, null, false);
	analytics.track("belt_rejected", {"reason": "no_money" if cabia else "no_fit",
		"cells": int(absi(end.x - start.x) + absi(end.y - start.y) + 1)});

# Analítica M3: click sobre casilla del mapa donde no cabe ninguna factoría. Fuera del mapa
# (sin tile en la capa de suelo) no hay casilla que contar y no se manda.
func _track_click_rejected(tile_map, cell):
	if not _run_tracked() or tile_map.get_cell_source_id(0, cell) == -1:
		return;
	var saturated = false;
	if pollutionManager:
		saturated = float(pollutionManager.pollution_per_cell.get(cell, 0.0)) \
			>= float(pollutionManager.cell_block_pollution);
	analytics.track("click_rejected", {"cx": int(cell.x), "cy": int(cell.y),
		"tile": _tile_id(tile_map, cell), "saturated": saturated});

# El tipo de casilla para la analítica: el suelo normal no está en `cell_types` y es "plain".
func _tile_id(tile_map, cell) -> String:
	var t = tile_map.getCellType(cell);
	return t if t != "" else "plain";

func _demolish_at_cell(cell):
	var fab = _get_factory_at_cell(cell);
	if fab == null:
		return;
	var refunded = {};
	# Devolver workers a la bolsa
	var bag = get_node_or_null("Player/Bag");
	if bag and fab.workers_assigned > 0:
		bag.unassignWorkers(fab.workers_assigned);
	# Y devolver la mitad de lo que esta factoría pagó, redondeando abajo (Costes M4). Se SUMA
	# a los workers de la línea de arriba, no los sustituye: demoler recupera parte de las dos
	# inversiones, y la de workers es la que ya existía y no se toca.
	#
	# Quien decide cuánto es getRefund(), que mira lo PAGADO y no el precio del JSON: lo que se
	# colocó sin comprar —el almacén inicial del mapa, la suite— devuelve {} y no
	# imprime un solo tronco. La devolución entra por addToBag(), o sea al total: lo que el
	# checkpoint tuviera reservado sigue reservado, y lo devuelto es excedente desde el primer
	# frame, que es lo que hace de demoler una salida real cuando la bolsa se atasca.
	if bag and placer:
		var refund = placer.getRefund(fab);
		refunded = refund;
		for material in refund:
			bag.addToBag(material, refund[material]);
	factoryArray.erase(fab);
	# Revertir las sinergias que la demolida concedía: se recalculan desde cero las 8 vecinas.
	# Va DESPUÉS del erase, si no la demolida todavía contaría como vecina (queue_free() es
	# diferido y el nodo sigue vivo este frame; lo que la saca del cálculo es el erase).
	var tile_map = get_node_or_null("TileMap");
	if tile_map and placer:
		for offset in placer.NEIGHBOR_OFFSETS:
			var neighbor = _get_factory_at_cell(cell + offset);
			if neighbor != null:
				placer.recompute_synergies(neighbor, tile_map);
	if _hovered_factory == fab:
		_hovered_factory = null;
		_hide_factory_tooltip();
	# La cache de factorías por celda de la red de cintas queda vieja en cuanto una factoría
	# deja de estar: se invalida entera, que es más barato que razonar qué entradas sobreviven.
	if beltNetwork:
		beltNetwork.invalidate_factory_index();
	# Analítica M3. La edad sale del `run_time` que `_on_factory_chosen()` apuntó al construir; lo
	# que no pasó por ahí (el almacén inicial del mapa) nació con la run, en 0.
	if _run_tracked():
		var props = {"factory": String(fab.type), "cx": int(cell.x), "cy": int(cell.y),
			"age_s": max(0.0, float(gameManager.run_time) - float(fab.get_meta("built_run_t", 0.0)))
				if gameManager else 0.0};
		for material in refunded:
			props["refund_" + String(material)] = int(refunded[material]);
		analytics.track("factory_demolished", props);
	fab.queue_free();

func _show_radial_menu(cell):
	# Las sinergias que daría construir en esta casilla, consultadas sin aplicar nada: pegar la
	# línea o desparramarla es la decisión más cara del juego (un factor 5 en la run entera,
	# medido) y hasta hoy solo se veía después de haber construido.
	# Y si cada una se puede pagar AHORA MISMO (Costes M5), consultado en el mismo bucle y por
	# la misma razón: el hilo principal consulta y la UI pinta. canAfford() es solo lectura —el
	# radial no puede mover el estado de la partida— y mira `getAvailable()`, el excedente, que
	# es exactamente de donde cobrará build(): pintando contra el total de la bolsa el botón
	# diría «puedes» justo donde _on_factory_chosen() dice «no», y el jugador viviría el
	# rechazo como un gesto roto.
	#
	# 🔴 Y SE OFRECE SOLO LO QUE CABE EN ESTA CASILLA (Costes M7). Desde M7 la respuesta de
	# `canPlaceFactory()` depende del tipo —la casilla saturada admite restauración y no
	# producción—, así que el menú deja de poder ser la lista entera: una opción que
	# `_on_factory_chosen()` va a rechazar en silencio se vive como un gesto roto, que es
	# exactamente lo que M5 arregló con el dinero. Sobre casilla sana no cambia nada: ahí
	# caben todas y la lista es la de siempre.
	var opciones = [];
	var preview = {};
	var asequibles = {};
	var tile_map = get_node_or_null("TileMap");
	if placer:
		var bag = get_node_or_null("Player/Bag");
		for tipo in get_node("Player").availableFactories:
			# El CUARTO parámetro es el nombre del tipo (Variedad M4): es lo que deja a
			# canPlaceFactory() aplicar el `requires_adjacent` de la depuradora, y por eso lo
			# pasan solo este camino y _on_factory_chosen(). Sin él, el radial ofrecería la
			# WaterTreatment lejos del agua y el jugador se comería el rechazo silencioso —que
			# es exactamente el gesto roto que este filtro existe para evitar—.
			if tile_map != null and not tile_map.canPlaceFactory(
					cell, factoryArray, _factory_kind(tipo), str(tipo)):
				continue;
			opciones.append(tipo);
			preview[tipo] = placer.preview_synergies(tipo, cell, tile_map);
			asequibles[tipo] = placer.canAfford(tipo, bag);
	# Sin una sola opción no hay menú que abrir, y se sale ANTES de tocar el árbol: pasa cuando
	# la casilla saturada es lo único que queda y el jugador todavía no ha desbloqueado el
	# Reforester. Por eso desde M7 el nodo se monta al final y no al principio — crearlo para
	# liberarlo en el mismo frame es justo la trampa del nombre que documenta el `CLAUDE.md`:
	# `queue_free()` es diferido y el siguiente `RadialMenu` nacería renombrado.
	if opciones.is_empty():
		return;
	var existing = get_node_or_null("RadialMenu");
	if existing:
		existing.queue_free();
	var radial = load("res://ui/radialMenu.gd").new();
	radial.name = "RadialMenu";
	add_child(radial);
	radial.initialize(opciones, fileData, cell, get_viewport().get_mouse_position(),
		preview, asequibles);
	radial.factory_chosen.connect(_on_factory_chosen);
	# Analítica M3: el cierre, construyendo o no, con cuántas opciones había y cuántas se podían
	# pagar. El radial no conoce la analítica: emite `closed(built)` una vez y Main lo traduce.
	var n_affordable = 0;
	for tipo in asequibles:
		if asequibles[tipo]:
			n_affordable += 1;
	radial.closed.connect(_on_radial_closed.bind(cell, opciones.size(), n_affordable));

func _on_radial_closed(built, cell, n_options, n_affordable):
	if _run_tracked():
		analytics.track("radial_closed", {"cx": int(cell.x), "cy": int(cell.y), "built": bool(built),
			"n_options": int(n_options), "n_affordable": int(n_affordable)});

# La CATEGORÍA de una factoría (`type` del JSON), que es lo que `tileMap.canPlaceFactory()`
# necesita desde Costes M7. Vive aquí, en una función y no repetida en cada llamada, porque
# la piden los dos caminos del gesto de construir: el que abre el radial y el que elige.
# El default "production" es el mismo que aplica `factoryPlacer.build()` a una entrada que no
# declare `type`, y no un valor nuevo: las dos lecturas del campo tienen que decir lo mismo.
func _factory_kind(factory_type) -> String:
	return str(fileData.get("Factories", {}).get(factory_type, {}).get("type", "production"));

func _on_factory_chosen(factory_type, cell):
	var bag = get_node("Player").get_node("Bag");
	var tile_map = get_node("TileMap");
	# Se revalidan las reglas de colocación: entre abrir el radial y elegir factoría
	# la celda pudo ensuciarse u ocuparse. Desde Costes M7 la pregunta lleva la CATEGORÍA de
	# lo elegido, porque la respuesta depende de ella: sobre casilla saturada cabe una
	# restauradora y no una productora. Este sigue siendo el rechazo que manda —el filtrado
	# del radial es solo lo que se le enseña al jugador—.
	# Y desde Variedad M4 lleva también el NOMBRE del tipo, que es de donde sale el
	# `requires_adjacent`: éste sigue siendo el rechazo que manda, así que si la regla nueva
	# solo viviera en el filtro del radial se podría colocar la depuradora en seco por
	# cualquier otro camino que llame aquí.
	if not tile_map.canPlaceFactory(cell, factoryArray, _factory_kind(factory_type),
			str(factory_type)):
		_track_build_rejected(factory_type, "cell_invalid");
		return;
	# Y se revalida el dinero por la misma razón que la colocación: entre abrir el radial y
	# elegir, una factoría pudo comerse el insumo o el checkpoint en curso pudo apartar más de
	# lo que había. canAfford() mira el EXCEDENTE (getAvailable()), nunca el total: lo
	# reservado para el peaje no se puede gastar en construir.
	if not placer.canAfford(factory_type, bag):
		_track_build_rejected(factory_type, "no_money");
		return;
	var fabrica = placer.build(factory_type, cell, get_node("Player"), bag, tile_map, true);
	# `true` es lo que hace que esta llamada —y solo esta— cobre: build() descuenta dentro. Si
	# aun así devuelve null, el dinero dejó de dar entre la comprobación y el cobro y no hay
	# factoría que añadir: los dos rechazos son el mismo y tener ambos es lo que deja imposible
	# colocar una factoría a medio pagar.
	if fabrica == null:
		_track_build_rejected(factory_type, "no_money");
		return;
	add_child(fabrica);
	placer.register_and_evaluate(fabrica, cell);
	_track_factory_built(fabrica, cell, tile_map);
	if beltNetwork:
		beltNetwork.invalidate_factory_index();
		# La factoría nueva puede ser el destino que le faltaba al final de una cinta ya
		# tendida: quien estuviera parado por búfer lleno (M4) se desatasca aquí. Sin esto una
		# factoría parada no vuelve a emitir nunca —no produce, así que nada dispararía el
		# reintento— y el camino recién completado no se enteraría.
		beltNetwork.flush_output_buffers();
	# Se ata el nodo a la conexión: _on_resource_produced() necesita la CELDA de origen para
	# preguntarle a la red por dónde sale el material, y la señal solo lleva la posición de
	# mundo. Bindear el nodo y no su celda mantiene el dato vivo.
	fabrica.resource_produced.connect(_on_resource_produced.bind(fabrica));
	# Efectos on_build del tile
	var tdef = tile_map.getCellTypeDef(cell);
	if not tdef.is_empty():
		# Tierra quemada: contamina la celda al construir
		if tdef.has("on_build_pollution"):
			pollutionManager.addPollution(float(tdef["on_build_pollution"]), cell);
		# Ruinas: ofrecer mejora gratuita
		if tdef.has("on_build_reward") and tdef["on_build_reward"].get("upgrades", 0) > 0:
			tile_map.cell_types.erase(cell); # consumir la ruina
			_on_checkpoint_reached(gameManager._pick_upgrades(1), {}, [], "ruins");

# Analítica M3: los rechazos de `_on_factory_chosen()`. El tercero (`build()` devolvió null) es el
# mismo rechazo por dinero que el segundo, y cuenta como tal.
func _track_build_rejected(factory_type, reason):
	if _run_tracked():
		analytics.track("build_rejected", {"factory": String(factory_type), "reason": reason});

# Analítica M3: la factoría recién registrada, con la casilla (ANTES de que las ruinas se
# consuman), lo pagado de verdad (`cost_paid`, el recibo) y cuántas vecinas comparten sinergia
# con ella en cualquiera de los dos sentidos. Apunta además en el nodo el `run_time` de
# construcción, del que `_demolish_at_cell()` saca `age_s`.
func _track_factory_built(fabrica, cell, tile_map):
	if not _run_tracked():
		return;
	fabrica.set_meta("built_run_t", float(gameManager.run_time) if gameManager else 0.0);
	var factories = fileData.get("Factories", {});
	var own = factories.get(fabrica.type, {}).get("synergies", {});
	var n_synergies = 0;
	for offset in placer.NEIGHBOR_OFFSETS:
		var neighbor = _get_factory_at_cell(cell + offset);
		if neighbor == null or neighbor == fabrica:
			continue;
		if own.has(neighbor.type) or factories.get(neighbor.type, {}).get("synergies", {}).has(fabrica.type):
			n_synergies += 1;
	var props = {"factory": String(fabrica.type), "cx": int(cell.x), "cy": int(cell.y),
		"tile": _tile_id(tile_map, cell), "n_synergies": n_synergies};
	for material in fabrica.cost_paid:
		props["paid_" + String(material)] = int(fabrica.cost_paid[material]);
	analytics.track("factory_built", props);

# `source` es la factoría que produjo, atada en la conexión de la señal (ver _on_factory_chosen).
# Queda con default porque la señal en sí solo lleva tres argumentos y hay quien la conecta sin
# atar nada (la suite).
func _on_resource_produced(material, amount, world_pos, source = null):
	if material == null:
		return;
	# --- Las dos excepciones, intactas: ni el worker ni el token viajan por cinta. La
	# desviación a beltNetwork.deliver() ocurre DESPUÉS de las dos, nunca antes.
	# Factory token: muestra pantalla de desbloqueo de factory
	if material == "factory_token":
		# El token sigue contándose en la bolsa como hasta M1 —es lo que lo pinta en el HUD de
		# recursos—; lo que no hace es viajar por la red.
		var bag_token = get_node_or_null("Player/Bag");
		if bag_token:
			bag_token.addToBag(material, amount);
		_show_factory_token_screen();
		return;
	if material == "worker":
		var bag_node = get_node_or_null("Player/Bag");
		if bag_node:
			bag_node.addWorkers(amount);
		# FX igual que otros recursos
		var label_node = get_node_or_null("Label");
		var target = Vector2(10, 10);
		if label_node:
			var bag2 = get_node_or_null("Player/Bag");
			var line_index = 0;
			if bag2:
				line_index = bag2.bag.keys().size(); # workers line está al final
			target = label_node.position + Vector2(10, line_index * 20 + 8);
		_spawn_fx_label(world_pos, target, amount, Color(0.2, 0.7, 1.0));
		return;
	# --- Y aquí acaba la excepción y empieza la red: desde M2 lo producido NO entra en la
	# bolsa, sale por una cinta. Sin segmento que salga de su casilla —o con el camino roto— la
	# entrega devuelve 0 y desde M4 ese material YA NO SE PIERDE: se queda en el búfer de
	# salida de la factoría, que al llenarse (OUTPUT_BUFFER_MAX) la para y con ella su
	# contaminación.
	if beltNetwork and source != null:
		# POR DÓNDE se encamina. Por defecto, «por la primera cinta que salga de su casilla»,
		# que es lo que ha hecho siempre y lo que toda factoría de producción necesita: fabrica
		# UNA cosa y le da igual la ruta. Pero el almacén emite una cosa DISTINTA por cada una
		# de sus cintas (factoryData._tick_storage_emit()), así que apunta en `emit_route_cell`
		# por cuál va ESTA emisión: sin leerlo, las dos emisiones de un almacén con dos líneas
		# se irían por la misma cinta y la segunda línea no recibiría nunca nada.
		var entregado = 0;
		if source.emit_route_cell != null:
			entregado = beltNetwork.deliver_via(source.cell_position,
				beltNetwork.get_belt(source.emit_route_cell), material, amount);
		else:
			entregado = beltNetwork.deliver(source.cell_position, material, amount);
		if source.factory_type == "storage":
			# El almacén no fabrica: EMITE sacando de la bolsa, y ya la ha descontado en
			# su tick (factoryData._tick_storage()). Así que las dos mitades de «la red no ha
			# sabido llevárselo» son distintas para él:
			#   · no tiene búfer de salida y NO se atasca —contrato de M4, que emitir no
			#     cambia—, así que lo no entregado VUELVE a la bolsa en el acto y el saldo del
			#     tick es cero: emitir sin cinta, con la cinta filtrada o con el camino roto no
			#     cuesta nada;
			#   · y no se pinta el FX de «+N hacia el HUD», que contaría al revés: el material
			#     sale de la bolsa, no entra.
			#
			# 🔴 Y la devolución SIGUE HACIENDO FALTA aunque desde 2026-09-23 el almacén solo
			# emita lo que ha comprobado que un consumidor suyo pide: quien planea la emisión
			# (el tick) y quien la entrega (esto) son dos pasos distintos, y entre medias
			# cualquiera puede haber puesto un filtro, borrado un segmento o demolido el
			# destino. Sin esta rama ese material desaparecería de la bolsa sin llegar a
			# ninguna parte, que es exactamente el agujero que M4 cerró para las demás.
			if entregado <= 0:
				var bag_back = get_node_or_null("Player/Bag");
				if bag_back:
					bag_back.addToBag(material, amount);
			return;
		if entregado <= 0:
			source.storeOutput(amount);
		elif source.output_buffer > 0:
			# La entrega ha colado y la factoría arrastraba atasco de cuando no había camino:
			# el mismo camino sirve para vaciarlo.
			beltNetwork.flush_output(source);
	# Calcular posición destino: línea del material en el Label de recursos
	var label_node = get_node_or_null("Label");
	var target = Vector2(10, 10);
	if label_node:
		var bag_node = get_node_or_null("Player/Bag");
		var line_index = 0;
		if bag_node:
			var keys = bag_node.bag.keys();
			line_index = keys.find(material);
			if line_index < 0:
				line_index = 0;
		target = label_node.position + Vector2(10, line_index * 20 + 8);
	var color = _get_material_color(material);
	_spawn_fx_label(world_pos, target, amount, color);

func _spawn_fx_label(world_pos, target, amount, color):
	var label = Label.new();
	label.text = "+" + str(amount);
	label.add_theme_color_override("font_color", color);
	label.add_theme_font_size_override("font_size", 18);
	label.z_index = 20;
	label.position = world_pos - Vector2(12, 12);
	add_child(label);
	var tween = create_tween();
	tween.set_trans(Tween.TRANS_QUAD);
	tween.set_ease(Tween.EASE_IN);
	tween.tween_property(label, "position", target, 0.55);
	tween.parallel().tween_property(label, "modulate:a", 0.0, 0.55);
	tween.tween_callback(label.queue_free);

func _get_material_color(material):
	match material:
		"wood": return Color(0.55, 0.32, 0.05);
		"plank": return Color(0.85, 0.65, 0.25);
		# La segunda cadena (Variedad M1): `stone` se lee en gris piedra y no en el amarillo
		# del comodín de abajo, que es el color de «material que nadie ha declarado». Con los
		# dos materiales viajando a la vez por el mapa, el FX es lo único que dice cuál de las
		# dos líneas acaba de entregar.
		# 🔴 SUBIDO DE (0,62·0,62·0,66) A ESTO (Variedad M4b, 2026-09-22), y por contraste, no
		# por gusto. Mirado en `capturas/2b_fx_zoom.png`: los tres colores se distinguen, pero la
		# etiqueta son 18 px y nace medio encima del cubo oscuro de la factoría —muestreado del
		# PNG, (69, 40, 60)—, y el gris era el de menos contraste ahí: **4,9** de razón WCAG
		# contra los **11,3** de ahora. Y se aclara hacia un blanco roto CÁLIDO, que lo aleja de
		# los otros dos en vez de acercarlo: la distancia RGB al terracota del `brick` sube de
		# **0,52 a 0,90** y la al azul-cristal del `glass` de **0,34 a 0,41**. Blanco puro no,
		# porque el gris tiene que seguir leyéndose como piedra y no como «color por defecto».
		"stone": return Color(0.95, 0.94, 0.90);
		# Y los dos que salen de la MISMA factoría (Variedad M3): la `Foundry` fabrica `brick`
		# o `glass` según lo que el jugador elija en su panel, así que el FX es lo único que
		# dice desde fuera cuál de los dos está saliendo ahora mismo — con el desplegable
		# cerrado, el mapa no lo cuenta de ninguna otra forma. Terracota contra azul-cristal:
		# se distinguen de un vistazo y ninguno se parece al gris de la piedra que los alimenta.
		"brick": return Color(0.78, 0.36, 0.24);
		"glass": return Color(0.55, 0.85, 0.90);
		"restoration": return Color(0.3, 0.85, 0.35);
		"worker": return Color(0.2, 0.7, 1.0);
		_: return Color(1.0, 0.9, 0.3);

func _check_toxic_unlock(tile_map):
	for cell in tile_map.cell_types.keys():
		if tile_map.cell_types[cell] == "toxic":
			# Solo se devuelve una casilla que ha estado sucia y ha llegado a 0 limpiándola.
			# El primer requisito lo pide el orden nuevo: comprobando ANTES del tick pasivo,
			# una `toxic` que todavía no se ha ensuciado marca 0 y se restauraría sola en el
			# primer frame de la run — le pasaría a la (6,7) de wasteland_01, que nace sin
			# suciedad registrada (mapLoader la deja fuera del reparto porque no tiene tile).
			if not pollutionManager.pollution_per_cell.has(cell):
				continue;
			if pollutionManager.getCellPollution(cell) <= 0.0:
				# Ya restaurada: vuelve a ser suelo normal y construible. El repintado lo
				# hace el tilemap, que es quien sabe qué tinte le había puesto al degradarla.
				tile_map.restoreCell(cell);
				if _run_tracked():
					analytics.track("cell_restored", {"cx": int(cell.x), "cy": int(cell.y)});

func _show_factory_token_screen():
	var existing = get_node_or_null("TokenUnlock");
	if existing:
		return;
	# Construye lista de factories no disponibles (candidatas a desbloquear)
	var playerNode = get_node("Player");
	var all_factories = fileData["Factories"].keys();
	var candidates = [];
	for f in all_factories:
		# El almacén queda fuera de la oferta: no es una factoría que el jugador desbloquee,
		# la coloca el mapa en su `storage_cell` (mapLoader.place_storage(), M3). Sin este
		# filtro el token ofrecería «Desbloquear Storage», que no es una decisión de juego.
		if fileData["Factories"][f].get("type", "production") == "storage":
			continue;
		if not playerNode.availableFactories.has(f):
			candidates.append(f);
	if candidates.is_empty():
		return;
	get_tree().paused = true;
	var screen = load("res://ui/upgradeScreen.gd").new();
	screen.name = "TokenUnlock";
	add_child(screen);
	# Reutiliza upgradeScreen: pasa IDs de factories como "upgrades" sintéticos
	var synthetic_catalog = {};
	for f in candidates:
		synthetic_catalog["token_unlock_" + f] = {
			"name": "Desbloquear " + f,
			"description": "Usa el factory token para desbloquear " + f + " en este run.",
			"type": "unlock_factory",
			"factory": f
		};
	var offered = synthetic_catalog.keys().slice(0, 3);
	screen.initialize(offered, synthetic_catalog);
	screen.upgrade_chosen.connect(_on_token_unlock_chosen);
	_remember_offer(offered, "token");
	if analytics:
		analytics.track("ui_open", {"screen": "token"});

func _on_token_unlock_chosen(upgrade_id):
	_track_offer(upgrade_id);
	get_tree().paused = false;
	var parts = upgrade_id.split("token_unlock_");
	if parts.size() >= 2:
		var factory_name = parts[1];
		var playerNode = get_node("Player");
		if not playerNode.availableFactories.has(factory_name):
			playerNode.availableFactories.append(factory_name);
	# Consume el token de la Bag
	get_node("Player").get_node("Bag").removeFromBag("factory_token", 1);

# Panel persistente de una factoría colocada: se abre por click y vive hasta que se cierra, al
# revés que el tooltip de hover. Mientras existe, el hover se calla (ver _update_hover_tooltip()):
# pintan la misma información y el panel nace justo bajo el cursor, que es donde el tooltip quiere
# estar, así que se solaparían.
func _show_factory_panel(factory_node):
	var existing = get_node_or_null("FactoryPanel");
	if existing:
		# Se saca del árbol antes de liberarlo: queue_free() es diferido, así que el viejo
		# seguiría ocupando el nombre «FactoryPanel» hasta el final del frame y el nuevo entraría
		# renombrado, invisible para _hide_factory_panel(). remove_child() libera el nombre ya.
		remove_child(existing);
		existing.queue_free();
	_clear_hover();
	var panel = load("res://ui/factoryPanel.gd").new();
	panel.name = "FactoryPanel";
	add_child(panel);
	# La bolsa va con el panel porque los botones de workers mueven los dos contadores a la vez
	# —el de la factoría y el de la bolsa—, igual que build() al construir y _demolish_at_cell()
	# al demoler. Sin ella el panel se monta igual, pero en solo lectura.
	# Y la red de cintas, que desde M5 el panel necesita para dos cosas: el desplegable de
	# material del ALMACÉN (su lista sale de la bolsa, no del JSON) y el filtro de la cinta de
	# salida, que es el otro control que M5 añade. Sin red el panel se monta igual, sin ese
	# bloque.
	# Y lo que demoler devolvería (Costes M5), calculado aquí con `factoryPlacer.getRefund()` —el
	# mismo que ejecuta la devolución en `_demolish_at_cell()`— y no por el panel: si el panel
	# dividiera por su cuenta, el día que cambie la regla habría dos mitades distintas, la que se
	# enseña y la que se cobra. Sale `{}` para lo que nadie pagó, y entonces no se enseña línea.
	var refund = placer.getRefund(factory_node) if placer else {};
	panel.initialize(factory_node, fileData, get_viewport().get_mouse_position(),
		get_node_or_null("Player/Bag"), beltNetwork, refund);
	# Analítica M3: se abre el panel, con la razón de parada que ENSEÑA (`blockedReason`, que ya
	# descarta el `workers` caducado), y sus tres acciones, que el panel emite solo si se aplican.
	panel.workers_changed.connect(_on_panel_workers_changed.bind(factory_node));
	panel.material_selected.connect(_on_panel_material_selected.bind(factory_node));
	panel.belt_filter_set.connect(_on_panel_belt_filter_set);
	if _run_tracked():
		var reason = BLOCKED_REASON.reason_now(factory_node);
		var cp = factory_node.cell_position;
		analytics.track("panel_opened", {"factory": String(factory_node.type), "cx": int(cp.x),
			"cy": int(cp.y), "blocked": reason if reason != "" else "none"});

func _on_panel_workers_changed(delta, factory_node):
	if _run_tracked() and is_instance_valid(factory_node):
		analytics.track("workers_changed", {"factory": String(factory_node.type), "delta": int(delta),
			"assigned": int(factory_node.workers_assigned)});

func _on_panel_material_selected(material, factory_node):
	if _run_tracked() and is_instance_valid(factory_node) and material != null:
		analytics.track("material_selected", {"factory": String(factory_node.type),
			"material": String(material)});

func _on_panel_belt_filter_set(cell, material):
	if _run_tracked():
		analytics.track("belt_filter_set", {"cx": int(cell.x), "cy": int(cell.y),
			"material": String(material) if String(material) != "" else "any"});

func _hide_factory_panel():
	var panel = get_node_or_null("FactoryPanel");
	if panel:
		panel.queue_free();

# El panel también se cierra solo (ESC o click en su fondo) sin avisar a nadie, así que quien
# quiera saber si está abierto tiene que preguntárselo al árbol. Un nodo ya en cola de borrado no
# cuenta: sigue en el árbol este frame, pero el jugador ya no lo ve.
func _factory_panel_open():
	var panel = get_node_or_null("FactoryPanel");
	return panel != null and not panel.is_queued_for_deletion();

func _show_factory_tooltip(factory_node):
	_hide_factory_tooltip();
	var tooltip = load("res://ui/factoryTooltip.gd").new();
	tooltip.name = "FactoryTooltip";
	add_child(tooltip);
	tooltip.initialize(factory_node, fileData);
	tooltip.show_at(get_viewport().get_mouse_position());
	# Con qué razón se acaba de pintar. Se anota AQUÍ y no en quien llama porque este es el único
	# sitio que construye el contenido: así el campo no puede describir un tooltip que no es el que
	# está en pantalla, venga la llamada de donde venga.
	_hovered_reason = BLOCKED_REASON.reason_now(factory_node);

func _hide_factory_tooltip():
	var tooltip = get_node_or_null("FactoryTooltip");
	if tooltip:
		# queue_free() y no free(): liberar en el acto puede matar el nodo en mitad de la
		# propagación de un evento de entrada. Y remove_child() antes, porque queue_free() es
		# diferido: el tooltip viejo ocuparía el nombre «FactoryTooltip» hasta el final del frame
		# y el siguiente —que se crea en el mismo frame, al pasar de una factoría a otra— entraría
		# renombrado y esta función no volvería a encontrarlo nunca.
		remove_child(tooltip);
		tooltip.queue_free();
	# Sin tooltip no hay razón pintada. Se limpia aquí —el único punto por el que el nodo deja de
	# existir— y no en cada uno de los cinco sitios que llaman: si sobreviviera, al volver el ratón
	# a la MISMA factoría se compararía la razón de ahora contra una de hace rato y el tooltip
	# recién montado se reconstruiría por un motivo caducado, o peor, no se reconstruiría nunca.
	_hovered_reason = "";

func _update_hover_tooltip():
	# Con el panel abierto no hay hover: la información es la misma y el panel está encima.
	# _clear_hover() deja _hovered_factory en null, así que al cerrarse el panel el primer frame
	# de ratón sobre una factoría vuelve a montar el tooltip por el camino normal.
	if _factory_panel_open():
		_clear_hover();
		return;
	var tile_map = get_node_or_null("TileMap");
	if not tile_map:
		_clear_hover();
		return;
	# 🔴 Un nodo LIBERADO se compara igual que `null` en GDScript, así que no lo ve ninguno de los
	# dos `!= null` de abajo: se cuela por las dos ramas y `_hovered_factory` se queda apuntando
	# a un objeto muerto —con su `_hovered_reason` pegada— para el resto de la run.
	# `is_instance_valid()` es el único que los distingue, y por eso el guardia va AQUÍ y no
	# dentro de una rama que el nodo muerto ni siquiera alcanza. Por el camino normal no llega
	# ninguno (`_demolish_at_cell()` anula el hover y `_get_factory_at_cell()` no devuelve
	# liberados), pero el panel se protege de esto desde la enmienda de M3 y las dos superficies
	# leen lo mismo del mismo sitio.
	if not is_instance_valid(_hovered_factory):
		_clear_hover();
	var cell = tile_map.local_to_map(tile_map.get_local_mouse_position());
	var factory_under_cursor = _get_factory_at_cell(cell);
	if factory_under_cursor != _hovered_factory:
		_hovered_factory = factory_under_cursor;
		_hide_factory_tooltip();
		if _hovered_factory != null:
			_show_factory_tooltip(_hovered_factory);
	elif _hovered_factory != null:
		# El ratón quieto sobre la misma factoría (M4). Antes esta rama solo movía el panel de
		# sitio y el contenido no se repintaba jamás: el tooltip muere cuando el ratón se va a otra
		# casilla, no cuando el estado cambia, así que enseñaba una cortadora SIN «Parada» mientras
		# su marcador rojo sí estaba pintado en esa misma celda. Las dos superficies se
		# contradecían, y es el mismo defecto que la enmienda de M3 arregló en el panel.
		# Se compara contra `reason_now()` y no contra `blocked_reason` a pelo: la prioridad 1 se
		# lee viva, así que con el campo crudo el tooltip discreparía del panel justo en el caso de
		# los workers, que es el único que el jugador arregla sin tocar el mapa.
		# Y SOLO cuando cambia: esta función corre por frame, y rehacer el CanvasLayer entero para
		# volver a escribir lo mismo es el gasto que el panel ya decidió no hacer.
		if BLOCKED_REASON.reason_now(_hovered_factory) != _hovered_reason:
			# `_show_factory_tooltip()` abre por `_hide_factory_tooltip()`, que saca el viejo del
			# árbol con `remove_child()` antes del `queue_free()` diferido. Sin ese paso el nuevo
			# —que nace en el MISMO frame— entraría renombrado a `@CanvasLayer@N` y nadie volvería
			# a encontrar «FactoryTooltip» nunca más.
			_show_factory_tooltip(_hovered_factory);
		else:
			var tooltip = get_node_or_null("FactoryTooltip");
			if tooltip:
				tooltip.update_position(get_viewport().get_mouse_position());

func _clear_hover():
	# Pregunta también por la razón: un `_hovered_factory` ya liberado se compara como `null`,
	# así que preguntando solo por él esta función no limpiaría nunca el estado que ese nodo
	# muerto dejó atrás (la razón pegada y el tooltip todavía colgando).
	if _hovered_factory != null or _hovered_reason != "":
		_hovered_factory = null;
		_hide_factory_tooltip();

func _get_factory_at_cell(cell):
	for fab in factoryArray:
		if fab.cell_position == cell:
			return fab;
	return null;

func _close_menus():
	var radial = get_node_or_null("RadialMenu");
	if radial:
		radial.queue_free();
	_hide_factory_panel();
	_hide_factory_tooltip();
	_hovered_factory = null;

# `granted_upgrade_ids` tiene valor por defecto porque la mejora gratis de las ruinas llama
# aquí a mano, y ahí no se concede nada: lo que las ruinas dan ya es una carta regalada.
# `source` (M2 de «Analítica de Runs») es de dónde sale la oferta para `card_offered`: la señal
# del gameManager no lo lleva y vale "checkpoint"; las ruinas pasan "ruins". Solo un checkpoint
# de verdad emite `checkpoint_reached`.
func _on_checkpoint_reached(offered_upgrade_ids, rewards, granted_upgrade_ids = [], source = "checkpoint"):
	if source == "checkpoint" and _run_tracked() and gameManager:
		var closed_t = float(gameManager.last_checkpoint_time);
		var cp_props = {
			"checkpoint": int(gameManager.current_checkpoint_index),
			"seg_t": max(0.0, closed_t - _prev_checkpoint_t),
			"tier": int(gameManager.last_tier),
		};
		# Sin integral en el tramo el cociente vale el −1.0 centinela, que falsearía cualquier
		# `avg`: entonces `rate` no se manda (enmienda tras M2, hecha en M3).
		var rate = float(gameManager.last_segment_rate);
		if rate >= 0.0:
			cp_props["rate"] = rate;
		analytics.track("checkpoint_reached", cp_props);
		_prev_checkpoint_t = closed_t;
	_close_menus();
	var bag = get_node("Player").get_node("Bag");
	if rewards.get("workers", 0) > 0:
		bag.addWorkers(int(rewards["workers"]));
	# Las concedidas se aplican ANTES de montar la pantalla: la garantía no puede depender de
	# que el jugador pulse nada, que es justo lo que fallaba cuando se ofrecían entre las tres.
	_apply_granted_upgrades(granted_upgrade_ids);
	_show_upgrade_offer(offered_upgrade_ids, source, granted_upgrade_ids);

# Monta la pantalla de cartas con una oferta YA decidida: pausa el árbol, la conecta a
# _on_upgrade_chosen() y la apunta para `card_offered`. Vive aparte de _on_checkpoint_reached()
# desde Serialización M2 porque la reanudación reabre la oferta guardada TAL CUAL —mismos ids,
# sin re-barajar— y sin repetir nada de lo que hizo el checkpoint: ni la analítica del tramo,
# ni las recompensas, ni las concedidas, que ya están aplicadas. Por eso al reanudar
# `granted` llega vacío: la pantalla no vuelve a anunciar una carta que el snapshot no guarda.
func _show_upgrade_offer(offered_upgrade_ids, source, granted_upgrade_ids = []):
	get_tree().paused = true;
	var screen = load("res://ui/upgradeScreen.gd").new();
	screen.name = "UpgradeScreen";
	add_child(screen);
	screen.initialize(offered_upgrade_ids, fileData["Upgrades"], granted_upgrade_ids);
	screen.upgrade_chosen.connect(_on_upgrade_chosen);
	_remember_offer(offered_upgrade_ids, source);
	if analytics:
		analytics.track("ui_open", {"screen": "upgrade"});

# La oferta que hay en pantalla, para mandarla al elegir (M2): una fila de `card_offered` por carta
# mostrada, en su orden (`slot` 1..N) y con los milisegundos de reloj que tardó la decisión. El
# checkpoint se toma al montarla: son los cerrados hasta ese momento.
func _remember_offer(offered_ids, source):
	_offer_ids = Array(offered_ids).duplicate();
	_offer_source = source;
	_offer_checkpoint = int(gameManager.current_checkpoint_index) if gameManager else 0;
	_offer_ms = Time.get_ticks_msec();

func _track_offer(chosen_id):
	var ids = _offer_ids;
	_offer_ids = [];
	if not _run_tracked():
		return;
	var decision_ms = int(Time.get_ticks_msec() - _offer_ms);
	for i in range(ids.size()):
		var props = {
			"card": String(ids[i]),
			"slot": i + 1,
			"chosen": 1 if ids[i] == chosen_id else 0,
			"source": _offer_source,
			"checkpoint": _offer_checkpoint,
			"decision_ms": decision_ms,
		};
		# El tier es el de la carta (el `tier` de Upgrades); las sintéticas del token no tienen.
		var upgrade = fileData["Upgrades"].get(ids[i], {}) if fileData else {};
		if upgrade.has("tier"):
			props["tier"] = int(upgrade["tier"]);
		analytics.track("card_offered", props);

# Las mejoras que la run recibe sin elegirlas. Vive aparte de _on_checkpoint_reached() para
# que se le pueda dar la lista sin montar la escena entera: lo que hay que poder afirmar es
# que se aplican pase lo que pase en la pantalla, no que la pantalla se dibuje.
func _apply_granted_upgrades(granted_upgrade_ids):
	for id in granted_upgrade_ids:
		_apply_upgrade(id);
		if _run_tracked():
			analytics.track("card_granted", {"card": String(id),
				"checkpoint": int(gameManager.current_checkpoint_index) if gameManager else 0});

func _on_upgrade_chosen(upgrade_id):
	_track_offer(upgrade_id);
	_apply_upgrade(upgrade_id);
	get_tree().paused = false;
	gameManager.resume_after_upgrade();

func _apply_upgrade(upgrade_id):
	if not fileData["Upgrades"].has(upgrade_id):
		return;
	var upgrade = fileData["Upgrades"][upgrade_id];
	var playerNode = get_node("Player");
	var bag = get_node("Player").get_node("Bag");
	match upgrade["type"]:
		"speed_boost":
			var target = upgrade["target"];
			var amount = int(upgrade["amount"]);
			playerNode.applySpeedBoost(target, amount);
			for fab in factoryArray:
				if fab.type == target:
					fab.tickTimer = max(1, fab.tickTimer - amount);
		"extra_output":
			var target = upgrade["target"];
			var amount = int(upgrade["amount"]);
			playerNode.applyExtraOutput(target, amount);
			for fab in factoryArray:
				if fab.type == target:
					fab.outputAmount += amount;
		"unlock_factory":
			var factory_name = upgrade["factory"];
			if not playerNode.availableFactories.has(factory_name):
				playerNode.availableFactories.append(factory_name);
		"add_workers":
			var amount = int(upgrade["amount"]);
			bag.addWorkers(amount);
	# El coste de la mejora. Va DESPUÉS del match a propósito: el beneficio se cobra aunque
	# no quede sitio donde poner el castigo, y una mejora sin `map_downside` —todo el tier 1—
	# no paga nada.
	if upgrade.has("map_downside"):
		_apply_map_downside(upgrade["map_downside"]);

# Convierte N casillas libres al azar al tipo indicado (hoy `toxic`). El castigo es perder
# sitio donde construir, no perder mapa: la casilla conserva su tile del suelo, así que se ve,
# un Reforester puede limpiarla y `_check_toxic_unlock()` acaba devolviéndola. Ahí está la
# tensión que se busca — el downside es reversible, pero a un precio alto (unos seis
# Reforester adyacentes para compensar los +0.5/s de una `toxic`).
func _apply_map_downside(downside):
	var tile_map = get_node_or_null("TileMap");
	if tile_map == null:
		return;
	var cells = int(downside.get("cells", 0));
	var ttype = downside.get("type", "");
	if cells <= 0 or ttype == "":
		return;
	var candidates = _degradable_cells(tile_map);
	candidates.shuffle();
	for cell in candidates.slice(0, cells):
		if not tile_map.degradeCell(cell, ttype):
			continue;
		# Nace sucia, con un segundo de su propia pasiva encima. Si naciera limpia no habría
		# nada que limpiar y el check del frame siguiente la devolvería intacta: el castigo
		# duraría un frame.
		if pollutionManager:
			var passive = float(tile_map.getCellTypeDef(cell).get("passive_pollution_per_tick", 0.0));
			if passive > 0.0:
				pollutionManager.addPollution(passive, cell);

# Elegibles: suelo llano, libre y sin tipo. Se descartan las casillas con factoría —degradar
# una no le quita nada al jugador y el castigo sería invisible— y las que ya tienen tipo:
# pisar una especial borraría el mapa curado para siempre, porque al restaurarse vuelve como
# suelo normal y el bosque, las ruinas o el lago no volverían. De paso, eso impide degradar
# dos veces la misma casilla.
func _degradable_cells(tile_map):
	var cells = [];
	for cell in tile_map.get_used_cells(0):
		if tile_map.cell_types.has(cell):
			continue;
		if _get_factory_at_cell(cell) != null:
			continue;
		cells.append(cell);
	return cells;

func _on_run_won(stats):
	_end_run("win");
	# Una run terminada no se reanuda. Solo run.json: save.json es del saveManager, justo abajo.
	runSave.clear();
	_close_menus();
	stats["factories_placed"] = factoryArray.size();
	# Guardar progresión
	if saveManager:
		saveManager.record_run_completion(float(stats.get("time", 0.0)));
		# Desbloquear paquetes si aplica (runs completadas >= 1 desbloquea todos los paquetes)
		var runs = saveManager.get_runs_completed();
		if runs >= 1:
			saveManager.unlock_package("lumberjack");
			saveManager.unlock_map("wasteland_01");
		if runs >= 3:
			saveManager.unlock_package("ecologist");
	get_tree().paused = true;
	var summary = load("res://ui/runSummary.gd").new();
	summary.name = "RunSummary";
	add_child(summary);
	summary.initialize(stats, true);
	summary.restart_pressed.connect(reset);
	if analytics:
		analytics.track("ui_open", {"screen": "run_summary"});

# Espejo de _on_run_won(), con una asimetría deliberada: perder NO registra progresión. Ver
# _close_lost_run() — lo único que se queda aquí es pausar, que es lo que necesita el árbol.
func _on_run_lost(stats):
	_end_run("lose");
	get_tree().paused = true;
	_close_lost_run(stats);

# El cierre de una run perdida, sin el árbol de por medio: vive aparte por lo mismo que
# _apply_granted_upgrades(), para poder afirmar que perder no toca user://save.json sin tener
# que montar la escena entera. Lo que hay que poder demostrar es la asimetría, no que la
# pantalla se dibuje.
func _close_lost_run(stats):
	_close_menus();
	# Perder tampoco deja run que reanudar —si no, cerrar y continuar desharía la derrota—. Borra
	# run.json y SOLO ese: save.json no se toca al perder (ver abajo).
	runSave.clear();
	# gameManager lo emite a 0 —no lleva la cuenta de lo construido—, igual que en la victoria.
	stats["factories_placed"] = factoryArray.size();
	# Aquí NO va el bloque de saveManager de _on_run_won(): perder no incrementa
	# `runs_completed`, no toca el mejor tiempo y no desbloquea ni paquetes ni mapas. La
	# meta-progresión se gana terminando la run, y esta no ha terminado.
	# Se reutiliza runSummary y no se escribe una pantalla de derrota aparte: su initialize()
	# ya pinta «Run fallida» y, sobre todo, ya se pone en PROCESS_MODE_ALWAYS — una pantalla
	# nueva saldría muerta bajo el get_tree().paused de arriba.
	var summary = load("res://ui/runSummary.gd").new();
	summary.name = "RunSummary";
	add_child(summary);
	summary.initialize(stats, false);
	summary.restart_pressed.connect(reset);
	if analytics:
		analytics.track("ui_open", {"screen": "run_summary"});

func reset():
	# Reiniciar abandona la run: su save se va con ella.
	runSave.clear();
	get_tree().paused = false;
	for node_name in ["UpgradeScreen", "RunSummary", "TokenUnlock", "Player", "TileMap", "GameManager", "PollutionManager", "BeltNetwork", "WeatherManager"]:
		var node = get_node_or_null(node_name);
		if node:
			node.queue_free();
	for fabrica in factoryArray:
		fabrica.queue_free();
	factoryArray.clear();
	pollutionManager = null;
	gameManager = null;
	placer = null;
	beltNetwork = null;
	weatherManager = null;
	_drag_start_cell = null;
	_hovered_factory = null;
	_hide_factory_panel();
	_hide_factory_tooltip();
	_show_package_select();

# ---------- Serialización de Run (M4): cuándo se guarda ----------

# ¿Hay una run que merezca reanudarse? Montada (gameManager vivo, con su Player y su TileMap) y
# sin resumen en pantalla: una run ganada o perdida ya terminó, y guardarla permitiría deshacer
# la derrota cerrando el juego. La oferta de cartas abierta SÍ cuenta como viva: el snapshot la
# lleva en `pending_offer`.
func _run_alive() -> bool:
	if gameManager == null or not is_instance_valid(gameManager) or pollutionManager == null:
		return false;
	if get_node_or_null("Player") == null or get_node_or_null("TileMap") == null:
		return false;
	var summary = get_node_or_null("RunSummary");
	return summary == null or summary.is_queued_for_deletion();

# Escribe la run en curso. Sin run viva no escribe NADA —ni borra—: el fichero que hubiera es
# de una run anterior y lo gestiona su propio ciclo (ganar, perder, reiniciar, continuar).
# Devuelve si quedó escrita, que es lo que decide `suspend` o `abandon` al cerrar.
func _save_run() -> bool:
	if not _run_alive():
		return false;
	return runSave.write(_capture_run());

# Cerrar la ventana SIN Augur: no hay `closing`, así que el guardado va aquí. Con Augur también
# llega (después de `_on_app_closing()`, porque el autoload la recibe antes) y vuelve a escribir
# lo mismo: inofensivo. NO cierra la analítica: sin Augur su `track()` no manda nada.
func _notification(what):
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_save_run();

# Cerrar la ventana CON Augur (atado a `Augur.closing` en _configure_augur()): se guarda primero y
# la run se cierra como `suspend` si quedó en disco, o `abandon` si no se pudo escribir. Sin run
# viva `end_run()` no manda nada.
func _on_app_closing():
	if analytics:
		analytics.end_run("suspend" if _save_run() else "abandon");
	else:
		_save_run();

# ---------- Serialización de Run (M1): la captura ----------

# La run en curso como un Dictionary de tipos JSON puros —ni un Vector2i, ni un nodo, ni un
# Object—: cada objeto vivo sabe qué es suyo (su `snapshot()`) y Main solo compone, más lo que
# solo Main sabe: el mapa y el paquete elegidos, el diff del mapa y la oferta de cartas abierta.
# Presupone run viva; decidir si la hay es cosa de quien guarda (M4).
func _capture_run() -> Dictionary:
	var fabricas = [];
	for fab in factoryArray:
		if is_instance_valid(fab):
			fabricas.append(fab.snapshot());
	var player_node = get_node("Player");
	return {
		"version": RunSave.VERSION,
		"params_hash": _params_hash,
		"map_id": _run_map_id,
		"package_id": _run_package_id,
		"prev_checkpoint_t": float(_prev_checkpoint_t),
		# El `run_id` de ESTA run: la que se reanude abrirá uno nuevo y lo citará (M4).
		"resumed_from": analytics.run_id() if analytics else "",
		"cells": _capture_cells(get_node("TileMap")),
		"bag": player_node.get_node("Bag").snapshot(),
		"player": player_node.snapshot(),
		"pollution": pollutionManager.snapshot(),
		"game": gameManager.snapshot(),
		"weather": weatherManager.snapshot() if weatherManager else null,
		"belts": beltNetwork.snapshot() if beltNetwork else [],
		"factories": fabricas,
		"pending_offer": _capture_pending_offer(),
	};

# El DIFF entre los tipos de casilla de ahora y los que deja tileMap.generate() con el mapa del
# JSON: un tipo nuevo o cambiado sale con su nombre, uno que ha desaparecido sale `null`. Hoy
# solo hay tres mutaciones —`toxic` degradada por carta, `toxic` restaurada, ruina consumida— y
# cada una se repite al reanudar con su función de verdad, que es la que repinta tinte y sprite.
# La base se rehace leyendo `special_cells` igual que generate() rellena `cell_types`: todas, sin
# filtrar por tipo, y la última gana si una celda se repitiera.
func _capture_cells(tile_map) -> Dictionary:
	var base = _base_cell_types(_map_data_by_id(_run_map_id));
	var diff = {};
	for cell in tile_map.cell_types:
		var ahora = String(tile_map.cell_types[cell]);
		if base.get(cell, null) != ahora:
			diff[RunSave.cell_key(cell)] = ahora;
	for cell in base:
		if not tile_map.cell_types.has(cell):
			diff[RunSave.cell_key(cell)] = null;
	return diff;

# La oferta de cartas que hay en pantalla, si la hay: se guarda TAL CUAL —reanudar no re-baraja—
# y las concedidas no, porque ya están aplicadas al montarla. Los ids salen de `_offer_ids`, que
# _remember_offer() escribe al montar cualquiera de las dos pantallas y _track_offer() vacía al
# elegir. Una pantalla ya elegida sigue en el árbol hasta final de frame (queue_free()), por eso
# se mira también `is_queued_for_deletion()`.
func _capture_pending_offer():
	for nombre in ["UpgradeScreen", "TokenUnlock"]:
		var screen = get_node_or_null(nombre);
		if screen != null and not screen.is_queued_for_deletion():
			var ids = [];
			for id in _offer_ids:
				ids.append(String(id));
			return {"source": String(_offer_source), "ids": ids};
	return null;

# La entrada de `Maps` del JSON con ese id, o {} si no está. Al reanudar es lo que sustituye a
# pick_map(): el mapa no se elige, se busca.
func _map_data_by_id(map_id) -> Dictionary:
	for m in fileData.get("Maps", []):
		if String(m.get("id", "")) == String(map_id):
			return m;
	return {};

# Los tipos de casilla que tileMap.generate() deja con ese mapa, sin mutación ninguna: la base
# contra la que se calcula el diff de `cells` y contra la que se reaplica. Todas las
# `special_cells`, sin filtrar por tipo, y la última gana si una celda se repitiera —igual que
# generate()—.
func _base_cell_types(map_data: Dictionary) -> Dictionary:
	var base = {};
	for sc in map_data.get("special_cells", []):
		base[Vector2i(int(sc["pos"][0]), int(sc["pos"][1]))] = String(sc["type"]);
	return base;

# ---------- Serialización de Run (M2): la restauración en memoria ----------

# Reanuda una run desde su snapshot, sobre un Main sin run viva. El orden ES la decisión del
# plan («restauración en dos fases»): build() re-DERIVA tick, output, workers y sinergias de lo
# que hay ahora, así que primero se instancian las factorías y después se pisa todo con lo
# guardado; la bolsa y los managers, los últimos, porque build() les ha tocado cosas (workers).
# Devuelve false sin montar nada si el mapa del snapshot ya no existe en el JSON.
func _continue_game(snap: Dictionary) -> bool:
	# 2. El mapa se BUSCA por id, no se baraja: pick_map() devolvería otro.
	var map_data = _map_data_by_id(snap.get("map_id", ""));
	if map_data.is_empty():
		push_warning("Main: el snapshot cita el mapa '%s', que no está en el JSON" % str(snap.get("map_id", "")));
		return false;
	# 1. Player + grid como una run nueva, SIN apply_package(): suma stock, workers y boosts, y
	# todo eso ya está en la bolsa y el Player guardados.
	_mount_player_and_grid();
	var player_node = get_node("Player");
	var bag = player_node.get_node("Bag");
	var tile_map = get_node("TileMap");
	# 3. El mismo cableado que una run nueva, pero SIN almacén: vuelve con las factorías.
	_mount_run(map_data, false);
	# 4. DESPUÉS de apply_map(), que acaba de repartir `pollution_start`: restore() lo pisa. Al
	# revés, la suciedad de partida se sumaría a la guardada.
	pollutionManager.restore(snap.get("pollution", {}));
	# 5. Las mutaciones del mapa, con sus funciones de verdad (tinte, sprite).
	_restore_cells(tile_map, snap.get("cells", {}), _base_cell_types(map_data));
	# 6. Las factorías, en dos fases. build() SIN cobro —ya se pagaron— y con el Player y la
	# bolsa recién montados; luego restore() pisa lo derivado. NUNCA register_and_evaluate() (las
	# sinergias vienen guardadas y recalcularlas con el mapa a medio montar daría otras) ni los
	# efectos on_build del tile (la suciedad del suelo quemado ya está en `pollution_per_cell` y
	# la ruina ya está consumida en `cells`). Por eso no se pasa por _on_factory_chosen().
	for d in snap.get("factories", []):
		var cell = RunSave.parse_cell(String(d.get("cell", "0,0")));
		var fab = placer.build(String(d.get("type", "")), cell, player_node, bag, tile_map);
		if fab == null:
			continue;
		add_child(fab);
		factoryArray.append(fab);
		fab.restore(d);
		# A mano para todas, almacén incluido: sin el bind(fab) la factoría produce al vacío
		# (_on_resource_produced() necesita la celda de origen).
		fab.resource_produced.connect(_on_resource_produced.bind(fab));
	# 7. La red, con la cache de factorías invalidada (restore() lo hace).
	beltNetwork.restore(snap.get("belts", []));
	# 8. Los últimos: pisan lo que build() tocó —los workers que asignó por orden de llegada—.
	player_node.restore(snap.get("player", {}));
	bag.restore(snap.get("bag", {}));
	gameManager.restore(snap.get("game", {}));
	if weatherManager and snap.get("weather", null) is Dictionary:
		weatherManager.restore(snap["weather"]);
	# 9. Lo que solo Main sabe.
	_run_package_id = String(snap.get("package_id", ""));
	_run_map_id = String(map_data.get("id", ""));
	_prev_checkpoint_t = float(snap.get("prev_checkpoint_t", 0.0));
	_offer_ids = [];
	# 10. Una run NUEVA para la analítica (`run_id` nuevo), enlazada con la guardada por
	# `resumed_from`: aquella ya mandó su `run_end` con `suspend` al cerrarse (M4).
	if analytics:
		analytics.begin_run(gameManager, pollutionManager, bag, tile_map, factoryArray,
			_run_package_id, _run_map_id, String(snap.get("resumed_from", "")));
	# El HUD se pinta UNA vez aquí, antes de reabrir la oferta: con oferta pendiente el árbol se
	# pausa en el paso 11 sin que _process() haya corrido ni un frame, y detrás de las cartas se
	# veía el texto de relleno de Main.tscn («Objective: 2 wood») en vez de la run (visto con
	# tools/ver_serializacion.gd, 2026-10-01).
	_paint_hud(bag);
	# 11. La oferta que estaba en pantalla, tal cual: mismas cartas, sin re-barajar. El token no
	# guarda ids porque _show_factory_token_screen() no baraja: ofrece las tres primeras
	# candidatas, y con el Player ya restaurado son las mismas.
	var oferta = snap.get("pending_offer", null);
	if oferta is Dictionary:
		if String(oferta.get("source", "")) == "token":
			_show_factory_token_screen();
		else:
			var ids = [];
			for id in oferta.get("ids", []):
				ids.append(String(id));
			_show_upgrade_offer(ids, String(oferta.get("source", "checkpoint")));
	# 12. El save se borra al cargarlo: reanudar no es rebobinar. Si el juego se cierra ahora, lo
	# que vuelva a haber en disco lo escribirá el autoguardado de ESTA run (M4).
	runSave.clear();
	return true;

# Los dos textos del HUD, los mismos que pinta _process() cada frame. Solo con ventana: sin ella
# nadie los lee (Rendimiento M0b), y los Main de la suite no tienen los Label.
func _paint_hud(bag):
	if not render_enabled:
		return;
	var label = get_node_or_null("Label");
	if label:
		label.text = _buildResourceText(bag);
	var objective = get_node_or_null("Objective");
	if objective and gameManager:
		objective.text = gameManager.getObjectiveText(bag, pollutionManager);

# Lo que llamará el «CONTINUAR» del menú (M5): el fichero, si vale para este balance, y la run.
# Un save inválido lo borra read_valid() y aquí solo se devuelve false.
func _continue_from_file() -> bool:
	var snap = runSave.read_valid(_params_hash);
	if snap.is_empty():
		return false;
	return _continue_game(snap);

# Reaplica el diff de `cells` sobre el mapa recién generado, con las tres mutaciones que el juego
# sabe hacer y que no se pisan entre sí:
#   · un tipo nuevo (hoy solo `toxic`, el downside de una carta) → degradeCell(), que tiñe;
#   · `null` sobre una `ruins` → la ruina se consumió al construir encima: se borra el tipo y
#     nada más, IGUAL que _on_factory_chosen() (el sprite de la ruina se quedaba);
#   · `null` sobre cualquier otro tipo (hoy `toxic`, restaurada por _check_toxic_unlock()) →
#     restoreCell(), que le quita tinte y sprite.
func _restore_cells(tile_map, cells: Dictionary, base: Dictionary):
	for key in cells:
		var cell = RunSave.parse_cell(String(key));
		var tipo = cells[key];
		if tipo != null:
			tile_map.degradeCell(cell, String(tipo));
		elif base.get(cell, "") == "ruins":
			tile_map.cell_types.erase(cell);
		else:
			tile_map.restoreCell(cell);
