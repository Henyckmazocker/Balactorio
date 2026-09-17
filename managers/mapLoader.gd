extends Node

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

# Aplica el estado inicial del mapa: genera los tiles y marca celdas bloqueadas.
# tile_map debe ser el nodo TileMap ya añadido al árbol.
func apply_map(map_data, pollution_manager, tile_map = null, file_data = null):
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
