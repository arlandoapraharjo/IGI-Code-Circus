extends Node

## Controller that handles grid-snapping turret placement on the map.

@export var map_generator: Node3D
@export var turret_y_offset: float = 0.1

var _is_building: bool = false
var _turret_scene: PackedScene = null
var _ghost_instance: Node3D = null
var _ghost_material: ShaderMaterial = null
var _range_marker_node: Node3D = null
var _attack_range: float = 0.0

signal building_stopped

var COLOR_VALID = Color(0.2, 0.8, 1.0, 0.5)
var COLOR_INVALID = Color(1.0, 0.2, 0.2, 0.5)

func _ready() -> void:
	_ghost_material = ShaderMaterial.new()
	var shader = preload("res://shaders/ghost_hologram.gdshader")
	if shader:
		_ghost_material.shader = shader
		_ghost_material.set_shader_parameter("base_color", COLOR_VALID)
		
	_range_marker_node = Node3D.new()
	_range_marker_node.name = "RangeMarker"
	add_child(_range_marker_node)

func start_building(_index: int, turret_scene: PackedScene, attack_range: float = 0.0) -> void:
	if not map_generator:
		push_warning("BuilderController: map_generator is not assigned!")
		return

	if _is_building:
		stop_building(false)

	# Create the ghost instance
	_turret_scene = turret_scene
	_attack_range = attack_range
	_is_building = true
	_ghost_instance = turret_scene.instantiate()
	_ghost_instance.name = "GhostTurret"
	# Assign Turret base script and configure properties
	var turret_script = load("res://scripts/Turret.gd")
	if turret_script == null:
		push_error("Failed to load Turret script at res://scripts/Turret.gd")
	else:
		_ghost_instance.set_script(turret_script)
	_ghost_instance.attack_range = attack_range
	# All facilities are single-target with 1s cooldown
	_ghost_instance.is_aoe = false
	_ghost_instance.cooldown = 1.0
	# Disable ghost logic and apply ghost material
	_disable_logic(_ghost_instance)
	_apply_ghost_material(_ghost_instance)
	add_child(_ghost_instance)
	_build_range_marker(attack_range)

func stop_building(emit_signal: bool = true) -> void:
	_is_building = false
	_turret_scene = null
	if _ghost_instance:
		_ghost_instance.queue_free()
		_ghost_instance = null
	_clear_range_marker()
	if emit_signal:
		building_stopped.emit()

func _unhandled_input(event: InputEvent) -> void:
	if not _is_building:
		return

	if event.is_action_pressed("ui_cancel") or (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed):
		stop_building()
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_try_place_turret()
		get_viewport().set_input_as_handled()
		return

func _process(_delta: float) -> void:
	if not _is_building or not _ghost_instance:
		return

	var camera = get_viewport().get_camera_3d()
	if not camera:
		return

	var mouse_pos = get_viewport().get_mouse_position()
	var origin = camera.project_ray_origin(mouse_pos)
	var normal = camera.project_ray_normal(mouse_pos)
	var plane = Plane(Vector3.UP, 0.0)
	
	var hit = plane.intersects_ray(origin, normal)
	if hit != null:
		# Convert global hit to Map's local space to align with grid
		var local_hit = map_generator.to_local(hit)
		
		# Map tiles are 1.0x1.0, centered on integers
		var grid_x = round(local_hit.x)
		var grid_z = round(local_hit.z)
		var grid_pos = Vector2i(int(grid_x), int(grid_z))
		
		# Move ghost to snapped local position relative to Map, then convert back to global
		var local_snap_pos = Vector3(grid_pos.x, turret_y_offset, grid_pos.y)
		_ghost_instance.global_position = map_generator.to_global(local_snap_pos)
		_range_marker_node.global_position = _ghost_instance.global_position
		
		var can_build = false
		if map_generator.has_method("is_buildable"):
			can_build = map_generator.is_buildable(grid_pos)

		_ghost_instance.visible = true
		_range_marker_node.visible = true
		if can_build:
			_ghost_material.set_shader_parameter("base_color", COLOR_VALID)
		else:
			_ghost_material.set_shader_parameter("base_color", COLOR_INVALID)
	else:
		_ghost_instance.visible = false
		_range_marker_node.visible = false

func _build_range_marker(attack_range: float) -> void:
	_clear_range_marker()
	if attack_range <= 0.0:
		return
		
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(0.0, 0.0, 0.0, 0.35)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = true
	material.render_priority = 1
	
	var mesh = QuadMesh.new()
	mesh.size = Vector2(0.9, 0.9)
	mesh.orientation = PlaneMesh.FACE_Y
	
	var r = int(ceil(attack_range))
	var r_sq = attack_range * attack_range
	for x in range(-r, r + 1):
		for z in range(-r, r + 1):
			if (x * x + z * z) <= r_sq:
				var mi = MeshInstance3D.new()
				mi.mesh = mesh
				mi.material_override = material
				mi.position = Vector3(x, 0.15, z)
				_range_marker_node.add_child(mi)

func _clear_range_marker() -> void:
	for child in _range_marker_node.get_children():
		_range_marker_node.remove_child(child)
		child.free()

func _try_place_turret() -> void:
	if not is_instance_valid(_ghost_instance) or not _ghost_instance.visible:
		return

	var local_ghost_pos = map_generator.to_local(_ghost_instance.global_position)
	var grid_pos = Vector2i(int(round(local_ghost_pos.x)), int(round(local_ghost_pos.z)))
	
	if map_generator.has_method("is_buildable") and map_generator.is_buildable(grid_pos):
		# Valid placement!
		var new_turret = _turret_scene.instantiate()
		# IMPORTANT: assign script BEFORE add_child so _ready() fires with Turret.gd
		var turret_script = load("res://scripts/Turret.gd")
		if turret_script != null:
			new_turret.set_script(turret_script)
			new_turret.attack_range = _attack_range
			# All facilities are single-target with 1s cooldown
			new_turret.is_aoe = false
			new_turret.cooldown = 1.0
		else:
			push_error("Turret.gd failed to load")
		# Now add to tree — this triggers _ready() on the Turret script
		map_generator.add_child(new_turret)
		new_turret.position = Vector3(grid_pos.x, turret_y_offset, grid_pos.y)
		print("Placed turret: attack_range=", _attack_range)
		
		if map_generator.has_method("occupy_cell"):
			map_generator.occupy_cell(grid_pos)
		# Refresh the range marker so no ghost tiles linger at the placement spot
		_clear_range_marker()
		_build_range_marker(_attack_range)
		# Do not call stop_building() here so the user can place multiple turrets
	else:
		# Invalid placement, maybe play a sound
		pass

func _disable_logic(node: Node) -> void:
	# Disable processing, physics, and collisions for the ghost
	node.process_mode = Node.PROCESS_MODE_DISABLED
	if node is CollisionObject3D:
		node.collision_layer = 0
		node.collision_mask = 0
	for child in node.get_children():
		_disable_logic(child)

func _apply_ghost_material(node: Node) -> void:
	if node is MeshInstance3D:
		node.material_override = _ghost_material
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children():
		_apply_ghost_material(child)
