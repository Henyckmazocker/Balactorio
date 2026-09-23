extends CanvasLayer

# La razón de parada en palabras, compartida con `ui/factoryPanel.gd`: las dos superficies de
# detalle dicen la misma frase con el mismo color, y ese color es el del marcador del mapa.
const BLOCKED = preload("res://ui/blockedReason.gd");

# 🔴 EL MARGEN DEL MARCO (Variedad M4b, 2026-09-22). El `panel` del tema por defecto de Godot
# trae los cuatro `content_margin` a **0**, y un PanelContainer estira su hijo a todo lo que el
# marco mide: medido, el tooltip salía con `marco 144 px` contra una línea de `144 px`, o sea
# **0 px de aire a cada lado**. Con la depuradora del M4 la línea más ancha que estas superficies
# saben escribir pasó a ser `⚠ Parada: sin insumo — tiéndele cinta de entrada`, **289 px**, que
# llenaba el marco de borde a borde y hacía que el texto pareciera salirse. Se mete por un
# `MarginContainer` y no tocando el `StyleBox` del tema a propósito: duplicar el stylebox
# arrastraría también su fondo y su borde, que son del tema y no de esta pantalla.
const MARGIN_H = 8;
const MARGIN_V = 5;

var _panel;

func initialize(factory_node, file_data):
	layer = 5;

	_panel = PanelContainer.new();
	add_child(_panel);

	var margen = MarginContainer.new();
	margen.add_theme_constant_override("margin_left", MARGIN_H);
	margen.add_theme_constant_override("margin_right", MARGIN_H);
	margen.add_theme_constant_override("margin_top", MARGIN_V);
	margen.add_theme_constant_override("margin_bottom", MARGIN_V);
	_panel.add_child(margen);

	var vbox = VBoxContainer.new();
	vbox.add_theme_constant_override("separation", 3);
	margen.add_child(vbox);

	var params = file_data["Factories"].get(factory_node.type, {});

	_add_label(vbox, factory_node.type, Color(1.0, 0.9, 0.2));

	# Por qué está parada, en una frase y con la acción dentro (M3). Va justo debajo del título
	# porque es la pregunta con la que el ratón se ha quedado quieto encima: todo lo demás
	# describe a la factoría, y esto dice qué hacer con ella.
	# La que produce no enseña NADA de esto: el silencio significa que va bien, igual que en el
	# mapa. Se pregunta contra "" y no contra un texto, que es la trampa que documenta el bloque
	# de «Produce:» de aquí abajo.
	# Aquí la etiqueta SÍ es estática, al revés que en el panel, pero no porque el tooltip diga
	# la verdad para siempre: M3 lo razonó así —«nace y muere con el ratón»— y M4 lo desmintió
	# con una captura, el tooltip abierto sin «Parada» sobre una casilla con el marcador rojo
	# pintado. El tooltip muere cuando el ratón se va a OTRA casilla, no cuando el estado cambia.
	# Quien lo mantiene al día es `Main._update_hover_tooltip()`, que compara por frame la razón
	# de ahora con la que pintó y RECONSTRUYE el nodo entero cuando cambia. O sea: este
	# `initialize()` no necesita repintarse porque quien lo llama lo vuelve a llamar, no porque el
	# estado no se mueva. Si alguien le quita esa comparación, la etiqueta vuelve a mentir.
	var razon = BLOCKED.reason_now(factory_node);
	if BLOCKED.text_for(razon) != "":
		_add_label(vbox, BLOCKED.text_for(razon), BLOCKED.color_for(razon));

	# Se lee `production` de la FACTORÍA, no `material` del JSON: desde M2 una factoría puede
	# cambiar qué fabrica (`factoryData.setProduction()`), y el JSON solo declara con qué se
	# COLOCA. Leyendo el JSON, el tooltip de una factoría multi-material enseñaría siempre el
	# material por defecto en vez del elegido. `production` arranca valiendo `material`, así que
	# para las cinco factorías de hoy no cambia nada.
	# Y se compara contra `null`, NO contra el texto "null": `str(null)` devuelve "<null>", así que
	# la comparación de texto nunca acertaba, la rama de restauración era código muerto y el
	# tooltip del Reforester pintaba literalmente «Produce: <null>». Mismo criterio que
	# `ui/factoryPanel.gd:87-91`.
	var material = factory_node.production;
	if material == null:
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
		var w_text = "Workers: " + str(factory_node.workers_assigned) + "/" + str(factory_node.workers_needed);
		var w_color = Color(0.3, 1.0, 0.4) if factory_node.isActive() else Color(1.0, 0.3, 0.3);
		_add_label(vbox, w_text, w_color);
		# Aquí vivía `⚠ INACTIVA (sin workers)`, que M3 ha SUSTITUIDO por la línea de arriba:
		# decía exactamente el mismo estado —la razón "workers"— con otras palabras, en otro
		# sitio y en otro color (rojo, el que el mapa reserva para el ahogo), así que dejarlos
		# convivir era darle al jugador dos avisos de una sola cosa y dos vocabularios de color
		# para el mismo estado. El contador «Workers: 0/1» en rojo se queda: eso es un número,
		# no un aviso.

	# Sinergias activas
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

func _add_label(parent, text, color = Color(0.9, 0.9, 0.9)):
	var lbl = Label.new();
	lbl.text = text;
	lbl.add_theme_color_override("font_color", color);
	lbl.add_theme_font_size_override("font_size", 12);
	parent.add_child(lbl);

func show_at(screen_pos: Vector2):
	_panel.position = screen_pos + Vector2(14, -10);

func update_position(screen_pos: Vector2):
	_panel.position = screen_pos + Vector2(14, -10);
