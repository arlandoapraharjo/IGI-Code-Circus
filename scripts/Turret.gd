extends Node3D

# Turret base class handling targeting, attack types, cooldowns, and placeholder visuals.

# Exported configurable properties
@export_range(0.0, 20.0, 0.1) var attack_range: float = 1.5
@export var is_aoe: bool = false
@export_range(0.1, 10.0, 0.1) var cooldown: float = 1.0
# How fast (deg/sec) the turret rotates to face its target
@export_range(10.0, 720.0, 5.0) var rotation_speed: float = 180.0

# Internal timer
var _cooldown_timer: float = 0.0
# Current locked target for rotation tracking
var _current_target: Node3D = null

# Placeholder visual nodes
var _line_mesh_instance: MeshInstance3D = null
var _line_mesh: ImmediateMesh = null
var _aoe_marker: MeshInstance3D = null
var _hide_timer: Timer = null

func _ready() -> void:
	# Single-target line placeholder using ImmediateMesh (Godot 4)
	_line_mesh = ImmediateMesh.new()
	_line_mesh_instance = MeshInstance3D.new()
	_line_mesh_instance.mesh = _line_mesh
	_line_mesh_instance.name = "single_target_line"
	_line_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var line_mat = StandardMaterial3D.new()
	# Bright neon yellow — bold and high contrast
	line_mat.albedo_color = Color(1.0, 1.0, 0.0)
	line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line_mat.no_depth_test = true
	line_mat.render_priority = 2
	_line_mesh_instance.material_override = line_mat
	add_child(_line_mesh_instance)

	# AoE marker — flat cylinder disc on the ground, bold red
	_aoe_marker = MeshInstance3D.new()
	_aoe_marker.name = "aoe_marker"
	var disc = CylinderMesh.new()
	disc.top_radius = attack_range
	disc.bottom_radius = attack_range
	disc.height = 0.05
	disc.radial_segments = 32
	_aoe_marker.mesh = disc
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.05, 0.05, 0.75)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true
	mat.render_priority = 2
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_aoe_marker.material_override = mat
	_aoe_marker.position = Vector3(0, 0.08, 0)
	_aoe_marker.visible = false
	add_child(_aoe_marker)

	# Timer to hide visuals after a flash
	_hide_timer = Timer.new()
	_hide_timer.one_shot = true
	_hide_timer.wait_time = 0.25
	_hide_timer.connect("timeout", Callable(self, "_on_hide_timer_timeout"))
	add_child(_hide_timer)

func _process(delta: float) -> void:
	# --- Continuous rotation toward locked target (single-target only) ---
	if not is_aoe and is_instance_valid(_current_target):
		_rotate_toward_target(_current_target, delta)

	if _cooldown_timer > 0.0:
		_cooldown_timer -= delta
		return

	var enemies = EnemyDetector.get_enemies_in_range(self, global_transform.origin, attack_range)
	if enemies.is_empty():
		_current_target = null
		return

	if is_aoe:
		_trigger_aoe_attack(enemies)
	else:
		_current_target = enemies[0]
		_trigger_single_target_attack(_current_target)

	_cooldown_timer = cooldown

# Smoothly rotate the turret (Y-axis only) to face the target.
func _rotate_toward_target(target: Node3D, delta: float) -> void:
	var target_pos = target.global_transform.origin
	var my_pos = global_transform.origin
	# Flatten to horizontal plane
	var dir = Vector3(target_pos.x - my_pos.x, 0.0, target_pos.z - my_pos.z)
	if dir.length_squared() < 0.0001:
		return
	var target_basis = Basis.looking_at(dir.normalized(), Vector3.UP, true)
	# Slerp at rotation_speed degrees per second
	var t = clampf(deg_to_rad(rotation_speed) * delta, 0.0, 1.0)
	global_transform.basis = global_transform.basis.slerp(target_basis, t)

func _trigger_single_target_attack(target: Node3D) -> void:
	# Draw a bold neon line from turret origin to the target
	_line_mesh.clear_surfaces()
	_line_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	# Draw 3 parallel lines (offset slightly) to simulate thickness
	var local_target = to_local(target.global_transform.origin)
	var offsets = [Vector3.ZERO, Vector3(0.04, 0, 0), Vector3(-0.04, 0, 0)]
	for o in offsets:
		_line_mesh.surface_add_vertex(Vector3.ZERO + o)
		_line_mesh.surface_add_vertex(local_target + o)
	_line_mesh.surface_end()
	_hide_timer.start()
	# Placeholder for damage logic
	print("Turret (single) fired at ", target.name)

func _trigger_aoe_attack(targets: Array) -> void:
	_aoe_marker.visible = true
	_hide_timer.start()
	# Placeholder for AoE damage logic
	print("Turret (AoE) fired, affecting ", targets.size(), " enemies")

func _on_hide_timer_timeout() -> void:
	_line_mesh.clear_surfaces()
	_aoe_marker.visible = false

func reset_cooldown() -> void:
	_cooldown_timer = 0.0
