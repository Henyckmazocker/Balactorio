extends CanvasLayer

# Panel de una factoría ya colocada. No sustituye a `ui/factoryTooltip.gd`: son dos superficies
# distintas a propósito. El tooltip nace y muere según el ratón entra y sale de la casilla, así que
# nunca podrá alojar un control con el que se interactúe —al ir hacia él se sale de la casilla y el
# tooltip se destruye—. Este se abre con una acción explícita (click izquierdo sobre casilla
# ocupada) y vive hasta que se cierra, que es lo que permite colgarle los botones de workers: es
# la única superficie del juego desde la que se puede reasignar un worker sin demoler la factoría.
#
# El esqueleto es el de `ui/radialMenu.gd`, que es el patrón que ya funciona en este juego: fondo
# que captura el ratón, ESC, y `queue_free()` siempre —nunca `free()`, que liberaría el nodo en
# mitad de la propagación del evento que lo está cerrando—.

# Separación mínima con los bordes de la pantalla al recortar la posición.
const MARGIN = 8.0;
# El color del dinero (Costes M5). Es el MISMO tono con el que el radial escribe el precio
# (`ui/radialMenu.gd`, `PRICE_COLOR`): lo que cuesta y lo que devuelve son la misma mecánica
# vista desde los dos lados, y dos colores distintos la contarían como dos.
const REFUND_COLOR = Color(0.85, 0.82, 0.6);
# La razón de parada en palabras, compartida con `ui/factoryTooltip.gd`: las dos superficies de
# detalle dicen la misma frase con el mismo color, y ese color es el del marcador del mapa.
const BLOCKED = preload("res://ui/blockedReason.gd");

var _panel;
# Dónde querría estar el panel (esquina superior izquierda, antes de recortar contra la pantalla).
var _wanted_pos = Vector2.ZERO;

# Lo que el bloque de workers necesita recordar entre pulsaciones: la factoría que se gestiona,
# la bolsa de la que salen y a la que vuelven los workers, y los nodos que cambian al reasignar.
var _factory_node = null;
var _bag = null;
var _workers_label = null;
var _free_label = null;
# La línea de «por qué está parada» (M3) y la razón que está pintando ahora mismo. La razón se
# guarda para poder comparar en `_process()` y repintar SOLO cuando cambia: el texto de una
# etiqueta se reasigna barato, pero hacerlo 60 veces por segundo para escribir lo mismo obliga a
# remedir el panel y a recortarlo contra la pantalla en cada frame.
var _blocked_label = null;
var _last_reason = "";
var _btn_assign = null;
var _btn_unassign = null;
# El desplegable de material, si esta factoría tiene entre qué elegir. Null en ocho de las nueve
# entradas del JSON, que tienen un solo candidato y no lo montan; lo monta la `Foundry` con su
# `materials: ["brick", "glass"]`. El ALMACÉN lo tuvo entre 2026-09-18 y 2026-09-23 y ya no:
# emite solo lo que le piden los consumidores de sus cintas y no hay nada que elegirle.
var _material_option = null;

# --- El bloque del filtro de cinta (M5). La red hace falta para dos cosas: saber si esta
# factoría tiene cinta de salida (`output_segment()`) y poner el filtro en ella
# (`set_belt_filter()`). Sin red inyectada el bloque no se monta y el panel es el de M4.
var _belt_network = null;
var _file_data = null;
var _belt_row = null;
var _belt_option = null;
var _belt_none_label = null;
# El segmento cuyo filtro se está editando. Se recalcula en cada refresco: el jugador puede
# tender o borrar cinta con el panel abierto, y por eso escuchamos `belt_network_changed`.
var _belt_cell = null;

# Lo que demoler esta factoría devolvería, ya calculado: `material -> cantidad`. Lo pasa hecho
# `Main._show_factory_panel()` con `factoryPlacer.getRefund()`, y el panel NO lo divide por su
# cuenta — el precio se lee, se cobra y se devuelve en un único sitio, y aquí solo se pinta.
# Vacío (el default) es lo normal para lo que nadie compró, y entonces no hay línea.
var _refund = {};

# `belt_network` va al final y con default, por lo mismo que el `materials` de
# factoryData.initialize(): hay llamadores que pasan posicionalmente (la suite) y un panel sin
# red tiene que seguir montándose igual que en M4.
# `refund` va detrás por lo mismo que `belt_network`: quien no sepa de economía (la suite)
# monta el panel de siempre y no enseña la línea de la devolución.
func initialize(factory_node, file_data, screen_pos, bag = null, belt_network = null, refund = {}):
	_factory_node = factory_node;
	_bag = bag;
	_file_data = file_data;
	_belt_network = belt_network;
	_refund = refund if refund is Dictionary else {};
	layer = 8;

	var root = Control.new();
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);
	add_child(root);

	# Fondo semi-transparente: click en él cierra el panel. De paso se traga los clicks que
	# llegarían a `Main._unhandled_input()`, así que con el panel abierto no se construye ni se
	# demuele por accidente detrás de él.
	var bg = ColorRect.new();
	bg.color = Color(0, 0, 0, 0.25);
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);
	bg.mouse_filter = Control.MOUSE_FILTER_STOP;
	bg.gui_input.connect(_on_bg_input);
	root.add_child(bg);

	_panel = PanelContainer.new();
	root.add_child(_panel);

	var vbox = VBoxContainer.new();
	vbox.add_theme_constant_override("separation", 3);
	_panel.add_child(vbox);

	_fill(vbox, factory_node, file_data);

	_wanted_pos = screen_pos + Vector2(14, -10);
	_panel.position = _wanted_pos;
	# El alto definitivo llega un frame tarde —medido: recortando justo después de `reset_size()`
	# el panel se colocaba contra un límite falso y se salía por abajo—, así que la posición se
	# recalcula cada vez que el contenedor cambia de tamaño. Sirve igual cuando M1 le cuelgue los
	# botones y el panel crezca.
	_panel.resized.connect(_reposition);
	_panel.reset_size();
	_reposition();

	# `belt_network_changed` existe desde M1 y el plan dice que la escucha este panel: mientras
	# vive, el jugador puede tender o borrar una cinta detrás de él —el fondo se traga el click,
	# pero el filtro lo movemos nosotros mismos— y lo que enseña se quedaría viejo.
	if _belt_network != null and not _belt_network.belt_network_changed.is_connected(_on_belt_network_changed):
		_belt_network.belt_network_changed.connect(_on_belt_network_changed);

func _fill(vbox, factory_node, file_data):
	var params = file_data["Factories"].get(factory_node.type, {});

	_add_label(vbox, factory_node.type, Color(1.0, 0.9, 0.2));

	# Por qué está parada, en una frase y con la acción dentro (M3). Va justo debajo del título
	# —el mismo sitio que en el tooltip— porque es la pregunta con la que se abre el panel de una
	# factoría quieta: todo lo demás la describe, y esto dice qué hacer con ella.
	# La etiqueta se monta SIEMPRE y se enseña o se esconde, que es lo que ya hacía el aviso de
	# workers al que sustituye: aparecer y desaparecer es lo que cambia el alto del panel, y
	# remedirlo (`_reposition()`) sale más barato que crear y liberar la etiqueta.
	#
	# 🔴 Y ESCONDIDA NO RESERVA NI UN PÍXEL, comprobado con el número (Variedad M4b, 2026-09-22):
	# un `BoxContainer` de Godot salta a los hijos invisibles al repartir sitio y tampoco los
	# cuenta en su tamaño mínimo, así que con la factoría funcionando el panel va del título
	# (`y 0..17`) directo a la línea siguiente (`y 20`), los mismos 20 px que separan a dos
	# líneas cualesquiera. La prueba del bloque «Variedad M4b» de `tests/run_tests.gd` lo fija,
	# porque es justo la clase de cosa que se rompería en silencio si alguien sustituyera el
	# `visible = false` por un texto en blanco: una Label con `" "` SÍ ocupa su línea entera.
	_blocked_label = _add_label(vbox, "");
	_refresh_blocked();

	# Qué produce. Si la factoría tiene entre qué elegir, la etiqueta fija se sustituye por el
	# desplegable: la etiqueta sale de `params["material"]` —lo que el JSON declara— y en cuanto se
	# cambiara de material estaría mintiendo, porque lo que la factoría fabrica de verdad vive en
	# `factory_node.production`.
	if factory_node.hasMaterialChoice():
		_build_material_block(vbox, factory_node);
	else:
		# Las de restauración declaran `material: null` en el JSON. Se compara contra `null` y no
		# contra el texto: `str(null)` devuelve "<null>", no "null", y comparar el texto deja la rama
		# de abajo muerta. Fue un bug real de `ui/factoryTooltip.gd` —pintaba «Produce: <null>»— y
		# está arreglado desde el 2026-09-17; la regla se conserva aquí porque es la trampa que
		# el `CLAUDE.md` del repo manda no repetir en UI nueva, no porque quede nada roto.
		var material = params.get("material");
		if factory_node.factory_type == "storage":
			# El almacén también declara `material: null`, pero no es una restauración ni una
			# factoría sin nada que hacer: desde 2026-09-23 emite AUTOMÁTICAMENTE lo que pida
			# el consumidor que haya al final de cada una de sus cintas de salida. No hay nada
			# que elegir, así que la línea lo explica en vez de ofrecer un desplegable. Si no
			# tiene cinta de salida, quien lo dice es el bloque del filtro, unas líneas más
			# abajo, y no hacía falta repetirlo aquí.
			_add_label(vbox, "Emite: lo que pidan sus cintas", Color(0.7, 0.9, 0.7));
		elif material == null:
			_add_label(vbox, "Produce: — (restauración)", Color(0.5, 1.0, 0.5));
		else:
			_add_label(vbox, "Produce: " + str(material));

	var needs = params.get("recieve", null);
	if needs != null:
		_add_label(vbox, "Necesita: " + ", ".join(needs), Color(0.85, 0.75, 0.5));
	else:
		_add_label(vbox, "Sin inputs (generadora)", Color(0.7, 0.9, 0.7));

	var eff_tick = factory_node.getEffectiveTick();
	var base_tick = factory_node.tickTimer;
	var tick_text = "Tick: " + str(eff_tick) + "s";
	if eff_tick != base_tick:
		tick_text += " (base " + str(base_tick) + ")";
	_add_label(vbox, tick_text);

	var eff_output = factory_node.getEffectiveOutput();
	if eff_output > 1:
		_add_label(vbox, "Output: ×" + str(eff_output));

	var pollution = factory_node.getEffectivePollution();
	# Las de restauración rinden por output efectivo (factoryData._tick_restoration)
	if factory_node.factory_type == "restoration":
		pollution *= factory_node.getRestorationScale();
	if pollution > 0:
		_add_label(vbox, "Contaminación: +" + str(snapped(pollution, 0.1)) + "/tick", Color(1.0, 0.5, 0.2));
	elif pollution < 0:
		_add_label(vbox, "Restauración: " + str(snapped(pollution, 0.1)) + "/tick", Color(0.3, 1.0, 0.4));

	if factory_node.workers_needed > 0:
		_build_workers_block(vbox);

	# Sinergias activas. Se pueden enseñar sin mentir porque al demoler se recalculan las 8
	# vecinas (`Main._demolish_at_cell()` → `factoryPlacer.recompute_synergies()`), así que estos
	# tres acumuladores están al día mientras el panel vive.
	var has_synergy = (factory_node.synergy_tick_bonus != 0
		or factory_node.synergy_output_bonus != 0
		or factory_node.synergy_pollution_mult != 1.0);
	if has_synergy:
		_add_label(vbox, "— Sinergias —", Color(0.5, 0.8, 1.0));
		if factory_node.synergy_tick_bonus != 0:
			# Un bonus positivo acelera (resta segundos al tick); uno negativo ralentiza
			var tick_sign = "-" if factory_node.synergy_tick_bonus > 0 else "+";
			_add_label(vbox, "  Tick " + tick_sign + str(abs(factory_node.synergy_tick_bonus)) + "s", Color(0.6, 1.0, 0.6));
		if factory_node.synergy_output_bonus != 0:
			_add_label(vbox, "  Output +" + str(factory_node.synergy_output_bonus), Color(0.6, 1.0, 0.6));
		if factory_node.synergy_pollution_mult != 1.0:
			_add_label(vbox, "  Contam. ×" + str(snapped(factory_node.synergy_pollution_mult, 0.01)), Color(0.6, 1.0, 0.6));

	# Lo que demoler devolvería (Costes M5). Va aquí abajo, después de todo lo que describe a la
	# factoría, porque no habla de lo que hace sino de deshacerla; y antes del bloque de la cinta,
	# que ya no habla de esta factoría sino de la casilla de al lado.
	#
	# Sin recibo no hay línea, y eso NO es un olvido: `getRefund()` devuelve `{}` para lo que
	# nadie pagó —el almacén con el que arranca el mapa, lo que monta la suite— y
	# también omite los materiales cuya mitad es 0. Anunciar «devuelve: 0 de madera» sería
	# ofrecer una devolución que al demoler no llega.
	if not _refund.is_empty():
		_add_label(vbox, "Demoler devuelve: " + _amount_text(_refund), REFUND_COLOR);

	# El filtro de la cinta de salida (M5). Va al final, debajo de todo lo que describe a la
	# factoría, porque no habla de ella sino de la casilla que tiene al lado.
	if _belt_network != null:
		_build_belt_filter_block(vbox);

	# Este panel, al contrario que el tooltip, no se va solo: hay que decir cómo se cierra.
	_add_label(vbox, "ESC o click fuera: cerrar", Color(0.6, 0.6, 0.6));

# ---------- la razón de parada, que es lo único de este panel que cambia sin que nadie lo
# ---------- pulse (M3 del Plan - Feedback de Cuellos de Botella)

# Por qué este panel necesita un `_process()` y el tooltip no: el tooltip nace y muere con el
# ratón, así que una etiqueta estática allí siempre dice la verdad. Este se monta UNA vez en
# `_fill()` y vive hasta que se cierra, repintando solo trozos sueltos ante eventos
# (`_refresh_workers()` al pulsar un botón, `_refresh_belt_filter()` con `belt_network_changed`).
# La razón de parada no tiene ningún evento al que engancharse: la escribe `factoryData.update()`
# desde su Timer, sin señal, porque a 1.300 emisiones por frame una señal es coste sin beneficio
# (el precedente de `pollution_changed`). Así que se mira por frame, que es el mismo criterio que
# siguen el StatusOverlay del mapa y el tinte de casilla.
#
# Y se mira, pero solo se REPINTA cuando la razón cambia. Sin esa comparación el panel remediría
# su alto y se recortaría contra la pantalla sesenta veces por segundo para escribir la misma
# frase.
#
# 🔴 `_factory_node` puede estar demolido con el panel abierto: `Main._demolish_at_cell()` cierra
# el tooltip pero NO este panel, así que aquí llega una factoría liberada. `reason_now()` lo
# comprueba con `is_instance_valid()` y devuelve "", o sea que la línea desaparece sola; el campo
# se pone a null para que tampoco lo lean los botones ni el filtro de cinta, que ya saben vivir
# sin factoría.
func _process(_delta):
	if _blocked_label == null:
		return;
	if _factory_node != null and not is_instance_valid(_factory_node):
		_factory_node = null;
	if BLOCKED.reason_now(_factory_node) != _last_reason:
		_refresh_blocked();

# Repinta la línea con la razón de AHORA. Se llama al montarla, desde `_process()` cuando la
# razón ha cambiado y desde `_refresh_workers()`: el worker que falta se asigna con los botones
# de este mismo panel, así que esa frase tiene que caerse en la pulsación y no en el frame
# siguiente.
func _refresh_blocked():
	if _blocked_label == null:
		return;
	_last_reason = BLOCKED.reason_now(_factory_node);
	var texto = BLOCKED.text_for(_last_reason);
	# Contra "" y jamás contra un texto: `str(null)` devuelve "<null>" y comparar el texto es lo
	# que pintó «Produce: <null>» durante meses en `ui/factoryTooltip.gd`.
	_blocked_label.visible = texto != "";
	if texto != "":
		_blocked_label.text = texto;
		_blocked_label.add_theme_color_override("font_color", BLOCKED.color_for(_last_reason));
	# La línea entra y sale, así que el panel cambia de alto: se vuelve a medir y a recortar
	# contra la pantalla, igual que al asignar un worker.
	if _panel != null:
		_panel.reset_size();
		_reposition();

# `material -> cantidad` en texto, con la MISMA redacción con la que el radial escribe el precio
# (`ui/radialMenu.gd`, `_cost_text()`): «4 wood», y varios materiales separados por comas. Están
# duplicadas porque son dos pantallas sin relación, no porque la redacción sea distinta: si
# cambia una, cambia la otra, y la suite compara las dos salidas.
# `int()` porque las cantidades vienen de un JSON parseado, donde todo número es float: sin ella
# el panel diría «devuelve: 4.0 wood».
func _amount_text(amounts) -> String:
	if not (amounts is Dictionary) or amounts.is_empty():
		return "";
	var partes = [];
	for material in amounts:
		partes.append(str(int(amounts[material])) + " " + str(material));
	return ", ".join(partes);

func _add_label(parent, text, color = Color(0.9, 0.9, 0.9)):
	var lbl = Label.new();
	lbl.text = text;
	lbl.add_theme_color_override("font_color", color);
	lbl.add_theme_font_size_override("font_size", 12);
	parent.add_child(lbl);
	return lbl;

# Desplegable de material: la decisión de QUÉ fabricar, para la factoría que pueda elegirlo.
# Solo se monta cuando hay más de un candidato (`factoryData.hasMaterialChoice()`): un desplegable
# de un elemento no es una decisión, es ruido, y con un candidato el panel sigue enseñando la
# etiqueta «Produce:» de siempre. Hoy lo estrena UNA de las nueve entradas, la `Foundry` con su
# `materials: ["brick", "glass"]` **estático** del JSON (Variedad M3, 2026-09-22), que es el caso
# para el que el campo se diseñó: ahí elegir el destino de la línea ES la jugada, porque el
# checkpoint 4 acepta `brick` y el objetivo final `glass`.
#
# 🔴 El otro caso, el `Storage` con su lista DINÁMICA sacada de la bolsa (2026-09-18), se fue el
# 2026-09-23: el almacén emite lo que le piden los consumidores de sus cintas, así que elegirle
# material a mano dejó de ser una decisión para ser una tarea —volver al panel cada pocos
# segundos— y encima solo podía alimentar a una línea. Con él se fue la única lista que no salía
# del JSON, y este bloque vuelve a servir al caso estático para el que se escribió.
func _build_material_block(vbox, factory_node):
	var row = HBoxContainer.new();
	row.add_theme_constant_override("separation", 4);
	vbox.add_child(row);
	_add_label(row, "Produce:");

	_material_option = OptionButton.new();
	_material_option.add_theme_font_size_override("font_size", 12);
	_material_option.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND;
	for i in range(factory_node.production_candidates.size()):
		_material_option.add_item(_material_text(factory_node.production_candidates[i]), i);
	# Se marca lo que produce AHORA, no el primero de la lista: el panel se abre sobre una factoría
	# que puede llevar rato fabricando otra cosa.
	_material_option.select(factory_node.production_candidates.find(factory_node.production));
	_material_option.item_selected.connect(_on_material_selected);
	row.add_child(_material_option);

# Un candidato `null` (el `material: null` de las de restauración) no se pinta con `str()`, que
# daría el "<null>" que el panel evita desde M0.
# El caso «— (no emitir)» del almacén se fue con su desplegable (2026-09-23): ninguna factoría
# con más de un candidato tiene hoy un `null` entre ellos, y dejar escrito aquí el texto de un
# estado que ya no existe sería exactamente la rama muerta que este panel arrastró una vez.
func _material_text(material):
	if material != null:
		return str(material);
	return "—";

# Cambiar de material es un cambio de DESTINO, no una factoría nueva: `setProduction()` no
# reinicia el `Timer` ni toca `production_debt`, así que la producción fraccionaria que el ahogo
# venía arrastrando sigue donde estaba. Y como el bloque de workers, se repinta in situ: el panel
# NO se remonta desde la señal de uno de sus propios hijos.
func _on_material_selected(index):
	if _factory_node == null or _material_option == null:
		return;
	var candidates = _factory_node.production_candidates;
	if index < 0 or index >= candidates.size():
		return;
	_factory_node.setProduction(candidates[index]);
	# Se vuelve a marcar lo que la factoría produce DE VERDAD: si `setProduction()` hubiera
	# rechazado el candidato, el desplegable se quedaría enseñando una mentira.
	_material_option.select(candidates.find(_factory_node.production));
	# El texto del botón cambia de ancho con el material elegido, así que el panel cambia de tamaño
	# y hay que recortarlo otra vez contra la pantalla, igual que al asignar un worker.
	if _panel != null:
		_panel.reset_size();
		_reposition();

# ---------- el filtro de la cinta de salida (M5) ----------

# Los materiales que pueden viajar por una cinta, sacados del JSON y no de una lista escrita a
# mano: todo material no nulo que alguna entrada de `Factories` sepa fabricar, menos las dos
# excepciones de siempre —`worker` y `factory_token` no viajan por cinta, los intercepta Main
# antes de la red—. Ordenados, para que el desplegable no cambie de orden entre aperturas.
#
# 🔴 SE LEE `materials: [...]` Y NO SOLO `material` (Variedad M3, 2026-09-22). El `glass` de la
# `Foundry` es el primer material del juego que NINGUNA entrada declara como su `material`: vive
# solo en la lista de candidatos. Leyendo únicamente `material`, el desplegable del filtro no lo
# ofrecería jamás y el jugador que acaba de cambiar su fundición a vidrio no podría encaminarlo
# —el resto de la red sí lo mueve, porque `deliver()` es genérico por material—. Es la misma
# clase de excepción por material contra la que el M1 dejó su red de pruebas.
# El contrato es el de siempre: `materials` es opcional y su ausencia significa `[material]`.
func _belt_filter_materials():
	var mats = [];
	if _file_data == null:
		return mats;
	for nombre in _file_data.get("Factories", {}):
		var entrada = _file_data["Factories"][nombre];
		var candidatos = entrada.get("materials", null);
		if candidatos == null or candidatos.is_empty():
			candidatos = [entrada.get("material", null)];
		for m in candidatos:
			if m == null or mats.has(m):
				continue;
			if _factory_node != null and _factory_node.BELT_EXCLUDED_MATERIALS.has(m):
				continue;
			mats.append(m);
	mats.sort();
	return mats;

# El control del filtro. La cinta que se edita es la de SALIDA de esta factoría —el segmento
# cuyo `dir_in` apunta a su casilla, el mismo con el que arranca deliver()—, que es la que el
# jugador tiene en la cabeza al abrir el panel de la factoría que emite. Filtrar ese primer
# segmento basta para cortar la línea entera: deliver() comprueba el filtro de cada tramo que
# recorre, así que si el primero rechaza, no hay entrega.
func _build_belt_filter_block(vbox):
	_add_label(vbox, "— Cinta de salida —", Color(0.5, 0.8, 1.0));

	_belt_row = HBoxContainer.new();
	_belt_row.add_theme_constant_override("separation", 4);
	vbox.add_child(_belt_row);
	_add_label(_belt_row, "Solo deja pasar:");

	_belt_option = OptionButton.new();
	_belt_option.add_theme_font_size_override("font_size", 12);
	_belt_option.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND;
	# El índice 0 es SIEMPRE "" = acepta todo, que es con lo que nace un segmento y el valor
	# por defecto que pide el plan. Los materiales van detrás, en el orden del JSON ordenado.
	_belt_option.add_item("Todo (sin filtro)", 0);
	var mats = _belt_filter_materials();
	for i in range(mats.size()):
		_belt_option.add_item(str(mats[i]), i + 1);
	_belt_option.item_selected.connect(_on_belt_filter_selected);
	_belt_row.add_child(_belt_option);

	# Sin cinta de salida no hay nada que filtrar, y decirlo es más útil que un desplegable
	# apagado: el jugador sabe que lo que le falta es tender la cinta.
	_belt_none_label = _add_label(vbox, "Sin cinta de salida", Color(0.7, 0.7, 0.7));

	_refresh_belt_filter();

# Repinta el bloque con el estado de la red AHORA. Se llama al montarlo, tras cada cambio de
# filtro y desde `belt_network_changed`. No recrea ningún nodo —solo cambia visibilidad y
# selección—, así que no hay trampa de `queue_free()` diferido que sortear.
func _refresh_belt_filter():
	if _belt_option == null or _factory_node == null or _belt_network == null:
		return;
	var seg = _belt_network.output_segment(_factory_node.cell_position);
	_belt_cell = seg.cell if seg != null else null;
	var hay_cinta = seg != null;
	_belt_row.visible = hay_cinta;
	_belt_none_label.visible = not hay_cinta;
	if hay_cinta:
		# select() NO emite `item_selected`, así que esto no se muerde la cola con
		# _on_belt_filter_selected() ni con la señal de la red que ese handler dispara.
		var idx = _belt_option.get_item_count() - 1;
		while idx > 0 and _belt_option.get_item_text(idx) != seg.filter:
			idx -= 1;
		_belt_option.select(idx);
	if _panel != null:
		_panel.reset_size();
		_reposition();

func _on_belt_filter_selected(index):
	if _belt_network == null or _belt_cell == null or _belt_option == null:
		return;
	# El 0 es «Todo»: el filtro vuelve a "" y la cinta acepta cualquier cosa otra vez.
	var material = "" if index <= 0 else _belt_option.get_item_text(index);
	_belt_network.set_belt_filter(_belt_cell, material);
	# set_belt_filter() emite `belt_network_changed` y eso ya nos repinta, pero solo si de
	# verdad ha cambiado algo: se repinta aquí también para no depender de ese detalle.
	_refresh_belt_filter();

# La red ha cambiado con el panel abierto (se ha tendido o borrado una cinta, o ha cambiado un
# filtro). Lo que este panel enseña de la red es el bloque del filtro, y nada más: el resto
# describe a la factoría, que la red no toca.
func _on_belt_network_changed():
	_refresh_belt_filter();

# Bloque de workers: el estado, los dos botones y el aviso de inactiva. Es lo único del panel que
# cambia sin volver a abrirlo, así que sus nodos se guardan y se refrescan in situ. El panel NO se
# remonta al pulsar: un botón que reconstruyera el panel desde su propia señal `pressed` estaría
# liberando el nodo que está emitiendo, que es exactamente el crash del que avisa el plan.
#
# Granularidad: cada pulsación mueve UN worker, no el bloque entero. Lo decide el escenario que el
# hito viene a resolver —«quitarle un worker a la MetaFactory y dárselo» a la WoodProcessing—: con
# dos workers en total, una factoría de 2 y otra de 1, moviendo bloques enteros no hay forma de
# expresarlo. La asignación sigue siendo todo-o-nada donde siempre lo fue (`factoryPlacer.build()`
# solo asigna si caben los `workers_needed`); aquí se reparte a mano, que es la carencia.
func _build_workers_block(vbox):
	_workers_label = _add_label(vbox, "");

	var row = HBoxContainer.new();
	row.add_theme_constant_override("separation", 4);
	vbox.add_child(row);

	_btn_unassign = _add_button(row, "− 1 worker", _on_unassign_pressed);
	_btn_assign = _add_button(row, "+ 1 worker", _on_assign_pressed);

	# Aquí vivía `⚠ INACTIVA (sin workers)`, que M3 ha SUSTITUIDO por la línea de parada de
	# debajo del título: decía exactamente el mismo estado —la razón "workers"— con otras
	# palabras, en otro sitio y en otro color (rojo, el que el mapa reserva para el ahogo). Dos
	# avisos de una sola cosa, y dos vocabularios de color para un solo estado. La regla que
	# heredó de él —montada siempre, enseñada cuando toca— sigue en pie, que es lo que hace
	# barato que el panel cambie de alto.
	# La bolsa, aquí mismo: es el número que decide si «+ 1 worker» puede hacer algo, y el HUD
	# queda detrás del fondo del panel.
	_free_label = _add_label(vbox, "", Color(0.7, 0.7, 0.7));

	_refresh_workers();

func _add_button(parent, text, handler):
	var btn = Button.new();
	btn.text = text;
	btn.add_theme_font_size_override("font_size", 12);
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND;
	btn.pressed.connect(handler);
	parent.add_child(btn);
	return btn;

# Repinta el bloque con los contadores de ahora mismo. Se llama al montarlo y después de cada
# pulsación; nada más del panel cambia, así que nada más se toca.
func _refresh_workers():
	if _workers_label == null or _factory_node == null:
		return;
	var activa = _factory_node.isActive();
	_workers_label.text = ("Workers: " + str(_factory_node.workers_assigned)
		+ "/" + str(_factory_node.workers_needed));
	_workers_label.add_theme_color_override("font_color",
		Color(0.3, 1.0, 0.4) if activa else Color(1.0, 0.3, 0.3));
	# La razón de parada se repinta AQUÍ y no en el `_process()` del frame siguiente: el worker
	# que falta se asigna con estos botones, y la frase que dice «le faltan workers» tiene que
	# caerse en la misma pulsación que la arregla o el panel se contradiría a sí mismo dos
	# líneas más arriba.
	_refresh_blocked();

	var libres = _bag.getFreeWorkers() if _bag != null else 0;
	_free_label.text = "Libres en la bolsa: " + str(libres);
	# Apagar «+ 1 worker» sin libres no es cosmética: `Bag.assignWorkers()` clampa contra
	# `workers_total` pero no sabe nada de esta factoría, así que pulsarlo con la bolsa vacía
	# subiría el contador global sin que la factoría recibiera nada y los dos dejarían de cuadrar.
	# Y por encima de `workers_needed` el worker no haría nada: la factoría ya está activa.
	_btn_assign.disabled = (_bag == null or libres <= 0
		or _factory_node.workers_assigned >= _factory_node.workers_needed);
	_btn_unassign.disabled = (_bag == null or _factory_node.workers_assigned <= 0);

	# El aviso entra y sale, así que el panel cambia de alto: se vuelve a medir y a recortar
	# contra la pantalla, que es para lo que existe _reposition().
	if _panel != null:
		_panel.reset_size();
		_reposition();

# Mueve UN worker de la bolsa a la factoría. Los dos contadores —`Bag.workers_assigned` y
# `factoryData.workers_assigned`— se mueven SIEMPRE juntos: es la invariante que mantienen
# `factoryPlacer.build()` al construir y `Main._demolish_at_cell()` al demoler, y romperla duplica
# o pierde workers para el resto de la run. No se duplica el clamp de `Bag.gd`, pero sí se
# comprueba antes que hay un worker libre que mover. Devuelve true si se movió.
func assign_one():
	if _factory_node == null or _bag == null:
		return false;
	if _factory_node.workers_assigned >= _factory_node.workers_needed:
		return false;
	if _bag.getFreeWorkers() <= 0:
		return false;
	_bag.assignWorkers(1);
	_factory_node.workers_assigned += 1;
	return true;

# Devuelve UN worker a la bolsa. Si con eso la factoría baja de `workers_needed`, deja de producir
# ella sola: `factoryData.update()` sale por `isActive()` en su primera línea, así que no hay que
# parar su Timer ni avisar a nadie.
func unassign_one():
	if _factory_node == null or _bag == null:
		return false;
	if _factory_node.workers_assigned <= 0:
		return false;
	_bag.unassignWorkers(1);
	_factory_node.workers_assigned -= 1;
	return true;

func _on_assign_pressed():
	if assign_one():
		_refresh_workers();

func _on_unassign_pressed():
	if unassign_one():
		_refresh_workers();

# El panel se abre donde se hizo click, en coordenadas de viewport —el mismo criterio que el
# tooltip; con la cámara fija coinciden con las de mundo—. La diferencia es que este no desaparece
# al mover el ratón: uno abierto medio fuera de la pantalla se queda ahí, y por eso se recorta.
func _reposition():
	var limit = get_viewport().get_visible_rect().size - _panel.size - Vector2(MARGIN, MARGIN);
	_panel.position = Vector2(
		clamp(_wanted_pos.x, MARGIN, max(MARGIN, limit.x)),
		clamp(_wanted_pos.y, MARGIN, max(MARGIN, limit.y)));

func _on_bg_input(event):
	if event is InputEventMouseButton and event.pressed:
		queue_free();

func _unhandled_input(event):
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		queue_free();
