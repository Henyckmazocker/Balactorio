extends CanvasLayer

var _panel;

func initialize(factory_node, file_data):
	layer = 5;

	_panel = PanelContainer.new();
	add_child(_panel);

	var vbox = VBoxContainer.new();
	vbox.add_theme_constant_override("separation", 3);
	_panel.add_child(vbox);

	var params = file_data["Factories"].get(factory_node.type, {});

	_add_label(vbox, factory_node.type, Color(1.0, 0.9, 0.2));

	var material = str(params.get("material", null));
	if material != "null":
		_add_label(vbox, "Produce: " + material);
	else:
		_add_label(vbox, "Produce: — (restauración)", Color(0.5, 1.0, 0.5));

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
		if not factory_node.isActive():
			_add_label(vbox, "⚠ INACTIVA (sin workers)", Color(1.0, 0.3, 0.3));

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
