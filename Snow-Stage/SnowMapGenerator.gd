extends Node3D

const MAP_SIZE = 20
const TILE_SIZE = 1.0 # Standard size of kenney tiles
const HALF_STEP = 2 # path lives on a half-resolution grid -> spacing is automatic
const MAX_ROUTE_RETRIES = 10 # how many times to re-roll the zigzag if a leg gets boxed in

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
var enemy_path: Array[Vector2i] = []
# O(1) lookup of position -> index in enemy_path (replaces .has()/.find())
var path_lookup: Dictionary = {}

var spawner_script = preload("res://Snow-Stage/Spawner.gd")

# Batching containers for repeated static meshes
var mm_base: MultiMeshInstance3D
var mm_tree: MultiMeshInstance3D
var mm_tree_large: MultiMeshInstance3D
var mm_rock: MultiMeshInstance3D

func _ready():
	randomize() # only need to seed the RNG once, not every generation
	_generate_path()
	_build_map()
	_setup_spawner()

var target_end: Vector2i

# --- Path generation ----------------------------------------------------
#
# The path lives on a HALF-RESOLUTION grid (steps of 2 real cells), so any
# two path segments are always at least one cell apart automatically —
# that satisfies the "one gap between path lines" rule by construction.
#
# To guarantee the whole map gets used and the path reads as genuinely
# complex, the route is forced through checkpoints at each QUARTER of the
# map's width, and each checkpoint alternates between the top and bottom
# of the map. That forces a zigzag: right, then up (or down), then down
# (or up), then right again — a direction change is baked in at every
# quarter, instead of leaving shape to chance.
#
# Each leg between consecutive waypoints is its own independent maze
# spanning tree, built only over cells earlier legs haven't already used
# — so the zigzag can never fold back over itself.

func _generate_path():
	var start_y = randi_range(1, MAP_SIZE - 2)
	var end_y = _random_matching_parity(1, MAP_SIZE - 2, start_y)

	var start_pos = Vector2i(1, start_y)
	target_end = Vector2i(MAP_SIZE - 2, end_y)

	var target_x_half = MAP_SIZE - 2
	if (target_x_half - start_pos.x) % 2 != 0:
		target_x_half -= 1
	var target_half = Vector2i(target_x_half, end_y)

	var half_path: Array[Vector2i] = []

	for attempt in range(MAX_ROUTE_RETRIES):
		var desired_mids = _build_quarter_targets()
		half_path = _route_through_waypoints(start_pos, desired_mids, target_half)
		if not half_path.is_empty():
			break

	if half_path.is_empty():
		# Fallback: drop the zigzag requirement entirely and just connect
		# start to target with one unrestricted maze leg.
		var parent = _build_maze_spanning_tree(start_pos, {})
		if parent.has(target_half):
			half_path = _extract_path(start_pos, target_half, parent)
		else:
			half_path = [start_pos, target_half]

	var full_path = _expand_half_path(half_path)
	if full_path[-1] != target_end:
		full_path.append(target_end)

	enemy_path = full_path
	path_lookup.clear()
	for i in range(enemy_path.size()):
		path_lookup[enemy_path[i]] = i

func _build_quarter_targets() -> Array[Vector2i]:
	# Desired (approximate) real-grid positions at 1/4, 2/4, and 3/4 of the
	# map's width, alternating between the top and bottom of the map so
	# each leg is forced into a different vertical direction than the last.
	var q1_x = clampi(int(MAP_SIZE / 4.0), 1, MAP_SIZE - 2)
	var q2_x = clampi(int(MAP_SIZE / 2.0), 1, MAP_SIZE - 2)
	var q3_x = clampi(int(3.0 * MAP_SIZE / 4.0), 1, MAP_SIZE - 2)

	var y_top = clampi(int(MAP_SIZE / 4.0), 1, MAP_SIZE - 2)
	var y_bottom = clampi(int(3.0 * MAP_SIZE / 4.0), 1, MAP_SIZE - 2)

	var flip = (randi() % 2 == 0)
	var ys = [y_top, y_bottom, y_top]
	if flip:
		ys = [y_bottom, y_top, y_bottom]

	return [Vector2i(q1_x, ys[0]), Vector2i(q2_x, ys[1]), Vector2i(q3_x, ys[2])]

func _route_through_waypoints(start_pos: Vector2i, desired_mids: Array[Vector2i], target_half: Vector2i) -> Array[Vector2i]:
	var full_half_path: Array[Vector2i] = [start_pos]
	var blocked: Dictionary = {start_pos: true}
	var current_root = start_pos

	for desired in desired_mids:
		var checkpoint = _pick_checkpoint_near(current_root, desired)
		if checkpoint == current_root:
			continue # degenerate on a tiny map — just skip this waypoint

		var parent = _build_maze_spanning_tree(current_root, blocked)
		if not parent.has(checkpoint):
			return [] # boxed in — caller will re-roll with a fresh zigzag

		var leg = _extract_path(current_root, checkpoint, parent)
		for i in range(1, leg.size()):
			full_half_path.append(leg[i])
			blocked[leg[i]] = true

		current_root = checkpoint

	var parent_final = _build_maze_spanning_tree(current_root, blocked)
	if not parent_final.has(target_half) and target_half != current_root:
		return []

	if target_half != current_root:
		var leg_final = _extract_path(current_root, target_half, parent_final)
		for i in range(1, leg_final.size()):
			full_half_path.append(leg_final[i])

	return full_half_path

func _pick_checkpoint_near(root: Vector2i, desired: Vector2i) -> Vector2i:
	var cx = _nearest_matching_parity(desired.x, 1, MAP_SIZE - 2, root.x)
	var cy = _nearest_matching_parity(desired.y, 1, MAP_SIZE - 2, root.y)
	return Vector2i(cx, cy)

func _nearest_matching_parity(target: int, lo: int, hi: int, reference: int) -> int:
	var best = -1
	var best_dist = INF
	for v in range(lo, hi + 1):
		if (v - reference) % 2 == 0:
			var d = abs(v - target)
			if d < best_dist:
				best_dist = d
				best = v
	return best

func _random_matching_parity(lo: int, hi: int, reference: int) -> int:
	var candidates: Array[int] = []
	for v in range(lo, hi + 1):
		if (v - reference) % 2 == 0:
			candidates.append(v)
	return candidates[randi() % candidates.size()]

func _build_maze_spanning_tree(root: Vector2i, blocked: Dictionary) -> Dictionary:
	# Iterative randomized DFS ("recursive backtracker") over every
	# half-grid cell in bounds, skipping any cell in `blocked`.
	var parent: Dictionary = {}
	var visited: Dictionary = {root: true}
	var stack: Array[Vector2i] = [root]

	while not stack.is_empty():
		var current = stack[-1]
		var dirs = [Vector2i(0, HALF_STEP), Vector2i(0, -HALF_STEP), Vector2i(HALF_STEP, 0), Vector2i(-HALF_STEP, 0)]
		dirs.shuffle()

		var advanced = false
		for dir in dirs:
			var next_pos = current + dir
			if next_pos.x < 1 or next_pos.x > MAP_SIZE - 2 or next_pos.y < 1 or next_pos.y > MAP_SIZE - 2:
				continue
			if visited.has(next_pos) or blocked.has(next_pos):
				continue

			visited[next_pos] = true
			parent[next_pos] = current
			stack.append(next_pos)
			advanced = true
			break

		if not advanced:
			stack.pop_back()

	return parent

func _extract_path(root: Vector2i, target: Vector2i, parent: Dictionary) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	var node = target
	while node != root:
		path.append(node)
		node = parent[node]
	path.append(root)
	path.reverse()
	return path

func _expand_half_path(half_path: Array[Vector2i]) -> Array[Vector2i]:
	# Turns each 2-cell hop into two real, adjacent tiles (the midpoint
	# connector plus the destination), so the final path is a normal
	# single-cell-wide corridor again.
	var full: Array[Vector2i] = []
	full.append(half_path[0])
	for i in range(1, half_path.size()):
		var a = half_path[i - 1]
		var b = half_path[i]
		var mid = (a + b) / 2
		full.append(mid)
		full.append(b)
	return full

func _build_map():
	for child in get_children():
		child.queue_free()

	# Pull a single mesh out of each repeated-prop scene once, then batch
	# every placement of that prop into one MultiMeshInstance3D.
	mm_base = _make_multimesh_node("BaseTiles", tile_base)
	mm_tree = _make_multimesh_node("Trees", tree_model)
	mm_tree_large = _make_multimesh_node("TreesLarge", tree_large_model)
	mm_rock = _make_multimesh_node("Rocks", rock_model)

	var base_transforms: Array[Transform3D] = []
	var tree_transforms: Array[Transform3D] = []
	var tree_large_transforms: Array[Transform3D] = []
	var rock_transforms: Array[Transform3D] = []

	for x in range(MAP_SIZE):
		for z in range(MAP_SIZE):
			var pos = Vector2i(x, z)
			# O(1) dictionary lookup instead of enemy_path.has()/.find()
			if path_lookup.has(pos):
				_place_path_tile(pos)
			else:
				var origin = Vector3(pos.x * TILE_SIZE, 0, pos.y * TILE_SIZE)
				base_transforms.append(Transform3D(Basis(), origin))

				if randf() > 0.8:
					var r = randf()
					var rot_y = randf() * TAU
					var deco_basis = Basis(Vector3.UP, rot_y)
					var deco_xform = Transform3D(deco_basis, origin)
					if r > 0.6:
						tree_transforms.append(deco_xform)
					elif r > 0.3:
						tree_large_transforms.append(deco_xform)
					else:
						rock_transforms.append(deco_xform)

	_apply_multimesh(mm_base, base_transforms)
	_apply_multimesh(mm_tree, tree_transforms)
	_apply_multimesh(mm_tree_large, tree_large_transforms)
	_apply_multimesh(mm_rock, rock_transforms)

# --- MultiMesh helpers -------------------------------------------------

func _extract_mesh(scene: PackedScene) -> Mesh:
	var temp = scene.instantiate()
	var mesh: Mesh = null
	if temp is MeshInstance3D:
		mesh = temp.mesh
	else:
		for child in temp.get_children():
			if child is MeshInstance3D:
				mesh = child.mesh
				break
	temp.queue_free()
	return mesh

func _make_multimesh_node(node_name: String, scene: PackedScene) -> MultiMeshInstance3D:
	var mmi = MultiMeshInstance3D.new()
	mmi.name = node_name
	add_child(mmi)

	var mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _extract_mesh(scene)
	mmi.multimesh = mm
	return mmi

func _apply_multimesh(mmi: MultiMeshInstance3D, transforms: Array[Transform3D]) -> void:
	var mm: MultiMesh = mmi.multimesh
	mm.instance_count = transforms.size()
	for i in range(transforms.size()):
		mm.set_instance_transform(i, transforms[i])

# --- Path tiles (kept as individual instances — few of them, and each needs
# its own type + rotation, so this is not worth batching) ---------------

func _place_path_tile(pos: Vector2i):
	var index = path_lookup[pos] # O(1) instead of enemy_path.find(pos)

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
		if dir_in == dir_out:
			tile_instance = tile_straight.instantiate()
			rot_y = _get_rotation_from_dir(dir_out)
		else:
			tile_instance = tile_corner.instantiate()
			rot_y = _get_corner_rotation(dir_in, dir_out)

	_add_tile_to_scene(tile_instance, pos, rot_y)

func _add_tile_to_scene(instance, pos: Vector2i, rot_y: float):
	add_child(instance)
	instance.position = Vector3(pos.x * TILE_SIZE, 0, pos.y * TILE_SIZE)
	instance.rotation.y = rot_y

func _get_rotation_from_dir(dir: Vector2i) -> float:
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
	if (dir_in == Vector2i(1, 0) and dir_out == Vector2i(0, -1)) or \
	   (dir_in == Vector2i(0, 1) and dir_out == Vector2i(-1, 0)):
		return deg_to_rad(180)

	if (dir_in == Vector2i(0, -1) and dir_out == Vector2i(-1, 0)) or \
	   (dir_in == Vector2i(1, 0) and dir_out == Vector2i(0, 1)):
		return deg_to_rad(270)

	if (dir_in == Vector2i(-1, 0) and dir_out == Vector2i(0, 1)) or \
	   (dir_in == Vector2i(0, -1) and dir_out == Vector2i(1, 0)):
		return 0.0

	if (dir_in == Vector2i(0, 1) and dir_out == Vector2i(1, 0)) or \
	   (dir_in == Vector2i(-1, 0) and dir_out == Vector2i(0, -1)):
		return deg_to_rad(90)

	return 0.0

func _setup_spawner() -> void:
	var old_spawner = get_node_or_null("Spawner")
	if old_spawner:
		old_spawner.queue_free()

	if enemy_path.is_empty():
		return

	var spawner = Node3D.new()
	spawner.name = "Spawner"
	spawner.set_script(spawner_script)
	add_child(spawner)

	spawner.setup(enemy_path)
