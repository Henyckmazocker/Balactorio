extends Node2D

var inventoryPixelsForFactory = 64;
var player_ref = null;
var factory_nodes = {};
var file_data_ref = null;

@export var factoryTemplate: PackedScene
@export var inventoryPosition: Node2D

func _ready():
	pass;

func initialize(factories, fileData, player):
	player_ref = player;
	file_data_ref = fileData;
	var index = 0;
	for x in factories:
		_add_factory_node(x, index);
		index += 1;
	if factories.size() > 0:
		_on_factory_selected(factories[0]);

func _add_factory_node(factory_name, index):
	if factory_nodes.has(factory_name):
		return;
	var fact = factoryTemplate.instantiate();
	var inventoryFactory = file_data_ref["Factories"][factory_name];
	fact.initialize(
		factory_name,
		inventoryFactory["tick"],
		inventoryFactory["recieve"],
		inventoryFactory["material"]
	);
	fact.in_inventory = true;
	var base_pos = inventoryPosition.position;
	fact.position = base_pos + Vector2(0, index * inventoryPixelsForFactory);
	fact.scale = Vector2(scale.x, scale.y);
	fact.factory_selected.connect(_on_factory_selected);
	factory_nodes[factory_name] = fact;
	add_child(fact);

func addFactory(factory_name):
	if factory_nodes.has(factory_name):
		return;
	_add_factory_node(factory_name, factory_nodes.size());

func _on_factory_selected(factory_type):
	if player_ref:
		player_ref.selectedFactory = factory_type;
	for key in factory_nodes:
		if key == factory_type:
			factory_nodes[key].modulate = Color(1.5, 1.5, 0.5);
		else:
			factory_nodes[key].modulate = Color(1.0, 1.0, 1.0);

func _process(_delta):
	pass;

