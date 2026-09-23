extends Node

# La red de cintas: transporte dirigido entre factorías. Nodo hijo de Main, como el resto de
# managers (en este proyecto no hay autoloads).
#
# La red vive INDEXADA POR CELDA, no en un array: localizar el segmento de una casilla es un
# acceso a diccionario y no un recorrido lineal. Es la lección de M0, donde el recorrido lineal
# de hoy (`factoryPlacer._getFactoryAtCell()`) medía 0,207-0,553 ms de mediana con la red más
# grande que cabe en el mapa, contra 0,023-0,036 ms indexando.
#
# Las cintas NO son un tipo de casilla: no entran en `tileMap.cell_types` —que se muta en
# cuatro sitios exactos y del que cuelgan la serialización y el tintado—, sino en el
# diccionario `belts` de este nodo.

# Lo emite este manager al colocar o demoler. Escucha ui/factoryPanel (M5).
signal belt_network_changed();

# Tope del recorrido de la red. En M2 lo consume deliver() para que un bucle de cintas
# —trivial de construir arrastrando en círculo— no cuelgue el juego; aquí acota ya el largo
# de un arrastre, que en un mapa de 16x10 nunca se acerca.
const MAX_PATH: int = 64;

# Solo cuatro direcciones ortogonales, no ocho: una cinta en diagonal no se puede dibujar de
# forma legible sobre tiles isométricos, y la vecindad de 8 ya la usan las sinergias para otra
# cosa.
const ORTHOGONAL_DIRS = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)];

# Un tramo de cinta, uno por casilla. `dir_in` apunta desde la celda hacia DE DÓNDE le entra el
# material y `dir_out` hacia DÓNDE lo saca, así que encadenar dos segmentos es que el `dir_out`
# de uno lleve a la celda del otro y el `dir_in` del otro vuelva a la del primero.
class BeltSegment:
	var cell: Vector2i = Vector2i.ZERO;
	var dir_in: Vector2i = Vector2i.ZERO;
	var dir_out: Vector2i = Vector2i.ZERO;
	var filter: String = "";  # "" = acepta todo; si no, solo ese material (se usa en M5)
	func _init(p_cell = Vector2i.ZERO, p_dir_in = Vector2i.ZERO, p_dir_out = Vector2i.ZERO, p_filter = ""):
		cell = p_cell;
		dir_in = p_dir_in;
		dir_out = p_dir_out;
		filter = p_filter;

# El canvas item por el que salen las cintas. Por el mismo motivo que el `TintOverlay` del
# TileMap: un TileMap pinta cada capa en un canvas item HIJO del suyo, así que lo que dibuje el
# propio nodo queda POR DEBAJO de los tiles y no llega nunca a pantalla. Este overlay es hijo
# del TileMap (hereda su transform, así que map_to_local() sigue valiendo) y lleva z_index
# propio para quedar por encima del suelo, del highlight de hover y del tinte.
class BeltOverlay extends Node2D:
	var belt_network = null;
	func _draw():
		if belt_network:
			belt_network.draw_belts(self);

var belts = {};            # Vector2i -> BeltSegment
# Cache de factoryArray por celda, que consume deliver(). Se invalida entera al construir o al
# demoler una factoría (Main._on_factory_chosen() y Main._demolish_at_cell()) y se repuebla
# perezosamente en la primera entrega que la necesite.
var _factory_index = {};   # Vector2i -> Node
# Si la cache está al día. Hace falta aparte del diccionario porque un mapa SIN factorías
# también produce un índice vacío, y sin este flag se repoblaría en cada entrega.
var _factory_index_ready = false;
# El array VIVO de factorías de Main, no una copia: `placer` lo muta al construir y
# _demolish_at_cell() al demoler, igual que con gameManager.setFactories().
var _factory_array = [];
var _tile_map = null;
var _overlay = null;
# El JSON entero de la run, del que sale UN solo dato: `Belts.cost_per_cell` (Costes M3). Se
# guarda la referencia y no una copia del precio, igual que factoryPlacer._file_data, porque
# el diccionario es el mismo que parsea Main: copiarlo aquí dejaría dos precios que pueden
# divergir. `null` —la suite, que llama con dos argumentos— significa cinta gratis.
var _file_data = null;

# Main inyecta el TileMap —de él salen la geometría del dibujo y las reglas de colocación—,
# el array de factorías, que es de donde deliver() saca el destino del camino, y el JSON, del
# que sale el precio por casilla.
func initialize(tile_map, factory_array = null, file_data = null):
	_tile_map = tile_map;
	_file_data = file_data;
	set_factories(factory_array);
	_ensure_overlay();

func set_factories(factory_array):
	_factory_array = factory_array if factory_array != null else [];
	invalidate_factory_index();

# ---------- consulta ----------

func has_belt(cell) -> bool:
	return belts.has(cell);

func get_belt(cell):
	return belts.get(cell, null);

func belt_count() -> int:
	return belts.size();

# ---------- el trazado en L ----------

# Una L entre origen y destino, INCLUIDOS los dos extremos. Los dos siguen en el array aunque
# el jugador haya arrastrado desde (o hasta) la casilla de una factoría: son ellos los que
# ORIENTAN los segmentos de las puntas, y quién lleva cinta de verdad lo decide `_belt_range()`
# (M7), no este trazado.
#
# `horizontal_first` elige por dónde DOBLA la L: avanzar en X y luego en Y, o al revés. Las dos
# tienen el mismo largo (la distancia manhattan + 1) y exactamente las mismas casillas en las
# puntas; lo único que cambia es el codo.
func _trace_l(from_cell, to_cell, horizontal_first: bool) -> Array:
	var cells = [];
	var x = from_cell.x;
	var y = from_cell.y;
	cells.append(Vector2i(x, y));
	var primero_x = to_cell.x if horizontal_first else from_cell.x;
	while x != primero_x:
		x += signi(primero_x - x);
		cells.append(Vector2i(x, y));
	while y != to_cell.y:
		y += signi(to_cell.y - y);
		cells.append(Vector2i(x, y));
	while x != to_cell.x:
		x += signi(to_cell.x - x);
		cells.append(Vector2i(x, y));
	return cells;

# El trazado horizontal-primero, que es el PREFERENTE. Sigue siendo público y con la misma
# firma que en M1 porque sirve para contar casillas antes de arrastrar; quien
# quiera saber qué camino se va a tender DE VERDAD tiene que preguntar por
# `resolve_drag_path()`, que es el que prueba las dos L.
func trace_path(from_cell, to_cell) -> Array:
	return _trace_l(from_cell, to_cell, true);

# Las dos L de un arrastre, en ORDEN DE PREFERENCIA (Costes M5b).
#
# Sigue sin haber pathfinding, y por la misma razón de siempre: rodear un obstáculo sería
# elegir por el jugador dónde gasta sus casillas, que es justo la decisión que el diseño quiere
# que tome él. Lo que M5b corrige es lo contrario de un exceso de ayuda — con UNA sola L,
# bastaba una casilla cerrada por `cell_block_pollution` en la fila de paso para dejar
# inalcanzable todo lo que hubiera detrás, y el jugador ni siquiera veía por qué le fallaba el
# gesto. Se prueban DOS caminos
# deterministas, no dieciocho: el jugador sigue pudiendo predecir por dónde va a ir la cinta y
# lo que le van a cobrar, que es lo que la decisión original protege.
#
# 🔴 El orden es FIJO: horizontal-primero siempre que quepa, vertical solo como alternativa. Si
# la preferencia dependiera de algo más —de cuál sale más barata, de por dónde hay menos
# contaminación—, el trazado dejaría de ser predecible, que es justo lo que este orden defiende.
#
# En un arrastre recto (misma fila o misma columna) las dos L son el MISMO camino, así que solo
# se devuelve uno: probar dos veces lo mismo no cambia el resultado y confunde al leerlo. Si
# ninguna de las dos cabe, el arrastre falla entero y el jugador tiende en dos tramos, como
# hasta M5b.
func _candidate_paths(from_cell, to_cell) -> Array:
	var paths = [_trace_l(from_cell, to_cell, true)];
	if from_cell.x != to_cell.x and from_cell.y != to_cell.y:
		paths.append(_trace_l(from_cell, to_cell, false));
	return paths;

# ---------- los extremos ocupados por una factoría (M7) ----------

# ¿Hay una factoría en esa celda? Es el mismo recorrido que la condición 4 de
# `tileMap.canPlaceFactory()`, y sobre el MISMO array que le llega al arrastre: no se consulta
# `_factory_index` porque quien valida un arrastre puede traer un array que nunca se inyectó
# con `set_factories()` —la suite monta escenarios así—, y las dos respuestas
# tienen que ser la misma o el recorte y la validación dejarían de estar de acuerdo.
func _has_factory(cell, factory_array) -> bool:
	if factory_array == null:
		return false;
	for fab in factory_array:
		if is_instance_valid(fab) and fab.cell_position == cell:
			return true;
	return false;

# El tramo del camino que de verdad lleva cinta, como par de índices [primero, último] sobre
# `path`.
#
# M7: el arrastre ACEPTA las casillas de las factorías como extremos y las EXCLUYE del camino
# —se arrastra de la cortadora a la serrería y la cinta se tiende ENTRE las dos—. Es lo que
# hace posible la cinta de una sola casilla, y con ella unir dos factorías en diagonal: entre
# ellas hay exactamente una casilla ortogonalmente vecina de las dos, y hasta M7 ese segmento
# único no se podía colocar (`from_cell == to_cell` es el click de siempre, así que había que
# arrastrar de factoría a factoría y eso lo rechazaba `canPlaceFactory()`).
#
# Los extremos recortados NO se borran de `path`: `_build_chain()` los necesita para orientar,
# y por eso el primer segmento sigue mirando a la factoría de origen y el último apuntando a
# la de destino, que es el contrato del que cuelgan `_entry_segment()` y `deliver()`.
#
# Solo se recortan los EXTREMOS, y solo si están ocupados: una celda intermedia con factoría
# —o con montaña, lago o cinta— sigue tumbando el arrastre entero, que es la regla de todo o
# nada de M1. Y si al recortar no queda ninguna celda —dos factorías ortogonalmente pegadas,
# entre las que no hay casilla— el tramo sale vacío (primero > último) y no se tiende nada:
# eso es la decisión de «todo pasa por cinta», no un defecto.
func _belt_range(path, factory_array) -> Vector2i:
	var first = 0;
	var last = path.size() - 1;
	if _has_factory(path[first], factory_array):
		first += 1;
	if last >= first and _has_factory(path[last], factory_array):
		last -= 1;
	return Vector2i(first, last);

# ---------- el precio de la cinta (Costes M3) ----------

# El precio por casilla, tal cual lo declara el JSON. `Belts.cost_per_cell` es OPCIONAL y su
# ausencia —la del bloque entero, o la del JSON, que es lo que pasa cuando la suite monta
# una red con `initialize(tile_map, factory_array)`— significa GRATIS. Es el
# mismo contrato que el `cost` de las factorías (factoryPlacer.getCost()), y por el mismo
# motivo: quien monta un escenario de cintas no tiene que enterarse de que existe una
# economía. Diccionario `material -> cantidad` y no un número, para que un precio mixto no
# obligue a tocar el formato.
func get_cost_per_cell() -> Dictionary:
	if _file_data == null:
		return {};
	var cost = _file_data.get("Belts", {}).get("cost_per_cell", null);
	return cost if cost is Dictionary else {};

# Lo que cuesta el arrastre ENTERO: el precio por casilla multiplicado por las casillas que de
# verdad van a llevar cinta.
#
# 🔴 Ese número NO es el largo del camino. `trace_path()` incluye origen y destino y
# `_belt_range()` recorta los extremos ocupados por una factoría (M7 del plan de cintas: se
# arrastra de la cortadora a la serrería y la cinta se tiende ENTRE las dos). Cobrar el camino
# entero le pasaría al jugador dos casillas fantasma en cada tendido de factoría a factoría,
# que es justo el gesto que el diseño quiere que haga.
func belt_cost_for(cell_count: int) -> Dictionary:
	var total = {};
	if cell_count <= 0:
		return total;
	var per_cell = get_cost_per_cell();
	for material in per_cell:
		total[material] = int(per_cell[material]) * cell_count;
	return total;

# 🔴 Consulta getAvailable() y NUNCA getQuantity(), exactamente igual que
# factoryPlacer.canAfford(): tender cinta come del excedente y jamás de lo que el almacén
# aparta para el checkpoint en curso. Gastarse el peaje en logística deja un checkpoint que ya
# no se puede cerrar nunca, y de ahí no se sale produciendo.
#
# Se pregunta por el arrastre COMPLETO y no casilla a casilla: el precio se compara antes de
# confirmar y el arrastre se rechaza entero si no alcanza, porque media cinta pagada no
# transporta nada y el jugador habría perdido la madera en nada.
func can_afford_belt(cell_count: int, bag) -> bool:
	if bag == null:
		return true;
	var total = belt_cost_for(cell_count);
	for material in total:
		if bag.getAvailable(material) < int(total[material]):
			return false;
	return true;

# Descuenta el arrastre entero. Se llama SIEMPRE detrás de can_afford_belt(): removeFromBag()
# corta en 0 y no sabe nada de la reserva, así que cobrar sin comprobar antes se comería el
# peaje del checkpoint en silencio.
func pay_belt_cost(cell_count: int, bag) -> void:
	if bag == null:
		return;
	var total = belt_cost_for(cell_count);
	for material in total:
		bag.removeFromBag(material, int(total[material]));

# ¿Cabe ESTE camino entero? Todo o nada: basta una celda que vaya a llevar cinta y no admita
# para que no se tienda ninguna. La pregunta se le hace a `tileMap.canPlaceFactory()`, único
# punto de verdad de «¿cabe aquí?», que desde M1 rechaza también las celdas con cinta.
#
# Se pregunta SIN categoría, o sea por la regla estricta, y eso es deliberado desde Costes M7:
# la excepción que esa versión abre —la casilla saturada admite restauración— es de las
# factorías que limpian, y LA CINTA NO ES UNA FACTORÍA. Una cinta sobre suelo muerto no lo
# devuelve; tenderla ahí solo sería saltarse la regla de colocación por la puerta de atrás.
#
# Solo geometría: el dinero no entra aquí porque no elige camino (ver `_plan_drag()`).
func _path_fits(path, span, factory_array) -> bool:
	# El tope del recorrido. No sirve para descartar ENTRE las dos L: las dos miden lo mismo,
	# así que si una se pasa la otra también.
	if path.size() > MAX_PATH:
		return false;
	# Nada que tender: el arrastre iba de una factoría a otra ortogonalmente pegada y entre
	# las dos no hay casilla donde poner el segmento.
	if span.x > span.y:
		return false;
	# La validación sigue cayendo sobre TODAS las celdas que van a llevar cinta. Lo que M7
	# quita del camino son los dos extremos ocupados, no la regla: un obstáculo en medio
	# aborta el arrastre igual que antes.
	for i in range(span.x, span.y + 1):
		if not _tile_map.canPlaceFactory(path[i], factory_array):
			return false;
	return true;

# 🔴 EL PLAN DEL ARRASTRE, resuelto UNA sola vez: el camino elegido entre las dos L y el tramo
# de ese camino que de verdad llevará cinta, como `{"path": [...], "first": i, "last": j}`, o
# `{}` si el arrastre no sale. Lo llaman `can_place_drag()` y `place_drag()`, y por eso los dos
# ven exactamente el MISMO trazado: desde M5b hay dos caminos posibles, así que resolverlo cada
# uno por su cuenta sería validar una L y tender la otra —y cobrar por una tercera cosa—.
#
# `bag` y `charge_cost` son de Costes M3 y van al final, opcionales y sin cobrar por defecto,
# por el mismo motivo que el `charge_cost` de factoryPlacer.build() y con el mismo mecanismo:
# el arrastre tiene dos clases de llamante y solo una COMPRA. Paga el gesto del jugador
# (Main._unhandled_input(), el único que pasa `true`), mientras que la suite
# tiende redes enteras con bolsas que nunca pensaron en pagar. Cobrar por defecto los dejaría
# a todos sin dinero en escenarios que no van de economía.
func _plan_drag(from_cell, to_cell, factory_array, bag = null, charge_cost: bool = false) -> Dictionary:
	# La regla de gesto de M1, que ni M7 ni M5b tocan: pulsar y soltar en la MISMA celda es el
	# click de siempre (radial si está libre, panel si está ocupada), nunca un arrastre.
	if from_cell == to_cell:
		return {};
	if _tile_map == null:
		return {};
	for path in _candidate_paths(from_cell, to_cell):
		var span = _belt_range(path, factory_array);
		if not _path_fits(path, span, factory_array):
			continue;
		# El dinero, LO ÚLTIMO y con la misma regla de todo o nada que la geometría: se calcula
		# el precio del tramo COMPLETO —el que va a llevar cinta, no el camino— y se compara
		# antes de confirmar nada.
		#
		# 🔴 Y se comprueba sobre el camino YA ELEGIDO, sin probar la otra L: el dinero no
		# elige trazado. Puede hacerlo porque las dos L cuestan lo MISMO por construcción —el
		# largo es la distancia manhattan + 1 en las dos, y `_belt_range()` solo recorta los
		# extremos, que son las mismas dos casillas en las dos—, así que si no alcanza para una
		# tampoco alcanza para la otra. Si algún día el recorte mirase celdas de en medio, esto
		# dejaría de ser cierto y habría que decidir si el precio puede elegir camino; hoy no
		# puede, y es deliberado: un trazado que cambia según lo que llevas en la bolsa no se
		# puede predecir.
		if charge_cost and not can_afford_belt(span.y - span.x + 1, bag):
			return {};
		return {"path": path, "first": span.x, "last": span.y};
	return {};

# El camino que el arrastre tendería DE VERDAD, incluidos sus dos extremos, o [] si ninguna de
# las dos L cabe. Es el mismo trazado que va a usar `place_drag()`, porque sale de la misma
# función: quien necesite saberlo por adelantado pregunta aquí y no a `trace_path()`, que solo
# conoce la L preferente.
func resolve_drag_path(from_cell, to_cell, factory_array) -> Array:
	var plan = _plan_drag(from_cell, to_cell, factory_array);
	return plan.get("path", []);

# ¿Cabe el arrastre entero? Es exactamente la pregunta que `place_drag()` se hace a sí misma,
# resuelta por la misma función, así que validar y tender no pueden discrepar.
func can_place_drag(from_cell, to_cell, factory_array, bag = null, charge_cost: bool = false) -> bool:
	return not _plan_drag(from_cell, to_cell, factory_array, bag, charge_cost).is_empty();

# Tiende la cinta. Devuelve las celdas creadas en orden —que son las del camino elegido SIN los
# extremos ocupados (M7)—, o [] si ninguna de las dos L cabía entera, si la que cabía no dejaba
# ninguna celda que tender, o (con `charge_cost`) si no había dinero para pagarla completa. En
# los tres casos no se ha tocado NADA: ni un segmento, ni la bolsa, ni un búfer, ni se ha
# emitido la señal.
func place_drag(from_cell, to_cell, factory_array, bag = null, charge_cost: bool = false) -> Array:
	# El trazado se resuelve AQUÍ y una sola vez, y de este mismo plan salen la validación, las
	# celdas que se tienden y lo que se cobra. Volver a llamar a `trace_path()` por su cuenta
	# —como hacía hasta M5b, cuando solo había una L posible— tendería un camino que nadie ha
	# validado en cuanto la L preferente no quepa.
	var plan = _plan_drag(from_cell, to_cell, factory_array, bag, charge_cost);
	if plan.is_empty():
		return [];
	var cells = _build_chain(plan["path"], plan["first"], plan["last"]);
	# Se cobra por las casillas que _build_chain() acaba de tender, y no por una segunda
	# cuenta del camino: la validación de arriba miró ese mismo tramo del mismo plan, así que
	# lo comprobado y lo cobrado son el mismo número por construcción. Va antes del flush y del
	# emit para que quien escuche la señal vea la bolsa ya pagada.
	if charge_cost:
		pay_belt_cost(cells.size(), bag);
	# El camino acaba de existir: las factorías paradas por búfer lleno (M4) se vacían AQUÍ, en
	# el mismo gesto, sin esperar a su tick. Es el «al tenderle una cinta al almacén, vacía su
	# búfer y sigue» del hito, y va antes del emit para que quien escuche la señal vea ya el
	# estado asentado.
	flush_output_buffers();
	_redraw();
	belt_network_changed.emit();
	return cells;

# Encadena los segmentos del tramo [first, last] de un camino ya validado, y devuelve sus
# celdas en orden. El primero mira hacia atrás por donde vendría el material (su `dir_in` es
# el opuesto del paso que lo trajo hasta él) y el último sigue hacia donde lo entregaría (su
# `dir_out` es el paso siguiente): así los dos extremos apuntan a la casilla de la factoría
# que se les pegue, que es lo que deliver() busca desde M2.
#
# Los vecinos se leen de `path` ENTERO y no del tramo, y eso es lo que hace que M7 funcione
# sin tocar el contrato: si un extremo se recortó por estar ocupado, ese extremo es justo el
# paso que orienta a su segmento, así que la punta apunta a la factoría que el jugador tocó al
# arrastrar. Solo cuando el tramo llega al borde del camino —arrastre entre dos celdas libres,
# como hasta M6— se cae al «mira hacia atrás / sigue recto» de M1.
func _build_chain(path, first, last) -> Array:
	var cells = [];
	for i in range(first, last + 1):
		var prev_dir = path[i] - path[i - 1] if i > 0 else path[i + 1] - path[i];
		var next_dir = path[i + 1] - path[i] if i < path.size() - 1 else prev_dir;
		belts[path[i]] = BeltSegment.new(path[i], -prev_dir, next_dir);
		cells.append(path[i]);
	return cells;

# Demoler un segmento NO recablea a sus vecinos: sus `dir_in`/`dir_out` siguen apuntando al
# hueco y la cadena queda PARTIDA, que es exactamente lo que el jugador ha pedido al borrarlo.
func remove_belt(cell) -> bool:
	if not belts.has(cell):
		return false;
	belts.erase(cell);
	_redraw();
	belt_network_changed.emit();
	return true;

# ---------- la propagación ----------

# Entrega `amount` de `material` producido en `from_cell` a través de la red.
#
# SIN EXCEPCIÓN POR ADYACENCIA (decidido el 2026-09-18): una factoría vecina NO recibe nada si
# no hay cinta de por medio. Como entre dos casillas pegadas no cabe un segmento, encadenar
# obliga a separarlas — y a perder su sinergia de adyacencia. Ésa es la tensión del diseño:
# elegir entre pegar la línea y tenderla.
#
# Arranca en el segmento cuyo `dir_in` apunte a `from_cell` (si no hay, devuelve 0) y recorre
# siguiendo `dir_out` hasta uno de estos finales:
#   · factoría que declara `material` en su `recieve` -> suma a su input_buffer; devuelve amount
#   · almacén (`type: "storage"`) -> acepta lo que sea y lo vuelca en la bolsa en su tick
#   · celda sin cinta ni destino válido, o filtro que rechaza -> devuelve 0
#
# Devuelve lo entregado: 0 o `amount`, nunca una entrega parcial —la cinta es una conexión
# lógica, no un simulador de tránsito—. Lo que no se entrega SE PIERDE hasta M4, que le dará
# búfer de salida a la factoría.
#
# El recorrido en sí ya no vive aquí sino en `route_destination()`, y la entrega en
# `deliver_via()`: lo que esta función aporta es la elección de cinta —«la primera que salga»—,
# que es exactamente lo único que el almacén emisor (2026-09-23) necesitaba poder cambiar.
func deliver(from_cell, material, amount) -> int:
	# El PRIMER segmento de salida, que hasta hoy era el único camino que la red sabía tomar.
	# Se conserva exactamente así para los llamadores de siempre —una factoría de producción
	# fabrica UNA cosa y le da igual por dónde salga—, y quien tenga que ELEGIR cinta llama a
	# `deliver_via()`: es el caso del almacén desde que emite a cada uno de sus consumidores
	# (ver factoryData._tick_storage_emit()).
	return deliver_via(from_cell, _entry_segment(from_cell), material, amount);

# Lo mismo que deliver(), pero EMPEZANDO POR UN SEGMENTO DADO en vez de por «el primero que
# salga de la celda».
#
# 🔴 POR QUÉ EXISTE (2026-09-23, el almacén emisor). `_entry_segment()` devuelve el primer
# vecino cuyo `dir_in` apunte a la celda, así que un almacén con DOS cintas de salida metía
# todo lo que emitía por la misma: la segunda línea no recibía nada, y encima dos emisiones
# del mismo material en el mismo tick se apilaban sobre el primer destino. El almacén planea
# ahora una emisión POR CINTA y le dice a la red por cuál va cada una, que es lo único que
# `deliver()` no sabía preguntar.
#
# El contrato de deliver() se conserva entero: 0 o `amount`, nunca una entrega parcial.
func deliver_via(from_cell, seg, material, amount) -> int:
	if material == null or amount <= 0 or seg == null:
		return 0;
	var dest = route_destination(from_cell, seg, material);
	if dest == null:
		return 0;
	# El almacén (M3) acepta CUALQUIER material: no declara `recieve` y su trabajo es
	# volcar en la bolsa global lo que le llegue. Lo que filtra, si algo, es la cinta.
	# El volcado en sí NO ocurre aquí sino en el tick del almacén
	# (factoryData._tick_storage()), que es quien tiene la bolsa: la red deja el material
	# en su búfer de entrada igual que con cualquier otra factoría.
	if dest.factory_type == "storage":
		dest.receiveMaterial(material, amount);
		return amount;
	if dest.itemNeeded.has(material):
		dest.receiveMaterial(material, amount);
		return amount;
	return 0;

# La factoría que hay al final de la cinta que arranca en `seg`, o `null` si el camino no
# termina en ninguna. Es el recorrido que deliver() llevaba dentro desde M2, extraído para que
# el almacén pueda preguntar A QUIÉN alimenta una cinta ANTES de decidir qué le manda: hasta
# hoy la única forma de saberlo era emitir y ver si colaba.
#
# `material` es OPCIONAL y cambia lo que se pregunta:
#   · con material  -> «¿llega ESTE material hasta el final?», así que los filtros de la cinta
#     (M5) pueden cortar el camino y devolver null;
#   · sin material (null) -> «¿a quién lleva esta cinta?», y los filtros NO se miran: quien
#     pregunta todavía no ha elegido qué mandar, y es justo lo que el destino le va a decir.
#
# Lo que NO cambia es el resto del contrato de M2, que vive aquí desde entonces: tope de
# saltos Y set de visitadas (un bucle de cintas es trivial de construir arrastrando en
# círculo, y sin las dos cosas la primera entrega colgaría el juego; el set corta el ciclo
# exacto y el tope cubre cualquier camino patológico que el set no vea venir), y el guardia de
# «nadie se entrega a sí mismo», que importa desde M5, cuando el almacén EMITE: un almacén con
# una cinta que da la vuelta y vuelve a él sacaría de la bolsa y se lo volvería a meter cada
# tick —un ciclo que no duplica nada pero tampoco hace nada—. El set de visitadas no lo ve: el
# bucle se cierra por fuera de la cinta, en la factoría.
func route_destination(from_cell, seg, material = null):
	if seg == null:
		return null;
	var visited = {};
	for _paso in range(MAX_PATH):
		if visited.has(seg.cell):
			return null;
		visited[seg.cell] = true;
		# El filtro de la cinta (por defecto "" = acepta todo). Su interfaz es M5; la regla de
		# rechazo es del contrato de deliver() y vive aquí desde M2.
		if material != null and seg.filter != "" and seg.filter != material:
			return null;
		var next_cell = seg.cell + seg.dir_out;
		var next_seg = belts.get(next_cell, null);
		if next_seg != null:
			seg = next_seg;
			continue;
		# Se acabó la cinta: o hay destino en esa celda o el material se pierde.
		var dest = factory_at(next_cell);
		if dest == null:
			return null;
		if dest.cell_position == from_cell:
			return null;
		return dest;
	return null;

# El segmento por el que el material sale de `from_cell`: uno de los cuatro vecinos ortogonales
# cuyo `dir_in` apunte de vuelta a la celda. Por eso _build_chain() hace que el primer segmento
# de un arrastre mire hacia atrás: así el extremo apunta a la casilla de la factoría que se le
# pegue.
func _entry_segment(from_cell):
	for dir in ORTHOGONAL_DIRS:
		var seg = belts.get(from_cell + dir, null);
		if seg != null and seg.cell + seg.dir_in == from_cell:
			return seg;
	return null;

# TODOS los segmentos por los que sale material de `from_cell`, hasta cuatro, y no solo el
# primero. Lo estrena el almacén emisor (2026-09-23), que tiene que repartir entre las cintas
# que salen de él en vez de volcarlo todo por una.
#
# 🔴 EL ORDEN ES FIJO Y ES EL DE `ORTHOGONAL_DIRS` —derecha, izquierda, abajo, arriba—, no el
# de `belts`. No es cosmética: este proyecto mide con IGUALDAD EXACTA (los cuatro golden de
# tests/run_tests.gd), y con las existencias justas para un solo destino quién se las lleva
# decide la curva entera. Recorrer el diccionario `belts` haría depender la emisión del orden
# de inserción de los segmentos —o sea, del orden en que el jugador tendió las cintas— y dos
# runs idénticas dejarían de medir lo mismo.
func output_segments(from_cell) -> Array:
	var segs = [];
	for dir in ORTHOGONAL_DIRS:
		var seg = belts.get(from_cell + dir, null);
		if seg != null and seg.cell + seg.dir_in == from_cell:
			segs.append(seg);
	return segs;

# ---------- el filtro de la cinta (M5) ----------

# El segmento por el que una factoría saca el material: el mismo que busca deliver(), pero
# público, porque ui/factoryPanel.gd necesita saber si la factoría del panel tiene cinta de
# salida y cuál es, para ofrecer (o no) el control del filtro.
#
# Sigue devolviendo UNO —el primero— y por eso no lo sustituye `output_segments()`: el panel
# edita el filtro de UNA cinta, la de salida, y ese control no se ha rediseñado para varias.
# Quien quiera las cuatro pregunta por la otra.
func output_segment(from_cell):
	return _entry_segment(from_cell);

# El filtro de una celda con cinta. "" si no hay cinta: el mismo valor que «acepta todo», que
# es lo que una casilla sin cinta hace de todas formas.
func get_belt_filter(cell) -> String:
	var seg = belts.get(cell, null);
	return seg.filter if seg != null else "";

# Pone el filtro de un segmento. "" (o null) lo levanta y la cinta vuelve a aceptar todo; un
# material lo restringe a ése y solo a ése. La REGLA de rechazo ya vive en deliver() desde M2
# —`if seg.filter != "" and seg.filter != material: return 0`—; lo que faltaba, y es lo que M5
# añade, es la forma de ponerlo.
#
# Emite `belt_network_changed` como place_drag() y remove_belt(): lo que la red entrega ha
# cambiado, y quien la esté mirando —el panel abierto— se quedaría enseñando algo viejo. Y
# vacía por el camino los búferes de salida (M4): levantar un filtro puede ser exactamente el
# camino que le faltaba a una factoría parada, igual que tender la cinta.
func set_belt_filter(cell, material) -> bool:
	var seg = belts.get(cell, null);
	if seg == null:
		return false;
	var nuevo = "" if material == null else str(material);
	if seg.filter == nuevo:
		return false;
	seg.filter = nuevo;
	flush_output_buffers();
	_redraw();
	belt_network_changed.emit();
	return true;

# ---------- el búfer de salida (M4) ----------

# Vacía por la red el búfer de salida de una factoría parada. Devuelve lo entregado: 0 o el
# búfer entero, nunca una parte —la cinta es una conexión lógica y deliver() no hace entregas
# parciales—, así que o se desatasca del todo o sigue igual de parada.
#
# Se llama desde place_drag() (el camino acaba de aparecer), desde Main._on_factory_chosen()
# (la factoría nueva puede ser el destino que faltaba al final de una cinta ya tendida) y desde
# Main._on_resource_produced() cuando una entrega cuela y la factoría arrastraba atasco.
func flush_output(fab) -> int:
	if fab == null or not is_instance_valid(fab):
		return 0;
	if fab.output_buffer <= 0:
		return 0;
	var moved = deliver(fab.cell_position, fab.production, fab.output_buffer);
	if moved > 0:
		fab.clearOutputBuffer();
	return moved;

# Todas las factorías de la red. Recorre el array vivo que inyecta Main, y para las que no
# tienen nada atascado —la inmensa mayoría— es una comparación y nada más.
func flush_output_buffers() -> int:
	var total = 0;
	for fab in _factory_array:
		total += flush_output(fab);
	return total;

# ---------- la cache de factorías (la consume deliver()) ----------

# La factoría de una celda, por diccionario y no recorriendo `factoryArray`: indexar evita un
# recorrido lineal de la lista en cada entrega.
func factory_at(cell):
	if not _factory_index_ready:
		_rebuild_factory_index();
	return _factory_index.get(cell, null);

func _rebuild_factory_index():
	_factory_index.clear();
	for fab in _factory_array:
		if is_instance_valid(fab):
			_factory_index[fab.cell_position] = fab;
	_factory_index_ready = true;

func invalidate_factory_index():
	_factory_index.clear();
	_factory_index_ready = false;

# ---------- dibujo ----------

func _ensure_overlay():
	if _tile_map == null:
		return;
	if _overlay != null and is_instance_valid(_overlay):
		return;
	_overlay = BeltOverlay.new();
	_overlay.name = "BeltOverlay";
	_overlay.belt_network = self;
	# 2 = por encima del TintOverlay (1) y de la capa 2 de sprites: una cinta tapa el tinte de
	# su casilla, no al revés.
	_overlay.z_index = 2;
	_tile_map.add_child(_overlay);

func _redraw():
	if _overlay != null and is_instance_valid(_overlay):
		_overlay.queue_redraw();

# Punto medio del borde de la casilla en la dirección `dir`, en coordenadas locales del
# TileMap. Sale de la geometría del propio mapa (medio vector hacia la celda vecina) en vez de
# a ojo, así que vale para cualquier tamaño de tile isométrico.
func _edge_point(cell, dir) -> Vector2:
	var center = _tile_map.map_to_local(cell);
	return center + (_tile_map.map_to_local(cell + dir) - center) * 0.5;

# La dibuja el BeltOverlay, no el TileMap (ver la cabecera de la clase). `target` es el canvas
# item que pinta: las llamadas draw_*() solo salen por el nodo que las ejecuta.
func draw_belts(target):
	if _tile_map == null or _tile_map.tile_set == null:
		return;
	for cell in belts:
		var seg = belts[cell];
		var center = _tile_map.map_to_local(cell);
		# Base: el rombo de la casilla, como el tinte, para que se lea qué casilla ocupa.
		var hw = 32.0;
		var hh = 16.0;
		target.draw_colored_polygon(PackedVector2Array([
			center + Vector2(0, -hh),
			center + Vector2(hw, 0),
			center + Vector2(0, hh),
			center + Vector2(-hw, 0),
		]), Color(0.15, 0.15, 0.18, 0.75));
		# Y encima la orientación: entrada -> centro -> salida, con punta de flecha en la
		# salida. Sin la punta, una cinta y la misma cinta del revés se ven igual.
		var p_in = _edge_point(cell, seg.dir_in);
		var p_out = _edge_point(cell, seg.dir_out);
		target.draw_polyline(PackedVector2Array([p_in, center, p_out]), Color(0.95, 0.75, 0.15, 1.0), 3.0);
		var forward = (p_out - center).normalized();
		if forward.length() > 0.0:
			var side = Vector2(-forward.y, forward.x);
			target.draw_colored_polygon(PackedVector2Array([
				p_out,
				p_out - forward * 9.0 + side * 5.0,
				p_out - forward * 9.0 - side * 5.0,
			]), Color(0.95, 0.75, 0.15, 1.0));
