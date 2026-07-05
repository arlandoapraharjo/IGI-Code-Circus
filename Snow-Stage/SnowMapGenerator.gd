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

func _ready():
	_generate_path()
	_build_map()

func _generate_path():
	enemy_path.clear()
	# Randomize seed so the path changes every time you play
	randomize()
	
	# Start at the left edge (x=0) with a random Y position
	var current = Vector2i(0, randi_range(2, MAP_SIZE - 3))
	enemy_path.append(current)
	
	var current_dir = 0 # 0: Right, 1: Down, -1: Up
	
	while current.x < MAP_SIZE - 1:
		var segment_length = 0
		
		if current_dir == 0:
			# Going right, decide how far to go (2 to 4 steps)
			segment_length = randi_range(2, 4)
			# Don't go past the right edge
			segment_length = min(segment_length, (MAP_SIZE - 1) - current.x)
			
			for i in range(segment_length):
				current.x += 1
				enemy_path.append(current)
				
			# If we haven't reached the right edge, decide to turn up or down
			if current.x < MAP_SIZE - 1:
				if current.y <= 2:
					current_dir = 1 # Too close to top edge, must go down
				elif current.y >= MAP_SIZE - 3:
					current_dir = -1 # Too close to bottom edge, must go up
				else:
					current_dir = 1 if randf() > 0.5 else -1 # Random up or down
		else:
			# Going up or down
			segment_length = randi_range(2, 4)
			
			if current_dir == 1:
				# Going down
				segment_length = min(segment_length, (MAP_SIZE - 2) - current.y)
				for i in range(segment_length):
					current.y += 1
					enemy_path.append(current)
			else:
				# Going up
				segment_length = min(segment_length, current.y - 1)
				for i in range(segment_length):
					current.y -= 1
					enemy_path.append(current)
					
			# After moving vertically, we MUST go right to progress towards the end
			current_dir = 0

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
	# Corner tiles usually connect from -Z to +X or similar.
	# We need to map combinations of (dir_in, dir_out) to Y rotations.
	# In this logic:
	# dir_in is the vector FROM previous TO current
	# dir_out is the vector FROM current TO next
	
	if (dir_in == Vector2i(0, 1) and dir_out == Vector2i(1, 0)) or (dir_in == Vector2i(-1, 0) and dir_out == Vector2i(0, -1)):
		# Path came from Z- (going Z+) and turns X+, OR came from X+ (going X-) and turns Z-
		return -PI / 2.0
	if (dir_in == Vector2i(0, 1) and dir_out == Vector2i(-1, 0)) or (dir_in == Vector2i(1, 0) and dir_out == Vector2i(0, -1)):
		return PI
	if (dir_in == Vector2i(0, -1) and dir_out == Vector2i(1, 0)) or (dir_in == Vector2i(-1, 0) and dir_out == Vector2i(0, 1)):
		return 0.0
	if (dir_in == Vector2i(0, -1) and dir_out == Vector2i(-1, 0)) or (dir_in == Vector2i(1, 0) and dir_out == Vector2i(0, 1)):
		return PI / 2.0
		
	return 0.0
