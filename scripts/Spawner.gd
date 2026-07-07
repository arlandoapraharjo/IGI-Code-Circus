extends Node3D

# Enemy UFO models — preloaded once, not load()'d per spawn
var enemy_models: Array[PackedScene] = [
	preload("res://assets/Models/GLB format/enemy-ufo-a.glb"),
	preload("res://assets/Models/GLB format/enemy-ufo-b.glb"),
	preload("res://assets/Models/GLB format/enemy-ufo-c.glb"),
	preload("res://assets/Models/GLB format/enemy-ufo-d.glb"),
]

var enemy_script = preload("res://scripts/Enemy.gd")

@export var spawn_interval: float = 2.0  # Seconds between each spawn
@export var enemy_speed: float = 1.5     # Tiles per second
@export var pool_size: int = 20          # Pre-allocated enemy count

var _timer: float = 0.0
var _waypoints: Array[Vector3] = []
var _ready_to_spawn: bool = false

# Object pool — avoids allocation hitches during waves
var _pool: Array[Node3D] = []
var _active_enemies: Array[Node3D] = []

func setup(path: Array[Vector2i]) -> void:
	# Convert grid coordinates to world-space Vector3 waypoints
	for grid_pos in path:
		_waypoints.append(Vector3(grid_pos.x * 1.0, 0.5, grid_pos.y * 1.0))

	_build_pool()
	_ready_to_spawn = true
	_timer = spawn_interval  # Spawn first enemy immediately after interval

func _build_pool() -> void:
	for i in range(pool_size):
		var enemy = _create_enemy_node()
		enemy.deactivate()
		_pool.append(enemy)

func _create_enemy_node() -> Node3D:
	var enemy_root = Node3D.new()
	enemy_root.set_script(enemy_script)

	# Pick a random UFO model for this pool slot
	var model_scene = enemy_models[randi() % enemy_models.size()]
	var model_instance = model_scene.instantiate()
	enemy_root.add_child(model_instance)

	# Parent to the Map node
	get_parent().add_child(enemy_root)

	# Connect the reached_end signal so we can reclaim it
	enemy_root.reached_end.connect(_on_enemy_reached_end.bind(enemy_root))

	return enemy_root

func _physics_process(delta: float) -> void:
	if not _ready_to_spawn or _waypoints.is_empty():
		return

	_timer -= delta
	if _timer <= 0.0:
		_timer = spawn_interval
		_spawn_enemy()

func _spawn_enemy() -> void:
	var enemy: Node3D

	if not _pool.is_empty():
		enemy = _pool.pop_back()
	else:
		# Pool exhausted — grow by 1 (should be rare with a well-sized pool)
		push_warning("Spawner: enemy pool exhausted, creating new instance. Consider increasing pool_size.")
		enemy = _create_enemy_node()

	enemy.reset(_waypoints, enemy_speed)
	_active_enemies.append(enemy)

func _on_enemy_reached_end(enemy: Node3D) -> void:
	# Return the enemy to the pool for reuse
	_active_enemies.erase(enemy)
	_pool.append(enemy)
