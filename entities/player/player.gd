extends Node

var availableFactories = ["WoodCutter", "WoodProcessing"];
var speedModifiers = {};
var outputModifiers = {};

func applySpeedBoost(factory_name, amount):
	if not speedModifiers.has(factory_name):
		speedModifiers[factory_name] = 0;
	speedModifiers[factory_name] -= amount;

func applyExtraOutput(factory_name, amount):
	if not outputModifiers.has(factory_name):
		outputModifiers[factory_name] = 0;
	outputModifiers[factory_name] += amount;

func getTickForFactory(factory_name, base_tick):
	if speedModifiers.has(factory_name):
		return max(1, base_tick + speedModifiers[factory_name]);
	return base_tick;

func getOutputForFactory(factory_name, base_output):
	if outputModifiers.has(factory_name):
		return base_output + outputModifiers[factory_name];
	return base_output;

func reset():
	availableFactories = ["WoodCutter", "WoodProcessing"];
	speedModifiers = {};
	outputModifiers = {};

# ---------- Serialización de Run (M1) ----------

# Los modificadores se guardan ACUMULADOS y no como la lista de cartas que los produjo: es lo
# que factoryPlacer.build() lee al reconstruir, y repetir las cartas volvería a mutar las
# factorías ya construidas (Main._apply_upgrade()).
# Y salen como int —applySpeedBoost()/applyExtraOutput() solo suman enteros— para
# que snapshot() y restore() fijen el mismo tipo y la ida y vuelta sea `==` (M2).
func snapshot() -> Dictionary:
	return {
		"availableFactories": availableFactories.duplicate(),
		"speedModifiers": _int_values(speedModifiers),
		"outputModifiers": _int_values(outputModifiers),
	};

# Serialización de Run (M2): el espejo de snapshot(). Asigna, no suma: re-aplicar las cartas
# mutaría las factorías ya reconstruidas, que traen su tick y su output guardados. int() porque
# de JSON (M3) todo número vuelve como float.
func restore(d: Dictionary) -> void:
	availableFactories = [];
	for f in d.get("availableFactories", []):
		availableFactories.append(String(f));
	speedModifiers = _int_values(d.get("speedModifiers", {}));
	outputModifiers = _int_values(d.get("outputModifiers", {}));

func _int_values(src: Dictionary) -> Dictionary:
	var out = {};
	for k in src:
		out[String(k)] = int(src[k]);
	return out;
