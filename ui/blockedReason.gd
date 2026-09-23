extends RefCounted

# La razón por la que una factoría está parada, dicha en palabras y con su color. La usan las
# DOS superficies de detalle —`ui/factoryTooltip.gd` (hover) y `ui/factoryPanel.gd` (panel)—,
# que tienen que decir exactamente lo MISMO: son la misma pregunta hecha con el ratón quieto o
# con el panel abierto, y dos redacciones del mismo estado se leerían como dos estados.
#
# Por qué un fichero y no una copia en cada una, que es lo que hacen `_amount_text()` del panel
# y `_cost_text()` del radial: aquel precedente son dos pantallas SIN relación que coinciden en
# un formato, y aquí lo compartido no es un formato sino la regla viva de `reason_now()`. Una
# regla duplicada diverge sin que nada falle.

# Los colores NO se copian: se leen de donde los tiene puestos el mapa
# (`entities/tilemap/tileMap.gd`, STATUS_COLORS, que los declara como vocabulario de PANTALLA y
# no del modelo). El icono sobre la casilla y la frase del panel son el mismo estado visto de
# cerca y de lejos: con dos paletas el jugador aprendería dos vocabularios para una sola cosa.
const TILE_MAP = preload("res://entities/tilemap/tileMap.gd");

# Una frase por razón, corta y con la ACCIÓN dentro. El jugador no abre el panel para que le
# describan lo que ya ve —que la factoría está quieta—, sino para saber qué hacer: las cuatro
# acciones son las de la tabla del plan (reasignar / cinta de entrada / cinta de salida /
# limpiar), y ninguna nombra la superficie desde la que se lee, porque la misma frase sale en
# las dos.
# No se nombra el material que falta («sin madera que procesar») a propósito: las dos
# superficies ya pintan «Necesita: wood» dos líneas más arriba, y los materiales son
# identificadores en inglés que habría que traducir aquí con una tabla que nadie más usa.
const TEXTS := {
	"workers": "⚠ Parada: le faltan workers — reasigna uno",
	"input":   "⚠ Parada: sin insumo — tiéndele cinta de entrada",
	"output":  "⚠ Parada: salida llena — tiéndele cinta de salida",
	"choke":   "⚠ Parada: la ahoga el suelo — limpia la casilla",
};

# La razón que se ENSEÑA ahora mismo, que no siempre es la que el modelo lleva escrita.
#
# `blocked_reason` lo escribe `factoryData.update()`, o sea UNA VEZ POR TICK (2-5 s): entre dos
# ticks el campo cuenta el tick anterior. Para tres de las cuatro razones da igual —se arreglan
# en el mapa, tendiendo cinta o limpiando, y el tick llega antes que el jugador—, pero la cuarta
# se arregla con los dos botones del propio panel: darle el worker que le falta dejaría la frase
# diciendo «le faltan workers» durante un tick entero, justo debajo de un «Workers: 1/1» en
# verde que dice lo contrario. Por eso la prioridad 1 se lee VIVA.
#
# Y esto no es una prioridad propia inventada en la UI: es la PRIMERA LÍNEA de
# `factoryData.update()` —`if not isActive(): blocked_reason = "workers"`— leída en el momento
# en vez de un tick tarde. Nunca puede contradecir al modelo, solo adelantarlo.
#
# El "choke" parpadea entre razón y silencio tick sí tick no, porque el ahogo es una RAMPA y no
# una parada (ver `factoryData.update()`). Es a propósito y es lo mismo que hace el marcador del
# mapa: el jugador tiene que ver que esa casilla le está costando la mitad de la producción.
static func reason_now(factory) -> String:
	if factory == null or not is_instance_valid(factory):
		return "";
	if not factory.isActive():
		return "workers";
	# Y al revés: un "workers" con la factoría YA activa es la razón caducada del tick anterior.
	# Callar es lo honesto —el tick que viene dirá si ahora le falta otra cosa—; seguir
	# enseñándola es justo la etiqueta pegada que la enmienda del plan viene a evitar.
	if factory.blocked_reason == "workers":
		return "";
	return factory.blocked_reason;

# La frase de esa razón, o "" si no hay nada que decir. Se pregunta contra "" y contra las
# claves del diccionario, JAMÁS contra el texto "null": `str(null)` devuelve "<null>", y esa
# comparación es la que pintó «Produce: <null>» durante meses en `ui/factoryTooltip.gd`.
# Una razón que nadie ha declarado no dice nada, igual que no pinta nada en el mapa: mejor una
# superficie callada que una frase que el jugador no sabe leer.
static func text_for(reason) -> String:
	return TEXTS.get(reason, "");

# El color con el que se escribe, el mismo con el que el mapa pinta su marcador. El gris de
# reserva no se usa nunca por el camino normal —sin frase no hay etiqueta que colorear—, pero
# una razón sin color no puede salir en negro sobre el fondo oscuro del panel.
static func color_for(reason) -> Color:
	return TILE_MAP.STATUS_COLORS.get(reason, Color(0.9, 0.9, 0.9));
