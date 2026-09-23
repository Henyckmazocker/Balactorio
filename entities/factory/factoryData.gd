extends Area2D

signal resource_produced(material, amount, world_pos);

var type;
var production;
var tickTimer;
var itemNeeded = [];
var timer = 0;
var outputAmount = 1;
var pollutionAmount = 0.0;   # >0 contamina, <0 restaura
var factory_type = "production";  # "production" | "restoration" | "storage"
var cell_position = Vector2i(0, 0);
# Producción fraccionaria arrastrada entre ticks por el ahogo (ver getPollutionChoke).
var production_debt = 0.0;

# Lo que ESTA factoría pagó de verdad al colocarse, `material -> cantidad`, y de donde sale la
# devolución al demolerla (Costes M4). Es el recibo del pago y NO una copia del precio del
# JSON: `factoryPlacer.build()` solo lo rellena cuando ha cobrado de verdad (`charge_cost`),
# así que lo colocado sin pagar —el almacén con el que arranca el mapa, la suite—
# lo deja vacío y al demolerse no devuelve nada. Si la devolución mirase el `cost` del JSON,
# demoler ese almacén regalado daría 5 de madera de la nada: demoler dejaría de costar dinero
# para pasar a imprimirlo.
var cost_paid = {};

# Lo que las cintas le han ENTREGADO a esta factoría: `material -> int`. Desde M2 es la única
# despensa de la que come: checkNeeds() lo consulta y consumeNeeds() lo vacía, en vez de la
# bolsa global. El búfer es SUYO y no compartido, así que la reserva del peaje del checkpoint
# (Bag.getAvailable()) ya no protege su input — no hace falta: lo que entra aquí lo ha traído
# una cinta y no está en la bolsa de nadie.
var input_buffer = {};

# El búfer de SALIDA (M4): lo que esta factoría ha producido y la red NO ha sabido llevarse a
# ninguna parte. Lo llena Main._on_resource_produced() cuando beltNetwork.deliver() devuelve 0
# —hasta M4 ese material se perdía en silencio— y lo vacía la red en cuanto aparece un camino
# (beltNetwork.flush_output()). Sin salida el material ya no desaparece: se acumula y frena.
var output_buffer: int = 0;
# 🔴 POR QUÉ CINTA SALE LA EMISIÓN EN CURSO, para el encaminador (2026-09-23, el almacén
# emisor). La señal `resource_produced` lleva tres argumentos y Main le ata el nodo de origen,
# pero no la CINTA: con una sola salida por factoría nunca hizo falta —`deliver()` tomaba la
# primera y era la única—. Desde que el almacén emite una cosa distinta por cada una de sus
# cintas, la primera ya no vale: sin este dato las dos emisiones de un almacén con dos líneas
# se irían por la misma y la segunda línea no recibiría nunca nada.
#
# Es un dato de UN emit y no un estado: `_tick_storage_emit()` lo escribe justo antes de emitir
# y lo borra justo después, y como las señales de Godot son SÍNCRONAS, Main lo lee dentro de
# ese mismo emit(). `null` significa «por donde sea», que es lo que hacen —y seguirán
# haciendo— todas las factorías de producción.
var emit_route_cell = null;

# Búfer lleno -> la factoría deja de producir Y DE CONTAMINAR. Que deje de ensuciar es la
# mitad cara del hito: mueve el balance de la derrota y por eso M4 va antes de la re-medición
# de las constantes (M6). Lo que rebose se pierde: el búfer es el freno, no un almacén.
const OUTPUT_BUFFER_MAX: int = 10;
# POR QUÉ no está produciendo, para quien lo quiera pintar — el estado lo creó el M4 del
# Plan - Cintas y Almacén y lo completa y dibuja el Plan - Feedback de Cuellos de Botella.
# CINCO valores y en este orden de prioridad, que es el que fija ese plan: "" (produce),
# "workers", "input", "output", "choke".
# El quinto, el ahogo, lo añadió el M1 de ese plan. M4 lo dejó a propósito sin escribir
# —declarar un valor que diseñaba otro plan era decidir por él— y hasta entonces un tick
# ahogado dejaba `blocked_reason` en "": no había forma de distinguir «va lenta porque el
# suelo la está matando» de «va bien». Va el ÚLTIMO porque las otras tres lo enmascaran: una
# factoría sin insumo tampoco produciría con el suelo limpio, así que decirle «limpia» en vez
# de «tiéndele cinta» la mandaría al arreglo equivocado.
#
# Lo escribe update() y solo update(), que es donde vive la prioridad; clearOutputBuffer() se
# limita a borrar el "output" al desatascar, para que el estado no mienta durante un tick
# entero después de que el jugador haya tendido la cinta.
var blocked_reason: String = "";

# Modificadores aplicados por sinergias de adyacencia
var synergy_tick_bonus = 0;      # reduce tickTimer efectivo
var synergy_output_bonus = 0;    # suma a outputAmount efectivo
var synergy_pollution_mult = 1.0; # multiplica pollutionAmount

# Workers
var workers_needed = 0;
var workers_assigned = 0;        # 0 = inactiva si workers_needed > 0

# Materiales entre los que esta factoría puede elegir qué fabricar. Es SIEMPRE una lista con al
# menos un elemento en cuanto se llama a initialize(): el JSON declara `materials: [...]` solo
# cuando hay algo que elegir, y su ausencia significa `[material]` —el caso de OCHO de las nueve
# entradas de hoy; la novena es la `Foundry`, que desde Variedad M3 (2026-09-22) declara
# `["brick", "glass"]`—. El fallback vive aquí y no en
# factoryPlacer para que valga para TODOS los llamadores de initialize(), incluidas las pruebas
# de tests/run_tests.gd, que construyen factorías a mano.
var production_candidates = [];

# 🔴 EL PollutionManager, CACHEADO Y CON INVALIDACIÓN (M0b, 2026-09-21).
# `get_tree().get_root().find_child("PollutionManager", true, false)` es una búsqueda
# RECURSIVA POR TODO EL ÁRBOL, y se hacía dos veces por tick —_apply_pollution() y
# getPollutionChoke()— en cada factoría.
#
# La invalidación NO se puede escribir con `!= null`: en GDScript un nodo LIBERADO se compara
# igual que `null` y se cuela por todas las ramas; solo `is_instance_valid()` los distingue
# (CLAUDE.md, donde costó un bug latente en Main._update_hover_tooltip()). Y aquí hace falta de
# verdad, no por higiene: la suite monta y suelta escenarios EN SERIE y find_child()
# devuelve el PRIMERO del árbol, así que una referencia cacheada a un manager liberado dejaría
# a la prueba midiendo contra la contaminación del escenario anterior.
# Tampoco se cachea el «no lo hay»: se guarda el resultado y un `null` vuelve a buscar al tick
# siguiente, que es lo que deja funcionar a las pruebas que montan el manager DESPUÉS de la
# factoría.
var _pollution_manager = null;

# 🔴 SIN VENTANA NO HAY SPRITE QUE ANIMAR (M0b, 2026-09-21). `get_node("AnimatedSprite2D")` +
# `play()` en cada tick de producción, de restauración y de almacén, por factoría. Sin
# `DisplayServer` con ventana no hay nada que dibujar y nadie que lo mire.
# Es `static` y no una propiedad por nodo porque la respuesta es la MISMA para las ~60
# factorías de la suite y para todas las de una run: preguntarla una vez por clase es lo que
# la hace gratis. Y es `var` para que la suite pueda fijar el contrato en los dos sentidos.
static var animations_enabled: bool = DisplayServer.get_name() != "headless";

# `materials` va al final y con default a propósito: factoryPlacer.build() pasa los parámetros
# POSICIONALMENTE y hay llamadores fuera del juego (tests/run_tests.gd, que monta
# factorías a mano).
func initialize(name, tick, needs, material, output = 1, pollution = 0.0, ftype = "production", w_needed = 0, materials = null):
	type = name;
	tickTimer = tick;
	production = material;
	outputAmount = output;
	pollutionAmount = pollution;
	factory_type = ftype;
	workers_needed = w_needed;
	if needs != null:
		itemNeeded = needs.duplicate();
	# `production` arranca en el `material` de siempre: `materials` no dice con qué se coloca la
	# factoría, solo entre qué puede cambiar después. El guardia del `has()` cubre una entrada mal
	# escrita —una lista que no incluya su propio `material`—: sin él la factoría produciría algo
	# que el desplegable no ofrece y el panel no tendría qué marcar.
	if materials != null and not materials.is_empty():
		production_candidates = materials.duplicate();
		if not production_candidates.has(production):
			production = production_candidates[0];
	else:
		production_candidates = [material];

# ¿Hay de verdad algo que elegir? Con un solo candidato —ocho de las nueve entradas del JSON de
# hoy, el almacén incluido desde que emite solo— el desplegable del panel sería de un elemento,
# así que ui/factoryPanel.gd lo esconde.
func hasMaterialChoice():
	return production_candidates.size() > 1;

# Las dos excepciones de siempre: `worker` y `factory_token` NO viajan por cinta
# (Main._on_resource_produced() las intercepta antes de la red), así que un almacén tampoco los
# emite —aunque estén contados en la bolsa y aunque un destino los declare en su `recieve`—:
# sacarlos por una cinta sería sacarlos de la bolsa para que la excepción te los devolviera.
const BELT_EXCLUDED_MATERIALS = ["worker", "factory_token"];

# Cambia QUÉ fabrica la factoría. Es un cambio de destino, no una factoría nueva: NO se reinicia
# el `Timer` (ni el contador `timer` que cuenta sus timeouts) y NO se toca `production_debt`. Si
# se reiniciaran, cambiar de material sería un exploit —saltarse el tick a medio cumplir— o un
# castigo —perder la producción fraccionaria que el ahogo venía arrastrando—, y el desajuste no
# se vería hasta que alguien midiera el balance. Devuelve false si el material no es candidato.
func setProduction(material):
	if not production_candidates.has(material):
		return false;
	production = material;
	return true;

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
	var pm = _pollutionManager();
	if pm == null:
		return 1.0;
	return 1.0 - pm.getCellPollution(cell_position);

# El PollutionManager de ESTE árbol, cacheado (M0b). Ver el comentario de `_pollution_manager`:
# la guarda es is_instance_valid() y no `!= null` porque un nodo liberado se compara como nulo,
# y sin ella una prueba que suelta un escenario y monta el siguiente seguiría ensuciando el
# manager del anterior — que es la trampa que el CLAUDE.md ya documenta sobre find_child().
func _pollutionManager():
	if is_instance_valid(_pollution_manager):
		return _pollution_manager;
	if not is_inside_tree():
		return null;
	_pollution_manager = get_tree().get_root().find_child("PollutionManager", true, false);
	return _pollution_manager;

# La red de cintas, que es de donde el almacén saca A QUIÉN alimenta cada una de sus cintas
# (_tick_storage_emit()). Es un HERMANO directo —Main mete el manager con `add_child()` y le
# pone el nombre "BeltNetwork", y las factorías cuelgan del mismo Main—, así que se pregunta por
# el nombre y NO con `find_child()` recursivo: la trampa del `CLAUDE.md` —devuelve el PRIMERO
# del árbol— es justo lo que rompería a las pruebas, que montan y sueltan
# escenarios EN SERIE. Por lo mismo no se cachea: un `get_node_or_null()` sobre un hijo directo
# es un acceso a diccionario, solo lo pregunta el tick de los almacenes (uno o dos por mapa) y
# una referencia guardada sobreviviría a `Main.reset()`, que suelta la red entera.
func _beltNetwork():
	var padre = get_parent();
	if padre == null:
		return null;
	return padre.get_node_or_null("BeltNetwork");

# Factor por el que escala la restauración. `max(1, ...)` evita que un output_bonus
# negativo futuro anule la limpieza en silencio, igual que el guardia de getEffectiveTick().
func getRestorationScale():
	return max(1, getEffectiveOutput());

# `_bag` no lo usa ya ninguna productora —desde M2 lo producido no entra en la bolsa, sale por
# `resource_produced` y lo encamina Main a beltNetwork.deliver()—, pero sí el almacén de M3:
# _tick_storage() vuelca en ella lo que las cintas le han traído. Lo pasan _on_timer_timeout()
# y todos los llamadores de fuera del juego.
func update(_bag = null):
	# La prioridad de las cinco razones, en este orden: workers -> input -> output -> choke. La
	# fija el Plan - Feedback de Cuellos de Botella, que es quien las pinta; aquí solo se
	# respeta. Los CINCO puntos de salida temprana escriben la suya y el camino de éxito la
	# limpia: si uno se dejara sin escribir, el estado se quedaría congelado en el del tick
	# anterior y el indicador del mapa mentiría hasta que la factoría cambiase de humor.
	# (El quinto es el "input" de la restauradora con insumos, Variedad M4: usa la razón que ya
	# existía y NO cambia la prioridad — una depuradora sin workers sigue diciendo "workers".)
	if not isActive():
		blocked_reason = "workers";
		return;
	if factory_type == "restoration":
		# Limpiar tiene que funcionar SIEMPRE. La restauración no produce material, así que no
		# tiene salida que atascar y NUNCA se bloquea por "output": que se ahogase la limpieza
		# es justo lo que el diseño evita —es la salida que convierte la espiral en castigo y
		# no en sentencia—. Y tampoco pasa por el ahogo: getPollutionChoke() la exime, y aquí
		# ni se consulta.
		#
		# 🔴 Lo ÚNICO que una restauradora sí puede es quedarse SIN INSUMO (Variedad M4). Hasta
		# hoy este camino se saltaba checkNeeds() y consumeNeeds() enteros, así que la
		# WaterTreatment —la primera restauradora con `recieve`— habría limpiado gratis y su
		# cinta de `stone` habría sido decorado. La fragilidad es deliberada y es su contrapeso:
		# limpia casi el doble que el Reforester, pero hay que alimentarla.
		#
		# Para el Reforester —y para cualquier entrada con `recieve: null`— esto NO cambia nada:
		# `itemNeeded` está vacío, así que checkNeeds() contesta true sin mirar nada y
		# consumeNeeds() no recorre ni un material. Sigue siendo restauración pasiva.
		if not checkNeeds():
			blocked_reason = "input";
			return;
		blocked_reason = "";
		consumeNeeds();
		_tick_restoration();
	elif factory_type == "storage":
		# El almacén tampoco produce: vuelca en la bolsa lo que le traen las cintas y no emite
		# nada, así que tampoco tiene búfer de salida que se le llene.
		blocked_reason = "";
		_tick_storage(_bag);
	elif not checkNeeds():
		blocked_reason = "input";
	elif output_buffer >= OUTPUT_BUFFER_MAX:
		# El corte va AQUÍ, ANTES de tocar `production_debt`, y no donde corta el ahogo. Son
		# dos cosas distintas y conviven sin pisarse: el ahogo es una RAMPA —el tick no entrega
		# pero la deuda sigue acumulando, así que al 50 % se entrega 1 de cada 2 ticks— y el
		# búfer lleno es una PARADA. Si la deuda acumulara mientras está parada, desatascarla
		# soltaría de golpe todo lo que "debió" producir sin salida, que es justo lo contrario
		# de pararse. Y como se sale antes, no consume insumos (consumeNeeds() vaciaría el
		# input_buffer: sería un sumidero de material), no anima y —lo que importa para el
		# balance— NO llama a _apply_pollution(): una factoría parada no ensucia.
		blocked_reason = "output";
	else:
		blocked_reason = "";
		# El ahogo se aplica AQUÍ, donde se produce, y NO en getEffectiveOutput(): esa función
		# es el techo con el que gameManager._installed_rate() juzga el tier de la recompensa, y
		# si el ahogo lo bajara, ahogar tu propia línea te haría cobrar cartas potentes por
		# jugar mal. Baja el ritmo sin bajar el techo, igual que una serrería sin madera. Por lo
		# mismo, la parada por búfer lleno tampoco toca getEffectiveOutput().
		# Se acumula en un float en vez de redondear porque casi todas las factorías tienen
		# output 1: int(1 * 0.6) daría 0 y el ahogo sería un interruptor en vez de una rampa.
		# Con el acumulador, al 50 % de ahogo se entrega 1 cada 2 ticks. Determinista, así que
		# se puede probar.
		production_debt += getEffectiveOutput() * getPollutionChoke();
		var eff_out = int(production_debt);
		# Un tick que no entrega nada NO consume insumos, no ensucia y no anima: si consumiera,
		# el ahogo sería además un sumidero de recursos y aceleraría la espiral por un camino
		# que el plan no ha diseñado. La deuda sí sigue acumulando — es lo que hace la rampa.
		#
		# Y es el CUARTO punto de salida temprana, así que escribe su razón (M1 del Plan -
		# Feedback de Cuellos de Botella). Va DESPUÉS del `""` de arriba y no en su lugar,
		# porque la razón la decide el resultado del tick y no su intención: mientras la rampa
		# entregue —1 de cada 2 ticks al 50 % de ahogo— el estado parpadea entre "choke" y "",
		# que es justo lo que el jugador tiene que ver, que la casilla le está costando la
		# mitad de la producción. Con el suelo limpio no se llega aquí jamás: choke 1.0 sobre
		# un output efectivo >= 1 da eff_out >= 1, así que la única causa real de este cero es
		# la contaminación local — que es lo que "choke" dice.
		if eff_out <= 0:
			blocked_reason = "choke";
			return;
		production_debt -= eff_out;
		consumeNeeds();
		# Desde M2 NADA entra en la bolsa desde aquí: lo producido sale por la señal y es Main
		# quien lo encamina por la red de cintas (beltNetwork.deliver()), con sus dos
		# excepciones de siempre —"worker" y "factory_token"—. Desde M4 lo que la red no sabe
		# entregar tampoco se pierde: Main lo guarda en el búfer de salida (storeOutput()).
		resource_produced.emit(production, eff_out, global_position);
		# Sin ventana no se anima (M0b): ver `animations_enabled`.
		if animations_enabled:
			get_node("AnimatedSprite2D").play();
		_apply_pollution();

# Lo producido que no ha encontrado salida. Lo llama Main._on_resource_produced() cuando
# beltNetwork.deliver() devuelve 0. Devuelve cuánto ha cabido: se recorta en OUTPUT_BUFFER_MAX
# y lo que rebosa SE PIERDE, porque el búfer es el freno de la factoría y no un almacén
# paralelo que le permitiera seguir produciendo sin cinta.
#
# NO escribe `blocked_reason`: la prioridad de las cuatro razones vive en update() y tener dos
# escritores la rompería (una factoría sin workers y con el búfer lleno diría "output"). El
# estado se pone al día en el tick siguiente, que es cuando de verdad deja de producir.
func storeOutput(amount):
	if amount == null or int(amount) <= 0:
		return 0;
	# El almacén NO se atasca, ni siquiera desde que emite (M5): M4 lo dejó sin búfer de
	# salida a propósito y emitir no cambia ese contrato. Lo que la red no sabe llevarse
	# vuelve a la bolsa (Main._on_resource_produced()), que es de donde salió.
	if factory_type == "storage":
		return 0;
	var libre = OUTPUT_BUFFER_MAX - output_buffer;
	if libre <= 0:
		return 0;
	var guardado = min(libre, int(amount));
	output_buffer += guardado;
	return guardado;

# El atasco se ha ido por una cinta. Lo llama beltNetwork.flush_output() tras una entrega que
# sí ha colado. Borra además el "output" para que el estado no mienta durante un tick entero
# después de que el jugador haya tendido la cinta; cualquier otra razón la sigue decidiendo
# update().
func clearOutputBuffer():
	output_buffer = 0;
	if blocked_reason == "output":
		blocked_reason = "";

# El almacén. No FABRICA nada —`material: null`, como el Reforester—, y su tick hace dos cosas
# en este orden: VACÍA en la bolsa global lo que las cintas le han dejado en el búfer de entrada
# —por eso acepta cualquier material: el filtrado, si lo hay, es de la cinta— y EMITE por sus
# cintas de salida lo que pidan los consumidores que hay al final de cada una.
#
# Es el único sitio del juego donde algo entra hoy en la `Bag` (desde M2 producir ya no la
# llena), y de ahí sale gratis la regla del plan: solo cuenta para los checkpoints lo que ha
# pasado por un almacén. El evaluador de gameManager no se toca — sigue leyendo y reservando
# contra la bolsa, lo que cambia es quién la llena.
#
# El volcado vive aquí y no en beltNetwork.deliver() porque la bolsa la tiene el tick
# (_on_timer_timeout() se la pasa) y la red no: la cinta deja el material en el búfer, como
# con cualquier otra factoría, y el almacén lo vacía al tick siguiente.
func _tick_storage(bag):
	if bag == null:
		return;
	var ha_movido = false;
	# --- 1) ACEPTA: lo que las cintas han dejado en el búfer se vuelca en la bolsa.
	if not input_buffer.is_empty():
		for material in input_buffer:
			var amount = int(input_buffer[material]);
			if amount > 0:
				bag.addToBag(material, amount);
		input_buffer.clear();
		ha_movido = true;
	# --- 2) EMITE: lo que PIDAN los consumidores que cuelgan de sus cintas de salida.
	#
	# 🔴 QUÉ CAMBIÓ Y QUÉ SE ROMPÍA ANTES (2026-09-23). Hasta hoy el almacén emitía UN material,
	# el que el jugador le eligiera a mano en el desplegable del panel (`production`), y por UNA
	# cinta, la primera que `beltNetwork._entry_segment()` encontrara. Las dos mitades estaban
	# mal: un almacén con dos líneas alimentaba solo a una —la otra era decorado, y el jugador
	# no tenía forma de verlo—, y alimentar a dos consumidores distintos obligaba a volver al
	# panel a cambiar el desplegable cada pocos segundos, que no es una decisión sino una
	# tarea. Ahora no hay nada que elegir: el almacén mira A QUIÉN lleva cada una de sus cintas
	# y le manda lo que ese destino declara en su `recieve`. `production` ya NO decide nada aquí
	# y se queda en el `material: null` del JSON.
	if _tick_storage_emit(bag):
		ha_movido = true;
	if not ha_movido:
		return;
	# El almacén no contamina (`pollution: 0.0`), así que aquí no se llama a _apply_pollution():
	# sería buscar el PollutionManager por el árbol cada segundo para sumarle un cero.
	# Sin ventana no se anima (M0b): ver `animations_enabled`.
	if not animations_enabled:
		return;
	var sprite = get_node_or_null("AnimatedSprite2D");
	if sprite != null:
		sprite.play();

# El reparto de la emisión, una cinta cada vez. Devuelve si ha salido algo.
#
# 🔴 ORDEN FIJO Y ESCRITO: el de `beltNetwork.output_segments()`, que es el de
# `ORTHOGONAL_DIRS` —derecha, izquierda, abajo, arriba—. No es cosmética: este proyecto mide
# con IGUALDAD EXACTA (los cuatro golden de tests/run_tests.gd), y con existencias justas para
# un solo destino, quién se las lleva mueve la curva entera. Si el reparto dependiera del orden
# de iteración de un diccionario, dos runs idénticas dejarían de medir lo mismo.
#
# Las reglas, y por qué:
#   · UNA emisión por destino y por tick, y por tanto UN material. Si el destino declara dos
#     (`recieve: ["a", "b"]`) se le manda el primero que tenga existencias y se pasa a la cinta
#     siguiente; y si dos cintas distintas acaban en el MISMO consumidor, cobra una vez y no
#     dos (`servidos`). Acumular varias emisiones sobre un destino en el mismo tick sería darle
#     al almacén un ritmo que ninguna factoría del juego tiene, y encima se compraría duplicando
#     cintas en vez de produciendo.
#   · UN almacén NO alimenta a otro almacén. Es un bucle de trasiego sin sentido —sale de la
#     bolsa por una cinta y vuelve a la misma bolsa por el tick del otro— y encima parecería
#     producción en las medidas.
#   · `worker` y `factory_token` NUNCA salen por cinta (BELT_EXCLUDED_MATERIALS): los
#     intercepta Main._on_resource_produced() antes de la red, así que emitirlos sería sacarlos
#     de la bolsa para volver a metértelos por el camino de la excepción.
#   · El FILTRO de la cinta (M5) se consulta ANTES de elegir material, no después: una cinta
#     filtrada a `wood` hacia un destino que pide `stone` y `wood` tiene que llevar `wood`, y
#     preguntarlo después sería emitir `stone`, que la red rechace y que la bolsa se lo coma y
#     lo devuelva sin que nada se mueva nunca.
#
# 🔴 Sale de getAvailable() y NO de getQuantity(): la bolsa APARTA lo que el mantenimiento del
# checkpoint en curso exige (`Bag.reserved`) y un almacén que emitiera el peaje por una cinta
# se lo comería igual que se lo comía una serrería rápida antes de que existiera la reserva —
# la run se colgaría para siempre y el bug ya se sufrió una vez en este proyecto. Y con varios
# destinos hay que DESCONTAR SOBRE LA MARCHA (`comprometido`): `getAvailable()` no se entera de
# lo que ya se ha sacado en este mismo tick hasta que se llama a `removeFromBag()`, así que sin
# ese recuento dos cintas se repartirían dos veces la misma madera y la bolsa se quedaría corta.
#
# El almacén NO tiene búfer de salida (contrato de M4: no produce, así que no se atasca). Si la
# red no sabe llevárselo, Main._on_resource_produced() lo DEVUELVE a la bolsa en el acto en vez
# de acumularlo aquí, y el saldo del tick es cero.
func _tick_storage_emit(bag) -> bool:
	var net = _beltNetwork();
	if net == null or bag == null:
		return false;
	var segs = net.output_segments(cell_position);
	if segs.is_empty():
		return false;
	var pedido = max(1, getEffectiveOutput());
	# Lo ya sacado en ESTE tick, material -> cantidad. Ver el 🔴 de arriba.
	#
	# No se descuenta lo que Main devuelva a la bolsa si la entrega falla: el compromiso se
	# mantiene hasta el final del tick y ese material vuelve a estar libre en el siguiente. Es
	# a propósito, y es el lado conservador: reabrirlo a mitad de tick significaría que una
	# entrega fallida le da existencias a la cinta de al lado, que es exactamente la clase de
	# reparto que depende del orden y que este método no quiere tener.
	var comprometido = {};
	# Los destinos ya servidos en ESTE tick, por celda: dos cintas al mismo consumidor le
	# entregan una vez, no dos.
	var servidos = {};
	var ha_emitido = false;
	for seg in segs:
		# Sin material: la pregunta es «¿a quién lleva esta cinta?», y los filtros no se miran
		# todavía porque es el destino quien va a decir qué se le manda.
		var dest = net.route_destination(cell_position, seg);
		if dest == null or not is_instance_valid(dest):
			continue;
		if dest.factory_type == "storage":
			continue;
		if servidos.has(dest.cell_position):
			continue;
		for material in dest.itemNeeded:
			if material == null or BELT_EXCLUDED_MATERIALS.has(material):
				continue;
			# Ahora sí, con material: si un filtro del camino lo corta, esta cinta no lo lleva.
			if net.route_destination(cell_position, seg, material) == null:
				continue;
			var libre = int(bag.getAvailable(material)) - int(comprometido.get(material, 0));
			var sale = int(min(pedido, libre));
			if sale <= 0:
				continue;
			comprometido[material] = int(comprometido.get(material, 0)) + sale;
			servidos[dest.cell_position] = true;
			bag.removeFromBag(material, sale);
			# POR QUÉ CINTA va ESTA emisión, para el encaminador. Se pone justo antes de emitir
			# y se borra justo después: la señal es SÍNCRONA, así que Main la lee dentro de este
			# mismo emit() y nadie más la ve nunca puesta.
			emit_route_cell = seg.cell;
			resource_produced.emit(material, sale, global_position);
			emit_route_cell = null;
			ha_emitido = true;
			# Un solo material por destino y por tick.
			break;
	return ha_emitido;

func _tick_restoration():
	# El output efectivo dice cuánto rinde la factoría por tick, también en restauración:
	# un Reforester sobre `fertile` (output_bonus: 2) limpia x3 en vez de x1.
	_apply_pollution(getRestorationScale());
	# Sin ventana no se anima (M0b): ver `animations_enabled`.
	if animations_enabled:
		get_node("AnimatedSprite2D").play();

func _apply_pollution(output_scale = 1.0):
	var pm = _pollutionManager();
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

# Desde M2 los insumos salen del BÚFER DE ENTRADA, no de la bolsa global: una factoría solo
# come lo que una cinta le ha traído. Es el cambio del que cuelga todo el plan de cintas —una
# WoodProcessing en la esquina opuesta del mapa ya no se alimenta sola—.
#
# Con él desaparece de este camino la reserva del peaje (`Bag.getAvailable()`, que apartaba lo
# que el checkpoint en curso exige para que una serrería rápida no se comiera la madera del
# mantenimiento). No hace falta aquí: el búfer es de la factoría y no está compartido con el
# almacén, así que nadie puede quemar el peaje como insumo. La reserva sigue viva y sin tocar
# en `Bag` para lo que sí la necesita, el evaluador de checkpoints.
func checkNeeds():
	for x in itemNeeded:
		if int(input_buffer.get(x, 0)) > 0:
			continue;
		else:
			return false;
	return true;

func consumeNeeds():
	for x in itemNeeded:
		input_buffer[x] = max(0, int(input_buffer.get(x, 0)) - 1);

# Lo que una cinta entrega. Lo llama beltNetwork.deliver() al encontrar esta factoría al final
# del camino, y solo si el material está en su `recieve`: aquí no se vuelve a comprobar para
# que la regla de aceptación viva en un único sitio.
func receiveMaterial(material, amount):
	input_buffer[material] = int(input_buffer.get(material, 0)) + amount;

func _on_timer_timeout():
	timer += 1;
	if int(timer) % int(getEffectiveTick()) == 0:
		update(get_parent().get_node("Player").get_node("Bag"));
