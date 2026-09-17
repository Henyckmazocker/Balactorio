extends TileMap

var last_hovered_cell: Vector2i = Vector2i(-1, -1);
var pollution_manager = null;
var cell_types = {};      # Vector2i -> String (tile type id)
var tile_type_data = {};  # String -> dict (from JSON TileTypes)
var _cell_sprite_sources = {};  # Vector2i -> int  (cells using a custom sprite source_id)
var _cell_colors = {};    # Vector2i -> Color
var _tint_overlay = null; # canvas item propio para el tinte; ver TintOverlay

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
	if _tint_overlay != null and is_instance_valid(_tint_overlay):
		return;
	_tint_overlay = TintOverlay.new();
	_tint_overlay.name = "TintOverlay";
	_tint_overlay.tile_map = self;
	# z_index 1 = la misma altura que la capa 2 (sprites de montaña/lago/lava). No compiten:
	# una casilla con sprite no lleva tinte.
	_tint_overlay.z_index = 1;
	add_child(_tint_overlay);

# Sustituye al queue_redraw() de este nodo: el color ya no lo pinta el TileMap, así que
# repintarlo a él no dibujaría nada. Lo llama todo lo que cambia un tinte.
func _redraw_tints():
	if _tint_overlay != null and is_instance_valid(_tint_overlay):
		_tint_overlay.queue_redraw();

func _process(_delta):
	_update_hover();
	_redraw_tints();

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
	for cell in sources:
		pollution_manager_ref.spreadFrom(cell, amount, is_valid);

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

# Único punto de verdad de "¿cabe una factoría aquí?": agrupa las cuatro condiciones.
# factory_array es el array de factorías vivas que Main comparte por referencia con
# factoryPlacer; se recorre aquí para no depender de ningún otro nodo.
func canPlaceFactory(cell, factory_array) -> bool:
	# 1. El tile existe en la capa de suelo
	if get_cell_source_id(0, cell) == -1:
		return false;
	# 2. No está bloqueada por contaminación
	if isCellBlocked(cell):
		return false;
	# 3. El tipo de casilla admite construcción (toxic bloqueado hasta restaurar)
	if not isBuildable(cell):
		return false;
	# 4. La celda está libre: una factoría por casilla
	for fab in factory_array:
		if fab.cell_position == cell:
			return false;
	return true;

# ¿Queda alguna casilla donde construir? Es la condición 3 del punto muerto
# (gameManager._evaluate_deadlock) y vive aquí por lo mismo que tick_contagion: el TileMap es
# quien sabe qué casillas existen. Preguntado desde fuera habría que recorrer un rango de
# coordenadas a ojo, y los límites del mapa salen del JSON y cambian con cada mapa.
# get_used_cells(0) es la misma verdad que la condición 1 de canPlaceFactory(): lo que tiene
# tile en la capa de suelo es el mapa, y nada más.
# Corta en la primera que valga, así que en una partida sana contesta en las primeras
# casillas; solo el mapa saturado —el que de verdad está muerto— paga el barrido entero.
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

# Lo pinta el TintOverlay, no este nodo. El orden de las dos pasadas es el que se lee: el
# rojo de contaminación va DESPUÉS del color del tipo para leerse encima de él.
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

func isCellBlocked(cell):
	if pollution_manager == null:
		return false;
	return pollution_manager.getCellPollution(cell) >= 1.0;

func setPollutionManager(pm):
	pollution_manager = pm;
