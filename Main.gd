extends Node

var factoryArray = [];
var file = "resources/factoryParams.json";
var fileData;
var gameManager;
var pollutionManager;
var saveManager;
var mapLoader;
var placer;
var _hovered_factory = null;

@export var factory: PackedScene
@export var player: PackedScene
@export var grid: PackedScene

func _ready():
	saveManager = load("res://managers/saveManager.gd").new();
	saveManager.name = "SaveManager";
	add_child(saveManager);

	mapLoader = load("res://managers/mapLoader.gd").new();

	var json_as_text = FileAccess.get_file_as_string(file);
	fileData = JSON.parse_string(json_as_text);

	var menu = load("res://ui/mainMenu.gd").new();
	menu.name = "MainMenu";
	add_child(menu);
	menu.initialize(saveManager);
	menu.play_pressed.connect(_show_package_select);

func _show_package_select():
	var screen = load("res://ui/packageSelect.gd").new();
	screen.name = "PackageSelect";
	add_child(screen);
	screen.initialize(fileData, saveManager);
	screen.package_chosen.connect(_start_game);

func _start_game(package_id = "standard"):
	var playerNode = player.instantiate();
	add_child(playerNode);
	var playGrid = grid.instantiate();
	add_child(playGrid);
	get_node("Player").get_node("Bag").initialize(fileData);

	# Aplicar paquete de inicio
	mapLoader.apply_package(package_id, fileData, get_node("Player"), get_node("Player").get_node("Bag"));

	pollutionManager = load("res://managers/pollutionManager.gd").new();
	pollutionManager.name = "PollutionManager";
	add_child(pollutionManager);
	get_node("TileMap").setPollutionManager(pollutionManager);

	# Aplicar mapa de la run
	var map_data = mapLoader.pick_map(fileData, saveManager);
	mapLoader.apply_map(map_data, pollutionManager, get_node("TileMap"), fileData);

	# FactoryPlacer — lógica de colocación desacoplada de Main
	placer = load("res://entities/factory/factoryPlacer.gd").new();
	placer.initialize(factory, fileData, factoryArray);

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
	# el playGrid ya instanciado al principio de _start_game().
	gameManager.setTileMap(get_node("TileMap"));
	gameManager.checkpoint_reached.connect(_on_checkpoint_reached);
	gameManager.run_won.connect(_on_run_won);
	gameManager.run_lost.connect(_on_run_lost);

func _initiateInventory(_playerNode):
	pass;

func _process(delta):
	if not fileData or not gameManager:
		return;
	var player_node = get_node_or_null("Player");
	if not player_node:
		return;
	var bag = player_node.get_node("Bag");
	get_node("Label").text = _buildResourceText(bag);
	gameManager.update(bag, pollutionManager);
	get_node("Objective").text = gameManager.getObjectiveText(bag, pollutionManager);
	var tile_map_node = get_node_or_null("TileMap");
	if tile_map_node and pollutionManager:
		_tick_world(tile_map_node, delta);
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

func _buildResourceText(bag):
	var text = "";
	for resource in bag.bag:
		text += resource + ": " + str(bag.getQuantity(resource)) + "\n";
	var free_workers = bag.getFreeWorkers();
	var total_workers = bag.workers_total;
	text += "Workers: " + str(free_workers) + "/" + str(total_workers) + " libres\n";
	return text;

func _unhandled_input(event):
	if event is InputEventKey and event.pressed and event.keycode == KEY_R:
		reset();
		return;
	var tile_map = get_node_or_null("TileMap");
	if not tile_map or not gameManager:
		return;
	var mouse_pos = tile_map.get_local_mouse_position();
	var cell = tile_map.local_to_map(mouse_pos);
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if not gameManager.active:
				return;
			# Reglas de colocación: tile, contaminación, tipo de casilla y ocupación
			if not tile_map.canPlaceFactory(cell, factoryArray):
				return;
			_show_radial_menu(cell);
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_demolish_at_cell(cell);

func _demolish_at_cell(cell):
	var fab = _get_factory_at_cell(cell);
	if fab == null:
		return;
	# Devolver workers a la bolsa
	var bag = get_node_or_null("Player/Bag");
	if bag and fab.workers_assigned > 0:
		bag.unassignWorkers(fab.workers_assigned);
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
	fab.queue_free();

func _show_radial_menu(cell):
	var existing = get_node_or_null("RadialMenu");
	if existing:
		existing.queue_free();
	var screen_pos = get_viewport().get_mouse_position();
	var radial = load("res://ui/radialMenu.gd").new();
	radial.name = "RadialMenu";
	add_child(radial);
	# Las sinergias que daría construir en esta casilla, consultadas sin aplicar nada: pegar la
	# línea o desparramarla es la decisión más cara del juego (un factor 5 en la run entera,
	# medido) y hasta hoy solo se veía después de haber construido.
	var preview = {};
	if placer:
		var tile_map = get_node_or_null("TileMap");
		for tipo in get_node("Player").availableFactories:
			preview[tipo] = placer.preview_synergies(tipo, cell, tile_map);
	radial.initialize(get_node("Player").availableFactories, fileData, cell, screen_pos, preview);
	radial.factory_chosen.connect(_on_factory_chosen);

func _on_factory_chosen(factory_type, cell):
	var bag = get_node("Player").get_node("Bag");
	var tile_map = get_node("TileMap");
	# Se revalidan las reglas de colocación: entre abrir el radial y elegir factoría
	# la celda pudo ensuciarse u ocuparse
	if not tile_map.canPlaceFactory(cell, factoryArray):
		return;
	var fabrica = placer.build(factory_type, cell, get_node("Player"), bag, tile_map);
	add_child(fabrica);
	placer.register_and_evaluate(fabrica, cell);
	fabrica.resource_produced.connect(_on_resource_produced);
	# Efectos on_build del tile
	var tdef = tile_map.getCellTypeDef(cell);
	if not tdef.is_empty():
		# Tierra quemada: contamina la celda al construir
		if tdef.has("on_build_pollution"):
			pollutionManager.addPollution(float(tdef["on_build_pollution"]), cell);
		# Ruinas: ofrecer mejora gratuita
		if tdef.has("on_build_reward") and tdef["on_build_reward"].get("upgrades", 0) > 0:
			tile_map.cell_types.erase(cell); # consumir la ruina
			_on_checkpoint_reached(gameManager._pick_upgrades(1), {});

func _on_resource_produced(material, amount, world_pos):
	if material == null:
		return;
	# Factory token: muestra pantalla de desbloqueo de factory
	if material == "factory_token":
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

func _show_factory_token_screen():
	var existing = get_node_or_null("TokenUnlock");
	if existing:
		return;
	# Construye lista de factories no disponibles (candidatas a desbloquear)
	var playerNode = get_node("Player");
	var all_factories = fileData["Factories"].keys();
	var candidates = [];
	for f in all_factories:
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
	screen.initialize(synthetic_catalog.keys().slice(0, 3), synthetic_catalog);
	screen.upgrade_chosen.connect(_on_token_unlock_chosen);

func _on_token_unlock_chosen(upgrade_id):
	get_tree().paused = false;
	var parts = upgrade_id.split("token_unlock_");
	if parts.size() >= 2:
		var factory_name = parts[1];
		var playerNode = get_node("Player");
		if not playerNode.availableFactories.has(factory_name):
			playerNode.availableFactories.append(factory_name);
	# Consume el token de la Bag
	get_node("Player").get_node("Bag").removeFromBag("factory_token", 1);

func _show_factory_tooltip(factory_node):
	_hide_factory_tooltip();
	var tooltip = load("res://ui/factoryTooltip.gd").new();
	tooltip.name = "FactoryTooltip";
	add_child(tooltip);
	tooltip.initialize(factory_node, fileData);
	tooltip.show_at(get_viewport().get_mouse_position());

func _hide_factory_tooltip():
	var tooltip = get_node_or_null("FactoryTooltip");
	if tooltip:
		tooltip.free();

func _update_hover_tooltip():
	var tile_map = get_node_or_null("TileMap");
	if not tile_map:
		_clear_hover();
		return;
	var cell = tile_map.local_to_map(tile_map.get_local_mouse_position());
	var factory_under_cursor = _get_factory_at_cell(cell);
	if factory_under_cursor != _hovered_factory:
		_hovered_factory = factory_under_cursor;
		_hide_factory_tooltip();
		if _hovered_factory != null:
			_show_factory_tooltip(_hovered_factory);
	elif _hovered_factory != null:
		var tooltip = get_node_or_null("FactoryTooltip");
		if tooltip:
			tooltip.update_position(get_viewport().get_mouse_position());

func _clear_hover():
	if _hovered_factory != null:
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
	_hide_factory_tooltip();
	_hovered_factory = null;

# `granted_upgrade_ids` tiene valor por defecto porque la mejora gratis de las ruinas llama
# aquí a mano, con dos argumentos, y ahí no se concede nada: lo que las ruinas dan ya es una
# carta regalada.
func _on_checkpoint_reached(offered_upgrade_ids, rewards, granted_upgrade_ids = []):
	_close_menus();
	var bag = get_node("Player").get_node("Bag");
	if rewards.get("workers", 0) > 0:
		bag.addWorkers(int(rewards["workers"]));
	# Las concedidas se aplican ANTES de montar la pantalla: la garantía no puede depender de
	# que el jugador pulse nada, que es justo lo que fallaba cuando se ofrecían entre las tres.
	_apply_granted_upgrades(granted_upgrade_ids);
	get_tree().paused = true;
	var screen = load("res://ui/upgradeScreen.gd").new();
	screen.name = "UpgradeScreen";
	add_child(screen);
	screen.initialize(offered_upgrade_ids, fileData["Upgrades"], granted_upgrade_ids);
	screen.upgrade_chosen.connect(_on_upgrade_chosen);

# Las mejoras que la run recibe sin elegirlas. Vive aparte de _on_checkpoint_reached() para
# que se le pueda dar la lista sin montar la escena entera: lo que hay que poder afirmar es
# que se aplican pase lo que pase en la pantalla, no que la pantalla se dibuje.
func _apply_granted_upgrades(granted_upgrade_ids):
	for id in granted_upgrade_ids:
		_apply_upgrade(id);

func _on_upgrade_chosen(upgrade_id):
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

# Espejo de _on_run_won(), con una asimetría deliberada: perder NO registra progresión. Ver
# _close_lost_run() — lo único que se queda aquí es pausar, que es lo que necesita el árbol.
func _on_run_lost(stats):
	get_tree().paused = true;
	_close_lost_run(stats);

# El cierre de una run perdida, sin el árbol de por medio: vive aparte por lo mismo que
# _apply_granted_upgrades(), para poder afirmar que perder no toca user://save.json sin tener
# que montar la escena entera. Lo que hay que poder demostrar es la asimetría, no que la
# pantalla se dibuje.
func _close_lost_run(stats):
	_close_menus();
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

func reset():
	get_tree().paused = false;
	for node_name in ["UpgradeScreen", "RunSummary", "TokenUnlock", "Player", "TileMap", "GameManager", "PollutionManager"]:
		var node = get_node_or_null(node_name);
		if node:
			node.queue_free();
	for fabrica in factoryArray:
		fabrica.queue_free();
	factoryArray.clear();
	pollutionManager = null;
	gameManager = null;
	placer = null;
	_hovered_factory = null;
	_hide_factory_tooltip();
	_show_package_select();
