extends CanvasLayer

signal factory_chosen(type, cell);

var _cell = Vector2i(0, 0);

# El botón ya no se dimensiona por su propio texto: el contenido son labels hijas, para poder
# pintar la sinergia en verde sin teñir también el nombre (que lleva el color de contaminación).
# Por eso el alto se calcula contando líneas, y la línea más larga es la que fija el ancho,
# porque una Label no se recorta y se saldría del panel.
const LINE_HEIGHT = 16;
# 🔴 EL ANCHO BAJA DE 130 A 112 (Variedad M4b, 2026-09-22), y es la mitad barata del arreglo del
# solape. Medido con la fuente del juego —el proyecto no declara tema propio— al tamaño 11 con el
# que este menú pinta sus labels: la línea más ancha que el radial SABE escribir es
# «✦ Mejora 2 vecinas», **101 px**, y la siguiente «✖ Coste: 10 wood», **93 px**. Con 112 quedan
# 11 px de holgura sobre la peor y ningún texto se recorta —que es la condición que no se podía
# romper: el bug era de click ambiguo, no de lectura—. Los 18 px que se ahorran a lo ancho son
# 18 px que el radio de la corona no tiene que crecer.
const BUTTON_WIDTH = 112;
const BUTTON_PADDING = 18;
# 🔴 EL RADIO YA NO ES UNA CONSTANTE: esto es su SUELO (Variedad M4b, 2026-09-22). Con seis
# opciones los centros vecinos distaban estos 118 px, pero en diagonal solo se separaban **102 px
# en horizontal** contra los 130 del botón, así que **cuatro pares** se montaban con una franja
# de **28 px** (`WoodCutter`×`WoodProcessing` 28×15, `WoodCutter`×`WaterTreatment` 28×23,
# `Quarry`×`Foundry` 28×31, `Foundry`×`Reforester` 28×23) — y con siete y con ocho opciones era
# peor (5 pares, el peor 28×66; y 6 pares, el peor 47×47). Ningún TEXTO pisaba a otro: lo que se
# montaba eran las cajas, el botón dibujado después tapaba al anterior y esa franja era **zona de
# click ambiguo**. El radio de verdad lo calcula `_ring_radius()` sobre los rectángulos reales, y
# este número es solo lo que nunca baja: con cuatro y cinco opciones la corona es la de siempre.
const MIN_RADIUS = 118.0;
# El hueco LIMPIO que se exige entre dos botones, además de no tocarse: dos cajas que se besan se
# ven como una sola y el click de la frontera vuelve a ser ambiguo.
const BUTTON_GAP = 6.0;
# Lo que se respeta de borde de ventana al meter la corona dentro (ver `_fit_shift()`).
const SCREEN_MARGIN = 8.0;
# La resolución del proyecto, que es contra la que se mide si la corona cabe cuando el menú
# todavía no cuelga de un viewport (la suite monta radiales sueltos).
const FALLBACK_SCREEN = Vector2(1280, 720);
const SYNERGY_COLOR = Color(0.6, 1.0, 0.6);
# El dinero (Costes M5). `PRICE_COLOR` es el mismo tono con el que `ui/factoryPanel.gd` escribe
# la devolución al demoler: el precio se lee igual en las dos superficies, o parecerían dos
# mecánicas distintas. Es deliberadamente un tono apagado y NO naranja ni verde, porque esos dos
# ya significan otra cosa en este botón —el nombre va naranja si la factoría contamina y verde si
# limpia—, y tampoco el verde claro de las sinergias.
const PRICE_COLOR = Color(0.85, 0.82, 0.6);
# Y el precio que no se puede pagar, en rojo: es el «no» que ya usa el panel para la factoría
# inactiva. Va acompañado de un «✖» a propósito, para que el rechazo no dependa solo del color.
const UNAFFORDABLE_PRICE_COLOR = Color(1.0, 0.45, 0.45);
# Lo que atenúa una opción impagable: se baja el ALFA y se conserva el tono, así que el código de
# color de arriba sigue leyéndose (apagado) en vez de quedar pisado por un gris plano.
const DIMMED_ALPHA = 0.35;

# `affordable` es `tipo -> bool` y va al final con default, por lo mismo que `synergy_preview`:
# quien no sepa de dinero (la suite) sigue montando el menú de siempre, y la ausencia
# de una clave significa «se puede pagar». El precio, en cambio, NO viaja por aquí: sale de
# `file_data`, que es el mismo sitio del que cobra `factoryPlacer.build()` — dos fuentes para el
# precio serían dos verdades, y la que el jugador lee sería la falsa.
func initialize(available_factories, file_data, cell, screen_pos, synergy_preview = {}, affordable = {}):
	_cell = cell;
	layer = 10;

	var root = Control.new();
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);
	add_child(root);

	# Fondo semi-transparente: click en él cierra el menú
	var bg = ColorRect.new();
	bg.color = Color(0, 0, 0, 0.25);
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);
	bg.mouse_filter = Control.MOUSE_FILTER_STOP;
	bg.gui_input.connect(_on_bg_input);
	root.add_child(bg);

	# Label central
	var lbl = Label.new();
	lbl.text = "Construir";
	lbl.add_theme_color_override("font_color", Color.YELLOW);
	lbl.add_theme_font_size_override("font_size", 13);
	lbl.position = screen_pos + Vector2(-30, -10);
	root.add_child(lbl);

	# 🔴 PRIMERO EL CONTENIDO Y DESPUÉS DÓNDE VA (Variedad M4b). El alto de cada botón sale de
	# cuántas líneas escribe, y el radio de la corona sale de esos altos: calcular el sitio antes
	# de saber el tamaño es exactamente lo que dejaba cuatro pares montados con seis opciones.
	var n = available_factories.size();
	var contenidos = [];
	var alturas = [];
	for i in range(n):
		var datos = _button_lines(available_factories[i], file_data, synergy_preview, affordable);
		contenidos.append(datos);
		alturas.append(float(BUTTON_PADDING + datos["lines"].size() * LINE_HEIGHT));
	var radius = _ring_radius(alturas);
	var rects = [];
	for i in range(n):
		var angle = (2.0 * PI * i / float(n)) - PI / 2.0;
		var tam = Vector2(BUTTON_WIDTH, alturas[i]);
		var centro = screen_pos + Vector2(cos(angle) * radius, sin(angle) * radius);
		rects.append(Rect2(centro - tam / 2.0, tam));
	# Y la corona entera se mete en la ventana si se salía. Es una TRASLACIÓN y no un recolocado:
	# mover todos los botones lo mismo no cambia ni una distancia entre dos de ellos, así que el
	# «ningún par se solapa» que acaba de calcularse sobrevive intacto. La etiqueta «Construir»
	# NO se mueve: marca la casilla sobre la que se va a construir, y desplazarla apuntaría a otra.
	var shift = _fit_shift(rects);

	for i in range(n):
		var factory_name = available_factories[i];
		var lines = contenidos[i]["lines"];
		var afford = contenidos[i]["afford"];
		var precio_desde = contenidos[i]["precio_desde"];
		var precio_hasta = contenidos[i]["precio_hasta"];

		var btn = Button.new();
		btn.custom_minimum_size = rects[i].size;
		btn.size = rects[i].size;
		btn.position = rects[i].position + shift;
		# Atenuar no basta: el hito pide que la opción impagable TAMPOCO se pueda elegir.
		# `disabled` se come el click, el cursor deja de prometer una acción, y la señal ni
		# siquiera se conecta —tres capas, y ninguna es la de verdad: el rechazo que manda sigue
		# siendo el de `Main._on_factory_chosen()`, que revalida el dinero al elegir porque entre
		# abrir el menú y pulsar la bolsa puede haber cambiado—.
		btn.disabled = not afford;
		btn.mouse_default_cursor_shape = (Control.CURSOR_POINTING_HAND if afford
			else Control.CURSOR_ARROW);
		if afford:
			btn.pressed.connect(_on_factory_pressed.bind(factory_name));
		root.add_child(btn);

		# Las labels van dentro del botón e ignoran el ratón: el click sigue siendo del botón.
		var vbox = VBoxContainer.new();
		vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);
		vbox.alignment = BoxContainer.ALIGNMENT_CENTER;
		vbox.add_theme_constant_override("separation", 0);
		vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE;
		btn.add_child(vbox);
		for idx in range(lines.size()):
			var l = Label.new();
			l.text = lines[idx][0];
			# 🔴 El `disabled` del botón NO tiñe estas labels: llevan su propio
			# `font_color` override y el tema solo apaga el texto del propio Button, que aquí
			# está vacío. Si la atenuación no se hace a mano, una opción impagable se ve igual
			# de disponible que las demás.
			var col = lines[idx][1];
			if not afford and (idx < precio_desde or idx >= precio_hasta):
				col = Color(col.r, col.g, col.b, DIMMED_ALPHA);
			l.add_theme_color_override("font_color", col);
			l.add_theme_font_size_override("font_size", 11);
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER;
			l.mouse_filter = Control.MOUSE_FILTER_IGNORE;
			vbox.add_child(l);

# Lo que un botón escribe, en orden y con su color, sin decidir todavía dónde cae: devuelve
# `lines` (pares texto/color), si la opción se puede pagar y el RANGO de líneas del precio, que es
# lo único que no se atenúa cuando no se puede pagar.
func _button_lines(factory_name, file_data, synergy_preview, affordable) -> Dictionary:
	var params = file_data["Factories"].get(factory_name, {});
	# Las de restauración declaran `material: null` en el JSON, y str(null) es "<null>": sin
	# esta comprobación el botón anuncia «→ <null>» en vez de «(restauración)», que es lo que
	# la rama de abajo lleva queriendo decir desde siempre.
	var material_raw = params.get("material");
	var material = "—" if material_raw == null else str(material_raw);
	var pollution_val = float(params.get("pollution", 0.0));
	var w_needed = int(params.get("workers_needed", 0));

	var name_color = Color(0.9, 0.9, 0.9);
	if pollution_val > 0:
		name_color = Color(1.0, 0.6, 0.3);
	elif pollution_val < 0:
		name_color = Color(0.4, 1.0, 0.5);

	var lines = [[factory_name, name_color]];
	if material != "—":
		lines.append(["→ " + material, name_color]);
	else:
		lines.append(["(restauración)", name_color]);
	if w_needed > 0:
		lines.append(["⚙ " + str(w_needed) + "W", name_color]);
	# Lo que cuesta, justo debajo de los workers: las dos líneas dicen lo mismo —lo que hay
	# que poner— y leerlas juntas es lo que convierte el menú en una decisión de compra.
	# Va ANTES de las sinergias, que son lo que se gana y cierran la lectura.
	var afford = bool(affordable.get(factory_name, true));
	var precio_lineas = _cost_lines(params.get("cost", null), afford);
	# Las líneas que NO se atenúan cuando la opción es impagable: son la razón por la que
	# el botón está apagado, y apagarlas también dejaría el rechazo sin explicación. Es un
	# RANGO y ya no un índice porque el precio ocupa una línea POR MATERIAL (ver _cost_lines).
	var precio_desde = lines.size();
	if precio_lineas.is_empty():
		# `cost` es OPCIONAL en el JSON y su ausencia significa gratis. Se dice con todas las
		# letras en vez de callar la línea: una opción sin precio y una opción cuyo precio no
		# se ha pintado se ven igual, y este hito existe precisamente para que no se vean igual.
		lines.append(["Gratis", PRICE_COLOR]);
	else:
		for texto in precio_lineas:
			lines.append([texto, UNAFFORDABLE_PRICE_COLOR if not afford else PRICE_COLOR]);
	var precio_hasta = lines.size();
	# Lo que se gana construyendo AQUÍ, que es la decisión que este menú toma.
	for texto in _synergy_lines(synergy_preview.get(factory_name, {})):
		lines.append([texto, SYNERGY_COLOR]);

	return {
		"lines": lines,
		"afford": afford,
		"precio_desde": precio_desde,
		"precio_hasta": precio_hasta,
	};

# 🔴 EL RADIO DE LA CORONA, CALCULADO Y NO PUESTO A OJO (Variedad M4b, 2026-09-22). Es el arreglo
# del defecto que se veía en `capturas/5_radial_seis_opciones.png`.
#
# Dos rectángulos se solapan si y solo si se solapan en los DOS ejes, así que a cada par de
# botones le basta con separarse en UNO: o sus centros distan `BUTTON_WIDTH + BUTTON_GAP` en
# horizontal, o distan la media de sus dos altos (más el hueco) en vertical. Repartidos en
# corona, las dos distancias crecen LINEALMENTE con el radio —`dx = r·|Δcos|`, `dy = r·|Δsen|`—,
# o sea que el radio que le hace falta a un par es exactamente
# `min(ancho/|Δcos|, medioAlto/|Δsen|)` y el del menú entero es el MAYOR de todos. Cerrado y
# exacto: no se busca a tientas y no hay constante mágica que re-anclar cuando una factoría nueva
# añada una línea a su botón.
#
# Por qué el alto entra en la cuenta y no solo el ancho: los dos botones que caen a la misma x
# —el de las 2 y el de las 4 en punto con seis opciones— no se separan NADA en horizontal, y lo
# único que los mantiene apartados es lo altos que sean. Un arreglo que solo mirase el ancho los
# dejaría montados en cuanto un botón creciera de líneas.
#
# Lo que devuelve con el JSON de hoy, medido: de 2 a 5 opciones **118** (el suelo: la corona es
# exactamente la de siempre), 6 → **136**, 7 → **151**, 8 → **167** —ocho es el techo real, que
# es lo que el jugador puede llegar a tener desbloqueado: las nueve entradas menos el `Storage`,
# que no se elige— y 9 → **218**. Con seis, el radio efectivo pasa de `118 + 65 = 183` px a
# `136 + 56 = 192`: **nueve píxeles**, no una corona nueva, y eso es exactamente lo que compra
# bajar `BUTTON_WIDTH` a la vez que se sube el radio. Las envolventes miden 348×355 (6),
# 406×369 (7) y 446×400 (8): las tres caben de sobra en los 1280×720 del proyecto.
func _ring_radius(heights: Array) -> float:
	var n = heights.size();
	var radius = MIN_RADIUS;
	if n < 2:
		return radius;
	for i in range(n):
		var ai = (2.0 * PI * i / float(n)) - PI / 2.0;
		for j in range(i + 1, n):
			var aj = (2.0 * PI * j / float(n)) - PI / 2.0;
			var dcos = abs(cos(ai) - cos(aj));
			var dsen = abs(sin(ai) - sin(aj));
			# Un eje en el que los dos centros coinciden (Δ = 0) no separa nunca, por mucho que
			# crezca el radio: ese camino no existe para este par y se descarta con INF.
			var por_ancho = INF;
			if dcos > 0.0001:
				por_ancho = (float(BUTTON_WIDTH) + BUTTON_GAP) / dcos;
			var por_alto = INF;
			if dsen > 0.0001:
				por_alto = (0.5 * (float(heights[i]) + float(heights[j])) + BUTTON_GAP) / dsen;
			radius = max(radius, min(por_ancho, por_alto));
	return radius;

# Cuánto hay que MOVER la corona entera para que no se salga de la ventana. Es una traslación y
# nada más: mover todos los botones lo mismo no cambia ninguna distancia entre dos de ellos, así
# que lo que `_ring_radius()` garantiza sigue garantizado. Hace falta porque el radio ya no es
# fijo —con ocho opciones son 167 px más medio botón— y porque el menú nace donde está el ratón,
# que puede ser el borde del mapa: un botón fuera de la ventana no se puede pulsar, y ése es el
# mismo gesto roto que este hito viene a quitar. Si ni trasladada cabe, se deja donde estaba:
# media corona visible es mejor que una corona movida que tampoco cabe.
func _fit_shift(rects: Array) -> Vector2:
	if rects.is_empty():
		return Vector2.ZERO;
	var caja = rects[0];
	for i in range(1, rects.size()):
		caja = caja.merge(rects[i]);
	var pantalla = FALLBACK_SCREEN;
	if is_inside_tree() and get_viewport() != null:
		pantalla = Vector2(get_viewport().get_visible_rect().size);
	var shift = Vector2.ZERO;
	if caja.size.x + 2.0 * SCREEN_MARGIN <= pantalla.x:
		if caja.position.x < SCREEN_MARGIN:
			shift.x = SCREEN_MARGIN - caja.position.x;
		elif caja.end.x > pantalla.x - SCREEN_MARGIN:
			shift.x = pantalla.x - SCREEN_MARGIN - caja.end.x;
	if caja.size.y + 2.0 * SCREEN_MARGIN <= pantalla.y:
		if caja.position.y < SCREEN_MARGIN:
			shift.y = SCREEN_MARGIN - caja.position.y;
		elif caja.end.y > pantalla.y - SCREEN_MARGIN:
			shift.y = pantalla.y - SCREEN_MARGIN - caja.end.y;
	return shift;

# Cada material del precio por separado —«8 wood»—, que es la MISMA redacción con la que
# `ui/factoryPanel.gd` escribe la devolución al demoler (`_amount_text()`, allí). De aquí salen
# las dos presentaciones: la del botón, una línea por material, y la de una sola línea con
# comas que sigue usando el panel.
#
# `int()` sobre la cantidad no es cosmética: `JSON.parse_string()` devuelve todo número como
# float, así que sin ella el botón anunciaría «Coste: 8.0 wood». Y un `cost` ausente o que no
# sea diccionario devuelve la lista vacía, que es lo que el llamante lee como «gratis».
func _cost_parts(cost) -> Array:
	var partes = [];
	if not (cost is Dictionary) or cost.is_empty():
		return partes;
	for material in cost:
		partes.append(str(int(cost[material])) + " " + str(material));
	return partes;

# 🔴 EL PRECIO OCUPA UNA LÍNEA POR MATERIAL, y no una sola con comas (Variedad M0, 2026-09-20).
# El `cost` mixto que estrenan `Foundry` (6 wood + 12 stone) y `WaterTreatment` (4 wood + 8
# stone) no cabe de una tirada: «✖ Coste: 6 wood, 12 stone» mide 138 px contra los 130 que
# `BUTTON_WIDTH` valía entonces (112 desde el M4b), y una Label no se recorta — se saldría del
# botón. Se parte, y el botón crece
# a lo alto, que es barato: el alto sale de `lines.size()` y el ancho es el que fija el radio.
# El primer material se queda EN la línea del «Coste:» a propósito: así un precio de un solo
# material —los seis de siempre— sigue siendo exactamente una línea y ningún botón engorda por
# una factoría que no es la suya.
func _cost_lines(cost, afford = true) -> Array:
	var partes = _cost_parts(cost);
	if partes.is_empty():
		return [];
	# El «✖» acompaña al color rojo a propósito: el rechazo no depende solo del color.
	var lineas = [("Coste: " if afford else "✖ Coste: ") + str(partes[0])];
	for i in range(1, partes.size()):
		lineas.append(str(partes[i]));
	return lineas;

# La redacción de una sola línea, la que el panel usa para la devolución. Se conserva aquí
# porque es la que la suite compara contra `factoryPanel._amount_text()`: dos redacciones
# distintas para lo mismo se leerían como dos mecánicas distintas.
func _cost_text(cost) -> String:
	return ", ".join(_cost_parts(cost));

# Redacta lo que `factoryPlacer.preview_synergies()` ha calculado para esta casilla. El
# vocabulario es el del tooltip de una factoría ya colocada (`ui/factoryTooltip.gd`): es la misma
# información, solo que a tiempo, y dos redacciones distintas para lo mismo se leerían como dos
# mecánicas distintas. Sin sinergias devuelve vacío, y la casilla aislada no anuncia nada.
func _synergy_lines(preview) -> Array:
	var lines = [];
	if preview == null or preview.is_empty():
		return lines;
	var tick = int(preview.get("tick_bonus", 0));
	if tick != 0:
		# Un bonus positivo acelera (le resta segundos al tick); uno negativo ralentiza.
		var tick_sign = "-" if tick > 0 else "+";
		lines.append("✦ Tick " + tick_sign + str(abs(tick)) + "s");
	var out_bonus = int(preview.get("output_bonus", 0));
	if out_bonus != 0:
		lines.append("✦ Output " + ("+" if out_bonus > 0 else "") + str(out_bonus));
	var mult = float(preview.get("pollution_mult", 1.0));
	if mult != 1.0:
		lines.append("✦ Contam. ×" + str(snapped(mult, 0.01)));
	var gives = int(preview.get("gives_to", 0));
	if gives > 0:
		lines.append("✦ Mejora " + str(gives) + (" vecina" if gives == 1 else " vecinas"));
	return lines;

func _on_factory_pressed(factory_type):
	factory_chosen.emit(factory_type, _cell);
	queue_free();

func _on_bg_input(event):
	if event is InputEventMouseButton and event.pressed:
		queue_free();

func _unhandled_input(event):
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		queue_free();
