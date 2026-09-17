extends CanvasLayer

signal package_chosen(package_id);

func initialize(file_data, save_manager):
	layer = 15;

	var bg = ColorRect.new();
	bg.color = Color(0.04, 0.07, 0.04);
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);
	add_child(bg);

	var vbox = VBoxContainer.new();
	vbox.set_anchors_preset(Control.PRESET_CENTER);
	vbox.position = Vector2(-260, -160);
	vbox.size = Vector2(520, 320);
	vbox.add_theme_constant_override("separation", 16);
	add_child(vbox);

	var title = Label.new();
	title.text = "Elige tu estilo de inicio";
	title.add_theme_font_size_override("font_size", 22);
	title.add_theme_color_override("font_color", Color(0.85, 0.95, 0.5));
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER;
	vbox.add_child(title);

	var hbox = HBoxContainer.new();
	hbox.add_theme_constant_override("separation", 14);
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER;
	vbox.add_child(hbox);

	var packages = file_data.get("StartingPackages", {});
	for pkg_id in packages:
		var pkg = packages[pkg_id];
		var locked = not save_manager.is_package_unlocked(pkg_id);
		_add_card(hbox, pkg_id, pkg, locked);

	var hint = Label.new();
	hint.text = "Completa runs para desbloquear más paquetes";
	hint.add_theme_color_override("font_color", Color(0.45, 0.55, 0.45));
	hint.add_theme_font_size_override("font_size", 11);
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER;
	vbox.add_child(hint);

func _add_card(parent, pkg_id, pkg, locked):
	var panel = PanelContainer.new();
	panel.custom_minimum_size = Vector2(148, 180);
	parent.add_child(panel);

	var vbox = VBoxContainer.new();
	vbox.add_theme_constant_override("separation", 6);
	panel.add_child(vbox);

	var name_lbl = Label.new();
	name_lbl.text = pkg["name"] if not locked else "??  (bloqueado)";
	name_lbl.add_theme_font_size_override("font_size", 15);
	name_lbl.add_theme_color_override("font_color",
		Color(0.4, 0.4, 0.4) if locked else Color(1.0, 0.9, 0.3));
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER;
	vbox.add_child(name_lbl);

	if not locked:
		var desc_lbl = Label.new();
		desc_lbl.text = pkg["description"];
		desc_lbl.add_theme_font_size_override("font_size", 10);
		desc_lbl.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8));
		desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART;
		desc_lbl.custom_minimum_size = Vector2(130, 0);
		vbox.add_child(desc_lbl);

		var factories = pkg.get("factories", []);
		var factories_lbl = Label.new();
		factories_lbl.text = "Factories:\n" + "\n".join(factories);
		factories_lbl.add_theme_font_size_override("font_size", 10);
		factories_lbl.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6));
		vbox.add_child(factories_lbl);

		var w_bonus = int(pkg.get("extra_workers", 0));
		if w_bonus > 0:
			var w_lbl = Label.new();
			w_lbl.text = "+%d workers" % w_bonus;
			w_lbl.add_theme_font_size_override("font_size", 10);
			w_lbl.add_theme_color_override("font_color", Color(0.7, 0.9, 1.0));
			vbox.add_child(w_lbl);

	var btn = Button.new();
	btn.text = "Elegir" if not locked else "Bloqueado";
	btn.disabled = locked;
	btn.pressed.connect(_on_card_pressed.bind(pkg_id));
	vbox.add_child(btn);

func _on_card_pressed(pkg_id):
	package_chosen.emit(pkg_id);
	queue_free();
