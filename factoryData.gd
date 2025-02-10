extends Area2D

var type;
var production;
var tickTimer;
var itemNeeded = [];
var timer = 0;

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
		get_node("AnimatedSprite2D").play()

func checkNeeds(bag):
	for x in itemNeeded:
		if bag[x].quantity > 0:
			continue
		else:
			return false
	return true

func _on_timer_timeout():
	timer += 1
	if int(timer) % int(tickTimer) == 0:
		update(get_parent().get_node("Player").get_node("Bag"))
