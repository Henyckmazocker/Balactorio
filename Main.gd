extends Node

var factoryArray = [];
var wood = 0;
var timer = 0;
var file = "resources/factoryParams.json"
var fileData;

@export var factory: PackedScene
@export var player: PackedScene
@export var inventory: PackedScene
@export var grid: PackedScene

# Called when the node enters the scene tree for the first time.
func _ready():
	var player = player.instantiate()
	add_child(player)
	var playGrid = grid.instantiate()
	add_child(playGrid)
	var json_as_text = FileAccess.get_file_as_string(file)
	fileData = JSON.parse_string(json_as_text)
	initiateInventory(player)
	
func initiateInventory(player):
	var inventario = inventory.instantiate()
	inventario.initialize(player.availableFactories, fileData);
	add_child(inventario)
	
# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	get_node("Label").text = str(get_node("Player").get_node("Bag").bag.wood)

func _input(event):
	var mouse_pos = get_node("TileMap").get_local_mouse_position()
	var cell = get_node("TileMap").local_to_map(mouse_pos)
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed and get_node("TileMap").get_cell_source_id(0, cell) != -1:
			if(get_node("Player").selectedFactory == null):
				get_node("Player").selectedFactory = get_node("Player").availableFactories[0]
			var selectedFactoryParams = fileData.Factories[get_node("Player").selectedFactory]
			var fabrica = factory.instantiate()
			fabrica.initialize(
				get_node("Player").selectedFactory, 
				selectedFactoryParams.tick, 
				selectedFactoryParams.recieve,
				selectedFactoryParams.material
				)
				
			var tile_center = get_node("TileMap").map_to_local(cell)
			var tile_size = get_node("TileMap").tile_set.tile_size
			tile_center.y -= tile_size.y / 4
			tile_center.x += tile_size.x / 4
			fabrica.global_position = tile_center
			add_child(fabrica)
			factoryCreated(fabrica)

func _on_timer_timeout():
	timer += 1
	for x in factoryArray:
		if int(timer) % int(x.tickTimer) == 0:
			x.update(get_node("Player").get_node("Bag"))

func factoryCreated(node):
	factoryArray.append(node)
