extends Area2D

var tickTimer;
var type;
var deliversTo;
var recievesFrom;

func _ready():
	pass
	
func initialize(name, tick):
	tickTimer = tick;
	type = name;

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass
