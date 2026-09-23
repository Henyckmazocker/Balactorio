extends Node
# Encapsula la lógica de colocación de factories y evaluación de sinergias.
# Main.gd lo instancia y le pasa referencias; no accede al árbol de nodos directamente.

signal factory_placed(factory_node, cell);

# Vecindario de 8 que usan recompute_synergies() y quien necesite recalcular al demoler.
# _evaluate_synergies() conserva su copia local a propósito: se deja intacta.
const NEIGHBOR_OFFSETS = [
	Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1),
	Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1)
];

var _factory_scene: PackedScene;
var _file_data;
var _factory_array: Array;

func initialize(factory_scene: PackedScene, file_data, factory_array: Array):
	_factory_scene = factory_scene;
	_file_data = file_data;
	_factory_array = factory_array;

# --- El precio de construir (Costes M1) ---
# `cost` es OPCIONAL en el JSON y su ausencia significa GRATIS, exactamente el mismo contrato
# que `materials`: así ni las entradas que no lo declaren ni las factorías que una prueba se
# invente tienen que enterarse de que existe una economía.

# El coste declarado para `factory_type`, siempre como `material -> cantidad`. Es un
# diccionario y no un número a propósito: deja la puerta abierta a precios mixtos sin volver a
# tocar el formato del JSON. Devuelve `{}` para lo que no lo declare, que es lo que hace que
# «gratis» no necesite un caso aparte en ninguno de los dos de abajo.
func getCost(factory_type: String) -> Dictionary:
	var params = _file_data["Factories"].get(factory_type, {});
	var cost = params.get("cost", null);
	return cost if cost is Dictionary else {};

# 🔴 Consulta getAvailable() y NUNCA getQuantity(): construir come del excedente y jamás de lo
# que el almacén aparta para el checkpoint en curso. Es la misma regla que ya siguen las
# factorías al consumir, y es la que impide colgar la run — gastarse el peaje en un edificio
# deja un checkpoint que ya no se puede cerrar nunca, y de ahí no se sale produciendo.
func canAfford(factory_type: String, bag) -> bool:
	if bag == null:
		return true;
	var cost = getCost(factory_type);
	for material in cost:
		if bag.getAvailable(material) < int(cost[material]):
			return false;
	return true;

# Descuenta el coste. Se llama DENTRO de build() y siempre detrás de canAfford():
# removeFromBag() corta en 0 y no sabe nada de la reserva, así que cobrar sin comprobar antes
# se comería el peaje del checkpoint en silencio.
func payCost(factory_type: String, bag) -> void:
	if bag == null:
		return;
	var cost = getCost(factory_type);
	for material in cost:
		bag.removeFromBag(material, int(cost[material]));

# --- La devolución al demoler (Costes M4) ---

# Lo que demoler `fab` devuelve a la bolsa: la MITAD de lo que esa factoría pagó, redondeando
# hacia abajo. La llama `Main._demolish_at_cell()`, y vive aquí —y no allí— porque es la otra
# cara de `payCost()`: el precio de una factoría se lee, se cobra y se devuelve en el mismo
# sitio, que es lo que impide que el día de mañana haya dos ideas distintas de lo que cuesta.
#
# 🔴 Se calcula sobre `fab.cost_paid` (lo que se pagó) y NUNCA sobre el `cost` del JSON (lo
# que vale). Lo que no se pagó no se devuelve: si mirase el precio, demoler el almacén con el
# que arranca el mapa —gratis, `mapLoader.place_storage()`— soltaría 5 de madera salidas de
# ninguna parte, y lo mismo cada factoría que la suite coloca sin comprar.
#
# Y la mitad, no el todo: devolver el 100 % convierte «colocar y demoler» en un sondeo
# gratuito del mapa —el mismo agujero que tuvieron las sinergias hasta el 2026-09-17—, y
# devolver 0 castiga el reset rápido que el GDD promete. Redondeando ABAJO, que es lo que
# deja el coste impar del lado del jugador que decide y no del que prueba: pagar 5 devuelve 2.
func getRefund(fab) -> Dictionary:
	var refund = {};
	if fab == null or not ("cost_paid" in fab):
		return refund;
	for material in fab.cost_paid:
		# floori() sobre float y no división entera: `int / int` es un aviso del compilador, y
		# el redondeo que pide el hito es explícitamente hacia abajo, no «el que salga».
		var half = floori(float(int(fab.cost_paid[material])) / 2.0);
		# El 0 no se anota: una devolución de nada no es una entrada del diccionario, y así
		# quien la pinte (el panel de M5) no enseña «devuelve: 0 de madera».
		if half > 0:
			refund[material] = half;
	return refund;

# Coloca una factory en cell y devuelve el nodo instanciado (sin añadirlo al árbol — lo hace el caller).
# `charge_cost` va al final y con default a `false` porque build() tiene dos clases de llamante
# y solo una COMPRA: el gesto del jugador (Main._on_factory_chosen(), el único que pasa `true`)
# paga, mientras que quien monta el mundo o un escenario coloca sin comprar — el almacén con el
# que arranca el mapa (mapLoader.place_storage(), que el plan deja explícitamente gratis), la
# suite. Cobrar por defecto le pasaría al jugador la factura del almacén inicial y
# dejaría sin dinero a decenas de pruebas que no van de economía.
func build(factory_type, cell, player_node, bag, tile_map, charge_cost: bool = false) -> Node:
	# El cobro vive aquí dentro para que no haya dos verdades sobre qué cuesta colocar: quien
	# construye paga en el mismo sitio en que se instancia. Devolver null —y no una factoría a
	# medio pagar— es la única respuesta posible si al llegar aquí el dinero ya no da.
	# Lo que de verdad se cobra se APUNTA en la factoría, y de ese recibo sale la devolución al
	# demolerla (M4, getRefund()). Queda vacío en los dos casos en los que no ha salido dinero
	# de ninguna bolsa: sin `charge_cost` y sin `bag` —con `bag` nulo payCost() no cobra nada—.
	var paid_cost = {};
	if charge_cost:
		if not canAfford(factory_type, bag):
			return null;
		if bag != null:
			paid_cost = getCost(factory_type).duplicate();
		payCost(factory_type, bag);

	var params = _file_data["Factories"][factory_type];
	var adjusted_tick = player_node.getTickForFactory(factory_type, params["tick"]);
	var adjusted_output = player_node.getOutputForFactory(factory_type, 1);
	var pollution = float(params.get("pollution", 0.0));
	var ftype = params.get("type", "production");
	var w_needed = int(params.get("workers_needed", 0));
	# `materials` es OPCIONAL en el JSON: solo lo declara la factoría que puede elegir qué
	# fabricar, que desde Variedad M3 (2026-09-22) es UNA, la `Foundry` con su
	# `["brick", "glass"]`. Se pasa tal cual —`null` incluido—, porque
	# el fallback a `[material]` lo aplica factoryData.initialize(): así vale también para quien
	# construye factorías sin pasar por aquí (hoy, las pruebas de tests/run_tests.gd).
	var materials = params.get("materials", null);

	var fabrica = _factory_scene.instantiate();
	fabrica.initialize(
		factory_type,
		adjusted_tick,
		params["recieve"],
		params["material"],
		adjusted_output,
		pollution,
		ftype,
		w_needed,
		materials
	);
	fabrica.cell_position = cell;
	fabrica.cost_paid = paid_cost;

	var tile_center = tile_map.map_to_local(cell);
	var tile_size = tile_map.tile_set.tile_size;
	tile_center.y -= tile_size.y / 4;
	fabrica.global_position = tile_map.to_global(tile_center);

	# Asignar workers si hay disponibles
	if w_needed > 0 and bag.getFreeWorkers() >= w_needed:
		bag.assignWorkers(w_needed);
		fabrica.workers_assigned = w_needed;

	# Aplicar efectos del tile bajo la factory
	var tdef = tile_map.getCellTypeDef(cell);
	if not tdef.is_empty():
		# Pantano: multiplica contaminación. Muta pollutionAmount, que es el valor BASE y no
		# un acumulador de sinergia: sobrevive a un reset y por eso no se reaplica al recalcular.
		if tdef.has("pollution_multiplier"):
			fabrica.pollutionAmount *= float(tdef["pollution_multiplier"]);
	# Adjacency bonus del tile sobre esta factory
	_apply_tile_adjacency_bonus(fabrica, factory_type, cell, tile_map);

	return fabrica;

# Aplica el adjacency_bonus que el tipo de casilla bajo cell declara para factory_type.
# Es la segunda fuente de los acumuladores de sinergia (la primera son las factorías vecinas),
# así que la usan tanto build() como recompute_synergies().
func _apply_tile_adjacency_bonus(fabrica, factory_type, cell, tile_map):
	var tdef = tile_map.getCellTypeDef(cell);
	if tdef.is_empty():
		return;
	var adj = tdef.get("adjacency_bonus", {});
	var bonus = adj.get(factory_type, adj.get("*", {}));
	_apply_synergy_bonus(fabrica, bonus);

# Llama tras add_child(fabrica) para que cell_position sea consultable en neighbors.
func register_and_evaluate(fabrica, cell):
	_factory_array.append(fabrica);
	_evaluate_synergies(fabrica, cell);
	factory_placed.emit(fabrica, cell);

func _evaluate_synergies(new_factory, cell):
	var neighbor_offsets = [
		Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1),
		Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1)
	];
	var new_params = _file_data["Factories"].get(new_factory.type, {});
	for offset in neighbor_offsets:
		var neighbor = _getFactoryAtCell(cell + offset);
		if neighbor == null:
			continue;
		var neighbor_params = _file_data["Factories"].get(neighbor.type, {});
		var neighbor_synergies = neighbor_params.get("synergies", {});
		if neighbor_synergies.has(new_factory.type):
			_apply_synergy_bonus(new_factory, neighbor_synergies[new_factory.type]);
		var new_synergies = new_params.get("synergies", {});
		if new_synergies.has(neighbor.type):
			_apply_synergy_bonus(neighbor, new_synergies[neighbor.type]);

# Recalcula desde cero los acumuladores de sinergia de una factory ya colocada.
# Se llama al demoler una vecina: recalcular en vez de restar lo concedido es deliberado, porque
# pollution_mult es multiplicativo y deshacerlo dividiendo arrastra error de coma flotante.
func recompute_synergies(factory, tile_map):
	if factory == null:
		return;
	# (1) Reset. pollution_mult es multiplicativo, así que su neutro es 1.0 y no 0.
	factory.synergy_tick_bonus = 0;
	factory.synergy_output_bonus = 0;
	factory.synergy_pollution_mult = 1.0;
	# (2) El adjacency_bonus del tile vive en esos mismos tres acumuladores: si no se reaplica,
	# el reset borraría para siempre el +1 output de forest, el -1 tick de stream o el +2 de fertile.
	_apply_tile_adjacency_bonus(factory, factory.type, factory.cell_position, tile_map);
	# (3) Solo la dirección ENTRANTE: lo que las synergies de cada vecina declaran para el tipo de
	# esta factory. _evaluate_synergies() es bidireccional y reutilizarlo aquí duplicaría los bonos,
	# porque a las vecinas se las recalcula por separado.
	for offset in NEIGHBOR_OFFSETS:
		var neighbor = _getFactoryAtCell(factory.cell_position + offset);
		if neighbor == null:
			continue;
		var neighbor_params = _file_data["Factories"].get(neighbor.type, {});
		var neighbor_synergies = neighbor_params.get("synergies", {});
		if neighbor_synergies.has(factory.type):
			_apply_synergy_bonus(factory, neighbor_synergies[factory.type]);

func _apply_synergy_bonus(target_factory, bonus_dict):
	if bonus_dict.has("tick_bonus"):
		target_factory.synergy_tick_bonus += int(bonus_dict["tick_bonus"]);
	if bonus_dict.has("output_bonus"):
		target_factory.synergy_output_bonus += int(bonus_dict["output_bonus"]);
	if bonus_dict.has("pollution_mult"):
		target_factory.synergy_pollution_mult *= float(bonus_dict["pollution_mult"]);

func _getFactoryAtCell(cell):
	for fab in _factory_array:
		if fab.cell_position == cell:
			return fab;
	return null;

# Consulta las sinergias que obtendría una factoría de `factory_type` colocada en `cell`, SIN
# aplicar ni un solo bonus. El radial la usa para anticipar lo que el jugador gana ahí antes de
# elegir: abrir un menú no puede mover el estado de la partida, así que esto no reutiliza
# _evaluate_synergies() (que aplica) ni aplica-y-revierte (que arrastraría el pollution_mult
# multiplicativo). Resuelve las mismas dos fuentes que resolvería colocar: el adjacency_bonus de
# la casilla y las 8 vecinas.
func preview_synergies(factory_type, cell, tile_map) -> Dictionary:
	var preview = {
		"tick_bonus": 0,
		"output_bonus": 0,
		"pollution_mult": 1.0,
		"gives_to": 0,
	};
	# (1) El bonus del tipo de casilla, que build() aplica antes de mirar a ninguna vecina.
	if tile_map != null:
		var tdef = tile_map.getCellTypeDef(cell);
		if not tdef.is_empty():
			var adj = tdef.get("adjacency_bonus", {});
			_accumulate_preview(preview, adj.get(factory_type, adj.get("*", {})));
	# (2) Las vecinas, en los dos sentidos que _evaluate_synergies() resuelve al colocar: lo que
	# cada una concedería a la nueva se suma al bonus, y lo que la nueva concedería a ellas se
	# cuenta aparte — no es un número que esta factoría vaya a lucir, pero es la mitad del valor
	# de pegar la línea y sin él el radial contaría media verdad.
	var own_synergies = _file_data["Factories"].get(factory_type, {}).get("synergies", {});
	for offset in NEIGHBOR_OFFSETS:
		var neighbor = _getFactoryAtCell(cell + offset);
		if neighbor == null:
			continue;
		var neighbor_synergies = _file_data["Factories"].get(neighbor.type, {}).get("synergies", {});
		if neighbor_synergies.has(factory_type):
			_accumulate_preview(preview, neighbor_synergies[factory_type]);
		if own_synergies.has(neighbor.type):
			preview["gives_to"] += 1;
	return preview;

# Gemelo de _apply_synergy_bonus() sobre un diccionario en vez de sobre una factoría viva: son
# dos porque el destino es distinto, no porque la aritmética lo sea. Si cambia una, cambia la otra.
func _accumulate_preview(preview: Dictionary, bonus_dict) -> void:
	if bonus_dict.has("tick_bonus"):
		preview["tick_bonus"] += int(bonus_dict["tick_bonus"]);
	if bonus_dict.has("output_bonus"):
		preview["output_bonus"] += int(bonus_dict["output_bonus"]);
	if bonus_dict.has("pollution_mult"):
		preview["pollution_mult"] *= float(bonus_dict["pollution_mult"]);
