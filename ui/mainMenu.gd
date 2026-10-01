extends CanvasLayer

# Con run guardada solo se emite tras confirmar «Empezar nueva»: quien la recibe (`Main`) borra
# el fichero. El menú no toca disco —de `save_manager` solo lee—, así que no conoce `RunSave`.
signal play_pressed;
# Serialización de Run (M5): «CONTINUAR». Main reanuda la run del fichero.
signal continue_pressed;
# Pide a `Main` abrir la pantalla de consentimiento en modo "change". El menú no conoce `Augur`:
# solo avisa, como hace con JUGAR.
signal privacy_pressed;

var _save_manager;
# Si Augur está configurado (Plan «Builds Públicas con Consentimiento», M1). Sin él no hay
# permiso que pedir ni que retirar, así que el botón «Privacidad» no aparece.
var _augur_enabled := false;
# Expuesto para la suite; null si no hay Augur.
var privacy_button: Button = null;
# Si hay una run guardada que vale para este balance (`RunSave.exists_valid()`, lo pregunta Main).
# Con ella sale «CONTINUAR» y «JUGAR» pide confirmación, porque empezar otra la borra.
var _has_run_save := false;
# Expuestos para la suite; null sin run guardada (y el diálogo, hasta pulsar «JUGAR»).
var continue_button: Button = null;
var confirm_dialog: ConfirmationDialog = null;

func initialize(save_manager, augur_enabled: bool = false, has_run_save := false):
	_save_manager = save_manager;
	_augur_enabled = augur_enabled;
	_has_run_save = has_run_save;
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

	# Encima de «JUGAR» y del mismo tamaño: con una run a medias, seguirla es lo esperable.
	if _has_run_save:
		continue_button = Button.new();
		continue_button.text = "CONTINUAR";
		continue_button.custom_minimum_size = Vector2(240, 56);
		continue_button.add_theme_font_size_override("font_size", 22);
		continue_button.pressed.connect(_on_continue_pressed);
		vbox.add_child(continue_button);

	var play_btn = Button.new();
	play_btn.text = "JUGAR";
	play_btn.custom_minimum_size = Vector2(240, 56);
	play_btn.add_theme_font_size_override("font_size", 22);
	play_btn.pressed.connect(_on_play_pressed);
	vbox.add_child(play_btn);

	if _augur_enabled:
		privacy_button = Button.new();
		privacy_button.text = "Privacidad";
		privacy_button.custom_minimum_size = Vector2(240, 36);
		# El menú NO se libera: la pantalla de consentimiento se pone encima y al cerrarla se vuelve aquí.
		privacy_button.pressed.connect(func(): privacy_pressed.emit());
		vbox.add_child(privacy_button);

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
	# Es el ÚNICO texto del juego que enseña los controles, así que tiene que decir la verdad: el
	# radial se abre con click izquierdo (`Main.gd:141-151`), no con ESC —ESC lo CIERRA
	# (`ui/radialMenu.gd:132`)—, y desde M0/M1 ese mismo click sobre una casilla ya ocupada abre el
	# panel de la factoría en vez del radial.
	hint.text = "Click izq: construir  ·  sobre factoría: gestionar  ·  Click der: demoler  ·  R: reiniciar";
	hint.add_theme_color_override("font_color", Color(0.45, 0.55, 0.45));
	hint.add_theme_font_size_override("font_size", 11);
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER;
	vbox.add_child(hint);

func _on_play_pressed():
	if _has_run_save:
		_ask_new_run();
		return;
	_start_new_run();

func _start_new_run():
	play_pressed.emit();
	queue_free();

func _on_continue_pressed():
	continue_pressed.emit();
	queue_free();

# El diálogo nativo de Godot (una `Window`): es un sí/no y el juego no tiene estilo de modal propio.
# Se crea al pulsar y no en _build_ui(), para no dejar una ventana oculta colgando del menú. Cancelar
# lo cierra y deja el menú como estaba.
func _ask_new_run():
	if confirm_dialog == null:
		confirm_dialog = ConfirmationDialog.new();
		confirm_dialog.title = "Run guardada";
		confirm_dialog.dialog_text = "Hay una run guardada. Empezar otra la borra.";
		confirm_dialog.ok_button_text = "Empezar nueva";
		confirm_dialog.cancel_button_text = "Cancelar";
		confirm_dialog.confirmed.connect(_start_new_run);
		add_child(confirm_dialog);
	if confirm_dialog.is_inside_tree():
		confirm_dialog.popup_centered();
