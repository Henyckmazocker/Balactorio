extends Node

var factoryArray = [];
var wood = 0;
var timer;

@export var factory: PackedScene
@export var player: PackedScene

# Called when the node enters the scene tree for the first time.
func _ready():
	timer = 0.0;
	var player = player.instantiate()
	add_child(player)
	
# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	get_node("Label").text = str(get_node("Player").get_node("Bag").bag.wood)

func _input(event):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			var fabrica = factory.instantiate()
			fabrica.position = event.position
			add_child(fabrica)
			factoryCreated(fabrica);

		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			print("Wheel up")

func _on_timer_timeout():
	for x in factoryArray:
		get_node("Player").get_node("Bag").addToBag(x.type, 1)

func factoryCreated(node):
	factoryArray.append(node);
