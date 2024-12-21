extends Area2D

var tickTimer;
var type;

# Called when the node enters the scene tree for the first time.
func _ready():
	tickTimer = 1;
	type = "woodCutter";


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass
