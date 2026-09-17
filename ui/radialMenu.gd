extends CanvasLayer

signal factory_chosen(type, cell);

var _cell = Vector2i(0, 0);

# El botón ya no se dimensiona por su propio texto: el contenido son labels hijas, para poder
# pintar la sinergia en verde sin teñir también el nombre (que lleva el color de contaminación).
# Por eso el alto se calcula contando líneas, y el radio se separa lo justo para que dos botones
# vecinos no se toquen ni cuando los dos anuncian sinergias: la línea más larga («✦ Mejora 1
# vecina») es la que fija el ancho, porque una Label no se recorta y se saldría del panel.
const LINE_HEIGHT = 16;
const BUTTON_WIDTH = 130;
const BUTTON_PADDING = 18;
const RADIUS = 118.0;
const SYNERGY_COLOR = Color(0.6, 1.0, 0.6);

func initialize(available_factories, file_data, cell, screen_pos, synergy_preview = {}):
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

	var n = available_factories.size();
	for i in range(n):
		var angle = (2.0 * PI * i / float(n)) - PI / 2.0;
		var offset = Vector2(cos(angle) * RADIUS, sin(angle) * RADIUS);
		var btn_pos = screen_pos + offset;

		var factory_name = available_factories[i];
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
		# Lo que se gana construyendo AQUÍ, que es la decisión que este menú toma.
		for texto in _synergy_lines(synergy_preview.get(factory_name, {})):
			lines.append([texto, SYNERGY_COLOR]);

		var btn = Button.new();
		btn.custom_minimum_size = Vector2(BUTTON_WIDTH, BUTTON_PADDING + lines.size() * LINE_HEIGHT);
		btn.size = btn.custom_minimum_size;
		btn.position = btn_pos - btn.size / 2.0;
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND;
		btn.pressed.connect(_on_factory_pressed.bind(factory_name));
		root.add_child(btn);

		# Las labels van dentro del botón e ignoran el ratón: el click sigue siendo del botón.
		var vbox = VBoxContainer.new();
		vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);
		vbox.alignment = BoxContainer.ALIGNMENT_CENTER;
		vbox.add_theme_constant_override("separation", 0);
		vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE;
		btn.add_child(vbox);
		for linea in lines:
			var l = Label.new();
			l.text = linea[0];
			l.add_theme_color_override("font_color", linea[1]);
			l.add_theme_font_size_override("font_size", 11);
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER;
			l.mouse_filter = Control.MOUSE_FILTER_IGNORE;
			vbox.add_child(l);

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
