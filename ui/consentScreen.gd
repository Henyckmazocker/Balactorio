extends CanvasLayer

# Pantalla de consentimiento de la analítica (Plan «Builds Públicas con Consentimiento», M1).
# 🔴 NO habla con `Augur`: solo emite la decisión y quien la monta (`Main`) llama a
# `Augur.set_consent()`. Así la suite la prueba pulsando botones sin encender el SDK, y la regla
# de que solo `analytics.gd` y `Main._configure_augur()` tocan Augur sigue intacta.
#
# Dos modos:
# - "first_run": primer arranque, sin decisión en disco. Bloquea el menú (que ni existe todavía:
#   `Main` lo crea en `decided`) y no se puede cerrar sin elegir.
# - "change": desde «Privacidad» del menú. Enseña la decisión actual y deja volver sin cambiar
#   nada (`closed`), porque abrirla por curiosidad no debe obligar a decidir otra vez.

signal decided(granted: bool);
signal closed;

const MODE_FIRST_RUN = "first_run";
const MODE_CHANGE = "change";

# El texto se escribe tal cual lo fija el plan: la mención a la IA externa la exigen el README del
# SDK y el roadmap de Augur, y «si rechazas, no se guarda nada» lo cumple `set_consent(false)`, que
# borra la cola local.
const TITLE_TEXT = "¿Nos ayudas a mejorar Balactorio?";
const BODY_TEXT = "Si aceptas, el juego guarda de forma anónima lo que haces en cada partida: qué construyes, qué cartas eliges, cuánto duras y cómo evoluciona el mapa. Sirve para detectar dónde se atasca la gente y ajustar el equilibrio del juego.\n\nNo se recoge tu nombre, ni tu IP, ni nada fuera del juego. Los datos se identifican con un número aleatorio de esta instalación, se guardan en un servidor propio y pueden analizarse bajo demanda con un servicio de IA externo (Anthropic Claude).\n\nPuedes cambiar de opinión cuando quieras desde [b]Privacidad[/b] en el menú principal. Si rechazas, no se guarda nada.";

var mode = MODE_FIRST_RUN;
var current = false;
# Expuestos para la suite: pulsarlos con `.pressed.emit()` es lo mismo que el click del jugador.
var accept_button: Button;
var decline_button: Button;
var back_button: Button = null;

func initialize(p_mode: String, p_current: bool = false):
	mode = p_mode;
	current = p_current;
	# Se monta antes de cualquier run y no hay pausa, pero si algún día se abre desde una pausa no
	# debe congelarse (mismo criterio que `ui/runSummary.gd`).
	process_mode = Node.PROCESS_MODE_ALWAYS;
	_build_ui();

func _build_ui():
	# Por encima del menú principal (`layer = 20`), que en modo "change" sigue debajo.
	layer = 25;

	var overlay = ColorRect.new();
	# Opaco: con el 0,94 de antes, en modo "change" el título y «JUGAR» del menú se leían a través
	# del texto (visto con `ver-el-juego`). Detrás no hay nada que el jugador tenga que ver.
	overlay.color = Color(0.02, 0.04, 0.02, 1.0);
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT);
	# Se traga los clicks: el menú de debajo no debe poder pulsarse con la pantalla abierta.
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP;
	add_child(overlay);

	# El panel se mide por su contenido y crece hacia los dos lados desde el centro. Con 600×460
	# fijos y sin márgenes, el modo "change" (una línea de estado y «Volver» más) pegaba el título
	# y «Volver» a los bordes.
	var panel = PanelContainer.new();
	var style = StyleBoxFlat.new();
	style.bg_color = Color(0.07, 0.1, 0.07);
	style.set_corner_radius_all(4);
	style.set_content_margin_all(28);
	panel.add_theme_stylebox_override("panel", style);
	panel.set_anchors_preset(Control.PRESET_CENTER);
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH;
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH;
	add_child(panel);

	var vbox = VBoxContainer.new();
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER;
	vbox.add_theme_constant_override("separation", 14);
	panel.add_child(vbox);

	var title = Label.new();
	title.text = TITLE_TEXT;
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER;
	title.add_theme_font_size_override("font_size", 24);
	title.add_theme_color_override("font_color", Color(0.3, 0.95, 0.35));
	vbox.add_child(title);

	# RichTextLabel y no Label para poder poner «Privacidad» en negrita, como en el texto del plan.
	var body = RichTextLabel.new();
	body.bbcode_enabled = true;
	body.text = BODY_TEXT;
	body.fit_content = true;
	body.scroll_active = false;
	body.custom_minimum_size = Vector2(560, 0);
	body.add_theme_color_override("default_color", Color(0.8, 0.9, 0.8));
	vbox.add_child(body);

	# En modo "change" el jugador tiene que ver qué eligió antes de cambiarlo.
	if mode == MODE_CHANGE:
		var status = Label.new();
		status.text = "Ahora mismo: " + ("aceptado" if current else "rechazado");
		status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER;
		status.add_theme_color_override("font_color", Color(0.6, 0.85, 0.6));
		vbox.add_child(status);

	var buttons = HBoxContainer.new();
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER;
	buttons.add_theme_constant_override("separation", 24);
	vbox.add_child(buttons);

	# Los dos botones con el mismo tamaño, la misma fuente y sin color propio: nada de patrón
	# oscuro que empuje a aceptar.
	accept_button = _make_button("Aceptar");
	accept_button.pressed.connect(_on_decided.bind(true));
	buttons.add_child(accept_button);

	decline_button = _make_button("No, gracias");
	decline_button.pressed.connect(_on_decided.bind(false));
	buttons.add_child(decline_button);

	if mode == MODE_CHANGE:
		back_button = Button.new();
		back_button.text = "Volver";
		back_button.pressed.connect(_on_back);
		vbox.add_child(back_button);
		# Marca la decisión actual dejando el foco en su botón.
		call_deferred("_focus_current");

# Diferido porque `Main` la inicializa ya montada pero el foco solo se coge dentro del árbol; la
# suite la construye fuera de él y ahí no hay nada que enfocar.
func _focus_current():
	if is_inside_tree():
		(accept_button if current else decline_button).grab_focus();

func _make_button(text: String) -> Button:
	var btn = Button.new();
	btn.text = text;
	btn.custom_minimum_size = Vector2(180, 48);
	btn.add_theme_font_size_override("font_size", 18);
	return btn;

func _on_decided(granted: bool):
	decided.emit(granted);
	queue_free();

func _on_back():
	closed.emit();
	queue_free();
