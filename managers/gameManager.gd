extends Node

# `granted_upgrade_ids` son las mejoras que la run recibe SIN elegirlas (ver
# _granted_upgrades()). Viajan con la señal y no se aplican aquí porque quien sabe aplicar
# una mejora es Main, igual que con las elegidas.
signal checkpoint_reached(offered_upgrade_ids, rewards, granted_upgrade_ids);
signal run_won(stats);
signal run_lost(stats);

var checkpoints = [];
var current_checkpoint_index = 0;
var upgrades_catalog = {};
var factories_catalog = {};
var run_time = 0.0;
# Momento en que se cerró el checkpoint anterior: lo que hay entre él y `run_time` es el
# tramo que se mide para decidir la calidad de la recompensa.
var last_checkpoint_time = 0.0;
var active = true;
var production_done = false;
# Material del checkpoint en curso que YA estaba en la bolsa cuando arrancó el tramo. No es
# ritmo del tramo: es trabajo del tramo anterior, y sin descontarlo un objetivo cubierto de
# antemano se cerraría en un frame y regalaría la recompensa potente (ver _reference_time()).
var segment_start_stock = 0;
# El Player de la run, solo para consultar qué factorías tiene ya disponibles. Se guarda el
# nodo y no una copia de la lista a propósito: `Main._apply_upgrade()` y la pantalla del
# factory token amplían `availableFactories` durante la partida, y una copia haría que el
# siguiente checkpoint volviera a ofrecer lo que acabas de desbloquear.
var player_node = null;
# Las factorías vivas de la run (`Main.factoryArray`). Se guarda la referencia al array y no
# una copia porque Main lo muta al construir y al demoler —igual que hace factoryPlacer—, y
# una copia mediría la línea de hace un checkpoint.
var factory_nodes = [];
# Integral del ritmo instalado a lo largo del tramo en curso, y los segundos que cubre. La
# media de las dos es la línea que el jugador tuvo DE VERDAD durante el tramo.
var segment_capacity_area = 0.0;
var segment_capacity_time = 0.0;
var last_capacity_sample = 0.0;
# El TileMap de la run, solo para la condición 3 del punto muerto: «¿queda alguna casilla
# construible?». Se guarda el nodo por lo mismo que player_node y factory_nodes — es estado
# vivo de la partida, no datos del JSON — y mientras nadie lo inyecte el punto muerto no se
# evalúa (ver _evaluate_deadlock).
var tile_map_node = null;
# Las tres observaciones del punto muerto (ver _evaluate_deadlock).
# Lo que había en la bolsa de TODO lo que el checkpoint en curso cobra, la última vez que se
# miró: si sube, se ha producido algo de verdad.
var last_pending_quantity = 0;
# El total_pollution de la última mirada: si baja, algo está limpiando.
var last_seen_pollution = 0.0;
# El `run_time` en que se abrió la ventana de punto muerto, 0.0 si no hay ninguna abierta.
# Guarda el instante y no los segundos acumulados porque update() no recibe delta —la llama
# Main._process() cada frame— y porque run_time ya se congela con `active = false`, así que
# la gracia no corre con la pantalla de mejora abierta. Es el mismo truco que segment_time
# contra last_checkpoint_time. El único caso raro que tiene, que run_time valga exactamente
# 0.0 en el frame en que se abre, retrasa la ventana un frame en un mapa que al arrancar la
# run ya no tuviera ni una casilla libre: no existe, y aunque existiera no cambia nada.
var deadlock_timer = 0.0;

# Fracción del techo de tu propia línea que hay que sostener para merecer la recompensa
# potente. 0.55 sale del barrido de M7 —nueve runs enteras, 45 tramos medidos—: una línea
# alimentada, pegada y con los workers puestos rinde entre 0,59 y 1,00 de su techo, y una
# sobreconstruida, desparramada o con la sierra sin madera que darle cae a 0,26-0,52. El
# listón se pone en medio de ese hueco. Sensibilidad sobre esos mismos tramos: con 0,35 el
# tier 2 se lleva 27 de 37 checkpoints —casi el regalo que M7 vino a quitar—, con 0,55-0,65
# se queda en 19-20, y con 0,80 baja a 8, que es no llegar ni jugando bien.
const TIER2_EFFICIENCY = 0.55;

# Segundos seguidos que las tres condiciones del punto muerto tienen que cumplirse a la vez
# para declarar muerta la run. 25,0 sale MEDIDO del spike de M6 (tests/sim_derrota.gd,
# bloque 4), que cronometra lo único que fija el suelo: cuánto tarda LA JUGADA que desatasca
# en romper una condición, contada desde que se coloca.
#   Reforester sobre suciedad (rompe la 2, es su tick).......  5 s
#   WoodCutter sobre casilla limpia (rompe la 1)..............  4 s
#   WoodCutter sobre casilla a medio ahogar, choke 0,50.......  8 s
#   WoodCutter sobre casilla casi cerrada, choke 0,25......... 16 s
#   WoodCutter sobre casilla a punto de cerrarse, choke 0,10.. 44 s
# El ahogo es lo que alarga la espera, no el `tick` del JSON: production_debt suelta una
# unidad cada ceil(1/choke) ticks, así que la última casilla libre de un mapa medio saturado
# —que está sucia, no limpia— multiplica por cuatro el tiempo hasta la primera entrega. 25,0
# cubre esos 16 s con margen para que el jugador lea el aviso de M5 y reaccione (~9 s), y
# deja FUERA a propósito el caso de choke 0,10: una línea que entrega una unidad cada 44 s
# sobre un mapa donde nadie limpia y no queda dónde construir está muerta, aunque se mueva.
# Y no más: la gracia es exactamente el tiempo que el jugador pasa mirando una pantalla
# sentenciada con la cuenta atrás delante.
const DEADLOCK_GRACE = 25.0;

# Presupuesto de caracteres de la línea del HUD. El Label `Objective` de Main.tscn es UNA
# línea a 1280 px y no hace wrap: lo que no cabe se corta a media palabra y se pierde. El 155
# sale medido en captura de pantalla —la línea del colapso de M5 tenía ~200 caracteres y se
# cortaba en `… | Contamin`—, no de una estimación.
# No lo lee el runtime: recortar el texto sería peor que pasarse, porque lo que se caería es
# justo lo que el jugador necesita leer. Lo lee la PRUEBA de longitud de la suite, que es la
# única forma de que esto no vuelva a romperse en headless, que es donde se rompió: mirando
# el juego en pantalla se ve, ejecutando la suite entera no.
const HUD_MAX_CHARS = 155;

func initialize(fileData):
	if fileData.has("Checkpoints"):
		checkpoints = fileData["Checkpoints"];
	else:
		checkpoints = [{ "material": "plank", "quantity": 5, "label": "Objetivo" }];
	if fileData.has("Upgrades"):
		upgrades_catalog = fileData["Upgrades"];
	# Las factorías se guardan por su `tick` y su `material`: son la referencia con la que se
	# juzga si un tramo fue rápido (ver _reference_time()).
	if fileData.has("Factories"):
		factories_catalog = fileData["Factories"];

# Inyección desde Main, al montar la run. Va en su propio setter y no en initialize() porque
# lo que llega no son datos del JSON sino el estado vivo de la partida.
func setPlayer(node):
	player_node = node;

# Igual que setPlayer(): lo que llega es estado vivo de la partida, no datos del JSON. Con
# esto el tier puede compararse contra la línea que el jugador ha construido (ver
# _installed_rate()) en vez de contra una factoría imaginaria.
func setFactories(array):
	factory_nodes = array;

# Tercer trozo de estado vivo que Main inyecta, y por el mismo motivo que los dos de arriba.
# Lo pide la condición 3 del punto muerto: quién sabe qué casillas existen es el TileMap, y
# recorrer un rango a ojo desde aquí sería inventarse unos límites de mapa que salen del JSON
# y cambian con cada mapa.
func setTileMap(node):
	tile_map_node = node;

func _process(delta):
	if active:
		run_time += delta;

func update(bag, pollution_manager = null):
	if not active:
		# La reserva describe el estado de la partida, no el de la evaluación: sigue vigente
		# con la pantalla de mejora abierta y se levanta sola al ganar.
		_sync_reserve(bag);
		return;

	# Fase de producción: evaluar checkpoints en orden
	if not production_done:
		if current_checkpoint_index >= checkpoints.size():
			production_done = true;
		else:
			var cp = checkpoints[current_checkpoint_index];
			# Antes de mirar si el checkpoint se cierra: la muestra tiene que recoger el
			# trozo de tramo que acaba de correrse con la línea que había durante él.
			_sample_capacity(cp);
			if _can_afford(bag, cp):
				# El cobro va aquí, en update(), y no en _process: `active = false` congela
				# la evaluación pero NO el árbol, así que desde _process se seguiría
				# cobrando con la pantalla de mejora abierta.
				_charge_checkpoint(bag, cp);
				var rewards = cp.get("rewards", {});
				# El tramo se mide aquí y no en _process porque `run_time` se congela con
				# `active = false` mientras la pantalla de mejora está abierta: así el tramo
				# es tiempo jugado, no tiempo de reloj.
				var segment_time = run_time - last_checkpoint_time;
				var tier = _evaluate_performance(cp, segment_time, segment_start_stock,
					_segment_rate());
				last_checkpoint_time = run_time;
				current_checkpoint_index += 1;
				# El tramo siguiente mide su línea desde cero: arrastrar la media del
				# anterior juzgaría trabajo nuevo con la fábrica de hace un checkpoint.
				_reset_capacity();
				# Y la cuenta atrás del punto muerto vuelve a cero: cerrar un checkpoint es la
				# prueba más fuerte que hay de que la run se mueve. Sin esto, el peaje que se
				# acaba de cobrar BAJA la bolsa, la condición 1 leería «no se ha producido
				# nada» y un checkpoint cerrado in extremis contaría a favor de la derrota en
				# vez de en contra.
				_reset_deadlock();
				# El arranque del tramo siguiente se mide DESPUÉS de cobrar objetivo y
				# mantenimiento: lo que sobrevive a los dos es lo que el jugador ya no
				# tendrá que producir, y el mantenimiento se come justo esa ventaja.
				segment_start_stock = _stock_for_current(bag);
				if current_checkpoint_index >= checkpoints.size():
					# Solo se marca el fin de la producción. La victoria NO se dispara aquí
					# aunque el mapa ya esté limpio: la rama de restauración de abajo corre
					# en esta misma llamada y la comprobaría otra vez, así que `run_won` se
					# emitía dos veces y el runSummary se montaba dos veces con él. Un único
					# sitio donde se gana y el bug no puede volver.
					production_done = true;
				else:
					# Las cartas que desatascan la run se conceden, no se ofrecen: ver
					# _granted_upgrades(). Se quitan de la oferta porque al llegar a la
					# pantalla ya están aplicadas y serían cartas muertas.
					var granted = _granted_upgrades();
					active = false;
					checkpoint_reached.emit(_pick_upgrades(3, tier, granted), rewards, granted);
	# Fase de restauración: esperar a que la contaminación baje. Es el único punto del que
	# sale la victoria, también el de la producción que acaba de terminar con el mapa limpio.
	if production_done:
		if pollution_manager == null or pollution_manager.isRestored():
			_triggerWin(pollution_manager);
	# El punto muerto se evalúa DESPUÉS de los checkpoints y de la restauración, y solo si la
	# run sigue activa: cerrar un checkpoint y ganar apagan los dos `active`, así que un
	# checkpoint cerrado in extremis sigue contando y perder nunca puede adelantar a ganar.
	if active:
		_evaluate_deadlock(bag, pollution_manager);
	# Al final y no al principio: con el índice ya avanzado, el peaje apartado es siempre el
	# del checkpoint que toca ahora y no el del que se acaba de cerrar.
	_sync_reserve(bag);

# Todo lo que un checkpoint se lleva de la bolsa: el objetivo más su `maintenance`, que es
# un dict `material -> cantidad`. Si el mantenimiento pide el mismo material que el objetivo
# se suman, porque salen de la misma bolsa y el jugador tiene que juntar los dos.
func _checkpoint_cost(checkpoint):
	var cost = {};
	cost[checkpoint.get("material", "")] = int(checkpoint.get("quantity", 0));
	var maintenance = _maintenance_cost(checkpoint);
	for material in maintenance:
		cost[material] = cost.get(material, 0) + maintenance[material];
	return cost;

# Solo el peaje, sin el objetivo. Se mira aparte porque el peaje se reserva siempre y el
# objetivo solo a veces (ver _reserved_materials()).
func _maintenance_cost(checkpoint):
	var cost = {};
	var maintenance = checkpoint.get("maintenance", {});
	for material in maintenance:
		var quantity = int(maintenance[material]);
		if quantity > 0:
			cost[material] = cost.get(material, 0) + quantity;
	return cost;

# Lo que el almacén APARTA del checkpoint en curso: las factorías no pueden quemarlo como
# insumo (Bag.getAvailable() → factoryData.checkNeeds()). Son dos cosas:
#
#  1. **El peaje entero.** Se paga en `wood`, que es además el insumo de la serrería que
#     fabrica el `plank` del objetivo: objetivo y peaje compiten por la misma materia prima,
#     así que acelerar la serrería —«Sierra industrial»— se comía la madera antes de que
#     llegara a cubrirlo y el checkpoint, que desde M4 exige el peaje entero, no se cerraba
#     jamás. Medido antes de M6: `ecologist` clavada en 2/5 y `standard` en 3/5 tras 900 s.
#  2. **El objetivo, si es una materia prima** (_is_raw_material()). Una materia prima es la
#     raíz de la cadena: quien se la come por debajo de lo exigido bloquea el checkpoint para
#     siempre, porque no hay nada más arriba que la reponga aparte de su propia factoría.
#     Es lo que colgaba el primer checkpoint —15 `wood`— en cuanto el jugador levantaba dos
#     serrerías nada más empezar, sin haber cogido una sola mejora.
#
# Y NO se aparta el objetivo cuando es un material procesado (`plank`): comérselo solo
# retrasa el checkpoint —su productora sigue fabricando del excedente de madera—, mientras
# que apartarlo dejaría a la MetaFactory y al WorkerCamp sin poder consumir un solo tablón en
# toda la fase de producción (el checkpoint se cierra en el frame exacto en que se alcanza la
# cantidad, así que nunca habría excedente), y una factoría que no hace nada es justo el bug
# que este plan lleva entero quitando.
#
# Con esto, de cada material que un checkpoint exige y que alguna factoría consume como
# insumo: o bien está reservado, o bien solo lo consumen factorías que ninguna mejora del
# catálogo puede acelerar. La suite lo fija como invariante y no como casualidad.
func _reserved_materials(checkpoint):
	var reserve = _maintenance_cost(checkpoint);
	var material = checkpoint.get("material", "");
	if material != "" and _is_raw_material(material):
		reserve[material] = reserve.get(material, 0) + int(checkpoint.get("quantity", 0));
	return reserve;

# Materia prima: la fabrica alguna factoría que no consume nada, así que su ritmo no depende
# de ningún otro material. Sale del catálogo y no de una lista de nombres, como todo lo que
# describe a las factorías en este proyecto.
func _is_raw_material(material):
	for factory_name in factories_catalog:
		var factory = factories_catalog[factory_name];
		if factory.get("material", null) != material:
			continue;
		var inputs = factory.get("recieve", null);
		if inputs == null or inputs.is_empty():
			return true;
	return false;

func _sync_reserve(bag):
	if bag == null or not bag.has_method("setReserved"):
		return;
	if production_done or current_checkpoint_index >= checkpoints.size():
		bag.setReserved({});
		return;
	bag.setReserved(_reserved_materials(checkpoints[current_checkpoint_index]));

# El checkpoint no se supera hasta que el almacén cubre objetivo Y mantenimiento. Es un
# requisito y no un cobro a lo que haya, porque el checkpoint salta el frame exacto en que
# se alcanza la cantidad: medido con la curva de este hito, en ese instante la bolsa tiene
# entre 0 y 8 maderas, así que un mantenimiento «de lo que haya» se cobraría casi siempre a
# cero y el coste sería humo. Como requisito se cobra entero, coincide con lo que el HUD
# anuncia y obliga a sostener la línea de madera en vez de reconvertirla toda a tablones.
# No puede colgar la run, y desde M6 no es solo porque `wood` no necesite inputs y los tres
# StartingPackages traigan WoodCutter: además la bolsa reserva el peaje (_sync_reserve()),
# así que ninguna factoría puede comerse la madera que falta para cubrirlo.
func _can_afford(bag, checkpoint):
	var cost = _checkpoint_cost(checkpoint);
	for material in cost:
		if bag.getQuantity(material) < cost[material]:
			return false;
	return true;

# Devuelve lo cobrado para que las pruebas puedan afirmarlo sin espiar la bolsa.
func _charge_checkpoint(bag, checkpoint):
	var cost = _checkpoint_cost(checkpoint);
	for material in cost:
		bag.removeFromBag(material, cost[material]);
	return cost;

# Cuánto material del checkpoint en curso hay ya en la bolsa. 0 si no queda checkpoint.
func _stock_for_current(bag):
	if current_checkpoint_index >= checkpoints.size():
		return 0;
	return bag.getQuantity(checkpoints[current_checkpoint_index].get("material", ""));

# El punto muerto: aquí no hay ningún «demasiado sucio». La run se declara muerta cuando
# durante DEADLOCK_GRACE segundos SEGUIDOS se cumplen las tres a la vez —no se produce nada,
# nadie limpia y no queda dónde construir—, porque las tres juntas significan que ninguna
# acción disponible altera nada. No es una heurística de «vas mal»: es un punto muerto
# demostrado, y cualquiera de las tres que se rompa devuelve el timer a cero, así que la
# cuenta atrás siempre es cancelable.
func _evaluate_deadlock(bag, pollution_manager):
	# Sin PollutionManager o sin TileMap faltan dos de las tres observaciones y no se puede
	# demostrar nada, así que la ventana se cierra en vez de darse por cumplida. Es el caso de
	# las pruebas que llaman update(bag) a secas — y el de la partida hasta que Main inyecta
	# el TileMap—: callar es lo correcto, matar a ciegas no.
	if pollution_manager == null or tile_map_node == null or not is_instance_valid(tile_map_node):
		deadlock_timer = 0.0;
		return;
	# 1. No se ha producido ni una unidad de lo que el checkpoint pendiente exige. Se mide
	#    mirando la bolsa y NO _installed_rate(), que suma el techo de toda factoría que
	#    fabrique el material tenga workers o no: eso juzga bien el tier, pero de producción
	#    real no dice nada.
	var pending = _pending_quantity(bag);
	var produced = pending > last_pending_quantity;
	last_pending_quantity = pending;
	# 2. La contaminación total no ha bajado. Una sola observación que cubre a la vez los
	#    Reforester parados y los tiles que limpian solos (el lago): si algo estuviera
	#    limpiando, las casillas se desbloquearían por su cuenta y habría salida. El epsilon
	#    es ruido de coma flotante, no tolerancia — limpiar de verdad mueve décimas.
	var pollution = pollution_manager.total_pollution;
	var cleaned = pollution < last_seen_pollution - 0.0001;
	last_seen_pollution = pollution;
	if produced or cleaned:
		deadlock_timer = 0.0;
		return;
	# 3. No queda ninguna casilla construible. Va la última y solo cuando las dos baratas ya
	#    se cumplen porque es la cara: recorre el mapa entero preguntando canPlaceFactory(),
	#    que a su vez recorre las factorías vivas. Medido antes de darlo por bueno: el peor
	#    caso —16x10 casillas, 20 factorías y ninguna casilla libre, o sea el barrido entero—
	#    cuesta 0,06 ms por llamada, un 0,4 % de un frame a 60 fps. No hace falta espaciar la
	#    evaluación, así que no se espacia: un punto muerto evaluado a saltos daría avisos que
	#    parpadean.
	if tile_map_node.hasBuildableCell(factory_nodes):
		deadlock_timer = 0.0;
		return;
	if deadlock_timer <= 0.0:
		# La ventana se abre ahora: el primer frame en punto muerto no gasta gracia.
		deadlock_timer = run_time;
		return;
	if run_time - deadlock_timer < DEADLOCK_GRACE:
		return;
	# `active = false` antes de emitir, y por eso run_lost se emite UNA sola vez: update()
	# sale por su guardia de arriba en todas las llamadas siguientes. Es la misma disciplina
	# de _triggerWin(), que la aprendió del run_won que se emitía dos veces.
	active = false;
	run_lost.emit({
		"time": run_time,
		"checkpoints": current_checkpoint_index,
		"factories_placed": 0,
		"final_pollution": int(pollution_manager.total_pollution)
	});

# Lo que hay en la bolsa de TODO lo que el checkpoint en curso cobra: el objetivo Y su
# `maintenance`. Los dos son requisito por igual desde la Tensión del Loop (_checkpoint_cost),
# así que una cortadora que solo talla la madera del peaje está moviendo la run exactamente
# igual que la serrería que hace los tablones, y las dos tienen que romper la condición 1.
# Con la producción ya terminada no queda material pendiente y la suma es 0, que nunca sube:
# la condición se cumple sola, y es lo que toca — en la fase de restauración la única salida
# es limpiar, que es justo lo que mira la condición 2.
func _pending_quantity(bag):
	if current_checkpoint_index >= checkpoints.size():
		return 0;
	var total = 0;
	for material in _checkpoint_cost(checkpoints[current_checkpoint_index]):
		total += bag.getQuantity(material);
	return total;

# Cierra la ventana y deja las dos observaciones sin calibrar: el frame siguiente vuelve a
# tomarlas antes de que nada pueda contar. Lo llaman el cierre de un checkpoint y reset().
func _reset_deadlock():
	last_pending_quantity = 0;
	last_seen_pollution = 0.0;
	deadlock_timer = 0.0;

func _triggerWin(pollution_manager):
	active = false;
	run_won.emit({
		"time": run_time,
		"checkpoints": current_checkpoint_index,
		"factories_placed": 0,
		"final_pollution": int(pollution_manager.total_pollution) if pollution_manager else 0
	});

# El GDD pide que «el tiempo desde inicialización hasta cumplimiento determine la calidad de
# la recompensa». Hasta M7 la vara era _reference_time(): lo que tardaría UNA factoría base
# sin sinergias ni mejoras. Medido al cerrar M4, M5 y M6, esa vara **no discrimina**: la
# curva pide 60/75/165/300/510 s de factoría base y cualquier cadena real cierra los tramos
# en 16-29 s, así que los cinco checkpoints salían tier 2 en todas las runs y la recompensa
# potente se regalaba. El motivo número 1 del plan —«las mejoras no premian jugar bien»—
# seguía sin cumplirse.
#
# Desde M7 la vara es **la línea que el jugador tiene puesta**: el techo que su propia
# fábrica podría dar si nada la parase (_installed_rate(), promediado a lo largo del tramo).
# El tier 2 se gana sosteniendo al menos TIER2_EFFICIENCY de ese techo, o sea manteniendo la
# fábrica alimentada y con los workers puestos. Lo que esto premia y castiga:
#
#  - Alimentar la cadena: una serrería sin madera baja el rendimiento sin bajar el techo.
#  - Encadenar sinergias: suben el techo y el ritmo a la vez, así que no penalizan.
#  - Gastar las mejoras con cabeza: «Sierra industrial» triplica el techo de la serrería, y
#    quien la coja sin madera que darle **baja** de tier. Ahí está el dilema que M2 buscaba.
#  - No construir de más: cinco serrerías para dos workers son tres que no producen nada,
#    y cuentan en el techo porque capacidad instalada sin usar es capacidad mal jugada.
#
# `rate` son unidades por segundo del material del checkpoint; 0.0 significa «no se ha
# medido ninguna línea» (montaje sin factorías, o llamada directa desde las pruebas), y
# entonces se juzga con la regla de M2 tal cual: la factoría base. Nunca pasa en una partida
# real, porque sin factorías que produzcan el material el checkpoint no se alcanza.
func _evaluate_performance(checkpoint, segment_time, carryover = 0, rate = 0.0):
	var pending = _pending_units(checkpoint, carryover);
	if pending <= 0.0:
		return 1;   # el objetivo ya venía hecho: no hay ritmo que premiar
	if rate <= 0.0:
		var reference = _reference_time(checkpoint, carryover);
		if reference <= 0.0:
			return 1;   # sin referencia fiable (material que nadie produce), recompensa corriente
		return 2 if segment_time <= reference else 1;
	# Techo: lo que habría tardado la línea medida a pleno rendimiento. El rendimiento real
	# es techo / tramo, y se compara con el listón sin dividir para no tropezar con un tramo
	# de 0 s (el checkpoint que se cierra en el frame en que se abre).
	var ceiling = pending / rate;
	return 2 if ceiling >= TIER2_EFFICIENCY * segment_time else 1;

# Lo que el tramo tuvo que producir de verdad: la cantidad del checkpoint menos lo que ya
# estaba hecho al abrirse. Se descuenta porque con una curva de varios checkpoints el
# material llega acumulado del tramo anterior, y medir contra la cantidad entera diría que
# el jugador ha producido en diez segundos lo que en realidad traía hecho.
func _pending_units(checkpoint, carryover = 0):
	return max(0.0, float(checkpoint.get("quantity", 0)) - float(carryover));

# Segundos que tardaría UNA factoría base del catálogo en cubrir lo que falta del checkpoint.
# 0.0 si ninguna produce ese material. Sigue siendo la vara con la que M4 comprueba que la
# curva es creciente —es la única que no depende de cómo se juegue— y el respaldo de
# _evaluate_performance() cuando no hay línea que medir.
func _reference_time(checkpoint, carryover = 0):
	var material = checkpoint.get("material", "");
	var pending = _pending_units(checkpoint, carryover);
	if pending <= 0.0:
		return 0.0;
	for factory_name in factories_catalog:
		var factory = factories_catalog[factory_name];
		if factory.get("material", null) == material:
			return pending * float(factory.get("tick", 0));
	return 0.0;

# Unidades por segundo de `material` que la línea instalada podría dar si nada la parase:
# la suma de `output efectivo / tick efectivo` de cada factoría viva que lo fabrica. Efectivo
# quiere decir con las sinergias y las mejoras ya dentro, que es lo que convierte una carta
# potente en un compromiso: sube el techo el mismo día que se coge.
# Cuentan también las factorías sin workers. No es un olvido: una factoría parada por no
# tener a quien ponerle es capacidad instalada que no se usa, y este hito mide exactamente
# eso —cómo de bien se juega con lo que se tiene—.
func _installed_rate(material):
	if material == "" or material == null:
		return 0.0;
	var rate = 0.0;
	for factory in factory_nodes:
		if factory == null or not is_instance_valid(factory):
			continue;
		if factory.production != material:
			continue;
		var tick = float(factory.getEffectiveTick());
		if tick <= 0.0:
			continue;
		rate += float(factory.getEffectiveOutput()) / tick;
	return rate;

# El techo se muestrea a lo largo del tramo y no se mira al cerrarlo, porque el jugador
# construye DURANTE el tramo: medir contra la línea final diría que quien la ha doblado a
# mitad de camino iba lento, y castigaría crecer, que es el juego entero. La media es
# ponderada por tiempo, así que la línea que estuvo puesta más rato pesa más.
func _sample_capacity(checkpoint):
	var dt = run_time - last_capacity_sample;
	last_capacity_sample = run_time;
	if dt <= 0.0:
		return;
	segment_capacity_area += _installed_rate(checkpoint.get("material", "")) * dt;
	segment_capacity_time += dt;

func _segment_rate():
	if segment_capacity_time <= 0.0:
		return 0.0;
	return segment_capacity_area / segment_capacity_time;

func _reset_capacity():
	segment_capacity_area = 0.0;
	segment_capacity_time = 0.0;
	last_capacity_sample = run_time;

# Las mejoras que la partida recibe sí o sí al cerrar un checkpoint, sin gastar la elección
# y sin poder rechazarlas. Son las cartas de rescate de M5: el `unlock_factory` de la única
# factoría capaz de fabricar un material que los checkpoints pendientes exigen.
#
# Ofrecerlas entre las tres no bastaba. El jugador podía coger otra —una mejora de velocidad
# se lee siempre como más apetecible que un desbloqueo— y quedarse sin salida: el checkpoint
# siguiente pide un material que su partida no sabe fabricar y, sin condición de derrota, eso
# no es perder sino una run infinita. Que la salida exista no sirve si se puede tirar a la
# basura sin saberlo.
#
# Se conceden en vez de ofrecerse sola, que era la otra salida, porque ofrecerla sola
# convierte la pantalla de recompensa en un botón: el jugador pierde la elección entera por
# un problema que no ha causado. Concediéndola, la elección de tres cartas sigue intacta y lo
# único que desaparece es la posibilidad de tirar la salida. Y la pantalla lo dice con su
# nombre y su motivo (`ui/upgradeScreen.gd`), porque una mejora que aparece sin haberla
# elegido y sin explicación se lee como un bug.
func _granted_upgrades():
	return _rescue_upgrades(_usable_upgrades());

# `tier` tiene valor por defecto para que las llamadas que no saben de tiers —la mejora
# gratis de las ruinas en Main.gd— sigan funcionando y reciban una mejora corriente.
# `granted` son las que ya se han concedido en esta misma pantalla: salen de la baraja porque
# ofrecer algo que el jugador ya tiene es la carta muerta que M2 vino a quitar.
func _pick_upgrades(count, tier = 1, granted = []):
	var picked = [];
	# La baraja se depura ANTES de repartir por tier. Si el filtro fuera después, el relleno
	# de un tier escaso volvería a colar por la puerta de atrás la carta que no hace nada.
	var pool = _usable_upgrades();
	for id in granted:
		pool.erase(id);
	# La carta que desatasca la partida va la primera y FUERA del barajado. Si saliera a
	# suerte, un jugador de `lumberjack` podría no verla nunca y quedarse clavado ante un
	# checkpoint que pide un material que su partida no sabe fabricar — y sin condición de
	# derrota eso no es perder, es una run infinita, que es peor. En la pantalla de checkpoint
	# esto ya no llega a ocurrir —la carta se concede antes y se resta de `pool`—, pero sí en
	# la llamada de una sola carta de las ruinas (Main.gd), que sigue siendo la segunda
	# oportunidad de quien se atasca sin haber cerrado todavía un checkpoint.
	for id in _rescue_upgrades(pool):
		if not picked.has(id):
			picked.append(id);
	# Del tier pedido hacia abajo: si el tier pedido no da para `count` cartas se completa
	# con los de abajo, porque una pantalla con una sola opción no es un dilema, es un botón.
	# Se comprueba id a id porque la carta fijada arriba ya puede estar dentro y una pantalla
	# con la misma mejora dos veces ofrece menos de lo que enseña.
	var current_tier = tier;
	while current_tier >= 1 and picked.size() < count:
		for id in _shuffled_tier(current_tier, pool):
			if not picked.has(id):
				picked.append(id);
		current_tier -= 1;
	# Último recurso: lo que quede de la baraja, sea del tier que sea. Cubre el caso de pedir
	# tier 1 con un tier 1 escaso, donde ya no hay nada «inferior» con lo que rellenar.
	if picked.size() < count:
		var rest = [];
		for id in pool:
			if not picked.has(id):
				rest.append(id);
		rest.shuffle();
		picked.append_array(rest);
	return picked.slice(0, min(count, picked.size()));

# La baraja de esta partida: el catálogo menos las mejoras que aquí no harían nada. Hoy el
# único caso es un `unlock_factory` de una factoría que el paquete de inicio ya trae —los
# tres traen MetaFactory, WorkerCamp y Reforester—. No se puede resolver etiquetando el
# JSON porque el mismo id es útil o humo según el paquete: WoodProcessing falta en
# `lumberjack` y `ecologist` pero está en `standard`.
func _usable_upgrades():
	var available = _available_factories();
	var pool = [];
	for id in upgrades_catalog:
		var upgrade = upgrades_catalog[id];
		if upgrade.get("type", "") == "unlock_factory" and available.has(upgrade.get("factory", "")):
			continue;
		pool.append(id);
	return pool;

# Sin Player no hay nada que descartar y se ofrece el catálogo entero, que es lo que se hacía
# antes de este filtro: un montaje a medias no debe quedarse sin cartas.
func _available_factories():
	if player_node == null or not is_instance_valid(player_node):
		return [];
	return player_node.availableFactories;

# Las cartas que desatascan la partida, y que por eso no pueden depender de una tirada: un
# `unlock_factory` de una factoría que fabrica un material que los checkpoints pendientes van
# a pedir y que ninguna de las disponibles sabe fabricar. Hoy eso es WoodProcessing en
# `lumberjack` y `ecologist` —única fuente de `plank`, que piden los checkpoints 2 a 5, y sin
# tablones tampoco hay `factory_token` con el que desbloquearla—, pero aquí no se nombra a
# nadie: sale de cruzar la curva con el catálogo, así que si mañana cambia el material de un
# checkpoint o el paquete que trae la factoría, la garantía se mueve sola.
func _rescue_upgrades(pool):
	# Sin Player no hay partida que desatascar y `_available_factories()` devuelve vacío: se
	# daría por imposible todo material y se fijarían cartas que aquí no rescatan de nada.
	if player_node == null or not is_instance_valid(player_node):
		return [];
	var missing = _unproducible_materials();
	if missing.is_empty():
		return [];
	var rescue = [];
	for id in pool:
		var upgrade = upgrades_catalog[id];
		if upgrade.get("type", "") != "unlock_factory":
			continue;
		var factory = factories_catalog.get(upgrade.get("factory", ""), {});
		if missing.has(factory.get("material", null)):
			rescue.append(id);
	return rescue;

# Materiales que los checkpoints que quedan van a pedir —objetivo y mantenimiento, que desde
# M4 son requisito por igual— y que ninguna factoría disponible produce. Se miran todos los
# pendientes y no solo el siguiente: la carta tiene que ofrecerse en el checkpoint ANTERIOR
# al que bloquea, que es el único momento en que todavía sirve de algo.
func _unproducible_materials():
	var producible = {};
	for factory_name in _available_factories():
		var material = factories_catalog.get(factory_name, {}).get("material", null);
		if material != null:
			producible[material] = true;
	var missing = {};
	for i in range(current_checkpoint_index, checkpoints.size()):
		for material in _checkpoint_cost(checkpoints[i]):
			if material != "" and not producible.has(material):
				missing[material] = true;
	return missing;

# Una mejora sin `tier` en el JSON cuenta como corriente: así un catálogo a medio etiquetar
# sigue saliendo por pantalla en vez de caerse de todos los filtros.
func _shuffled_tier(tier, pool):
	var keys = [];
	for id in pool:
		if int(upgrades_catalog[id].get("tier", 1)) == tier:
			keys.append(id);
	keys.shuffle();
	return keys;

func resume_after_upgrade():
	active = true;

# El texto del HUD, con el aviso de colapso DELANTE de todo lo demás cuando la ventana del
# punto muerto está abierta. Se antepone en la misma línea, que es lo que el plan pide por
# defecto, y no se parte en dos con `\n`: el Label `Objective` de Main.tscn empieza en y=44 y
# el de los recursos en y=73, así que una segunda línea se le montaría encima.
# M5 aceptó a cambio una línea muy larga; mirar el juego en pantalla demostró que no cabía y
# que lo que se caía por la derecha se cortaba a media palabra. Por eso desde M7 el aviso
# SUSTITUYE a la cola de contaminación en vez de sumarse a ella (ver _progressText): el
# `⚠ COLAPSO … nadie limpia …` ya dice lo que esa cola diría. Es solo lectura, así que el
# estado de la ventana se le pasa a _progressText() en vez de consultarlo allí.
# Envuelve a _progressText() en vez de repetirse en cada `return` porque esa función tiene
# tres caminos de salida y el punto muerto puede darse en todos: en la fase de restauración
# la condición 1 se cumple sola (ver _pending_quantity()), así que ahí es MÁS probable, no
# menos.
func getObjectiveText(bag, pollution_manager = null):
	var warning = _deadlockText();
	return warning + _progressText(bag, pollution_manager, warning != "");

# Cuenta atrás y motivo, o cadena vacía si no hay ventana abierta. Es SOLO lectura: el HUD
# la llama cada frame desde Main._process() y quien mueve `deadlock_timer` es
# _evaluate_deadlock(); tocar estado aquí haría que mirar el HUD cambiara la partida.
# `deadlock_timer` guarda el instante de `run_time` en que se abrió la ventana —0.0 es
# «cerrada», no «quedan cero segundos»—, así que lo que queda se calcula, no se lee.
# Los tres motivos se nombran siempre juntos porque las tres condiciones se cumplen a la vez
# por construcción: no hay ventana abierta con una sola rota, y el jugador necesita ver las
# tres para saber que romper cualquiera de ellas le devuelve la run.
func _deadlockText():
	if deadlock_timer <= 0.0:
		return "";
	var left = DEADLOCK_GRACE - (run_time - deadlock_timer);
	# Se redondea hacia arriba y se corta en 0: el frame en que se abre la ventana anuncia la
	# gracia entera y el último segundo se lee «1 s» en vez de «0 s», que se leería como que
	# el aviso se ha quedado colgado.
	var seconds = max(0, int(ceil(left)));
	return "⚠ COLAPSO EN %d s — no se produce, nadie limpia y no queda dónde construir  |  " % seconds;

# `deadlock_open` lo pone getObjectiveText(): con la ventana del punto muerto abierta, la cola
# de contaminación se va y deja sitio al aviso, que dice lo mismo y con más urgencia («nadie
# limpia»). Lo que se queda son el objetivo y el mantenimiento reservado: son exactamente lo
# que el jugador tiene que mirar para romper la condición 1 y cancelar la cuenta atrás.
# EXCEPCIÓN, la fase de restauración: ahí la cola es lo ÚNICO que dice el texto —cuánto queda
# para cerrar la run— y además la línea es corta (~133 caracteres con el aviso delante, que
# caben de sobra), así que ahí el aviso se antepone como en M5. Quitarla dejaría al jugador
# sin saber cuánto le falta justo cuando más lo necesita.
func _progressText(bag, pollution_manager = null, deadlock_open = false):
	if production_done:
		if pollution_manager:
			return "Restaurando: %s" % pollution_manager.getStatusText();
		return "¡Producción completada!";
	if current_checkpoint_index >= checkpoints.size():
		return "¡Producción completada!";
	var cp = checkpoints[current_checkpoint_index];
	var current = bag.getQuantity(cp["material"]);
	var label = cp.get("label", "Objetivo");
	var pollution_text = "";
	if pollution_manager and not deadlock_open:
		pollution_text = "  |  " + pollution_manager.getStatusText();
	return "%s: %d / %d %s%s%s" % [label, current, cp["quantity"], cp["material"],
		_maintenanceText(bag, cp), pollution_text];

# El mantenimiento se anuncia ANTES de cobrarse, y con su progreso, no solo con su importe.
# Es la mitad del requisito del checkpoint: sin verlo, el jugador con los tablones hechos no
# entendería por qué el objetivo no se cierra, y el material desaparecería de la bolsa sin
# motivo visible. Cadena vacía cuando el checkpoint no cobra nada, para no ensuciar el HUD
# con un paréntesis hueco.
func _maintenanceText(bag, checkpoint):
	var parts = [];
	var maintenance = checkpoint.get("maintenance", {});
	for material in maintenance:
		var quantity = int(maintenance[material]);
		if quantity > 0:
			parts.append("%d / %d %s" % [min(bag.getQuantity(material), quantity), quantity, material]);
	if parts.is_empty():
		return "";
	# «reservado» no es adorno: desde M6 esa cantidad está apartada de verdad y las factorías
	# no la consumen, así que el jugador ve madera en el almacén y serrerías paradas. Sin la
	# palabra, eso se lee como un bug; con ella, el número que el HUD anuncia, el que la
	# bolsa protege y el que el checkpoint cobra son el mismo.
	return "  (mantenimiento reservado: %s)" % ", ".join(parts);

func reset():
	current_checkpoint_index = 0;
	run_time = 0.0;
	last_checkpoint_time = 0.0;
	segment_start_stock = 0;
	active = true;
	production_done = false;
	_reset_capacity();
	_reset_deadlock();
