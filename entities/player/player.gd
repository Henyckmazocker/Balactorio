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
