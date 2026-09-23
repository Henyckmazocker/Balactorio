extends SceneTree

# Verificación VISUAL del Plan «Feedback de Cuellos de Botella» — las dos comprobaciones que su
# sección «Verificación» llama «las dos que de verdad importan, jugadas»:
#
#   1. Montar una cadena con un fallo deliberado de cada tipo y comprobar que los CUATRO COLORES
#      se distinguen en pantalla a resolución normal, SIN HOVER.
#   2. Una run sana: confirmar que el mapa está EN SILENCIO. Si el indicador aparece sobre
#      factorías que van bien, el plan ha fracasado aunque el código sea correcto.
#
# No es una prueba: no mide balance y no va en la suite. Arranca el juego CON render.
#
#   godot-4 --path . --script res://tools/ver_cuellos.gd
#
# Las capturas salen en `res://capturas/`. El snap de Godot no puede escribir en /tmp.

const MAPA = "forest_01";
const PAQUETE = "standard";
const SEMILLA = 20260920;

# Las cuatro casillas del escenario 1, en fila y separadas para que los marcadores no se toquen.
# Se eligen en la banda alta del mapa, lejos del almacén de `storage_cell` [13, 8].
const CELDA_WORKERS = Vector2i(3, 2);
const CELDA_INPUT   = Vector2i(6, 2);
const CELDA_OUTPUT  = Vector2i(9, 2);
const CELDA_CHOKE   = Vector2i(12, 2);

# La cadena sana del escenario 2: cortadora -> cinta -> almacén del mapa.
const CELDA_SANA = Vector2i(11, 8);

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

	# --- ESCENARIO 1: los cuatro colores a la vez -------------------------------------------
	var main = await _montar();
	var fabs = await _montar_los_cuatro(main);
	await _capturar_mapa(main, "res://capturas/1_cuatro_razones.png");
	print("");
	print("=== Escenario 1 — un fallo de cada tipo ===");
	for clave in ["workers", "input", "output", "choke"]:
		var fab = fabs.get(clave, null);
		var real = fab.blocked_reason if fab != null else "<sin factoría>";
		var veredicto = "OK" if real == clave else "NO COINCIDE";
		print("  %-8s esperado '%s' -> real '%s'  [%s]" % [
			_nombre_celda(fab), clave, real, veredicto]);
	print("  marcadores pintados en el mapa: %d" % _contar_marcados(main));
	_soltar(main);

	# --- ESCENARIO 2: la run sana, en silencio ----------------------------------------------
	main = await _montar();
	await _montar_cadena_sana(main);
	# Se le dan segundos de juego de verdad: el silencio que interesa no es el del primer frame
	# —cuando nada ha tickeado todavía y `blocked_reason` vale "" por nacimiento— sino el de una
	# línea que lleva rato produciendo y entregando.
	paused = false;
	Engine.time_scale = 20.0;
	# Se MUESTREA a lo largo de la run en vez de mirar solo el último frame: la pregunta del
	# plan es si el indicador aparece CONSTANTEMENTE sobre factorías que van bien, y eso es una
	# proporción del tiempo, no una foto. Un parpadeo suelto es el ahogo haciendo de rampa; un
	# marcador permanente sobre una línea que produce sería el fracaso del hito.
	var muestras = 0;
	var con_ruido = 0;
	var visto = {};
	for i in 40:
		await _esperar(6);
		muestras += 1;
		var censo = _censo(main);
		if not censo.is_empty():
			con_ruido += 1;
			for linea in censo:
				visto[linea] = int(visto.get(linea, 0)) + 1;
	Engine.time_scale = 1.0;
	await _capturar_mapa(main, "res://capturas/2_run_sana.png");
	print("");
	print("=== Escenario 2 — run sana, ¿el mapa calla? ===");
	print("  factorías en el mapa        : %d" % main.factoryArray.size());
	print("  muestras                    : %d" % muestras);
	print("  muestras con algún marcador : %d (%.0f%%)" % [con_ruido, 100.0 * con_ruido / muestras]);
	for linea in visto:
		print("    %s  en %d/%d muestras" % [linea, visto[linea], muestras]);
	if con_ruido == 0:
		print("  VEREDICTO: el mapa está en silencio toda la run.");
	else:
		print("  VEREDICTO: hay marcador en parte de la run — mirar si es el ahogo (legítimo) o ruido.");
	_soltar(main);

	# --- ESCENARIO 3: el tooltip con el ratón QUIETO (M4) ------------------------------------
	# La pregunta que M4 vino a arreglar: con el cursor parado sobre una factoría, ¿la línea de
	# «Parada» aparece al pararse y se cae al volver a producir SIN mover el ratón? Antes de M4
	# no: `_update_hover_tooltip()` solo reconstruía el tooltip al cambiar de casilla, así que
	# enseñaba una cortadora sin «Parada» mientras su marcador rojo sí estaba pintado.
	main = await _montar();
	var bag3 = main.get_node("Player").get_node("Bag");
	bag3.addToBag("wood", 500);
	bag3.addWorkers(4);
	main._on_factory_chosen("WoodProcessing", CELDA_INPUT);
	var wp = _fab_en(main, CELDA_INPUT);
	# El cursor se planta encima y NO se vuelve a tocar en todo el escenario: es la condición
	# entera de la prueba. `_update_hover_tooltip()` lee la celda de la posición del ratón.
	var tm3 = main.get_node("TileMap");
	Input.warp_mouse(tm3.map_to_local(CELDA_INPUT) + tm3.position);
	wp.update(bag3);
	# 🔴 Hay que DESPAUSAR y cerrar la pantalla de mejora antes de leer nada: con el árbol
	# pausado `Main._process()` no corre, así que `_update_hover_tooltip()` no llega a montar el
	# tooltip y la lectura devolvería «<sin tooltip>» por un motivo que no tiene nada que ver
	# con lo que se está probando.
	await _estabilizar(main);
	var razon_parada = wp.blocked_reason;
	var texto_parada = _texto_tooltip(main);
	await _capturar_mapa(main, "res://capturas/3a_tooltip_parada.png");

	# Y ahora se le da de comer, SIN TOCAR EL RATÓN.
	wp.receiveMaterial("wood", 50);
	wp.update(bag3);
	await _estabilizar(main);
	var texto_produce = _texto_tooltip(main);
	await _capturar_mapa(main, "res://capturas/3b_tooltip_produce.png");

	print("");
	print("=== Escenario 3 — el tooltip con el ratón quieto (M4) ===");
	print("  parada    -> razón '%s' | tooltip dice 'Parada': %s" % [
		razon_parada, str(texto_parada.contains("Parada"))]);
	print("     %s" % texto_parada.replace("\n", " / "));
	print("  produciendo -> tooltip dice 'Parada': %s" % str(texto_produce.contains("Parada")));
	print("     %s" % texto_produce.replace("\n", " / "));
	if texto_parada.contains("Parada") and not texto_produce.contains("Parada"):
		print("  VEREDICTO: el tooltip se repinta solo. M4 cumplido.");
	else:
		print("  VEREDICTO: NO cumplido — el tooltip no sigue al estado con el ratón quieto.");
	_soltar(main);

	print("");
	print("  capturas en res://capturas/");
	quit();

# Deja el juego VIVO y sin pantallas encima, y le da frames para que `_process()` corra. Es el
# paso que separa «leer el estado de ahora» de «leer el estado de la última vez que el árbol no
# estuvo pausado», y el juego pausa el árbol solo con abrir la pantalla de mejora.
func _estabilizar(main):
	_cerrar_pantallas(main);
	paused = false;
	await _esperar(8);

# Todo el texto que el tooltip tiene en pantalla ahora mismo, recorriendo sus Labels. Se lee del
# árbol y no del modelo a propósito: lo que se verifica es lo que el jugador LEE.
func _texto_tooltip(main) -> String:
	var tt = main.get_node_or_null("FactoryTooltip");
	if tt == null:
		return "<sin tooltip>";
	var trozos = [];
	_recoger_labels(tt, trozos);
	return "\n".join(trozos);

func _recoger_labels(nodo, fuera):
	if nodo is Label:
		fuera.append(nodo.text);
	for hijo in nodo.get_children():
		_recoger_labels(hijo, fuera);

# Los cuatro fallos, cada uno por el camino que lo provoca de verdad. El orden importa: la
# saturación de la casilla del `choke` se aplica DESPUÉS de colocar su factoría, porque
# `canPlaceFactory()` no deja poner una productora sobre casilla saturada (Costes M7).
func _montar_los_cuatro(main) -> Dictionary:
	var bag = main.get_node("Player").get_node("Bag");
	# Dinero y gente de sobra: lo que se mira aquí es el feedback, no la economía.
	bag.addToBag("wood", 500);
	bag.addWorkers(4);

	var fabs = {};

	# 1. "workers" — una WoodProcessing a la que se le quitan los workers que el placer le dio.
	main._on_factory_chosen("WoodProcessing", CELDA_WORKERS);
	fabs["workers"] = _fab_en(main, CELDA_WORKERS);
	if fabs["workers"] != null and fabs["workers"].workers_assigned > 0:
		bag.unassignWorkers(fabs["workers"].workers_assigned);
		fabs["workers"].workers_assigned = 0;

	# 2. "input" — una WoodProcessing CON su worker pero sin madera en el búfer de entrada.
	#    Desde Cintas M2 una factoría solo come lo que una cinta le trae, así que basta con no
	#    tenderle ninguna: el búfer se queda vacío y `checkNeeds()` falla.
	main._on_factory_chosen("WoodProcessing", CELDA_INPUT);
	fabs["input"] = _fab_en(main, CELDA_INPUT);

	# 3. "output" — una WoodCutter con el búfer de salida lleno. Se rellena a mano en vez de
	#    esperar los 40 s de juego que tardaría en llenarse sola a 10 unidades por tick de 4 s:
	#    el estado resultante es el mismo que vería el jugador, y lo que se mira es el color.
	main._on_factory_chosen("WoodCutter", CELDA_OUTPUT);
	fabs["output"] = _fab_en(main, CELDA_OUTPUT);
	if fabs["output"] != null:
		fabs["output"].output_buffer = fabs["output"].OUTPUT_BUFFER_MAX;

	# 4. "choke" — una WoodCutter sobre casilla saturada. Primero se coloca y después se ensucia,
	#    por la regla de colocación de arriba.
	main._on_factory_chosen("WoodCutter", CELDA_CHOKE);
	fabs["choke"] = _fab_en(main, CELDA_CHOKE);
	main.pollutionManager.addPollution(
		main.pollutionManager.cell_block_pollution * 2.0, CELDA_CHOKE);

	# Un tick de cada una: `blocked_reason` lo escribe `update()` y nadie más, así que sin
	# tickear las cuatro seguirían con el "" con el que nacieron.
	for clave in fabs:
		if fabs[clave] != null:
			fabs[clave].update(main.get_node("Player").get_node("Bag"));
	await _esperar(5);
	return fabs;

# La cadena que SÍ funciona: cortadora con cinta hasta el almacén con el que arranca el mapa,
# y un Reforester al lado.
#
# El Reforester no es decorado: sin él, una cortadora sola le mete 3.0 de contaminación por tick
# a SU PROPIA casilla y en ~20 ticks la satura (`cell_block_pollution` = 12.5), así que acaba
# marcada con "choke" — legítimamente, porque el ahogo es la mecánica y la cortadora se está
# asfixiando de verdad. Eso no es una run sana: es una run sin limpiar. La primera versión de
# este fichero midió justo eso y llamó «ruido» al juego funcionando.
func _montar_cadena_sana(main):
	var bag = main.get_node("Player").get_node("Bag");
	bag.addToBag("wood", 500);
	main._on_factory_chosen("WoodCutter", CELDA_SANA);
	# DOS y no uno: la restauración se reparte entre las 9 casillas del área
	# (`factoryData._spread_restoration`), así que a la casilla de la cortadora le llega una
	# novena parte de los -4.0 de cada Reforester. Con uno solo, la cortadora sigue ganando la
	# carrera contra su propia suciedad y acaba ahogándose — que es el juego funcionando, no un
	# fallo del feedback, pero tampoco es la «run sana» que este escenario tiene que enseñar.
	main._on_factory_chosen("Reforester", CELDA_SANA + Vector2i(0, -1));
	main._on_factory_chosen("Reforester", CELDA_SANA + Vector2i(-1, 0));
	var almacen = null;
	for fab in main.factoryArray:
		if fab.factory_type == "storage":
			almacen = fab;
	if almacen != null and main.beltNetwork != null:
		main.beltNetwork.place_drag(
			CELDA_SANA, almacen.cell_position, main.factoryArray, bag, true);
	await _esperar(5);

# Quién lleva marcador ahora mismo, con su razón. Es lo mismo que `tileMap.draw_status()` decide
# pintar, leído del mismo sitio: `blocked_reason != ""`.
func _censo(main) -> Array:
	var fuera = [];
	for fab in main.factoryArray:
		if fab == null or not is_instance_valid(fab):
			continue;
		if fab.blocked_reason != "":
			fuera.append("%s en %s -> '%s'" % [fab.type, fab.cell_position, fab.blocked_reason]);
	return fuera;

func _contar_marcados(main) -> int:
	return _censo(main).size();

func _nombre_celda(fab) -> String:
	if fab == null:
		return "—";
	return "%s%s" % [fab.type, fab.cell_position];

func _fab_en(main, cell):
	for fab in main.factoryArray:
		if fab.cell_position == cell:
			return fab;
	return null;

# El montaje es el de `tools/ver_dilema.gd`, con su mismo porqué: `pick_map()` es aleatorio, así
# que el mapa se reaplica entero y hay que demoler antes el almacén del mapa descartado o
# `place_storage()` deja la run con dos.
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

# Las pantallas NO se buscan por nombre: `ui/upgradeScreen.gd` extiende `CanvasLayer` y en cuanto
# se apila más de una Godot las renombra a `@CanvasLayer@N`. Se identifican por su señal.
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

# El árbol se queda PAUSADO para la foto: despausarlo deja correr la run, que alcanza su
# checkpoint siguiente en unos frames y abre la pantalla de mejora justo encima del mapa.
#
# 🔴 PERO SE DESPAUSA ANTES, Y ESO NO ES UN DETALLE. El juego pausa el árbol solo al abrir la
# pantalla de mejora, y con el árbol pausado `tileMap._process()` NO corre — así que ni el tinte
# ni el `StatusOverlay` se repintan y la foto sale con el estado de la última vez que el juego
# estuvo vivo, que es antes de que este driver montara nada. La primera versión de este fichero
# capturó así cuatro factorías correctamente bloqueadas y un mapa sin un solo marcador, y el
# fallo era de la foto y no del juego.
func _capturar_mapa(main, ruta):
	main._close_menus();
	_cerrar_pantallas(main);
	paused = false;
	await _esperar(5);
	paused = true;
	await _esperar(2);
	await RenderingServer.frame_post_draw;
	var img = root.get_texture().get_image();
	img.save_png(ruta);
	print("captura: %s" % ruta);
	paused = false;
