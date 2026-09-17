extends CanvasLayer

signal upgrade_chosen(upgrade_id);

var upgrades_catalog = {};

# Nombre en castellano de los tipos de casilla que una mejora puede dejar en el mapa. Vive
# aquí y no en el JSON porque el texto del castigo se construye a partir del propio
# `map_downside`: así el número de casillas que se degradan y el que lee el jugador no
# pueden divergir nunca.
const DOWNSIDE_TYPE_NAMES = {
	"toxic": "tóxica",
	"swamp": "pantano",
	"burned": "tierra quemada",
	"lava": "lava"
};

# Mejoras que la run ha recibido sin elegirlas (las cartas de rescate de
# `gameManager._granted_upgrades()`). Se pintan como aviso, no como carta: ya están aplicadas
# cuando esta pantalla se monta.
var granted_ids = [];

func initialize(offered_ids, catalog, granted = []):
	upgrades_catalog = catalog;
	granted_ids = granted;
	process_mode = Node.PROCESS_MODE_ALWAYS;
	_build_ui(offered_ids);

func _build_ui(offered_ids):
	var overlay = ColorRect.new();
	overlay.color = Color(0, 0, 0, 0.75);
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT);
	add_child(overlay);

	var panel = PanelContainer.new();
	panel.set_anchors_preset(Control.PRESET_CENTER);
	panel.offset_left = -340;
	panel.offset_right = 340;
	# El aviso de lo concedido necesita su sitio: sin alto extra el texto empujaría las cartas
	# fuera del panel.
	panel.offset_top = -220 if not granted_ids.is_empty() else -180;
	panel.offset_bottom = 220 if not granted_ids.is_empty() else 180;
	add_child(panel);

	var vbox = VBoxContainer.new();
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER;
	vbox.add_theme_constant_override("separation", 16);
	panel.add_child(vbox);

	var title = Label.new();
	title.text = "— Checkpoint superado — Elige una mejora —";
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER;
	title.add_theme_font_size_override("font_size", 18);
	vbox.add_child(title);

	# Lo concedido va ARRIBA, antes de las cartas: si el jugador ve primero las tres opciones
	# ya está eligiendo, y el aviso llegaría tarde. En verde y con su motivo, porque una
	# mejora que aparece sin haberla elegido y sin explicación se lee como un bug.
	for id in granted_ids:
		if not upgrades_catalog.has(id):
			continue;
		# El aviso es texto largo y el Label se estira al ancho del panel: sin margen queda
		# pegado a los dos bordes y se lee peor que las cartas, que sí tienen aire.
		var margen = MarginContainer.new();
		margen.add_theme_constant_override("margin_left", 28);
		margen.add_theme_constant_override("margin_right", 28);
		vbox.add_child(margen);
		var granted_label = Label.new();
		granted_label.text = _granted_text(upgrades_catalog[id]);
		granted_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER;
		granted_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART;
		granted_label.add_theme_font_size_override("font_size", 12);
		granted_label.add_theme_color_override("font_color", Color(0.35, 0.9, 0.45));
		granted_label.custom_minimum_size = Vector2(560, 0);
		margen.add_child(granted_label);

	var hbox = HBoxContainer.new();
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER;
	hbox.add_theme_constant_override("separation", 20);
	vbox.add_child(hbox);

	for id in offered_ids:
		if upgrades_catalog.has(id):
			hbox.add_child(_make_card(id, upgrades_catalog[id]));

func _make_card(upgrade_id, upgrade) -> Control:
	var card = PanelContainer.new();
	card.custom_minimum_size = Vector2(180, 140);

	var inner = VBoxContainer.new();
	inner.alignment = BoxContainer.ALIGNMENT_CENTER;
	inner.add_theme_constant_override("separation", 10);
	card.add_child(inner);

	var name_label = Label.new();
	name_label.text = upgrade.get("name", upgrade_id);
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER;
	name_label.add_theme_font_size_override("font_size", 15);
	inner.add_child(name_label);

	var separator = HSeparator.new();
	inner.add_child(separator);

	var desc_label = Label.new();
	desc_label.text = upgrade.get("description", "");
	desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER;
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART;
	desc_label.add_theme_font_size_override("font_size", 11);
	desc_label.custom_minimum_size = Vector2(160, 0);
	inner.add_child(desc_label);

	# El castigo, en rojo y debajo de la descripción: una penalización invisible no es un
	# dilema, es una trampa. Sin `map_downside` no se añade nada y la carta queda como estaba.
	if upgrade.has("map_downside"):
		var downside_label = Label.new();
		downside_label.text = _downside_text(upgrade["map_downside"]);
		downside_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER;
		downside_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART;
		downside_label.add_theme_font_size_override("font_size", 11);
		downside_label.add_theme_color_override("font_color", Color(0.95, 0.25, 0.2));
		downside_label.custom_minimum_size = Vector2(160, 0);
		inner.add_child(downside_label);

	var btn = Button.new();
	btn.text = "Elegir";
	btn.pressed.connect(func(): _on_upgrade_chosen(upgrade_id));
	inner.add_child(btn);

	return card;

# El aviso de lo concedido: qué se ha dado y POR QUÉ no se ha dejado elegir. El motivo es
# fijo y no viene del JSON porque la razón es siempre la misma —lo que queda por delante pide
# un material que esta partida no sabe fabricar— y es la mitad del mensaje: sin ella, una
# mejora que aparece sola se lee como un error del juego.
func _granted_text(upgrade) -> String:
	return "✔ Concedida: %s — %s\nNo se ofrece entre las tres porque es la única salida: los checkpoints que quedan piden un material que tu partida todavía no sabe fabricar, y rechazarla dejaría la run sin final. Tu elección sigue intacta." % [
		upgrade.get("name", ""), upgrade.get("description", "")];

# "⚠ Degrada 2 casillas del mapa a tóxica". Un tipo que no esté en la tabla sale con su id
# antes que sin texto: quedarse mudo es justo lo que este hito viene a arreglar.
func _downside_text(downside) -> String:
	var cells = int(downside.get("cells", 0));
	var ttype = downside.get("type", "");
	var type_name = DOWNSIDE_TYPE_NAMES.get(ttype, ttype);
	if cells == 1:
		return "⚠ Degrada 1 casilla del mapa a %s" % type_name;
	return "⚠ Degrada %d casillas del mapa a %s" % [cells, type_name];

func _on_upgrade_chosen(upgrade_id):
	upgrade_chosen.emit(upgrade_id);
	queue_free();
