extends CanvasLayer

signal restart_pressed;

func initialize(stats, won):
	process_mode = Node.PROCESS_MODE_ALWAYS;
	_build_ui(stats, won);

func _build_ui(stats, won):
	var overlay = ColorRect.new();
	overlay.color = Color(0, 0, 0, 0.88);
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT);
	add_child(overlay);

	var panel = PanelContainer.new();
	panel.set_anchors_preset(Control.PRESET_CENTER);
	panel.offset_left = -220;
	panel.offset_right = 220;
	panel.offset_top = -180;
	panel.offset_bottom = 180;
	add_child(panel);

	var vbox = VBoxContainer.new();
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER;
	vbox.add_theme_constant_override("separation", 14);
	panel.add_child(vbox);

	var title = Label.new();
	title.text = "¡Run completada!" if won else "Run fallida";
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER;
	title.add_theme_font_size_override("font_size", 26);
	vbox.add_child(title);

	var separator = HSeparator.new();
	vbox.add_child(separator);

	var total_secs = int(stats.get("time", 0));
	var time_label = Label.new();
	time_label.text = "Tiempo: %02d:%02d" % [total_secs / 60, total_secs % 60];
	time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER;
	vbox.add_child(time_label);

	var cp_label = Label.new();
	cp_label.text = "Checkpoints superados: %d" % stats.get("checkpoints", 0);
	cp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER;
	vbox.add_child(cp_label);

	var factories_label = Label.new();
	factories_label.text = "Factories usadas: %d" % stats.get("factories_placed", 0);
	factories_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER;
	vbox.add_child(factories_label);

	var spacer = Control.new();
	spacer.custom_minimum_size = Vector2(0, 12);
	vbox.add_child(spacer);

	var restart_btn = Button.new();
	restart_btn.text = "Volver a jugar  [R]";
	restart_btn.pressed.connect(func(): restart_pressed.emit());
	vbox.add_child(restart_btn);

func _unhandled_input(event):
	if event is InputEventKey and event.pressed and event.keycode == KEY_R:
		restart_pressed.emit();
