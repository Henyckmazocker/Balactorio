extends SceneTree

# Verificación VISUAL del Plan «Variedad de Factorías» — las siete situaciones que la suite NO
# puede afirmar, porque ninguna es una cantidad: son preguntas de «¿cabe?», «¿se lee?», «¿se
# distinguen?». Monta cada una, deja una captura en `capturas/` y NO juzga nada: lo que decide
# si algo está bien o mal es mirar el PNG.
#
#   godot-4 --path . --script res://tools/ver_variedad.gd        # CON ventana, sin --headless
#
# Las siete (las cinco de M1-M4 y las dos que estrena el M4b):
#   1. M3 — el desplegable `Produce: [brick ▾]` del panel de la `Foundry`: ¿cabe dentro del panel?
#   2. M3 — el color del FX de `brick` / `glass` / `stone` subiendo al HUD: ¿se distinguen?
#   3. M4 — la `WaterTreatment` junto al agua y SIN `stone`: el marcador del mapa y la frase
#      genérica de `input` («⚠ Parada: sin insumo — tiéndele cinta de entrada»), que en una
#      restauradora se lee por primera vez. Dos capturas: el tooltip y el panel NO conviven.
#   4. M4 — el botón de la depuradora en el radial, con su precio partido en dos líneas.
#   5. M4b — 🔴 el radial con SEIS opciones, que es el defecto que abrió el hito y ya está
#      ARREGLADO: era `RADIUS = 118` px de separación entre centros contra un `BUTTON_WIDTH = 130`,
#      o sea cuatro pares montados con una franja de 28 px. La captura de antes se conserva al
#      lado, en `capturas/5_antes_m4b_seis_opciones.png`.
#   6. M4b — el mismo radial con OCHO opciones, que es el techo real (las nueve entradas del JSON
#      menos el `Storage`): el caso que el M5 va a hacer común al repartir sus mejoras.
#   7. M4b — el radial abierto en la ESQUINA de la pantalla: la corona creció, así que hay que
#      ver que sigue cabiendo entera en los 1280x720.
#
# El patrón es el de `tools/ver_dilema.gd` y `tools/ver_cuellos.gd`, con sus mismas trampas:
# `await RenderingServer.frame_post_draw` antes de `save_png()`, pausar para la foto pero
# DESPAUSAR antes (con el árbol pausado `_process()` no corre y los overlays no se repintan), las
# pantallas de mejora identificadas por su señal y nunca por su nombre, y el PNG bajo `res://`
# porque el snap de Godot no escribe en /tmp.

const MAPA = "forest_01";
const PAQUETE = "standard";
const SEMILLA = 20260922;

# Las seis del radial de la situación 5: las dos de siempre más las tres de la segunda cadena y
# el Reforester. El `Storage` queda fuera porque no es una factoría que el jugador coloque (lo
# pone el mapa en su `storage_cell`), y las dos de plank (MetaFactory / WorkerCamp) tampoco caben
# en la lista: seis es el número que el defecto del M1 describe.
const SEIS = ["WoodCutter", "WoodProcessing", "Quarry", "Foundry", "Reforester", "WaterTreatment"];
# Las cuatro de la situación 4: un surtido de media run con la depuradora dentro, para poder
# juzgar SU botón sin el amontonamiento de las seis.
const CUATRO = ["WoodCutter", "WoodProcessing", "Quarry", "WaterTreatment"];
# Las ocho de la situación 6: el techo de lo que el jugador puede llegar a tener desbloqueado.
# El `Storage` no entra —lo coloca el mapa, no se elige— y por eso son ocho y no nueve.
const OCHO = ["WoodCutter", "WoodProcessing", "Quarry", "Foundry", "Reforester",
	"WaterTreatment", "MetaFactory", "WorkerCamp"];
# El color del cubo de la factoría, muestreado del PNG de la situación 2: es el fondo sobre el
# que nace la etiqueta del FX, y por tanto contra el que hay que medir su contraste.
const CUBO = Color(69.0 / 255.0, 40.0 / 255.0, 60.0 / 255.0);

var _hecho = false;
var _capturas = [];

func _process(_delta):
	if _hecho:
		return false;
	_hecho = true;
	_todo();
	return false;

func _todo():
	seed(SEMILLA);
	DirAccess.make_dir_recursive_absolute("res://capturas");
	print("");
	print("### ver_variedad — siete situaciones de M1-M4b, mapa %s, paquete %s" % [MAPA, PAQUETE]);
	print("### ventana: %s" % str(root.size));

	await _situacion_1();
	await _situacion_2();
	await _situacion_3();
	await _situacion_4();
	await _situacion_5();
	await _situacion_6();
	await _situacion_7();

	print("");
	print("=== capturas dejadas en res://capturas/ ===");
	for c in _capturas:
		print("  %s" % c);
	quit();

# --- 1. El desplegable de la fundición (M3) -------------------------------------------------
func _situacion_1():
	var main = await _montar();
	_abastecer(main);
	var celdas = _elegir_celdas(main, 1, "production", "", 0.0, 150.0, 150.0);
	print("");
	print("=== 1. El desplegable de la Foundry (M3) ===");
	if celdas.is_empty():
		print("  NO MONTADA: no hay casilla libre bien centrada en pantalla.");
		_soltar(main);
		return;
	var celda = celdas[0];
	main._on_factory_chosen("Foundry", celda);
	var fab = _fab_en(main, celda);
	if fab == null:
		print("  NO MONTADA: la Foundry no se ha colocado en %s." % str(celda));
		_soltar(main);
		return;
	print("  Foundry en %s (pantalla %s), produce '%s', candidatos %s" % [
		str(celda), str(_pos_pantalla(main, celda)), str(fab.production),
		str(fab.production_candidates)]);
	await _estabilizar(main);
	_raton(main, celda);
	await _esperar(4);
	# Por el camino real del juego: el click izquierdo sobre casilla ocupada acaba aquí.
	main._show_factory_panel(fab);
	await _esperar(6);
	var panel = main.get_node_or_null("FactoryPanel");
	if panel == null:
		print("  NO MONTADA: el panel no está en el árbol.");
		_soltar(main);
		return;
	var r_panel = panel._panel.get_global_rect();
	print("  panel      : %s" % _rect_txt(r_panel));
	if panel._material_option == null:
		print("  🔴 SIN DESPLEGABLE: hasMaterialChoice() = %s" % str(fab.hasMaterialChoice()));
	else:
		var r_opt = panel._material_option.get_global_rect();
		print("  desplegable: %s  texto '%s'" % [
			_rect_txt(r_opt), panel._material_option.text]);
		print("  desbordes del desplegable respecto al panel (px, >0 = se sale):");
		print("    izquierda %.1f · derecha %.1f · arriba %.1f · abajo %.1f" % [
			r_panel.position.x - r_opt.position.x,
			r_opt.end.x - r_panel.end.x,
			r_panel.position.y - r_opt.position.y,
			r_opt.end.y - r_panel.end.y]);
	print("  texto del panel: %s" % _texto(panel).replace("\n", " / "));
	# Las filas del panel, una a una, con el hueco que deja cada una respecto de la anterior
	# (M4b): la línea de `blocked_reason` se monta SIEMPRE y se esconde, y lo que hay que ver es
	# que escondida no reserva ni un píxel. Una fila invisible sale marcada como tal.
	_medir_filas(panel);
	await _capturar(main, "res://capturas/1_foundry_desplegable.png");
	_soltar(main);

# --- 2. Los colores del FX (M3) -------------------------------------------------------------
func _situacion_2():
	var main = await _montar();
	_abastecer(main);
	# Tres casillas separadas en pantalla para que las tres etiquetas no se pisen.
	var celdas = _elegir_celdas(main, 3, "production", "", 110.0, 140.0, 130.0);
	print("");
	print("=== 2. El color del FX: brick / glass / stone (M3) ===");
	if celdas.size() < 3:
		print("  NO MONTADA: solo %d casilla(s) separada(s) en pantalla." % celdas.size());
		_soltar(main);
		return;
	# Las dos fundiciones y la cantera, colocadas de verdad: así la captura enseña de QUÉ
	# factoría sale cada color, que es justo lo que el FX tiene que desambiguar.
	main._on_factory_chosen("Foundry", celdas[0]);
	main._on_factory_chosen("Foundry", celdas[1]);
	main._on_factory_chosen("Quarry", celdas[2]);
	var f_glass = _fab_en(main, celdas[1]);
	if f_glass != null:
		f_glass.setProduction("glass");
	for i in 3:
		var f = _fab_en(main, celdas[i]);
		print("  %s en %s (pantalla %s) -> produce '%s'" % [
			("—" if f == null else f.type), str(celdas[i]),
			str(_pos_pantalla(main, celdas[i])), ("—" if f == null else str(f.production))]);
	# El cursor se lleva a una esquina vacía: en cuanto se queda sobre una casilla ocupada,
	# `Main._update_hover_tooltip()` monta el tooltip de hover y tapa justo el FX que se quiere
	# mirar. El ratón no se reinicia entre situaciones —es del sistema, no del árbol—.
	Input.warp_mouse(Vector2(30, root.size.y - 30));
	await _estabilizar(main);
	# El FX se dispara por el MISMO camino que el juego —`Main._on_resource_produced()`, que es
	# quien elige el color en `_get_material_color()`—, con `source = null` para que no entre en
	# la red de cintas: lo que se mira es el color de la etiqueta, no la entrega.
	main._on_resource_produced("brick", 5, _mundo(main, celdas[0]));
	main._on_resource_produced("glass", 5, _mundo(main, celdas[1]));
	main._on_resource_produced("stone", 5, _mundo(main, celdas[2]));
	await _esperar(3);
	print("  FX vivos en pantalla: %d" % _contar_fx(main));
	# Los tres colores, medidos contra el cubo oscuro de la factoría sobre el que nace la
	# etiqueta (M4b): el `+5` de `stone` era el de menos contraste ahí, y ésta es la cuenta que
	# la captura tiene que confirmar. La distancia RGB a los otros dos dice lo otro que no podía
	# romperse: que aclararlo no lo acercara ni al terracota ni al azul.
	print("  contraste del FX sobre el cubo de la factoría %s (WCAG, más alto = mejor):" % (
		"(69,40,60)"));
	var c_stone = main._get_material_color("stone");
	var c_brick = main._get_material_color("brick");
	var c_glass = main._get_material_color("glass");
	for par in [["brick", c_brick], ["glass", c_glass], ["stone", c_stone]]:
		print("    %-6s %s -> contraste %.2f" % [par[0], str(par[1]), _wcag(par[1], CUBO)]);
	print("    distancia RGB stone↔brick %.2f · stone↔glass %.2f · brick↔glass %.2f" % [
		_dist(c_stone, c_brick), _dist(c_stone, c_glass), _dist(c_brick, c_glass)]);
	# El FX es una etiqueta de 18 px en un mapa de 1280x720: a tamaño real los tres colores se
	# juzgan mal, así que además de la foto entera se guarda un recorte ampliado de la zona
	# donde están los tres. El recorte NO es otra captura: sale de la misma imagen.
	await _capturar(main, "res://capturas/2_fx_brick_glass_stone.png",
		_zona(main, celdas, 70.0), 3, "res://capturas/2b_fx_zoom.png");
	_soltar(main);

# --- 3. La depuradora parada (M4) -----------------------------------------------------------
func _situacion_3():
	var main = await _montar();
	_abastecer(main);
	print("");
	print("=== 3. La WaterTreatment sin stone (M4) ===");
	# Entre todas las casillas donde la depuradora cabe se prefiere una cuyo agua quede a la
	# IZQUIERDA en pantalla: el tooltip y el panel nacen a la derecha del cursor (+14 px), así que
	# con el agua a la derecha la propia superficie que se quiere leer tapa la razón por la que la
	# depuradora está ahí.
	var celdas = _elegir_celdas(main, 8, "restoration", "WaterTreatment", 0.0, 150.0, 150.0);
	if celdas.is_empty():
		print("  NO MONTADA: ninguna casilla junto al agua queda centrada en pantalla.");
		_soltar(main);
		return;
	var celda = celdas[0];
	for c in celdas:
		if _agua_a_la_izquierda(main, c):
			celda = c;
			break;
	main._on_factory_chosen("WaterTreatment", celda);
	var fab = _fab_en(main, celda);
	if fab == null:
		print("  NO MONTADA: la depuradora no se ha colocado en %s." % str(celda));
		_soltar(main);
		return;
	# Un tick: `blocked_reason` lo escribe update() y nadie más. Sin cinta de entrada el búfer
	# está vacío, así que checkNeeds() falla y la razón es "input".
	fab.update(_bolsa(main));
	print("  WaterTreatment en %s (pantalla %s), workers %d/%d, búfer %s -> razón '%s'" % [
		str(celda), str(_pos_pantalla(main, celda)), fab.workers_assigned, fab.workers_needed,
		str(fab.input_buffer), fab.blocked_reason]);
	print("  vecinas de agua: %s" % str(_vecinas_agua(main, celda)));
	await _estabilizar(main);
	# 3a — el tooltip (el hover). Se monta solo, desde `Main._update_hover_tooltip()`, con el
	# ratón plantado sobre la casilla.
	_raton(main, celda);
	await _esperar(8);
	var tooltip = main.get_node_or_null("FactoryTooltip");
	print("  3a tooltip: %s" % ("<sin tooltip>" if tooltip == null
		else _texto(tooltip).replace("\n", " / ")));
	_medir_superficie(tooltip, "3a tooltip");
	await _capturar(main, "res://capturas/3a_depuradora_tooltip.png");
	# 3b — el panel (el persistente). Mientras vive, el tooltip se calla: son dos superficies
	# distintas a propósito y no se mezclan, así que van en dos capturas.
	main._show_factory_panel(fab);
	await _esperar(6);
	var panel = main.get_node_or_null("FactoryPanel");
	print("  3b panel  : %s" % ("<sin panel>" if panel == null
		else _texto(panel).replace("\n", " / ")));
	_medir_superficie(panel, "3b panel");
	await _capturar(main, "res://capturas/3b_depuradora_panel.png");
	_soltar(main);

# --- 4. El botón de la depuradora en el radial (M4) -----------------------------------------
func _situacion_4():
	print("");
	print("=== 4. El botón de la WaterTreatment en el radial, con 4 opciones (M4) ===");
	await _radial(CUATRO, "res://capturas/4_radial_depuradora.png",
		"res://capturas/4b_radial_depuradora_zoom.png");

# --- 5. El radial con SEIS opciones (M4b) ---------------------------------------------------
func _situacion_5():
	print("");
	print("=== 5. 🔴 El radial con SEIS opciones (el defecto del M4b, ya arreglado) ===");
	print("  ANTES: RADIUS = 118 px fijo contra BUTTON_WIDTH = 130 -> 4 pares montados, el peor");
	print("         28x31 px (WoodCutter×WoodProcessing 28x15, WoodCutter×WaterTreatment 28x23,");
	print("         Quarry×Foundry 28x31, Foundry×Reforester 28x23).");
	print("  AHORA: BUTTON_WIDTH = 112 (la línea más ancha que el radial sabe escribir mide 101)");
	print("         y el radio lo calcula _ring_radius() sobre los rectángulos de verdad.");
	await _radial(SEIS, "res://capturas/5_radial_seis_opciones.png",
		"res://capturas/5b_radial_seis_zoom.png");

# --- 6. El radial con OCHO opciones, el techo (M4b) ------------------------------------------
func _situacion_6():
	print("");
	print("=== 6. El radial con OCHO opciones: el techo de lo desbloqueable (M4b) ===");
	print("  ANTES: 6 pares montados, el peor 47x47 px.");
	await _radial(OCHO, "res://capturas/6_radial_ocho_opciones.png",
		"res://capturas/6b_radial_ocho_zoom.png", Vector2(-1, -1), Vector2(300, 260));

# --- 7. El radial en la ESQUINA de la pantalla (M4b) -----------------------------------------
func _situacion_7():
	print("");
	print("=== 7. El radial abierto en la ESQUINA: ¿cabe la corona nueva? (M4b) ===");
	print("  El menú nace donde está el ratón, y con 8 opciones la corona mide 446x400 px.");
	await _radial(OCHO, "res://capturas/7_radial_esquina.png", "", Vector2(30, 30));

# El radial abierto sobre una casilla junto al agua —la única donde la depuradora es una opción
# de verdad— y medido botón a botón. Lo abre `Main._show_radial_menu()`, el camino real: es quien
# filtra por `canPlaceFactory()` con el nombre del tipo y quien lee la posición del ratón.
func _radial(disponibles, ruta, ruta_zoom = "", raton = Vector2(-1, -1), media = Vector2(230, 200)):
	var main = await _montar();
	_abastecer(main);
	var celdas = _elegir_celdas(main, 1, "restoration", "WaterTreatment", 0.0, 260.0, 220.0);
	if celdas.is_empty():
		print("  NO MONTADA: ninguna casilla junto al agua deja sitio al radial en pantalla.");
		_soltar(main);
		return;
	var celda = celdas[0];
	main.get_node("Player").availableFactories = disponibles.duplicate();
	await _estabilizar(main);
	# El menú nace donde está el ratón y filtra por la CASILLA: son dos cosas independientes, y
	# por eso la situación de la esquina puede plantar el cursor lejos de la celda elegida.
	if raton.x >= 0.0:
		Input.warp_mouse(raton);
	else:
		_raton(main, celda);
	await _esperar(4);
	print("  casilla %s · pantalla %s · ratón %s" % [
		str(celda), str(_pos_pantalla(main, celda)),
		str(main.get_viewport().get_mouse_position())]);
	main._show_radial_menu(celda);
	await _esperar(6);
	var radial = main.get_node_or_null("RadialMenu");
	if radial == null:
		print("  NO MONTADA: el radial no está en el árbol (¿ninguna opción cabía?).");
		_soltar(main);
		return;
	_medir_radial(main, radial);
	var foco = main.get_viewport().get_mouse_position();
	await _capturar(main, ruta, _zona_en(foco, media), 2, ruta_zoom);
	_soltar(main);

# Los botones del radial con su rectángulo real, sus solapes dos a dos y lo que se sale de la
# ventana. Es el número que la captura tiene que confirmar con los ojos, y desde el M4b el
# criterio del hito es literalmente esta cuenta: «ningún par de botones se solapa» no se afirma
# de palabra, se imprime en píxeles.
func _medir_radial(main, radial):
	var botones = [];
	_recoger_botones(radial, botones);
	var alturas = [];
	for b in botones:
		alturas.append(b[1].size.y);
	print("  botones: %d · ancho %d px · radio de la corona %.1f px (suelo %.0f)" % [
		botones.size(), radial.BUTTON_WIDTH, radial._ring_radius(alturas), radial.MIN_RADIUS]);
	var pantalla = Rect2(Vector2.ZERO, Vector2(root.size));
	var se_salen = 0;
	var caja = Rect2();
	for i in range(botones.size()):
		var r = botones[i][1];
		caja = r if i == 0 else caja.merge(r);
		var fuera = "";
		if not pantalla.encloses(r):
			fuera = "  ⚠ SE SALE DE LA VENTANA";
			se_salen += 1;
		print("    %-16s %s%s" % [botones[i][0], _rect_txt(r), fuera]);
		print("      lineas: %s" % _texto(botones[i][2]).replace("\n", " | "));
	# Las distancias entre centros VECINOS, que es de donde salía el defecto: los 118 px del
	# radio viejo se quedaban en 102 de separación horizontal contra los 130 del botón.
	for i in range(botones.size()):
		var j = (i + 1) % botones.size();
		if botones.size() < 2:
			break;
		var d = botones[j][1].get_center() - botones[i][1].get_center();
		print("    centros %s → %s: dx %.0f px, dy %.0f px (ancho %d)" % [
			botones[i][0], botones[j][0], abs(d.x), abs(d.y), radial.BUTTON_WIDTH]);
	var solapes = 0;
	for i in range(botones.size()):
		for j in range(i + 1, botones.size()):
			var inter = botones[i][1].intersection(botones[j][1]);
			if inter.size.x > 0.0 and inter.size.y > 0.0:
				solapes += 1;
				print("    🔴 SOLAPE %s × %s -> %.0f x %.0f px" % [
					botones[i][0], botones[j][0], inter.size.x, inter.size.y]);
	print("    SOLAPES: %d · corona %.0f x %.0f px · fuera de ventana: %d botón(es)" % [
		solapes, caja.size.x, caja.size.y, se_salen]);
	if solapes == 0:
		print("    sin solapes entre botones.");

# ---------- montaje ----------

# Igual que en `tools/ver_dilema.gd` y `tools/ver_cuellos.gd`: `pick_map()` es ALEATORIO, así que
# el mapa se reaplica entero y hay que demoler antes el almacén del mapa descartado o
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

# Dinero y gente de sobra: aquí no se mira la economía, se mira si algo cabe en pantalla. Con la
# bolsa corta, media opción del radial saldría atenuada y el ancho del botón no cambiaría — pero
# la captura contaría otra historia.
func _abastecer(main):
	var bag = _bolsa(main);
	bag.addToBag("wood", 500);
	bag.addToBag("stone", 500);
	bag.addToBag("plank", 200);
	bag.addWorkers(10);

func _bolsa(main):
	return main.get_node("Player").get_node("Bag");

func _soltar(main):
	paused = false;
	root.remove_child(main);
	main.free();

func _esperar(frames):
	for i in frames:
		await process_frame;

# ---------- geometría ----------

# La posición en PANTALLA del centro de una casilla, con la cámara dentro. Se calcula con la
# transformación real del nodo y no a mano: el TileMap va escalado (1.038 en x) y la Camera2D
# mueve el canvas, así que una fórmula escrita a ojo apunta a la casilla de al lado.
func _pos_pantalla(main, cell) -> Vector2:
	var tm = main.get_node("TileMap");
	return tm.get_global_transform_with_canvas() * tm.map_to_local(cell);

# La posición en MUNDO, que es la que la señal `resource_produced` lleva y con la que nace el FX.
func _mundo(main, cell) -> Vector2:
	var tm = main.get_node("TileMap");
	return tm.to_global(tm.map_to_local(cell));

# Planta el cursor sobre una casilla. Es la condición de tres de las cinco situaciones: el
# tooltip lo monta `Main._update_hover_tooltip()` leyendo la celda del ratón, y tanto el panel
# como el radial nacen en `get_viewport().get_mouse_position()`.
func _raton(main, cell):
	Input.warp_mouse(_pos_pantalla(main, cell));

# `n` casillas donde ese tipo de factoría cabe de verdad —lo pregunta `canPlaceFactory()`, el
# único punto de verdad, con la categoría y el NOMBRE, que es de donde sale el
# `requires_adjacent` de la depuradora—, ordenadas por cercanía al centro de la pantalla y
# separadas entre sí al menos `sep` px. Se buscan en vez de escribirlas a mano porque lo que
# hace falta es que la situación quepa EN LA FOTO.
func _elegir_celdas(main, n, kind, tipo, sep, margen_x, margen_y) -> Array:
	var tm = main.get_node("TileMap");
	var centro = Vector2(root.size) * 0.5;
	var candidatas = [];
	for cell in tm.get_used_cells(0):
		if not tm.canPlaceFactory(cell, main.factoryArray, kind, tipo):
			continue;
		var p = _pos_pantalla(main, cell);
		if p.x < margen_x or p.x > root.size.x - margen_x:
			continue;
		if p.y < margen_y or p.y > root.size.y - margen_y:
			continue;
		candidatas.append([p.distance_to(centro), cell, p]);
	candidatas.sort_custom(func(a, b): return a[0] < b[0]);
	var fuera = [];
	var puestas = [];
	for c in candidatas:
		if fuera.size() >= n:
			break;
		var vale = true;
		for p in puestas:
			if p.distance_to(c[2]) < sep:
				vale = false;
		if vale:
			fuera.append(c[1]);
			puestas.append(c[2]);
	return fuera;

# ¿Alguna de sus vecinas de agua queda a la izquierda en pantalla? Ver el porqué en la situación 3.
func _agua_a_la_izquierda(main, cell) -> bool:
	var tm = main.get_node("TileMap");
	var p = _pos_pantalla(main, cell);
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			if dx == 0 and dy == 0:
				continue;
			var v = cell + Vector2i(dx, dy);
			var t = tm.cell_types.get(v, "");
			if t != "lake" and t != "stream":
				continue;
			if _pos_pantalla(main, v).x <= p.x - 10.0:
				return true;
	return false;

func _vecinas_agua(main, cell) -> Array:
	var tm = main.get_node("TileMap");
	var fuera = [];
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			if dx == 0 and dy == 0:
				continue;
			var v = cell + Vector2i(dx, dy);
			var t = tm.cell_types.get(v, "");
			if t == "lake" or t == "stream":
				fuera.append("%s %s" % [str(v), t]);
	return fuera;

func _rect_txt(r: Rect2) -> String:
	return "x %.0f..%.0f  y %.0f..%.0f  (%.0f x %.0f)" % [
		r.position.x, r.end.x, r.position.y, r.end.y, r.size.x, r.size.y];

# ---------- lectura del árbol ----------

func _fab_en(main, cell):
	for fab in main.factoryArray:
		if fab.cell_position == cell:
			return fab;
	return null;

# Todo el texto que una superficie tiene EN PANTALLA ahora mismo, recorriendo sus Labels. Se lee
# del árbol y no del modelo a propósito: lo que se comprueba es lo que el jugador LEE.
func _texto(nodo) -> String:
	var trozos = [];
	_recoger_labels(nodo, trozos);
	return "\n".join(trozos);

func _recoger_labels(nodo, fuera):
	if nodo is Label:
		fuera.append(nodo.text);
	for hijo in nodo.get_children():
		_recoger_labels(hijo, fuera);

# Cada botón del radial con el nombre que lleva escrito en su primera línea, su rectángulo en
# pantalla y el propio nodo (para leerle las líneas).
func _recoger_botones(nodo, fuera):
	if nodo is Button:
		var lineas = [];
		_recoger_labels(nodo, lineas);
		var nombre = lineas[0] if not lineas.is_empty() else "<sin texto>";
		fuera.append([nombre, nodo.get_global_rect(), nodo]);
	for hijo in nodo.get_children():
		_recoger_botones(hijo, fuera);

# Las etiquetas de FX son Labels hijas directas de Main con su `+N` dentro (`_spawn_fx_label()`).
func _contar_fx(main) -> int:
	var n = 0;
	for hijo in main.get_children():
		if hijo is Label and hijo.text.begins_with("+"):
			n += 1;
	return n;

# ---------- pantallas y capturas ----------

# Las pantallas de mejora NO se buscan por nombre: `ui/upgradeScreen.gd` extiende `CanvasLayer` y
# en cuanto se apila más de una Godot las renombra a `@CanvasLayer@N`. Se identifican por su
# señal, que es lo único que no les cambia.
func _cerrar_pantallas(main):
	for hijo in main.get_children():
		if hijo.has_signal("upgrade_chosen"):
			main.remove_child(hijo);
			hijo.queue_free();

# 🔴 Deja el juego VIVO y sin pantallas encima, y le da frames para que `_process()` corra. Es lo
# que separa «la foto de ahora» de «la foto de la última vez que el árbol no estuvo pausado»: con
# el árbol pausado ni el tinte ni el `StatusOverlay` se repintan, y la primera pasada de
# `tools/ver_cuellos.gd` capturó así un mapa sin un solo marcador.
func _estabilizar(main):
	_cerrar_pantallas(main);
	paused = false;
	await _esperar(8);

# La foto. El árbol se PAUSA justo para el disparo —si se deja correr, la run alcanza su
# checkpoint siguiente en unos frames y abre una pantalla encima de lo que se quería ver— y NO se
# cierran los menús: aquí lo fotografiado es justo el panel o el radial, al revés que en
# `ver_cuellos._capturar_mapa()`. Lo que sí se despeja es la pantalla de mejora.
# Y `await RenderingServer.frame_post_draw` antes de `save_png()`, o se guarda el frame anterior.
func _capturar(main, ruta, zona = Rect2i(), factor = 3, ruta_zoom = ""):
	_cerrar_pantallas(main);
	paused = true;
	await _esperar(2);
	await RenderingServer.frame_post_draw;
	var img = root.get_texture().get_image();
	img.save_png(ruta);
	_capturas.append(ruta);
	print("  captura: %s" % ruta);
	# El recorte ampliado sale de ESTA misma imagen, no de otra foto: si se volviera a disparar,
	# el FX habría seguido desvaneciéndose y las dos capturas contarían cosas distintas.
	if ruta_zoom != "" and zona.size.x > 0 and zona.size.y > 0:
		var recorte = img.get_region(zona);
		recorte.resize(zona.size.x * factor, zona.size.y * factor, Image.INTERPOLATE_NEAREST);
		recorte.save_png(ruta_zoom);
		_capturas.append(ruta_zoom);
		print("  captura: %s  (recorte %s ×%d)" % [ruta_zoom, str(zona), factor]);
	paused = false;

# El rectángulo de pantalla que cubre esas casillas con un margen, recortado contra la ventana.
func _zona(main, celdas, margen) -> Rect2i:
	var minimo = Vector2(root.size);
	var maximo = Vector2.ZERO;
	for c in celdas:
		var p = _pos_pantalla(main, c);
		minimo = Vector2(min(minimo.x, p.x), min(minimo.y, p.y));
		maximo = Vector2(max(maximo.x, p.x), max(maximo.y, p.y));
	var zona = Rect2i(
		Vector2i(int(minimo.x - margen), int(minimo.y - margen)),
		Vector2i(int(maximo.x - minimo.x + 2.0 * margen), int(maximo.y - minimo.y + 2.0 * margen)));
	return zona.intersection(Rect2i(Vector2i.ZERO, Vector2i(root.size)));

# El rectángulo centrado en un punto de PANTALLA, del tamaño pedido. Lo usa el radial, cuyos
# botones se reparten alrededor del cursor y no de la casilla.
func _zona_en(p: Vector2, media: Vector2) -> Rect2i:
	var zona = Rect2i(Vector2i(int(p.x - media.x), int(p.y - media.y)),
		Vector2i(int(2.0 * media.x), int(2.0 * media.y)));
	return zona.intersection(Rect2i(Vector2i.ZERO, Vector2i(root.size)));

# Una superficie de detalle (el tooltip o el panel) medida contra su propio marco y contra la
# ventana: la frase de parada de la depuradora es la línea más larga que el juego escribe en
# ellas, así que es la que decide su ancho.
func _medir_superficie(nodo, etiqueta):
	if nodo == null or nodo._panel == null:
		return;
	var r = nodo._panel.get_global_rect();
	var pantalla = Rect2(Vector2.ZERO, Vector2(root.size));
	print("  %s marco: %s%s" % [etiqueta, _rect_txt(r),
		("" if pantalla.encloses(r) else "  ⚠ SE SALE DE LA VENTANA")]);
	# Una Label del VBox se estira al ancho del contenedor, así que su rectángulo no dice nada:
	# lo que decide el ancho del marco es el ancho NATURAL del texto más largo
	# (`get_minimum_size()`), que es lo que se compara aquí contra el marco.
	var etiquetas = [];
	_recoger_nodos_label(nodo, etiquetas);
	for l in etiquetas:
		var ancho = l.get_minimum_size().x;
		print("    '%s' -> texto %.0f px, marco %.0f px, holgura %.0f px" % [
			l.text, ancho, r.size.x, r.size.x - ancho]);

# Las filas de una superficie de detalle con su alto y el hueco contra la anterior. Lo que se
# busca es una fila INVISIBLE que aun así ocupe sitio: ése era el defecto 4 del M4b.
func _medir_filas(superficie):
	if superficie == null or superficie._panel == null:
		return;
	var caja = superficie._panel.get_child(0);
	var anterior = -1.0;
	for hijo in caja.get_children():
		var texto = hijo.text if hijo is Label else "<%s>" % hijo.get_class();
		if not hijo.visible:
			print("    (oculta, 0 px)      '%s'" % texto);
			continue;
		var r = hijo.get_rect();
		var hueco = "—" if anterior < 0.0 else "%.0f" % (r.position.y - anterior);
		print("    y %6.0f..%-6.0f hueco %-4s '%s'" % [
			r.position.y, r.end.y, hueco, texto]);
		anterior = r.end.y;

func _recoger_nodos_label(nodo, fuera):
	if nodo is Label:
		fuera.append(nodo);
	for hijo in nodo.get_children():
		_recoger_nodos_label(hijo, fuera);

# La razón de contraste WCAG entre dos colores, con la linealización sRGB de verdad: `
# Color.get_luminance()` de Godot pondera los canales SIN linearizar y da otro número, así que
# aquí se hace a mano. Es lo que dice si una etiqueta de 18 px se lee sobre el cubo de debajo.
func _wcag(a: Color, b: Color) -> float:
	var la = _lum(a);
	var lb = _lum(b);
	return (max(la, lb) + 0.05) / (min(la, lb) + 0.05);

func _lum(c: Color) -> float:
	return 0.2126 * _canal(c.r) + 0.7152 * _canal(c.g) + 0.0722 * _canal(c.b);

func _canal(v: float) -> float:
	if v <= 0.03928:
		return v / 12.92;
	return pow((v + 0.055) / 1.055, 2.4);

# La distancia RGB entre dos colores, que es lo que dice si dos etiquetas se confunden.
func _dist(a: Color, b: Color) -> float:
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length();
