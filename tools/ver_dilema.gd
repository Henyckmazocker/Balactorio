extends SceneTree

# Verificación VISUAL del dilema del catálogo de mejoras — la que el Plan «Catálogo de Mejoras»
# llama «la que de verdad importa, jugada»: los dos mapas finales tienen que VERSE distintos.
#
# No es una prueba: no mide nada y no va en la suite. Arranca el juego CON render,
# aplica el castigo de las dos políticas por el camino real del juego —`_on_checkpoint_reached()`
# → `upgradeScreen` → `_on_upgrade_chosen()` → `_apply_upgrade()` → `_apply_map_downside()`— y
# guarda capturas para mirarlas con los ojos.
#
#   godot-4 --path . --script res://tools/ver_dilema.gd
#
# Las capturas salen en `res://capturas/`. El snap de Godot no puede escribir en /tmp, así que
# viven dentro del proyecto y se sacan de ahí al terminar.

const MAPA = "forest_01";
const PAQUETE = "standard";
const SEMILLA = 20260920;

# Las tres cartas de tier 2 que se le enseñan al jugador en la captura de la pantalla, con su
# castigo graduado 1/2/3 del M1. La cuarta (`speed_woodprocessing_ii`, 1 casilla) se queda fuera
# porque la pantalla ofrece TRES, que es justo el aprieto que este plan viene a arreglar.
const OFRECIDAS = ["extra_wood", "extra_plank", "extra_reforest"];

# La política extrema de cada lado: `agresivo` coge
# siempre la carta más castigada (3 casillas) y `prudente` la menos (1).
const CARTA_AGRESIVA = "extra_wood";
const CARTA_PRUDENTE = "extra_reforest";

# Cuántos checkpoints de tier 2 se simulan. La run tiene cinco, pero los primeros reparten tier 1;
# tres es lo que una run entera suele ofrecer de tier 2.
const VECES = 3;

var _hecho = false;

func _process(_delta):
	if _hecho:
		return false;
	_hecho = true;
	_todo();
	return false;

func _todo():
	seed(SEMILLA);
	DirAccess.make_dir_recursive_absolute("res://capturas");

	# 1. La pantalla de mejora, tal como la lee el jugador: las tres cartas con su «⚠ Degrada N
	#    casillas», que `ui/upgradeScreen.gd:_downside_text()` redacta del mismo `map_downside`
	#    del que cobra `Main._apply_map_downside()`.
	var main = await _montar();
	main._on_checkpoint_reached(OFRECIDAS, {}, []);
	await _capturar("res://capturas/1_pantalla_mejoras.png");
	var pantalla = main.get_node_or_null("UpgradeScreen");
	if pantalla:
		pantalla.queue_free();
	paused = false;
	await _esperar(5);

	# 2. El mapa de partida, para tener con qué comparar.
	await _capturar_mapa(main, "res://capturas/2_mapa_inicial.png");
	_soltar(main);

	# 3. El mapa del jugador PRUDENTE: tres cartas de 1 casilla.
	main = await _montar();
	var t_prudente = await _aplicar(main, CARTA_PRUDENTE);
	await _capturar_mapa(main, "res://capturas/3_mapa_prudente.png");
	_soltar(main);

	# 4. El mapa del jugador AGRESIVO: tres cartas de 3 casillas.
	main = await _montar();
	var t_agresivo = await _aplicar(main, CARTA_AGRESIVA);
	await _capturar_mapa(main, "res://capturas/4_mapa_agresivo.png");
	_soltar(main);

	print("");
	print("=== Dilema del catálogo — casillas `toxic` en el mapa tras %d checkpoints ===" % VECES);
	print("  prudente (%s, 1 casilla por carta) : %d toxic" % [CARTA_PRUDENTE, t_prudente]);
	print("  agresivo (%s, 3 casillas por carta): %d toxic" % [CARTA_AGRESIVA, t_agresivo]);
	print("  capturas en res://capturas/");
	quit();

# Aplica la misma carta `veces` veces por el camino real del juego y devuelve cuántas casillas
# `toxic` quedan en el mapa. Se pasa por `_on_upgrade_chosen()` y no por `_apply_map_downside()`
# a pelo: lo que se quiere ver es lo que le pasa al jugador cuando pulsa «Elegir».
func _aplicar(main, carta) -> int:
	for i in VECES:
		main._on_checkpoint_reached(OFRECIDAS, {}, []);
		await _esperar(2);
		var pantalla = _pantalla(main);
		if pantalla:
			pantalla._on_upgrade_chosen(carta);
			# `_on_upgrade_chosen()` hace `queue_free()`, que es DIFERIDO: si no se saca del
			# árbol ahora, la pantalla del checkpoint siguiente entra renombrada
			# (`@UpgradeScreen@2`) y se apilan una encima de otra — la trampa que el
			# `CLAUDE.md` del repo documenta para el tooltip.
			if pantalla.get_parent() == main:
				main.remove_child(pantalla);
		await _esperar(3);
	paused = false;
	await _esperar(10);
	return _contar_toxic(main);

func _contar_toxic(main) -> int:
	var tile_map = main.get_node_or_null("TileMap");
	if tile_map == null:
		return -1;
	var n = 0;
	for cell in tile_map.cell_types.keys():
		if tile_map.cell_types[cell] == "toxic":
			n += 1;
	return n;

# El montaje: `pick_map()` es aleatorio, así que el mapa se reaplica entero y hay que demoler antes
# el almacén del mapa descartado o `place_storage()` deja la run sin almacén.
func _montar():
	var main = load("res://Main.tscn").instantiate();
	root.add_child(main);
	var menu = main.get_node_or_null("MainMenu");
	if menu:
		main.remove_child(menu);
		menu.free();
	main._start_game(PAQUETE);
	var pm = main.pollutionManager;
	pm.total_pollution = 0.0;
	pm.pollution_per_cell.clear();
	pm.peak_pollution = 0.0;
	for fab in main.factoryArray.duplicate():
		main._demolish_at_cell(fab.cell_position);
	var datos = {};
	for m in main.fileData.get("Maps", []):
		if m.get("id", "") == MAPA:
			datos = m;
	main.mapLoader.apply_map(datos, pm, main.get_node("TileMap"), main.fileData, {
		"placer": main.placer,
		"parent": main,
		"player": main.get_node("Player"),
		"bag": main.get_node("Player").get_node("Bag"),
		"factories": main.factoryArray,
		"on_produced": main._on_resource_produced,
	});
	await _esperar(10);
	return main;

# Las pantallas NO se buscan por nombre. `ui/upgradeScreen.gd` extiende `CanvasLayer` y en el árbol
# aparecen como `@CanvasLayer@N` en cuanto se apila más de una, así que `get_node("UpgradeScreen")`
# encuentra solo la primera y la foto sale con un panel encima del mapa. Se identifican por su
# señal, que es lo único que no les cambia.
func _pantalla(main):
	for hijo in main.get_children():
		if hijo.has_signal("upgrade_chosen"):
			return hijo;
	return null;

func _cerrar_pantallas(main):
	for hijo in main.get_children():
		if hijo.has_signal("upgrade_chosen"):
			main.remove_child(hijo);
			hijo.queue_free();

func _soltar(main):
	root.remove_child(main);
	main.free();

func _esperar(frames):
	for i in frames:
		await process_frame;

# Sin el `await RenderingServer.frame_post_draw` se guarda el frame ANTERIOR.
func _capturar(ruta):
	await _esperar(3);
	await RenderingServer.frame_post_draw;
	var img = root.get_texture().get_image();
	img.save_png(ruta);
	print("captura: %s" % ruta);

# Igual que `_capturar()`, pero despejando antes la pantalla de mejora: el juego alcanza sus
# propios checkpoints mientras el driver inyecta los suyos, y el panel tapa justo el mapa que
# se quiere mirar.
func _capturar_mapa(main, ruta):
	# `_close_menus()` cierra el radial, el panel y el tooltip, pero NO la `UpgradeScreen`: esa
	# solo se va sola cuando el jugador pulsa «Elegir». Aquí se libera a mano, y con
	# `remove_child()` antes del `queue_free()` porque el nodo viejo retiene su nombre hasta
	# final de frame y el checkpoint siguiente entraría renombrado.
	# Y el árbol se queda PAUSADO para la foto: despausarlo deja correr la run, que alcanza su
	# siguiente checkpoint en unos frames y vuelve a abrir la pantalla justo encima del mapa.
	main._close_menus();
	_cerrar_pantallas(main);
	paused = true;
	await _esperar(5);
	await RenderingServer.frame_post_draw;
	var img = root.get_texture().get_image();
	img.save_png(ruta);
	print("captura: %s" % ruta);
