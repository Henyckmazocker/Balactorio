extends Node

# Contaminación global acumulada. Cada tick de producción suma pollution_per_tick.
# Los edificios de restauración restan. El HUD y el tilemap consultan este nodo.

var total_pollution = 0.0;
var pollution_per_cell = {};       # Vector2i -> float: contaminación local por casilla
# Máximo histórico del total. Es la memoria de cuánto se ha ensuciado: sin ella, en cuanto
# un Reforester limpia desaparece la evidencia y restaurar cuesta lo mismo hayas producido
# a lo bestia o con cuidado. NO baja nunca (ver removePollution): es lo que sostiene el
# pilar de diseño «producir sin piedad se paga después».
var peak_pollution = 0.0;
# Escala del TINTADO global del mapa (ver getNormalizedPollution). Subido de 50.0 a 200.0 al
# medir el pico real de una run sucia (180 en forest_01, 220 en wasteland_01): con 50 el tinte
# saturaba a los ~11 s y dejaba de informar.
# Desde M7 ya NO es la escala del HUD: el texto decía `Contaminación: 14209 / 200` y ese
# cociente deja de querer decir nada en cuanto el contagio arranca —el 200 se calibró para un
# mundo sin contagio—. Quien comunica la gravedad de verdad es el tinte, que sí se ve.
var pollution_threshold = 200.0;
# Contaminación LOCAL que satura una casilla (getCellPollution → 1.0) y por tanto la cierra
# a la construcción vía tileMap.isCellBlocked() → canPlaceFactory(). Era pollution_threshold
# * 0.25 = 12.5; se desacopla en su propia constante para que recalibrar la escala del tintado
# no mueva ni un punto la regla de colocación.
var cell_block_pollution = 12.5;
# Umbral de restauración escalado: thr = base + factor * pico. Con el pico a 0 vale el 5.0
# de siempre; una run sucia de pico 200 tiene que bajar a 29. El factor sale del barrido de
# M0 (tests/sim_m0.gd) remedido tras M0.5.
# Contaminación LOCAL a partir de la cual una casilla desborda sobre sus vecinas (ver
# tileMap.tick_contagion). Arranca en el punto de saturación, 12,5, pero es constante propia
# por la misma razón por la que cell_block_pollution se separó de pollution_threshold:
# recalibrar CUÁNDO desborda no debe mover ni un punto la regla de colocación.
var contagion_pollution = 12.5;
# Lo que un foco GENERA sobre cada vecina, POR SEGUNDO (tick_contagion lo escala por delta,
# igual que passive_pollution_per_tick). 0,12 sale MEDIDO del spike de M6
# (tests/sim_derrota.gd, bloques 1 y 2): es el valor más bajo del barrido que colapsa un mapa
# abandonado —seis WoodCutter y nadie que vuelva— en menos de diez minutos en los DOS mapas,
# que es lo que hace que el derrumbe se vea venir dentro de una sentada:
#   rate  0,00   0,02    0,05    0,08    0,10    0,12    0,20   -> run_lost en forest_01
#         nunca  nunca   1310 s   780 s   650 s   564 s   382 s
#         nunca  —        988 s   642 s   —       450 s   296 s  -> y en wasteland_01
# Con 0,00 el mapa conserva 150 casillas libres para siempre (la derrota es inalcanzable, que
# es la razón entera de que el contagio exista) y con 0,02 todavía le quedan 30 a los 2000 s.
# Y no lo nota una run jugada con cuidado: con Reforester pegados a la línea y racimo sobre
# los focos, el pico de forest_01 pasa de 46,2 (sin contagio) a 74,9 y el umbral de
# restauración de 10,5 a 14,0; en wasteland_01, de 59,6 a 61,0 y de 12,2 a 12,3. Las dos
# cierran 5/5 en los mismos 205 s y 343 s que sin contagio: el número no le quita ritmo a
# quien limpia, solo a quien abandona.
var contagion_rate = 0.12;
var restoration_base = 5.0;
var restoration_peak_factor = 0.12;

# Vecindario de 8 sobre el que se reparte la limpieza en área (ver removePollutionArea).
const NEIGHBOR_OFFSETS = [
	Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1),
	Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1)
];

signal pollution_changed(new_total);

func addPollution(amount, cell = null):
	total_pollution += amount;
	if total_pollution > peak_pollution:
		peak_pollution = total_pollution;
	if cell != null:
		if not pollution_per_cell.has(cell):
			pollution_per_cell[cell] = 0.0;
		pollution_per_cell[cell] += amount;
	pollution_changed.emit(total_pollution);

# El global solo baja lo que se ha quitado DE VERDAD de la casilla: la contaminación vive
# en las casillas, así que limpiar sobre una celda ya limpia no debe acercar la victoria.
# Sin esto, las nueve llamadas de _spread_restoration() descontaban del global nueve veces
# aunque solo una casilla tuviera suciedad, y la geometría del Reforester daba igual.
# Sin celda (null) se sigue descontando del global a secas: es el camino que usan los
# efectos que no viven en ninguna casilla.
# peak_pollution NO se toca aquí: limpiar borra la suciedad, no el recuerdo de haberla hecho.
func removePollution(amount, cell = null):
	if cell != null:
		var actual = pollution_per_cell.get(cell, 0.0);
		var quitado = min(amount, actual);
		if quitado > 0.0:
			pollution_per_cell[cell] = actual - quitado;
			total_pollution = max(0.0, total_pollution - quitado);
	else:
		total_pollution = max(0.0, total_pollution - amount);
	pollution_changed.emit(total_pollution);

# Limpieza en área: reparte `amount` entre la celda y sus 8 vecinas, un noveno cada una.
# Vive aquí y no en quien limpia porque lo usan dos sitios —las factorías de restauración
# (factoryData._spread_restoration) y los tiles limpiadores como el lago
# (tileMap.tick_passive)—, y duplicar el reparto era duplicar también su aritmética fina:
# removePollution() descuenta del global solo lo que quita de cada casilla, así que el
# noveno que cae sobre una casilla limpia se pierde. Esa pérdida es la mecánica: premia
# cubrir lo sucio y castiga apilar limpieza sobre lo ya limpio.
func removePollutionArea(amount, cell):
	var share = amount / 9.0;
	removePollution(share, cell);
	for offset in NEIGHBOR_OFFSETS:
		removePollution(share, cell + offset);

# Desborde de un foco sobre sus 8 vecinas. GENERA, no reparte: cada vecina recibe `amount`
# entero y el foco no pierde nada. Repartir conservaría el total global y el mapa convergería
# a un empate tibio por debajo de la saturación; generar es lo que hace que una zona sucia
# CREZCA, que es la espiral de la que cuelga la derrota. El precio, aceptado, es que
# peak_pollution sube con ella y con él el umbral de restauración.
# Se suma POR CASILLA con addPollution(amount, cell) y nunca al global a secas: removePollution()
# solo descuenta del global lo que quita DE VERDAD de una casilla, así que contagio sumado al
# global a pelo sería suciedad que ningún Reforester podría deshacer jamás.
# `is_valid` lo pone quien llama para filtrar vecinas: aquí no se sabe qué casillas existen
# —eso lo sabe el TileMap—, y sin el filtro el contagio se saldría del mapa.
func spreadFrom(cell, amount, is_valid = null):
	for offset in NEIGHBOR_OFFSETS:
		var neighbor = cell + offset;
		if is_valid != null and not is_valid.call(neighbor):
			continue;
		addPollution(amount, neighbor);

# Devuelve un valor 0..1 representando el nivel de contaminación global (saturado a 1)
func getNormalizedPollution():
	return clamp(total_pollution / pollution_threshold, 0.0, 1.0);

# Devuelve nivel 0..1 de contaminación para una celda concreta
func getCellPollution(cell):
	if pollution_per_cell.has(cell):
		return clamp(pollution_per_cell[cell] / cell_block_pollution, 0.0, 1.0);
	return 0.0;

# Umbral efectivo de victoria de la fase de restauración: cuanto más alto fue el pico, más
# hay que limpiar para cerrar la run.
func getRestorationThreshold():
	return restoration_base + restoration_peak_factor * peak_pollution;

func isRestored():
	return total_pollution <= getRestorationThreshold();

# El HUD enseña el total y el umbral EFECTIVO de restauración: si el objetivo se mueve porque
# el jugador ha ensuciado más, tiene que poder verlo mientras juega.
# El denominador fijo (pollution_threshold) SALIÓ del HUD en M7, por dos razones a la vez:
#   1. Mentía. `Contaminación: 14209 / 200` no informa de nada; el 200 es la escala del tinte,
#      calibrada para un mundo sin contagio, y nunca fue un objetivo que alcanzar.
#   2. Ocupaba los 8 caracteres que hacían que la línea del HUD se saliera de pantalla cuando
#      el aviso de colapso se le pone delante (ver gameManager.HUD_MAX_CHARS).
# El número que el jugador sí necesita es el umbral de restauración, que ya escala con el pico.
func getStatusText():
	return "Contaminación: %d  (restaurar: ≤ %d)" % [
		int(total_pollution), int(getRestorationThreshold())];

func reset():
	total_pollution = 0.0;
	pollution_per_cell.clear();
	peak_pollution = 0.0;
	pollution_changed.emit(0.0);
