extends Area2D

var type;
var production;
var tickTimer;
var itemNeeded = [];

func _ready():
	pass

func initialize(name, tick, itemNeeded, material):
	type = name
	tickTimer = tick
	production = material
	if itemNeeded != null:
		for x in itemNeeded:
			itemNeeded.append(x)

func update(bag):
	if checkNeeds(bag):
		bag.addToBag(production, 1)

func checkNeeds(bag):
	for x in itemNeeded:
		if bag[x].quantity > 0:
			continue
		else:
			return false
	return true

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass
