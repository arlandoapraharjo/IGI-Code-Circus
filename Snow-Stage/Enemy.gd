extends Node3D

# Speed in tiles per second
@export var speed: float = 2.3

var path_waypoints: Array[Vector3] = []
var current_waypoint_index: int = 0
var _is_done: bool = false

signal reached_end

func setup(waypoints: Array[Vector3]) -> void:
	path_waypoints = waypoints
	current_waypoint_index = 0
	_is_done = false

func _process(delta: float) -> void:
	if _is_done or path_waypoints.is_empty():
		return

	if current_waypoint_index >= path_waypoints.size():
		_is_done = true
		reached_end.emit()
		queue_free()
		return

	var target = path_waypoints[current_waypoint_index]
	var direction = (target - global_position)

	if direction.length() < 0.05:
		current_waypoint_index += 1
	else:
		# Move towards current waypoint
		global_position += direction.normalized() * speed * delta
		
		# Face direction of travel (rotate smoothly on Y axis)
		var look_target = global_position + Vector3(direction.x, 0, direction.z).normalized()
		if look_target != global_position:
			look_at(look_target, Vector3.UP)
