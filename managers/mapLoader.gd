extends Node

# El tipo de factoría que hace de almacén. Vive en el JSON como una factoría más
# (`type: "storage"`), así que aquí solo hace falta su nombre para pedírsela a factoryPlacer.
const STORAGE_FACTORY = "Storage";

# Aplica los datos de un paquete de inicio al estado del juego.
# Debe llamarse tras inicializar Player y Bag.
func apply_package(package_id, file_data, player_node, bag_node):
	var packages = file_data.get("StartingPackages", {});
	if not packages.has(package_id):
		return;
	var pkg = packages[package_id];

	# Factories disponibles
	var factories = pkg.get("factories", []);
	player_node.availableFactories = factories.duplicate();

	# Stock de salida (Costes M2). Desde que construir cuesta material, un paquete sin bolsa es
	# una run que nace sin poder colocar nada: el checkpoint 1 se cobra sus 15 de madera en el
	# primer frame y el 2 aparta 5 más, así que el número que el jugador llega a gastar es el
	# stock MENOS 20. Los 40/50/36 son PROVISIONALES: salieron de mediciones
	# defectuosas (retiradas el 2026-09-23) y se suponen incorrectos hasta volver a medirlos.
	# Va en el JSON y no aquí, como las factorías y los boosts, y es OPCIONAL: su ausencia
	# significa bolsa vacía, el mismo contrato que `cost` y que `materials`.
	# 🔴 addToBag() SUMA, igual que las otras tres cosas que reparte esta función: llamar dos
	# veces a apply_package() duplica el stock. Se aplica una sola vez, en Main._start_game(),
	# y después de Bag.initialize() —que solo crea las claves— pero nunca después de un
	# Bag.reset(), que las pone a 0 y se lo llevaría por delante sin dejar rastro.
	var starting_stock = pkg.get("starting_stock", {});
	for material in starting_stock:
		var quantity = int(starting_stock[material]);
		if quantity > 0:
			bag_node.addToBag(material, quantity);

	# Workers extra
	var extra_workers = int(pkg.get("extra_workers", 0));
	if extra_workers > 0:
		bag_node.addWorkers(extra_workers);

	# Speed boosts del paquete
	var boosts = pkg.get("speed_boosts", []);
	for boost in boosts:
		var target = boost["target"];
		var amount = int(boost["amount"]);
		player_node.applySpeedBoost(target, amount);

# Devuelve el mapa a cargar en esta run (selección aleatoria entre los desbloqueados).
func pick_map(file_data, save_manager) -> Dictionary:
	var maps = file_data.get("Maps", []);
	var available = [];
	for m in maps:
		var unlock_id = m.get("unlock_id", null);
		if unlock_id == null or save_manager.is_map_unlocked(m["id"]):
			available.append(m);
	if available.is_empty():
		return maps[0] if maps.size() > 0 else {};
	available.shuffle();
	return available[0];

# Aplica el estado inicial del mapa: genera los tiles, marca celdas bloqueadas, reparte la
# contaminación de partida y coloca el almacén con el que el mapa arranca.
# tile_map debe ser el nodo TileMap ya añadido al árbol.
#
# `storage_ctx` (opcional) es lo único que apply_map() no puede sacar de sus otros argumentos
# y necesita para CONSTRUIR ese almacén. Viaja junto porque son las cinco piezas de una misma
# llamada a factoryPlacer.build(), no cinco decisiones independientes:
#   { "placer":    el factoryPlacer ya inicializado,
#     "parent":    el nodo al que se cuelga la factoría (Main),
#     "player":    el Player (de él salen los speed boosts del paquete),
#     "bag":       la Bag (de ella salen los workers, aunque el almacén no pida ninguno),
#     "factories": el array VIVO de factorías, el mismo que comparten placer y beltNetwork,
#     "on_produced": (opcional, M5) el Callable al que conectar `resource_produced` del
#                    almacén, que desde M5 emite a las cintas }
# Sin él —las pruebas que solo quieren el terreno— apply_map() se comporta
# exactamente como antes de M3.
func apply_map(map_data, pollution_manager, tile_map = null, file_data = null, storage_ctx = null):
	var size = map_data.get("size", [16, 10]);
	var blocked = map_data.get("blocked_cells", []);
	# Generar tiles
	if tile_map != null:
		var special_cells = map_data.get("special_cells", []);
		var type_data = file_data.get("TileTypes", {}) if file_data else {};
		tile_map.generate(size, blocked, special_cells, type_data);
	# Contaminación de partida: se reparte sobre las casillas del mapa, no sobre el aire.
	# removePollution() solo descuenta del global lo que quita de una celda, así que una
	# contaminación sin casilla sería suciedad que ningún Reforester puede alcanzar: el
	# mapa se volvería imposible de restaurar (en wasteland_01 eran 20 puntos eternos).
	# Y se concentra en los FOCOS —las casillas degradadas—, no en todo el suelo: una capa
	# fina sobre 154 casillas obliga a barrer tres cuartos del mapa y no se lee como nada;
	# concentrada, el páramo se lee como lo que es, zonas sucias que atender.
	var start_pollution = float(map_data.get("pollution_start", 0.0));
	if start_pollution > 0.0:
		var cells = _degraded_cells(map_data, tile_map, file_data);
		if cells.is_empty():
			# Un mapa que ensucia de salida pero no declara focos: se reparte sobre el suelo,
			# que es lo que hacía M0.5. Mejor difuso que inalcanzable.
			cells = _pollutable_cells(map_data, tile_map);
		if cells.is_empty():
			# Sin tilemap no hay casillas donde repartir: se conserva el camino global.
			pollution_manager.addPollution(start_pollution, null);
		else:
			var share = start_pollution / float(cells.size());
			for cell in cells:
				pollution_manager.addPollution(share, cell);
	# El almacén va AL FINAL: necesita el suelo ya generado para que canPlaceFactory() tenga
	# qué contestar, y la contaminación ya repartida para que una storage_cell sembrada de
	# suciedad no pase el filtro en silencio.
	place_storage(map_data, tile_map, file_data, storage_ctx);

# Focos del mapa: las casillas especiales cuyo tipo está marcado `degraded: true` en
# TileTypes (burned, swamp, toxic, lava). Qué tipos son focos se decide en el JSON y no
# aquí, como todo lo demás de las casillas.
# Se exige además que la casilla exista en el suelo, por el mismo motivo que
# _pollutable_cells(): generate() borra el tile de las no construibles sin sprite —hoy
# `toxic`—, y sembrar suciedad ahí es contaminación que no se tinta. La `toxic` de
# wasteland_01 queda por tanto fuera del reparto: ya se ensucia sola, +0.5/s eternos.
func _degraded_cells(map_data, tile_map, file_data) -> Array:
	var cells = [];
	if tile_map == null or file_data == null:
		return cells;
	var type_data = file_data.get("TileTypes", {});
	for sc in map_data.get("special_cells", []):
		var ttype = sc.get("type", "");
		if not type_data.get(ttype, {}).get("degraded", false):
			continue;
		var cell = Vector2i(int(sc["pos"][0]), int(sc["pos"][1]));
		if tile_map.get_cell_source_id(0, cell) != -1:
			cells.append(cell);
	return cells;

# Casillas sobre las que se reparte la contaminación de partida cuando el mapa no declara
# focos: las que existen de verdad en el suelo tras generate(). Quedan fuera las de
# blocked_cells y las no construibles sin sprite (`toxic`), a las que generate() les borra
# el tile: poner suciedad ahí sería volver a inventar contaminación que no se puede tintar
# ni, en el caso de toxic, desbloquear.
func _pollutable_cells(map_data, tile_map) -> Array:
	var cells = [];
	if tile_map == null:
		return cells;
	var size = map_data.get("size", [16, 10]);
	for y in range(int(size[1])):
		for x in range(int(size[0])):
			var cell = Vector2i(x, y);
			if tile_map.get_cell_source_id(0, cell) != -1:
				cells.append(cell);
	return cells;

# Coloca el almacén con el que la run empieza: la celda la dice `storage_cell` de la entrada
# del mapa en `Maps[]`, como todo lo demás del mapa, y no este script.
#
# POR QUÉ ESAS DOS CELDAS — se eligieron leyendo las `special_cells` curadas de cada mapa, no
# a ojo:
#   · forest_01   (13,8) — libre de las 7 especiales —(2,2) y (3,2) forest, (5,4) fertile,
#     (9,1) stream, (12,6) ruins, (14,3) y (14,4) lake—, lejos de la esquina noroeste donde
#     se tiende la cadena, y con sus cuatro vecinas ortogonales vacías: al almacén hay que
#     poder tenderle cinta, que es lo que decide dónde va y no estar pegado al sitio obvio de
#     construir (no hay entrega por adyacencia, decidido el 2026-09-18).
#   · wasteland_01 (13,8) — libre de las 10 especiales y de las 5 `blocked_cells`; en
#     particular NO cae sobre la ruina de (15,8), que da una mejora gratis al construir encima
#     y se consumiría sin que el jugador la eligiera, ni sobre los pantanos de (13,5)/(14,5),
#     que son focos de la contaminación de partida y multiplican lo que se construye encima.
#
# Devuelve el nodo del almacén, o null si el mapa no declara `storage_cell`, si falta el
# contexto de construcción o si la celda no admite factoría: no se fuerza nada, se avisa.
func place_storage(map_data, tile_map, file_data, storage_ctx):
	if tile_map == null or file_data == null or storage_ctx == null or storage_ctx.is_empty():
		return null;
	var raw = map_data.get("storage_cell", null);
	if raw == null:
		return null;
	if not file_data.get("Factories", {}).has(STORAGE_FACTORY):
		return null;
	var placer = storage_ctx.get("placer", null);
	var parent_node = storage_ctx.get("parent", null);
	var player_node = storage_ctx.get("player", null);
	var bag_node = storage_ctx.get("bag", null);
	var factories = storage_ctx.get("factories", []);
	if placer == null or parent_node == null or player_node == null or bag_node == null:
		return null;
	var cell = Vector2i(int(raw[0]), int(raw[1]));
	# canPlaceFactory() es el único punto de verdad de «¿cabe aquí?», y lo es también para el
	# almacén que el mapa trae puesto. Si la celda curada dejara de admitir factoría —porque
	# alguien la mueva sobre un lago, sobre una `blocked_cell` o sobre una casilla que la
	# contaminación de partida cierra— la run arranca sin almacén y se ve, en vez de colarse
	# una factoría en una casilla que el resto del juego considera imposible.
	# La categoría va desde Costes M7, y para el almacén no cambia nada: `storage` no es
	# restauración, así que sigue pidiendo la casilla entera —tile, sin saturar, construible,
	# libre y sin cinta—. Se pasa igualmente en vez de dejar el default porque el default es
	# «la regla estricta» y no «la de esta factoría», y un mapa que algún día colocara de
	# salida algo que no fuera un almacén heredaría la respuesta equivocada en silencio.
	var kind = str(file_data["Factories"][STORAGE_FACTORY].get("type", "production"));
	if not tile_map.canPlaceFactory(cell, factories, kind):
		push_warning("mapLoader: storage_cell %s no admite factoría en el mapa '%s'" % [
			str(cell), str(map_data.get("id", "?"))]);
		return null;
	# Sin `charge_cost`: el `Storage` tiene precio desde Costes M1, pero el PRIMERO viene
	# puesto con el mapa y no se cobra. Pasar `true` aquí le pasaría al jugador la factura de
	# un almacén que no ha decidido colocar —y con la bolsa del paquete inicial, en el primer
	# frame de la run—.
	var storage = placer.build(STORAGE_FACTORY, cell, player_node, bag_node, tile_map);
	parent_node.add_child(storage);
	# register_and_evaluate() lo mete en el array vivo de factorías —de donde lo saca el
	# `_factory_index` de beltNetwork para resolver el final de un camino— y evalúa sus
	# sinergias, que en el almacén son ninguna (`synergies: {}`).
	placer.register_and_evaluate(storage, cell);
	# Desde M5 el almacén SÍ emite —saca de la bolsa el material que el jugador elija en el
	# panel y lo mete en la cinta—, así que su `resource_produced` tiene que llegar al mismo
	# encaminador que el del resto (Main._on_resource_produced). El callable llega por el
	# contexto y no se nombra a Main aquí: mapLoader no conoce a su padre. Se bindea el nodo,
	# igual que Main._on_factory_chosen(), porque deliver() necesita la CELDA de origen y la
	# señal solo lleva la posición de mundo.
	var on_produced = storage_ctx.get("on_produced", null);
	if on_produced is Callable and on_produced.is_valid():
		storage.resource_produced.connect(on_produced.bind(storage));
	return storage;
