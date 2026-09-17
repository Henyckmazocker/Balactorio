extends Area2D

signal factory_selected(type);
signal resource_produced(material, amount, world_pos);

var type;
var production;
var tickTimer;
var itemNeeded = [];
var timer = 0;
var in_inventory = false;
var outputAmount = 1;
var pollutionAmount = 0.0;   # >0 contamina, <0 restaura
var factory_type = "production";  # "production" | "restoration"
var cell_position = Vector2i(0, 0);
# Producción fraccionaria arrastrada entre ticks por el ahogo (ver getPollutionChoke).
var production_debt = 0.0;

# Modificadores aplicados por sinergias de adyacencia
var synergy_tick_bonus = 0;      # reduce tickTimer efectivo
var synergy_output_bonus = 0;    # suma a outputAmount efectivo
var synergy_pollution_mult = 1.0; # multiplica pollutionAmount

# Workers
var workers_needed = 0;
var workers_assigned = 0;        # 0 = inactiva si workers_needed > 0

func _ready():
	input_pickable = true;
	connect("input_event", _on_input_event);

func initialize(name, tick, needs, material, output = 1, pollution = 0.0, ftype = "production", w_needed = 0):
	type = name;
	tickTimer = tick;
	production = material;
	outputAmount = output;
	pollutionAmount = pollution;
	factory_type = ftype;
	workers_needed = w_needed;
	if needs != null:
		itemNeeded = needs.duplicate();

func _on_input_event(_viewport, event, _shape_idx):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if in_inventory:
			factory_selected.emit(type);
		get_viewport().set_input_as_handled();

# Devuelve true si tiene los workers necesarios (o no necesita ninguno)
func isActive():
	return workers_needed == 0 or workers_assigned >= workers_needed;

func getEffectiveTick():
	return max(1, tickTimer - synergy_tick_bonus);

func getEffectiveOutput():
	return outputAmount + synergy_output_bonus;

func getEffectivePollution():
	return pollutionAmount * synergy_pollution_mult;

# El ahogo: la contaminación LOCAL de la casilla quita ritmo, no solo sitio. Vale 1.0 sobre
# suelo limpio y 0.0 sobre casilla saturada (getCellPollution ya satura en cell_block_pollution
# y viene clampado 0..1, así que el choke nunca se va de rango).
# Las de restauración quedan exentas a propósito: si el Reforester rindiera menos sobre suelo
# sucio, saturar el mapa sería irreversible y el jugador perdería sin agencia. Limpiar tiene que
# funcionar siempre — es la salida que convierte la espiral en castigo y no en sentencia.
# Localiza el manager como _apply_pollution(), y hereda su trampa entera: find_child devuelve el
# PRIMER PollutionManager del árbol, así que en las pruebas hay que soltar un escenario antes de
# montar el siguiente.
func getPollutionChoke():
	if factory_type == "restoration":
		return 1.0;
	var pm = get_tree().get_root().find_child("PollutionManager", true, false);
	if pm == null:
		return 1.0;
	return 1.0 - pm.getCellPollution(cell_position);

# Factor por el que escala la restauración. `max(1, ...)` evita que un output_bonus
# negativo futuro anule la limpieza en silencio, igual que el guardia de getEffectiveTick().
func getRestorationScale():
	return max(1, getEffectiveOutput());

func update(bag):
	if not isActive():
		return;
	if factory_type == "restoration":
		_tick_restoration();
	elif checkNeeds(bag):
		# El ahogo se aplica AQUÍ, donde se produce, y NO en getEffectiveOutput(): esa función es
		# el techo con el que gameManager._installed_rate() juzga el tier de la recompensa, y si
		# el ahogo lo bajara, ahogar tu propia línea te haría cobrar cartas potentes por jugar
		# mal. Baja el ritmo sin bajar el techo, igual que una serrería sin madera.
		# Se acumula en un float en vez de redondear porque casi todas las factorías tienen
		# output 1: int(1 * 0.6) daría 0 y el ahogo sería un interruptor en vez de una rampa. Con
		# el acumulador, al 50 % de ahogo se entrega 1 cada 2 ticks. Determinista, así que se puede probar.
		production_debt += getEffectiveOutput() * getPollutionChoke();
		var eff_out = int(production_debt);
		# Un tick que no entrega nada NO consume insumos, no ensucia y no anima: si consumiera, el
		# ahogo sería además un sumidero de recursos y aceleraría la espiral por un camino que el
		# plan no ha diseñado. La deuda sí sigue acumulando — es lo que hace la rampa.
		if eff_out <= 0:
			return;
		production_debt -= eff_out;
		consumeNeeds(bag);
		# "worker" no va al bag — Main lo intercepta vía resource_produced
		if production != "worker":
			bag.addToBag(production, eff_out);
		resource_produced.emit(production, eff_out, global_position);
		get_node("AnimatedSprite2D").play();
		_apply_pollution();

func _tick_restoration():
	# El output efectivo dice cuánto rinde la factoría por tick, también en restauración:
	# un Reforester sobre `fertile` (output_bonus: 2) limpia x3 en vez de x1.
	_apply_pollution(getRestorationScale());
	get_node("AnimatedSprite2D").play();

func _apply_pollution(output_scale = 1.0):
	var pm = get_tree().get_root().find_child("PollutionManager", true, false);
	if pm == null:
		return;
	var effective = getEffectivePollution() * output_scale;
	if effective >= 0:
		# Producción: ensucia solo su propia celda, como siempre.
		pm.addPollution(effective, cell_position);
	elif factory_type == "restoration":
		_spread_restoration(pm, -effective);
	else:
		pm.removePollution(-effective, cell_position);

# La restauración se reparte entre la celda propia y sus 8 vecinas: cada una recibe la
# novena parte. El reparto vive en pollutionManager.removePollutionArea() porque los tiles
# limpiadores (el lago) limpian igual, y con él vienen sus dos consecuencias: el total
# restaurado por tick es como mucho `amount` —solo se alcanza si las nueve casillas tienen
# al menos amount/9 de suciedad—, y es lo que permite limpiar una casilla `toxic`, que al
# ser buildable: false nunca tiene factoría encima.
func _spread_restoration(pm, amount):
	pm.removePollutionArea(amount, cell_position);

# Se mira lo DISPONIBLE, no lo que hay: la bolsa aparta el mantenimiento del checkpoint en
# curso y esa parte no se puede quemar como insumo. Sin esta línea, una serrería acelerada
# consume madera más rápido de lo que se tala, el peaje se queda sin cubrir y el checkpoint
# —que desde M4 lo exige entero— no se cierra jamás; sin condición de derrota, eso no es
# perder, es una run infinita. Con ella la serrería solo come del excedente, así que el
# peaje se reúne siempre y la producción sigue al ritmo de la tala.
func checkNeeds(bag):
	for x in itemNeeded:
		if bag.getAvailable(x) > 0:
			continue;
		else:
			return false;
	return true;

func consumeNeeds(bag):
	for x in itemNeeded:
		bag.removeFromBag(x, 1);

func _on_timer_timeout():
	timer += 1;
	if int(timer) % int(getEffectiveTick()) == 0:
		update(get_parent().get_node("Player").get_node("Bag"));
