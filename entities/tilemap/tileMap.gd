extends TileMap

var last_hovered_cell: Vector2i = Vector2i(-1, -1);
var pollution_manager = null;
var belt_network = null;
var cell_types = {};      # Vector2i -> String (tile type id)
var tile_type_data = {};  # String -> dict (from JSON TileTypes)
var _cell_sprite_sources = {};  # Vector2i -> int  (cells using a custom sprite source_id)
var _cell_colors = {};    # Vector2i -> Color
var _tint_overlay = null; # canvas item propio para el tinte; ver TintOverlay
var _status_overlay = null; # canvas item propio para el estado de las factorías; ver StatusOverlay
var _factory_array = [];  # las factorías vivas; la inyecta Main, ver setFactories()
var game_manager = null;  # de él sale la ventana del punto muerto; ver setGameManager()
var weather_manager = null;  # clima por zonas (lluvia, viento, tinte M5); ver setWeatherManager()

# Alpha máximo del tinte de colapso, el que se alcanza con la gracia agotada. Es un tope de
# LEGIBILIDAD, no de balance: a 0,55 el rojo manda sobre el color del tipo (0,45) y sobre el
# de contaminación de una casilla ya bloqueada (0,5), pero todavía deja ver las factorías y
# las cintas, que van en overlays superiores. Lo que dura la subida NO está aquí: sale de
# DEADLOCK_GRACE, que es provisional y se lee del gameManager, nunca se copia.
const COLLAPSE_MAX_ALPHA = 0.55;
# Más oscuro y sin verde, frente al rojo anaranjado (1.0, 0.15, 0.0) de la contaminación: son
# dos avisos distintos —«esta casilla está sucia» y «la run se muere»— y no deben confundirse.
const COLLAPSE_COLOR = Color(0.85, 0.0, 0.0);

# El tinte de casilla NO puede salir por el _draw() de este nodo. Un TileMap pinta cada capa
# en un canvas item HIJO del suyo, así que lo que dibuje el nodo queda por debajo de los
# tiles y no llega nunca a pantalla: por eso los ocho tipos de casilla sin sprite —forest,
# mineral, fertile, stream, swamp, ruins, burned, toxic— eran invisibles y el páramo se veía
# igual que el bosque. El color sale por este nodo aparte, que es hijo del TileMap (hereda su
# transform, así que map_to_local() sigue valiendo) y lleva z_index propio para quedar por
# encima del suelo y del highlight de hover.
class TintOverlay extends Node2D:
	var tile_map = null;
	func _draw():
		if tile_map:
			tile_map.draw_tints(self);

# Y el estado de las factorías paradas va en un canvas item aparte, no en una pasada más del
# TintOverlay: el tinte se repinta cuando cambia la contaminación y el estado cuando cambia la
# producción, así que compartir nodo obligaría a repintar el mapa entero cada vez que una
# factoría cambia de humor. El z_index es el 3 y no el 2 porque el 2 ya es del BeltOverlay
# (managers/beltNetwork.gd, _ensure_overlay()), que cuelga de ESTE mismo nodo: el icono de
# parada tiene que verse aunque cruce una cinta por la casilla, así que va por encima.
class StatusOverlay extends Node2D:
	var tile_map = null;
	func _draw():
		if tile_map:
			tile_map.draw_status(self, tile_map._factory_array);

# Genera el mapa de tiles a partir de los datos del JSON.
func generate(size_array, blocked_array, special_cells = [], type_data = {}):
	clear_layer(0);
	clear_layer(2);
	cell_types.clear();
	_cell_sprite_sources.clear();
	_cell_colors.clear();
	tile_type_data = type_data;
	var blocked = [];
	for bc in blocked_array:
		blocked.append(Vector2i(int(bc[0]), int(bc[1])));
	for y in range(size_array[1]):
		for x in range(size_array[0]):
			var cell = Vector2i(x, y);
			if not blocked.has(cell):
				set_cell(0, cell, 1, Vector2i(0, 0));
	# Registrar y colorear celdas especiales
	for sc in special_cells:
		var cell = Vector2i(int(sc["pos"][0]), int(sc["pos"][1]));
		var ttype = sc["type"];
		cell_types[cell] = ttype;
		if not type_data.has(ttype):
			continue;
		var tdef = type_data[ttype];
		var sprite_source = int(tdef.get("sprite_source_id", -1));
		if sprite_source >= 0:
			# overlay_layer: true → capa 2 (encima del highlight), false → capa 0 (nivel suelo)
			var target_layer = 2 if tdef.get("overlay_layer", false) else 0;
			set_cell(target_layer, cell, sprite_source, Vector2i(0, 0));
			_cell_sprite_sources[cell] = sprite_source;
		elif not tdef.get("buildable", true):
			# No buildable sin sprite: quitar tile
			erase_cell(0, cell);
		else:
			# Buildable sin sprite: tint de color
			var col_arr = tdef.get("color", [1,1,1,1]);
			set_cell_color(cell, Color(col_arr[0], col_arr[1], col_arr[2], col_arr[3]));
	# Centrar el mapa en pantalla
	var tl = map_to_local(Vector2i(0, 0));
	var br = map_to_local(Vector2i(size_array[0] - 1, size_array[1] - 1));
	var map_center = (tl + br) / 2.0;
	var screen_size = get_viewport().get_visible_rect().size;
	position = screen_size / 2.0 - map_center;
	var cam = get_viewport().get_camera_2d();
	if cam:
		cam.global_position = screen_size / 2.0;
	_ensure_overlay();
	_redraw_tints();

func set_cell_color(cell, color):
	_cell_colors[cell] = color;

func _ready():
	_ensure_overlay();

# El overlay se crea aquí y no en la escena porque el dibujo y la capa por la que sale son la
# misma decisión: quien toque uno tiene que ver el otro.
func _ensure_overlay():
	# Los dos se comprueban por separado y no con un `return` común: quien añada un tercero
	# tiene que poder crearlo sin que la existencia del primero se lo salte.
	if _tint_overlay == null or not is_instance_valid(_tint_overlay):
		_tint_overlay = TintOverlay.new();
		_tint_overlay.name = "TintOverlay";
		_tint_overlay.tile_map = self;
		# z_index 1 = la misma altura que la capa 2 (sprites de montaña/lago/lava). No compiten:
		# una casilla con sprite no lleva tinte.
		_tint_overlay.z_index = 1;
		add_child(_tint_overlay);
	if _status_overlay == null or not is_instance_valid(_status_overlay):
		_status_overlay = StatusOverlay.new();
		_status_overlay.name = "StatusOverlay";
		_status_overlay.tile_map = self;
		# z_index 3 = por encima del tinte (1) y de las cintas (2). Es la decisión entera del
		# hito: una factoría parada con una cinta cruzándole la casilla tiene que seguir
		# enseñando por qué está parada.
		_status_overlay.z_index = 3;
		add_child(_status_overlay);

# Sustituye al queue_redraw() de este nodo: el color ya no lo pinta el TileMap, así que
# repintarlo a él no dibujaría nada. Lo llama todo lo que cambia un tinte.
func _redraw_tints():
	if _tint_overlay != null and is_instance_valid(_tint_overlay):
		_tint_overlay.queue_redraw();

# El gemelo de _redraw_tints() para el estado, y separado a propósito por lo mismo que lo
# están los dos nodos: el tinte se repinta con la contaminación y el estado con la producción.
func _redraw_status():
	if _status_overlay != null and is_instance_valid(_status_overlay):
		_status_overlay.queue_redraw();

func _process(_delta):
	_update_hover();
	_redraw_tints();
	# Por frame y sin señal, igual que el tinte: `blocked_reason` cambia en el tick de cada
	# factoría, y una señal por cambio costaría ~1.300 emisiones por frame con el mapa saturado
	# —el mismo coste por el que el PollutionManager tampoco emite nada— para un dibujo que se
	# vuelve a pintar en el frame siguiente.
	_redraw_status();

func tick_passive(pollution_manager_ref, delta):
	# Llamado por Main cada frame: efecto pasivo de lake, toxic, etc.
	# passive_pollution_per_tick está expresado POR SEGUNDO, así que se escala por
	# delta; sin esto se aplicaría entero en cada frame (~60 veces por segundo).
	for cell in cell_types:
		var ttype = cell_types[cell];
		if not tile_type_data.has(ttype):
			continue;
		var passive = float(tile_type_data[ttype].get("passive_pollution_per_tick", 0.0)) * delta;
		if passive < 0.0:
			# Los tiles que limpian lo hacen EN ÁREA, igual que un Reforester. Sobre su propia
			# celda no tienen nada que restar —nada ensucia un lago: la producción ensucia solo
			# la casilla de la factoría y sobre un lago no se puede construir—, así que sin el
			# reparto son tiles inertes en vez de un buen sitio donde construir al lado.
			pollution_manager_ref.removePollutionArea(-passive, cell);
		elif passive > 0.0:
			# Los que ensucian siguen ensuciando solo la suya: un foco es un foco.
			pollution_manager_ref.addPollution(passive, cell);
	_tick_weather_passive(pollution_manager_ref, delta);

# Pasiva del clima (Plan «Eventos Climáticos», M2): la lluvia. Pasada PROPIA y no dentro del
# bucle de arriba porque ese recorre `cell_types`, que solo tiene las casillas especiales: la
# lluvia no llegaría nunca al suelo normal, que es donde están las factorías y lo sucio.
# Recorre las casillas de las zonas activas (sin repetir las de dos zonas solapadas: la suma
# ya la hace getPassiveAt()) que tengan tile de suelo, es decir, que sean del mapa.
# Por SEGUNDO como todo lo pasivo: se escala por delta.
# CASILLA A CASILLA y no en área como el lago: la zona ya es el área, y repartir cada casilla
# entre sus 8 vecinas sacaría la lluvia de su zona. removePollution() solo descuenta del global
# lo que quita de verdad de la casilla, así que llover sobre suelo limpio no acerca la victoria.
# Una casilla con lago bajo la lluvia suma los dos pasivos: es coherente y no se evita.
# Sin manager (la suite monta TileMaps sueltos), con él liberado o sin eventos: no hace nada.
func _tick_weather_passive(pollution_manager_ref, delta):
	if not is_instance_valid(weather_manager) or weather_manager.active.is_empty():
		return;
	var seen = {};
	for ev in weather_manager.active:
		for y in range(ev.rect.position.y, ev.rect.end.y):
			for x in range(ev.rect.position.x, ev.rect.end.x):
				var cell = Vector2i(x, y);
				if seen.has(cell):
					continue;
				seen[cell] = true;
				if not _existsOnGround(cell):
					continue;
				var passive = weather_manager.getPassiveAt(cell) * delta;
				if passive < 0.0:
					pollution_manager_ref.removePollution(-passive, cell);
				elif passive > 0.0:
					pollution_manager_ref.addPollution(passive, cell);

# El contagio: una casilla saturada desborda sobre sus vecinas. Sin él, el ahogo solo ensucia
# la casilla de cada factoría y un mapa de 16x10 conserva decenas de casillas limpias para
# siempre: el punto muerto nunca se alcanzaría y la derrota sería teórica.
# Vive aquí y no en el manager por lo mismo que tick_passive: el TileMap es quien sabe qué
# casillas existen, así que es quien puede impedir que el desborde se salga del mapa.
# Calcado de tick_passive() en la FORMA, no en el recorrido: tick_passive itera cell_types,
# que solo tiene las casillas con tipo especial (lake, toxic, lava...). Las que se contaminan
# son suelo normal con una factoría encima y no están ahí — viven en pollution_per_cell, que
# es lo que se recorre aquí. Iterando cell_types el contagio no se dispararía jamás.
# contagion_rate está POR SEGUNDO, como passive_pollution_per_tick: se escala por delta.
func tick_contagion(pollution_manager_ref, delta):
	var amount = pollution_manager_ref.contagion_rate * delta;
	if amount <= 0.0:
		return;
	var is_valid = Callable(self, "_existsOnGround");
	# Los focos se congelan ANTES de tocar nada: spreadFrom() crea entradas nuevas en
	# pollution_per_cell (las vecinas que estaban limpias) y modificar un diccionario mientras
	# se recorre es un error. Además, una vecina recién ensuciada no debe contagiar en el mismo
	# frame en que la han ensuciado: el orden del diccionario decidiría cuánto se propaga.
	var sources = [];
	for cell in pollution_manager_ref.pollution_per_cell:
		if pollution_manager_ref.pollution_per_cell[cell] <= pollution_manager_ref.contagion_pollution:
			continue;
		# Una casilla sin tile en el suelo está fuera del mapa (canPlaceFactory la rechaza por
		# esa misma condición): ni recibe contagio ni lo emite.
		if not _existsOnGround(cell):
			continue;
		sources.append(cell);
	# Viento (clima M4): un foco dentro de una zona de viento no reparte entre las 8 vecinas
	# sino que lo manda todo a la de sotavento. SOLO cambia la dirección: la cantidad total
	# se conserva —spreadFrom() da `amount` a CADA vecina, así que sotavento recibe 8×amount—,
	# y ni contagion_rate, ni el umbral, ni la congelación de focos de arriba se tocan (de
	# ellos cuelga la derrota). Si la vecina de sotavento no existe (borde del mapa), el foco
	# contagia como siempre: el viento no puede tirar suciedad fuera del mapa ni hacerla
	# desaparecer. Sin WeatherManager, sin viento o con el clima suspendido (plan B 1) la
	# dirección es ZERO y el camino es exactamente el de antes.
	var downwind_amount = amount * pollution_manager_ref.NEIGHBOR_OFFSETS.size();
	for cell in sources:
		var dir = _windAt(cell);
		if dir != Vector2i.ZERO and _existsOnGround(cell + dir):
			pollution_manager_ref.addPollution(downwind_amount, cell + dir);
		else:
			pollution_manager_ref.spreadFrom(cell, amount, is_valid);

# Dirección del viento sobre `cell`, o ZERO si no hay manager inyectado (TileMap suelto en
# la suite o antes de _start_game) o no sopla ahí.
func _windAt(cell) -> Vector2i:
	if not is_instance_valid(weather_manager):
		return Vector2i.ZERO;
	return weather_manager.getContagionDirectionAt(cell);

# Única verdad de «esta casilla existe» para el contagio, y la misma condición 1 de
# canPlaceFactory(): sin tile en la capa de suelo, la casilla no es del mapa.
func _existsOnGround(cell) -> bool:
	return get_cell_source_id(0, cell) != -1;

func getCellType(cell) -> String:
	return cell_types.get(cell, "");

func getCellTypeDef(cell) -> Dictionary:
	var ttype = cell_types.get(cell, "");
	if ttype == "" or not tile_type_data.has(ttype):
		return {};
	return tile_type_data[ttype];

# Degrada una casilla en caliente: es el downside de una mejora (Main._apply_map_downside).
# A diferencia de generate(), que a un tipo no construible y sin sprite le borra el tile del
# suelo, aquí el tile se conserva a propósito: una casilla sin tile queda fuera del mapa
# —canPlaceFactory() la rechaza por su condición 1 y la limpieza de un Reforester no tendría
# nada que devolver—, y el castigo dejaría de ser reversible. Basta el tinte del tipo para
# que se vea, y `buildable: false` para que deje de admitir factorías.
func degradeCell(cell, ttype) -> bool:
	if not tile_type_data.has(ttype) or get_cell_source_id(0, cell) == -1:
		return false;
	cell_types[cell] = ttype;
	var col_arr = tile_type_data[ttype].get("color", [1, 1, 1, 1]);
	set_cell_color(cell, Color(col_arr[0], col_arr[1], col_arr[2], col_arr[3]));
	_redraw_tints();
	return true;

# Devuelve una casilla degradada a suelo normal cuando se ha limpiado del todo. Le quita
# también el tinte y el sprite: sin eso una casilla ya restaurada seguiría pintada de verde
# tóxico y el jugador no vería que puede volver a construir ahí.
func restoreCell(cell):
	cell_types.erase(cell);
	_cell_colors.erase(cell);
	_cell_sprite_sources.erase(cell);
	set_cell(0, cell, 1, Vector2i(0, 0));
	_redraw_tints();

func isBuildable(cell) -> bool:
	var tdef = getCellTypeDef(cell);
	if tdef.is_empty():
		return true;
	return tdef.get("buildable", true);

# La categoría de factoría que LIMPIA (`type` en factoryParams.json). Es la misma cadena con
# la que factoryData decide que una factoría no se ahoga y reparte su limpieza en área, y por
# eso vive en una constante: la regla de abajo y la del ahogo hablan del mismo conjunto de
# factorías, y escribir el literal en dos sitios dejaría que se separasen.
const RESTORATION_KIND = "restoration";

# Las 8 vecinas de una casilla, en el mismo orden y con la misma forma que el
# NEIGHBOR_OFFSETS de factoryPlacer. Se repite la lista y no se importa la de allí a
# propósito: son dos vecindades que hoy coinciden pero responden a preguntas distintas —una
# es la de las sinergias y ésta la de la GEOGRAFÍA de la casilla—, y hacer que una dependa de
# la otra ataría el día que alguna quiera cambiar de forma.
const ADJACENCY_OFFSETS = [
	Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
	Vector2i(-1, 0),                   Vector2i(1, 0),
	Vector2i(-1, 1),  Vector2i(0, 1),  Vector2i(1, 1),
];

# El bloque `Factories` del JSON, del que sale `requires_adjacent`. Es el cuarto setter de
# inyección, hermano de setPollutionManager()/setBeltNetwork()/setFactories() y por lo mismo:
# la regla tiene que vivir en el único punto de verdad de «¿cabe aquí?» y no repartida por los
# llamadores, y el TileMap no conoce el JSON de factorías por su cuenta.
# El default {} es para quien no lo inyecta —la suite y cualquier montaje a mano—: sin él,
# `requires_adjacent` es lista vacía y canPlaceFactory() se comporta exactamente como antes.
var factory_params = {};

func setFactoryParams(params):
	factory_params = params if params != null else {};

# Los tipos de casilla que ESE tipo de factoría exige tener al lado (`requires_adjacent` del
# JSON, opcional). Su ausencia significa «ninguno», que es lo que declaran las ocho entradas
# que no lo llevan: nada que no lo declare se entera de que existe la regla, mismo contrato
# que `materials: [...]` y que `cost`.
func requiredAdjacentTypes(factory_type: String) -> Array:
	if factory_type == "":
		return [];
	return factory_params.get(factory_type, {}).get("requires_adjacent", []);

# Único punto de verdad de "¿cabe una factoría aquí?": agrupa las seis condiciones.
# factory_array es el array de factorías vivas que Main comparte por referencia con
# factoryPlacer; se recorre aquí para no depender de ningún otro nodo.
#
# `factory_kind` es la CATEGORÍA de lo que se quiere colocar —el campo `type` del JSON:
# "production", "restoration" o "storage"—, y va al final con default "" porque desde M7 del
# Plan «Costes de Construcción» (2026-09-19) la respuesta depende de ella y no todos los
# llamantes tienen una a mano. El "" NO es «cualquiera»: es la regla ESTRICTA, exactamente la
# de antes de M7, y es lo que siguen preguntando hasBuildableCell() —y con ella la condición 3
# del punto muerto— y la validación del arrastre de cinta, que no coloca factorías.
#
# 🔴 LA CASILLA SATURADA SE CIERRA A LA PRODUCCIÓN, NO A LA LIMPIEZA (M7). `cell_block_pollution`
# existe para impedir que levantes una fábrica sobre suelo muerto, no para impedir que lo
# LIMPIES, y es la misma idea que ya sostenía `factoryData.getPollutionChoke()`: las de
# restauración no se ahogan, porque limpiar tiene que funcionar siempre o la espiral deja de
# ser un castigo y pasa a ser una sentencia. Hasta M7 faltaba la otra mitad de esa idea: de
# nada sirve que el Reforester rinda igual sobre suelo muerto si el suelo muerto es justo
# donde no se le deja poner: con la casilla saturada cerrada a todo, las casillas libres
# estaban limpias y las sucias no admitían limpiador, así que la fase 2 no se podía ganar. La
# regla la fija la prueba «Costes M7» de tests/run_tests.gd.
#
# 🔴 Y `factory_type` es un CUARTO parámetro, con el NOMBRE del tipo, porque el tercero ya
# estaba ocupado por la categoría (Variedad M4, 2026-09-22). Lo pasan solo los dos caminos del
# gesto de construir —Main._show_radial_menu() y Main._on_factory_chosen()—, y quien no lo
# pase se comporta EXACTAMENTE como hoy: es lo que deja intactas la regla estricta de
# hasBuildableCell() —condición 3 del punto muerto— y la validación del arrastre de cinta, que
# cuelgan del default "" del tercero y no deben enterarse de la regla nueva. Una cinta no es
# una factoría y no tiene geografía que respetar.
func canPlaceFactory(cell, factory_array, factory_kind: String = "", factory_type: String = "") -> bool:
	# 1. El tile existe en la capa de suelo
	if get_cell_source_id(0, cell) == -1:
		return false;
	# 2. No está bloqueada por contaminación. La excepción, y la única: una factoría de
	# restauración SÍ cabe sobre la casilla saturada, que es la que hay que limpiar.
	if factory_kind != RESTORATION_KIND and isCellBlocked(cell):
		return false;
	# 3. El tipo de casilla admite construcción (toxic bloqueado hasta restaurar)
	if not isBuildable(cell):
		return false;
	# 4. La celda está libre: una factoría por casilla
	for fab in factory_array:
		if fab.cell_position == cell:
			return false;
	# 5. No hay cinta tendida en la celda. Las cintas ocupan casilla construible: es lo que
	# convierte tender una cinta en una decisión y no en decoración (decidido el 2026-09-18
	# tras medir M0: 92 casillas libres al cerrar el checkpoint 5 contra las 20 exigidas, así
	# que los números no obligan a renunciar a ello). Por vivir aquí, la regla alcanza también
	# a hasBuildableCell() y con ella a la condición 3 del punto muerto, que es intencionado.
	# Si nadie ha inyectado la red —pruebas que montan escenarios sin cintas—,
	# canPlaceFactory() se comporta exactamente como antes de M1.
	if belt_network != null and belt_network.has_belt(cell):
		return false;
	# 6. La geografía: si el tipo declara `requires_adjacent`, al menos UNA de las 8 vecinas
	# tiene que ser de uno de esos tipos de casilla (Variedad M4). Hoy lo declara una sola
	# entrada —la WaterTreatment, con `["stream", "lake"]`—: la depuradora es restauración
	# INDUSTRIAL y está atada al agua del mapa, que es lo que la distingue del Reforester.
	#
	# Vive AQUÍ y no en el radial ni en _on_factory_chosen() porque ésta es la única respuesta
	# a «¿cabe aquí?»: repartirla entre los llamadores es exactamente el bug del apilado de
	# factorías que se arregló el 2026-09-17, donde dos sitios contestaban a la misma pregunta
	# y se contradecían.
	#
	# Y ojo a la geometría que sale de esto: `lake` y `toxic` son `buildable: false`, así que
	# la condición 3 ya impide construir SOBRE el agua — la depuradora va siempre AL LADO.
	# Sobre un `stream`, que sí es construible, tampoco cabe salvo que tenga otra casilla de
	# agua entre sus vecinas: una casilla no es vecina de sí misma.
	if not _hasRequiredAdjacent(cell, factory_type):
		return false;
	return true;

# ¿Tiene esta casilla al lado alguno de los tipos que `factory_type` exige? Sin exigencia
# declarada contesta que sí y no recorre nada, que es el caso de las ocho entradas de hoy y de
# todo el que llame sin el cuarto parámetro.
# Mira `getCellType()` y no el tile del suelo: lo que decide es el TIPO de la vecina, y una
# vecina fuera del mapa devuelve "" —que no está en ninguna lista— sin necesitar un guardia
# aparte.
func _hasRequiredAdjacent(cell, factory_type: String) -> bool:
	var required = requiredAdjacentTypes(factory_type);
	if required.is_empty():
		return true;
	for offset in ADJACENCY_OFFSETS:
		if required.has(getCellType(cell + offset)):
			return true;
	return false;

# ¿Cabe aquí ALGUNA factoría, sea de la clase que sea? Lo pregunta quien todavía no sabe qué
# se va a colocar: el click que abre el radial de construcción (Main._unhandled_input()).
# Desde M7 la respuesta depende del tipo, así que un click sobre casilla saturada que
# preguntara por la regla estricta no abriría nunca el menú — y el jugador no podría poner
# ahí el Reforester que la regla nueva le acaba de permitir.
# No duplica ni una condición: delega en canPlaceFactory() con la clase más permisiva, que
# sigue siendo el único punto de verdad.
func canPlaceAnyFactory(cell, factory_array) -> bool:
	return canPlaceFactory(cell, factory_array, RESTORATION_KIND);

# ¿Queda alguna casilla donde construir? Es la condición 3 del punto muerto
# (gameManager._evaluate_deadlock) y vive aquí por lo mismo que tick_contagion: el TileMap es
# quien sabe qué casillas existen. Preguntado desde fuera habría que recorrer un rango de
# coordenadas a ojo, y los límites del mapa salen del JSON y cambian con cada mapa.
# get_used_cells(0) es la misma verdad que la condición 1 de canPlaceFactory(): lo que tiene
# tile en la capa de suelo es el mapa, y nada más.
# Corta en la primera que valga, así que en una partida sana contesta en las primeras
# casillas; solo el mapa saturado —el que de verdad está muerto— paga el barrido entero.
#
# 🔴 PREGUNTA POR LA REGLA ESTRICTA, Y ESO NO SE MOVIÓ EN M7. La condición 3 del punto muerto
# es «no queda dónde construir», y desde M7 sobre un mapa saturado SIEMPRE quedaría dónde
# poner un Reforester: pasarle la clase permisiva haría la condición 3 inalcanzable, y con
# ella la derrota por punto muerto entera —el mapa abandonado dejaría de colapsar y con él se
# caería el criterio del que salió `contagion_rate`—. La regla nueva abre una salida al que
# LIMPIA; no deroga la derrota del que no hace nada.
func hasBuildableCell(factory_array) -> bool:
	for cell in get_used_cells(0):
		if canPlaceFactory(cell, factory_array):
			return true;
	return false;

func _update_hover():
	var mouse_pos = get_global_mouse_position();
	var local_pos = to_local(mouse_pos);
	var cell = local_to_map(local_pos);
	if cell != last_hovered_cell:
		erase_cell(1, last_hovered_cell);
		if get_cell_source_id(0, cell) != -1:
			set_cell(1, cell, 0, Vector2i(0, 0));
		last_hovered_cell = cell;

# Lo pinta el TintOverlay, no este nodo. El orden de las pasadas es el que se lee: el rojo
# de contaminación va DESPUÉS del color del tipo para leerse encima de él, el clima (M5) va
# encima de los dos porque es lo que está pasando AHORA en esa zona y caduca, y el colapso va
# el último porque es el único que habla del mapa entero y no de una casilla.
func draw_tints(target):
	for cell in _cell_colors:
		if _cell_sprite_sources.has(cell):
			continue;  # sprite tile: no overlay needed
		var c = _cell_colors[cell];
		_draw_diamond(target, cell, Color(c.r, c.g, c.b, 0.45));
	if pollution_manager:
		for cell in pollution_manager.pollution_per_cell:
			if get_cell_source_id(0, cell) == -1:
				continue;
			var level = pollution_manager.getCellPollution(cell);
			if level > 0.01:
				_draw_diamond(target, cell, Color(1.0, 0.15, 0.0, level * 0.5));
	_draw_weather(target);
	# Cuarta pasada: el punto muerto tiñe TODO el suelo, no solo lo sucio, porque lo que se
	# anuncia es que la run entera se acaba. Con la ventana cerrada la intensidad es 0 y no se
	# pinta nada: el corte en seco al romper la condición no necesita código propio, porque
	# _process() repinta este overlay cada frame y el frame siguiente ya sale sin la pasada.
	var collapse = collapseIntensity();
	if collapse > 0.0:
		var red = Color(COLLAPSE_COLOR.r, COLLAPSE_COLOR.g, COLLAPSE_COLOR.b,
			collapse * COLLAPSE_MAX_ALPHA);
		for cell in get_used_cells(0):
			_draw_diamond(target, cell, red);

# Grosor del contorno de una zona de clima, en píxeles. El contorno es lo que separa la zona
# de la contaminación de un vistazo: el rojo de contaminación va casilla a casilla y sin borde,
# y una zona de clima es UN rectángulo con su perímetro dibujado.
const WEATHER_BORDER_WIDTH = 3.0;
# Alpha del contorno: el color del catálogo casi opaco. El relleno usa el alpha del catálogo
# tal cual (0,30-0,40), que es el que decide su dueño en el JSON.
const WEATHER_BORDER_ALPHA = 0.95;
# Y debajo del contorno de color, uno oscuro más ancho, por lo mismo que el marcador de estado
# lleva borde: mirando las capturas, la sequía (ocre) sobre un suelo ya teñido de contaminación
# se leía casi del mismo color que el suelo, y su contorno naranja se perdía. Con el filo oscuro
# el perímetro se lee igual sobre verde que sobre rojo.
const WEATHER_UNDERLINE_WIDTH = 6.0;
const WEATHER_UNDERLINE_COLOR = Color(0.05, 0.05, 0.08, 0.55);

# Tercera pasada de draw_tints() (Clima M5): cada evento vivo tiñe su rectángulo con el color
# del catálogo y le dibuja el contorno. Solo las casillas con suelo: el rectángulo ya viene
# recortado contra el mapa, pero un mapa puede tener huecos. Suspendido (plan B 1, ventana de
# punto muerto abierta) no se pinta nada, igual que el manager no aplica nada: una zona tintada
# que no hace efecto mentiría. SOLO lee, como collapseIntensity(): se llama en cada dibujo.
func _draw_weather(target):
	if not is_instance_valid(weather_manager) or weather_manager.isSuspended():
		return;
	for ev in weather_manager.active:
		var cells = weatherCells(ev);
		if cells.is_empty():
			continue;
		var c = _weatherColor(ev.id);
		for cell in cells:
			_draw_diamond(target, cell, c);
		var border = Color(c.r, c.g, c.b, WEATHER_BORDER_ALPHA);
		var inside = {};
		for cell in cells:
			inside[cell] = true;
		# Dos vueltas y no una por lado: todo el filo oscuro primero y el color encima, o el filo
		# de un lado taparía la esquina del color del lado anterior.
		for layer in [[WEATHER_UNDERLINE_COLOR, WEATHER_UNDERLINE_WIDTH], [border, WEATHER_BORDER_WIDTH]]:
			for cell in cells:
				for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					if not inside.has(cell + step):
						_draw_diamond_edge(target, cell, cell + step, layer[0], layer[1]);

# Las casillas de suelo que cubre un evento. Pública porque es la que decide QUÉ se tiñe, y la
# suite la prueba sin tener que reconocer polígonos por su color.
func weatherCells(ev) -> Array:
	var cells = [];
	for y in range(ev.rect.position.y, ev.rect.end.y):
		for x in range(ev.rect.position.x, ev.rect.end.x):
			var cell = Vector2i(x, y);
			if get_cell_source_id(0, cell) != -1:
				cells.append(cell);
	return cells;

func _weatherColor(id) -> Color:
	var col = weather_manager.catalog.get(id, {}).get("color", [1.0, 1.0, 1.0, 0.3]);
	return Color(float(col[0]), float(col[1]), float(col[2]), float(col[3]));

# El lado del rombo de `cell` que da a `neighbor`: los dos vértices más cercanos al centro de
# la vecina. Se calcula así y no con una tabla de lados porque la tabla dependería del
# `tile_layout` del TileSet (hoy DIAMOND_DOWN); esto vale para cualquiera.
func _draw_diamond_edge(target, cell, neighbor, color, width):
	var center = map_to_local(cell);
	var towards = map_to_local(neighbor);
	var corners = [center + Vector2(0, -16.0), center + Vector2(32.0, 0),
		center + Vector2(0, 16.0), center + Vector2(-32.0, 0)];
	corners.sort_custom(func(a, b): return a.distance_squared_to(towards) < b.distance_squared_to(towards));
	target.draw_polyline(PackedVector2Array([corners[0], corners[1]]), color, width);

# Cuánto se ha agotado la gracia del punto muerto: 0 con la ventana cerrada (o sin
# gameManager), y de 0 a 1 según corre, lineal con run_time. SOLO lee, por lo mismo que
# gameManager._deadlockText(): se llama en cada dibujo, y mirar el mapa no puede mover la
# partida. `deadlock_timer` es el run_time en que se abrió la ventana, no una cuenta atrás
# —0.0 es «cerrada»—, así que lo corrido se calcula contra run_time.
func collapseIntensity() -> float:
	if game_manager == null or not is_instance_valid(game_manager):
		return 0.0;
	var opened_at = game_manager.deadlock_timer;
	if opened_at <= 0.0:
		return 0.0;
	return clamp((game_manager.run_time - opened_at) / game_manager.DEADLOCK_GRACE, 0.0, 1.0);

# target es el canvas item que dibuja: las llamadas draw_*() solo pintan sobre el nodo que
# las ejecuta, así que el diamante se calcula aquí y se dibuja allí.
func _draw_diamond(target, cell, color):
	var center = map_to_local(cell);
	var hw = 32.0;
	var hh = 16.0;
	var points = PackedVector2Array([
		center + Vector2(0, -hh),
		center + Vector2(hw, 0),
		center + Vector2(0, hh),
		center + Vector2(-hw, 0),
	]);
	target.draw_colored_polygon(points, color);

# Los cuatro colores del estado, uno por valor de `factoryData.blocked_reason`. Viven en el
# TileMap y no en factoryData porque son vocabulario de PANTALLA y no del modelo: la factoría
# sabe por qué está parada, y de qué color se lee eso lo decide quien lo pinta. Reutilizan el
# vocabulario que el mapa ya tiene puesto —naranja = te falta algo, rojo = el suelo—, así que
# el jugador no aprende una paleta nueva.
const STATUS_COLORS := {
	"workers": Color(0.95, 0.80, 0.20),  # amarillo: te falta gente
	"input":   Color(0.90, 0.35, 0.15),  # naranja: te falta material
	"output":  Color(0.55, 0.45, 0.85),  # violeta: no tiene por dónde salir
	"choke":   Color(0.85, 0.15, 0.10),  # rojo: el suelo la está matando
	# Azul grisáceo, el de la tormenta del catálogo (WeatherEvents.storm.color) pero opaco y más
	# claro: el marcador tiene que leerse sobre el tinte de la zona, que es ese mismo color al 40%.
	"storm":   Color(0.60, 0.70, 0.78),  # azul grisáceo: la para una tormenta — espera
}

# El marcador se mide en píxeles y no en fracción de casilla: la casilla isométrica es 64x32 y
# un icono proporcional a ella taparía la factoría que intenta describir.
const STATUS_MARKER_HW = 6.0;
const STATUS_MARKER_HH = 8.0;
const STATUS_MARKER_BORDER = 2.0;

# Lo pinta el StatusOverlay, no este nodo (ver la cabecera de la clase). `target` es el canvas
# item que dibuja, igual que en draw_tints(), y la lista entra por parámetro en vez de leerse
# del campo para que se pueda pintar contra una lista cualquiera sin inyectar nada en el nodo
# —es lo que hace la suite—.
# Solo sale lo que está PARADO: el mapa en silencio significa que todo va, y un icono sobre
# cada factoría sana sería el fracaso del hito aunque el código fuera correcto.
func draw_status(target, factory_array):
	# Sin lista no se pinta nada, y no es un caso raro: la suite monta este
	# TileMap a mano y no llaman nunca a setFactories().
	if factory_array == null:
		return;
	for fab in factory_array:
		# Se dibuja por frame, así que aquí dentro no cabe nada caro: ni find_child(), ni
		# get_tree(), ni una consulta al manager. Todo lo que hace falta ya está en el nodo.
		if fab == null or not is_instance_valid(fab):
			continue;
		# Contra "" y jamás contra el texto "null": str(null) devuelve "<null>" y esa
		# comparación es la que pintó «Produce: <null>» durante meses en ui/factoryTooltip.gd.
		var reason = fab.blocked_reason;
		if reason == "" or not STATUS_COLORS.has(reason):
			continue;
		_draw_status_marker(target, fab.cell_position, STATUS_COLORS[reason]);

# El marcador va en el VÉRTICE SUPERIOR del rombo y no es el rombo entero: el rombo ya lo usan
# el tinte del tipo de casilla y el rojo de la contaminación, y repintarlo en cuatro colores
# más dejaría el mapa ilegible justo cuando más lleno está. Va OPACO —el tinte va al 45%—
# porque lo que tiene que funcionar es distinguir los cuatro colores de un vistazo y sin
# hover, y en dos pasadas porque el mismo marcador tiene que leerse sobre suelo claro y sobre
# una casilla teñida de rojo: el borde oscuro es lo que se lo garantiza.
func _draw_status_marker(target, cell, color):
	# 16.0 es la media altura del rombo, la misma de _draw_diamond(): el vértice de arriba.
	var top = map_to_local(cell) + Vector2(0, -16.0);
	_draw_marker_polygon(target, top, STATUS_MARKER_HW + STATUS_MARKER_BORDER,
		STATUS_MARKER_HH + STATUS_MARKER_BORDER, Color(0.05, 0.05, 0.08, 0.9));
	_draw_marker_polygon(target, top, STATUS_MARKER_HW, STATUS_MARKER_HH, color);

# Un rombo vertical (más alto que ancho) para que no se confunda con el rombo de la casilla,
# que es justo al revés. Mismo reparto que _draw_diamond(): se calcula aquí y se dibuja allí.
func _draw_marker_polygon(target, center, hw, hh, color):
	target.draw_colored_polygon(PackedVector2Array([
		center + Vector2(0, -hh),
		center + Vector2(hw, 0),
		center + Vector2(0, hh),
		center + Vector2(-hw, 0),
	]), color);

func isCellBlocked(cell):
	if pollution_manager == null:
		return false;
	return pollution_manager.getCellPollution(cell) >= 1.0;

func setPollutionManager(pm):
	pollution_manager = pm;

# La inyecta Main._start_game(), igual que el pollutionManager y por lo mismo: canPlaceFactory()
# la llaman desde media docena de sitios que no conocen la red, y la regla tiene que vivir en el
# único punto de verdad y no repartida por los llamadores.
func setBeltNetwork(bn):
	belt_network = bn;

# El tercer setter de inyección, hermano de los dos de arriba y por lo mismo: el StatusOverlay
# dibuja por frame y necesita la lista de factorías a mano, sin salir a buscarla al árbol
# —un find_child() dentro de un bucle por frame es exactamente lo que un dibujo no puede
# permitirse—.
# 🔴 El array va VIVO y NO una copia, igual que en beltNetwork.set_factories(),
# gameManager.setFactories() y factoryPlacer.initialize(): `placer` lo muta al construir y
# Main._demolish_at_cell() al demoler, así que una copia pintaría el estado de hace un rato y
# dejaría el icono de una factoría ya demolida flotando sobre una casilla vacía.
# El default [] es para quien no llama aquí —la suite monta el TileMap a
# mano y no tienen por qué enterarse de que existe un overlay de estado—.
func setFactories(factory_array):
	_factory_array = factory_array if factory_array != null else [];

# El cuarto setter, y el único al revés del resto: el gameManager ya recibe este TileMap por
# gameManager.setTileMap() para evaluar el punto muerto, y el tinte de colapso necesita leer
# esa misma ventana. Se inyecta en vez de buscarlo en el árbol por lo mismo que setFactories():
# se lee en cada dibujo. Sin llamarlo —la suite monta TileMaps sueltos— la tercera pasada de
# draw_tints() no pinta nada.
func setGameManager(gm):
	game_manager = gm;

# El quinto setter, hermano de los de arriba: la pasada de lluvia de tick_passive() corre cada
# frame y no puede salir a buscar el manager al árbol. Lo inyecta Main._start_game() después
# de crearlo. Sin llamarlo —la suite monta TileMaps sueltos— la lluvia no existe y
# tick_passive() hace exactamente lo de antes. Se mira con is_instance_valid(): Main.reset()
# lo suelta y un nodo liberado se compara igual que null.
func setWeatherManager(wm):
	weather_manager = wm;
