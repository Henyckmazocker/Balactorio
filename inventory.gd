extends Node2D

var availableFactories = [];
var inventoryPixelsForFactory = 64

@export var factoryTemplate: PackedScene
@export var inventoryPosition: Node2D

# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.

func initialize(availableFactories, fileData):
	for x in availableFactories:
		var factory = factoryTemplate.instantiate()
		var inventoryFactory = fileData.Factories[x]
		factory.initialize(
			x, 
			inventoryFactory.tick, 
			inventoryFactory.recieve, 
			inventoryFactory.material
			)
		factory.position = inventoryPosition.position
		add_child(factory)

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass
