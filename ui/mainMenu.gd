extends CanvasLayer

signal play_pressed;

var _save_manager;

func initialize(save_manager):
	_save_manager = save_manager;
	_build_ui();

func _ready():
	if _save_manager == null:
		_build_ui();

func _build_ui():
	layer = 20;

	var bg = ColorRect.new();
	bg.color = Color(0.04, 0.07, 0.04);
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);
	add_child(bg);

	var vbox = VBoxContainer.new();
	vbox.set_anchors_preset(Control.PRESET_CENTER);
	vbox.position = Vector2(-150, -120);
	vbox.size = Vector2(300, 240);
	vbox.add_theme_constant_override("separation", 12);
	add_child(vbox);

	var title = Label.new();
	title.text = "BALACTORIO";
	title.add_theme_font_size_override("font_size", 48);
	title.add_theme_color_override("font_color", Color(0.3, 0.95, 0.35));
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER;
	vbox.add_child(title);

	var subtitle = Label.new();
	subtitle.text = "Construye · Produce · Restaura";
	subtitle.add_theme_color_override("font_color", Color(0.6, 0.85, 0.6));
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER;
	vbox.add_child(subtitle);

	var spacer = Control.new();
	spacer.custom_minimum_size = Vector2(0, 32);
	vbox.add_child(spacer);

	var play_btn = Button.new();
	play_btn.text = "JUGAR";
	play_btn.custom_minimum_size = Vector2(240, 56);
	play_btn.add_theme_font_size_override("font_size", 22);
	play_btn.pressed.connect(_on_play_pressed);
	vbox.add_child(play_btn);

	# Mejor tiempo si hay runs completadas
	if _save_manager and _save_manager.get_runs_completed() > 0:
		var best = _save_manager.get_best_time();
		var mins = int(best) / 60;
		var secs = int(best) % 60;
		var stats_lbl = Label.new();
		stats_lbl.text = "Runs: %d   Mejor: %02d:%02d" % [_save_manager.get_runs_completed(), mins, secs];
		stats_lbl.add_theme_color_override("font_color", Color(0.55, 0.75, 0.55));
		stats_lbl.add_theme_font_size_override("font_size", 12);
		stats_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER;
		vbox.add_child(stats_lbl);

	var hint = Label.new();
	hint.text = "R: reiniciar run   ESC: menú radial";
	hint.add_theme_color_override("font_color", Color(0.45, 0.55, 0.45));
	hint.add_theme_font_size_override("font_size", 11);
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER;
	vbox.add_child(hint);

func _on_play_pressed():
	play_pressed.emit();
	queue_free();
