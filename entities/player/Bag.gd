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
