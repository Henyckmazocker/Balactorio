extends Node

var bag = {};
var workers_total = 0;
var workers_assigned = 0;
# El peaje del checkpoint en curso: `material -> cantidad` que el almacén APARTA y que las
# factorías no pueden quemar como insumo. Lo sincroniza gameManager.update() con el
# mantenimiento del checkpoint que toca, así que el número que el HUD anuncia y el que la
# bolsa protege son el mismo. Existe porque el mantenimiento pide `wood`, que es también el
# insumo de la serrería: sin apartarlo, una mejora que acelere la serrería se come el peaje
# y el checkpoint no se cierra nunca — y sin condición de derrota eso es una run infinita.
var reserved = {};

func initialize(fileData):
	for factoryName in fileData["Factories"]:
		var material = fileData["Factories"][factoryName]["material"];
		if material != null and not bag.has(material):
			bag[material] = { "quantity": 0 };
	if fileData.has("Workers"):
		workers_total = int(fileData["Workers"]["initial"]);

func addToBag(type, quantity):
	if not bag.has(type):
		bag[type] = { "quantity": 0 };
	bag[type].quantity += quantity;

func removeFromBag(type, quantity):
	if bag.has(type):
		bag[type].quantity = max(0, bag[type].quantity - quantity);

func getQuantity(type):
	if bag.has(type):
		return bag[type].quantity;
	return 0;

# Sustituye la reserva entera de golpe, que es como piensa quien la pone: el checkpoint en
# curso exige esto y nada más. Un dict vacío la levanta (fase de restauración, o un
# checkpoint sin mantenimiento).
func setReserved(amounts):
	reserved = amounts.duplicate() if amounts != null else {};

func getReserved(type):
	return int(reserved.get(type, 0));

# Lo que una factoría puede consumir: todo menos la reserva. Nunca negativo — no se puede
# apartar lo que no hay, y lo que falta por reunir ya lo cuenta el requisito del checkpoint.
# El objetivo NO se reserva: quien se come un tablón (MetaFactory, WorkerCamp) solo retrasa
# el checkpoint, mientras que quien se come la madera del peaje lo impide para siempre.
func getAvailable(type):
	return max(0, getQuantity(type) - getReserved(type));

func getFreeWorkers():
	return workers_total - workers_assigned;

func assignWorkers(amount):
	workers_assigned = min(workers_assigned + amount, workers_total);

func unassignWorkers(amount):
	workers_assigned = max(0, workers_assigned - amount);

func addWorkers(amount):
	workers_total += amount;

func reset():
	for key in bag:
		bag[key].quantity = 0;
	workers_assigned = 0;
	reserved = {};

# ---------- Serialización de Run (M1) ----------

# Lo que la run en curso guarda de la bolsa. Copias PROFUNDAS: el snapshot no puede seguir
# vivo enganchado a la bolsa, o el autoguardado escribiría lo que haya en el frame en que se
# serializa y no lo del frame en que se capturó. `reserved` va aunque gameManager.update() lo
# re-sincronice cada frame: entre restaurar y ese primer update() las factorías ya leen
# getAvailable(), y sin la reserva se comerían el peaje del checkpoint en ese hueco.
#
# Los números salen con su tipo CANÓNICO —int, que es lo que la bolsa cuenta— y no tal cual: el
# `==` de dos Dictionary de GDScript distingue 3 de 3.0, así que la ida y vuelta de M2 solo es
# idéntica si snapshot() y restore() fijan el mismo tipo a cada campo (Serialización M2).
func snapshot() -> Dictionary:
	var materiales = {};
	for material in bag:
		materiales[material] = {"quantity": int(bag[material].quantity)};
	var apartado = {};
	for material in reserved:
		apartado[material] = int(reserved[material]);
	return {
		"bag": materiales,
		"workers_total": int(workers_total),
		"workers_assigned": int(workers_assigned),
		"reserved": apartado,
	};

# Serialización de Run (M2): el espejo de snapshot(). PISA la bolsa entera —claves incluidas—
# en vez de sumar como apply_package(): se llama la última al reanudar, después de que build()
# haya asignado workers a las factorías reconstruidas, y lo que vale es lo guardado. Todo pasa
# por int() porque un snapshot leído de JSON (M3) trae cada número como float.
func restore(d: Dictionary) -> void:
	bag = {};
	for material in d.get("bag", {}):
		bag[material] = {"quantity": int(d["bag"][material]["quantity"])};
	workers_total = int(d.get("workers_total", 0));
	workers_assigned = int(d.get("workers_assigned", 0));
	reserved = {};
	for material in d.get("reserved", {}):
		reserved[material] = int(d["reserved"][material]);
