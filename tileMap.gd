extends TileMap

var last_hovered_cell: Vector2i = Vector2i(-1, -1)

func _process(_delta):
	# Obtener posición global del mouse y convertir al espacio del TileMap
	var mouse_pos = get_global_mouse_position()
	var local_pos = to_local(mouse_pos)
	var cell = local_to_map(local_pos)

	# Si la celda cambió
	if cell != last_hovered_cell:
		# Limpiar celda anterior en la capa de resaltado
		erase_cell(1, last_hovered_cell)
		
		# Si la celda actual tiene un tile en la capa base
		if get_cell_source_id(0, cell) != -1:
			# Colocar tile de resaltado (ajusta el atlas_coord según tu tileset)
			set_cell(1, cell, 0, Vector2i(0, 0))  # Ejemplo: atlas_coord (1,0)
			
		last_hovered_cell = cell
