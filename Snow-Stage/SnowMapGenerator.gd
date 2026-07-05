extends Node3D

const MAP_SIZE = 15
const TILE_SIZE = 1.0 # Standard size of kenney tiles

# Use load() instead of preload to avoid strict parse-time path requirements
var tile_base = load("res://kenney_tower-defense-kit/Models/GLB format/snow/snow-tile.glb")
var tile_straight = load("res://kenney_tower-defense-kit/Models/GLB format/snow/snow-tile-straight.glb")
var tile_corner = load("res://kenney_tower-defense-kit/Models/GLB format/snow/snow-tile-corner-round.glb")
var tile_spawn = load("res://kenney_tower-defense-kit/Models/GLB format/snow/snow-tile-spawn-round.glb")
var tile_end = load("res://kenney_tower-defense-kit/Models/GLB format/snow/snow-tile-end-round.glb")

var tree_model = load("res://kenney_tower-defense-kit/Models/GLB format/snow/snow-tile-tree.glb")
var tree_large_model = load("res://kenney_tower-defense-kit/Models/GLB format/snow/snow-tile-tree-double.glb")
var rock_model = load("res://kenney_tower-defense-kit/Models/GLB format/snow/snow-tile-rock.glb")

# Path definition: list of Vector2i grid coordinates
# We will define a simple S-shaped path starting from left and ending on the right
var enemy_path: Array[Vector2i] = []

var spawner_script = preload("res://Snow-Stage/Spawner.gd")

func _ready():
	_generate_path()
	_build_map()
	_setup_spawner()

var dfs_visited: Dictionary = {}
var target_end: Vector2i

func _generate_path():
	enemy_path.clear()
	randomize()
	
	# Spawn at x=1 (2nd tile from left)
	# Defense/End at x=MAP_SIZE-2 (2nd tile from right)
	var start_y = randi_range(1, MAP_SIZE - 2)
	var end_y = randi_range(1, MAP_SIZE - 2)
	
	var start_pos = Vector2i(1, start_y)
	target_end = Vector2i(MAP_SIZE - 2, end_y)
	
	var found = false
	
	# Try multiple times in case the random DFS traps itself in a dead end
	for attempt in range(100):
		dfs_visited.clear()
		enemy_path.clear()
		
		enemy_path.append(start_pos)
		dfs_visited[start_pos] = true
		
		if _dfs_step(start_pos):
			found = true
			break
			
	# Fallback just in case all 100 attempts fail (extremely rare)
	if not found:
		enemy_path.clear()
		for i in range(1, MAP_SIZE - 1):
			enemy_path.append(Vector2i(i, start_y))

func _dfs_step(current: Vector2i) -> bool:
	if current == target_end:
		return true
		
	var dirs = [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]
	dirs.shuffle()
	
	for dir in dirs:
		var next_pos = current + dir
		
		if _is_valid_step(next_pos):
			enemy_path.append(next_pos)
			dfs_visited[next_pos] = true
			
			if _dfs_step(next_pos):
				return true
				
			# Backtrack if it leads to a dead end
			enemy_path.pop_back()
			dfs_visited.erase(next_pos)
			
	return false

func _is_valid_step(pos: Vector2i) -> bool:
	# 1. Bounds check (strict 1-tile border all around)
	if pos.x < 1 or pos.x > MAP_SIZE - 2 or pos.y < 1 or pos.y > MAP_SIZE - 2:
		return false
		
	# 2. Prevent revisiting
	if dfs_visited.has(pos):
		return false
		
	# 3. Adjacency rule: Ensure exactly 1 tile gap between path lines
	var adjacent_visited = 0
	var check_dirs = [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]
	
	for dir in check_dirs:
		var neighbor = pos + dir
		if dfs_visited.has(neighbor):
			adjacent_visited += 1
			
	# A valid next step should only touch the cell we just came from
	# (which means exactly 1 adjacent visited cell).
	# We slightly relax this if we are stepping onto the target_end to allow finishing.
	if adjacent_visited > 1 and pos != target_end:
		return false
		
	return true

func _build_map():
	# Clear existing children just in case
	for child in get_children():
		child.queue_free()

	for x in range(MAP_SIZE):
		for z in range(MAP_SIZE):
			var pos = Vector2i(x, z)
			if enemy_path.has(pos):
				_place_path_tile(pos)
			else:
				_place_base_tile(pos)

func _place_path_tile(pos: Vector2i):
	var index = enemy_path.find(pos)
	
	var is_start = (index == 0)
	var is_end = (index == enemy_path.size() - 1)
	
	var dir_in = Vector2i.ZERO
	var dir_out = Vector2i.ZERO
	
	if not is_start:
		dir_in = pos - enemy_path[index - 1]
	if not is_end:
		dir_out = enemy_path[index + 1] - pos
		
	var tile_instance = null
	var rot_y = 0.0
	
	if is_start:
		tile_instance = tile_spawn.instantiate()
		rot_y = _get_rotation_from_dir(dir_out)
	elif is_end:
		tile_instance = tile_end.instantiate()
		rot_y = _get_rotation_from_dir(-dir_in)
	else:
		# Check if it's a straight path or a corner
		if dir_in == dir_out:
			tile_instance = tile_straight.instantiate()
			rot_y = _get_rotation_from_dir(dir_out)
		else:
			tile_instance = tile_corner.instantiate()
			# Determine corner rotation based on in and out directions
			rot_y = _get_corner_rotation(dir_in, dir_out)
	
	_add_tile_to_scene(tile_instance, pos, rot_y)

func _place_base_tile(pos: Vector2i):
	var tile_instance = tile_base.instantiate()
	_add_tile_to_scene(tile_instance, pos, 0.0)
	
	# Random chance to spawn decoration
	if randf() > 0.8:
		var r = randf()
		var deco_instance = null
		if r > 0.6:
			deco_instance = tree_model.instantiate()
		elif r > 0.3:
			deco_instance = tree_large_model.instantiate()
		else:
			deco_instance = rock_model.instantiate()
			
		if deco_instance:
			_add_tile_to_scene(deco_instance, pos, randf() * TAU)

func _add_tile_to_scene(instance, pos: Vector2i, rot_y: float):
	add_child(instance)
	# Kenney tiles usually have their origin at the bottom center.
	instance.position = Vector3(pos.x * TILE_SIZE, 0, pos.y * TILE_SIZE)
	instance.rotation.y = rot_y

func _get_rotation_from_dir(dir: Vector2i) -> float:
	# Assume default straight tile goes along Z axis (0, 1) or X axis (1, 0)
	# Needs to match the specific tile's forward direction.
	# Let's say straight tile aligns with Z axis.
	if dir == Vector2i(0, 1):
		return 0.0
	elif dir == Vector2i(0, -1):
		return PI
	elif dir == Vector2i(1, 0):
		return PI / 2.0
	elif dir == Vector2i(-1, 0):
		return -PI / 2.0
	return 0.0

func _get_corner_rotation(dir_in: Vector2i, dir_out: Vector2i) -> float:
	# Asset confirmed: 0deg = {West(-X), North(-Z)} openings.
	# Godot positive Y-rotation = CCW from above. Each 90deg CCW step:
	#   West→South, North→West, East→North, South→East
	#
	#   0deg:  {West,  North} 
	#   90deg: {South, West}    ← NOTE: 90deg CCW moves West→South, North→West
	#  180deg: {East,  South}
	#  270deg: {North, East}

	# 0deg → now 180deg
	if (dir_in == Vector2i(1, 0) and dir_out == Vector2i(0, -1)) or \
	   (dir_in == Vector2i(0, 1) and dir_out == Vector2i(-1, 0)):
		return deg_to_rad(180)

	# 90deg → now 270deg
	if (dir_in == Vector2i(0, -1) and dir_out == Vector2i(-1, 0)) or \
	   (dir_in == Vector2i(1, 0) and dir_out == Vector2i(0, 1)):
		return deg_to_rad(270)

	# 180deg → now 0deg
	if (dir_in == Vector2i(-1, 0) and dir_out == Vector2i(0, 1)) or \
	   (dir_in == Vector2i(0, -1) and dir_out == Vector2i(1, 0)):
		return 0.0

	# 270deg → now 90deg
	if (dir_in == Vector2i(0, 1) and dir_out == Vector2i(1, 0)) or \
	   (dir_in == Vector2i(-1, 0) and dir_out == Vector2i(0, -1)):
		return deg_to_rad(90)

	return 0.0

func _setup_spawner() -> void:
	# Remove any existing spawner to avoid duplicates on regeneration
	var old_spawner = get_node_or_null("Spawner")
	if old_spawner:
		old_spawner.queue_free()
		
	if enemy_path.is_empty():
		return
		
	var spawner = Node3D.new()
	spawner.name = "Spawner"
	spawner.set_script(spawner_script)
	add_child(spawner)
	
	# Pass the generated path to the spawner
	spawner.setup(enemy_path)
