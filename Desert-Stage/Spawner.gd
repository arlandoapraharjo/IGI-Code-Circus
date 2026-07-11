extends Node3D

# Enemy UFO models (randomly picked)
var enemy_models = [
	"res://kenney_tower-defense-kit/Models/GLB format/enemy-ufo-a.glb",
	"res://kenney_tower-defense-kit/Models/GLB format/enemy-ufo-b.glb",
	"res://kenney_tower-defense-kit/Models/GLB format/enemy-ufo-c.glb",
	"res://kenney_tower-defense-kit/Models/GLB format/enemy-ufo-d.glb",
]

var enemy_script = preload("res://Desert-Stage/Enemy.gd")

@export var spawn_interval: float = 2.0  # Seconds between each spawn
@export var enemy_speed: float = 3.0     # Tiles per second

var _timer: float = 0.0
var _waypoints: Array[Vector3] = []
var _ready_to_spawn: bool = false

func setup(path: Array[Vector2i]) -> void:
	# Convert grid coordinates to world-space Vector3 waypoints
	for grid_pos in path:
		_waypoints.append(Vector3(grid_pos.x * 1.0, 0.5, grid_pos.y * 1.0))
	_ready_to_spawn = true
	_timer = spawn_interval  # Spawn first enemy immediately after interval

func _process(delta: float) -> void:
	if not _ready_to_spawn or _waypoints.is_empty():
		return

	_timer -= delta
	if _timer <= 0.0:
		_timer = spawn_interval
		_spawn_enemy()

func _spawn_enemy() -> void:
	# Pick a random UFO model
	var model_path = enemy_models[randi() % enemy_models.size()]
	var model_scene = load(model_path)
	if not model_scene:
		return

	var enemy_root = Node3D.new()
	enemy_root.set_script(enemy_script)

	# Attach model as child
	var model_instance = model_scene.instantiate()
	enemy_root.add_child(model_instance)

	# Add to the Map node (parent of this spawner)
	get_parent().add_child(enemy_root)

	# Start at the first waypoint
	enemy_root.global_position = _waypoints[0]
	enemy_root.speed = enemy_speed
	enemy_root.setup(_waypoints)
