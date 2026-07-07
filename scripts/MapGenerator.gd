extends Node3D

const MAP_SIZE = 20
const TILE_SIZE = 1.0 # Standard size of kenney tiles
const HALF_STEP = 2 # path lives on a half-resolution grid -> spacing is automatic
const MAX_ROUTE_RETRIES = 10 # how many times to re-roll the zigzag if a leg gets boxed in
const BUSH_VARIANT_COUNT = 4 # how many randomized wind/wiggle presets to spread bushes across
const BUSH_SCALE_MIN = 0.5 # smallest random bush size (1.0 = original mesh size)
const BUSH_SCALE_MAX = 0.75 # largest random bush size
const BUSH_CAST_SHADOWS = false # alpha-blended wind-animated shadows are expensive for how little bushes contribute visually
const BUSH_VISIBILITY_END = 35.0 # bushes fully disappear past this distance
const BUSH_VISIBILITY_FADE = 6.0 # distance over which they fade out, instead of popping

## Assign one or more BiomeData resources in the Inspector (one per biome —
## e.g. biome_snow.tres, biome_desert.tres, biome_grass.tres). One is picked
## at random each run. To force a specific biome instead of random, leave
## this populated but set forced_biome_index >= 0.
@export var biomes: Array[BiomeData] = []
@export var forced_biome_index: int = -1
## Drag the scene's WorldEnvironment node here so the generator can swap in
## the active biome's Environment resource.
@export var world_environment_node: WorldEnvironment

# Resolved from whichever BiomeData is active this run — populated by
# _apply_biome() before generation starts. Nothing below this point
# hardcodes a specific biome's assets.
var tile_base: PackedScene
var tile_straight: PackedScene
var tile_corner: PackedScene
var tile_spawn: PackedScene
var tile_end: PackedScene
var tree_model: PackedScene
var tree_large_model: PackedScene
var rock_model: PackedScene
var bush_model: PackedScene
var decoration_chance: float = 0.2

# Path definition: list of Vector2i grid coordinates
var enemy_path: Array[Vector2i] = []
# O(1) lookup of position -> index in enemy_path (replaces .has()/.find())
var path_lookup: Dictionary = {}

var spawner_script = preload("res://scripts/Spawner.gd")

# Batching containers for repeated static meshes
var mm_base: MultiMeshInstance3D
var mm_tree: MultiMeshInstance3D
var mm_tree_large: MultiMeshInstance3D
var mm_rock: MultiMeshInstance3D
# Bushes get several MultiMeshInstance3Ds, each with its own randomized wind
# preset, so not every bush sways in perfect unison.
var mm_bushes: Array[MultiMeshInstance3D] = []

func _ready():
	randomize() # only need to seed the RNG once, not every generation
	_apply_biome(_pick_biome())
	_generate_path()
	_build_map()
	_setup_spawner()

static var _current_biome_index: int = 0

func _pick_biome() -> BiomeData:
	assert(not biomes.is_empty(), "MapGenerator: no BiomeData assigned in the Inspector.")
	if forced_biome_index >= 0 and forced_biome_index < biomes.size():
		return biomes[forced_biome_index]
	
	var biome = biomes[_current_biome_index]
	_current_biome_index = (_current_biome_index + 1) % biomes.size()
	return biome

func _apply_biome(biome: BiomeData) -> void:
	tile_base = biome.tile_base
	tile_straight = biome.tile_straight
	tile_corner = biome.tile_corner
	tile_spawn = biome.tile_spawn
	tile_end = biome.tile_end

	tree_model = biome.tree_model
	tree_large_model = biome.tree_large_model
	rock_model = biome.rock_model
	bush_model = biome.bush_model

	decoration_chance = biome.decoration_chance

	if world_environment_node != null and biome.environment != null:
		world_environment_node.environment = biome.environment

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
		@warning_ignore("integer_division")
		var mid = (a + b) / 2 # a and b are always exactly 2 apart, so this is always exact
		full.append(mid)
		full.append(b)
	return full

func _build_map():
	for child in get_children():
		child.queue_free()

	# Pull a single mesh (and material) out of each repeated-prop scene
	# once, then batch every placement of that prop into one
	# MultiMeshInstance3D.
	mm_base = _make_multimesh_node("BaseTiles", tile_base)
	mm_tree = _make_multimesh_node("Trees", tree_model)
	mm_tree_large = _make_multimesh_node("TreesLarge", tree_large_model)
	mm_rock = _make_multimesh_node("Rocks", rock_model)
	mm_bushes = _make_bush_variant_nodes(bush_model, BUSH_VARIANT_COUNT)

	var base_transforms: Array[Transform3D] = []
	var tree_transforms: Array[Transform3D] = []
	var tree_large_transforms: Array[Transform3D] = []
	var rock_transforms: Array[Transform3D] = []
	var bush_transforms: Array = [] # array of Array[Transform3D], one per variant
	for i in range(BUSH_VARIANT_COUNT):
		var variant_list: Array[Transform3D] = []
		bush_transforms.append(variant_list)

	for x in range(MAP_SIZE):
		for z in range(MAP_SIZE):
			var pos = Vector2i(x, z)
			# O(1) dictionary lookup instead of enemy_path.has()/.find()
			if path_lookup.has(pos):
				_place_path_tile(pos)
			else:
				var origin = Vector3(pos.x * TILE_SIZE, 0, pos.y * TILE_SIZE)
				base_transforms.append(Transform3D(Basis(), origin))

				if randf() < decoration_chance:
					var r = randf()
					var rot_y = randf() * TAU
					var deco_basis = Basis(Vector3.UP, rot_y)
					var deco_xform = Transform3D(deco_basis, origin)
					if r > 0.75:
						tree_transforms.append(deco_xform)
					elif r > 0.5:
						tree_large_transforms.append(deco_xform)
					elif r > 0.25:
						rock_transforms.append(deco_xform)
					else:
						var variant_idx = randi() % BUSH_VARIANT_COUNT
						var bush_scale = randf_range(BUSH_SCALE_MIN, BUSH_SCALE_MAX)
						var bush_basis = deco_basis.scaled(Vector3(bush_scale, bush_scale, bush_scale))
						var bush_xform = Transform3D(bush_basis, origin)
						bush_transforms[variant_idx].append(bush_xform)

	_apply_multimesh(mm_base, base_transforms)
	_apply_multimesh(mm_tree, tree_transforms)
	_apply_multimesh(mm_tree_large, tree_large_transforms)
	_apply_multimesh(mm_rock, rock_transforms)
	for i in range(BUSH_VARIANT_COUNT):
		_apply_multimesh(mm_bushes[i], bush_transforms[i])

# --- MultiMesh helpers -------------------------------------------------

func _extract_mesh_and_material(scene: PackedScene) -> Dictionary:
	var temp = scene.instantiate()
	var mesh_instance: MeshInstance3D = null

	if temp is MeshInstance3D:
		mesh_instance = temp
	else:
		for child in temp.get_children():
			if child is MeshInstance3D:
				mesh_instance = child
				break

	var mesh: Mesh = null
	var material: Material = null

	if mesh_instance != null:
		mesh = mesh_instance.mesh
		# A custom ShaderMaterial (like the foliage shader) is usually set as
		# a per-node surface override rather than baked into the mesh
		# resource itself — MultiMeshInstance3D only sees the raw mesh, so
		# without grabbing this explicitly, batched instances would render
		# with no shader at all.
		if mesh != null and mesh.get_surface_count() > 0:
			material = mesh_instance.get_surface_override_material(0)
			if material == null:
				material = mesh.surface_get_material(0)

	temp.queue_free()
	return {"mesh": mesh, "material": material}

func _make_multimesh_node(node_name: String, scene: PackedScene) -> MultiMeshInstance3D:
	var mmi = MultiMeshInstance3D.new()
	mmi.name = node_name
	add_child(mmi)

	var extracted = _extract_mesh_and_material(scene)

	var mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = extracted["mesh"]
	mmi.multimesh = mm

	if extracted["material"] != null:
		mmi.material_override = extracted["material"]

	return mmi

func _make_bush_variant_nodes(scene: PackedScene, count: int) -> Array[MultiMeshInstance3D]:
	var extracted = _extract_mesh_and_material(scene)
	var base_mesh: Mesh = extracted["mesh"]
	var base_material: Material = extracted["material"]

	var nodes: Array[MultiMeshInstance3D] = []

	for i in range(count):
		var mmi = MultiMeshInstance3D.new()
		mmi.name = "Bushes_Variant%d" % i
		add_child(mmi)

		var mm = MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = base_mesh # geometry is identical across variants — only the material differs
		mmi.multimesh = mm

		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if not BUSH_CAST_SHADOWS else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		mmi.visibility_range_end = BUSH_VISIBILITY_END
		mmi.visibility_range_end_margin = BUSH_VISIBILITY_FADE
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF

		if base_material != null:
			# .duplicate() gives each variant its own independent
			# ShaderMaterial resource, so changing its uniforms below can't
			# affect the other variants (or the original bush scene).
			var variant_material: ShaderMaterial = base_material.duplicate()
			_randomize_bush_wind(variant_material)
			mmi.material_override = variant_material

		nodes.append(mmi)

	return nodes

func _randomize_bush_wind(mat: ShaderMaterial) -> void:
	# Ranges are deliberately modest — enough that bushes read as
	# individually alive rather than a single synchronized field, without
	# any one bush looking wildly out of place next to its neighbors.
	mat.set_shader_parameter("WindSpeed", randf_range(2.5, 6.0))
	mat.set_shader_parameter("WindStrength", randf_range(3.0, 7.0))
	mat.set_shader_parameter("WindScale", randf_range(0.8, 1.4))
	mat.set_shader_parameter("WindDensity", randf_range(3.0, 7.0))
	mat.set_shader_parameter("WiggleSpeed", randf_range(0.7, 1.4))
	mat.set_shader_parameter("WiggleStrength", randf_range(0.06, 0.14))
	mat.set_shader_parameter("WiggleFrequency", randf_range(2.0, 4.0))

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
	# Rotate around the tile's actual geometric center, not whatever origin
	# point the imported model happens to have. If that origin is offset
	# along the tile's "forward" axis (common for road-segment assets),
	# rotating the raw instance directly would swing that offset into a
	# different world axis depending on rotation — which is exactly what
	# was causing east-west (rotated) tiles to visually drift sideways in
	# X while north-south (unrotated) tiles looked fine.
	var pivot = Node3D.new()
	add_child(pivot)
	pivot.position = Vector3(pos.x * TILE_SIZE, 0, pos.y * TILE_SIZE)
	pivot.rotation.y = rot_y

	pivot.add_child(instance)

	var mesh_instance = _find_mesh_instance_recursive(instance)
	if mesh_instance != null:
		var aabb = mesh_instance.get_aabb()
		var local_center = mesh_instance.transform * (aabb.position + aabb.size / 2.0)
		instance.position -= Vector3(local_center.x, 0, local_center.z)

func _find_mesh_instance_recursive(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	for child in node.get_children():
		var found = _find_mesh_instance_recursive(child)
		if found != null:
			return found
	return null

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
