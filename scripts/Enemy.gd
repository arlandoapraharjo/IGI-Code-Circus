extends Node3D
# Speed in tiles per second
@export var speed: float = 1.5
var path_waypoints: Array[Vector3] = []
var current_waypoint_index: int = 0
var _is_done: bool = false
signal reached_end
func setup(waypoints: Array[Vector3]) -> void:
	path_waypoints = waypoints
	current_waypoint_index = 0
	_is_done = false
## Re-initialize this enemy for reuse from the pool.
## Places it at the first waypoint and makes it visible/active.
func reset(waypoints: Array[Vector3], new_speed: float) -> void:
	path_waypoints = waypoints
	current_waypoint_index = 0
	_is_done = false
	speed = new_speed
	visible = true
	set_physics_process(true)
	if not waypoints.is_empty():
		position = waypoints[0]
		if waypoints.size() > 1:
			var dir = waypoints[1] - waypoints[0]
			var look_dir = Vector3(dir.x, 0, dir.z)
			if look_dir.length() > 0.001:
				var look_pos = position + look_dir.normalized()
				look_at(get_parent().to_global(look_pos), Vector3.UP)
## Hide and stop processing — the Spawner will reclaim this node.
func deactivate() -> void:
	_is_done = true
	visible = false
	set_physics_process(false)
func _physics_process(delta: float) -> void:
	if _is_done or path_waypoints.is_empty():
		return
	if current_waypoint_index >= path_waypoints.size():
		_is_done = true
		reached_end.emit()
		deactivate()
		return

	# How far this enemy is allowed to travel this tick. Any distance left
	# over after reaching a waypoint gets spent on the NEXT waypoint in the
	# same tick, rather than being allowed to overshoot past the current
	# one — that overshoot is what was letting enemies keep travelling in
	# their old direction straight through corner tiles instead of turning.
	var remaining_move = speed * delta

	while remaining_move > 0.0 and current_waypoint_index < path_waypoints.size():
		var target = path_waypoints[current_waypoint_index]
		var to_target = target - position
		var dist = to_target.length()

		if dist <= remaining_move:
			# Snap exactly onto the waypoint (never past it), spend only
			# the distance it actually took to get there, and move on.
			position = target
			remaining_move -= dist
			current_waypoint_index += 1

			if current_waypoint_index < path_waypoints.size():
				var next_target = path_waypoints[current_waypoint_index]
				var look_dir = Vector3(next_target.x - position.x, 0, next_target.z - position.z)
				if look_dir.length() > 0.001:
					var look_pos = position + look_dir.normalized()
					var global_look = get_parent().to_global(look_pos)
					var target_transform = global_transform.looking_at(global_look, Vector3.UP)
					global_transform.basis = global_transform.basis.slerp(target_transform.basis, 15.0 * delta)
		else:
			var dir = to_target / dist # already-normalized direction, reusing the length we computed
			position += dir * remaining_move

			var look_dir = Vector3(dir.x, 0, dir.z)
			if look_dir.length() > 0.001:
				var look_pos = position + look_dir.normalized()
				var global_look = get_parent().to_global(look_pos)
				var target_transform = global_transform.looking_at(global_look, Vector3.UP)
				global_transform.basis = global_transform.basis.slerp(target_transform.basis, 15.0 * delta)

			remaining_move = 0.0

	if current_waypoint_index >= path_waypoints.size():
		_is_done = true
		reached_end.emit()
		deactivate()
