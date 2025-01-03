extends Node2D

var availableFactories = [];
var inventoryPixelsForFactory = 64

@export var factoryTemplate: PackedScene

# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.

func initialize(availableFactories):
	for x in availableFactories:
		var factory = factoryTemplate.instantiate()
		factory.initialize(x);
		add_child(factory)

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass
